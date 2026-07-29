(** One serialized Bonsai-to-renderer runtime.

    [Driver] owns Bonsai effect scheduling, reconciliation, revision-scoped
    handlers, binary frame encoding, and presentation-gated lifecycle calls. *)

module Handler : sig
  type t

  (** Creates a dependency-aware UI handler whose returned effect is scheduled
      by the next [pump].

      The returned handler retains its physical identity while [dependencies]
      are equal according to [equal]. A dependency change creates a fresh
      handler identity so revision-scoped event dispatch remains safe.

      Every value that can change callback behavior must be included in
      [dependencies]. A false-positive [equal] result can retain stale callback
      behavior; a false-negative result only causes an unnecessary event
      binding update. *)
  val create
    :  t
    -> ?name:string
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.t
    -> f:('dependencies -> Bonsai_flutter_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t Bonsai.t

  val create_native
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_flutter_ui.Native_widget.Extension.t
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.t
    -> f:('dependencies -> 'event -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t Bonsai.t

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

type pump_result =
  { presentation_id : int64
  ; renderer_revision : int64
  ; frame : frame option
  ; recoverable_error : error option
  }

type rejection_reason =
  | Decode_failed
  | Frame_validation_failed
  | Renderer_epoch_mismatch
  | Renderer_revision_mismatch

type t

val create
  :  ?trace:(string -> unit)
  -> runtime_epoch:int64
  -> time_source:Bonsai.Time_source.t
  -> (Handler.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t)
  -> t

(** Advances logical time, consumes at most one atomic input batch, flushes
    Bonsai once, and reserves one presentation token. *)
val pump
  :  t
  -> monotonic_now_ns:int64
  -> ?events:Bonsai_flutter_protocol.Inbound_event.batch
  -> unit
  -> (pump_result, error) result

val presentation_succeeded
  :  t
  -> presentation_id:int64
  -> renderer_revision:int64
  -> monotonic_now_ns:int64
  -> (unit, error) result

val presentation_rejected
  :  t
  -> presentation_id:int64
  -> renderer_revision:int64
  -> reason:rejection_reason
  -> (unit, error) result

val shutdown : t -> unit
val is_shutdown : t -> bool

module For_testing : sig
  val runtime_epoch : t -> int64
  val revision : t -> int64
  val snapshot : t -> Bonsai_flutter_runtime.Mounted_tree.Snapshot.t option
  val environment : t -> Environment.snapshot
  val pending_host_effect_count : t -> int
  val retained_handler_frame_count : t -> int
  val set_next_presentation_id : t -> int64 -> unit
  val set_next_renderer_revision : t -> int64 -> unit
end
