module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

module Handler = struct
  type t =
    { pending_effects : unit Bonsai.Effect.t Queue.t
    ; pending_before_display : (unit, unit) Bonsai.Effect.Private.Callback.t Queue.t
    ; host_effects : Host_effect.t
    ; application_platform : Host_effect.Application_platform.t
    ; environment : Environment.t
    }

  let create_with_dependencies ~equal dependencies ~f =
    dependencies |> Bonsai.Cont.cutoff ~equal |> Bonsai.Cont.map ~f
  ;;

  let create t ?name ~equal dependencies ~f =
    create_with_dependencies ~equal dependencies ~f:(fun dependencies ->
      Ui.Event.Handler.create ?name (fun payload ->
        Queue.add (f dependencies payload) t.pending_effects))
  ;;

  let create_native t ?name extension ~equal dependencies ~f =
    create_with_dependencies ~equal dependencies ~f:(fun dependencies ->
      Ui.Native_widget.event_handler ?name extension (fun event ->
        Queue.add (f dependencies event) t.pending_effects))
  ;;

  let host_effects t = t.host_effects
  let application_platform t = t.application_platform
  let environment t = t.environment

  let wait_before_display t =
    Bonsai.Effect.Private.make ~request:() ~evaluator:(fun callback ->
      Queue.add callback t.pending_before_display)
  ;;
end

module View = struct
  type t =
    { theme : Ui.Theme.application
    ; body : Ui.Widget.t
    }

  let create ~theme ~body = { theme; body }

  module Private = struct
    type view = t =
      { theme : Ui.Theme.application
      ; body : Ui.Widget.t
      }

    let view t = t
  end
end

type frame =
  { revision : ID.Runtime.renderer_revision
  ; frame_patch : Runtime.Frame_patch.t
  ; bytes : bytes
  ; stats : Protocol.Wire_frame.runtime_stats
  }

type error =
  | Runtime_error of Runtime.Runtime_error.t
  | Event_error of Runtime.Event_dispatcher.error
  | Codec_error of Protocol.Binary_codec.error
  | Unsupported_widget of string
  | Invalid_state of string
  | Lifecycle_error of string
  | Host_response_error of string
  | Application_platform_error of string
  | Shutdown

type pump_result =
  { presentation_id : ID.Runtime.presentation_id
  ; renderer_revision : ID.Runtime.renderer_revision
  ; frame : frame option
  ; recoverable_error : error option
  }

type rejection_reason =
  | Decode_failed
  | Frame_validation_failed
  | Renderer_epoch_mismatch
  | Renderer_revision_mismatch

let event_error_to_string = function
  | Runtime.Event_dispatcher.Invalid_event message -> "invalid event: " ^ message
  | Handler_error error -> Runtime.Runtime_error.to_string error
;;

let error_to_string = function
  | Runtime_error error -> Runtime.Runtime_error.to_string error
  | Event_error error -> event_error_to_string error
  | Codec_error error -> error.message
  | Unsupported_widget kind -> "unsupported widget in binary protocol: " ^ kind
  | Invalid_state message -> "invalid driver state: " ^ message
  | Lifecycle_error message -> "lifecycle failed: " ^ message
  | Host_response_error message -> "host response failed: " ^ message
  | Application_platform_error message -> "application platform failed: " ^ message
  | Shutdown -> "driver is shut down"
;;

type pending_presentation =
  { presentation_id : ID.Runtime.presentation_id
  ; renderer_revision : ID.Runtime.renderer_revision
  ; candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; candidate_application_theme : Ui.Theme.application
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; prepared_application_operations :
      Host_effect.Application_platform.Prepared_operations.t
  ; emitted_frame : frame option
  }

type t =
  { runtime_epoch : ID.Runtime.epoch
  ; application_title : string option
  ; trace : (string -> unit) option
  ; before_flush : schedule:(unit Bonsai.Effect.t -> unit) -> unit
  ; before_shutdown : unit -> unit
  ; time_source : Bonsai.Time_source.t
  ; logical_time_origin : Core.Time_ns.t
  ; bonsai : View.t Bonsai_runtime_adapter.t
  ; reconciler : Runtime.Reconciler.t
  ; handlers : Runtime.Handler_registry.t
  ; pending_effects : Handler.t
  ; host_effects : Host_effect.t
  ; application_platform : Host_effect.Application_platform.t
  ; environment : Environment.t
  ; mutable displayed_tree : Runtime.Mounted_tree.t option
  ; mutable displayed_handler_frame : Runtime.Handler_registry.Frame.t option
  ; mutable displayed_application_theme : Ui.Theme.application option
  ; mutable displayed_revision : ID.Runtime.renderer_revision
  ; mutable last_monotonic_ns : int64
  ; mutable last_event_sequence : ID.Runtime.event_sequence option
  ; mutable next_presentation_id : ID.Runtime.presentation_id
  ; mutable presentation_sequence_exhausted : bool
  ; mutable next_renderer_revision : ID.Runtime.renderer_revision
  ; mutable pending_presentation : pending_presentation option
  ; mutable force_full_snapshot_next : bool
  ; mutable terminal_error : error option
  ; mutable is_shutdown : bool
  ; mutable last_lifecycle_ns : int64
  ; mutable full_snapshot_count : int
  ; mutable resync_count : int
  }

let create
      ?trace
      ?(before_flush = fun ~schedule:_ -> ())
      ?(before_shutdown = fun () -> ())
      ?application_title
      ~runtime_epoch
      ~time_source
      component
  =
  if ID.Runtime.Epoch.compare runtime_epoch ID.Runtime.Epoch.zero <= 0
  then invalid_arg "Driver.create: runtime_epoch must be positive";
  let pending_queue = Queue.create () in
  let pending_before_display = Queue.create () in
  let host_effect_manager =
    Host_effect.Private.create ~schedule:(fun scheduled_effect ->
      Queue.add scheduled_effect pending_queue)
  in
  let application_platform_manager =
    Host_effect.Application_platform.Private.create ~schedule:(fun scheduled_effect ->
      Queue.add scheduled_effect pending_queue)
  in
  let environment_input = Environment.Private.create () in
  let pending_effects =
    Handler.
      { pending_effects = pending_queue
      ; pending_before_display
      ; host_effects = host_effect_manager
      ; application_platform = application_platform_manager
      ; environment = environment_input
      }
  in
  let bonsai = Bonsai_runtime_adapter.create ~time_source (component pending_effects) in
  { runtime_epoch
  ; application_title
  ; trace
  ; before_flush
  ; before_shutdown
  ; time_source
  ; logical_time_origin = Bonsai.Time_source.now time_source
  ; bonsai
  ; reconciler = Runtime.Reconciler.create ~runtime_epoch
  ; handlers = Runtime.Handler_registry.create ~runtime_epoch
  ; pending_effects
  ; host_effects = host_effect_manager
  ; application_platform = application_platform_manager
  ; environment = environment_input
  ; displayed_tree = None
  ; displayed_handler_frame = None
  ; displayed_application_theme = None
  ; displayed_revision = ID.Runtime.Renderer_revision.zero
  ; last_monotonic_ns = -1L
  ; last_event_sequence = None
  ; next_presentation_id = ID.Runtime.Presentation_id.one
  ; presentation_sequence_exhausted = false
  ; next_renderer_revision = ID.Runtime.Renderer_revision.one
  ; pending_presentation = None
  ; force_full_snapshot_next = false
  ; terminal_error = None
  ; is_shutdown = false
  ; last_lifecycle_ns = 0L
  ; full_snapshot_count = 0
  ; resync_count = 0
  }
;;

let trace_lazy t make_message =
  match t.trace with
  | None -> ()
  | Some sink ->
    (try sink (make_message ()) with
     | _ -> ())
;;

let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.)
let elapsed_ns start = Int64.sub (now_ns ()) start

let wire_frame_kind = function
  | Runtime.Frame_patch.Full_snapshot -> Protocol.Wire_frame.Full_snapshot
  | Incremental_frame -> Incremental_frame
;;

let wire_node_kind = function
  | Ui.Widget.Private.K_empty -> Ok Protocol.Wire_frame.Empty
  | K_text -> Ok Text
  | K_rich_text -> Ok Rich_text
  | K_icon -> Ok Icon
  | K_image -> Ok Image
  | K_row -> Ok Row
  | K_column -> Ok Column
  | K_flex_row -> Ok Row
  | K_flex_column -> Ok Column
  | K_stack -> Ok Stack
  | K_button -> Ok Button
  | K_padding -> Ok Padding
  | K_align -> Ok Align
  | K_center -> Ok Center
  | K_sized_box -> Ok Sized_box
  | K_constrained_box -> Ok Constrained_box
  | K_decorated_box -> Ok Decorated_box
  | K_clip -> Ok Clip
  | K_opacity -> Ok Opacity
  | K_animated_opacity -> Ok Animated_opacity
  | K_transform -> Ok Transform
  | K_scroll_view -> Ok Scroll_view
  | K_sliver_box -> Ok Sliver_box
  | K_sliver_list -> Ok Sliver_list
  | K_sliver_fill -> Ok Sliver_fill
  | K_sliver_fixed_extent -> Ok Sliver_fixed_extent
  | K_sliver_varied_extent -> Ok Sliver_varied_extent
  | K_sliver_padding -> Ok Sliver_padding
  | K_sliver_app_bar -> Ok Sliver_app_bar
  | K_preferred_size -> Ok Preferred_size
  | K_gesture -> Ok Gesture
  | K_focus_scope -> Ok Focus_scope
  | K_mouse_region -> Ok Mouse_region
  | K_keyboard_listener -> Ok Keyboard_listener
  | K_pressable -> Ok Pressable
  | K_semantics -> Ok Semantics
  | K_theme -> Ok Theme
  | K_material_scaffold -> Ok Material_scaffold
  | K_material_app_bar -> Ok Material_app_bar
  | K_material_elevated_button -> Ok Material_elevated_button
  | K_material_text_button -> Ok Material_text_button
  | K_material_icon_button -> Ok Material_icon_button
  | K_material_filled_button -> Ok Material_filled_button
  | K_material_filled_tonal_button -> Ok Material_filled_tonal_button
  | K_material_outlined_button -> Ok Material_outlined_button
  | K_material_floating_action_button -> Ok Material_floating_action_button
  | K_material_navigation_bar -> Ok Material_navigation_bar
  | K_material_radio_group -> Ok Material_radio_group
  | K_material_segmented_button -> Ok Material_segmented_button
  | K_material_slider -> Ok Material_slider
  | K_material_range_slider -> Ok Material_range_slider
  | K_material_action_chip -> Ok Material_action_chip
  | K_material_filter_chip -> Ok Material_filter_chip
  | K_material_choice_chip -> Ok Material_choice_chip
  | K_material_input_chip -> Ok Material_input_chip
  | K_material_alert_dialog -> Ok Material_alert_dialog
  | K_material_search_bar -> Ok Material_search_bar
  | K_material_tooltip -> Ok Material_tooltip
  | K_material_data_table -> Ok Material_data_table
  | K_material_stepper -> Ok Material_stepper
  | K_material_expansion_panel_list -> Ok Material_expansion_panel_list
  | K_material_simple_dialog -> Ok Material_simple_dialog
  | K_material_fullscreen_dialog -> Ok Material_fullscreen_dialog
  | K_material_checkbox -> Ok Material_checkbox
  | K_material_switch -> Ok Material_switch
  | K_material_list_tile -> Ok Material_list_tile
  | K_material_divider -> Ok Material_divider
  | K_material_card -> Ok Material_card
  | K_material_circular_progress_indicator -> Ok Material_circular_progress_indicator
  | K_material_linear_progress_indicator -> Ok Material_linear_progress_indicator
  | K_cupertino_button -> Ok Cupertino_button
  | K_cupertino_switch -> Ok Cupertino_switch
  | K_text_input -> Ok Text_input
  | K_overlay -> Ok Overlay
  | K_navigator -> Ok Navigator
  | K_page -> Ok Page
  | K_safe_area -> Ok Safe_area
  | K_environment_boundary -> Ok Environment_boundary
  | K_native_widget -> Ok Native_widget
;;

let wire_theme_text_style (style : Ui.Style.Text_style.Private.view)
  : Protocol.Wire_frame.theme_text_style
  =
  let font_weight =
    Option.map
      (function
        | Ui.Style.Font_weight.Normal -> Protocol.Wire_frame.Normal
        | Medium -> Medium
        | Semi_bold -> Semi_bold
        | Bold -> Bold)
      style.font_weight
  in
  { font_size = style.font_size
  ; font_weight
  ; line_height = style.line_height
  ; color = style.color
  }
;;

let wire_theme_data (data : Ui.Theme.Private.data_view) : Protocol.Wire_frame.theme_data =
  let typography = data.typography in
  let style = Option.map wire_theme_text_style in
  { brightness =
      (match data.brightness with
       | Ui.Style.Brightness.Light -> Protocol.Wire_frame.Light
       | Dark -> Dark)
  ; color_scheme =
      { seed_argb = data.color_scheme.seed_argb
      ; variant =
          (match data.color_scheme.variant with
           | Ui.Theme.Color_scheme.Tonal_spot -> Protocol.Wire_frame.Tonal_spot
           | Fidelity -> Fidelity
           | Content -> Content
           | Monochrome -> Monochrome
           | Neutral -> Neutral
           | Vibrant -> Vibrant
           | Expressive -> Expressive)
      ; contrast_level = data.color_scheme.contrast_level
      }
  ; typography =
      { font_family = typography.font_family
      ; font_family_fallback = typography.font_family_fallback
      ; display_large = style typography.display_large
      ; display_medium = style typography.display_medium
      ; display_small = style typography.display_small
      ; headline_large = style typography.headline_large
      ; headline_medium = style typography.headline_medium
      ; headline_small = style typography.headline_small
      ; title_large = style typography.title_large
      ; title_medium = style typography.title_medium
      ; title_small = style typography.title_small
      ; body_large = style typography.body_large
      ; body_medium = style typography.body_medium
      ; body_small = style typography.body_small
      ; label_large = style typography.label_large
      ; label_medium = style typography.label_medium
      ; label_small = style typography.label_small
      }
  ; shape =
      { extra_small = data.shape.extra_small
      ; small = data.shape.small
      ; medium = data.shape.medium
      ; large = data.shape.large
      ; extra_large = data.shape.extra_large
      }
  ; visual_density =
      (match data.visual_density with
       | Ui.Theme.Adaptive -> Protocol.Wire_frame.Adaptive
       | Standard -> Standard
       | Comfortable -> Comfortable
       | Compact -> Compact)
  ; tap_target_size =
      (match data.tap_target_size with
       | Ui.Theme.Padded -> Protocol.Wire_frame.Padded
       | Shrink_wrap -> Shrink_wrap)
  }
;;

let wire_application_theme theme : Protocol.Wire_frame.application_theme =
  let view = Ui.Theme.Private.view_application theme in
  { mode =
      (match view.mode with
       | Ui.Theme.System -> Protocol.Wire_frame.System
       | Light -> Light
       | Dark -> Dark)
  ; light = wire_theme_data view.light
  ; dark = wire_theme_data view.dark
  ; high_contrast_light = Option.map wire_theme_data view.high_contrast_light
  ; high_contrast_dark = Option.map wire_theme_data view.high_contrast_dark
  }
;;

let wire_node_props (type k) (node : k Ui.Widget.Private.node) =
  match node with
  | Ui.Widget.Private.Empty -> Ok Protocol.Wire_frame.Empty_props
  | Stack -> Ok Empty_props
  | Text { value; style; text_align; max_lines; overflow } ->
    let style =
      Option.map
        (fun (style : Ui.Style.Text_style.Private.view) ->
           let font_weight =
             Option.map
               (function
                 | Ui.Style.Font_weight.Normal -> Protocol.Wire_frame.Normal
                 | Medium -> Medium
                 | Semi_bold -> Semi_bold
                 | Bold -> Bold)
               style.font_weight
           in
           Protocol.Wire_frame.
             { font_size = style.font_size
             ; font_weight
             ; line_height = style.line_height
             ; color = style.color
             })
        style
    in
    let text_align =
      match text_align with
      | Ui.Style.Text_align.Start -> Protocol.Wire_frame.Start
      | Center -> Center_text
      | End -> End
    in
    let overflow =
      match overflow with
      | Ui.Style.Text_overflow.Clip -> Protocol.Wire_frame.Clip_text
      | Fade -> Fade
      | Ellipsis -> Ellipsis
      | Visible -> Visible
    in
    Ok (Text_props { value; style; text_align; max_lines; overflow })
  | Rich_text { spans } -> Ok (Rich_text_props { spans })
  | Icon { code_point; font_family; size; color } ->
    Ok (Icon_props { code_point; font_family; size; color })
  | Image { uri; fit; width; height } ->
    let fit =
      match fit with
      | Ui.Style.Image_fit.Fill -> Protocol.Wire_frame.Fill
      | Contain -> Contain
      | Cover -> Cover
      | Fit_width -> Fit_width
      | Fit_height -> Fit_height
      | None -> No_fit
      | Scale_down -> Scale_down
    in
    Ok (Image_props { uri; fit; width; height })
  | Row -> Ok Linear_props
  | Column -> Ok Linear_props
  | Flex_row -> Ok Linear_props
  | Flex_column -> Ok Linear_props
  | Button { enabled } -> Ok (Button_props { enabled })
  | Pressable { overlay_color; release_delay_ms } ->
    Ok
      (Pressable_props
         { overlay_color_argb = Ui.Style.Color.Private.to_argb32 overlay_color
         ; release_delay_ms
         })
  | Padding { left; top; right; bottom } ->
    Ok (Padding_props { left; top; right; bottom })
  | Align { alignment } ->
    let alignment : Protocol.Wire_frame.alignment =
      match alignment with
      | Ui.Layout.Alignment.Top_start -> Protocol.Wire_frame.Top_start
      | Top_center -> Top_center
      | Top_end -> Top_end
      | Center_start -> Center_start
      | Center -> Center
      | Center_end -> Center_end
      | Bottom_start -> Bottom_start
      | Bottom_center -> Bottom_center
      | Bottom_end -> Bottom_end
    in
    Ok (Align_props { alignment })
  | Center { width_factor; height_factor } ->
    Ok (Center_props { width_factor; height_factor })
  | Sized_box { width; height } -> Ok (Sized_box_props { width; height })
  | Constrained_box { min_width; max_width; min_height; max_height } ->
    Ok (Constrained_box_props { min_width; max_width; min_height; max_height })
  | Decorated_box { background; border_radius } ->
    Ok (Decorated_box_props { background; border_radius })
  | Clip { behavior } ->
    let behavior =
      match behavior with
      | Ui.Style.Clip.Hard_edge -> Protocol.Wire_frame.Hard_edge
      | Anti_alias -> Anti_alias
      | Anti_alias_with_save_layer -> Anti_alias_with_save_layer
    in
    Ok (Clip_props { behavior })
  | Opacity { opacity } -> Ok (Opacity_props { opacity })
  | Animated_opacity { opacity; animation } ->
    let curve : Protocol.Wire_frame.animation_curve =
      match Ui.Animation.Private.curve animation with
      | Linear -> Linear
      | Ease_in -> Ease_in
      | Ease_out -> Ease_out
      | Ease_in_out -> Ease_in_out
    in
    let animation =
      { Protocol.Wire_frame.id = Ui.Animation.Private.id animation
      ; duration_ms = Ui.Animation.Private.duration_ms animation
      ; curve
      }
    in
    Ok (Animated_opacity_props { opacity; animation })
  | Transform { matrix4 } -> Ok (Transform_props { matrix4 = Array.copy matrix4 })
  | Scroll_view { axis; reverse; primary; cache_extent } ->
    let axis =
      match axis with
      | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
      | Vertical -> Vertical
    in
    Ok (Scroll_view_props { axis; reverse; primary; cache_extent })
  | Sliver_box -> Ok Sliver_box_props
  | Sliver_list -> Ok Sliver_list_props
  | Sliver_fill -> Ok Sliver_fill_props
  | Sliver_fixed_extent { total_count; first_index; item_extent; overscan } ->
    Ok (Sliver_fixed_extent_props { total_count; first_index; item_extent; overscan })
  | Sliver_varied_extent
      { total_count
      ; first_index
      ; default_item_extent
      ; extent_overrides
      ; overscan
      ; transition
      } ->
    let extent_overrides =
      List.map
        (fun { Ui.Widget.Sparse_extent_override.index; extent } ->
           Protocol.Wire_frame.{ index; extent })
        extent_overrides
    in
    let transition =
      Option.map
        (fun (transition : Ui.Widget.Sparse_extent_transition.t) ->
           let open Ui.Widget.Sparse_extent_transition in
           let wire_curve = function
             | Linear -> Protocol.Wire_frame.Se_linear
             | Ease_in -> Se_ease_in
             | Ease_out -> Se_ease_out
             | Ease_in_out -> Se_ease_in_out
             | Ease_out_cubic -> Se_ease_out_cubic
             | Ease_in_out_cubic -> Se_ease_in_out_cubic
           in
           Protocol.Wire_frame.
             { enabled = enabled transition
             ; expand_duration_ms = expand_duration_ms transition
             ; collapse_duration_ms = collapse_duration_ms transition
             ; expand_curve = wire_curve (expand_curve transition)
             ; collapse_curve = wire_curve (collapse_curve transition)
             })
        transition
    in
    Ok
      (Sliver_varied_extent_props
         { total_count
         ; first_index
         ; default_item_extent
         ; overscan
         ; extent_overrides
         ; transition
         })
  | Sliver_padding { left; top; right; bottom } ->
    Ok (Sliver_padding_props { left; top; right; bottom })
  | Sliver_app_bar
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
    Ok
      (Sliver_app_bar_props
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
         })
  | Preferred_size { height } -> Ok (Preferred_size_props { height })
  | Gesture -> Ok Gesture_props
  | Focus_scope { autofocus } -> Ok (Focus_scope_props { autofocus })
  | Mouse_region { opaque } -> Ok (Mouse_region_props { opaque })
  | Keyboard_listener { autofocus; key_policy } ->
    let key_policy =
      match key_policy with
      | Ui.Event.Key_policy.Handled -> Protocol.Wire_frame.Handled
      | Ignored -> Ignored
    in
    Ok (Keyboard_listener_props { autofocus; key_policy })
  | Semantics
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
    let role =
      match role with
      | Ui.Semantics.Role.Generic -> Protocol.Wire_frame.Generic
      | Button -> Semantics_button
      | Link -> Link
      | Image -> Image
      | Header -> Header
      | Text_field -> Text_field
      | Checkbox -> Checkbox
      | Switch -> Switch
      | Slider -> Slider
    in
    Ok
      (Semantics_props
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
         ; actions = Ui.Semantics.Private.actions_to_bits actions
         })
  | Theme data -> Ok (Theme_props (wire_theme_data data))
  | Material_scaffold
      { has_app_bar
      ; has_floating_action_button
      ; floating_action_button_location
      ; has_bottom_navigation_bar
      ; has_bottom_sheet
      } ->
    let floating_action_button_location =
      match floating_action_button_location with
      | Ui.Widget.Private.Start_float -> Protocol.Wire_frame.Start_float
      | Center_float -> Center_float
      | End_float -> End_float
      | Start_docked -> Start_docked
      | Center_docked -> Center_docked
      | End_docked -> End_docked
    in
    Ok
      (Material_scaffold_props
         { has_app_bar
         ; has_floating_action_button
         ; floating_action_button_location
         ; has_bottom_navigation_bar
         ; has_bottom_sheet
         })
  | Material_app_bar { center_title } -> Ok (Material_app_bar_props { center_title })
  | Material_elevated_button { variant; enabled; autofocus }
  | Material_text_button { variant; enabled; autofocus }
  | Material_icon_button { variant; enabled; autofocus }
  | Material_filled_button { variant; enabled; autofocus }
  | Material_filled_tonal_button { variant; enabled; autofocus }
  | Material_outlined_button { variant; enabled; autofocus } ->
    let variant =
      match variant with
      | Ui.Widget.Private.Filled -> Protocol.Wire_frame.Filled
      | Filled_tonal -> Filled_tonal
      | Outlined -> Outlined
      | Ui.Widget.Private.Elevated -> Protocol.Wire_frame.Elevated
      | Text_button -> Text_button
      | Icon_button -> Icon_button
    in
    Ok (Material_button_props { variant; enabled; autofocus })
  | Material_floating_action_button { variant; enabled; autofocus; has_icon } ->
    let variant =
      match variant with
      | Ui.Widget.Private.Small -> Protocol.Wire_frame.Small
      | Standard -> Standard
      | Large -> Large
      | Extended -> Extended
    in
    Ok (Material_floating_action_button_props { variant; enabled; autofocus; has_icon })
  | Material_navigation_bar { selected_index; destinations } ->
    Ok
      (Material_navigation_bar_props
         { selected_index
         ; destinations =
             List.map
               (fun (destination : Ui.Widget.Private.material_navigation_destination) ->
                  Protocol.Wire_frame.
                    { label = destination.label
                    ; enabled = destination.enabled
                    ; has_selected_icon = destination.has_selected_icon
                    })
               destinations
         })
  | Material_radio_group { selected_id; options } ->
    Ok
      (Material_radio_group_props
         { selected_id
         ; options =
             List.map
               (fun (option : Ui.Widget.Private.material_radio_option) ->
                  Protocol.Wire_frame.
                    { option_id = option.option_id
                    ; enabled = option.enabled
                    ; has_label = option.has_label
                    })
               options
         })
  | Material_segmented_button
      { selected_ids
      ; enabled
      ; direction
      ; multi_selection_enabled
      ; empty_selection_allowed
      ; expanded_insets
      ; show_selected_icon
      ; has_selected_icon
      ; segments
      } ->
    let direction =
      match direction with
      | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
      | Vertical -> Vertical
    in
    Ok
      (Material_segmented_button_props
         { selected_ids
         ; enabled
         ; direction
         ; multi_selection_enabled
         ; empty_selection_allowed
         ; expanded_insets
         ; show_selected_icon
         ; has_selected_icon
         ; segments =
             List.map
               (fun (segment : Ui.Widget.Private.material_segment) ->
                  Protocol.Wire_frame.
                    { segment_id = segment.segment_id
                    ; enabled = segment.enabled
                    ; tooltip = segment.tooltip
                    ; has_icon = segment.has_icon
                    ; has_label = segment.has_label
                    })
               segments
         })
  | Material_slider { value; min; max; divisions; label; enabled; has_on_change } ->
    Ok
      (Material_slider_props { value; min; max; divisions; label; enabled; has_on_change })
  | Material_range_slider
      { start; end_; min; max; divisions; label_start; label_end; enabled; has_on_change }
    ->
    Ok
      (Material_range_slider_props
         { start
         ; end_
         ; min
         ; max
         ; divisions
         ; label_start
         ; label_end
         ; enabled
         ; has_on_change
         })
  | Material_action_chip fields ->
    Ok
      (Material_chip_props
         { variant = Action_chip
         ; presentation =
             (match fields.presentation with
              | Ui.Widget.Private.Flat_chip -> Flat_chip
              | Elevated_chip -> Elevated_chip)
         ; enabled = fields.enabled
         ; selected = fields.selected
         ; has_avatar = fields.has_avatar
         ; has_delete_icon = fields.has_delete_icon
         ; has_on_press = fields.has_on_press
         ; has_on_selected = fields.has_on_selected
         ; has_on_delete = fields.has_on_delete
         })
  | Material_filter_chip fields ->
    Ok
      (Material_chip_props
         { variant = Filter_chip
         ; presentation =
             (match fields.presentation with
              | Ui.Widget.Private.Flat_chip -> Flat_chip
              | Elevated_chip -> Elevated_chip)
         ; enabled = fields.enabled
         ; selected = fields.selected
         ; has_avatar = fields.has_avatar
         ; has_delete_icon = fields.has_delete_icon
         ; has_on_press = fields.has_on_press
         ; has_on_selected = fields.has_on_selected
         ; has_on_delete = fields.has_on_delete
         })
  | Material_choice_chip fields ->
    Ok
      (Material_chip_props
         { variant = Choice_chip
         ; presentation =
             (match fields.presentation with
              | Ui.Widget.Private.Flat_chip -> Flat_chip
              | Elevated_chip -> Elevated_chip)
         ; enabled = fields.enabled
         ; selected = fields.selected
         ; has_avatar = fields.has_avatar
         ; has_delete_icon = fields.has_delete_icon
         ; has_on_press = fields.has_on_press
         ; has_on_selected = fields.has_on_selected
         ; has_on_delete = fields.has_on_delete
         })
  | Material_input_chip fields ->
    Ok
      (Material_chip_props
         { variant = Input_chip
         ; presentation = Flat_chip
         ; enabled = fields.enabled
         ; selected = fields.selected
         ; has_avatar = fields.has_avatar
         ; has_delete_icon = fields.has_delete_icon
         ; has_on_press = fields.has_on_press
         ; has_on_selected = fields.has_on_selected
         ; has_on_delete = fields.has_on_delete
         })
  | Material_alert_dialog { has_icon; has_title; has_content; action_count } ->
    Ok (Material_alert_dialog_props { has_icon; has_title; has_content; action_count })
  | Material_search_bar fields ->
    let wire_range range =
      Protocol.Wire_frame.
        { start_utf16 = Ui.Text_editing.Range.start_utf16 range
        ; end_utf16 = Ui.Text_editing.Range.end_utf16 range
        }
    in
    let value =
      Protocol.Wire_frame.
        { text = Ui.Text_editing.Value.text fields.value
        ; selection = wire_range (Ui.Text_editing.Value.selection fields.value)
        ; composing = Option.map wire_range (Ui.Text_editing.Value.composing fields.value)
        }
    in
    let keyboard_type =
      match fields.keyboard_type with
      | Ui.Text_editing.Text -> Protocol.Wire_frame.Keyboard_text
      | Multiline -> Keyboard_multiline
      | Number -> Keyboard_number
      | Email -> Keyboard_email
      | Phone -> Keyboard_phone
      | Url -> Keyboard_url
    in
    let input_action =
      match fields.input_action with
      | Ui.Text_editing.Done -> Protocol.Wire_frame.Done
      | Newline -> Newline
      | Next -> Next
      | Previous -> Previous
      | Search -> Search
      | Send -> Send
      | Go -> Go
    in
    let update_mode =
      match fields.update_mode with
      | Ui.Text_editing.Ack -> Protocol.Wire_frame.Ack
      | Correction -> Correction
      | Force_replace -> Force_replace
    in
    Ok
      (Material_search_bar_props
         { session_id = fields.session_id
         ; document_revision = fields.document_revision
         ; value
         ; enabled = fields.enabled
         ; read_only = fields.read_only
         ; keyboard_type
         ; input_action
         ; accepted_local_revision = fields.accepted_local_revision
         ; update_mode
         ; autofocus = fields.autofocus
         ; max_utf8_bytes = fields.max_utf8_bytes
         ; has_leading = fields.has_leading
         ; trailing_count = fields.trailing_count
         ; hint_text = fields.hint_text
         ; has_on_tap = fields.has_on_tap
         })
  | Material_tooltip fields ->
    Ok
      (Material_tooltip_props
         { message = fields.message
         ; enabled = fields.enabled
         ; exclude_from_semantics = fields.exclude_from_semantics
         ; prefer_below = fields.prefer_below
         ; trigger_mode =
             (match fields.trigger_mode with
              | Ui.Widget.Private.Tooltip_long_press -> Tooltip_long_press
              | Tooltip_tap -> Tooltip_tap)
         ; wait_duration_ms = fields.wait_duration_ms
         ; show_duration_ms = fields.show_duration_ms
         ; exit_duration_ms = fields.exit_duration_ms
         ; enable_tap_to_dismiss = fields.enable_tap_to_dismiss
         ; enable_feedback = fields.enable_feedback
         ; has_on_triggered = fields.has_on_triggered
         })
  | Material_data_table fields ->
    let cell (value : Ui.Widget.Private.material_data_table_cell) =
      Protocol.Wire_frame.
        { placeholder = value.placeholder
        ; show_edit_icon = value.show_edit_icon
        ; activatable = value.activatable
        }
    in
    Ok
      (Material_data_table_props
         { columns =
             List.map
               (fun (value : Ui.Widget.Private.material_data_table_column) ->
                  Protocol.Wire_frame.
                    { column_id = value.column_id
                    ; tooltip = value.tooltip
                    ; numeric = value.numeric
                    ; sortable = value.sortable
                    })
               fields.columns
         ; rows =
             List.map
               (fun (value : Ui.Widget.Private.material_data_table_row) ->
                  Protocol.Wire_frame.
                    { row_id = value.row_id
                    ; selected = value.selected
                    ; selection_enabled = value.selection_enabled
                    ; cells = List.map cell value.cells
                    })
               fields.rows
         ; sort_column_id = fields.sort_column_id
         ; sort_ascending = fields.sort_ascending
         ; selected_row_ids = fields.selected_row_ids
         ; has_on_sort = fields.has_on_sort
         ; has_on_row_selected = fields.has_on_row_selected
         ; has_on_select_all = fields.has_on_select_all
         ; has_on_cell_activate = fields.has_on_cell_activate
         })
  | Material_stepper fields ->
    let state = function
      | Ui.Widget.Private.Step_indexed -> Protocol.Wire_frame.Step_indexed
      | Step_editing -> Step_editing
      | Step_complete -> Step_complete
      | Step_disabled -> Step_disabled
      | Step_error -> Step_error
    in
    Ok
      (Material_stepper_props
         { orientation =
             (match fields.orientation with
              | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
              | Vertical -> Vertical)
         ; current_step_id = fields.current_step_id
         ; steps =
             List.map
               (fun (value : Ui.Widget.Private.material_step) ->
                  Protocol.Wire_frame.
                    { step_id = value.step_id
                    ; active = value.active
                    ; state = state value.state
                    ; has_subtitle = value.has_subtitle
                    ; has_label = value.has_label
                    })
               fields.steps
         })
  | Material_expansion_panel_list fields ->
    Ok
      (Material_expansion_panel_list_props
         { policy =
             (match fields.policy with
              | Ui.Widget.Private.Multiple_panels -> Multiple_panels
              | Single_panel -> Single_panel)
         ; expanded_ids = fields.expanded_ids
         ; panels =
             List.map
               (fun (value : Ui.Widget.Private.material_expansion_panel) ->
                  Protocol.Wire_frame.
                    { panel_id = value.panel_id
                    ; enabled = value.enabled
                    ; can_tap_on_header = value.can_tap_on_header
                    })
               fields.panels
         })
  | Material_simple_dialog fields ->
    Ok
      (Material_simple_dialog_props
         { has_title = fields.has_title
         ; options =
             List.map
               (fun (value : Ui.Widget.Private.material_simple_dialog_option) ->
                  Protocol.Wire_frame.
                    { option_id = value.option_id; enabled = value.enabled })
               fields.options
         })
  | Material_fullscreen_dialog -> Ok Material_fullscreen_dialog_props
  | Material_checkbox { value; enabled } ->
    Ok (Material_checkbox_props { value; enabled })
  | Material_switch { value; enabled } -> Ok (Material_switch_props { value; enabled })
  | Material_list_tile { enabled; selected; has_subtitle; has_leading; has_trailing } ->
    Ok
      (Material_list_tile_props
         { enabled; selected; has_subtitle; has_leading; has_trailing })
  | Material_divider { orientation; thickness; spacing; indent; end_indent } ->
    Ok
      (Material_divider_props
         { orientation =
             (match orientation with
              | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
              | Vertical -> Vertical)
         ; thickness
         ; spacing
         ; indent
         ; end_indent
         })
  | Material_card { variant; elevation } ->
    Ok
      (Material_card_props
         { variant =
             (match variant with
              | Ui.Widget.Private.Elevated_card -> Protocol.Wire_frame.Elevated_card
              | Filled_card -> Filled_card
              | Outlined_card -> Outlined_card)
         ; elevation
         })
  | Material_circular_progress_indicator { value } ->
    Ok (Material_circular_progress_props { value })
  | Material_linear_progress_indicator { value } ->
    Ok (Material_linear_progress_props { value })
  | Cupertino_button { enabled } -> Ok (Cupertino_button_props { enabled })
  | Cupertino_switch { value; enabled } -> Ok (Cupertino_switch_props { value; enabled })
  | Text_input
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
    let wire_range range =
      Protocol.Wire_frame.
        { start_utf16 = Ui.Text_editing.Range.start_utf16 range
        ; end_utf16 = Ui.Text_editing.Range.end_utf16 range
        }
    in
    let value =
      Protocol.Wire_frame.
        { text = Ui.Text_editing.Value.text value
        ; selection = wire_range (Ui.Text_editing.Value.selection value)
        ; composing = Option.map wire_range (Ui.Text_editing.Value.composing value)
        }
    in
    let keyboard_type =
      match keyboard_type with
      | Ui.Text_editing.Text -> Protocol.Wire_frame.Keyboard_text
      | Multiline -> Keyboard_multiline
      | Number -> Keyboard_number
      | Email -> Keyboard_email
      | Phone -> Keyboard_phone
      | Url -> Keyboard_url
    in
    let input_action =
      match input_action with
      | Ui.Text_editing.Done -> Protocol.Wire_frame.Done
      | Newline -> Newline
      | Next -> Next
      | Previous -> Previous
      | Search -> Search
      | Send -> Send
      | Go -> Go
    in
    let update_mode =
      match update_mode with
      | Ui.Text_editing.Ack -> Protocol.Wire_frame.Ack
      | Correction -> Correction
      | Force_replace -> Force_replace
    in
    Ok
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
  | Overlay { alignment; dismissible } ->
    let alignment =
      match alignment with
      | Ui.Navigation.Top_start -> Protocol.Wire_frame.Top_start
      | Top_center -> Top_center
      | Top_end -> Top_end
      | Center_start -> Center_start
      | Center -> Center
      | Center_end -> Center_end
      | Bottom_start -> Bottom_start
      | Bottom_center -> Bottom_center
      | Bottom_end -> Bottom_end
    in
    Ok (Overlay_props { alignment; dismissible })
  | Navigator { restoration_scope_id } -> Ok (Navigator_props { restoration_scope_id })
  | Page { page_key; presentation; can_pop; restoration_id } ->
    let presentation =
      match presentation with
      | Ui.Navigation.Standard transition ->
        let transition =
          match transition with
          | Ui.Navigation.None -> Protocol.Wire_frame.No_transition
          | Fade -> Fade
          | Slide -> Slide
        in
        Protocol.Wire_frame.Standard_page transition
      | Modal_bottom_sheet modal ->
        let modal = Ui.Navigation.Modal_bottom_sheet.Private.view modal in
        let sizing =
          match modal.sizing with
          | Ui.Navigation.Modal_bottom_sheet.Sizing.Content_bounded ->
            Protocol.Wire_frame.Content_bounded_sizing
          | Scroll_controlled -> Scroll_controlled_sizing
          | Detented detents ->
            let detents = Ui.Navigation.Modal_bottom_sheet.Detents.Private.view detents in
            let detent = function
              | Ui.Navigation.Modal_bottom_sheet.Detent.Medium ->
                Protocol.Wire_frame.Medium_detent
              | Large -> Large_detent
            in
            let detent_set =
              match detents.detents with
              | [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium ] ->
                Protocol.Wire_frame.Medium_only
              | [ Large ] -> Large_only
              | [ Medium; Large ] -> Medium_and_large
              | _ -> assert false
            in
            let semantics =
              Ui.Navigation.Modal_bottom_sheet.Handle_semantics.Private.view
                detents.semantics
            in
            Detented_sizing
              { detents = detent_set
              ; initial_detent = detent detents.initial
              ; dismiss_on_drag = detents.dismiss_on_drag
              ; handle_semantics_label = semantics.label
              ; medium_semantics_value = semantics.medium_value
              ; large_semantics_value = semantics.large_value
              }
        in
        Modal_bottom_sheet
          { barrier_dismissible = modal.barrier_dismissible
          ; barrier_color_argb =
              Option.map Ui.Style.Color.Private.to_argb32 modal.barrier_color
          ; barrier_label = modal.barrier_label
          ; sizing
          ; use_safe_area = modal.use_safe_area
          ; request_focus = modal.request_focus
          ; transition_duration_ms = modal.transition_duration_ms
          ; reverse_transition_duration_ms = modal.reverse_transition_duration_ms
          }
      | Modal_dialog modal ->
        let modal = Ui.Navigation.Modal_dialog.Private.view modal in
        Protocol.Wire_frame.Modal_dialog
          { barrier_dismissible = modal.barrier_dismissible
          ; barrier_color_argb =
              Option.map Ui.Style.Color.Private.to_argb32 modal.barrier_color
          ; barrier_label = modal.barrier_label
          ; use_safe_area = modal.use_safe_area
          ; request_focus = modal.request_focus
          ; transition_duration_ms = modal.transition_duration_ms
          ; reverse_transition_duration_ms = modal.reverse_transition_duration_ms
          }
    in
    Ok (Page_props { page_key; presentation; can_pop; restoration_id })
  | Safe_area
      { left
      ; top
      ; right
      ; bottom
      ; minimum_left
      ; minimum_top
      ; minimum_right
      ; minimum_bottom
      } ->
    Ok
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
  | Environment_boundary -> Ok Environment_boundary_props
  | Native_widget { kind_id; version; capabilities; payload } ->
    Ok (Native_widget_props { kind_id; version; capabilities; payload })
;;

let wire_parent_data = function
  | Ui.Widget.Private.No_parent_data -> Protocol.Wire_frame.No_parent_data
  | Flex_parent_data { flex; fit } ->
    let fit =
      match fit with
      | Ui.Widget.Private.Loose -> Protocol.Wire_frame.Loose
      | Tight -> Tight
    in
    Flex_parent_data { flex; fit }
  | Stack_position { left; top; right; bottom } ->
    Stack_position { left; top; right; bottom }
;;

let wire_event_tag =
  let module Tag = Protocol.Generated_protocol.Event_tag in
  function
  | Ui.Event.Tag.Press -> Tag.press
  | Long_press -> Tag.long_press
  | Tap -> Tag.tap
  | Double_tap -> Tag.double_tap
  | Pointer_enter -> Tag.pointer_enter
  | Pointer_leave -> Tag.pointer_leave
  | Pointer_down -> Tag.pointer_down
  | Pointer_up -> Tag.pointer_up
  | Key -> Tag.key
  | Focus_changed -> Tag.focus_changed
  | Text_edit -> Tag.text_edit
  | Text_submit -> Tag.text_submit
  | Text_limit_reached -> Tag.text_limit_reached
  | Scroll_notification -> Tag.scroll_notification
  | Visible_range_changed -> Tag.visible_range_changed
  | Animation_completed -> Tag.animation_completed
  | Route_pop -> Tag.route_pop
  | Layout_observed -> Tag.layout_observed
  | Value_changed -> Tag.value_changed
  | Native_event -> Tag.native_event
  | Semantics_action -> Tag.semantics_action
  | Navigation_destination_selected -> Tag.navigation_destination_selected
  | Radio_selected -> Tag.radio_selected
  | Slider_changed -> Tag.slider_changed
  | Slider_change_end -> Tag.slider_change_end
  | Range_slider_changed -> Tag.range_slider_changed
  | Range_slider_change_end -> Tag.range_slider_change_end
  | Delete -> Tag.delete
  | Segmented_selection_changed -> Tag.segmented_selection_changed
  | Tooltip_triggered -> Tag.tooltip_triggered
  | Table_sort_requested -> Tag.table_sort_requested
  | Table_row_selected -> Tag.table_row_selected
  | Table_select_all -> Tag.table_select_all
  | Table_cell_activated -> Tag.table_cell_activated
  | Step_selected -> Tag.step_selected
  | Step_continue -> Tag.step_continue
  | Step_cancel -> Tag.step_cancel
  | Expansion_changed -> Tag.expansion_changed
  | Dialog_option_selected -> Tag.dialog_option_selected
;;

let wire_bindings bindings =
  Array.to_list bindings
  |> List.map (fun (binding : Runtime.Mounted_tree.Mounted_binding.t) ->
    Protocol.Wire_frame.
      { event_tag = wire_event_tag binding.event_tag; handler_id = binding.handler_id })
;;

let wire_operation = function
  | Runtime.Frame_patch.Operation.Create_node
      { node_id; node_tag; widget; event_bindings; parent_data; _ } ->
    let (Av view) = Ui.Widget.Private.view widget in
    (match wire_node_kind node_tag, wire_node_props view.node with
     | Ok kind, Ok props ->
       Ok
         (Protocol.Wire_frame.Create_node
            { node_id
            ; kind
            ; props
            ; event_bindings = wire_bindings event_bindings
            ; parent_data = wire_parent_data parent_data
            })
     | Error error, _ | _, Error error -> Error error)
  | Update_node { node_id; widget } ->
    let (Av view) = Ui.Widget.Private.view widget in
    (match wire_node_props view.node with
     | Ok props -> Ok (Protocol.Wire_frame.Update_props { node_id; props })
     | Error error -> Error error)
  | Update_event_bindings { node_id; event_bindings } ->
    Ok
      (Protocol.Wire_frame.Update_event_bindings
         { node_id; event_bindings = wire_bindings event_bindings })
  | Set_children { node_id; children } ->
    Ok (Protocol.Wire_frame.Set_children { node_id; children = Array.to_list children })
  | Set_root node_id -> Ok (Protocol.Wire_frame.Set_root node_id)
  | Drop_node node_id -> Ok (Protocol.Wire_frame.Drop_node node_id)
;;

let wire_operations operations =
  let rec loop reversed = function
    | [] -> Ok (List.rev reversed)
    | operation :: rest ->
      (match wire_operation operation with
       | Ok operation -> loop (operation :: reversed) rest
       | Error error -> Error error)
  in
  loop [] operations
;;

let drain_effects t =
  while not (Queue.is_empty t.pending_effects.pending_effects) do
    Bonsai_runtime_adapter.schedule_event
      t.bonsai
      (Queue.take t.pending_effects.pending_effects)
  done
;;

let flush_before_display t =
  let rec loop () =
    if not (Queue.is_empty t.pending_effects.pending_before_display)
    then (
      while not (Queue.is_empty t.pending_effects.pending_before_display) do
        let callback = Queue.take t.pending_effects.pending_before_display in
        Bonsai_runtime_adapter.schedule_event
          t.bonsai
          (Bonsai.Effect.Private.Callback.respond_to callback ())
      done;
      Bonsai_runtime_adapter.flush t.bonsai;
      loop ())
  in
  loop ()
;;

let frame_kind_name = function
  | Runtime.Frame_patch.Full_snapshot -> "full_snapshot"
  | Incremental_frame -> "incremental_frame"
;;

let operation_summary operations =
  let create_node = ref 0 in
  let update_props = ref 0 in
  let update_event_bindings = ref 0 in
  let set_children = ref 0 in
  let set_root = ref 0 in
  let drop_node = ref 0 in
  let host_request = ref 0 in
  let cancel_host_request = ref 0 in
  let application_request = ref 0 in
  List.iter
    (function
      | Protocol.Wire_frame.Create_node _ -> incr create_node
      | Update_props _ -> incr update_props
      | Update_event_bindings _ -> incr update_event_bindings
      | Set_children _ -> incr set_children
      | Set_root _ -> incr set_root
      | Set_application_theme _ -> ()
      | Drop_node _ -> incr drop_node
      | Host_request _ -> incr host_request
      | Cancel_host_request _ -> incr cancel_host_request
      | Application_request _ -> incr application_request
      | Runtime_stats _ -> ())
    operations;
  Printf.sprintf
    "createNode=%d updateProps=%d updateEventBindings=%d setChildren=%d setRoot=%d \
     dropNode=%d hostRequest=%d cancelHostRequest=%d applicationRequest=%d"
    !create_node
    !update_props
    !update_event_bindings
    !set_children
    !set_root
    !drop_node
    !host_request
    !cancel_host_request
    !application_request
;;

type widget_change =
  { node_id : Runtime.Node_id.t
  ; mutable operations : string list
  ; mutable widget : Ui.Widget.t option
  }

let find_source_widget mounted_tree node_id =
  let rec find (node : Runtime.Mounted_tree.Private.node) =
    if Runtime.Node_id.equal node.node_id node_id
    then Some node.source_widget
    else Array.find_map find node.children
  in
  Option.bind mounted_tree (fun tree -> find (Runtime.Mounted_tree.Private.root tree))
;;

let incremental_widget_diff ~old_tree ~new_tree operations =
  let changes_by_node = Hashtbl.create (List.length operations) in
  let changes = ref [] in
  let add operation node_id mounted_tree =
    let widget = find_source_widget mounted_tree node_id in
    match Hashtbl.find_opt changes_by_node node_id with
    | Some change ->
      if not (List.mem operation change.operations)
      then change.operations <- change.operations @ [ operation ];
      if Option.is_none change.widget then change.widget <- widget
    | None ->
      let change = { node_id; operations = [ operation ]; widget } in
      Hashtbl.add changes_by_node node_id change;
      changes := change :: !changes
  in
  List.iter
    (function
      | Runtime.Frame_patch.Operation.Create_node { node_id; _ } ->
        add "createNode" node_id new_tree
      | Update_node { node_id; _ } -> add "updateNode" node_id new_tree
      | Update_event_bindings { node_id; _ } -> add "updateEventBindings" node_id new_tree
      | Set_children { node_id; _ } -> add "setChildren" node_id new_tree
      | Set_root node_id -> add "setRoot" node_id new_tree
      | Drop_node node_id -> add "dropNode" node_id old_tree)
    operations;
  List.rev !changes
  |> List.map (fun change ->
    let description =
      match change.widget with
      | Some widget -> Ui.Debug.dump_widget widget
      | None -> "<widget unavailable>"
    in
    Printf.sprintf
      "  %s node=%Ld %s"
      (String.concat "+" change.operations)
      (Runtime.Node_id.to_int64 change.node_id)
      description)
  |> String.concat "\n"
;;

let trace_widget_diff t ~target_revision ~widget ~old_tree output =
  let frame_patch = output.Runtime.Reconciler.frame_patch in
  match t.trace with
  | None -> ()
  | Some _ when Runtime.Frame_patch.is_empty frame_patch -> ()
  | Some _ ->
    trace_lazy t (fun () ->
      let frame_kind = Runtime.Frame_patch.kind frame_patch in
      let diff =
        match frame_kind with
        | Runtime.Frame_patch.Full_snapshot -> Ui.Debug.dump_tree widget
        | Incremental_frame ->
          incremental_widget_diff
            ~old_tree
            ~new_tree:(Some output.mounted_tree)
            (Runtime.Frame_patch.operations frame_patch)
      in
      Printf.sprintf
        "[widget-diff] targetRevision=%Ld kind=%s\n%s"
        (ID.Runtime.Renderer_revision.to_int64 target_revision)
        (frame_kind_name frame_kind)
        diff)
;;

type produced_candidate =
  { candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; candidate_application_theme : Ui.Theme.application
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; prepared_application_operations :
      Host_effect.Application_platform.Prepared_operations.t
  ; renderer_revision : ID.Runtime.renderer_revision
  ; emitted_frame : frame option
  }

let produce_candidate t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot =
  if
    ID.Runtime.Renderer_revision.equal
      t.next_renderer_revision
      ID.Runtime.Renderer_revision.max_value
  then Error (Invalid_state "renderer revision counter exhausted")
  else (
    let target_revision = t.next_renderer_revision in
    let result_started = now_ns () in
    let view = Bonsai_runtime_adapter.result t.bonsai |> View.Private.view in
    let widget = view.body in
    let application_theme = view.theme in
    let theme_changed =
      force_full_snapshot
      ||
      match t.displayed_application_theme with
      | None -> true
      | Some displayed ->
        not (Ui.Theme.Private.equal_application application_theme displayed)
    in
    let result_read_ns = elapsed_ns result_started in
    let reconcile_started = now_ns () in
    match
      Runtime.Reconciler.reconcile
        t.reconciler
        ~base_revision:t.displayed_revision
        ~target_revision
        ~old:(if force_full_snapshot then None else t.displayed_tree)
        ~base_handler_frame:
          (if force_full_snapshot then None else t.displayed_handler_frame)
        widget
    with
    | Error error -> Error (Runtime_error error)
    | Ok output ->
      let reconcile_ns = elapsed_ns reconcile_started in
      trace_widget_diff t ~target_revision ~widget ~old_tree:t.displayed_tree output;
      let prepared_host_operations = Host_effect.prepare_operations t.host_effects in
      let host_operations =
        Host_effect.Prepared_operations.operations prepared_host_operations
      in
      let prepared_application_operations =
        Host_effect.Application_platform.prepare_operations t.application_platform
      in
      let application_operations =
        Host_effect.Application_platform.Prepared_operations.operations
          prepared_application_operations
      in
      if
        Runtime.Frame_patch.is_empty output.frame_patch
        && (not theme_changed)
        && host_operations = []
        && application_operations = []
      then
        Ok
          { candidate_tree = output.mounted_tree
          ; candidate_handler_frame = None
          ; candidate_application_theme = application_theme
          ; prepared_host_operations
          ; prepared_application_operations
          ; renderer_revision = t.displayed_revision
          ; emitted_frame = None
          }
      else (
        match wire_operations (Runtime.Frame_patch.operations output.frame_patch) with
        | Error _ as error -> error
        | Ok ui_operations ->
          let theme_operations =
            if theme_changed
            then
              [ Protocol.Wire_frame.Set_application_theme
                  { title = t.application_title
                  ; theme = wire_application_theme application_theme
                  }
              ]
            else []
          in
          let operations =
            theme_operations @ ui_operations @ host_operations @ application_operations
          in
          let frame_kind = Runtime.Frame_patch.kind output.frame_patch in
          let base_revision =
            match frame_kind with
            | Runtime.Frame_patch.Full_snapshot -> ID.Runtime.Renderer_revision.zero
            | Incremental_frame -> t.displayed_revision
          in
          if frame_kind = Runtime.Frame_patch.Full_snapshot
          then t.full_snapshot_count <- t.full_snapshot_count + 1;
          if force_full_snapshot then t.resync_count <- t.resync_count + 1;
          let stats : Protocol.Wire_frame.runtime_stats =
            { event_batch_size
            ; bonsai_flush_ns
            ; result_read_ns
            ; reconcile_ns
            ; encode_ns = 0L
            ; patch_count = List.length operations
            ; patch_bytes = 0
            ; lifecycle_ns = t.last_lifecycle_ns
            ; full_snapshot_count = t.full_snapshot_count
            ; resync_count = t.resync_count
            }
          in
          let wire_frame stats =
            Protocol.Wire_frame.
              { runtime_epoch = t.runtime_epoch
              ; base_revision
              ; target_revision
              ; kind = wire_frame_kind frame_kind
              ; operations = operations @ [ Runtime_stats stats ]
              }
          in
          let encode_started = now_ns () in
          (match Protocol.Binary_codec.encode_runtime_frame (wire_frame stats) with
           | Error error -> Error (Codec_error error)
           | Ok encoded ->
             let bytes = Protocol.Binary_codec.Runtime_encoded_frame.bytes encoded in
             let stats =
               { stats with
                 encode_ns = elapsed_ns encode_started
               ; patch_bytes = Bytes.length bytes
               }
             in
             (match
                Protocol.Binary_codec.patch_runtime_stats
                  encoded
                  ~encode_ns:stats.encode_ns
                  ~patch_bytes:stats.patch_bytes
              with
              | Error error -> Error (Codec_error error)
              | Ok () ->
                let frame =
                  { revision = target_revision
                  ; frame_patch = output.frame_patch
                  ; bytes
                  ; stats
                  }
                in
                t.next_renderer_revision
                <- ID.Runtime.Renderer_revision.succ target_revision;
                trace_lazy t (fun () ->
                  Printf.sprintf
                    "[outbound-frame] direction=ocaml->flutter epoch=%Ld kind=%s \
                     baseRevision=%Ld targetRevision=%Ld operations=%d bytes=%d\n\
                    \  operationSummary=%s"
                    (ID.Runtime.Epoch.to_int64 t.runtime_epoch)
                    (frame_kind_name frame_kind)
                    (ID.Runtime.Renderer_revision.to_int64 base_revision)
                    (ID.Runtime.Renderer_revision.to_int64 target_revision)
                    (List.length operations)
                    (Bytes.length bytes)
                    (operation_summary operations));
                Ok
                  { candidate_tree = output.mounted_tree
                  ; candidate_handler_frame = Some output.handler_frame
                  ; candidate_application_theme = application_theme
                  ; prepared_host_operations
                  ; prepared_application_operations
                  ; renderer_revision = target_revision
                  ; emitted_frame = Some frame
                  }))))
;;

let event_tag_name event_tag =
  match Protocol.Generated_protocol.Event_tag.debug_name event_tag with
  | Some name -> name
  | None -> Printf.sprintf "unknown(%d)" (ID.Protocol.Event_tag.to_int event_tag)
;;

let pointer_kind_name = function
  | Protocol.Inbound_event.Mouse -> "mouse"
  | Touch -> "touch"
  | Stylus -> "stylus"
  | Inverted_stylus -> "inverted_stylus"
  | Trackpad -> "trackpad"
  | Unknown_pointer -> "unknown"
;;

let key_action_name = function
  | Protocol.Inbound_event.Key_down -> "down"
  | Key_up -> "up"
  | Key_repeat -> "repeat"
;;

let host_response_status_name = function
  | Protocol.Inbound_event.Host_ok -> "ok"
  | Host_error -> "error"
  | Host_cancelled -> "cancelled"
;;

let payload_summary = function
  | Protocol.Inbound_event.Unit -> "unit"
  | Bool value -> Printf.sprintf "bool(%b)" value
  | Float value -> Printf.sprintf "float(%g)" value
  | Float_range { start; end_ } -> Printf.sprintf "float_range(%g,%g)" start end_
  | Text value -> Printf.sprintf "text(bytes=%d)" (String.length value)
  | Text_edit edit ->
    Printf.sprintf
      "text_edit(session=%Ld localRevision=%Ld baseDocumentRevision=%Ld bytes=%d)"
      (ID.Text_input.Session_id.to_int64 edit.session_id)
      (ID.Text_input.Local_revision.to_int64 edit.local_revision)
      (ID.Text_input.Document_revision.to_int64 edit.base_document_revision)
      (String.length edit.text)
  | Int64 value -> Printf.sprintf "int64(%Ld)" value
  | Int64_list values ->
    Printf.sprintf "int64_list(%s)" (String.concat "," (List.map Int64.to_string values))
  | Int64_bool { id; value } -> Printf.sprintf "int64_bool(%Ld,%b)" id value
  | Int64_pair { first; second } -> Printf.sprintf "int64_pair(%Ld,%Ld)" first second
  | Tap tap ->
    Printf.sprintf
      "tap(local=%g,%g global=%g,%g pointer=%s)"
      tap.local_x
      tap.local_y
      tap.global_x
      tap.global_y
      (pointer_kind_name tap.pointer_kind)
  | Pointer pointer ->
    Printf.sprintf
      "pointer(id=%Ld local=%g,%g global=%g,%g pointer=%s buttons=%d)"
      (ID.Input.Pointer_id.to_int64 pointer.pointer_id)
      pointer.local_x
      pointer.local_y
      pointer.global_x
      pointer.global_y
      (pointer_kind_name pointer.pointer_kind)
      pointer.buttons
  | Key key ->
    Printf.sprintf
      "key(logical=%Ld physical=%Ld action=%s modifiers=%d)"
      (ID.Input.Logical_key.to_int64 key.logical_key)
      (ID.Input.Physical_key.to_int64 key.physical_key)
      (key_action_name key.action)
      key.modifiers
  | Scroll { pixels; delta } -> Printf.sprintf "scroll(pixels=%g delta=%g)" pixels delta
  | Visible_range { first_index; last_exclusive } ->
    Printf.sprintf "visible_range(first=%Ld lastExclusive=%Ld)" first_index last_exclusive
  | Route_pop route ->
    Printf.sprintf
      "route_pop(pageKey=%S resultBytes=%d)"
      (ID.Navigation.Page_key.to_string route.page_key)
      (Option.fold ~none:0 ~some:String.length route.result)
  | Host_response response ->
    Printf.sprintf
      "host_response(request=%Ld status=%s bytes=%d)"
      (ID.Host.Request_id.to_int64 response.request_id)
      (host_response_status_name response.status)
      (Bytes.length response.value)
  | Application_response response ->
    Printf.sprintf
      "application_response(request=%Ld bytes=%d)"
      response.request_id
      (Bytes.length response.payload)
  | Application_request_error response ->
    Printf.sprintf "application_request_error(request=%Ld)" response.request_id
  | Application_event payload ->
    Printf.sprintf "application_event(bytes=%d)" (Bytes.length payload)
  | Environment_changed environment ->
    Printf.sprintf
      "environment_changed(platform=%S locale=%S viewport=%gx%g)"
      environment.platform
      environment.locale
      environment.viewport_width
      environment.viewport_height
  | Native_event event ->
    Printf.sprintf
      "native_event(kind=%d version=%d event=%d bytes=%d)"
      (ID.Native_widget.Kind_id.to_int event.kind_id)
      event.version
      (ID.Native_widget.Event_id.to_int event.event_id)
      (Bytes.length event.payload)
;;

let trace_inbound_event_batch t (batch : Protocol.Inbound_event.batch) =
  trace_lazy t (fun () ->
    let output = Buffer.create 256 in
    Printf.bprintf
      output
      "[inbound-event-batch] direction=flutter->ocaml epoch=%Ld events=%d"
      (ID.Runtime.Epoch.to_int64 batch.runtime_epoch)
      (List.length batch.events);
    List.iter
      (fun (event : Protocol.Inbound_event.t) ->
         Printf.bprintf
           output
           "\n  sequence=%Ld displayedRevision=%Ld node=%Ld handler=%Ld tag=%s payload=%s"
           (ID.Runtime.Event_sequence.to_int64 event.sequence)
           (ID.Runtime.Renderer_revision.to_int64 event.displayed_revision)
           (ID.Ui.Node_id.to_int64 event.node_id)
           (ID.Ui.Handler_id.to_int64 event.handler_id)
           (event_tag_name event.event_tag)
           (payload_summary event.payload))
      batch.events;
    Buffer.contents output)
;;

let environment_of_protocol (environment : Protocol.Inbound_event.environment)
  : Environment.snapshot
  =
  let edge_insets (insets : Protocol.Inbound_event.edge_insets) =
    Environment.
      { left = insets.left
      ; top = insets.top
      ; right = insets.right
      ; bottom = insets.bottom
      }
  in
  { viewport_width = environment.viewport_width
  ; viewport_height = environment.viewport_height
  ; device_pixel_ratio = environment.device_pixel_ratio
  ; text_scale = environment.text_scale
  ; brightness =
      (match environment.brightness with
       | Protocol.Inbound_event.Environment_light -> Environment.Light
       | Environment_dark -> Dark)
  ; platform = environment.platform
  ; locale = environment.locale
  ; safe_area = edge_insets environment.safe_area
  ; keyboard_insets = edge_insets environment.keyboard_insets
  ; accessible_navigation = environment.accessible_navigation
  ; bold_text = environment.bold_text
  ; invert_colors = environment.invert_colors
  ; disable_animations = environment.disable_animations
  ; reduced_motion = environment.reduced_motion
  ; high_contrast = environment.high_contrast
  ; orientation =
      (match environment.orientation with
       | Protocol.Inbound_event.Portrait -> Environment.Portrait
       | Landscape -> Landscape)
  ; pointer_kinds = environment.pointer_kinds
  }
;;

let exception_message exception_ =
  match exception_ with
  | Failure message | Invalid_argument message -> message
  | _ -> Printexc.to_string exception_
;;

type validated_control =
  | Validated_host_response of Host_effect.Private.Validated_response.t
  | Validated_application_input of
      Host_effect.Application_platform.Private.Validated_input.t
  | Validated_environment of Environment.snapshot
  | Validated_resync

type validated_input =
  { ui_events : Runtime.Event_dispatcher.Validated_batch.t option
  ; controls : validated_control list
  ; last_event_sequence : ID.Runtime.event_sequence option
  ; force_full_snapshot : bool
  }

let terminal t error =
  t.terminal_error <- Some error;
  error
;;

let active_error t = if t.is_shutdown then Some Shutdown else t.terminal_error

let logical_time t monotonic_now_ns =
  if Int64.compare monotonic_now_ns 0L < 0
  then Error (Invalid_state "monotonic time must be nonnegative")
  else if Int64.compare monotonic_now_ns t.last_monotonic_ns < 0
  then Error (Invalid_state "monotonic time moved backwards")
  else (
    try
      let span =
        monotonic_now_ns |> Core.Int63.of_int64_exn |> Core.Time_ns.Span.of_int63_ns
      in
      let target = Core.Time_ns.add t.logical_time_origin span in
      if Core.Time_ns.compare target t.logical_time_origin < 0
      then Error (Invalid_state "logical time overflow")
      else Ok target
    with
    | _ -> Error (Invalid_state "monotonic time is not representable"))
;;

let valid_environment (environment : Protocol.Inbound_event.environment) =
  let finite_nonnegative value = Float.is_finite value && Float.compare value 0. >= 0 in
  let valid_insets (insets : Protocol.Inbound_event.edge_insets) =
    finite_nonnegative insets.left
    && finite_nonnegative insets.top
    && finite_nonnegative insets.right
    && finite_nonnegative insets.bottom
  in
  finite_nonnegative environment.viewport_width
  && finite_nonnegative environment.viewport_height
  && finite_nonnegative environment.device_pixel_ratio
  && finite_nonnegative environment.text_scale
  && valid_insets environment.safe_area
  && valid_insets environment.keyboard_insets
;;

let is_application_platform_tag event_tag =
  event_tag = Protocol.Generated_protocol.Event_tag.application_response
  || event_tag = Protocol.Generated_protocol.Event_tag.application_request_error
  || event_tag = Protocol.Generated_protocol.Event_tag.application_event
;;

let validate_input t (batch : Protocol.Inbound_event.batch) =
  if not (ID.Runtime.Epoch.equal batch.runtime_epoch t.runtime_epoch)
  then
    if
      List.exists
        (fun (event : Protocol.Inbound_event.t) ->
           is_application_platform_tag event.event_tag)
        batch.events
    then Error (Application_platform_error "runtime epoch mismatch")
    else Error (Host_response_error "runtime epoch mismatch")
  else (
    let seen_host_responses = Hashtbl.create 8 in
    let seen_application_responses = Hashtbl.create 8 in
    let rec validate_events reversed_ui reversed_controls last_sequence force = function
      | [] ->
        let ui_events = List.rev reversed_ui in
        let ui_batch = Protocol.Inbound_event.{ batch with events = ui_events } in
        let validated_ui =
          match ui_events with
          | [] -> Ok None
          | _ ->
            (match Runtime.Event_dispatcher.validate_batch t.handlers ui_batch with
             | Ok validated -> Ok (Some validated)
             | Error error -> Error (Event_error error))
        in
        (match validated_ui with
         | Error _ as error -> error
         | Ok ui_events ->
           Ok
             { ui_events
             ; controls = List.rev reversed_controls
             ; last_event_sequence = last_sequence
             ; force_full_snapshot = force
             })
      | (event : Protocol.Inbound_event.t) :: rest ->
        if
          match last_sequence with
          | Some previous ->
            ID.Runtime.Event_sequence.compare event.sequence previous <= 0
          | None -> false
        then
          Error
            (Host_response_error
               (Printf.sprintf
                  "duplicate or out-of-order event sequence %Ld"
                  (ID.Runtime.Event_sequence.to_int64 event.sequence)))
        else (
          let next_sequence = Some event.sequence in
          let is_host_response =
            event.event_tag = Protocol.Generated_protocol.Event_tag.host_response
          in
          let is_environment =
            event.event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
          in
          let is_resync =
            event.event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
          in
          let is_application_response =
            event.event_tag = Protocol.Generated_protocol.Event_tag.application_response
            || event.event_tag
               = Protocol.Generated_protocol.Event_tag.application_request_error
          in
          let is_application_event =
            event.event_tag = Protocol.Generated_protocol.Event_tag.application_event
          in
          if
            is_host_response
            || is_environment
            || is_resync
            || is_application_response
            || is_application_event
          then
            if
              (not (ID.Ui.Node_id.equal event.node_id ID.Ui.Node_id.zero))
              || (not (ID.Ui.Handler_id.equal event.handler_id ID.Ui.Handler_id.zero))
              || not
                   (ID.Runtime.Renderer_revision.equal
                      event.displayed_revision
                      t.displayed_revision)
            then
              if is_application_response || is_application_event
              then
                Error (Application_platform_error "malformed application control event")
              else Error (Host_response_error "malformed runtime control event")
            else if is_host_response
            then (
              match event.payload with
              | Host_response response ->
                if Hashtbl.mem seen_host_responses response.request_id
                then
                  Error
                    (Host_response_error
                       (Printf.sprintf
                          "duplicate host response ID %Ld"
                          (ID.Host.Request_id.to_int64 response.request_id)))
                else (
                  Hashtbl.add seen_host_responses response.request_id ();
                  match Host_effect.Private.validate_response t.host_effects response with
                  | Error message -> Error (Host_response_error message)
                  | Ok response ->
                    validate_events
                      reversed_ui
                      (Validated_host_response response :: reversed_controls)
                      next_sequence
                      force
                      rest)
              | _ -> Error (Host_response_error "malformed host response event"))
            else if is_application_response || is_application_event
            then (
              match
                Host_effect.Application_platform.Private.validate_input
                  t.application_platform
                  event.payload
              with
              | Error message -> Error (Application_platform_error message)
              | Ok validated ->
                (match
                   Host_effect.Application_platform.Private.Validated_input.request_id
                     validated
                 with
                 | Some request_id when Hashtbl.mem seen_application_responses request_id
                   ->
                   Error
                     (Application_platform_error
                        (Printf.sprintf
                           "duplicate application response ID %Ld"
                           request_id))
                 | Some request_id ->
                   Hashtbl.add seen_application_responses request_id ();
                   validate_events
                     reversed_ui
                     (Validated_application_input validated :: reversed_controls)
                     next_sequence
                     force
                     rest
                 | None ->
                   validate_events
                     reversed_ui
                     (Validated_application_input validated :: reversed_controls)
                     next_sequence
                     force
                     rest))
            else if is_environment
            then (
              match event.payload with
              | Environment_changed environment when valid_environment environment ->
                validate_events
                  reversed_ui
                  (Validated_environment (environment_of_protocol environment)
                   :: reversed_controls)
                  next_sequence
                  force
                  rest
              | _ -> Error (Host_response_error "malformed environment event"))
            else (
              match event.payload with
              | Unit ->
                validate_events
                  reversed_ui
                  (Validated_resync :: reversed_controls)
                  next_sequence
                  true
                  rest
              | _ -> Error (Host_response_error "malformed resync event"))
          else
            validate_events
              (event :: reversed_ui)
              reversed_controls
              next_sequence
              force
              rest)
    in
    validate_events [] [] t.last_event_sequence false batch.events)
;;

let execute_validated_input t validated =
  let execute_ui =
    match validated.ui_events with
    | None -> Ok ()
    | Some ui_events ->
      (match Runtime.Event_dispatcher.dispatch_validated t.handlers ui_events with
       | Ok () -> Ok ()
       | Error error -> Error (Event_error error))
  in
  match execute_ui with
  | Error _ as error -> error
  | Ok () ->
    let rec execute_controls = function
      | [] ->
        t.last_event_sequence <- validated.last_event_sequence;
        Ok ()
      | Validated_host_response response :: rest ->
        (match Host_effect.Private.resolve_validated t.host_effects response with
         | Ok () -> execute_controls rest
         | Error message -> Error (Host_response_error message))
      | Validated_application_input input :: rest ->
        (match
           Host_effect.Application_platform.Private.resolve_validated
             t.application_platform
             input
         with
         | Ok () -> execute_controls rest
         | Error message -> Error (Application_platform_error message))
      | Validated_environment environment :: rest ->
        ignore (Environment.Private.update t.environment environment);
        execute_controls rest
      | Validated_resync :: rest -> execute_controls rest
    in
    execute_controls validated.controls
;;

let reserve_presentation_id t =
  if t.presentation_sequence_exhausted
  then Error (Invalid_state "presentation ID counter exhausted")
  else (
    let presentation_id = t.next_presentation_id in
    if
      ID.Runtime.Presentation_id.equal
        presentation_id
        ID.Runtime.Presentation_id.max_value
    then t.presentation_sequence_exhausted <- true
    else t.next_presentation_id <- ID.Runtime.Presentation_id.succ presentation_id;
    Ok presentation_id)
;;

let pump t ~monotonic_now_ns ?events () =
  Option.iter (trace_inbound_event_batch t) events;
  match active_error t with
  | Some error -> Error error
  | None ->
    (match t.pending_presentation with
     | Some _ -> Error (Invalid_state "a presentation is already pending")
     | None ->
       (match logical_time t monotonic_now_ns with
        | Error _ as error -> error
        | Ok logical_time ->
          let validated_input, recoverable_error =
            match events with
            | None -> None, None
            | Some events ->
              (match validate_input t events with
               | Ok validated -> Some validated, None
               | Error error -> None, Some error)
          in
          let force_full_snapshot =
            t.force_full_snapshot_next
            ||
            match validated_input with
            | Some validated -> validated.force_full_snapshot
            | None -> false
          in
          (try
             Bonsai_runtime_adapter.advance_clock t.bonsai ~to_:logical_time;
             ignore (Bonsai.Time_source.now t.time_source);
             t.last_monotonic_ns <- monotonic_now_ns;
             (match validated_input with
              | None -> ()
              | Some validated ->
                (match execute_validated_input t validated with
                 | Ok () -> ()
                 | Error error -> raise (Failure (error_to_string error))));
             t.before_flush ~schedule:(fun scheduled_effect ->
               Queue.add scheduled_effect t.pending_effects.pending_effects);
             drain_effects t;
             let flush_started = now_ns () in
             Bonsai_runtime_adapter.flush t.bonsai;
             flush_before_display t;
             let bonsai_flush_ns = elapsed_ns flush_started in
             let event_batch_size =
               match events with
               | None -> 0
               | Some events -> List.length events.Protocol.Inbound_event.events
             in
             match
               produce_candidate t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot
             with
             | Error error -> Error (terminal t error)
             | Ok candidate ->
               (match reserve_presentation_id t with
                | Error error -> Error (terminal t error)
                | Ok presentation_id ->
                  let pending =
                    { presentation_id
                    ; renderer_revision = candidate.renderer_revision
                    ; candidate_tree = candidate.candidate_tree
                    ; candidate_handler_frame = candidate.candidate_handler_frame
                    ; candidate_application_theme = candidate.candidate_application_theme
                    ; prepared_host_operations = candidate.prepared_host_operations
                    ; prepared_application_operations =
                        candidate.prepared_application_operations
                    ; emitted_frame = candidate.emitted_frame
                    }
                  in
                  t.pending_presentation <- Some pending;
                  Ok
                    { presentation_id
                    ; renderer_revision = candidate.renderer_revision
                    ; frame = candidate.emitted_frame
                    ; recoverable_error
                    })
           with
           | exception_ ->
             let error = Invalid_state (exception_message exception_) in
             Error (terminal t error))))
;;

let exact_pending t ~presentation_id ~renderer_revision =
  match t.pending_presentation with
  | None -> Error (Invalid_state "no presentation is pending")
  | Some pending ->
    if not (ID.Runtime.Presentation_id.equal pending.presentation_id presentation_id)
    then Error (Invalid_state "presentation ID does not match the pending token")
    else if
      not (ID.Runtime.Renderer_revision.equal pending.renderer_revision renderer_revision)
    then Error (Invalid_state "renderer revision does not match the pending token")
    else Ok pending
;;

let presentation_succeeded t ~presentation_id ~renderer_revision ~monotonic_now_ns =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match exact_pending t ~presentation_id ~renderer_revision with
     | Error _ as error -> error
     | Ok pending ->
       (match logical_time t monotonic_now_ns with
        | Error _ as error -> error
        | Ok logical_time ->
          Option.iter
            (fun _ ->
               trace_lazy t (fun () ->
                 Printf.sprintf
                   "[presentation-ack] presentationId=%Ld revision=%Ld \
                    direction=flutter->ocaml"
                   (ID.Runtime.Presentation_id.to_int64 presentation_id)
                   (ID.Runtime.Renderer_revision.to_int64 renderer_revision)))
            pending.emitted_frame;
          let fail_fatal error = Error (terminal t error) in
          (match
             Host_effect.commit_operations t.host_effects pending.prepared_host_operations
           with
           | Error message -> fail_fatal (Invalid_state message)
           | Ok () ->
             (match
                Host_effect.Application_platform.commit_operations
                  t.application_platform
                  pending.prepared_application_operations
              with
              | Error message -> fail_fatal (Invalid_state message)
              | Ok () ->
                let commit_handler =
                  match pending.emitted_frame, pending.candidate_handler_frame with
                  | None, None ->
                    Ok (t.displayed_revision, t.displayed_handler_frame, false)
                  | Some _, Some handler_frame ->
                    (match Runtime.Handler_registry.install t.handlers handler_frame with
                     | Error error -> Error (Runtime_error error)
                     | Ok () ->
                       (match
                          Runtime.Handler_registry.mark_displayed_revision
                            t.handlers
                            ~revision:renderer_revision
                        with
                        | Error error -> Error (Runtime_error error)
                        | Ok () -> Ok (renderer_revision, Some handler_frame, true)))
                  | None, Some _ | Some _, None ->
                    Error
                      (Invalid_state
                         "candidate frame and handler metadata are inconsistent")
                in
                (match commit_handler with
                 | Error error -> fail_fatal error
                 | Ok (displayed_revision, displayed_handler_frame, retire_handlers) ->
                   t.displayed_tree <- Some pending.candidate_tree;
                   t.displayed_handler_frame <- displayed_handler_frame;
                   t.displayed_application_theme
                   <- Some pending.candidate_application_theme;
                   t.displayed_revision <- displayed_revision;
                   if retire_handlers
                   then
                     Runtime.Handler_registry.retire_superseded
                       t.handlers
                       ~displayed_revision;
                   (try
                      Bonsai_runtime_adapter.advance_clock t.bonsai ~to_:logical_time;
                      ignore (Bonsai.Time_source.now t.time_source);
                      t.last_monotonic_ns <- monotonic_now_ns;
                      t.pending_presentation <- None;
                      t.force_full_snapshot_next <- false;
                      let lifecycle_started = now_ns () in
                      Bonsai_runtime_adapter.trigger_lifecycles t.bonsai;
                      t.last_lifecycle_ns <- elapsed_ns lifecycle_started;
                      Ok ()
                    with
                    | exception_ ->
                      fail_fatal (Lifecycle_error (exception_message exception_))))))))
;;

let presentation_rejected t ~presentation_id ~renderer_revision ~reason:_ =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match exact_pending t ~presentation_id ~renderer_revision with
     | Error _ as error -> error
     | Ok _ ->
       trace_lazy t (fun () ->
         Printf.sprintf
           "[presentation-rejected] presentationId=%Ld revision=%Ld"
           (ID.Runtime.Presentation_id.to_int64 presentation_id)
           (ID.Runtime.Renderer_revision.to_int64 renderer_revision));
       t.pending_presentation <- None;
       t.force_full_snapshot_next <- true;
       Ok ())
;;

let shutdown ?(application_error = Host_effect.Application_platform.Shutdown) t =
  if not t.is_shutdown
  then (
    t.before_shutdown ();
    t.is_shutdown <- true;
    Host_effect.Private.shutdown t.host_effects;
    Host_effect.Application_platform.Private.shutdown
      t.application_platform
      application_error;
    (try
       drain_effects t;
       Bonsai_runtime_adapter.flush t.bonsai
     with
     | _ -> ());
    Queue.clear t.pending_effects.pending_effects;
    Queue.clear t.pending_effects.pending_before_display;
    Runtime.Handler_registry.clear t.handlers;
    t.displayed_handler_frame <- None;
    t.displayed_application_theme <- None;
    Bonsai_runtime_adapter.shutdown t.bonsai)
;;

let is_shutdown t = t.is_shutdown

module For_testing = struct
  let create_widget_component
        ?trace
        ?before_flush
        ?before_shutdown
        ~runtime_epoch
        ~time_source
        component
    =
    let scheme =
      Ui.Theme.Color_scheme.from_seed
        ~color:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164)
        ()
    in
    let light =
      Ui.Theme.material ~brightness:Ui.Style.Brightness.Light ~color_scheme:scheme ()
    in
    let dark =
      Ui.Theme.material ~brightness:Ui.Style.Brightness.Dark ~color_scheme:scheme ()
    in
    let theme = Ui.Theme.application ~mode:Ui.Theme.System ~light ~dark () in
    create
      ?trace
      ?before_flush
      ?before_shutdown
      ~runtime_epoch
      ~time_source
      (fun handlers graph ->
         Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
           View.create ~theme ~body))
  ;;

  let runtime_epoch t = t.runtime_epoch
  let revision t = t.displayed_revision

  let snapshot t =
    match t.pending_presentation with
    | Some pending -> Some (Runtime.Mounted_tree.snapshot pending.candidate_tree)
    | None -> Option.map Runtime.Mounted_tree.snapshot t.displayed_tree
  ;;

  let environment t = Environment.Private.current t.environment
  let pending_host_effect_count t = Host_effect.Private.pending_count t.host_effects

  let pending_application_request_count t =
    Host_effect.Application_platform.Private.pending_count t.application_platform
  ;;

  let retained_handler_frame_count t =
    Runtime.Handler_registry.retained_frame_count t.handlers
  ;;

  let set_next_presentation_id t value =
    t.next_presentation_id <- value;
    t.presentation_sequence_exhausted <- false
  ;;

  let set_next_renderer_revision t value = t.next_renderer_revision <- value
end
