let command ~framework_root program arguments =
  let command : Plan.command =
    { program = Filename.concat framework_root program
    ; arguments
    ; working_directory = framework_root
    ; environment = []
    }
  in
  Process_runner.run command
;;

let verify ~framework_root ~target =
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
      let environment =
        [ "OPAMROOT", Filename.concat framework_root "_build/ios/opam-root"
        ; "HOST_OCAML_SWITCH", switch
        ]
      in
      let command : Plan.command =
        { program = Filename.concat framework_root "tool/ios/verify_runtime_closure.sh"
        ; arguments = []
        ; working_directory = framework_root
        ; environment
        }
      in
      Process_runner.run command)
;;

let build_from_source ~framework_root ~target ~features:_ =
  match target with
  | Plan.Macos -> Ok ()
  | Plan.Iphoneos ->
    (match verify ~framework_root ~target with
     | Ok () -> Ok ()
     | Error _ ->
       let steps =
         [ "tool/ios/setup_toolchain.sh", [ "iphoneos" ]
         ; "tool/ios/setup_host_dependencies.sh", [ "iphoneos" ]
         ; "tool/ios/build_runtime_closure.sh", [ "iphoneos" ]
         ]
       in
       List.fold_left
         (fun result (program, arguments) ->
            match result with
            | Error _ -> result
            | Ok () -> command ~framework_root program arguments)
         (Ok ())
         steps)
;;

let fetch ~target:_ ~features:_ =
  Error
    "No prebuilt SDK distribution is configured for this development version. Run: \
     bonsai-flutter sdk build-from-source --target iphoneos"
;;
