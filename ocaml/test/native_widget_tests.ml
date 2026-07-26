module Ui = Bonsai_flutter_ui

let check condition message = if not condition then failwith message

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
   | _ -> failwith "native widget props");
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
   | _ -> failwith "virtual list props");
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
  | None -> failwith "visible range callback"
;;

let () =
  test_typed_native_widget ();
  test_virtual_list_window ()
;;
