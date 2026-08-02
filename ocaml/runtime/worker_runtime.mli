(** Process-wide singleton OCaml Worker Domain lifecycle. *)

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
  ; worker_domain_id : Bonsai_flutter_spec.Id.Worker.domain_id option
  ; active_sessions : int
  ; peak_active_sessions : int
  ; idle_wait_count : int
  }

val start
  :  runtime_epoch:Bonsai_flutter_spec.Id.Runtime.epoch
  -> ('config, 'request, 'response, 'push) Worker.Service.t
  -> 'config
  -> (('request, 'response, 'push) Worker.client, string) result

(** Cooperatively removes one attached session. This never joins the
    process-wide Worker Domain. *)
val stop : ('request, 'response, 'push) Worker.client -> unit

module For_testing : sig
  val diagnostics : unit -> diagnostics
  val await_state : state -> unit
  val await_idle_wait_count : int -> unit

  (** Stops and joins the process-wide Worker Domain exactly once when a
      Domain was successfully spawned. *)
  val final_shutdown : unit -> unit

  val crash_worker_loop : unit -> unit
  val fail_next_spawn : exn -> unit
end
