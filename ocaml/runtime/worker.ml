module ID = Bonsai_flutter_spec.Id

type computation =
  [ `Idle
  | `Continue
  ]

type 'response outcome =
  | Completed of 'response
  | Failed of string
  | Cancelled
  | Shutdown

type ('response, 'push) event =
  | Response of
      { runtime_epoch : ID.Runtime.epoch
      ; worker_generation : ID.Worker.generation
      ; request_id : ID.Worker.request_id
      ; outcome : 'response outcome
      }
  | Push of
      { runtime_epoch : ID.Runtime.epoch
      ; worker_generation : ID.Worker.generation
      ; push_sequence : ID.Worker.push_sequence
      ; topic : ID.Worker.push_topic
      ; payload : 'push
      }
  | Terminal of
      { runtime_epoch : ID.Runtime.epoch
      ; worker_generation : ID.Worker.generation
      ; error : string
      }

type send_result =
  | Accepted of ID.Worker.request_id
  | Full
  | Not_ready
  | Stopping

type client_status =
  | Starting_status
  | Ready_status
  | Stopping_status
  | Stopped_status
  | Terminal_status

let status_code = function
  | Starting_status -> 0
  | Ready_status -> 1
  | Stopping_status -> 2
  | Stopped_status -> 3
  | Terminal_status -> 4
;;

let status_of_code = function
  | 0 -> Starting_status
  | 1 -> Ready_status
  | 2 -> Stopping_status
  | 3 -> Stopped_status
  | 4 -> Terminal_status
  | _ -> failwith "Worker client status invariant failed"
;;

module Service = struct
  type ('config, 'request, 'response, 'push) t =
    | Service :
        { push_topic_count : int
        ; init :
            emit:(topic:ID.Worker.push_topic -> 'push -> unit)
            -> 'config
            -> ('state, string) result
        ; handle_request :
            'state
            -> cancelled:(unit -> bool)
            -> emit:(topic:ID.Worker.push_topic -> 'push -> unit)
            -> 'request
            -> ('response, string) result * computation
        ; step :
            'state
            -> cancelled:(unit -> bool)
            -> emit:(topic:ID.Worker.push_topic -> 'push -> unit)
            -> computation
        ; cancel : 'state -> request_id:ID.Worker.request_id -> unit
        ; shutdown : 'state -> unit
        }
        -> ('config, 'request, 'response, 'push) t

  let create ~push_topic_count ~init ~handle_request ~step ~cancel ~shutdown =
    if push_topic_count <= 0
    then invalid_arg "Worker.Service.create: push_topic_count must be positive";
    Service { push_topic_count; init; handle_request; step; cancel; shutdown }
  ;;
end

type 'request request_envelope =
  { runtime_epoch : ID.Runtime.epoch
  ; worker_generation : ID.Worker.generation
  ; request_id : ID.Worker.request_id
  ; payload : 'request
  }

type ('request, 'response, 'push) client =
  { runtime_epoch : ID.Runtime.epoch
  ; worker_generation : ID.Worker.generation
  ; requests : 'request request_envelope Bounded_mailbox.Fifo.t
  ; responses : ('response, 'push) event Bounded_mailbox.Reserved.t
  ; pushes : ('response, 'push) event Bounded_mailbox.Coalesced.t
  ; injected : ('response, 'push) event Bounded_mailbox.Fifo.t
  ; status : int Atomic.t
  ; stop_requested : bool Atomic.t
  ; cancellation_mutex : Mutex.t
  ; cancellations : (ID.Worker.request_id, unit) Hashtbl.t
  ; output_mutex : Mutex.t
  ; output_condition : Condition.t
  ; pending_output_count : int Atomic.t
  ; stopped_mutex : Mutex.t
  ; stopped_condition : Condition.t
  ; mutable stopped : bool
  ; mutable next_request_id : ID.Worker.request_id
  ; pending_requests : (ID.Worker.request_id, unit) Hashtbl.t
  ; mutable subscribers : (('response, 'push) event -> unit Bonsai.Effect.t) list
  ; mutable last_push_sequence : ID.Worker.push_sequence
  ; mutable terminal_event : ('response, 'push) event option
  }

type packed_startup =
  | Packed_startup :
      { service : ('config, 'request, 'response, 'push) Service.t
      ; config : 'config
      ; client : ('request, 'response, 'push) client
      }
      -> packed_startup

type packed_client =
  | Packed_client : ('request, 'response, 'push) client -> packed_client

let request_capacity = 32
let response_capacity = 32
let injected_capacity = 1024

let prepare ~runtime_epoch ~worker_generation service config =
  let (Service.Service { push_topic_count; _ }) = service in
  let client =
    { runtime_epoch
    ; worker_generation
    ; requests = Bounded_mailbox.Fifo.create ~capacity:request_capacity
    ; responses = Bounded_mailbox.Reserved.create ~capacity:response_capacity
    ; pushes = Bounded_mailbox.Coalesced.create ~capacity:push_topic_count
    ; injected = Bounded_mailbox.Fifo.create ~capacity:injected_capacity
    ; status = Atomic.make (status_code Starting_status)
    ; stop_requested = Atomic.make false
    ; cancellation_mutex = Mutex.create ()
    ; cancellations = Hashtbl.create request_capacity
    ; output_mutex = Mutex.create ()
    ; output_condition = Condition.create ()
    ; pending_output_count = Atomic.make 0
    ; stopped_mutex = Mutex.create ()
    ; stopped_condition = Condition.create ()
    ; stopped = false
    ; next_request_id = ID.Worker.Request_id.one
    ; pending_requests = Hashtbl.create request_capacity
    ; subscribers = []
    ; last_push_sequence = ID.Worker.Push_sequence.zero
    ; terminal_event = None
    }
  in
  client, Packed_startup { service; config; client }
;;

let runtime_epoch client = client.runtime_epoch
let worker_generation client = client.worker_generation

let with_output_lock client f =
  Mutex.lock client.output_mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock client.output_mutex) f
;;

let increment_pending_output_locked client =
  ignore (Atomic.fetch_and_add client.pending_output_count 1 : int);
  Condition.broadcast client.output_condition
;;

let decrement_pending_output_locked client count =
  if count > 0
  then ignore (Atomic.fetch_and_add client.pending_output_count (-count) : int)
;;

let next_request_id client =
  let request_id = client.next_request_id in
  if ID.Worker.Request_id.equal request_id ID.Worker.Request_id.max_value
  then failwith "Worker request ID counter exhausted"
  else client.next_request_id <- ID.Worker.Request_id.succ request_id;
  request_id
;;

let send client payload =
  match status_of_code (Atomic.get client.status) with
  | Starting_status -> Not_ready
  | Stopping_status | Stopped_status | Terminal_status -> Stopping
  | Ready_status ->
    if not (Bounded_mailbox.Reserved.reserve client.responses)
    then Full
    else (
      let request_id = next_request_id client in
      let request =
        { runtime_epoch = client.runtime_epoch
        ; worker_generation = client.worker_generation
        ; request_id
        ; payload
        }
      in
      match Bounded_mailbox.Fifo.try_push client.requests request with
      | `Ok ->
        Hashtbl.add client.pending_requests request_id ();
        Accepted request_id
      | `Full ->
        Bounded_mailbox.Reserved.cancel client.responses;
        Full
      | `Closed ->
        Bounded_mailbox.Reserved.cancel client.responses;
        Stopping)
;;

let with_cancellations client f =
  Mutex.lock client.cancellation_mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock client.cancellation_mutex) f
;;

let cancel client ~request_id =
  if Hashtbl.mem client.pending_requests request_id
  then
    with_cancellations client (fun () ->
      Hashtbl.replace client.cancellations request_id ())
;;

let is_cancelled client request_id =
  Atomic.get client.stop_requested
  || with_cancellations client (fun () -> Hashtbl.mem client.cancellations request_id)
;;

let clear_cancelled client request_id =
  with_cancellations client (fun () -> Hashtbl.remove client.cancellations request_id)
;;

let on_event client handler = client.subscribers <- client.subscribers @ [ handler ]

let publish_response client request_id outcome =
  with_output_lock client (fun () ->
    Bounded_mailbox.Reserved.publish
      client.responses
      (Response
         { runtime_epoch = client.runtime_epoch
         ; worker_generation = client.worker_generation
         ; request_id
         ; outcome
         });
    increment_pending_output_locked client)
;;

let set_terminal_event client error =
  with_output_lock client (fun () ->
    if Option.is_none client.terminal_event
    then (
      client.terminal_event
      <- Some
           (Terminal
              { runtime_epoch = client.runtime_epoch
              ; worker_generation = client.worker_generation
              ; error
              });
      increment_pending_output_locked client))
;;

let mark_stopped client status =
  Atomic.set client.status (status_code status);
  Mutex.lock client.stopped_mutex;
  client.stopped <- true;
  Condition.broadcast client.stopped_condition;
  Mutex.unlock client.stopped_mutex;
  with_output_lock client (fun () -> Condition.broadcast client.output_condition)
;;

let request_stop client =
  let status = status_of_code (Atomic.get client.status) in
  (match status with
   | Starting_status | Ready_status ->
     Atomic.set client.status (status_code Stopping_status)
   | Stopping_status | Stopped_status | Terminal_status -> ());
  Atomic.set client.stop_requested true;
  Bounded_mailbox.Fifo.close client.requests
;;

let await_stopped client =
  Mutex.lock client.stopped_mutex;
  while not client.stopped do
    Condition.wait client.stopped_condition client.stopped_mutex
  done;
  Mutex.unlock client.stopped_mutex
;;

let request_stop_packed (Packed_client client) = request_stop client
let await_stopped_packed (Packed_client client) = await_stopped client
let pack_client client = Packed_client client

let fail_unrecoverable (Packed_client client) error =
  request_stop client;
  set_terminal_event client error;
  mark_stopped client Terminal_status
;;

let exception_message exception_ =
  match exception_ with
  | Failure message | Invalid_argument message -> message
  | _ -> Printexc.to_string exception_
;;

type run_result =
  | Session_stopped
  | Session_startup_failed of string
  | Session_callback_failed of string

let run_session (Packed_startup { service; config; client }) ~on_startup ~on_idle_wait =
  let (Service.Service callbacks) = service in
  let next_push_sequence = ref ID.Worker.Push_sequence.one in
  let emit ~topic payload =
    let topic_index = ID.Worker.Push_topic.to_int topic in
    if topic_index < 0 || topic_index >= callbacks.push_topic_count
    then failwith "Worker push topic invariant failed";
    let push_sequence = !next_push_sequence in
    if ID.Worker.Push_sequence.equal push_sequence ID.Worker.Push_sequence.max_value
    then failwith "Worker push sequence exhausted"
    else next_push_sequence := ID.Worker.Push_sequence.succ push_sequence;
    let event =
      Push
        { runtime_epoch = client.runtime_epoch
        ; worker_generation = client.worker_generation
        ; push_sequence
        ; topic
        ; payload
        }
    in
    with_output_lock client (fun () ->
      match Bounded_mailbox.Coalesced.push client.pushes ~topic:topic_index event with
      | `Added -> increment_pending_output_locked client
      | `Replaced -> Condition.broadcast client.output_condition
      | `Full -> failwith "Worker push mailbox invariant failed")
  in
  let shutdown_state state =
    try callbacks.shutdown state with
    | exception_ ->
      raise (Failure ("Worker shutdown callback failed: " ^ exception_message exception_))
  in
  let drain_shutdown_requests state =
    let requests = Bounded_mailbox.Fifo.drain client.requests ~max_items:max_int in
    List.iter
      (fun request ->
         (try callbacks.cancel state ~request_id:request.request_id with
          | _ -> ());
         clear_cancelled client request.request_id;
         publish_response client request.request_id Shutdown)
      requests
  in
  let fail_session state ?current ?(shutdown_attempted = false) error =
    Option.iter
      (fun request ->
         clear_cancelled client request.request_id;
         publish_response client request.request_id (Failed error))
      current;
    drain_shutdown_requests state;
    let error =
      if shutdown_attempted
      then error
      else (
        try
          shutdown_state state;
          error
        with
        | exception_ -> error ^ "\n" ^ exception_message exception_)
    in
    set_terminal_event client error;
    mark_stopped client Terminal_status;
    Session_callback_failed error
  in
  let initialized =
    try callbacks.init ~emit config with
    | exception_ -> Error (exception_message exception_)
  in
  match initialized with
  | Error error ->
    on_startup (Error error);
    mark_stopped client Stopped_status;
    Session_startup_failed error
  | Ok state ->
    Atomic.set client.status (status_code Ready_status);
    on_startup (Ok ());
    let rec loop consecutive_requests dirty pending_request =
      if Atomic.get client.stop_requested
      then (
        Option.iter
          (fun request ->
             (try callbacks.cancel state ~request_id:request.request_id with
              | _ -> ());
             clear_cancelled client request.request_id;
             publish_response client request.request_id Shutdown)
          pending_request;
        drain_shutdown_requests state;
        try
          shutdown_state state;
          mark_stopped client Stopped_status;
          Session_stopped
        with
        | exception_ ->
          fail_session state ~shutdown_attempted:true (exception_message exception_))
      else if dirty && consecutive_requests >= 8
      then (
        try
          let computation =
            callbacks.step
              state
              ~cancelled:(fun () -> Atomic.get client.stop_requested)
              ~emit
          in
          loop 0 (computation = `Continue) None
        with
        | exception_ -> fail_session state (exception_message exception_))
      else (
        let request =
          match pending_request with
          | Some request -> Some request
          | None -> Bounded_mailbox.Fifo.pop client.requests
        in
        match request with
        | Some request ->
          if
            (not (ID.Runtime.Epoch.equal request.runtime_epoch client.runtime_epoch))
            || not
                 (ID.Worker.Generation.equal
                    request.worker_generation
                    client.worker_generation)
          then failwith "Worker request metadata invariant failed";
          if is_cancelled client request.request_id
          then (
            try
              callbacks.cancel state ~request_id:request.request_id;
              let outcome =
                if Atomic.get client.stop_requested then Shutdown else Cancelled
              in
              clear_cancelled client request.request_id;
              publish_response client request.request_id outcome;
              loop (consecutive_requests + 1) dirty None
            with
            | exception_ ->
              fail_session state ~current:request (exception_message exception_))
          else (
            try
              let response, computation =
                callbacks.handle_request
                  state
                  ~cancelled:(fun () -> is_cancelled client request.request_id)
                  ~emit
                  request.payload
              in
              let cancelled = is_cancelled client request.request_id in
              let outcome =
                if Atomic.get client.stop_requested
                then Shutdown
                else if cancelled
                then Cancelled
                else (
                  match response with
                  | Ok response -> Completed response
                  | Error error -> Failed error)
              in
              if cancelled then callbacks.cancel state ~request_id:request.request_id;
              clear_cancelled client request.request_id;
              publish_response client request.request_id outcome;
              loop (consecutive_requests + 1) (dirty || computation = `Continue) None
            with
            | exception_ ->
              fail_session state ~current:request (exception_message exception_))
        | None ->
          if dirty
          then (
            try
              let computation =
                callbacks.step
                  state
                  ~cancelled:(fun () -> Atomic.get client.stop_requested)
                  ~emit
              in
              loop 0 (computation = `Continue) None
            with
            | exception_ -> fail_session state (exception_message exception_))
          else (
            on_idle_wait ();
            match Bounded_mailbox.Fifo.wait_pop client.requests with
            | Some request -> loop 0 false (Some request)
            | None -> loop 0 false None))
    in
    loop 0 false None
;;

let take_terminal_locked client =
  let terminal = client.terminal_event in
  client.terminal_event <- None;
  terminal
;;

let raw_events client ~max_events =
  if max_events < 0 then invalid_arg "Worker drain max_events must be nonnegative";
  with_output_lock client (fun () ->
    let responses =
      Bounded_mailbox.Reserved.drain client.responses ~max_items:max_events
    in
    let remaining = max_events - List.length responses in
    let terminal =
      if remaining = 0
      then []
      else (
        match take_terminal_locked client with
        | None -> []
        | Some terminal -> [ terminal ])
    in
    let remaining = remaining - List.length terminal in
    let injected = Bounded_mailbox.Fifo.drain client.injected ~max_items:remaining in
    let remaining = remaining - List.length injected in
    let pushes =
      Bounded_mailbox.Coalesced.drain client.pushes ~max_items:remaining
      |> List.map snd
      |> List.sort (fun left right ->
        match left, right with
        | Push left, Push right ->
          ID.Worker.Push_sequence.compare left.push_sequence right.push_sequence
        | _ -> 0)
    in
    let events = responses @ terminal @ injected @ pushes in
    decrement_pending_output_locked client (List.length events);
    events)
;;

let accepted_event client = function
  | Response response as event ->
    if
      ID.Runtime.Epoch.equal response.runtime_epoch client.runtime_epoch
      && ID.Worker.Generation.equal response.worker_generation client.worker_generation
      && Hashtbl.mem client.pending_requests response.request_id
    then (
      Hashtbl.remove client.pending_requests response.request_id;
      clear_cancelled client response.request_id;
      Some event)
    else None
  | Push push as event ->
    if
      ID.Runtime.Epoch.equal push.runtime_epoch client.runtime_epoch
      && ID.Worker.Generation.equal push.worker_generation client.worker_generation
      && ID.Worker.Push_sequence.compare push.push_sequence client.last_push_sequence > 0
    then (
      client.last_push_sequence <- push.push_sequence;
      Some event)
    else None
  | Terminal terminal as event ->
    if
      ID.Runtime.Epoch.equal terminal.runtime_epoch client.runtime_epoch
      && ID.Worker.Generation.equal terminal.worker_generation client.worker_generation
    then Some event
    else None
;;

let drain_events client ~max_events =
  raw_events client ~max_events |> List.filter_map (accepted_event client)
;;

let drain_to_effects client ~max_events ~schedule =
  let events = drain_events client ~max_events in
  List.iter
    (fun event ->
       List.iter (fun subscriber -> schedule (subscriber event)) client.subscribers)
    events
;;

let await_output client =
  Mutex.lock client.output_mutex;
  while
    Atomic.get client.pending_output_count = 0
    &&
    match status_of_code (Atomic.get client.status) with
    | Starting_status | Ready_status | Stopping_status -> true
    | Stopped_status | Terminal_status -> false
  do
    Condition.wait client.output_condition client.output_mutex
  done;
  Mutex.unlock client.output_mutex
;;

let pending_output_count client = Atomic.get client.pending_output_count

let inject_push client ~runtime_epoch ~worker_generation ~push_sequence ~topic payload =
  let event = Push { runtime_epoch; worker_generation; push_sequence; topic; payload } in
  with_output_lock client (fun () ->
    match Bounded_mailbox.Fifo.try_push client.injected event with
    | `Ok -> increment_pending_output_locked client
    | `Full | `Closed -> failwith "Worker test injection mailbox is unavailable")
;;

module Private = struct
  type nonrec packed_startup = packed_startup
  type nonrec packed_client = packed_client

  type nonrec run_result = run_result =
    | Session_stopped
    | Session_startup_failed of string
    | Session_callback_failed of string

  let prepare = prepare
  let run_session = run_session
  let pack_client = pack_client
  let request_stop = request_stop
  let request_stop_packed = request_stop_packed
  let await_stopped = await_stopped
  let await_stopped_packed = await_stopped_packed
  let fail_unrecoverable = fail_unrecoverable
  let drain_to_effects = drain_to_effects
end

module For_testing = struct
  let drain_events = drain_events
  let await_output = await_output
  let pending_output_count = pending_output_count
  let inject_push = inject_push
end
