module ID = Bonsai_flutter_spec.Id

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
  | K_preferred_size
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

let kind_tag_compare left right = Stdlib.compare left right
let kind_tag_equal left right = kind_tag_compare left right = 0

let kind_tag_to_string = function
  | K_empty -> "Empty"
  | K_text -> "Text"
  | K_rich_text -> "Rich_text"
  | K_icon -> "Icon"
  | K_image -> "Image"
  | K_row -> "Row"
  | K_column -> "Column"
  | K_flex_row -> "Flex_row"
  | K_flex_column -> "Flex_column"
  | K_stack -> "Stack"
  | K_button -> "Button"
  | K_padding -> "Padding"
  | K_align -> "Align"
  | K_center -> "Center"
  | K_sized_box -> "Sized_box"
  | K_constrained_box -> "Constrained_box"
  | K_decorated_box -> "Decorated_box"
  | K_clip -> "Clip"
  | K_opacity -> "Opacity"
  | K_animated_opacity -> "Animated_opacity"
  | K_transform -> "Transform"
  | K_scroll_view -> "Scroll_view"
  | K_sliver_box -> "Sliver_box"
  | K_sliver_list -> "Sliver_list"
  | K_sliver_fill -> "Sliver_fill"
  | K_sliver_fixed_extent -> "Sliver_fixed_extent"
  | K_sliver_varied_extent -> "Sliver_varied_extent"
  | K_sliver_padding -> "Sliver_padding"
  | K_sliver_app_bar -> "Sliver_app_bar"
  | K_preferred_size -> "Preferred_size"
  | K_gesture -> "Gesture"
  | K_focus_scope -> "Focus_scope"
  | K_mouse_region -> "Mouse_region"
  | K_keyboard_listener -> "Keyboard_listener"
  | K_pressable -> "Pressable"
  | K_semantics -> "Semantics"
  | K_theme -> "Theme"
  | K_material_scaffold -> "Material_scaffold"
  | K_material_app_bar -> "Material_app_bar"
  | K_material_elevated_button -> "Material_elevated_button"
  | K_material_text_button -> "Material_text_button"
  | K_material_icon_button -> "Material_icon_button"
  | K_material_checkbox -> "Material_checkbox"
  | K_material_switch -> "Material_switch"
  | K_material_list_tile -> "Material_list_tile"
  | K_material_divider -> "Material_divider"
  | K_material_card -> "Material_card"
  | K_material_circular_progress_indicator -> "Material_circular_progress_indicator"
  | K_cupertino_button -> "Cupertino_button"
  | K_cupertino_switch -> "Cupertino_switch"
  | K_text_input -> "Text_input"
  | K_overlay -> "Overlay"
  | K_navigator -> "Navigator"
  | K_page -> "Page"
  | K_safe_area -> "Safe_area"
  | K_environment_boundary -> "Environment_boundary"
  | K_material_dialog -> "Material_dialog"
  | K_native_widget -> "Native_widget"
;;

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

module Sparse_extent_override = struct
  type t =
    { index : int
    ; extent : float
    }
end

module Sparse_extent_transition = struct
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

  let validate_duration label duration =
    if duration < 0 || Int64.of_int duration > 0xffff_ffffL
    then
      invalid_arg
        (Printf.sprintf "Widget.Sparse_extent_transition: %s must be a valid u32" label)
  ;;

  let create
        ?(enabled = true)
        ~expand_duration_ms
        ~collapse_duration_ms
        ?(expand_curve = Ease_out_cubic)
        ?(collapse_curve = Ease_in_out_cubic)
        ()
    =
    validate_duration "expand_duration_ms" expand_duration_ms;
    validate_duration "collapse_duration_ms" collapse_duration_ms;
    { enabled; expand_duration_ms; collapse_duration_ms; expand_curve; collapse_curve }
  ;;
end

module Private_types = struct
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
        ; expanded_height : float option
        ; collapsed_height : float option
        ; floating : bool
        ; snap : bool
        ; stretch : bool
        ; toolbar_height : float
        ; has_leading : bool
        ; has_flexible_space : bool
        ; has_bottom : bool
        ; has_actions : bool
        ; force_elevated : bool
        ; automatically_imply_leading : bool
        ; center_title : bool option
        ; background_color : int32 option
        ; foreground_color : int32 option
        ; elevation : float option
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
        { session_id : ID.Text_input.session_id
        ; document_revision : ID.Text_input.document_revision
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; obscure_text : bool
        ; keyboard_type : Text_editing.keyboard_type
        ; input_action : Text_editing.input_action
        ; accepted_local_revision : ID.Text_input.local_revision
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
        { restoration_scope_id : ID.Navigation.restoration_scope_id option }
        -> [ `Navigator ] node
    | Page :
        { page_key : ID.Navigation.page_key
        ; presentation : Navigation.page_presentation
        ; can_pop : bool
        ; restoration_id : ID.Navigation.restoration_id option
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
        { kind_id : ID.Native_widget.kind_id
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }
        -> [ `Native_widget ] node

  type event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type t = T : 'k view -> t

  and child =
    { widget : t
    ; parent_data : child_parent_data
    }

  and 'k view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; node : 'k node
    ; event_bindings : event_binding array
    ; children : child array
    ; fingerprint : int64
    }
end

[@@@ocaml.warning "-34"]

type t = Private_types.t
type child = Private_types.child
type 'k view = 'k Private_types.view
type 'k node = 'k Private_types.node
type event_binding = Private_types.event_binding

[@@@ocaml.warning "+34"]

open Private_types

let node_kind_tag (type k) (n : k node) : kind_tag =
  match n with
  | Empty -> K_empty
  | Text _ -> K_text
  | Rich_text _ -> K_rich_text
  | Icon _ -> K_icon
  | Image _ -> K_image
  | Row -> K_row
  | Column -> K_column
  | Flex_row -> K_flex_row
  | Flex_column -> K_flex_column
  | Stack -> K_stack
  | Button _ -> K_button
  | Pressable _ -> K_pressable
  | Padding _ -> K_padding
  | Align _ -> K_align
  | Center _ -> K_center
  | Sized_box _ -> K_sized_box
  | Constrained_box _ -> K_constrained_box
  | Decorated_box _ -> K_decorated_box
  | Clip _ -> K_clip
  | Opacity _ -> K_opacity
  | Animated_opacity _ -> K_animated_opacity
  | Transform _ -> K_transform
  | Scroll_view _ -> K_scroll_view
  | Sliver_box -> K_sliver_box
  | Sliver_list -> K_sliver_list
  | Sliver_fill -> K_sliver_fill
  | Sliver_fixed_extent _ -> K_sliver_fixed_extent
  | Sliver_varied_extent _ -> K_sliver_varied_extent
  | Sliver_padding _ -> K_sliver_padding
  | Sliver_app_bar _ -> K_sliver_app_bar
  | Preferred_size _ -> K_preferred_size
  | Gesture -> K_gesture
  | Focus_scope _ -> K_focus_scope
  | Mouse_region _ -> K_mouse_region
  | Keyboard_listener _ -> K_keyboard_listener
  | Semantics _ -> K_semantics
  | Theme _ -> K_theme
  | Material_scaffold _ -> K_material_scaffold
  | Material_app_bar _ -> K_material_app_bar
  | Material_elevated_button _ -> K_material_elevated_button
  | Material_text_button _ -> K_material_text_button
  | Material_icon_button _ -> K_material_icon_button
  | Material_checkbox _ -> K_material_checkbox
  | Material_switch _ -> K_material_switch
  | Material_list_tile _ -> K_material_list_tile
  | Material_divider _ -> K_material_divider
  | Material_card _ -> K_material_card
  | Material_circular_progress_indicator _ -> K_material_circular_progress_indicator
  | Cupertino_button _ -> K_cupertino_button
  | Cupertino_switch _ -> K_cupertino_switch
  | Text_input _ -> K_text_input
  | Overlay _ -> K_overlay
  | Navigator _ -> K_navigator
  | Page _ -> K_page
  | Safe_area _ -> K_safe_area
  | Environment_boundary -> K_environment_boundary
  | Material_dialog _ -> K_material_dialog
  | Native_widget _ -> K_native_widget
;;

let node_equal (type k1 k2) (a : k1 node) (b : k2 node) : bool =
  match a, b with
  | Empty, Empty
  | Row, Row
  | Column, Column
  | Flex_row, Flex_row
  | Flex_column, Flex_column
  | Stack, Stack
  | Gesture, Gesture
  | Environment_boundary, Environment_boundary -> true
  | Text x, Text y ->
    String.equal x.value y.value
    && Option.equal ( = ) x.style y.style
    && x.text_align = y.text_align
    && Option.equal Int.equal x.max_lines y.max_lines
    && x.overflow = y.overflow
  | Rich_text x, Rich_text y -> List.equal String.equal x.spans y.spans
  | Icon x, Icon y ->
    x.code_point = y.code_point
    && Option.equal String.equal x.font_family y.font_family
    && Option.equal Float.equal x.size y.size
    && Option.equal Int32.equal x.color y.color
  | Image x, Image y ->
    String.equal x.uri y.uri
    && x.fit = y.fit
    && Option.equal Float.equal x.width y.width
    && Option.equal Float.equal x.height y.height
  | Button x, Button y -> Bool.equal x.enabled y.enabled
  | Pressable x, Pressable y ->
    Int32.equal
      (Style.Color.Private.to_argb32 x.overlay_color)
      (Style.Color.Private.to_argb32 y.overlay_color)
    && x.release_delay_ms = y.release_delay_ms
  | Padding x, Padding y ->
    Float.equal x.left y.left
    && Float.equal x.top y.top
    && Float.equal x.right y.right
    && Float.equal x.bottom y.bottom
  | Align x, Align y -> x.alignment = y.alignment
  | Center x, Center y ->
    Option.equal Float.equal x.width_factor y.width_factor
    && Option.equal Float.equal x.height_factor y.height_factor
  | Sized_box x, Sized_box y ->
    Option.equal Float.equal x.width y.width && Option.equal Float.equal x.height y.height
  | Constrained_box x, Constrained_box y ->
    Float.equal x.min_width y.min_width
    && Float.equal x.max_width y.max_width
    && Float.equal x.min_height y.min_height
    && Float.equal x.max_height y.max_height
  | Decorated_box x, Decorated_box y ->
    Option.equal Int32.equal x.background y.background
    && Float.equal x.border_radius y.border_radius
  | Clip x, Clip y -> x.behavior = y.behavior
  | Opacity x, Opacity y -> Float.equal x.opacity y.opacity
  | Animated_opacity x, Animated_opacity y ->
    Float.equal x.opacity y.opacity && Animation.Private.equal x.animation y.animation
  | Transform x, Transform y ->
    Array.length x.matrix4 = Array.length y.matrix4
    && Array.for_all2 Float.equal x.matrix4 y.matrix4
  | Scroll_view x, Scroll_view y ->
    x.axis = y.axis
    && Bool.equal x.reverse y.reverse
    && Bool.equal x.primary y.primary
    && Option.equal Float.equal x.cache_extent y.cache_extent
  | Sliver_box, Sliver_box -> true
  | Sliver_list, Sliver_list -> true
  | Sliver_fill, Sliver_fill -> true
  | Sliver_fixed_extent x, Sliver_fixed_extent y ->
    Int.equal x.total_count y.total_count
    && Int.equal x.first_index y.first_index
    && Float.equal x.item_extent y.item_extent
    && Int.equal x.overscan y.overscan
  | Sliver_varied_extent x, Sliver_varied_extent y ->
    Int.equal x.total_count y.total_count
    && Int.equal x.first_index y.first_index
    && Float.equal x.default_item_extent y.default_item_extent
    && Int.equal x.overscan y.overscan
    && List.length x.extent_overrides = List.length y.extent_overrides
    && List.for_all2
         (fun (a : Sparse_extent_override.t) (b : Sparse_extent_override.t) ->
            Int.equal a.index b.index && Float.equal a.extent b.extent)
         x.extent_overrides
         y.extent_overrides
    && Option.equal
         (fun a b ->
            Bool.equal a.Sparse_extent_transition.enabled b.enabled
            && Int.equal a.expand_duration_ms b.expand_duration_ms
            && Int.equal a.collapse_duration_ms b.collapse_duration_ms
            && a.expand_curve = b.expand_curve
            && a.collapse_curve = b.collapse_curve)
         x.transition
         y.transition
  | Sliver_padding x, Sliver_padding y ->
    Float.equal x.left y.left
    && Float.equal x.top y.top
    && Float.equal x.right y.right
    && Float.equal x.bottom y.bottom
  | Sliver_app_bar x, Sliver_app_bar y ->
    Bool.equal x.pinned y.pinned
    && Option.equal Float.equal x.expanded_height y.expanded_height
    && Option.equal Float.equal x.collapsed_height y.collapsed_height
    && Bool.equal x.floating y.floating
    && Bool.equal x.snap y.snap
    && Bool.equal x.stretch y.stretch
    && Float.equal x.toolbar_height y.toolbar_height
    && Bool.equal x.has_leading y.has_leading
    && Bool.equal x.has_flexible_space y.has_flexible_space
    && Bool.equal x.has_bottom y.has_bottom
    && Bool.equal x.has_actions y.has_actions
    && Bool.equal x.force_elevated y.force_elevated
    && Bool.equal x.automatically_imply_leading y.automatically_imply_leading
    && Option.equal Bool.equal x.center_title y.center_title
    && Option.equal Int32.equal x.background_color y.background_color
    && Option.equal Int32.equal x.foreground_color y.foreground_color
    && Option.equal Float.equal x.elevation y.elevation
  | Preferred_size x, Preferred_size y -> Float.equal x.height y.height
  | Focus_scope x, Focus_scope y -> Bool.equal x.autofocus y.autofocus
  | Mouse_region x, Mouse_region y -> Bool.equal x.opaque y.opaque
  | Keyboard_listener x, Keyboard_listener y ->
    Bool.equal x.autofocus y.autofocus && x.key_policy = y.key_policy
  | Semantics x, Semantics y ->
    Option.equal String.equal x.label y.label
    && Option.equal String.equal x.hint y.hint
    && Option.equal String.equal x.value y.value
    && Semantics.Role.equal x.role y.role
    && Option.equal Bool.equal x.enabled y.enabled
    && Option.equal Bool.equal x.selected y.selected
    && Option.equal Bool.equal x.checked y.checked
    && Option.equal Bool.equal x.focusable y.focusable
    && Bool.equal x.obscured y.obscured
    && Bool.equal x.live_region y.live_region
    && Option.equal Int.equal x.heading_level y.heading_level
    && Option.equal Float.equal x.sort_key y.sort_key
    && List.equal Semantics.Action.equal x.actions y.actions
  | Theme x, Theme y ->
    x.brightness = y.brightness && Int32.equal x.color_seed y.color_seed
  | Material_scaffold x, Material_scaffold y -> Bool.equal x.has_app_bar y.has_app_bar
  | Material_app_bar x, Material_app_bar y -> Bool.equal x.center_title y.center_title
  | Material_elevated_button x, Material_elevated_button y ->
    x.variant = y.variant
    && Bool.equal x.enabled y.enabled
    && Bool.equal x.autofocus y.autofocus
  | Material_text_button x, Material_text_button y ->
    x.variant = y.variant
    && Bool.equal x.enabled y.enabled
    && Bool.equal x.autofocus y.autofocus
  | Material_icon_button x, Material_icon_button y ->
    x.variant = y.variant
    && Bool.equal x.enabled y.enabled
    && Bool.equal x.autofocus y.autofocus
  | Material_checkbox x, Material_checkbox y ->
    Bool.equal x.value y.value && Bool.equal x.enabled y.enabled
  | Material_switch x, Material_switch y ->
    Bool.equal x.value y.value && Bool.equal x.enabled y.enabled
  | Material_list_tile x, Material_list_tile y ->
    Bool.equal x.enabled y.enabled
    && Bool.equal x.selected y.selected
    && Bool.equal x.has_subtitle y.has_subtitle
    && Bool.equal x.has_leading y.has_leading
    && Bool.equal x.has_trailing y.has_trailing
  | Material_divider x, Material_divider y -> Float.equal x.thickness y.thickness
  | Material_card x, Material_card y -> Float.equal x.elevation y.elevation
  | Material_circular_progress_indicator x, Material_circular_progress_indicator y ->
    Option.equal Float.equal x.value y.value
  | Cupertino_button x, Cupertino_button y -> Bool.equal x.enabled y.enabled
  | Cupertino_switch x, Cupertino_switch y ->
    Bool.equal x.value y.value && Bool.equal x.enabled y.enabled
  | Text_input x, Text_input y ->
    ID.Text_input.Session_id.equal x.session_id y.session_id
    && ID.Text_input.Document_revision.equal x.document_revision y.document_revision
    && Text_editing.Value.equal x.value y.value
    && Bool.equal x.enabled y.enabled
    && Bool.equal x.read_only y.read_only
    && Bool.equal x.obscure_text y.obscure_text
    && x.keyboard_type = y.keyboard_type
    && x.input_action = y.input_action
    && ID.Text_input.Local_revision.equal
         x.accepted_local_revision
         y.accepted_local_revision
    && x.update_mode = y.update_mode
    && Bool.equal x.autofocus y.autofocus
    && Option.equal Int.equal x.max_utf8_bytes y.max_utf8_bytes
  | Overlay x, Overlay y ->
    x.alignment = y.alignment && Bool.equal x.dismissible y.dismissible
  | Navigator x, Navigator y ->
    Option.equal
      ID.Navigation.Restoration_scope_id.equal
      x.restoration_scope_id
      y.restoration_scope_id
  | Page x, Page y ->
    ID.Navigation.Page_key.equal x.page_key y.page_key
    && x.presentation = y.presentation
    && Bool.equal x.can_pop y.can_pop
    && Option.equal ID.Navigation.Restoration_id.equal x.restoration_id y.restoration_id
  | Safe_area x, Safe_area y ->
    Bool.equal x.left y.left
    && Bool.equal x.top y.top
    && Bool.equal x.right y.right
    && Bool.equal x.bottom y.bottom
    && Float.equal x.minimum_left y.minimum_left
    && Float.equal x.minimum_top y.minimum_top
    && Float.equal x.minimum_right y.minimum_right
    && Float.equal x.minimum_bottom y.minimum_bottom
  | Material_dialog x, Material_dialog y ->
    Bool.equal x.barrier_dismissible y.barrier_dismissible
  | Native_widget x, Native_widget y ->
    x.kind_id = y.kind_id
    && x.version = y.version
    && Int64.equal x.capabilities y.capabilities
    && Bytes.equal x.payload y.payload
  | _ -> false
;;

let option_float_equal left right = Option.equal Float.equal left right

let parent_data_equal left right =
  match left, right with
  | No_parent_data, No_parent_data -> true
  | Flex_parent_data left, Flex_parent_data right ->
    left.flex = right.flex && left.fit = right.fit
  | Stack_position left, Stack_position right ->
    option_float_equal left.left right.left
    && option_float_equal left.top right.top
    && option_float_equal left.right right.right
    && option_float_equal left.bottom right.bottom
  | _ -> false
;;

let hash_combine state value =
  Int64.(mul (logxor state (of_int (Hashtbl.hash value))) 0x100000001b3L)
;;

let fingerprint (type k) ~key ~test_id ~(node : k node) ~event_bindings ~children =
  let state = ref 0xcbf29ce484222325L in
  state := hash_combine !state key;
  state := hash_combine !state test_id;
  state := hash_combine !state (node_kind_tag node);
  state := hash_combine !state node;
  Array.iter
    (fun binding ->
       state := hash_combine !state binding.tag;
       state := hash_combine !state (Event.Handler.name binding.handler))
    event_bindings;
  Array.iter
    (fun child ->
       state := hash_combine !state child.parent_data;
       let (T child_view) = child.widget in
       state := hash_combine !state child_view.fingerprint)
    children;
  !state
;;

let create_typed (type k) ~key ~(node : k node) ~event_bindings ~children =
  let test_id = None in
  let fingerprint = fingerprint ~key ~test_id ~node ~event_bindings ~children in
  T { key; test_id; node; event_bindings; children; fingerprint }
;;

let with_test_id test_id widget =
  let (T view) = widget in
  let fingerprint =
    fingerprint
      ~key:view.key
      ~test_id:(Some test_id)
      ~node:view.node
      ~event_bindings:view.event_bindings
      ~children:view.children
  in
  T { view with test_id = Some test_id; fingerprint }
;;

let plain_children widgets =
  widgets
  |> List.map (fun widget -> { widget; parent_data = No_parent_data })
  |> Array.of_list
;;

let empty ?key () = create_typed ~key ~node:Empty ~event_bindings:[||] ~children:[||]

let text
      ?key
      ?style
      ?(text_align = Style.Text_align.Start)
      ?max_lines
      ?(overflow = Style.Text_overflow.Clip)
      value
  =
  Option.iter
    (fun value ->
       if value <= 0 then invalid_arg "Widget.text: max_lines must be positive")
    max_lines;
  create_typed
    ~key
    ~node:
      (Text
         { value
         ; style = Option.map Style.Text_style.Private.view style
         ; text_align
         ; max_lines
         ; overflow
         })
    ~event_bindings:[||]
    ~children:[||]
;;

let rich_text ?key spans =
  create_typed ~key ~node:(Rich_text { spans }) ~event_bindings:[||] ~children:[||]
;;

let optional_dimension label = function
  | None -> None
  | Some value ->
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then invalid_arg (Printf.sprintf "Widget.%s must be finite and non-negative" label);
    Some value
;;

let icon ?key ?font_family ?size ?color ~code_point () =
  if
    code_point < 0
    || code_point > 0x10ffff
    || (code_point >= 0xd800 && code_point <= 0xdfff)
  then invalid_arg "Widget.icon: code_point must be a Unicode scalar value";
  create_typed
    ~key
    ~node:
      (Icon
         { code_point
         ; font_family
         ; size = optional_dimension "icon.size" size
         ; color = Option.map Style.Color.Private.to_argb32 color
         })
    ~event_bindings:[||]
    ~children:[||]
;;

let image ?key ?(fit = Style.Image_fit.Contain) ?width ?height ~uri () =
  if String.length uri = 0 then invalid_arg "Widget.image: uri must not be empty";
  create_typed
    ~key
    ~node:
      (Image
         { uri
         ; fit
         ; width = optional_dimension "image.width" width
         ; height = optional_dimension "image.height" height
         })
    ~event_bindings:[||]
    ~children:[||]
;;

let row ?key children =
  create_typed ~key ~node:Row ~event_bindings:[||] ~children:(plain_children children)
;;

let column ?key children =
  create_typed ~key ~node:Column ~event_bindings:[||] ~children:(plain_children children)
;;

let button ?key ?(enabled = true) ~on_press ~child () =
  create_typed
    ~key
    ~node:(Button { enabled })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let default_pressable_overlay_color =
  Style.Color.argb ~alpha:24 ~red:28 ~green:32 ~blue:38
;;

let pressable
      ?key
      ?(overlay_color = default_pressable_overlay_color)
      ?(release_delay_ms = 80)
      ~on_press
      ~child
      ()
  =
  if release_delay_ms < 0 || release_delay_ms > 100
  then invalid_arg "Widget.pressable: release delay must be in 0..100ms";
  create_typed
    ~key
    ~node:(Pressable { overlay_color; release_delay_ms })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let padding ?key ~insets child =
  let left, top, right, bottom = Layout.Edge_insets.Private.to_sides insets in
  create_typed
    ~key
    ~node:(Padding { left; top; right; bottom })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let align ?key ~alignment child =
  create_typed
    ~key
    ~node:(Align { alignment })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let finite_factor label = function
  | None -> None
  | Some value ->
    (match Float.classify_float value with
     | (FP_normal | FP_subnormal) when Float.compare value 0. > 0 -> Some value
     | FP_zero | FP_normal | FP_subnormal | FP_infinite | FP_nan ->
       invalid_arg (Printf.sprintf "Widget.center: %s must be finite and positive" label))
;;

let center ?key ?width_factor ?height_factor child =
  create_typed
    ~key
    ~node:
      (Center
         { width_factor = finite_factor "width_factor" width_factor
         ; height_factor = finite_factor "height_factor" height_factor
         })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let sized_box ?key ?width ?height child =
  create_typed
    ~key
    ~node:
      (Sized_box
         { width = optional_dimension "sized_box.width" width
         ; height = optional_dimension "sized_box.height" height
         })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let constrained_box ?key ~constraints child =
  let min_width, max_width, min_height, max_height =
    Layout.Box_constraints.Private.to_values constraints
  in
  create_typed
    ~key
    ~node:(Constrained_box { min_width; max_width; min_height; max_height })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let decorated_box ?key ~decoration child =
  let background, border_radius = Style.Decoration.Private.to_values decoration in
  create_typed
    ~key
    ~node:(Decorated_box { background; border_radius })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let clip ?key ?(behavior = Style.Clip.Anti_alias) child =
  create_typed
    ~key
    ~node:(Clip { behavior })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let opacity ?key opacity child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "Widget.opacity: opacity must be finite and in 0..1";
  create_typed
    ~key
    ~node:(Opacity { opacity })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let animated_opacity ?key ~animation ~opacity ~on_completed child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "Widget.animated_opacity: opacity must be finite and in 0..1";
  create_typed
    ~key
    ~node:(Animated_opacity { opacity; animation })
    ~event_bindings:[| { tag = Event.Tag.Animation_completed; handler = on_completed } |]
    ~children:(plain_children [ child ])
;;

let transform ?key ~transform child =
  create_typed
    ~key
    ~node:(Transform { matrix4 = Style.Transform.Private.to_array transform })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

(* Plan B (docs/sliver-fix-plan.md D1): the viewport-level [cache_extent] is
   derived from the virtualized child slivers so Flutter pre-renders the
   [overscan] window instead of falling back to its ~250px default. Each
   [Sliver_fixed_extent] / [Sliver_varied_extent] contributes
   [overscan * extent]; [Sliver_padding] transparently wraps a single inner
   sliver, so we recurse to find the virtualized descendant. *)
let rec sliver_cache_extent_candidate (widget : t) : float option =
  let (T view) = widget in
  match view.node with
  | Sliver_fixed_extent { overscan; item_extent; _ } ->
    Some (float_of_int overscan *. item_extent)
  | Sliver_varied_extent { overscan; default_item_extent; _ } ->
    Some (float_of_int overscan *. default_item_extent)
  | Sliver_padding _ ->
    if Array.length view.children > 0
    then sliver_cache_extent_candidate view.children.(0).widget
    else None
  | _ -> None
;;

let scroll_view_widget
      ?key
      ~axis
      ?(reverse = false)
      ?(primary = false)
      ?cache_extent
      ~on_scroll
      children
      ()
  =
  let cache_extent =
    match cache_extent with
    | Some _ as explicit -> explicit
    | None ->
      let candidates = List.filter_map sliver_cache_extent_candidate children in
      (match candidates with
       | [] -> None
       | _ -> Some (List.fold_left max 0. candidates))
  in
  create_typed
    ~key
    ~node:(Scroll_view { axis; reverse; primary; cache_extent })
    ~event_bindings:[| { tag = Event.Tag.Scroll_notification; handler = on_scroll } |]
    ~children:(plain_children children)
;;

let sliver_box_widget ?key child () =
  create_typed
    ~key
    ~node:Sliver_box
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let sliver_list_widget ?key children () =
  create_typed
    ~key
    ~node:Sliver_list
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let sliver_fill_widget ?key child () =
  create_typed
    ~key
    ~node:Sliver_fill
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let sliver_padding_widget ?key ~insets child () =
  let left, top, right, bottom = Layout.Edge_insets.Private.to_sides insets in
  create_typed
    ~key
    ~node:(Sliver_padding { left; top; right; bottom })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let sliver_app_bar_widget
      ?key
      ?(pinned = false)
      ?expanded_height
      ?collapsed_height
      ?(floating = false)
      ?(snap = false)
      ?(stretch = false)
      ?(toolbar_height = 56.)
      ?(force_elevated = false)
      ?(automatically_imply_leading = true)
      ?center_title
      ?background_color
      ?foreground_color
      ?elevation
      ?leading
      ?flexible_space
      ?bottom
      ?actions
      ~title
      ()
  =
  let optional value = Option.to_list value in
  let finite_nonnegative label value =
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then
      invalid_arg
        (Printf.sprintf "Widget.Sliver.app_bar: %s must be finite and non-negative" label)
  in
  finite_nonnegative "toolbar_height" toolbar_height;
  Option.iter (finite_nonnegative "expanded_height") expanded_height;
  Option.iter (finite_nonnegative "collapsed_height") collapsed_height;
  Option.iter (finite_nonnegative "elevation") elevation;
  if snap && not floating then invalid_arg "Widget.Sliver.app_bar: snap requires floating";
  Option.iter
    (fun height ->
       if Float.compare height toolbar_height < 0
       then
         invalid_arg
           "Widget.Sliver.app_bar: collapsed_height must be at least toolbar_height")
    collapsed_height;
  Option.iter
    (fun (T view) ->
       match view.node with
       | Preferred_size _ -> ()
       | _ -> invalid_arg "Widget.Sliver.app_bar: bottom must use Widget.preferred_size")
    bottom;
  let actions = Option.value actions ~default:[] in
  create_typed
    ~key
    ~node:
      (Sliver_app_bar
         { pinned
         ; expanded_height
         ; collapsed_height
         ; floating
         ; snap
         ; stretch
         ; toolbar_height
         ; has_leading = Option.is_some leading
         ; has_flexible_space = Option.is_some flexible_space
         ; has_bottom = Option.is_some bottom
         ; has_actions = not (List.is_empty actions)
         ; force_elevated
         ; automatically_imply_leading
         ; center_title
         ; background_color
         ; foreground_color
         ; elevation
         })
    ~event_bindings:[||]
    ~children:
      (plain_children
         (optional leading
          @ [ title ]
          @ optional flexible_space
          @ optional bottom
          @ actions))
;;

let validate_sliver_extent label extent =
  if (not (Float.is_finite extent)) || Float.compare extent 0. <= 0
  then
    invalid_arg
      (Printf.sprintf "Widget.Sliver.%s: extent must be finite and positive" label)
;;

let validate_sliver_window label ~total_count ~first_index child_count =
  if total_count < 0
  then
    invalid_arg
      (Printf.sprintf "Widget.Sliver.%s: total_count must be non-negative" label);
  if first_index < 0 || first_index > total_count
  then
    invalid_arg
      (Printf.sprintf "Widget.Sliver.%s: first_index is outside the logical list" label);
  if child_count > total_count - first_index
  then
    invalid_arg (Printf.sprintf "Widget.Sliver.%s: item window exceeds total_count" label)
;;

let sliver_fixed_extent_widget
      ?key
      ~total_count
      ~first_index
      ~item_extent
      ?(overscan = 2)
      ~items
      ~on_visible_range
      ()
  =
  validate_sliver_window "fixed_extent" ~total_count ~first_index (List.length items);
  validate_sliver_extent "fixed_extent" item_extent;
  if overscan < 0
  then invalid_arg "Widget.Sliver.fixed_extent: overscan must be non-negative";
  create_typed
    ~key
    ~node:(Sliver_fixed_extent { total_count; first_index; item_extent; overscan })
    ~event_bindings:
      [| { tag = Event.Tag.Visible_range_changed; handler = on_visible_range } |]
    ~children:(plain_children items)
;;

let validate_extent_overrides label ~total_count overrides =
  let rec check previous = function
    | [] -> ()
    | { Sparse_extent_override.index; extent } :: tail ->
      if index < 0 || index >= total_count
      then
        invalid_arg
          (Printf.sprintf
             "Widget.Sliver.%s: override index is outside the logical list"
             label);
      (match previous with
       | Some previous when index <= previous ->
         invalid_arg
           (Printf.sprintf
              "Widget.Sliver.%s: override indexes must be sorted and unique"
              label)
       | None | Some _ -> ());
      validate_sliver_extent label extent;
      check (Some index) tail
  in
  check None overrides
;;

let sliver_varied_extent_widget
      ?key
      ~total_count
      ~first_index
      ~default_item_extent
      ~extent_overrides
      ?(overscan = 2)
      ?transition
      ~items
      ~on_visible_range
      ()
  =
  validate_sliver_window "varied_extent" ~total_count ~first_index (List.length items);
  validate_sliver_extent "varied_extent" default_item_extent;
  if overscan < 0
  then invalid_arg "Widget.Sliver.varied_extent: overscan must be non-negative";
  validate_extent_overrides "varied_extent" ~total_count extent_overrides;
  create_typed
    ~key
    ~node:
      (Sliver_varied_extent
         { total_count
         ; first_index
         ; default_item_extent
         ; extent_overrides
         ; overscan
         ; transition
         })
    ~event_bindings:
      [| { tag = Event.Tag.Visible_range_changed; handler = on_visible_range } |]
    ~children:(plain_children items)
;;

let preferred_size ?key ~height child =
  validate_sliver_extent "preferred_size" height;
  create_typed
    ~key
    ~node:(Preferred_size { height })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let safe_area
      ?key
      ?(left = true)
      ?(top = true)
      ?(right = true)
      ?(bottom = true)
      ?(minimum = Layout.Edge_insets.all 0.)
      child
  =
  let minimum_left, minimum_top, minimum_right, minimum_bottom =
    Layout.Edge_insets.Private.to_sides minimum
  in
  create_typed
    ~key
    ~node:
      (Safe_area
         { left
         ; top
         ; right
         ; bottom
         ; minimum_left
         ; minimum_top
         ; minimum_right
         ; minimum_bottom
         })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let environment_boundary ?key child =
  create_typed
    ~key
    ~node:Environment_boundary
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let optional_binding tag = function
  | None -> []
  | Some handler -> [ { tag; handler } ]
;;

let gesture
      ?key
      ?on_tap
      ?on_double_tap
      ?on_long_press
      ?on_pointer_down
      ?on_pointer_up
      child
  =
  let event_bindings =
    optional_binding Event.Tag.Tap on_tap
    @ optional_binding Double_tap on_double_tap
    @ optional_binding Long_press on_long_press
    @ optional_binding Pointer_down on_pointer_down
    @ optional_binding Pointer_up on_pointer_up
  in
  if event_bindings = []
  then invalid_arg "Widget.gesture: at least one event handler is required";
  create_typed
    ~key
    ~node:Gesture
    ~event_bindings:(Array.of_list event_bindings)
    ~children:(plain_children [ child ])
;;

let focus_scope ?key ?(autofocus = false) ~on_focus_changed child =
  create_typed
    ~key
    ~node:(Focus_scope { autofocus })
    ~event_bindings:[| { tag = Event.Tag.Focus_changed; handler = on_focus_changed } |]
    ~children:(plain_children [ child ])
;;

let mouse_region ?key ?(opaque = true) ~on_enter ~on_leave child =
  create_typed
    ~key
    ~node:(Mouse_region { opaque })
    ~event_bindings:
      [| { tag = Event.Tag.Pointer_enter; handler = on_enter }
       ; { tag = Event.Tag.Pointer_leave; handler = on_leave }
      |]
    ~children:(plain_children [ child ])
;;

let keyboard_listener
      ?key
      ?(autofocus = false)
      ?(key_policy = Event.Key_policy.Ignored)
      ~on_key
      child
  =
  create_typed
    ~key
    ~node:(Keyboard_listener { autofocus; key_policy })
    ~event_bindings:[| { tag = Event.Tag.Key; handler = on_key } |]
    ~children:(plain_children [ child ])
;;

let semantics ?key ?on_action ~properties child =
  let properties = Semantics.Private.view properties in
  let event_bindings =
    match properties.actions, on_action with
    | [], None -> [||]
    | [], Some _ ->
      invalid_arg "Widget.semantics: on_action requires at least one declared action"
    | _ :: _, None -> invalid_arg "Widget.semantics: declared actions require on_action"
    | _ :: _, Some handler -> [| { tag = Event.Tag.Semantics_action; handler } |]
  in
  create_typed
    ~key
    ~node:
      (Semantics
         { label = properties.label
         ; hint = properties.hint
         ; value = properties.value
         ; role = properties.role
         ; enabled = properties.enabled
         ; selected = properties.selected
         ; checked = properties.checked
         ; focusable = properties.focusable
         ; obscured = properties.obscured
         ; live_region = properties.live_region
         ; heading_level = properties.heading_level
         ; sort_key = properties.sort_key
         ; actions = properties.actions
         })
    ~event_bindings
    ~children:(plain_children [ child ])
;;

let theme ?key ~data child =
  let data = Theme.Private.view data in
  create_typed
    ~key
    ~node:(Theme { brightness = data.brightness; color_seed = data.color_seed })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let navigator ?key ?restoration_scope_id ~on_pop pages =
  create_typed
    ~key
    ~node:(Navigator { restoration_scope_id })
    ~event_bindings:[| { tag = Event.Tag.Route_pop; handler = on_pop } |]
    ~children:(plain_children pages)
;;

let page
      ?key
      ~page_key
      ?(presentation = Navigation.Standard Navigation.None)
      ?(can_pop = true)
      ?restoration_id
      child
  =
  if String.length (ID.Navigation.Page_key.to_string page_key) = 0
  then invalid_arg "Widget.page: page_key must not be empty";
  create_typed
    ~key
    ~node:(Page { page_key; presentation; can_pop; restoration_id })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let overlay ?key ?(alignment = Navigation.Center) ?(dismissible = false) children =
  create_typed
    ~key
    ~node:(Overlay { alignment; dismissible })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let material_dialog ?key ?(barrier_dismissible = true) child =
  create_typed
    ~key
    ~node:(Material_dialog { barrier_dismissible })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let native_widget ?key ~kind_id ~version ~capabilities ~payload ~on_event ~children () =
  create_typed
    ~key
    ~node:(Native_widget { kind_id; version; capabilities; payload })
    ~event_bindings:[| { tag = Event.Tag.Native_event; handler = on_event } |]
    ~children:(plain_children children)
;;

let material_checkbox ?key ?(enabled = true) ~value ~on_changed () =
  create_typed
    ~key
    ~node:(Material_checkbox { value; enabled })
    ~event_bindings:[| { tag = Event.Tag.Value_changed; handler = on_changed } |]
    ~children:[||]
;;

let material_scaffold_widget ?key ?app_bar ~body () =
  create_typed
    ~key
    ~node:(Material_scaffold { has_app_bar = Option.is_some app_bar })
    ~event_bindings:[||]
    ~children:(plain_children (Option.to_list app_bar @ [ body ]))
;;

let material_app_bar ?key ?(center_title = false) ~title () =
  create_typed
    ~key
    ~node:(Material_app_bar { center_title })
    ~event_bindings:[||]
    ~children:(plain_children [ title ])
;;

let material_button
      ?key
      ?(enabled = true)
      ?(autofocus = false)
      ~variant
      ~on_press
      ~child
      ()
  =
  let event_bindings = [| { tag = Event.Tag.Press; handler = on_press } |] in
  let children = plain_children [ child ] in
  match variant with
  | Elevated ->
    create_typed
      ~key
      ~node:(Material_elevated_button { variant; enabled; autofocus })
      ~event_bindings
      ~children
  | Text_button ->
    create_typed
      ~key
      ~node:(Material_text_button { variant; enabled; autofocus })
      ~event_bindings
      ~children
  | Icon_button ->
    create_typed
      ~key
      ~node:(Material_icon_button { variant; enabled; autofocus })
      ~event_bindings
      ~children
;;

let material_switch ?key ?(enabled = true) ~value ~on_changed () =
  create_typed
    ~key
    ~node:(Material_switch { value; enabled })
    ~event_bindings:[| { tag = Event.Tag.Value_changed; handler = on_changed } |]
    ~children:[||]
;;

let material_list_tile
      ?key
      ?(enabled = true)
      ?(selected = false)
      ?subtitle
      ?leading
      ?trailing
      ~on_press
      ~title
      ()
  =
  let optional value = Option.to_list value in
  create_typed
    ~key
    ~node:
      (Material_list_tile
         { enabled
         ; selected
         ; has_subtitle = Option.is_some subtitle
         ; has_leading = Option.is_some leading
         ; has_trailing = Option.is_some trailing
         })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:
      (plain_children
         (optional leading @ [ title ] @ optional subtitle @ optional trailing))
;;

let finite_nonnegative label value =
  match Float.classify_float value with
  | (FP_normal | FP_subnormal | FP_zero) when Float.compare value 0. >= 0 -> value
  | FP_normal | FP_subnormal | FP_zero | FP_infinite | FP_nan ->
    invalid_arg (Printf.sprintf "%s must be finite and non-negative" label)
;;

let material_divider ?key ?(thickness = 1.) () =
  create_typed
    ~key
    ~node:(Material_divider { thickness = finite_nonnegative "thickness" thickness })
    ~event_bindings:[||]
    ~children:[||]
;;

let material_card ?key ?(elevation = 1.) child =
  create_typed
    ~key
    ~node:(Material_card { elevation = finite_nonnegative "elevation" elevation })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let material_progress ?key ?value () =
  let value =
    Option.map
      (fun value ->
         if
           Float.classify_float value = FP_nan
           || Float.compare value 0. < 0
           || Float.compare value 1. > 0
         then
           invalid_arg
             "Material.circular_progress_indicator: value must be finite and in 0..1";
         value)
      value
  in
  create_typed
    ~key
    ~node:(Material_circular_progress_indicator { value })
    ~event_bindings:[||]
    ~children:[||]
;;

let cupertino_button ?key ?(enabled = true) ~on_press ~child () =
  create_typed
    ~key
    ~node:(Cupertino_button { enabled })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let cupertino_switch ?key ?(enabled = true) ~value ~on_changed () =
  create_typed
    ~key
    ~node:(Cupertino_switch { value; enabled })
    ~event_bindings:[| { tag = Event.Tag.Value_changed; handler = on_changed } |]
    ~children:[||]
;;

let text_input
      ?key
      ?(enabled = true)
      ?(read_only = false)
      ?(obscure_text = false)
      ?(keyboard_type = Text_editing.Text)
      ?(input_action = Text_editing.Done)
      ?(autofocus = false)
      ?max_utf8_bytes
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ?on_limit_reached
      ()
  =
  if ID.Text_input.Session_id.compare session_id ID.Text_input.Session_id.zero < 0
  then invalid_arg "Widget.text_input: session_id must be non-negative";
  if
    ID.Text_input.Document_revision.compare
      document_revision
      ID.Text_input.Document_revision.zero
    < 0
  then invalid_arg "Widget.text_input: document_revision must be non-negative";
  if
    ID.Text_input.Local_revision.compare
      accepted_local_revision
      ID.Text_input.Local_revision.zero
    < 0
  then invalid_arg "Widget.text_input: accepted_local_revision must be non-negative";
  (match max_utf8_bytes with
   | Some value when value <= 0 || value > 0xffff_ffff ->
     invalid_arg "Widget.text_input: max_utf8_bytes must fit positive uint32"
   | None | Some _ -> ());
  create_typed
    ~key
    ~node:
      (Text_input
         { session_id
         ; document_revision
         ; value
         ; enabled
         ; read_only
         ; obscure_text
         ; keyboard_type
         ; input_action
         ; accepted_local_revision
         ; update_mode
         ; autofocus
         ; max_utf8_bytes
         })
    ~event_bindings:
      (Array.of_list
         ([ { tag = Event.Tag.Text_edit; handler = on_edit }
          ; { tag = Event.Tag.Text_submit; handler = on_submit }
          ; { tag = Event.Tag.Focus_changed; handler = on_focus_changed }
          ]
          @
          match on_limit_reached with
          | None -> []
          | Some handler -> [ { tag = Event.Tag.Text_limit_reached; handler } ]))
    ~children:[||]
;;

module Flex = struct
  type nonrec child = child

  let positive_flex flex =
    if flex <= 0 then invalid_arg "Widget.Flex: flex must be positive";
    flex
  ;;

  let fixed widget = { widget; parent_data = No_parent_data }

  let flexible ?(flex = 1) widget =
    { widget; parent_data = Flex_parent_data { flex = positive_flex flex; fit = Loose } }
  ;;

  let expanded ?(flex = 1) widget =
    { widget; parent_data = Flex_parent_data { flex = positive_flex flex; fit = Tight } }
  ;;

  let create_linear ?key node children =
    create_typed ~key ~node ~event_bindings:[||] ~children:(Array.of_list children)
  ;;

  let row ?key children = create_linear ?key Flex_row children
  let column ?key children = create_linear ?key Flex_column children
end

module Stack = struct
  type nonrec child = child

  let child widget = { widget; parent_data = No_parent_data }

  let positioned ?left ?top ?right ?bottom widget =
    { widget; parent_data = Stack_position { left; top; right; bottom } }
  ;;

  let create ?key children =
    create_typed ~key ~node:Stack ~event_bindings:[||] ~children:(Array.of_list children)
  ;;
end

type vertical_viewport = Vertical_viewport of t
type horizontal_viewport = Horizontal_viewport of t

let vertical_viewport widget = Vertical_viewport widget
let horizontal_viewport widget = Horizontal_viewport widget

module Viewport = struct
  type nonrec widget = t

  let positive_extent label value =
    if (not (Float.is_finite value)) || Float.compare value 0. <= 0
    then
      invalid_arg (Printf.sprintf "Widget.Viewport.%s must be finite and positive" label)
  ;;

  module Vertical = struct
    type t = vertical_viewport

    let map f (Vertical_viewport widget) = Vertical_viewport (f widget)
    let widget (Vertical_viewport widget) = widget
    let with_test_id test_id = map (with_test_id test_id)
    let padding ~insets = map (padding ~insets)
    let decorated_box ~decoration = map (decorated_box ~decoration)
    let semantics ~properties = map (semantics ~properties)
    let safe_area ?minimum = map (safe_area ?minimum)
    let theme ~data = map (theme ~data)

    let with_height ~height viewport =
      positive_extent "Vertical.with_height" height;
      sized_box ~height (widget viewport)
    ;;
  end

  module Horizontal = struct
    type t = horizontal_viewport

    let map f (Horizontal_viewport widget) = Horizontal_viewport (f widget)
    let widget (Horizontal_viewport widget) = widget
    let with_test_id test_id = map (with_test_id test_id)
    let padding ~insets = map (padding ~insets)
    let decorated_box ~decoration = map (decorated_box ~decoration)
    let semantics ~properties = map (semantics ~properties)
    let safe_area ?minimum = map (safe_area ?minimum)
    let theme ~data = map (theme ~data)

    let with_width ~width viewport =
      positive_extent "Horizontal.with_width" width;
      sized_box ~width (widget viewport)
    ;;
  end
end

module Sliver = struct
  type widget = t
  type sliver = Sliver of t
  type t = sliver

  let with_test_id test_id (Sliver widget) = Sliver (with_test_id test_id widget)
  let box ?key child = Sliver (sliver_box_widget ?key child ())
  let list ?key children = Sliver (sliver_list_widget ?key children ())
  let fill ?key child = Sliver (sliver_fill_widget ?key child ())

  let fixed_extent
        ?key
        ~total_count
        ~first_index
        ~item_extent
        ?overscan
        ~items
        ~on_visible_range
        ()
    =
    Sliver
      (sliver_fixed_extent_widget
         ?key
         ~total_count
         ~first_index
         ~item_extent
         ?overscan
         ~items
         ~on_visible_range
         ())
  ;;

  let varied_extent
        ?key
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ?overscan
        ?transition
        ~items
        ~on_visible_range
        ()
    =
    Sliver
      (sliver_varied_extent_widget
         ?key
         ~total_count
         ~first_index
         ~default_item_extent
         ~extent_overrides
         ?overscan
         ?transition
         ~items
         ~on_visible_range
         ())
  ;;

  let padding ?key ~insets (Sliver inner) =
    Sliver (sliver_padding_widget ?key ~insets inner ())
  ;;

  let app_bar
        ?key
        ?pinned
        ?expanded_height
        ?collapsed_height
        ?floating
        ?snap
        ?stretch
        ?toolbar_height
        ?force_elevated
        ?automatically_imply_leading
        ?center_title
        ?background_color
        ?foreground_color
        ?elevation
        ?leading
        ?flexible_space
        ?bottom
        ?actions
        ~title
        ()
    =
    Sliver
      (sliver_app_bar_widget
         ?key
         ?pinned
         ?expanded_height
         ?collapsed_height
         ?floating
         ?snap
         ?stretch
         ?toolbar_height
         ?force_elevated
         ?automatically_imply_leading
         ?center_title
         ?background_color
         ?foreground_color
         ?elevation
         ?leading
         ?flexible_space
         ?bottom
         ?actions
         ~title
         ())
  ;;

  let visible_range_of_payload = function
    | Event.Payload.Visible_range range -> Some range
    | _ -> None
  ;;
end

module Scroll_view = struct
  let vertical ?key ?reverse ?primary ?cache_extent ~on_scroll slivers () =
    scroll_view_widget
      ?key
      ~axis:Layout.Axis.Vertical
      ?reverse
      ?primary
      ?cache_extent
      ~on_scroll
      (List.map (fun (Sliver.Sliver widget) -> widget) slivers)
      ()
    |> vertical_viewport
  ;;

  let horizontal ?key ?reverse ?cache_extent ~on_scroll slivers () =
    scroll_view_widget
      ?key
      ~axis:Layout.Axis.Horizontal
      ?reverse
      ?cache_extent
      ~on_scroll
      (List.map (fun (Sliver.Sliver widget) -> widget) slivers)
      ()
    |> horizontal_viewport
  ;;
end

type body = Body of t

type vertical_body_child =
  | Vertical_fixed of t
  | Vertical_fill of int * vertical_viewport

type horizontal_body_child =
  | Horizontal_fixed of t
  | Horizontal_fill of int * horizontal_viewport

module Body = struct
  type nonrec widget = t
  type t = body

  let static widget = Body widget
  let map f (Body widget) = Body (f widget)
  let with_test_id test_id = map (with_test_id test_id)
  let padding ~insets = map (padding ~insets)
  let decorated_box ~decoration = map (decorated_box ~decoration)
  let semantics ~properties = map (semantics ~properties)

  let safe_area ?left ?top ?right ?bottom ?minimum =
    map (safe_area ?left ?top ?right ?bottom ?minimum)
  ;;

  let theme ~data = map (theme ~data)

  let positive_flex axis flex =
    if flex <= 0
    then invalid_arg (Printf.sprintf "Widget.Body.%s.fill: flex must be positive" axis);
    flex
  ;;

  let nonempty axis children =
    if children = []
    then
      invalid_arg
        (Printf.sprintf "Widget.Body.%s.create: at least one child is required" axis)
  ;;

  module Vertical = struct
    type child = vertical_body_child

    let fixed widget = Vertical_fixed widget
    let fill ?(flex = 1) viewport = Vertical_fill (positive_flex "Vertical" flex, viewport)

    let create ?key children =
      nonempty "Vertical" children;
      children
      |> List.map (function
        | Vertical_fixed widget -> Flex.fixed widget
        | Vertical_fill (flex, viewport) ->
          Flex.expanded ~flex (Viewport.Vertical.widget viewport))
      |> Flex.column ?key
      |> fun widget -> Body widget
    ;;
  end

  module Horizontal = struct
    type child = horizontal_body_child

    let fixed widget = Horizontal_fixed widget

    let fill ?(flex = 1) viewport =
      Horizontal_fill (positive_flex "Horizontal" flex, viewport)
    ;;

    let create ?key children =
      nonempty "Horizontal" children;
      children
      |> List.map (function
        | Horizontal_fixed widget -> Flex.fixed widget
        | Horizontal_fill (flex, viewport) ->
          Flex.expanded ~flex (Viewport.Horizontal.widget viewport))
      |> Flex.row ?key
      |> fun widget -> Body widget
    ;;
  end

  let overlay ?key ~base:(Body base) ~overlays () =
    Stack.create
      ?key
      (Stack.positioned ~left:0. ~top:0. ~right:0. ~bottom:0. base :: overlays)
    |> fun widget -> Body widget
  ;;

  module Private = struct
    let to_widget (Body widget) = widget
  end
end

let material_scaffold ?key ?app_bar ~body () =
  material_scaffold_widget ?key ?app_bar ~body:(Body.Private.to_widget body) ()
;;

module For_testing = struct
  let kind_name widget =
    let (T view) = widget in
    kind_tag_to_string (node_kind_tag view.node)
  ;;

  let key widget =
    let (T view) = widget in
    view.key
  ;;

  let test_id widget =
    let (T view) = widget in
    view.test_id
  ;;

  let children widget =
    let (T view) = widget in
    Array.map (fun child -> child.widget) view.children
  ;;

  let text_content widget =
    let (T view) = widget in
    match view.node with
    | Text { value; _ } -> Some value
    | _ -> None
  ;;
end

module Private = struct
  type nonrec kind_tag = kind_tag =
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
    | K_preferred_size
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

  let kind_tag_compare = kind_tag_compare
  let kind_tag_equal = kind_tag_equal
  let kind_tag_to_string = kind_tag_to_string

  type nonrec flex_fit = flex_fit =
    | Loose
    | Tight

  type nonrec flex_parent_data = flex_parent_data =
    { flex : int
    ; fit : flex_fit
    }

  type nonrec position = position =
    { left : float option
    ; top : float option
    ; right : float option
    ; bottom : float option
    }

  type nonrec child_parent_data = child_parent_data =
    | No_parent_data
    | Flex_parent_data of flex_parent_data
    | Stack_position of position

  type nonrec material_button_variant = material_button_variant =
    | Elevated
    | Text_button
    | Icon_button

  include Private_types

  type any_view = Av : 'k view -> any_view

  let view widget =
    let (T v) = widget in
    Av v
  ;;

  let node_equal_widgets left right =
    let (Av left_view) = view left in
    let (Av right_view) = view right in
    node_equal left_view.node right_view.node
  ;;

  let kind_tag_of_widget widget =
    let (Av view) = view widget in
    node_kind_tag view.node
  ;;

  let node_kind_tag = node_kind_tag
  let node_equal = node_equal
  let parent_data_equal = parent_data_equal
  let material_checkbox = material_checkbox
  let material_scaffold = material_scaffold
  let material_app_bar = material_app_bar
  let material_button = material_button
  let material_switch = material_switch
  let material_list_tile = material_list_tile
  let material_divider = material_divider
  let material_card = material_card
  let material_progress = material_progress
  let cupertino_button = cupertino_button
  let cupertino_switch = cupertino_switch
  let native_widget = native_widget
  let vertical_viewport = vertical_viewport
  let horizontal_viewport = horizontal_viewport

  let native_widget_with_body_children
        ?key
        ~kind_id
        ~version
        ~capabilities
        ~payload
        ~on_event
        ~bodies
        ~trailing_children
        ()
    =
    native_widget
      ?key
      ~kind_id
      ~version
      ~capabilities
      ~payload
      ~on_event
      ~children:(List.map Body.Private.to_widget bodies @ trailing_children)
      ()
  ;;
end
