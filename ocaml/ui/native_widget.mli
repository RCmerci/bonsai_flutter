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

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option

  val create_with_handler
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> ?axis:Layout.Axis.t
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
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

module Navigation_shell : sig
  type drawer_state =
    | Closed
    | Open

  val kind_id : int
  val drawer_state_changed_event_id : int

  val create
    :  ?key:Key.t
    -> selected_index:int
    -> drawer_open:bool
    -> drawer_enabled:bool
    -> bodies:Widget.t list
    -> drawer:Widget.t
    -> bottom_navigation:Widget.t
    -> on_drawer_state_changed:(drawer_state -> unit)
    -> unit
    -> Widget.t

  val drawer_state_of_payload : Event.Payload.t -> drawer_state option

  val create_with_handler
    :  ?key:Key.t
    -> selected_index:int
    -> drawer_open:bool
    -> drawer_enabled:bool
    -> bodies:Widget.t list
    -> drawer:Widget.t
    -> bottom_navigation:Widget.t
    -> on_drawer_state_changed:Event.Handler.t
    -> unit
    -> Widget.t

  module For_testing : sig
    type props =
      { selected_index : int
      ; destination_count : int
      ; drawer_open : bool
      ; drawer_enabled : bool
      }

    val decode_props_exn : bytes -> props
    val encode_drawer_state : drawer_state -> bytes
  end
end

module Pressable : sig
  val kind_id : int
  val activate_event_id : int

  val create
    :  ?key:Key.t
    -> ?overlay_color:Style.Color.t
    -> ?release_delay_ms:int
    -> child:Widget.t
    -> on_activate:(unit -> unit)
    -> unit
    -> Widget.t

  val activation_of_payload : Event.Payload.t -> bool

  val create_with_handler
    :  ?key:Key.t
    -> ?overlay_color:Style.Color.t
    -> ?release_delay_ms:int
    -> child:Widget.t
    -> on_activate:Event.Handler.t
    -> unit
    -> Widget.t

  module For_testing : sig
    type props =
      { overlay_color : Style.Color.t
      ; release_delay_ms : int
      }

    val decode_props_exn : bytes -> props
  end
end
