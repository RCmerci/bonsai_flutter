(** Stable application-supplied identity used only by headless and renderer tests. *)

type t

val string : string -> t
val equal : t -> t -> bool
val to_string : t -> string
