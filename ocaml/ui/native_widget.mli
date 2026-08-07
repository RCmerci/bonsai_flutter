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
    :  kind_id:Bonsai_flutter_spec.Id.Native_widget.kind_id
    -> version:int
    -> capabilities:Capability.t list
    -> encode_props:('props -> bytes)
    -> decode_event:
         (event_id:Bonsai_flutter_spec.Id.Native_widget.event_id
          -> bytes
          -> ('event, string) result)
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
  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val visible_range_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  val vertical
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Widget.Viewport.Vertical.t

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option

  val horizontal
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Widget.Viewport.Horizontal.t

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

module Sparse_extent_list : sig
  module Transition : sig
    type curve =
      | Linear
      | Ease_in
      | Ease_out
      | Ease_in_out
      | Ease_out_cubic
      | Ease_in_out_cubic

    type t =
      { enabled : bool
      ; expand_duration_ms : int
      ; collapse_duration_ms : int
      ; expand_curve : curve
      ; collapse_curve : curve
      }

    val create
      :  ?enabled:bool
      -> expand_duration_ms:int
      -> collapse_duration_ms:int
      -> ?expand_curve:curve
      -> ?collapse_curve:curve
      -> unit
      -> t
  end

  type extent_override =
    { index : int
    ; extent : float
    }

  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val visible_range_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  val vertical
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:extent_override list
    -> ?overscan:int
    -> ?transition:Transition.t
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Widget.Viewport.Vertical.t

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option

  val horizontal
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:extent_override list
    -> ?overscan:int
    -> ?transition:Transition.t
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Widget.Viewport.Horizontal.t

  module For_testing : sig
    type nonrec extent_override = extent_override =
      { index : int
      ; extent : float
      }

    type props =
      { total_count : int
      ; first_index : int
      ; default_item_extent : float
      ; extent_overrides : extent_override list
      ; overscan : int
      ; axis : Layout.Axis.t
      ; transition : Transition.t option
      }

    val decode_props_exn : bytes -> props
    val encode_visible_range : first_index:int -> last_exclusive:int -> bytes
  end
end

module Morphing_surface : sig
  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id

  val create
    :  ?key:Key.t
    -> expanded:bool
    -> compact_content:Widget.t
    -> expanded_content:Widget.t
    -> unit
    -> Widget.t

  module For_testing : sig
    type props = { expanded : bool }

    val decode_props_exn : bytes -> props
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

  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val drawer_state_changed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  val create
    :  ?key:Key.t
    -> selected_index:int
    -> drawer_open:bool
    -> drawer_enabled:bool
    -> bodies:Widget.Body.t list
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
    -> bodies:Widget.Body.t list
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
