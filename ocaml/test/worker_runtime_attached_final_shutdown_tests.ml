module ID = Bonsai_flutter_spec.Id

let require condition message = if not condition then failwith message
let shutdown_count = Atomic.make 0

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~init:(fun ~emit:_ () -> Ok ())
    ~handle_request:(fun () ~cancelled:_ ~emit:_ request -> Ok request, `Idle)
    ~step:(fun () ~cancelled:_ ~emit:_ -> `Idle)
    ~cancel:(fun () ~request_id:_ -> ())
    ~shutdown:(fun () -> Atomic.incr shutdown_count)
;;

let () =
  let client =
    match
      Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 11L) service ()
    with
    | Ok client -> client
    | Error error -> failwith error
  in
  ignore (Worker.send client "pending");
  Worker_runtime.For_testing.final_shutdown ();
  let diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (diagnostics.state = Worker_runtime.Stopped)
    "attached final shutdown did not stop";
  require (diagnostics.spawn_count = 1) "attached final shutdown changed spawn count";
  require (diagnostics.join_count = 1) "attached final shutdown did not join once";
  require (diagnostics.active_sessions = 0) "attached final shutdown retained session";
  require
    (Atomic.get shutdown_count = 1)
    "attached final shutdown skipped service cleanup";
  Worker_runtime.For_testing.final_shutdown ();
  require
    ((Worker_runtime.For_testing.diagnostics ()).join_count = 1)
    "repeated attached final shutdown joined twice"
;;
