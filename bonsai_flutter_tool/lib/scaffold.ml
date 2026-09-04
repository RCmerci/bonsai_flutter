let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let rec ensure_directory path =
  if path = "" || path = Filename.dirname path || Sys.file_exists path
  then ()
  else (
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let write_if_missing path contents =
  if not (Sys.file_exists path)
  then (
    ensure_directory (Filename.dirname path);
    let channel = open_out_bin path in
    output_string channel contents;
    close_out channel)
;;

let read_file path =
  if not (Sys.file_exists path)
  then None
  else (
    let channel = open_in_bin path in
    let contents = really_input_string channel (in_channel_length channel) in
    close_in channel;
    Some contents)
;;

let write_if_changed path contents =
  if read_file path <> Some contents
  then (
    ensure_directory (Filename.dirname path);
    let channel = open_out_bin path in
    output_string channel contents;
    close_out channel)
;;

let managed_aliases_begin = "; BEGIN bonsai-flutter native aliases"
let managed_aliases_end = "; END bonsai-flutter native aliases"

let dune_native_aliases config =
  let dependency =
    Sexplib.Sexp.Atom (Filename.basename config.Config.native_target)
    |> Sexplib.Sexp.to_string
  in
  Printf.sprintf
    "%s\n\
     (alias\n\
    \ (name bonsai-flutter-macos)\n\
    \ (enabled_if (= %%{context_name} default))\n\
    \ (deps %s))\n\n\
     (alias\n\
    \ (name bonsai-flutter-ios)\n\
    \ (enabled_if (= %%{context_name} default.ios))\n\
    \ (deps %s))\n\
     %s\n"
    managed_aliases_begin
    dependency
    dependency
    managed_aliases_end
;;

let dune_alias_path ~project_root ~config =
  Filename.concat
    project_root
    (Filename.concat (Filename.dirname config.Config.native_target) "dune")
;;

let obsolete_dune_alias_path ~project_root ~config =
  Filename.concat
    project_root
    (Filename.concat (Filename.dirname config.Config.native_target) "bonsai_flutter/dune")
;;

let find_substring source pattern from =
  let source_length = String.length source in
  let pattern_length = String.length pattern in
  let rec search index =
    if index + pattern_length > source_length
    then None
    else if String.sub source index pattern_length = pattern
    then Some index
    else search (index + 1)
  in
  search from
;;

let replace_managed_aliases source replacement =
  match find_substring source managed_aliases_begin 0 with
  | None ->
    let separator =
      if source = "" || String.ends_with ~suffix:"\n" source then "" else "\n"
    in
    Ok (source ^ separator ^ "\n" ^ replacement)
  | Some begin_index ->
    (match find_substring source managed_aliases_end begin_index with
     | None -> Error "The app/dune managed alias block has no end marker"
     | Some end_index ->
       let suffix_index = end_index + String.length managed_aliases_end in
       let prefix = String.sub source 0 begin_index in
       let suffix =
         String.sub source suffix_index (String.length source - suffix_index)
       in
       Ok (prefix ^ replacement ^ suffix))
;;

let alias_contract config =
  let dependency = Filename.basename config.Config.native_target in
  [ "bonsai-flutter-macos", "default", dependency
  ; "bonsai-flutter-ios", "default.ios", dependency
  ]
;;

let alias_fields = function
  | Sexplib.Sexp.List (Sexplib.Sexp.Atom "alias" :: fields) -> Some fields
  | _ -> None
;;

let field name fields =
  fields
  |> List.filter_map (function
    | Sexplib.Sexp.List (Sexplib.Sexp.Atom actual :: values) when actual = name ->
      Some values
    | _ -> None)
;;

let alias_matches ~name ~context ~dependency fields =
  let expected_condition =
    Sexplib.Sexp.List
      [ Sexplib.Sexp.Atom "="
      ; Sexplib.Sexp.Atom "%{context_name}"
      ; Sexplib.Sexp.Atom context
      ]
  in
  field "name" fields = [ [ Sexplib.Sexp.Atom name ] ]
  && field "enabled_if" fields = [ [ expected_condition ] ]
  && field "deps" fields = [ [ Sexplib.Sexp.Atom dependency ] ]
  && List.length fields = 3
;;

let validate_dune_native_aliases ~project_root ~config =
  let path = dune_alias_path ~project_root ~config in
  let obsolete_path = obsolete_dune_alias_path ~project_root ~config in
  let invalid detail =
    Error
      (Printf.sprintf
         "Invalid application Dune alias contract in %s: %s. Run: bonsai-flutter \
          sync-project"
         path
         detail)
  in
  if Sys.file_exists obsolete_path
  then invalid (Printf.sprintf "obsolete alias file still exists at %s" obsolete_path)
  else (
    match read_file path with
    | None -> invalid "file is missing"
    | Some source ->
      (try
         let aliases =
           Sexplib.Sexp.of_string_many source |> List.filter_map alias_fields
         in
         let invalid_alias =
           alias_contract config
           |> List.find_opt (fun (name, context, dependency) ->
             aliases
             |> List.filter (fun fields ->
               field "name" fields = [ [ Sexplib.Sexp.Atom name ] ])
             |> function
             | [ fields ] -> not (alias_matches ~name ~context ~dependency fields)
             | [] | _ :: _ :: _ -> true)
         in
         match invalid_alias with
         | None -> Ok ()
         | Some (name, _, _) ->
           invalid (Printf.sprintf "alias %s is missing or invalid" name)
       with
       | Sexplib.Sexp.Parse_error _ -> invalid "file is not valid Dune syntax"))
;;

let remove_obsolete_dune_aliases ~project_root ~config =
  let path = obsolete_dune_alias_path ~project_root ~config in
  let directory = Filename.dirname path in
  if Sys.file_exists path
  then (
    match (Unix.lstat directory).st_kind with
    | Unix.S_DIR ->
      Sys.remove path;
      (try Unix.rmdir directory with
       | Unix.Unix_error (Unix.ENOTEMPTY, _, _) -> ())
    | Unix.S_LNK ->
      raise
        (Sys_error
           (Printf.sprintf "Refusing to follow obsolete alias symlink: %s" directory))
    | Unix.S_REG | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
      raise (Sys_error (Printf.sprintf "Invalid obsolete alias directory: %s" directory)))
;;

let write_dune_native_aliases ~project_root ~config =
  let path = dune_alias_path ~project_root ~config in
  let source = Option.value ~default:"" (read_file path) in
  match replace_managed_aliases source (dune_native_aliases config) with
  | Error _ as error -> error
  | Ok contents ->
    write_if_changed path contents;
    remove_obsolete_dune_aliases ~project_root ~config;
    Ok ()
;;

let synchronize_dune_native_aliases ~project_root ~config =
  try write_dune_native_aliases ~project_root ~config with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let generated_app_ml name =
  Printf.sprintf
    {|module Ui = Bonsai_flutter_ui

let component handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      set_count
      ~f:(fun set_count _ -> set_count (fun count -> count + 1))
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.App_bar.top ~title:(Ui.Widget.text "%s") ())
      ~body:
        (Ui.Widget.Body.static
           (Ui.Widget.center
              (Ui.Widget.column
                 [ Ui.Widget.text (Printf.sprintf "Count: %%d" count)
                 ; Ui.Material.elevated_button
                     ~on_press:increment
                     ~child:(Ui.Widget.text "Increment")
                     ()
                 ])))
      ())
;;

let app = App.create ~name:"%s" component
|}
    name
    name
;;

let native_embed name =
  Printf.sprintf
    {|let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "%s")
    Application.app
;;
|}
    name
;;

let app_dune =
  {|(library
 (name app)
 (wrapped false)
 (modules application)
 (libraries
  bonsai_flutter.spec_impl
  base
  bonsai
  bonsai_flutter.ui
  bonsai_flutter.driver
  incr_dom.ui_incr
  virtual_dom.ui_effect))

(executable
 (name native_embed)
 (modules native_embed)
 (enabled_if
  (= %{env:BONSAI_FLUTTER_EMBED_OCAML=disabled} enabled))
 (libraries
  bonsai_flutter.spec_impl
  app
  bonsai_flutter.driver
  bonsai_flutter.native_backend)
 (modes
  (native object)))
|}
;;

let configuration_text ~name ~features ~macos_minimum_version ~ios_minimum_version =
  let explicit_features =
    features
    |> List.filter (fun feature -> not (Config.Feature.equal feature Config.Feature.Core))
    |> List.map Config.Feature.to_string
  in
  let feature_line =
    match explicit_features with
    | [] -> " (features)"
    | features -> " (features " ^ String.concat " " features ^ ")"
  in
  Printf.sprintf
    {|(lang 2)

(app
 (name %s)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
%s
 (host
  (mode managed_adapter)
  (adapter lib/application_host_adapter.dart)
  (entrypoint %s)
  (launch_policy replace_existing))
 (macos
  (minimum_version %s)
  (architectures arm64))
 (ios
  (minimum_version %s)
  (architectures arm64)))
|}
    name
    feature_line
    name
    macos_minimum_version
    ios_minimum_version
;;

let application_host_adapter =
  {|import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/widgets.dart';

BonsaiFlutterHostAdapter createBonsaiFlutterHostAdapter() =>
    ApplicationHostAdapter();

final class ApplicationHostAdapter implements BonsaiFlutterHostAdapter {
  @override
  Future<Uint8List> createApplicationPayload() async => Uint8List(0);

  @override
  BonsaiFlutterApplicationPlatform? createApplicationPlatform() => null;

  @override
  Widget buildHost({
    required BuildContext context,
    required Widget child,
  }) => child;
}
|}
;;

let dune_project name =
  Printf.sprintf
    {|(lang dune 3.17)
(name %s)
(generate_opam_files false)
(license MIT)

(package
 (name %s)
 (allow_empty)
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (bonsai_flutter (= 0.1.0~dev))
  (bonsai_flutter_tool (= 0.1.0~dev))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))
|}
    name
    name
;;

let opam_manifest name =
  Printf.sprintf
    {|opam-version: "2.0"
name: "%s"
version: "0.1.0"
synopsis: "%s Bonsai Flutter application"
maintainer: "application authors"
authors: ["application authors"]
license: "MIT"
depends: [
  "ocaml" {= "5.1.1"}
  "dune" {>= "3.17"}
  "bonsai_flutter" {= "0.1.0~dev"}
  "bonsai_flutter_tool" {= "0.1.0~dev"}
  "base" {>= "v0.17" & < "v0.18~"}
  "bonsai" {>= "v0.17" & < "v0.18~"}
  "core" {>= "v0.17" & < "v0.18~"}
  "incr_dom" {>= "v0.17" & < "v0.18~"}
  "virtual_dom" {>= "v0.17" & < "v0.18~"}
]
build: [
  ["dune" "build" "-p" name "-j" jobs]
]
|}
    name
    name
;;

let opam_locked_manifest name =
  Printf.sprintf
    {|opam-version: "2.0"
name: "%s"
version: "0.1.0"
synopsis: "%s Bonsai Flutter application lock"
maintainer: "application authors"
authors: ["application authors"]
license: "MIT"
depends: [
  "ocaml" {= "5.1.1"}
  "ocaml-ios64" {= "5.1.1"}
  "dune" {= "3.23.1"}
  "bonsai_flutter" {= "0.1.0~dev"}
  "bonsai_flutter_tool" {= "0.1.0~dev"}
  "base" {= "v0.17.3"}
  "bonsai" {= "v0.17.0"}
  "core" {= "v0.17.2"}
  "incr_dom" {= "v0.17.0"}
  "virtual_dom" {= "v0.17.0"}
]
|}
    name
    name
;;

let initialize ~project_root ~config =
  try
    let app_directory = Filename.concat project_root "app" in
    write_if_missing
      (Filename.concat app_directory "application.ml")
      (generated_app_ml config.Config.name);
    write_if_missing (Filename.concat app_directory "application.mli") "val app : App.t\n";
    write_if_missing
      (Filename.concat app_directory "native_embed.ml")
      (native_embed config.name);
    write_if_missing (Filename.concat app_directory "dune") app_dune;
    (match config.Config.host with
     | Config.Managed_adapter adapter ->
       write_if_missing
         (Filename.concat
            (Filename.concat project_root config.Config.flutter_root)
            adapter.Config.adapter)
         application_host_adapter
     | Config.Custom _ -> ());
    let* () = write_dune_native_aliases ~project_root ~config in
    List.iter
      (fun (relative_path, contents) ->
         write_if_missing (Filename.concat project_root relative_path) contents)
      (Host.render ~config);
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let ensure_configuration ~project_root ~config_text =
  let path = Filename.concat project_root "bonsai-flutter.sexp" in
  match read_file path with
  | None ->
    write_if_missing path config_text;
    Ok ()
  | Some existing when String.equal existing config_text -> Ok ()
  | Some _ -> Error (Printf.sprintf "bonsai-flutter.sexp conflicts with %s" path)
;;

let initialize_metadata ~project_root ~config_text ~config =
  let* () = ensure_configuration ~project_root ~config_text in
  write_if_missing
    (Filename.concat project_root ".ocamlformat")
    "version=0.29.0\nprofile=janestreet\n";
  write_if_missing
    (Filename.concat project_root "dune-project")
    (dune_project config.Config.name);
  let existing_manifests =
    Sys.readdir project_root
    |> Array.to_list
    |> List.filter (fun name -> String.ends_with ~suffix:".opam" name)
  in
  if existing_manifests = []
  then (
    write_if_missing
      (Filename.concat project_root (config.name ^ ".opam"))
      (opam_manifest config.name);
    write_if_missing
      (Filename.concat project_root (config.name ^ ".opam.locked"))
      (opam_locked_manifest config.name));
  Ok ()
;;

let initialize_workspace ~project_root ~config_text ~config =
  try
    let* () = initialize_metadata ~project_root ~config_text ~config in
    initialize ~project_root ~config
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let adopt_workspace ~project_root ~config_text ~config =
  try
    let dune_path = dune_alias_path ~project_root ~config in
    if not (Sys.file_exists dune_path)
    then
      Error
        (Printf.sprintf "Cannot adopt: native target Dune file is missing: %s" dune_path)
    else
      let* () = initialize_metadata ~project_root ~config_text ~config in
      write_dune_native_aliases ~project_root ~config
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
