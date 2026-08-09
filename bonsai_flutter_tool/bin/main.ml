open Bonsai_flutter_tool
open Cmdliner

let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let write_file_if_missing path contents =
  if Sys.file_exists path
  then Ok ()
  else (
    try
      Scaffold.ensure_directory (Filename.dirname path);
      let channel = open_out_bin path in
      output_string channel contents;
      close_out channel;
      Ok ()
    with
    | Sys_error message | Unix.Unix_error (_, _, message) -> Error message)
;;

let parse_features value =
  let names =
    value
    |> String.split_on_char ','
    |> List.map String.trim
    |> List.filter (fun name -> name <> "")
  in
  let rec parse acc = function
    | [] -> Ok (List.rev acc)
    | name :: rest ->
      (match Config.Feature.of_string name with
       | Ok Config.Feature.Core -> parse acc rest
       | Ok feature -> parse (feature :: acc) rest
       | Error _ as error -> error)
  in
  parse [ Config.Feature.Core ] names
;;

let run_flutter_create ~project_root ~config =
  let flutter_root = Filename.concat project_root config.Config.flutter_root in
  if
    Sys.file_exists (Filename.concat flutter_root "macos")
    && Sys.file_exists (Filename.concat flutter_root "ios")
  then Ok ()
  else (
    let command : Plan.command =
      { program = "flutter"
      ; arguments =
          [ "create"
          ; "--platforms=macos,ios"
          ; "--project-name"
          ; "bonsai_flutter_" ^ config.name ^ "_host"
          ; config.flutter_root
          ]
      ; working_directory = project_root
      ; environment = []
      }
    in
    Process_runner.run command)
;;

let init name features macos_minimum ios_minimum adopt =
  let project_root = Sys.getcwd () in
  let configuration_path = Filename.concat project_root "bonsai-flutter.sexp" in
  if adopt && not (Sys.file_exists configuration_path)
  then Error "--adopt requires an existing bonsai-flutter.sexp"
  else if (not adopt) && Sys.file_exists configuration_path
  then Error "bonsai-flutter.sexp already exists; use bonsai-flutter init --adopt"
  else
    let* configuration_text =
      if adopt
      then
        let* config = Config.parse_file configuration_path in
        Ok
          (Scaffold.configuration_text
             ~name:config.name
             ~features:config.features
             ~macos_minimum_version:config.macos.minimum_version
             ~ios_minimum_version:config.ios.minimum_version)
      else
        let* name =
          match name with
          | Some name -> Ok name
          | None -> Error "--name is required unless --adopt is used"
        in
        let* features = parse_features features in
        Ok
          (Scaffold.configuration_text
             ~name
             ~features
             ~macos_minimum_version:macos_minimum
             ~ios_minimum_version:ios_minimum)
    in
    let* () = write_file_if_missing configuration_path configuration_text in
    let* config = Config.parse_file configuration_path in
    let* () =
      Scaffold.initialize_workspace ~project_root ~config_text:configuration_text ~config
    in
    let* framework_root = Assets.find_framework_root () in
    let* () = Assets.synchronize_flutter_packages ~framework_root ~project_root in
    let* () = run_flutter_create ~project_root ~config in
    let* changed = Host.sync ~project_root ~config ~mode:Host.Write in
    List.iter (fun path -> Printf.printf "generated %s\n%!" path) changed;
    Ok ()
;;

let load_project () =
  let* project_root = Project.find_root (Sys.getcwd ()) in
  let* config = Config.parse_file (Filename.concat project_root "bonsai-flutter.sexp") in
  Ok (project_root, config)
;;

let doctor target =
  let* project_root, _config = load_project () in
  let* diagnostics = Doctor.run ~project_root ~target in
  List.iter
    (fun (program, output) ->
       let summary =
         match String.split_on_char '\n' output with
         | first :: _ -> first
         | [] -> output
       in
       Printf.printf "ok %-12s %s\n%!" program summary)
    diagnostics;
  Ok ()
;;

let build_native target profile =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  let* artifact =
    Build_system.build_native ~framework_root ~project_root ~config ~target ~profile
  in
  Printf.printf "native artifact: %s\n%!" artifact;
  Ok ()
;;

let run platform profile device forwarded =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  if platform = Plan.Ios_platform && Option.is_none device
  then Error "bonsai-flutter run ios requires --device <device-id>"
  else
    Build_system.run_flutter
      ~framework_root
      ~project_root
      ~config
      ~action:Plan.Run
      ~platform
      ~profile
      ~device
      ~no_codesign:false
      ~forwarded
;;

let build platform profile no_codesign forwarded =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  Build_system.run_flutter
    ~framework_root
    ~project_root
    ~config
    ~action:Plan.Build
    ~platform
    ~profile
    ~device:None
    ~no_codesign
    ~forwarded
;;

let sync_host check =
  let* project_root, config = load_project () in
  let mode = if check then Host.Check else Host.Write in
  let* changed = Host.sync ~project_root ~config ~mode in
  if changed = [] then Printf.printf "generated host is up to date\n%!";
  List.iter (fun path -> Printf.printf "updated %s\n%!" path) changed;
  Ok ()
;;

let sync_project check =
  let* project_root, config = load_project () in
  if check
  then (
    let* () = Scaffold.validate_dune_native_aliases ~project_root ~config in
    Printf.printf "application Dune aliases are up to date\n%!";
    Ok ())
  else (
    Printf.printf "%s\n%!" (Scaffold.dune_alias_path ~project_root ~config);
    Build_system.synchronize ~framework_root:"" ~project_root ~config)
;;

let clean platform all_project_builds =
  let* project_root, _config = load_project () in
  match platform, all_project_builds with
  | Some _, true -> Error "Select a platform or --all-project-builds, not both"
  | None, false -> Error "Select macos, iphoneos, or --all-project-builds"
  | Some Clean.Macos, false -> Clean.run ~project_root Clean.Macos
  | Some Clean.Iphoneos, false -> Clean.run ~project_root Clean.Iphoneos
  | Some Clean.All, false -> assert false
  | None, true -> Clean.run ~project_root Clean.All
;;

let toolchain_show () =
  let* info = Toolchain.show ~working_directory:(Sys.getcwd ()) in
  Printf.printf
    "switch: %s\n\
     prefix: %s\n\
     manifest: %s\n\
     fingerprint: %s\n\
     bonsai_flutter: %s\n\
     ocaml: %s\n\
     target: %s\n\
     %!"
    info.switch
    info.prefix
    info.manifest_path
    info.fingerprint
    info.bonsai_flutter_version
    info.ocaml_version
    info.target;
  Ok ()
;;

let toolchain_verify () =
  let* verified = Toolchain.verify ~working_directory:(Sys.getcwd ()) in
  Printf.printf "verified iPhoneOS toolchain: %s\n%!" verified.fingerprint;
  Ok ()
;;

let toolchain_remove () = Toolchain.remove ~working_directory:(Sys.getcwd ())

let toolchain_install () =
  let* framework_root = Assets.find_framework_root () in
  Toolchain.install ~framework_root ~working_directory:(Sys.getcwd ())
;;

let resolve_dune_closure project_root target =
  let target_key = Digest.string target |> Digest.to_hex in
  let build_directory =
    Filename.concat
      project_root
      ("_build/bonsai-flutter/dune/internal-closure/" ^ target_key)
  in
  let* dependencies =
    Dune_closure.resolve_project ~project_root ~target ~build_directory
  in
  List.iter print_endline dependencies;
  Ok ()
;;

let target =
  Arg.(
    required
    & opt (some (enum [ "macos", Plan.Macos; "iphoneos", Plan.Iphoneos ])) None
    & info [ "target" ] ~docv:"TARGET" ~doc:"Native target: macos or iphoneos.")
;;

let profile =
  Arg.(
    value
    & opt
        (enum [ "debug", Plan.Debug; "profile", Plan.Profile; "release", Plan.Release ])
        Plan.Debug
    & info [ "profile" ] ~docv:"PROFILE" ~doc:"Build profile.")
;;

let platform =
  Arg.(
    required
    & pos 0 (some (enum [ "macos", Plan.Macos_platform; "ios", Plan.Ios_platform ])) None
    & info [] ~docv:"PLATFORM")
;;

let forwarded = Arg.(value & pos_right 0 string [] & info [] ~docv:"FLUTTER_ARGUMENT")
let features = Arg.(value & opt string "" & info [ "features" ] ~docv:"FEATURES")

let resolve_dune_closure_command =
  let project_root =
    Arg.(required & opt (some string) None & info [ "project-root" ] ~docv:"PATH")
  in
  let target =
    Arg.(required & opt (some string) None & info [ "target" ] ~docv:"DUNE_TARGET")
  in
  Cmd.v
    (Cmd.info
       "internal-resolve-dune-closure"
       ~doc:"Resolve the external Dune closure of one application target.")
    Term.(const resolve_dune_closure $ project_root $ target)
;;

let init_command =
  let name = Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME") in
  let macos =
    Arg.(value & opt string "26.0" & info [ "macos-minimum-version" ] ~docv:"VERSION")
  in
  let ios =
    Arg.(value & opt string "15.0" & info [ "ios-deployment-target" ] ~docv:"VERSION")
  in
  let adopt =
    Arg.(value & flag & info [ "adopt" ] ~doc:"Adopt an existing configuration.")
  in
  Cmd.v
    (Cmd.info "init" ~doc:"Initialize or adopt a Bonsai Flutter application.")
    Term.(const init $ name $ features $ macos $ ios $ adopt)
;;

let doctor_command =
  let optional_target =
    Arg.(
      value
      & opt (some (enum [ "macos", Plan.Macos; "iphoneos", Plan.Iphoneos ])) None
      & info [ "target" ] ~docv:"TARGET")
  in
  Cmd.v
    (Cmd.info "doctor" ~doc:"Check the local development environment.")
    Term.(const doctor $ optional_target)
;;

let build_native_command =
  Cmd.v
    (Cmd.info "build-native" ~doc:"Build and stage the OCaml complete object.")
    Term.(const build_native $ target $ profile)
;;

let run_command =
  let device =
    Arg.(value & opt (some string) None & info [ "device" ] ~docv:"DEVICE_ID")
  in
  Cmd.v
    (Cmd.info "run" ~doc:"Build the native object and run the Flutter host.")
    Term.(const run $ platform $ profile $ device $ forwarded)
;;

let build_command =
  let no_codesign = Arg.(value & flag & info [ "no-codesign" ]) in
  Cmd.v
    (Cmd.info "build" ~doc:"Build the complete Flutter application.")
    Term.(const build $ platform $ profile $ no_codesign $ forwarded)
;;

let sync_host_command =
  let check =
    Arg.(value & flag & info [ "check" ] ~doc:"Check without modifying files.")
  in
  Cmd.v
    (Cmd.info "sync-host" ~doc:"Synchronize the mechanical Flutter host.")
    Term.(const sync_host $ check)
;;

let sync_project_command =
  let check =
    Arg.(value & flag & info [ "check" ] ~doc:"Check without modifying app/dune.")
  in
  Cmd.v
    (Cmd.info "sync-project" ~doc:"Validate or repair application Dune aliases.")
    Term.(const sync_project $ check)
;;

let clean_command =
  let platform =
    Arg.(
      value
      & pos 0 (some (enum [ "macos", Clean.Macos; "iphoneos", Clean.Iphoneos ])) None
      & info [] ~docv:"PLATFORM")
  in
  let all_project_builds =
    Arg.(
      value
      & flag
      & info
          [ "all-project-builds" ]
          ~doc:"Delete all Bonsai Flutter build state in this project.")
  in
  Cmd.v
    (Cmd.info "clean" ~doc:"Delete project-local Bonsai Flutter build output.")
    Term.(const clean $ platform $ all_project_builds)
;;

let toolchain_command =
  let iphoneos =
    Arg.(required & pos 0 (some (enum [ "iphoneos", () ])) None & info [] ~docv:"TARGET")
  in
  let subcommand name doc action =
    Cmd.v (Cmd.info name ~doc) Term.(const (fun () -> action ()) $ iphoneos)
  in
  Cmd.group
    (Cmd.info
       "toolchain"
       ~doc:"Install, inspect, or remove the global iPhoneOS toolchain.")
    [ subcommand "install" "Install the locked global iPhoneOS SDK." toolchain_install
    ; subcommand "show" "Show the installed iPhoneOS SDK manifest." toolchain_show
    ; subcommand "verify" "Verify the installed iPhoneOS SDK." toolchain_verify
    ; subcommand "remove" "Remove the fixed global iPhoneOS switch." toolchain_remove
    ]
;;

let command =
  Cmd.group
    (Cmd.info
       "bonsai-flutter"
       ~version:"0.1.0~dev"
       ~doc:"OCaml-first tooling for Bonsai Flutter applications.")
    [ init_command
    ; doctor_command
    ; build_native_command
    ; run_command
    ; build_command
    ; sync_host_command
    ; sync_project_command
    ; clean_command
    ; toolchain_command
    ; resolve_dune_closure_command
    ]
;;

let () = exit (Cmd.eval_result command)
