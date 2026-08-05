module Backend = Eio_worker_backend_spike

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let await ?(timeout = 2.0) description predicate =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec loop () =
    if predicate ()
    then ()
    else if Unix.gettimeofday () >= deadline
    then fail "timed out waiting for %s" description
    else (
      Unix.sleepf 0.001;
      loop ())
  in
  loop ()
;;

let await_started backend =
  await "the Eio backend to start" (fun () ->
    let diagnostics = Backend.diagnostics backend in
    diagnostics.backend_run_count = 1 && Option.is_some diagnostics.worker_domain_id)
;;

let await_processed backend expected =
  await "all queued requests to be processed" (fun () ->
    (Backend.diagnostics backend).processed_requests = expected)
;;

let await_session backend expected =
  await "the session control transition" (fun () ->
    (Backend.diagnostics backend).attached_session = expected)
;;

let idle_observation_seconds () =
  match Sys.getenv_opt "BONSAI_FLUTTER_EIO_SPIKE_IDLE_SECONDS" with
  | None -> 0.05
  | Some value -> Float.of_string value
;;

let test_notification_before_wait_and_bounded_enqueue () =
  let backend = Backend.create ~request_capacity:2 in
  require
    (Backend.try_enqueue_request backend 1 = `Ok)
    "first pre-start request was not accepted";
  require
    (Backend.try_enqueue_request backend 2 = `Ok)
    "second pre-start request was not accepted";
  require
    (Backend.try_enqueue_request backend 3 = `Full)
    "bounded request mailbox accepted work beyond its capacity";
  require (Backend.start backend = Ok ()) "Eio backend did not start";
  await_started backend;
  await_processed backend [ 1; 2 ];
  let diagnostics = Backend.diagnostics backend in
  require
    (diagnostics.backend_run_count = 1)
    "pre-wait notification started more than one Eio backend";
  Backend.final_shutdown backend;
  require
    ((Backend.diagnostics backend).join_count = 1)
    "final shutdown did not join the Worker Domain exactly once"
;;

let test_cross_domain_wake_idle_and_sequential_sessions () =
  let domain0 = Domain.self () in
  let backend = Backend.create ~request_capacity:4 in
  require (Backend.start backend = Ok ()) "Eio backend did not start";
  await_started backend;
  let started = Backend.diagnostics backend in
  require
    (started.worker_domain_id <> Some domain0)
    "Eio backend ran on domain 0 instead of the spawned Worker Domain";
  await "the coordinator to enter its idle wait" (fun () ->
    (Backend.diagnostics backend).idle_wait_count >= 1);
  let idle_wait_count = (Backend.diagnostics backend).idle_wait_count in
  Unix.sleepf (idle_observation_seconds ());
  require
    ((Backend.diagnostics backend).idle_wait_count = idle_wait_count)
    "idle Eio coordinator appears to be polling or busy-spinning";
  Backend.attach backend 11;
  await_session backend (Some 11);
  require
    (Backend.try_enqueue_request backend 10 = `Ok)
    "first session request was not accepted";
  await_processed backend [ 10 ];
  Backend.detach backend;
  await_session backend None;
  Backend.attach backend 22;
  await_session backend (Some 22);
  require
    (Backend.try_enqueue_request backend 20 = `Ok)
    "second session request was not accepted";
  await_processed backend [ 10; 20 ];
  let reused = Backend.diagnostics backend in
  require
    (reused.backend_run_count = 1)
    "sequential sessions did not reuse one Eio backend loop";
  require
    (reused.worker_domain_id = started.worker_domain_id)
    "sequential sessions did not reuse one Worker Domain";
  require
    (reused.session_attach_count = 2)
    "sequential session controls were not both observed";
  Backend.final_shutdown backend;
  Backend.final_shutdown backend;
  require
    ((Backend.diagnostics backend).join_count = 1)
    "repeated final shutdown joined the Worker Domain more than once"
;;

let test_final_stop_bypasses_full_request_mailbox () =
  let backend = Backend.create ~request_capacity:1 in
  require
    (Backend.try_enqueue_request backend 99 = `Ok)
    "request mailbox could not be filled for stop-priority test";
  require
    (Backend.try_enqueue_request backend 100 = `Full)
    "request mailbox did not report full before stop-priority test";
  Backend.final_shutdown backend;
  let diagnostics = Backend.diagnostics backend in
  require
    (diagnostics.backend_run_count = 0)
    "final shutdown unexpectedly started an unused Eio backend";
  require
    (diagnostics.join_count = 0)
    "final shutdown joined a Worker Domain that was never started"
;;

let () =
  test_notification_before_wait_and_bounded_enqueue ();
  test_cross_domain_wake_idle_and_sequential_sessions ();
  test_final_stop_bypasses_full_request_mailbox ();
  print_endline "Eio Worker backend Phase 0 spike tests passed"
;;
