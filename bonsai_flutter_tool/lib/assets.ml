let framework_marker root =
  Sys.file_exists (Filename.concat root "tool/ios/toolchain.lock")
  && Sys.file_exists (Filename.concat root "flutter/packages/bonsai_flutter/pubspec.yaml")
;;

let find_framework_root () =
  match Sys.getenv_opt "BONSAI_FLUTTER_SOURCE_ROOT" with
  | Some root when framework_marker root -> Ok root
  | Some root -> Error (Printf.sprintf "BONSAI_FLUTTER_SOURCE_ROOT is invalid: %s" root)
  | None ->
    let executable =
      try Unix.realpath Sys.executable_name with
      | Unix.Unix_error _ -> Sys.executable_name
    in
    let prefix = Filename.dirname (Filename.dirname executable) in
    let installed = Filename.concat prefix "share/bonsai_flutter_tool/framework" in
    if framework_marker installed
    then Ok installed
    else (
      let rec walk directory =
        if framework_marker directory
        then Some directory
        else (
          let parent = Filename.dirname directory in
          if String.equal parent directory then None else walk parent)
      in
      match walk (Sys.getcwd ()) with
      | Some root -> Ok root
      | None ->
        Error
          "The Bonsai Flutter framework assets are unavailable; reinstall \
           bonsai_flutter_tool")
;;

let ignored name = List.mem name [ ".dart_tool"; ".git"; "_build"; "build" ]

let copy_file source destination permissions =
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
    copy;
  Unix.chmod destination permissions
;;

let rec copy_tree source destination =
  let metadata = Unix.lstat source in
  match metadata.st_kind with
  | Unix.S_DIR ->
    Scaffold.ensure_directory destination;
    Sys.readdir source
    |> Array.iter (fun name ->
      if not (ignored name)
      then copy_tree (Filename.concat source name) (Filename.concat destination name))
  | Unix.S_REG -> copy_file source destination metadata.st_perm
  | Unix.S_LNK ->
    let target = Unix.readlink source in
    if Sys.file_exists destination then Sys.remove destination;
    Unix.symlink target destination
  | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK -> ()
;;

let synchronize_flutter_packages ~framework_root ~project_root =
  try
    let destination = Filename.concat project_root ".bonsai-flutter/flutter-packages" in
    List.iter
      (fun package ->
         copy_tree
           (Filename.concat framework_root ("flutter/packages/" ^ package))
           (Filename.concat destination package))
      [ "bonsai_flutter"; "bonsai_flutter_native" ];
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
