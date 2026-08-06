let source ~project_root ~config ~target ~profile:_ =
  let build_root =
    match target with
    | Plan.Macos -> Filename.concat project_root "_build/default"
    | Plan.Iphoneos -> Filename.concat project_root "_build/iphoneos/default.ios"
  in
  Filename.concat build_root config.Config.native_target
;;

let destination ~project_root ~config ~target ~profile:_ =
  let platform =
    match target with
    | Plan.Macos -> "macos/arm64"
    | Plan.Iphoneos -> "ios/iphoneos/arm64"
  in
  Filename.concat
    project_root
    (Printf.sprintf
       "_build/bonsai-flutter/native-artifacts/%s/%s/native_embed.exe.o"
       config.Config.name
       platform)
;;

let copy_file source destination =
  Scaffold.ensure_directory (Filename.dirname destination);
  let input_channel = open_in_bin source in
  let output_channel = open_out_bin destination in
  let buffer = Bytes.create 65536 in
  let rec copy () =
    match input input_channel buffer 0 (Bytes.length buffer) with
    | 0 -> ()
    | count ->
      output output_channel buffer 0 count;
      copy ()
  in
  Fun.protect
    ~finally:(fun () ->
      close_in_noerr input_channel;
      close_out_noerr output_channel)
    copy
;;

let stage ~framework_root ~project_root ~config ~target ~profile =
  let source = source ~project_root ~config ~target ~profile in
  let destination = destination ~project_root ~config ~target ~profile in
  if not (Sys.file_exists source)
  then Error (Printf.sprintf "The native complete object is missing: %s" source)
  else (
    try
      copy_file source destination;
      let platform, minimum_version =
        match target with
        | Plan.Macos -> "MACOS", "26.0"
        | Plan.Iphoneos -> "IOS", config.Config.ios.minimum_version
      in
      let verify = Filename.concat framework_root "tool/ios/verify_complete_object.sh" in
      let command : Plan.command =
        { program = verify
        ; arguments = [ destination; platform; minimum_version; "arm64" ]
        ; working_directory = project_root
        ; environment = []
        }
      in
      match Process_runner.run command with
      | Ok () -> Ok destination
      | Error message -> Error message
    with
    | Sys_error message | Unix.Unix_error (_, _, message) -> Error message)
;;
