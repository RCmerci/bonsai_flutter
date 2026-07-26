(** Renderer-local semantic animation intent.

    OCaml publishes targets and completion identity. Flutter performs all
    interpolation locally and reports only completion. *)

module Curve : sig
  type t =
    | Linear
    | Ease_in
    | Ease_out
    | Ease_in_out

  val equal : t -> t -> bool
end

type t

(** [create ~id ~duration_ms ~curve ()] creates renderer-local animation
    intent. [id] is returned by the completion event and [duration_ms] must be
    non-negative. *)
val create : id:int64 -> duration_ms:int -> ?curve:Curve.t -> unit -> t

module Private : sig
  val id : t -> int64
  val duration_ms : t -> int
  val curve : t -> Curve.t
  val equal : t -> t -> bool
end
