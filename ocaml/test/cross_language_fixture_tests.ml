module Protocol = Bonsai_flutter_protocol

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

let fixture name =
  let from_root = "protocol/generated/fixtures/" ^ name in
  let from_test = "../../protocol/generated/fixtures/" ^ name in
  let path =
    if Sys.file_exists from_root
    then from_root
    else if Sys.file_exists from_test
    then from_test
    else fail "missing Dart-generated cross-language fixture: %s" name
  in
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
;;

let expect_fixture name expected =
  let encoded = fixture name in
  let decoded =
    match Protocol.Event_batch_codec.decode encoded with
    | Ok batch -> batch
    | Error error -> fail "%s decode failed: %s" name error.message
  in
  expect (decoded = expected) "%s decoded to unexpected events" name;
  match Protocol.Event_batch_codec.encode expected with
  | Error error -> fail "%s encode failed: %s" name error.message
  | Ok reencoded ->
    expect
      (Bytes.equal encoded reencoded)
      "OCaml and Dart encoded different bytes for %s"
      name
;;

let test_counter_press () =
  let open Protocol.Inbound_event in
  expect_fixture
    "dart_counter_press.hex"
    { runtime_epoch = 21L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 1L
          ; node_id = 3L
          ; handler_id = 9001L
          ; event_tag = Protocol.Generated_protocol.Event_tag.press
          ; payload = Unit
          }
        ]
    }
;;

let test_host_response () =
  let open Protocol.Inbound_event in
  expect_fixture
    "dart_host_response.hex"
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 2L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = 44L
                ; status = Host_error
                ; value = Bytes.of_string "denied: 剪贴板😀"
                }
          }
        ]
    }
;;

let test_text_edit_unicode () =
  let open Protocol.Inbound_event in
  expect_fixture
    "dart_text_edit_unicode.hex"
    { runtime_epoch = 22L
    ; events =
        [ { sequence = 3L
          ; displayed_revision = 2L
          ; node_id = 4L
          ; handler_id = 44L
          ; event_tag = Protocol.Generated_protocol.Event_tag.text_edit
          ; payload =
              Text_edit
                { session_id = 7L
                ; local_revision = 3L
                ; base_document_revision = 2L
                ; text = "拼😀音"
                ; selection = { start_utf16 = 4; end_utf16 = 4 }
                ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
                }
          }
        ]
    }
;;

let test_environment_changed () =
  let open Protocol.Inbound_event in
  expect_fixture
    "dart_environment_changed.hex"
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 4L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
          ; payload =
              Environment_changed
                { viewport_width = 1440.
                ; viewport_height = 900.
                ; device_pixel_ratio = 2.
                ; text_scale = 1.25
                ; brightness = Environment_dark
                ; platform = "macos"
                ; locale = "zh-CN"
                ; safe_area = { left = 0.; top = 24.; right = 0.; bottom = 0. }
                ; keyboard_insets = { left = 0.; top = 0.; right = 0.; bottom = 280. }
                ; accessible_navigation = false
                ; bold_text = true
                ; invert_colors = false
                ; disable_animations = false
                ; reduced_motion = true
                ; high_contrast = true
                ; orientation = Landscape
                ; pointer_kinds = 10
                }
          }
        ]
    }
;;

let () =
  test_counter_press ();
  test_host_response ();
  test_text_edit_unicode ();
  test_environment_changed ();
  print_endline "cross-language fixture tests passed"
;;
