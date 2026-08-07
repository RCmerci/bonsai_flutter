module ID = Bonsai_flutter_spec.Id
module Protocol = Bonsai_flutter_protocol
module Effect = Bonsai.Effect

type error =
  | Failed of string
  | Cancelled
  | Shutdown
  | Invalid_response of string

type file =
  { path : string option
  ; data : bytes option
  }

type platform_information =
  { operating_system : string
  ; operating_system_version : string
  ; locale_name : string
  }

type layout =
  { left : float
  ; top : float
  ; width : float
  ; height : float
  }

type native_menu_item =
  { item_id : ID.Host.native_menu_item_id
  ; label : string
  ; enabled : bool
  }

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

module Cancellation = struct
  type t =
    { mutable cancelled : bool
    ; mutable cancel_active : (unit -> unit) option
    }

  let create () = { cancelled = false; cancel_active = None }

  let cancel t =
    if not t.cancelled
    then (
      t.cancelled <- true;
      Option.iter (fun cancel -> cancel ()) t.cancel_active;
      t.cancel_active <- None)
  ;;

  let is_cancelled t = t.cancelled
end

module Application_platform = struct
  type error =
    | Unavailable
    | Payload_too_large
    | Handler_failed of string
    | Cancelled
    | Shutdown
    | Runtime_replaced
    | Invalid_response of string

  let maximum_payload_bytes =
    Protocol.Generated_protocol.Limits.max_application_payload_bytes
  ;;

  module Cancellation = struct
    type t =
      { mutable cancelled : bool
      ; mutable cancel_active : (unit -> unit) option
      }

    let create () = { cancelled = false; cancel_active = None }

    let cancel t =
      if not t.cancelled
      then (
        t.cancelled <- true;
        Option.iter (fun cancel -> cancel ()) t.cancel_active;
        t.cancel_active <- None)
    ;;
  end

  type pending =
    { callback : (unit, (bytes, error) result) Effect.Private.Callback.t
    ; cancellation : Cancellation.t option
    }

  type queued_operation =
    { id : int64
    ; operation : Protocol.Wire_frame.operation
    }

  type t =
    { schedule : unit Effect.t -> unit
    ; pending : (int64, pending) Hashtbl.t
    ; operations : queued_operation Queue.t
    ; mutable subscribers : (bytes -> unit Effect.t) list
    ; mutable next_request_id : int64
    ; mutable next_operation_id : int64
    ; mutable shutdown_error : error option
    }

  let respond t callback response =
    t.schedule (Effect.Private.Callback.respond_to callback response)
  ;;

  let enqueue_operation t operation =
    if Int64.equal t.next_operation_id Int64.max_int
    then failwith "application operation ID space exhausted";
    let id = t.next_operation_id in
    t.next_operation_id <- Int64.succ id;
    Queue.add { id; operation } t.operations
  ;;

  let cancel_request t request_id =
    match Hashtbl.find_opt t.pending request_id with
    | None -> ()
    | Some pending ->
      Hashtbl.remove t.pending request_id;
      Option.iter
        (fun (cancellation : Cancellation.t) -> cancellation.cancel_active <- None)
        pending.cancellation;
      respond t pending.callback (Error Cancelled)
  ;;

  let request ?cancellation t payload =
    let payload = Bytes.copy payload in
    Effect.Private.make ~request:() ~evaluator:(fun callback ->
      match t.shutdown_error with
      | Some error -> respond t callback (Error error)
      | None when Bytes.length payload > maximum_payload_bytes ->
        respond t callback (Error Payload_too_large)
      | None ->
        (match cancellation with
         | Some (cancellation : Cancellation.t) when cancellation.cancelled ->
           respond t callback (Error Cancelled)
         | _ ->
           if Int64.equal t.next_request_id Int64.max_int
           then respond t callback (Error (Handler_failed "request ID space exhausted"))
           else (
             let request_id = t.next_request_id in
             t.next_request_id <- Int64.succ request_id;
             Hashtbl.add t.pending request_id { callback; cancellation };
             Option.iter
               (fun (cancellation : Cancellation.t) ->
                  cancellation.cancel_active
                  <- Some (fun () -> cancel_request t request_id))
               cancellation;
             enqueue_operation
               t
               (Protocol.Wire_frame.Application_request
                  { request_id; payload = Bytes.copy payload }))))
  ;;

  let on_event t subscriber =
    if Option.is_none t.shutdown_error
    then t.subscribers <- t.subscribers @ [ subscriber ]
  ;;

  module Prepared_operations = struct
    type nonrec t =
      { owner : t
      ; entries : queued_operation list
      ; mutable committed : bool
      }

    let operations t = List.map (fun entry -> entry.operation) t.entries
  end

  let prepare_operations t =
    Prepared_operations.
      { owner = t; entries = Queue.to_seq t.operations |> List.of_seq; committed = false }
  ;;

  let commit_operations t (prepared : Prepared_operations.t) =
    if prepared.committed
    then Error "prepared application operations were already committed"
    else if not (prepared.owner == t)
    then Error "prepared application operations belong to another manager"
    else (
      let current = Queue.to_seq t.operations |> List.of_seq in
      let rec validate_prefix expected actual =
        match expected, actual with
        | [], _ -> Ok ()
        | _, [] -> Error "prepared application operation prefix is unavailable"
        | expected :: expected_rest, actual :: actual_rest ->
          if Int64.equal expected.id actual.id
          then validate_prefix expected_rest actual_rest
          else Error "prepared application operation prefix is stale"
      in
      match validate_prefix prepared.entries current with
      | Error _ as error -> error
      | Ok () ->
        List.iter (fun _ -> ignore (Queue.take t.operations)) prepared.entries;
        prepared.committed <- true;
        Ok ())
  ;;

  module Private = struct
    let create ~schedule =
      { schedule
      ; pending = Hashtbl.create 16
      ; operations = Queue.create ()
      ; subscribers = []
      ; next_request_id = 1L
      ; next_operation_id = 1L
      ; shutdown_error = None
      }
    ;;

    module Validated_input = struct
      type nonrec t =
        { owner : t
        ; request_id : int64 option
        ; still_current : unit -> bool
        ; apply : unit -> unit
        }

      let request_id t = t.request_id
    end

    let typed_error (error : Protocol.Inbound_event.application_error) =
      match error.code with
      | Protocol.Inbound_event.Unavailable -> Unavailable
      | Payload_too_large -> Payload_too_large
      | Handler_failed -> Handler_failed error.message
      | Cancelled -> Cancelled
      | Shutdown -> Shutdown
      | Runtime_replaced -> Runtime_replaced
      | Invalid_response -> Invalid_response error.message
    ;;

    let validate_response t response_request_id result =
      if Int64.compare response_request_id 0L <= 0
      then Error "application request ID must be positive"
      else (
        match Hashtbl.find_opt t.pending response_request_id with
        | None ->
          Error (Printf.sprintf "unknown application request ID %Ld" response_request_id)
        | Some pending ->
          Ok
            Validated_input.
              { owner = t
              ; request_id = Some response_request_id
              ; still_current =
                  (fun () ->
                    match Hashtbl.find_opt t.pending response_request_id with
                    | Some current -> current == pending
                    | None -> false)
              ; apply =
                  (fun () ->
                    Hashtbl.remove t.pending response_request_id;
                    Option.iter
                      (fun (cancellation : Cancellation.t) ->
                         cancellation.cancel_active <- None)
                      pending.cancellation;
                    respond t pending.callback result)
              })
    ;;

    let validate_input t = function
      | Protocol.Inbound_event.Application_response { request_id; payload } ->
        if Bytes.length payload > maximum_payload_bytes
        then Error "application response exceeds the payload limit"
        else validate_response t request_id (Ok (Bytes.copy payload))
      | Application_request_error { request_id; error } ->
        validate_response t request_id (Error (typed_error error))
      | Application_event payload ->
        if Bytes.length payload > maximum_payload_bytes
        then Error "application event exceeds the payload limit"
        else (
          let payload = Bytes.copy payload in
          let subscribers = t.subscribers in
          Ok
            Validated_input.
              { owner = t
              ; request_id = None
              ; still_current = (fun () -> Option.is_none t.shutdown_error)
              ; apply =
                  (fun () ->
                    List.iter
                      (fun subscriber -> t.schedule (subscriber (Bytes.copy payload)))
                      subscribers)
              })
      | _ -> Error "payload is not an application platform control"
    ;;

    let resolve_validated t (validated : Validated_input.t) =
      if not (validated.owner == t)
      then Error "validated application input belongs to another manager"
      else if not (validated.still_current ())
      then Error "stale application platform input"
      else (
        validated.apply ();
        Ok ())
    ;;

    let shutdown t error =
      if Option.is_none t.shutdown_error
      then (
        t.shutdown_error <- Some error;
        Hashtbl.iter
          (fun _ pending ->
             Option.iter
               (fun (cancellation : Cancellation.t) -> cancellation.cancel_active <- None)
               pending.cancellation;
             respond t pending.callback (Error error))
          t.pending;
        Hashtbl.clear t.pending;
        Queue.clear t.operations;
        t.subscribers <- [])
    ;;

    let pending_count t = Hashtbl.length t.pending
  end
end

type pending =
  | Pending :
      { decode : bytes -> ('a, error) result
      ; callback : (unit, ('a, error) result) Effect.Private.Callback.t
      ; cancellation : Cancellation.t option
      }
      -> pending

type queued_operation =
  { id : ID.Host.operation_id
  ; operation : Protocol.Wire_frame.operation
  }

type t =
  { schedule : unit Effect.t -> unit
  ; pending : (ID.Host.request_id, pending) Hashtbl.t
  ; cancelled : (ID.Host.request_id, unit) Hashtbl.t
  ; operations : queued_operation Queue.t
  ; mutable next_request_id : ID.Host.request_id
  ; mutable next_operation_id : ID.Host.operation_id
  ; mutable shutdown : bool
  }

let enqueue_operation t operation =
  if ID.Host.Operation_id.equal t.next_operation_id ID.Host.Operation_id.max_value
  then failwith "host operation ID space exhausted";
  let id = t.next_operation_id in
  t.next_operation_id <- ID.Host.Operation_id.succ id;
  Queue.add { id; operation } t.operations
;;

let invalid_response message = Error (Invalid_response message)

let valid_utf8 value =
  let length = String.length value in
  let rec loop offset =
    if offset = length
    then true
    else (
      let decoded = String.get_utf_8_uchar value offset in
      Uchar.utf_decode_is_valid decoded && loop (offset + Uchar.utf_decode_length decoded))
  in
  loop 0
;;

let decode_string bytes =
  let value = Bytes.to_string bytes in
  if valid_utf8 value then Ok value else invalid_response "response is not valid UTF-8"
;;

let decode_unit bytes =
  if Bytes.length bytes = 0 then Ok () else invalid_response "unit response must be empty"
;;

module Bytes_reader = struct
  type t =
    { bytes : bytes
    ; mutable offset : int
    }

  let create bytes = { bytes; offset = 0 }
  let remaining t = Bytes.length t.bytes - t.offset

  let require t count =
    if count < 0 || count > remaining t then raise (Invalid_argument "truncated response")
  ;;

  let u8 t =
    require t 1;
    let value = Char.code (Bytes.get t.bytes t.offset) in
    t.offset <- t.offset + 1;
    value
  ;;

  let u32 t =
    let b0 = u8 t in
    let b1 = u8 t in
    let b2 = u8 t in
    let b3 = u8 t in
    b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24)
  ;;

  let f64 t =
    let bits = ref 0L in
    for shift = 0 to 7 do
      bits := Int64.logor !bits (Int64.shift_left (Int64.of_int (u8 t)) (shift * 8))
    done;
    Int64.float_of_bits !bits
  ;;

  let bytes t length =
    require t length;
    let value = Bytes.sub t.bytes t.offset length in
    t.offset <- t.offset + length;
    value
  ;;

  let string t =
    let value = bytes t (u32 t) |> Bytes.to_string in
    if not (valid_utf8 value) then raise (Invalid_argument "invalid UTF-8");
    value
  ;;

  let optional read t =
    match u8 t with
    | 0 -> None
    | 1 -> Some (read t)
    | _ -> raise (Invalid_argument "invalid optional tag")
  ;;

  let require_empty t =
    if remaining t <> 0 then raise (Invalid_argument "trailing response bytes")
  ;;
end

let protect_decode decode bytes =
  try decode bytes with
  | Invalid_argument message -> invalid_response message
;;

let decode_optional_file bytes =
  protect_decode
    (fun bytes ->
       let reader = Bytes_reader.create bytes in
       let value =
         match Bytes_reader.u8 reader with
         | 0 -> None
         | 1 ->
           let path = Bytes_reader.optional Bytes_reader.string reader in
           let data =
             Bytes_reader.optional
               (fun reader -> Bytes_reader.bytes reader (Bytes_reader.u32 reader))
               reader
           in
           Some { path; data }
         | _ -> raise (Invalid_argument "invalid optional file tag")
       in
       Bytes_reader.require_empty reader;
       Ok value)
    bytes
;;

let decode_optional_string bytes =
  protect_decode
    (fun bytes ->
       let reader = Bytes_reader.create bytes in
       let value = Bytes_reader.optional Bytes_reader.string reader in
       Bytes_reader.require_empty reader;
       Ok value)
    bytes
;;

let decode_platform_information bytes =
  protect_decode
    (fun bytes ->
       let reader = Bytes_reader.create bytes in
       let operating_system = Bytes_reader.string reader in
       let operating_system_version = Bytes_reader.string reader in
       let locale_name = Bytes_reader.string reader in
       Bytes_reader.require_empty reader;
       Ok { operating_system; operating_system_version; locale_name })
    bytes
;;

let decode_layout bytes =
  protect_decode
    (fun bytes ->
       let reader = Bytes_reader.create bytes in
       let left = Bytes_reader.f64 reader in
       let top = Bytes_reader.f64 reader in
       let width = Bytes_reader.f64 reader in
       let height = Bytes_reader.f64 reader in
       Bytes_reader.require_empty reader;
       if
         not
           (Float.is_finite left
            && Float.is_finite top
            && Float.is_finite width
            && Float.is_finite height)
       then invalid_response "layout response contains a non-finite value"
       else Ok { left; top; width; height })
    bytes
;;

let respond t callback response =
  t.schedule (Effect.Private.Callback.respond_to callback response)
;;

let cancel_request t request_id =
  match Hashtbl.find_opt t.pending request_id with
  | None -> ()
  | Some (Pending pending) ->
    Hashtbl.remove t.pending request_id;
    Hashtbl.replace t.cancelled request_id ();
    enqueue_operation t (Protocol.Wire_frame.Cancel_host_request { request_id });
    Option.iter
      (fun (cancellation : Cancellation.t) -> cancellation.cancel_active <- None)
      pending.cancellation;
    respond t pending.callback (Error Cancelled)
;;

let request ?cancellation t payload decode =
  Effect.Private.make ~request:() ~evaluator:(fun callback ->
    if t.shutdown
    then respond t callback (Error Shutdown)
    else (
      match cancellation with
      | Some (cancellation : Cancellation.t) when cancellation.cancelled ->
        respond t callback (Error Cancelled)
      | _ ->
        if ID.Host.Request_id.equal t.next_request_id ID.Host.Request_id.max_value
        then respond t callback (Error (Failed "host request ID space exhausted"))
        else (
          let request_id = t.next_request_id in
          t.next_request_id <- ID.Host.Request_id.succ request_id;
          Hashtbl.add t.pending request_id (Pending { decode; callback; cancellation });
          Option.iter
            (fun (cancellation : Cancellation.t) ->
               cancellation.cancel_active <- Some (fun () -> cancel_request t request_id))
            cancellation;
          enqueue_operation t (Protocol.Wire_frame.Host_request { request_id; payload }))))
;;

module Clipboard = struct
  let read ?cancellation t () =
    request ?cancellation t Protocol.Wire_frame.Clipboard_read decode_string
  ;;

  let write ?cancellation t text =
    request ?cancellation t (Protocol.Wire_frame.Clipboard_write { text }) decode_unit
  ;;
end

let open_url ?cancellation t uri =
  request ?cancellation t (Protocol.Wire_frame.Open_url { uri }) decode_unit
;;

let pick_file ?cancellation ?(allowed_extensions = []) ?(allow_multiple = false) t () =
  request
    ?cancellation
    t
    (Protocol.Wire_frame.Pick_file { allowed_extensions; allow_multiple })
    decode_optional_file
;;

let save_file ?cancellation ?suggested_name ~data t () =
  request
    ?cancellation
    t
    (Protocol.Wire_frame.Save_file { suggested_name; data })
    decode_optional_file
;;

let request_focus ?cancellation t ~node_id =
  request ?cancellation t (Protocol.Wire_frame.Request_focus { node_id }) decode_unit
;;

let clear_focus ?cancellation t () =
  request ?cancellation t Protocol.Wire_frame.Clear_focus decode_unit
;;

let scroll_to ?cancellation ?(alignment = 0.) ?(animated = true) t ~node_id =
  request
    ?cancellation
    t
    (Protocol.Wire_frame.Scroll_to { node_id; alignment; animated })
    decode_unit
;;

let set_window_title ?cancellation t title =
  request ?cancellation t (Protocol.Wire_frame.Set_window_title { title }) decode_unit
;;

let set_window_size ?cancellation t ~width ~height =
  request
    ?cancellation
    t
    (Protocol.Wire_frame.Set_window_size { width; height })
    decode_unit
;;

let show_native_menu ?cancellation t items =
  let items =
    List.map
      (fun (item : native_menu_item) ->
         Protocol.Wire_frame.
           { item_id = item.item_id; label = item.label; enabled = item.enabled })
      items
  in
  request
    ?cancellation
    t
    (Protocol.Wire_frame.Show_native_menu { items })
    (fun bytes ->
       match decode_optional_string bytes with
       | Error _ as error -> error
       | Ok item_id -> Ok (Option.map ID.Host.Native_menu_item_id.of_string item_id))
;;

let haptic_feedback ?cancellation t kind =
  let kind =
    match kind with
    | Haptic_light -> Protocol.Wire_frame.Haptic_light
    | Haptic_medium -> Protocol.Wire_frame.Haptic_medium
    | Haptic_heavy -> Protocol.Wire_frame.Haptic_heavy
    | Haptic_selection -> Protocol.Wire_frame.Haptic_selection
  in
  request ?cancellation t (Protocol.Wire_frame.Haptic_feedback kind) decode_unit
;;

let platform_information ?cancellation t () =
  request
    ?cancellation
    t
    Protocol.Wire_frame.Platform_information
    decode_platform_information
;;

let measure_layout ?cancellation t ~node_id =
  request ?cancellation t (Protocol.Wire_frame.Measure_layout { node_id }) decode_layout
;;

module Prepared_operations = struct
  type nonrec t =
    { owner : t
    ; entries : queued_operation list
    ; mutable committed : bool
    }

  let operations t = List.map (fun entry -> entry.operation) t.entries
end

let prepare_operations t =
  Prepared_operations.
    { owner = t; entries = Queue.to_seq t.operations |> List.of_seq; committed = false }
;;

let commit_operations t (prepared : Prepared_operations.t) =
  if prepared.committed
  then Error "prepared host operations were already committed"
  else if not (prepared.owner == t)
  then Error "prepared host operations belong to another manager"
  else (
    let current = Queue.to_seq t.operations |> List.of_seq in
    let rec validate_prefix expected actual =
      match expected, actual with
      | [], _ -> Ok ()
      | _, [] -> Error "prepared host operation prefix is no longer available"
      | expected :: expected_rest, actual :: actual_rest ->
        if ID.Host.Operation_id.equal expected.id actual.id
        then validate_prefix expected_rest actual_rest
        else Error "prepared host operation prefix is stale"
    in
    match validate_prefix prepared.entries current with
    | Error _ as error -> error
    | Ok () ->
      List.iter (fun _ -> ignore (Queue.take t.operations)) prepared.entries;
      prepared.committed <- true;
      Ok ())
;;

module Private = struct
  let create ~schedule =
    { schedule
    ; pending = Hashtbl.create 16
    ; cancelled = Hashtbl.create 16
    ; operations = Queue.create ()
    ; next_request_id = ID.Host.Request_id.one
    ; next_operation_id = ID.Host.Operation_id.one
    ; shutdown = false
    }
  ;;

  module Validated_response = struct
    type nonrec t =
      { owner : t
      ; request_id : ID.Host.request_id
      ; pending_identity : pending option
      ; apply : unit -> unit
      }

    let request_id t = t.request_id
  end

  let validate_response t (response : Protocol.Inbound_event.host_response) =
    match Hashtbl.find_opt t.pending response.request_id with
    | None ->
      if Hashtbl.mem t.cancelled response.request_id
      then
        Ok
          Validated_response.
            { owner = t
            ; request_id = response.request_id
            ; pending_identity = None
            ; apply = (fun () -> Hashtbl.remove t.cancelled response.request_id)
            }
      else
        Error
          (Printf.sprintf
             "unknown host request ID %Ld"
             (ID.Host.Request_id.to_int64 response.request_id))
    | Some (Pending pending as pending_identity) ->
      let result =
        match response.status with
        | Protocol.Inbound_event.Host_ok -> pending.decode response.value
        | Host_error ->
          (match decode_string response.value with
           | Ok message -> Error (Failed message)
           | Error error -> Error error)
        | Host_cancelled -> Error Cancelled
      in
      Ok
        Validated_response.
          { owner = t
          ; request_id = response.request_id
          ; pending_identity = Some pending_identity
          ; apply =
              (fun () ->
                Hashtbl.remove t.pending response.request_id;
                Option.iter
                  (fun (cancellation : Cancellation.t) ->
                     cancellation.cancel_active <- None)
                  pending.cancellation;
                respond t pending.callback result)
          }
  ;;

  let resolve_validated t (validated : Validated_response.t) =
    if not (validated.owner == t)
    then Error "validated host response belongs to another manager"
    else (
      let still_current =
        match validated.pending_identity with
        | None -> Hashtbl.mem t.cancelled validated.request_id
        | Some expected ->
          (match Hashtbl.find_opt t.pending validated.request_id with
           | Some actual -> actual == expected
           | None -> false)
      in
      if not still_current
      then
        Error
          (Printf.sprintf
             "stale host response ID %Ld"
             (ID.Host.Request_id.to_int64 validated.request_id))
      else (
        validated.apply ();
        Ok ()))
  ;;

  let resolve t response =
    match validate_response t response with
    | Error _ as error -> error
    | Ok validated -> resolve_validated t validated
  ;;

  let shutdown t =
    if not t.shutdown
    then (
      t.shutdown <- true;
      Hashtbl.iter
        (fun _ (Pending pending) ->
           Option.iter
             (fun (cancellation : Cancellation.t) -> cancellation.cancel_active <- None)
             pending.cancellation;
           respond t pending.callback (Error Shutdown))
        t.pending;
      Hashtbl.clear t.pending;
      Hashtbl.clear t.cancelled;
      Queue.clear t.operations)
  ;;

  let pending_count t = Hashtbl.length t.pending
end
