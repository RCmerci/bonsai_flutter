open Protocol_generator

let fail format = Printf.ksprintf failwith format

let expect condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format
;;

let expect_contains text fragment =
  let text_length = String.length text in
  let fragment_length = String.length fragment in
  let rec loop index =
    if index + fragment_length > text_length
    then false
    else if String.sub text index fragment_length = fragment
    then true
    else loop (index + 1)
  in
  expect (loop 0) "generated output is missing %S" fragment
;;

let load_schema () =
  match Schema.load "../schema.sexp" with
  | Ok schema -> schema
  | Error message -> fail "schema load failed: %s" message
;;

let test_schema_values () =
  let schema = load_schema () in
  expect (schema.major = 1) "unexpected protocol major";
  expect (schema.minor = 14) "unexpected protocol minor";
  expect (schema.limits.header_bytes = 48) "unexpected header size";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "incremental_frame" && entry.id = 3)
       schema.frame_kinds)
    "incremental frame ID was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "material_dialog" && entry.id = 107)
       schema.node_kinds)
    "material dialog ID was not parsed";
  let padding =
    List.find
      (fun (group : Schema.property_group) -> String.equal group.name "padding")
      schema.kind_props
  in
  expect
    (List.exists
       (fun (property : Schema.property) ->
          String.equal property.name "insets"
          && property.id = 1
          && String.equal property.encoding "edge_insets")
       padding.properties)
    "padding property schema was not parsed"
;;

let test_duplicate_ids_are_rejected () =
  let duplicate_schema =
    "((protocol (major 1) (minor 0) (header_bytes 48) (max_frame_bytes 1) \
     (max_string_bytes 1) (max_operations 1) (max_nodes 1)) (frame_kinds ((a 1) (b 1))) \
     (operations ()) (node_kinds ()) (event_tags ()) (host_requests ()) (runtime_errors \
     ()))"
  in
  match Schema.parse duplicate_schema with
  | Ok _ -> fail "duplicate IDs unexpectedly parsed"
  | Error message -> expect_contains message "duplicate ID"
;;

let test_all_targets_are_rendered_from_one_model () =
  let outputs = Render.all (load_schema ()) in
  expect_contains outputs.ocaml_interface "val protocol_major : int";
  expect_contains outputs.ocaml_implementation "let protocol_major = 1";
  expect_contains outputs.ocaml_implementation "let create_node = 2";
  expect_contains outputs.ocaml_implementation {|Some "create_node"|};
  expect_contains outputs.ocaml_interface "module Padding_prop : sig";
  expect_contains outputs.ocaml_interface "val insets : int";
  expect_contains outputs.ocaml_implementation "module Material_checkbox_prop = struct";
  expect_contains outputs.dart "static const int protocolMajor = 1;";
  expect_contains outputs.dart "static const int materialDialog = 107;";
  expect_contains outputs.dart "abstract final class PaddingPropId";
  expect_contains outputs.dart "abstract final class MaterialCheckboxPropId";
  expect_contains outputs.dart "static const int acceptedLocalRevision = 9;";
  expect_contains outputs.dart "static const int hostResponse = 19;";
  expect_contains outputs.dart "static const int nativeEvent = 21;";
  expect_contains outputs.dart "static const int nativeWidget = 128;";
  expect_contains outputs.dart "abstract final class PagePropId";
  expect_contains outputs.dart "static String? debugName(int id)";
  expect_contains outputs.dart "2 => 'create_node'";
  expect_contains outputs.markdown "| `runtime_error` | 5 |";
  expect_contains outputs.markdown "## Padding properties";
  expect_contains outputs.markdown "| `insets` | 1 | `edge_insets` |"
;;

let () =
  test_schema_values ();
  test_duplicate_ids_are_rejected ();
  test_all_targets_are_rendered_from_one_model ();
  print_endline "generator tests passed"
;;
