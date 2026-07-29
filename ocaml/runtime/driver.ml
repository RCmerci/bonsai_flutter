module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

module Handler = struct
  type t =
    { pending_effects : unit Bonsai.Effect.t Queue.t
    ; host_effects : Host_effect.t
    ; environment : Environment.t
    }

  let create_with_dependencies ~equal dependencies ~f =
    dependencies |> Bonsai.cutoff ~equal |> Bonsai.map ~f
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
  let environment t = t.environment
end

type frame =
  { revision : int64
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
  | Shutdown

type pump_result =
  { presentation_id : int64
  ; renderer_revision : int64
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
  | Shutdown -> "driver is shut down"
;;

type pending_presentation =
  { presentation_id : int64
  ; renderer_revision : int64
  ; candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; emitted_frame : frame option
  }

type t =
  { runtime_epoch : int64
  ; trace : (string -> unit) option
  ; time_source : Bonsai.Time_source.t
  ; logical_time_origin : Core.Time_ns.t
  ; bonsai : Ui.Widget.t Bonsai_runtime_adapter.t
  ; reconciler : Runtime.Reconciler.t
  ; handlers : Runtime.Handler_registry.t
  ; pending_effects : Handler.t
  ; host_effects : Host_effect.t
  ; environment : Environment.t
  ; mutable displayed_tree : Runtime.Mounted_tree.t option
  ; mutable displayed_revision : int64
  ; mutable last_monotonic_ns : int64
  ; mutable last_event_sequence : int64 option
  ; mutable next_presentation_id : int64
  ; mutable presentation_sequence_exhausted : bool
  ; mutable next_renderer_revision : int64
  ; mutable pending_presentation : pending_presentation option
  ; mutable force_full_snapshot_next : bool
  ; mutable terminal_error : error option
  ; mutable is_shutdown : bool
  ; mutable last_lifecycle_ns : int64
  ; mutable full_snapshot_count : int
  ; mutable resync_count : int
  }

let create ?trace ~runtime_epoch ~time_source component =
  if Int64.compare runtime_epoch 0L <= 0
  then invalid_arg "Driver.create: runtime_epoch must be positive";
  let pending_queue = Queue.create () in
  let host_effect_manager =
    Host_effect.Private.create ~schedule:(fun scheduled_effect ->
      Queue.add scheduled_effect pending_queue)
  in
  let environment_input = Environment.Private.create () in
  let pending_effects =
    Handler.
      { pending_effects = pending_queue
      ; host_effects = host_effect_manager
      ; environment = environment_input
      }
  in
  let bonsai = Bonsai_runtime_adapter.create ~time_source (component pending_effects) in
  { runtime_epoch
  ; trace
  ; time_source
  ; logical_time_origin = Bonsai.Time_source.now time_source
  ; bonsai
  ; reconciler = Runtime.Reconciler.create ~runtime_epoch
  ; handlers = Runtime.Handler_registry.create ~runtime_epoch
  ; pending_effects
  ; host_effects = host_effect_manager
  ; environment = environment_input
  ; displayed_tree = None
  ; displayed_revision = 0L
  ; last_monotonic_ns = -1L
  ; last_event_sequence = None
  ; next_presentation_id = 1L
  ; presentation_sequence_exhausted = false
  ; next_renderer_revision = 1L
  ; pending_presentation = None
  ; force_full_snapshot_next = false
  ; terminal_error = None
  ; is_shutdown = false
  ; last_lifecycle_ns = 0L
  ; full_snapshot_count = 0
  ; resync_count = 0
  }
;;

let trace t message =
  match t.trace with
  | None -> ()
  | Some sink ->
    (try sink message with
     | _ -> ())
;;

let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.)
let elapsed_ns start = Int64.sub (now_ns ()) start

let wire_frame_kind = function
  | Runtime.Frame_patch.Full_snapshot -> Protocol.Wire_frame.Full_snapshot
  | Incremental_frame -> Incremental_frame
;;

let wire_node_kind = function
  | Ui.Widget.Private.Kind.Empty -> Ok Protocol.Wire_frame.Empty
  | Text -> Ok Text
  | Rich_text -> Ok Rich_text
  | Icon -> Ok Icon
  | Image -> Ok Image
  | Row -> Ok Row
  | Column -> Ok Column
  | Flex_row -> Ok Row
  | Flex_column -> Ok Column
  | Stack -> Ok Stack
  | Button -> Ok Button
  | Padding -> Ok Padding
  | Align -> Ok Align
  | Center -> Ok Center
  | Sized_box -> Ok Sized_box
  | Constrained_box -> Ok Constrained_box
  | Decorated_box -> Ok Decorated_box
  | Clip -> Ok Clip
  | Opacity -> Ok Opacity
  | Animated_opacity -> Ok Animated_opacity
  | Transform -> Ok Transform
  | Scroll_view -> Ok Scroll_view
  | List_view -> Ok List_view
  | Gesture -> Ok Gesture
  | Focus_scope -> Ok Focus_scope
  | Mouse_region -> Ok Mouse_region
  | Keyboard_listener -> Ok Keyboard_listener
  | Semantics -> Ok Semantics
  | Theme -> Ok Theme
  | Material_scaffold -> Ok Material_scaffold
  | Material_app_bar -> Ok Material_app_bar
  | Material_elevated_button -> Ok Material_elevated_button
  | Material_text_button -> Ok Material_text_button
  | Material_icon_button -> Ok Material_icon_button
  | Material_checkbox -> Ok Material_checkbox
  | Material_switch -> Ok Material_switch
  | Material_list_tile -> Ok Material_list_tile
  | Material_divider -> Ok Material_divider
  | Material_card -> Ok Material_card
  | Material_circular_progress_indicator -> Ok Material_circular_progress_indicator
  | Cupertino_button -> Ok Cupertino_button
  | Cupertino_switch -> Ok Cupertino_switch
  | Text_input -> Ok Text_input
  | Overlay -> Ok Overlay
  | Navigator -> Ok Navigator
  | Page -> Ok Page
  | Safe_area -> Ok Safe_area
  | Environment_boundary -> Ok Environment_boundary
  | Material_dialog -> Ok Material_dialog
  | Native_widget -> Ok Native_widget
;;

let wire_props = function
  | Ui.Widget.Private.Empty_props -> Ok Protocol.Wire_frame.Empty_props
  | Stack_props -> Ok Empty_props
  | Text_props { value; style; text_align; max_lines; overflow } ->
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
  | Rich_text_props { spans } -> Ok (Rich_text_props { spans })
  | Icon_props { code_point; font_family; size; color } ->
    Ok (Icon_props { code_point; font_family; size; color })
  | Image_props { uri; fit; width; height } ->
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
  | Linear_props -> Ok Linear_props
  | Button_props { enabled } -> Ok (Button_props { enabled })
  | Padding_props { left; top; right; bottom } ->
    Ok (Padding_props { left; top; right; bottom })
  | Align_props { alignment } ->
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
  | Center_props { width_factor; height_factor } ->
    Ok (Center_props { width_factor; height_factor })
  | Sized_box_props { width; height } -> Ok (Sized_box_props { width; height })
  | Constrained_box_props { min_width; max_width; min_height; max_height } ->
    Ok (Constrained_box_props { min_width; max_width; min_height; max_height })
  | Decorated_box_props { background; border_radius } ->
    Ok (Decorated_box_props { background; border_radius })
  | Clip_props { behavior } ->
    let behavior =
      match behavior with
      | Ui.Style.Clip.Hard_edge -> Protocol.Wire_frame.Hard_edge
      | Anti_alias -> Anti_alias
      | Anti_alias_with_save_layer -> Anti_alias_with_save_layer
    in
    Ok (Clip_props { behavior })
  | Opacity_props { opacity } -> Ok (Opacity_props { opacity })
  | Animated_opacity_props { opacity; animation } ->
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
  | Transform_props { matrix4 } -> Ok (Transform_props { matrix4 = Array.copy matrix4 })
  | Scroll_view_props { axis; reverse } ->
    let axis =
      match axis with
      | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
      | Vertical -> Vertical
    in
    Ok (Scroll_view_props { axis; reverse })
  | List_view_props { axis; reverse } ->
    let axis =
      match axis with
      | Ui.Layout.Axis.Horizontal -> Protocol.Wire_frame.Horizontal
      | Vertical -> Vertical
    in
    Ok (List_view_props { axis; reverse })
  | Gesture_props -> Ok Gesture_props
  | Focus_scope_props { autofocus } -> Ok (Focus_scope_props { autofocus })
  | Mouse_region_props { opaque } -> Ok (Mouse_region_props { opaque })
  | Keyboard_listener_props { autofocus; key_policy } ->
    let key_policy =
      match key_policy with
      | Ui.Event.Key_policy.Handled -> Protocol.Wire_frame.Handled
      | Ignored -> Ignored
    in
    Ok (Keyboard_listener_props { autofocus; key_policy })
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
  | Theme_props { brightness; color_seed } ->
    let brightness =
      match brightness with
      | Ui.Style.Brightness.Light -> Protocol.Wire_frame.Light
      | Dark -> Dark
    in
    Ok (Theme_props { brightness; color_seed })
  | Material_scaffold_props { has_app_bar } ->
    Ok (Material_scaffold_props { has_app_bar })
  | Material_app_bar_props { center_title } ->
    Ok (Material_app_bar_props { center_title })
  | Material_button_props { variant; enabled; autofocus } ->
    let variant =
      match variant with
      | Ui.Widget.Private.Elevated -> Protocol.Wire_frame.Elevated
      | Text_button -> Text_button
      | Icon_button -> Icon_button
    in
    Ok (Material_button_props { variant; enabled; autofocus })
  | Material_checkbox_props { value; enabled } ->
    Ok (Material_checkbox_props { value; enabled })
  | Material_switch_props { value; enabled } ->
    Ok (Material_switch_props { value; enabled })
  | Material_list_tile_props
      { enabled; selected; has_subtitle; has_leading; has_trailing } ->
    Ok
      (Material_list_tile_props
         { enabled; selected; has_subtitle; has_leading; has_trailing })
  | Material_divider_props { thickness } -> Ok (Material_divider_props { thickness })
  | Material_card_props { elevation } -> Ok (Material_card_props { elevation })
  | Material_progress_props { value } -> Ok (Material_progress_props { value })
  | Cupertino_button_props { enabled } -> Ok (Cupertino_button_props { enabled })
  | Cupertino_switch_props { value; enabled } ->
    Ok (Cupertino_switch_props { value; enabled })
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
         })
  | Overlay_props { alignment; dismissible } ->
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
  | Navigator_props { restoration_scope_id } ->
    Ok (Navigator_props { restoration_scope_id })
  | Page_props { page_key; transition; can_pop; restoration_id } ->
    let transition =
      match transition with
      | Ui.Navigation.None -> Protocol.Wire_frame.No_transition
      | Fade -> Fade
      | Slide -> Slide
    in
    Ok (Page_props { page_key; transition; can_pop; restoration_id })
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
  | Environment_boundary_props -> Ok Environment_boundary_props
  | Material_dialog_props { barrier_dismissible } ->
    Ok (Material_dialog_props { barrier_dismissible })
  | Native_widget_props { kind_id; version; capabilities; payload } ->
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
  | Scroll_notification -> Tag.scroll_notification
  | Visible_range_changed -> Tag.visible_range_changed
  | Animation_completed -> Tag.animation_completed
  | Route_pop -> Tag.route_pop
  | Layout_observed -> Tag.layout_observed
  | Value_changed -> Tag.value_changed
  | Native_event -> Tag.native_event
  | Semantics_action -> Tag.semantics_action
;;

let wire_bindings bindings =
  Array.to_list bindings
  |> List.map (fun (binding : Runtime.Mounted_tree.Mounted_binding.t) ->
    Protocol.Wire_frame.
      { event_tag = wire_event_tag binding.event_tag
      ; handler_id = Runtime.Handler_id.to_int64 binding.handler_id
      })
;;

let wire_operation = function
  | Runtime.Frame_patch.Operation.Create_node
      { node_id; kind; props; event_bindings; parent_data; _ } ->
    (match wire_node_kind kind, wire_props props with
     | Ok kind, Ok props ->
       Ok
         (Protocol.Wire_frame.Create_node
            { node_id = Runtime.Node_id.to_int64 node_id
            ; kind
            ; props
            ; event_bindings = wire_bindings event_bindings
            ; parent_data = wire_parent_data parent_data
            })
     | Error error, _ | _, Error error -> Error error)
  | Update_props { node_id; props } ->
    (match wire_props props with
     | Ok props ->
       Ok
         (Protocol.Wire_frame.Update_props
            { node_id = Runtime.Node_id.to_int64 node_id; props })
     | Error error -> Error error)
  | Update_event_bindings { node_id; event_bindings } ->
    Ok
      (Protocol.Wire_frame.Update_event_bindings
         { node_id = Runtime.Node_id.to_int64 node_id
         ; event_bindings = wire_bindings event_bindings
         })
  | Set_children { node_id; children } ->
    Ok
      (Protocol.Wire_frame.Set_children
         { node_id = Runtime.Node_id.to_int64 node_id
         ; children = Array.to_list children |> List.map Runtime.Node_id.to_int64
         })
  | Set_root node_id ->
    Ok (Protocol.Wire_frame.Set_root (Runtime.Node_id.to_int64 node_id))
  | Drop_node node_id ->
    Ok (Protocol.Wire_frame.Drop_node (Runtime.Node_id.to_int64 node_id))
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
  List.iter
    (function
      | Protocol.Wire_frame.Create_node _ -> incr create_node
      | Update_props _ -> incr update_props
      | Update_event_bindings _ -> incr update_event_bindings
      | Set_children _ -> incr set_children
      | Set_root _ -> incr set_root
      | Drop_node _ -> incr drop_node
      | Host_request _ -> incr host_request
      | Cancel_host_request _ -> incr cancel_host_request
      | Runtime_stats _ -> ())
    operations;
  Printf.sprintf
    "createNode=%d updateProps=%d updateEventBindings=%d setChildren=%d setRoot=%d \
     dropNode=%d hostRequest=%d cancelHostRequest=%d"
    !create_node
    !update_props
    !update_event_bindings
    !set_children
    !set_root
    !drop_node
    !host_request
    !cancel_host_request
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
      | Update_props { node_id; _ } -> add "updateProps" node_id new_tree
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
  if not (Runtime.Frame_patch.is_empty frame_patch)
  then (
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
    trace
      t
      (Printf.sprintf
         "[widget-diff] targetRevision=%Ld kind=%s\n%s"
         target_revision
         (frame_kind_name frame_kind)
         diff))
;;

type produced_candidate =
  { candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; renderer_revision : int64
  ; emitted_frame : frame option
  }

let produce_candidate t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot =
  if Int64.equal t.next_renderer_revision Int64.max_int
  then Error (Invalid_state "renderer revision counter exhausted")
  else (
    let target_revision = t.next_renderer_revision in
    let result_started = now_ns () in
    let widget = Bonsai_runtime_adapter.result t.bonsai in
    let result_read_ns = elapsed_ns result_started in
    let reconcile_started = now_ns () in
    match
      Runtime.Reconciler.reconcile
        t.reconciler
        ~base_revision:t.displayed_revision
        ~target_revision
        ~old:(if force_full_snapshot then None else t.displayed_tree)
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
      if Runtime.Frame_patch.is_empty output.frame_patch && host_operations = []
      then (
        trace t (Printf.sprintf "[outbound-no-frame] revision=%Ld" t.displayed_revision);
        Ok
          { candidate_tree = output.mounted_tree
          ; candidate_handler_frame = None
          ; prepared_host_operations
          ; renderer_revision = t.displayed_revision
          ; emitted_frame = None
          })
      else (
        match wire_operations (Runtime.Frame_patch.operations output.frame_patch) with
        | Error _ as error -> error
        | Ok ui_operations ->
          let operations = ui_operations @ host_operations in
          let frame_kind = Runtime.Frame_patch.kind output.frame_patch in
          let base_revision =
            match frame_kind with
            | Runtime.Frame_patch.Full_snapshot -> 0L
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
          (match Protocol.Binary_codec.encode (wire_frame stats) with
           | Error error -> Error (Codec_error error)
           | Ok provisional_bytes ->
             let stats =
               { stats with
                 encode_ns = elapsed_ns encode_started
               ; patch_bytes = Bytes.length provisional_bytes
               }
             in
             (match Protocol.Binary_codec.encode (wire_frame stats) with
              | Error error -> Error (Codec_error error)
              | Ok bytes ->
                let frame =
                  { revision = target_revision
                  ; frame_patch = output.frame_patch
                  ; bytes
                  ; stats
                  }
                in
                t.next_renderer_revision <- Int64.succ target_revision;
                trace
                  t
                  (Printf.sprintf
                     "[outbound-frame] direction=ocaml->flutter epoch=%Ld kind=%s \
                      baseRevision=%Ld targetRevision=%Ld operations=%d bytes=%d\n\
                     \  operationSummary=%s"
                     t.runtime_epoch
                     (frame_kind_name frame_kind)
                     base_revision
                     target_revision
                     (List.length operations)
                     (Bytes.length bytes)
                     (operation_summary operations));
                Ok
                  { candidate_tree = output.mounted_tree
                  ; candidate_handler_frame = Some output.handler_frame
                  ; prepared_host_operations
                  ; renderer_revision = target_revision
                  ; emitted_frame = Some frame
                  }))))
;;

let event_tag_name event_tag =
  match Protocol.Generated_protocol.Event_tag.debug_name event_tag with
  | Some name -> name
  | None -> Printf.sprintf "unknown(%d)" event_tag
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
  | Text value -> Printf.sprintf "text(bytes=%d)" (String.length value)
  | Text_edit edit ->
    Printf.sprintf
      "text_edit(session=%Ld localRevision=%Ld baseDocumentRevision=%Ld bytes=%d)"
      edit.session_id
      edit.local_revision
      edit.base_document_revision
      (String.length edit.text)
  | Int64 value -> Printf.sprintf "int64(%Ld)" value
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
      pointer.pointer_id
      pointer.local_x
      pointer.local_y
      pointer.global_x
      pointer.global_y
      (pointer_kind_name pointer.pointer_kind)
      pointer.buttons
  | Key key ->
    Printf.sprintf
      "key(logical=%Ld physical=%Ld action=%s modifiers=%d)"
      key.logical_key
      key.physical_key
      (key_action_name key.action)
      key.modifiers
  | Scroll { pixels; delta } -> Printf.sprintf "scroll(pixels=%g delta=%g)" pixels delta
  | Visible_range { first_index; last_exclusive } ->
    Printf.sprintf "visible_range(first=%Ld lastExclusive=%Ld)" first_index last_exclusive
  | Route_pop route ->
    Printf.sprintf
      "route_pop(pageKey=%S resultBytes=%d)"
      route.page_key
      (Option.fold ~none:0 ~some:String.length route.result)
  | Host_response response ->
    Printf.sprintf
      "host_response(request=%Ld status=%s bytes=%d)"
      response.request_id
      (host_response_status_name response.status)
      (Bytes.length response.value)
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
      event.kind_id
      event.version
      event.event_id
      (Bytes.length event.payload)
;;

let trace_inbound_event_batch t (batch : Protocol.Inbound_event.batch) =
  let output = Buffer.create 256 in
  Printf.bprintf
    output
    "[inbound-event-batch] direction=flutter->ocaml epoch=%Ld events=%d"
    batch.runtime_epoch
    (List.length batch.events);
  List.iter
    (fun (event : Protocol.Inbound_event.t) ->
       Printf.bprintf
         output
         "\n  sequence=%Ld displayedRevision=%Ld node=%Ld handler=%Ld tag=%s payload=%s"
         event.sequence
         event.displayed_revision
         event.node_id
         event.handler_id
         (event_tag_name event.event_tag)
         (payload_summary event.payload))
    batch.events;
  trace t (Buffer.contents output)
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
  | Validated_environment of Environment.snapshot
  | Validated_resync

type validated_input =
  { ui_events : Runtime.Event_dispatcher.Validated_batch.t option
  ; controls : validated_control list
  ; last_event_sequence : int64 option
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

let validate_input t (batch : Protocol.Inbound_event.batch) =
  if not (Int64.equal batch.runtime_epoch t.runtime_epoch)
  then Error (Host_response_error "runtime epoch mismatch")
  else (
    let seen_host_responses = Hashtbl.create 8 in
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
          | Some previous -> Int64.compare event.sequence previous <= 0
          | None -> false
        then
          Error
            (Host_response_error
               (Printf.sprintf
                  "duplicate or out-of-order event sequence %Ld"
                  event.sequence))
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
          if is_host_response || is_environment || is_resync
          then
            if
              (not (Int64.equal event.node_id 0L))
              || (not (Int64.equal event.handler_id 0L))
              || not (Int64.equal event.displayed_revision t.displayed_revision)
            then Error (Host_response_error "malformed runtime control event")
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
                          response.request_id))
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
    if Int64.equal presentation_id Int64.max_int
    then t.presentation_sequence_exhausted <- true
    else t.next_presentation_id <- Int64.succ presentation_id;
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
             drain_effects t;
             let flush_started = now_ns () in
             Bonsai_runtime_adapter.flush t.bonsai;
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
                    ; prepared_host_operations = candidate.prepared_host_operations
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
    if not (Int64.equal pending.presentation_id presentation_id)
    then Error (Invalid_state "presentation ID does not match the pending token")
    else if not (Int64.equal pending.renderer_revision renderer_revision)
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
          trace
            t
            (Printf.sprintf
               "[presentation-ack] presentationId=%Ld revision=%Ld \
                direction=flutter->ocaml"
               presentation_id
               renderer_revision);
          let fail_fatal error = Error (terminal t error) in
          (match
             Host_effect.commit_operations t.host_effects pending.prepared_host_operations
           with
           | Error message -> fail_fatal (Invalid_state message)
           | Ok () ->
             t.displayed_tree <- Some pending.candidate_tree;
             let commit_handler =
               match pending.emitted_frame, pending.candidate_handler_frame with
               | None, None -> Ok ()
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
                     | Ok () ->
                       t.displayed_revision <- renderer_revision;
                       Runtime.Handler_registry.retire_superseded
                         t.handlers
                         ~displayed_revision:renderer_revision;
                       Ok ()))
               | None, Some _ | Some _, None ->
                 Error
                   (Invalid_state "candidate frame and handler metadata are inconsistent")
             in
             (match commit_handler with
              | Error error -> fail_fatal error
              | Ok () ->
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
                   fail_fatal (Lifecycle_error (exception_message exception_)))))))
;;

let presentation_rejected t ~presentation_id ~renderer_revision ~reason:_ =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match exact_pending t ~presentation_id ~renderer_revision with
     | Error _ as error -> error
     | Ok _ ->
       trace
         t
         (Printf.sprintf
            "[presentation-rejected] presentationId=%Ld revision=%Ld"
            presentation_id
            renderer_revision);
       t.pending_presentation <- None;
       t.force_full_snapshot_next <- true;
       Ok ())
;;

let shutdown t =
  if not t.is_shutdown
  then (
    t.is_shutdown <- true;
    Host_effect.Private.shutdown t.host_effects;
    Queue.clear t.pending_effects.pending_effects;
    Runtime.Handler_registry.clear t.handlers;
    Bonsai_runtime_adapter.shutdown t.bonsai)
;;

let is_shutdown t = t.is_shutdown

module For_testing = struct
  let runtime_epoch t = t.runtime_epoch
  let revision t = t.displayed_revision

  let snapshot t =
    match t.pending_presentation with
    | Some pending -> Some (Runtime.Mounted_tree.snapshot pending.candidate_tree)
    | None -> Option.map Runtime.Mounted_tree.snapshot t.displayed_tree
  ;;

  let environment t = Environment.Private.current t.environment
  let pending_host_effect_count t = Host_effect.Private.pending_count t.host_effects

  let retained_handler_frame_count t =
    Runtime.Handler_registry.retained_frame_count t.handlers
  ;;

  let set_next_presentation_id t value =
    t.next_presentation_id <- value;
    t.presentation_sequence_exhausted <- false
  ;;

  let set_next_renderer_revision t value = t.next_renderer_revision <- value
end
