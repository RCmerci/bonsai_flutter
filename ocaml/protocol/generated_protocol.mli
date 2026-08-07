(** Generated from [protocol/schema.sexp]. Do not edit. *)

val protocol_major : int
val protocol_minor : int

module Limits : sig
  val header_bytes : int
  val max_frame_bytes : int
  val max_string_bytes : int
  val max_application_payload_bytes : int
  val max_operations : int
  val max_nodes : int
end

module Frame_kind : sig
  val handshake : Bonsai_flutter_spec.Id.Protocol.frame_kind
  val full_snapshot : Bonsai_flutter_spec.Id.Protocol.frame_kind
  val incremental_frame : Bonsai_flutter_spec.Id.Protocol.frame_kind
  val event_batch : Bonsai_flutter_spec.Id.Protocol.frame_kind
  val runtime_error : Bonsai_flutter_spec.Id.Protocol.frame_kind
  val debug_name : Bonsai_flutter_spec.Id.Protocol.frame_kind -> string option
end

module Operation : sig
  val begin_frame : Bonsai_flutter_spec.Id.Protocol.operation
  val create_node : Bonsai_flutter_spec.Id.Protocol.operation
  val update_props : Bonsai_flutter_spec.Id.Protocol.operation
  val update_event_bindings : Bonsai_flutter_spec.Id.Protocol.operation
  val set_children : Bonsai_flutter_spec.Id.Protocol.operation
  val set_root : Bonsai_flutter_spec.Id.Protocol.operation
  val drop_node : Bonsai_flutter_spec.Id.Protocol.operation
  val host_request : Bonsai_flutter_spec.Id.Protocol.operation
  val runtime_notification : Bonsai_flutter_spec.Id.Protocol.operation
  val end_frame : Bonsai_flutter_spec.Id.Protocol.operation
  val application_request : Bonsai_flutter_spec.Id.Protocol.operation
  val debug_name : Bonsai_flutter_spec.Id.Protocol.operation -> string option
end

module Node_kind : sig
  val empty : Bonsai_flutter_spec.Id.Protocol.node_kind
  val text : Bonsai_flutter_spec.Id.Protocol.node_kind
  val rich_text : Bonsai_flutter_spec.Id.Protocol.node_kind
  val icon : Bonsai_flutter_spec.Id.Protocol.node_kind
  val image : Bonsai_flutter_spec.Id.Protocol.node_kind
  val row : Bonsai_flutter_spec.Id.Protocol.node_kind
  val column : Bonsai_flutter_spec.Id.Protocol.node_kind
  val flex : Bonsai_flutter_spec.Id.Protocol.node_kind
  val stack : Bonsai_flutter_spec.Id.Protocol.node_kind
  val positioned : Bonsai_flutter_spec.Id.Protocol.node_kind
  val padding : Bonsai_flutter_spec.Id.Protocol.node_kind
  val align : Bonsai_flutter_spec.Id.Protocol.node_kind
  val center : Bonsai_flutter_spec.Id.Protocol.node_kind
  val sized_box : Bonsai_flutter_spec.Id.Protocol.node_kind
  val constrained_box : Bonsai_flutter_spec.Id.Protocol.node_kind
  val decorated_box : Bonsai_flutter_spec.Id.Protocol.node_kind
  val clip : Bonsai_flutter_spec.Id.Protocol.node_kind
  val opacity : Bonsai_flutter_spec.Id.Protocol.node_kind
  val transform : Bonsai_flutter_spec.Id.Protocol.node_kind
  val scroll_view : Bonsai_flutter_spec.Id.Protocol.node_kind
  val list_view : Bonsai_flutter_spec.Id.Protocol.node_kind
  val gesture : Bonsai_flutter_spec.Id.Protocol.node_kind
  val button : Bonsai_flutter_spec.Id.Protocol.node_kind
  val text_input : Bonsai_flutter_spec.Id.Protocol.node_kind
  val focus_scope : Bonsai_flutter_spec.Id.Protocol.node_kind
  val mouse_region : Bonsai_flutter_spec.Id.Protocol.node_kind
  val keyboard_listener : Bonsai_flutter_spec.Id.Protocol.node_kind
  val pressable : Bonsai_flutter_spec.Id.Protocol.node_kind
  val semantics : Bonsai_flutter_spec.Id.Protocol.node_kind
  val overlay : Bonsai_flutter_spec.Id.Protocol.node_kind
  val navigator : Bonsai_flutter_spec.Id.Protocol.node_kind
  val page : Bonsai_flutter_spec.Id.Protocol.node_kind
  val safe_area : Bonsai_flutter_spec.Id.Protocol.node_kind
  val theme : Bonsai_flutter_spec.Id.Protocol.node_kind
  val environment_boundary : Bonsai_flutter_spec.Id.Protocol.node_kind
  val animated_opacity : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_scaffold : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_app_bar : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_elevated_button : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_text_button : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_icon_button : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_checkbox : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_switch : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_text_field : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_list_tile : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_divider : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_card : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_dialog : Bonsai_flutter_spec.Id.Protocol.node_kind
  val material_circular_progress_indicator : Bonsai_flutter_spec.Id.Protocol.node_kind
  val cupertino_button : Bonsai_flutter_spec.Id.Protocol.node_kind
  val cupertino_switch : Bonsai_flutter_spec.Id.Protocol.node_kind
  val native_widget : Bonsai_flutter_spec.Id.Protocol.node_kind
  val debug_name : Bonsai_flutter_spec.Id.Protocol.node_kind -> string option
end

module Event_tag : sig
  val press : Bonsai_flutter_spec.Id.Protocol.event_tag
  val long_press : Bonsai_flutter_spec.Id.Protocol.event_tag
  val tap : Bonsai_flutter_spec.Id.Protocol.event_tag
  val double_tap : Bonsai_flutter_spec.Id.Protocol.event_tag
  val pointer_enter : Bonsai_flutter_spec.Id.Protocol.event_tag
  val pointer_leave : Bonsai_flutter_spec.Id.Protocol.event_tag
  val pointer_down : Bonsai_flutter_spec.Id.Protocol.event_tag
  val pointer_up : Bonsai_flutter_spec.Id.Protocol.event_tag
  val key : Bonsai_flutter_spec.Id.Protocol.event_tag
  val focus_changed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val text_edit : Bonsai_flutter_spec.Id.Protocol.event_tag
  val text_submit : Bonsai_flutter_spec.Id.Protocol.event_tag
  val scroll_notification : Bonsai_flutter_spec.Id.Protocol.event_tag
  val visible_range_changed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val animation_completed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val route_pop : Bonsai_flutter_spec.Id.Protocol.event_tag
  val layout_observed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val value_changed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val host_response : Bonsai_flutter_spec.Id.Protocol.event_tag
  val environment_changed : Bonsai_flutter_spec.Id.Protocol.event_tag
  val native_event : Bonsai_flutter_spec.Id.Protocol.event_tag
  val semantics_action : Bonsai_flutter_spec.Id.Protocol.event_tag
  val resync_requested : Bonsai_flutter_spec.Id.Protocol.event_tag
  val text_limit_reached : Bonsai_flutter_spec.Id.Protocol.event_tag
  val application_response : Bonsai_flutter_spec.Id.Protocol.event_tag
  val application_request_error : Bonsai_flutter_spec.Id.Protocol.event_tag
  val application_event : Bonsai_flutter_spec.Id.Protocol.event_tag
  val debug_name : Bonsai_flutter_spec.Id.Protocol.event_tag -> string option
end

module Host_request : sig
  val clipboard_read : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val clipboard_write : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val open_url : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val pick_file : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val save_file : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val request_focus : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val clear_focus : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val scroll_to : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val set_window_title : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val set_window_size : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val show_native_menu : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val haptic_feedback : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val platform_information : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val measure_layout : Bonsai_flutter_spec.Id.Protocol.host_request_kind
  val debug_name : Bonsai_flutter_spec.Id.Protocol.host_request_kind -> string option
end

module Runtime_error : sig
  val protocol_error : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val revision_mismatch : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val duplicate_key : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val unsupported_node_kind : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val invalid_prop : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val handler_missing : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val stale_event : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val host_effect_failure : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val ocaml_exception : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val dart_renderer_exception : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val lifecycle_exception : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val native_library_loading_error : Bonsai_flutter_spec.Id.Protocol.runtime_error
  val debug_name : Bonsai_flutter_spec.Id.Protocol.runtime_error -> string option
end

module Common_prop : sig
  val test_id : Bonsai_flutter_spec.Id.Protocol.property
  val semantics : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Text_prop : sig
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val text_style : Bonsai_flutter_spec.Id.Protocol.property
  val text_align : Bonsai_flutter_spec.Id.Protocol.property
  val max_lines : Bonsai_flutter_spec.Id.Protocol.property
  val overflow : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Rich_text_prop : sig
  val spans : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Icon_prop : sig
  val code_point : Bonsai_flutter_spec.Id.Protocol.property
  val font_family : Bonsai_flutter_spec.Id.Protocol.property
  val size : Bonsai_flutter_spec.Id.Protocol.property
  val color : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Image_prop : sig
  val uri : Bonsai_flutter_spec.Id.Protocol.property
  val fit : Bonsai_flutter_spec.Id.Protocol.property
  val width : Bonsai_flutter_spec.Id.Protocol.property
  val height : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Row_prop : sig
  val main_axis_alignment : Bonsai_flutter_spec.Id.Protocol.property
  val main_axis_size : Bonsai_flutter_spec.Id.Protocol.property
  val cross_axis_alignment : Bonsai_flutter_spec.Id.Protocol.property
  val text_direction : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Column_prop : sig
  val main_axis_alignment : Bonsai_flutter_spec.Id.Protocol.property
  val main_axis_size : Bonsai_flutter_spec.Id.Protocol.property
  val cross_axis_alignment : Bonsai_flutter_spec.Id.Protocol.property
  val text_direction : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Padding_prop : sig
  val insets : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Align_prop : sig
  val alignment : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Center_prop : sig
  val width_factor : Bonsai_flutter_spec.Id.Protocol.property
  val height_factor : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Sized_box_prop : sig
  val width : Bonsai_flutter_spec.Id.Protocol.property
  val height : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Constrained_box_prop : sig
  val min_width : Bonsai_flutter_spec.Id.Protocol.property
  val max_width : Bonsai_flutter_spec.Id.Protocol.property
  val min_height : Bonsai_flutter_spec.Id.Protocol.property
  val max_height : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Decorated_box_prop : sig
  val background : Bonsai_flutter_spec.Id.Protocol.property
  val border_radius : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Clip_prop : sig
  val behavior : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Opacity_prop : sig
  val opacity : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Animated_opacity_prop : sig
  val opacity : Bonsai_flutter_spec.Id.Protocol.property
  val animation_id : Bonsai_flutter_spec.Id.Protocol.property
  val duration_ms : Bonsai_flutter_spec.Id.Protocol.property
  val curve : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Transform_prop : sig
  val matrix4 : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Scroll_view_prop : sig
  val axis : Bonsai_flutter_spec.Id.Protocol.property
  val reverse : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module List_view_prop : sig
  val axis : Bonsai_flutter_spec.Id.Protocol.property
  val reverse : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Focus_scope_prop : sig
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Mouse_region_prop : sig
  val opaque : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Keyboard_listener_prop : sig
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val key_policy : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Button_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Semantics_prop : sig
  val label : Bonsai_flutter_spec.Id.Protocol.property
  val hint : Bonsai_flutter_spec.Id.Protocol.property
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val role : Bonsai_flutter_spec.Id.Protocol.property
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val selected : Bonsai_flutter_spec.Id.Protocol.property
  val checked : Bonsai_flutter_spec.Id.Protocol.property
  val focusable : Bonsai_flutter_spec.Id.Protocol.property
  val obscured : Bonsai_flutter_spec.Id.Protocol.property
  val live_region : Bonsai_flutter_spec.Id.Protocol.property
  val heading_level : Bonsai_flutter_spec.Id.Protocol.property
  val sort_key : Bonsai_flutter_spec.Id.Protocol.property
  val actions : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Theme_prop : sig
  val brightness : Bonsai_flutter_spec.Id.Protocol.property
  val color_seed : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_scaffold_prop : sig
  val has_app_bar : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_app_bar_prop : sig
  val center_title : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_elevated_button_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_text_button_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_icon_button_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_checkbox_prop : sig
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_switch_prop : sig
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_list_tile_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val selected : Bonsai_flutter_spec.Id.Protocol.property
  val has_subtitle : Bonsai_flutter_spec.Id.Protocol.property
  val has_leading : Bonsai_flutter_spec.Id.Protocol.property
  val has_trailing : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_divider_prop : sig
  val thickness : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_card_prop : sig
  val elevation : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_circular_progress_indicator_prop : sig
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Cupertino_button_prop : sig
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Cupertino_switch_prop : sig
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Text_input_prop : sig
  val session_id : Bonsai_flutter_spec.Id.Protocol.property
  val document_revision : Bonsai_flutter_spec.Id.Protocol.property
  val value : Bonsai_flutter_spec.Id.Protocol.property
  val enabled : Bonsai_flutter_spec.Id.Protocol.property
  val read_only : Bonsai_flutter_spec.Id.Protocol.property
  val obscure_text : Bonsai_flutter_spec.Id.Protocol.property
  val keyboard_type : Bonsai_flutter_spec.Id.Protocol.property
  val input_action : Bonsai_flutter_spec.Id.Protocol.property
  val accepted_local_revision : Bonsai_flutter_spec.Id.Protocol.property
  val update_mode : Bonsai_flutter_spec.Id.Protocol.property
  val autofocus : Bonsai_flutter_spec.Id.Protocol.property
  val max_utf8_bytes : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Overlay_prop : sig
  val alignment : Bonsai_flutter_spec.Id.Protocol.property
  val dismissible : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Navigator_prop : sig
  val restoration_scope_id : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Page_prop : sig
  val page_key : Bonsai_flutter_spec.Id.Protocol.property
  val transition : Bonsai_flutter_spec.Id.Protocol.property
  val can_pop : Bonsai_flutter_spec.Id.Protocol.property
  val restoration_id : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Safe_area_prop : sig
  val left : Bonsai_flutter_spec.Id.Protocol.property
  val top : Bonsai_flutter_spec.Id.Protocol.property
  val right : Bonsai_flutter_spec.Id.Protocol.property
  val bottom : Bonsai_flutter_spec.Id.Protocol.property
  val minimum : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Material_dialog_prop : sig
  val barrier_dismissible : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Pressable_prop : sig
  val overlay_color : Bonsai_flutter_spec.Id.Protocol.property
  val release_delay_ms : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end

module Native_widget_prop : sig
  val kind_id : Bonsai_flutter_spec.Id.Protocol.property
  val version : Bonsai_flutter_spec.Id.Protocol.property
  val capabilities : Bonsai_flutter_spec.Id.Protocol.property
  val payload : Bonsai_flutter_spec.Id.Protocol.property
  val debug_name : Bonsai_flutter_spec.Id.Protocol.property -> string option
end
