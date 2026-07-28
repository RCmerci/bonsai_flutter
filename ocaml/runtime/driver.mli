(** One serialized Bonsai-to-renderer runtime.

    [Driver] owns Bonsai effect scheduling, reconciliation, revision-scoped
    handlers, binary frame encoding, and presentation-gated lifecycle calls. *)

module Handler : sig
  type t

  (** Creates a UI handler whose returned effect is scheduled by the next
      [step]. *)
  val create
    :  t
    -> ?name:string
    -> (Bonsai_flutter_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t

  val create_native
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_flutter_ui.Native_widget.Extension.t
    -> ('event -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t

  val host_effects : t -> Host_effect.t
  val environment : t -> Environment.t
end

type frame =
  { revision : int64
  ; frame_patch : Bonsai_flutter_runtime.Frame_patch.t
  ; bytes : bytes
  ; stats : Bonsai_flutter_protocol.Wire_frame.runtime_stats
  }

type error =
  | Runtime_error of Bonsai_flutter_runtime.Runtime_error.t
  | Event_error of Bonsai_flutter_runtime.Event_dispatcher.error
  | Codec_error of Bonsai_flutter_protocol.Binary_codec.error
  | Unsupported_widget of string
  | Invalid_state of string
  | Lifecycle_error of string
  | Host_response_error of string
  | Shutdown

val error_to_string : error -> string

type t

val create
  :  ?trace:(string -> unit)
  -> runtime_epoch:int64
  -> time_source:Bonsai.Time_source.t
  -> (Handler.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t)
  -> t

(** Dispatches one validated event batch, schedules its effects, flushes
    Bonsai once, and emits at most one atomic renderer frame. *)
val step
  :  t
  -> ?events:Bonsai_flutter_protocol.Inbound_event.batch
  -> unit
  -> (frame option, error) result

(** Acknowledges Flutter presentation and only then runs lifecycle effects. *)
val frame_presented : t -> revision:int64 -> (unit, error) result

val shutdown : t -> unit
val is_shutdown : t -> bool

module For_testing : sig
  val runtime_epoch : t -> int64
  val revision : t -> int64
  val snapshot : t -> Bonsai_flutter_runtime.Mounted_tree.Snapshot.t option
  val environment : t -> Environment.snapshot
  val pending_host_effect_count : t -> int
  val retained_handler_frame_count : t -> int
end
