let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

type gate =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable started : bool
  ; mutable released : bool
  }

let gate =
  { mutex = Mutex.create ()
  ; condition = Condition.create ()
  ; started = false
  ; released = false
  }
;;

let hold () =
  Mutex.lock gate.mutex;
  gate.started <- true;
  Condition.broadcast gate.condition;
  while not gate.released do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let await_hold () =
  Mutex.lock gate.mutex;
  while not gate.started do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let release_hold () =
  Mutex.lock gate.mutex;
  gate.released <- true;
  Condition.broadcast gate.condition;
  Mutex.unlock gate.mutex
;;

type request =
  | Hold
  | Echo

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~init:(fun ~emit:_ () -> Ok ())
    ~handle_request:(fun () ~cancelled:_ ~emit:_ -> function
       | Hold ->
         hold ();
         Ok "held", `Idle
       | Echo -> Ok "echo", `Idle)
    ~step:(fun () ~cancelled:_ ~emit:_ -> `Idle)
    ~cancel:(fun () ~request_id:_ -> failwith "intentional cancel callback failure")
    ~shutdown:(fun () -> ())
;;

let benign_service =
  Worker.Service.create
    ~push_topic_count:1
    ~init:(fun ~emit:_ () -> Ok ())
    ~handle_request:(fun () ~cancelled:_ ~emit:_ request -> Ok request, `Idle)
    ~step:(fun () ~cancelled:_ ~emit:_ -> `Idle)
    ~cancel:(fun () ~request_id:_ -> ())
    ~shutdown:(fun () -> ())
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "request unexpectedly hit backpressure"
  | Not_ready -> fail "worker client was not ready"
  | Stopping -> fail "worker client was stopping"
;;

let rec drain_until_terminal client events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
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

let () =
  let client =
    match Worker_runtime.start ~runtime_epoch:501L service () with
    | Ok client -> client
    | Error error -> fail "unexpected worker startup failure: %s" error
  in
  ignore (accepted (Worker.send client Hold));
  await_hold ();
  let cancelled_request_id = accepted (Worker.send client Echo) in
  Worker.cancel client ~request_id:cancelled_request_id;
  release_hold ();
  let events = drain_until_terminal client [] in
  require
    (List.exists
       (function
         | Worker.Response { request_id; outcome = Failed error; _ } ->
           Int64.equal request_id cancelled_request_id
           && Core.String.is_substring
                error
                ~substring:"intentional cancel callback failure"
         | _ -> false)
       events)
    "cancel callback failure did not complete the accepted request";
  require
    ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
    "cancel callback failure escaped the session boundary";
  let replacement =
    match Worker_runtime.start ~runtime_epoch:502L benign_service () with
    | Ok client -> client
    | Error error -> fail "cancel callback failure prevented Domain reuse: %s" error
  in
  Worker_runtime.stop replacement;
  Worker_runtime.For_testing.final_shutdown ()
;;
