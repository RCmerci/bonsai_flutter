let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let synchronize ~framework_root:_ ~project_root ~config =
  Scaffold.synchronize_dune_native_aliases ~project_root ~config
;;

let synchronize_flutter ~framework_root ~project_root ~config =
  let* () = Assets.synchronize_flutter_packages ~framework_root ~project_root in
  let* _changed = Host.sync ~project_root ~config ~mode:Host.Write in
  Ok ()
;;

let capture ~project_root program arguments =
  Process_runner.capture ~working_directory:project_root ~environment:[] program arguments
;;

let apple_sdk ~project_root target =
  let sdk =
    match target with
    | Plan.Macos -> "macosx"
    | Plan.Iphoneos -> "iphoneos"
  in
  let* root = capture ~project_root "xcrun" [ "--sdk"; sdk; "--show-sdk-path" ] in
  match target with
  | Plan.Macos -> Ok (root, None)
  | Plan.Iphoneos ->
    let* version = capture ~project_root "xcrun" [ "--sdk"; sdk; "--show-sdk-version" ] in
    Ok (root, Some version)
;;

let host_fingerprint ~project_root ~(config : Config.t) =
  let* dune_version =
    capture ~project_root "opam" [ "exec"; "--"; "dune"; "--version" ]
  in
  let* ocaml_version =
    capture ~project_root "opam" [ "exec"; "--"; "ocamlc"; "-version" ]
  in
  let* package_version =
    capture
      ~project_root
      "opam"
      [ "exec"; "--"; "ocamlfind"; "query"; "-format"; "%v"; "bonsai_flutter" ]
  in
  let identity =
    String.concat
      "\000"
      [ "bonsai-flutter-host-v1"
      ; dune_version
      ; ocaml_version
      ; package_version
      ; Sdk.supported_abi_version
      ; config.macos.minimum_version
      ; String.concat "," config.macos.architectures
      ]
  in
  Ok Digestif.SHA256.(to_hex (digest_string identity))
;;

let iphoneos_fingerprint ~(config : Config.t) sdk_fingerprint =
  String.concat
    "\000"
    [ "bonsai-flutter-iphoneos-v1"
    ; sdk_fingerprint
    ; Sdk.supported_abi_version
    ; config.ios.minimum_version
    ; String.concat "," config.ios.architectures
    ]
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
;;

let build_manifest ~(build : Plan.native_build) ~target ~profile ~fingerprint artifact =
  Printf.sprintf
    "(build\n\
    \ (format_version 1)\n\
    \ (target %s)\n\
    \ (profile %s)\n\
    \ (toolchain_fingerprint %s)\n\
    \ (source_digest %s)\n\
    \ (artifact_digest %s))\n"
    (Plan.target_name target)
    (Plan.profile_name profile)
    fingerprint
    (Artifact.digest build.source_object)
    (Artifact.digest artifact)
;;

let execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  =
  let* build =
    Plan.native_build
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  in
  Scaffold.ensure_directory (Filename.dirname build.build_directory);
  let* () = Process_runner.run build.command in
  Lock.with_lock build.lock (fun () ->
    let* artifact = Artifact.stage ~framework_root ~build ~config ~target in
    let manifest =
      build_manifest ~build ~target ~profile ~fingerprint:toolchain_fingerprint artifact
    in
    let* () = Artifact.write_if_changed build.manifest manifest in
    Ok artifact)
;;

let build_native ~framework_root ~project_root ~config ~target ~profile =
  let* () = Scaffold.validate_dune_native_aliases ~project_root ~config in
  let* apple_sdk_root, apple_sdk_version = apple_sdk ~project_root target in
  match target with
  | Plan.Macos ->
    let* toolchain_fingerprint = host_fingerprint ~project_root ~config in
    execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  | Plan.Iphoneos ->
    let* sdk =
      Sdk.preflight
        ~project_root
        ~bonsai_flutter_version:Sdk.supported_bonsai_flutter_version
        ~abi_version:Sdk.supported_abi_version
        ~minimum_deployment_target:config.Config.ios.minimum_version
        ~required_packages:[ "bonsai_flutter", Sdk.supported_bonsai_flutter_version ]
    in
    let closure_build_directory =
      Filename.concat
        project_root
        ("_build/bonsai-flutter/dune/iphoneos/" ^ sdk.fingerprint ^ "/closure")
    in
    let* reachable_libraries =
      Dune_closure.resolve_project
        ~project_root
        ~target:config.native_target
        ~build_directory:closure_build_directory
    in
    let* _reachable_packages =
      Sdk.validate_application_lock
        ~project_root
        ~application_name:config.name
        ~reachable_libraries
        sdk.manifest
    in
    let toolchain_fingerprint = iphoneos_fingerprint ~config sdk.fingerprint in
    execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
;;

let flutter_dependency_inputs ~project_root ~(config : Config.t) =
  let flutter_root = Filename.concat project_root config.flutter_root in
  let packages_root = Filename.concat project_root ".bonsai-flutter/flutter-packages" in
  let required =
    [ Filename.concat flutter_root "pubspec.yaml"
    ; Filename.concat packages_root "bonsai_flutter/pubspec.yaml"
    ; Filename.concat packages_root "bonsai_flutter_native/pubspec.yaml"
    ]
  in
  match List.find_opt (fun path -> not (Sys.file_exists path)) required with
  | Some path -> Error (Printf.sprintf "Flutter dependency input is missing: %s" path)
  | None ->
    let optional =
      [ Filename.concat flutter_root "pubspec.lock"
      ; Filename.concat flutter_root "pubspec_overrides.yaml"
      ]
      |> List.filter Sys.file_exists
    in
    Ok (required @ optional)
;;

let flutter_dependency_fingerprint ~project_root ~config =
  try
    let* inputs = flutter_dependency_inputs ~project_root ~config in
    inputs
    |> List.map (fun path -> path ^ "\000" ^ Artifact.digest path)
    |> String.concat "\000"
    |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex
    |> Result.ok
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let flutter_pub_get ~project_root ~config =
  let flutter_root = Filename.concat project_root config.Config.flutter_root in
  let state =
    Filename.concat project_root "_build/bonsai-flutter/state/flutter/pub-get.sexp"
  in
  let package_config = Filename.concat flutter_root ".dart_tool/package_config.json" in
  let state_contents fingerprint =
    Printf.sprintf "(pub_get\n (format_version 1)\n (fingerprint %s))\n" fingerprint
  in
  try
    let* fingerprint = flutter_dependency_fingerprint ~project_root ~config in
    let current = state_contents fingerprint in
    let unchanged =
      Sys.file_exists package_config
      && Sys.file_exists state
      && String.equal (read_file state) current
    in
    if unchanged
    then Ok ()
    else (
      let command : Plan.command =
        { program = "flutter"
        ; arguments = [ "pub"; "get" ]
        ; working_directory = flutter_root
        ; environment = []
        }
      in
      let* () = Process_runner.run command in
      let* fingerprint = flutter_dependency_fingerprint ~project_root ~config in
      Artifact.write_if_changed state (state_contents fingerprint))
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
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
  let lock = Filename.concat project_root "_build/bonsai-flutter/locks/flutter.lock" in
  Lock.with_lock lock (fun () ->
    let* () = synchronize_flutter ~framework_root ~project_root ~config in
    let* _artifact =
      build_native ~framework_root ~project_root ~config ~target ~profile
    in
    let* () = flutter_pub_get ~project_root ~config in
    Host.with_artifact_profile
      ~project_root
      ~config
      ~profile:(Plan.profile_name profile)
      (fun () ->
         run_flutter_host
           ~framework_root
           ~project_root
           ~config
           ~action
           ~platform
           ~profile
           ~device
           ~no_codesign
           ~forwarded))
;;

let forward_signal process signal =
  try Unix.kill process signal with
  | Unix.Unix_error ((Unix.ESRCH | Unix.EPERM), _, _) -> ()
;;

let with_forwarded_interrupts f =
  let child = ref None in
  let received_signal = ref None in
  let handle_signal signal =
    if Option.is_none !received_signal then received_signal := Some signal;
    Option.iter (fun process -> forward_signal process signal) !child
  in
  let signals = [ Sys.sigint; Sys.sigterm; Sys.sighup; Sys.sigquit ] in
  let previous_handlers =
    List.map
      (fun signal -> signal, Sys.signal signal (Sys.Signal_handle handle_signal))
      signals
  in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun (signal, handler) -> ignore (Sys.signal signal handler))
        previous_handlers)
    (fun () ->
       let on_spawn process =
         child := Some process;
         Option.iter (forward_signal process) !received_signal
       in
       f ~on_spawn ~received_signal:(fun () -> !received_signal))
;;

let exec ~framework_root ~project_root ~config ~profile ~working_directory ~command =
  match command with
  | [] -> Error "A command is required after --"
  | program :: arguments ->
    let lock = Filename.concat project_root "_build/bonsai-flutter/locks/flutter.lock" in
    Lock.with_lock lock (fun () ->
      let* () = synchronize_flutter ~framework_root ~project_root ~config in
      let* _artifact =
        build_native ~framework_root ~project_root ~config ~target:Plan.Macos ~profile
      in
      let* () = flutter_pub_get ~project_root ~config in
      with_forwarded_interrupts (fun ~on_spawn ~received_signal ->
        let command : Plan.command =
          { program; arguments; working_directory; environment = [] }
        in
        let result =
          Host.with_artifact_profile
            ~project_root
            ~config
            ~profile:(Plan.profile_name profile)
            (fun () ->
               match received_signal () with
               | Some signal -> Ok (Process_runner.signal_exit_code signal)
               | None -> Process_runner.run_status ~on_spawn command)
        in
        match result, received_signal () with
        | Ok _, Some signal -> Ok (Process_runner.signal_exit_code signal)
        | result, None -> result
        | (Error _ as error), Some _ -> error))
;;
