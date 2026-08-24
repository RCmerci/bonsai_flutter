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
  let set_u16 bytes offset value =
    Bytes.set bytes offset (Char.chr (value land 0xff));
    Bytes.set bytes (offset + 1) (Char.chr ((value lsr 8) land 0xff))
  ;;

  let get_u16 bytes offset =
    Char.code (Bytes.get bytes offset) lor (Char.code (Bytes.get bytes (offset + 1)) lsl 8)
  ;;

  let set_u64 bytes offset value = Bytes.set_int64_le bytes offset value
  let set_u32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.of_int value)
  let get_u32 bytes offset = Int32.to_int (Bytes.get_int32_le bytes offset)

  let get_u32_unsigned bytes offset =
    Int64.logand (Int64.of_int32 (Bytes.get_int32_le bytes offset)) 0xffff_ffffL
  ;;

  let set_f64 bytes offset value = set_u64 bytes offset (Int64.bits_of_float value)
  let get_f64 bytes offset = Int64.float_of_bits (Bytes.get_int64_le bytes offset)
end

module Morphing_surface = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 5
  let version = 1

  type props = { expanded : bool }

  let encode_props (props : props) =
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

module Slidable = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 2
  let version = 3
  let action_pressed_event_id = ID.Native_widget.Event_id.of_int 1
  let dismissed_event_id = ID.Native_widget.Event_id.of_int 2
  let header_size = 16
  let pane_size = 48
  let action_size = 64
  let max_u16 = 0xffff
  let max_u32 = 0xffff_ffff

  type side =
    | Start
    | End

  type motion =
    | Behind
    | Drawer
    | Scroll
    | Stretch

  type dismiss_motion = Inversed_drawer

  type dismissible =
    { dismiss_threshold : float
    ; dismissal_duration_ms : int
    ; resize_duration_ms : int
    ; close_on_cancel : bool
    ; motion : dismiss_motion
    }

  type action =
    { id : int
    ; enabled : bool
    ; flex : int
    ; foreground : Style.Color.t option
    ; background : Style.Color.t
    ; auto_close : bool
    ; border_radius : float
    ; padding : Layout.Edge_insets.t option
    ; alignment : Layout.Alignment.t option
    ; child : Widget.t
    }

  type action_pane =
    { extent_ratio : float
    ; motion : motion
    ; dismissible : dismissible option
    ; drag_dismissible : bool
    ; open_threshold : float option
    ; close_threshold : float option
    ; actions : action list
    }

  type props =
    { enabled : bool
    ; close_on_scroll : bool
    ; direction : Layout.Axis.t
    ; use_text_direction : bool
    ; group_tag : string option
    ; start_action_pane : action_pane option
    ; end_action_pane : action_pane option
    }

  type event =
    | Action_pressed of int
    | Dismissed of side

  type decoded_action =
    { id : int
    ; enabled : bool
    ; flex : int
    ; foreground : Style.Color.t option
    ; background : Style.Color.t
    ; auto_close : bool
    ; border_radius : float
    ; padding : Layout.Edge_insets.t option
    ; alignment : Layout.Alignment.t option
    }

  type decoded_action_pane =
    { extent_ratio : float
    ; motion : motion
    ; dismissible : dismissible option
    ; drag_dismissible : bool
    ; open_threshold : float option
    ; close_threshold : float option
    ; actions : decoded_action list
    }

  type decoded_props =
    { enabled : bool
    ; close_on_scroll : bool
    ; direction : Layout.Axis.t
    ; use_text_direction : bool
    ; group_tag : string option
    ; start_action_pane : decoded_action_pane option
    ; end_action_pane : decoded_action_pane option
    }

  let invalid label message =
    invalid_arg (Printf.sprintf "Native_widget.Slidable.%s: %s" label message)
  ;;

  let validate_finite_nonnegative label value =
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then invalid label "must be finite and non-negative"
  ;;

  let validate_unit_interval label value =
    if
      (not (Float.is_finite value))
      || Float.compare value 0. <= 0
      || Float.compare value 1. >= 0
    then invalid label "must be finite and in the open interval (0, 1)"
  ;;

  let validate_extent_ratio value =
    if
      (not (Float.is_finite value))
      || Float.compare value 0. <= 0
      || Float.compare value 1. > 0
    then invalid "action_pane" "extent_ratio must be finite and in (0, 1]"
  ;;

  let validate_u32 label value =
    if value <= 0 || value > max_u32 then invalid label "must be in 1..4294967295"
  ;;

  let validate_duration label value =
    if value < 0 || value > max_u32
    then invalid label "must be in 0..4294967295 milliseconds"
  ;;

  let action
        ~id
        ?(enabled = true)
        ?(flex = 1)
        ?foreground
        ~background
        ?(auto_close = true)
        ?(border_radius = 0.)
        ?padding
        ?alignment
        ~child
        ()
    =
    validate_u32 "action id" id;
    validate_u32 "action flex" flex;
    validate_finite_nonnegative "action border_radius" border_radius;
    { id
    ; enabled
    ; flex
    ; foreground
    ; background
    ; auto_close
    ; border_radius
    ; padding
    ; alignment
    ; child
    }
  ;;

  let icon_label_action
        ~id
        ?enabled
        ?flex
        ?foreground
        ~background
        ?auto_close
        ?border_radius
        ?padding
        ?alignment
        ?(spacing = 4.)
        ~icon
        ~label
        ()
    =
    if String.length label = 0 then invalid "icon_label_action" "label must not be empty";
    ignore (Text_editing.Utf16.length label);
    validate_finite_nonnegative "icon_label_action spacing" spacing;
    let child =
      Widget.column
        [ icon; Widget.sized_box ~height:spacing (Widget.empty ()); Widget.text label ]
    in
    action
      ~id
      ?enabled
      ?flex
      ?foreground
      ~background
      ?auto_close
      ?border_radius
      ?padding
      ?alignment
      ~child
      ()
  ;;

  let dismissible
        ?(dismiss_threshold = 0.75)
        ?(dismissal_duration_ms = 300)
        ?(resize_duration_ms = 300)
        ?(close_on_cancel = false)
        ?(motion = Inversed_drawer)
        ()
    =
    validate_unit_interval "dismissible dismiss_threshold" dismiss_threshold;
    validate_duration "dismissible dismissal_duration_ms" dismissal_duration_ms;
    validate_duration "dismissible resize_duration_ms" resize_duration_ms;
    { dismiss_threshold
    ; dismissal_duration_ms
    ; resize_duration_ms
    ; close_on_cancel
    ; motion
    }
  ;;

  let action_pane
        ?(extent_ratio = 0.5)
        ~motion
        ?dismissible
        ?(drag_dismissible = true)
        ?open_threshold
        ?close_threshold
        ~(actions : action list)
        ()
    : action_pane
    =
    validate_extent_ratio extent_ratio;
    Option.iter (validate_unit_interval "action_pane open_threshold") open_threshold;
    Option.iter (validate_unit_interval "action_pane close_threshold") close_threshold;
    let action_count = List.length actions in
    if action_count = 0 then invalid "action_pane" "actions must not be empty";
    if action_count > max_u16
    then invalid "action_pane" "actions must contain at most 65535 entries";
    { extent_ratio
    ; motion
    ; dismissible
    ; drag_dismissible
    ; open_threshold
    ; close_threshold
    ; actions
    }
  ;;

  let motion_byte = function
    | Behind -> 0
    | Drawer -> 1
    | Scroll -> 2
    | Stretch -> 3
  ;;

  let alignment_byte = function
    | Layout.Alignment.Top_start -> 0
    | Top_center -> 1
    | Top_end -> 2
    | Center_start -> 3
    | Center -> 4
    | Center_end -> 5
    | Bottom_start -> 6
    | Bottom_center -> 7
    | Bottom_end -> 8
  ;;

  let pane_flags (pane : action_pane) =
    (if pane.drag_dismissible then 1 else 0)
    lor (if Option.is_some pane.dismissible then 2 else 0)
    lor (if Option.is_some pane.open_threshold then 4 else 0)
    lor (if Option.is_some pane.close_threshold then 8 else 0)
    lor
    match pane.dismissible with
    | Some dismissible when dismissible.close_on_cancel -> 16
    | None | Some _ -> 0
  ;;

  let encode_pane payload offset (pane : action_pane) =
    Bytes.set payload offset (Char.chr (motion_byte pane.motion));
    Bytes.set payload (offset + 1) (Char.chr (pane_flags pane));
    Bytes.set payload (offset + 2) '\000';
    Little_endian.set_f64 payload (offset + 8) pane.extent_ratio;
    Little_endian.set_f64
      payload
      (offset + 16)
      (Option.value ~default:0. pane.open_threshold);
    Little_endian.set_f64
      payload
      (offset + 24)
      (Option.value ~default:0. pane.close_threshold);
    match pane.dismissible with
    | None -> ()
    | Some dismissible ->
      Little_endian.set_f64 payload (offset + 32) dismissible.dismiss_threshold;
      Little_endian.set_u32 payload (offset + 40) dismissible.dismissal_duration_ms;
      Little_endian.set_u32 payload (offset + 44) dismissible.resize_duration_ms
  ;;

  let action_flags (action : action) =
    (if action.enabled then 1 else 0)
    lor (if action.auto_close then 2 else 0)
    lor (if Option.is_some action.foreground then 4 else 0)
    lor (if Option.is_some action.padding then 8 else 0)
    lor if Option.is_some action.alignment then 16 else 0
  ;;

  let encode_action payload offset (action : action) =
    Little_endian.set_u32 payload offset action.id;
    Bytes.set_int32_le
      payload
      (offset + 4)
      (Style.Color.Private.to_argb32 action.background);
    Bytes.set_int32_le
      payload
      (offset + 8)
      (Option.fold ~none:0l ~some:Style.Color.Private.to_argb32 action.foreground);
    Bytes.set payload (offset + 12) (Char.chr (action_flags action));
    Bytes.set
      payload
      (offset + 13)
      (Char.chr (Option.fold ~none:0 ~some:alignment_byte action.alignment));
    Little_endian.set_u32 payload (offset + 16) action.flex;
    Little_endian.set_f64 payload (offset + 24) action.border_radius;
    match action.padding with
    | None -> ()
    | Some padding ->
      let left, top, right, bottom = Layout.Edge_insets.Private.to_sides padding in
      Little_endian.set_f64 payload (offset + 32) left;
      Little_endian.set_f64 payload (offset + 40) top;
      Little_endian.set_f64 payload (offset + 48) right;
      Little_endian.set_f64 payload (offset + 56) bottom
  ;;

  let pane_actions : action_pane option -> action list = function
    | None -> []
    | Some pane -> pane.actions
  ;;

  let encode_props (props : props) =
    let start_actions = pane_actions props.start_action_pane in
    let end_actions = pane_actions props.end_action_pane in
    let group_tag = Option.value ~default:"" props.group_tag in
    let pane_count =
      (if Option.is_some props.start_action_pane then 1 else 0)
      + if Option.is_some props.end_action_pane then 1 else 0
    in
    let payload_length =
      header_size
      + (pane_count * pane_size)
      + ((List.length start_actions + List.length end_actions) * action_size)
      + String.length group_tag
    in
    let payload = Bytes.make payload_length '\000' in
    let flags =
      (if props.enabled then 1 else 0)
      lor (if props.close_on_scroll then 2 else 0)
      lor (if props.use_text_direction then 4 else 0)
      lor (if Option.is_some props.start_action_pane then 8 else 0)
      lor if Option.is_some props.end_action_pane then 16 else 0
    in
    Bytes.set payload 0 (Char.chr flags);
    Bytes.set
      payload
      1
      (Char.chr
         (match props.direction with
          | Layout.Axis.Horizontal -> 0
          | Vertical -> 1));
    Little_endian.set_u16 payload 4 (List.length start_actions);
    Little_endian.set_u16 payload 6 (List.length end_actions);
    Little_endian.set_u32 payload 8 (String.length group_tag);
    let offset = ref header_size in
    List.iter
      (function
        | None -> ()
        | Some pane ->
          encode_pane payload !offset pane;
          offset := !offset + pane_size)
      [ props.start_action_pane; props.end_action_pane ];
    List.iter
      (fun action ->
         encode_action payload !offset action;
         offset := !offset + action_size)
      (start_actions @ end_actions);
    Bytes.blit_string group_tag 0 payload !offset (String.length group_tag);
    payload
  ;;

  exception Decode_error of string

  let decode_error message = raise (Decode_error message)
  let require condition message = if not condition then decode_error message

  let require_zero_range payload offset length message =
    for index = offset to offset + length - 1 do
      require (Bytes.get payload index = '\000') message
    done
  ;;

  let decode_motion = function
    | 0 -> Behind
    | 1 -> Drawer
    | 2 -> Scroll
    | 3 -> Stretch
    | _ -> decode_error "unknown slidable pane motion"
  ;;

  let decode_alignment = function
    | 0 -> Layout.Alignment.Top_start
    | 1 -> Top_center
    | 2 -> Top_end
    | 3 -> Center_start
    | 4 -> Center
    | 5 -> Center_end
    | 6 -> Bottom_start
    | 7 -> Bottom_center
    | 8 -> Bottom_end
    | _ -> decode_error "unknown slidable action alignment"
  ;;

  let decode_pane payload offset =
    let motion = decode_motion (Char.code (Bytes.get payload offset)) in
    let flags = Char.code (Bytes.get payload (offset + 1)) in
    require (flags land lnot 0x1f = 0) "unknown slidable pane flags";
    require (Bytes.get payload (offset + 2) = '\000') "unknown dismiss motion";
    require_zero_range payload (offset + 3) 5 "slidable pane reserved bytes";
    let drag_dismissible = flags land 1 <> 0 in
    let has_dismissible = flags land 2 <> 0 in
    let has_open_threshold = flags land 4 <> 0 in
    let has_close_threshold = flags land 8 <> 0 in
    let close_on_cancel = flags land 16 <> 0 in
    require
      (has_dismissible || not close_on_cancel)
      "close_on_cancel requires a dismissible pane";
    let extent_ratio = Little_endian.get_f64 payload (offset + 8) in
    let open_value = Little_endian.get_f64 payload (offset + 16) in
    let close_value = Little_endian.get_f64 payload (offset + 24) in
    let dismiss_threshold = Little_endian.get_f64 payload (offset + 32) in
    let dismissal_duration_ms = Little_endian.get_u32_unsigned payload (offset + 40) in
    let resize_duration_ms = Little_endian.get_u32_unsigned payload (offset + 44) in
    require
      (Float.is_finite extent_ratio
       && Float.compare extent_ratio 0. > 0
       && Float.compare extent_ratio 1. <= 0)
      "invalid slidable pane extent ratio";
    let optional_threshold present value label =
      if present
      then (
        require
          (Float.is_finite value
           && Float.compare value 0. > 0
           && Float.compare value 1. < 0)
          ("invalid slidable pane " ^ label);
        Some value)
      else (
        require (Float.equal value 0.) ("absent " ^ label ^ " must be zero");
        None)
    in
    let open_threshold =
      optional_threshold has_open_threshold open_value "open threshold"
    in
    let close_threshold =
      optional_threshold has_close_threshold close_value "close threshold"
    in
    let dismissible =
      if has_dismissible
      then (
        require
          (Float.is_finite dismiss_threshold
           && Float.compare dismiss_threshold 0. > 0
           && Float.compare dismiss_threshold 1. < 0)
          "invalid slidable dismiss threshold";
        require
          (Int64.compare dismissal_duration_ms (Int64.of_int max_u32) <= 0
           && Int64.compare resize_duration_ms (Int64.of_int max_u32) <= 0)
          "invalid slidable dismiss duration";
        Some
          { dismiss_threshold
          ; dismissal_duration_ms = Int64.to_int dismissal_duration_ms
          ; resize_duration_ms = Int64.to_int resize_duration_ms
          ; close_on_cancel
          ; motion = Inversed_drawer
          })
      else (
        require (Float.equal dismiss_threshold 0.) "absent dismiss threshold must be zero";
        require
          (Int64.equal dismissal_duration_ms 0L && Int64.equal resize_duration_ms 0L)
          "absent dismiss durations must be zero";
        None)
    in
    { extent_ratio
    ; motion
    ; dismissible
    ; drag_dismissible
    ; open_threshold
    ; close_threshold
    ; actions = []
    }
  ;;

  let decode_action payload offset =
    let id_value = Little_endian.get_u32_unsigned payload offset in
    require (not (Int64.equal id_value 0L)) "slidable action ID must be positive";
    let background =
      Style.Color.Private.of_argb32 (Bytes.get_int32_le payload (offset + 4))
    in
    let foreground_value = Bytes.get_int32_le payload (offset + 8) in
    let flags = Char.code (Bytes.get payload (offset + 12)) in
    require (flags land lnot 0x1f = 0) "unknown slidable action flags";
    let enabled = flags land 1 <> 0 in
    let auto_close = flags land 2 <> 0 in
    let has_foreground = flags land 4 <> 0 in
    let has_padding = flags land 8 <> 0 in
    let has_alignment = flags land 16 <> 0 in
    let alignment_value = Char.code (Bytes.get payload (offset + 13)) in
    require_zero_range payload (offset + 14) 2 "slidable action reserved bytes";
    let flex_value = Little_endian.get_u32_unsigned payload (offset + 16) in
    require (not (Int64.equal flex_value 0L)) "slidable action flex must be positive";
    require_zero_range payload (offset + 20) 4 "slidable action reserved bytes";
    let border_radius = Little_endian.get_f64 payload (offset + 24) in
    require
      (Float.is_finite border_radius && Float.compare border_radius 0. >= 0)
      "invalid slidable action border radius";
    let left = Little_endian.get_f64 payload (offset + 32) in
    let top = Little_endian.get_f64 payload (offset + 40) in
    let right = Little_endian.get_f64 payload (offset + 48) in
    let bottom = Little_endian.get_f64 payload (offset + 56) in
    let padding =
      if has_padding
      then Some (Layout.Edge_insets.only ~left ~top ~right ~bottom ())
      else (
        require
          (List.for_all (Float.equal 0.) [ left; top; right; bottom ])
          "absent slidable action padding must be zero";
        None)
    in
    let alignment =
      if has_alignment
      then Some (decode_alignment alignment_value)
      else (
        require (alignment_value = 0) "absent slidable action alignment must be zero";
        None)
    in
    let foreground =
      if has_foreground
      then Some (Style.Color.Private.of_argb32 foreground_value)
      else (
        require (Int32.equal foreground_value 0l) "absent foreground must be zero";
        None)
    in
    { id = Int64.to_int id_value
    ; enabled
    ; flex = Int64.to_int flex_value
    ; foreground
    ; background
    ; auto_close
    ; border_radius
    ; padding
    ; alignment
    }
  ;;

  let decode_props payload =
    try
      let length = Bytes.length payload in
      require (length >= header_size) "slidable props require a 16-byte header";
      let flags = Char.code (Bytes.get payload 0) in
      require (flags land lnot 0x1f = 0) "unknown slidable flags";
      let direction =
        match Char.code (Bytes.get payload 1) with
        | 0 -> Layout.Axis.Horizontal
        | 1 -> Vertical
        | _ -> decode_error "unknown slidable axis"
      in
      require_zero_range payload 2 2 "slidable header reserved bytes";
      let start_count = Little_endian.get_u16 payload 4 in
      let end_count = Little_endian.get_u16 payload 6 in
      let group_length = Little_endian.get_u32_unsigned payload 8 in
      require_zero_range payload 12 4 "slidable header reserved bytes";
      let has_start = flags land 8 <> 0 in
      let has_end = flags land 16 <> 0 in
      require (has_start || has_end) "slidable requires at least one pane";
      require
        ((has_start && start_count > 0) || ((not has_start) && start_count = 0))
        "slidable start pane count is inconsistent";
      require
        ((has_end && end_count > 0) || ((not has_end) && end_count = 0))
        "slidable end pane count is inconsistent";
      let pane_count = (if has_start then 1 else 0) + if has_end then 1 else 0 in
      let expected_length =
        Int64.add
          (Int64.of_int
             (header_size
              + (pane_count * pane_size)
              + ((start_count + end_count) * action_size)))
          group_length
      in
      require
        (Int64.equal expected_length (Int64.of_int length))
        "slidable props have an incorrect exact length";
      let offset = ref header_size in
      let decode_optional_pane present =
        if present
        then (
          let pane = decode_pane payload !offset in
          offset := !offset + pane_size;
          Some pane)
        else None
      in
      let start_pane = decode_optional_pane has_start in
      let end_pane = decode_optional_pane has_end in
      let decode_actions count =
        List.init count (fun _ ->
          let action = decode_action payload !offset in
          offset := !offset + action_size;
          action)
      in
      let start_actions = decode_actions start_count in
      let end_actions = decode_actions end_count in
      let ids = Hashtbl.create (start_count + end_count) in
      List.iter
        (fun action ->
           require (not (Hashtbl.mem ids action.id)) "duplicate slidable action ID";
           Hashtbl.add ids action.id ())
        (start_actions @ end_actions);
      let group_length = Int64.to_int group_length in
      let group_tag =
        if group_length = 0
        then None
        else (
          let value = Bytes.sub_string payload !offset group_length in
          ignore (Text_editing.Utf16.length value);
          Some value)
      in
      let attach pane actions = Option.map (fun pane -> { pane with actions }) pane in
      Ok
        { enabled = flags land 1 <> 0
        ; close_on_scroll = flags land 2 <> 0
        ; direction
        ; use_text_direction = flags land 4 <> 0
        ; group_tag
        ; start_action_pane = attach start_pane start_actions
        ; end_action_pane = attach end_pane end_actions
        }
    with
    | Decode_error message -> Error message
    | Invalid_argument message -> Error message
  ;;

  let decode_event ~event_id payload =
    if event_id = action_pressed_event_id
    then
      if Bytes.length payload <> 4
      then Error "slidable action event payload must contain exactly four bytes"
      else (
        let id = Little_endian.get_u32_unsigned payload 0 in
        if Int64.equal id 0L
        then Error "slidable action event ID must be positive"
        else Ok (Action_pressed (Int64.to_int id)))
    else if event_id = dismissed_event_id
    then
      if Bytes.length payload <> 1
      then Error "slidable dismissed event payload must contain exactly one byte"
      else (
        match Char.code (Bytes.get payload 0) with
        | 0 -> Ok (Dismissed Start)
        | 1 -> Ok (Dismissed End)
        | _ -> Error "unknown slidable dismissed side")
    else Error "unknown slidable event"
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

  let validate_props (props : props) =
    if Option.is_none props.start_action_pane && Option.is_none props.end_action_pane
    then invalid "create" "at least one action pane is required";
    (match props.group_tag with
     | None -> ()
     | Some group_tag ->
       if String.length group_tag = 0 then invalid "create" "group_tag must not be empty";
       if String.length group_tag > max_u32
       then invalid "create" "group_tag must contain at most 4294967295 bytes";
       ignore (Text_editing.Utf16.length group_tag));
    let ids = Hashtbl.create 8 in
    List.iter
      (fun (action : action) ->
         if Hashtbl.mem ids action.id
         then invalid "create" "action IDs must be unique across both panes";
         Hashtbl.add ids action.id ())
      (pane_actions props.start_action_pane @ pane_actions props.end_action_pane)
  ;;

  let children (props : props) content =
    content
    :: List.map
         (fun (action : action) -> action.child)
         (pane_actions props.start_action_pane @ pane_actions props.end_action_pane)
  ;;

  let create
        ~key
        ?(enabled = true)
        ?(close_on_scroll = true)
        ?(direction = Layout.Axis.Horizontal)
        ?(use_text_direction = true)
        ?group_tag
        ?start_action_pane
        ?end_action_pane
        ~content
        ~on_event
        ()
    =
    let props : props =
      { enabled
      ; close_on_scroll
      ; direction
      ; use_text_direction
      ; group_tag
      ; start_action_pane
      ; end_action_pane
      }
    in
    validate_props props;
    widget extension ~key ~props ~on_event ~children:(children props content) ()
  ;;

  let create_with_handler
        ~key
        ?(enabled = true)
        ?(close_on_scroll = true)
        ?(direction = Layout.Axis.Horizontal)
        ?(use_text_direction = true)
        ?group_tag
        ?start_action_pane
        ?end_action_pane
        ~content
        ~on_event
        ()
    =
    let props : props =
      { enabled
      ; close_on_scroll
      ; direction
      ; use_text_direction
      ; group_tag
      ; start_action_pane
      ; end_action_pane
      }
    in
    validate_props props;
    widget_with_handler
      extension
      ~key
      ~props
      ~on_event
      ~children:(children props content)
      ()
  ;;

  let event_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  module For_testing = struct
    type action_props = decoded_action =
      { id : int
      ; enabled : bool
      ; flex : int
      ; foreground : Style.Color.t option
      ; background : Style.Color.t
      ; auto_close : bool
      ; border_radius : float
      ; padding : Layout.Edge_insets.t option
      ; alignment : Layout.Alignment.t option
      }

    type dismissible_props = dismissible =
      { dismiss_threshold : float
      ; dismissal_duration_ms : int
      ; resize_duration_ms : int
      ; close_on_cancel : bool
      ; motion : dismiss_motion
      }

    type action_pane_props = decoded_action_pane =
      { extent_ratio : float
      ; motion : motion
      ; dismissible : dismissible_props option
      ; drag_dismissible : bool
      ; open_threshold : float option
      ; close_threshold : float option
      ; actions : action_props list
      }

    type props = decoded_props =
      { enabled : bool
      ; close_on_scroll : bool
      ; direction : Layout.Axis.t
      ; use_text_direction : bool
      ; group_tag : string option
      ; start_action_pane : action_pane_props option
      ; end_action_pane : action_pane_props option
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;

    let encode_action_pressed id =
      validate_u32 "event action ID" id;
      let payload = Bytes.make 4 '\000' in
      Little_endian.set_u32 payload 0 id;
      payload
    ;;

    let encode_dismissed side =
      Bytes.make
        1
        (Char.chr
           (match side with
            | Start -> 0
            | End -> 1))
    ;;
  end
end

module Slidable_auto_close_behavior = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 8
  let version = 1

  type props =
    { close_when_opened : bool
    ; close_when_tapped : bool
    }

  let encode_props props =
    let payload = Bytes.make 4 '\000' in
    Bytes.set
      payload
      0
      (Char.chr
         ((if props.close_when_opened then 1 else 0)
          lor if props.close_when_tapped then 2 else 0));
    payload
  ;;

  let decode_props payload =
    if Bytes.length payload <> 4
    then Error "slidable auto-close props must contain exactly four bytes"
    else if
      Bytes.get payload 1 <> '\000'
      || Bytes.get payload 2 <> '\000'
      || Bytes.get payload 3 <> '\000'
    then Error "slidable auto-close reserved bytes must be zero"
    else (
      let flags = Char.code (Bytes.get payload 0) in
      if flags land lnot 3 <> 0
      then Error "unknown slidable auto-close flags"
      else
        Ok
          { close_when_opened = flags land 1 <> 0; close_when_tapped = flags land 2 <> 0 })
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful ]
      ~encode_props
      ~decode_event:(fun ~event_id:_ _ -> Error "slidable auto-close has no events")
      ()
  ;;

  let create ?key ?(close_when_opened = true) ?(close_when_tapped = true) ~child () =
    widget
      extension
      ?key
      ~props:{ close_when_opened; close_when_tapped }
      ~on_event:(fun _ -> ())
      ~children:[ child ]
      ()
  ;;

  module For_testing = struct
    type nonrec props = props =
      { close_when_opened : bool
      ; close_when_tapped : bool
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;
  end
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

module Message_composer = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 6
  let version = 1
  let text_changed_event_id = ID.Native_widget.Event_id.of_int 1
  let button_pressed_event_id = ID.Native_widget.Event_id.of_int 2

  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button_props =
    { id : int
    ; tooltip : string
    ; position : button_position
    ; visibility : button_visibility
    ; style : button_style
    ; enabled : bool
    }

  type button =
    { props : button_props
    ; child : Widget.t
    }

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  type props =
    { enabled : bool
    ; autofocus : bool
    ; max_lines : int
    ; hint_text : string
    ; buttons : button_props list
    }

  let validate_utf8 label value =
    try ignore (Text_editing.Utf16.length value) with
    | Invalid_argument _ ->
      invalid_arg (Printf.sprintf "Native_widget.Message_composer: %s is not UTF-8" label)
  ;;

  let validate_button_id id =
    if id <= 0 || Int64.compare (Int64.of_int id) 0xffff_ffffL > 0
    then invalid_arg "Native_widget.Message_composer: button id must be in 1..4294967295"
  ;;

  let button
        ~id
        ~tooltip
        ?(position = Trailing)
        ?(visibility = Always)
        ?(style = Plain)
        ?(enabled = true)
        ~child
        ()
    =
    validate_button_id id;
    if String.length tooltip = 0
    then invalid_arg "Native_widget.Message_composer: button tooltip must not be empty";
    validate_utf8 "button tooltip" tooltip;
    { props = { id; tooltip; position; visibility; style; enabled }; child }
  ;;

  let validate_props props =
    if props.max_lines <= 0 || props.max_lines > 0xffff
    then invalid_arg "Native_widget.Message_composer: max_lines must be in 1..65535";
    if List.length props.buttons > 0xffff
    then
      invalid_arg
        "Native_widget.Message_composer: buttons must contain at most 65535 entries";
    validate_utf8 "hint_text" props.hint_text;
    let ids = Hashtbl.create (List.length props.buttons) in
    List.iter
      (fun button ->
         validate_button_id button.id;
         if Hashtbl.mem ids button.id
         then invalid_arg "Native_widget.Message_composer: button ids must be unique";
         Hashtbl.add ids button.id ())
      props.buttons
  ;;

  let position_byte = function
    | Leading -> 0
    | Trailing -> 1
  ;;

  let visibility_byte = function
    | Always -> 0
    | When_empty -> 1
    | When_non_empty -> 2
  ;;

  let style_byte = function
    | Plain -> 0
    | Filled -> 1
  ;;

  let encode_props props =
    validate_props props;
    let hint_length = String.length props.hint_text in
    let length =
      12
      + hint_length
      + List.fold_left
          (fun total button -> 12 + String.length button.tooltip + total)
          0
          props.buttons
    in
    let payload = Bytes.make length '\000' in
    Bytes.set
      payload
      0
      (Char.chr ((if props.enabled then 1 else 0) lor if props.autofocus then 2 else 0));
    Little_endian.set_u16 payload 2 props.max_lines;
    Little_endian.set_u16 payload 4 (List.length props.buttons);
    Little_endian.set_u32 payload 8 hint_length;
    Bytes.blit_string props.hint_text 0 payload 12 hint_length;
    ignore
      (List.fold_left
         (fun offset button ->
            let tooltip_length = String.length button.tooltip in
            Little_endian.set_u32 payload offset button.id;
            Bytes.set payload (offset + 4) (Char.chr (position_byte button.position));
            Bytes.set payload (offset + 5) (Char.chr (visibility_byte button.visibility));
            Bytes.set payload (offset + 6) (Char.chr (style_byte button.style));
            Bytes.set payload (offset + 7) (Char.chr (if button.enabled then 1 else 0));
            Little_endian.set_u32 payload (offset + 8) tooltip_length;
            Bytes.blit_string button.tooltip 0 payload (offset + 12) tooltip_length;
            offset + 12 + tooltip_length)
         (12 + hint_length)
         props.buttons);
    payload
  ;;

  let decode_enum value cases error =
    match List.assoc_opt value cases with
    | Some value -> Ok value
    | None -> Error error
  ;;

  let decode_utf8 label value =
    try
      ignore (Text_editing.Utf16.length value);
      Ok value
    with
    | Invalid_argument _ -> Error (label ^ " must be valid UTF-8")
  ;;

  let decode_props payload =
    let ( let* ) = Result.bind in
    if Bytes.length payload < 12
    then Error "message composer props must contain a 12-byte header"
    else if Bytes.get payload 6 <> '\000' || Bytes.get payload 7 <> '\000'
    then Error "message composer reserved bytes must be zero"
    else (
      let flags = Char.code (Bytes.get payload 0) in
      let max_lines = Little_endian.get_u16 payload 2 in
      let button_count = Little_endian.get_u16 payload 4 in
      let hint_length = Little_endian.get_u32_unsigned payload 8 in
      if Bytes.get payload 1 <> '\000'
      then Error "message composer reserved bytes must be zero"
      else if flags land lnot 3 <> 0
      then Error "message composer flags contain unknown bits"
      else if max_lines = 0
      then Error "message composer max_lines must be positive"
      else if Int64.compare hint_length (Int64.of_int (Bytes.length payload - 12)) > 0
      then Error "message composer hint exceeds payload"
      else (
        let hint_length = Int64.to_int hint_length in
        let hint_text = Bytes.sub_string payload 12 hint_length in
        let* hint_text = decode_utf8 "message composer hint" hint_text in
        let rec decode_buttons remaining offset ids decoded =
          if remaining = 0
          then
            if offset = Bytes.length payload
            then Ok (List.rev decoded)
            else Error "message composer props contain extra bytes"
          else if offset + 12 > Bytes.length payload
          then Error "message composer button header exceeds payload"
          else (
            let id = Little_endian.get_u32_unsigned payload offset in
            let tooltip_length = Little_endian.get_u32_unsigned payload (offset + 8) in
            let tooltip_offset = offset + 12 in
            if Int64.equal id 0L || List.mem id ids
            then Error "message composer button ids must be positive and unique"
            else if
              Int64.compare
                tooltip_length
                (Int64.of_int (Bytes.length payload - tooltip_offset))
              > 0
            then Error "message composer button tooltip exceeds payload"
            else
              let* position =
                decode_enum
                  (Char.code (Bytes.get payload (offset + 4)))
                  [ 0, Leading; 1, Trailing ]
                  "invalid message composer button position"
              in
              let* visibility =
                decode_enum
                  (Char.code (Bytes.get payload (offset + 5)))
                  [ 0, Always; 1, When_empty; 2, When_non_empty ]
                  "invalid message composer button visibility"
              in
              let* style =
                decode_enum
                  (Char.code (Bytes.get payload (offset + 6)))
                  [ 0, Plain; 1, Filled ]
                  "invalid message composer button style"
              in
              let button_flags = Char.code (Bytes.get payload (offset + 7)) in
              if button_flags land lnot 1 <> 0
              then Error "message composer button flags contain unknown bits"
              else (
                let tooltip_length = Int64.to_int tooltip_length in
                let tooltip = Bytes.sub_string payload tooltip_offset tooltip_length in
                let* tooltip = decode_utf8 "message composer button tooltip" tooltip in
                if String.length tooltip = 0
                then Error "message composer button tooltip must not be empty"
                else
                  decode_buttons
                    (remaining - 1)
                    (tooltip_offset + tooltip_length)
                    (id :: ids)
                    ({ id = Int64.to_int id
                     ; tooltip
                     ; position
                     ; visibility
                     ; style
                     ; enabled = button_flags land 1 <> 0
                     }
                     :: decoded)))
        in
        let* buttons = decode_buttons button_count (12 + hint_length) [] [] in
        Ok
          { enabled = flags land 1 <> 0
          ; autofocus = flags land 2 <> 0
          ; max_lines
          ; hint_text
          ; buttons
          }))
  ;;

  let decode_event ~event_id payload =
    if event_id = text_changed_event_id
    then
      Result.map
        (fun text -> Text_changed text)
        (decode_utf8 "text" (Bytes.to_string payload))
    else if event_id = button_pressed_event_id
    then
      if Bytes.length payload < 4
      then Error "message composer button event must contain a 4-byte button id"
      else (
        let button_id = Little_endian.get_u32_unsigned payload 0 in
        if Int64.equal button_id 0L
        then Error "message composer button event id must be positive"
        else
          Result.map
            (fun text -> Button_pressed { button_id = Int64.to_int button_id; text })
            (decode_utf8
               "button event text"
               (Bytes.sub_string payload 4 (Bytes.length payload - 4))))
    else Error "unknown message composer event"
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful; Semantics ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let make_props enabled autofocus max_lines hint_text buttons =
    let props =
      { enabled
      ; autofocus
      ; max_lines
      ; hint_text
      ; buttons = List.map (fun button -> button.props) buttons
      }
    in
    validate_props props;
    props
  ;;

  let create
        ?key
        ?(enabled = true)
        ?(autofocus = false)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ~buttons
        ~on_event
        ()
    =
    widget
      extension
      ?key
      ~props:(make_props enabled autofocus max_lines hint_text buttons)
      ~on_event
      ~children:(List.map (fun button -> button.child) buttons)
      ()
  ;;

  let create_with_handler
        ?key
        ?(enabled = true)
        ?(autofocus = false)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ~buttons
        ~on_event
        ()
    =
    widget_with_handler
      extension
      ?key
      ~props:(make_props enabled autofocus max_lines hint_text buttons)
      ~on_event
      ~children:(List.map (fun button -> button.child) buttons)
      ()
  ;;

  let event_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  module For_testing = struct
    type nonrec button_props = button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type nonrec props = props =
      { enabled : bool
      ; autofocus : bool
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;
  end
end

module Expandable_message_composer = struct
  let kind_id = ID.Native_widget.Kind_id.of_int 7
  let version = 1
  let text_changed_event_id = ID.Native_widget.Event_id.of_int 1
  let button_pressed_event_id = ID.Native_widget.Event_id.of_int 2

  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button_props =
    { id : int
    ; tooltip : string
    ; position : button_position
    ; visibility : button_visibility
    ; style : button_style
    ; enabled : bool
    }

  type button =
    { props : button_props
    ; child : Widget.t
    }

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  type props =
    { enabled : bool
    ; fab_label : string
    ; fab_tooltip : string
    ; animation_duration_ms : int
    ; animation_curve : Animation.Curve.t
    ; max_lines : int
    ; hint_text : string
    ; buttons : button_props list
    }

  let error_prefix = "Native_widget.Expandable_message_composer: "

  let validate_utf8 label value =
    try ignore (Text_editing.Utf16.length value) with
    | Invalid_argument _ -> invalid_arg (error_prefix ^ label ^ " is not UTF-8")
  ;;

  let validate_required_string label value =
    if String.length value = 0
    then invalid_arg (error_prefix ^ label ^ " must not be empty");
    validate_utf8 label value
  ;;

  let validate_u32_string_length label value =
    if Int64.compare (Int64.of_int (String.length value)) 0xffff_ffffL > 0
    then invalid_arg (error_prefix ^ label ^ " is too long")
  ;;

  let validate_button_id id =
    if id <= 0 || Int64.compare (Int64.of_int id) 0xffff_ffffL > 0
    then invalid_arg (error_prefix ^ "button id must be in 1..4294967295")
  ;;

  let button
        ~id
        ~tooltip
        ?(position = Trailing)
        ?(visibility = Always)
        ?(style = Plain)
        ?(enabled = true)
        ~child
        ()
    =
    validate_button_id id;
    validate_required_string "button tooltip" tooltip;
    validate_u32_string_length "button tooltip" tooltip;
    { props = { id; tooltip; position; visibility; style; enabled }; child }
  ;;

  let validate_props props =
    if props.animation_duration_ms < 0 || props.animation_duration_ms > 0xffff
    then invalid_arg (error_prefix ^ "animation_duration_ms must be in 0..65535");
    if props.max_lines <= 0 || props.max_lines > 0xffff
    then invalid_arg (error_prefix ^ "max_lines must be in 1..65535");
    if List.length props.buttons > 0xfffe
    then invalid_arg (error_prefix ^ "buttons must contain at most 65534 entries");
    validate_required_string "FAB label" props.fab_label;
    validate_required_string "FAB tooltip" props.fab_tooltip;
    validate_utf8 "hint_text" props.hint_text;
    validate_u32_string_length "FAB label" props.fab_label;
    validate_u32_string_length "FAB tooltip" props.fab_tooltip;
    validate_u32_string_length "hint_text" props.hint_text;
    let ids = Hashtbl.create (List.length props.buttons) in
    List.iter
      (fun button ->
         validate_button_id button.id;
         validate_required_string "button tooltip" button.tooltip;
         validate_u32_string_length "button tooltip" button.tooltip;
         if Hashtbl.mem ids button.id
         then invalid_arg (error_prefix ^ "button ids must be unique");
         Hashtbl.add ids button.id ())
      props.buttons
  ;;

  let curve_byte = function
    | Animation.Curve.Linear -> 0
    | Ease_in -> 1
    | Ease_out -> 2
    | Ease_in_out -> 3
  ;;

  let position_byte = function
    | Leading -> 0
    | Trailing -> 1
  ;;

  let visibility_byte = function
    | Always -> 0
    | When_empty -> 1
    | When_non_empty -> 2
  ;;

  let style_byte = function
    | Plain -> 0
    | Filled -> 1
  ;;

  let encode_props props =
    validate_props props;
    let label_length = String.length props.fab_label in
    let fab_tooltip_length = String.length props.fab_tooltip in
    let hint_length = String.length props.hint_text in
    let length =
      24
      + label_length
      + fab_tooltip_length
      + hint_length
      + List.fold_left
          (fun total button -> total + 12 + String.length button.tooltip)
          0
          props.buttons
    in
    let payload = Bytes.make length (Char.chr 0) in
    Bytes.set payload 0 (Char.chr (if props.enabled then 1 else 0));
    Bytes.set payload 1 (Char.chr (curve_byte props.animation_curve));
    Little_endian.set_u16 payload 2 props.animation_duration_ms;
    Little_endian.set_u16 payload 4 props.max_lines;
    Little_endian.set_u16 payload 6 (List.length props.buttons);
    Little_endian.set_u32 payload 8 label_length;
    Little_endian.set_u32 payload 12 fab_tooltip_length;
    Little_endian.set_u32 payload 16 hint_length;
    let offset = 24 in
    Bytes.blit_string props.fab_label 0 payload offset label_length;
    let offset = offset + label_length in
    Bytes.blit_string props.fab_tooltip 0 payload offset fab_tooltip_length;
    let offset = offset + fab_tooltip_length in
    Bytes.blit_string props.hint_text 0 payload offset hint_length;
    ignore
      (List.fold_left
         (fun offset button ->
            let tooltip_length = String.length button.tooltip in
            Little_endian.set_u32 payload offset button.id;
            Bytes.set payload (offset + 4) (Char.chr (position_byte button.position));
            Bytes.set payload (offset + 5) (Char.chr (visibility_byte button.visibility));
            Bytes.set payload (offset + 6) (Char.chr (style_byte button.style));
            Bytes.set payload (offset + 7) (Char.chr (if button.enabled then 1 else 0));
            Little_endian.set_u32 payload (offset + 8) tooltip_length;
            Bytes.blit_string button.tooltip 0 payload (offset + 12) tooltip_length;
            offset + 12 + tooltip_length)
         (offset + hint_length)
         props.buttons);
    payload
  ;;

  let decode_enum value cases error =
    match List.assoc_opt value cases with
    | Some value -> Ok value
    | None -> Error error
  ;;

  let decode_utf8 label value =
    try
      ignore (Text_editing.Utf16.length value);
      Ok value
    with
    | Invalid_argument _ -> Error (label ^ " must be valid UTF-8")
  ;;

  let decode_props payload =
    let ( let* ) = Result.bind in
    if Bytes.length payload < 24
    then Error "expandable message composer props must contain a 24-byte header"
    else (
      let flags = Char.code (Bytes.get payload 0) in
      let curve_value = Char.code (Bytes.get payload 1) in
      let duration = Little_endian.get_u16 payload 2 in
      let max_lines = Little_endian.get_u16 payload 4 in
      let button_count = Little_endian.get_u16 payload 6 in
      let label_length = Little_endian.get_u32_unsigned payload 8 in
      let fab_tooltip_length = Little_endian.get_u32_unsigned payload 12 in
      let hint_length = Little_endian.get_u32_unsigned payload 16 in
      if flags land lnot 1 <> 0
      then Error "expandable message composer flags contain unknown bits"
      else if Bytes.get_int32_le payload 20 <> 0l
      then Error "expandable message composer reserved bytes must be zero"
      else if max_lines = 0
      then Error "expandable message composer max_lines must be positive"
      else if button_count > 0xfffe
      then Error "expandable message composer button count exceeds child bound"
      else
        let* curve =
          decode_enum
            curve_value
            [ 0, Animation.Curve.Linear; 1, Ease_in; 2, Ease_out; 3, Ease_in_out ]
            "invalid expandable message composer curve"
        in
        let decode_string label offset length =
          if Int64.compare length (Int64.of_int (Bytes.length payload - offset)) > 0
          then Error (label ^ " exceeds payload")
          else (
            let length = Int64.to_int length in
            let value = Bytes.sub_string payload offset length in
            let* value = decode_utf8 label value in
            Ok (value, offset + length))
        in
        let* fab_label, offset = decode_string "expandable FAB label" 24 label_length in
        if String.length fab_label = 0
        then Error "expandable FAB label must not be empty"
        else
          let* fab_tooltip, offset =
            decode_string "expandable FAB tooltip" offset fab_tooltip_length
          in
          if String.length fab_tooltip = 0
          then Error "expandable FAB tooltip must not be empty"
          else
            let* hint_text, offset =
              decode_string "expandable composer hint" offset hint_length
            in
            let rec decode_buttons remaining offset ids decoded =
              if remaining = 0
              then
                if offset = Bytes.length payload
                then Ok (List.rev decoded)
                else Error "expandable message composer props contain extra bytes"
              else if offset + 12 > Bytes.length payload
              then Error "expandable message composer button header exceeds payload"
              else (
                let id = Little_endian.get_u32_unsigned payload offset in
                let tooltip_length =
                  Little_endian.get_u32_unsigned payload (offset + 8)
                in
                let tooltip_offset = offset + 12 in
                if Int64.equal id 0L || List.mem id ids
                then
                  Error
                    "expandable message composer button ids must be positive and unique"
                else if
                  Int64.compare
                    tooltip_length
                    (Int64.of_int (Bytes.length payload - tooltip_offset))
                  > 0
                then Error "expandable message composer button tooltip exceeds payload"
                else
                  let* position =
                    decode_enum
                      (Char.code (Bytes.get payload (offset + 4)))
                      [ 0, Leading; 1, Trailing ]
                      "invalid expandable message composer button position"
                  in
                  let* visibility =
                    decode_enum
                      (Char.code (Bytes.get payload (offset + 5)))
                      [ 0, Always; 1, When_empty; 2, When_non_empty ]
                      "invalid expandable message composer button visibility"
                  in
                  let* style =
                    decode_enum
                      (Char.code (Bytes.get payload (offset + 6)))
                      [ 0, Plain; 1, Filled ]
                      "invalid expandable message composer button style"
                  in
                  let button_flags = Char.code (Bytes.get payload (offset + 7)) in
                  if button_flags land lnot 1 <> 0
                  then
                    Error "expandable message composer button flags contain unknown bits"
                  else (
                    let tooltip_length = Int64.to_int tooltip_length in
                    let tooltip =
                      Bytes.sub_string payload tooltip_offset tooltip_length
                    in
                    let* tooltip =
                      decode_utf8 "expandable message composer button tooltip" tooltip
                    in
                    if String.length tooltip = 0
                    then
                      Error "expandable message composer button tooltip must not be empty"
                    else
                      decode_buttons
                        (remaining - 1)
                        (tooltip_offset + tooltip_length)
                        (id :: ids)
                        ({ id = Int64.to_int id
                         ; tooltip
                         ; position
                         ; visibility
                         ; style
                         ; enabled = button_flags land 1 <> 0
                         }
                         :: decoded)))
            in
            let* buttons = decode_buttons button_count offset [] [] in
            Ok
              { enabled = flags land 1 <> 0
              ; fab_label
              ; fab_tooltip
              ; animation_duration_ms = duration
              ; animation_curve = curve
              ; max_lines
              ; hint_text
              ; buttons
              })
  ;;

  let decode_event ~event_id payload =
    if event_id = text_changed_event_id
    then
      Result.map
        (fun text -> Text_changed text)
        (decode_utf8 "text" (Bytes.to_string payload))
    else if event_id = button_pressed_event_id
    then
      if Bytes.length payload < 4
      then Error "expandable composer button event must contain a 4-byte button id"
      else (
        let button_id = Little_endian.get_u32_unsigned payload 0 in
        if Int64.equal button_id 0L
        then Error "expandable composer button event id must be positive"
        else
          Result.map
            (fun text -> Button_pressed { button_id = Int64.to_int button_id; text })
            (decode_utf8
               "button event text"
               (Bytes.sub_string payload 4 (Bytes.length payload - 4))))
    else Error "unknown expandable message composer event"
  ;;

  let extension =
    Extension.create
      ~kind_id
      ~version
      ~capabilities:[ Capability.Stateful; Semantics ]
      ~encode_props
      ~decode_event
      ()
  ;;

  let make_props
        enabled
        fab_label
        fab_tooltip
        animation_duration_ms
        animation_curve
        max_lines
        hint_text
        buttons
    =
    let props =
      { enabled
      ; fab_label
      ; fab_tooltip
      ; animation_duration_ms
      ; animation_curve
      ; max_lines
      ; hint_text
      ; buttons = List.map (fun button -> button.props) buttons
      }
    in
    validate_props props;
    props
  ;;

  let children fab_icon buttons =
    fab_icon :: List.map (fun button -> button.child) buttons
  ;;

  let create
        ?key
        ?(enabled = true)
        ~fab_label
        ~fab_tooltip
        ~fab_icon
        ?(animation_duration_ms = 200)
        ?(animation_curve = Animation.Curve.Ease_out)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ~buttons
        ~on_event
        ()
    =
    widget
      extension
      ?key
      ~props:
        (make_props
           enabled
           fab_label
           fab_tooltip
           animation_duration_ms
           animation_curve
           max_lines
           hint_text
           buttons)
      ~on_event
      ~children:(children fab_icon buttons)
      ()
  ;;

  let create_with_handler
        ?key
        ?(enabled = true)
        ~fab_label
        ~fab_tooltip
        ~fab_icon
        ?(animation_duration_ms = 200)
        ?(animation_curve = Animation.Curve.Ease_out)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ~buttons
        ~on_event
        ()
    =
    widget_with_handler
      extension
      ?key
      ~props:
        (make_props
           enabled
           fab_label
           fab_tooltip
           animation_duration_ms
           animation_curve
           max_lines
           hint_text
           buttons)
      ~on_event
      ~children:(children fab_icon buttons)
      ()
  ;;

  let event_of_payload = function
    | Event.Payload.Native_event event
      when event.kind_id = kind_id && event.version = version ->
      Result.to_option (decode_event ~event_id:event.event_id event.payload)
    | _ -> None
  ;;

  module For_testing = struct
    type nonrec button_props = button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type nonrec props = props =
      { enabled : bool
      ; fab_label : string
      ; fab_tooltip : string
      ; animation_duration_ms : int
      ; animation_curve : Animation.Curve.t
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    let decode_props_exn payload =
      match decode_props payload with
      | Ok props -> props
      | Error message -> invalid_arg message
    ;;
  end
end
