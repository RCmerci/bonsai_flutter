module ID = Bonsai_flutter_spec.Id

type state =
  | Not_started
  | Idle
  | Attached
  | Stopping
  | Stopped
  | Terminal

type diagnostics =
  { state : state
  ; spawn_count : int
  ; join_count : int
  ; worker_domain_id : ID.Worker.domain_id option
  ; active_sessions : int
  ; peak_active_sessions : int
  ; idle_wait_count : int
  }

type startup_reply =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable result : (unit, string) result option
  }

type attachment =
  { startup : Worker.Private.packed_startup
  ; reply : startup_reply
  }

type control =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable state : state
  ; mutable pending_attachment : attachment option
  ; mutable current_client : Worker.Private.packed_client option
  ; mutable final_stop : bool
  ; mutable crash_requested : bool
  ; mutable domain_handle : unit Domain.t option
  ; mutable worker_domain_id : ID.Worker.domain_id option
  ; mutable spawn_count : int
  ; mutable join_count : int
  ; mutable active_sessions : int
  ; mutable peak_active_sessions : int
  ; mutable idle_wait_count : int
  ; mutable next_generation : ID.Worker.generation
  ; mutable fail_next_spawn : exn option
  }

let control =
  { mutex = Mutex.create ()
  ; condition = Condition.create ()
  ; state = Not_started
  ; pending_attachment = None
  ; current_client = None
  ; final_stop = false
  ; crash_requested = false
  ; domain_handle = None
  ; worker_domain_id = None
  ; spawn_count = 0
  ; join_count = 0
  ; active_sessions = 0
  ; peak_active_sessions = 0
  ; idle_wait_count = 0
  ; next_generation = ID.Worker.Generation.one
  ; fail_next_spawn = None
  }
;;

let with_control f =
  Mutex.lock control.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock control.mutex) f
;;

let signal_reply (reply : startup_reply) result =
  Mutex.lock reply.mutex;
  if Option.is_none reply.result
  then (
    reply.result <- Some result;
    Condition.broadcast reply.condition);
  Mutex.unlock reply.mutex
;;

let await_reply (reply : startup_reply) =
  Mutex.lock reply.mutex;
  while Option.is_none reply.result do
    Condition.wait reply.condition reply.mutex
  done;
  let result = Option.get reply.result in
  Mutex.unlock reply.mutex;
  result
;;

let set_terminal_from_loop exception_ =
  let error =
    match exception_ with
    | Failure message | Invalid_argument message -> message
    | _ -> Printexc.to_string exception_
  in
  with_control (fun () ->
    Option.iter
      (fun client -> Worker.Private.fail_unrecoverable client error)
      control.current_client;
    Option.iter
      (fun attachment -> signal_reply attachment.reply (Error error))
      control.pending_attachment;
    control.pending_attachment <- None;
    control.current_client <- None;
    control.active_sessions <- 0;
    control.state <- Terminal;
    Condition.broadcast control.condition)
;;

let worker_loop () =
  with_control (fun () ->
    control.worker_domain_id <- Some (ID.Worker.Domain_id.of_domain_id (Domain.self ()));
    Condition.broadcast control.condition);
  let rec await_action () =
    Mutex.lock control.mutex;
    while
      Option.is_none control.pending_attachment
      && (not control.final_stop)
      && not control.crash_requested
    do
      Condition.wait control.condition control.mutex
    done;
    if control.crash_requested
    then (
      control.crash_requested <- false;
      Mutex.unlock control.mutex;
      failwith "Injected uncaught Worker Domain loop failure")
    else if control.final_stop
    then (
      Mutex.unlock control.mutex;
      ())
    else (
      let attachment = Option.get control.pending_attachment in
      control.pending_attachment <- None;
      Mutex.unlock control.mutex;
      let result =
        Worker.Private.run_session
          attachment.startup
          ~on_startup:(signal_reply attachment.reply)
          ~on_idle_wait:(fun () ->
            with_control (fun () ->
              control.idle_wait_count <- control.idle_wait_count + 1;
              Condition.broadcast control.condition))
      in
      with_control (fun () ->
        control.current_client <- None;
        control.active_sessions <- 0;
        if control.final_stop then control.state <- Stopping else control.state <- Idle;
        Condition.broadcast control.condition);
      (match result with
       | Worker.Private.Session_startup_failed error ->
         signal_reply attachment.reply (Error error)
       | Session_stopped | Session_callback_failed _ -> ());
      await_action ())
  in
  await_action ()
;;

let worker_entrypoint () =
  try worker_loop () with
  | exception_ -> set_terminal_from_loop exception_
;;

let ensure_started () =
  let action =
    with_control (fun () ->
      match control.state with
      | Not_started ->
        let injected_failure = control.fail_next_spawn in
        control.fail_next_spawn <- None;
        `Spawn injected_failure
      | Idle -> `Ready
      | Attached | Stopping -> `Busy
      | Stopped -> `Error "Worker Domain subsystem is stopped"
      | Terminal -> `Error "Worker Domain subsystem is terminal")
  in
  match action with
  | `Ready -> Ok ()
  | `Busy -> Error "Worker Domain session is already attached"
  | `Error error -> Error error
  | `Spawn injected_failure ->
    (try
       Option.iter raise injected_failure;
       let domain = Domain.spawn worker_entrypoint in
       with_control (fun () ->
         control.domain_handle <- Some domain;
         control.spawn_count <- control.spawn_count + 1;
         control.state <- Idle;
         Condition.broadcast control.condition);
       Ok ()
     with
     | exception_ ->
       let error =
         match exception_ with
         | Failure message | Invalid_argument message -> message
         | _ -> Printexc.to_string exception_
       in
       with_control (fun () ->
         control.state <- Terminal;
         Condition.broadcast control.condition);
       Error ("Failed to spawn OCaml Worker Domain: " ^ error))
;;

let fresh_generation () =
  with_control (fun () ->
    let generation = control.next_generation in
    if ID.Worker.Generation.equal generation ID.Worker.Generation.max_value
    then failwith "Worker generation counter exhausted"
    else control.next_generation <- ID.Worker.Generation.succ generation;
    generation)
;;

let start ~runtime_epoch service config =
  match ensure_started () with
  | Error _ as error -> error
  | Ok () ->
    let generation = fresh_generation () in
    let client, startup =
      Worker.Private.prepare ~runtime_epoch ~worker_generation:generation service config
    in
    let packed_client = Worker.Private.pack_client client in
    let reply =
      { mutex = Mutex.create (); condition = Condition.create (); result = None }
    in
    let attached =
      with_control (fun () ->
        match control.state with
        | Idle ->
          control.state <- Attached;
          control.current_client <- Some packed_client;
          control.pending_attachment <- Some { startup; reply };
          control.active_sessions <- 1;
          control.peak_active_sessions <- Int.max control.peak_active_sessions 1;
          Condition.broadcast control.condition;
          Ok ()
        | Attached | Stopping -> Error "Worker Domain session is already attached"
        | Not_started -> Error "Worker Domain did not start"
        | Stopped -> Error "Worker Domain subsystem is stopped"
        | Terminal -> Error "Worker Domain subsystem is terminal")
    in
    (match attached with
     | Error _ as error -> error
     | Ok () ->
       (match await_reply reply with
        | Ok () -> Ok client
        | Error error ->
          with_control (fun () ->
            while control.state = Attached do
              Condition.wait control.condition control.mutex
            done);
          Error error))
;;

let stop client =
  Worker.Private.request_stop client;
  Worker.Private.await_stopped client;
  with_control (fun () ->
    while control.state = Attached do
      Condition.wait control.condition control.mutex
    done)
;;

let diagnostics () =
  with_control (fun () ->
    { state = control.state
    ; spawn_count = control.spawn_count
    ; join_count = control.join_count
    ; worker_domain_id = control.worker_domain_id
    ; active_sessions = control.active_sessions
    ; peak_active_sessions = control.peak_active_sessions
    ; idle_wait_count = control.idle_wait_count
    })
;;

let await_state state =
  with_control (fun () ->
    while control.state <> state do
      Condition.wait control.condition control.mutex
    done)
;;

let await_idle_wait_count count =
  with_control (fun () ->
    while control.idle_wait_count < count do
      Condition.wait control.condition control.mutex
    done)
;;

let final_shutdown () =
  let handle, client =
    with_control (fun () ->
      match control.state with
      | Stopped -> None, None
      | Not_started ->
        control.state <- Stopped;
        Condition.broadcast control.condition;
        None, None
      | Idle | Terminal ->
        control.final_stop <- true;
        control.state <- Stopping;
        Condition.broadcast control.condition;
        control.domain_handle, None
      | Attached ->
        control.final_stop <- true;
        control.state <- Stopping;
        let client = control.current_client in
        Option.iter Worker.Private.request_stop_packed client;
        Condition.broadcast control.condition;
        control.domain_handle, client
      | Stopping -> control.domain_handle, control.current_client)
  in
  Option.iter Worker.Private.await_stopped_packed client;
  Option.iter
    (fun domain ->
       let should_join = with_control (fun () -> control.join_count = 0) in
       if should_join
       then (
         Domain.join domain;
         with_control (fun () -> control.join_count <- 1)))
    handle;
  with_control (fun () ->
    control.current_client <- None;
    control.pending_attachment <- None;
    control.active_sessions <- 0;
    control.state <- Stopped;
    Condition.broadcast control.condition)
;;

let crash_worker_loop () =
  with_control (fun () ->
    match control.state with
    | Idle ->
      control.crash_requested <- true;
      Condition.broadcast control.condition
    | Not_started | Attached | Stopping | Stopped | Terminal ->
      invalid_arg "Worker_runtime.For_testing.crash_worker_loop requires Idle")
;;

let fail_next_spawn exception_ =
  with_control (fun () ->
    match control.state with
    | Not_started -> control.fail_next_spawn <- Some exception_
    | Idle | Attached | Stopping | Stopped | Terminal ->
      invalid_arg "Worker_runtime.For_testing.fail_next_spawn requires Not_started")
;;

module For_testing = struct
  let diagnostics = diagnostics
  let await_state = await_state
  let await_idle_wait_count = await_idle_wait_count
  let final_shutdown = final_shutdown
  let crash_worker_loop = crash_worker_loop
  let fail_next_spawn = fail_next_spawn
end
