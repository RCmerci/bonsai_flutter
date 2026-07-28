(** Strongly typed application-native widget extensions.

    Extension payloads are opaque to the core renderer. A matching typed Dart
    registration decodes them and owns the platform widget implementation. *)

module Capability : sig
  type t =
    | Stateful
    | Resource
    | Semantics
    | Semantics_canvas
    | Virtualized

  val bit : t -> int64
  val bits : t list -> int64
end

module Extension : sig
  type ('props, 'event) t

  val create
    :  kind_id:int
    -> version:int
    -> capabilities:Capability.t list
    -> encode_props:('props -> bytes)
    -> decode_event:(event_id:int -> bytes -> ('event, string) result)
    -> unit
    -> ('props, 'event) t
end

val event_handler
  :  ?name:string
  -> ('props, 'event) Extension.t
  -> ('event -> unit)
  -> Event.Handler.t

val widget
  :  ('props, 'event) Extension.t
  -> ?key:Key.t
  -> props:'props
  -> on_event:('event -> unit)
  -> ?children:Widget.t list
  -> unit
  -> Widget.t

val widget_with_handler
  :  ('props, 'event) Extension.t
  -> ?key:Key.t
  -> props:'props
  -> on_event:Event.Handler.t
  -> ?children:Widget.t list
  -> unit
  -> Widget.t

module Virtual_list : sig
  val kind_id : int
  val visible_range_event_id : int

  val create
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> ?axis:Layout.Axis.t
    -> items:Widget.t list
    -> on_visible_range:(Event.Payload.visible_range -> unit)
    -> unit
    -> Widget.t

  module For_testing : sig
    type props =
      { total_count : int
      ; first_index : int
      ; item_extent : float
      ; overscan : int
      ; axis : Layout.Axis.t
      }

    val decode_props_exn : bytes -> props
    val encode_visible_range : first_index:int -> last_exclusive:int -> bytes
  end
end

module Swipe_action : sig
  type direction =
    | Start_to_end
    | End_to_start

  type disposition =
    | Dismiss
    | Rebound

  type action

  val action
    :  label:string
    -> background:Style.Color.t
    -> disposition:disposition
    -> icon:Widget.t
    -> action

  val create
    :  ?key:Key.t
    -> ?start_action:action
    -> ?end_action:action
    -> content:Widget.t
    -> on_commit:(direction -> unit)
    -> unit
    -> Widget.t

  val direction_of_payload : Event.Payload.t -> direction option

  val create_with_handler
    :  ?key:Key.t
    -> ?start_action:action
    -> ?end_action:action
    -> content:Widget.t
    -> on_commit:Event.Handler.t
    -> unit
    -> Widget.t
end
