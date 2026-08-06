let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let command ~framework_root ?(environment = []) program arguments =
  let command : Plan.command =
    { program = Filename.concat framework_root program
    ; arguments
    ; working_directory = framework_root
    ; environment
    }
  in
  Process_runner.run command
;;

let features_string features =
  features
  |> List.map Config.Feature.to_string
  |> List.sort_uniq String.compare
  |> String.concat ","
;;

let find_application_opam_file project_root =
  let candidates =
    Sys.readdir project_root
    |> Array.to_list
    |> List.filter (fun filename -> Filename.check_suffix filename ".opam")
    |> List.sort String.compare
  in
  match candidates with
  | [ filename ] -> Ok (Filename.concat project_root filename)
  | [] -> Error "The application must provide one pinned top-level opam file"
  | _ ->
    Error "The application has multiple top-level opam files; select one package root"
;;

let closure_lock_path project_root =
  Filename.concat project_root "_build/bonsai-flutter/ios/runtime-closure.lock"
;;

let sdk_identity_path project_root =
  Filename.concat project_root "_build/bonsai-flutter/ios/sdk-identity"
;;

let read_file path =
  try
    let channel = open_in_bin path in
    let value = really_input_string channel (in_channel_length channel) in
    close_in channel;
    Ok (String.trim value)
  with
  | Sys_error message -> Error message
;;

let write_file path contents =
  try
    Scaffold.ensure_directory (Filename.dirname path);
    let channel = open_out_bin path in
    output_string channel contents;
    output_char channel '\n';
    close_out channel;
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let application_sdk_root ~framework_root ~project_root =
  let* identity = read_file (sdk_identity_path project_root) in
  Ok (Filename.concat framework_root ("_build/ios/sdk-cache/" ^ identity))
;;

let application_target_lib ~framework_root ~project_root =
  let* sdk_root = application_sdk_root ~framework_root ~project_root in
  Ok (Filename.concat sdk_root "lib")
;;

let application_findlib_conf ~framework_root ~project_root =
  let* sdk_root = application_sdk_root ~framework_root ~project_root in
  Ok (Filename.concat sdk_root "findlib.conf")
;;

let identity ~framework_root ~lock ~features =
  let features = features_string features in
  Process_runner.capture
    ~working_directory:framework_root
    ~environment:[]
    (Filename.concat framework_root "tool/ios/resolve_application_closure.sh")
    [ "--identity"; "--lock"; lock; "--features"; features ]
;;

let verify_lock ~framework_root ~lock ~features ~target_lib =
  command
    ~framework_root
    ~environment:
      [ "IPHONEOS_SWITCH", Filename.concat framework_root "_build/ios/switches/iphoneos" ]
    "tool/ios/verify_runtime_closure.sh"
    [ "--lock"; lock; "--features"; features_string features; "--target-lib"; target_lib ]
;;

let verify ~framework_root ~project_root ~features ~target =
  match target with
  | Plan.Macos -> Ok ()
  | Plan.Iphoneos ->
    let switch = Filename.concat framework_root "_build/ios/switches/iphoneos" in
    if not (Sys.file_exists (Filename.concat switch "_opam/bin/ocamlc"))
    then
      Error
        "The iPhoneOS SDK is not cached. Run: bonsai-flutter sdk build-from-source \
         --target iphoneos"
    else (
      let lock = closure_lock_path project_root in
      if not (Sys.file_exists lock)
      then Error "The application iPhoneOS closure lock is missing; build its SDK first"
      else
        let* target_lib = application_target_lib ~framework_root ~project_root in
        verify_lock ~framework_root ~lock ~features ~target_lib)
;;

let resolve_application_lock
      ~framework_root
      ~project_root
      ~features
      ~application_opam_file
  =
  let lock = closure_lock_path project_root in
  Scaffold.ensure_directory (Filename.dirname lock);
  let switch = Filename.concat framework_root "_build/ios/switches/iphoneos" in
  let environment =
    [ "OPAMROOT", Filename.concat framework_root "_build/ios/opam-root"
    ; "HOST_OCAML_SWITCH", switch
    ; "APPLICATION_OPAM_FILE", application_opam_file
    ; "BONSAI_FLUTTER_FEATURES", features_string features
    ]
  in
  let* () =
    command
      ~framework_root
      ~environment
      "tool/ios/resolve_application_closure.sh"
      [ "iphoneos"; project_root; lock ]
  in
  Ok lock
;;

let build_application_sdk ~framework_root ~project_root ~features =
  let* application_opam_file = find_application_opam_file project_root in
  let common_environment =
    [ "APPLICATION_OPAM_FILE", application_opam_file
    ; "BONSAI_FLUTTER_FEATURES", features_string features
    ; "SKIP_CLOSURE_VERIFY", "true"
    ]
  in
  let* () = command ~framework_root "tool/ios/setup_toolchain.sh" [ "iphoneos" ] in
  let* () =
    command
      ~framework_root
      ~environment:common_environment
      "tool/ios/setup_host_dependencies.sh"
      [ "iphoneos" ]
  in
  let* lock =
    resolve_application_lock
      ~framework_root
      ~project_root
      ~features
      ~application_opam_file
  in
  let* closure_digest = identity ~framework_root ~lock ~features in
  let features_digest =
    Digestif.SHA256.(to_hex (digest_string (features_string features)))
  in
  let sdk_cache_root =
    Filename.concat framework_root ("_build/ios/sdk-cache/" ^ closure_digest)
  in
  let target_lib = Filename.concat sdk_cache_root "lib" in
  Scaffold.ensure_directory target_lib;
  let environment =
    [ "RUNTIME_CLOSURE_LOCK", lock
    ; "TARGET_LIB", target_lib
    ; "BONSAI_FLUTTER_FEATURES", features_string features
    ; "BONSAI_FLUTTER_CLOSURE_DIGEST", closure_digest
    ; "BONSAI_FLUTTER_FEATURES_DIGEST", features_digest
    ]
  in
  let* () =
    command
      ~framework_root
      ~environment
      "tool/ios/build_runtime_closure.sh"
      [ "iphoneos" ]
  in
  let findlib_conf = Filename.concat sdk_cache_root "findlib.conf" in
  let* () =
    command ~framework_root "tool/ios/write_findlib_conf.sh" [ target_lib; findlib_conf ]
  in
  let* () = verify_lock ~framework_root ~lock ~features ~target_lib in
  write_file (sdk_identity_path project_root) closure_digest
;;

let build_from_source ~framework_root ~project_root ~target ~features =
  match target, project_root with
  | Plan.Macos, _ -> Ok ()
  | Plan.Iphoneos, Some project_root ->
    build_application_sdk ~framework_root ~project_root ~features
  | Plan.Iphoneos, None ->
    Error
      "An iPhoneOS SDK build requires an application project root with pinned opam \
       metadata"
;;

let fetch ~target:_ ~features:_ =
  Error
    "No prebuilt SDK distribution is configured for this development version. Run: \
     bonsai-flutter sdk build-from-source --target iphoneos"
;;
