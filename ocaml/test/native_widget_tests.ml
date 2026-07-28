module Ui = Bonsai_flutter_ui

let check condition message = if not condition then failwith message

let expect_invalid_argument f message =
  match f () with
  | exception Invalid_argument _ -> ()
  | exception error -> raise error
  | () -> failwith message
;;

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

let swipe_action
      ?(label = "Archive")
      ?(background = Ui.Style.Color.argb ~alpha:255 ~red:80 ~green:125 ~blue:88)
      disposition
  =
  Ui.Native_widget.Swipe_action.action
    ~label
    ~background
    ~disposition
    ~icon:(Ui.Widget.text label)
;;

let test_swipe_action_props_contract () =
  let received = ref None in
  let widget =
    Ui.Native_widget.Swipe_action.create
      ~key:(Ui.Key.string "swipe")
      ~start_action:(swipe_action Dismiss)
      ~end_action:
        (swipe_action
           ~label:"Mark unread ✓"
           ~background:(Ui.Style.Color.argb ~alpha:255 ~red:67 ~green:95 ~blue:138)
           Rebound)
      ~content:(Ui.Widget.text "Message")
      ~on_commit:(fun direction -> received := Some direction)
      ()
  in
  let view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 3) "swipe action must always have three children";
  (match view.props with
   | Native_widget_props { kind_id; version; capabilities; payload } ->
     check (kind_id = 2) "swipe action kind ID";
     check (version = 1) "swipe action schema version";
     check (Int64.equal capabilities 7L) "swipe action capabilities";
     check (Char.code (Bytes.get payload 0) = 3) "swipe action enabled flags";
     check (Char.code (Bytes.get payload 1) = 0) "dismiss disposition encoding";
     check (Char.code (Bytes.get payload 2) = 1) "rebound disposition encoding";
     check (Char.code (Bytes.get payload 3) = 0) "reserved byte";
     check
       (Int32.equal (Bytes.get_int32_le payload 4) 0xff507d58l)
       "start background encoding";
     check
       (Int32.equal (Bytes.get_int32_le payload 8) 0xff435f8al)
       "end background encoding";
     let start_length = Int32.to_int (Bytes.get_int32_le payload 12) in
     let end_length = Int32.to_int (Bytes.get_int32_le payload 16) in
     check (start_length = String.length "Archive") "start label byte length";
     check (end_length = String.length "Mark unread ✓") "UTF-8 label byte length";
     check
       (Bytes.length payload = 20 + start_length + end_length)
       "swipe action exact payload length";
     check
       (String.equal (Bytes.sub_string payload 20 start_length) "Archive")
       "start label payload";
     check
       (String.equal
          (Bytes.sub_string payload (20 + start_length) end_length)
          "Mark unread ✓")
       "end label payload"
   | _ -> failwith "swipe action native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = 2; version = 1; event_id = 1; payload = Bytes.of_string "\000" });
  check
    (!received = Some Ui.Native_widget.Swipe_action.Start_to_end)
    "start-to-end commit decoding";
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = 2; version = 1; event_id = 1; payload = Bytes.of_string "\001" });
  check
    (!received = Some Ui.Native_widget.Swipe_action.End_to_start)
    "end-to-start commit decoding"
;;

let test_swipe_action_omitted_direction_and_validation () =
  let widget =
    Ui.Native_widget.Swipe_action.create
      ~start_action:(swipe_action Dismiss)
      ~content:(Ui.Widget.text "Message")
      ~on_commit:(fun _ -> ())
      ()
  in
  let view = Ui.Widget.Private.view widget in
  (match view.props with
   | Native_widget_props { payload; _ } ->
     check (Char.code (Bytes.get payload 0) = 1) "omitted end direction flag"
   | _ -> failwith "swipe action native props");
  check
    (Ui.Widget.Private.Kind.equal
       (Ui.Widget.Private.view view.children.(2).widget).kind
       Empty)
    "omitted end action must use an empty icon child";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Swipe_action.create
            ~content:(Ui.Widget.empty ())
            ~on_commit:(fun _ -> ())
            ()))
    "swipe action accepted no actions";
  expect_invalid_argument
    (fun () -> ignore (swipe_action ~label:"" Dismiss))
    "swipe action accepted an empty enabled label"
;;

let test_swipe_action_event_filtering () =
  let received = ref [] in
  let widget =
    Ui.Native_widget.Swipe_action.create
      ~start_action:(swipe_action Dismiss)
      ~content:(Ui.Widget.empty ())
      ~on_commit:(fun direction -> received := direction :: !received)
      ()
  in
  let binding = (Ui.Widget.Private.view widget).event_bindings.(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke 99 1 1 (Bytes.of_string "\000");
  invoke 2 2 1 (Bytes.of_string "\000");
  invoke 2 1 2 (Bytes.of_string "\000");
  invoke 2 1 1 Bytes.empty;
  invoke 2 1 1 (Bytes.of_string "\002");
  check (!received = []) "malformed swipe native event was not ignored";
  invoke 2 1 1 (Bytes.of_string "\000");
  check
    (!received = [ Ui.Native_widget.Swipe_action.Start_to_end ])
    "valid swipe event was filtered"
;;

let () =
  test_typed_native_widget ();
  test_virtual_list_window ();
  test_swipe_action_props_contract ();
  test_swipe_action_omitted_direction_and_validation ();
  test_swipe_action_event_filtering ()
;;
