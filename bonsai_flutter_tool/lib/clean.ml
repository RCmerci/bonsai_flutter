type target =
  | Macos
  | Iphoneos
  | All

let rec remove_tree path =
  try
    match (Unix.lstat path).st_kind with
    | Unix.S_DIR ->
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    | Unix.S_REG | Unix.S_LNK | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
      Unix.unlink path
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> ()
;;

let platform_paths = function
  | Macos ->
    [ "dune/macos"; "artifacts/macos"; "state/macos"; "logs/macos"; "locks/macos" ]
  | Iphoneos ->
    [ "dune/iphoneos"
    ; "artifacts/ios"
    ; "state/iphoneos"
    ; "logs/iphoneos"
    ; "locks/iphoneos"
    ]
  | All -> []
;;

let run ~project_root target =
  try
    if Filename.is_relative project_root
    then Error "The project root must be absolute"
    else (
      let project_root = Unix.realpath project_root in
      if project_root = Filename.dir_sep
      then Error "Refusing to clean from the filesystem root"
      else (
        let build_root = Filename.concat project_root "_build/bonsai-flutter" in
        (match target with
         | All -> remove_tree build_root
         | Macos | Iphoneos ->
           platform_paths target
           |> List.iter (fun relative_path ->
             remove_tree (Filename.concat build_root relative_path)));
        Ok ()))
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
