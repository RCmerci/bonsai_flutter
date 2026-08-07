module ID = Bonsai_flutter_spec.Id

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
    { kind_id : ID.Native_widget.kind_id
    ; version : int
    ; capabilities : int64
    ; encode_props : 'props -> bytes
    ; decode_event :
        event_id:ID.Native_widget.event_id -> bytes -> ('event, string) result
    }

  let validate_u16 label value =
    if value <= 0 || value > 0xffff
    then
      invalid_arg
        (Printf.sprintf "Native_widget.Extension.create: %s must be in 1..65535" label)
  ;;

  let create ~kind_id ~version ~capabilities ~encode_props ~decode_event () =
    validate_u16 "kind_id" (ID.Native_widget.Kind_id.to_int kind_id);
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

  let get_u32_unsigned bytes offset =
    Int64.logand (Int64.of_int32 (Bytes.get_int32_le bytes offset)) 0xffff_ffffL
  ;;

  let set_f64 bytes offset value = set_u64 bytes offset (Int64.bits_of_float value)
  let get_f64 bytes offset = Int64.float_of_bits (get_u64 bytes offset)
end

module Virtual_list = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 1
  let version = 1
  let visible_range_event_id = ID.Native_widget.Event_id.of_int 1

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
      ~version
      ~capabilities:[ Capability.Stateful; Resource; Semantics; Virtualized ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let create_widget
        ?key
        ~axis
        ~total_count
        ~first_index
        ~item_extent
        ?(overscan = 2)
        ~items
        ~on_visible_range
        ()
    =
    let props = { total_count; first_index; item_extent; overscan; axis } in
    validate props (List.length items);
    widget_with_handler
      extension
      ?key
      ~props
      ~on_event:on_visible_range
      ~children:items
      ()
  ;;

  let vertical
        ?key
        ~total_count
        ~first_index
        ~item_extent
        ?overscan
        ~items
        ~on_visible_range
        ()
    =
    create_widget
      ?key
      ~axis:Layout.Axis.Vertical
      ~total_count
      ~first_index
      ~item_extent
      ?overscan
      ~items
      ~on_visible_range
      ()
    |> Widget.Private.vertical_viewport
  ;;

  let horizontal
        ?key
        ~total_count
        ~first_index
        ~item_extent
        ?overscan
        ~items
        ~on_visible_range
        ()
    =
    create_widget
      ?key
      ~axis:Layout.Axis.Horizontal
      ~total_count
      ~first_index
      ~item_extent
      ?overscan
      ~items
      ~on_visible_range
      ()
    |> Widget.Private.horizontal_viewport
  ;;

  let visible_range_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
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

module Sparse_extent_list = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 4
  let version_v1 = 1
  let version_v2 = 2
  let visible_range_event_id = ID.Native_widget.Event_id.of_int 1

  module Transition = struct
    type curve =
      | Linear
      | Ease_in
      | Ease_out
      | Ease_in_out
      | Ease_out_cubic
      | Ease_in_out_cubic

    type t =
      { enabled : bool
      ; expand_duration_ms : int
      ; collapse_duration_ms : int
      ; expand_curve : curve
      ; collapse_curve : curve
      }

    let validate_duration label duration =
      if duration < 0 || Int64.of_int duration > 0xffff_ffffL
      then
        invalid_arg
          (Printf.sprintf
             "Native_widget.Sparse_extent_list.Transition: %s must be a valid u32"
             label)
    ;;

    let create
          ?(enabled = true)
          ~expand_duration_ms
          ~collapse_duration_ms
          ?(expand_curve = Ease_out_cubic)
          ?(collapse_curve = Ease_in_out_cubic)
          ()
      =
      validate_duration "expand_duration_ms" expand_duration_ms;
      validate_duration "collapse_duration_ms" collapse_duration_ms;
      { enabled; expand_duration_ms; collapse_duration_ms; expand_curve; collapse_curve }
    ;;
  end

  type extent_override =
    { index : int
    ; extent : float
    }

  type props =
    { total_count : int
    ; first_index : int
    ; default_item_extent : float
    ; extent_overrides : extent_override list
    ; overscan : int
    ; axis : Layout.Axis.t
    ; transition : Transition.t option
    }

  let validate_extent label extent =
    if (not (Float.is_finite extent)) || Float.compare extent 0. <= 0
    then
      invalid_arg
        (Printf.sprintf
           "Native_widget.Sparse_extent_list: %s must be finite and positive"
           label)
  ;;

  let validate props child_count =
    if props.total_count < 0
    then invalid_arg "Native_widget.Sparse_extent_list: total_count must be non-negative";
    if props.first_index < 0 || props.first_index > props.total_count
    then
      invalid_arg
        "Native_widget.Sparse_extent_list: first_index is outside the logical list";
    if child_count < 0 || child_count > props.total_count - props.first_index
    then invalid_arg "Native_widget.Sparse_extent_list: item window exceeds total_count";
    validate_extent "default_item_extent" props.default_item_extent;
    if props.overscan < 0 || Int64.of_int props.overscan > 0xffff_ffffL
    then invalid_arg "Native_widget.Sparse_extent_list: overscan must be a valid u32";
    Option.iter
      (fun (transition : Transition.t) ->
         Transition.validate_duration "expand_duration_ms" transition.expand_duration_ms;
         Transition.validate_duration
           "collapse_duration_ms"
           transition.collapse_duration_ms)
      props.transition;
    let rec validate_overrides previous = function
      | [] -> ()
      | { index; extent } :: tail ->
        if index < 0 || index >= props.total_count
        then
          invalid_arg
            "Native_widget.Sparse_extent_list: override index is outside the logical list";
        (match previous with
         | Some previous when index <= previous ->
           invalid_arg
             "Native_widget.Sparse_extent_list: override indexes must be sorted and \
              unique"
         | None | Some _ -> ());
        validate_extent "override extent" extent;
        validate_overrides (Some index) tail
    in
    validate_overrides None props.extent_overrides
  ;;

  let axis_byte = function
    | Layout.Axis.Horizontal -> 0
    | Vertical -> 1
  ;;

  let transition_curve_byte = function
    | Transition.Linear -> 0
    | Ease_in -> 1
    | Ease_out -> 2
    | Ease_in_out -> 3
    | Ease_out_cubic -> 4
    | Ease_in_out_cubic -> 5
  ;;

  let transition_curve_of_byte = function
    | 0 -> Ok Transition.Linear
    | 1 -> Ok Ease_in
    | 2 -> Ok Ease_out
    | 3 -> Ok Ease_in_out
    | 4 -> Ok Ease_out_cubic
    | 5 -> Ok Ease_in_out_cubic
    | _ -> Error "invalid sparse extent transition curve"
  ;;

  let encode_props props =
    let override_count = List.length props.extent_overrides in
    let header_length = if Option.is_some props.transition then 48 else 36 in
    let payload = Bytes.make (header_length + (override_count * 16)) '\000' in
    Little_endian.set_u64 payload 0 (Int64.of_int props.total_count);
    Little_endian.set_u64 payload 8 (Int64.of_int props.first_index);
    Little_endian.set_f64 payload 16 props.default_item_extent;
    Little_endian.set_u32 payload 24 props.overscan;
    Bytes.set payload 28 (Char.chr (axis_byte props.axis));
    Little_endian.set_u32 payload 32 override_count;
    Option.iter
      (fun (transition : Transition.t) ->
         Bytes.set payload 29 '\001';
         Little_endian.set_u32 payload 36 transition.expand_duration_ms;
         Little_endian.set_u32 payload 40 transition.collapse_duration_ms;
         Bytes.set payload 44 (Char.chr (transition_curve_byte transition.expand_curve));
         Bytes.set payload 45 (Char.chr (transition_curve_byte transition.collapse_curve));
         Bytes.set payload 46 (if transition.enabled then '\001' else '\000'))
      props.transition;
    List.iteri
      (fun offset { index; extent } ->
         let payload_offset = header_length + (offset * 16) in
         Little_endian.set_u64 payload payload_offset (Int64.of_int index);
         Little_endian.set_f64 payload (payload_offset + 8) extent)
      props.extent_overrides;
    payload
  ;;

  let decode_props payload =
    let length = Bytes.length payload in
    if length < 36
    then Error "sparse extent list props must contain a 36-byte header"
    else if Bytes.get payload 30 <> '\000' || Bytes.get payload 31 <> '\000'
    then Error "sparse extent list reserved bytes must be zero"
    else (
      let schema = Char.code (Bytes.get payload 29) in
      let header_length =
        if schema = 0
        then Ok 36
        else if schema = 1
        then Ok 48
        else Error "invalid sparse extent list payload schema"
      in
      match header_length with
      | Error _ as error -> error
      | Ok header_length ->
        if length < header_length || (schema = 1 && Bytes.get payload 47 <> '\000')
        then Error "sparse extent list transition header is malformed"
        else (
          let override_count = Little_endian.get_u32_unsigned payload 32 in
          let expected_length =
            Int64.add (Int64.of_int header_length) (Int64.mul override_count 16L)
          in
          if Int64.compare expected_length (Int64.of_int length) <> 0
          then Error "sparse extent list props length does not match override_count"
          else (
            let total_count = Little_endian.get_u64 payload 0 in
            let first_index = Little_endian.get_u64 payload 8 in
            let overscan = Little_endian.get_u32_unsigned payload 24 in
            let axis =
              match Char.code (Bytes.get payload 28) with
              | 0 -> Ok Layout.Axis.Horizontal
              | 1 -> Ok Vertical
              | _ -> Error "invalid sparse extent list axis"
            in
            let transition =
              if schema = 0
              then Ok None
              else (
                let enabled =
                  match Char.code (Bytes.get payload 46) with
                  | 0 -> Ok false
                  | 1 -> Ok true
                  | _ -> Error "invalid sparse extent transition enablement"
                in
                let expand_duration = Little_endian.get_u32_unsigned payload 36 in
                let collapse_duration = Little_endian.get_u32_unsigned payload 40 in
                if
                  Int64.compare expand_duration (Int64.of_int max_int) > 0
                  || Int64.compare collapse_duration (Int64.of_int max_int) > 0
                then Error "sparse extent transition duration exceeds OCaml int"
                else (
                  match
                    ( enabled
                    , transition_curve_of_byte (Char.code (Bytes.get payload 44))
                    , transition_curve_of_byte (Char.code (Bytes.get payload 45)) )
                  with
                  | (Error _ as error), _, _
                  | _, (Error _ as error), _
                  | _, _, (Error _ as error) -> error
                  | Ok enabled, Ok expand_curve, Ok collapse_curve ->
                    Ok
                      (Some
                         Transition.
                           { enabled
                           ; expand_duration_ms = Int64.to_int expand_duration
                           ; collapse_duration_ms = Int64.to_int collapse_duration
                           ; expand_curve
                           ; collapse_curve
                           })))
            in
            if
              Int64.compare total_count (Int64.of_int max_int) > 0
              || Int64.compare first_index (Int64.of_int max_int) > 0
              || Int64.compare overscan (Int64.of_int max_int) > 0
            then Error "sparse extent list integer exceeds OCaml int"
            else (
              let override_count = Int64.to_int override_count in
              let rec decode_overrides offset result =
                if offset = override_count
                then Ok (List.rev result)
                else (
                  let payload_offset = header_length + (offset * 16) in
                  let index = Little_endian.get_u64 payload payload_offset in
                  if Int64.compare index (Int64.of_int max_int) > 0
                  then Error "sparse extent list override index exceeds OCaml int"
                  else
                    decode_overrides
                      (offset + 1)
                      ({ index = Int64.to_int index
                       ; extent = Little_endian.get_f64 payload (payload_offset + 8)
                       }
                       :: result))
              in
              match axis, transition, decode_overrides 0 [] with
              | (Error _ as error), _, _
              | _, (Error _ as error), _
              | _, _, (Error _ as error) -> error
              | Ok axis, Ok transition, Ok extent_overrides ->
                let props =
                  { total_count = Int64.to_int total_count
                  ; first_index = Int64.to_int first_index
                  ; default_item_extent = Little_endian.get_f64 payload 16
                  ; extent_overrides
                  ; overscan = Int64.to_int overscan
                  ; axis
                  ; transition
                  }
                in
                (try
                   validate props 0;
                   Ok props
                 with
                 | Invalid_argument message -> Error message)))))
  ;;

  let decode_event ~event_id payload =
    if event_id <> visible_range_event_id
    then Error "unknown sparse extent list event"
    else if Bytes.length payload <> 16
    then Error "visible range payload must be exactly 16 bytes"
    else (
      let first_index = Little_endian.get_u64 payload 0 in
      let last_exclusive = Little_endian.get_u64 payload 8 in
      if Int64.compare last_exclusive first_index < 0
      then Error "visible range is reversed"
      else Ok Event.Payload.{ first_index; last_exclusive })
  ;;

  let extension version =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful; Resource; Semantics; Virtualized ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let extension_v1 = extension version_v1
  let extension_v2 = extension version_v2

  let extension_for transition =
    if Option.is_some transition then extension_v2 else extension_v1
  ;;

  let props
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ~overscan
        ~axis
        ~transition
        items
    =
    let props =
      { total_count
      ; first_index
      ; default_item_extent
      ; extent_overrides
      ; overscan
      ; axis
      ; transition
      }
    in
    validate props (List.length items);
    props
  ;;

  let create_widget
        ?key
        ~axis
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ?(overscan = 2)
        ?transition
        ~items
        ~on_visible_range
        ()
    =
    let props =
      props
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ~overscan
        ~axis
        ~transition
        items
    in
    widget_with_handler
      (extension_for transition)
      ?key
      ~props
      ~on_event:on_visible_range
      ~children:items
      ()
  ;;

  let vertical
        ?key
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ?overscan
        ?transition
        ~items
        ~on_visible_range
        ()
    =
    create_widget
      ?key
      ~axis:Layout.Axis.Vertical
      ~total_count
      ~first_index
      ~default_item_extent
      ~extent_overrides
      ?overscan
      ?transition
      ~items
      ~on_visible_range
      ()
    |> Widget.Private.vertical_viewport
  ;;

  let horizontal
        ?key
        ~total_count
        ~first_index
        ~default_item_extent
        ~extent_overrides
        ?overscan
        ?transition
        ~items
        ~on_visible_range
        ()
    =
    create_widget
      ?key
      ~axis:Layout.Axis.Horizontal
      ~total_count
      ~first_index
      ~default_item_extent
      ~extent_overrides
      ?overscan
      ?transition
      ~items
      ~on_visible_range
      ()
    |> Widget.Private.horizontal_viewport
  ;;

  let visible_range_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id
           && (event.version = version_v1 || event.version = version_v2) ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  module For_testing = struct
    type nonrec extent_override = extent_override =
      { index : int
      ; extent : float
      }

    type nonrec props = props =
      { total_count : int
      ; first_index : int
      ; default_item_extent : float
      ; extent_overrides : extent_override list
      ; overscan : int
      ; axis : Layout.Axis.t
      ; transition : Transition.t option
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;

    let encode_visible_range ~first_index ~last_exclusive =
      if first_index < 0 || last_exclusive < first_index
      then invalid_arg "Native_widget.Sparse_extent_list: invalid visible range";
      let bytes = Bytes.make 16 '\000' in
      Little_endian.set_u64 bytes 0 (Int64.of_int first_index);
      Little_endian.set_u64 bytes 8 (Int64.of_int last_exclusive);
      bytes
    ;;
  end
end

module Morphing_surface = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 5
  let version = 1

  type props = { expanded : bool }

  let encode_props props =
    let payload = Bytes.make 4 '\000' in
    Bytes.set payload 0 (if props.expanded then '\001' else '\000');
    payload
  ;;

  let decode_props payload =
    if Bytes.length payload <> 4
    then Error "morphing surface props must contain exactly 4 bytes"
    else if
      Bytes.get payload 1 <> '\000'
      || Bytes.get payload 2 <> '\000'
      || Bytes.get payload 3 <> '\000'
    then Error "morphing surface reserved bytes must be zero"
    else (
      match Char.code (Bytes.get payload 0) with
      | 0 -> Ok { expanded = false }
      | 1 -> Ok { expanded = true }
      | _ -> Error "invalid morphing surface target state")
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Semantics ]
      ~encode_props
      ~decode_event:(fun ~event_id:_ _ -> Error "morphing surface has no events")
      ()
  ;;

  let create ?key ~expanded ~compact_content ~expanded_content () =
    widget
      extension
      ?key
      ~props:{ expanded }
      ~on_event:(fun _ -> ())
      ~children:[ compact_content; expanded_content ]
      ()
  ;;

  module For_testing = struct
    type nonrec props = props = { expanded : bool }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;
  end
end

module Swipe_action = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 2
  let version = 1
  let commit_event_id = ID.Native_widget.Event_id.of_int 1

  type direction =
    | Start_to_end
    | End_to_start

  type disposition =
    | Dismiss
    | Rebound

  type action =
    { label : string
    ; background : Style.Color.t
    ; disposition : disposition
    ; icon : Widget.t
    }

  let action ~label ~background ~disposition ~icon =
    if String.length label = 0
    then invalid_arg "Native_widget.Swipe_action: action label must not be empty";
    ignore (Text_editing.Utf16.length label);
    { label; background; disposition; icon }
  ;;

  type props =
    { start_action : action option
    ; end_action : action option
    }

  let disposition_byte = function
    | Dismiss -> 0
    | Rebound -> 1
  ;;

  let encode_props { start_action; end_action } =
    let label = function
      | None -> ""
      | Some action -> action.label
    in
    let start_label = label start_action in
    let end_label = label end_action in
    let start_length = String.length start_label in
    let end_length = String.length end_label in
    let payload = Bytes.make (20 + start_length + end_length) '\000' in
    let enabled option flag = if Option.is_some option then flag else 0 in
    Bytes.set payload 0 (Char.chr (enabled start_action 1 lor enabled end_action 2));
    Bytes.set
      payload
      1
      (Char.chr
         (Option.fold
            ~none:0
            ~some:(fun action -> disposition_byte action.disposition)
            start_action));
    Bytes.set
      payload
      2
      (Char.chr
         (Option.fold
            ~none:0
            ~some:(fun action -> disposition_byte action.disposition)
            end_action));
    let background = function
      | None -> 0l
      | Some action -> Style.Color.Private.to_argb32 action.background
    in
    Bytes.set_int32_le payload 4 (background start_action);
    Bytes.set_int32_le payload 8 (background end_action);
    Little_endian.set_u32 payload 12 start_length;
    Little_endian.set_u32 payload 16 end_length;
    Bytes.blit_string start_label 0 payload 20 start_length;
    Bytes.blit_string end_label 0 payload (20 + start_length) end_length;
    payload
  ;;

  let decode_event ~event_id payload =
    if event_id <> commit_event_id
    then Error "unknown swipe action event"
    else if Bytes.length payload <> 1
    then Error "swipe action direction payload must be exactly one byte"
    else (
      match Char.code (Bytes.get payload 0) with
      | 0 -> Ok Start_to_end
      | 1 -> Ok End_to_start
      | _ -> Error "unknown swipe action direction")
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful; Resource; Semantics ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let validate_actions start_action end_action =
    if Option.is_none start_action && Option.is_none end_action
    then invalid_arg "Native_widget.Swipe_action: at least one action is required"
  ;;

  let children start_action end_action content =
    let icon = function
      | None -> Widget.empty ()
      | Some action -> action.icon
    in
    [ content; icon start_action; icon end_action ]
  ;;

  let direction_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  let create ?key ?start_action ?end_action ~content ~on_commit () =
    validate_actions start_action end_action;
    widget
      extension
      ?key
      ~props:{ start_action; end_action }
      ~on_event:on_commit
      ~children:(children start_action end_action content)
      ()
  ;;

  let create_with_handler ?key ?start_action ?end_action ~content ~on_commit () =
    validate_actions start_action end_action;
    widget_with_handler
      extension
      ?key
      ~props:{ start_action; end_action }
      ~on_event:on_commit
      ~children:(children start_action end_action content)
      ()
  ;;
end

module Navigation_shell = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 3
  let version = 1
  let drawer_state_changed_event_id = ID.Native_widget.Event_id.of_int 1

  type drawer_state =
    | Closed
    | Open

  type props =
    { selected_index : int
    ; destination_count : int
    ; drawer_open : bool
    ; drawer_enabled : bool
    }

  let validate props =
    if props.destination_count <= 0
    then invalid_arg "Native_widget.Navigation_shell: at least one body is required";
    if props.selected_index < 0 || props.selected_index >= props.destination_count
    then invalid_arg "Native_widget.Navigation_shell: selected index is outside bodies"
  ;;

  let encode_props props =
    let payload = Bytes.make 12 '\000' in
    let flags =
      (if props.drawer_open then 1 else 0) lor if props.drawer_enabled then 2 else 0
    in
    Bytes.set payload 0 (Char.chr flags);
    Little_endian.set_u32 payload 4 props.selected_index;
    Little_endian.set_u32 payload 8 props.destination_count;
    payload
  ;;

  let decode_props payload =
    if Bytes.length payload <> 12
    then Error "navigation shell props must be exactly 12 bytes"
    else if
      Bytes.get payload 1 <> '\000'
      || Bytes.get payload 2 <> '\000'
      || Bytes.get payload 3 <> '\000'
    then Error "navigation shell reserved bytes must be zero"
    else (
      let flags = Char.code (Bytes.get payload 0) in
      if flags land lnot 3 <> 0
      then Error "navigation shell flags contain unknown bits"
      else (
        let props =
          { selected_index = Little_endian.get_u32 payload 4
          ; destination_count = Little_endian.get_u32 payload 8
          ; drawer_open = flags land 1 <> 0
          ; drawer_enabled = flags land 2 <> 0
          }
        in
        try
          validate props;
          Ok props
        with
        | Invalid_argument message -> Error message))
  ;;

  let decode_event ~event_id payload =
    if event_id <> drawer_state_changed_event_id
    then Error "unknown navigation shell event"
    else if Bytes.length payload <> 1
    then Error "drawer state payload must be exactly one byte"
    else (
      match Char.code (Bytes.get payload 0) with
      | 0 -> Ok Closed
      | 1 -> Ok Open
      | _ -> Error "unknown drawer state")
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful; Resource; Semantics ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let props ~selected_index ~drawer_open ~drawer_enabled bodies =
    let props =
      { selected_index
      ; destination_count = List.length bodies
      ; drawer_open
      ; drawer_enabled
      }
    in
    validate props;
    props
  ;;

  let widget_with_handler_and_bodies
        ?key
        ~props
        ~on_event
        ~bodies
        ~drawer
        ~bottom_navigation
        ()
    =
    Widget.Private.native_widget_with_body_children
      ?key
      ~kind_id:extension.kind_id
      ~version:extension.version
      ~capabilities:extension.capabilities
      ~payload:(extension.encode_props props)
      ~on_event
      ~bodies
      ~trailing_children:[ drawer; bottom_navigation ]
      ()
  ;;

  let widget_with_bodies ?key ~props ~on_event ~bodies ~drawer ~bottom_navigation () =
    widget_with_handler_and_bodies
      ?key
      ~props
      ~on_event:(event_handler extension on_event)
      ~bodies
      ~drawer
      ~bottom_navigation
      ()
  ;;

  let drawer_state_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  let create
        ?key
        ~selected_index
        ~drawer_open
        ~drawer_enabled
        ~bodies
        ~drawer
        ~bottom_navigation
        ~on_drawer_state_changed
        ()
    =
    widget_with_bodies
      ?key
      ~props:(props ~selected_index ~drawer_open ~drawer_enabled bodies)
      ~on_event:on_drawer_state_changed
      ~bodies
      ~drawer
      ~bottom_navigation
      ()
  ;;

  let create_with_handler
        ?key
        ~selected_index
        ~drawer_open
        ~drawer_enabled
        ~bodies
        ~drawer
        ~bottom_navigation
        ~on_drawer_state_changed
        ()
    =
    widget_with_handler_and_bodies
      ?key
      ~props:(props ~selected_index ~drawer_open ~drawer_enabled bodies)
      ~on_event:on_drawer_state_changed
      ~bodies
      ~drawer
      ~bottom_navigation
      ()
  ;;

  module For_testing = struct
    type nonrec props = props =
      { selected_index : int
      ; destination_count : int
      ; drawer_open : bool
      ; drawer_enabled : bool
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;

    let encode_drawer_state = function
      | Closed -> Bytes.of_string "\000"
      | Open -> Bytes.of_string "\001"
    ;;
  end
end
