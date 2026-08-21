module ID = Bonsai_flutter_spec.Id

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_flags
  | Invalid_payload_length
  | Frame_too_large
  | Too_many_operations
  | String_too_large
  | Unknown_operation
  | Unknown_node_kind
  | Invalid_props
  | Invalid_utf8
  | Invalid_operation_order
  | Truncated_input
  | Trailing_bytes
  | Application_payload_too_large

type error =
  { code : error_code
  ; message : string
  }

exception Codec_error of error

open Wire_frame

let fail code format =
  Printf.ksprintf (fun message -> raise (Codec_error { code; message })) format
;;

module Writer = struct
  let create () = Buffer.create 128
  let length = Buffer.length
  let u8 buffer value = Buffer.add_char buffer (Char.chr (value land 0xff))

  let u16 buffer value =
    u8 buffer value;
    u8 buffer (value lsr 8)
  ;;

  let u32 buffer value =
    u8 buffer value;
    u8 buffer (value lsr 8);
    u8 buffer (value lsr 16);
    u8 buffer (value lsr 24)
  ;;

  let u64 buffer value =
    for shift = 0 to 7 do
      Int64.(shift_right_logical value (shift * 8) |> to_int) |> u8 buffer
    done
  ;;

  let f64 buffer value = u64 buffer (Int64.bits_of_float value)
  let bytes buffer value = Buffer.add_bytes buffer value
  let string buffer value = Buffer.add_string buffer value
  let contents buffer = Buffer.to_bytes buffer
end

module Runtime_encoded_frame = struct
  type stats_offsets =
    { encode_ns : int
    ; patch_bytes : int
    }

  type t =
    { bytes : bytes
    ; stats_offsets : stats_offsets
    }

  let bytes t = t.bytes
end

let check_u16 label value =
  if value < 0 || value > 0xffff then fail Invalid_props "%s is outside u16" label
;;

let check_u32 label value =
  if value < 0 || Int64.compare (Int64.of_int value) 0xffffffffL > 0
  then fail Invalid_props "%s is outside u32" label
;;

let check_pressable_release_delay value =
  check_u16 "pressable release delay" value;
  if value > 100 then fail Invalid_props "pressable release delay must be in 0..100ms"
;;

let check_u64 label value =
  if Int64.compare value 0L < 0 then fail Invalid_props "%s must be non-negative" label
;;

let write_string writer value =
  let length = String.length value in
  if length > Generated_protocol.Limits.max_string_bytes
  then fail String_too_large "string is %d bytes" length;
  Writer.u32 writer length;
  Writer.string writer value
;;

let write_bool writer value = Writer.u8 writer (if value then 1 else 0)

let write_optional_string writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    write_string writer value
;;

let write_optional_bool writer = function
  | None -> Writer.u8 writer 0
  | Some false -> Writer.u8 writer 1
  | Some true -> Writer.u8 writer 2
;;

let write_optional_f64 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    Writer.f64 writer value
;;

let write_optional_u8 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    check_u16 "optional u8" value;
    if value > 0xff then fail Invalid_props "optional u8 is outside u8";
    Writer.u8 writer 1;
    Writer.u8 writer value
;;

let write_optional_argb32 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    Writer.u32 writer (Int32.to_int value)
;;

let text_font_weight_id = function
  | Wire_frame.Normal -> 0
  | Medium -> 1
  | Semi_bold -> 2
  | Bold -> 3
;;

let text_align_id = function
  | Wire_frame.Start -> 0
  | Center_text -> 1
  | End -> 2
;;

let text_overflow_id = function
  | Wire_frame.Clip_text -> 0
  | Fade -> 1
  | Ellipsis -> 2
  | Visible -> 3
;;

let write_text_style writer = function
  | None -> Writer.u8 writer 0
  | Some (style : Wire_frame.text_style) ->
    Writer.u8 writer 1;
    write_optional_f64 writer style.font_size;
    (match style.font_weight with
     | None -> Writer.u8 writer 0
     | Some weight ->
       Writer.u8 writer 1;
       Writer.u8 writer (text_font_weight_id weight));
    write_optional_f64 writer style.line_height;
    write_optional_argb32 writer style.color
;;

let write_optional_u32 writer label = function
  | None -> Writer.u8 writer 0
  | Some value ->
    check_u32 label value;
    if value = 0 then fail Invalid_props "%s must be positive" label;
    Writer.u8 writer 1;
    Writer.u32 writer value
;;

let write_text_props
      writer
      ({ value; style; text_align; max_lines; overflow } : Wire_frame.text_props)
  =
  write_string writer value;
  write_text_style writer style;
  Writer.u8 writer (text_align_id text_align);
  write_optional_u32 writer "text max lines" max_lines;
  Writer.u8 writer (text_overflow_id overflow)
;;

let alignment_id (alignment : Wire_frame.alignment) =
  match alignment with
  | Wire_frame.Top_start -> 0
  | Top_center -> 1
  | Top_end -> 2
  | Center_start -> 3
  | Center -> 4
  | Center_end -> 5
  | Bottom_start -> 6
  | Bottom_center -> 7
  | Bottom_end -> 8
;;

let image_fit_id = function
  | Wire_frame.Fill -> 0
  | Contain -> 1
  | Cover -> 2
  | Fit_width -> 3
  | Fit_height -> 4
  | No_fit -> 5
  | Scale_down -> 6
;;

let clip_behavior_id = function
  | Wire_frame.Hard_edge -> 0
  | Anti_alias -> 1
  | Anti_alias_with_save_layer -> 2
;;

let animation_curve_id = function
  | Wire_frame.Linear -> 0
  | Ease_in -> 1
  | Ease_out -> 2
  | Ease_in_out -> 3
;;

let write_animation writer { id; duration_ms; curve } =
  let id = ID.Ui.Animation_id.to_int64 id in
  check_u64 "animation id" id;
  check_u32 "animation duration" duration_ms;
  Writer.u64 writer id;
  Writer.u32 writer duration_ms;
  Writer.u8 writer (animation_curve_id curve)
;;

let sparse_extent_curve_id = function
  | Wire_frame.Se_linear -> 0
  | Se_ease_in -> 1
  | Se_ease_out -> 2
  | Se_ease_in_out -> 3
  | Se_ease_out_cubic -> 4
  | Se_ease_in_out_cubic -> 5
;;

let write_optional_sparse_extent_curve writer = function
  | None -> Writer.u8 writer 0
  | Some curve ->
    Writer.u8 writer 1;
    Writer.u8 writer (sparse_extent_curve_id curve)
;;

let write_optional_duration_ms writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    check_u32 "sliver transition duration" value;
    Writer.u8 writer 1;
    Writer.u32 writer value
;;

let validate_sliver_window ~total_count ~first_index =
  if total_count < 0 then fail Invalid_props "sliver total_count must be non-negative";
  if first_index < 0 || first_index > total_count
  then fail Invalid_props "sliver first_index is outside the logical list"
;;

let validate_sliver_extent_overrides ~total_count overrides =
  if List.length overrides > total_count
  then fail Invalid_props "sliver override count is out of range";
  ignore
    (List.fold_left
       (fun previous { Wire_frame.index; extent } ->
          if index < 0 || index >= total_count
          then fail Invalid_props "sliver override index is outside the logical list";
          (match previous with
           | Some previous when index <= previous ->
             fail Invalid_props "sliver override indexes must be sorted and unique"
           | _ -> ());
          if (not (Float.is_finite extent)) || Float.compare extent 0. <= 0
          then fail Invalid_props "sliver override extent must be finite and positive";
          Some index)
       None
       overrides)
;;

let write_sliver_extent_overrides writer overrides =
  check_u32 "sliver override count" (List.length overrides);
  Writer.u32 writer (List.length overrides);
  List.iter
    (fun { Wire_frame.index; extent } ->
       check_u64 "sliver override index" (Int64.of_int index);
       Writer.u64 writer (Int64.of_int index);
       Writer.f64 writer extent)
    overrides
;;

let write_sliver_fixed_extent_payload
      writer
      ~total_count
      ~first_index
      ~item_extent
      ~overscan
  =
  validate_sliver_window ~total_count ~first_index;
  check_u64 "sliver total_count" (Int64.of_int total_count);
  check_u64 "sliver first_index" (Int64.of_int first_index);
  if (not (Float.is_finite item_extent)) || Float.compare item_extent 0. <= 0
  then fail Invalid_props "sliver item_extent must be finite and positive";
  check_u32 "sliver overscan" overscan;
  Writer.u64 writer (Int64.of_int total_count);
  Writer.u64 writer (Int64.of_int first_index);
  Writer.f64 writer item_extent;
  Writer.u32 writer overscan
;;

let write_sliver_varied_extent_payload
      writer
      ~total_count
      ~first_index
      ~default_item_extent
      ~overscan
      ~extent_overrides
      ~(transition : Wire_frame.sparse_extent_transition option)
  =
  validate_sliver_window ~total_count ~first_index;
  validate_sliver_extent_overrides ~total_count extent_overrides;
  check_u64 "sliver total_count" (Int64.of_int total_count);
  check_u64 "sliver first_index" (Int64.of_int first_index);
  if
    (not (Float.is_finite default_item_extent))
    || Float.compare default_item_extent 0. <= 0
  then fail Invalid_props "sliver default_item_extent must be finite and positive";
  check_u32 "sliver overscan" overscan;
  Writer.u64 writer (Int64.of_int total_count);
  Writer.u64 writer (Int64.of_int first_index);
  Writer.f64 writer default_item_extent;
  Writer.u32 writer overscan;
  write_sliver_extent_overrides writer extent_overrides;
  match transition with
  | None ->
    write_optional_bool writer None;
    write_optional_duration_ms writer None;
    write_optional_duration_ms writer None;
    write_optional_sparse_extent_curve writer None;
    write_optional_sparse_extent_curve writer None
  | Some
      { enabled; expand_duration_ms; collapse_duration_ms; expand_curve; collapse_curve }
    ->
    write_optional_bool writer (Some enabled);
    write_optional_duration_ms writer (Some expand_duration_ms);
    write_optional_duration_ms writer (Some collapse_duration_ms);
    write_optional_sparse_extent_curve writer (Some expand_curve);
    write_optional_sparse_extent_curve writer (Some collapse_curve)
;;

let validate_cache_extent = function
  | Some value when (not (Float.is_finite value)) || Float.compare value 0. < 0 ->
    fail Invalid_props "scroll cache_extent must be finite and non-negative"
  | None | Some _ -> ()
;;

let validate_sliver_app_bar
      ~expanded_height
      ~collapsed_height
      ~floating
      ~snap
      ~toolbar_height
      ~elevation
  =
  let optional_nonnegative label = function
    | Some value when (not (Float.is_finite value)) || Float.compare value 0. < 0 ->
      fail Invalid_props "%s must be non-negative and finite" label
    | None | Some _ -> ()
  in
  if (not (Float.is_finite toolbar_height)) || Float.compare toolbar_height 0. <= 0
  then fail Invalid_props "sliver toolbar_height must be positive and finite";
  optional_nonnegative "expanded_height" expanded_height;
  optional_nonnegative "collapsed_height" collapsed_height;
  optional_nonnegative "elevation" elevation;
  (match expanded_height, collapsed_height with
   | Some expanded, Some collapsed when Float.compare collapsed expanded > 0 ->
     fail Invalid_props "collapsed_height must not exceed expanded_height"
   | _ -> ());
  (match collapsed_height with
   | Some collapsed when Float.compare collapsed toolbar_height < 0 ->
     fail Invalid_props "collapsed_height must be at least toolbar_height"
   | None | Some _ -> ());
  if snap && not floating then fail Invalid_props "sliver snap requires floating"
;;

let semantics_role_id = function
  | Wire_frame.Generic -> 0
  | Semantics_button -> 1
  | Link -> 2
  | Image -> 3
  | Header -> 4
  | Text_field -> 5
  | Checkbox -> 6
  | Switch -> 7
  | Slider -> 8
;;

let text_keyboard_type_id = function
  | Wire_frame.Keyboard_text -> 0
  | Keyboard_multiline -> 1
  | Keyboard_number -> 2
  | Keyboard_email -> 3
  | Keyboard_phone -> 4
  | Keyboard_url -> 5
;;

let text_input_action_id = function
  | Wire_frame.Done -> 0
  | Newline -> 1
  | Next -> 2
  | Previous -> 3
  | Search -> 4
  | Send -> 5
  | Go -> 6
;;

let text_update_mode_id = function
  | Wire_frame.Ack -> 0
  | Correction -> 1
  | Force_replace -> 2
;;

let page_transition_id = function
  | Wire_frame.No_transition -> 0
  | Fade -> 1
  | Slide -> 2
;;

let modal_sheet_detent_id = function
  | Wire_frame.Medium_detent -> 0
  | Large_detent -> 1
;;

let modal_sheet_detents_id = function
  | Wire_frame.Medium_only -> 0
  | Large_only -> 1
  | Medium_and_large -> 2
;;

let detent_is_in_set detent detents =
  match detent, detents with
  | Wire_frame.Medium_detent, (Medium_only | Medium_and_large)
  | Large_detent, (Large_only | Medium_and_large) -> true
  | _ -> false
;;

let require_nonempty_modal_string name value =
  if String.length (String.trim value) = 0
  then fail Invalid_props "modal %s must not be empty" name
;;

let write_page_presentation writer = function
  | Wire_frame.Standard_page _ ->
    Writer.u8 writer 0;
    write_bool writer false;
    write_optional_argb32 writer None;
    write_optional_string writer None;
    Writer.u8 writer 0;
    write_bool writer false;
    write_bool writer false;
    Writer.u32 writer 0;
    Writer.u32 writer 0;
    Writer.u8 writer 0;
    Writer.u8 writer 0;
    write_bool writer false;
    write_optional_string writer None;
    write_optional_string writer None;
    write_optional_string writer None
  | Modal_bottom_sheet
      { barrier_dismissible
      ; barrier_color_argb
      ; barrier_label
      ; sizing
      ; use_safe_area
      ; request_focus
      ; transition_duration_ms
      ; reverse_transition_duration_ms
      } ->
    check_u32 "modal transition duration" transition_duration_ms;
    check_u32 "modal reverse transition duration" reverse_transition_duration_ms;
    Writer.u8 writer 1;
    write_bool writer barrier_dismissible;
    write_optional_argb32 writer barrier_color_argb;
    write_optional_string writer barrier_label;
    let sizing_id, detents, initial_detent, dismiss_on_drag, semantics =
      match sizing with
      | Wire_frame.Content_bounded_sizing -> 0, Medium_only, Medium_detent, false, None
      | Scroll_controlled_sizing -> 1, Medium_only, Medium_detent, false, None
      | Detented_sizing detented ->
        if not (detent_is_in_set detented.initial_detent detented.detents)
        then fail Invalid_props "modal initial detent must belong to detents";
        require_nonempty_modal_string
          "handle semantics label"
          detented.handle_semantics_label;
        require_nonempty_modal_string
          "medium semantics value"
          detented.medium_semantics_value;
        require_nonempty_modal_string
          "large semantics value"
          detented.large_semantics_value;
        ( 2
        , detented.detents
        , detented.initial_detent
        , detented.dismiss_on_drag
        , Some
            ( detented.handle_semantics_label
            , detented.medium_semantics_value
            , detented.large_semantics_value ) )
    in
    Writer.u8 writer sizing_id;
    write_bool writer use_safe_area;
    write_bool writer request_focus;
    Writer.u32 writer transition_duration_ms;
    Writer.u32 writer reverse_transition_duration_ms;
    Writer.u8 writer (modal_sheet_detents_id detents);
    Writer.u8 writer (modal_sheet_detent_id initial_detent);
    write_bool writer dismiss_on_drag;
    let label, medium_value, large_value =
      match semantics with
      | None -> None, None, None
      | Some (label, medium_value, large_value) ->
        Some label, Some medium_value, Some large_value
    in
    write_optional_string writer label;
    write_optional_string writer medium_value;
    write_optional_string writer large_value
;;

let overlay_alignment_id = function
  | Wire_frame.Top_start -> 0
  | Top_center -> 1
  | Top_end -> 2
  | Center_start -> 3
  | Center -> 4
  | Center_end -> 5
  | Bottom_start -> 6
  | Bottom_center -> 7
  | Bottom_end -> 8
;;

let is_utf16_boundary text target =
  if target < 0
  then false
  else (
    let byte_length = String.length text in
    let rec loop byte_offset utf16_offset =
      if utf16_offset = target
      then true
      else if byte_offset = byte_length || utf16_offset > target
      then false
      else (
        let decoded = String.get_utf_8_uchar text byte_offset in
        if not (Uchar.utf_decode_is_valid decoded)
        then fail Invalid_utf8 "text is not valid UTF-8";
        let scalar = Uchar.utf_decode_uchar decoded in
        loop
          (byte_offset + Uchar.utf_decode_length decoded)
          (utf16_offset + if Uchar.to_int scalar > 0xffff then 2 else 1))
    in
    loop 0 0)
;;

let validate_text_range text (range : Wire_frame.text_range) =
  if range.start_utf16 > range.end_utf16 then fail Invalid_props "text range is reversed";
  if
    not
      (is_utf16_boundary text range.start_utf16 && is_utf16_boundary text range.end_utf16)
  then fail Invalid_props "text range is not on a UTF-16 boundary"
;;

let write_text_range writer text (range : Wire_frame.text_range) =
  check_u32 "text range start" range.start_utf16;
  check_u32 "text range end" range.end_utf16;
  validate_text_range text range;
  Writer.u32 writer range.start_utf16;
  Writer.u32 writer range.end_utf16
;;

let write_text_editing_value writer (value : Wire_frame.text_editing_value) =
  write_string writer value.text;
  write_text_range writer value.text value.selection;
  match value.composing with
  | None -> Writer.u8 writer 0
  | Some composing ->
    Writer.u8 writer 1;
    write_text_range writer value.text composing
;;

let node_kind_id = function
  | Wire_frame.Empty -> Generated_protocol.Node_kind.empty
  | Text -> Generated_protocol.Node_kind.text
  | Rich_text -> Generated_protocol.Node_kind.rich_text
  | Icon -> Generated_protocol.Node_kind.icon
  | Image -> Generated_protocol.Node_kind.image
  | Row -> Generated_protocol.Node_kind.row
  | Column -> Generated_protocol.Node_kind.column
  | Stack -> Generated_protocol.Node_kind.stack
  | Button -> Generated_protocol.Node_kind.button
  | Padding -> Generated_protocol.Node_kind.padding
  | Align -> Generated_protocol.Node_kind.align
  | Center -> Generated_protocol.Node_kind.center
  | Sized_box -> Generated_protocol.Node_kind.sized_box
  | Constrained_box -> Generated_protocol.Node_kind.constrained_box
  | Decorated_box -> Generated_protocol.Node_kind.decorated_box
  | Clip -> Generated_protocol.Node_kind.clip
  | Opacity -> Generated_protocol.Node_kind.opacity
  | Animated_opacity -> Generated_protocol.Node_kind.animated_opacity
  | Transform -> Generated_protocol.Node_kind.transform
  | Scroll_view -> Generated_protocol.Node_kind.scroll_view
  | Sliver_box -> Generated_protocol.Node_kind.sliver_box
  | Sliver_list -> Generated_protocol.Node_kind.sliver_list
  | Sliver_fill -> Generated_protocol.Node_kind.sliver_fill
  | Sliver_fixed_extent -> Generated_protocol.Node_kind.sliver_fixed_extent
  | Sliver_varied_extent -> Generated_protocol.Node_kind.sliver_varied_extent
  | Sliver_padding -> Generated_protocol.Node_kind.sliver_padding
  | Sliver_app_bar -> Generated_protocol.Node_kind.sliver_app_bar
  | Preferred_size -> Generated_protocol.Node_kind.preferred_size
  | Gesture -> Generated_protocol.Node_kind.gesture
  | Focus_scope -> Generated_protocol.Node_kind.focus_scope
  | Mouse_region -> Generated_protocol.Node_kind.mouse_region
  | Keyboard_listener -> Generated_protocol.Node_kind.keyboard_listener
  | Pressable -> Generated_protocol.Node_kind.pressable
  | Semantics -> Generated_protocol.Node_kind.semantics
  | Theme -> Generated_protocol.Node_kind.theme
  | Material_scaffold -> Generated_protocol.Node_kind.material_scaffold
  | Material_app_bar -> Generated_protocol.Node_kind.material_app_bar
  | Material_elevated_button -> Generated_protocol.Node_kind.material_elevated_button
  | Material_text_button -> Generated_protocol.Node_kind.material_text_button
  | Material_icon_button -> Generated_protocol.Node_kind.material_icon_button
  | Material_checkbox -> Generated_protocol.Node_kind.material_checkbox
  | Material_switch -> Generated_protocol.Node_kind.material_switch
  | Material_list_tile -> Generated_protocol.Node_kind.material_list_tile
  | Material_divider -> Generated_protocol.Node_kind.material_divider
  | Material_card -> Generated_protocol.Node_kind.material_card
  | Material_circular_progress_indicator ->
    Generated_protocol.Node_kind.material_circular_progress_indicator
  | Cupertino_button -> Generated_protocol.Node_kind.cupertino_button
  | Cupertino_switch -> Generated_protocol.Node_kind.cupertino_switch
  | Text_input -> Generated_protocol.Node_kind.text_input
  | Overlay -> Generated_protocol.Node_kind.overlay
  | Navigator -> Generated_protocol.Node_kind.navigator
  | Page -> Generated_protocol.Node_kind.page
  | Safe_area -> Generated_protocol.Node_kind.safe_area
  | Environment_boundary -> Generated_protocol.Node_kind.environment_boundary
  | Material_dialog -> Generated_protocol.Node_kind.material_dialog
  | Native_widget -> Generated_protocol.Node_kind.native_widget
;;

let write_props writer kind props =
  match kind, props with
  | (Wire_frame.Empty | Stack), Empty_props
  | Environment_boundary, Environment_boundary_props
  | Row, Linear_props
  | Column, Linear_props -> ()
  | Text, Text_props props -> write_text_props writer props
  | Rich_text, Rich_text_props { spans } ->
    check_u16 "rich text span count" (List.length spans);
    Writer.u16 writer (List.length spans);
    List.iter (write_string writer) spans
  | Icon, Icon_props { code_point; font_family; size; color } ->
    check_u32 "icon code point" code_point;
    Writer.u32 writer code_point;
    write_optional_string writer font_family;
    write_optional_f64 writer size;
    write_optional_argb32 writer color
  | Image, Image_props { uri; fit; width; height } ->
    write_string writer uri;
    Writer.u8 writer (image_fit_id fit);
    write_optional_f64 writer width;
    write_optional_f64 writer height
  | Button, Button_props { enabled } -> write_bool writer enabled
  | Pressable, Pressable_props { overlay_color_argb; release_delay_ms } ->
    check_pressable_release_delay release_delay_ms;
    Writer.u32 writer (Int32.to_int overlay_color_argb);
    Writer.u16 writer release_delay_ms
  | Padding, Padding_props { left; top; right; bottom } ->
    Writer.f64 writer left;
    Writer.f64 writer top;
    Writer.f64 writer right;
    Writer.f64 writer bottom
  | Align, Align_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Center, Center_props { width_factor; height_factor } ->
    write_optional_f64 writer width_factor;
    write_optional_f64 writer height_factor
  | Sized_box, Sized_box_props { width; height } ->
    write_optional_f64 writer width;
    write_optional_f64 writer height
  | ( Constrained_box
    , Constrained_box_props { min_width; max_width; min_height; max_height } ) ->
    Writer.f64 writer min_width;
    Writer.f64 writer max_width;
    Writer.f64 writer min_height;
    Writer.f64 writer max_height
  | Decorated_box, Decorated_box_props { background; border_radius } ->
    write_optional_argb32 writer background;
    Writer.f64 writer border_radius
  | Clip, Clip_props { behavior } -> Writer.u8 writer (clip_behavior_id behavior)
  | Opacity, Opacity_props { opacity } -> Writer.f64 writer opacity
  | Animated_opacity, Animated_opacity_props { opacity; animation } ->
    Writer.f64 writer opacity;
    write_animation writer animation
  | Transform, Transform_props { matrix4 } ->
    if Array.length matrix4 <> 16
    then fail Invalid_props "transform matrix must contain 16 values";
    Array.iter (Writer.f64 writer) matrix4
  | Scroll_view, Scroll_view_props { axis; reverse; primary; cache_extent } ->
    validate_cache_extent cache_extent;
    Writer.u8
      writer
      (match axis with
       | Horizontal -> 0
       | Vertical -> 1);
    write_bool writer reverse;
    write_bool writer primary;
    write_optional_f64 writer cache_extent
  | Sliver_box, Sliver_box_props -> ()
  | Sliver_list, Sliver_list_props -> ()
  | Sliver_fill, Sliver_fill_props -> ()
  | ( Sliver_fixed_extent
    , Sliver_fixed_extent_props { total_count; first_index; item_extent; overscan } ) ->
    write_sliver_fixed_extent_payload
      writer
      ~total_count
      ~first_index
      ~item_extent
      ~overscan
  | ( Sliver_varied_extent
    , Sliver_varied_extent_props
        { total_count
        ; first_index
        ; default_item_extent
        ; overscan
        ; extent_overrides
        ; transition
        } ) ->
    write_sliver_varied_extent_payload
      writer
      ~total_count
      ~first_index
      ~default_item_extent
      ~overscan
      ~extent_overrides
      ~transition
  | Sliver_padding, Sliver_padding_props { left; top; right; bottom } ->
    Writer.f64 writer left;
    Writer.f64 writer top;
    Writer.f64 writer right;
    Writer.f64 writer bottom
  | ( Sliver_app_bar
    , Sliver_app_bar_props
        { pinned
        ; expanded_height
        ; collapsed_height
        ; floating
        ; snap
        ; stretch
        ; toolbar_height
        ; has_leading
        ; has_flexible_space
        ; has_bottom
        ; has_actions
        ; force_elevated
        ; automatically_imply_leading
        ; center_title
        ; background_color
        ; foreground_color
        ; elevation
        } ) ->
    validate_sliver_app_bar
      ~expanded_height
      ~collapsed_height
      ~floating
      ~snap
      ~toolbar_height
      ~elevation;
    write_bool writer pinned;
    write_optional_f64 writer expanded_height;
    write_optional_f64 writer collapsed_height;
    write_bool writer floating;
    write_bool writer snap;
    write_bool writer stretch;
    Writer.f64 writer toolbar_height;
    write_bool writer has_leading;
    write_bool writer has_flexible_space;
    write_bool writer has_bottom;
    write_bool writer has_actions;
    write_bool writer force_elevated;
    write_bool writer automatically_imply_leading;
    write_optional_bool writer center_title;
    write_optional_argb32 writer background_color;
    write_optional_argb32 writer foreground_color;
    write_optional_f64 writer elevation
  | Preferred_size, Preferred_size_props { height } -> Writer.f64 writer height
  | Gesture, Gesture_props -> ()
  | Focus_scope, Focus_scope_props { autofocus } -> write_bool writer autofocus
  | Mouse_region, Mouse_region_props { opaque } -> write_bool writer opaque
  | Keyboard_listener, Keyboard_listener_props { autofocus; key_policy } ->
    write_bool writer autofocus;
    Writer.u8
      writer
      (match key_policy with
       | Handled -> 0
       | Ignored -> 1)
  | ( Semantics
    , Semantics_props
        { label
        ; hint
        ; value
        ; role
        ; enabled
        ; selected
        ; checked
        ; focusable
        ; obscured
        ; live_region
        ; heading_level
        ; sort_key
        ; actions
        } ) ->
    write_optional_string writer label;
    write_optional_string writer hint;
    write_optional_string writer value;
    Writer.u8 writer (semantics_role_id role);
    write_optional_bool writer enabled;
    write_optional_bool writer selected;
    write_optional_bool writer checked;
    write_optional_bool writer focusable;
    write_bool writer obscured;
    write_bool writer live_region;
    write_optional_u8 writer heading_level;
    write_optional_f64 writer sort_key;
    check_u32 "semantics actions" actions;
    Writer.u32 writer actions
  | Theme, Theme_props { brightness; color_seed } ->
    Writer.u8
      writer
      (match brightness with
       | Light -> 0
       | Dark -> 1);
    Writer.u32 writer (Int32.to_int color_seed)
  | Material_scaffold, Material_scaffold_props { has_app_bar } ->
    write_bool writer has_app_bar
  | Material_app_bar, Material_app_bar_props { center_title } ->
    write_bool writer center_title
  | ( (Material_elevated_button | Material_text_button | Material_icon_button)
    , Material_button_props { enabled; autofocus; _ } ) ->
    write_bool writer enabled;
    write_bool writer autofocus
  | Material_checkbox, Material_checkbox_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | Material_switch, Material_switch_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | ( Material_list_tile
    , Material_list_tile_props
        { enabled; selected; has_subtitle; has_leading; has_trailing } ) ->
    write_bool writer enabled;
    write_bool writer selected;
    write_bool writer has_subtitle;
    write_bool writer has_leading;
    write_bool writer has_trailing
  | Material_divider, Material_divider_props { thickness } -> Writer.f64 writer thickness
  | Material_card, Material_card_props { elevation } -> Writer.f64 writer elevation
  | Material_circular_progress_indicator, Material_progress_props { value } ->
    write_optional_f64 writer value
  | Cupertino_button, Cupertino_button_props { enabled } -> write_bool writer enabled
  | Cupertino_switch, Cupertino_switch_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | ( Text_input
    , Text_input_props
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
        } ) ->
    let session_id = ID.Text_input.Session_id.to_int64 session_id in
    let document_revision = ID.Text_input.Document_revision.to_int64 document_revision in
    let accepted_local_revision =
      ID.Text_input.Local_revision.to_int64 accepted_local_revision
    in
    check_u64 "text session ID" session_id;
    check_u64 "document revision" document_revision;
    check_u64 "accepted local revision" accepted_local_revision;
    Writer.u64 writer session_id;
    Writer.u64 writer document_revision;
    write_text_editing_value writer value;
    write_bool writer enabled;
    write_bool writer read_only;
    write_bool writer obscure_text;
    Writer.u8 writer (text_keyboard_type_id keyboard_type);
    Writer.u8 writer (text_input_action_id input_action);
    Writer.u64 writer accepted_local_revision;
    Writer.u8 writer (text_update_mode_id update_mode);
    write_bool writer autofocus;
    (match max_utf8_bytes with
     | Some value when value > Generated_protocol.Limits.max_string_bytes ->
       fail Invalid_props "text input max UTF-8 bytes exceeds the protocol string limit"
     | None | Some _ -> ());
    write_optional_u32 writer "text input max UTF-8 bytes" max_utf8_bytes
  | Overlay, Overlay_props { alignment; dismissible } ->
    Writer.u8 writer (overlay_alignment_id alignment);
    write_bool writer dismissible
  | Navigator, Navigator_props { restoration_scope_id } ->
    write_optional_string
      writer
      (Option.map ID.Navigation.Restoration_scope_id.to_string restoration_scope_id)
  | Page, Page_props { page_key; presentation; can_pop; restoration_id } ->
    write_string writer (ID.Navigation.Page_key.to_string page_key);
    Writer.u8
      writer
      (page_transition_id
         (match presentation with
          | Wire_frame.Standard_page transition -> transition
          | Modal_bottom_sheet _ -> No_transition));
    write_bool writer can_pop;
    write_optional_string
      writer
      (Option.map ID.Navigation.Restoration_id.to_string restoration_id);
    write_page_presentation writer presentation
  | ( Safe_area
    , Safe_area_props
        { left
        ; top
        ; right
        ; bottom
        ; minimum_left
        ; minimum_top
        ; minimum_right
        ; minimum_bottom
        } ) ->
    write_bool writer left;
    write_bool writer top;
    write_bool writer right;
    write_bool writer bottom;
    Writer.f64 writer minimum_left;
    Writer.f64 writer minimum_top;
    Writer.f64 writer minimum_right;
    Writer.f64 writer minimum_bottom
  | Material_dialog, Material_dialog_props { barrier_dismissible } ->
    write_bool writer barrier_dismissible
  | Native_widget, Native_widget_props { kind_id; version; capabilities; payload } ->
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    check_u32 "native widget kind ID" kind_id;
    check_u16 "native widget version" version;
    check_u32 "native widget payload length" (Bytes.length payload);
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u64 writer capabilities;
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
  | _ -> fail Invalid_props "props do not match the node kind"
;;

let props_kind_id = function
  | Wire_frame.Empty_props -> Generated_protocol.Node_kind.empty
  | Text_props _ -> Generated_protocol.Node_kind.text
  | Rich_text_props _ -> Generated_protocol.Node_kind.rich_text
  | Icon_props _ -> Generated_protocol.Node_kind.icon
  | Image_props _ -> Generated_protocol.Node_kind.image
  | Linear_props -> Generated_protocol.Node_kind.row
  | Button_props _ -> Generated_protocol.Node_kind.button
  | Pressable_props _ -> Generated_protocol.Node_kind.pressable
  | Padding_props _ -> Generated_protocol.Node_kind.padding
  | Align_props _ -> Generated_protocol.Node_kind.align
  | Center_props _ -> Generated_protocol.Node_kind.center
  | Sized_box_props _ -> Generated_protocol.Node_kind.sized_box
  | Constrained_box_props _ -> Generated_protocol.Node_kind.constrained_box
  | Decorated_box_props _ -> Generated_protocol.Node_kind.decorated_box
  | Clip_props _ -> Generated_protocol.Node_kind.clip
  | Opacity_props _ -> Generated_protocol.Node_kind.opacity
  | Animated_opacity_props _ -> Generated_protocol.Node_kind.animated_opacity
  | Transform_props _ -> Generated_protocol.Node_kind.transform
  | Scroll_view_props _ -> Generated_protocol.Node_kind.scroll_view
  | Sliver_box_props -> Generated_protocol.Node_kind.sliver_box
  | Sliver_list_props -> Generated_protocol.Node_kind.sliver_list
  | Sliver_fill_props -> Generated_protocol.Node_kind.sliver_fill
  | Sliver_fixed_extent_props _ -> Generated_protocol.Node_kind.sliver_fixed_extent
  | Sliver_varied_extent_props _ -> Generated_protocol.Node_kind.sliver_varied_extent
  | Sliver_padding_props _ -> Generated_protocol.Node_kind.sliver_padding
  | Sliver_app_bar_props _ -> Generated_protocol.Node_kind.sliver_app_bar
  | Preferred_size_props _ -> Generated_protocol.Node_kind.preferred_size
  | Gesture_props -> Generated_protocol.Node_kind.gesture
  | Focus_scope_props _ -> Generated_protocol.Node_kind.focus_scope
  | Mouse_region_props _ -> Generated_protocol.Node_kind.mouse_region
  | Keyboard_listener_props _ -> Generated_protocol.Node_kind.keyboard_listener
  | Semantics_props _ -> Generated_protocol.Node_kind.semantics
  | Theme_props _ -> Generated_protocol.Node_kind.theme
  | Material_scaffold_props _ -> Generated_protocol.Node_kind.material_scaffold
  | Material_app_bar_props _ -> Generated_protocol.Node_kind.material_app_bar
  | Material_button_props { variant; _ } ->
    (match variant with
     | Elevated -> Generated_protocol.Node_kind.material_elevated_button
     | Text_button -> Generated_protocol.Node_kind.material_text_button
     | Icon_button -> Generated_protocol.Node_kind.material_icon_button)
  | Material_checkbox_props _ -> Generated_protocol.Node_kind.material_checkbox
  | Material_switch_props _ -> Generated_protocol.Node_kind.material_switch
  | Material_list_tile_props _ -> Generated_protocol.Node_kind.material_list_tile
  | Material_divider_props _ -> Generated_protocol.Node_kind.material_divider
  | Material_card_props _ -> Generated_protocol.Node_kind.material_card
  | Material_progress_props _ ->
    Generated_protocol.Node_kind.material_circular_progress_indicator
  | Cupertino_button_props _ -> Generated_protocol.Node_kind.cupertino_button
  | Cupertino_switch_props _ -> Generated_protocol.Node_kind.cupertino_switch
  | Text_input_props _ -> Generated_protocol.Node_kind.text_input
  | Overlay_props _ -> Generated_protocol.Node_kind.overlay
  | Navigator_props _ -> Generated_protocol.Node_kind.navigator
  | Page_props _ -> Generated_protocol.Node_kind.page
  | Safe_area_props _ -> Generated_protocol.Node_kind.safe_area
  | Environment_boundary_props -> Generated_protocol.Node_kind.environment_boundary
  | Material_dialog_props _ -> Generated_protocol.Node_kind.material_dialog
  | Native_widget_props _ -> Generated_protocol.Node_kind.native_widget
;;

let field_mask id =
  let id = ID.Protocol.Property.to_int id in
  Int64.shift_left 1L (id - 1)
;;

let changed_fields = function
  | Wire_frame.Empty_props | Linear_props | Gesture_props | Environment_boundary_props ->
    0L
  | Text_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Text_prop.value
      ; field_mask Generated_protocol.Text_prop.text_style
      ; field_mask Generated_protocol.Text_prop.text_align
      ; field_mask Generated_protocol.Text_prop.max_lines
      ; field_mask Generated_protocol.Text_prop.overflow
      ]
  | Rich_text_props _ -> field_mask Generated_protocol.Rich_text_prop.spans
  | Icon_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Icon_prop.code_point
      ; field_mask Generated_protocol.Icon_prop.font_family
      ; field_mask Generated_protocol.Icon_prop.size
      ; field_mask Generated_protocol.Icon_prop.color
      ]
  | Image_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Image_prop.uri
      ; field_mask Generated_protocol.Image_prop.fit
      ; field_mask Generated_protocol.Image_prop.width
      ; field_mask Generated_protocol.Image_prop.height
      ]
  | Button_props _ -> field_mask Generated_protocol.Button_prop.enabled
  | Pressable_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Pressable_prop.overlay_color)
      (field_mask Generated_protocol.Pressable_prop.release_delay_ms)
  | Padding_props _ -> field_mask Generated_protocol.Padding_prop.insets
  | Align_props _ -> field_mask Generated_protocol.Align_prop.alignment
  | Center_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Center_prop.width_factor)
      (field_mask Generated_protocol.Center_prop.height_factor)
  | Sized_box_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Sized_box_prop.width)
      (field_mask Generated_protocol.Sized_box_prop.height)
  | Constrained_box_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Constrained_box_prop.min_width
      ; field_mask Generated_protocol.Constrained_box_prop.max_width
      ; field_mask Generated_protocol.Constrained_box_prop.min_height
      ; field_mask Generated_protocol.Constrained_box_prop.max_height
      ]
  | Decorated_box_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Decorated_box_prop.background)
      (field_mask Generated_protocol.Decorated_box_prop.border_radius)
  | Clip_props _ -> field_mask Generated_protocol.Clip_prop.behavior
  | Opacity_props _ -> field_mask Generated_protocol.Opacity_prop.opacity
  | Animated_opacity_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Animated_opacity_prop.opacity
      ; field_mask Generated_protocol.Animated_opacity_prop.animation_id
      ; field_mask Generated_protocol.Animated_opacity_prop.duration_ms
      ; field_mask Generated_protocol.Animated_opacity_prop.curve
      ]
  | Transform_props _ -> field_mask Generated_protocol.Transform_prop.matrix4
  | Scroll_view_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Scroll_view_prop.axis
      ; field_mask Generated_protocol.Scroll_view_prop.reverse
      ; field_mask Generated_protocol.Scroll_view_prop.primary
      ; field_mask Generated_protocol.Scroll_view_prop.cache_extent
      ]
  | Sliver_box_props | Sliver_list_props -> 0L
  | Sliver_fill_props -> 0L
  | Sliver_fixed_extent_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Sliver_fixed_extent_prop.total_count
      ; field_mask Generated_protocol.Sliver_fixed_extent_prop.first_index
      ; field_mask Generated_protocol.Sliver_fixed_extent_prop.item_extent
      ; field_mask Generated_protocol.Sliver_fixed_extent_prop.overscan
      ]
  | Sliver_varied_extent_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Sliver_varied_extent_prop.total_count
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.first_index
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.default_item_extent
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.overscan
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.override_count
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.overrides
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.transition_enabled
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.expand_duration_ms
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.collapse_duration_ms
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.expand_curve
      ; field_mask Generated_protocol.Sliver_varied_extent_prop.collapse_curve
      ]
  | Sliver_padding_props _ -> field_mask Generated_protocol.Sliver_padding_prop.insets
  | Sliver_app_bar_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Sliver_app_bar_prop.pinned
      ; field_mask Generated_protocol.Sliver_app_bar_prop.expanded_height
      ; field_mask Generated_protocol.Sliver_app_bar_prop.collapsed_height
      ; field_mask Generated_protocol.Sliver_app_bar_prop.floating
      ; field_mask Generated_protocol.Sliver_app_bar_prop.snap
      ; field_mask Generated_protocol.Sliver_app_bar_prop.stretch
      ; field_mask Generated_protocol.Sliver_app_bar_prop.toolbar_height
      ; field_mask Generated_protocol.Sliver_app_bar_prop.has_leading
      ; field_mask Generated_protocol.Sliver_app_bar_prop.has_flexible_space
      ; field_mask Generated_protocol.Sliver_app_bar_prop.has_bottom
      ; field_mask Generated_protocol.Sliver_app_bar_prop.has_actions
      ; field_mask Generated_protocol.Sliver_app_bar_prop.force_elevated
      ; field_mask Generated_protocol.Sliver_app_bar_prop.automatically_imply_leading
      ; field_mask Generated_protocol.Sliver_app_bar_prop.center_title
      ; field_mask Generated_protocol.Sliver_app_bar_prop.background_color
      ; field_mask Generated_protocol.Sliver_app_bar_prop.foreground_color
      ; field_mask Generated_protocol.Sliver_app_bar_prop.elevation
      ]
  | Preferred_size_props _ -> field_mask Generated_protocol.Preferred_size_prop.height
  | Focus_scope_props _ -> field_mask Generated_protocol.Focus_scope_prop.autofocus
  | Mouse_region_props _ -> field_mask Generated_protocol.Mouse_region_prop.opaque
  | Keyboard_listener_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Keyboard_listener_prop.autofocus)
      (field_mask Generated_protocol.Keyboard_listener_prop.key_policy)
  | Semantics_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Semantics_prop.label
      ; field_mask Generated_protocol.Semantics_prop.hint
      ; field_mask Generated_protocol.Semantics_prop.value
      ; field_mask Generated_protocol.Semantics_prop.role
      ; field_mask Generated_protocol.Semantics_prop.enabled
      ; field_mask Generated_protocol.Semantics_prop.selected
      ; field_mask Generated_protocol.Semantics_prop.checked
      ; field_mask Generated_protocol.Semantics_prop.focusable
      ; field_mask Generated_protocol.Semantics_prop.obscured
      ; field_mask Generated_protocol.Semantics_prop.live_region
      ; field_mask Generated_protocol.Semantics_prop.heading_level
      ; field_mask Generated_protocol.Semantics_prop.sort_key
      ; field_mask Generated_protocol.Semantics_prop.actions
      ]
  | Theme_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Theme_prop.brightness)
      (field_mask Generated_protocol.Theme_prop.color_seed)
  | Material_scaffold_props _ ->
    field_mask Generated_protocol.Material_scaffold_prop.has_app_bar
  | Material_app_bar_props _ ->
    field_mask Generated_protocol.Material_app_bar_prop.center_title
  | Material_button_props { variant; _ } ->
    let enabled, autofocus =
      match variant with
      | Elevated ->
        ( Generated_protocol.Material_elevated_button_prop.enabled
        , Generated_protocol.Material_elevated_button_prop.autofocus )
      | Text_button ->
        ( Generated_protocol.Material_text_button_prop.enabled
        , Generated_protocol.Material_text_button_prop.autofocus )
      | Icon_button ->
        ( Generated_protocol.Material_icon_button_prop.enabled
        , Generated_protocol.Material_icon_button_prop.autofocus )
    in
    Int64.logor (field_mask enabled) (field_mask autofocus)
  | Material_checkbox_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Material_checkbox_prop.value)
      (field_mask Generated_protocol.Material_checkbox_prop.enabled)
  | Material_switch_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Material_switch_prop.value)
      (field_mask Generated_protocol.Material_switch_prop.enabled)
  | Material_list_tile_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Material_list_tile_prop.enabled
      ; field_mask Generated_protocol.Material_list_tile_prop.selected
      ; field_mask Generated_protocol.Material_list_tile_prop.has_subtitle
      ; field_mask Generated_protocol.Material_list_tile_prop.has_leading
      ; field_mask Generated_protocol.Material_list_tile_prop.has_trailing
      ]
  | Material_divider_props _ ->
    field_mask Generated_protocol.Material_divider_prop.thickness
  | Material_card_props _ -> field_mask Generated_protocol.Material_card_prop.elevation
  | Material_progress_props _ ->
    field_mask Generated_protocol.Material_circular_progress_indicator_prop.value
  | Cupertino_button_props _ ->
    field_mask Generated_protocol.Cupertino_button_prop.enabled
  | Cupertino_switch_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Cupertino_switch_prop.value)
      (field_mask Generated_protocol.Cupertino_switch_prop.enabled)
  | Text_input_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Text_input_prop.session_id
      ; field_mask Generated_protocol.Text_input_prop.document_revision
      ; field_mask Generated_protocol.Text_input_prop.value
      ; field_mask Generated_protocol.Text_input_prop.enabled
      ; field_mask Generated_protocol.Text_input_prop.read_only
      ; field_mask Generated_protocol.Text_input_prop.obscure_text
      ; field_mask Generated_protocol.Text_input_prop.keyboard_type
      ; field_mask Generated_protocol.Text_input_prop.input_action
      ; field_mask Generated_protocol.Text_input_prop.accepted_local_revision
      ; field_mask Generated_protocol.Text_input_prop.update_mode
      ; field_mask Generated_protocol.Text_input_prop.autofocus
      ; field_mask Generated_protocol.Text_input_prop.max_utf8_bytes
      ]
  | Overlay_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Overlay_prop.alignment)
      (field_mask Generated_protocol.Overlay_prop.dismissible)
  | Navigator_props _ -> field_mask Generated_protocol.Navigator_prop.restoration_scope_id
  | Page_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Page_prop.page_key
      ; field_mask Generated_protocol.Page_prop.transition
      ; field_mask Generated_protocol.Page_prop.can_pop
      ; field_mask Generated_protocol.Page_prop.restoration_id
      ; field_mask Generated_protocol.Page_prop.presentation
      ; field_mask Generated_protocol.Page_prop.modal_barrier_dismissible
      ; field_mask Generated_protocol.Page_prop.modal_barrier_color
      ; field_mask Generated_protocol.Page_prop.modal_barrier_label
      ; field_mask Generated_protocol.Page_prop.modal_use_safe_area
      ; field_mask Generated_protocol.Page_prop.modal_request_focus
      ; field_mask Generated_protocol.Page_prop.modal_transition_duration_ms
      ; field_mask Generated_protocol.Page_prop.modal_reverse_transition_duration_ms
      ; field_mask Generated_protocol.Page_prop.modal_sizing
      ; field_mask Generated_protocol.Page_prop.modal_detents
      ; field_mask Generated_protocol.Page_prop.modal_initial_detent
      ; field_mask Generated_protocol.Page_prop.modal_dismiss_on_drag
      ; field_mask Generated_protocol.Page_prop.modal_handle_semantics_label
      ; field_mask Generated_protocol.Page_prop.modal_medium_semantics_value
      ; field_mask Generated_protocol.Page_prop.modal_large_semantics_value
      ]
  | Safe_area_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Safe_area_prop.left
      ; field_mask Generated_protocol.Safe_area_prop.top
      ; field_mask Generated_protocol.Safe_area_prop.right
      ; field_mask Generated_protocol.Safe_area_prop.bottom
      ; field_mask Generated_protocol.Safe_area_prop.minimum
      ]
  | Material_dialog_props _ ->
    field_mask Generated_protocol.Material_dialog_prop.barrier_dismissible
  | Native_widget_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Native_widget_prop.kind_id
      ; field_mask Generated_protocol.Native_widget_prop.version
      ; field_mask Generated_protocol.Native_widget_prop.capabilities
      ; field_mask Generated_protocol.Native_widget_prop.payload
      ]
;;

let write_update_props writer props =
  Writer.u16 writer (ID.Protocol.Node_kind.to_int (props_kind_id props));
  Writer.u64 writer (changed_fields props);
  match props with
  | Wire_frame.Empty_props
  | Linear_props
  | Gesture_props
  | Environment_boundary_props
  | Sliver_box_props
  | Sliver_list_props -> ()
  | Text_props props -> write_text_props writer props
  | Rich_text_props { spans } ->
    check_u16 "rich text span count" (List.length spans);
    Writer.u16 writer (List.length spans);
    List.iter (write_string writer) spans
  | Icon_props { code_point; font_family; size; color } ->
    check_u32 "icon code point" code_point;
    Writer.u32 writer code_point;
    write_optional_string writer font_family;
    write_optional_f64 writer size;
    write_optional_argb32 writer color
  | Image_props { uri; fit; width; height } ->
    write_string writer uri;
    Writer.u8 writer (image_fit_id fit);
    write_optional_f64 writer width;
    write_optional_f64 writer height
  | Button_props { enabled } -> write_bool writer enabled
  | Pressable_props { overlay_color_argb; release_delay_ms } ->
    check_pressable_release_delay release_delay_ms;
    Writer.u32 writer (Int32.to_int overlay_color_argb);
    Writer.u16 writer release_delay_ms
  | Padding_props { left; top; right; bottom } ->
    Writer.f64 writer left;
    Writer.f64 writer top;
    Writer.f64 writer right;
    Writer.f64 writer bottom
  | Align_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Center_props { width_factor; height_factor } ->
    write_optional_f64 writer width_factor;
    write_optional_f64 writer height_factor
  | Sized_box_props { width; height } ->
    write_optional_f64 writer width;
    write_optional_f64 writer height
  | Constrained_box_props { min_width; max_width; min_height; max_height } ->
    Writer.f64 writer min_width;
    Writer.f64 writer max_width;
    Writer.f64 writer min_height;
    Writer.f64 writer max_height
  | Decorated_box_props { background; border_radius } ->
    write_optional_argb32 writer background;
    Writer.f64 writer border_radius
  | Clip_props { behavior } -> Writer.u8 writer (clip_behavior_id behavior)
  | Opacity_props { opacity } -> Writer.f64 writer opacity
  | Animated_opacity_props { opacity; animation } ->
    Writer.f64 writer opacity;
    write_animation writer animation
  | Transform_props { matrix4 } ->
    if Array.length matrix4 <> 16
    then fail Invalid_props "transform matrix must contain 16 values";
    Array.iter (Writer.f64 writer) matrix4
  | Scroll_view_props { axis; reverse; primary; cache_extent } ->
    validate_cache_extent cache_extent;
    Writer.u8
      writer
      (match axis with
       | Horizontal -> 0
       | Vertical -> 1);
    write_bool writer reverse;
    write_bool writer primary;
    write_optional_f64 writer cache_extent
  | Sliver_fill_props -> ()
  | Sliver_fixed_extent_props { total_count; first_index; item_extent; overscan } ->
    write_sliver_fixed_extent_payload
      writer
      ~total_count
      ~first_index
      ~item_extent
      ~overscan
  | Sliver_varied_extent_props
      { total_count
      ; first_index
      ; default_item_extent
      ; overscan
      ; extent_overrides
      ; transition
      } ->
    write_sliver_varied_extent_payload
      writer
      ~total_count
      ~first_index
      ~default_item_extent
      ~overscan
      ~extent_overrides
      ~transition
  | Sliver_padding_props { left; top; right; bottom } ->
    Writer.f64 writer left;
    Writer.f64 writer top;
    Writer.f64 writer right;
    Writer.f64 writer bottom
  | Sliver_app_bar_props
      { pinned
      ; expanded_height
      ; collapsed_height
      ; floating
      ; snap
      ; stretch
      ; toolbar_height
      ; has_leading
      ; has_flexible_space
      ; has_bottom
      ; has_actions
      ; force_elevated
      ; automatically_imply_leading
      ; center_title
      ; background_color
      ; foreground_color
      ; elevation
      } ->
    validate_sliver_app_bar
      ~expanded_height
      ~collapsed_height
      ~floating
      ~snap
      ~toolbar_height
      ~elevation;
    write_bool writer pinned;
    write_optional_f64 writer expanded_height;
    write_optional_f64 writer collapsed_height;
    write_bool writer floating;
    write_bool writer snap;
    write_bool writer stretch;
    Writer.f64 writer toolbar_height;
    write_bool writer has_leading;
    write_bool writer has_flexible_space;
    write_bool writer has_bottom;
    write_bool writer has_actions;
    write_bool writer force_elevated;
    write_bool writer automatically_imply_leading;
    write_optional_bool writer center_title;
    write_optional_argb32 writer background_color;
    write_optional_argb32 writer foreground_color;
    write_optional_f64 writer elevation
  | Preferred_size_props { height } -> Writer.f64 writer height
  | Focus_scope_props { autofocus } -> write_bool writer autofocus
  | Mouse_region_props { opaque } -> write_bool writer opaque
  | Keyboard_listener_props { autofocus; key_policy } ->
    write_bool writer autofocus;
    Writer.u8
      writer
      (match key_policy with
       | Handled -> 0
       | Ignored -> 1)
  | Semantics_props
      { label
      ; hint
      ; value
      ; role
      ; enabled
      ; selected
      ; checked
      ; focusable
      ; obscured
      ; live_region
      ; heading_level
      ; sort_key
      ; actions
      } ->
    write_optional_string writer label;
    write_optional_string writer hint;
    write_optional_string writer value;
    Writer.u8 writer (semantics_role_id role);
    write_optional_bool writer enabled;
    write_optional_bool writer selected;
    write_optional_bool writer checked;
    write_optional_bool writer focusable;
    write_bool writer obscured;
    write_bool writer live_region;
    write_optional_u8 writer heading_level;
    write_optional_f64 writer sort_key;
    check_u32 "semantics actions" actions;
    Writer.u32 writer actions
  | Theme_props { brightness; color_seed } ->
    Writer.u8
      writer
      (match brightness with
       | Light -> 0
       | Dark -> 1);
    Writer.u32 writer (Int32.to_int color_seed)
  | Material_scaffold_props { has_app_bar } -> write_bool writer has_app_bar
  | Material_app_bar_props { center_title } -> write_bool writer center_title
  | Material_button_props { enabled; autofocus; _ } ->
    write_bool writer enabled;
    write_bool writer autofocus
  | Material_checkbox_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | Material_switch_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | Material_list_tile_props
      { enabled; selected; has_subtitle; has_leading; has_trailing } ->
    write_bool writer enabled;
    write_bool writer selected;
    write_bool writer has_subtitle;
    write_bool writer has_leading;
    write_bool writer has_trailing
  | Material_divider_props { thickness } -> Writer.f64 writer thickness
  | Material_card_props { elevation } -> Writer.f64 writer elevation
  | Material_progress_props { value } -> write_optional_f64 writer value
  | Cupertino_button_props { enabled } -> write_bool writer enabled
  | Cupertino_switch_props { value; enabled } ->
    write_bool writer value;
    write_bool writer enabled
  | Text_input_props
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
      } ->
    let session_id = ID.Text_input.Session_id.to_int64 session_id in
    let document_revision = ID.Text_input.Document_revision.to_int64 document_revision in
    let accepted_local_revision =
      ID.Text_input.Local_revision.to_int64 accepted_local_revision
    in
    check_u64 "text session ID" session_id;
    check_u64 "document revision" document_revision;
    check_u64 "accepted local revision" accepted_local_revision;
    Writer.u64 writer session_id;
    Writer.u64 writer document_revision;
    write_text_editing_value writer value;
    write_bool writer enabled;
    write_bool writer read_only;
    write_bool writer obscure_text;
    Writer.u8 writer (text_keyboard_type_id keyboard_type);
    Writer.u8 writer (text_input_action_id input_action);
    Writer.u64 writer accepted_local_revision;
    Writer.u8 writer (text_update_mode_id update_mode);
    write_bool writer autofocus;
    (match max_utf8_bytes with
     | Some value when value > Generated_protocol.Limits.max_string_bytes ->
       fail Invalid_props "text input max UTF-8 bytes exceeds the protocol string limit"
     | None | Some _ -> ());
    write_optional_u32 writer "text input max UTF-8 bytes" max_utf8_bytes
  | Overlay_props { alignment; dismissible } ->
    Writer.u8 writer (overlay_alignment_id alignment);
    write_bool writer dismissible
  | Navigator_props { restoration_scope_id } ->
    write_optional_string
      writer
      (Option.map ID.Navigation.Restoration_scope_id.to_string restoration_scope_id)
  | Page_props { page_key; presentation; can_pop; restoration_id } ->
    write_string writer (ID.Navigation.Page_key.to_string page_key);
    Writer.u8
      writer
      (page_transition_id
         (match presentation with
          | Wire_frame.Standard_page transition -> transition
          | Modal_bottom_sheet _ -> No_transition));
    write_bool writer can_pop;
    write_optional_string
      writer
      (Option.map ID.Navigation.Restoration_id.to_string restoration_id);
    write_page_presentation writer presentation
  | Safe_area_props
      { left
      ; top
      ; right
      ; bottom
      ; minimum_left
      ; minimum_top
      ; minimum_right
      ; minimum_bottom
      } ->
    write_bool writer left;
    write_bool writer top;
    write_bool writer right;
    write_bool writer bottom;
    Writer.f64 writer minimum_left;
    Writer.f64 writer minimum_top;
    Writer.f64 writer minimum_right;
    Writer.f64 writer minimum_bottom
  | Material_dialog_props { barrier_dismissible } -> write_bool writer barrier_dismissible
  | Native_widget_props { kind_id; version; capabilities; payload } ->
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    check_u32 "native widget kind ID" kind_id;
    check_u16 "native widget version" version;
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u64 writer capabilities;
    check_u32 "native widget payload length" (Bytes.length payload);
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
;;

let write_bytes writer value =
  let length = Bytes.length value in
  check_u32 "byte payload length" length;
  Writer.u32 writer length;
  Writer.bytes writer value
;;

let write_string_list writer values =
  check_u16 "string list length" (List.length values);
  Writer.u16 writer (List.length values);
  List.iter (write_string writer) values
;;

let write_host_request body request_id payload =
  let request_id = ID.Host.Request_id.to_int64 request_id in
  check_u64 "host request ID" request_id;
  Writer.u64 body request_id;
  let request_kind, write_payload =
    match payload with
    | Wire_frame.Clipboard_read ->
      Generated_protocol.Host_request.clipboard_read, fun () -> ()
    | Clipboard_write { text } ->
      Generated_protocol.Host_request.clipboard_write, fun () -> write_string body text
    | Open_url { uri } ->
      Generated_protocol.Host_request.open_url, fun () -> write_string body uri
    | Pick_file { allowed_extensions; allow_multiple } ->
      ( Generated_protocol.Host_request.pick_file
      , fun () ->
          write_string_list body allowed_extensions;
          write_bool body allow_multiple )
    | Save_file { suggested_name; data } ->
      ( Generated_protocol.Host_request.save_file
      , fun () ->
          write_optional_string body suggested_name;
          write_bytes body data )
    | Request_focus { node_id } ->
      ( Generated_protocol.Host_request.request_focus
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "focus node ID" node_id;
          Writer.u64 body node_id )
    | Clear_focus -> Generated_protocol.Host_request.clear_focus, fun () -> ()
    | Scroll_to { node_id; alignment; animated } ->
      ( Generated_protocol.Host_request.scroll_to
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "scroll node ID" node_id;
          if not (Float.is_finite alignment)
          then fail Invalid_props "scroll alignment must be finite";
          Writer.u64 body node_id;
          Writer.f64 body alignment;
          write_bool body animated )
    | Set_window_title { title } ->
      Generated_protocol.Host_request.set_window_title, fun () -> write_string body title
    | Set_window_size { width; height } ->
      ( Generated_protocol.Host_request.set_window_size
      , fun () ->
          if
            not
              (Float.is_finite width
               && Float.is_finite height
               && Float.compare width 0. > 0
               && Float.compare height 0. > 0)
          then fail Invalid_props "window size must be finite and positive";
          Writer.f64 body width;
          Writer.f64 body height )
    | Show_native_menu { items } ->
      ( Generated_protocol.Host_request.show_native_menu
      , fun () ->
          check_u16 "native menu item count" (List.length items);
          Writer.u16 body (List.length items);
          List.iter
            (fun (item : Wire_frame.native_menu_item) ->
               write_string body (ID.Host.Native_menu_item_id.to_string item.item_id);
               write_string body item.label;
               write_bool body item.enabled)
            items )
    | Haptic_feedback kind ->
      ( Generated_protocol.Host_request.haptic_feedback
      , fun () ->
          Writer.u8
            body
            (match kind with
             | Wire_frame.Haptic_light -> 0
             | Haptic_medium -> 1
             | Haptic_heavy -> 2
             | Haptic_selection -> 3) )
    | Platform_information ->
      Generated_protocol.Host_request.platform_information, fun () -> ()
    | Measure_layout { node_id } ->
      ( Generated_protocol.Host_request.measure_layout
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "layout node ID" node_id;
          Writer.u64 body node_id )
  in
  Writer.u16 body (ID.Protocol.Host_request_kind.to_int request_kind);
  write_payload ()
;;

let write_bindings writer bindings =
  let count = List.length bindings in
  check_u16 "event binding count" count;
  Writer.u16 writer count;
  List.iter
    (fun (binding : Wire_frame.event_binding) ->
       let event_tag = ID.Protocol.Event_tag.to_int binding.event_tag in
       let handler_id = ID.Ui.Handler_id.to_int64 binding.handler_id in
       check_u16 "event tag" event_tag;
       check_u64 "handler ID" handler_id;
       Writer.u16 writer event_tag;
       Writer.u64 writer handler_id)
    bindings
;;

let write_parent_data writer = function
  | Wire_frame.No_parent_data -> Writer.u8 writer 0
  | Flex_parent_data { flex; fit } ->
    check_u32 "flex factor" flex;
    if flex = 0 then fail Invalid_props "flex factor must be positive";
    Writer.u8
      writer
      (match fit with
       | Loose -> 1
       | Tight -> 2);
    Writer.u32 writer flex
  | Stack_position { left; top; right; bottom } ->
    Writer.u8 writer 3;
    write_optional_f64 writer left;
    write_optional_f64 writer top;
    write_optional_f64 writer right;
    write_optional_f64 writer bottom
;;

let envelope payload opcode body =
  let bytes = Writer.contents body in
  Writer.u8 payload (ID.Protocol.Operation.to_int opcode);
  Writer.u32 payload (Bytes.length bytes);
  Writer.bytes payload bytes
;;

let write_empty_envelope payload opcode =
  Writer.u8 payload (ID.Protocol.Operation.to_int opcode);
  Writer.u32 payload 0
;;

let write_operation ?(record_runtime_stats_offsets = fun _ -> ()) payload = function
  | Wire_frame.Create_node { node_id; kind; props; event_bindings; parent_data } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    Writer.u16 body (ID.Protocol.Node_kind.to_int (node_kind_id kind));
    write_props body kind props;
    write_bindings body event_bindings;
    write_parent_data body parent_data;
    envelope payload Generated_protocol.Operation.create_node body
  | Update_props { node_id; props } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    write_update_props body props;
    envelope payload Generated_protocol.Operation.update_props body
  | Update_event_bindings { node_id; event_bindings } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    write_bindings body event_bindings;
    envelope payload Generated_protocol.Operation.update_event_bindings body
  | Set_children { node_id; children } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    if List.length children > Generated_protocol.Limits.max_nodes
    then fail Invalid_props "child count exceeds the node limit";
    let body = Writer.create () in
    Writer.u64 body node_id;
    Writer.u32 body (List.length children);
    List.iter
      (fun child ->
         let child = ID.Ui.Node_id.to_int64 child in
         check_u64 "child node ID" child;
         Writer.u64 body child)
      children;
    envelope payload Generated_protocol.Operation.set_children body
  | Set_root node_id ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "root node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    envelope payload Generated_protocol.Operation.set_root body
  | Drop_node node_id ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    envelope payload Generated_protocol.Operation.drop_node body
  | Host_request { request_id; payload = request } ->
    let body = Writer.create () in
    write_host_request body request_id request;
    envelope payload Generated_protocol.Operation.host_request body
  | Cancel_host_request { request_id } ->
    let request_id = ID.Host.Request_id.to_int64 request_id in
    check_u64 "host request ID" request_id;
    let body = Writer.create () in
    Writer.u64 body request_id;
    Writer.u16 body 0;
    envelope payload Generated_protocol.Operation.host_request body
  | Application_request { request_id; payload = application_payload } ->
    if Int64.compare request_id 0L <= 0
    then fail Invalid_props "application request ID must be positive";
    let payload_length = Bytes.length application_payload in
    if payload_length > Generated_protocol.Limits.max_application_payload_bytes
    then
      fail
        Application_payload_too_large
        "application request payload is %d bytes"
        payload_length;
    let body = Writer.create () in
    Writer.u64 body request_id;
    Writer.u32 body payload_length;
    Writer.bytes body application_payload;
    envelope payload Generated_protocol.Operation.application_request body
  | Runtime_stats stats ->
    let body = Writer.create () in
    check_u32 "event batch size" stats.event_batch_size;
    check_u64 "Bonsai flush duration" stats.bonsai_flush_ns;
    check_u64 "result read duration" stats.result_read_ns;
    check_u64 "reconcile duration" stats.reconcile_ns;
    check_u64 "encode duration" stats.encode_ns;
    check_u32 "patch count" stats.patch_count;
    check_u32 "patch bytes" stats.patch_bytes;
    check_u64 "lifecycle duration" stats.lifecycle_ns;
    check_u32 "full snapshot count" stats.full_snapshot_count;
    check_u32 "resync count" stats.resync_count;
    Writer.u32 body stats.event_batch_size;
    Writer.u64 body stats.bonsai_flush_ns;
    Writer.u64 body stats.result_read_ns;
    Writer.u64 body stats.reconcile_ns;
    let encode_ns = Writer.length body in
    Writer.u64 body stats.encode_ns;
    Writer.u32 body stats.patch_count;
    let patch_bytes = Writer.length body in
    Writer.u32 body stats.patch_bytes;
    Writer.u64 body stats.lifecycle_ns;
    Writer.u32 body stats.full_snapshot_count;
    Writer.u32 body stats.resync_count;
    let body_start = Writer.length payload + 5 in
    envelope payload Generated_protocol.Operation.runtime_notification body;
    record_runtime_stats_offsets
      Runtime_encoded_frame.
        { encode_ns = body_start + encode_ns; patch_bytes = body_start + patch_bytes }
;;

let encode_bytes frame ~record_runtime_stats_offsets =
  let operation_count = List.length frame.Wire_frame.operations + 2 in
  if operation_count > Generated_protocol.Limits.max_operations
  then fail Too_many_operations "frame has %d operations" operation_count;
  let runtime_epoch = ID.Runtime.Epoch.to_int64 frame.runtime_epoch in
  let base_revision = ID.Runtime.Renderer_revision.to_int64 frame.base_revision in
  let target_revision = ID.Runtime.Renderer_revision.to_int64 frame.target_revision in
  check_u64 "runtime epoch" runtime_epoch;
  check_u64 "base revision" base_revision;
  check_u64 "target revision" target_revision;
  let payload = Writer.create () in
  write_empty_envelope payload Generated_protocol.Operation.begin_frame;
  List.iter (write_operation ~record_runtime_stats_offsets payload) frame.operations;
  write_empty_envelope payload Generated_protocol.Operation.end_frame;
  let payload = Writer.contents payload in
  let total_length = Generated_protocol.Limits.header_bytes + Bytes.length payload in
  if total_length > Generated_protocol.Limits.max_frame_bytes
  then fail Frame_too_large "encoded frame is %d bytes" total_length;
  let output = Writer.create () in
  Writer.string output "BFFR";
  Writer.u16 output Generated_protocol.protocol_major;
  Writer.u16 output Generated_protocol.protocol_minor;
  Writer.u16 output Generated_protocol.Limits.header_bytes;
  Writer.u8
    output
    (ID.Protocol.Frame_kind.to_int
       (match frame.kind with
        | Wire_frame.Full_snapshot -> Generated_protocol.Frame_kind.full_snapshot
        | Incremental_frame -> Generated_protocol.Frame_kind.incremental_frame));
  Writer.u8 output 0;
  Writer.u64 output runtime_epoch;
  Writer.u64 output base_revision;
  Writer.u64 output target_revision;
  Writer.u32 output (Bytes.length payload);
  Writer.u32 output 0;
  Writer.u32 output 0;
  Writer.bytes output payload;
  Writer.contents output
;;

let encode frame =
  try Ok (encode_bytes frame ~record_runtime_stats_offsets:(fun _ -> ())) with
  | Codec_error error -> Error error
;;

let encode_runtime_frame frame =
  try
    let discovered_offsets = ref [] in
    let encoded_bytes =
      encode_bytes frame ~record_runtime_stats_offsets:(fun offsets ->
        discovered_offsets := offsets :: !discovered_offsets)
    in
    match !discovered_offsets with
    | [ payload_offsets ] ->
      let translate offset = Generated_protocol.Limits.header_bytes + offset in
      let stats_offsets =
        Runtime_encoded_frame.
          { encode_ns = translate payload_offsets.encode_ns
          ; patch_bytes = translate payload_offsets.patch_bytes
          }
      in
      Ok Runtime_encoded_frame.{ bytes = encoded_bytes; stats_offsets }
    | [] ->
      fail
        Invalid_operation_order
        "runtime frame must contain exactly one runtime stats operation"
    | _ ->
      fail
        Invalid_operation_order
        "runtime frame must contain exactly one runtime stats operation"
  with
  | Codec_error error -> Error error
;;

let require_patch_range bytes ~offset ~width ~label =
  if offset < 0 || offset > Bytes.length bytes - width
  then fail Invalid_props "%s patch offset is outside the encoded frame" label
;;

let patch_u32 bytes offset value =
  for shift = 0 to 3 do
    Bytes.set bytes (offset + shift) (Char.chr ((value lsr (shift * 8)) land 0xff))
  done
;;

let patch_u64 bytes offset value =
  for shift = 0 to 7 do
    let byte = Int64.(shift_right_logical value (shift * 8) |> to_int) land 0xff in
    Bytes.set bytes (offset + shift) (Char.chr byte)
  done
;;

let patch_runtime_stats encoded ~encode_ns ~patch_bytes =
  try
    check_u64 "encode duration" encode_ns;
    check_u32 "patch bytes" patch_bytes;
    let bytes = Runtime_encoded_frame.bytes encoded in
    let offsets = encoded.Runtime_encoded_frame.stats_offsets in
    require_patch_range bytes ~offset:offsets.encode_ns ~width:8 ~label:"encode duration";
    require_patch_range bytes ~offset:offsets.patch_bytes ~width:4 ~label:"patch bytes";
    patch_u64 bytes offsets.encode_ns encode_ns;
    patch_u32 bytes offsets.patch_bytes patch_bytes;
    Ok ()
  with
  | Codec_error error -> Error error
;;

module Reader = struct
  type t =
    { bytes : bytes
    ; mutable position : int
    ; limit : int
    }

  let create ?limit bytes =
    { bytes; position = 0; limit = Option.value limit ~default:(Bytes.length bytes) }
  ;;

  let remaining reader = reader.limit - reader.position

  let require reader count =
    if count < 0 || count > remaining reader
    then fail Truncated_input "need %d bytes, only %d remain" count (remaining reader)
  ;;

  let u8 reader =
    require reader 1;
    let value = Char.code (Bytes.get reader.bytes reader.position) in
    reader.position <- reader.position + 1;
    value
  ;;

  let u16 reader =
    let byte0 = u8 reader in
    let byte1 = u8 reader in
    byte0 lor (byte1 lsl 8)
  ;;

  let u32 reader =
    let byte0 = u8 reader in
    let byte1 = u8 reader in
    let byte2 = u8 reader in
    let byte3 = u8 reader in
    byte0 lor (byte1 lsl 8) lor (byte2 lsl 16) lor (byte3 lsl 24)
  ;;

  let u64 reader =
    let result = ref 0L in
    for shift = 0 to 7 do
      result
      := Int64.logor !result (Int64.shift_left (Int64.of_int (u8 reader)) (shift * 8))
    done;
    !result
  ;;

  let f64 reader = Int64.float_of_bits (u64 reader)

  let sub_reader reader length =
    require reader length;
    let result =
      { bytes = reader.bytes
      ; position = reader.position
      ; limit = reader.position + length
      }
    in
    reader.position <- reader.position + length;
    result
  ;;

  let string reader length =
    require reader length;
    let result = Bytes.sub_string reader.bytes reader.position length in
    reader.position <- reader.position + length;
    result
  ;;

  let bytes reader length =
    require reader length;
    let result = Bytes.sub reader.bytes reader.position length in
    reader.position <- reader.position + length;
    result
  ;;
end

let validate_utf8 value =
  let length = String.length value in
  let continuation index =
    index < length
    &&
    let byte = Char.code value.[index] in
    byte land 0xc0 = 0x80
  in
  let rec loop index =
    if index = length
    then true
    else (
      let byte = Char.code value.[index] in
      if byte <= 0x7f
      then loop (index + 1)
      else if byte >= 0xc2 && byte <= 0xdf
      then continuation (index + 1) && loop (index + 2)
      else if byte = 0xe0
      then
        index + 2 < length
        && Char.code value.[index + 1] >= 0xa0
        && Char.code value.[index + 1] <= 0xbf
        && continuation (index + 2)
        && loop (index + 3)
      else if (byte >= 0xe1 && byte <= 0xec) || (byte >= 0xee && byte <= 0xef)
      then continuation (index + 1) && continuation (index + 2) && loop (index + 3)
      else if byte = 0xed
      then
        index + 2 < length
        && Char.code value.[index + 1] >= 0x80
        && Char.code value.[index + 1] <= 0x9f
        && continuation (index + 2)
        && loop (index + 3)
      else if byte = 0xf0
      then
        index + 3 < length
        && Char.code value.[index + 1] >= 0x90
        && Char.code value.[index + 1] <= 0xbf
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if byte >= 0xf1 && byte <= 0xf3
      then
        continuation (index + 1)
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if byte = 0xf4
      then
        index + 3 < length
        && Char.code value.[index + 1] >= 0x80
        && Char.code value.[index + 1] <= 0x8f
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else false)
  in
  loop 0
;;

let read_string reader =
  let length = Reader.u32 reader in
  if length < 0 then fail Truncated_input "negative string length";
  if length > Generated_protocol.Limits.max_string_bytes
  then fail String_too_large "string is %d bytes" length;
  let value = Reader.string reader length in
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  value
;;

let read_bool reader =
  match Reader.u8 reader with
  | 0 -> false
  | 1 -> true
  | value -> fail Invalid_props "invalid bool %d" value
;;

let read_optional_string reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_string reader)
  | value -> fail Invalid_props "invalid optional string tag %d" value
;;

let read_optional_bool reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some false
  | 2 -> Some true
  | value -> fail Invalid_props "invalid optional bool tag %d" value
;;

let read_finite_f64 reader =
  let value = Reader.f64 reader in
  match Float.classify_float value with
  | FP_normal | FP_subnormal | FP_zero -> value
  | FP_infinite | FP_nan -> fail Invalid_props "float property must be finite"
;;

let read_optional_f64 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_finite_f64 reader)
  | value ->
    fail
      Invalid_props
      "invalid optional float tag %d at byte %d"
      value
      (reader.Reader.position - 1)
;;

let read_optional_u8 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (Reader.u8 reader)
  | value -> fail Invalid_props "invalid optional u8 tag %d" value
;;

let read_optional_argb32 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (Int32.of_int (Reader.u32 reader))
  | value -> fail Invalid_props "invalid optional ARGB tag %d" value
;;

let read_positive_optional_f64 reader label =
  match read_optional_f64 reader with
  | None -> None
  | Some value ->
    if Float.compare value 0. <= 0 then fail Invalid_props "%s must be positive" label;
    Some value
;;

let read_text_style reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 ->
    let font_size = read_positive_optional_f64 reader "text font size" in
    let font_weight =
      match Reader.u8 reader with
      | 0 -> None
      | 1 ->
        Some
          (match Reader.u8 reader with
           | 0 -> Wire_frame.Normal
           | 1 -> Medium
           | 2 -> Semi_bold
           | 3 -> Bold
           | value -> fail Invalid_props "invalid text font weight %d" value)
      | value -> fail Invalid_props "invalid optional text font weight tag %d" value
    in
    let line_height = read_positive_optional_f64 reader "text line height" in
    let color = read_optional_argb32 reader in
    Some Wire_frame.{ font_size; font_weight; line_height; color }
  | value -> fail Invalid_props "invalid optional text style tag %d" value
;;

let read_text_align reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Start
  | 1 -> Center_text
  | 2 -> End
  | value -> fail Invalid_props "invalid text alignment %d" value
;;

let read_optional_positive_u32 reader label =
  match Reader.u8 reader with
  | 0 -> None
  | 1 ->
    let value = Reader.u32 reader in
    if value = 0 then fail Invalid_props "%s must be positive" label;
    Some value
  | value -> fail Invalid_props "invalid optional u32 tag %d" value
;;

let read_text_overflow reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Clip_text
  | 1 -> Fade
  | 2 -> Ellipsis
  | 3 -> Visible
  | value -> fail Invalid_props "invalid text overflow %d" value
;;

let styled_text_protocol_minor = 13

let read_text_props reader ~protocol_minor =
  let value = read_string reader in
  if protocol_minor < styled_text_protocol_minor
  then
    Wire_frame.
      { value; style = None; text_align = Start; max_lines = None; overflow = Clip_text }
  else (
    let style = read_text_style reader in
    let text_align = read_text_align reader in
    let max_lines = read_optional_positive_u32 reader "text max lines" in
    let overflow = read_text_overflow reader in
    Wire_frame.{ value; style; text_align; max_lines; overflow })
;;

let read_animation reader =
  let id_value = Reader.u64 reader in
  if Int64.compare id_value 0L < 0
  then fail Invalid_props "animation id must be non-negative";
  let id = ID.Ui.Animation_id.of_int64 id_value in
  let duration_ms = Reader.u32 reader in
  let curve =
    match Reader.u8 reader with
    | 0 -> Wire_frame.Linear
    | 1 -> Ease_in
    | 2 -> Ease_out
    | 3 -> Ease_in_out
    | value -> fail Invalid_props "invalid animation curve %d" value
  in
  { id; duration_ms; curve }
;;

let read_sparse_extent_curve reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Se_linear
  | 1 -> Se_ease_in
  | 2 -> Se_ease_out
  | 3 -> Se_ease_in_out
  | 4 -> Se_ease_out_cubic
  | 5 -> Se_ease_in_out_cubic
  | value -> fail Invalid_props "invalid sparse extent curve %d" value
;;

let read_optional_sparse_extent_curve reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_sparse_extent_curve reader)
  | value -> fail Invalid_props "invalid optional curve tag %d" value
;;

let read_optional_duration_ms reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (Reader.u32 reader)
  | value -> fail Invalid_props "invalid optional duration tag %d" value
;;

let read_sliver_extent_overrides reader ~total_count =
  let count = Reader.u32 reader in
  if count < 0 || count > total_count
  then fail Invalid_props "sliver override count is out of range";
  let rec read remaining =
    if remaining = 0
    then []
    else (
      let index64 = Reader.u64 reader in
      if Int64.compare index64 0L < 0
      then fail Invalid_props "sliver override index is negative";
      if Int64.compare index64 (Int64.of_int max_int) > 0
      then fail Invalid_props "sliver override index exceeds OCaml int";
      let index = Int64.to_int index64 in
      let extent = read_finite_f64 reader in
      { Wire_frame.index; extent } :: read (remaining - 1))
  in
  let overrides = read count in
  validate_sliver_extent_overrides ~total_count overrides;
  overrides
;;

let read_sliver_varied_extent_transition reader =
  let enabled = read_optional_bool reader in
  let expand_duration_ms = read_optional_duration_ms reader in
  let collapse_duration_ms = read_optional_duration_ms reader in
  let expand_curve = read_optional_sparse_extent_curve reader in
  let collapse_curve = read_optional_sparse_extent_curve reader in
  match
    enabled, expand_duration_ms, collapse_duration_ms, expand_curve, collapse_curve
  with
  | None, None, None, None, None -> None
  | ( Some enabled
    , Some expand_duration_ms
    , Some collapse_duration_ms
    , Some expand_curve
    , Some collapse_curve ) ->
    Some
      Wire_frame.
        { enabled
        ; expand_duration_ms
        ; collapse_duration_ms
        ; expand_curve
        ; collapse_curve
        }
  | _ -> fail Invalid_props "sliver transition fields must be all-present or all-absent"
;;

let read_semantics_role reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Generic
  | 1 -> Semantics_button
  | 2 -> Link
  | 3 -> Image
  | 4 -> Header
  | 5 -> Text_field
  | 6 -> Checkbox
  | 7 -> Switch
  | 8 -> Slider
  | value -> fail Invalid_props "invalid semantics role %d" value
;;

let read_node_kind reader =
  match Reader.u16 reader |> ID.Protocol.Node_kind.of_int with
  | value when value = Generated_protocol.Node_kind.empty -> Wire_frame.Empty
  | value when value = Generated_protocol.Node_kind.text -> Text
  | value when value = Generated_protocol.Node_kind.rich_text -> Rich_text
  | value when value = Generated_protocol.Node_kind.icon -> Icon
  | value when value = Generated_protocol.Node_kind.image -> Image
  | value when value = Generated_protocol.Node_kind.row -> Row
  | value when value = Generated_protocol.Node_kind.column -> Column
  | value when value = Generated_protocol.Node_kind.stack -> Stack
  | value when value = Generated_protocol.Node_kind.button -> Button
  | value when value = Generated_protocol.Node_kind.padding -> Padding
  | value when value = Generated_protocol.Node_kind.align -> Align
  | value when value = Generated_protocol.Node_kind.center -> Center
  | value when value = Generated_protocol.Node_kind.sized_box -> Sized_box
  | value when value = Generated_protocol.Node_kind.constrained_box -> Constrained_box
  | value when value = Generated_protocol.Node_kind.decorated_box -> Decorated_box
  | value when value = Generated_protocol.Node_kind.clip -> Clip
  | value when value = Generated_protocol.Node_kind.opacity -> Opacity
  | value when value = Generated_protocol.Node_kind.animated_opacity -> Animated_opacity
  | value when value = Generated_protocol.Node_kind.transform -> Transform
  | value when value = Generated_protocol.Node_kind.scroll_view -> Scroll_view
  | value when value = Generated_protocol.Node_kind.sliver_box -> Sliver_box
  | value when value = Generated_protocol.Node_kind.sliver_list -> Sliver_list
  | value when value = Generated_protocol.Node_kind.sliver_fill -> Sliver_fill
  | value when value = Generated_protocol.Node_kind.sliver_fixed_extent ->
    Sliver_fixed_extent
  | value when value = Generated_protocol.Node_kind.sliver_varied_extent ->
    Sliver_varied_extent
  | value when value = Generated_protocol.Node_kind.sliver_padding -> Sliver_padding
  | value when value = Generated_protocol.Node_kind.sliver_app_bar -> Sliver_app_bar
  | value when value = Generated_protocol.Node_kind.preferred_size -> Preferred_size
  | value when value = Generated_protocol.Node_kind.gesture -> Gesture
  | value when value = Generated_protocol.Node_kind.focus_scope -> Focus_scope
  | value when value = Generated_protocol.Node_kind.mouse_region -> Mouse_region
  | value when value = Generated_protocol.Node_kind.keyboard_listener -> Keyboard_listener
  | value when value = Generated_protocol.Node_kind.pressable -> Pressable
  | value when value = Generated_protocol.Node_kind.semantics -> Semantics
  | value when value = Generated_protocol.Node_kind.theme -> Theme
  | value when value = Generated_protocol.Node_kind.material_scaffold -> Material_scaffold
  | value when value = Generated_protocol.Node_kind.material_app_bar -> Material_app_bar
  | value when value = Generated_protocol.Node_kind.material_elevated_button ->
    Material_elevated_button
  | value when value = Generated_protocol.Node_kind.material_text_button ->
    Material_text_button
  | value when value = Generated_protocol.Node_kind.material_icon_button ->
    Material_icon_button
  | value when value = Generated_protocol.Node_kind.material_checkbox -> Material_checkbox
  | value when value = Generated_protocol.Node_kind.material_switch -> Material_switch
  | value when value = Generated_protocol.Node_kind.material_list_tile ->
    Material_list_tile
  | value when value = Generated_protocol.Node_kind.material_divider -> Material_divider
  | value when value = Generated_protocol.Node_kind.material_card -> Material_card
  | value when value = Generated_protocol.Node_kind.material_circular_progress_indicator
    -> Material_circular_progress_indicator
  | value when value = Generated_protocol.Node_kind.cupertino_button -> Cupertino_button
  | value when value = Generated_protocol.Node_kind.cupertino_switch -> Cupertino_switch
  | value when value = Generated_protocol.Node_kind.text_input -> Text_input
  | value when value = Generated_protocol.Node_kind.overlay -> Overlay
  | value when value = Generated_protocol.Node_kind.navigator -> Navigator
  | value when value = Generated_protocol.Node_kind.page -> Page
  | value when value = Generated_protocol.Node_kind.safe_area -> Safe_area
  | value when value = Generated_protocol.Node_kind.environment_boundary ->
    Environment_boundary
  | value when value = Generated_protocol.Node_kind.material_dialog -> Material_dialog
  | value when value = Generated_protocol.Node_kind.native_widget -> Native_widget
  | value ->
    fail Unknown_node_kind "unknown node kind %d" (ID.Protocol.Node_kind.to_int value)
;;

let read_props reader kind ~protocol_minor =
  match kind with
  | Wire_frame.Empty | Stack -> Empty_props
  | Environment_boundary -> Environment_boundary_props
  | Sliver_box -> Sliver_box_props
  | Sliver_list -> Sliver_list_props
  | Text -> Text_props (read_text_props reader ~protocol_minor)
  | Rich_text ->
    Rich_text_props
      { spans = List.init (Reader.u16 reader) (fun _ -> read_string reader) }
  | Icon ->
    let code_point = Reader.u32 reader in
    if code_point > 0x10ffff || (code_point >= 0xd800 && code_point <= 0xdfff)
    then fail Invalid_props "icon code point is not a Unicode scalar";
    let font_family = read_optional_string reader in
    let size = read_optional_f64 reader in
    let color = read_optional_argb32 reader in
    Icon_props { code_point; font_family; size; color }
  | Image ->
    let uri = read_string reader in
    if String.length uri = 0 then fail Invalid_props "image URI must not be empty";
    let fit =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Fill
      | 1 -> Contain
      | 2 -> Cover
      | 3 -> Fit_width
      | 4 -> Fit_height
      | 5 -> No_fit
      | 6 -> Scale_down
      | value -> fail Invalid_props "invalid image fit %d" value
    in
    let width = read_optional_f64 reader in
    let height = read_optional_f64 reader in
    Image_props { uri; fit; width; height }
  | Row | Column -> Linear_props
  | Button -> Button_props { enabled = read_bool reader }
  | Pressable ->
    let overlay_color_argb = Int32.of_int (Reader.u32 reader) in
    let release_delay_ms = Reader.u16 reader in
    if release_delay_ms > 100
    then fail Invalid_props "pressable release delay must be in 0..100ms";
    Pressable_props { overlay_color_argb; release_delay_ms }
  | Padding ->
    let left = read_finite_f64 reader in
    let top = read_finite_f64 reader in
    let right = read_finite_f64 reader in
    let bottom = read_finite_f64 reader in
    Padding_props { left; top; right; bottom }
  | Align ->
    let alignment : Wire_frame.alignment =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Top_start
      | 1 -> Top_center
      | 2 -> Top_end
      | 3 -> Center_start
      | 4 -> Center
      | 5 -> Center_end
      | 6 -> Bottom_start
      | 7 -> Bottom_center
      | 8 -> Bottom_end
      | value -> fail Invalid_props "invalid alignment %d" value
    in
    Align_props { alignment }
  | Center ->
    let width_factor = read_optional_f64 reader in
    let height_factor = read_optional_f64 reader in
    Center_props { width_factor; height_factor }
  | Sized_box ->
    let width = read_optional_f64 reader in
    let height = read_optional_f64 reader in
    Sized_box_props { width; height }
  | Constrained_box ->
    let min_width = read_finite_f64 reader in
    let max_width = read_finite_f64 reader in
    let min_height = read_finite_f64 reader in
    let max_height = read_finite_f64 reader in
    if
      Float.compare min_width 0. < 0
      || Float.compare min_height 0. < 0
      || Float.compare min_width max_width > 0
      || Float.compare min_height max_height > 0
    then fail Invalid_props "invalid box constraints";
    Constrained_box_props { min_width; max_width; min_height; max_height }
  | Decorated_box ->
    let background = read_optional_argb32 reader in
    let border_radius = read_finite_f64 reader in
    if Float.compare border_radius 0. < 0
    then fail Invalid_props "border radius must be non-negative";
    Decorated_box_props { background; border_radius }
  | Clip ->
    let behavior =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Hard_edge
      | 1 -> Anti_alias
      | 2 -> Anti_alias_with_save_layer
      | value -> fail Invalid_props "invalid clip behavior %d" value
    in
    Clip_props { behavior }
  | Opacity ->
    let opacity = read_finite_f64 reader in
    if Float.compare opacity 0. < 0 || Float.compare opacity 1. > 0
    then fail Invalid_props "opacity must be in 0..1";
    Opacity_props { opacity }
  | Animated_opacity ->
    let opacity = read_finite_f64 reader in
    if Float.compare opacity 0. < 0 || Float.compare opacity 1. > 0
    then fail Invalid_props "animated opacity must be in 0..1";
    Animated_opacity_props { opacity; animation = read_animation reader }
  | Transform ->
    Transform_props { matrix4 = Array.init 16 (fun _ -> read_finite_f64 reader) }
  | Scroll_view ->
    let axis =
      match Reader.u8 reader with
      | 0 -> Horizontal
      | 1 -> Vertical
      | value -> fail Invalid_props "invalid scroll axis %d" value
    in
    let reverse = read_bool reader in
    let primary = read_bool reader in
    if axis = Horizontal && primary
    then fail Invalid_props "horizontal scroll view cannot be primary";
    let cache_extent = read_optional_f64 reader in
    validate_cache_extent cache_extent;
    Scroll_view_props { axis; reverse; primary; cache_extent }
  | Sliver_fill -> Sliver_fill_props
  | Sliver_fixed_extent ->
    let total_count64 = Reader.u64 reader in
    if Int64.compare total_count64 (Int64.of_int max_int) > 0
    then fail Invalid_props "sliver total_count exceeds OCaml int";
    let total_count = Int64.to_int total_count64 in
    let first_index64 = Reader.u64 reader in
    if Int64.compare first_index64 (Int64.of_int max_int) > 0
    then fail Invalid_props "sliver first_index exceeds OCaml int";
    let first_index = Int64.to_int first_index64 in
    let item_extent = read_finite_f64 reader in
    if Float.compare item_extent 0. <= 0
    then fail Invalid_props "sliver item_extent must be finite and positive";
    let overscan = Reader.u32 reader in
    validate_sliver_window ~total_count ~first_index;
    Sliver_fixed_extent_props { total_count; first_index; item_extent; overscan }
  | Sliver_varied_extent ->
    let total_count64 = Reader.u64 reader in
    if Int64.compare total_count64 (Int64.of_int max_int) > 0
    then fail Invalid_props "sliver total_count exceeds OCaml int";
    let total_count = Int64.to_int total_count64 in
    let first_index64 = Reader.u64 reader in
    if Int64.compare first_index64 (Int64.of_int max_int) > 0
    then fail Invalid_props "sliver first_index exceeds OCaml int";
    let first_index = Int64.to_int first_index64 in
    let default_item_extent = read_finite_f64 reader in
    if Float.compare default_item_extent 0. <= 0
    then fail Invalid_props "sliver default_item_extent must be finite and positive";
    let overscan = Reader.u32 reader in
    let extent_overrides = read_sliver_extent_overrides reader ~total_count in
    let transition = read_sliver_varied_extent_transition reader in
    validate_sliver_window ~total_count ~first_index;
    Sliver_varied_extent_props
      { total_count
      ; first_index
      ; default_item_extent
      ; overscan
      ; extent_overrides
      ; transition
      }
  | Sliver_padding ->
    let left = read_finite_f64 reader in
    let top = read_finite_f64 reader in
    let right = read_finite_f64 reader in
    let bottom = read_finite_f64 reader in
    Sliver_padding_props { left; top; right; bottom }
  | Sliver_app_bar ->
    let pinned = read_bool reader in
    let expanded_height = read_optional_f64 reader in
    let collapsed_height = read_optional_f64 reader in
    let floating = read_bool reader in
    let snap = read_bool reader in
    let stretch = read_bool reader in
    let toolbar_height = read_finite_f64 reader in
    let has_leading = read_bool reader in
    let has_flexible_space = read_bool reader in
    let has_bottom = read_bool reader in
    let has_actions = read_bool reader in
    let force_elevated = read_bool reader in
    let automatically_imply_leading = read_bool reader in
    let center_title = read_optional_bool reader in
    let background_color = read_optional_argb32 reader in
    let foreground_color = read_optional_argb32 reader in
    let elevation = read_optional_f64 reader in
    validate_sliver_app_bar
      ~expanded_height
      ~collapsed_height
      ~floating
      ~snap
      ~toolbar_height
      ~elevation;
    Sliver_app_bar_props
      { pinned
      ; expanded_height
      ; collapsed_height
      ; floating
      ; snap
      ; stretch
      ; toolbar_height
      ; has_leading
      ; has_flexible_space
      ; has_bottom
      ; has_actions
      ; force_elevated
      ; automatically_imply_leading
      ; center_title
      ; background_color
      ; foreground_color
      ; elevation
      }
  | Preferred_size ->
    let height = read_finite_f64 reader in
    if Float.compare height 0. <= 0
    then fail Invalid_props "preferred_size height must be positive";
    Preferred_size_props { height }
  | Gesture -> Gesture_props
  | Focus_scope -> Focus_scope_props { autofocus = read_bool reader }
  | Mouse_region -> Mouse_region_props { opaque = read_bool reader }
  | Keyboard_listener ->
    let autofocus = read_bool reader in
    let key_policy =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Handled
      | 1 -> Ignored
      | value -> fail Invalid_props "invalid key policy %d" value
    in
    Keyboard_listener_props { autofocus; key_policy }
  | Semantics ->
    let label = read_optional_string reader in
    let hint = read_optional_string reader in
    let value = read_optional_string reader in
    let role = read_semantics_role reader in
    let enabled = read_optional_bool reader in
    let selected = read_optional_bool reader in
    let checked = read_optional_bool reader in
    let focusable = read_optional_bool reader in
    let obscured = read_bool reader in
    let live_region = read_bool reader in
    let heading_level = read_optional_u8 reader in
    Option.iter
      (fun level ->
         if level < 1 || level > 6
         then fail Invalid_props "semantics heading level must be between 1 and 6")
      heading_level;
    let sort_key = read_optional_f64 reader in
    let actions = Reader.u32 reader in
    if actions land lnot 0x1ff <> 0
    then fail Invalid_props "semantics actions contain unknown bits";
    Semantics_props
      { label
      ; hint
      ; value
      ; role
      ; enabled
      ; selected
      ; checked
      ; focusable
      ; obscured
      ; live_region
      ; heading_level
      ; sort_key
      ; actions
      }
  | Theme ->
    let brightness =
      match Reader.u8 reader with
      | 0 -> Light
      | 1 -> Dark
      | value -> fail Invalid_props "invalid brightness %d" value
    in
    Theme_props { brightness; color_seed = Int32.of_int (Reader.u32 reader) }
  | Material_scaffold -> Material_scaffold_props { has_app_bar = read_bool reader }
  | Material_app_bar -> Material_app_bar_props { center_title = read_bool reader }
  | Material_elevated_button ->
    Material_button_props
      { variant = Elevated; enabled = read_bool reader; autofocus = read_bool reader }
  | Material_text_button ->
    Material_button_props
      { variant = Text_button; enabled = read_bool reader; autofocus = read_bool reader }
  | Material_icon_button ->
    Material_button_props
      { variant = Icon_button; enabled = read_bool reader; autofocus = read_bool reader }
  | Material_checkbox ->
    let value = read_bool reader in
    let enabled = read_bool reader in
    Material_checkbox_props { value; enabled }
  | Material_switch ->
    let value = read_bool reader in
    let enabled = read_bool reader in
    Material_switch_props { value; enabled }
  | Material_list_tile ->
    Material_list_tile_props
      { enabled = read_bool reader
      ; selected = read_bool reader
      ; has_subtitle = read_bool reader
      ; has_leading = read_bool reader
      ; has_trailing = read_bool reader
      }
  | Material_divider -> Material_divider_props { thickness = read_finite_f64 reader }
  | Material_card -> Material_card_props { elevation = read_finite_f64 reader }
  | Material_circular_progress_indicator ->
    Material_progress_props { value = read_optional_f64 reader }
  | Cupertino_button -> Cupertino_button_props { enabled = read_bool reader }
  | Cupertino_switch ->
    Cupertino_switch_props { value = read_bool reader; enabled = read_bool reader }
  | Text_input ->
    let session_id = Reader.u64 reader |> ID.Text_input.Session_id.of_int64 in
    let document_revision =
      Reader.u64 reader |> ID.Text_input.Document_revision.of_int64
    in
    let text = read_string reader in
    let read_text_range () =
      let start_utf16 = Reader.u32 reader in
      let end_utf16 = Reader.u32 reader in
      if start_utf16 > end_utf16 then fail Invalid_props "text range is reversed";
      let range = Wire_frame.{ start_utf16; end_utf16 } in
      validate_text_range text range;
      range
    in
    let selection = read_text_range () in
    let composing =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (read_text_range ())
      | value -> fail Invalid_props "invalid composing tag %d" value
    in
    let enabled = read_bool reader in
    let read_only = read_bool reader in
    let obscure_text = read_bool reader in
    let keyboard_type =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Keyboard_text
      | 1 -> Keyboard_multiline
      | 2 -> Keyboard_number
      | 3 -> Keyboard_email
      | 4 -> Keyboard_phone
      | 5 -> Keyboard_url
      | value -> fail Invalid_props "invalid keyboard type %d" value
    in
    let input_action =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Done
      | 1 -> Newline
      | 2 -> Next
      | 3 -> Previous
      | 4 -> Search
      | 5 -> Send
      | 6 -> Go
      | value -> fail Invalid_props "invalid text input action %d" value
    in
    let accepted_local_revision =
      Reader.u64 reader |> ID.Text_input.Local_revision.of_int64
    in
    let update_mode =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Ack
      | 1 -> Correction
      | 2 -> Force_replace
      | value -> fail Invalid_props "invalid text update mode %d" value
    in
    let autofocus = read_bool reader in
    let max_utf8_bytes = read_optional_positive_u32 reader "text input max UTF-8 bytes" in
    (match max_utf8_bytes with
     | Some value when value > Generated_protocol.Limits.max_string_bytes ->
       fail Invalid_props "text input max UTF-8 bytes exceeds the protocol string limit"
     | None | Some _ -> ());
    Text_input_props
      { session_id
      ; document_revision
      ; value = { text; selection; composing }
      ; enabled
      ; read_only
      ; obscure_text
      ; keyboard_type
      ; input_action
      ; accepted_local_revision
      ; update_mode
      ; autofocus
      ; max_utf8_bytes
      }
  | Overlay ->
    let alignment =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Top_start
      | 1 -> Top_center
      | 2 -> Top_end
      | 3 -> Center_start
      | 4 -> Center
      | 5 -> Center_end
      | 6 -> Bottom_start
      | 7 -> Bottom_center
      | 8 -> Bottom_end
      | value -> fail Invalid_props "invalid overlay alignment %d" value
    in
    Overlay_props { alignment; dismissible = read_bool reader }
  | Navigator ->
    Navigator_props
      { restoration_scope_id =
          Option.map
            ID.Navigation.Restoration_scope_id.of_string
            (read_optional_string reader)
      }
  | Page ->
    let page_key_value = read_string reader in
    if String.length page_key_value = 0
    then fail Invalid_props "page key must not be empty";
    let page_key = ID.Navigation.Page_key.of_string page_key_value in
    let transition =
      match Reader.u8 reader with
      | 0 -> Wire_frame.No_transition
      | 1 -> Fade
      | 2 -> Slide
      | value -> fail Invalid_props "invalid page transition %d" value
    in
    let can_pop = read_bool reader in
    let restoration_id =
      Option.map ID.Navigation.Restoration_id.of_string (read_optional_string reader)
    in
    let presentation_kind = Reader.u8 reader in
    let barrier_dismissible = read_bool reader in
    let barrier_color_argb = read_optional_argb32 reader in
    let barrier_label = read_optional_string reader in
    let sizing_kind = Reader.u8 reader in
    let use_safe_area = read_bool reader in
    let request_focus = read_bool reader in
    let transition_duration_ms = Reader.u32 reader in
    let reverse_transition_duration_ms = Reader.u32 reader in
    let detents =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Medium_only
      | 1 -> Large_only
      | 2 -> Medium_and_large
      | value -> fail Invalid_props "invalid modal detent set %d" value
    in
    let initial_detent =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Medium_detent
      | 1 -> Large_detent
      | value -> fail Invalid_props "invalid modal initial detent %d" value
    in
    let dismiss_on_drag = read_bool reader in
    let handle_semantics_label = read_optional_string reader in
    let medium_semantics_value = read_optional_string reader in
    let large_semantics_value = read_optional_string reader in
    let presentation =
      match presentation_kind with
      | 0 ->
        if
          barrier_dismissible
          || Option.is_some barrier_color_argb
          || Option.is_some barrier_label
          || sizing_kind <> 0
          || use_safe_area
          || request_focus
          || transition_duration_ms <> 0
          || reverse_transition_duration_ms <> 0
          || detents <> Wire_frame.Medium_only
          || initial_detent <> Wire_frame.Medium_detent
          || dismiss_on_drag
          || Option.is_some handle_semantics_label
          || Option.is_some medium_semantics_value
          || Option.is_some large_semantics_value
        then fail Invalid_props "standard page has noncanonical modal properties";
        Wire_frame.Standard_page transition
      | 1 ->
        if transition <> Wire_frame.No_transition
        then fail Invalid_props "modal bottom sheet cannot carry a standard transition";
        let sizing =
          match sizing_kind with
          | 0 -> Wire_frame.Content_bounded_sizing
          | 1 -> Scroll_controlled_sizing
          | 2 ->
            if not (detent_is_in_set initial_detent detents)
            then fail Invalid_props "modal initial detent must belong to detents";
            let require_some name = function
              | Some value ->
                require_nonempty_modal_string name value;
                value
              | None -> fail Invalid_props "detented modal must include %s" name
            in
            Detented_sizing
              { detents
              ; initial_detent
              ; dismiss_on_drag
              ; handle_semantics_label =
                  require_some "handle semantics label" handle_semantics_label
              ; medium_semantics_value =
                  require_some "medium semantics value" medium_semantics_value
              ; large_semantics_value =
                  require_some "large semantics value" large_semantics_value
              }
          | value -> fail Invalid_props "invalid modal sizing %d" value
        in
        (match sizing with
         | Wire_frame.Detented_sizing _ -> ()
         | Content_bounded_sizing | Scroll_controlled_sizing ->
           if
             detents <> Wire_frame.Medium_only
             || initial_detent <> Wire_frame.Medium_detent
             || dismiss_on_drag
             || Option.is_some handle_semantics_label
             || Option.is_some medium_semantics_value
             || Option.is_some large_semantics_value
           then fail Invalid_props "non-detented modal has noncanonical detent properties");
        Modal_bottom_sheet
          { barrier_dismissible
          ; barrier_color_argb
          ; barrier_label
          ; sizing
          ; use_safe_area
          ; request_focus
          ; transition_duration_ms
          ; reverse_transition_duration_ms
          }
      | value -> fail Invalid_props "invalid page presentation %d" value
    in
    Page_props { page_key; presentation; can_pop; restoration_id }
  | Safe_area ->
    Safe_area_props
      { left = read_bool reader
      ; top = read_bool reader
      ; right = read_bool reader
      ; bottom = read_bool reader
      ; minimum_left = read_finite_f64 reader
      ; minimum_top = read_finite_f64 reader
      ; minimum_right = read_finite_f64 reader
      ; minimum_bottom = read_finite_f64 reader
      }
  | Material_dialog -> Material_dialog_props { barrier_dismissible = read_bool reader }
  | Native_widget ->
    let kind_id_value = Reader.u32 reader in
    let version = Reader.u16 reader in
    if kind_id_value = 0 then fail Invalid_props "native widget kind ID must be positive";
    if version = 0 then fail Invalid_props "native widget version must be positive";
    let capabilities = Reader.u64 reader in
    let payload_length = Reader.u32 reader in
    if payload_length < 0
    then fail Truncated_input "negative native widget payload length";
    let payload = Reader.bytes reader payload_length in
    let kind_id = ID.Native_widget.Kind_id.of_int kind_id_value in
    Native_widget_props { kind_id; version; capabilities; payload }
;;

let read_update_props reader ~protocol_minor =
  let kind = read_node_kind reader in
  let changed = Reader.u64 reader in
  let props = read_props reader kind ~protocol_minor in
  let expected =
    match props with
    | Wire_frame.Text_props _ when protocol_minor < styled_text_protocol_minor ->
      field_mask Generated_protocol.Text_prop.value
    | _ -> changed_fields props
  in
  if changed <> expected then fail Invalid_props "unsupported changed-field bitset";
  props
;;

let read_bindings reader =
  let count = Reader.u16 reader in
  List.init count (fun _ ->
    let event_tag = Reader.u16 reader |> ID.Protocol.Event_tag.of_int in
    let handler_id = Reader.u64 reader |> ID.Ui.Handler_id.of_int64 in
    Wire_frame.{ event_tag; handler_id })
;;

let read_bytes reader =
  let length = Reader.u32 reader in
  if length < 0 then fail Truncated_input "negative byte payload length";
  Reader.bytes reader length
;;

let read_string_list reader =
  let count = Reader.u16 reader in
  List.init count (fun _ -> read_string reader)
;;

let read_host_request body request_id request_kind =
  let open Wire_frame in
  let payload =
    if request_kind = Generated_protocol.Host_request.clipboard_read
    then Clipboard_read
    else if request_kind = Generated_protocol.Host_request.clipboard_write
    then Clipboard_write { text = read_string body }
    else if request_kind = Generated_protocol.Host_request.open_url
    then Open_url { uri = read_string body }
    else if request_kind = Generated_protocol.Host_request.pick_file
    then (
      let allowed_extensions = read_string_list body in
      let allow_multiple = read_bool body in
      Pick_file { allowed_extensions; allow_multiple })
    else if request_kind = Generated_protocol.Host_request.save_file
    then (
      let suggested_name = read_optional_string body in
      let data = read_bytes body in
      Save_file { suggested_name; data })
    else if request_kind = Generated_protocol.Host_request.request_focus
    then Request_focus { node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 }
    else if request_kind = Generated_protocol.Host_request.clear_focus
    then Clear_focus
    else if request_kind = Generated_protocol.Host_request.scroll_to
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let alignment = read_finite_f64 body in
      let animated = read_bool body in
      Scroll_to { node_id; alignment; animated })
    else if request_kind = Generated_protocol.Host_request.set_window_title
    then Set_window_title { title = read_string body }
    else if request_kind = Generated_protocol.Host_request.set_window_size
    then (
      let width = read_finite_f64 body in
      let height = read_finite_f64 body in
      Set_window_size { width; height })
    else if request_kind = Generated_protocol.Host_request.show_native_menu
    then (
      let count = Reader.u16 body in
      Show_native_menu
        { items =
            List.init count (fun _ ->
              let item_id = read_string body |> ID.Host.Native_menu_item_id.of_string in
              let label = read_string body in
              let enabled = read_bool body in
              { item_id; label; enabled })
        })
    else if request_kind = Generated_protocol.Host_request.haptic_feedback
    then
      Haptic_feedback
        (match Reader.u8 body with
         | 0 -> Haptic_light
         | 1 -> Haptic_medium
         | 2 -> Haptic_heavy
         | 3 -> Haptic_selection
         | value -> fail Invalid_props "invalid haptic kind %d" value)
    else if request_kind = Generated_protocol.Host_request.platform_information
    then Platform_information
    else if request_kind = Generated_protocol.Host_request.measure_layout
    then Measure_layout { node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 }
    else
      fail
        Invalid_props
        "unknown host request kind %d"
        (ID.Protocol.Host_request_kind.to_int request_kind)
  in
  Host_request { request_id; payload }
;;

let require_empty reader =
  if Reader.remaining reader <> 0
  then
    fail Trailing_bytes "operation body has %d trailing bytes" (Reader.remaining reader)
;;

let read_parent_data reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.No_parent_data
  | 1 ->
    let flex = Reader.u32 reader in
    if flex = 0 then fail Invalid_props "flex factor must be positive";
    Flex_parent_data { flex; fit = Loose }
  | 2 ->
    let flex = Reader.u32 reader in
    if flex = 0 then fail Invalid_props "flex factor must be positive";
    Flex_parent_data { flex; fit = Tight }
  | 3 ->
    Stack_position
      { left = read_optional_f64 reader
      ; top = read_optional_f64 reader
      ; right = read_optional_f64 reader
      ; bottom = read_optional_f64 reader
      }
  | value -> fail Invalid_props "invalid parent-data tag %d" value
;;

let read_operation opcode body ~protocol_minor =
  let open Wire_frame in
  let operation =
    if opcode = Generated_protocol.Operation.create_node
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let kind = read_node_kind body in
      let props =
        try read_props body kind ~protocol_minor with
        | Codec_error error ->
          fail
            error.code
            "node %Ld kind %d: %s"
            (ID.Ui.Node_id.to_int64 node_id)
            (ID.Protocol.Node_kind.to_int (node_kind_id kind))
            error.message
      in
      let event_bindings = read_bindings body in
      let parent_data = read_parent_data body in
      Create_node { node_id; kind; props; event_bindings; parent_data })
    else if opcode = Generated_protocol.Operation.update_props
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let props = read_update_props body ~protocol_minor in
      Update_props { node_id; props })
    else if opcode = Generated_protocol.Operation.update_event_bindings
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let event_bindings = read_bindings body in
      Update_event_bindings { node_id; event_bindings })
    else if opcode = Generated_protocol.Operation.set_children
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let count = Reader.u32 body in
      if count < 0 || count > Generated_protocol.Limits.max_nodes
      then fail Invalid_props "invalid child count";
      let children =
        List.init count (fun _ -> Reader.u64 body |> ID.Ui.Node_id.of_int64)
      in
      Set_children { node_id; children })
    else if opcode = Generated_protocol.Operation.set_root
    then Set_root (Reader.u64 body |> ID.Ui.Node_id.of_int64)
    else if opcode = Generated_protocol.Operation.drop_node
    then Drop_node (Reader.u64 body |> ID.Ui.Node_id.of_int64)
    else if opcode = Generated_protocol.Operation.host_request
    then (
      let request_id = Reader.u64 body |> ID.Host.Request_id.of_int64 in
      let request_kind = Reader.u16 body in
      if request_kind = 0
      then Cancel_host_request { request_id }
      else
        read_host_request
          body
          request_id
          (ID.Protocol.Host_request_kind.of_int request_kind))
    else if opcode = Generated_protocol.Operation.runtime_notification
    then (
      let event_batch_size = Reader.u32 body in
      let bonsai_flush_ns = Reader.u64 body in
      let result_read_ns = Reader.u64 body in
      let reconcile_ns = Reader.u64 body in
      let encode_ns = Reader.u64 body in
      let patch_count = Reader.u32 body in
      let patch_bytes = Reader.u32 body in
      let lifecycle_ns = Reader.u64 body in
      let full_snapshot_count = Reader.u32 body in
      let resync_count = Reader.u32 body in
      Runtime_stats
        { event_batch_size
        ; bonsai_flush_ns
        ; result_read_ns
        ; reconcile_ns
        ; encode_ns
        ; patch_count
        ; patch_bytes
        ; lifecycle_ns
        ; full_snapshot_count
        ; resync_count
        })
    else if opcode = Generated_protocol.Operation.application_request
    then (
      let request_id = Reader.u64 body in
      if Int64.compare request_id 0L <= 0
      then fail Invalid_props "application request ID must be positive";
      let payload_length = Reader.u32 body in
      if payload_length > Generated_protocol.Limits.max_application_payload_bytes
      then
        fail
          Application_payload_too_large
          "application request payload is %d bytes"
          payload_length;
      Application_request { request_id; payload = Reader.bytes body payload_length })
    else
      fail Unknown_operation "unknown operation %d" (ID.Protocol.Operation.to_int opcode)
  in
  require_empty body;
  operation
;;

let decode bytes =
  try
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Frame_too_large "frame is %d bytes" (Bytes.length bytes);
    if Bytes.length bytes < Generated_protocol.Limits.header_bytes
    then fail Truncated_input "frame is shorter than the fixed header";
    let reader = Reader.create bytes in
    let magic = Reader.string reader 4 in
    if not (String.equal magic "BFFR") then fail Invalid_magic "invalid frame magic";
    let major = Reader.u16 reader in
    let minor = Reader.u16 reader in
    if
      major <> Generated_protocol.protocol_major
      || minor > Generated_protocol.protocol_minor
    then fail Unsupported_version "unsupported protocol version %d.%d" major minor;
    let header_bytes = Reader.u16 reader in
    if header_bytes <> Generated_protocol.Limits.header_bytes
    then fail Invalid_header "invalid header size %d" header_bytes;
    let kind =
      match Reader.u8 reader with
      | value
        when value
             = ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.full_snapshot
        -> Wire_frame.Full_snapshot
      | value
        when value
             = ID.Protocol.Frame_kind.to_int
                 Generated_protocol.Frame_kind.incremental_frame -> Incremental_frame
      | value -> fail Invalid_frame_kind "invalid frame kind %d" value
    in
    let flags = Reader.u8 reader in
    if flags <> 0 then fail Invalid_flags "unsupported flags 0x%x" flags;
    let runtime_epoch = Reader.u64 reader |> ID.Runtime.Epoch.of_int64 in
    let base_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
    let target_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
    let payload_length = Reader.u32 reader in
    let checksum = Reader.u32 reader in
    let reserved = Reader.u32 reader in
    if checksum <> 0 || reserved <> 0
    then fail Invalid_header "reserved header fields are nonzero";
    if payload_length < 0 || payload_length <> Reader.remaining reader
    then fail Invalid_payload_length "payload length does not match the frame";
    let payload = Reader.sub_reader reader payload_length in
    let operation_count = ref 0 in
    let operations = ref [] in
    let saw_begin = ref false in
    let saw_end = ref false in
    while Reader.remaining payload > 0 do
      incr operation_count;
      if !operation_count > Generated_protocol.Limits.max_operations
      then fail Too_many_operations "operation limit exceeded";
      let opcode = Reader.u8 payload |> ID.Protocol.Operation.of_int in
      let body_length = Reader.u32 payload in
      if body_length < 0 then fail Truncated_input "negative operation body length";
      let body = Reader.sub_reader payload body_length in
      if opcode = Generated_protocol.Operation.begin_frame
      then (
        if !operation_count <> 1 || !saw_begin
        then fail Invalid_operation_order "BeginFrame must be first";
        require_empty body;
        saw_begin := true)
      else if opcode = Generated_protocol.Operation.end_frame
      then (
        if (not !saw_begin) || !saw_end
        then fail Invalid_operation_order "invalid EndFrame";
        require_empty body;
        saw_end := true;
        if Reader.remaining payload <> 0
        then fail Invalid_operation_order "EndFrame must be last")
      else (
        if (not !saw_begin) || !saw_end
        then fail Invalid_operation_order "operation is outside BeginFrame/EndFrame";
        operations := read_operation opcode body ~protocol_minor:minor :: !operations)
    done;
    if (not !saw_begin) || not !saw_end
    then fail Invalid_operation_order "frame is missing BeginFrame or EndFrame";
    Ok
      Wire_frame.
        { runtime_epoch
        ; base_revision
        ; target_revision
        ; kind
        ; operations = List.rev !operations
        }
  with
  | Codec_error error -> Error error
;;
