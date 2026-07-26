module Ui = Bonsai_flutter_ui
module Protocol = Bonsai_flutter_protocol

let fail message = raise (Failure message)
let check condition message = if not condition then fail message

type dial_event = Changed of int

let dial_extension =
  Ui.Native_widget.Extension.create
    ~kind_id:42
    ~version:3
    ~capabilities:[ Ui.Native_widget.Capability.Stateful ]
    ~encode_props:(fun value -> Bytes.of_string (string_of_int value))
    ~decode_event:(fun ~event_id payload ->
      if event_id = 7
      then Ok (Changed (int_of_string (Bytes.to_string payload)))
      else Error "unknown dial event")
    ()
;;

let test_typed_native_widget () =
  let received = ref None in
  let widget =
    Ui.Native_widget.widget
      dial_extension
      ~key:(Ui.Key.string "dial")
      ~props:17
      ~on_event:(fun event -> received := Some event)
      ()
  in
  let view = Ui.Widget.Private.view widget in
  check (Ui.Widget.Private.Kind.equal view.kind Native_widget) "native widget kind";
  (match view.props with
   | Native_widget_props { kind_id; version; capabilities; payload } ->
     check (kind_id = 42) "native kind ID";
     check (version = 3) "native version";
     check (Int64.equal capabilities 1L) "native capabilities";
     check (Bytes.equal payload (Bytes.of_string "17")) "native props payload"
   | _ -> fail "native widget props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = 42; version = 3; event_id = 7; payload = Bytes.of_string "23" });
  check (!received = Some (Changed 23)) "typed native event"
;;

let test_virtual_list_window () =
  let items =
    List.init 20 (fun index ->
      Ui.Widget.text
        ~key:(Ui.Key.string (string_of_int (100 + index)))
        (string_of_int (100 + index)))
  in
  let received = ref None in
  let widget =
    Ui.Native_widget.Virtual_list.create
      ~key:(Ui.Key.string "large-list")
      ~total_count:50_000
      ~first_index:100
      ~item_extent:48.
      ~overscan:4
      ~items
      ~on_visible_range:(fun range -> received := Some range)
      ()
  in
  let view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 20) "only the supplied window is mounted";
  (match view.props with
   | Native_widget_props { kind_id; payload; _ } ->
     check (kind_id = Ui.Native_widget.Virtual_list.kind_id) "virtual list extension ID";
     let props = Ui.Native_widget.Virtual_list.For_testing.decode_props_exn payload in
     check (props.total_count = 50_000) "virtual total count";
     check (props.first_index = 100) "virtual first index";
     check (props.overscan = 4) "virtual overscan"
   | _ -> fail "virtual list props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = Ui.Native_widget.Virtual_list.kind_id
       ; version = 1
       ; event_id = Ui.Native_widget.Virtual_list.visible_range_event_id
       ; payload =
           Ui.Native_widget.Virtual_list.For_testing.encode_visible_range
             ~first_index:104
             ~last_exclusive:116
       });
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 104L) "visible first index";
    check (Int64.equal last_exclusive 116L) "visible last index"
  | None -> fail "visible range callback"
;;

let test_native_protocol_round_trip () =
  let props =
    Protocol.Wire_frame.Native_widget_props
      { kind_id = 42
      ; version = 3
      ; capabilities = 5L
      ; payload = Bytes.of_string "\000typed\255"
      }
  in
  let frame : Protocol.Wire_frame.t =
    { runtime_epoch = 7L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = 1L
            ; kind = Native_widget
            ; props
            ; event_bindings = [ { event_tag = 21; handler_id = 9L } ]
            ; parent_data = No_parent_data
            }
        ; Set_root 1L
        ]
    }
  in
  let decoded =
    let encoded =
      match Protocol.Binary_codec.encode frame with
      | Ok encoded -> encoded
      | Error error -> fail error.message
    in
    match Protocol.Binary_codec.decode encoded with
    | Ok decoded -> decoded
    | Error error -> fail error.message
  in
  check (decoded = frame) "native widget protocol round trip"
;;

let test_native_event_protocol_round_trip () =
  let event : Protocol.Inbound_event.t =
    { sequence = 1L
    ; displayed_revision = 3L
    ; node_id = 8L
    ; handler_id = 9L
    ; event_tag = Protocol.Generated_protocol.Event_tag.native_event
    ; payload =
        Native_event
          { kind_id = 42
          ; version = 3
          ; event_id = 7
          ; payload = Bytes.of_string "\000\023\255"
          }
    }
  in
  let batch = Protocol.Inbound_event.{ runtime_epoch = 4L; events = [ event ] } in
  let encoded =
    match Protocol.Event_batch_codec.encode batch with
    | Ok encoded -> encoded
    | Error error -> fail error.message
  in
  let decoded =
    match Protocol.Event_batch_codec.decode encoded with
    | Ok decoded -> decoded
    | Error error -> fail error.message
  in
  check (decoded = batch) "native event protocol round trip"
;;

let () =
  test_typed_native_widget ();
  test_virtual_list_window ();
  test_native_protocol_round_trip ();
  test_native_event_protocol_round_trip ()
;;
