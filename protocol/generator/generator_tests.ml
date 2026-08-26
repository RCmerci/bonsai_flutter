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
  expect (schema.minor = 23) "unexpected protocol minor";
  expect (schema.limits.header_bytes = 48) "unexpected header size";
  expect
    (schema.limits.max_application_payload_bytes = 1_048_576)
    "unexpected application payload limit";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "incremental_frame" && entry.id = 3)
       schema.frame_kinds)
    "incremental frame ID was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "reserved_node_kind_107" && entry.id = 107)
       schema.node_kinds)
    "reserved node kind ID was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "material_linear_progress_indicator" && entry.id = 124)
       schema.node_kinds)
    "linear progress node kind ID was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "material_segmented_button" && entry.id = 125)
       schema.node_kinds)
    "segmented button node kind ID was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "segmented_selection_changed" && entry.id = 35)
       schema.event_tags)
    "segmented selection event tag was not parsed";
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
    "padding property schema was not parsed";
  let text_input =
    List.find
      (fun (group : Schema.property_group) -> String.equal group.name "text_input")
      schema.kind_props
  in
  expect
    (List.exists
       (fun (property : Schema.property) ->
          String.equal property.name "max_utf8_bytes"
          && property.id = 12
          && String.equal property.encoding "optional_u32")
       text_input.properties)
    "text input UTF-8 byte limit schema was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "text_limit_reached" && entry.id = 24)
       schema.event_tags)
    "text input limit event schema was not parsed";
  expect
    (List.exists
       (fun (entry : Schema.entry) ->
          String.equal entry.name "application_request" && entry.id = 11)
       schema.operations)
    "application request operation schema was not parsed";
  [ "application_response", 25; "application_request_error", 26; "application_event", 27 ]
  |> List.iter (fun (name, id) ->
    expect
      (List.exists
         (fun (entry : Schema.entry) -> String.equal entry.name name && entry.id = id)
         schema.event_tags)
      "%s event schema was not parsed"
      name)
;;

let test_duplicate_ids_are_rejected () =
  let duplicate_schema =
    "((protocol (major 1) (minor 0) (header_bytes 48) (max_frame_bytes 1) \
     (max_string_bytes 1) (max_application_payload_bytes 1) (max_operations 1) \
     (max_nodes 1)) (frame_kinds ((a 1) (b 1))) (operations ()) (node_kinds ()) \
     (event_tags ()) (host_requests ()) (runtime_errors ()))"
  in
  match Schema.parse duplicate_schema with
  | Ok _ -> fail "duplicate IDs unexpectedly parsed"
  | Error message -> expect_contains message "duplicate ID"
;;

let test_all_targets_are_rendered_from_one_model () =
  let outputs = Render.all (load_schema ()) in
  expect_contains outputs.ocaml_interface "val protocol_major : int";
  expect_contains outputs.ocaml_implementation "let protocol_major = 1";
  expect_contains outputs.ocaml_implementation "module ID = Bonsai_flutter_spec.Id";
  expect_contains
    outputs.ocaml_implementation
    "let create_node = ID.Protocol.Operation.of_int 2";
  expect_contains
    outputs.ocaml_implementation
    "match ID.Protocol.Operation.to_int id with";
  expect_contains outputs.ocaml_implementation {|Some "create_node"|};
  expect_contains
    outputs.ocaml_interface
    "val incremental_frame : Bonsai_flutter_spec.Id.Protocol.frame_kind";
  expect_contains
    outputs.ocaml_interface
    "val create_node : Bonsai_flutter_spec.Id.Protocol.operation";
  expect_contains
    outputs.ocaml_interface
    "val reserved_node_kind_107 : Bonsai_flutter_spec.Id.Protocol.node_kind";
  expect_contains
    outputs.ocaml_interface
    "val material_linear_progress_indicator : Bonsai_flutter_spec.Id.Protocol.node_kind";
  expect_contains
    outputs.ocaml_interface
    "val material_segmented_button : Bonsai_flutter_spec.Id.Protocol.node_kind";
  expect_contains
    outputs.ocaml_interface
    "val host_response : Bonsai_flutter_spec.Id.Protocol.event_tag";
  expect_contains
    outputs.ocaml_interface
    "val application_request : Bonsai_flutter_spec.Id.Protocol.operation";
  expect_contains
    outputs.ocaml_interface
    "val application_response : Bonsai_flutter_spec.Id.Protocol.event_tag";
  expect_contains
    outputs.ocaml_interface
    "val application_request_error : Bonsai_flutter_spec.Id.Protocol.event_tag";
  expect_contains
    outputs.ocaml_interface
    "val application_event : Bonsai_flutter_spec.Id.Protocol.event_tag";
  expect_contains
    outputs.ocaml_interface
    "val clipboard_read : Bonsai_flutter_spec.Id.Protocol.host_request_kind";
  expect_contains
    outputs.ocaml_interface
    "val stale_event : Bonsai_flutter_spec.Id.Protocol.runtime_error";
  expect_contains outputs.ocaml_interface "module Padding_prop : sig";
  expect_contains
    outputs.ocaml_interface
    "val insets : Bonsai_flutter_spec.Id.Protocol.property";
  expect_contains outputs.ocaml_implementation "module Material_checkbox_prop = struct";
  expect_contains outputs.dart "static const int protocolMajor = 1;";
  expect_contains outputs.dart "static const int reservedNodeKind107 = 107;";
  expect_contains outputs.dart "static const int materialLinearProgressIndicator = 124;";
  expect_contains outputs.dart "static const int materialSegmentedButton = 125;";
  expect_contains outputs.dart "static const int segmentedSelectionChanged = 35;";
  expect_contains outputs.dart "abstract final class PaddingPropId";
  expect_contains outputs.dart "abstract final class MaterialCheckboxPropId";
  expect_contains outputs.dart "static const int acceptedLocalRevision = 9;";
  expect_contains outputs.dart "static const int maxUtf8Bytes = 12;";
  expect_contains outputs.dart "static const int hostResponse = 19;";
  expect_contains outputs.dart "static const int nativeEvent = 21;";
  expect_contains outputs.dart "static const int textLimitReached = 24;";
  expect_contains outputs.dart "static const int applicationRequest = 11;";
  expect_contains outputs.dart "static const int applicationResponse = 25;";
  expect_contains outputs.dart "static const int applicationRequestError = 26;";
  expect_contains outputs.dart "static const int applicationEvent = 27;";
  expect_contains outputs.dart "static const int maxApplicationPayloadBytes = 1048576;";
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
