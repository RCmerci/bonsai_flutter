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


let sliver_range_handler callback =
  Ui.Event.Handler.create (fun payload ->
    Option.iter callback (Ui.Widget.Sliver.visible_range_of_payload payload))
;;

let sliver_override index extent : Ui.Widget.Sparse_extent_override.t =
  { index; extent }
;;

let scroll_view_child viewport =
  let Av view = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  view.children.(0).widget
;;

let test_sliver_box_and_scroll_view () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.box (Ui.Widget.text "Hi") ]
      ()
  in
  let Av sv = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag sv.node)
       Ui.Widget.Private.K_scroll_view)
    "scroll view kind";
  check (Array.length sv.children = 1) "scroll view has one sliver child";
  let Av bv = Ui.Widget.Private.view sv.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag bv.node)
       Ui.Widget.Private.K_sliver_box)
    "sliver box kind";
  check (Array.length bv.children = 1) "sliver box has one child"
;;

let test_sliver_fixed_extent_contract () =
  let received = ref None in
  let items = List.init 20 (fun i -> Ui.Widget.text (string_of_int (100 + i))) in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.fixed_extent
          ~key:(Ui.Key.string "large-list")
          ~total_count:50_000
          ~first_index:100
          ~item_extent:48.
          ~overscan:4
          ~items
          ~on_visible_range:(sliver_range_handler (fun range -> received := Some range))
          ()
      ]
      ()
  in
  let Av fv = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length fv.children = 20) "only the supplied window is mounted";
  (match fv.node with
   | Ui.Widget.Private.Sliver_fixed_extent { total_count; first_index; item_extent; overscan } ->
     check (total_count = 50_000) "fixed total count";
     check (first_index = 100) "fixed first index";
     check (Float.equal item_extent 48.) "fixed item extent";
     check (overscan = 4) "fixed overscan"
   | _ -> failwith "fixed extent node");
  let binding = fv.event_bindings.(0) in
  check
    (Ui.Event.Tag.equal binding.tag Ui.Event.Tag.Visible_range_changed)
    "fixed extent visible range binding";
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Visible_range { first_index = 104L; last_exclusive = 116L });
  (match !received with
   | Some { Ui.Event.Payload.first_index; last_exclusive } ->
     check (Int64.equal first_index 104L) "visible first index";
     check (Int64.equal last_exclusive 116L) "visible last index"
   | None -> failwith "visible range callback")
;;

let test_sliver_varied_extent_contract () =
  let received = ref None in
  let items = List.init 6 (fun i -> Ui.Widget.text (string_of_int (40 + i))) in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.varied_extent
          ~key:(Ui.Key.string "sparse-list")
          ~total_count:50_000
          ~first_index:40
          ~default_item_extent:48.
          ~extent_overrides:[ sliver_override 3 120.; sliver_override 42 312. ]
          ~overscan:5
          ~items
          ~on_visible_range:(sliver_range_handler (fun range -> received := Some range))
          ()
      ]
      ()
  in
  let Av vv = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length vv.children = 6) "varied extent mounted window";
  (match vv.node with
   | Ui.Widget.Private.Sliver_varied_extent
       { total_count; first_index; default_item_extent; extent_overrides; overscan; transition } ->
     check (total_count = 50_000) "varied total count";
     check (first_index = 40) "varied first index";
     check (Float.equal default_item_extent 48.) "varied default extent";
     check (overscan = 5) "varied overscan";
     check (transition = None) "varied default transition";
     check
       (extent_overrides = [ sliver_override 3 120.; sliver_override 42 312. ])
       "varied overrides round trip"
   | _ -> failwith "varied extent node");
  let binding = vv.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Visible_range { first_index = 41L; last_exclusive = 44L });
  (match !received with
   | Some { Ui.Event.Payload.first_index; last_exclusive } ->
     check (Int64.equal first_index 41L) "varied visible first index";
     check (Int64.equal last_exclusive 44L) "varied visible last index"
   | None -> failwith "varied visible range callback")
;;

let test_sliver_varied_extent_transition () =
  let transition =
    Ui.Widget.Sparse_extent_transition.create
      ~expand_duration_ms:240
      ~collapse_duration_ms:190
      ~expand_curve:Ease_out_cubic
      ~collapse_curve:Ease_in_out_cubic
      ()
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.varied_extent
          ~total_count:20
          ~first_index:4
          ~default_item_extent:88.
          ~extent_overrides:[ sliver_override 6 320. ]
          ~overscan:4
          ~transition
          ~items:[ Ui.Widget.empty () ]
          ~on_visible_range:(sliver_range_handler (fun _ -> ()))
          ()
      ]
      ()
  in
  let Av vv = Ui.Widget.Private.view (scroll_view_child viewport) in
  (match vv.node with
   | Ui.Widget.Private.Sliver_varied_extent { transition = Some decoded; _ } ->
     let open Ui.Widget.Sparse_extent_transition in
     check decoded.enabled "transition enabled";
     check (decoded.expand_duration_ms = 240) "expand duration";
     check (decoded.collapse_duration_ms = 190) "collapse duration";
     check (decoded.expand_curve = Ease_out_cubic) "expand curve";
     check (decoded.collapse_curve = Ease_in_out_cubic) "collapse curve"
   | _ -> failwith "varied extent transition node")
;;

let test_sliver_varied_extent_validation () =
  let create
        ?(total_count = 10)
        ?(first_index = 0)
        ?(default_item_extent = 48.)
        ?(extent_overrides = [])
        ?(overscan = 2)
        ?(items = [])
        ()
    =
    ignore
      (Ui.Widget.Scroll_view.vertical
         ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
         [ Ui.Widget.Sliver.varied_extent
             ~total_count
             ~first_index
             ~default_item_extent
             ~extent_overrides
             ~overscan
             ~items
             ~on_visible_range:(sliver_range_handler (fun _ -> ()))
             ()
         ]
         ())
  in
  List.iter
    (fun (build, message) -> expect_invalid_argument build message)
    [ ( (fun () -> create ~total_count:(-1) ())
      , "sliver accepted a negative total" )
    ; ( (fun () -> create ~first_index:11 ())
      , "sliver accepted an invalid first index" )
    ; ( (fun () -> create ~default_item_extent:Float.nan ())
      , "sliver accepted a non-finite default extent" )
    ; ( (fun () -> create ~default_item_extent:0. ())
      , "sliver accepted a non-positive default extent" )
    ; ( (fun () -> create ~overscan:(-1) ())
      , "sliver accepted negative overscan" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override (-1) 80. ] ())
      , "sliver accepted a negative override index" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 10 80. ] ())
      , "sliver accepted an out-of-bounds override index" )
    ; ( (fun () ->
          create ~extent_overrides:[ sliver_override 4 80.; sliver_override 3 90. ] ())
      , "sliver accepted unsorted overrides" )
    ; ( (fun () ->
          create ~extent_overrides:[ sliver_override 3 80.; sliver_override 3 90. ] ())
      , "sliver accepted duplicate overrides" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 3 Float.infinity ] ())
      , "sliver accepted a non-finite override extent" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 3 0. ] ())
      , "sliver accepted a non-positive override extent" )
    ; ( (fun () ->
          create ~total_count:2 ~first_index:1 ~items:[ Ui.Widget.empty (); Ui.Widget.empty () ] ())
      , "sliver accepted a child window beyond total_count" )
    ]
;;

let test_sliver_fill_and_padding () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.padding
          ~insets:(Ui.Layout.Edge_insets.all 8.)
          (Ui.Widget.Sliver.fill ~flex:2 (Ui.Widget.text "Fill"))
      ]
      ()
  in
  let Av sv = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  let Av pad = Ui.Widget.Private.view sv.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag pad.node)
       Ui.Widget.Private.K_sliver_padding)
    "sliver padding kind";
  let Av fill = Ui.Widget.Private.view pad.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag fill.node)
       Ui.Widget.Private.K_sliver_fill)
    "sliver fill kind";
  (match fill.node with
   | Ui.Widget.Private.Sliver_fill { flex } -> check (flex = 2) "sliver fill flex"
   | _ -> failwith "sliver fill node");
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Widget.Scroll_view.vertical
            ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
            [ Ui.Widget.Sliver.fill ~flex:0 (Ui.Widget.text "Bad") ]
            ()))
    "sliver accepted non-positive fill flex"
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
  let Av view = Ui.Widget.Private.view widget in
  check (Ui.Widget.Private.kind_tag_equal (Ui.Widget.Private.node_kind_tag view.node) Ui.Widget.Private.K_native_widget) "native widget kind";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
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
let test_morphing_surface_contract () =
  let widget =
    Ui.Native_widget.Morphing_surface.create
      ~expanded:true
      ~compact_content:(Ui.Widget.text "Compact")
      ~expanded_content:(Ui.Widget.text "Expanded")
      ()
  in
  let Av view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 2) "morphing surface child slots";
  match view.node with
  | Native_widget { kind_id; version; capabilities; payload } ->
    check (kind_id = native_kind_id 5) "morphing surface kind ID";
    check (version = 1) "morphing surface version";
    check (Int64.equal capabilities 4L) "morphing surface capabilities";
    let props = Ui.Native_widget.Morphing_surface.For_testing.decode_props_exn payload in
    check props.expanded "morphing surface expanded state"
  | _ -> failwith "morphing surface native props"
;;
let swipe_action
      ?(label = "Archive")
      ?(background = Ui.Style.Color.argb ~alpha:255 ~red:80 ~green:125 ~blue:88)
      ?border_radius
      disposition
  =
  Ui.Native_widget.Swipe_action.action
    ~label
    ~background
    ?border_radius
    ~disposition
    ~icon:(Ui.Widget.text label)
    ()
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
           ~border_radius:12.
           Rebound)
      ~clip_border_radius:18.
      ~content:(Ui.Widget.text "Message")
      ~on_commit:(fun direction -> received := Some direction)
      ()
  in
  let Av view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 3) "swipe action must always have three children";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check
       (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 2))
       "swipe action kind ID";
     check (version = 2) "swipe action schema version";
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
     check
       (Float.equal (Int64.float_of_bits (Bytes.get_int64_le payload 12)) 999.)
       "default start action border radius encoding";
     check
       (Float.equal (Int64.float_of_bits (Bytes.get_int64_le payload 20)) 12.)
       "custom end action border radius encoding";
     check
       (Float.equal (Int64.float_of_bits (Bytes.get_int64_le payload 28)) 18.)
       "host clip border radius encoding";
     let start_length = Int32.to_int (Bytes.get_int32_le payload 36) in
     let end_length = Int32.to_int (Bytes.get_int32_le payload 40) in
     check (start_length = String.length "Archive") "start label byte length";
     check (end_length = String.length "Mark unread ✓") "UTF-8 label byte length";
     check
       (Bytes.length payload = 44 + start_length + end_length)
       "swipe action exact payload length";
     check
       (String.equal (Bytes.sub_string payload 44 start_length) "Archive")
       "start label payload";
     check
       (String.equal
          (Bytes.sub_string payload (44 + start_length) end_length)
          "Mark unread ✓")
       "end label payload"
   | _ -> failwith "swipe action native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 2
       ; version = 2
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
       ; version = 2
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
  let Av view = Ui.Widget.Private.view widget in
  (match view.node with
   | Native_widget { payload; _ } ->
     check (Char.code (Bytes.get payload 0) = 1) "omitted end direction flag";
     check
       (Float.equal (Int64.float_of_bits (Bytes.get_int64_le payload 20)) 999.)
       "omitted action keeps the encoded default border radius";
     check
       (Float.equal (Int64.float_of_bits (Bytes.get_int64_le payload 28)) 0.)
       "host clip border radius defaults to square"
   | _ -> failwith "swipe action native props");
  check
    (Ui.Widget.Private.kind_tag_equal
       (let Av v = Ui.Widget.Private.view view.children.(2).widget in Ui.Widget.Private.node_kind_tag v.node)
       K_empty)
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
    "swipe action accepted an empty enabled label";
  List.iter
    (fun border_radius ->
       expect_invalid_argument
         (fun () -> ignore (swipe_action ~border_radius Dismiss))
         "swipe action accepted an invalid action border radius";
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Swipe_action.create
                 ~start_action:(swipe_action Dismiss)
                 ~clip_border_radius:border_radius
                 ~content:(Ui.Widget.empty ())
                 ~on_commit:(fun _ -> ())
                 ()))
         "swipe action accepted an invalid host clip border radius")
    [ -1.; Float.nan; Float.infinity ]
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
  let binding = (let Av v = Ui.Widget.Private.view widget in v.event_bindings).(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 1 (native_event_id 1) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 2 (native_event_id 2) (Bytes.of_string "\000");
  invoke (native_kind_id 2) 2 (native_event_id 1) Bytes.empty;
  invoke (native_kind_id 2) 2 (native_event_id 1) (Bytes.of_string "\002");
  check (!received = []) "malformed swipe native event was not ignored";
  invoke (native_kind_id 2) 2 (native_event_id 1) (Bytes.of_string "\000");
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
  let Av view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 4) "navigation shell child shape";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
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

let message_composer_button
      ?(position = Ui.Native_widget.Message_composer.Trailing)
      ?(visibility = Ui.Native_widget.Message_composer.Always)
      ?(style = Ui.Native_widget.Message_composer.Plain)
      ?(enabled = true)
      ~id
      ~tooltip
      label
  =
  Ui.Native_widget.Message_composer.button
    ~id
    ~tooltip
    ~position
    ~visibility
    ~style
    ~enabled
    ~child:(Ui.Widget.text label)
    ()
;;

let test_message_composer_contract_and_custom_buttons () =
  let events = ref [] in
  let buttons =
    [ message_composer_button
        ~id:10
        ~tooltip:"Add attachment"
        ~position:Leading
        "attachment"
    ; message_composer_button
        ~id:20
        ~tooltip:"Start voice input"
        ~visibility:When_empty
        ~style:Filled
        "voice"
    ; message_composer_button
        ~id:21
        ~tooltip:"Send message"
        ~visibility:When_non_empty
        ~style:Filled
        "send"
    ]
  in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~key:(Ui.Key.string "composer")
      ~autofocus:true
      ~max_lines:7
      ~hint_text:"Ask anything \226\156\168"
      ~buttons
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let Av view = Ui.Widget.Private.view widget in
  check (Array.length view.children = 3) "message composer custom button child count";
  Array.iteri
    (fun index expected ->
       let Av child = Ui.Widget.Private.view view.children.(index).widget in
       match child.node with
       | Ui.Widget.Private.Text { value; _ } ->
         check (String.equal value expected) "message composer custom button order"
       | _ -> failwith "message composer button child")
    [| "attachment"; "voice"; "send" |];
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 6) "message composer kind ID";
     check (version = 1) "message composer schema version";
     check (Int64.equal capabilities 5L) "message composer capabilities";
     let props = Ui.Native_widget.Message_composer.For_testing.decode_props_exn payload in
     check props.enabled "message composer enabled default";
     check props.autofocus "message composer autofocus";
     check (props.max_lines = 7) "message composer max lines";
     check
       (String.equal props.hint_text "Ask anything \226\156\168")
       "message composer UTF-8 hint";
     check (List.length props.buttons = 3) "message composer button metadata count";
     let attachment = List.nth props.buttons 0 in
     check (attachment.id = 10) "message composer button ID";
     check (attachment.position = Leading) "message composer leading button";
     let voice = List.nth props.buttons 1 in
     check (voice.visibility = When_empty) "message composer empty visibility";
     check (voice.style = Filled) "message composer filled style";
     let send = List.nth props.buttons 2 in
     check (send.visibility = When_non_empty) "message composer non-empty visibility"
   | _ -> failwith "message composer native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Bytes.of_string "hello \240\159\145\139"
       });
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 2
       ; payload =
           (let payload = Bytes.make 12 '\000' in
            Bytes.set_int32_le payload 0 21l;
            Bytes.blit_string "  send  " 0 payload 4 8;
            payload)
       });
  check
    (!events
     = [ Ui.Native_widget.Message_composer.Button_pressed
           { button_id = 21; text = "  send  " }
       ; Text_changed "hello \240\159\145\139"
       ])
    "message composer typed events"
;;

let test_message_composer_validation_and_event_filtering () =
  let button = message_composer_button ~id:1 ~tooltip:"One" "one" in
  List.iter
    (fun max_lines ->
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Message_composer.create
                 ~max_lines
                 ~buttons:[]
                 ~on_event:(fun _ -> ())
                 ()))
         "message composer accepted invalid max_lines")
    [ 0; -1; 0x1_0000 ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () -> ignore (message_composer_button ~id ~tooltip:"Invalid" "x"))
         "message composer accepted invalid button ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (message_composer_button ~id:2 ~tooltip:"" "empty"))
    "message composer accepted empty tooltip";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Message_composer.create
            ~buttons:[ button; button ]
            ~on_event:(fun _ -> ())
            ()))
    "message composer accepted duplicate button IDs";
  let received = ref [] in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~buttons:[ button ]
      ~on_event:(fun event -> received := event :: !received)
      ()
  in
  let binding = (let Av v = Ui.Widget.Private.view widget in v.event_bindings).(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 2 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 1 (native_event_id 9) Bytes.empty;
  invoke (native_kind_id 6) 1 (native_event_id 2) (Bytes.make 3 '\000');
  check (!received = []) "message composer malformed event was accepted";
  invoke (native_kind_id 6) 1 (native_event_id 1) (Bytes.of_string "accepted");
  check
    (!received = [ Ui.Native_widget.Message_composer.Text_changed "accepted" ])
    "message composer valid event was filtered"
;;

let () =
  test_typed_native_widget ();
  test_sliver_box_and_scroll_view ();
  test_sliver_fixed_extent_contract ();
  test_sliver_varied_extent_contract ();
  test_sliver_varied_extent_transition ();
  test_sliver_varied_extent_validation ();
  test_sliver_fill_and_padding ();
  test_morphing_surface_contract ();
  test_swipe_action_props_contract ();
  test_swipe_action_omitted_direction_and_validation ();
  test_swipe_action_event_filtering ();
  test_navigation_shell_contract_and_events ();
  test_message_composer_contract_and_custom_buttons ();
  test_message_composer_validation_and_event_filtering ()
;;
