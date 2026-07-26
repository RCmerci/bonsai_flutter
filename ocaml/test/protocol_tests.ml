open Bonsai_flutter_protocol

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

let fixture () =
  let path =
    let from_root = "protocol/generated/fixtures/counter_full.hex" in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/counter_full.hex"
  in
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
;;

let counter_frame =
  Wire_frame.
    { runtime_epoch = 7L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = 1L
            ; kind = Column
            ; props = Linear_props
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Create_node
            { node_id = 2L
            ; kind = Text
            ; props = Text_props { value = "Count: 0" }
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Set_children { node_id = 1L; children = [ 2L ] }
        ; Set_root 1L
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
      { runtime_epoch = 7L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props { node_id = 2L; props = Text_props { value = "计数: 1" } } ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "round trip changed the incremental frame")
;;

let test_animation_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = 7L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.75
                    ; animation = { id = 7001L; duration_ms = 250; curve = Ease_in_out }
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

let test_legacy_opacity_layout () =
  let frame =
    Wire_frame.
      { runtime_epoch = 8L
      ; base_revision = 0L
      ; target_revision = 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = 4L
              ; kind = Opacity
              ; props = Opacity_props { opacity = 0.5 }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Set_root 4L
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
      { runtime_epoch = 9L
      ; base_revision = 0L
      ; target_revision = 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = 1L
              ; kind = Padding
              ; props = Padding_props { left = 12.; top = 8.; right = 12.; bottom = 8. }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 2L
              ; kind = Center
              ; props = Center_props { width_factor = None; height_factor = Some 1.5 }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 3L
              ; kind = Scroll_view
              ; props = Scroll_view_props { axis = Vertical; reverse = false }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.scroll_notification
                    ; handler_id = 80L
                    }
                  ]
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 4L
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
              { node_id = 5L
              ; kind = Theme
              ; props =
                  Theme_props
                    { brightness = Dark; color_seed = Int32.of_string "0xff2060a0" }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 6L
              ; kind = Material_checkbox
              ; props = Material_checkbox_props { value = false; enabled = true }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.value_changed
                    ; handler_id = 81L
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
      { runtime_epoch = 10L
      ; base_revision = 4L
      ; target_revision = 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = 12L
              ; props =
                  Text_input_props
                    { session_id = 7L
                    ; document_revision = 9L
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
                    ; accepted_local_revision = 11L
                    ; update_mode = Correction
                    ; autofocus = true
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
      { runtime_epoch = 10L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = 12L
              ; props =
                  Text_input_props
                    { session_id = 1L
                    ; document_revision = 1L
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
                    ; accepted_local_revision = 0L
                    ; update_mode = Ack
                    ; autofocus = false
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
    expect (runtime_epoch = 21L) "unexpected event epoch";
    expect (event.sequence = 1L) "unexpected event sequence";
    expect (event.displayed_revision = 1L) "unexpected displayed revision";
    expect (event.node_id = 3L) "unexpected event node";
    expect (event.handler_id = 9001L) "unexpected handler";
    expect (event.event_tag = Generated_protocol.Event_tag.press) "unexpected tag";
    expect (event.payload = Unit) "unexpected payload"
  | Ok _ -> fail "unexpected event batch shape"
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
      { runtime_epoch = 12L
      ; base_revision = 0L
      ; target_revision = 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = 1L
              ; kind = Gesture
              ; props = Gesture_props
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 2L
              ; kind = Focus_scope
              ; props = Focus_scope_props { autofocus = true }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 3L
              ; kind = Mouse_region
              ; props = Mouse_region_props { opaque = false }
              ; event_bindings = []
              ; parent_data = No_parent_data
              }
          ; Create_node
              { node_id = 4L
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
      [ { sequence = 1L
        ; displayed_revision = 1L
        ; node_id = 1L
        ; handler_id = 10L
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
      ; { sequence = 2L
        ; displayed_revision = 1L
        ; node_id = 1L
        ; handler_id = 11L
        ; event_tag = Generated_protocol.Event_tag.pointer_down
        ; payload =
            Pointer
              { pointer_id = 7L
              ; local_x = 5.
              ; local_y = 6.
              ; global_x = 7.
              ; global_y = 8.
              ; pointer_kind = Mouse
              ; buttons = 1
              }
        }
      ; { sequence = 3L
        ; displayed_revision = 1L
        ; node_id = 2L
        ; handler_id = 12L
        ; event_tag = Generated_protocol.Event_tag.key
        ; payload =
            Key
              { logical_key = 97L
              ; physical_key = 0x70004L
              ; action = Key_down
              ; modifiers = 3
              }
        }
      ]
  in
  let batch = Inbound_event.{ runtime_epoch = 12L; events } in
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
    { runtime_epoch = 31L
    ; base_revision = 2L
    ; target_revision = 3L
    ; kind = Incremental_frame
    ; operations =
        [ Host_request { request_id = 1L; payload = Clipboard_write { text = "剪贴板😀" } }
        ; Host_request
            { request_id = 2L
            ; payload =
                Pick_file { allowed_extensions = [ "txt"; "md" ]; allow_multiple = true }
            }
        ; Host_request
            { request_id = 3L; payload = Open_url { uri = "https://example.com/路径" } }
        ; Cancel_host_request { request_id = 2L }
        ]
    }
;;

let test_host_response_events_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "host response events"
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = 1L; status = Host_ok; value = Bytes.of_string "accepted" }
          }
        ; { sequence = 2L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = 2L; status = Host_cancelled; value = Bytes.empty }
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
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
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
    { runtime_epoch = 7L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = 1L
            ; kind = Native_widget
            ; props =
                Native_widget_props
                  { kind_id = 42
                  ; version = 3
                  ; capabilities = 5L
                  ; payload = Bytes.of_string "\000typed\255"
                  }
            ; event_bindings = [ { event_tag = 21; handler_id = 9L } ]
            ; parent_data = No_parent_data
            }
        ; Set_root 1L
        ]
    }
;;

let test_native_event_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "native event"
    { runtime_epoch = 4L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 3L
          ; node_id = 8L
          ; handler_id = 9L
          ; event_tag = Generated_protocol.Event_tag.native_event
          ; payload =
              Native_event
                { kind_id = 42
                ; version = 3
                ; event_id = 7
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
    { runtime_epoch = 9L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = 1L
            ; kind = Empty
            ; props = Empty_props
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Set_root 1L
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

let () =
  test_golden_fixture ();
  test_round_trip ();
  test_animation_props_round_trip ();
  test_legacy_opacity_layout ();
  test_layout_material_and_semantics_props_round_trip ();
  test_text_input_props_round_trip ();
  test_text_input_rejects_split_surrogate_range ();
  test_malformed_frames ();
  test_event_batch_fixture ();
  test_unknown_event_tag ();
  test_interaction_props_round_trip ();
  test_interaction_event_round_trip ();
  test_host_requests_round_trip ();
  test_host_response_events_round_trip ();
  test_environment_event_round_trip ();
  test_native_widget_props_round_trip ();
  test_native_event_round_trip ();
  test_runtime_stats_round_trip ();
  print_endline "protocol tests passed"
;;
