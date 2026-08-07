let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let synchronize ~framework_root ~project_root ~config =
  let* () = Assets.synchronize_flutter_packages ~framework_root ~project_root in
  let* _changed = Host.sync ~project_root ~config ~mode:Host.Write in
  Ok ()
;;

let macos_environment project_root =
  let* sdk_root =
    Process_runner.capture
      ~working_directory:project_root
      ~environment:[]
      "xcrun"
      [ "--sdk"; "macosx"; "--show-sdk-path" ]
  in
  Ok [ "BONSAI_FLUTTER_APPLE_SDK_ROOT", sdk_root ]
;;

let build_macos ~framework_root ~project_root ~config ~profile =
  let* environment = macos_environment project_root in
  let plan = Plan.build_native ~project_root ~config ~target:Plan.Macos ~profile in
  let* () =
    Process_runner.run { plan with environment = plan.environment @ environment }
  in
  Artifact.stage ~framework_root ~project_root ~config ~target:Plan.Macos ~profile
;;

let copy_file source destination =
  try
    Artifact.copy_file source destination;
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let with_external_app ~framework_root ~project_root ~key f =
  let external_root = Filename.concat framework_root ("external_apps/" ^ key) in
  let link = Filename.concat external_root "app" in
  let lock_root = Filename.concat framework_root "_build/ios/locks" in
  let lock = Filename.concat lock_root (key ^ ".lock") in
  try
    Scaffold.ensure_directory lock_root;
    Unix.mkdir lock 0o755;
    Scaffold.ensure_directory external_root;
    Unix.symlink (Filename.concat project_root "app") link;
    Fun.protect
      ~finally:(fun () ->
        if Sys.file_exists link then Unix.unlink link;
        (try Unix.rmdir external_root with
         | Unix.Unix_error _ -> ());
        try Unix.rmdir lock with
        | Unix.Unix_error _ -> ())
      (fun () -> f external_root)
  with
  | Unix.Unix_error (Unix.EEXIST, _, _) ->
    Error (Printf.sprintf "An iPhoneOS build already owns cache key %s" key)
  | Unix.Unix_error (_, _, message) -> Error message
;;

let build_iphoneos ~framework_root ~project_root ~config ~profile =
  let* () =
    Sdk.build_from_source
      ~framework_root
      ~project_root:(Some project_root)
      ~target:Plan.Iphoneos
      ~features:config.Config.features
  in
  let key = Cache.application_key ~config ~target:Plan.Iphoneos ~profile in
  with_external_app ~framework_root ~project_root ~key (fun _external_root ->
    let* sdk_version =
      Process_runner.capture
        ~working_directory:project_root
        ~environment:[]
        "xcrun"
        [ "--sdk"; "iphoneos"; "--show-sdk-version" ]
    in
    let* sdk_root =
      Process_runner.capture
        ~working_directory:project_root
        ~environment:[]
        "xcrun"
        [ "--sdk"; "iphoneos"; "--show-sdk-path" ]
    in
    let opam_root = Filename.concat framework_root "_build/ios/opam-root" in
    let switch = Filename.concat framework_root "_build/ios/switches/iphoneos" in
    let* findlib_conf = Sdk.application_findlib_conf ~framework_root ~project_root in
    let build_directory = Filename.concat framework_root ("_build/ios/external/" ^ key) in
    Scaffold.ensure_directory (Filename.dirname build_directory);
    let external_target =
      "external_apps/" ^ key ^ "/app/" ^ Filename.basename config.native_target
    in
    let command : Plan.command =
      { program = "opam"
      ; arguments =
          [ "exec"
          ; "--switch=" ^ switch
          ; "--"
          ; "dune"
          ; "build"
          ; "--root=" ^ framework_root
          ; "--build-dir=" ^ build_directory
          ; "--profile=" ^ Plan.profile_name profile
          ; "-x"
          ; "ios"
          ; external_target
          ]
      ; working_directory = framework_root
      ; environment =
          [ "OPAMROOT", opam_root
          ; "OCAMLFIND_CONF", findlib_conf
          ; "BUILD_PATH_PREFIX_MAP", project_root ^ "=."
          ; "BONSAI_FLUTTER_APPLE_SDK_ROOT", sdk_root
          ; "SDK", sdk_version
          ; "VER", config.ios.minimum_version
          ; "BONSAI_FLUTTER_EMBED_OCAML", "enabled"
          ]
      }
    in
    let* () = Process_runner.run command in
    let built = Filename.concat build_directory ("default.ios/" ^ external_target) in
    let staged_source =
      Artifact.source ~project_root ~config ~target:Plan.Iphoneos ~profile
    in
    let* () = copy_file built staged_source in
    Artifact.stage ~framework_root ~project_root ~config ~target:Plan.Iphoneos ~profile)
;;

let build_native ~framework_root ~project_root ~config ~target ~profile =
  let* () = synchronize ~framework_root ~project_root ~config in
  match target with
  | Plan.Macos -> build_macos ~framework_root ~project_root ~config ~profile
  | Plan.Iphoneos -> build_iphoneos ~framework_root ~project_root ~config ~profile
;;

let flutter_pub_get ~project_root ~config =
  let command : Plan.command =
    { program = "flutter"
    ; arguments = [ "pub"; "get" ]
    ; working_directory = Filename.concat project_root config.Config.flutter_root
    ; environment = []
    }
  in
  Process_runner.run command
;;

let verify_ios_bundle ~framework_root ~project_root ~config ~profile =
  let app = Plan.ios_app_bundle ~project_root ~config ~profile in
  let sqlite_required =
    List.exists (Config.Feature.equal Config.Feature.Sqlite) config.Config.features
  in
  if not (Sys.file_exists app && Sys.is_directory app)
  then
    Error (Printf.sprintf "Build succeeded but the expected app at %s was not found" app)
  else (
    let command : Plan.command =
      { program = Filename.concat framework_root "tool/ios/verify_app_bundle.sh"
      ; arguments = app :: (if sqlite_required then [ "require-sqlite" ] else [])
      ; working_directory = project_root
      ; environment = []
      }
    in
    Process_runner.run command)
;;

let capture_command (command : Plan.command) =
  Process_runner.capture
    ~working_directory:command.working_directory
    ~environment:command.environment
    command.program
    command.arguments
;;

let resolve_ios_bundle_identifier ~project_root ~app_bundle =
  let command = Plan.ios_bundle_identifier ~project_root ~app_bundle in
  let* bundle_identifier = capture_command command in
  if bundle_identifier = ""
  then
    Error
      (Printf.sprintf
         "Built application bundle has an empty CFBundleIdentifier: %s"
         (Filename.concat app_bundle "Info.plist"))
  else Ok bundle_identifier
;;

let run_ios_device ~framework_root ~project_root ~config ~profile ~device ~forwarded =
  let app_bundle = Plan.ios_app_bundle ~project_root ~config ~profile in
  let* () =
    Plan.flutter
      ~project_root
      ~config
      ~action:Plan.Build
      ~platform:Plan.Ios_platform
      ~profile
      ~device:None
      ~no_codesign:false
      ~forwarded
    |> Process_runner.run
  in
  let* () = verify_ios_bundle ~framework_root ~project_root ~config ~profile in
  let* bundle_identifier = resolve_ios_bundle_identifier ~project_root ~app_bundle in
  let* () =
    Plan.ios_device_install ~project_root ~device ~app_bundle |> Process_runner.run
  in
  Plan.ios_device_launch ~project_root ~device ~bundle_identifier |> Process_runner.run
;;

let run_flutter_host
      ~framework_root
      ~project_root
      ~config
      ~action
      ~platform
      ~profile
      ~device
      ~no_codesign
      ~forwarded
  =
  match action, platform, profile with
  | Plan.Run, Plan.Ios_platform, (Plan.Profile | Plan.Release) ->
    (match device with
     | None -> Error "bonsai-flutter run ios requires --device <device-id>"
     | Some device ->
       run_ios_device ~framework_root ~project_root ~config ~profile ~device ~forwarded)
  | Plan.Run, _, _ | Plan.Build, _, _ ->
    let* () =
      Plan.flutter
        ~project_root
        ~config
        ~action
        ~platform
        ~profile
        ~device
        ~no_codesign
        ~forwarded
      |> Process_runner.run
    in
    (match action, platform with
     | Plan.Build, Plan.Ios_platform ->
       verify_ios_bundle ~framework_root ~project_root ~config ~profile
     | Plan.Run, _ | Plan.Build, Plan.Macos_platform -> Ok ())
;;

let run_flutter
      ~framework_root
      ~project_root
      ~config
      ~action
      ~platform
      ~profile
      ~device
      ~no_codesign
      ~forwarded
  =
  let target =
    match platform with
    | Plan.Macos_platform -> Plan.Macos
    | Plan.Ios_platform -> Plan.Iphoneos
  in
  let* _artifact = build_native ~framework_root ~project_root ~config ~target ~profile in
  let* () = flutter_pub_get ~project_root ~config in
  run_flutter_host
    ~framework_root
    ~project_root
    ~config
    ~action
    ~platform
    ~profile
    ~device
    ~no_codesign
    ~forwarded
;;
