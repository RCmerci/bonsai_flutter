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
  | List_view
  | Gesture
  | Focus_scope
  | Mouse_region
  | Keyboard_listener
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
  | Elevated
  | Text_button
  | Icon_button

type key_policy =
  | Handled
  | Ignored

type animation_curve =
  | Linear
  | Ease_in
  | Ease_out
  | Ease_in_out

type animation =
  { id : int64
  ; duration_ms : int
  ; curve : animation_curve
  }

type props =
  | Empty_props
  | Text_props of { value : string }
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
      }
  | List_view_props of
      { axis : axis
      ; reverse : bool
      }
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
  | Theme_props of
      { brightness : brightness
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
      ; value : text_editing_value
      ; enabled : bool
      ; read_only : bool
      ; obscure_text : bool
      ; keyboard_type : text_keyboard_type
      ; input_action : text_input_action
      ; accepted_local_revision : int64
      ; update_mode : text_update_mode
      ; autofocus : bool
      }
  | Overlay_props of
      { alignment : overlay_alignment
      ; dismissible : bool
      }
  | Navigator_props of { restoration_scope_id : string option }
  | Page_props of
      { page_key : string
      ; transition : page_transition
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

type file_picker_options =
  { allowed_extensions : string list
  ; allow_multiple : bool
  }

type save_file_options =
  { suggested_name : string option
  ; data : bytes
  }

type scroll_to =
  { node_id : int64
  ; alignment : float
  ; animated : bool
  }

type size =
  { width : float
  ; height : float
  }

type native_menu_item =
  { item_id : string
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
  | Request_focus of { node_id : int64 }
  | Clear_focus
  | Scroll_to of scroll_to
  | Set_window_title of { title : string }
  | Set_window_size of size
  | Show_native_menu of { items : native_menu_item list }
  | Haptic_feedback of haptic_kind
  | Platform_information
  | Measure_layout of { node_id : int64 }

type event_binding =
  { event_tag : int
  ; handler_id : int64
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
      { node_id : int64
      ; kind : node_kind
      ; props : props
      ; event_bindings : event_binding list
      ; parent_data : parent_data
      }
  | Update_props of
      { node_id : int64
      ; props : props
      }
  | Update_event_bindings of
      { node_id : int64
      ; event_bindings : event_binding list
      }
  | Set_children of
      { node_id : int64
      ; children : int64 list
      }
  | Set_root of int64
  | Drop_node of int64
  | Host_request of
      { request_id : int64
      ; payload : host_request_payload
      }
  | Cancel_host_request of { request_id : int64 }
  | Runtime_stats of runtime_stats

type t =
  { runtime_epoch : int64
  ; base_revision : int64
  ; target_revision : int64
  ; kind : frame_kind
  ; operations : operation list
  }
