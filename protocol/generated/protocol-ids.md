<!-- Generated from protocol/schema.sexp. Do not edit. -->

# Protocol IDs

Protocol version: `1.24`

## Frame kind

| Name | ID |
|---|---:|
| `handshake` | 1 |
| `full_snapshot` | 2 |
| `incremental_frame` | 3 |
| `event_batch` | 4 |
| `runtime_error` | 5 |

## Operation

| Name | ID |
|---|---:|
| `begin_frame` | 1 |
| `create_node` | 2 |
| `update_props` | 3 |
| `update_event_bindings` | 4 |
| `set_children` | 5 |
| `set_root` | 6 |
| `drop_node` | 7 |
| `host_request` | 8 |
| `runtime_notification` | 9 |
| `end_frame` | 10 |
| `application_request` | 11 |
| `set_application_theme` | 12 |

## Node kind

| Name | ID |
|---|---:|
| `empty` | 1 |
| `text` | 2 |
| `rich_text` | 3 |
| `icon` | 4 |
| `image` | 5 |
| `row` | 16 |
| `column` | 17 |
| `flex` | 18 |
| `stack` | 19 |
| `positioned` | 20 |
| `padding` | 21 |
| `align` | 22 |
| `center` | 23 |
| `sized_box` | 24 |
| `constrained_box` | 25 |
| `decorated_box` | 26 |
| `clip` | 27 |
| `opacity` | 28 |
| `transform` | 29 |
| `scroll_view` | 30 |
| `sliver_box` | 32 |
| `sliver_list` | 33 |
| `sliver_fill` | 34 |
| `sliver_fixed_extent` | 35 |
| `sliver_varied_extent` | 36 |
| `sliver_padding` | 37 |
| `sliver_app_bar` | 38 |
| `preferred_size` | 39 |
| `gesture` | 48 |
| `button` | 49 |
| `text_input` | 50 |
| `focus_scope` | 51 |
| `mouse_region` | 52 |
| `keyboard_listener` | 53 |
| `pressable` | 54 |
| `semantics` | 64 |
| `overlay` | 65 |
| `navigator` | 66 |
| `page` | 67 |
| `safe_area` | 68 |
| `theme` | 69 |
| `environment_boundary` | 70 |
| `animated_opacity` | 71 |
| `material_scaffold` | 96 |
| `material_app_bar` | 97 |
| `material_elevated_button` | 98 |
| `material_text_button` | 99 |
| `material_icon_button` | 100 |
| `material_checkbox` | 101 |
| `material_switch` | 102 |
| `material_text_field` | 103 |
| `material_list_tile` | 104 |
| `material_divider` | 105 |
| `material_card` | 106 |
| `reserved_node_kind_107` | 107 |
| `material_circular_progress_indicator` | 108 |
| `material_filled_button` | 109 |
| `material_filled_tonal_button` | 110 |
| `material_outlined_button` | 111 |
| `cupertino_button` | 112 |
| `cupertino_switch` | 113 |
| `material_floating_action_button` | 114 |
| `material_navigation_bar` | 115 |
| `material_radio_group` | 116 |
| `material_slider` | 117 |
| `material_range_slider` | 118 |
| `material_action_chip` | 119 |
| `material_filter_chip` | 120 |
| `material_choice_chip` | 121 |
| `material_input_chip` | 122 |
| `material_alert_dialog` | 123 |
| `material_linear_progress_indicator` | 124 |
| `material_segmented_button` | 125 |
| `native_widget` | 128 |
| `material_search_bar` | 129 |
| `material_tooltip` | 130 |
| `material_data_table` | 131 |
| `material_stepper` | 132 |
| `material_expansion_panel_list` | 133 |
| `material_simple_dialog` | 134 |
| `material_fullscreen_dialog` | 135 |

## Event tag

| Name | ID |
|---|---:|
| `press` | 1 |
| `long_press` | 2 |
| `tap` | 3 |
| `double_tap` | 4 |
| `pointer_enter` | 5 |
| `pointer_leave` | 6 |
| `pointer_down` | 7 |
| `pointer_up` | 8 |
| `key` | 9 |
| `focus_changed` | 10 |
| `text_edit` | 11 |
| `text_submit` | 12 |
| `scroll_notification` | 13 |
| `visible_range_changed` | 14 |
| `animation_completed` | 15 |
| `route_pop` | 16 |
| `layout_observed` | 17 |
| `value_changed` | 18 |
| `host_response` | 19 |
| `environment_changed` | 20 |
| `native_event` | 21 |
| `semantics_action` | 22 |
| `resync_requested` | 23 |
| `text_limit_reached` | 24 |
| `application_response` | 25 |
| `application_request_error` | 26 |
| `application_event` | 27 |
| `navigation_destination_selected` | 28 |
| `radio_selected` | 29 |
| `slider_changed` | 30 |
| `slider_change_end` | 31 |
| `range_slider_changed` | 32 |
| `range_slider_change_end` | 33 |
| `delete` | 34 |
| `segmented_selection_changed` | 35 |
| `tooltip_triggered` | 36 |
| `table_sort_requested` | 37 |
| `table_row_selected` | 38 |
| `table_select_all` | 39 |
| `table_cell_activated` | 40 |
| `step_selected` | 41 |
| `step_continue` | 42 |
| `step_cancel` | 43 |
| `expansion_changed` | 44 |
| `dialog_option_selected` | 45 |

## Host request

| Name | ID |
|---|---:|
| `clipboard_read` | 1 |
| `clipboard_write` | 2 |
| `open_url` | 3 |
| `pick_file` | 4 |
| `save_file` | 5 |
| `request_focus` | 6 |
| `clear_focus` | 7 |
| `scroll_to` | 8 |
| `set_window_title` | 9 |
| `set_window_size` | 10 |
| `show_native_menu` | 11 |
| `haptic_feedback` | 12 |
| `platform_information` | 13 |
| `measure_layout` | 14 |
| `show_snack_bar` | 15 |

## Runtime error

| Name | ID |
|---|---:|
| `protocol_error` | 1 |
| `revision_mismatch` | 2 |
| `duplicate_key` | 3 |
| `unsupported_node_kind` | 4 |
| `invalid_prop` | 5 |
| `handler_missing` | 6 |
| `stale_event` | 7 |
| `host_effect_failure` | 8 |
| `ocaml_exception` | 9 |
| `dart_renderer_exception` | 10 |
| `lifecycle_exception` | 11 |
| `native_library_loading_error` | 12 |

## Common properties

| Name | ID | Encoding |
|---|---:|---|
| `test_id` | 1 | `optional_string` |
| `semantics` | 2 | `optional_semantics` |

## Text properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `string` |
| `text_style` | 2 | `optional_text_style` |
| `text_align` | 3 | `text_align` |
| `max_lines` | 4 | `optional_u32` |
| `overflow` | 5 | `text_overflow` |

## Rich text properties

| Name | ID | Encoding |
|---|---:|---|
| `spans` | 1 | `string_list` |

## Icon properties

| Name | ID | Encoding |
|---|---:|---|
| `code_point` | 1 | `u32` |
| `font_family` | 2 | `optional_string` |
| `size` | 3 | `optional_f64` |
| `color` | 4 | `optional_argb32` |

## Image properties

| Name | ID | Encoding |
|---|---:|---|
| `uri` | 1 | `string` |
| `fit` | 2 | `image_fit` |
| `width` | 3 | `optional_f64` |
| `height` | 4 | `optional_f64` |

## Row properties

| Name | ID | Encoding |
|---|---:|---|
| `main_axis_alignment` | 1 | `main_axis_alignment` |
| `main_axis_size` | 2 | `main_axis_size` |
| `cross_axis_alignment` | 3 | `cross_axis_alignment` |
| `text_direction` | 4 | `text_direction` |

## Column properties

| Name | ID | Encoding |
|---|---:|---|
| `main_axis_alignment` | 1 | `main_axis_alignment` |
| `main_axis_size` | 2 | `main_axis_size` |
| `cross_axis_alignment` | 3 | `cross_axis_alignment` |
| `text_direction` | 4 | `text_direction` |

## Padding properties

| Name | ID | Encoding |
|---|---:|---|
| `insets` | 1 | `edge_insets` |

## Align properties

| Name | ID | Encoding |
|---|---:|---|
| `alignment` | 1 | `alignment` |

## Center properties

| Name | ID | Encoding |
|---|---:|---|
| `width_factor` | 1 | `optional_f64` |
| `height_factor` | 2 | `optional_f64` |

## Sized box properties

| Name | ID | Encoding |
|---|---:|---|
| `width` | 1 | `optional_f64` |
| `height` | 2 | `optional_f64` |

## Constrained box properties

| Name | ID | Encoding |
|---|---:|---|
| `min_width` | 1 | `f64` |
| `max_width` | 2 | `f64` |
| `min_height` | 3 | `f64` |
| `max_height` | 4 | `f64` |

## Decorated box properties

| Name | ID | Encoding |
|---|---:|---|
| `background` | 1 | `optional_argb32` |
| `border_radius` | 2 | `f64` |

## Clip properties

| Name | ID | Encoding |
|---|---:|---|
| `behavior` | 1 | `clip_behavior` |

## Opacity properties

| Name | ID | Encoding |
|---|---:|---|
| `opacity` | 1 | `f64` |

## Animated opacity properties

| Name | ID | Encoding |
|---|---:|---|
| `opacity` | 1 | `f64` |
| `animation_id` | 2 | `u64` |
| `duration_ms` | 3 | `u32` |
| `curve` | 4 | `animation_curve` |

## Transform properties

| Name | ID | Encoding |
|---|---:|---|
| `matrix4` | 1 | `matrix4` |

## Scroll view properties

| Name | ID | Encoding |
|---|---:|---|
| `axis` | 1 | `axis` |
| `reverse` | 2 | `bool` |
| `primary` | 3 | `bool` |
| `cache_extent` | 4 | `optional_f64` |

## Sliver fill properties

| Name | ID | Encoding |
|---|---:|---|

## Sliver fixed extent properties

| Name | ID | Encoding |
|---|---:|---|
| `total_count` | 1 | `u64` |
| `first_index` | 2 | `u64` |
| `item_extent` | 3 | `f64` |
| `overscan` | 4 | `u32` |

## Sliver varied extent properties

| Name | ID | Encoding |
|---|---:|---|
| `total_count` | 1 | `u64` |
| `first_index` | 2 | `u64` |
| `default_item_extent` | 3 | `f64` |
| `overscan` | 4 | `u32` |
| `override_count` | 5 | `u32` |
| `overrides` | 6 | `varied_extent_overrides` |
| `transition_enabled` | 7 | `optional_bool` |
| `expand_duration_ms` | 8 | `optional_u32` |
| `collapse_duration_ms` | 9 | `optional_u32` |
| `expand_curve` | 10 | `optional_animation_curve` |
| `collapse_curve` | 11 | `optional_animation_curve` |

## Sliver padding properties

| Name | ID | Encoding |
|---|---:|---|
| `insets` | 1 | `edge_insets` |

## Sliver app bar properties

| Name | ID | Encoding |
|---|---:|---|
| `pinned` | 1 | `bool` |
| `expanded_height` | 2 | `optional_f64` |
| `collapsed_height` | 3 | `optional_f64` |
| `floating` | 4 | `bool` |
| `snap` | 5 | `bool` |
| `stretch` | 6 | `bool` |
| `toolbar_height` | 7 | `f64` |
| `has_leading` | 8 | `bool` |
| `has_flexible_space` | 9 | `bool` |
| `has_bottom` | 10 | `bool` |
| `has_actions` | 11 | `bool` |
| `force_elevated` | 12 | `bool` |
| `automatically_imply_leading` | 13 | `bool` |
| `center_title` | 14 | `optional_bool` |
| `background_color` | 15 | `optional_argb32` |
| `foreground_color` | 16 | `optional_argb32` |
| `elevation` | 17 | `optional_f64` |

## Preferred size properties

| Name | ID | Encoding |
|---|---:|---|
| `height` | 1 | `f64` |

## Focus scope properties

| Name | ID | Encoding |
|---|---:|---|
| `autofocus` | 1 | `bool` |

## Mouse region properties

| Name | ID | Encoding |
|---|---:|---|
| `opaque` | 1 | `bool` |

## Keyboard listener properties

| Name | ID | Encoding |
|---|---:|---|
| `autofocus` | 1 | `bool` |
| `key_policy` | 2 | `key_policy` |

## Button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |

## Semantics properties

| Name | ID | Encoding |
|---|---:|---|
| `label` | 1 | `optional_string` |
| `hint` | 2 | `optional_string` |
| `value` | 3 | `optional_string` |
| `role` | 4 | `semantics_role` |
| `enabled` | 5 | `optional_bool` |
| `selected` | 6 | `optional_bool` |
| `checked` | 7 | `optional_bool` |
| `focusable` | 8 | `optional_bool` |
| `obscured` | 9 | `bool` |
| `live_region` | 10 | `bool` |
| `heading_level` | 11 | `optional_u8` |
| `sort_key` | 12 | `optional_f64` |
| `actions` | 13 | `u32` |

## Theme properties

| Name | ID | Encoding |
|---|---:|---|
| `data` | 1 | `theme_data` |

## Material scaffold properties

| Name | ID | Encoding |
|---|---:|---|
| `has_app_bar` | 1 | `bool` |
| `has_floating_action_button` | 2 | `bool` |
| `floating_action_button_location` | 3 | `material_floating_action_button_location` |
| `has_bottom_navigation_bar` | 4 | `bool` |
| `has_bottom_sheet` | 5 | `bool` |

## Material app bar properties

| Name | ID | Encoding |
|---|---:|---|
| `center_title` | 1 | `bool` |

## Material elevated button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material text button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material icon button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material filled button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material filled tonal button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material outlined button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `autofocus` | 2 | `bool` |

## Material floating action button properties

| Name | ID | Encoding |
|---|---:|---|
| `variant` | 1 | `material_floating_action_button_variant` |
| `enabled` | 2 | `bool` |
| `autofocus` | 3 | `bool` |
| `has_icon` | 4 | `bool` |

## Material navigation bar properties

| Name | ID | Encoding |
|---|---:|---|
| `selected_index` | 1 | `u32` |
| `destinations` | 2 | `material_navigation_destinations` |

## Material radio group properties

| Name | ID | Encoding |
|---|---:|---|
| `selected_id` | 1 | `optional_i64` |
| `options` | 2 | `material_radio_options` |

## Material slider properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `f64` |
| `min` | 2 | `f64` |
| `max` | 3 | `f64` |
| `divisions` | 4 | `optional_u32` |
| `label` | 5 | `optional_string` |
| `enabled` | 6 | `bool` |
| `has_on_change` | 7 | `bool` |

## Material range slider properties

| Name | ID | Encoding |
|---|---:|---|
| `start` | 1 | `f64` |
| `end_value` | 2 | `f64` |
| `min` | 3 | `f64` |
| `max` | 4 | `f64` |
| `divisions` | 5 | `optional_u32` |
| `label_start` | 6 | `optional_string` |
| `label_end` | 7 | `optional_string` |
| `enabled` | 8 | `bool` |
| `has_on_change` | 9 | `bool` |

## Material action chip properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `selected` | 2 | `bool` |
| `has_avatar` | 3 | `bool` |
| `has_delete_icon` | 4 | `bool` |
| `has_on_press` | 5 | `bool` |
| `has_on_selected` | 6 | `bool` |
| `has_on_delete` | 7 | `bool` |
| `presentation` | 8 | `material_chip_presentation` |

## Material filter chip properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `selected` | 2 | `bool` |
| `has_avatar` | 3 | `bool` |
| `has_delete_icon` | 4 | `bool` |
| `has_on_press` | 5 | `bool` |
| `has_on_selected` | 6 | `bool` |
| `has_on_delete` | 7 | `bool` |
| `presentation` | 8 | `material_chip_presentation` |

## Material choice chip properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `selected` | 2 | `bool` |
| `has_avatar` | 3 | `bool` |
| `has_delete_icon` | 4 | `bool` |
| `has_on_press` | 5 | `bool` |
| `has_on_selected` | 6 | `bool` |
| `has_on_delete` | 7 | `bool` |
| `presentation` | 8 | `material_chip_presentation` |

## Material input chip properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `selected` | 2 | `bool` |
| `has_avatar` | 3 | `bool` |
| `has_delete_icon` | 4 | `bool` |
| `has_on_press` | 5 | `bool` |
| `has_on_selected` | 6 | `bool` |
| `has_on_delete` | 7 | `bool` |
| `presentation` | 8 | `material_chip_presentation` |

## Material alert dialog properties

| Name | ID | Encoding |
|---|---:|---|
| `has_icon` | 1 | `bool` |
| `has_title` | 2 | `bool` |
| `has_content` | 3 | `bool` |
| `action_count` | 4 | `u32` |

## Material checkbox properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `bool` |
| `enabled` | 2 | `bool` |

## Material switch properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `bool` |
| `enabled` | 2 | `bool` |

## Material list tile properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `selected` | 2 | `bool` |
| `has_subtitle` | 3 | `bool` |
| `has_leading` | 4 | `bool` |
| `has_trailing` | 5 | `bool` |

## Material divider properties

| Name | ID | Encoding |
|---|---:|---|
| `thickness` | 1 | `f64` |
| `orientation` | 2 | `axis` |
| `spacing` | 3 | `f64` |
| `indent` | 4 | `f64` |
| `end_indent` | 5 | `f64` |

## Material card properties

| Name | ID | Encoding |
|---|---:|---|
| `elevation` | 1 | `f64` |
| `variant` | 2 | `material_card_variant` |

## Material circular progress indicator properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `optional_f64` |

## Material linear progress indicator properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `optional_f64` |

## Material segmented button properties

| Name | ID | Encoding |
|---|---:|---|
| `selected_ids` | 1 | `i64_list` |
| `enabled` | 2 | `bool` |
| `direction` | 3 | `axis` |
| `multi_selection_enabled` | 4 | `bool` |
| `empty_selection_allowed` | 5 | `bool` |
| `expanded_insets` | 6 | `optional_edge_insets` |
| `show_selected_icon` | 7 | `bool` |
| `has_selected_icon` | 8 | `bool` |
| `segments` | 9 | `material_segments` |

## Material search bar properties

| Name | ID | Encoding |
|---|---:|---|
| `session_id` | 1 | `u64` |
| `document_revision` | 2 | `u64` |
| `value` | 3 | `text_editing_value` |
| `enabled` | 4 | `bool` |
| `read_only` | 5 | `bool` |
| `keyboard_type` | 6 | `keyboard_type` |
| `input_action` | 7 | `input_action` |
| `accepted_local_revision` | 8 | `u64` |
| `update_mode` | 9 | `text_update_mode` |
| `autofocus` | 10 | `bool` |
| `max_utf8_bytes` | 11 | `optional_u32` |
| `has_leading` | 12 | `bool` |
| `trailing_count` | 13 | `u32` |
| `hint_text` | 14 | `optional_string` |
| `has_on_tap` | 15 | `bool` |

## Material tooltip properties

| Name | ID | Encoding |
|---|---:|---|
| `message` | 1 | `string` |
| `enabled` | 2 | `bool` |
| `exclude_from_semantics` | 3 | `bool` |
| `prefer_below` | 4 | `bool` |
| `trigger_mode` | 5 | `material_tooltip_trigger_mode` |
| `wait_duration_ms` | 6 | `u32` |
| `show_duration_ms` | 7 | `u32` |
| `exit_duration_ms` | 8 | `u32` |
| `enable_tap_to_dismiss` | 9 | `bool` |
| `enable_feedback` | 10 | `bool` |
| `has_on_triggered` | 11 | `bool` |

## Material data table properties

| Name | ID | Encoding |
|---|---:|---|
| `columns` | 1 | `material_data_table_columns` |
| `rows` | 2 | `material_data_table_rows` |
| `sort_column_id` | 3 | `optional_i64` |
| `sort_ascending` | 4 | `bool` |
| `selected_row_ids` | 5 | `i64_list` |
| `has_on_sort` | 6 | `bool` |
| `has_on_row_selected` | 7 | `bool` |
| `has_on_select_all` | 8 | `bool` |
| `has_on_cell_activate` | 9 | `bool` |

## Material stepper properties

| Name | ID | Encoding |
|---|---:|---|
| `orientation` | 1 | `axis` |
| `current_step_id` | 2 | `i64` |
| `steps` | 3 | `material_steps` |

## Material expansion panel list properties

| Name | ID | Encoding |
|---|---:|---|
| `policy` | 1 | `material_expansion_panel_policy` |
| `expanded_ids` | 2 | `i64_list` |
| `panels` | 3 | `material_expansion_panels` |

## Material simple dialog properties

| Name | ID | Encoding |
|---|---:|---|
| `has_title` | 1 | `bool` |
| `options` | 2 | `material_simple_dialog_options` |

## Material fullscreen dialog properties

| Name | ID | Encoding |
|---|---:|---|

## Cupertino button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |

## Cupertino switch properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `bool` |
| `enabled` | 2 | `bool` |

## Text input properties

| Name | ID | Encoding |
|---|---:|---|
| `session_id` | 1 | `u64` |
| `document_revision` | 2 | `u64` |
| `value` | 3 | `text_editing_value` |
| `enabled` | 4 | `bool` |
| `read_only` | 5 | `bool` |
| `obscure_text` | 6 | `bool` |
| `keyboard_type` | 7 | `keyboard_type` |
| `input_action` | 8 | `input_action` |
| `accepted_local_revision` | 9 | `u64` |
| `update_mode` | 10 | `text_update_mode` |
| `autofocus` | 11 | `bool` |
| `max_utf8_bytes` | 12 | `optional_u32` |

## Overlay properties

| Name | ID | Encoding |
|---|---:|---|
| `alignment` | 1 | `overlay_alignment` |
| `dismissible` | 2 | `bool` |

## Navigator properties

| Name | ID | Encoding |
|---|---:|---|
| `restoration_scope_id` | 1 | `optional_string` |

## Page properties

| Name | ID | Encoding |
|---|---:|---|
| `page_key` | 1 | `string` |
| `transition` | 2 | `page_transition` |
| `can_pop` | 3 | `bool` |
| `restoration_id` | 4 | `optional_string` |
| `presentation` | 5 | `page_presentation` |
| `modal_barrier_dismissible` | 6 | `bool` |
| `modal_barrier_color` | 7 | `optional_argb32` |
| `modal_barrier_label` | 8 | `optional_string` |
| `modal_use_safe_area` | 10 | `bool` |
| `modal_request_focus` | 11 | `bool` |
| `modal_transition_duration_ms` | 12 | `u32` |
| `modal_reverse_transition_duration_ms` | 13 | `u32` |
| `modal_sizing` | 14 | `modal_sheet_sizing` |
| `modal_detents` | 15 | `modal_sheet_detents` |
| `modal_initial_detent` | 16 | `modal_sheet_detent` |
| `modal_dismiss_on_drag` | 17 | `bool` |
| `modal_handle_semantics_label` | 18 | `optional_string` |
| `modal_medium_semantics_value` | 19 | `optional_string` |
| `modal_large_semantics_value` | 20 | `optional_string` |
| `dialog_barrier_dismissible` | 21 | `bool` |
| `dialog_barrier_color` | 22 | `optional_argb32` |
| `dialog_barrier_label` | 23 | `optional_string` |
| `dialog_use_safe_area` | 24 | `bool` |
| `dialog_request_focus` | 25 | `bool` |
| `dialog_transition_duration_ms` | 26 | `u32` |
| `dialog_reverse_transition_duration_ms` | 27 | `u32` |

## Safe area properties

| Name | ID | Encoding |
|---|---:|---|
| `left` | 1 | `bool` |
| `top` | 2 | `bool` |
| `right` | 3 | `bool` |
| `bottom` | 4 | `bool` |
| `minimum` | 5 | `edge_insets` |

## Pressable properties

| Name | ID | Encoding |
|---|---:|---|
| `overlay_color` | 1 | `argb32` |
| `release_delay_ms` | 2 | `u16` |

## Native widget properties

| Name | ID | Encoding |
|---|---:|---|
| `kind_id` | 1 | `u32` |
| `version` | 2 | `u16` |
| `capabilities` | 3 | `u64` |
| `payload` | 4 | `bytes` |

