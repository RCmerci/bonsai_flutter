open Bonsai_flutter_protocol
module ID = Bonsai_flutter_spec.Id

let epoch = ID.Runtime.Epoch.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let sequence = ID.Runtime.Event_sequence.of_int64
let node = ID.Ui.Node_id.of_int64
let handler = ID.Ui.Handler_id.of_int64
let request = ID.Host.Request_id.of_int64
let session = ID.Text_input.Session_id.of_int64
let document_revision = ID.Text_input.Document_revision.of_int64
let local_revision = ID.Text_input.Local_revision.of_int64
let animation = ID.Ui.Animation_id.of_int64
let fail format = Printf.ksprintf failwith format

let expect condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format
;;

let bytes_of_hex text =
  let digit = function
    | '0' .. '9' as value -> Char.code value - Char.code '0'
    | 'a' .. 'f' as value -> 10 + Char.code value - Char.code 'a'
    | 'A' .. 'F' as value -> 10 + Char.code value - Char.code 'A'
    | value -> fail "invalid hex digit %C" value
  in
  let compact =
    text
    |> String.to_seq
    |> Seq.filter (fun value -> not (Char.equal value ' ' || Char.equal value '\n'))
    |> String.of_seq
  in
  expect (String.length compact mod 2 = 0) "hex fixture has an odd number of digits";
  Bytes.init
    (String.length compact / 2)
    (fun index ->
       let offset = index * 2 in
       Char.chr ((digit compact.[offset] lsl 4) lor digit compact.[offset + 1]))
;;

let fixture_named name =
  let path =
    let from_root = "protocol/generated/fixtures/" ^ name in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/" ^ name
  in
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
;;

let fixture () = fixture_named "counter_full.hex"

let counter_frame =
  Wire_frame.
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Column
            ; props = Linear_props
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Create_node
            { node_id = node 2L
            ; kind = Text
            ; props =
                Text_props
                  { value = "Count: 0"
                  ; style = None
                  ; text_align = Start
                  ; max_lines = None
                  ; overflow = Clip_text
                  }
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Set_children { node_id = node 1L; children = [ node 2L ] }
        ; Set_root (node 1L)
        ]
    }
;;

let test_golden_fixture () =
  match Binary_codec.encode counter_frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok encoded -> expect (Bytes.equal encoded (fixture ())) "golden frame differs"
;;

let test_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 2L
              ; props =
                  Text_props
                    { value = "计数: 1"
                    ; style = None
                    ; text_align = Start
                    ; max_lines = None
                    ; overflow = Clip_text
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "round trip changed the incremental frame")
;;

let test_styled_text_props_round_trip () =
  let props =
    Wire_frame.Text_props
      { value = "Quarterly planning"
      ; style =
          Some
            { font_size = Some 16.
            ; font_weight = Some Semi_bold
            ; line_height = Some 1.4
            ; color = Some 0xff183758l
            }
      ; text_align = End
      ; max_lines = Some 2
      ; overflow = Ellipsis
      }
  in
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations = [ Update_props { node_id = node 2L; props } ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "styled text encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "styled text decode failed: %s" error.message
     | Ok decoded ->
       expect
         (decoded = frame)
         "styled text round trip changed style, alignment, line limit, or overflow")
;;

let test_legacy_text_props_layout () =
  match Binary_codec.decode (fixture_named "legacy_1_12_counter_full.hex") with
  | Error error -> fail "legacy text frame decode failed: %s" error.message
  | Ok decoded -> expect (decoded = counter_frame) "legacy text frame changed on decode"
;;

let test_animation_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.75
                    ; animation =
                        { id = animation 7001L; duration_ms = 250; curve = Ease_in_out }
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "animation encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "animation decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "animation props changed during round trip")
;;

let test_page_presentations_round_trip_and_incremental_updates () =
  let standard =
    Wire_frame.Page_props
      { page_key = ID.Navigation.Page_key.of_string "settings"
      ; presentation = Standard_page Fade
      ; can_pop = true
      ; restoration_id = Some (ID.Navigation.Restoration_id.of_string "settings-page")
      }
  in
  let modal ~can_pop ~barrier_dismissible ~request_focus ~transition_duration_ms =
    Wire_frame.Page_props
      { page_key = ID.Navigation.Page_key.of_string "editor"
      ; presentation =
          Modal_bottom_sheet
            { barrier_dismissible
            ; barrier_color_argb = Some (Int32.of_string "0x7f102030")
            ; barrier_label = Some "Close editor"
            ; sizing =
                Detented_sizing
                  { detents = Medium_and_large
                  ; initial_detent = Medium_detent
                  ; dismiss_on_drag = true
                  ; handle_semantics_label = "Adjust sheet height"
                  ; medium_semantics_value = "Half height"
                  ; large_semantics_value = "Full height"
                  }
            ; use_safe_area = true
            ; request_focus
            ; transition_duration_ms
            ; reverse_transition_duration_ms = 175
            }
      ; can_pop
      ; restoration_id = Some (ID.Navigation.Restoration_id.of_string "editor-page")
      }
  in
  let modal_before =
    modal
      ~can_pop:false
      ~barrier_dismissible:false
      ~request_focus:false
      ~transition_duration_ms:0
  in
  let modal_after =
    modal
      ~can_pop:true
      ~barrier_dismissible:true
      ~request_focus:true
      ~transition_duration_ms:325
  in
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 73L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props { node_id = node 30L; props = standard }
          ; Update_props { node_id = node 31L; props = modal_before }
          ; Update_props { node_id = node 31L; props = modal_after }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "page presentation encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "page presentation decode failed: %s" error.message
     | Ok decoded ->
       (match decoded.operations with
        | [ Update_props { props = Page_props standard; _ }
          ; Update_props { props = Page_props before; _ }
          ; Update_props { props = Page_props after; _ }
          ] ->
          expect
            (standard.presentation = Standard_page Fade)
            "standard presentation lost its fade transition";
          expect
            ((not before.can_pop) && after.can_pop)
            "incremental can_pop did not change";
          (match before.presentation, after.presentation with
           | Modal_bottom_sheet before, Modal_bottom_sheet after ->
             expect
               ((not before.barrier_dismissible) && after.barrier_dismissible)
               "incremental barrier policy did not change";
             expect
               ((not before.request_focus) && after.request_focus)
               "incremental focus policy did not change";
             expect
               (before.transition_duration_ms = 0
                && after.transition_duration_ms = 325
                && after.reverse_transition_duration_ms = 175)
               "incremental modal durations did not change";
             expect
               (after.barrier_color_argb = Some (Int32.of_string "0x7f102030"))
               "modal barrier color changed during round trip";
             expect
               (after.barrier_label = Some "Close editor")
               "modal barrier label changed during round trip";
             (match after.sizing with
              | Detented_sizing detents ->
                expect
                  (detents.detents = Medium_and_large
                   && detents.initial_detent = Medium_detent
                   && detents.dismiss_on_drag
                   && String.equal detents.handle_semantics_label "Adjust sheet height"
                   && String.equal detents.medium_semantics_value "Half height"
                   && String.equal detents.large_semantics_value "Full height")
                  "modal detent contract changed during round trip"
              | _ -> fail "modal sizing changed during round trip")
           | _ -> fail "modal presentation changed kind during round trip")
        | _ -> fail "page presentation operations changed during round trip"))
;;

let test_modal_bottom_sheet_rejects_unknown_wire_enums () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 73L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 30L
              ; props =
                  Page_props
                    { page_key = ID.Navigation.Page_key.of_string "modal"
                    ; presentation =
                        Modal_bottom_sheet
                          { barrier_dismissible = true
                          ; barrier_color_argb = Some (Int32.of_string "0x7f102030")
                          ; barrier_label = None
                          ; sizing =
                              Detented_sizing
                                { detents = Medium_and_large
                                ; initial_detent = Medium_detent
                                ; dismiss_on_drag = true
                                ; handle_semantics_label = "Adjust sheet height"
                                ; medium_semantics_value = "Half height"
                                ; large_semantics_value = "Full height"
                                }
                          ; use_safe_area = false
                          ; request_focus = true
                          ; transition_duration_ms = 250
                          ; reverse_transition_duration_ms = 200
                          }
                    ; can_pop = true
                    ; restoration_id = None
                    }
              }
          ]
      }
  in
  let encoded =
    match Binary_codec.encode frame with
    | Ok bytes -> bytes
    | Error error -> fail "modal enum fixture encode failed: %s" error.message
  in
  List.iter
    (fun offset ->
       let invalid = Bytes.copy encoded in
       Bytes.set invalid offset '\xff';
       match Binary_codec.decode invalid with
       | Error { code = Invalid_props; _ } -> ()
       | Error error -> fail "unexpected modal enum error: %s" error.message
       | Ok _ -> fail "unknown modal enum at offset %d unexpectedly decoded" offset)
    [ 88; 96; 107; 108 ]
;;

let test_legacy_opacity_layout () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 8L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 4L
              ; kind = Opacity
              ; props = Opacity_props { opacity = 0.5 }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Set_root (node 4L)
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "legacy opacity encode failed: %s" error.message
  | Ok encoded ->
    Bytes.set encoded 6 '\x0b';
    Bytes.set encoded 7 '\x00';
    (match Binary_codec.decode encoded with
     | Error error -> fail "legacy opacity decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "legacy opacity layout changed")
;;

let test_layout_material_and_semantics_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 9L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Padding
              ; props = Padding_props { left = 12.; top = 8.; right = 12.; bottom = 8. }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 2L
              ; kind = Center
              ; props = Center_props { width_factor = None; height_factor = Some 1.5 }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 3L
              ; kind = Scroll_view
              ; props =
                  Scroll_view_props
                    { axis = Vertical
                    ; reverse = false
                    ; primary = true
                    ; cache_extent = None
                    }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.scroll_notification
                    ; handler_id = handler 80L
                    }
                  ]
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 4L
              ; kind = Semantics
              ; props =
                  Semantics_props
                    { label = Some "Accept terms"
                    ; hint = None
                    ; value = None
                    ; role = Checkbox
                    ; enabled = Some true
                    ; selected = None
                    ; checked = Some false
                    ; focusable = None
                    ; obscured = false
                    ; live_region = false
                    ; heading_level = None
                    ; sort_key = None
                    ; actions = 0
                    }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 5L
              ; kind = Theme
              ; props =
                  Theme_props
                    { brightness = Dark; color_seed = Int32.of_string "0xff2060a0" }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 6L
              ; kind = Material_checkbox
              ; props = Material_checkbox_props { value = false; enabled = true }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.value_changed
                    ; handler_id = handler 81L
                    }
                  ]
              ; parent_data = No_parent_data
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "widget props encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "widget props decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "widget props changed during round trip")
;;

let test_text_input_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 10L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 12L
              ; props =
                  Text_input_props
                    { session_id = session 7L
                    ; document_revision = document_revision 9L
                    ; value =
                        { text = "拼😀音"
                        ; selection = { start_utf16 = 4; end_utf16 = 4 }
                        ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
                        }
                    ; enabled = true
                    ; read_only = false
                    ; obscure_text = false
                    ; keyboard_type = Keyboard_text
                    ; input_action = Done
                    ; accepted_local_revision = local_revision 11L
                    ; update_mode = Correction
                    ; autofocus = true
                    ; max_utf8_bytes = Some 64
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "text input encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "text input decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "text input props changed during round trip")
;;

let test_text_input_rejects_split_surrogate_range () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 10L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 12L
              ; props =
                  Text_input_props
                    { session_id = session 1L
                    ; document_revision = document_revision 1L
                    ; value =
                        { text = "😀"
                        ; selection = { start_utf16 = 1; end_utf16 = 1 }
                        ; composing = None
                        }
                    ; enabled = true
                    ; read_only = false
                    ; obscure_text = false
                    ; keyboard_type = Keyboard_text
                    ; input_action = Done
                    ; accepted_local_revision = local_revision 0L
                    ; update_mode = Ack
                    ; autofocus = false
                    ; max_utf8_bytes = None
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "unexpected split-surrogate error: %s" error.message
  | Ok _ -> fail "split surrogate range unexpectedly encoded"
;;

let expect_decode_error code bytes =
  match Binary_codec.decode bytes with
  | Ok _ -> fail "malformed input unexpectedly decoded"
  | Error error -> expect (error.code = code) "unexpected decoder error"
;;

let test_malformed_frames () =
  let valid = fixture () in
  let bad_magic = Bytes.copy valid in
  Bytes.set bad_magic 0 '\x00';
  expect_decode_error Invalid_magic bad_magic;
  expect_decode_error Truncated_input (Bytes.sub valid 0 47);
  let trailing = Bytes.extend valid 0 1 in
  expect_decode_error Invalid_payload_length trailing
;;

let test_event_batch_fixture () =
  let path =
    let from_root = "protocol/generated/fixtures/counter_press.hex" in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/counter_press.hex"
  in
  let channel = open_in_bin path in
  let encoded =
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
  in
  match Event_batch_codec.decode encoded with
  | Error error -> fail "event batch decode failed: %s" error.message
  | Ok { Inbound_event.runtime_epoch; events = [ event ] } ->
    expect (runtime_epoch = epoch 21L) "unexpected event epoch";
    expect (event.sequence = sequence 1L) "unexpected event sequence";
    expect (event.displayed_revision = revision 1L) "unexpected displayed revision";
    expect (event.node_id = node 3L) "unexpected event node";
    expect (event.handler_id = handler 9001L) "unexpected handler";
    expect (event.event_tag = Generated_protocol.Event_tag.press) "unexpected tag";
    expect (event.payload = Unit) "unexpected payload"
  | Ok _ -> fail "unexpected event batch shape"
;;

let test_text_limit_reached_event_round_trip () =
  let batch : Inbound_event.batch =
    { runtime_epoch = epoch 21L
    ; events =
        [ { sequence = sequence 9L
          ; displayed_revision = revision 4L
          ; node_id = node 12L
          ; handler_id = handler 104L
          ; event_tag = Generated_protocol.Event_tag.text_limit_reached
          ; payload = Unit
          }
        ]
    }
  in
  match Event_batch_codec.encode batch with
  | Error error -> fail "text limit event encode failed: %s" error.message
  | Ok encoded ->
    expect (Bytes.length encoded < 128) "text limit event payload is not bounded";
    (match Event_batch_codec.decode encoded with
     | Error error -> fail "text limit event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "text limit event changed during round trip")
;;

let test_text_input_rejects_invalid_utf8_byte_limits () =
  let encode max_utf8_bytes =
    Binary_codec.encode
      Wire_frame.
        { runtime_epoch = epoch 10L
        ; base_revision = revision 4L
        ; target_revision = revision 5L
        ; kind = Incremental_frame
        ; operations =
            [ Update_props
                { node_id = node 12L
                ; props =
                    Text_input_props
                      { session_id = session 7L
                      ; document_revision = document_revision 9L
                      ; value =
                          { text = ""
                          ; selection = { start_utf16 = 0; end_utf16 = 0 }
                          ; composing = None
                          }
                      ; enabled = true
                      ; read_only = false
                      ; obscure_text = false
                      ; keyboard_type = Keyboard_text
                      ; input_action = Done
                      ; accepted_local_revision = local_revision 0L
                      ; update_mode = Ack
                      ; autofocus = false
                      ; max_utf8_bytes
                      }
                }
            ]
        }
  in
  List.iter
    (fun value ->
       match encode (Some value) with
       | Error { code = Invalid_props; _ } -> ()
       | Error error -> fail "unexpected byte limit error: %s" error.message
       | Ok _ -> fail "invalid max_utf8_bytes=%d unexpectedly encoded" value)
    [ 0; -1; 1_048_577; 0x1_0000_0000 ];
  match encode None with
  | Error error -> fail "unlimited text input failed: %s" error.message
  | Ok _ -> ()
;;

let test_unknown_event_tag () =
  let encoded =
    let path =
      let from_root = "protocol/generated/fixtures/counter_press.hex" in
      if Sys.file_exists from_root
      then from_root
      else "../../protocol/generated/fixtures/counter_press.hex"
    in
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
  in
  Bytes.set encoded 88 '\xff';
  match Event_batch_codec.decode encoded with
  | Error { code = Unknown_event_tag; _ } -> ()
  | Error error -> fail "unexpected event decoder error: %s" error.message
  | Ok _ -> fail "unknown event tag unexpectedly decoded"
;;

let test_interaction_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 12L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Gesture
              ; props = Gesture_props
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 2L
              ; kind = Focus_scope
              ; props = Focus_scope_props { autofocus = true }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 3L
              ; kind = Mouse_region
              ; props = Mouse_region_props { opaque = false }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = node 4L
              ; kind = Keyboard_listener
              ; props = Keyboard_listener_props { autofocus = true; key_policy = Handled }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "interaction encode failed: %s" error.message
  | Ok bytes ->
    (match Binary_codec.decode bytes with
     | Error error -> fail "interaction decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "interaction props changed")
;;

let test_interaction_event_round_trip () =
  let events =
    Inbound_event.
      [ { sequence = sequence 1L
        ; displayed_revision = revision 1L
        ; node_id = node 1L
        ; handler_id = handler 10L
        ; event_tag = Generated_protocol.Event_tag.tap
        ; payload =
            Tap
              { local_x = 1.
              ; local_y = 2.
              ; global_x = 3.
              ; global_y = 4.
              ; pointer_kind = Touch
              }
        }
      ; { sequence = sequence 2L
        ; displayed_revision = revision 1L
        ; node_id = node 1L
        ; handler_id = handler 11L
        ; event_tag = Generated_protocol.Event_tag.pointer_down
        ; payload =
            Pointer
              { pointer_id = ID.Input.Pointer_id.of_int64 7L
              ; local_x = 5.
              ; local_y = 6.
              ; global_x = 7.
              ; global_y = 8.
              ; pointer_kind = Mouse
              ; buttons = 1
              }
        }
      ; { sequence = sequence 3L
        ; displayed_revision = revision 1L
        ; node_id = node 2L
        ; handler_id = handler 12L
        ; event_tag = Generated_protocol.Event_tag.key
        ; payload =
            Key
              { logical_key = ID.Input.Logical_key.of_int64 97L
              ; physical_key = ID.Input.Physical_key.of_int64 0x70004L
              ; action = Key_down
              ; modifiers = 3
              }
        }
      ]
  in
  let batch = Inbound_event.{ runtime_epoch = epoch 12L; events } in
  match Event_batch_codec.encode batch with
  | Error error -> fail "interaction event encode failed: %s" error.message
  | Ok bytes ->
    (match Event_batch_codec.decode bytes with
     | Error error -> fail "interaction event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "interaction event payload changed")
;;

let expect_frame_round_trip label frame =
  match Binary_codec.encode frame with
  | Error error -> fail "%s encode failed: %s" label error.message
  | Ok bytes ->
    (match Binary_codec.decode bytes with
     | Error error -> fail "%s decode failed: %s" label error.message
     | Ok decoded -> expect (decoded = frame) "%s changed during round trip" label)
;;

let expect_event_batch_round_trip label batch =
  match Event_batch_codec.encode batch with
  | Error error -> fail "%s encode failed: %s" label error.message
  | Ok bytes ->
    (match Event_batch_codec.decode bytes with
     | Error error -> fail "%s decode failed: %s" label error.message
     | Ok decoded -> expect (decoded = batch) "%s changed during round trip" label)
;;

let test_host_requests_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "host requests"
    { runtime_epoch = epoch 31L
    ; base_revision = revision 2L
    ; target_revision = revision 3L
    ; kind = Incremental_frame
    ; operations =
        [ Host_request
            { request_id = request 1L; payload = Clipboard_write { text = "剪贴板😀" } }
        ; Host_request
            { request_id = request 2L
            ; payload =
                Pick_file { allowed_extensions = [ "txt"; "md" ]; allow_multiple = true }
            }
        ; Host_request
            { request_id = request 3L
            ; payload = Open_url { uri = "https://example.com/路径" }
            }
        ; Cancel_host_request { request_id = request 2L }
        ]
    }
;;

let test_host_response_events_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "host response events"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = request 1L
                ; status = Host_ok
                ; value = Bytes.of_string "accepted"
                }
          }
        ; { sequence = sequence 2L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = request 2L; status = Host_cancelled; value = Bytes.empty }
          }
        ]
    }
;;

let test_environment_event_round_trip () =
  let open Inbound_event in
  let environment =
    { viewport_width = 1440.
    ; viewport_height = 900.
    ; device_pixel_ratio = 2.
    ; text_scale = 1.1
    ; brightness = Environment_dark
    ; platform = "macos"
    ; locale = "zh_CN"
    ; safe_area = { left = 0.; top = 24.; right = 0.; bottom = 0. }
    ; keyboard_insets = { left = 0.; top = 0.; right = 0.; bottom = 280. }
    ; accessible_navigation = false
    ; bold_text = false
    ; invert_colors = false
    ; disable_animations = false
    ; reduced_motion = false
    ; high_contrast = true
    ; orientation = Landscape
    ; pointer_kinds = 5
    }
  in
  expect_event_batch_round_trip
    "environment event"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.environment_changed
          ; payload = Environment_changed environment
          }
        ]
    }
;;

let test_native_widget_props_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "native widget props"
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Native_widget
            ; props =
                Native_widget_props
                  { kind_id = ID.Native_widget.Kind_id.of_int 42
                  ; version = 3
                  ; capabilities = 5L
                  ; payload = Bytes.of_string "\000typed\255"
                  }
            ; event_bindings =
                [ { event_tag = ID.Protocol.Event_tag.of_int 21; handler_id = handler 9L }
                ]
            ; parent_data = No_parent_data
            }
        ; Set_root (node 1L)
        ]
    }
;;

let test_pressable_props_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "pressable props"
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Pressable
            ; props =
                Pressable_props
                  { overlay_color_argb = 0x181c2026l; release_delay_ms = 80 }
            ; event_bindings =
                [ { event_tag = Generated_protocol.Event_tag.press
                  ; handler_id = handler 9L
                  }
                ]
            ; parent_data = No_parent_data
            }
        ; Set_root (node 1L)
        ]
    }
;;

let test_native_event_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "native event"
    { runtime_epoch = epoch 4L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 8L
          ; handler_id = handler 9L
          ; event_tag = Generated_protocol.Event_tag.native_event
          ; payload =
              Native_event
                { kind_id = ID.Native_widget.Kind_id.of_int 42
                ; version = 3
                ; event_id = ID.Native_widget.Event_id.of_int 7
                ; payload = Bytes.of_string "\000\023\255"
                }
          }
        ]
    }
;;

let test_runtime_stats_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "runtime stats"
    { runtime_epoch = epoch 9L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Empty
            ; props = Empty_props
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Set_root (node 1L)
        ; Runtime_stats
            { event_batch_size = 3
            ; bonsai_flush_ns = 11L
            ; result_read_ns = 12L
            ; reconcile_ns = 13L
            ; encode_ns = 14L
            ; patch_count = 2
            ; patch_bytes = 80
            ; lifecycle_ns = 15L
            ; full_snapshot_count = 1
            ; resync_count = 0
            }
        ]
    }
;;

let zero_runtime_stats =
  Wire_frame.
    { event_batch_size = 0
    ; bonsai_flush_ns = 0L
    ; result_read_ns = 0L
    ; reconcile_ns = 0L
    ; encode_ns = 0L
    ; patch_count = 0
    ; patch_bytes = 0
    ; lifecycle_ns = 0L
    ; full_snapshot_count = 0
    ; resync_count = 0
    }
;;

let runtime_encode_exn frame =
  match Binary_codec.encode_runtime_frame frame with
  | Ok encoded -> encoded
  | Error error -> fail "runtime encode failed: %s" error.message
;;

let patch_runtime_exn encoded ~encode_ns ~patch_bytes =
  match Binary_codec.patch_runtime_stats encoded ~encode_ns ~patch_bytes with
  | Ok () -> ()
  | Error error -> fail "runtime stats patch failed: %s" error.message
;;

let replace_runtime_stats frame ~encode_ns ~patch_bytes =
  let operations =
    List.map
      (function
        | Wire_frame.Runtime_stats stats ->
          Wire_frame.Runtime_stats { stats with encode_ns; patch_bytes }
        | operation -> operation)
      frame.Wire_frame.operations
  in
  { frame with operations }
;;

let runtime_stats_exn frame =
  match
    List.filter_map
      (function
        | Wire_frame.Runtime_stats stats -> Some stats
        | _ -> None)
      frame.Wire_frame.operations
  with
  | [ stats ] -> stats
  | _ -> fail "decoded runtime frame did not contain exactly one stats operation"
;;

let test_runtime_stats_backpatch () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 91L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Empty
              ; props = Empty_props
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Set_root (node 1L)
          ; Runtime_stats zero_runtime_stats
          ]
      }
  in
  let encoded = runtime_encode_exn frame in
  let bytes = Binary_codec.Runtime_encoded_frame.bytes encoded in
  let patch_bytes = Bytes.length bytes in
  patch_runtime_exn encoded ~encode_ns:123_456L ~patch_bytes;
  let decoded =
    match Binary_codec.decode bytes with
    | Ok frame -> frame
    | Error error -> fail "backpatched frame did not decode: %s" error.message
  in
  let stats = runtime_stats_exn decoded in
  expect (Int64.equal stats.encode_ns 123_456L) "backpatch changed encode_ns";
  expect (stats.patch_bytes = patch_bytes) "backpatch did not write the final byte length";
  let expected = replace_runtime_stats frame ~encode_ns:123_456L ~patch_bytes in
  expect (decoded = expected) "backpatch changed fields outside runtime stats";
  match Binary_codec.encode expected with
  | Error error -> fail "ordinary comparison encode failed: %s" error.message
  | Ok ordinary ->
    expect
      (Bytes.equal bytes ordinary)
      "backpatched bytes differ from ordinary encoding of the same frame"
;;

let test_runtime_stats_backpatch_limits () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 92L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations = [ Runtime_stats zero_runtime_stats ]
      }
  in
  let encoded = runtime_encode_exn frame in
  patch_runtime_exn encoded ~encode_ns:Int64.max_int ~patch_bytes:0xffffffff;
  let decoded =
    match Binary_codec.decode (Binary_codec.Runtime_encoded_frame.bytes encoded) with
    | Ok frame -> frame
    | Error error -> fail "maximum-value runtime frame did not decode: %s" error.message
  in
  let stats = runtime_stats_exn decoded in
  expect (Int64.equal stats.encode_ns Int64.max_int) "maximum encode_ns changed";
  expect (stats.patch_bytes = 0xffffffff) "maximum patch_bytes changed"
;;

let test_runtime_encode_requires_exactly_one_stats_operation () =
  (match Binary_codec.encode_runtime_frame counter_frame with
   | Error _ -> ()
   | Ok _ -> fail "runtime encoder accepted a frame without runtime stats");
  let duplicate =
    Wire_frame.
      { runtime_epoch = epoch 93L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Runtime_stats zero_runtime_stats; Runtime_stats zero_runtime_stats ]
      }
  in
  match Binary_codec.encode_runtime_frame duplicate with
  | Error _ -> ()
  | Ok _ -> fail "runtime encoder accepted duplicate runtime stats"
;;

let test_runtime_stats_backpatch_variants () =
  let frames =
    Wire_frame.
      [ { runtime_epoch = epoch 95L
        ; base_revision = revision 0L
        ; target_revision = revision 1L
        ; kind = Full_snapshot
        ; operations =
            [ Create_node
                { node_id = node 1L
                ; kind = Empty
                ; props = Empty_props
                ; event_bindings = []
                ; parent_data = No_parent_data
                }
            ; Set_root (node 1L)
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 1L
        ; target_revision = revision 2L
        ; kind = Incremental_frame
        ; operations =
            [ Update_props { node_id = node 1L; props = Empty_props }
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 2L
        ; target_revision = revision 3L
        ; kind = Incremental_frame
        ; operations =
            [ Host_request
                { request_id = request 7L
                ; payload = Clipboard_write { text = "patched" }
                }
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 3L
        ; target_revision = revision 4L
        ; kind = Incremental_frame
        ; operations = [ Runtime_stats zero_runtime_stats ]
        }
      ]
  in
  List.iteri
    (fun index frame ->
       let encoded = runtime_encode_exn frame in
       let bytes = Binary_codec.Runtime_encoded_frame.bytes encoded in
       let encode_ns = Int64.of_int (index + 1) in
       let patch_bytes = Bytes.length bytes in
       patch_runtime_exn encoded ~encode_ns ~patch_bytes;
       match Binary_codec.decode bytes with
       | Error error -> fail "runtime variant did not decode: %s" error.message
       | Ok decoded ->
         expect
           (decoded = replace_runtime_stats frame ~encode_ns ~patch_bytes)
           "runtime backpatch changed a frame variant")
    frames
;;

let test_application_request_round_trip_and_bounds () =
  let below = Bytes.of_string "\000\001\127\128\255" in
  let boundary =
    Bytes.make Generated_protocol.Limits.max_application_payload_bytes '\255'
  in
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 96L
      ; base_revision = revision 3L
      ; target_revision = revision 4L
      ; kind = Incremental_frame
      ; operations =
          [ Application_request { request_id = 71L; payload = below }
          ; Application_request { request_id = 72L; payload = boundary }
          ]
      }
  in
  let encoded =
    match Binary_codec.encode frame with
    | Ok bytes -> bytes
    | Error error -> fail "application request encode failed: %s" error.message
  in
  (match Binary_codec.decode encoded with
   | Ok decoded -> expect (decoded = frame) "application request bytes changed"
   | Error error -> fail "application request decode failed: %s" error.message);
  let oversized =
    Wire_frame.
      { frame with
        operations =
          [ Application_request
              { request_id = 73L
              ; payload =
                  Bytes.make
                    (Generated_protocol.Limits.max_application_payload_bytes + 1)
                    '\000'
              }
          ]
      }
  in
  match Binary_codec.encode oversized with
  | Error { code = Application_payload_too_large; _ } -> ()
  | Error error -> fail "oversized application request returned %s" error.message
  | Ok _ -> fail "oversized application request encoded"
;;

let test_application_response_error_and_event_round_trip () =
  let open Inbound_event in
  let batch =
    { runtime_epoch = epoch 96L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_response
          ; payload =
              Application_response
                { request_id = 71L; payload = Bytes.of_string "\000\255response" }
          }
        ; { sequence = sequence 2L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_request_error
          ; payload =
              Application_request_error
                { request_id = 72L
                ; error =
                    { code = Handler_failed; message = "application handler failed" }
                }
          }
        ; { sequence = sequence 3L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_event
          ; payload = Application_event (Bytes.of_string "\128\000event")
          }
        ]
    }
  in
  let encoded =
    match Event_batch_codec.encode batch with
    | Ok bytes -> bytes
    | Error error -> fail "application event encode failed: %s" error.message
  in
  match Event_batch_codec.decode encoded with
  | Ok decoded -> expect (decoded = batch) "application event bytes changed"
  | Error error -> fail "application event decode failed: %s" error.message
;;

let props_frame props =
  Wire_frame.
    { runtime_epoch = epoch 90L
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; kind = Incremental_frame
    ; operations = [ Update_props { node_id = node 1L; props } ]
    }
;;

let expect_invalid_props_encode label frame =
  match Binary_codec.encode frame with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "%s produced the wrong encode error: %s" label error.message
  | Ok _ -> fail "%s unexpectedly encoded" label
;;

let find_float64 bytes value =
  let needle = Bytes.create 8 in
  Bytes.set_int64_le needle 0 (Int64.bits_of_float value);
  let rec search offset =
    if offset + Bytes.length needle > Bytes.length bytes
    then fail "float64 value %g was not found" value
    else (
      let rec matches index =
        index = Bytes.length needle
        || (Char.equal (Bytes.get bytes (offset + index)) (Bytes.get needle index)
            && matches (index + 1))
      in
      if matches 0 then offset else search (offset + 1))
  in
  search 0
;;

let replace_float64_at bytes offset value =
  let result = Bytes.copy bytes in
  Bytes.set_int64_le result offset (Int64.bits_of_float value);
  result
;;

let replace_float64 bytes before after =
  replace_float64_at bytes (find_float64 bytes before) after
;;

let expect_invalid_props_decode label bytes =
  match Binary_codec.decode bytes with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "%s produced the wrong decode error: %s" label error.message
  | Ok _ -> fail "%s unexpectedly decoded" label
;;

let test_sliver_wire_boundaries () =
  let fixed overscan =
    Wire_frame.Sliver_fixed_extent_props
      { total_count = 1; first_index = 0; item_extent = 48.; overscan }
  in
  let transition duration =
    Wire_frame.
      { enabled = true
      ; expand_duration_ms = duration
      ; collapse_duration_ms = duration
      ; expand_curve = Se_linear
      ; collapse_curve = Se_linear
      }
  in
  let varied overscan transition =
    Wire_frame.Sliver_varied_extent_props
      { total_count = 1
      ; first_index = 0
      ; default_item_extent = 48.
      ; overscan
      ; extent_overrides = []
      ; transition
      }
  in
  List.iter
    (fun boundary ->
       expect_frame_round_trip "fixed sliver u32 boundary" (props_frame (fixed boundary));
       expect_frame_round_trip
         "varied sliver u32 boundary"
         (props_frame (varied boundary (Some (transition boundary)))))
    [ 0; 0xffff_ffff ];
  List.iter
    (fun invalid ->
       expect_invalid_props_encode
         "fixed sliver invalid overscan"
         (props_frame (fixed invalid));
       expect_invalid_props_encode
         "varied sliver invalid overscan"
         (props_frame (varied invalid None));
       expect_invalid_props_encode
         "varied sliver invalid transition"
         (props_frame (varied 0 (Some (transition invalid)))))
    [ -1; 0x1_0000_0000 ]
;;

let test_virtual_sliver_invariant_validation () =
  let fixed ~total_count ~first_index =
    Wire_frame.Sliver_fixed_extent_props
      { total_count; first_index; item_extent = 48.; overscan = 0 }
  in
  let varied ~total_count ~first_index ~extent_overrides =
    Wire_frame.Sliver_varied_extent_props
      { total_count
      ; first_index
      ; default_item_extent = 48.
      ; overscan = 0
      ; extent_overrides
      ; transition = None
      }
  in
  expect_invalid_props_encode
    "fixed first_index above total_count"
    (props_frame (fixed ~total_count:10 ~first_index:11));
  expect_invalid_props_encode
    "varied first_index above total_count"
    (props_frame (varied ~total_count:10 ~first_index:11 ~extent_overrides:[]));
  List.iter
    (fun (label, extent_overrides) ->
       expect_invalid_props_encode
         label
         (props_frame (varied ~total_count:10 ~first_index:0 ~extent_overrides)))
    [ ( "descending sliver overrides"
      , [ Wire_frame.{ index = 4; extent = 60. }; Wire_frame.{ index = 3; extent = 70. } ]
      )
    ; ( "duplicate sliver overrides"
      , [ Wire_frame.{ index = 3; extent = 60. }; Wire_frame.{ index = 3; extent = 70. } ]
      )
    ; "out-of-range sliver override", [ Wire_frame.{ index = 10; extent = 60. } ]
    ];
  expect_frame_round_trip
    "empty fixed sliver boundary"
    (props_frame (fixed ~total_count:0 ~first_index:0));
  expect_frame_round_trip
    "varied final override boundary"
    (props_frame
       (varied
          ~total_count:10
          ~first_index:10
          ~extent_overrides:[ Wire_frame.{ index = 9; extent = 60. } ]))
;;

let test_scroll_view_cache_extent_validation () =
  let props cache_extent =
    Wire_frame.Scroll_view_props
      { axis = Vertical; reverse = false; primary = false; cache_extent }
  in
  expect_frame_round_trip "zero scroll cache extent" (props_frame (props (Some 0.)));
  List.iter
    (fun invalid ->
       expect_invalid_props_encode
         "invalid scroll cache extent"
         (props_frame (props (Some invalid))))
    [ -1.; Float.nan; Float.infinity; Float.neg_infinity ];
  let encoded =
    match Binary_codec.encode (props_frame (props (Some 123.25))) with
    | Ok bytes -> bytes
    | Error error -> fail "valid scroll cache extent failed to encode: %s" error.message
  in
  List.iter
    (fun invalid ->
       expect_invalid_props_decode
         "invalid decoded scroll cache extent"
         (replace_float64 encoded 123.25 invalid))
    [ -1.; Float.nan; Float.infinity; Float.neg_infinity ]
;;

let test_sliver_app_bar_codec_validation () =
  let props
        ?(pinned = true)
        ?(expanded_height = Some 200.)
        ?(collapsed_height = Some 100.)
        ?(floating = true)
        ?(snap = true)
        ?(toolbar_height = 56.)
        ?(elevation = Some 4.)
        ()
    =
    Wire_frame.Sliver_app_bar_props
      { pinned
      ; expanded_height
      ; collapsed_height
      ; floating
      ; snap
      ; stretch = false
      ; toolbar_height
      ; has_leading = false
      ; has_flexible_space = false
      ; has_bottom = false
      ; has_actions = false
      ; force_elevated = false
      ; automatically_imply_leading = true
      ; center_title = None
      ; background_color = None
      ; foreground_color = None
      ; elevation
      }
  in
  expect_frame_round_trip "valid sliver app bar" (props_frame (props ()));
  List.iter
    (fun (label, invalid) -> expect_invalid_props_encode label (props_frame invalid))
    [ "zero toolbar height", props ~toolbar_height:0. ()
    ; "negative toolbar height", props ~toolbar_height:(-1.) ()
    ; "NaN toolbar height", props ~toolbar_height:Float.nan ()
    ; "infinite toolbar height", props ~toolbar_height:Float.infinity ()
    ; "negative expanded height", props ~expanded_height:(Some (-1.)) ()
    ; "negative collapsed height", props ~collapsed_height:(Some (-1.)) ()
    ; ( "collapsed height above expanded height"
      , props ~expanded_height:(Some 100.) ~collapsed_height:(Some 120.) () )
    ; "collapsed height below toolbar", props ~collapsed_height:(Some 40.) ()
    ; "snap without floating", props ~floating:false ~snap:true ()
    ; "negative elevation", props ~elevation:(Some (-1.)) ()
    ; "NaN elevation", props ~elevation:(Some Float.nan) ()
    ; "infinite elevation", props ~elevation:(Some Float.infinity) ()
    ];
  let encoded =
    match Binary_codec.encode (props_frame (props ())) with
    | Ok bytes -> bytes
    | Error error -> fail "valid sliver app bar failed to encode: %s" error.message
  in
  let expanded_offset = find_float64 encoded 200. in
  List.iter
    (fun (label, invalid) -> expect_invalid_props_decode label invalid)
    [ "decoded negative expanded height", replace_float64_at encoded expanded_offset (-1.)
    ; "decoded NaN expanded height", replace_float64_at encoded expanded_offset Float.nan
    ; ( "decoded infinite expanded height"
      , replace_float64_at encoded expanded_offset Float.infinity )
    ; "decoded negative collapsed height", replace_float64 encoded 100. (-1.)
    ; ( "decoded collapsed height above expanded height"
      , replace_float64_at encoded expanded_offset 50. )
    ; "decoded collapsed height below toolbar", replace_float64 encoded 100. 40.
    ; "decoded zero toolbar height", replace_float64 encoded 56. 0.
    ; "decoded negative elevation", replace_float64 encoded 4. (-1.)
    ; "decoded NaN elevation", replace_float64 encoded 4. Float.nan
    ; "decoded infinite elevation", replace_float64 encoded 4. Float.infinity
    ; ( "decoded snap without floating"
      , let value = Bytes.copy encoded in
        Bytes.set value (expanded_offset + 17) '\000';
        value )
    ]
;;

let () =
  test_golden_fixture ();
  test_round_trip ();
  test_styled_text_props_round_trip ();
  test_legacy_text_props_layout ();
  test_animation_props_round_trip ();
  test_page_presentations_round_trip_and_incremental_updates ();
  test_modal_bottom_sheet_rejects_unknown_wire_enums ();
  test_legacy_opacity_layout ();
  test_layout_material_and_semantics_props_round_trip ();
  test_text_input_props_round_trip ();
  test_text_input_rejects_split_surrogate_range ();
  test_malformed_frames ();
  test_event_batch_fixture ();
  test_text_limit_reached_event_round_trip ();
  test_text_input_rejects_invalid_utf8_byte_limits ();
  test_unknown_event_tag ();
  test_interaction_props_round_trip ();
  test_interaction_event_round_trip ();
  test_host_requests_round_trip ();
  test_host_response_events_round_trip ();
  test_environment_event_round_trip ();
  test_pressable_props_round_trip ();
  test_native_widget_props_round_trip ();
  test_native_event_round_trip ();
  test_runtime_stats_round_trip ();
  test_runtime_stats_backpatch ();
  test_runtime_stats_backpatch_limits ();
  test_runtime_encode_requires_exactly_one_stats_operation ();
  test_runtime_stats_backpatch_variants ();
  test_application_request_round_trip_and_bounds ();
  test_application_response_error_and_event_round_trip ();
  test_sliver_wire_boundaries ();
  test_virtual_sliver_invariant_validation ();
  test_scroll_view_cache_extent_validation ();
  test_sliver_app_bar_codec_validation ();
  print_endline "protocol tests passed"
;;
