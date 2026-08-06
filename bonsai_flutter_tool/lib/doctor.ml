let command_version ~working_directory program arguments =
  match Process_runner.capture ~working_directory ~environment:[] program arguments with
  | Ok output -> Ok (program, output)
  | Error message -> Error (Printf.sprintf "%s is unavailable: %s" program message)
;;

let run ~project_root ~target =
  let common =
    [ "opam", [ "--version" ]; "dune", [ "--version" ]; "flutter", [ "--version" ] ]
  in
  let target_commands =
    match target with
    | None | Some Plan.Macos ->
      [ "xcodebuild", [ "-version" ]; "xcrun", [ "--sdk"; "macosx"; "--show-sdk-path" ] ]
    | Some Plan.Iphoneos ->
      [ "xcodebuild", [ "-version" ]
      ; "xcrun", [ "--sdk"; "iphoneos"; "--show-sdk-path" ]
      ]
  in
  let rec check acc = function
    | [] -> Ok (List.rev acc)
    | (program, arguments) :: rest ->
      (match command_version ~working_directory:project_root program arguments with
       | Ok diagnostic -> check (diagnostic :: acc) rest
       | Error _ as error -> error)
  in
  check [] (common @ target_commands)
;;
