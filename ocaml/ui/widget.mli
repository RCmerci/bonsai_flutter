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

(** Axis-specific scrolling content that is not an ordinary widget until it is
    placed in a bounded body slot or given an explicit finite extent. *)
module Viewport : sig
  type widget = t

  module Vertical : sig
    type t

    val with_test_id : Test_id.t -> t -> t
    val padding : insets:Layout.Edge_insets.t -> t -> t
    val decorated_box : decoration:Style.Decoration.t -> t -> t
    val semantics : properties:Semantics.t -> t -> t
    val safe_area : ?minimum:Layout.Edge_insets.t -> t -> t
    val theme : data:Theme.t -> t -> t
    val with_height : height:float -> t -> widget
  end

  module Horizontal : sig
    type t

    val with_test_id : Test_id.t -> t -> t
    val padding : insets:Layout.Edge_insets.t -> t -> t
    val decorated_box : decoration:Style.Decoration.t -> t -> t
    val semantics : properties:Semantics.t -> t -> t
    val safe_area : ?minimum:Layout.Edge_insets.t -> t -> t
    val theme : data:Theme.t -> t -> t
    val with_width : width:float -> t -> widget
  end
end

module Sparse_extent_override : sig
  type t =
    { index : int
    ; extent : float
    }
end

module Sparse_extent_transition : sig
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

(** A sliver is scroll-axis content that lives only inside a [Scroll_view].
    It is not a [t] and cannot be placed in a column, row, or body. *)
module Sliver : sig
  type widget = t
  type t

  val with_test_id : Test_id.t -> t -> t

  (** Wraps a single box widget. *)
  val box : ?key:Key.t -> widget -> t

  (** A non-virtualized list of box widgets. *)
  val list : ?key:Key.t -> widget list -> t

  (** Fills the remaining viewport extent. *)
  val fill : ?key:Key.t -> ?flex:int -> widget -> t

  (** Fixed-extent virtual list. Replaces [Native_widget.Virtual_list]. *)
  val fixed_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:widget list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** Varied-extent virtual list with sparse overrides.
      Replaces [Native_widget.Sparse_extent_list]. *)
  val varied_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:Sparse_extent_override.t list
    -> ?overscan:int
    -> ?transition:Sparse_extent_transition.t
    -> items:widget list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** SliverPadding wrapper. *)
  val padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t

  (** Collapsible app bar. *)
  val app_bar
    :  ?key:Key.t
    -> ?pinned:bool
    -> ?expanded_height:float
    -> ?collapsed_height:float
    -> widget
    -> t

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option
end

(** [Scroll_view] builds a [CustomScrollView]. Its children are [Sliver.t], not
    ordinary widgets. It still returns [Viewport.Vertical.t] /
    [Viewport.Horizontal.t] so the existing [Body.fill] /
    [Viewport.with_height] embedding paths are unchanged. *)
module Scroll_view : sig
  val vertical
    :  ?key:Key.t
    -> ?reverse:bool
    -> ?primary:bool
    -> on_scroll:Event.Handler.t
    -> Sliver.t list
    -> unit
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?reverse:bool
    -> on_scroll:Event.Handler.t
    -> Sliver.t list
    -> unit
    -> Viewport.Horizontal.t
end

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
  -> ?restoration_scope_id:Bonsai_flutter_spec.Id.Navigation.restoration_scope_id
  -> on_pop:Event.Handler.t
  -> t list
  -> t

(** [page] creates a declarative Navigator page. [presentation] defaults to
    [Navigation.Standard Navigation.None]. *)
val page
  :  ?key:Key.t
  -> page_key:Bonsai_flutter_spec.Id.Navigation.page_key
  -> ?presentation:Navigation.page_presentation
  -> ?can_pop:bool
  -> ?restoration_id:Bonsai_flutter_spec.Id.Navigation.restoration_id
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
  -> ?max_utf8_bytes:int
  -> session_id:Bonsai_flutter_spec.Id.Text_input.session_id
  -> document_revision:Bonsai_flutter_spec.Id.Text_input.document_revision
  -> accepted_local_revision:Bonsai_flutter_spec.Id.Text_input.local_revision
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> ?on_limit_reached:Event.Handler.t
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

(** Content validated for framework slots that provide finite constraints. *)
module Body : sig
  type widget = t
  type t

  val static : widget -> t
  val with_test_id : Test_id.t -> t -> t
  val padding : insets:Layout.Edge_insets.t -> t -> t
  val decorated_box : decoration:Style.Decoration.t -> t -> t
  val semantics : properties:Semantics.t -> t -> t

  val safe_area
    :  ?left:bool
    -> ?top:bool
    -> ?right:bool
    -> ?bottom:bool
    -> ?minimum:Layout.Edge_insets.t
    -> t
    -> t

  val theme : data:Theme.t -> t -> t

  module Vertical : sig
    type child

    val fixed : widget -> child
    val fill : ?flex:int -> Viewport.Vertical.t -> child
    val create : ?key:Key.t -> child list -> t
  end

  module Horizontal : sig
    type child

    val fixed : widget -> child
    val fill : ?flex:int -> Viewport.Horizontal.t -> child
    val create : ?key:Key.t -> child list -> t
  end

  val overlay : ?key:Key.t -> base:t -> overlays:Stack.child list -> unit -> t
end

module For_testing : sig
  val kind_name : t -> string
  val key : t -> Key.t option
  val test_id : t -> Test_id.t option
  val children : t -> t array
  val text_content : t -> string option
end

module Private : sig
  type kind_tag =
    | K_empty
    | K_text
    | K_rich_text
    | K_icon
    | K_image
    | K_row
    | K_column
    | K_flex_row
    | K_flex_column
    | K_stack
    | K_button
    | K_padding
    | K_align
    | K_center
    | K_sized_box
    | K_constrained_box
    | K_decorated_box
    | K_clip
    | K_opacity
    | K_animated_opacity
    | K_transform
    | K_scroll_view
    | K_sliver_box
    | K_sliver_list
    | K_sliver_fill
    | K_sliver_fixed_extent
    | K_sliver_varied_extent
    | K_sliver_padding
    | K_sliver_app_bar
    | K_gesture
    | K_focus_scope
    | K_mouse_region
    | K_keyboard_listener
    | K_pressable
    | K_semantics
    | K_theme
    | K_material_scaffold
    | K_material_app_bar
    | K_material_elevated_button
    | K_material_text_button
    | K_material_icon_button
    | K_material_checkbox
    | K_material_switch
    | K_material_list_tile
    | K_material_divider
    | K_material_card
    | K_material_circular_progress_indicator
    | K_cupertino_button
    | K_cupertino_switch
    | K_text_input
    | K_overlay
    | K_navigator
    | K_page
    | K_safe_area
    | K_environment_boundary
    | K_material_dialog
    | K_native_widget

  val kind_tag_compare : kind_tag -> kind_tag -> int
  val kind_tag_equal : kind_tag -> kind_tag -> bool
  val kind_tag_to_string : kind_tag -> string

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

  type 'k node =
    | Empty : [ `Empty ] node
    | Text :
        { value : string
        ; style : Style.Text_style.Private.view option
        ; text_align : Style.Text_align.t
        ; max_lines : int option
        ; overflow : Style.Text_overflow.t
        }
        -> [ `Text ] node
    | Rich_text : { spans : string list } -> [ `Rich_text ] node
    | Icon :
        { code_point : int
        ; font_family : string option
        ; size : float option
        ; color : int32 option
        }
        -> [ `Icon ] node
    | Image :
        { uri : string
        ; fit : Style.Image_fit.t
        ; width : float option
        ; height : float option
        }
        -> [ `Image ] node
    | Row : [ `Row ] node
    | Column : [ `Column ] node
    | Flex_row : [ `Flex_row ] node
    | Flex_column : [ `Flex_column ] node
    | Stack : [ `Stack ] node
    | Button : { enabled : bool } -> [ `Button ] node
    | Pressable :
        { overlay_color : Style.Color.t
        ; release_delay_ms : int
        }
        -> [ `Pressable ] node
    | Padding :
        { left : float
        ; top : float
        ; right : float
        ; bottom : float
        }
        -> [ `Padding ] node
    | Align : { alignment : Layout.Alignment.t } -> [ `Align ] node
    | Center :
        { width_factor : float option
        ; height_factor : float option
        }
        -> [ `Center ] node
    | Sized_box :
        { width : float option
        ; height : float option
        }
        -> [ `Sized_box ] node
    | Constrained_box :
        { min_width : float
        ; max_width : float
        ; min_height : float
        ; max_height : float
        }
        -> [ `Constrained_box ] node
    | Decorated_box :
        { background : int32 option
        ; border_radius : float
        }
        -> [ `Decorated_box ] node
    | Clip : { behavior : Style.Clip.t } -> [ `Clip ] node
    | Opacity : { opacity : float } -> [ `Opacity ] node
    | Animated_opacity :
        { opacity : float
        ; animation : Animation.t
        }
        -> [ `Animated_opacity ] node
    | Transform : { matrix4 : float array } -> [ `Transform ] node
    | Scroll_view :
        { axis : Layout.Axis.t
        ; reverse : bool
        ; primary : bool
        }
        -> [ `Scroll_view ] node
    | Sliver_box : [ `Sliver_box ] node
    | Sliver_list : [ `Sliver_list ] node
    | Sliver_fill : { flex : int } -> [ `Sliver_fill ] node
    | Sliver_fixed_extent :
        { total_count : int
        ; first_index : int
        ; item_extent : float
        ; overscan : int
        }
        -> [ `Sliver_fixed_extent ] node
    | Sliver_varied_extent :
        { total_count : int
        ; first_index : int
        ; default_item_extent : float
        ; extent_overrides : Sparse_extent_override.t list
        ; overscan : int
        ; transition : Sparse_extent_transition.t option
        }
        -> [ `Sliver_varied_extent ] node
    | Sliver_padding :
        { left : float
        ; top : float
        ; right : float
        ; bottom : float
        }
        -> [ `Sliver_padding ] node
    | Sliver_app_bar :
        { pinned : bool
        ; expanded_height : float option
        ; collapsed_height : float option
        }
        -> [ `Sliver_app_bar ] node
    | Gesture : [ `Gesture ] node
    | Focus_scope : { autofocus : bool } -> [ `Focus_scope ] node
    | Mouse_region : { opaque : bool } -> [ `Mouse_region ] node
    | Keyboard_listener :
        { autofocus : bool
        ; key_policy : Event.Key_policy.t
        }
        -> [ `Keyboard_listener ] node
    | Semantics :
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
        -> [ `Semantics ] node
    | Theme :
        { brightness : Style.Brightness.t
        ; color_seed : int32
        }
        -> [ `Theme ] node
    | Material_scaffold : { has_app_bar : bool } -> [ `Material_scaffold ] node
    | Material_app_bar : { center_title : bool } -> [ `Material_app_bar ] node
    | Material_elevated_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_elevated_button ] node
    | Material_text_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_text_button ] node
    | Material_icon_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_icon_button ] node
    | Material_checkbox :
        { value : bool
        ; enabled : bool
        }
        -> [ `Material_checkbox ] node
    | Material_switch :
        { value : bool
        ; enabled : bool
        }
        -> [ `Material_switch ] node
    | Material_list_tile :
        { enabled : bool
        ; selected : bool
        ; has_subtitle : bool
        ; has_leading : bool
        ; has_trailing : bool
        }
        -> [ `Material_list_tile ] node
    | Material_divider : { thickness : float } -> [ `Material_divider ] node
    | Material_card : { elevation : float } -> [ `Material_card ] node
    | Material_circular_progress_indicator :
        { value : float option }
        -> [ `Material_circular_progress_indicator ] node
    | Cupertino_button : { enabled : bool } -> [ `Cupertino_button ] node
    | Cupertino_switch :
        { value : bool
        ; enabled : bool
        }
        -> [ `Cupertino_switch ] node
    | Text_input :
        { session_id : Bonsai_flutter_spec.Id.Text_input.session_id
        ; document_revision : Bonsai_flutter_spec.Id.Text_input.document_revision
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; obscure_text : bool
        ; keyboard_type : Text_editing.keyboard_type
        ; input_action : Text_editing.input_action
        ; accepted_local_revision : Bonsai_flutter_spec.Id.Text_input.local_revision
        ; update_mode : Text_editing.update_mode
        ; autofocus : bool
        ; max_utf8_bytes : int option
        }
        -> [ `Text_input ] node
    | Overlay :
        { alignment : Navigation.overlay_alignment
        ; dismissible : bool
        }
        -> [ `Overlay ] node
    | Navigator :
        { restoration_scope_id :
            Bonsai_flutter_spec.Id.Navigation.restoration_scope_id option
        }
        -> [ `Navigator ] node
    | Page :
        { page_key : Bonsai_flutter_spec.Id.Navigation.page_key
        ; presentation : Navigation.page_presentation
        ; can_pop : bool
        ; restoration_id : Bonsai_flutter_spec.Id.Navigation.restoration_id option
        }
        -> [ `Page ] node
    | Safe_area :
        { left : bool
        ; top : bool
        ; right : bool
        ; bottom : bool
        ; minimum_left : float
        ; minimum_top : float
        ; minimum_right : float
        ; minimum_bottom : float
        }
        -> [ `Safe_area ] node
    | Environment_boundary : [ `Environment_boundary ] node
    | Material_dialog : { barrier_dismissible : bool } -> [ `Material_dialog ] node
    | Native_widget :
        { kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }
        -> [ `Native_widget ] node

  type event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type child =
    { widget : t
    ; parent_data : child_parent_data
    }

  type 'k view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; node : 'k node
    ; event_bindings : event_binding array
    ; children : child array
    ; fingerprint : int64
    }

  type any_view = Av : 'k view -> any_view

  val view : t -> any_view
  val node_equal_widgets : t -> t -> bool
  val kind_tag_of_widget : t -> kind_tag
  val node_kind_tag : 'k node -> kind_tag
  val node_equal : 'k1 node -> 'k2 node -> bool
  val parent_data_equal : child_parent_data -> child_parent_data -> bool

  val material_checkbox
    :  ?key:Key.t
    -> ?enabled:bool
    -> value:bool
    -> on_changed:Event.Handler.t
    -> unit
    -> t

  val material_scaffold : ?key:Key.t -> ?app_bar:t -> body:Body.t -> unit -> t
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
    -> kind_id:Bonsai_flutter_spec.Id.Native_widget.kind_id
    -> version:int
    -> capabilities:int64
    -> payload:bytes
    -> on_event:Event.Handler.t
    -> children:t list
    -> unit
    -> t

  val vertical_viewport : t -> Viewport.Vertical.t
  val horizontal_viewport : t -> Viewport.Horizontal.t

  val native_widget_with_body_children
    :  ?key:Key.t
    -> kind_id:Bonsai_flutter_spec.Id.Native_widget.kind_id
    -> version:int
    -> capabilities:int64
    -> payload:bytes
    -> on_event:Event.Handler.t
    -> bodies:Body.t list
    -> trailing_children:t list
    -> unit
    -> t
end
