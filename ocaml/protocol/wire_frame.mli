(** Renderer-independent values carried by protocol frames.

    This type deliberately contains no Bonsai closures or application keys. *)

type frame_kind =
  | Full_snapshot
  | Incremental_frame

type node_kind =
  | Empty
  | Text
  | Rich_text
  | Icon
  | Image
  | Row
  | Column
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
  | Sliver_box
  | Sliver_list
  | Sliver_fill
  | Sliver_fixed_extent
  | Sliver_varied_extent
  | Sliver_padding
  | Sliver_app_bar
  | Preferred_size
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
  | Material_filled_button
  | Material_filled_tonal_button
  | Material_outlined_button
  | Material_floating_action_button
  | Material_navigation_bar
  | Material_radio_group
  | Material_slider
  | Material_range_slider
  | Material_action_chip
  | Material_filter_chip
  | Material_choice_chip
  | Material_input_chip
  | Material_alert_dialog
  | Material_search_bar
  | Material_tooltip
  | Material_data_table
  | Material_stepper
  | Material_expansion_panel_list
  | Material_simple_dialog
  | Material_fullscreen_dialog
  | Material_checkbox
  | Material_switch
  | Material_list_tile
  | Material_divider
  | Material_card
  | Material_circular_progress_indicator
  | Material_linear_progress_indicator
  | Material_segmented_button
  | Cupertino_button
  | Cupertino_switch
  | Text_input
  | Overlay
  | Navigator
  | Page
  | Safe_area
  | Environment_boundary
  | Native_widget

type axis =
  | Horizontal
  | Vertical

type alignment =
  | Top_start
  | Top_center
  | Top_end
  | Center_start
  | Center
  | Center_end
  | Bottom_start
  | Bottom_center
  | Bottom_end

type image_fit =
  | Fill
  | Contain
  | Cover
  | Fit_width
  | Fit_height
  | No_fit
  | Scale_down

type clip_behavior =
  | Hard_edge
  | Anti_alias
  | Anti_alias_with_save_layer

type brightness =
  | Light
  | Dark

type text_font_weight =
  | Normal
  | Medium
  | Semi_bold
  | Bold

type text_align =
  | Start
  | Center_text
  | End

type text_overflow =
  | Clip_text
  | Fade
  | Ellipsis
  | Visible

type text_style =
  { font_size : float option
  ; font_weight : text_font_weight option
  ; line_height : float option
  ; color : int32 option
  }

type theme_dynamic_variant =
  | Tonal_spot
  | Fidelity
  | Content
  | Monochrome
  | Neutral
  | Vibrant
  | Expressive

type theme_text_style = text_style

type theme_color_scheme =
  { seed_argb : int32
  ; variant : theme_dynamic_variant
  ; contrast_level : float
  }

type theme_typography =
  { font_family : string option
  ; font_family_fallback : string list
  ; display_large : theme_text_style option
  ; display_medium : theme_text_style option
  ; display_small : theme_text_style option
  ; headline_large : theme_text_style option
  ; headline_medium : theme_text_style option
  ; headline_small : theme_text_style option
  ; title_large : theme_text_style option
  ; title_medium : theme_text_style option
  ; title_small : theme_text_style option
  ; body_large : theme_text_style option
  ; body_medium : theme_text_style option
  ; body_small : theme_text_style option
  ; label_large : theme_text_style option
  ; label_medium : theme_text_style option
  ; label_small : theme_text_style option
  }

type theme_shape =
  { extra_small : float
  ; small : float
  ; medium : float
  ; large : float
  ; extra_large : float
  }

type theme_visual_density =
  | Adaptive
  | Standard
  | Comfortable
  | Compact

type theme_tap_target_size =
  | Padded
  | Shrink_wrap

type theme_data =
  { brightness : brightness
  ; color_scheme : theme_color_scheme
  ; typography : theme_typography
  ; shape : theme_shape
  ; visual_density : theme_visual_density
  ; tap_target_size : theme_tap_target_size
  }

type application_theme_mode =
  | System
  | Light
  | Dark

type application_theme =
  { mode : application_theme_mode
  ; light : theme_data
  ; dark : theme_data
  ; high_contrast_light : theme_data option
  ; high_contrast_dark : theme_data option
  }

type text_props =
  { value : string
  ; style : text_style option
  ; text_align : text_align
  ; max_lines : int option
  ; overflow : text_overflow
  }

type semantics_role =
  | Generic
  | Semantics_button
  | Link
  | Image
  | Header
  | Text_field
  | Checkbox
  | Switch
  | Slider

type text_range =
  { start_utf16 : int
  ; end_utf16 : int
  }

type text_editing_value =
  { text : string
  ; selection : text_range
  ; composing : text_range option
  }

type text_keyboard_type =
  | Keyboard_text
  | Keyboard_multiline
  | Keyboard_number
  | Keyboard_email
  | Keyboard_phone
  | Keyboard_url

type text_input_action =
  | Done
  | Newline
  | Next
  | Previous
  | Search
  | Send
  | Go

type text_update_mode =
  | Ack
  | Correction
  | Force_replace

type page_transition =
  | No_transition
  | Fade
  | Slide

type modal_sheet_detent =
  | Medium_detent
  | Large_detent

type modal_sheet_detents =
  | Medium_only
  | Large_only
  | Medium_and_large

type detented_sheet_sizing =
  { detents : modal_sheet_detents
  ; initial_detent : modal_sheet_detent
  ; dismiss_on_drag : bool
  ; handle_semantics_label : string
  ; medium_semantics_value : string
  ; large_semantics_value : string
  }

type modal_sheet_sizing =
  | Content_bounded_sizing
  | Scroll_controlled_sizing
  | Detented_sizing of detented_sheet_sizing

type modal_bottom_sheet_presentation =
  { barrier_dismissible : bool
  ; barrier_color_argb : int32 option
  ; barrier_label : string option
  ; sizing : modal_sheet_sizing
  ; use_safe_area : bool
  ; request_focus : bool
  ; transition_duration_ms : int
  ; reverse_transition_duration_ms : int
  }

type page_presentation =
  | Standard_page of page_transition
  | Modal_bottom_sheet of modal_bottom_sheet_presentation
  | Modal_dialog of modal_dialog_presentation

and modal_dialog_presentation =
  { barrier_dismissible : bool
  ; barrier_color_argb : int32 option
  ; barrier_label : string option
  ; use_safe_area : bool
  ; request_focus : bool
  ; transition_duration_ms : int
  ; reverse_transition_duration_ms : int
  }

type overlay_alignment =
  | Top_start
  | Top_center
  | Top_end
  | Center_start
  | Center
  | Center_end
  | Bottom_start
  | Bottom_center
  | Bottom_end

type flex_fit =
  | Loose
  | Tight

type position =
  { left : float option
  ; top : float option
  ; right : float option
  ; bottom : float option
  }

type parent_data =
  | No_parent_data
  | Flex_parent_data of
      { flex : int
      ; fit : flex_fit
      }
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
  ; enabled : bool
  ; has_selected_icon : bool
  }

type material_radio_option =
  { option_id : int64
  ; enabled : bool
  ; has_label : bool
  }

type material_segment =
  { segment_id : int64
  ; enabled : bool
  ; tooltip : string option
  ; has_icon : bool
  ; has_label : bool
  }

type material_chip_variant =
  | Action_chip
  | Filter_chip
  | Choice_chip
  | Input_chip

type material_chip_presentation =
  | Flat_chip
  | Elevated_chip

type material_card_variant =
  | Elevated_card
  | Filled_card
  | Outlined_card

type material_tooltip_trigger_mode =
  | Tooltip_long_press
  | Tooltip_tap

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

type key_policy =
  | Handled
  | Ignored

type animation_curve =
  | Linear
  | Ease_in
  | Ease_out
  | Ease_in_out

type animation =
  { id : Bonsai_flutter_spec.Id.Ui.animation_id
  ; duration_ms : int
  ; curve : animation_curve
  }

type sparse_extent_curve =
  | Se_linear
  | Se_ease_in
  | Se_ease_out
  | Se_ease_in_out
  | Se_ease_out_cubic
  | Se_ease_in_out_cubic

type sparse_extent_transition =
  { enabled : bool
  ; expand_duration_ms : int
  ; collapse_duration_ms : int
  ; expand_curve : sparse_extent_curve
  ; collapse_curve : sparse_extent_curve
  }

type sliver_extent_override =
  { index : int
  ; extent : float
  }

type props =
  | Empty_props
  | Text_props of text_props
  | Rich_text_props of { spans : string list }
  | Icon_props of
      { code_point : int
      ; font_family : string option
      ; size : float option
      ; color : int32 option
      }
  | Image_props of
      { uri : string
      ; fit : image_fit
      ; width : float option
      ; height : float option
      }
  | Linear_props
  | Button_props of { enabled : bool }
  | Pressable_props of
      { overlay_color_argb : int32
      ; release_delay_ms : int
      }
  | Padding_props of
      { left : float
      ; top : float
      ; right : float
      ; bottom : float
      }
  | Align_props of { alignment : alignment }
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
  | Clip_props of { behavior : clip_behavior }
  | Opacity_props of { opacity : float }
  | Animated_opacity_props of
      { opacity : float
      ; animation : animation
      }
  | Transform_props of { matrix4 : float array }
  | Scroll_view_props of
      { axis : axis
      ; reverse : bool
      ; primary : bool
      ; cache_extent : float option
      }
  | Sliver_box_props
  | Sliver_list_props
  | Sliver_fill_props
  | Sliver_fixed_extent_props of
      { total_count : int
      ; first_index : int
      ; item_extent : float
      ; overscan : int
      }
  | Sliver_varied_extent_props of
      { total_count : int
      ; first_index : int
      ; default_item_extent : float
      ; overscan : int
      ; extent_overrides : sliver_extent_override list
      ; transition : sparse_extent_transition option
      }
  | Sliver_padding_props of
      { left : float
      ; top : float
      ; right : float
      ; bottom : float
      }
  | Sliver_app_bar_props of
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
  | Preferred_size_props of { height : float }
  | Gesture_props
  | Focus_scope_props of { autofocus : bool }
  | Mouse_region_props of { opaque : bool }
  | Keyboard_listener_props of
      { autofocus : bool
      ; key_policy : key_policy
      }
  | Semantics_props of
      { label : string option
      ; hint : string option
      ; value : string option
      ; role : semantics_role
      ; enabled : bool option
      ; selected : bool option
      ; checked : bool option
      ; focusable : bool option
      ; obscured : bool
      ; live_region : bool
      ; heading_level : int option
      ; sort_key : float option
      ; actions : int
      }
  | Theme_props of theme_data
  | Material_scaffold_props of
      { has_app_bar : bool
      ; has_floating_action_button : bool
      ; floating_action_button_location : material_floating_action_button_location
      ; has_bottom_navigation_bar : bool
      ; has_bottom_sheet : bool
      }
  | Material_app_bar_props of { center_title : bool }
  | Material_button_props of
      { variant : material_button_variant
      ; enabled : bool
      ; autofocus : bool
      }
  | Material_floating_action_button_props of
      { variant : material_floating_action_button_variant
      ; enabled : bool
      ; autofocus : bool
      ; has_icon : bool
      }
  | Material_navigation_bar_props of
      { selected_index : int
      ; destinations : material_navigation_destination list
      }
  | Material_radio_group_props of
      { selected_id : int64 option
      ; options : material_radio_option list
      }
  | Material_slider_props of
      { value : float
      ; min : float
      ; max : float
      ; divisions : int option
      ; label : string option
      ; enabled : bool
      ; has_on_change : bool
      }
  | Material_range_slider_props of
      { start : float
      ; end_ : float
      ; min : float
      ; max : float
      ; divisions : int option
      ; label_start : string option
      ; label_end : string option
      ; enabled : bool
      ; has_on_change : bool
      }
  | Material_chip_props of
      { variant : material_chip_variant
      ; presentation : material_chip_presentation
      ; enabled : bool
      ; selected : bool
      ; has_avatar : bool
      ; has_delete_icon : bool
      ; has_on_press : bool
      ; has_on_selected : bool
      ; has_on_delete : bool
      }
  | Material_alert_dialog_props of
      { has_icon : bool
      ; has_title : bool
      ; has_content : bool
      ; action_count : int
      }
  | Material_search_bar_props of
      { session_id : Bonsai_flutter_spec.Id.Text_input.session_id
      ; document_revision : Bonsai_flutter_spec.Id.Text_input.document_revision
      ; value : text_editing_value
      ; enabled : bool
      ; read_only : bool
      ; keyboard_type : text_keyboard_type
      ; input_action : text_input_action
      ; accepted_local_revision : Bonsai_flutter_spec.Id.Text_input.local_revision
      ; update_mode : text_update_mode
      ; autofocus : bool
      ; max_utf8_bytes : int option
      ; has_leading : bool
      ; trailing_count : int
      ; hint_text : string option
      ; has_on_tap : bool
      }
  | Material_tooltip_props of
      { message : string
      ; enabled : bool
      ; exclude_from_semantics : bool
      ; prefer_below : bool
      ; trigger_mode : material_tooltip_trigger_mode
      ; wait_duration_ms : int
      ; show_duration_ms : int
      ; exit_duration_ms : int
      ; enable_tap_to_dismiss : bool
      ; enable_feedback : bool
      ; has_on_triggered : bool
      }
  | Material_data_table_props of
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
  | Material_stepper_props of
      { orientation : axis
      ; current_step_id : int64
      ; steps : material_step list
      }
  | Material_expansion_panel_list_props of
      { policy : material_expansion_panel_policy
      ; expanded_ids : int64 list
      ; panels : material_expansion_panel list
      }
  | Material_simple_dialog_props of
      { has_title : bool
      ; options : material_simple_dialog_option list
      }
  | Material_fullscreen_dialog_props
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
  | Material_divider_props of
      { orientation : axis
      ; thickness : float
      ; spacing : float
      ; indent : float
      ; end_indent : float
      }
  | Material_card_props of
      { variant : material_card_variant
      ; elevation : float
      }
  | Material_circular_progress_props of { value : float option }
  | Material_linear_progress_props of { value : float option }
  | Material_segmented_button_props of
      { selected_ids : int64 list
      ; enabled : bool
      ; direction : axis
      ; multi_selection_enabled : bool
      ; empty_selection_allowed : bool
      ; expanded_insets : (float * float * float * float) option
      ; show_selected_icon : bool
      ; has_selected_icon : bool
      ; segments : material_segment list
      }
  | Cupertino_button_props of { enabled : bool }
  | Cupertino_switch_props of
      { value : bool
      ; enabled : bool
      }
  | Text_input_props of
      { session_id : Bonsai_flutter_spec.Id.Text_input.session_id
      ; document_revision : Bonsai_flutter_spec.Id.Text_input.document_revision
      ; value : text_editing_value
      ; enabled : bool
      ; read_only : bool
      ; obscure_text : bool
      ; keyboard_type : text_keyboard_type
      ; input_action : text_input_action
      ; accepted_local_revision : Bonsai_flutter_spec.Id.Text_input.local_revision
      ; update_mode : text_update_mode
      ; autofocus : bool
      ; max_utf8_bytes : int option
      }
  | Overlay_props of
      { alignment : overlay_alignment
      ; dismissible : bool
      }
  | Navigator_props of
      { restoration_scope_id :
          Bonsai_flutter_spec.Id.Navigation.restoration_scope_id option
      }
  | Page_props of
      { page_key : Bonsai_flutter_spec.Id.Navigation.page_key
      ; presentation : page_presentation
      ; can_pop : bool
      ; restoration_id : Bonsai_flutter_spec.Id.Navigation.restoration_id option
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
  | Native_widget_props of
      { kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
      ; version : int
      ; capabilities : int64
      ; payload : bytes
      }

type file_picker_options =
  { allowed_extensions : string list
  ; allow_multiple : bool
  }

type save_file_options =
  { suggested_name : string option
  ; data : bytes
  }

type scroll_to =
  { node_id : Bonsai_flutter_spec.Id.Ui.node_id
  ; alignment : float
  ; animated : bool
  }

type size =
  { width : float
  ; height : float
  }

type native_menu_item =
  { item_id : Bonsai_flutter_spec.Id.Host.native_menu_item_id
  ; label : string
  ; enabled : bool
  }

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

type host_request_payload =
  | Clipboard_read
  | Clipboard_write of { text : string }
  | Open_url of { uri : string }
  | Pick_file of file_picker_options
  | Save_file of save_file_options
  | Request_focus of { node_id : Bonsai_flutter_spec.Id.Ui.node_id }
  | Clear_focus
  | Scroll_to of scroll_to
  | Set_window_title of { title : string }
  | Set_window_size of size
  | Show_native_menu of { items : native_menu_item list }
  | Haptic_feedback of haptic_kind
  | Platform_information
  | Measure_layout of { node_id : Bonsai_flutter_spec.Id.Ui.node_id }
  | Show_snack_bar of
      { message : string
      ; action_label : string option
      ; duration_ms : int
      }

type event_binding =
  { event_tag : Bonsai_flutter_spec.Id.Protocol.event_tag
  ; handler_id : Bonsai_flutter_spec.Id.Ui.handler_id
  }

type runtime_stats =
  { event_batch_size : int
  ; bonsai_flush_ns : int64
  ; result_read_ns : int64
  ; reconcile_ns : int64
  ; encode_ns : int64
  ; patch_count : int
  ; patch_bytes : int
  ; lifecycle_ns : int64
  ; full_snapshot_count : int
  ; resync_count : int
  }

type operation =
  | Create_node of
      { node_id : Bonsai_flutter_spec.Id.Ui.node_id
      ; kind : node_kind
      ; props : props
      ; event_bindings : event_binding list
      ; parent_data : parent_data
      }
  | Update_props of
      { node_id : Bonsai_flutter_spec.Id.Ui.node_id
      ; props : props
      }
  | Update_event_bindings of
      { node_id : Bonsai_flutter_spec.Id.Ui.node_id
      ; event_bindings : event_binding list
      }
  | Set_children of
      { node_id : Bonsai_flutter_spec.Id.Ui.node_id
      ; children : Bonsai_flutter_spec.Id.Ui.node_id list
      }
  | Set_root of Bonsai_flutter_spec.Id.Ui.node_id
  | Set_application_theme of
      { title : string option
      ; theme : application_theme
      }
  | Drop_node of Bonsai_flutter_spec.Id.Ui.node_id
  | Host_request of
      { request_id : Bonsai_flutter_spec.Id.Host.request_id
      ; payload : host_request_payload
      }
  | Cancel_host_request of { request_id : Bonsai_flutter_spec.Id.Host.request_id }
  | Application_request of
      { request_id : int64
      ; payload : bytes
      }
  | Runtime_stats of runtime_stats

type t =
  { runtime_epoch : Bonsai_flutter_spec.Id.Runtime.epoch
  ; base_revision : Bonsai_flutter_spec.Id.Runtime.renderer_revision
  ; target_revision : Bonsai_flutter_spec.Id.Runtime.renderer_revision
  ; kind : frame_kind
  ; operations : operation list
  }
