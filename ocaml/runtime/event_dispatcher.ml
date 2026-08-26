module ID = Bonsai_flutter_spec.Id
module Protocol_event = Bonsai_flutter_protocol.Inbound_event
module Ui_event = Bonsai_flutter_ui.Event

type error =
  | Invalid_event of string
  | Handler_error of Runtime_error.t

let invalid format = Printf.ksprintf (fun message -> Error (Invalid_event message)) format

let convert_tag tag =
  let module Id = Bonsai_flutter_protocol.Generated_protocol.Event_tag in
  if tag = Id.press
  then Ok Ui_event.Tag.Press
  else if tag = Id.long_press
  then Ok Long_press
  else if tag = Id.tap
  then Ok Tap
  else if tag = Id.double_tap
  then Ok Double_tap
  else if tag = Id.pointer_enter
  then Ok Pointer_enter
  else if tag = Id.pointer_leave
  then Ok Pointer_leave
  else if tag = Id.pointer_down
  then Ok Pointer_down
  else if tag = Id.pointer_up
  then Ok Pointer_up
  else if tag = Id.key
  then Ok Key
  else if tag = Id.semantics_action
  then Ok Semantics_action
  else if tag = Id.focus_changed
  then Ok Focus_changed
  else if tag = Id.value_changed
  then Ok Value_changed
  else if tag = Id.text_edit
  then Ok Text_edit
  else if tag = Id.text_submit
  then Ok Text_submit
  else if tag = Id.scroll_notification
  then Ok Scroll_notification
  else if tag = Id.visible_range_changed
  then Ok Visible_range_changed
  else if tag = Id.animation_completed
  then Ok Animation_completed
  else if tag = Id.route_pop
  then Ok Route_pop
  else if tag = Id.native_event
  then Ok Native_event
  else if tag = Id.navigation_destination_selected
  then Ok Navigation_destination_selected
  else if tag = Id.radio_selected
  then Ok Radio_selected
  else if tag = Id.segmented_selection_changed
  then Ok Segmented_selection_changed
  else if tag = Id.slider_changed
  then Ok Slider_changed
  else if tag = Id.slider_change_end
  then Ok Slider_change_end
  else if tag = Id.range_slider_changed
  then Ok Range_slider_changed
  else if tag = Id.range_slider_change_end
  then Ok Range_slider_change_end
  else if tag = Id.delete
  then Ok Delete
  else invalid "unsupported event tag %d" (ID.Protocol.Event_tag.to_int tag)
;;

let convert_payload tag payload =
  let module Id = Bonsai_flutter_protocol.Generated_protocol.Event_tag in
  let pointer_kind = function
    | Protocol_event.Mouse -> Ui_event.Payload.Mouse
    | Touch -> Touch
    | Stylus -> Stylus
    | Inverted_stylus -> Inverted_stylus
    | Trackpad -> Trackpad
    | Unknown_pointer -> Unknown_pointer
  in
  match payload with
  | Protocol_event.Unit when tag = Id.press || tag = Id.long_press ->
    Ok Ui_event.Payload.Unit
  | Bool value when tag = Id.focus_changed || tag = Id.value_changed -> Ok (Bool value)
  | Tap { local_x; local_y; global_x; global_y; pointer_kind = kind }
    when tag = Id.tap || tag = Id.double_tap ->
    Ok (Tap { local_x; local_y; global_x; global_y; pointer_kind = pointer_kind kind })
  | Pointer
      { pointer_id; local_x; local_y; global_x; global_y; pointer_kind = kind; buttons }
    when tag = Id.pointer_enter
         || tag = Id.pointer_leave
         || tag = Id.pointer_down
         || tag = Id.pointer_up ->
    Ok
      (Pointer
         { pointer_id
         ; local_x
         ; local_y
         ; global_x
         ; global_y
         ; pointer_kind = pointer_kind kind
         ; buttons
         })
  | Key { logical_key; physical_key; action; modifiers } when tag = Id.key ->
    let action =
      match action with
      | Protocol_event.Key_down -> Ui_event.Payload.Key_down
      | Key_up -> Key_up
      | Key_repeat -> Key_repeat
    in
    Ok (Key { logical_key; physical_key; action; modifiers })
  | Int64 value when tag = Id.semantics_action -> Ok (Int64 value)
  | Text value when tag = Id.text_submit -> Ok (Text value)
  | Text_edit edit when tag = Id.text_edit ->
    let selection =
      Ui_event.Payload.
        { start_utf16 = edit.selection.start_utf16; end_utf16 = edit.selection.end_utf16 }
    in
    let composing =
      Option.map
        (fun (composing : Protocol_event.text_selection) ->
           Ui_event.Payload.
             { start_utf16 = composing.start_utf16; end_utf16 = composing.end_utf16 })
        edit.composing
    in
    Ok
      (Text_edit
         { session_id = edit.session_id
         ; local_revision = edit.local_revision
         ; base_document_revision = edit.base_document_revision
         ; text = edit.text
         ; selection
         ; composing
         })
  | Int64 value when tag = Id.animation_completed -> Ok (Int64 value)
  | Int64 value when tag = Id.navigation_destination_selected || tag = Id.radio_selected
    -> Ok (Int64 value)
  | Int64_list values when tag = Id.segmented_selection_changed -> Ok (Int64_list values)
  | Float value when tag = Id.slider_changed || tag = Id.slider_change_end ->
    Ok (Float value)
  | Float_range { start; end_ }
    when tag = Id.range_slider_changed || tag = Id.range_slider_change_end ->
    Ok (Float_range { start; end_ })
  | Unit when tag = Id.delete -> Ok Unit
  | Scroll { pixels; delta } when tag = Id.scroll_notification ->
    Ok (Scroll { pixels; delta })
  | Visible_range { first_index; last_exclusive } when tag = Id.visible_range_changed ->
    Ok (Visible_range { first_index; last_exclusive })
  | Route_pop { page_key; result } when tag = Id.route_pop ->
    Ok (Route_pop { page_key; result })
  | Native_event { kind_id; version; event_id; payload } when tag = Id.native_event ->
    Ok (Native_event { kind_id; version; event_id; payload })
  | _ -> invalid "payload does not match event tag %d" (ID.Protocol.Event_tag.to_int tag)
;;

let convert_event ~runtime_epoch (event : Protocol_event.t) =
  match convert_tag event.event_tag, convert_payload event.event_tag event.payload with
  | Ok event_tag, Ok payload ->
    Ok
      Handler_registry.
        { runtime_epoch
        ; displayed_revision = event.displayed_revision
        ; node_id = event.node_id
        ; event_tag
        ; handler_id = event.handler_id
        ; event_sequence = event.sequence
        ; payload
        }
  | Error error, _ | _, Error error -> Error error
;;

let convert_batch (batch : Protocol_event.batch) =
  let rec loop reversed = function
    | [] -> Ok (List.rev reversed)
    | event :: rest ->
      (match convert_event ~runtime_epoch:batch.runtime_epoch event with
       | Ok event -> loop (event :: reversed) rest
       | Error error -> Error error)
  in
  loop [] batch.events
;;

module Validated_batch = struct
  type t = Handler_registry.Validated_batch.t
end

let validate_batch registry batch =
  match convert_batch batch with
  | Error error -> Error error
  | Ok events ->
    (match Handler_registry.validate_batch registry events with
     | Ok validated -> Ok validated
     | Error error -> Error (Handler_error error))
;;

let dispatch_validated registry validated =
  match Handler_registry.dispatch_validated registry validated with
  | Ok () -> Ok ()
  | Error error -> Error (Handler_error error)
;;

let dispatch_batch registry batch =
  match validate_batch registry batch with
  | Error _ as error -> error
  | Ok validated -> dispatch_validated registry validated
;;
