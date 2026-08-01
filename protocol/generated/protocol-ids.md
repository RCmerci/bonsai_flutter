<!-- Generated from protocol/schema.sexp. Do not edit. -->

# Protocol IDs

Protocol version: `1.14`

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
| `list_view` | 31 |
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
| `material_dialog` | 107 |
| `material_circular_progress_indicator` | 108 |
| `cupertino_button` | 112 |
| `cupertino_switch` | 113 |
| `native_widget` | 128 |

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

## List view properties

| Name | ID | Encoding |
|---|---:|---|
| `axis` | 1 | `axis` |
| `reverse` | 2 | `bool` |

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
| `brightness` | 1 | `brightness` |
| `color_seed` | 2 | `argb32` |

## Material scaffold properties

| Name | ID | Encoding |
|---|---:|---|
| `has_app_bar` | 1 | `bool` |

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

## Material card properties

| Name | ID | Encoding |
|---|---:|---|
| `elevation` | 1 | `f64` |

## Material circular progress indicator properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `optional_f64` |

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

## Safe area properties

| Name | ID | Encoding |
|---|---:|---|
| `left` | 1 | `bool` |
| `top` | 2 | `bool` |
| `right` | 3 | `bool` |
| `bottom` | 4 | `bool` |
| `minimum` | 5 | `edge_insets` |

## Material dialog properties

| Name | ID | Encoding |
|---|---:|---|
| `barrier_dismissible` | 1 | `bool` |

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

