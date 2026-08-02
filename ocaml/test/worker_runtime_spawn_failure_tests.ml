module ID = Bonsai_flutter_spec.Id

let require condition message = if not condition then failwith message

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~init:(fun ~emit:_ () -> Ok ())
    ~handle_request:(fun () ~cancelled:_ ~emit:_ request -> Ok request, `Idle)
    ~step:(fun () ~cancelled:_ ~emit:_ -> `Idle)
    ~cancel:(fun () ~request_id:_ -> ())
    ~shutdown:(fun () -> ())
;;

let () =
  Worker_runtime.For_testing.fail_next_spawn (Failure "injected Domain.spawn failure");
  let started =
    Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 1L) service ()
  in
  require (Result.is_error started) "injected Domain.spawn failure started on domain 0";
  let diagnostics = Worker_runtime.For_testing.diagnostics () in
  require (diagnostics.state = Worker_runtime.Terminal) "spawn failure was not terminal";
  require (diagnostics.spawn_count = 0) "failed spawn incremented spawn count";
  require (diagnostics.join_count = 0) "failed spawn joined a nonexistent Domain";
  Worker_runtime.For_testing.final_shutdown ();
  let stopped = Worker_runtime.For_testing.diagnostics () in
  require (stopped.state = Worker_runtime.Stopped) "spawn failure did not finalize";
  require (stopped.join_count = 0) "spawn failure final shutdown joined"
;;
