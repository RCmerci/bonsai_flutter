(** Typed domain-0 client and Worker Domain service contract. *)

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
      { runtime_epoch : int64
      ; worker_generation : int64
      ; request_id : int64
      ; outcome : 'response outcome
      }
  | Push of
      { runtime_epoch : int64
      ; worker_generation : int64
      ; push_sequence : int64
      ; topic : int
      ; payload : 'push
      }
  | Terminal of
      { runtime_epoch : int64
      ; worker_generation : int64
      ; error : string
      }

type send_result =
  | Accepted of int64
  | Full
  | Not_ready
  | Stopping

type ('request, 'response, 'push) client

module Service : sig
  type ('config, 'request, 'response, 'push) t

  val create
    :  push_topic_count:int
    -> init:(emit:(topic:int -> 'push -> unit) -> 'config -> ('state, string) result)
    -> handle_request:
         ('state
          -> cancelled:(unit -> bool)
          -> emit:(topic:int -> 'push -> unit)
          -> 'request
          -> ('response, string) result * computation)
    -> step:
         ('state
          -> cancelled:(unit -> bool)
          -> emit:(topic:int -> 'push -> unit)
          -> computation)
    -> cancel:('state -> request_id:int64 -> unit)
    -> shutdown:('state -> unit)
    -> ('config, 'request, 'response, 'push) t
end

(** Non-blocking domain-0 request enqueue. *)
val send : ('request, 'response, 'push) client -> 'request -> send_result

(** Requests cooperative cancellation without entering the bounded request
    lane. *)
val cancel : ('request, 'response, 'push) client -> request_id:int64 -> unit

(** Registers a domain-0-only effect handler. The handler is invoked only by a
    later accepted Driver pump. *)
val on_event
  :  ('request, 'response, 'push) client
  -> (('response, 'push) event -> unit Bonsai.Effect.t)
  -> unit

val runtime_epoch : ('request, 'response, 'push) client -> int64
val worker_generation : ('request, 'response, 'push) client -> int64

module Private : sig
  type packed_startup
  type packed_client

  type run_result =
    | Session_stopped
    | Session_startup_failed of string
    | Session_callback_failed of string

  val prepare
    :  runtime_epoch:int64
    -> worker_generation:int64
    -> ('config, 'request, 'response, 'push) Service.t
    -> 'config
    -> ('request, 'response, 'push) client * packed_startup

  val run_session
    :  packed_startup
    -> on_startup:((unit, string) result -> unit)
    -> on_idle_wait:(unit -> unit)
    -> run_result

  val pack_client : ('request, 'response, 'push) client -> packed_client
  val request_stop : ('request, 'response, 'push) client -> unit
  val request_stop_packed : packed_client -> unit
  val await_stopped : ('request, 'response, 'push) client -> unit
  val await_stopped_packed : packed_client -> unit
  val fail_unrecoverable : packed_client -> string -> unit

  val drain_to_effects
    :  ('request, 'response, 'push) client
    -> max_events:int
    -> schedule:(unit Bonsai.Effect.t -> unit)
    -> unit
end

module For_testing : sig
  val drain_events
    :  ('request, 'response, 'push) client
    -> max_events:int
    -> ('response, 'push) event list

  val await_output : ('request, 'response, 'push) client -> unit
  val pending_output_count : ('request, 'response, 'push) client -> int

  val inject_push
    :  ('request, 'response, 'push) client
    -> runtime_epoch:int64
    -> worker_generation:int64
    -> push_sequence:int64
    -> topic:int
    -> 'push
    -> unit
end
