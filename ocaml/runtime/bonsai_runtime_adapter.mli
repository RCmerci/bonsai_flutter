(** Version-sensitive access to the upstream Bonsai driver.

    This module keeps driver construction and lifecycle sequencing behind a
    renderer-neutral API. Its public interface does not expose
    [Bonsai.Private]. *)

type 'result t

(** [create ~time_source component] owns a new upstream driver for [component]. *)
val create
  :  time_source:Bonsai.Time_source.t
  -> (Bonsai.graph -> 'result Bonsai.t)
  -> 'result t

(** Applies pending effects, stabilizes Bonsai, and runs before-display work. *)
val flush : 'result t -> unit

(** Returns the result from the most recent stabilization. *)
val result : 'result t -> 'result

(** Schedules an effect for application by a subsequent [flush]. *)
val schedule_event : 'result t -> unit Bonsai.Effect.t -> unit

(** Reports whether [flush] has pending before-display work. *)
val has_before_display_events : 'result t -> bool

(** Reports whether a presented frame has pending lifecycle work. *)
val has_after_display_events : 'result t -> bool

(** Runs activation, deactivation, and after-display work.

    The runtime must call this only after Flutter acknowledges presentation of
    the corresponding frame. *)
val frame_presented : 'result t -> unit

(** Invalidates the upstream driver's Incremental observers.

    This operation is idempotent. Other operations are invalid after shutdown. *)
val shutdown : 'result t -> unit

val is_shutdown : 'result t -> bool
