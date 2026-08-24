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

  (** Creates one directional action. [border_radius] controls the revealed
      feedback surface and defaults to a capsule radius of [999.]. *)
  val action
    :  label:string
    -> background:Style.Color.t
    -> ?border_radius:float
    -> disposition:disposition
    -> icon:Widget.t
    -> unit
    -> action

  (** Wraps [content] in a bidirectional swipe host. [clip_border_radius]
      clips the content, feedback, and translation animation together and
      defaults to [0.]. *)
  val create
    :  ?key:Key.t
    -> ?start_action:action
    -> ?end_action:action
    -> ?clip_border_radius:float
    -> content:Widget.t
    -> on_commit:(direction -> unit)
    -> unit
    -> Widget.t

  val direction_of_payload : Event.Payload.t -> direction option

  val create_with_handler
    :  ?key:Key.t
    -> ?start_action:action
    -> ?end_action:action
    -> ?clip_border_radius:float
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

module Message_composer : sig
  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val text_changed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id
  val button_pressed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  (** Defines a composer button whose visual content is any OCaml [Widget.t].
      The native host owns the tap target and reports [id] with the current
      editor text. Button IDs must be positive and unique within a composer. *)
  val button
    :  id:int
    -> tooltip:string
    -> ?position:button_position
    -> ?visibility:button_visibility
    -> ?style:button_style
    -> ?enabled:bool
    -> child:Widget.t
    -> unit
    -> button

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:(event -> unit)
    -> unit
    -> Widget.t

  val create_with_handler
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:Event.Handler.t
    -> unit
    -> Widget.t

  val event_of_payload : Event.Payload.t -> event option

  module For_testing : sig
    type button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type props =
      { enabled : bool
      ; autofocus : bool
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    val decode_props_exn : bytes -> props
  end
end

module Expandable_message_composer : sig
  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val text_changed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id
  val button_pressed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  (** Defines one composer action. The extended-FAB icon is always the first
      native child; button children follow this metadata order. *)
  val button
    :  id:int
    -> tooltip:string
    -> ?position:button_position
    -> ?visibility:button_visibility
    -> ?style:button_style
    -> ?enabled:bool
    -> child:Widget.t
    -> unit
    -> button

  (** Creates a native-local extended FAB that presents a modal bottom-sheet
      message composer. Presentation and dismissal never require an OCaml
      frame. Duration zero is the reduced-motion contract. *)
  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:Widget.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:(event -> unit)
    -> unit
    -> Widget.t

  val create_with_handler
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:Widget.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:Event.Handler.t
    -> unit
    -> Widget.t

  val event_of_payload : Event.Payload.t -> event option

  module For_testing : sig
    type button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type props =
      { enabled : bool
      ; fab_label : string
      ; fab_tooltip : string
      ; animation_duration_ms : int
      ; animation_curve : Animation.Curve.t
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    val decode_props_exn : bytes -> props
  end
end
