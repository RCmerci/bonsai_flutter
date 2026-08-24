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
  let version = 2
  let commit_event_id = ID.Native_widget.Event_id.of_int 1
  let default_action_border_radius = 999.

  type direction =
    | Start_to_end
    | End_to_start

  type disposition =
    | Dismiss
    | Rebound

  type action =
    { label : string
    ; background : Style.Color.t
    ; border_radius : float
    ; disposition : disposition
    ; icon : Widget.t
    }

  let validate_border_radius label value =
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then
      invalid_arg
        (Printf.sprintf
           "Native_widget.Swipe_action: %s must be finite and non-negative"
           label)
  ;;

  let action
        ~label
        ~background
        ?(border_radius = default_action_border_radius)
        ~disposition
        ~icon
        ()
    =
    if String.length label = 0
    then invalid_arg "Native_widget.Swipe_action: action label must not be empty";
    ignore (Text_editing.Utf16.length label);
    validate_border_radius "action border_radius" border_radius;
    { label; background; border_radius; disposition; icon }
  ;;

  type props =
    { start_action : action option
    ; end_action : action option
    ; clip_border_radius : float
    }

  let disposition_byte = function
    | Dismiss -> 0
    | Rebound -> 1
  ;;

  let encode_props { start_action; end_action; clip_border_radius } =
    let label = function
      | None -> ""
      | Some action -> action.label
    in
    let start_label = label start_action in
    let end_label = label end_action in
    let start_length = String.length start_label in
    let end_length = String.length end_label in
    let payload = Bytes.make (44 + start_length + end_length) '\000' in
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
    let border_radius = function
      | None -> default_action_border_radius
      | Some action -> action.border_radius
    in
    Little_endian.set_f64 payload 12 (border_radius start_action);
    Little_endian.set_f64 payload 20 (border_radius end_action);
    Little_endian.set_f64 payload 28 clip_border_radius;
    Little_endian.set_u32 payload 36 start_length;
    Little_endian.set_u32 payload 40 end_length;
    Bytes.blit_string start_label 0 payload 44 start_length;
    Bytes.blit_string end_label 0 payload (44 + start_length) end_length;
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

  let create
        ?key
        ?start_action
        ?end_action
        ?(clip_border_radius = 0.)
        ~content
        ~on_commit
        ()
    =
    validate_actions start_action end_action;
    validate_border_radius "clip_border_radius" clip_border_radius;
    widget
      extension
      ?key
      ~props:{ start_action; end_action; clip_border_radius }
      ~on_event:on_commit
      ~children:(children start_action end_action content)
      ()
  ;;

  let create_with_handler
        ?key
        ?start_action
        ?end_action
        ?(clip_border_radius = 0.)
        ~content
        ~on_commit
        ()
    =
    validate_actions start_action end_action;
    validate_border_radius "clip_border_radius" clip_border_radius;
    widget_with_handler
      extension
      ?key
      ~props:{ start_action; end_action; clip_border_radius }
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
