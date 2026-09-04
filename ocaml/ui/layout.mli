(** Typed layout values shared by logical widgets. *)

module Axis : sig
  type t =
    | Horizontal
    | Vertical
end

module Alignment : sig
  type t =
    | Top_start
    | Top_center
    | Top_end
    | Center_start
    | Center
    | Center_end
    | Bottom_start
    | Bottom_center
    | Bottom_end
end

module Box_constraints : sig
  type t

  (** Creates box constraints with finite, non-negative bounds. An omitted
      maximum is unbounded. *)
  val create
    :  ?min_width:float
    -> ?max_width:float
    -> ?min_height:float
    -> ?max_height:float
    -> unit
    -> t

  module Private : sig
    val to_values : t -> float * float option * float * float option
  end
end

module Edge_insets : sig
  type t

  val all : float -> t
  val symmetric : ?horizontal:float -> ?vertical:float -> unit -> t
  val only : ?left:float -> ?top:float -> ?right:float -> ?bottom:float -> unit -> t

  module Private : sig
    val to_sides : t -> float * float * float * float
  end
end
