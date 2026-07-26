(** Accessibility semantics attached to a logical widget subtree. *)

module Role : sig
  type t =
    | Generic
    | Button
    | Link
    | Image
    | Header
    | Text_field
    | Checkbox
    | Switch
    | Slider

  val equal : t -> t -> bool
  val to_string : t -> string
end

module Action : sig
  type t =
    | Tap
    | Long_press
    | Focus
    | Increase
    | Decrease
    | Copy
    | Cut
    | Paste
    | Dismiss

  val equal : t -> t -> bool
  val to_wire_id : t -> int64
  val of_wire_id : int64 -> t option
end

type t

val create
  :  ?label:string
  -> ?hint:string
  -> ?value:string
  -> ?role:Role.t
  -> ?enabled:bool
  -> ?selected:bool
  -> ?checked:bool
  -> ?focusable:bool
  -> ?obscured:bool
  -> ?live_region:bool
  -> ?heading_level:int
  -> ?sort_key:float
  -> ?actions:Action.t list
  -> unit
  -> t

module Private : sig
  type view =
    { label : string option
    ; hint : string option
    ; value : string option
    ; role : Role.t
    ; enabled : bool option
    ; selected : bool option
    ; checked : bool option
    ; focusable : bool option
    ; obscured : bool
    ; live_region : bool
    ; heading_level : int option
    ; sort_key : float option
    ; actions : Action.t list
    }

  val view : t -> view
  val role_to_wire : Role.t -> int
  val role_of_wire : int -> Role.t option
  val actions_to_bits : Action.t list -> int
  val actions_of_bits : int -> Action.t list option
end
