(** Generated from [protocol/schema.sexp]. Do not edit. *)

val protocol_major : int
val protocol_minor : int

module Limits : sig
  val header_bytes : int
  val max_frame_bytes : int
  val max_string_bytes : int
  val max_operations : int
  val max_nodes : int
end

module Frame_kind : sig
  val handshake : int
  val full_snapshot : int
  val incremental_frame : int
  val event_batch : int
  val runtime_error : int
  val debug_name : int -> string option
end

module Operation : sig
  val begin_frame : int
  val create_node : int
  val update_props : int
  val update_event_bindings : int
  val set_children : int
  val set_root : int
  val drop_node : int
  val host_request : int
  val runtime_notification : int
  val end_frame : int
  val debug_name : int -> string option
end

module Node_kind : sig
  val empty : int
  val text : int
  val rich_text : int
  val icon : int
  val image : int
  val row : int
  val column : int
  val flex : int
  val stack : int
  val positioned : int
  val padding : int
  val align : int
  val center : int
  val sized_box : int
  val constrained_box : int
  val decorated_box : int
  val clip : int
  val opacity : int
  val transform : int
  val scroll_view : int
  val list_view : int
  val gesture : int
  val button : int
  val text_input : int
  val focus_scope : int
  val mouse_region : int
  val keyboard_listener : int
  val semantics : int
  val overlay : int
  val navigator : int
  val page : int
  val safe_area : int
  val theme : int
  val environment_boundary : int
  val animated_opacity : int
  val material_scaffold : int
  val material_app_bar : int
  val material_elevated_button : int
  val material_text_button : int
  val material_icon_button : int
  val material_checkbox : int
  val material_switch : int
  val material_text_field : int
  val material_list_tile : int
  val material_divider : int
  val material_card : int
  val material_dialog : int
  val material_circular_progress_indicator : int
  val cupertino_button : int
  val cupertino_switch : int
  val native_widget : int
  val debug_name : int -> string option
end

module Event_tag : sig
  val press : int
  val long_press : int
  val tap : int
  val double_tap : int
  val pointer_enter : int
  val pointer_leave : int
  val pointer_down : int
  val pointer_up : int
  val key : int
  val focus_changed : int
  val text_edit : int
  val text_submit : int
  val scroll_notification : int
  val visible_range_changed : int
  val animation_completed : int
  val route_pop : int
  val layout_observed : int
  val value_changed : int
  val host_response : int
  val environment_changed : int
  val native_event : int
  val semantics_action : int
  val resync_requested : int
  val debug_name : int -> string option
end

module Host_request : sig
  val clipboard_read : int
  val clipboard_write : int
  val open_url : int
  val pick_file : int
  val save_file : int
  val request_focus : int
  val clear_focus : int
  val scroll_to : int
  val set_window_title : int
  val set_window_size : int
  val show_native_menu : int
  val haptic_feedback : int
  val platform_information : int
  val measure_layout : int
  val debug_name : int -> string option
end

module Runtime_error : sig
  val protocol_error : int
  val revision_mismatch : int
  val duplicate_key : int
  val unsupported_node_kind : int
  val invalid_prop : int
  val handler_missing : int
  val stale_event : int
  val host_effect_failure : int
  val ocaml_exception : int
  val dart_renderer_exception : int
  val lifecycle_exception : int
  val native_library_loading_error : int
  val debug_name : int -> string option
end

module Common_prop : sig
  val test_id : int
  val semantics : int
  val debug_name : int -> string option
end

module Text_prop : sig
  val value : int
  val text_style : int
  val text_align : int
  val max_lines : int
  val overflow : int
  val debug_name : int -> string option
end

module Rich_text_prop : sig
  val spans : int
  val debug_name : int -> string option
end

module Icon_prop : sig
  val code_point : int
  val font_family : int
  val size : int
  val color : int
  val debug_name : int -> string option
end

module Image_prop : sig
  val uri : int
  val fit : int
  val width : int
  val height : int
  val debug_name : int -> string option
end

module Row_prop : sig
  val main_axis_alignment : int
  val main_axis_size : int
  val cross_axis_alignment : int
  val text_direction : int
  val debug_name : int -> string option
end

module Column_prop : sig
  val main_axis_alignment : int
  val main_axis_size : int
  val cross_axis_alignment : int
  val text_direction : int
  val debug_name : int -> string option
end

module Padding_prop : sig
  val insets : int
  val debug_name : int -> string option
end

module Align_prop : sig
  val alignment : int
  val debug_name : int -> string option
end

module Center_prop : sig
  val width_factor : int
  val height_factor : int
  val debug_name : int -> string option
end

module Sized_box_prop : sig
  val width : int
  val height : int
  val debug_name : int -> string option
end

module Constrained_box_prop : sig
  val min_width : int
  val max_width : int
  val min_height : int
  val max_height : int
  val debug_name : int -> string option
end

module Decorated_box_prop : sig
  val background : int
  val border_radius : int
  val debug_name : int -> string option
end

module Clip_prop : sig
  val behavior : int
  val debug_name : int -> string option
end

module Opacity_prop : sig
  val opacity : int
  val debug_name : int -> string option
end

module Animated_opacity_prop : sig
  val opacity : int
  val animation_id : int
  val duration_ms : int
  val curve : int
  val debug_name : int -> string option
end

module Transform_prop : sig
  val matrix4 : int
  val debug_name : int -> string option
end

module Scroll_view_prop : sig
  val axis : int
  val reverse : int
  val debug_name : int -> string option
end

module List_view_prop : sig
  val axis : int
  val reverse : int
  val debug_name : int -> string option
end

module Focus_scope_prop : sig
  val autofocus : int
  val debug_name : int -> string option
end

module Mouse_region_prop : sig
  val opaque : int
  val debug_name : int -> string option
end

module Keyboard_listener_prop : sig
  val autofocus : int
  val key_policy : int
  val debug_name : int -> string option
end

module Button_prop : sig
  val enabled : int
  val debug_name : int -> string option
end

module Semantics_prop : sig
  val label : int
  val hint : int
  val value : int
  val role : int
  val enabled : int
  val selected : int
  val checked : int
  val focusable : int
  val obscured : int
  val live_region : int
  val heading_level : int
  val sort_key : int
  val actions : int
  val debug_name : int -> string option
end

module Theme_prop : sig
  val brightness : int
  val color_seed : int
  val debug_name : int -> string option
end

module Material_scaffold_prop : sig
  val has_app_bar : int
  val debug_name : int -> string option
end

module Material_app_bar_prop : sig
  val center_title : int
  val debug_name : int -> string option
end

module Material_elevated_button_prop : sig
  val enabled : int
  val autofocus : int
  val debug_name : int -> string option
end

module Material_text_button_prop : sig
  val enabled : int
  val autofocus : int
  val debug_name : int -> string option
end

module Material_icon_button_prop : sig
  val enabled : int
  val autofocus : int
  val debug_name : int -> string option
end

module Material_checkbox_prop : sig
  val value : int
  val enabled : int
  val debug_name : int -> string option
end

module Material_switch_prop : sig
  val value : int
  val enabled : int
  val debug_name : int -> string option
end

module Material_list_tile_prop : sig
  val enabled : int
  val selected : int
  val has_subtitle : int
  val has_leading : int
  val has_trailing : int
  val debug_name : int -> string option
end

module Material_divider_prop : sig
  val thickness : int
  val debug_name : int -> string option
end

module Material_card_prop : sig
  val elevation : int
  val debug_name : int -> string option
end

module Material_circular_progress_indicator_prop : sig
  val value : int
  val debug_name : int -> string option
end

module Cupertino_button_prop : sig
  val enabled : int
  val debug_name : int -> string option
end

module Cupertino_switch_prop : sig
  val value : int
  val enabled : int
  val debug_name : int -> string option
end

module Text_input_prop : sig
  val session_id : int
  val document_revision : int
  val value : int
  val enabled : int
  val read_only : int
  val obscure_text : int
  val keyboard_type : int
  val input_action : int
  val accepted_local_revision : int
  val update_mode : int
  val autofocus : int
  val debug_name : int -> string option
end

module Overlay_prop : sig
  val alignment : int
  val dismissible : int
  val debug_name : int -> string option
end

module Navigator_prop : sig
  val restoration_scope_id : int
  val debug_name : int -> string option
end

module Page_prop : sig
  val page_key : int
  val transition : int
  val can_pop : int
  val restoration_id : int
  val debug_name : int -> string option
end

module Safe_area_prop : sig
  val left : int
  val top : int
  val right : int
  val bottom : int
  val minimum : int
  val debug_name : int -> string option
end

module Material_dialog_prop : sig
  val barrier_dismissible : int
  val debug_name : int -> string option
end

module Native_widget_prop : sig
  val kind_id : int
  val version : int
  val capabilities : int
  val payload : int
  val debug_name : int -> string option
end
