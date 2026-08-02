let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

type gate =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable started : bool
  ; mutable released : bool
  }

let create_gate () =
  { mutex = Mutex.create ()
  ; condition = Condition.create ()
  ; started = false
  ; released = false
  }
;;

let signal_started gate =
  Mutex.lock gate.mutex;
  gate.started <- true;
  Condition.broadcast gate.condition;
  Mutex.unlock gate.mutex
;;

let await_started gate =
  Mutex.lock gate.mutex;
  while not gate.started do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let release gate =
  Mutex.lock gate.mutex;
  gate.released <- true;
  Condition.broadcast gate.condition;
  Mutex.unlock gate.mutex
;;

let await_release gate =
  Mutex.lock gate.mutex;
  while not gate.released do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let reset_started gate =
  Mutex.lock gate.mutex;
  gate.started <- false;
  Mutex.unlock gate.mutex
;;

type callback_log =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable entries : string list
  }

let create_log () =
  { mutex = Mutex.create (); condition = Condition.create (); entries = [] }
;;

let append_log log entry =
  Mutex.lock log.mutex;
  log.entries <- entry :: log.entries;
  Condition.broadcast log.condition;
  Mutex.unlock log.mutex
;;

let clear_log log =
  Mutex.lock log.mutex;
  log.entries <- [];
  Mutex.unlock log.mutex
;;

let await_log_length log length =
  Mutex.lock log.mutex;
  while List.length log.entries < length do
    Condition.wait log.condition log.mutex
  done;
  let entries = List.rev log.entries in
  Mutex.unlock log.mutex;
  entries
;;

type request =
  | Echo of string
  | Hold
  | Mark_dirty of int
  | Cooperative
  | Emit_push of string
  | Coalesce_push
  | Fail_callback

type config =
  { init_domain_id : Domain.id option Atomic.t
  ; hold_gate : gate
  ; cooperative_gate : gate
  ; log : callback_log
  ; cancel_count : int Atomic.t
  ; shutdown_count : int Atomic.t
  }

type state =
  { config : config
  ; mutable dirty : bool
  }

let service =
  Worker.Service.create
    ~push_topic_count:2
    ~init:(fun ~emit config ->
      Atomic.set config.init_domain_id (Some (Domain.self ()));
      emit ~topic:0 "ready";
      Ok { config; dirty = false })
    ~handle_request:(fun state ~cancelled ~emit request ->
      match request with
      | Echo value -> Ok value, `Idle
      | Hold ->
        signal_started state.config.hold_gate;
        await_release state.config.hold_gate;
        Ok "held", `Idle
      | Mark_dirty value ->
        append_log state.config.log (Printf.sprintf "R%d" value);
        state.dirty <- true;
        Ok (Printf.sprintf "marked-%d" value), `Continue
      | Cooperative ->
        signal_started state.config.cooperative_gate;
        while not (cancelled ()) do
          Domain.cpu_relax ()
        done;
        Ok "cooperative-finished", `Idle
      | Emit_push value ->
        emit ~topic:1 value;
        Ok "pushed", `Idle
      | Coalesce_push ->
        emit ~topic:1 "old";
        emit ~topic:1 "new";
        Ok "coalesced", `Idle
      | Fail_callback -> failwith "intentional service callback failure")
    ~step:(fun state ~cancelled:_ ~emit:_ ->
      if state.dirty
      then (
        append_log state.config.log "S";
        state.dirty <- false;
        `Idle)
      else `Idle)
    ~cancel:(fun state ~request_id:_ -> Atomic.incr state.config.cancel_count)
    ~shutdown:(fun state -> Atomic.incr state.config.shutdown_count)
;;

let create_config () =
  { init_domain_id = Atomic.make None
  ; hold_gate = create_gate ()
  ; cooperative_gate = create_gate ()
  ; log = create_log ()
  ; cancel_count = Atomic.make 0
  ; shutdown_count = Atomic.make 0
  }
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected worker runtime error: %s" error
;;

let drain client = Worker.For_testing.drain_events client ~max_events:64

let response_count events =
  List.fold_left
    (fun count -> function
       | Worker.Response _ -> count + 1
       | Push _ | Terminal _ -> count)
    0
    events
;;

let rec drain_until_responses client expected events =
  let events = events @ drain client in
  if response_count events >= expected
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_responses client expected events)
;;

let rec drain_until_terminal client events =
  let events = events @ drain client in
  if
    List.exists
      (function
        | Worker.Terminal _ -> true
        | Response _ | Push _ -> false)
      events
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_terminal client events)
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "request unexpectedly hit backpressure"
  | Not_ready -> fail "worker client was not ready"
  | Stopping -> fail "worker client was stopping"
;;

let test_request_push_backpressure_fairness_and_cancellation client config =
  Worker.For_testing.await_output client;
  let ready = drain client in
  require
    (List.exists
       (function
         | Worker.Push { topic = 0; payload = "ready"; _ } -> true
         | _ -> false)
       ready)
    "worker init did not emit its unsolicited Ready push";
  let echo_id = accepted (Worker.send client (Echo "hello")) in
  let echo_events = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Response { request_id; outcome = Completed "hello"; _ } ->
           Int64.equal request_id echo_id
         | _ -> false)
       echo_events)
    "domain-0 request did not receive its correlated Worker Domain response";
  ignore (accepted (Worker.send client Hold));
  await_started config.hold_gate;
  for index = 1 to 31 do
    ignore (accepted (Worker.send client (Echo (string_of_int index))))
  done;
  require
    (Worker.send client (Echo "overflow") = Worker.Full)
    "outstanding response capacity did not return Full";
  release config.hold_gate;
  ignore (drain_until_responses client 32 []);
  clear_log config.log;
  for index = 1 to 16 do
    ignore (accepted (Worker.send client (Mark_dirty index)))
  done;
  ignore (drain_until_responses client 16 []);
  let fairness = await_log_length config.log 18 in
  require
    (fairness
     = [ "R1"
       ; "R2"
       ; "R3"
       ; "R4"
       ; "R5"
       ; "R6"
       ; "R7"
       ; "R8"
       ; "S"
       ; "R9"
       ; "R10"
       ; "R11"
       ; "R12"
       ; "R13"
       ; "R14"
       ; "R15"
       ; "R16"
       ; "S"
       ])
    "request/computation fairness exceeded eight requests or starved requests";
  let cooperative_id = accepted (Worker.send client Cooperative) in
  await_started config.cooperative_gate;
  Worker.cancel client ~request_id:cooperative_id;
  let cancellation = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Response { request_id; outcome = Cancelled; _ } ->
           Int64.equal request_id cooperative_id
         | _ -> false)
       cancellation)
    "cooperative cancellation did not produce a typed Cancelled response";
  require (Atomic.get config.cancel_count = 1) "service cancel callback did not run";
  ignore (accepted (Worker.send client (Emit_push "unsolicited")));
  let pushed = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Push { topic = 1; payload = "unsolicited"; _ } -> true
         | _ -> false)
       pushed)
    "Worker Domain unsolicited push did not reach domain 0";
  ignore (accepted (Worker.send client Coalesce_push));
  let coalesced = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Push { topic = 1; payload = "new"; _ } -> true
         | _ -> false)
       coalesced
     && not
          (List.exists
             (function
               | Worker.Push { topic = 1; payload = "old"; _ } -> true
               | _ -> false)
             coalesced))
    "push lane did not retain only the latest value for a topic"
;;

let () =
  let domain0_id = Domain.self () in
  let config = create_config () in
  let first = ok (Worker_runtime.start ~runtime_epoch:101L service config) in
  let first_diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (first_diagnostics.state = Worker_runtime.Attached)
    "first worker session was not Attached";
  require (first_diagnostics.spawn_count = 1) "first worker session did not spawn once";
  require (first_diagnostics.join_count = 0) "ordinary startup joined the Worker Domain";
  require
    (Atomic.get config.init_domain_id <> Some domain0_id)
    "service init ran on OCaml domain 0";
  Worker_runtime.For_testing.await_idle_wait_count 1;
  require
    ((Worker_runtime.For_testing.diagnostics ()).idle_wait_count >= 1)
    "idle Worker Domain did not block on its condition";
  test_request_push_backpressure_fairness_and_cancellation first config;
  let first_domain_id = Option.get first_diagnostics.worker_domain_id in
  let first_generation = Worker.worker_generation first in
  reset_started config.cooperative_gate;
  ignore (accepted (Worker.send first Cooperative));
  await_started config.cooperative_gate;
  for index = 1 to 31 do
    ignore (accepted (Worker.send first (Echo (Printf.sprintf "stop-%d" index))))
  done;
  Worker_runtime.stop first;
  let shutdown_events = drain_until_responses first 32 [] in
  require
    (List.for_all
       (function
         | Worker.Response { outcome = Shutdown; _ } -> true
         | Push _ | Terminal _ -> true
         | Response _ -> false)
       shutdown_events)
    "out-of-band Stop did not complete pending requests as Shutdown";
  let after_destroy = Worker_runtime.For_testing.diagnostics () in
  require (after_destroy.state = Worker_runtime.Idle) "ordinary stop did not return Idle";
  require (after_destroy.spawn_count = 1) "ordinary stop respawned the Worker Domain";
  require (after_destroy.join_count = 0) "ordinary stop joined the Worker Domain";
  require
    (Worker.send first (Echo "stale") = Worker.Stopping)
    "stopped client accepted a stale request";
  let second_config = create_config () in
  let second = ok (Worker_runtime.start ~runtime_epoch:102L service second_config) in
  let second_diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (second_diagnostics.worker_domain_id = Some first_domain_id)
    "sequential recreation did not reuse the same Worker Domain";
  require (second_diagnostics.spawn_count = 1) "sequential recreation spawned again";
  require (second_diagnostics.join_count = 0) "sequential recreation joined the Domain";
  require
    (second_diagnostics.active_sessions = 1 && second_diagnostics.peak_active_sessions = 1)
    "sequential recreation overlapped worker sessions";
  require
    (not (Int64.equal first_generation (Worker.worker_generation second)))
    "sequential worker sessions reused a generation";
  Worker.For_testing.await_output second;
  ignore (drain second);
  ignore (accepted (Worker.send second Fail_callback));
  let failure_events = drain_until_terminal second [] in
  require
    (List.exists
       (function
         | Worker.Response { outcome = Failed error; _ } ->
           Core.String.is_substring
             error
             ~substring:"intentional service callback failure"
         | _ -> false)
       failure_events)
    "caught callback failure did not complete its accepted request";
  require
    (List.exists
       (function
         | Worker.Terminal { error; _ } ->
           Core.String.is_substring
             error
             ~substring:"intentional service callback failure"
         | _ -> false)
       failure_events)
    "caught callback failure did not emit a terminal application event";
  Worker_runtime.For_testing.await_state Worker_runtime.Idle;
  require
    ((Worker_runtime.For_testing.diagnostics ()).spawn_count = 1)
    "caught callback failure made the Worker Domain non-reusable";
  let third_config = create_config () in
  let third = ok (Worker_runtime.start ~runtime_epoch:103L service third_config) in
  require
    ((Worker_runtime.For_testing.diagnostics ()).worker_domain_id = Some first_domain_id)
    "post-failure session did not reuse the Worker Domain";
  Worker_runtime.stop third;
  Worker_runtime.For_testing.crash_worker_loop ();
  Worker_runtime.For_testing.await_state Worker_runtime.Terminal;
  require
    (Result.is_error
       (Worker_runtime.start ~runtime_epoch:104L service (create_config ())))
    "terminal Worker Domain accepted another session";
  Worker_runtime.For_testing.final_shutdown ();
  let stopped = Worker_runtime.For_testing.diagnostics () in
  require (stopped.state = Worker_runtime.Stopped) "final shutdown did not stop subsystem";
  require (stopped.spawn_count = 1) "final shutdown changed spawn count";
  require (stopped.join_count = 1) "final shutdown did not join exactly once";
  Worker_runtime.For_testing.final_shutdown ();
  require
    ((Worker_runtime.For_testing.diagnostics ()).join_count = 1)
    "repeated final shutdown joined again";
  require
    (Result.is_error
       (Worker_runtime.start ~runtime_epoch:105L service (create_config ())))
    "worker-backed start after Stopped succeeded"
;;
