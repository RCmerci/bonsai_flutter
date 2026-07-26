module Capability = struct
  type t =
    | Stateful
    | Resource
    | Semantics
    | Semantics_canvas
    | Virtualized

  let bit = function
    | Stateful -> 1L
    | Resource -> 2L
    | Semantics -> 4L
    | Semantics_canvas -> 8L
    | Virtualized -> 16L
  ;;

  let bits capabilities =
    List.fold_left
      (fun result capability -> Int64.logor result (bit capability))
      0L
      capabilities
  ;;
end

module Extension = struct
  type ('props, 'event) t =
    { kind_id : int
    ; version : int
    ; capabilities : int64
    ; encode_props : 'props -> bytes
    ; decode_event : event_id:int -> bytes -> ('event, string) result
    }

  let validate_u16 label value =
    if value <= 0 || value > 0xffff
    then
      invalid_arg
        (Printf.sprintf "Native_widget.Extension.create: %s must be in 1..65535" label)
  ;;

  let create ~kind_id ~version ~capabilities ~encode_props ~decode_event () =
    validate_u16 "kind_id" kind_id;
    validate_u16 "version" version;
    { kind_id
    ; version
    ; capabilities = Capability.bits capabilities
    ; encode_props
    ; decode_event
    }
  ;;
end

let event_handler
      (type props event)
      ?(name = "native-widget-event")
      (extension : (props, event) Extension.t)
      on_event
  =
  Event.Handler.create ~name (function
    | Event.Payload.Native_event event
      when event.kind_id = extension.kind_id && event.version = extension.version ->
      (match extension.decode_event ~event_id:event.event_id event.payload with
       | Ok decoded -> on_event decoded
       | Error _ -> ())
    | _ -> ())
;;

let widget_with_handler
      (extension : ('props, 'event) Extension.t)
      ?key
      ~props
      ~on_event
      ?(children = [])
      ()
  =
  Widget.Private.native_widget
    ?key
    ~kind_id:extension.kind_id
    ~version:extension.version
    ~capabilities:extension.capabilities
    ~payload:(extension.encode_props props)
    ~on_event
    ~children
    ()
;;

let widget extension ?key ~props ~on_event ?children () =
  let handler = event_handler extension on_event in
  widget_with_handler extension ?key ~props ~on_event:handler ?children ()
;;

module Little_endian = struct
  let set_u64 bytes offset value = Bytes.set_int64_le bytes offset value
  let get_u64 bytes offset = Bytes.get_int64_le bytes offset
  let set_u32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.of_int value)
  let get_u32 bytes offset = Int32.to_int (Bytes.get_int32_le bytes offset)
  let set_f64 bytes offset value = set_u64 bytes offset (Int64.bits_of_float value)
  let get_f64 bytes offset = Int64.float_of_bits (get_u64 bytes offset)
end

module Virtual_list = struct
  let kind_id = 1
  let visible_range_event_id = 1

  type props =
    { total_count : int
    ; first_index : int
    ; item_extent : float
    ; overscan : int
    ; axis : Layout.Axis.t
    }

  let validate props child_count =
    if props.total_count < 0
    then invalid_arg "Native_widget.Virtual_list: total_count must be non-negative";
    if props.first_index < 0 || props.first_index > props.total_count
    then invalid_arg "Native_widget.Virtual_list: first_index is outside the logical list";
    if child_count > props.total_count - props.first_index
    then invalid_arg "Native_widget.Virtual_list: item window exceeds total_count";
    if
      (not (Float.is_finite props.item_extent)) || Float.compare props.item_extent 0. <= 0
    then invalid_arg "Native_widget.Virtual_list: item_extent must be finite and positive";
    if props.overscan < 0
    then invalid_arg "Native_widget.Virtual_list: overscan must be non-negative"
  ;;

  let encode_props props =
    let bytes = Bytes.make 29 '\000' in
    Little_endian.set_u64 bytes 0 (Int64.of_int props.total_count);
    Little_endian.set_u64 bytes 8 (Int64.of_int props.first_index);
    Little_endian.set_f64 bytes 16 props.item_extent;
    Little_endian.set_u32 bytes 24 props.overscan;
    Bytes.set
      bytes
      28
      (Char.chr
         (match props.axis with
          | Layout.Axis.Horizontal -> 0
          | Vertical -> 1));
    bytes
  ;;

  let decode_props payload =
    if Bytes.length payload <> 29
    then Error "virtual list props must be exactly 29 bytes"
    else (
      let total_count = Little_endian.get_u64 payload 0 in
      let first_index = Little_endian.get_u64 payload 8 in
      let item_extent = Little_endian.get_f64 payload 16 in
      let overscan = Little_endian.get_u32 payload 24 in
      let axis =
        match Char.code (Bytes.get payload 28) with
        | 0 -> Ok Layout.Axis.Horizontal
        | 1 -> Ok Vertical
        | _ -> Error "invalid virtual list axis"
      in
      match axis with
      | Error _ as error -> error
      | Ok axis ->
        if
          Int64.compare total_count (Int64.of_int max_int) > 0
          || Int64.compare first_index (Int64.of_int max_int) > 0
        then Error "virtual list index exceeds OCaml int"
        else
          Ok
            { total_count = Int64.to_int total_count
            ; first_index = Int64.to_int first_index
            ; item_extent
            ; overscan
            ; axis
            })
  ;;

  let decode_event ~event_id payload =
    if event_id <> visible_range_event_id
    then Error "unknown virtual list event"
    else if Bytes.length payload <> 16
    then Error "visible range payload must be exactly 16 bytes"
    else (
      let first_index = Little_endian.get_u64 payload 0 in
      let last_exclusive = Little_endian.get_u64 payload 8 in
      if Int64.compare last_exclusive first_index < 0
      then Error "visible range is reversed"
      else Ok Event.Payload.{ first_index; last_exclusive })
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version:1
      ~capabilities:[ Capability.Stateful; Resource; Semantics; Virtualized ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let create
        ?key
        ~total_count
        ~first_index
        ~item_extent
        ?(overscan = 2)
        ?(axis = Layout.Axis.Vertical)
        ~items
        ~on_visible_range
        ()
    =
    let props = { total_count; first_index; item_extent; overscan; axis } in
    validate props (List.length items);
    widget extension ?key ~props ~on_event:on_visible_range ~children:items ()
  ;;

  module For_testing = struct
    type nonrec props = props =
      { total_count : int
      ; first_index : int
      ; item_extent : float
      ; overscan : int
      ; axis : Layout.Axis.t
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;

    let encode_visible_range ~first_index ~last_exclusive =
      if first_index < 0 || last_exclusive < first_index
      then invalid_arg "Native_widget.Virtual_list: invalid visible range";
      let bytes = Bytes.make 16 '\000' in
      Little_endian.set_u64 bytes 0 (Int64.of_int first_index);
      Little_endian.set_u64 bytes 8 (Int64.of_int last_exclusive);
      bytes
    ;;
  end
end
