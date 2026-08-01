(* Generated from [protocol/schema.sexp]. Do not edit. *)

let protocol_major = 1
let protocol_minor = 14

module Limits = struct
  let header_bytes = 48
  let max_frame_bytes = 16777216
  let max_string_bytes = 1048576
  let max_operations = 1000000
  let max_nodes = 1000000
end

module Frame_kind = struct
  let handshake = 1
  let full_snapshot = 2
  let incremental_frame = 3
  let event_batch = 4
  let runtime_error = 5

  let debug_name = function
    | 1 -> Some "handshake"
    | 2 -> Some "full_snapshot"
    | 3 -> Some "incremental_frame"
    | 4 -> Some "event_batch"
    | 5 -> Some "runtime_error"
    | _ -> None
  ;;
end

module Operation = struct
  let begin_frame = 1
  let create_node = 2
  let update_props = 3
  let update_event_bindings = 4
  let set_children = 5
  let set_root = 6
  let drop_node = 7
  let host_request = 8
  let runtime_notification = 9
  let end_frame = 10

  let debug_name = function
    | 1 -> Some "begin_frame"
    | 2 -> Some "create_node"
    | 3 -> Some "update_props"
    | 4 -> Some "update_event_bindings"
    | 5 -> Some "set_children"
    | 6 -> Some "set_root"
    | 7 -> Some "drop_node"
    | 8 -> Some "host_request"
    | 9 -> Some "runtime_notification"
    | 10 -> Some "end_frame"
    | _ -> None
  ;;
end

module Node_kind = struct
  let empty = 1
  let text = 2
  let rich_text = 3
  let icon = 4
  let image = 5
  let row = 16
  let column = 17
  let flex = 18
  let stack = 19
  let positioned = 20
  let padding = 21
  let align = 22
  let center = 23
  let sized_box = 24
  let constrained_box = 25
  let decorated_box = 26
  let clip = 27
  let opacity = 28
  let transform = 29
  let scroll_view = 30
  let list_view = 31
  let gesture = 48
  let button = 49
  let text_input = 50
  let focus_scope = 51
  let mouse_region = 52
  let keyboard_listener = 53
  let pressable = 54
  let semantics = 64
  let overlay = 65
  let navigator = 66
  let page = 67
  let safe_area = 68
  let theme = 69
  let environment_boundary = 70
  let animated_opacity = 71
  let material_scaffold = 96
  let material_app_bar = 97
  let material_elevated_button = 98
  let material_text_button = 99
  let material_icon_button = 100
  let material_checkbox = 101
  let material_switch = 102
  let material_text_field = 103
  let material_list_tile = 104
  let material_divider = 105
  let material_card = 106
  let material_dialog = 107
  let material_circular_progress_indicator = 108
  let cupertino_button = 112
  let cupertino_switch = 113
  let native_widget = 128

  let debug_name = function
    | 1 -> Some "empty"
    | 2 -> Some "text"
    | 3 -> Some "rich_text"
    | 4 -> Some "icon"
    | 5 -> Some "image"
    | 16 -> Some "row"
    | 17 -> Some "column"
    | 18 -> Some "flex"
    | 19 -> Some "stack"
    | 20 -> Some "positioned"
    | 21 -> Some "padding"
    | 22 -> Some "align"
    | 23 -> Some "center"
    | 24 -> Some "sized_box"
    | 25 -> Some "constrained_box"
    | 26 -> Some "decorated_box"
    | 27 -> Some "clip"
    | 28 -> Some "opacity"
    | 29 -> Some "transform"
    | 30 -> Some "scroll_view"
    | 31 -> Some "list_view"
    | 48 -> Some "gesture"
    | 49 -> Some "button"
    | 50 -> Some "text_input"
    | 51 -> Some "focus_scope"
    | 52 -> Some "mouse_region"
    | 53 -> Some "keyboard_listener"
    | 54 -> Some "pressable"
    | 64 -> Some "semantics"
    | 65 -> Some "overlay"
    | 66 -> Some "navigator"
    | 67 -> Some "page"
    | 68 -> Some "safe_area"
    | 69 -> Some "theme"
    | 70 -> Some "environment_boundary"
    | 71 -> Some "animated_opacity"
    | 96 -> Some "material_scaffold"
    | 97 -> Some "material_app_bar"
    | 98 -> Some "material_elevated_button"
    | 99 -> Some "material_text_button"
    | 100 -> Some "material_icon_button"
    | 101 -> Some "material_checkbox"
    | 102 -> Some "material_switch"
    | 103 -> Some "material_text_field"
    | 104 -> Some "material_list_tile"
    | 105 -> Some "material_divider"
    | 106 -> Some "material_card"
    | 107 -> Some "material_dialog"
    | 108 -> Some "material_circular_progress_indicator"
    | 112 -> Some "cupertino_button"
    | 113 -> Some "cupertino_switch"
    | 128 -> Some "native_widget"
    | _ -> None
  ;;
end

module Event_tag = struct
  let press = 1
  let long_press = 2
  let tap = 3
  let double_tap = 4
  let pointer_enter = 5
  let pointer_leave = 6
  let pointer_down = 7
  let pointer_up = 8
  let key = 9
  let focus_changed = 10
  let text_edit = 11
  let text_submit = 12
  let scroll_notification = 13
  let visible_range_changed = 14
  let animation_completed = 15
  let route_pop = 16
  let layout_observed = 17
  let value_changed = 18
  let host_response = 19
  let environment_changed = 20
  let native_event = 21
  let semantics_action = 22
  let resync_requested = 23

  let debug_name = function
    | 1 -> Some "press"
    | 2 -> Some "long_press"
    | 3 -> Some "tap"
    | 4 -> Some "double_tap"
    | 5 -> Some "pointer_enter"
    | 6 -> Some "pointer_leave"
    | 7 -> Some "pointer_down"
    | 8 -> Some "pointer_up"
    | 9 -> Some "key"
    | 10 -> Some "focus_changed"
    | 11 -> Some "text_edit"
    | 12 -> Some "text_submit"
    | 13 -> Some "scroll_notification"
    | 14 -> Some "visible_range_changed"
    | 15 -> Some "animation_completed"
    | 16 -> Some "route_pop"
    | 17 -> Some "layout_observed"
    | 18 -> Some "value_changed"
    | 19 -> Some "host_response"
    | 20 -> Some "environment_changed"
    | 21 -> Some "native_event"
    | 22 -> Some "semantics_action"
    | 23 -> Some "resync_requested"
    | _ -> None
  ;;
end

module Host_request = struct
  let clipboard_read = 1
  let clipboard_write = 2
  let open_url = 3
  let pick_file = 4
  let save_file = 5
  let request_focus = 6
  let clear_focus = 7
  let scroll_to = 8
  let set_window_title = 9
  let set_window_size = 10
  let show_native_menu = 11
  let haptic_feedback = 12
  let platform_information = 13
  let measure_layout = 14

  let debug_name = function
    | 1 -> Some "clipboard_read"
    | 2 -> Some "clipboard_write"
    | 3 -> Some "open_url"
    | 4 -> Some "pick_file"
    | 5 -> Some "save_file"
    | 6 -> Some "request_focus"
    | 7 -> Some "clear_focus"
    | 8 -> Some "scroll_to"
    | 9 -> Some "set_window_title"
    | 10 -> Some "set_window_size"
    | 11 -> Some "show_native_menu"
    | 12 -> Some "haptic_feedback"
    | 13 -> Some "platform_information"
    | 14 -> Some "measure_layout"
    | _ -> None
  ;;
end

module Runtime_error = struct
  let protocol_error = 1
  let revision_mismatch = 2
  let duplicate_key = 3
  let unsupported_node_kind = 4
  let invalid_prop = 5
  let handler_missing = 6
  let stale_event = 7
  let host_effect_failure = 8
  let ocaml_exception = 9
  let dart_renderer_exception = 10
  let lifecycle_exception = 11
  let native_library_loading_error = 12

  let debug_name = function
    | 1 -> Some "protocol_error"
    | 2 -> Some "revision_mismatch"
    | 3 -> Some "duplicate_key"
    | 4 -> Some "unsupported_node_kind"
    | 5 -> Some "invalid_prop"
    | 6 -> Some "handler_missing"
    | 7 -> Some "stale_event"
    | 8 -> Some "host_effect_failure"
    | 9 -> Some "ocaml_exception"
    | 10 -> Some "dart_renderer_exception"
    | 11 -> Some "lifecycle_exception"
    | 12 -> Some "native_library_loading_error"
    | _ -> None
  ;;
end

module Common_prop = struct
  let test_id = 1
  let semantics = 2

  let debug_name = function
    | 1 -> Some "test_id"
    | 2 -> Some "semantics"
    | _ -> None
  ;;
end

module Text_prop = struct
  let value = 1
  let text_style = 2
  let text_align = 3
  let max_lines = 4
  let overflow = 5

  let debug_name = function
    | 1 -> Some "value"
    | 2 -> Some "text_style"
    | 3 -> Some "text_align"
    | 4 -> Some "max_lines"
    | 5 -> Some "overflow"
    | _ -> None
  ;;
end

module Rich_text_prop = struct
  let spans = 1

  let debug_name = function
    | 1 -> Some "spans"
    | _ -> None
  ;;
end

module Icon_prop = struct
  let code_point = 1
  let font_family = 2
  let size = 3
  let color = 4

  let debug_name = function
    | 1 -> Some "code_point"
    | 2 -> Some "font_family"
    | 3 -> Some "size"
    | 4 -> Some "color"
    | _ -> None
  ;;
end

module Image_prop = struct
  let uri = 1
  let fit = 2
  let width = 3
  let height = 4

  let debug_name = function
    | 1 -> Some "uri"
    | 2 -> Some "fit"
    | 3 -> Some "width"
    | 4 -> Some "height"
    | _ -> None
  ;;
end

module Row_prop = struct
  let main_axis_alignment = 1
  let main_axis_size = 2
  let cross_axis_alignment = 3
  let text_direction = 4

  let debug_name = function
    | 1 -> Some "main_axis_alignment"
    | 2 -> Some "main_axis_size"
    | 3 -> Some "cross_axis_alignment"
    | 4 -> Some "text_direction"
    | _ -> None
  ;;
end

module Column_prop = struct
  let main_axis_alignment = 1
  let main_axis_size = 2
  let cross_axis_alignment = 3
  let text_direction = 4

  let debug_name = function
    | 1 -> Some "main_axis_alignment"
    | 2 -> Some "main_axis_size"
    | 3 -> Some "cross_axis_alignment"
    | 4 -> Some "text_direction"
    | _ -> None
  ;;
end

module Padding_prop = struct
  let insets = 1

  let debug_name = function
    | 1 -> Some "insets"
    | _ -> None
  ;;
end

module Align_prop = struct
  let alignment = 1

  let debug_name = function
    | 1 -> Some "alignment"
    | _ -> None
  ;;
end

module Center_prop = struct
  let width_factor = 1
  let height_factor = 2

  let debug_name = function
    | 1 -> Some "width_factor"
    | 2 -> Some "height_factor"
    | _ -> None
  ;;
end

module Sized_box_prop = struct
  let width = 1
  let height = 2

  let debug_name = function
    | 1 -> Some "width"
    | 2 -> Some "height"
    | _ -> None
  ;;
end

module Constrained_box_prop = struct
  let min_width = 1
  let max_width = 2
  let min_height = 3
  let max_height = 4

  let debug_name = function
    | 1 -> Some "min_width"
    | 2 -> Some "max_width"
    | 3 -> Some "min_height"
    | 4 -> Some "max_height"
    | _ -> None
  ;;
end

module Decorated_box_prop = struct
  let background = 1
  let border_radius = 2

  let debug_name = function
    | 1 -> Some "background"
    | 2 -> Some "border_radius"
    | _ -> None
  ;;
end

module Clip_prop = struct
  let behavior = 1

  let debug_name = function
    | 1 -> Some "behavior"
    | _ -> None
  ;;
end

module Opacity_prop = struct
  let opacity = 1

  let debug_name = function
    | 1 -> Some "opacity"
    | _ -> None
  ;;
end

module Animated_opacity_prop = struct
  let opacity = 1
  let animation_id = 2
  let duration_ms = 3
  let curve = 4

  let debug_name = function
    | 1 -> Some "opacity"
    | 2 -> Some "animation_id"
    | 3 -> Some "duration_ms"
    | 4 -> Some "curve"
    | _ -> None
  ;;
end

module Transform_prop = struct
  let matrix4 = 1

  let debug_name = function
    | 1 -> Some "matrix4"
    | _ -> None
  ;;
end

module Scroll_view_prop = struct
  let axis = 1
  let reverse = 2

  let debug_name = function
    | 1 -> Some "axis"
    | 2 -> Some "reverse"
    | _ -> None
  ;;
end

module List_view_prop = struct
  let axis = 1
  let reverse = 2

  let debug_name = function
    | 1 -> Some "axis"
    | 2 -> Some "reverse"
    | _ -> None
  ;;
end

module Focus_scope_prop = struct
  let autofocus = 1

  let debug_name = function
    | 1 -> Some "autofocus"
    | _ -> None
  ;;
end

module Mouse_region_prop = struct
  let opaque = 1

  let debug_name = function
    | 1 -> Some "opaque"
    | _ -> None
  ;;
end

module Keyboard_listener_prop = struct
  let autofocus = 1
  let key_policy = 2

  let debug_name = function
    | 1 -> Some "autofocus"
    | 2 -> Some "key_policy"
    | _ -> None
  ;;
end

module Button_prop = struct
  let enabled = 1

  let debug_name = function
    | 1 -> Some "enabled"
    | _ -> None
  ;;
end

module Semantics_prop = struct
  let label = 1
  let hint = 2
  let value = 3
  let role = 4
  let enabled = 5
  let selected = 6
  let checked = 7
  let focusable = 8
  let obscured = 9
  let live_region = 10
  let heading_level = 11
  let sort_key = 12
  let actions = 13

  let debug_name = function
    | 1 -> Some "label"
    | 2 -> Some "hint"
    | 3 -> Some "value"
    | 4 -> Some "role"
    | 5 -> Some "enabled"
    | 6 -> Some "selected"
    | 7 -> Some "checked"
    | 8 -> Some "focusable"
    | 9 -> Some "obscured"
    | 10 -> Some "live_region"
    | 11 -> Some "heading_level"
    | 12 -> Some "sort_key"
    | 13 -> Some "actions"
    | _ -> None
  ;;
end

module Theme_prop = struct
  let brightness = 1
  let color_seed = 2

  let debug_name = function
    | 1 -> Some "brightness"
    | 2 -> Some "color_seed"
    | _ -> None
  ;;
end

module Material_scaffold_prop = struct
  let has_app_bar = 1

  let debug_name = function
    | 1 -> Some "has_app_bar"
    | _ -> None
  ;;
end

module Material_app_bar_prop = struct
  let center_title = 1

  let debug_name = function
    | 1 -> Some "center_title"
    | _ -> None
  ;;
end

module Material_elevated_button_prop = struct
  let enabled = 1
  let autofocus = 2

  let debug_name = function
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_text_button_prop = struct
  let enabled = 1
  let autofocus = 2

  let debug_name = function
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_icon_button_prop = struct
  let enabled = 1
  let autofocus = 2

  let debug_name = function
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_checkbox_prop = struct
  let value = 1
  let enabled = 2

  let debug_name = function
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Material_switch_prop = struct
  let value = 1
  let enabled = 2

  let debug_name = function
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Material_list_tile_prop = struct
  let enabled = 1
  let selected = 2
  let has_subtitle = 3
  let has_leading = 4
  let has_trailing = 5

  let debug_name = function
    | 1 -> Some "enabled"
    | 2 -> Some "selected"
    | 3 -> Some "has_subtitle"
    | 4 -> Some "has_leading"
    | 5 -> Some "has_trailing"
    | _ -> None
  ;;
end

module Material_divider_prop = struct
  let thickness = 1

  let debug_name = function
    | 1 -> Some "thickness"
    | _ -> None
  ;;
end

module Material_card_prop = struct
  let elevation = 1

  let debug_name = function
    | 1 -> Some "elevation"
    | _ -> None
  ;;
end

module Material_circular_progress_indicator_prop = struct
  let value = 1

  let debug_name = function
    | 1 -> Some "value"
    | _ -> None
  ;;
end

module Cupertino_button_prop = struct
  let enabled = 1

  let debug_name = function
    | 1 -> Some "enabled"
    | _ -> None
  ;;
end

module Cupertino_switch_prop = struct
  let value = 1
  let enabled = 2

  let debug_name = function
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Text_input_prop = struct
  let session_id = 1
  let document_revision = 2
  let value = 3
  let enabled = 4
  let read_only = 5
  let obscure_text = 6
  let keyboard_type = 7
  let input_action = 8
  let accepted_local_revision = 9
  let update_mode = 10
  let autofocus = 11

  let debug_name = function
    | 1 -> Some "session_id"
    | 2 -> Some "document_revision"
    | 3 -> Some "value"
    | 4 -> Some "enabled"
    | 5 -> Some "read_only"
    | 6 -> Some "obscure_text"
    | 7 -> Some "keyboard_type"
    | 8 -> Some "input_action"
    | 9 -> Some "accepted_local_revision"
    | 10 -> Some "update_mode"
    | 11 -> Some "autofocus"
    | _ -> None
  ;;
end

module Overlay_prop = struct
  let alignment = 1
  let dismissible = 2

  let debug_name = function
    | 1 -> Some "alignment"
    | 2 -> Some "dismissible"
    | _ -> None
  ;;
end

module Navigator_prop = struct
  let restoration_scope_id = 1

  let debug_name = function
    | 1 -> Some "restoration_scope_id"
    | _ -> None
  ;;
end

module Page_prop = struct
  let page_key = 1
  let transition = 2
  let can_pop = 3
  let restoration_id = 4

  let debug_name = function
    | 1 -> Some "page_key"
    | 2 -> Some "transition"
    | 3 -> Some "can_pop"
    | 4 -> Some "restoration_id"
    | _ -> None
  ;;
end

module Safe_area_prop = struct
  let left = 1
  let top = 2
  let right = 3
  let bottom = 4
  let minimum = 5

  let debug_name = function
    | 1 -> Some "left"
    | 2 -> Some "top"
    | 3 -> Some "right"
    | 4 -> Some "bottom"
    | 5 -> Some "minimum"
    | _ -> None
  ;;
end

module Material_dialog_prop = struct
  let barrier_dismissible = 1

  let debug_name = function
    | 1 -> Some "barrier_dismissible"
    | _ -> None
  ;;
end

module Pressable_prop = struct
  let overlay_color = 1
  let release_delay_ms = 2

  let debug_name = function
    | 1 -> Some "overlay_color"
    | 2 -> Some "release_delay_ms"
    | _ -> None
  ;;
end

module Native_widget_prop = struct
  let kind_id = 1
  let version = 2
  let capabilities = 3
  let payload = 4

  let debug_name = function
    | 1 -> Some "kind_id"
    | 2 -> Some "version"
    | 3 -> Some "capabilities"
    | 4 -> Some "payload"
    | _ -> None
  ;;
end
