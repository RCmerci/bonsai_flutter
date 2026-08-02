module Protocol = Bonsai_flutter_protocol
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let require_substring output substring message =
  require (Core.String.is_substring output ~substring) message
;;

let require_no_substring output substring message =
  require (not (Core.String.is_substring output ~substring)) message
;;

let set_u16_le bytes offset value =
  Bytes.set_uint8 bytes offset (value land 0xff);
  Bytes.set_uint8 bytes (offset + 1) ((value lsr 8) land 0xff)
;;

let set_u32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.set_uint8 bytes (offset + index) ((value lsr (index * 8)) land 0xff)
  done
;;

let startup_config ~policy ~entrypoint =
  let entrypoint = Bytes.of_string entrypoint in
  let config = Bytes.create (20 + Bytes.length entrypoint) in
  Bytes.blit_string "BFR1" 0 config 0 4;
  set_u16_le config 4 1;
  set_u16_le config 6 0;
  Bytes.set_uint8 config 8 policy;
  Bytes.fill config 9 3 '\000';
  set_u32_le config 12 (Bytes.length entrypoint);
  set_u32_le config 16 0;
  Bytes.blit entrypoint 0 config 20 (Bytes.length entrypoint);
  config
;;

let capture_stderr run =
  let path = Filename.temp_file "bonsai_flutter_native_trace" ".log" in
  let saved_stderr = Unix.dup Unix.stderr in
  let output = open_out_bin path in
  flush stderr;
  Unix.dup2 (Unix.descr_of_out_channel output) Unix.stderr;
  Fun.protect
    ~finally:(fun () ->
      flush stderr;
      Unix.dup2 saved_stderr Unix.stderr;
      Unix.close saved_stderr;
      close_out_noerr output)
    run;
  let input = open_in_bin path in
  let contents =
    Fun.protect
      ~finally:(fun () ->
        close_in_noerr input;
        Sys.remove path)
      (fun () -> really_input_string input (in_channel_length input))
  in
  contents
;;

let counter handlers graph =
  let count, increment = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment_handler =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      increment
      ~f:(fun increment -> function
      | Ui.Event.Payload.Unit -> increment (fun value -> value + 1)
      | _ -> increment Fun.id)
  in
  Bonsai.Cont.map2 count increment_handler ~f:(fun count increment_handler ->
    Ui.Widget.column
      [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
      ; Ui.Widget.button
          ~on_press:increment_handler
          ~child:(Ui.Widget.text "Increment")
          ()
      ])
;;

let trace_fixture _handlers _graph =
  Bonsai.Cont.return
    (Ui.Widget.column
       [ Ui.Widget.text "First item"
         |> Ui.Widget.with_test_id (Ui.Test_id.string "trace-item-1")
       ; Ui.Widget.text "Second item"
         |> Ui.Widget.with_test_id (Ui.Test_id.string "trace-item-2")
       ]
     |> Ui.Widget.with_test_id (Ui.Test_id.string "trace-root"))
;;

let broken_component _handlers _graph = failwith "intentional startup failure"

let () =
  Entrypoint.For_testing.clear ();
  Entrypoint.register ~name:"counter" (App.create counter);
  Entrypoint.register ~name:"broken" (App.create broken_component);
  let created = Native_backend.create (Bytes.of_string "counter") in
  require (created.status = Native_backend.Ok) "registered entrypoint did not create";
  require (Int64.compare created.handle 0L > 0) "native handle must be positive";
  let initial = Native_backend.pump created.handle 0L Bytes.empty in
  require (initial.status = Native_backend.Ok) "initial native pump failed";
  require (Bytes.length initial.bytes > 0) "initial native pump returned no frame";
  require (initial.presentation_id = 1L) "initial presentation ID must be one";
  require (initial.revision = 1L) "initial native revision must be one";
  (match Protocol.Binary_codec.decode initial.bytes with
   | Ok { kind = Full_snapshot; _ } -> ()
   | Ok _ -> fail "initial native frame was not a full snapshot"
   | Error error -> fail "initial native frame did not decode: %s" error.message);
  let presented =
    Native_backend.presentation_succeeded
      created.handle
      initial.presentation_id
      initial.revision
      0L
  in
  require (presented.status = Native_backend.Ok) "frame presentation failed";
  Native_backend.destroy created.handle;
  Native_backend.destroy created.handle;
  let after_destroy = Native_backend.pump created.handle 1L Bytes.empty in
  require
    (after_destroy.status = Native_backend.Fatal_error)
    "destroyed native handle accepted a pump";
  require
    (String.length after_destroy.error > 0)
    "destroyed native handle returned no diagnostic";
  require (after_destroy.error_code = 9) "destroyed handle error was not structured";
  for _iteration = 1 to 100 do
    let runtime = Native_backend.create (Bytes.of_string "counter") in
    require (runtime.status = Native_backend.Ok) "soak runtime did not create";
    ignore (Native_backend.pump runtime.handle 0L Bytes.empty);
    Native_backend.destroy runtime.handle
  done;
  require
    (Native_backend.For_testing.runtime_count () = 0)
    "runtime destroy retained native backend handles";
  Native_backend.For_testing.reset_observations ();
  let fresh_config = startup_config ~policy:0 ~entrypoint:"counter" in
  let replace_config = startup_config ~policy:1 ~entrypoint:"counter" in
  let first = Native_backend.create fresh_config in
  require (first.status = Native_backend.Ok) "Fresh runtime did not create";
  let before_rejected_create = Native_backend.For_testing.observations () in
  let duplicate = Native_backend.create fresh_config in
  require
    (duplicate.status = Native_backend.Fatal_error)
    "second Fresh runtime was accepted";
  require_substring
    duplicate.error
    "Runtime_already_active"
    "second Fresh failure did not identify the occupied singleton";
  let after_rejected_create = Native_backend.For_testing.observations () in
  require
    (after_rejected_create.driver_creations = before_rejected_create.driver_creations)
    "second Fresh create allocated another Driver";
  require
    (after_rejected_create.active_drivers = 1)
    "second Fresh create changed the active Driver count";
  require
    (after_rejected_create.peak_active_drivers = 1)
    "second Fresh create overlapped Drivers";
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Active)
    "singleton slot did not remain Active after rejected Fresh create";
  Native_backend.For_testing.clear_state_history ();
  let replacement = Native_backend.create replace_config in
  require (replacement.status = Native_backend.Ok) "replacement runtime did not create";
  require
    (Native_backend.For_testing.state_history ()
     = [ Native_backend.For_testing.Destroying
       ; Native_backend.For_testing.Empty
       ; Native_backend.For_testing.Creating
       ; Native_backend.For_testing.Active
       ])
    "replacement did not follow Destroying -> Empty -> Creating -> Active";
  let replacement_observations = Native_backend.For_testing.observations () in
  require
    (replacement_observations.driver_shutdowns = 1)
    "replacement did not shut down the old Driver";
  require
    (replacement_observations.active_drivers = 1)
    "replacement did not leave exactly one active Driver";
  require
    (replacement_observations.peak_active_drivers = 1)
    "replacement overlapped old and new Drivers";
  let stale_pump = Native_backend.pump first.handle 0L Bytes.empty in
  require
    (stale_pump.status = Native_backend.Fatal_error)
    "tombstoned runtime accepted a stale pump";
  let stale_presentation = Native_backend.presentation_succeeded first.handle 1L 1L 0L in
  require
    (stale_presentation.status = Native_backend.Fatal_error)
    "tombstoned runtime accepted a stale presentation";
  Native_backend.destroy first.handle;
  let live_after_stale_destroy = Native_backend.pump replacement.handle 0L Bytes.empty in
  require
    (live_after_stale_destroy.status = Native_backend.Ok)
    "stale destroy affected the replacement runtime";
  Native_backend.destroy replacement.handle;
  let legacy_first = Native_backend.create fresh_config in
  require
    (legacy_first.status = Native_backend.Ok)
    "Fresh runtime before legacy create failed";
  let legacy_replacement = Native_backend.create (Bytes.of_string "counter") in
  require
    (legacy_replacement.status = Native_backend.Ok)
    "legacy raw configuration did not use compatibility replacement";
  let stale_legacy = Native_backend.pump legacy_first.handle 0L Bytes.empty in
  require
    (stale_legacy.status = Native_backend.Fatal_error)
    "legacy replacement did not tombstone the old handle";
  Native_backend.destroy legacy_replacement.handle;
  Native_backend.For_testing.clear_state_history ();
  let failed = Native_backend.create (startup_config ~policy:0 ~entrypoint:"broken") in
  require (failed.status = Native_backend.Fatal_error) "failed startup was accepted";
  require_substring
    failed.error
    "intentional startup failure"
    "failed startup lost its original error";
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Empty)
    "failed startup did not restore the singleton slot to Empty";
  require
    (Native_backend.For_testing.state_history ()
     = [ Native_backend.For_testing.Creating; Native_backend.For_testing.Empty ])
    "failed startup did not roll Creating back to Empty";
  let after_failure = Native_backend.create fresh_config in
  require
    (after_failure.status = Native_backend.Ok)
    "failed startup left the singleton slot unusable";
  Native_backend.destroy after_failure.handle;
  let missing = Native_backend.create (Bytes.of_string "missing") in
  require (missing.status = Native_backend.Fatal_error) "unknown entrypoint was accepted";
  let trace_message message = Printf.eprintf "[Trace Fixture][ocaml]%s\n%!" message in
  Entrypoint.register
    ~name:"trace-fixture"
    (App.create ~name:"Trace Fixture" ~trace:trace_message trace_fixture);
  let trace =
    capture_stderr (fun () ->
      let runtime = Native_backend.create (Bytes.of_string "trace-fixture") in
      require (runtime.status = Native_backend.Ok) "traced runtime did not create";
      let initial = Native_backend.pump runtime.handle 0L Bytes.empty in
      require (initial.status = Native_backend.Ok) "traced initial pump failed";
      let presented =
        Native_backend.presentation_succeeded
          runtime.handle
          initial.presentation_id
          initial.revision
          0L
      in
      require (presented.status = Native_backend.Ok) "traced presentation failed";
      let idle = Native_backend.pump runtime.handle 1L Bytes.empty in
      require (idle.status = Native_backend.Ok) "traced idle pump failed";
      require (Bytes.length idle.bytes = 0) "traced idle pump emitted a frame";
      let idle_presented =
        Native_backend.presentation_succeeded
          runtime.handle
          idle.presentation_id
          idle.revision
          1L
      in
      require
        (idle_presented.status = Native_backend.Ok)
        "traced idle presentation failed";
      let resync =
        Protocol.Inbound_event.
          { runtime_epoch = runtime.handle
          ; events =
              [ { sequence = 1L
                ; displayed_revision = initial.revision
                ; node_id = 0L
                ; handler_id = 0L
                ; event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
                ; payload = Unit
                }
              ]
          }
      in
      let encoded_resync =
        match Protocol.Event_batch_codec.encode resync with
        | Ok bytes -> bytes
        | Error error -> fail "resync batch did not encode: %s" error.message
      in
      let resynced = Native_backend.pump runtime.handle 1L encoded_resync in
      require (resynced.status = Native_backend.Ok) "traced resync failed";
      Native_backend.destroy runtime.handle)
  in
  require_substring
    trace
    "[Trace Fixture][ocaml][widget-diff] targetRevision=1 kind=full_snapshot"
    "trace did not include the logical widget tree";
  require_substring trace "Column" "trace did not include the widget root";
  require_substring trace "test_id=trace-root" "trace omitted the fixture root";
  require_substring trace "test_id=trace-item-1" "trace omitted the first fixture item";
  require_substring
    trace
    "[Trace Fixture][ocaml][outbound-frame]"
    "trace did not include the outbound frame";
  require_substring
    trace
    "kind=full_snapshot baseRevision=0 targetRevision=1"
    "trace omitted outbound frame revisions";
  require_substring
    trace
    "[Trace Fixture][ocaml][presentation-ack] presentationId=1 revision=1"
    "trace did not include the presentation acknowledgment";
  require_no_substring
    trace
    "[Trace Fixture][ocaml][outbound-no-frame]"
    "trace included an idle no-frame message";
  require_no_substring
    trace
    "[Trace Fixture][ocaml][presentation-ack] presentationId=2 revision=1"
    "trace included an idle presentation acknowledgment";
  require_substring
    trace
    "[Trace Fixture][ocaml][inbound-event-batch]"
    "trace did not include the inbound event batch";
  require_substring
    trace
    "sequence=1 displayedRevision=1 node=0 handler=0 tag=resync_requested payload=unit"
    "trace omitted inbound event metadata";
  require
    (Native_backend.For_testing.runtime_count () = 0)
    "traced runtime destroy retained native backend handles";
  Native_backend.For_testing.final_shutdown ();
  Native_backend.For_testing.final_shutdown ();
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Finalized)
    "final shutdown did not enter the absorbing Finalized state";
  let stopped = Native_backend.create fresh_config in
  require (stopped.status = Native_backend.Fatal_error) "create after Finalized succeeded";
  require_substring
    stopped.error
    "Runtime_stopped"
    "create after Finalized returned the wrong error"
;;
