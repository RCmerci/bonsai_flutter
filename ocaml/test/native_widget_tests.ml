module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

let native_kind_id = ID.Native_widget.Kind_id.of_int
let native_event_id = ID.Native_widget.Event_id.of_int
let check condition message = if not condition then failwith message

let expect_invalid_argument f message =
  match f () with
  | exception Invalid_argument _ -> ()
  | exception error -> raise error
  | () -> failwith message
;;

let widget_of_vertical_viewport viewport =
  viewport
  |> Ui.Widget.Viewport.Vertical.with_height ~height:240.
  |> Ui.Widget.For_testing.children
  |> fun children -> children.(0)
;;

let virtual_range_handler callback =
  Ui.Event.Handler.create (fun payload ->
    Option.iter callback (Ui.Native_widget.Virtual_list.visible_range_of_payload payload))
;;

let sparse_range_handler callback =
  Ui.Event.Handler.create (fun payload ->
    Option.iter
      callback
      (Ui.Native_widget.Sparse_extent_list.visible_range_of_payload payload))
;;

type dial_event = Changed of int

let dial_extension =
  Ui.Native_widget.Extension.create
    ~kind_id:(native_kind_id 42)
    ~version:3
    ~capabilities:[ Ui.Native_widget.Capability.Stateful ]
    ~encode_props:(fun value -> Bytes.of_string (string_of_int value))
    ~decode_event:(fun ~event_id payload ->
      if ID.Native_widget.Event_id.equal event_id (native_event_id 7)
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
     check (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 42)) "native kind ID";
     check (version = 3) "native version";
     check (Int64.equal capabilities 1L) "native capabilities";
     check (Bytes.equal payload (Bytes.of_string "17")) "native props payload"
   | _ -> failwith "native widget props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 42
       ; version = 3
       ; event_id = native_event_id 7
       ; payload = Bytes.of_string "23"
       });
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
    Ui.Native_widget.Virtual_list.vertical
      ~key:(Ui.Key.string "large-list")
      ~total_count:50_000
      ~first_index:100
      ~item_extent:48.
      ~overscan:4
      ~items
      ~on_visible_range:(virtual_range_handler (fun range -> received := Some range))
      ()
    |> widget_of_vertical_viewport
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

let test_virtual_list_handler_path_and_payload_filtering () =
  let received = ref None in
  let handler =
    Ui.Event.Handler.create ~name:"virtual-range" (fun payload ->
      received := Ui.Native_widget.Virtual_list.visible_range_of_payload payload)
  in
  let widget =
    Ui.Native_widget.Virtual_list.vertical
      ~total_count:40
      ~first_index:8
      ~item_extent:88.
      ~overscan:4
      ~items:(List.init 24 (fun index -> Ui.Widget.text (string_of_int index)))
      ~on_visible_range:handler
      ()
    |> widget_of_vertical_viewport
  in
  let binding = (Ui.Widget.Private.view widget).event_bindings.(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  let valid =
    Ui.Native_widget.Virtual_list.For_testing.encode_visible_range
      ~first_index:12
      ~last_exclusive:20
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) valid;
  invoke Ui.Native_widget.Virtual_list.kind_id 2 (native_event_id 1) valid;
  invoke Ui.Native_widget.Virtual_list.kind_id 1 (native_event_id 2) valid;
  invoke Ui.Native_widget.Virtual_list.kind_id 1 (native_event_id 1) Bytes.empty;
  check (!received = None) "malformed virtual-list event was accepted";
  invoke Ui.Native_widget.Virtual_list.kind_id 1 (native_event_id 1) valid;
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 12L) "handler visible first index";
    check (Int64.equal last_exclusive 20L) "handler visible last index"
  | None -> failwith "valid virtual-list handler event was filtered"
;;

let sparse_extent index extent : Ui.Native_widget.Sparse_extent_list.extent_override =
  { index; extent }
;;

let test_sparse_extent_list_contract () =
  let received = ref None in
  let items =
    List.init 6 (fun index ->
      Ui.Widget.text
        ~key:(Ui.Key.string (string_of_int (40 + index)))
        (string_of_int (40 + index)))
  in
  let widget =
    Ui.Native_widget.Sparse_extent_list.vertical
      ~key:(Ui.Key.string "sparse-list")
      ~total_count:50_000
      ~first_index:40
      ~default_item_extent:48.
      ~extent_overrides:[ sparse_extent 3 120.; sparse_extent 42 312. ]
      ~overscan:5
      ~items
      ~on_visible_range:(sparse_range_handler (fun range -> received := Some range))
      ()
    |> widget_of_vertical_viewport
  in
  let view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 6) "sparse list mounted outside its supplied window";
  (match view.props with
   | Native_widget_props { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 4) "sparse list kind ID";
     check (version = 1) "sparse list schema version";
     check (Int64.equal capabilities 23L) "sparse list capabilities";
     check (Bytes.length payload = 68) "sparse list exact payload length";
     let props =
       Ui.Native_widget.Sparse_extent_list.For_testing.decode_props_exn payload
     in
     check (props.total_count = 50_000) "sparse total count";
     check (props.first_index = 40) "sparse first index";
     check (Float.equal props.default_item_extent 48.) "sparse default extent";
     check (props.overscan = 5) "sparse overscan";
     check (props.axis = Ui.Layout.Axis.Vertical) "sparse default axis";
     check
       (props.extent_overrides = [ sparse_extent 3 120.; sparse_extent 42 312. ])
       "sparse overrides did not round trip"
   | _ -> failwith "sparse list native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 4
       ; version = 1
       ; event_id = native_event_id 1
       ; payload =
           Ui.Native_widget.Sparse_extent_list.For_testing.encode_visible_range
             ~first_index:41
             ~last_exclusive:44
       });
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 41L) "sparse visible first index";
    check (Int64.equal last_exclusive 44L) "sparse visible last index"
  | None -> failwith "sparse visible range callback"
;;

let test_sparse_extent_list_transition_contract () =
  let transition =
    Ui.Native_widget.Sparse_extent_list.Transition.create
      ~expand_duration_ms:240
      ~collapse_duration_ms:190
      ~expand_curve:Ease_out_cubic
      ~collapse_curve:Ease_in_out_cubic
      ()
  in
  let widget =
    Ui.Native_widget.Sparse_extent_list.vertical
      ~total_count:20
      ~first_index:4
      ~default_item_extent:88.
      ~extent_overrides:[ sparse_extent 6 320. ]
      ~overscan:4
      ~transition
      ~items:[ Ui.Widget.empty () ]
      ~on_visible_range:(sparse_range_handler (fun _ -> ()))
      ()
    |> widget_of_vertical_viewport
  in
  match (Ui.Widget.Private.view widget).props with
  | Native_widget_props { kind_id; version; payload; _ } ->
    check (kind_id = native_kind_id 4) "animated sparse list kind ID";
    check (version = 2) "animated sparse list schema version";
    check (Bytes.length payload = 64) "animated sparse list exact payload length";
    let props =
      Ui.Native_widget.Sparse_extent_list.For_testing.decode_props_exn payload
    in
    (match props.transition with
     | None -> failwith "animated sparse list omitted transition props"
     | Some decoded ->
       check decoded.enabled "sparse transition enabled";
       check (decoded.expand_duration_ms = 240) "sparse expand duration";
       check (decoded.collapse_duration_ms = 190) "sparse collapse duration";
       check (decoded.expand_curve = Ease_out_cubic) "sparse expand curve";
       check (decoded.collapse_curve = Ease_in_out_cubic) "sparse collapse curve")
  | _ -> failwith "animated sparse list native props"
;;

let test_morphing_surface_contract () =
  let widget =
    Ui.Native_widget.Morphing_surface.create
      ~expanded:true
      ~compact_content:(Ui.Widget.text "Compact")
      ~expanded_content:(Ui.Widget.text "Expanded")
      ()
  in
  let view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 2) "morphing surface child slots";
  match view.props with
  | Native_widget_props { kind_id; version; capabilities; payload } ->
    check (kind_id = native_kind_id 5) "morphing surface kind ID";
    check (version = 1) "morphing surface version";
    check (Int64.equal capabilities 4L) "morphing surface capabilities";
    let props = Ui.Native_widget.Morphing_surface.For_testing.decode_props_exn payload in
    check props.expanded "morphing surface expanded state"
  | _ -> failwith "morphing surface native props"
;;

let test_sparse_extent_list_validation () =
  let create
        ?(total_count = 10)
        ?(first_index = 0)
        ?(default_item_extent = 48.)
        ?(extent_overrides = [])
        ?(overscan = 2)
        ?(items = [])
        ()
    =
    Ui.Native_widget.Sparse_extent_list.vertical
      ~total_count
      ~first_index
      ~default_item_extent
      ~extent_overrides
      ~overscan
      ~items
      ~on_visible_range:(sparse_range_handler (fun _ -> ()))
      ()
  in
  List.iter
    (fun (build, message) -> expect_invalid_argument build message)
    [ ( (fun () -> ignore (create ~total_count:(-1) ()))
      , "sparse list accepted a negative total" )
    ; ( (fun () -> ignore (create ~first_index:11 ()))
      , "sparse list accepted an invalid first index" )
    ; ( (fun () -> ignore (create ~default_item_extent:Float.nan ()))
      , "sparse list accepted a non-finite default extent" )
    ; ( (fun () -> ignore (create ~default_item_extent:0. ()))
      , "sparse list accepted a non-positive default extent" )
    ; ( (fun () -> ignore (create ~overscan:(-1) ()))
      , "sparse list accepted negative overscan" )
    ; ( (fun () -> ignore (create ~extent_overrides:[ sparse_extent (-1) 80. ] ()))
      , "sparse list accepted a negative override index" )
    ; ( (fun () -> ignore (create ~extent_overrides:[ sparse_extent 10 80. ] ()))
      , "sparse list accepted an out-of-bounds override index" )
    ; ( (fun () ->
          ignore
            (create ~extent_overrides:[ sparse_extent 4 80.; sparse_extent 3 90. ] ()))
      , "sparse list accepted unsorted overrides" )
    ; ( (fun () ->
          ignore
            (create ~extent_overrides:[ sparse_extent 3 80.; sparse_extent 3 90. ] ()))
      , "sparse list accepted duplicate overrides" )
    ; ( (fun () -> ignore (create ~extent_overrides:[ sparse_extent 3 Float.infinity ] ()))
      , "sparse list accepted a non-finite override extent" )
    ; ( (fun () -> ignore (create ~extent_overrides:[ sparse_extent 3 0. ] ()))
      , "sparse list accepted a non-positive override extent" )
    ; ( (fun () ->
          ignore
            (create
               ~total_count:2
               ~first_index:1
               ~items:[ Ui.Widget.empty (); Ui.Widget.empty () ]
               ()))
      , "sparse list accepted a child window beyond total_count" )
    ];
  let valid =
    Ui.Native_widget.Sparse_extent_list.vertical
      ~total_count:8
      ~first_index:2
      ~default_item_extent:48.
      ~extent_overrides:[ sparse_extent 4 96. ]
      ~items:[ Ui.Widget.empty () ]
      ~on_visible_range:(sparse_range_handler (fun _ -> ()))
      ()
    |> widget_of_vertical_viewport
  in
  let payload =
    match (Ui.Widget.Private.view valid).props with
    | Native_widget_props { payload; _ } -> payload
    | _ -> failwith "sparse list native props"
  in
  let reject payload message =
    expect_invalid_argument
      (fun () ->
         ignore (Ui.Native_widget.Sparse_extent_list.For_testing.decode_props_exn payload))
      message
  in
  reject
    (Bytes.sub payload 0 (Bytes.length payload - 1))
    "truncated sparse payload accepted";
  let trailing = Bytes.cat payload (Bytes.of_string "\000") in
  reject trailing "trailing sparse payload byte accepted";
  let bad_reserved = Bytes.copy payload in
  Bytes.set bad_reserved 29 '\001';
  reject bad_reserved "nonzero sparse reserved byte accepted";
  let bad_axis = Bytes.copy payload in
  Bytes.set bad_axis 28 '\002';
  reject bad_axis "invalid sparse axis accepted";
  let bad_count = Bytes.copy payload in
  Bytes.set_int32_le bad_count 32 2l;
  reject bad_count "sparse override count/length mismatch accepted"
;;

let test_sparse_extent_handler_path_and_payload_filtering () =
  let received = ref None in
  let handler =
    Ui.Event.Handler.create ~name:"sparse-range" (fun payload ->
      received := Ui.Native_widget.Sparse_extent_list.visible_range_of_payload payload)
  in
  let widget =
    Ui.Native_widget.Sparse_extent_list.vertical
      ~total_count:40
      ~first_index:8
      ~default_item_extent:88.
      ~extent_overrides:[ sparse_extent 12 320. ]
      ~items:(List.init 24 (fun index -> Ui.Widget.text (string_of_int index)))
      ~on_visible_range:handler
      ()
    |> widget_of_vertical_viewport
  in
  let binding = (Ui.Widget.Private.view widget).event_bindings.(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  let valid =
    Ui.Native_widget.Sparse_extent_list.For_testing.encode_visible_range
      ~first_index:12
      ~last_exclusive:20
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) valid;
  invoke (native_kind_id 4) 3 (native_event_id 1) valid;
  invoke (native_kind_id 4) 1 (native_event_id 2) valid;
  invoke (native_kind_id 4) 1 (native_event_id 1) Bytes.empty;
  check (!received = None) "malformed sparse-list event was accepted";
  invoke (native_kind_id 4) 1 (native_event_id 1) valid;
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 12L) "sparse handler visible first index";
    check (Int64.equal last_exclusive 20L) "sparse handler visible last index"
  | None -> failwith "valid sparse-list handler event was filtered"
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
     check
       (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 2))
       "swipe action kind ID";
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
       { kind_id = native_kind_id 2
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Bytes.of_string "\000"
       });
  check
    (!received = Some Ui.Native_widget.Swipe_action.Start_to_end)
    "start-to-end commit decoding";
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 2
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Bytes.of_string "\001"
       });
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
  invoke (native_kind_id 99) 1 (native_event_id 1) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 2 (native_event_id 1) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 1 (native_event_id 2) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 1 (native_event_id 1) Bytes.empty;
  invoke (native_kind_id 2) 1 (native_event_id 1) (Bytes.of_string "\002");
  check (!received = []) "malformed swipe native event was not ignored";
  invoke (native_kind_id 2) 1 (native_event_id 1) (Bytes.of_string "\000");
  check
    (!received = [ Ui.Native_widget.Swipe_action.Start_to_end ])
    "valid swipe event was filtered"
;;

let test_navigation_shell_contract_and_events () =
  let received = ref None in
  let widget =
    Ui.Native_widget.Navigation_shell.create
      ~key:(Ui.Key.string "shell")
      ~selected_index:1
      ~drawer_open:true
      ~drawer_enabled:false
      ~bodies:
        [ Ui.Widget.Body.static (Ui.Widget.text "Primary")
        ; Ui.Widget.Body.static (Ui.Widget.text "Secondary")
        ]
      ~drawer:(Ui.Widget.text "Drawer")
      ~bottom_navigation:(Ui.Widget.text "Bottom")
      ~on_drawer_state_changed:(fun state -> received := Some state)
      ()
  in
  let view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 4) "navigation shell child shape";
  (match view.props with
   | Native_widget_props { kind_id; version; capabilities; payload } ->
     check
       (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 3))
       "navigation shell kind ID";
     check (version = 1) "navigation shell schema version";
     check (Int64.equal capabilities 7L) "navigation shell capabilities";
     let props = Ui.Native_widget.Navigation_shell.For_testing.decode_props_exn payload in
     check (props.destination_count = 2) "navigation destination count";
     check (props.selected_index = 1) "navigation selected index";
     check props.drawer_open "navigation requested drawer state";
     check (not props.drawer_enabled) "navigation drawer enabled state"
   | _ -> failwith "navigation shell native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 3
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Ui.Native_widget.Navigation_shell.For_testing.encode_drawer_state Open
       });
  check
    (!received = Some Ui.Native_widget.Navigation_shell.Open)
    "navigation shell open event";
  received := None;
  List.iter
    (fun (kind_id, version, event_id, payload) ->
       Ui.Event.Handler.Private.invoke
         binding.handler
         (Native_event { kind_id; version; event_id; payload }))
    [ native_kind_id 99, 1, native_event_id 1, Bytes.of_string "\000"
    ; native_kind_id 3, 2, native_event_id 1, Bytes.of_string "\000"
    ; native_kind_id 3, 1, native_event_id 2, Bytes.of_string "\000"
    ; native_kind_id 3, 1, native_event_id 1, Bytes.empty
    ; native_kind_id 3, 1, native_event_id 1, Bytes.of_string "\002"
    ];
  check (!received = None) "malformed navigation-shell event was accepted";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Navigation_shell.create
            ~selected_index:0
            ~drawer_open:false
            ~drawer_enabled:true
            ~bodies:[]
            ~drawer:(Ui.Widget.empty ())
            ~bottom_navigation:(Ui.Widget.empty ())
            ~on_drawer_state_changed:(fun _ -> ())
            ()))
    "navigation shell accepted no destination bodies";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Navigation_shell.create
            ~selected_index:2
            ~drawer_open:false
            ~drawer_enabled:true
            ~bodies:
              [ Ui.Widget.Body.static (Ui.Widget.empty ())
              ; Ui.Widget.Body.static (Ui.Widget.empty ())
              ]
            ~drawer:(Ui.Widget.empty ())
            ~bottom_navigation:(Ui.Widget.empty ())
            ~on_drawer_state_changed:(fun _ -> ())
            ()))
    "navigation shell accepted an invalid selected index"
;;

let () =
  test_typed_native_widget ();
  test_virtual_list_window ();
  test_virtual_list_handler_path_and_payload_filtering ();
  test_sparse_extent_list_contract ();
  test_sparse_extent_list_transition_contract ();
  test_morphing_surface_contract ();
  test_sparse_extent_list_validation ();
  test_sparse_extent_handler_path_and_payload_filtering ();
  test_swipe_action_props_contract ();
  test_swipe_action_omitted_direction_and_validation ();
  test_swipe_action_event_filtering ();
  test_navigation_shell_contract_and_events ()
;;
