(* Generated from [protocol/schema.sexp]. Do not edit. *)

module ID = Bonsai_flutter_spec.Id

let protocol_major = 1
let protocol_minor = 16

module Limits = struct
  let header_bytes = 48
  let max_frame_bytes = 16777216
  let max_string_bytes = 1048576
  let max_application_payload_bytes = 1048576
  let max_operations = 1000000
  let max_nodes = 1000000
end

module Frame_kind = struct
  let handshake = ID.Protocol.Frame_kind.of_int 1
  let full_snapshot = ID.Protocol.Frame_kind.of_int 2
  let incremental_frame = ID.Protocol.Frame_kind.of_int 3
  let event_batch = ID.Protocol.Frame_kind.of_int 4
  let runtime_error = ID.Protocol.Frame_kind.of_int 5

  let debug_name id =
    match ID.Protocol.Frame_kind.to_int id with
    | 1 -> Some "handshake"
    | 2 -> Some "full_snapshot"
    | 3 -> Some "incremental_frame"
    | 4 -> Some "event_batch"
    | 5 -> Some "runtime_error"
    | _ -> None
  ;;
end

module Operation = struct
  let begin_frame = ID.Protocol.Operation.of_int 1
  let create_node = ID.Protocol.Operation.of_int 2
  let update_props = ID.Protocol.Operation.of_int 3
  let update_event_bindings = ID.Protocol.Operation.of_int 4
  let set_children = ID.Protocol.Operation.of_int 5
  let set_root = ID.Protocol.Operation.of_int 6
  let drop_node = ID.Protocol.Operation.of_int 7
  let host_request = ID.Protocol.Operation.of_int 8
  let runtime_notification = ID.Protocol.Operation.of_int 9
  let end_frame = ID.Protocol.Operation.of_int 10
  let application_request = ID.Protocol.Operation.of_int 11

  let debug_name id =
    match ID.Protocol.Operation.to_int id with
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
    | 11 -> Some "application_request"
    | _ -> None
  ;;
end

module Node_kind = struct
  let empty = ID.Protocol.Node_kind.of_int 1
  let text = ID.Protocol.Node_kind.of_int 2
  let rich_text = ID.Protocol.Node_kind.of_int 3
  let icon = ID.Protocol.Node_kind.of_int 4
  let image = ID.Protocol.Node_kind.of_int 5
  let row = ID.Protocol.Node_kind.of_int 16
  let column = ID.Protocol.Node_kind.of_int 17
  let flex = ID.Protocol.Node_kind.of_int 18
  let stack = ID.Protocol.Node_kind.of_int 19
  let positioned = ID.Protocol.Node_kind.of_int 20
  let padding = ID.Protocol.Node_kind.of_int 21
  let align = ID.Protocol.Node_kind.of_int 22
  let center = ID.Protocol.Node_kind.of_int 23
  let sized_box = ID.Protocol.Node_kind.of_int 24
  let constrained_box = ID.Protocol.Node_kind.of_int 25
  let decorated_box = ID.Protocol.Node_kind.of_int 26
  let clip = ID.Protocol.Node_kind.of_int 27
  let opacity = ID.Protocol.Node_kind.of_int 28
  let transform = ID.Protocol.Node_kind.of_int 29
  let scroll_view = ID.Protocol.Node_kind.of_int 30
  let list_view = ID.Protocol.Node_kind.of_int 31
  let gesture = ID.Protocol.Node_kind.of_int 48
  let button = ID.Protocol.Node_kind.of_int 49
  let text_input = ID.Protocol.Node_kind.of_int 50
  let focus_scope = ID.Protocol.Node_kind.of_int 51
  let mouse_region = ID.Protocol.Node_kind.of_int 52
  let keyboard_listener = ID.Protocol.Node_kind.of_int 53
  let pressable = ID.Protocol.Node_kind.of_int 54
  let semantics = ID.Protocol.Node_kind.of_int 64
  let overlay = ID.Protocol.Node_kind.of_int 65
  let navigator = ID.Protocol.Node_kind.of_int 66
  let page = ID.Protocol.Node_kind.of_int 67
  let safe_area = ID.Protocol.Node_kind.of_int 68
  let theme = ID.Protocol.Node_kind.of_int 69
  let environment_boundary = ID.Protocol.Node_kind.of_int 70
  let animated_opacity = ID.Protocol.Node_kind.of_int 71
  let material_scaffold = ID.Protocol.Node_kind.of_int 96
  let material_app_bar = ID.Protocol.Node_kind.of_int 97
  let material_elevated_button = ID.Protocol.Node_kind.of_int 98
  let material_text_button = ID.Protocol.Node_kind.of_int 99
  let material_icon_button = ID.Protocol.Node_kind.of_int 100
  let material_checkbox = ID.Protocol.Node_kind.of_int 101
  let material_switch = ID.Protocol.Node_kind.of_int 102
  let material_text_field = ID.Protocol.Node_kind.of_int 103
  let material_list_tile = ID.Protocol.Node_kind.of_int 104
  let material_divider = ID.Protocol.Node_kind.of_int 105
  let material_card = ID.Protocol.Node_kind.of_int 106
  let material_dialog = ID.Protocol.Node_kind.of_int 107
  let material_circular_progress_indicator = ID.Protocol.Node_kind.of_int 108
  let cupertino_button = ID.Protocol.Node_kind.of_int 112
  let cupertino_switch = ID.Protocol.Node_kind.of_int 113
  let native_widget = ID.Protocol.Node_kind.of_int 128

  let debug_name id =
    match ID.Protocol.Node_kind.to_int id with
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
  let press = ID.Protocol.Event_tag.of_int 1
  let long_press = ID.Protocol.Event_tag.of_int 2
  let tap = ID.Protocol.Event_tag.of_int 3
  let double_tap = ID.Protocol.Event_tag.of_int 4
  let pointer_enter = ID.Protocol.Event_tag.of_int 5
  let pointer_leave = ID.Protocol.Event_tag.of_int 6
  let pointer_down = ID.Protocol.Event_tag.of_int 7
  let pointer_up = ID.Protocol.Event_tag.of_int 8
  let key = ID.Protocol.Event_tag.of_int 9
  let focus_changed = ID.Protocol.Event_tag.of_int 10
  let text_edit = ID.Protocol.Event_tag.of_int 11
  let text_submit = ID.Protocol.Event_tag.of_int 12
  let scroll_notification = ID.Protocol.Event_tag.of_int 13
  let visible_range_changed = ID.Protocol.Event_tag.of_int 14
  let animation_completed = ID.Protocol.Event_tag.of_int 15
  let route_pop = ID.Protocol.Event_tag.of_int 16
  let layout_observed = ID.Protocol.Event_tag.of_int 17
  let value_changed = ID.Protocol.Event_tag.of_int 18
  let host_response = ID.Protocol.Event_tag.of_int 19
  let environment_changed = ID.Protocol.Event_tag.of_int 20
  let native_event = ID.Protocol.Event_tag.of_int 21
  let semantics_action = ID.Protocol.Event_tag.of_int 22
  let resync_requested = ID.Protocol.Event_tag.of_int 23
  let text_limit_reached = ID.Protocol.Event_tag.of_int 24
  let application_response = ID.Protocol.Event_tag.of_int 25
  let application_request_error = ID.Protocol.Event_tag.of_int 26
  let application_event = ID.Protocol.Event_tag.of_int 27

  let debug_name id =
    match ID.Protocol.Event_tag.to_int id with
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
    | 24 -> Some "text_limit_reached"
    | 25 -> Some "application_response"
    | 26 -> Some "application_request_error"
    | 27 -> Some "application_event"
    | _ -> None
  ;;
end

module Host_request = struct
  let clipboard_read = ID.Protocol.Host_request_kind.of_int 1
  let clipboard_write = ID.Protocol.Host_request_kind.of_int 2
  let open_url = ID.Protocol.Host_request_kind.of_int 3
  let pick_file = ID.Protocol.Host_request_kind.of_int 4
  let save_file = ID.Protocol.Host_request_kind.of_int 5
  let request_focus = ID.Protocol.Host_request_kind.of_int 6
  let clear_focus = ID.Protocol.Host_request_kind.of_int 7
  let scroll_to = ID.Protocol.Host_request_kind.of_int 8
  let set_window_title = ID.Protocol.Host_request_kind.of_int 9
  let set_window_size = ID.Protocol.Host_request_kind.of_int 10
  let show_native_menu = ID.Protocol.Host_request_kind.of_int 11
  let haptic_feedback = ID.Protocol.Host_request_kind.of_int 12
  let platform_information = ID.Protocol.Host_request_kind.of_int 13
  let measure_layout = ID.Protocol.Host_request_kind.of_int 14

  let debug_name id =
    match ID.Protocol.Host_request_kind.to_int id with
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
  let protocol_error = ID.Protocol.Runtime_error.of_int 1
  let revision_mismatch = ID.Protocol.Runtime_error.of_int 2
  let duplicate_key = ID.Protocol.Runtime_error.of_int 3
  let unsupported_node_kind = ID.Protocol.Runtime_error.of_int 4
  let invalid_prop = ID.Protocol.Runtime_error.of_int 5
  let handler_missing = ID.Protocol.Runtime_error.of_int 6
  let stale_event = ID.Protocol.Runtime_error.of_int 7
  let host_effect_failure = ID.Protocol.Runtime_error.of_int 8
  let ocaml_exception = ID.Protocol.Runtime_error.of_int 9
  let dart_renderer_exception = ID.Protocol.Runtime_error.of_int 10
  let lifecycle_exception = ID.Protocol.Runtime_error.of_int 11
  let native_library_loading_error = ID.Protocol.Runtime_error.of_int 12

  let debug_name id =
    match ID.Protocol.Runtime_error.to_int id with
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
  let test_id = ID.Protocol.Property.of_int 1
  let semantics = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "test_id"
    | 2 -> Some "semantics"
    | _ -> None
  ;;
end

module Text_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let text_style = ID.Protocol.Property.of_int 2
  let text_align = ID.Protocol.Property.of_int 3
  let max_lines = ID.Protocol.Property.of_int 4
  let overflow = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "text_style"
    | 3 -> Some "text_align"
    | 4 -> Some "max_lines"
    | 5 -> Some "overflow"
    | _ -> None
  ;;
end

module Rich_text_prop = struct
  let spans = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spans"
    | _ -> None
  ;;
end

module Icon_prop = struct
  let code_point = ID.Protocol.Property.of_int 1
  let font_family = ID.Protocol.Property.of_int 2
  let size = ID.Protocol.Property.of_int 3
  let color = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "code_point"
    | 2 -> Some "font_family"
    | 3 -> Some "size"
    | 4 -> Some "color"
    | _ -> None
  ;;
end

module Image_prop = struct
  let uri = ID.Protocol.Property.of_int 1
  let fit = ID.Protocol.Property.of_int 2
  let width = ID.Protocol.Property.of_int 3
  let height = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "uri"
    | 2 -> Some "fit"
    | 3 -> Some "width"
    | 4 -> Some "height"
    | _ -> None
  ;;
end

module Row_prop = struct
  let main_axis_alignment = ID.Protocol.Property.of_int 1
  let main_axis_size = ID.Protocol.Property.of_int 2
  let cross_axis_alignment = ID.Protocol.Property.of_int 3
  let text_direction = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "main_axis_alignment"
    | 2 -> Some "main_axis_size"
    | 3 -> Some "cross_axis_alignment"
    | 4 -> Some "text_direction"
    | _ -> None
  ;;
end

module Column_prop = struct
  let main_axis_alignment = ID.Protocol.Property.of_int 1
  let main_axis_size = ID.Protocol.Property.of_int 2
  let cross_axis_alignment = ID.Protocol.Property.of_int 3
  let text_direction = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "main_axis_alignment"
    | 2 -> Some "main_axis_size"
    | 3 -> Some "cross_axis_alignment"
    | 4 -> Some "text_direction"
    | _ -> None
  ;;
end

module Padding_prop = struct
  let insets = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "insets"
    | _ -> None
  ;;
end

module Align_prop = struct
  let alignment = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "alignment"
    | _ -> None
  ;;
end

module Center_prop = struct
  let width_factor = ID.Protocol.Property.of_int 1
  let height_factor = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "width_factor"
    | 2 -> Some "height_factor"
    | _ -> None
  ;;
end

module Sized_box_prop = struct
  let width = ID.Protocol.Property.of_int 1
  let height = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "width"
    | 2 -> Some "height"
    | _ -> None
  ;;
end

module Constrained_box_prop = struct
  let min_width = ID.Protocol.Property.of_int 1
  let max_width = ID.Protocol.Property.of_int 2
  let min_height = ID.Protocol.Property.of_int 3
  let max_height = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "min_width"
    | 2 -> Some "max_width"
    | 3 -> Some "min_height"
    | 4 -> Some "max_height"
    | _ -> None
  ;;
end

module Decorated_box_prop = struct
  let background = ID.Protocol.Property.of_int 1
  let border_radius = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "background"
    | 2 -> Some "border_radius"
    | _ -> None
  ;;
end

module Clip_prop = struct
  let behavior = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "behavior"
    | _ -> None
  ;;
end

module Opacity_prop = struct
  let opacity = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "opacity"
    | _ -> None
  ;;
end

module Animated_opacity_prop = struct
  let opacity = ID.Protocol.Property.of_int 1
  let animation_id = ID.Protocol.Property.of_int 2
  let duration_ms = ID.Protocol.Property.of_int 3
  let curve = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "opacity"
    | 2 -> Some "animation_id"
    | 3 -> Some "duration_ms"
    | 4 -> Some "curve"
    | _ -> None
  ;;
end

module Transform_prop = struct
  let matrix4 = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "matrix4"
    | _ -> None
  ;;
end

module Scroll_view_prop = struct
  let axis = ID.Protocol.Property.of_int 1
  let reverse = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "axis"
    | 2 -> Some "reverse"
    | _ -> None
  ;;
end

module List_view_prop = struct
  let axis = ID.Protocol.Property.of_int 1
  let reverse = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "axis"
    | 2 -> Some "reverse"
    | _ -> None
  ;;
end

module Focus_scope_prop = struct
  let autofocus = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "autofocus"
    | _ -> None
  ;;
end

module Mouse_region_prop = struct
  let opaque = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "opaque"
    | _ -> None
  ;;
end

module Keyboard_listener_prop = struct
  let autofocus = ID.Protocol.Property.of_int 1
  let key_policy = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "autofocus"
    | 2 -> Some "key_policy"
    | _ -> None
  ;;
end

module Button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | _ -> None
  ;;
end

module Semantics_prop = struct
  let label = ID.Protocol.Property.of_int 1
  let hint = ID.Protocol.Property.of_int 2
  let value = ID.Protocol.Property.of_int 3
  let role = ID.Protocol.Property.of_int 4
  let enabled = ID.Protocol.Property.of_int 5
  let selected = ID.Protocol.Property.of_int 6
  let checked = ID.Protocol.Property.of_int 7
  let focusable = ID.Protocol.Property.of_int 8
  let obscured = ID.Protocol.Property.of_int 9
  let live_region = ID.Protocol.Property.of_int 10
  let heading_level = ID.Protocol.Property.of_int 11
  let sort_key = ID.Protocol.Property.of_int 12
  let actions = ID.Protocol.Property.of_int 13

  let debug_name id =
    match ID.Protocol.Property.to_int id with
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
  let brightness = ID.Protocol.Property.of_int 1
  let color_seed = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "brightness"
    | 2 -> Some "color_seed"
    | _ -> None
  ;;
end

module Material_scaffold_prop = struct
  let has_app_bar = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "has_app_bar"
    | _ -> None
  ;;
end

module Material_app_bar_prop = struct
  let center_title = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "center_title"
    | _ -> None
  ;;
end

module Material_elevated_button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let autofocus = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_text_button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let autofocus = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_icon_button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let autofocus = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "autofocus"
    | _ -> None
  ;;
end

module Material_checkbox_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Material_switch_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Material_list_tile_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let selected = ID.Protocol.Property.of_int 2
  let has_subtitle = ID.Protocol.Property.of_int 3
  let has_leading = ID.Protocol.Property.of_int 4
  let has_trailing = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "selected"
    | 3 -> Some "has_subtitle"
    | 4 -> Some "has_leading"
    | 5 -> Some "has_trailing"
    | _ -> None
  ;;
end

module Material_divider_prop = struct
  let thickness = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "thickness"
    | _ -> None
  ;;
end

module Material_card_prop = struct
  let elevation = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "elevation"
    | _ -> None
  ;;
end

module Material_circular_progress_indicator_prop = struct
  let value = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | _ -> None
  ;;
end

module Cupertino_button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | _ -> None
  ;;
end

module Cupertino_switch_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Text_input_prop = struct
  let session_id = ID.Protocol.Property.of_int 1
  let document_revision = ID.Protocol.Property.of_int 2
  let value = ID.Protocol.Property.of_int 3
  let enabled = ID.Protocol.Property.of_int 4
  let read_only = ID.Protocol.Property.of_int 5
  let obscure_text = ID.Protocol.Property.of_int 6
  let keyboard_type = ID.Protocol.Property.of_int 7
  let input_action = ID.Protocol.Property.of_int 8
  let accepted_local_revision = ID.Protocol.Property.of_int 9
  let update_mode = ID.Protocol.Property.of_int 10
  let autofocus = ID.Protocol.Property.of_int 11
  let max_utf8_bytes = ID.Protocol.Property.of_int 12

  let debug_name id =
    match ID.Protocol.Property.to_int id with
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
    | 12 -> Some "max_utf8_bytes"
    | _ -> None
  ;;
end

module Overlay_prop = struct
  let alignment = ID.Protocol.Property.of_int 1
  let dismissible = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "alignment"
    | 2 -> Some "dismissible"
    | _ -> None
  ;;
end

module Navigator_prop = struct
  let restoration_scope_id = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "restoration_scope_id"
    | _ -> None
  ;;
end

module Page_prop = struct
  let page_key = ID.Protocol.Property.of_int 1
  let transition = ID.Protocol.Property.of_int 2
  let can_pop = ID.Protocol.Property.of_int 3
  let restoration_id = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "page_key"
    | 2 -> Some "transition"
    | 3 -> Some "can_pop"
    | 4 -> Some "restoration_id"
    | _ -> None
  ;;
end

module Safe_area_prop = struct
  let left = ID.Protocol.Property.of_int 1
  let top = ID.Protocol.Property.of_int 2
  let right = ID.Protocol.Property.of_int 3
  let bottom = ID.Protocol.Property.of_int 4
  let minimum = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "left"
    | 2 -> Some "top"
    | 3 -> Some "right"
    | 4 -> Some "bottom"
    | 5 -> Some "minimum"
    | _ -> None
  ;;
end

module Material_dialog_prop = struct
  let barrier_dismissible = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "barrier_dismissible"
    | _ -> None
  ;;
end

module Pressable_prop = struct
  let overlay_color = ID.Protocol.Property.of_int 1
  let release_delay_ms = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "overlay_color"
    | 2 -> Some "release_delay_ms"
    | _ -> None
  ;;
end

module Native_widget_prop = struct
  let kind_id = ID.Protocol.Property.of_int 1
  let version = ID.Protocol.Property.of_int 2
  let capabilities = ID.Protocol.Property.of_int 3
  let payload = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "kind_id"
    | 2 -> Some "version"
    | 3 -> Some "capabilities"
    | 4 -> Some "payload"
    | _ -> None
  ;;
end
