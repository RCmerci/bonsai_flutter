(** Immutable, typed logical UI nodes.

    This module is renderer-independent. Application keys are optional and
    event closures remain in OCaml. *)

type t

(** Compile-time evidence that a widget root has an application key. *)
module Keyed : sig
  type widget = t
  type t

  (** [create ~key widget] returns [widget] with [key] on its existing root.
      Any previous root key is replaced; no wrapper node is added. *)
  val create : key:Key.t -> widget -> t
end

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
    val theme : data:Theme.data -> t -> t
    val with_height : height:float -> t -> widget
  end

  module Horizontal : sig
    type t

    val with_test_id : Test_id.t -> t -> t
    val padding : insets:Layout.Edge_insets.t -> t -> t
    val decorated_box : decoration:Style.Decoration.t -> t -> t
    val semantics : properties:Semantics.t -> t -> t
    val safe_area : ?minimum:Layout.Edge_insets.t -> t -> t
    val theme : data:Theme.data -> t -> t
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

  type t

  val create
    :  ?enabled:bool
    -> expand_duration_ms:int
    -> collapse_duration_ms:int
    -> ?expand_curve:curve
    -> ?collapse_curve:curve
    -> unit
    -> t

  val enabled : t -> bool
  val expand_duration_ms : t -> int
  val collapse_duration_ms : t -> int
  val expand_curve : t -> curve
  val collapse_curve : t -> curve
end

(** A sliver is scroll-axis content that lives only inside a [Scroll_view].
    It is not a [t] and cannot be placed in a column, row, or body. *)
module Sliver : sig
  type widget = t
  type t

  module Window : sig
    type t =
      { first_index : int
      ; last_exclusive : int
      }

    (** [create] expands a painted logical range by [overscan] on both sides
        and clamps the result to [0, total_count). *)
    val create
      :  total_count:int
      -> overscan:int
      -> visible_first_index:int
      -> visible_last_exclusive:int
      -> t
  end

  val with_test_id : Test_id.t -> t -> t

  (** Wraps a single box widget. *)
  val box : ?key:Key.t -> widget -> t

  (** A non-virtualized list of box widgets. *)
  val list : ?key:Key.t -> widget list -> t

  (** Fills the remaining viewport extent. *)
  val fill : ?key:Key.t -> widget -> t

  (** Fixed-extent virtual list over [total_count] logical items. [first_index]
      and [items] are the keyed materialized window owned by the application.
      [overscan] guides both [Window.create] and viewport cache derivation; it
      does not fetch or create widgets. [on_visible_range] receives only the
      painted half-open logical range. *)
  val fixed_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** Varied-extent virtual list with sparse overrides. Window ownership and
      painted-range semantics match [fixed_extent]. Extents are known values;
      Flutter does not measure arbitrary row heights for the application. *)
  val varied_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:Sparse_extent_override.t list
    -> ?overscan:int
    -> ?transition:Sparse_extent_transition.t
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** SliverPadding wrapper. *)
  val padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option
end

(** [Scroll_view] builds a [CustomScrollView]. Its children are [Sliver.t], not
    ordinary widgets. It returns an axis-specific viewport. [cache_extent],
    when explicit or derived from virtual slivers, must be finite and
    non-negative. One scroll-view-owned coordinator arbitrates implicit initial
    anchors across all virtual children. *)
module Scroll_view : sig
  val vertical
    :  ?key:Key.t
    -> ?reverse:bool
    -> ?primary:bool
    -> ?cache_extent:float
    -> on_scroll:Event.Handler.t
    -> Sliver.t list
    -> unit
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?reverse:bool
    -> ?cache_extent:float
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
val preferred_size : ?key:Key.t -> height:float -> t -> t

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

val theme : ?key:Key.t -> data:Theme.data -> t -> t

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

  val theme : data:Theme.data -> t -> t

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
    | K_preferred_size
    | K_gesture
    | K_focus_scope
    | K_mouse_region
    | K_keyboard_listener
    | K_pressable
    | K_semantics
    | K_theme
    | K_material_scaffold
    | K_material_elevated_button
    | K_material_text_button
    | K_material_icon_button
    | K_material_filled_button
    | K_material_filled_tonal_button
    | K_material_outlined_button
    | K_material_floating_action_button
    | K_material_navigation_bar
    | K_material_radio_group
    | K_material_segmented_button
    | K_material_slider
    | K_material_range_slider
    | K_material_action_chip
    | K_material_filter_chip
    | K_material_choice_chip
    | K_material_input_chip
    | K_material_search_bar
    | K_material_text_field
    | K_material_data_table
    | K_material_stepper
    | K_material_expansion_panel_list
    | K_material_simple_dialog
    | K_material_fullscreen_dialog
    | K_material_checkbox
    | K_material_switch
    | K_material_divider
    | K_material_card
    | K_material_circular_progress_indicator
    | K_material_linear_progress_indicator
    | K_material_expressive
    | K_cupertino_button
    | K_cupertino_switch
    | K_overlay
    | K_navigator
    | K_page
    | K_safe_area
    | K_environment_boundary
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
    | Filled
    | Filled_tonal
    | Outlined
    | Elevated
    | Text_button
    | Icon_button

  type material_floating_action_button_location =
    | Start_float
    | Center_float
    | End_float
    | Start_docked
    | Center_docked
    | End_docked

  type material_floating_action_button_variant =
    | Small
    | Standard
    | Large
    | Extended

  type material_navigation_destination =
    { label : string
    ; has_selected_icon : bool
    ; badge_count : int option
    ; badge_dot : bool
    ; semantic_label : string option
    }

  type material_navigation_bar_layout =
    | Auto
    | Compact
    | Wide

  type material_navigation_bar_visibility =
    | Always
    | Selected
    | Never

  type material_navigation_bar_alignment =
    | Start
    | Center
    | End

  type material_navigation_bar_size =
    | Small_bar
    | Medium_bar

  type material_navigation_bar_shape =
    | Round_bar
    | Square_bar

  type material_navigation_bar_density =
    | Regular_bar
    | Compact_bar

  type material_radio_option =
    { option_id : int64
    ; enabled : bool
    ; has_label : bool
    }

  type material_segment =
    { segment_id : int64
    ; has_icon : bool
    }

  type material_chip_variant =
    | Action
    | Filter
    | Choice
    | Input

  type material_chip_presentation =
    | Flat_chip
    | Elevated_chip

  type material_card_variant =
    | Elevated_card
    | Filled_card
    | Outlined_card

  type material_data_table_column =
    { column_id : int64
    ; tooltip : string option
    ; numeric : bool
    ; sortable : bool
    }

  type material_data_table_cell =
    { placeholder : bool
    ; show_edit_icon : bool
    ; activatable : bool
    }

  type material_data_table_row =
    { row_id : int64
    ; selected : bool
    ; selection_enabled : bool
    ; cells : material_data_table_cell list
    }

  type material_step_state =
    | Step_indexed
    | Step_editing
    | Step_complete
    | Step_disabled
    | Step_error

  type material_step =
    { step_id : int64
    ; active : bool
    ; state : material_step_state
    ; has_subtitle : bool
    ; has_label : bool
    }

  type material_expansion_panel_policy =
    | Multiple_panels
    | Single_panel

  type material_expansion_panel =
    { panel_id : int64
    ; enabled : bool
    ; can_tap_on_header : bool
    }

  type material_simple_dialog_option =
    { option_id : int64
    ; enabled : bool
    }

  type material_expressive_item =
    { item_id : int64
    ; kind : int
    ; label : string
    ; enabled : bool
    ; selected : bool
    ; child_count : int
    }

  type material_expressive_text_input =
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
        ; cache_extent : float option
        }
        -> [ `Scroll_view ] node
    | Sliver_box : [ `Sliver_box ] node
    | Sliver_list : [ `Sliver_list ] node
    | Sliver_fill : [ `Sliver_fill ] node
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
        ; floating : bool
        ; snap : bool
        ; has_leading : bool
        ; background_color : int32 option
        ; foreground_color : int32 option
        ; action_count : int
        ; center_title : bool
        ; variant : int
        ; shape : int
        ; density : int
        ; semantic_label : string option
        }
        -> [ `Sliver_app_bar ] node
    | Preferred_size : { height : float } -> [ `Preferred_size ] node
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
    | Theme : Theme.Private.data_view -> [ `Theme ] node
    | Material_scaffold :
        { has_app_bar : bool
        ; has_floating_action_button : bool
        ; floating_action_button_location : material_floating_action_button_location
        ; has_bottom_navigation_bar : bool
        ; has_bottom_sheet : bool
        }
        -> [ `Material_scaffold ] node
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
        }
        -> [ `Material_icon_button ] node
    | Material_filled_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_filled_button ] node
    | Material_filled_tonal_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_filled_tonal_button ] node
    | Material_outlined_button :
        { variant : material_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_outlined_button ] node
    | Material_floating_action_button :
        { variant : material_floating_action_button_variant
        ; enabled : bool
        ; autofocus : bool
        }
        -> [ `Material_floating_action_button ] node
    | Material_navigation_bar :
        { selected_index : int
        ; destinations : material_navigation_destination list
        ; layout : material_navigation_bar_layout
        ; alignment : material_navigation_bar_alignment
        ; label_behavior : material_navigation_bar_visibility
        ; icon_behavior : material_navigation_bar_visibility
        ; size : material_navigation_bar_size
        ; shape : material_navigation_bar_shape
        ; density : material_navigation_bar_density
        ; safe_area : bool
        ; semantic_label : string option
        }
        -> [ `Material_navigation_bar ] node
    | Material_radio_group :
        { selected_id : int64 option
        ; options : material_radio_option list
        }
        -> [ `Material_radio_group ] node
    | Material_segmented_button :
        { selected_ids : int64 list
        ; enabled : bool
        ; multi_selection_enabled : bool
        ; segments : material_segment list
        }
        -> [ `Material_segmented_button ] node
    | Material_slider :
        { value : float
        ; min : float
        ; max : float
        ; divisions : int option
        ; label : string option
        ; enabled : bool
        ; has_on_change : bool
        ; kind : int
        }
        -> [ `Material_slider ] node
    | Material_range_slider :
        { start : float
        ; end_ : float
        ; min : float
        ; max : float
        ; divisions : int option
        ; label_start : string option
        ; label_end : string option
        ; enabled : bool
        ; has_on_change : bool
        ; kind : int
        }
        -> [ `Material_range_slider ] node
    | Material_action_chip :
        { variant : material_chip_variant
        ; presentation : material_chip_presentation
        ; enabled : bool
        ; selected : bool
        ; has_leading : bool
        ; has_on_delete : bool
        }
        -> [ `Material_action_chip ] node
    | Material_filter_chip :
        { variant : material_chip_variant
        ; presentation : material_chip_presentation
        ; enabled : bool
        ; selected : bool
        ; has_leading : bool
        ; has_on_delete : bool
        }
        -> [ `Material_filter_chip ] node
    | Material_choice_chip :
        { variant : material_chip_variant
        ; presentation : material_chip_presentation
        ; enabled : bool
        ; selected : bool
        ; has_leading : bool
        ; has_on_delete : bool
        }
        -> [ `Material_choice_chip ] node
    | Material_input_chip :
        { variant : material_chip_variant
        ; presentation : material_chip_presentation
        ; enabled : bool
        ; selected : bool
        ; has_leading : bool
        ; has_on_delete : bool
        }
        -> [ `Material_input_chip ] node
    | Material_search_bar :
        { session_id : Bonsai_flutter_spec.Id.Text_input.session_id
        ; document_revision : Bonsai_flutter_spec.Id.Text_input.document_revision
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; keyboard_type : Text_editing.keyboard_type
        ; input_action : Text_editing.input_action
        ; accepted_local_revision : Bonsai_flutter_spec.Id.Text_input.local_revision
        ; update_mode : Text_editing.update_mode
        ; autofocus : bool
        ; max_utf8_bytes : int option
        ; has_leading : bool
        ; trailing_count : int
        ; hint_text : string option
        ; has_on_tap : bool
        }
        -> [ `Material_search_bar ] node
    | Material_text_field :
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
        ; max_utf8_bytes : int option
        ; variant : int
        ; label : string option
        ; supporting_text : string option
        ; error_text : string option
        ; has_leading : bool
        ; has_trailing : bool
        ; max_lines : int
        ; autofocus : bool
        }
        -> [ `Material_text_field ] node
    | Material_data_table :
        { columns : material_data_table_column list
        ; rows : material_data_table_row list
        ; sort_column_id : int64 option
        ; sort_ascending : bool
        ; selected_row_ids : int64 list
        ; has_on_sort : bool
        ; has_on_row_selected : bool
        ; has_on_select_all : bool
        ; has_on_cell_activate : bool
        }
        -> [ `Material_data_table ] node
    | Material_stepper :
        { orientation : Layout.Axis.t
        ; current_step_id : int64
        ; steps : material_step list
        }
        -> [ `Material_stepper ] node
    | Material_expansion_panel_list :
        { policy : material_expansion_panel_policy
        ; expanded_ids : int64 list
        ; panels : material_expansion_panel list
        }
        -> [ `Material_expansion_panel_list ] node
    | Material_simple_dialog :
        { has_title : bool
        ; options : material_simple_dialog_option list
        }
        -> [ `Material_simple_dialog ] node
    | Material_fullscreen_dialog : [ `Material_fullscreen_dialog ] node
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
    | Material_divider :
        { orientation : Layout.Axis.t
        ; thickness : float
        ; spacing : float
        ; indent : float
        ; end_indent : float
        }
        -> [ `Material_divider ] node
    | Material_card :
        { variant : material_card_variant
        ; elevation : float
        }
        -> [ `Material_card ] node
    | Material_circular_progress_indicator :
        { value : float option
        ; wavy : bool
        }
        -> [ `Material_circular_progress_indicator ] node
    | Material_linear_progress_indicator :
        { value : float option
        ; wavy : bool
        }
        -> [ `Material_linear_progress_indicator ] node
    | Material_expressive :
        { component : int
        ; variant : int
        ; flags : int64
        ; primary_text : string option
        ; secondary_text : string option
        ; value : float option
        ; end_value : float option
        ; selected_ids : int64 list
        ; items : material_expressive_item list
        ; text_input : material_expressive_text_input option
        }
        -> [ `Material_expressive ] node
    | Cupertino_button : { enabled : bool } -> [ `Cupertino_button ] node
    | Cupertino_switch :
        { value : bool
        ; enabled : bool
        }
        -> [ `Cupertino_switch ] node
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

  val material_scaffold
    :  ?key:Key.t
    -> ?app_bar:t
    -> ?floating_action_button:t
    -> ?floating_action_button_location:material_floating_action_button_location
    -> ?bottom_navigation_bar:t
    -> ?bottom_sheet:t
    -> body:Body.t
    -> unit
    -> t

  val material_button
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> variant:material_button_variant
    -> on_press:Event.Handler.t
    -> child:t
    -> unit
    -> t

  val material_floating_action_button
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> variant:material_floating_action_button_variant
    -> on_press:Event.Handler.t
    -> icon:t
    -> label:t
    -> unit
    -> t

  val material_navigation_bar
    :  ?key:Key.t
    -> selected_index:int
    -> destinations:material_navigation_destination list
    -> layout:material_navigation_bar_layout
    -> alignment:material_navigation_bar_alignment
    -> label_behavior:material_navigation_bar_visibility
    -> icon_behavior:material_navigation_bar_visibility
    -> size:material_navigation_bar_size
    -> shape:material_navigation_bar_shape
    -> density:material_navigation_bar_density
    -> safe_area:bool
    -> semantic_label:string option
    -> children:t list
    -> on_select:Event.Handler.t
    -> unit
    -> t

  val material_radio_group
    :  ?key:Key.t
    -> selected_id:int64 option
    -> options:material_radio_option list
    -> children:t list
    -> on_select:Event.Handler.t
    -> unit
    -> t

  val material_segmented_button
    :  ?key:Key.t
    -> selected_ids:int64 list
    -> enabled:bool
    -> multi_selection_enabled:bool
    -> segments:material_segment list
    -> children:t list
    -> on_selection_changed:Event.Handler.t
    -> unit
    -> t

  val material_slider
    :  ?key:Key.t
    -> value:float
    -> min:float
    -> max:float
    -> divisions:int option
    -> label:string option
    -> enabled:bool
    -> kind:int
    -> on_change:Event.Handler.t option
    -> on_change_end:Event.Handler.t
    -> unit
    -> t

  val material_range_slider
    :  ?key:Key.t
    -> start:float
    -> end_:float
    -> min:float
    -> max:float
    -> divisions:int option
    -> label_start:string option
    -> label_end:string option
    -> enabled:bool
    -> kind:int
    -> on_change:Event.Handler.t option
    -> on_change_end:Event.Handler.t
    -> unit
    -> t

  val material_chip
    :  ?key:Key.t
    -> variant:material_chip_variant
    -> presentation:material_chip_presentation
    -> enabled:bool
    -> selected:bool
    -> ?avatar:t
    -> on_press:Event.Handler.t
    -> ?on_delete:Event.Handler.t
    -> label:t
    -> unit
    -> t

  val material_search_bar
    :  ?key:Key.t
    -> session_id:Bonsai_flutter_spec.Id.Text_input.session_id
    -> document_revision:Bonsai_flutter_spec.Id.Text_input.document_revision
    -> accepted_local_revision:Bonsai_flutter_spec.Id.Text_input.local_revision
    -> update_mode:Text_editing.update_mode
    -> value:Text_editing.Value.t
    -> enabled:bool
    -> read_only:bool
    -> keyboard_type:Text_editing.keyboard_type
    -> input_action:Text_editing.input_action
    -> autofocus:bool
    -> max_utf8_bytes:int option
    -> on_edit:Event.Handler.t
    -> on_submit:Event.Handler.t
    -> on_focus_changed:Event.Handler.t
    -> on_limit_reached:Event.Handler.t option
    -> leading:t option
    -> trailing:t list
    -> hint_text:string option
    -> on_tap:Event.Handler.t option
    -> unit
    -> t

  val material_text_field
    :  ?key:Key.t
    -> session_id:Bonsai_flutter_spec.Id.Text_input.session_id
    -> document_revision:Bonsai_flutter_spec.Id.Text_input.document_revision
    -> accepted_local_revision:Bonsai_flutter_spec.Id.Text_input.local_revision
    -> update_mode:Text_editing.update_mode
    -> value:Text_editing.Value.t
    -> enabled:bool
    -> read_only:bool
    -> obscure_text:bool
    -> keyboard_type:Text_editing.keyboard_type
    -> input_action:Text_editing.input_action
    -> max_utf8_bytes:int option
    -> variant:int
    -> label:string option
    -> supporting_text:string option
    -> error_text:string option
    -> leading:t option
    -> trailing:t option
    -> max_lines:int
    -> autofocus:bool
    -> on_edit:Event.Handler.t
    -> on_submit:Event.Handler.t
    -> on_focus_changed:Event.Handler.t
    -> on_limit_reached:Event.Handler.t option
    -> unit
    -> t

  val material_sliver_app_bar
    :  ?key:Key.t
    -> pinned:bool
    -> floating:bool
    -> snap:bool
    -> center_title:bool
    -> ?background_color:int32
    -> ?foreground_color:int32
    -> ?leading:t
    -> actions:t list
    -> variant:int
    -> shape:int
    -> density:int
    -> ?semantic_label:string
    -> title:t
    -> unit
    -> Sliver.t

  val material_data_table
    :  ?key:Key.t
    -> columns:material_data_table_column list
    -> rows:material_data_table_row list
    -> sort_column_id:int64 option
    -> sort_ascending:bool
    -> selected_row_ids:int64 list
    -> on_sort:Event.Handler.t option
    -> on_row_selected:Event.Handler.t option
    -> on_select_all:Event.Handler.t option
    -> on_cell_activate:Event.Handler.t option
    -> children:t list
    -> unit
    -> t

  val material_stepper
    :  ?key:Key.t
    -> orientation:Layout.Axis.t
    -> current_step_id:int64
    -> steps:material_step list
    -> on_step_selected:Event.Handler.t option
    -> on_continue:Event.Handler.t option
    -> on_cancel:Event.Handler.t option
    -> children:t list
    -> unit
    -> t

  val material_expansion_panel_list
    :  ?key:Key.t
    -> policy:material_expansion_panel_policy
    -> expanded_ids:int64 list
    -> panels:material_expansion_panel list
    -> on_expansion_changed:Event.Handler.t
    -> children:t list
    -> unit
    -> t

  val material_simple_dialog
    :  ?key:Key.t
    -> ?title:t
    -> options:material_simple_dialog_option list
    -> on_select:Event.Handler.t
    -> children:t list
    -> unit
    -> t

  val material_fullscreen_dialog : ?key:Key.t -> t -> t

  val material_switch
    :  ?key:Key.t
    -> ?enabled:bool
    -> value:bool
    -> on_changed:Event.Handler.t
    -> unit
    -> t

  val material_divider
    :  ?key:Key.t
    -> ?orientation:Layout.Axis.t
    -> ?thickness:float
    -> ?spacing:float
    -> ?indent:float
    -> ?end_indent:float
    -> unit
    -> t

  val material_card
    :  ?key:Key.t
    -> ?variant:material_card_variant
    -> ?elevation:float
    -> t
    -> t

  val material_circular_progress : ?key:Key.t -> ?value:float -> wavy:bool -> unit -> t
  val material_linear_progress : ?key:Key.t -> ?value:float -> wavy:bool -> unit -> t

  val material_expressive
    :  ?key:Key.t
    -> component:int
    -> ?variant:int
    -> ?flags:int64
    -> ?primary_text:string
    -> ?secondary_text:string
    -> ?value:float
    -> ?end_value:float
    -> ?selected_ids:int64 list
    -> ?items:material_expressive_item list
    -> ?text_input:material_expressive_text_input
    -> ?on_press:Event.Handler.t
    -> ?on_select:Event.Handler.t
    -> ?on_selection_changed:Event.Handler.t
    -> ?on_active_changed:Event.Handler.t
    -> ?on_value_changed:Event.Handler.t
    -> ?on_change_end:Event.Handler.t
    -> ?on_text_changed:Event.Handler.t
    -> ?on_text_edit:Event.Handler.t
    -> ?on_text_submit:Event.Handler.t
    -> ?on_focus_changed:Event.Handler.t
    -> ?on_limit_reached:Event.Handler.t
    -> ?on_civil_date_changed:Event.Handler.t
    -> ?on_civil_time_changed:Event.Handler.t
    -> ?on_search_opened:Event.Handler.t
    -> ?on_search_closed:Event.Handler.t
    -> children:t list
    -> unit
    -> t

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
