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

module Slidable : sig
  type side =
    | Start
    | End

  type motion =
    | Behind
    | Drawer
    | Scroll
    | Stretch

  type dismiss_motion = Inversed_drawer
  type dismissible
  type action
  type action_pane

  type event =
    | Action_pressed of int
    | Dismissed of side

  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
  val action_pressed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id
  val dismissed_event_id : Bonsai_flutter_spec.Id.Native_widget.event_id

  (** Creates a fully custom action whose rendered content is [child]. *)
  val action
    :  id:int
    -> ?enabled:bool
    -> ?flex:int
    -> ?foreground:Style.Color.t
    -> background:Style.Color.t
    -> ?auto_close:bool
    -> ?border_radius:float
    -> ?padding:Layout.Edge_insets.t
    -> ?alignment:Layout.Alignment.t
    -> child:Widget.t
    -> unit
    -> action

  (** Creates the common vertically stacked icon-and-label action content. *)
  val icon_label_action
    :  id:int
    -> ?enabled:bool
    -> ?flex:int
    -> ?foreground:Style.Color.t
    -> background:Style.Color.t
    -> ?auto_close:bool
    -> ?border_radius:float
    -> ?padding:Layout.Edge_insets.t
    -> ?alignment:Layout.Alignment.t
    -> ?spacing:float
    -> icon:Widget.t
    -> label:string
    -> unit
    -> action

  val dismissible
    :  ?dismiss_threshold:float
    -> ?dismissal_duration_ms:int
    -> ?resize_duration_ms:int
    -> ?close_on_cancel:bool
    -> ?motion:dismiss_motion
    -> unit
    -> dismissible

  val action_pane
    :  ?extent_ratio:float
    -> motion:motion
    -> ?dismissible:dismissible
    -> ?drag_dismissible:bool
    -> ?open_threshold:float
    -> ?close_threshold:float
    -> actions:action list
    -> unit
    -> action_pane

  val create
    :  key:Key.t
    -> ?enabled:bool
    -> ?close_on_scroll:bool
    -> ?direction:Layout.Axis.t
    -> ?use_text_direction:bool
    -> ?group_tag:string
    -> ?start_action_pane:action_pane
    -> ?end_action_pane:action_pane
    -> content:Widget.t
    -> on_event:(event -> unit)
    -> unit
    -> Widget.t

  val event_of_payload : Event.Payload.t -> event option

  val create_with_handler
    :  key:Key.t
    -> ?enabled:bool
    -> ?close_on_scroll:bool
    -> ?direction:Layout.Axis.t
    -> ?use_text_direction:bool
    -> ?group_tag:string
    -> ?start_action_pane:action_pane
    -> ?end_action_pane:action_pane
    -> content:Widget.t
    -> on_event:Event.Handler.t
    -> unit
    -> Widget.t

  module For_testing : sig
    type action_props =
      { id : int
      ; enabled : bool
      ; flex : int
      ; foreground : Style.Color.t option
      ; background : Style.Color.t
      ; auto_close : bool
      ; border_radius : float
      ; padding : Layout.Edge_insets.t option
      ; alignment : Layout.Alignment.t option
      }

    type dismissible_props =
      { dismiss_threshold : float
      ; dismissal_duration_ms : int
      ; resize_duration_ms : int
      ; close_on_cancel : bool
      ; motion : dismiss_motion
      }

    type action_pane_props =
      { extent_ratio : float
      ; motion : motion
      ; dismissible : dismissible_props option
      ; drag_dismissible : bool
      ; open_threshold : float option
      ; close_threshold : float option
      ; actions : action_props list
      }

    type props =
      { enabled : bool
      ; close_on_scroll : bool
      ; direction : Layout.Axis.t
      ; use_text_direction : bool
      ; group_tag : string option
      ; start_action_pane : action_pane_props option
      ; end_action_pane : action_pane_props option
      }

    val decode_props_exn : bytes -> props
    val encode_action_pressed : int -> bytes
    val encode_dismissed : side -> bytes
  end
end

module Slidable_auto_close_behavior : sig
  val kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id

  val create
    :  ?key:Key.t
    -> ?close_when_opened:bool
    -> ?close_when_tapped:bool
    -> child:Widget.t
    -> unit
    -> Widget.t

  module For_testing : sig
    type props =
      { close_when_opened : bool
      ; close_when_tapped : bool
      }

    val decode_props_exn : bytes -> props
  end
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
  type fab_presentation =
    | Extended
    | Compact

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

  (** Defines one composer action. The FAB icon is always the first native
      child; button children follow this metadata order. *)
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

  (** Creates a native-local FAB for
      [Material.scaffold ~floating_action_button]. [Extended] renders an
      extended FAB; [Compact] renders the standard icon-only FAB, not the small
      FAB. [fab_label] remains required for both presentations, and
      [fab_tooltip] is their accessible label. The scaffold owns placement; its
      default is [End_float], and callers may select another standard
      floating-action-button location. The composer occupies the scaffold's
      single floating-action-button slot and presents a modal bottom-sheet
      message composer when pressed. With a stable logical key, changing only
      the presentation retains the modal route, exact draft, controller, and
      focus state. Presentation and dismissal never require an OCaml frame.
      Duration zero is the reduced-motion contract. *)
  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_presentation:fab_presentation
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
    -> fab_presentation:fab_presentation
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
      ; fab_presentation : fab_presentation
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
