module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected driver error: %s" (Driver.error_to_string error)
;;

let require_error = function
  | Error _ -> ()
  | Ok _ -> fail "expected an error"
;;

let span_ms milliseconds = Core.Time_ns.Span.of_ms (Float.of_int milliseconds)
let at_ms milliseconds = Core.Time_ns.add Core.Time_ns.epoch (span_ms milliseconds)

let decode_frame frame =
  match Protocol.Binary_codec.decode frame.Driver.bytes with
  | Ok wire -> wire
  | Error error -> fail "frame did not decode: %s" error.message
;;

let semantic_operations frame =
  List.filter
    (function
      | Protocol.Wire_frame.Runtime_stats _ -> false
      | _ -> true)
    frame.Protocol.Wire_frame.operations
;;

let text_values frame =
  semantic_operations (decode_frame frame)
  |> List.filter_map (function
    | Protocol.Wire_frame.Create_node { props = Text_props { value; _ }; _ }
    | Update_props { props = Text_props { value; _ }; _ } -> Some value
    | _ -> None)
;;

let find_button_binding frame =
  semantic_operations (decode_frame frame)
  |> List.find_map (function
    | Protocol.Wire_frame.Create_node
        { node_id; kind = Button; event_bindings = [ { event_tag; handler_id } ]; _ } ->
      Some (node_id, event_tag, handler_id)
    | _ -> None)
  |> function
  | Some binding -> binding
  | None -> fail "wire frame did not contain one Button event binding"
;;

let require_text result expected =
  match result.Driver.frame with
  | None -> fail "expected a wire frame containing %S" expected
  | Some frame ->
    require
      (List.exists (String.equal expected) (text_values frame))
      (Printf.sprintf "wire frame did not contain %S" expected)
;;

let create ?trace ?(runtime_epoch = 41L) component =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  time_source, Driver.create ?trace ~runtime_epoch ~time_source component
;;

let pump driver monotonic_now_ns = ok (Driver.pump driver ~monotonic_now_ns ())

let present driver result monotonic_now_ns =
  ok
    (Driver.presentation_succeeded
       driver
       ~presentation_id:result.Driver.presentation_id
       ~renderer_revision:result.renderer_revision
       ~monotonic_now_ns)
;;

let reject driver result reason =
  ok
    (Driver.presentation_rejected
       driver
       ~presentation_id:result.Driver.presentation_id
       ~renderer_revision:result.renderer_revision
       ~reason)
;;

let static_component _handlers _graph = Bonsai.return (Ui.Widget.text "static")

let clock_component _handlers graph =
  let deadline = Bonsai.return (at_ms 50) in
  let before_or_after = Bonsai.Clock.at deadline graph in
  let approx_now = Bonsai.Clock.approx_now ~tick_every:(span_ms 10) graph in
  let exact_now = Bonsai.Clock.Expert.now graph in
  let clock_values =
    Bonsai.map2 approx_now exact_now ~f:(fun approx_now exact_now ->
      approx_now, exact_now)
  in
  Bonsai.map2 before_or_after clock_values ~f:(fun before_or_after (approx, exact) ->
    let phase =
      match before_or_after with
      | Bonsai.Clock.Before_or_after.Before -> "before"
      | After -> "after"
    in
    Ui.Widget.text
      (Printf.sprintf
         "%s approx=%Ld exact=%Ld"
         phase
         (Core.Time_ns.to_int63_ns_since_epoch approx |> Core.Int63.to_int64)
         (Core.Time_ns.to_int63_ns_since_epoch exact |> Core.Int63.to_int64)))
;;

let test_clock_at_approx_and_expert_now () =
  let _, driver = create clock_component in
  let initial = pump driver 0L in
  require_text initial "before approx=0 exact=0";
  present driver initial 0L;
  let before = pump driver 49_000_000L in
  require_text before "before approx=49000000 exact=49000000";
  present driver before 49_000_000L;
  let due = pump driver 50_000_000L in
  require_text due "after approx=50000000 exact=50000000";
  present driver due 50_000_000L;
  Driver.shutdown driver
;;

let timer_component
      ~time_source
      ~clock_sleep_fired
      ~clock_until_fired
      ~source_sleep_fired
      ~source_until_fired
      _handlers
      graph
  =
  let clock_sleep = Bonsai.Clock.sleep graph in
  let clock_until = Bonsai.Clock.until graph in
  let on_activate =
    Bonsai.map2 clock_sleep clock_until ~f:(fun clock_sleep clock_until ->
      let record_after pending_effect fired =
        Bonsai.Effect.bind pending_effect ~f:(fun () ->
          Bonsai.Effect.of_thunk (fun () -> Stdlib.incr fired))
      in
      Bonsai.Effect.Many
        [ record_after (clock_sleep (span_ms 50)) clock_sleep_fired
        ; record_after (clock_until (at_ms 50)) clock_until_fired
        ; record_after
            (Bonsai.Time_source.sleep time_source (span_ms 50))
            source_sleep_fired
        ; record_after
            (Bonsai.Time_source.until time_source (at_ms 50))
            source_until_fired
        ])
  in
  Bonsai.Edge.lifecycle ~on_activate graph;
  Bonsai.return (Ui.Widget.text "timers")
;;

let test_sleep_and_until_without_input () =
  let clock_sleep_fired = ref 0 in
  let clock_until_fired = ref 0 in
  let source_sleep_fired = ref 0 in
  let source_until_fired = ref 0 in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create
      ~runtime_epoch:42L
      ~time_source
      (timer_component
         ~time_source
         ~clock_sleep_fired
         ~clock_until_fired
         ~source_sleep_fired
         ~source_until_fired)
  in
  let initial = pump driver 0L in
  present driver initial 0L;
  let before = pump driver 49_999_999L in
  require
    ([ !clock_sleep_fired; !clock_until_fired; !source_sleep_fired; !source_until_fired ]
     = [ 0; 0; 0; 0 ])
    "a timer fired before its deadline";
  present driver before 49_999_999L;
  let due = pump driver 50_000_000L in
  require
    ([ !clock_sleep_fired; !clock_until_fired; !source_sleep_fired; !source_until_fired ]
     = [ 1; 1; 1; 1 ])
    "sleep and until effects did not fire on the first due pump";
  present driver due 50_000_000L;
  Driver.shutdown driver
;;

let every_component ~ticks _handlers graph =
  Bonsai.Clock.every
    ~when_to_start_next_effect:`Every_multiple_of_period_non_blocking
    ~trigger_on_activate:true
    (Bonsai.return (span_ms 10))
    (Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr ticks)))
    graph;
  Bonsai.return (Ui.Widget.text "every")
;;

let test_every_catches_up_after_large_jump () =
  let ticks = ref 0 in
  let _, driver = create ~runtime_epoch:43L (every_component ~ticks) in
  let initial = pump driver 0L in
  present driver initial 0L;
  let armed = pump driver 0L in
  present driver armed 0L;
  require
    (!ticks = 1)
    (Printf.sprintf "Clock.every did not run its activation tick (ticks=%d)" !ticks);
  let jumped = pump driver 55_000_000L in
  require
    (!ticks = 2)
    (Printf.sprintf
       "Clock.every did not run exactly once on the overdue pump (ticks=%d)"
       !ticks);
  present driver jumped 55_000_000L;
  let follow_up = pump driver 56_000_000L in
  present driver follow_up 56_000_000L;
  require
    (!ticks > 2)
    (Printf.sprintf "Clock.every did not continue overdue catch-up (ticks=%d)" !ticks);
  Driver.shutdown driver
;;

let after_display_component ~after_displays ~wait_completions _handlers graph =
  let phase, set_phase = Bonsai.state' ~equal:Int.equal 0 graph in
  let wait_after_display = Bonsai.Edge.wait_after_display graph in
  let on_activate =
    Bonsai.map wait_after_display ~f:(fun wait_after_display ->
      Bonsai.Effect.bind wait_after_display ~f:(fun () ->
        Bonsai.Effect.of_thunk (fun () -> Stdlib.incr wait_completions)))
  in
  let after_display =
    Bonsai.map set_phase ~f:(fun set_phase ->
      Bonsai.Effect.Many
        [ Bonsai.Effect.of_thunk (fun () -> Stdlib.incr after_displays)
        ; set_phase (fun current -> Int.min 1 (current + 1))
        ])
  in
  Bonsai.Edge.lifecycle ~on_activate ~after_display graph;
  Bonsai.map phase ~f:(fun phase -> Ui.Widget.text (Printf.sprintf "phase-%d" phase))
;;

let test_after_display_and_wait_follow_up_without_input () =
  let after_displays = ref 0 in
  let wait_completions = ref 0 in
  let _, driver =
    create ~runtime_epoch:44L (after_display_component ~after_displays ~wait_completions)
  in
  let initial = pump driver 0L in
  require_text initial "phase-0";
  require
    (!after_displays = 0 && !wait_completions = 0)
    "lifecycle ran before presentation";
  present driver initial 1_000_000L;
  require
    (!after_displays = 1 && !wait_completions = 1)
    "presentation did not run after-display and wait_after_display exactly once";
  let follow_up = pump driver 2_000_000L in
  require_text follow_up "phase-1";
  present driver follow_up 3_000_000L;
  require
    (!after_displays = 2)
    "persistent after-display did not run for the second token";
  require (!wait_completions = 1) "wait_after_display completed more than once";
  Driver.shutdown driver
;;

let relative_timer_after_display_component ~timer_fired _handlers graph =
  let phase, set_phase = Bonsai.state' ~equal:Int.equal 0 graph in
  let sleep = Bonsai.Clock.sleep graph in
  let after_display =
    Bonsai.map2
      phase
      (Bonsai.map2 set_phase sleep ~f:(fun set_phase sleep -> set_phase, sleep))
      ~f:(fun phase (set_phase, sleep) ->
        if phase = 0
        then
          Bonsai.Effect.Many
            [ set_phase (fun _ -> 1)
            ; Bonsai.Effect.bind
                (sleep (span_ms 50))
                ~f:(fun () -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr timer_fired))
            ]
        else Bonsai.Effect.Ignore)
  in
  Bonsai.Edge.lifecycle ~after_display graph;
  Bonsai.return (Ui.Widget.text "relative-timer")
;;

let test_retained_token_starts_relative_timer_at_resume_acknowledgment () =
  let timer_fired = ref 0 in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create
      ~runtime_epoch:45L
      ~time_source
      (relative_timer_after_display_component ~timer_fired)
  in
  let initial = pump driver 0L in
  present driver initial 1_000_000_000L;
  let immediately_after_resume = pump driver 1_000_000_001L in
  require (!timer_fired = 0) "relative timer used stale pre-suspension pump time";
  present driver immediately_after_resume 1_000_000_001L;
  let before_deadline = pump driver 1_049_999_999L in
  require (!timer_fired = 0) "resume-relative timer fired before its deadline";
  present driver before_deadline 1_049_999_999L;
  let due = pump driver 1_050_000_000L in
  require (!timer_fired = 1) "resume-relative timer did not fire at its deadline";
  present driver due 1_050_000_000L;
  Driver.shutdown driver
;;

let lifecycle_only_component ~activations ~deactivations ~after_displays _handlers graph =
  Bonsai.Edge.lifecycle
    ~on_activate:
      (Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr activations)))
    ~on_deactivate:
      (Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr deactivations)))
    ~after_display:
      (Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr after_displays)))
    graph;
  Bonsai.return (Ui.Widget.text "unchanged")
;;

let test_no_diff_tokens_and_lifecycle_only_presentations () =
  let activations = ref 0 in
  let deactivations = ref 0 in
  let after_displays = ref 0 in
  let _, driver =
    create
      ~runtime_epoch:46L
      (lifecycle_only_component ~activations ~deactivations ~after_displays)
  in
  let initial = pump driver 0L in
  let stable_revision = initial.renderer_revision in
  present driver initial 0L;
  require (!activations = 1) "initial activation did not run";
  let stable_handler_frames = Driver.For_testing.retained_handler_frame_count driver in
  let previous_id = ref initial.presentation_id in
  for index = 1 to 100 do
    let now = Int64.of_int index in
    let result = pump driver now in
    require (Option.is_none result.frame) "no-diff pump emitted a wire frame";
    require
      (Int64.compare result.presentation_id !previous_id > 0)
      "presentation identifiers did not increase";
    require
      (Int64.equal result.renderer_revision stable_revision)
      "no-diff pump advanced renderer revision";
    present driver result now;
    previous_id := result.presentation_id
  done;
  require (!after_displays = 101) "persistent after-display did not run once per token";
  require
    (Driver.For_testing.retained_handler_frame_count driver = stable_handler_frames)
    "no-diff pumps installed redundant handler frames";
  require (!deactivations = 0) "stable lifecycle deactivated unexpectedly";
  Driver.shutdown driver
;;

let test_exact_token_barrier_duplicate_future_and_unsolicited_acknowledgments () =
  let _, driver = create ~runtime_epoch:47L static_component in
  let initial = pump driver 0L in
  require_error (Driver.pump driver ~monotonic_now_ns:1L ());
  require_error
    (Driver.presentation_succeeded
       driver
       ~presentation_id:(Int64.succ initial.presentation_id)
       ~renderer_revision:initial.renderer_revision
       ~monotonic_now_ns:1L);
  require_error
    (Driver.presentation_succeeded
       driver
       ~presentation_id:initial.presentation_id
       ~renderer_revision:(Int64.succ initial.renderer_revision)
       ~monotonic_now_ns:1L);
  present driver initial 1L;
  require_error
    (Driver.presentation_succeeded
       driver
       ~presentation_id:initial.presentation_id
       ~renderer_revision:initial.renderer_revision
       ~monotonic_now_ns:1L);
  require_error
    (Driver.presentation_rejected
       driver
       ~presentation_id:initial.presentation_id
       ~renderer_revision:initial.renderer_revision
       ~reason:Driver.Decode_failed);
  Driver.shutdown driver
;;

let test_rejection_burns_revision_skips_lifecycle_and_forces_snapshot () =
  let activations = ref 0 in
  let deactivations = ref 0 in
  let after_displays = ref 0 in
  let _, driver =
    create
      ~runtime_epoch:48L
      (lifecycle_only_component ~activations ~deactivations ~after_displays)
  in
  let rejected = pump driver 0L in
  reject driver rejected Driver.Frame_validation_failed;
  require (!activations = 0 && !after_displays = 0) "rejection ran presentation lifecycle";
  let recovery = pump driver 1L in
  require
    (Int64.compare recovery.renderer_revision rejected.renderer_revision > 0)
    "rejected renderer revision was reused";
  (match recovery.frame with
   | None -> fail "rejection recovery did not emit a full snapshot"
   | Some frame ->
     require
       (Runtime.Frame_patch.kind frame.frame_patch = Full_snapshot)
       "rejection recovery was not a full snapshot");
  present driver recovery 1L;
  require
    (!activations = 1 && !after_displays = 1)
    "recovery presentation did not run lifecycle exactly once";
  Driver.shutdown driver
;;

let test_negative_and_decreasing_clock_are_non_mutating () =
  let _, driver = create ~runtime_epoch:49L static_component in
  require_error (Driver.pump driver ~monotonic_now_ns:(-1L) ());
  let first = pump driver 10L in
  present driver first 20L;
  require_error (Driver.pump driver ~monotonic_now_ns:19L ());
  require_error
    (Driver.presentation_succeeded
       driver
       ~presentation_id:(Int64.succ first.presentation_id)
       ~renderer_revision:first.renderer_revision
       ~monotonic_now_ns:19L);
  let next = pump driver 21L in
  require
    (Int64.equal next.presentation_id (Int64.succ first.presentation_id))
    "invalid clock input mutated the presentation sequence";
  present driver next 21L;
  Driver.shutdown driver
;;

let atomic_input_component ~handled ~timer_fired ~time_source handlers graph =
  let callback =
    Driver.Handler.create
      handlers
      ~equal:(fun () () -> true)
      (Bonsai.return ())
      ~f:(fun () _ -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr handled))
  in
  let on_activate =
    Bonsai.return
      (Bonsai.Effect.bind
         (Bonsai.Time_source.sleep time_source (span_ms 50))
         ~f:(fun () -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr timer_fired)))
  in
  Bonsai.Edge.lifecycle ~on_activate graph;
  Bonsai.map callback ~f:(fun callback ->
    Ui.Widget.button ~on_press:callback ~child:(Ui.Widget.text "atomic") ())
;;

let test_invalid_input_is_atomic_and_does_not_starve_due_timer () =
  let runtime_epoch = 50L in
  let handled = ref 0 in
  let timer_fired = ref 0 in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create
      ~runtime_epoch
      ~time_source
      (atomic_input_component ~handled ~timer_fired ~time_source)
  in
  let initial = pump driver 0L in
  let initial_frame = Option.get initial.frame in
  let node_id, event_tag, handler_id = find_button_binding initial_frame in
  present driver initial 0L;
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.renderer_revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ; { sequence = 2L
            ; displayed_revision = initial.renderer_revision
            ; node_id
            ; handler_id = Int64.succ handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let result = ok (Driver.pump driver ~monotonic_now_ns:50_000_000L ~events ()) in
  require (Option.is_some result.recoverable_error) "invalid batch lost its diagnostic";
  require (!handled = 0) "invalid batch executed a valid prefix";
  require (!timer_fired = 1) "invalid batch prevented a due timer from firing";
  present driver result 50_000_000L;
  Driver.shutdown driver
;;

let handler_identity_component handlers graph =
  let enabled, toggle = Bonsai.toggle ~default_model:false graph in
  let dependencies =
    Bonsai.map2 enabled toggle ~f:(fun enabled toggle -> enabled, toggle)
  in
  let callback =
    Driver.Handler.create
      handlers
      ~equal:(fun (left, _) (right, _) -> Bool.equal left right)
      dependencies
      ~f:(fun (_, toggle) _ -> toggle)
  in
  Bonsai.map callback ~f:(fun callback ->
    Ui.Widget.button ~on_press:callback ~child:(Ui.Widget.text "identity") ())
;;

let test_changed_handler_identity_emits_binding_update () =
  let runtime_epoch = 51L in
  let _, driver = create ~runtime_epoch handler_identity_component in
  let initial = pump driver 0L in
  let frame = Option.get initial.frame in
  let node_id, event_tag, handler_id = find_button_binding frame in
  present driver initial 0L;
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.renderer_revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let updated = ok (Driver.pump driver ~monotonic_now_ns:1L ~events ()) in
  let operations =
    match updated.frame with
    | None -> fail "changed handler identity emitted no wire frame"
    | Some frame -> semantic_operations (decode_frame frame)
  in
  require
    (List.exists
       (function
         | Protocol.Wire_frame.Update_event_bindings _ -> true
         | _ -> false)
       operations)
    "changed handler identity did not emit UpdateEventBindings";
  present driver updated 1L;
  Driver.shutdown driver
;;

let host_effect_component handlers _graph =
  let host_effects = Driver.Handler.host_effects handlers in
  let callback =
    Driver.Handler.create
      handlers
      ~equal:(fun () () -> true)
      (Bonsai.return ())
      ~f:(fun () _ ->
        Bonsai.Effect.map (Host_effect.Clipboard.read host_effects ()) ~f:(fun _ -> ()))
  in
  Bonsai.map callback ~f:(fun callback ->
    Ui.Widget.button ~on_press:callback ~child:(Ui.Widget.text "host") ())
;;

let host_request_ids result =
  match result.Driver.frame with
  | None -> []
  | Some frame ->
    semantic_operations (decode_frame frame)
    |> List.filter_map (function
      | Protocol.Wire_frame.Host_request { request_id; _ } -> Some request_id
      | _ -> None)
;;

let test_host_operation_replays_after_rejection_and_commits_once () =
  let runtime_epoch = 52L in
  let _, driver = create ~runtime_epoch host_effect_component in
  let initial = pump driver 0L in
  let node_id, event_tag, handler_id = find_button_binding (Option.get initial.frame) in
  present driver initial 0L;
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = 1L
            ; displayed_revision = initial.renderer_revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let candidate = ok (Driver.pump driver ~monotonic_now_ns:1L ~events ()) in
  let request_id =
    match host_request_ids candidate with
    | [ request_id ] -> request_id
    | _ -> fail "host request candidate did not contain exactly one operation"
  in
  reject driver candidate Driver.Decode_failed;
  let recovery = pump driver 2L in
  require
    (host_request_ids recovery = [ request_id ])
    "recovery did not replay the exact host-operation prefix";
  present driver recovery 2L;
  let later = pump driver 3L in
  require
    (host_request_ids later = [])
    "successfully presented host operation was emitted again";
  present driver later 3L;
  Driver.shutdown driver
;;

let before_display_fixed_point_component ~observed handlers graph =
  let shown, set_shown = Bonsai.state' ~equal:Bool.equal false graph in
  let reveal = Bonsai.map set_shown ~f:(fun set_shown -> set_shown (fun _ -> true)) in
  Bonsai.Edge.lifecycle ~before_display:reveal graph;
  let dynamic_lifecycle =
    Bonsai.enum
      (module Core.Bool)
      ~match_:shown
      ~with_:(fun shown graph ->
        if shown
        then
          Bonsai.Edge.lifecycle
            ~before_display:
              (Bonsai.return
                 (Bonsai.Effect.of_thunk (fun () -> observed := 1 :: !observed)))
            graph;
        Bonsai.return ())
      graph
  in
  ignore handlers;
  Bonsai.map dynamic_lifecycle ~f:(fun () -> Ui.Widget.text "before-display")
;;

let test_lifecycle_before_display_reaches_fixed_point () =
  let observed = ref [] in
  let _, driver =
    create ~runtime_epoch:53L (before_display_fixed_point_component ~observed)
  in
  let initial =
    match Driver.pump driver ~monotonic_now_ns:0L () with
    | Ok result -> result
    | Error error ->
      fail "initial fixed-point pump failed: %s" (Driver.error_to_string error)
  in
  require
    (List.mem 1 !observed)
    "before-display action did not trigger dependent before-display work in one pump";
  present driver initial 0L;
  Driver.shutdown driver
;;

let wait_before_display_component ~time_source ~observed _handlers graph =
  let shown, set_shown = Bonsai.state' ~equal:Bool.equal false graph in
  let on_activate =
    Bonsai.map set_shown ~f:(fun set_shown ->
      Bonsai.Effect.bind
        (Bonsai.Time_source.wait_before_display time_source)
        ~f:(fun () -> set_shown (fun _ -> true)))
  in
  Bonsai.Edge.lifecycle ~on_activate graph;
  let dynamic_lifecycle =
    Bonsai.enum
      (module Core.Bool)
      ~match_:shown
      ~with_:(fun shown graph ->
        if shown
        then
          Bonsai.Edge.lifecycle
            ~before_display:
              (Bonsai.return
                 (Bonsai.Effect.of_thunk (fun () -> observed := 1 :: !observed)))
            graph;
        Bonsai.return ())
      graph
  in
  Bonsai.map dynamic_lifecycle ~f:(fun () -> Ui.Widget.text "wait-before-display")
;;

let test_time_source_wait_before_display_defers_new_lifecycle_work () =
  let observed = ref [] in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    Driver.create
      ~runtime_epoch:54L
      ~time_source
      (wait_before_display_component ~time_source ~observed)
  in
  let initial = pump driver 0L in
  present driver initial 0L;
  observed := [];
  let trigger_waiter = pump driver 1L in
  require
    (not (List.mem 1 !observed))
    "time-source waiter ran newly installed lifecycle work in the same pump";
  present driver trigger_waiter 1L;
  let follow_up = pump driver 2L in
  require
    (List.mem 1 !observed)
    (Printf.sprintf
       "next pump did not run lifecycle work created by wait_before_display (%s)"
       (String.concat "," (List.map string_of_int !observed)));
  present driver follow_up 2L;
  Driver.shutdown driver
;;

let lifecycle_replacement_component ~input_var ~first ~replacement _handlers graph =
  let inputs = Bonsai.Expert.Var.value input_var in
  let dynamic_lifecycle =
    Bonsai.assoc
      (module Core.Int)
      inputs
      ~f:(fun _key callback_version graph ->
        let on_deactivate =
          Bonsai.map callback_version ~f:(function
            | 0 -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr first)
            | _ -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr replacement))
        in
        Bonsai.Edge.lifecycle ~on_deactivate graph;
        Bonsai.return ())
      graph
  in
  Bonsai.map dynamic_lifecycle ~f:(fun _ -> Ui.Widget.text "lifecycle")
;;

let test_same_path_lifecycle_replacement_runs_replacement_on_removal () =
  let first = ref 0 in
  let replacement = ref 0 in
  let input_var = Bonsai.Expert.Var.create (Core.Map.singleton (module Core.Int) 0 0) in
  let _, driver =
    create
      ~runtime_epoch:55L
      (lifecycle_replacement_component ~input_var ~first ~replacement)
  in
  let initial = pump driver 0L in
  require_text initial "lifecycle";
  present driver initial 0L;
  Bonsai.Expert.Var.set input_var (Core.Map.singleton (module Core.Int) 0 1);
  let replace = pump driver 1L in
  present driver replace 1L;
  Bonsai.Expert.Var.set input_var (Core.Map.empty (module Core.Int));
  let remove = pump driver 2L in
  present driver remove 2L;
  let settle = pump driver 3L in
  present driver settle 3L;
  require
    (!first = 0)
    (Printf.sprintf
       "superseded lifecycle callback ran on removal (first=%d replacement=%d)"
       !first
       !replacement);
  require
    (!replacement = 1)
    (Printf.sprintf
       "replacement lifecycle callback did not run on removal (first=%d replacement=%d)"
       !first
       !replacement);
  Driver.shutdown driver
;;

let test_presentation_and_renderer_sequence_overflow_are_fatal () =
  let _, presentation_driver = create ~runtime_epoch:56L static_component in
  Driver.For_testing.set_next_presentation_id presentation_driver Int64.max_int;
  let final_id = pump presentation_driver 0L in
  present presentation_driver final_id 0L;
  require_error (Driver.pump presentation_driver ~monotonic_now_ns:1L ());
  Driver.shutdown presentation_driver;
  let _, renderer_driver = create ~runtime_epoch:57L static_component in
  Driver.For_testing.set_next_renderer_revision renderer_driver Int64.max_int;
  require_error (Driver.pump renderer_driver ~monotonic_now_ns:0L ());
  Driver.shutdown renderer_driver
;;

let run name test =
  try test () with
  | exn ->
    let backtrace = Printexc.get_backtrace () in
    fail
      "frame-driven pump test %S failed: %s\n%s"
      name
      (Printexc.to_string exn)
      backtrace
;;

let () =
  Printexc.record_backtrace true;
  run "Clock.at, approx_now, and Expert.now" test_clock_at_approx_and_expert_now;
  run "sleep and until without input" test_sleep_and_until_without_input;
  run
    "after-display and wait_after_display follow-up"
    test_after_display_and_wait_follow_up_without_input;
  run
    "presentation-relative timer after suspension"
    test_retained_token_starts_relative_timer_at_resume_acknowledgment;
  run
    "no-diff tokens and lifecycle-only presentations"
    test_no_diff_tokens_and_lifecycle_only_presentations;
  run
    "exact token barrier"
    test_exact_token_barrier_duplicate_future_and_unsolicited_acknowledgments;
  run
    "rejection recovery"
    test_rejection_burns_revision_skips_lifecycle_and_forces_snapshot;
  run "monotonic clock validation" test_negative_and_decreasing_clock_are_non_mutating;
  run
    "atomic invalid input and due timer"
    test_invalid_input_is_atomic_and_does_not_starve_due_timer;
  run "handler identity update" test_changed_handler_identity_emits_binding_update;
  run
    "host operation rejection replay"
    test_host_operation_replays_after_rejection_and_commits_once;
  run "before-display fixed point" test_lifecycle_before_display_reaches_fixed_point;
  run
    "time-source before-display staging"
    test_time_source_wait_before_display_defers_new_lifecycle_work;
  run
    "same-path lifecycle replacement"
    test_same_path_lifecycle_replacement_runs_replacement_on_removal;
  run "sequence overflow" test_presentation_and_renderer_sequence_overflow_are_fatal;
  run "Clock.every catches up after a large jump" test_every_catches_up_after_large_jump
;;
