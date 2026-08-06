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
      ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "%s") ())
      ~body:
        (Ui.Widget.center
           (Ui.Widget.column
              [ Ui.Widget.text (Printf.sprintf "Count: %%d" count)
              ; Ui.Material.elevated_button
                  ~on_press:increment
                  ~child:(Ui.Widget.text "Increment")
                  ()
              ]))
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
    {|(lang 1)

(app
 (name %s)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
%s
 (macos
  (minimum_version %s))
 (ios
  (minimum_version %s)
  (architectures arm64)))
|}
    name
    feature_line
    macos_minimum_version
    ios_minimum_version
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
    List.iter
      (fun (relative_path, contents) ->
         write_if_missing (Filename.concat project_root relative_path) contents)
      (Host.render ~config);
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let initialize_workspace ~project_root ~config_text ~config =
  try
    write_if_missing (Filename.concat project_root "bonsai-flutter.sexp") config_text;
    write_if_missing
      (Filename.concat project_root ".ocamlformat")
      "version=0.29.0\nprofile=janestreet\n";
    write_if_missing
      (Filename.concat project_root "dune-project")
      (dune_project config.Config.name);
    write_if_missing
      (Filename.concat project_root (config.name ^ ".opam"))
      (opam_manifest config.name);
    initialize ~project_root ~config
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
