(** Revision-scoped OCaml event handlers. *)

module Frame : sig
  type entry =
    { node_id : Node_id.t
    ; event_tag : Bonsai_flutter_ui.Event.Tag.t
    ; handler_id : Handler_id.t
    ; handler : Bonsai_flutter_ui.Event.Handler.t
    }

  type t

  val revision : t -> int64

  module Private : sig
    val create : revision:int64 -> entry list -> t
  end
end

type event =
  { runtime_epoch : int64
  ; displayed_revision : int64
  ; node_id : Node_id.t
  ; event_tag : Bonsai_flutter_ui.Event.Tag.t
  ; handler_id : Handler_id.t
  ; event_sequence : int64
  ; payload : Bonsai_flutter_ui.Event.Payload.t
  }

type t

val create : runtime_epoch:int64 -> t
val install : t -> Frame.t -> (unit, Runtime_error.t) result

(** Marks a revision as displayed without retiring any handler frames. *)
val mark_frame_presented : t -> revision:int64 -> (unit, Runtime_error.t) result

(** Retires handler frames strictly older than [revision]. *)
val retire_before : t -> revision:int64 -> unit

(** Retires frames older than the revision immediately preceding the displayed
    revision. This bounded grace period accepts input that Flutter queued while
    the next frame was being committed. *)
val retire_superseded : t -> displayed_revision:int64 -> unit

(** Marks a revision displayed and retires frames outside the grace period.

    Runtime drivers that must run lifecycle work between those operations
    should call [mark_frame_presented] and [retire_superseded] separately. *)
val frame_presented : t -> revision:int64 -> (unit, Runtime_error.t) result

val dispatch : t -> event -> (unit, Runtime_error.t) result
val dispatch_batch : t -> event list -> (unit, Runtime_error.t) result
val retained_frame_count : t -> int
val clear : t -> unit
