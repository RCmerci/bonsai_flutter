module ID = Bonsai_flutter_spec.Id

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_payload_length
  | Too_many_events
  | Unknown_event_tag
  | Invalid_payload
  | Invalid_utf8
  | Truncated_input
  | Trailing_bytes

type error =
  { code : error_code
  ; message : string
  }

exception Decode_error of error

let fail code format =
  Printf.ksprintf (fun message -> raise (Decode_error { code; message })) format
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

  let u64_bits reader =
    let result = ref 0L in
    for shift = 0 to 7 do
      result
      := Int64.logor !result (Int64.shift_left (Int64.of_int (u8 reader)) (shift * 8))
    done;
    !result
  ;;

  let u64 reader =
    let result = u64_bits reader in
    if Int64.compare result 0L < 0
    then fail Invalid_payload "u64 exceeds the supported positive int64 range";
    result
  ;;

  let f64 reader = Int64.float_of_bits (u64_bits reader)

  let string reader length =
    require reader length;
    let value = Bytes.sub_string reader.bytes reader.position length in
    reader.position <- reader.position + length;
    value
  ;;

  let bytes reader length =
    require reader length;
    let value = Bytes.sub reader.bytes reader.position length in
    reader.position <- reader.position + length;
    value
  ;;

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
end

module Writer = struct
  let create () = Buffer.create 128
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
  then fail Invalid_payload "string is %d bytes" length;
  let value = Reader.string reader length in
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  value
;;

let read_optional_string reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_string reader)
  | value -> fail Invalid_payload "invalid optional string tag %d" value
;;

let require_empty reader =
  if Reader.remaining reader <> 0
  then fail Trailing_bytes "event has %d trailing bytes" (Reader.remaining reader)
;;

let read_bool reader =
  match Reader.u8 reader with
  | 0 -> false
  | 1 -> true
  | value -> fail Invalid_payload "invalid bool %d" value
;;

let read_finite_f64 reader =
  let value = Reader.f64 reader in
  if not (Float.is_finite value)
  then fail Invalid_payload "environment value must be finite";
  value
;;

let read_edge_insets reader =
  let left = read_finite_f64 reader in
  let top = read_finite_f64 reader in
  let right = read_finite_f64 reader in
  let bottom = read_finite_f64 reader in
  Inbound_event.{ left; top; right; bottom }
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
        let scalar = Uchar.utf_decode_uchar decoded in
        loop
          (byte_offset + Uchar.utf_decode_length decoded)
          (utf16_offset + if Uchar.to_int scalar > 0xffff then 2 else 1))
    in
    loop 0 0)
;;

let read_text_selection reader text =
  let start_utf16 = Reader.u32 reader in
  let end_utf16 = Reader.u32 reader in
  if start_utf16 > end_utf16 then fail Invalid_payload "text range is reversed";
  if not (is_utf16_boundary text start_utf16 && is_utf16_boundary text end_utf16)
  then fail Invalid_payload "text range is not on a UTF-16 boundary";
  Inbound_event.{ start_utf16; end_utf16 }
;;

let read_pointer_kind reader =
  match Reader.u8 reader with
  | 0 -> Inbound_event.Mouse
  | 1 -> Touch
  | 2 -> Stylus
  | 3 -> Inverted_stylus
  | 4 -> Trackpad
  | 5 -> Unknown_pointer
  | value -> fail Invalid_payload "invalid pointer kind %d" value
;;

let read_position reader =
  let local_x = Reader.f64 reader in
  let local_y = Reader.f64 reader in
  let global_x = Reader.f64 reader in
  let global_y = Reader.f64 reader in
  if not (List.for_all Float.is_finite [ local_x; local_y; global_x; global_y ])
  then fail Invalid_payload "pointer coordinates must be finite";
  local_x, local_y, global_x, global_y
;;

let read_payload reader event_tag =
  if
    event_tag = Generated_protocol.Event_tag.press
    || event_tag = Generated_protocol.Event_tag.long_press
    || event_tag = Generated_protocol.Event_tag.resync_requested
  then Inbound_event.Unit
  else if
    event_tag = Generated_protocol.Event_tag.tap
    || event_tag = Generated_protocol.Event_tag.double_tap
  then (
    let local_x, local_y, global_x, global_y = read_position reader in
    let pointer_kind = read_pointer_kind reader in
    Tap { local_x; local_y; global_x; global_y; pointer_kind })
  else if
    event_tag = Generated_protocol.Event_tag.pointer_enter
    || event_tag = Generated_protocol.Event_tag.pointer_leave
    || event_tag = Generated_protocol.Event_tag.pointer_down
    || event_tag = Generated_protocol.Event_tag.pointer_up
  then (
    let pointer_id = Reader.u64 reader |> ID.Input.Pointer_id.of_int64 in
    let local_x, local_y, global_x, global_y = read_position reader in
    let pointer_kind = read_pointer_kind reader in
    let buttons = Reader.u32 reader in
    Pointer { pointer_id; local_x; local_y; global_x; global_y; pointer_kind; buttons })
  else if
    event_tag = Generated_protocol.Event_tag.focus_changed
    || event_tag = Generated_protocol.Event_tag.value_changed
  then Bool (read_bool reader)
  else if event_tag = Generated_protocol.Event_tag.text_edit
  then (
    let session_id = Reader.u64 reader |> ID.Text_input.Session_id.of_int64 in
    let local_revision = Reader.u64 reader |> ID.Text_input.Local_revision.of_int64 in
    let base_document_revision =
      Reader.u64 reader |> ID.Text_input.Document_revision.of_int64
    in
    let text = read_string reader in
    let selection = read_text_selection reader text in
    let composing =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (read_text_selection reader text)
      | value -> fail Invalid_payload "invalid composing tag %d" value
    in
    Text_edit
      { session_id; local_revision; base_document_revision; text; selection; composing })
  else if event_tag = Generated_protocol.Event_tag.text_submit
  then Text (read_string reader)
  else if event_tag = Generated_protocol.Event_tag.key
  then (
    let logical_key = Reader.u64 reader |> ID.Input.Logical_key.of_int64 in
    let physical_key = Reader.u64 reader |> ID.Input.Physical_key.of_int64 in
    let action =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Key_down
      | 1 -> Key_up
      | 2 -> Key_repeat
      | value -> fail Invalid_payload "invalid key action %d" value
    in
    let modifiers = Reader.u32 reader in
    Key { logical_key; physical_key; action; modifiers })
  else if
    event_tag = Generated_protocol.Event_tag.animation_completed
    || event_tag = Generated_protocol.Event_tag.semantics_action
  then Int64 (Reader.u64 reader)
  else if event_tag = Generated_protocol.Event_tag.scroll_notification
  then (
    let pixels = Reader.f64 reader in
    let delta = Reader.f64 reader in
    if not (Float.is_finite pixels && Float.is_finite delta)
    then fail Invalid_payload "scroll values must be finite";
    Scroll { pixels; delta })
  else if event_tag = Generated_protocol.Event_tag.visible_range_changed
  then (
    let first_index = Reader.u64 reader in
    let last_exclusive = Reader.u64 reader in
    if Int64.compare last_exclusive first_index < 0
    then fail Invalid_payload "visible range is reversed";
    Visible_range { first_index; last_exclusive })
  else if event_tag = Generated_protocol.Event_tag.route_pop
  then (
    let page_key_string = read_string reader in
    if String.length page_key_string = 0
    then fail Invalid_payload "route page key is empty";
    let page_key = ID.Navigation.Page_key.of_string page_key_string in
    Route_pop { page_key; result = read_optional_string reader })
  else if event_tag = Generated_protocol.Event_tag.host_response
  then (
    let request_id = Reader.u64 reader |> ID.Host.Request_id.of_int64 in
    let status =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Host_ok
      | 1 -> Host_error
      | 2 -> Host_cancelled
      | value -> fail Invalid_payload "invalid host response status %d" value
    in
    let value_length = Reader.u32 reader in
    if value_length < 0 then fail Truncated_input "negative host response length";
    let value = Reader.bytes reader value_length in
    Host_response { request_id; status; value })
  else if event_tag = Generated_protocol.Event_tag.environment_changed
  then (
    let viewport_width = read_finite_f64 reader in
    let viewport_height = read_finite_f64 reader in
    let device_pixel_ratio = read_finite_f64 reader in
    let text_scale = read_finite_f64 reader in
    if
      Float.compare viewport_width 0. < 0
      || Float.compare viewport_height 0. < 0
      || Float.compare device_pixel_ratio 0. <= 0
      || Float.compare text_scale 0. <= 0
    then fail Invalid_payload "environment dimensions and scales are invalid";
    let brightness =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Environment_light
      | 1 -> Environment_dark
      | value -> fail Invalid_payload "invalid environment brightness %d" value
    in
    let platform = read_string reader in
    let locale = read_string reader in
    let safe_area = read_edge_insets reader in
    let keyboard_insets = read_edge_insets reader in
    let accessible_navigation = read_bool reader in
    let bold_text = read_bool reader in
    let invert_colors = read_bool reader in
    let disable_animations = read_bool reader in
    let reduced_motion = read_bool reader in
    let high_contrast = read_bool reader in
    let orientation =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Portrait
      | 1 -> Landscape
      | value -> fail Invalid_payload "invalid orientation %d" value
    in
    let pointer_kinds = Reader.u32 reader in
    Environment_changed
      { viewport_width
      ; viewport_height
      ; device_pixel_ratio
      ; text_scale
      ; brightness
      ; platform
      ; locale
      ; safe_area
      ; keyboard_insets
      ; accessible_navigation
      ; bold_text
      ; invert_colors
      ; disable_animations
      ; reduced_motion
      ; high_contrast
      ; orientation
      ; pointer_kinds
      })
  else if event_tag = Generated_protocol.Event_tag.native_event
  then (
    let kind_id_value = Reader.u32 reader in
    let version = Reader.u16 reader in
    let event_id_value = Reader.u16 reader in
    if kind_id_value = 0 then fail Invalid_payload "native event kind ID must be positive";
    if version = 0 then fail Invalid_payload "native event version must be positive";
    if event_id_value = 0 then fail Invalid_payload "native event ID must be positive";
    let kind_id = ID.Native_widget.Kind_id.of_int kind_id_value in
    let event_id = ID.Native_widget.Event_id.of_int event_id_value in
    let payload_length = Reader.u32 reader in
    if payload_length < 0 then fail Truncated_input "negative native event payload length";
    Native_event
      { kind_id; version; event_id; payload = Reader.bytes reader payload_length })
  else
    fail
      Unknown_event_tag
      "unsupported event tag %d"
      (ID.Protocol.Event_tag.to_int event_tag)
;;

let check_u64 label value =
  if Int64.compare value 0L < 0 then fail Invalid_payload "%s must be non-negative" label
;;

let check_u32 label value =
  if value < 0 || Int64.compare (Int64.of_int value) 0xffff_ffffL > 0
  then fail Invalid_payload "%s must fit uint32" label
;;

let write_string writer value =
  let length = String.length value in
  if length > Generated_protocol.Limits.max_string_bytes
  then fail Invalid_payload "string is %d bytes" length;
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  Writer.u32 writer length;
  Writer.string writer value
;;

let write_optional_string writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    write_string writer value
;;

let write_bool writer value = Writer.u8 writer (if value then 1 else 0)

let write_text_selection writer text (selection : Inbound_event.text_selection) =
  if selection.start_utf16 > selection.end_utf16
  then fail Invalid_payload "text range is reversed";
  if
    not
      (is_utf16_boundary text selection.start_utf16
       && is_utf16_boundary text selection.end_utf16)
  then fail Invalid_payload "text range is not on a UTF-16 boundary";
  Writer.u32 writer selection.start_utf16;
  Writer.u32 writer selection.end_utf16
;;

let write_edge_insets writer (insets : Inbound_event.edge_insets) =
  let values = [ insets.left; insets.top; insets.right; insets.bottom ] in
  if List.exists (fun value -> not (Float.is_finite value)) values
  then fail Invalid_payload "environment insets must be finite";
  List.iter (Writer.f64 writer) values
;;

let write_pointer_kind writer = function
  | Inbound_event.Mouse -> Writer.u8 writer 0
  | Touch -> Writer.u8 writer 1
  | Stylus -> Writer.u8 writer 2
  | Inverted_stylus -> Writer.u8 writer 3
  | Trackpad -> Writer.u8 writer 4
  | Unknown_pointer -> Writer.u8 writer 5
;;

let write_position writer ~local_x ~local_y ~global_x ~global_y =
  let values = [ local_x; local_y; global_x; global_y ] in
  if not (List.for_all Float.is_finite values)
  then fail Invalid_payload "pointer coordinates must be finite";
  List.iter (Writer.f64 writer) values
;;

let write_payload writer event_tag payload =
  let open Inbound_event in
  match payload with
  | Unit ->
    if
      event_tag <> Generated_protocol.Event_tag.press
      && event_tag <> Generated_protocol.Event_tag.long_press
      && event_tag <> Generated_protocol.Event_tag.resync_requested
    then fail Invalid_payload "unit payload does not match event tag"
  | Bool value ->
    if
      event_tag <> Generated_protocol.Event_tag.focus_changed
      && event_tag <> Generated_protocol.Event_tag.value_changed
    then fail Invalid_payload "bool payload does not match event tag";
    write_bool writer value
  | Text value ->
    if event_tag <> Generated_protocol.Event_tag.text_submit
    then fail Invalid_payload "text payload does not match event tag";
    write_string writer value
  | Text_edit edit ->
    if event_tag <> Generated_protocol.Event_tag.text_edit
    then fail Invalid_payload "text edit payload does not match event tag";
    let session_id = ID.Text_input.Session_id.to_int64 edit.session_id in
    let local_revision = ID.Text_input.Local_revision.to_int64 edit.local_revision in
    let base_document_revision =
      ID.Text_input.Document_revision.to_int64 edit.base_document_revision
    in
    check_u64 "session ID" session_id;
    check_u64 "local revision" local_revision;
    check_u64 "base document revision" base_document_revision;
    Writer.u64 writer session_id;
    Writer.u64 writer local_revision;
    Writer.u64 writer base_document_revision;
    write_string writer edit.text;
    write_text_selection writer edit.text edit.selection;
    (match edit.composing with
     | None -> Writer.u8 writer 0
     | Some composing ->
       Writer.u8 writer 1;
       write_text_selection writer edit.text composing)
  | Int64 value ->
    if
      event_tag <> Generated_protocol.Event_tag.animation_completed
      && event_tag <> Generated_protocol.Event_tag.semantics_action
    then fail Invalid_payload "int64 payload does not match event tag";
    check_u64 "event int64" value;
    Writer.u64 writer value
  | Tap { local_x; local_y; global_x; global_y; pointer_kind } ->
    if
      event_tag <> Generated_protocol.Event_tag.tap
      && event_tag <> Generated_protocol.Event_tag.double_tap
    then fail Invalid_payload "tap payload does not match event tag";
    write_position writer ~local_x ~local_y ~global_x ~global_y;
    write_pointer_kind writer pointer_kind
  | Pointer { pointer_id; local_x; local_y; global_x; global_y; pointer_kind; buttons } ->
    if
      event_tag <> Generated_protocol.Event_tag.pointer_enter
      && event_tag <> Generated_protocol.Event_tag.pointer_leave
      && event_tag <> Generated_protocol.Event_tag.pointer_down
      && event_tag <> Generated_protocol.Event_tag.pointer_up
    then fail Invalid_payload "pointer payload does not match event tag";
    let pointer_id = ID.Input.Pointer_id.to_int64 pointer_id in
    check_u64 "pointer ID" pointer_id;
    check_u32 "pointer buttons" buttons;
    Writer.u64 writer pointer_id;
    write_position writer ~local_x ~local_y ~global_x ~global_y;
    write_pointer_kind writer pointer_kind;
    Writer.u32 writer buttons
  | Key { logical_key; physical_key; action; modifiers } ->
    if event_tag <> Generated_protocol.Event_tag.key
    then fail Invalid_payload "key payload does not match event tag";
    let logical_key = ID.Input.Logical_key.to_int64 logical_key in
    let physical_key = ID.Input.Physical_key.to_int64 physical_key in
    check_u64 "logical key" logical_key;
    check_u64 "physical key" physical_key;
    check_u32 "key modifiers" modifiers;
    Writer.u64 writer logical_key;
    Writer.u64 writer physical_key;
    Writer.u8
      writer
      (match action with
       | Key_down -> 0
       | Key_up -> 1
       | Key_repeat -> 2);
    Writer.u32 writer modifiers
  | Scroll { pixels; delta } ->
    if event_tag <> Generated_protocol.Event_tag.scroll_notification
    then fail Invalid_payload "scroll payload does not match event tag";
    if not (Float.is_finite pixels && Float.is_finite delta)
    then fail Invalid_payload "scroll values must be finite";
    Writer.f64 writer pixels;
    Writer.f64 writer delta
  | Visible_range { first_index; last_exclusive } ->
    if event_tag <> Generated_protocol.Event_tag.visible_range_changed
    then fail Invalid_payload "visible range payload does not match event tag";
    check_u64 "first visible index" first_index;
    check_u64 "last visible index" last_exclusive;
    if Int64.compare last_exclusive first_index < 0
    then fail Invalid_payload "visible range is reversed";
    Writer.u64 writer first_index;
    Writer.u64 writer last_exclusive
  | Route_pop { page_key; result } ->
    if event_tag <> Generated_protocol.Event_tag.route_pop
    then fail Invalid_payload "route pop payload does not match event tag";
    let page_key = ID.Navigation.Page_key.to_string page_key in
    if String.length page_key = 0 then fail Invalid_payload "route page key is empty";
    write_string writer page_key;
    write_optional_string writer result
  | Host_response { request_id; status; value } ->
    if event_tag <> Generated_protocol.Event_tag.host_response
    then fail Invalid_payload "host response payload does not match event tag";
    let request_id = ID.Host.Request_id.to_int64 request_id in
    check_u64 "host request ID" request_id;
    Writer.u64 writer request_id;
    Writer.u8
      writer
      (match status with
       | Host_ok -> 0
       | Host_error -> 1
       | Host_cancelled -> 2);
    Writer.u32 writer (Bytes.length value);
    Writer.bytes writer value
  | Environment_changed environment ->
    if event_tag <> Generated_protocol.Event_tag.environment_changed
    then fail Invalid_payload "environment payload does not match event tag";
    let values =
      [ environment.viewport_width
      ; environment.viewport_height
      ; environment.device_pixel_ratio
      ; environment.text_scale
      ]
    in
    if List.exists (fun value -> not (Float.is_finite value)) values
    then fail Invalid_payload "environment values must be finite";
    if
      Float.compare environment.viewport_width 0. < 0
      || Float.compare environment.viewport_height 0. < 0
      || Float.compare environment.device_pixel_ratio 0. <= 0
      || Float.compare environment.text_scale 0. <= 0
    then fail Invalid_payload "environment dimensions and scales are invalid";
    List.iter (Writer.f64 writer) values;
    Writer.u8
      writer
      (match environment.brightness with
       | Environment_light -> 0
       | Environment_dark -> 1);
    write_string writer environment.platform;
    write_string writer environment.locale;
    write_edge_insets writer environment.safe_area;
    write_edge_insets writer environment.keyboard_insets;
    write_bool writer environment.accessible_navigation;
    write_bool writer environment.bold_text;
    write_bool writer environment.invert_colors;
    write_bool writer environment.disable_animations;
    write_bool writer environment.reduced_motion;
    write_bool writer environment.high_contrast;
    Writer.u8
      writer
      (match environment.orientation with
       | Portrait -> 0
       | Landscape -> 1);
    Writer.u32 writer environment.pointer_kinds
  | Native_event { kind_id; version; event_id; payload } ->
    if event_tag <> Generated_protocol.Event_tag.native_event
    then fail Invalid_payload "native payload does not match event tag";
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    let event_id = ID.Native_widget.Event_id.to_int event_id in
    if kind_id <= 0 || kind_id > 0xffff
    then fail Invalid_payload "native event kind ID is outside 1..65535";
    if version <= 0 || version > 0xffff
    then fail Invalid_payload "native event version is outside 1..65535";
    if event_id <= 0 || event_id > 0xffff
    then fail Invalid_payload "native event ID is outside 1..65535";
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u16 writer event_id;
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
;;

let write_event event =
  let body = Writer.create () in
  let sequence = ID.Runtime.Event_sequence.to_int64 event.Inbound_event.sequence in
  let displayed_revision =
    ID.Runtime.Renderer_revision.to_int64 event.displayed_revision
  in
  let node_id = ID.Ui.Node_id.to_int64 event.node_id in
  let handler_id = ID.Ui.Handler_id.to_int64 event.handler_id in
  let event_tag = ID.Protocol.Event_tag.to_int event.event_tag in
  check_u64 "event sequence" sequence;
  check_u64 "displayed revision" displayed_revision;
  check_u64 "node ID" node_id;
  check_u64 "handler ID" handler_id;
  if event_tag < 0 || event_tag > 0xffff
  then fail Invalid_payload "event tag is outside u16";
  Writer.u64 body sequence;
  Writer.u64 body displayed_revision;
  Writer.u64 body node_id;
  Writer.u64 body handler_id;
  Writer.u16 body event_tag;
  write_payload body event.event_tag event.payload;
  Writer.contents body
;;

let encode batch =
  try
    let runtime_epoch = ID.Runtime.Epoch.to_int64 batch.Inbound_event.runtime_epoch in
    check_u64 "runtime epoch" runtime_epoch;
    if List.length batch.events > Generated_protocol.Limits.max_operations
    then fail Too_many_events "event count exceeds the limit";
    let payload = Writer.create () in
    Writer.u32 payload (List.length batch.events);
    let previous_sequence = ref None in
    List.iter
      (fun event ->
         if
           match !previous_sequence with
           | None -> false
           | Some previous ->
             ID.Runtime.Event_sequence.compare event.Inbound_event.sequence previous <= 0
         then fail Invalid_payload "event sequences must be strictly increasing";
         previous_sequence := Some event.sequence;
         let body = write_event event in
         Writer.u32 payload (Bytes.length body);
         Writer.bytes payload body)
      batch.events;
    let payload = Writer.contents payload in
    let base_revision, target_sequence =
      match batch.events with
      | [] -> 0L, 0L
      | first :: _ ->
        let last = List.hd (List.rev batch.events) in
        ( ID.Runtime.Renderer_revision.to_int64 first.displayed_revision
        , ID.Runtime.Event_sequence.to_int64 last.sequence )
    in
    let output = Writer.create () in
    Writer.string output "BFFR";
    Writer.u16 output Generated_protocol.protocol_major;
    Writer.u16 output Generated_protocol.protocol_minor;
    Writer.u16 output Generated_protocol.Limits.header_bytes;
    Writer.u8
      output
      (ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.event_batch);
    Writer.u8 output 0;
    Writer.u64 output runtime_epoch;
    Writer.u64 output base_revision;
    Writer.u64 output target_sequence;
    Writer.u32 output (Bytes.length payload);
    Writer.u32 output 0;
    Writer.u32 output 0;
    Writer.bytes output payload;
    let bytes = Writer.contents output in
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Invalid_payload_length "event batch exceeds the frame limit";
    Ok bytes
  with
  | Decode_error error -> Error error
;;

let read_event reader =
  let sequence = Reader.u64 reader |> ID.Runtime.Event_sequence.of_int64 in
  let displayed_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
  let node_id = Reader.u64 reader |> ID.Ui.Node_id.of_int64 in
  let handler_id = Reader.u64 reader |> ID.Ui.Handler_id.of_int64 in
  let event_tag = Reader.u16 reader |> ID.Protocol.Event_tag.of_int in
  let payload = read_payload reader event_tag in
  require_empty reader;
  Inbound_event.{ sequence; displayed_revision; node_id; handler_id; event_tag; payload }
;;

let decode bytes =
  try
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Invalid_payload_length "event batch exceeds the frame limit";
    if Bytes.length bytes < Generated_protocol.Limits.header_bytes
    then fail Truncated_input "event batch is shorter than the fixed header";
    let reader = Reader.create bytes in
    if not (String.equal (Reader.string reader 4) "BFFR")
    then fail Invalid_magic "invalid frame magic";
    let major = Reader.u16 reader in
    let minor = Reader.u16 reader in
    if
      major <> Generated_protocol.protocol_major
      || minor > Generated_protocol.protocol_minor
    then fail Unsupported_version "unsupported protocol version %d.%d" major minor;
    if Reader.u16 reader <> Generated_protocol.Limits.header_bytes
    then fail Invalid_header "invalid header size";
    if
      Reader.u8 reader
      <> ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.event_batch
    then fail Invalid_frame_kind "expected an event-batch frame";
    if Reader.u8 reader <> 0 then fail Invalid_header "unsupported frame flags";
    let runtime_epoch = Reader.u64 reader |> ID.Runtime.Epoch.of_int64 in
    let base_revision = Reader.u64 reader in
    let target_sequence = Reader.u64 reader in
    let payload_length = Reader.u32 reader in
    if Reader.u32 reader <> 0 || Reader.u32 reader <> 0
    then fail Invalid_header "reserved header fields must be zero";
    if payload_length < 0 || payload_length <> Reader.remaining reader
    then fail Invalid_payload_length "payload length does not match the event batch";
    let payload = Reader.sub_reader reader payload_length in
    let count = Reader.u32 payload in
    if count < 0 || count > Generated_protocol.Limits.max_operations
    then fail Too_many_events "event count exceeds the limit";
    let previous_sequence = ref None in
    let events =
      List.init count (fun _ ->
        let body_length = Reader.u32 payload in
        if body_length < 0 then fail Truncated_input "negative event body length";
        let event = read_event (Reader.sub_reader payload body_length) in
        if
          match !previous_sequence with
          | None -> false
          | Some previous ->
            ID.Runtime.Event_sequence.compare event.sequence previous <= 0
        then fail Invalid_payload "event sequences must be strictly increasing";
        previous_sequence := Some event.sequence;
        event)
    in
    require_empty payload;
    (match events with
     | [] ->
       if base_revision <> 0L || target_sequence <> 0L
       then fail Invalid_header "empty event batch has nonzero metadata"
     | first :: _ ->
       let last = List.hd (List.rev events) in
       if
         base_revision <> ID.Runtime.Renderer_revision.to_int64 first.displayed_revision
         || target_sequence <> ID.Runtime.Event_sequence.to_int64 last.sequence
       then fail Invalid_header "header event metadata does not match the payload");
    Ok Inbound_event.{ runtime_epoch; events }
  with
  | Decode_error error -> Error error
;;
