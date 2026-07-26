module Protocol = Bonsai_flutter_protocol
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format
let expect condition message = if not condition then fail "%s" message

let expect_round_trip frame =
  match Protocol.Binary_codec.encode frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok bytes ->
    (match Protocol.Binary_codec.decode bytes with
     | Error error -> fail "decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "frame changed during round trip")
;;

let test_host_requests_round_trip () =
  let open Protocol.Wire_frame in
  expect_round_trip
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

let test_host_response_event_round_trip () =
  let open Protocol.Inbound_event in
  let batch =
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = 1L; status = Host_ok; value = Bytes.of_string "accepted" }
          }
        ; { sequence = 2L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = 2L; status = Host_cancelled; value = Bytes.empty }
          }
        ]
    }
  in
  match Protocol.Event_batch_codec.encode batch with
  | Error error -> fail "event encode failed: %s" error.message
  | Ok bytes ->
    (match Protocol.Event_batch_codec.decode bytes with
     | Error error -> fail "event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "host responses changed during round trip")
;;

let test_environment_event_round_trip () =
  let open Protocol.Inbound_event in
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
  let batch =
    { runtime_epoch = 31L
    ; events =
        [ { sequence = 1L
          ; displayed_revision = 3L
          ; node_id = 0L
          ; handler_id = 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
          ; payload = Environment_changed environment
          }
        ]
    }
  in
  match Protocol.Event_batch_codec.encode batch with
  | Error error -> fail "environment encode failed: %s" error.message
  | Ok bytes ->
    (match Protocol.Event_batch_codec.decode bytes with
     | Error error -> fail "environment decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "environment changed during round trip")
;;

let test_navigation_widget_is_typed () =
  let popped = ref None in
  let on_pop =
    Ui.Event.Handler.create (function
      | Ui.Event.Payload.Route_pop { page_key; result } ->
        popped := Some (page_key, result)
      | _ -> fail "route pop handler received the wrong payload")
  in
  let page =
    Ui.Widget.page
      ~page_key:"settings"
      ~transition:Ui.Navigation.Fade
      ~can_pop:true
      ~restoration_id:"settings-page"
      (Ui.Widget.text "Settings")
  in
  let navigator = Ui.Widget.navigator ~on_pop [ page ] in
  expect
    (String.equal (Ui.Widget.For_testing.kind_name navigator) "Navigator")
    "navigator kind is not typed";
  let children = Ui.Widget.For_testing.children navigator in
  expect (Array.length children = 1) "navigator lost its page";
  expect
    (String.equal (Ui.Widget.For_testing.kind_name children.(0)) "Page")
    "navigator child is not a Page";
  let overlay =
    Ui.Widget.overlay ~alignment:Ui.Navigation.Center [ Ui.Widget.text "Overlay content" ]
  in
  expect
    (String.equal (Ui.Widget.For_testing.kind_name overlay) "Overlay")
    "overlay kind is not typed";
  let dialog =
    Ui.Widget.material_dialog ~barrier_dismissible:false (Ui.Widget.text "Confirm")
  in
  expect
    (String.equal (Ui.Widget.For_testing.kind_name dialog) "Material_dialog")
    "dialog kind is not typed"
;;

let () =
  test_host_requests_round_trip ();
  test_host_response_event_round_trip ();
  test_environment_event_round_trip ();
  test_navigation_widget_is_typed ();
  print_endline "Phase 6 protocol and navigation tests passed"
;;
