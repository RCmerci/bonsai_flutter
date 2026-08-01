(** Immutable, typed logical UI nodes.

    This module is renderer-independent. Application keys are optional and
    event closures remain in OCaml. *)

type t

val with_test_id : Test_id.t -> t -> t
val empty : ?key:Key.t -> unit -> t

val text
  :  ?key:Key.t
  -> ?style:Style.Text_style.t
  -> ?text_align:Style.Text_align.t
  -> ?max_lines:int
  -> ?overflow:Style.Text_overflow.t
  -> string
  -> t

val rich_text : ?key:Key.t -> string list -> t

val icon
  :  ?key:Key.t
  -> ?font_family:string
  -> ?size:float
  -> ?color:Style.Color.t
  -> code_point:int
  -> unit
  -> t

val image
  :  ?key:Key.t
  -> ?fit:Style.Image_fit.t
  -> ?width:float
  -> ?height:float
  -> uri:string
  -> unit
  -> t

val row : ?key:Key.t -> t list -> t
val column : ?key:Key.t -> t list -> t
val padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t
val align : ?key:Key.t -> alignment:Layout.Alignment.t -> t -> t
val center : ?key:Key.t -> ?width_factor:float -> ?height_factor:float -> t -> t
val sized_box : ?key:Key.t -> ?width:float -> ?height:float -> t -> t
val constrained_box : ?key:Key.t -> constraints:Layout.Box_constraints.t -> t -> t
val decorated_box : ?key:Key.t -> decoration:Style.Decoration.t -> t -> t
val clip : ?key:Key.t -> ?behavior:Style.Clip.t -> t -> t
val opacity : ?key:Key.t -> float -> t -> t

(** [animated_opacity] publishes a target and animation intent. Flutter
    performs interpolation locally and invokes [on_completed] with
    [Event.Payload.Int64 animation_id] after reaching the target. *)
val animated_opacity
  :  ?key:Key.t
  -> animation:Animation.t
  -> opacity:float
  -> on_completed:Event.Handler.t
  -> t
  -> t

val transform : ?key:Key.t -> transform:Style.Transform.t -> t -> t

val scroll_view
  :  ?key:Key.t
  -> ?axis:Layout.Axis.t
  -> ?reverse:bool
  -> on_scroll:Event.Handler.t
  -> t
  -> unit
  -> t

val list_view
  :  ?key:Key.t
  -> ?axis:Layout.Axis.t
  -> ?reverse:bool
  -> on_scroll:Event.Handler.t
  -> t list
  -> unit
  -> t

val safe_area
  :  ?key:Key.t
  -> ?left:bool
  -> ?top:bool
  -> ?right:bool
  -> ?bottom:bool
  -> ?minimum:Layout.Edge_insets.t
  -> t
  -> t

val environment_boundary : ?key:Key.t -> t -> t

val gesture
  :  ?key:Key.t
  -> ?on_tap:Event.Handler.t
  -> ?on_double_tap:Event.Handler.t
  -> ?on_long_press:Event.Handler.t
  -> ?on_pointer_down:Event.Handler.t
  -> ?on_pointer_up:Event.Handler.t
  -> t
  -> t

val focus_scope
  :  ?key:Key.t
  -> ?autofocus:bool
  -> on_focus_changed:Event.Handler.t
  -> t
  -> t

val mouse_region
  :  ?key:Key.t
  -> ?opaque:bool
  -> on_enter:Event.Handler.t
  -> on_leave:Event.Handler.t
  -> t
  -> t

val keyboard_listener
  :  ?key:Key.t
  -> ?autofocus:bool
  -> ?key_policy:Event.Key_policy.t
  -> on_key:Event.Handler.t
  -> t
  -> t

val semantics
  :  ?key:Key.t
  -> ?on_action:Event.Handler.t
  -> properties:Semantics.t
  -> t
  -> t

val theme : ?key:Key.t -> data:Theme.t -> t -> t

val navigator
  :  ?key:Key.t
  -> ?restoration_scope_id:string
  -> on_pop:Event.Handler.t
  -> t list
  -> t

val page
  :  ?key:Key.t
  -> page_key:string
  -> ?transition:Navigation.page_transition
  -> ?can_pop:bool
  -> ?restoration_id:string
  -> t
  -> t

val overlay
  :  ?key:Key.t
  -> ?alignment:Navigation.overlay_alignment
  -> ?dismissible:bool
  -> t list
  -> t

val material_dialog : ?key:Key.t -> ?barrier_dismissible:bool -> t -> t

val text_input
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?obscure_text:bool
  -> ?keyboard_type:Text_editing.keyboard_type
  -> ?input_action:Text_editing.input_action
  -> ?autofocus:bool
  -> session_id:int64
  -> document_revision:int64
  -> accepted_local_revision:int64
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> unit
  -> t

val button
  :  ?key:Key.t
  -> ?enabled:bool
  -> on_press:Event.Handler.t
  -> child:t
  -> unit
  -> t

val pressable
  :  ?key:Key.t
  -> ?overlay_color:Style.Color.t
  -> ?release_delay_ms:int
  -> on_press:Event.Handler.t
  -> child:t
  -> unit
  -> t

module Flex : sig
  type child

  val fixed : t -> child
  val flexible : ?flex:int -> t -> child
  val expanded : ?flex:int -> t -> child
  val row : ?key:Key.t -> child list -> t
  val column : ?key:Key.t -> child list -> t
end

module Stack : sig
  type child

  val child : t -> child

  val positioned
    :  ?left:float
    -> ?top:float
    -> ?right:float
    -> ?bottom:float
    -> t
    -> child

  val create : ?key:Key.t -> child list -> t
end

module For_testing : sig
  val kind_name : t -> string
  val key : t -> Key.t option
  val test_id : t -> Test_id.t option
  val children : t -> t array
  val text_content : t -> string option
end

module Private : sig
  module Kind : sig
    type t =
      | Empty
      | Text
      | Rich_text
      | Icon
      | Image
      | Row
      | Column
      | Flex_row
      | Flex_column
      | Stack
      | Button
      | Padding
      | Align
      | Center
      | Sized_box
      | Constrained_box
      | Decorated_box
      | Clip
      | Opacity
      | Animated_opacity
      | Transform
      | Scroll_view
      | List_view
      | Gesture
      | Focus_scope
      | Mouse_region
      | Keyboard_listener
      | Pressable
      | Semantics
      | Theme
      | Material_scaffold
      | Material_app_bar
      | Material_elevated_button
      | Material_text_button
      | Material_icon_button
      | Material_checkbox
      | Material_switch
      | Material_list_tile
      | Material_divider
      | Material_card
      | Material_circular_progress_indicator
      | Cupertino_button
      | Cupertino_switch
      | Text_input
      | Overlay
      | Navigator
      | Page
      | Safe_area
      | Environment_boundary
      | Material_dialog
      | Native_widget

    val compare : t -> t -> int
    val equal : t -> t -> bool
    val to_string : t -> string
  end

  type flex_fit =
    | Loose
    | Tight

  type flex_parent_data =
    { flex : int
    ; fit : flex_fit
    }

  type position =
    { left : float option
    ; top : float option
    ; right : float option
    ; bottom : float option
    }

  type child_parent_data =
    | No_parent_data
    | Flex_parent_data of flex_parent_data
    | Stack_position of position

  type material_button_variant =
    | Elevated
    | Text_button
    | Icon_button

  type props =
    | Empty_props
    | Text_props of
        { value : string
        ; style : Style.Text_style.Private.view option
        ; text_align : Style.Text_align.t
        ; max_lines : int option
        ; overflow : Style.Text_overflow.t
        }
    | Rich_text_props of { spans : string list }
    | Icon_props of
        { code_point : int
        ; font_family : string option
        ; size : float option
        ; color : int32 option
        }
    | Image_props of
        { uri : string
        ; fit : Style.Image_fit.t
        ; width : float option
        ; height : float option
        }
    | Linear_props
    | Stack_props
    | Button_props of { enabled : bool }
    | Pressable_props of
        { overlay_color : Style.Color.t
        ; release_delay_ms : int
        }
    | Padding_props of
        { left : float
        ; top : float
        ; right : float
        ; bottom : float
        }
    | Align_props of { alignment : Layout.Alignment.t }
    | Center_props of
        { width_factor : float option
        ; height_factor : float option
        }
    | Sized_box_props of
        { width : float option
        ; height : float option
        }
    | Constrained_box_props of
        { min_width : float
        ; max_width : float
        ; min_height : float
        ; max_height : float
        }
    | Decorated_box_props of
        { background : int32 option
        ; border_radius : float
        }
    | Clip_props of { behavior : Style.Clip.t }
    | Opacity_props of { opacity : float }
    | Animated_opacity_props of
        { opacity : float
        ; animation : Animation.t
        }
    | Transform_props of { matrix4 : float array }
    | Scroll_view_props of
        { axis : Layout.Axis.t
        ; reverse : bool
        }
    | List_view_props of
        { axis : Layout.Axis.t
        ; reverse : bool
        }
    | Gesture_props
    | Focus_scope_props of { autofocus : bool }
    | Mouse_region_props of { opaque : bool }
    | Keyboard_listener_props of
        { autofocus : bool
        ; key_policy : Event.Key_policy.t
        }
    | Semantics_props of
        { label : string option
        ; hint : string option
        ; value : string option
        ; role : Semantics.Role.t
        ; enabled : bool option
        ; selected : bool option
        ; checked : bool option
        ; focusable : bool option
        ; obscured : bool
        ; live_region : bool
        ; heading_level : int option
        ; sort_key : float option
        ; actions : Semantics.Action.t list
        }
    | Theme_props of
        { brightness : Style.Brightness.t
        ; color_seed : int32
        }
    | Material_scaffold_props of { has_app_bar : bool }
    | Material_app_bar_props of { center_title : bool }
    | Material_button_props of
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
    | Material_checkbox_props of
        { value : bool
        ; enabled : bool
        }
    | Material_switch_props of
        { value : bool
        ; enabled : bool
        }
    | Material_list_tile_props of
        { enabled : bool
        ; selected : bool
        ; has_subtitle : bool
        ; has_leading : bool
        ; has_trailing : bool
        }
    | Material_divider_props of { thickness : float }
    | Material_card_props of { elevation : float }
    | Material_progress_props of { value : float option }
    | Cupertino_button_props of { enabled : bool }
    | Cupertino_switch_props of
        { value : bool
        ; enabled : bool
        }
    | Text_input_props of
        { session_id : int64
        ; document_revision : int64
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; obscure_text : bool
        ; keyboard_type : Text_editing.keyboard_type
        ; input_action : Text_editing.input_action
        ; accepted_local_revision : int64
        ; update_mode : Text_editing.update_mode
        ; autofocus : bool
        }
    | Overlay_props of
        { alignment : Navigation.overlay_alignment
        ; dismissible : bool
        }
    | Navigator_props of { restoration_scope_id : string option }
    | Page_props of
        { page_key : string
        ; transition : Navigation.page_transition
        ; can_pop : bool
        ; restoration_id : string option
        }
    | Safe_area_props of
        { left : bool
        ; top : bool
        ; right : bool
        ; bottom : bool
        ; minimum_left : float
        ; minimum_top : float
        ; minimum_right : float
        ; minimum_bottom : float
        }
    | Environment_boundary_props
    | Material_dialog_props of { barrier_dismissible : bool }
    | Native_widget_props of
        { kind_id : int
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }

  type event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type child =
    { widget : t
    ; parent_data : child_parent_data
    }

  type view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; kind : Kind.t
    ; props : props
    ; event_bindings : event_binding array
    ; children : child array
    ; fingerprint : int64
    }

  val view : t -> view
  val props_equal : props -> props -> bool
  val parent_data_equal : child_parent_data -> child_parent_data -> bool

  val material_checkbox
    :  ?key:Key.t
    -> ?enabled:bool
    -> value:bool
    -> on_changed:Event.Handler.t
    -> unit
    -> t

  val material_scaffold : ?key:Key.t -> ?app_bar:t -> body:t -> unit -> t
  val material_app_bar : ?key:Key.t -> ?center_title:bool -> title:t -> unit -> t

  val material_button
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> variant:material_button_variant
    -> on_press:Event.Handler.t
    -> child:t
    -> unit
    -> t

  val material_switch
    :  ?key:Key.t
    -> ?enabled:bool
    -> value:bool
    -> on_changed:Event.Handler.t
    -> unit
    -> t

  val material_list_tile
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?selected:bool
    -> ?subtitle:t
    -> ?leading:t
    -> ?trailing:t
    -> on_press:Event.Handler.t
    -> title:t
    -> unit
    -> t

  val material_divider : ?key:Key.t -> ?thickness:float -> unit -> t
  val material_card : ?key:Key.t -> ?elevation:float -> t -> t
  val material_progress : ?key:Key.t -> ?value:float -> unit -> t

  val cupertino_button
    :  ?key:Key.t
    -> ?enabled:bool
    -> on_press:Event.Handler.t
    -> child:t
    -> unit
    -> t

  val cupertino_switch
    :  ?key:Key.t
    -> ?enabled:bool
    -> value:bool
    -> on_changed:Event.Handler.t
    -> unit
    -> t

  val native_widget
    :  ?key:Key.t
    -> kind_id:int
    -> version:int
    -> capabilities:int64
    -> payload:bytes
    -> on_event:Event.Handler.t
    -> children:t list
    -> unit
    -> t
end
