(** Theme data inherited by a logical widget subtree. *)

type t

val material : ?brightness:Style.Brightness.t -> ?color_seed:Style.Color.t -> unit -> t

module Private : sig
  type view =
    { brightness : Style.Brightness.t
    ; color_seed : int32
    }

  val view : t -> view
end
