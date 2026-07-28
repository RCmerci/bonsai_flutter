module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

type t =
  { driver : Driver.t
  ; runtime_epoch : int64
  ; mutable sequence : int64
  ; mutable last_frame : Driver.frame option
  ; mutable baseline : string
  ; mutable presented_revision : int64
  ; pending_requests : (int64, Protocol.Wire_frame.host_request_payload) Hashtbl.t
  }

let fail format = Printf.ksprintf failwith format

let driver_ok = function
  | Ok value -> value
  | Error error -> fail "headless driver error: %s" (Driver.error_to_string error)
;;

let record_frame t frame =
  t.last_frame <- Some frame;
  match Protocol.Binary_codec.decode frame.Driver.bytes with
  | Error error -> fail "headless frame did not decode: %s" error.message
  | Ok wire ->
    List.iter
      (function
        | Protocol.Wire_frame.Host_request { request_id; payload } ->
          Hashtbl.replace t.pending_requests request_id payload
        | Cancel_host_request { request_id } ->
          Hashtbl.remove t.pending_requests request_id
        | _ -> ())
      wire.operations
;;

let step t ?events () =
  match driver_ok (Driver.step t.driver ?events ()) with
  | None -> ()
  | Some frame -> record_frame t frame
;;

let snapshot t =
  match Driver.For_testing.snapshot t.driver with
  | Some snapshot -> snapshot
  | None -> fail "headless driver has no mounted tree"
;;

let ordered_nodes snapshot =
  let rec visit reversed node_id =
    match Runtime.Mounted_tree.Snapshot.find snapshot node_id with
    | None -> fail "mounted snapshot references missing node %Ld" node_id
    | Some node -> Array.fold_left visit (node :: reversed) node.children
  in
  match Runtime.Mounted_tree.Snapshot.root_id snapshot with
  | None -> []
  | Some root_id -> List.rev (visit [] root_id)
;;

let find_all t query =
  snapshot t |> ordered_nodes |> List.filter (Query.Private.matches query)
;;

let find t query = List.nth_opt (find_all t query) 0

let require_node t query =
  match find_all t query with
  | [ node ] -> node
  | [] -> fail "query did not match a mounted node"
  | nodes ->
    fail "query matched %d nodes; interaction queries must be unique" (List.length nodes)
;;

let unquote_debug_key key =
  let value = Ui.Key.to_debug_string key in
  let length = String.length value in
  if length >= 2 && value.[0] = '"' && value.[length - 1] = '"'
  then String.sub value 1 (length - 2)
  else value
;;

let render_tree t =
  let snapshot = snapshot t in
  let output = Buffer.create 256 in
  let rec write depth node_id =
    let node =
      match Runtime.Mounted_tree.Snapshot.find snapshot node_id with
      | Some node -> node
      | None -> fail "mounted snapshot references missing node %Ld" node_id
    in
    if Buffer.length output > 0 then Buffer.add_char output '\n';
    Buffer.add_string output (String.make (depth * 2) ' ');
    Buffer.add_string output (Ui.Widget.Private.Kind.to_string node.kind);
    Option.iter
      (fun key -> Printf.bprintf output " key=%s" (unquote_debug_key key))
      node.key;
    Option.iter
      (fun test_id -> Printf.bprintf output " test_id=%s" (Ui.Test_id.to_string test_id))
      node.test_id;
    (match node.props with
     | Ui.Widget.Private.Text_props { value; _ } ->
       Buffer.add_char output ' ';
       Buffer.add_string output (Printf.sprintf "%S" value)
     | Native_widget_props { kind_id; version; _ } ->
       Printf.bprintf output " native_kind=%d version=%d" kind_id version
     | _ -> ());
    if Array.length node.event_bindings > 0
    then (
      Buffer.add_string output " events=[";
      Array.iteri
        (fun index (binding : Runtime.Mounted_tree.Mounted_binding.t) ->
           if index > 0 then Buffer.add_char output ',';
           Buffer.add_string output (Ui.Event.Tag.to_string binding.event_tag))
        node.event_bindings;
      Buffer.add_char output ']');
    Array.iter (write (depth + 1)) node.children
  in
  (match Runtime.Mounted_tree.Snapshot.root_id snapshot with
   | None -> ()
   | Some root_id -> write 0 root_id);
  Buffer.contents output
;;

let show t =
  let rendered = render_tree t in
  t.baseline <- rendered;
  rendered
;;

let lines value =
  if String.length value = 0
  then [||]
  else String.split_on_char '\n' value |> Array.of_list
;;

let show_diff t =
  let current = render_tree t in
  let before = lines t.baseline in
  let after = lines current in
  let output = Buffer.create 128 in
  let add_line prefix value =
    if Buffer.length output > 0 then Buffer.add_char output '\n';
    Buffer.add_string output prefix;
    Buffer.add_string output value
  in
  let count = max (Array.length before) (Array.length after) in
  for index = 0 to count - 1 do
    let left = if index < Array.length before then Some before.(index) else None in
    let right = if index < Array.length after then Some after.(index) else None in
    match left, right with
    | Some left, Some right when String.equal left right -> ()
    | Some left, Some right ->
      add_line "- " left;
      add_line "+ " right
    | Some left, None -> add_line "- " left
    | None, Some right -> add_line "+ " right
    | None, None -> ()
  done;
  t.baseline <- current;
  Buffer.contents output
;;

let protocol_tag =
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

let dispatch t query tag payload =
  let node = require_node t query in
  let binding =
    Array.find_opt
      (fun binding ->
         Ui.Event.Tag.equal binding.Runtime.Mounted_tree.Mounted_binding.event_tag tag)
      node.event_bindings
    |> function
    | Some binding -> binding
    | None ->
      fail
        "node %Ld does not bind event %s"
        (Runtime.Node_id.to_int64 node.node_id)
        (Ui.Event.Tag.to_string tag)
  in
  t.sequence <- Int64.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = Runtime.Node_id.to_int64 node.node_id
      ; handler_id = Runtime.Handler_id.to_int64 binding.handler_id
      ; event_tag = protocol_tag tag
      ; payload
      }
  in
  step
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ()
;;

let click t query =
  let node = require_node t query in
  let binds tag =
    Array.exists
      (fun binding ->
         Ui.Event.Tag.equal binding.Runtime.Mounted_tree.Mounted_binding.event_tag tag)
      node.event_bindings
  in
  if binds Ui.Event.Tag.Press
  then dispatch t query Ui.Event.Tag.Press Protocol.Inbound_event.Unit
  else if binds Ui.Event.Tag.Tap
  then
    dispatch
      t
      query
      Ui.Event.Tag.Tap
      (Protocol.Inbound_event.Tap
         { local_x = 0.
         ; local_y = 0.
         ; global_x = 0.
         ; global_y = 0.
         ; pointer_kind = Mouse
         })
  else fail "matched node does not bind a press or tap event"
;;

let long_press t query =
  dispatch t query Ui.Event.Tag.Long_press Protocol.Inbound_event.Unit
;;

let route_pop t query ~page_key ?result () =
  dispatch
    t
    query
    Ui.Event.Tag.Route_pop
    (Protocol.Inbound_event.Route_pop { page_key; result })
;;

let native_event t query ~kind_id ~version ~event_id ~payload =
  dispatch
    t
    query
    Ui.Event.Tag.Native_event
    (Protocol.Inbound_event.Native_event { kind_id; version; event_id; payload })
;;

let apply_text_edit
      t
      query
      ~local_revision
      ~base_document_revision
      ~text
      ~selection_start
      ~selection_end
      ?composing_start
      ?composing_end
      ()
  =
  let node = require_node t query in
  let session_id =
    match node.props with
    | Ui.Widget.Private.Text_input_props { session_id; _ } -> session_id
    | _ -> fail "text edit query did not match a Text_input node"
  in
  let selection =
    Protocol.Inbound_event.{ start_utf16 = selection_start; end_utf16 = selection_end }
  in
  let composing =
    match composing_start, composing_end with
    | None, None -> None
    | Some start_utf16, Some end_utf16 ->
      Some Protocol.Inbound_event.{ start_utf16; end_utf16 }
    | None, Some _ | Some _, None ->
      invalid_arg "Handle.apply_text_edit: composing bounds must be supplied together"
  in
  dispatch
    t
    query
    Ui.Event.Tag.Text_edit
    (Protocol.Inbound_event.Text_edit
       { session_id; local_revision; base_document_revision; text; selection; composing })
;;

let input_text t query text =
  let node = require_node t query in
  let document_revision, accepted_local_revision =
    match node.props with
    | Ui.Widget.Private.Text_input_props { document_revision; accepted_local_revision; _ }
      -> document_revision, accepted_local_revision
    | _ -> fail "input_text query did not match a Text_input node"
  in
  let cursor = Ui.Text_editing.Utf16.length text in
  apply_text_edit
    t
    query
    ~local_revision:(Int64.succ accepted_local_revision)
    ~base_document_revision:document_revision
    ~text
    ~selection_start:cursor
    ~selection_end:cursor
    ()
;;

let key_down t query ~logical_key =
  dispatch
    t
    query
    Ui.Event.Tag.Key
    (Protocol.Inbound_event.Key
       { logical_key; physical_key = 0L; action = Key_down; modifiers = 0 })
;;

let focus t query =
  dispatch t query Ui.Event.Tag.Focus_changed (Protocol.Inbound_event.Bool true)
;;

let blur t query =
  dispatch t query Ui.Event.Tag.Focus_changed (Protocol.Inbound_event.Bool false)
;;

let protocol_environment (environment : Environment.snapshot) =
  let insets (value : Environment.edge_insets) =
    Protocol.Inbound_event.
      { left = value.left; top = value.top; right = value.right; bottom = value.bottom }
  in
  Protocol.Inbound_event.
    { viewport_width = environment.viewport_width
    ; viewport_height = environment.viewport_height
    ; device_pixel_ratio = environment.device_pixel_ratio
    ; text_scale = environment.text_scale
    ; brightness =
        (match environment.brightness with
         | Environment.Light -> Environment_light
         | Dark -> Environment_dark)
    ; platform = environment.platform
    ; locale = environment.locale
    ; safe_area = insets environment.safe_area
    ; keyboard_insets = insets environment.keyboard_insets
    ; accessible_navigation = environment.accessible_navigation
    ; bold_text = environment.bold_text
    ; invert_colors = environment.invert_colors
    ; disable_animations = environment.disable_animations
    ; reduced_motion = environment.reduced_motion
    ; high_contrast = environment.high_contrast
    ; orientation =
        (match environment.orientation with
         | Environment.Portrait -> Portrait
         | Landscape -> Landscape)
    ; pointer_kinds = environment.pointer_kinds
    }
;;

let set_environment t environment =
  t.sequence <- Int64.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = 0L
      ; handler_id = 0L
      ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
      ; payload = Environment_changed (protocol_environment environment)
      }
  in
  step
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ()
;;

let resize t ~width ~height =
  let environment = Driver.For_testing.environment t.driver in
  set_environment t { environment with viewport_width = width; viewport_height = height }
;;

let only_pending_request t =
  match
    Hashtbl.to_seq_keys t.pending_requests |> List.of_seq |> List.sort Int64.compare
  with
  | [ request_id ] -> request_id
  | [] -> fail "no host effect is pending"
  | requests ->
    fail "%d host effects are pending; pass request_id explicitly" (List.length requests)
;;

let respond_to_host_effect t ?request_id ?(status = Protocol.Inbound_event.Host_ok) value =
  let request_id =
    match request_id with
    | Some request_id -> request_id
    | None -> only_pending_request t
  in
  if not (Hashtbl.mem t.pending_requests request_id)
  then fail "host request %Ld is not pending" request_id;
  t.sequence <- Int64.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = 0L
      ; handler_id = 0L
      ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
      ; payload = Host_response { request_id; status; value }
      }
  in
  step
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ();
  Hashtbl.remove t.pending_requests request_id
;;

let trigger_frame_presented t =
  let revision = Driver.For_testing.revision t.driver in
  if Int64.compare revision t.presented_revision > 0
  then (
    driver_ok (Driver.frame_presented t.driver ~revision);
    t.presented_revision <- revision)
;;

let last_frame t = t.last_frame
let revision t = Driver.For_testing.revision t.driver
let pending_host_effect_count t = Driver.For_testing.pending_host_effect_count t.driver
let shutdown t = Driver.shutdown t.driver

let create ~runtime_epoch ~time_source component =
  let driver = Driver.create ~runtime_epoch ~time_source component in
  let t =
    { driver
    ; runtime_epoch
    ; sequence = 0L
    ; last_frame = None
    ; baseline = ""
    ; presented_revision = 0L
    ; pending_requests = Hashtbl.create 4
    }
  in
  (match driver_ok (Driver.step driver ()) with
   | None -> fail "initial headless step did not emit a full snapshot"
   | Some frame -> record_frame t frame);
  t.baseline <- render_tree t;
  t
;;
