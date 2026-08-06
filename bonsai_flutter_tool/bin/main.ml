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

let sdk_build target features =
  let* framework_root = Assets.find_framework_root () in
  let* features = parse_features features in
  Sdk.build_from_source ~framework_root ~project_root:None ~target ~features
;;

let sdk_verify target =
  let* framework_root = Assets.find_framework_root () in
  Sdk.verify ~framework_root ~target
;;

let sdk_fetch target features =
  let* features = parse_features features in
  Sdk.fetch ~target ~features
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

let init_command =
  let name = Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME") in
  let macos =
    Arg.(value & opt string "13.0" & info [ "macos-minimum-version" ] ~docv:"VERSION")
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

let sdk_command =
  let build_from_source =
    Cmd.v
      (Cmd.info "build-from-source" ~doc:"Build a native SDK from locked sources.")
      Term.(const sdk_build $ target $ features)
  in
  let verify =
    Cmd.v
      (Cmd.info "verify" ~doc:"Verify a cached native SDK.")
      Term.(const sdk_verify $ target)
  in
  let fetch =
    Cmd.v
      (Cmd.info "fetch" ~doc:"Fetch a prebuilt native SDK.")
      Term.(const sdk_fetch $ target $ features)
  in
  Cmd.group
    (Cmd.info "sdk" ~doc:"Manage native SDKs.")
    [ fetch; verify; build_from_source ]
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
    ; sdk_command
    ]
;;

let () = exit (Cmd.eval_result command)
