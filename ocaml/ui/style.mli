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

module Font_weight : sig
  type t =
    | Normal
    | Medium
    | Semi_bold
    | Bold
end

module Text_align : sig
  type t =
    | Start
    | Center
    | End
end

module Text_overflow : sig
  type t =
    | Clip
    | Fade
    | Ellipsis
    | Visible
end

module Text_style : sig
  type t

  val create
    :  ?font_size:float
    -> ?font_weight:Font_weight.t
    -> ?line_height:float
    -> ?color:Color.t
    -> unit
    -> t

  module Private : sig
    type view =
      { font_size : float option
      ; font_weight : Font_weight.t option
      ; line_height : float option
      ; color : int32 option
      }

    val view : t -> view
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
