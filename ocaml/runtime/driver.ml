module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

module Handler = struct
  type t =
    { pending_effects : unit Bonsai.Effect.t Queue.t
    ; host_effects : Host_effect.t
    ; environment : Environment.t
    }

  let create t ?name make_effect =
    Ui.Event.Handler.create ?name (fun payload ->
      Queue.add (make_effect payload) t.pending_effects)
  ;;

  let create_native t ?name extension make_effect =
    Ui.Native_widget.event_handler ?name extension (fun event ->
      Queue.add (make_effect event) t.pending_effects)
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

type t =
  { runtime_epoch : int64
  ; bonsai : Ui.Widget.t Bonsai_runtime_adapter.t
  ; reconciler : Runtime.Reconciler.t
  ; handlers : Runtime.Handler_registry.t
  ; pending_effects : Handler.t
  ; host_effects : Host_effect.t
  ; environment : Environment.t
  ; mutable mounted_tree : Runtime.Mounted_tree.t option
  ; mutable revision : int64
  ; mutable is_shutdown : bool
  ; mutable last_lifecycle_ns : int64
  ; mutable full_snapshot_count : int
  ; mutable resync_count : int
  }

let create ~runtime_epoch ~time_source component =
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
  ; bonsai
  ; reconciler = Runtime.Reconciler.create ~runtime_epoch
  ; handlers = Runtime.Handler_registry.create ~runtime_epoch
  ; pending_effects
  ; host_effects = host_effect_manager
  ; environment = environment_input
  ; mounted_tree = None
  ; revision = 0L
  ; is_shutdown = false
  ; last_lifecycle_ns = 0L
  ; full_snapshot_count = 0
  ; resync_count = 0
  }
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
  | Text_props { value } -> Ok (Text_props { value })
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

let next_revision revision =
  if Int64.equal revision Int64.max_int
  then Error (Invalid_state "revision counter exhausted")
  else Ok (Int64.succ revision)
;;

let produce_frame t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot =
  match next_revision t.revision with
  | Error _ as error -> error
  | Ok target_revision ->
    let result_started = now_ns () in
    let widget = Bonsai_runtime_adapter.result t.bonsai in
    let result_read_ns = elapsed_ns result_started in
    let reconcile_started = now_ns () in
    (match
       Runtime.Reconciler.reconcile
         t.reconciler
         ~base_revision:t.revision
         ~target_revision
         ~old:(if force_full_snapshot then None else t.mounted_tree)
         widget
     with
     | Error error -> Error (Runtime_error error)
     | Ok output ->
       let reconcile_ns = elapsed_ns reconcile_started in
       let host_operations = Host_effect.Private.take_operations t.host_effects in
       if Runtime.Frame_patch.is_empty output.frame_patch && host_operations = []
       then Ok None
       else (
         match wire_operations (Runtime.Frame_patch.operations output.frame_patch) with
         | Error _ as error -> error
         | Ok ui_operations ->
           let operations = ui_operations @ host_operations in
           let frame_kind = Runtime.Frame_patch.kind output.frame_patch in
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
               ; base_revision =
                   (match frame_kind with
                    | Runtime.Frame_patch.Full_snapshot -> 0L
                    | Incremental_frame -> t.revision)
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
                 (match
                    Runtime.Handler_registry.install t.handlers output.handler_frame
                  with
                  | Error error -> Error (Runtime_error error)
                  | Ok () ->
                    t.mounted_tree <- Some output.mounted_tree;
                    t.revision <- target_revision;
                    Ok
                      (Some
                         { revision = target_revision
                         ; frame_patch = output.frame_patch
                         ; bytes
                         ; stats
                         }))))))
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

let step t ?events () =
  if t.is_shutdown
  then Error Shutdown
  else (
    let force_full_snapshot = ref false in
    let dispatch_result =
      match events with
      | None -> Ok ()
      | Some (events : Protocol.Inbound_event.batch) ->
        let control_events, ui_events =
          List.partition
            (fun (event : Protocol.Inbound_event.t) ->
               event.event_tag = Protocol.Generated_protocol.Event_tag.host_response
               || event.event_tag
                  = Protocol.Generated_protocol.Event_tag.environment_changed
               || event.event_tag = Protocol.Generated_protocol.Event_tag.resync_requested)
            events.events
        in
        let ui_batch = Protocol.Inbound_event.{ events with events = ui_events } in
        let dispatch_ui =
          match ui_events with
          | [] -> Ok ()
          | _ ->
            (match Runtime.Event_dispatcher.dispatch_batch t.handlers ui_batch with
             | Ok () -> Ok ()
             | Error error -> Error (Event_error error))
        in
        (match dispatch_ui with
         | Error _ as error -> error
         | Ok () ->
           if not (Int64.equal events.runtime_epoch t.runtime_epoch)
           then Error (Host_response_error "runtime epoch mismatch")
           else (
             let rec resolve = function
               | [] -> Ok ()
               | (event : Protocol.Inbound_event.t) :: rest ->
                 (match event.payload with
                  | Host_response response
                    when Int64.equal event.node_id 0L && Int64.equal event.handler_id 0L
                    ->
                    (match Host_effect.Private.resolve t.host_effects response with
                     | Ok () -> resolve rest
                     | Error message -> Error (Host_response_error message))
                  | Environment_changed environment
                    when Int64.equal event.node_id 0L && Int64.equal event.handler_id 0L
                    ->
                    ignore
                      (Environment.Private.update
                         t.environment
                         (environment_of_protocol environment));
                    resolve rest
                  | Unit
                    when event.event_tag
                         = Protocol.Generated_protocol.Event_tag.resync_requested
                         && Int64.equal event.node_id 0L
                         && Int64.equal event.handler_id 0L ->
                    force_full_snapshot := true;
                    resolve rest
                  | _ -> Error (Host_response_error "malformed runtime control event"))
             in
             resolve control_events))
    in
    match dispatch_result with
    | Error _ as error ->
      Queue.clear t.pending_effects.pending_effects;
      error
    | Ok () ->
      drain_effects t;
      let flush_started = now_ns () in
      Bonsai_runtime_adapter.flush t.bonsai;
      let bonsai_flush_ns = elapsed_ns flush_started in
      let event_batch_size =
        match events with
        | None -> 0
        | Some events -> List.length events.Protocol.Inbound_event.events
      in
      produce_frame
        t
        ~event_batch_size
        ~bonsai_flush_ns
        ~force_full_snapshot:!force_full_snapshot)
;;

let exception_message exception_ =
  match exception_ with
  | Failure message | Invalid_argument message -> message
  | _ -> Printexc.to_string exception_
;;

let frame_presented t ~revision =
  if t.is_shutdown
  then Error Shutdown
  else (
    match Runtime.Handler_registry.mark_frame_presented t.handlers ~revision with
    | Error error -> Error (Runtime_error error)
    | Ok () ->
      let lifecycle_started = now_ns () in
      (try
         Bonsai_runtime_adapter.frame_presented t.bonsai;
         Runtime.Handler_registry.retire_superseded
           t.handlers
           ~displayed_revision:revision;
         t.last_lifecycle_ns <- elapsed_ns lifecycle_started;
         Ok ()
       with
       | exception_ ->
         t.last_lifecycle_ns <- elapsed_ns lifecycle_started;
         Error (Lifecycle_error (exception_message exception_))))
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
  let revision t = t.revision
  let snapshot t = Option.map Runtime.Mounted_tree.snapshot t.mounted_tree
  let environment t = Environment.Private.current t.environment
  let pending_host_effect_count t = Host_effect.Private.pending_count t.host_effects

  let retained_handler_frame_count t =
    Runtime.Handler_registry.retained_frame_count t.handlers
  ;;
end
