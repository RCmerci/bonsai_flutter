module ID = Bonsai_flutter_spec.Id

module Kind = struct
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

  let compare left right = Stdlib.compare left right
  let equal left right = compare left right = 0

  let to_string = function
    | Empty -> "Empty"
    | Text -> "Text"
    | Rich_text -> "Rich_text"
    | Icon -> "Icon"
    | Image -> "Image"
    | Row -> "Row"
    | Column -> "Column"
    | Flex_row -> "Flex_row"
    | Flex_column -> "Flex_column"
    | Stack -> "Stack"
    | Button -> "Button"
    | Padding -> "Padding"
    | Align -> "Align"
    | Center -> "Center"
    | Sized_box -> "Sized_box"
    | Constrained_box -> "Constrained_box"
    | Decorated_box -> "Decorated_box"
    | Clip -> "Clip"
    | Opacity -> "Opacity"
    | Animated_opacity -> "Animated_opacity"
    | Transform -> "Transform"
    | Scroll_view -> "Scroll_view"
    | List_view -> "List_view"
    | Gesture -> "Gesture"
    | Focus_scope -> "Focus_scope"
    | Mouse_region -> "Mouse_region"
    | Keyboard_listener -> "Keyboard_listener"
    | Pressable -> "Pressable"
    | Semantics -> "Semantics"
    | Theme -> "Theme"
    | Material_scaffold -> "Material_scaffold"
    | Material_app_bar -> "Material_app_bar"
    | Material_elevated_button -> "Material_elevated_button"
    | Material_text_button -> "Material_text_button"
    | Material_icon_button -> "Material_icon_button"
    | Material_checkbox -> "Material_checkbox"
    | Material_switch -> "Material_switch"
    | Material_list_tile -> "Material_list_tile"
    | Material_divider -> "Material_divider"
    | Material_card -> "Material_card"
    | Material_circular_progress_indicator -> "Material_circular_progress_indicator"
    | Cupertino_button -> "Cupertino_button"
    | Cupertino_switch -> "Cupertino_switch"
    | Text_input -> "Text_input"
    | Overlay -> "Overlay"
    | Navigator -> "Navigator"
    | Page -> "Page"
    | Safe_area -> "Safe_area"
    | Environment_boundary -> "Environment_boundary"
    | Material_dialog -> "Material_dialog"
    | Native_widget -> "Native_widget"
  ;;
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
  | Overlay_props of
      { alignment : Navigation.overlay_alignment
      ; dismissible : bool
      }
  | Navigator_props of
      { restoration_scope_id : ID.Navigation.restoration_scope_id option }
  | Page_props of
      { page_key : ID.Navigation.page_key
      ; transition : Navigation.page_transition
      ; can_pop : bool
      ; restoration_id : ID.Navigation.restoration_id option
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
      { kind_id : ID.Native_widget.kind_id
      ; version : int
      ; capabilities : int64
      ; payload : bytes
      }

type event_binding =
  { tag : Event.Tag.t
  ; handler : Event.Handler.t
  }

type t = { view : view }

and child =
  { widget : t
  ; parent_data : child_parent_data
  }

and view =
  { key : Key.t option
  ; test_id : Test_id.t option
  ; kind : Kind.t
  ; props : props
  ; event_bindings : event_binding array
  ; children : child array
  ; fingerprint : int64
  }

let props_equal left right =
  match left, right with
  | Empty_props, Empty_props
  | Linear_props, Linear_props
  | Stack_props, Stack_props
  | Gesture_props, Gesture_props
  | Environment_boundary_props, Environment_boundary_props -> true
  | Text_props left, Text_props right ->
    String.equal left.value right.value
    && Option.equal ( = ) left.style right.style
    && left.text_align = right.text_align
    && Option.equal Int.equal left.max_lines right.max_lines
    && left.overflow = right.overflow
  | Rich_text_props left, Rich_text_props right ->
    List.equal String.equal left.spans right.spans
  | Icon_props left, Icon_props right ->
    left.code_point = right.code_point
    && Option.equal String.equal left.font_family right.font_family
    && Option.equal Float.equal left.size right.size
    && Option.equal Int32.equal left.color right.color
  | Image_props left, Image_props right ->
    String.equal left.uri right.uri
    && left.fit = right.fit
    && Option.equal Float.equal left.width right.width
    && Option.equal Float.equal left.height right.height
  | Button_props left, Button_props right -> Bool.equal left.enabled right.enabled
  | Pressable_props left, Pressable_props right ->
    Int32.equal
      (Style.Color.Private.to_argb32 left.overlay_color)
      (Style.Color.Private.to_argb32 right.overlay_color)
    && left.release_delay_ms = right.release_delay_ms
  | Padding_props left, Padding_props right ->
    Float.equal left.left right.left
    && Float.equal left.top right.top
    && Float.equal left.right right.right
    && Float.equal left.bottom right.bottom
  | Align_props left, Align_props right -> left.alignment = right.alignment
  | Center_props left, Center_props right ->
    Option.equal Float.equal left.width_factor right.width_factor
    && Option.equal Float.equal left.height_factor right.height_factor
  | Sized_box_props left, Sized_box_props right ->
    Option.equal Float.equal left.width right.width
    && Option.equal Float.equal left.height right.height
  | Constrained_box_props left, Constrained_box_props right ->
    Float.equal left.min_width right.min_width
    && Float.equal left.max_width right.max_width
    && Float.equal left.min_height right.min_height
    && Float.equal left.max_height right.max_height
  | Decorated_box_props left, Decorated_box_props right ->
    Option.equal Int32.equal left.background right.background
    && Float.equal left.border_radius right.border_radius
  | Clip_props left, Clip_props right -> left.behavior = right.behavior
  | Opacity_props left, Opacity_props right -> Float.equal left.opacity right.opacity
  | Animated_opacity_props left, Animated_opacity_props right ->
    Float.equal left.opacity right.opacity
    && Animation.Private.equal left.animation right.animation
  | Transform_props left, Transform_props right ->
    Array.length left.matrix4 = Array.length right.matrix4
    && Array.for_all2 Float.equal left.matrix4 right.matrix4
  | Scroll_view_props left, Scroll_view_props right ->
    left.axis = right.axis && Bool.equal left.reverse right.reverse
  | List_view_props left, List_view_props right ->
    left.axis = right.axis && Bool.equal left.reverse right.reverse
  | Focus_scope_props left, Focus_scope_props right ->
    Bool.equal left.autofocus right.autofocus
  | Mouse_region_props left, Mouse_region_props right ->
    Bool.equal left.opaque right.opaque
  | Keyboard_listener_props left, Keyboard_listener_props right ->
    Bool.equal left.autofocus right.autofocus && left.key_policy = right.key_policy
  | Semantics_props left, Semantics_props right ->
    Option.equal String.equal left.label right.label
    && Option.equal String.equal left.hint right.hint
    && Option.equal String.equal left.value right.value
    && Semantics.Role.equal left.role right.role
    && Option.equal Bool.equal left.enabled right.enabled
    && Option.equal Bool.equal left.selected right.selected
    && Option.equal Bool.equal left.checked right.checked
    && Option.equal Bool.equal left.focusable right.focusable
    && Bool.equal left.obscured right.obscured
    && Bool.equal left.live_region right.live_region
    && Option.equal Int.equal left.heading_level right.heading_level
    && Option.equal Float.equal left.sort_key right.sort_key
    && List.equal Semantics.Action.equal left.actions right.actions
  | Theme_props left, Theme_props right ->
    left.brightness = right.brightness && Int32.equal left.color_seed right.color_seed
  | Material_scaffold_props left, Material_scaffold_props right ->
    Bool.equal left.has_app_bar right.has_app_bar
  | Material_app_bar_props left, Material_app_bar_props right ->
    Bool.equal left.center_title right.center_title
  | Material_button_props left, Material_button_props right ->
    left.variant = right.variant
    && Bool.equal left.enabled right.enabled
    && Bool.equal left.autofocus right.autofocus
  | Material_checkbox_props left, Material_checkbox_props right ->
    Bool.equal left.value right.value && Bool.equal left.enabled right.enabled
  | Material_switch_props left, Material_switch_props right ->
    Bool.equal left.value right.value && Bool.equal left.enabled right.enabled
  | Material_list_tile_props left, Material_list_tile_props right ->
    Bool.equal left.enabled right.enabled
    && Bool.equal left.selected right.selected
    && Bool.equal left.has_subtitle right.has_subtitle
    && Bool.equal left.has_leading right.has_leading
    && Bool.equal left.has_trailing right.has_trailing
  | Material_divider_props left, Material_divider_props right ->
    Float.equal left.thickness right.thickness
  | Material_card_props left, Material_card_props right ->
    Float.equal left.elevation right.elevation
  | Material_progress_props left, Material_progress_props right ->
    Option.equal Float.equal left.value right.value
  | Cupertino_button_props left, Cupertino_button_props right ->
    Bool.equal left.enabled right.enabled
  | Cupertino_switch_props left, Cupertino_switch_props right ->
    Bool.equal left.value right.value && Bool.equal left.enabled right.enabled
  | Text_input_props left, Text_input_props right ->
    ID.Text_input.Session_id.equal left.session_id right.session_id
    && ID.Text_input.Document_revision.equal
         left.document_revision
         right.document_revision
    && Text_editing.Value.equal left.value right.value
    && Bool.equal left.enabled right.enabled
    && Bool.equal left.read_only right.read_only
    && Bool.equal left.obscure_text right.obscure_text
    && left.keyboard_type = right.keyboard_type
    && left.input_action = right.input_action
    && ID.Text_input.Local_revision.equal
         left.accepted_local_revision
         right.accepted_local_revision
    && left.update_mode = right.update_mode
    && Bool.equal left.autofocus right.autofocus
    && Option.equal Int.equal left.max_utf8_bytes right.max_utf8_bytes
  | Overlay_props left, Overlay_props right ->
    left.alignment = right.alignment && Bool.equal left.dismissible right.dismissible
  | Navigator_props left, Navigator_props right ->
    Option.equal
      ID.Navigation.Restoration_scope_id.equal
      left.restoration_scope_id
      right.restoration_scope_id
  | Page_props left, Page_props right ->
    ID.Navigation.Page_key.equal left.page_key right.page_key
    && left.transition = right.transition
    && Bool.equal left.can_pop right.can_pop
    && Option.equal
         ID.Navigation.Restoration_id.equal
         left.restoration_id
         right.restoration_id
  | Safe_area_props left, Safe_area_props right ->
    Bool.equal left.left right.left
    && Bool.equal left.top right.top
    && Bool.equal left.right right.right
    && Bool.equal left.bottom right.bottom
    && Float.equal left.minimum_left right.minimum_left
    && Float.equal left.minimum_top right.minimum_top
    && Float.equal left.minimum_right right.minimum_right
    && Float.equal left.minimum_bottom right.minimum_bottom
  | Material_dialog_props left, Material_dialog_props right ->
    Bool.equal left.barrier_dismissible right.barrier_dismissible
  | Native_widget_props left, Native_widget_props right ->
    left.kind_id = right.kind_id
    && left.version = right.version
    && Int64.equal left.capabilities right.capabilities
    && Bytes.equal left.payload right.payload
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

let fingerprint ~key ~test_id ~kind ~props ~event_bindings ~children =
  let state = ref 0xcbf29ce484222325L in
  state := hash_combine !state key;
  state := hash_combine !state test_id;
  state := hash_combine !state kind;
  state := hash_combine !state props;
  Array.iter
    (fun binding ->
       state := hash_combine !state binding.tag;
       state := hash_combine !state (Event.Handler.name binding.handler))
    event_bindings;
  Array.iter
    (fun child ->
       state := hash_combine !state child.parent_data;
       state := hash_combine !state child.widget.view.fingerprint)
    children;
  !state
;;

let create ~key ~kind ~props ~event_bindings ~children =
  let test_id = None in
  let fingerprint = fingerprint ~key ~test_id ~kind ~props ~event_bindings ~children in
  { view = { key; test_id; kind; props; event_bindings; children; fingerprint } }
;;

let with_test_id test_id t =
  let view = t.view in
  let fingerprint =
    fingerprint
      ~key:view.key
      ~test_id:(Some test_id)
      ~kind:view.kind
      ~props:view.props
      ~event_bindings:view.event_bindings
      ~children:view.children
  in
  { view = { view with test_id = Some test_id; fingerprint } }
;;

let plain_children widgets =
  widgets
  |> List.map (fun widget -> { widget; parent_data = No_parent_data })
  |> Array.of_list
;;

let empty ?key () =
  create ~key ~kind:Kind.Empty ~props:Empty_props ~event_bindings:[||] ~children:[||]
;;

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
  create
    ~key
    ~kind:Kind.Text
    ~props:
      (Text_props
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
  create
    ~key
    ~kind:Kind.Rich_text
    ~props:(Rich_text_props { spans })
    ~event_bindings:[||]
    ~children:[||]
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
  create
    ~key
    ~kind:Kind.Icon
    ~props:
      (Icon_props
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
  create
    ~key
    ~kind:Kind.Image
    ~props:
      (Image_props
         { uri
         ; fit
         ; width = optional_dimension "image.width" width
         ; height = optional_dimension "image.height" height
         })
    ~event_bindings:[||]
    ~children:[||]
;;

let row ?key children =
  create
    ~key
    ~kind:Kind.Row
    ~props:Linear_props
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let column ?key children =
  create
    ~key
    ~kind:Kind.Column
    ~props:Linear_props
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let button ?key ?(enabled = true) ~on_press ~child () =
  create
    ~key
    ~kind:Kind.Button
    ~props:(Button_props { enabled })
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
  create
    ~key
    ~kind:Kind.Pressable
    ~props:(Pressable_props { overlay_color; release_delay_ms })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let padding ?key ~insets child =
  let left, top, right, bottom = Layout.Edge_insets.Private.to_sides insets in
  create
    ~key
    ~kind:Kind.Padding
    ~props:(Padding_props { left; top; right; bottom })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let align ?key ~alignment child =
  create
    ~key
    ~kind:Kind.Align
    ~props:(Align_props { alignment })
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
  create
    ~key
    ~kind:Kind.Center
    ~props:
      (Center_props
         { width_factor = finite_factor "width_factor" width_factor
         ; height_factor = finite_factor "height_factor" height_factor
         })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let sized_box ?key ?width ?height child =
  create
    ~key
    ~kind:Kind.Sized_box
    ~props:
      (Sized_box_props
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
  create
    ~key
    ~kind:Kind.Constrained_box
    ~props:(Constrained_box_props { min_width; max_width; min_height; max_height })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let decorated_box ?key ~decoration child =
  let background, border_radius = Style.Decoration.Private.to_values decoration in
  create
    ~key
    ~kind:Kind.Decorated_box
    ~props:(Decorated_box_props { background; border_radius })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let clip ?key ?(behavior = Style.Clip.Anti_alias) child =
  create
    ~key
    ~kind:Kind.Clip
    ~props:(Clip_props { behavior })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let opacity ?key opacity child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "Widget.opacity: opacity must be finite and in 0..1";
  create
    ~key
    ~kind:Kind.Opacity
    ~props:(Opacity_props { opacity })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let animated_opacity ?key ~animation ~opacity ~on_completed child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "Widget.animated_opacity: opacity must be finite and in 0..1";
  create
    ~key
    ~kind:Kind.Animated_opacity
    ~props:(Animated_opacity_props { opacity; animation })
    ~event_bindings:[| { tag = Event.Tag.Animation_completed; handler = on_completed } |]
    ~children:(plain_children [ child ])
;;

let transform ?key ~transform child =
  create
    ~key
    ~kind:Kind.Transform
    ~props:(Transform_props { matrix4 = Style.Transform.Private.to_array transform })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let scroll_view ?key ?(axis = Layout.Axis.Vertical) ?(reverse = false) ~on_scroll child ()
  =
  create
    ~key
    ~kind:Kind.Scroll_view
    ~props:(Scroll_view_props { axis; reverse })
    ~event_bindings:[| { tag = Event.Tag.Scroll_notification; handler = on_scroll } |]
    ~children:(plain_children [ child ])
;;

let list_view
      ?key
      ?(axis = Layout.Axis.Vertical)
      ?(reverse = false)
      ~on_scroll
      children
      ()
  =
  create
    ~key
    ~kind:Kind.List_view
    ~props:(List_view_props { axis; reverse })
    ~event_bindings:[| { tag = Event.Tag.Scroll_notification; handler = on_scroll } |]
    ~children:(plain_children children)
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
  create
    ~key
    ~kind:Kind.Safe_area
    ~props:
      (Safe_area_props
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
  create
    ~key
    ~kind:Kind.Environment_boundary
    ~props:Environment_boundary_props
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
  create
    ~key
    ~kind:Kind.Gesture
    ~props:Gesture_props
    ~event_bindings:(Array.of_list event_bindings)
    ~children:(plain_children [ child ])
;;

let focus_scope ?key ?(autofocus = false) ~on_focus_changed child =
  create
    ~key
    ~kind:Kind.Focus_scope
    ~props:(Focus_scope_props { autofocus })
    ~event_bindings:[| { tag = Event.Tag.Focus_changed; handler = on_focus_changed } |]
    ~children:(plain_children [ child ])
;;

let mouse_region ?key ?(opaque = true) ~on_enter ~on_leave child =
  create
    ~key
    ~kind:Kind.Mouse_region
    ~props:(Mouse_region_props { opaque })
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
  create
    ~key
    ~kind:Kind.Keyboard_listener
    ~props:(Keyboard_listener_props { autofocus; key_policy })
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
  create
    ~key
    ~kind:Kind.Semantics
    ~props:
      (Semantics_props
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
  create
    ~key
    ~kind:Kind.Theme
    ~props:(Theme_props { brightness = data.brightness; color_seed = data.color_seed })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let navigator ?key ?restoration_scope_id ~on_pop pages =
  create
    ~key
    ~kind:Kind.Navigator
    ~props:(Navigator_props { restoration_scope_id })
    ~event_bindings:[| { tag = Event.Tag.Route_pop; handler = on_pop } |]
    ~children:(plain_children pages)
;;

let page
      ?key
      ~page_key
      ?(transition = Navigation.None)
      ?(can_pop = true)
      ?restoration_id
      child
  =
  if String.length (ID.Navigation.Page_key.to_string page_key) = 0
  then invalid_arg "Widget.page: page_key must not be empty";
  create
    ~key
    ~kind:Kind.Page
    ~props:(Page_props { page_key; transition; can_pop; restoration_id })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let overlay ?key ?(alignment = Navigation.Center) ?(dismissible = false) children =
  create
    ~key
    ~kind:Kind.Overlay
    ~props:(Overlay_props { alignment; dismissible })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let material_dialog ?key ?(barrier_dismissible = true) child =
  create
    ~key
    ~kind:Kind.Material_dialog
    ~props:(Material_dialog_props { barrier_dismissible })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let native_widget ?key ~kind_id ~version ~capabilities ~payload ~on_event ~children () =
  create
    ~key
    ~kind:Kind.Native_widget
    ~props:(Native_widget_props { kind_id; version; capabilities; payload })
    ~event_bindings:[| { tag = Event.Tag.Native_event; handler = on_event } |]
    ~children:(plain_children children)
;;

let material_checkbox ?key ?(enabled = true) ~value ~on_changed () =
  create
    ~key
    ~kind:Kind.Material_checkbox
    ~props:(Material_checkbox_props { value; enabled })
    ~event_bindings:[| { tag = Event.Tag.Value_changed; handler = on_changed } |]
    ~children:[||]
;;

let material_scaffold ?key ?app_bar ~body () =
  create
    ~key
    ~kind:Kind.Material_scaffold
    ~props:(Material_scaffold_props { has_app_bar = Option.is_some app_bar })
    ~event_bindings:[||]
    ~children:(plain_children (Option.to_list app_bar @ [ body ]))
;;

let material_app_bar ?key ?(center_title = false) ~title () =
  create
    ~key
    ~kind:Kind.Material_app_bar
    ~props:(Material_app_bar_props { center_title })
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
  let kind =
    match variant with
    | Elevated -> Kind.Material_elevated_button
    | Text_button -> Material_text_button
    | Icon_button -> Material_icon_button
  in
  create
    ~key
    ~kind
    ~props:(Material_button_props { variant; enabled; autofocus })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let material_switch ?key ?(enabled = true) ~value ~on_changed () =
  create
    ~key
    ~kind:Kind.Material_switch
    ~props:(Material_switch_props { value; enabled })
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
  create
    ~key
    ~kind:Kind.Material_list_tile
    ~props:
      (Material_list_tile_props
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
  create
    ~key
    ~kind:Kind.Material_divider
    ~props:
      (Material_divider_props { thickness = finite_nonnegative "thickness" thickness })
    ~event_bindings:[||]
    ~children:[||]
;;

let material_card ?key ?(elevation = 1.) child =
  create
    ~key
    ~kind:Kind.Material_card
    ~props:(Material_card_props { elevation = finite_nonnegative "elevation" elevation })
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
  create
    ~key
    ~kind:Kind.Material_circular_progress_indicator
    ~props:(Material_progress_props { value })
    ~event_bindings:[||]
    ~children:[||]
;;

let cupertino_button ?key ?(enabled = true) ~on_press ~child () =
  create
    ~key
    ~kind:Kind.Cupertino_button
    ~props:(Cupertino_button_props { enabled })
    ~event_bindings:[| { tag = Event.Tag.Press; handler = on_press } |]
    ~children:(plain_children [ child ])
;;

let cupertino_switch ?key ?(enabled = true) ~value ~on_changed () =
  create
    ~key
    ~kind:Kind.Cupertino_switch
    ~props:(Cupertino_switch_props { value; enabled })
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
  create
    ~key
    ~kind:Kind.Text_input
    ~props:
      (Text_input_props
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

  let create_linear ?key kind children =
    create
      ~key
      ~kind
      ~props:Linear_props
      ~event_bindings:[||]
      ~children:(Array.of_list children)
  ;;

  let row ?key children = create_linear ?key Kind.Flex_row children
  let column ?key children = create_linear ?key Kind.Flex_column children
end

module Stack = struct
  type nonrec child = child

  let child widget = { widget; parent_data = No_parent_data }

  let positioned ?left ?top ?right ?bottom widget =
    { widget; parent_data = Stack_position { left; top; right; bottom } }
  ;;

  let create ?key children =
    create
      ~key
      ~kind:Kind.Stack
      ~props:Stack_props
      ~event_bindings:[||]
      ~children:(Array.of_list children)
  ;;
end

module For_testing = struct
  let kind_name t = Kind.to_string t.view.kind
  let key t = t.view.key
  let test_id t = t.view.test_id
  let children t = Array.map (fun child -> child.widget) t.view.children

  let text_content t =
    match t.view.props with
    | Text_props { value; _ } -> Some value
    | _ -> None
  ;;
end

module Private = struct
  module Kind = Kind

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

  type nonrec props = props =
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
    | Overlay_props of
        { alignment : Navigation.overlay_alignment
        ; dismissible : bool
        }
    | Navigator_props of
        { restoration_scope_id : ID.Navigation.restoration_scope_id option }
    | Page_props of
        { page_key : ID.Navigation.page_key
        ; transition : Navigation.page_transition
        ; can_pop : bool
        ; restoration_id : ID.Navigation.restoration_id option
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
        { kind_id : ID.Native_widget.kind_id
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }

  type nonrec event_binding = event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type nonrec child = child =
    { widget : t
    ; parent_data : child_parent_data
    }

  type nonrec view = view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; kind : Kind.t
    ; props : props
    ; event_bindings : event_binding array
    ; children : child array
    ; fingerprint : int64
    }

  let view t = t.view
  let props_equal = props_equal
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
end
