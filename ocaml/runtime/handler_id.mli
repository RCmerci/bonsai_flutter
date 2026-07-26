(** Monotonic handler identity, unique within a runtime epoch. *)

type t = int64

val compare : t -> t -> int
val equal : t -> t -> bool
val to_int64 : t -> int64

module Private : sig
  val of_int64 : int64 -> t
end
