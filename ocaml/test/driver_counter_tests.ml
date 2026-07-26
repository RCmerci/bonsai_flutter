module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected driver error: %s" (Driver.error_to_string error)
;;

let decode_frame bytes =
  match Protocol.Binary_codec.decode bytes with
  | Ok frame -> frame
  | Error error -> fail "frame did not decode: %s" error.message
;;

let semantic_operations (frame : Protocol.Wire_frame.t) =
  let stats =
    List.filter_map
      (function
        | Protocol.Wire_frame.Runtime_stats stats -> Some stats
        | _ -> None)
      frame.operations
  in
  (match stats with
   | [ stats ] ->
     require (stats.patch_count = List.length frame.operations - 1) "invalid patch count";
     require (stats.patch_bytes > 0) "missing patch byte count"
   | _ -> fail "frame must contain exactly one runtime stats operation");
  List.filter
    (function
      | Protocol.Wire_frame.Runtime_stats _ -> false
      | _ -> true)
    frame.operations
;;

let component ~activations ~after_displays handlers graph =
  let count, increment = Bonsai.state' ~equal:Int.equal 0 graph in
  let increment_handler =
    Bonsai.map increment ~f:(fun increment ->
      Driver.Handler.create handlers ~name:"increment" (function
        | Ui.Event.Payload.Unit -> increment (fun value -> value + 1)
        | _ -> increment Fun.id))
  in
  let on_activate =
    Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr activations))
  in
  let after_display =
    Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr after_displays))
  in
  Bonsai.Edge.lifecycle ~on_activate ~after_display graph;
  Bonsai.map2 count increment_handler ~f:(fun count increment_handler ->
    Ui.Widget.column
      [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
      ; Ui.Widget.button
          ~on_press:increment_handler
          ~child:(Ui.Widget.text "Increment")
          ()
      ])
;;

let find_button_binding (frame : Protocol.Wire_frame.t) =
  List.find_map
    (function
      | Protocol.Wire_frame.Create_node
          { node_id; kind = Button; event_bindings = [ { event_tag; handler_id } ]; _ } ->
        Some (node_id, event_tag, handler_id)
      | _ -> None)
    frame.operations
  |> function
  | Some binding -> binding
  | None -> fail "initial frame has no Button press binding"
;;

let () =
  let runtime_epoch = 21L in
  let activations = ref 0 in
  let after_displays = ref 0 in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create ~runtime_epoch ~time_source (component ~activations ~after_displays)
  in
  let initial =
    match ok (Driver.step driver ()) with
    | Some frame -> frame
    | None -> fail "initial step must emit a full snapshot"
  in
  require
    (Runtime.Frame_patch.kind initial.frame_patch = Full_snapshot)
    "initial step must reconcile a full snapshot";
  let initial_wire =
    match Protocol.Binary_codec.decode initial.bytes with
    | Ok frame -> frame
    | Error error -> fail "initial frame did not decode: %s" error.message
  in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  require
    (event_tag = Protocol.Generated_protocol.Event_tag.press)
    "Button must encode the press event tag";
  require
    (!activations = 0 && !after_displays = 0)
    "initial step must not trigger presentation-gated lifecycle events";
  ok (Driver.frame_presented driver ~revision:initial.revision);
  require (!activations = 1) "initial presentation must trigger activation";
  require (!after_displays = 1) "initial presentation must trigger after-display";
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let updated =
    match ok (Driver.step driver ~events ()) with
    | Some frame -> frame
    | None -> fail "Counter press must emit an incremental frame"
  in
  let updated_wire =
    match Protocol.Binary_codec.decode updated.bytes with
    | Ok frame -> frame
    | Error error -> fail "incremental frame did not decode: %s" error.message
  in
  (match semantic_operations updated_wire with
   | [ Protocol.Wire_frame.Update_props
         { node_id = _; props = Text_props { value = "Count: 1" } }
     ] -> ()
   | operations ->
     fail
       "Counter press must emit one text prop patch, got %d operations"
       (List.length operations));
  require
    (!after_displays = 1)
    "incremental step must not run after-display before presentation";
  ok (Driver.frame_presented driver ~revision:updated.revision);
  require (!after_displays = 2) "incremental presentation must run after-display";
  let invalid_batch =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 2L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ; { sequence = 3L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id = Int64.add handler_id 1000L
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  (match Driver.step driver ~events:invalid_batch () with
   | Error (Driver.Event_error _) -> ()
   | Error error ->
     fail
       "invalid event batch returned the wrong error: %s"
       (Driver.error_to_string error)
   | Ok _ -> fail "invalid event batch was accepted");
  let valid_after_rejection =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 4L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let after_rejection =
    match ok (Driver.step driver ~events:valid_after_rejection ()) with
    | Some frame -> frame
    | None -> fail "valid event after rejected batch must emit a frame"
  in
  let after_rejection_wire =
    match Protocol.Binary_codec.decode after_rejection.bytes with
    | Ok frame -> frame
    | Error error -> fail "post-rejection frame did not decode: %s" error.message
  in
  (match semantic_operations after_rejection_wire with
   | [ Protocol.Wire_frame.Update_props
         { node_id = _; props = Text_props { value = "Count: 2" } }
     ] -> ()
   | _ -> fail "rejected batch leaked a previously queued Bonsai effect");
  let resync_request =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 5L
            ; displayed_revision = after_rejection.revision
            ; node_id = 0L
            ; handler_id = 0L
            ; event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
            ; payload = Unit
            }
          ]
      }
  in
  let resync =
    match ok (Driver.step driver ~events:resync_request ()) with
    | Some frame -> frame
    | None -> fail "resync request did not emit a full snapshot"
  in
  let resync_wire = decode_frame resync.bytes in
  require (resync_wire.kind = Full_snapshot) "resync was not a full snapshot";
  require (Int64.equal resync_wire.base_revision 0L) "resync base revision was not zero";
  require (resync.stats.resync_count = 1) "resync instrumentation did not increment";
  Driver.shutdown driver
;;

let host_effect_component ?cancellation host_ref handlers graph =
  let text, set_text = Bonsai.state' ~equal:String.equal "Idle" graph in
  let host_effects = Driver.Handler.host_effects handlers in
  host_ref := Some host_effects;
  let request_clipboard =
    Bonsai.map set_text ~f:(fun set_text ->
      Driver.Handler.create handlers ~name:"clipboard-read" (fun _ ->
        Bonsai.Effect.bind
          (Host_effect.Clipboard.read ?cancellation host_effects ())
          ~f:(function
          | Ok clipboard -> set_text (fun _ -> clipboard)
          | Error _ -> set_text (fun _ -> "Host error"))))
  in
  Bonsai.map2 text request_clipboard ~f:(fun text request_clipboard ->
    Ui.Widget.column
      [ Ui.Widget.text text
      ; Ui.Widget.button
          ~on_press:request_clipboard
          ~child:(Ui.Widget.text "Read clipboard")
          ()
      ])
;;

let test_host_effect_round_trip () =
  let runtime_epoch = 81L in
  let host_ref = ref None in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create ~runtime_epoch ~time_source (host_effect_component host_ref)
  in
  let initial =
    match ok (Driver.step driver ()) with
    | Some frame -> frame
    | None -> fail "host-effect component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  ok (Driver.frame_presented driver ~revision:initial.revision);
  let press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let request_frame =
    match ok (Driver.step driver ~events:press ()) with
    | Some frame -> frame
    | None -> fail "clipboard effect did not emit a host request"
  in
  let request_wire = decode_frame request_frame.bytes in
  let request_id =
    match semantic_operations request_wire with
    | [ Protocol.Wire_frame.Host_request { request_id; payload = Clipboard_read } ] ->
      request_id
    | operations ->
      fail "clipboard effect emitted %d unexpected operations" (List.length operations)
  in
  let host =
    match !host_ref with
    | Some host -> host
    | None -> fail "component did not expose its host-effect context"
  in
  require
    (Host_effect.Private.pending_count host = 1)
    "clipboard request was not retained while pending";
  let response =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 2L
            ; displayed_revision = request_frame.revision
            ; node_id = 0L
            ; handler_id = 0L
            ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
            ; payload =
                Host_response
                  { request_id; status = Host_ok; value = Bytes.of_string "来自 Flutter" }
            }
          ]
      }
  in
  let response_frame =
    match ok (Driver.step driver ~events:response ()) with
    | Some frame -> frame
    | None -> fail "host response did not resume the Bonsai effect"
  in
  let response_wire = decode_frame response_frame.bytes in
  (match semantic_operations response_wire with
   | [ Protocol.Wire_frame.Update_props { props = Text_props { value = "来自 Flutter" }; _ }
     ] -> ()
   | _ -> fail "host response did not produce the expected text patch");
  require
    (Host_effect.Private.pending_count host = 0)
    "completed host request remained pending";
  Driver.shutdown driver;
  require
    (Host_effect.Private.pending_count host = 0)
    "driver shutdown retained a host request"
;;

let () = test_host_effect_round_trip ()

let test_host_effect_cancellation () =
  let runtime_epoch = 83L in
  let host_ref = ref None in
  let cancellation = Host_effect.Cancellation.create () in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create
      ~runtime_epoch
      ~time_source
      (host_effect_component ~cancellation host_ref)
  in
  let initial =
    match ok (Driver.step driver ()) with
    | Some frame -> frame
    | None -> fail "cancellation component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  ok (Driver.frame_presented driver ~revision:initial.revision);
  let press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let request_frame =
    match ok (Driver.step driver ~events:press ()) with
    | Some frame -> frame
    | None -> fail "cancellable effect did not emit a host request"
  in
  let request_id =
    match semantic_operations (decode_frame request_frame.bytes) with
    | [ Protocol.Wire_frame.Host_request { request_id; _ } ] -> request_id
    | _ -> fail "cancellable effect emitted unexpected operations"
  in
  Host_effect.Cancellation.cancel cancellation;
  let cancelled =
    match ok (Driver.step driver ()) with
    | Some frame -> decode_frame frame.bytes
    | None -> fail "cancellation did not resume the effect"
  in
  require
    (List.exists
       (function
         | Protocol.Wire_frame.Cancel_host_request { request_id = cancelled_request_id }
           -> Int64.equal request_id cancelled_request_id
         | _ -> false)
       cancelled.operations)
    "cancellation frame did not carry CancelHostRequest";
  let host =
    match !host_ref with
    | Some host -> host
    | None -> fail "cancellation component did not expose host effects"
  in
  require
    (Host_effect.Private.pending_count host = 0)
    "cancelled host effect remained pending";
  Driver.shutdown driver
;;

let () = test_host_effect_cancellation ()

let environment_component handlers _graph =
  Environment.value (Driver.Handler.environment handlers)
  |> Bonsai.map ~f:(fun (environment : Environment.snapshot) ->
    Ui.Widget.text
      (Printf.sprintf
         "%.0fx%.0f %s"
         environment.viewport_width
         environment.viewport_height
         environment.locale))
;;

let test_environment_is_dynamic_input () =
  let runtime_epoch = 82L in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver = Driver.create ~runtime_epoch ~time_source environment_component in
  let initial =
    match ok (Driver.step driver ()) with
    | Some frame -> frame
    | None -> fail "environment component did not mount"
  in
  ok (Driver.frame_presented driver ~revision:initial.revision);
  let insets = Protocol.Inbound_event.{ left = 0.; top = 0.; right = 0.; bottom = 0. } in
  let environment =
    Protocol.Inbound_event.
      { viewport_width = 1440.
      ; viewport_height = 900.
      ; device_pixel_ratio = 2.
      ; text_scale = 1.
      ; brightness = Environment_dark
      ; platform = "macos"
      ; locale = "zh-CN"
      ; safe_area = insets
      ; keyboard_insets = insets
      ; accessible_navigation = false
      ; bold_text = false
      ; invert_colors = false
      ; disable_animations = false
      ; reduced_motion = false
      ; high_contrast = false
      ; orientation = Landscape
      ; pointer_kinds = 10
      }
  in
  let batch =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.revision
            ; node_id = 0L
            ; handler_id = 0L
            ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
            ; payload = Environment_changed environment
            }
          ]
      }
  in
  let updated_frame =
    match ok (Driver.step driver ~events:batch ()) with
    | Some frame -> frame
    | None -> fail "environment change did not invalidate Bonsai"
  in
  let updated = decode_frame updated_frame.bytes in
  (match semantic_operations updated with
   | [ Protocol.Wire_frame.Update_props
         { props = Text_props { value = "1440x900 zh-CN" }; _ }
     ] -> ()
   | _ -> fail "environment change did not produce the expected text patch");
  let unchanged =
    Protocol.Inbound_event.
      { batch with
        events =
          [ { sequence = 2L
            ; displayed_revision = updated_frame.revision
            ; node_id = 0L
            ; handler_id = 0L
            ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
            ; payload = Environment_changed environment
            }
          ]
      }
  in
  require
    (ok (Driver.step driver ~events:unchanged ()) = None)
    "unchanged environment unexpectedly produced a frame";
  Driver.shutdown driver
;;

let () = test_environment_is_dynamic_input ()
