(** Typed visual style values. *)

module Brightness : sig
  type t =
    | Light
    | Dark
end

module Color : sig
  type t

  val argb : alpha:int -> red:int -> green:int -> blue:int -> t
  val rgb : red:int -> green:int -> blue:int -> t

  module Private : sig
    val to_argb32 : t -> int32
  end
end

module Image_fit : sig
  type t =
    | Fill
    | Contain
    | Cover
    | Fit_width
    | Fit_height
    | None
    | Scale_down
end

module Clip : sig
  type t =
    | Hard_edge
    | Anti_alias
    | Anti_alias_with_save_layer
end

module Decoration : sig
  type t

  val create : ?background:Color.t -> ?border_radius:float -> unit -> t

  module Private : sig
    val to_values : t -> int32 option * float
  end
end

module Transform : sig
  type t

  val identity : t
  val scale : ?x:float -> ?y:float -> unit -> t
  val translate : ?x:float -> ?y:float -> unit -> t
  val matrix4 : float array -> t

  module Private : sig
    val to_array : t -> float array
  end
end
