module Protocol = Bonsai_flutter_protocol

external ensure_native_bridge_linked : unit -> unit = "bf_native_embed_link_anchor"

let embed ~name app =
  Entrypoint.register ~name app;
  ensure_native_bridge_linked ()
;;

type status =
  | Ok
  | Recoverable_error
  | Fatal_error

type create_result =
  { status : status
  ; handle : int64
  ; error : string
  }

type output =
  { status : status
  ; bytes : bytes
  ; presentation_id : int64
  ; revision : int64
  ; error_code : int
  ; error : string
  }

let runtimes : (int64, Driver.t) Hashtbl.t = Hashtbl.create 8
let random = Random.State.make_self_init ()

let status_code = function
  | Ok -> 0
  | Recoverable_error -> 1
  | Fatal_error -> 2
;;

let create_error error = { status = Fatal_error; handle = 0L; error }

let output
      ?(status = Ok)
      ?(bytes = Bytes.empty)
      ?(presentation_id = 0L)
      ?(revision = 0L)
      ?(error_code = 0)
      ?(error = "")
      ()
  =
  { status; bytes; presentation_id; revision; error_code; error }
;;

let fresh_handle () =
  let rec loop () =
    let high = Int64.of_int (Random.State.bits random) in
    let low = Int64.of_int (Random.State.bits random) in
    let candidate =
      Int64.logor (Int64.shift_left high 30) low |> Int64.logand Int64.max_int
    in
    if Int64.equal candidate 0L || Hashtbl.mem runtimes candidate
    then loop ()
    else candidate
  in
  loop ()
;;

let exception_message exception_ =
  let message =
    match exception_ with
    | Failure message | Invalid_argument message -> message
    | _ -> Printexc.to_string exception_
  in
  let backtrace = Printexc.get_backtrace () in
  if String.length backtrace = 0 then message else message ^ "\n" ^ backtrace
;;

let () = Printexc.record_backtrace true

let create config =
  try
    let name = Bytes.to_string config in
    match Entrypoint.Private.find name with
    | None -> create_error ("Unknown OCaml entrypoint: " ^ name)
    | Some app ->
      let handle = fresh_handle () in
      let time_source = Bonsai.Time_source.create ~start:(Core.Time_ns.now ()) in
      let driver =
        Driver.create
          ?trace:(App.Private.trace app)
          ~runtime_epoch:handle
          ~time_source
          (App.Private.component app)
      in
      Hashtbl.add runtimes handle driver;
      { status = Ok; handle; error = "" }
  with
  | exception_ -> create_error (exception_message exception_)
;;

let driver_error_metadata error =
  let status, error_code =
    match error with
    | Driver.Event_error
        (Bonsai_flutter_runtime.Event_dispatcher.Handler_error runtime_error)
    | Runtime_error runtime_error ->
      let error_code =
        match runtime_error with
        | Bonsai_flutter_runtime.Runtime_error.Duplicate_key _ -> 3
        | Revision_mismatch _ -> 2
        | Stale_event _ | Duplicate_or_out_of_order_event _ -> 7
        | Handler_missing _ | Handler_mismatch _ -> 6
        | Handler_exception _ -> 9
        | Invalid_patch _ | Wrong_runtime_epoch _ -> 1
      in
      Recoverable_error, error_code
    | Event_error (Invalid_event _) -> Recoverable_error, 1
    | Codec_error _ -> Fatal_error, 1
    | Unsupported_widget _ -> Fatal_error, 4
    | Invalid_state message ->
      if Core.String.is_substring message ~substring:"monotonic"
      then Recoverable_error, 14
      else if Core.String.is_substring message ~substring:"presentation"
      then Recoverable_error, 13
      else Fatal_error, 15
    | Lifecycle_error _ -> Fatal_error, 11
    | Host_response_error _ -> Fatal_error, 8
    | Shutdown -> Fatal_error, 9
  in
  status, error_code, Driver.error_to_string error
;;

let driver_error error =
  let status, error_code, error = driver_error_metadata error in
  output ~status ~error_code ~error ()
;;

let find_runtime handle =
  match Hashtbl.find_opt runtimes handle with
  | Some runtime -> Result.Ok runtime
  | None ->
    Result.Error
      (output ~status:Fatal_error ~error_code:9 ~error:"Unknown native runtime handle" ())
;;

let pump handle monotonic_now_ns input =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      let decoded_events, decode_error =
        if Bytes.length input = 0
        then None, None
        else (
          match Protocol.Event_batch_codec.decode input with
          | Result.Ok events -> Some events, None
          | Result.Error error ->
            ( None
            , Some
                (Driver.Event_error
                   (Bonsai_flutter_runtime.Event_dispatcher.Invalid_event error.message))
            ))
      in
      let result =
        match decoded_events with
        | None -> Driver.pump driver ~monotonic_now_ns ()
        | Some events -> Driver.pump driver ~monotonic_now_ns ~events ()
      in
      (match result with
       | Result.Error error -> driver_error error
       | Result.Ok result ->
         let recoverable_error =
           match decode_error with
           | Some error -> Some error
           | None -> result.recoverable_error
         in
         let bytes =
           match result.frame with
           | None -> Bytes.empty
           | Some frame -> frame.bytes
         in
         (match recoverable_error with
          | None ->
            output
              ~bytes
              ~presentation_id:result.presentation_id
              ~revision:result.renderer_revision
              ()
          | Some error ->
            let _, error_code, error = driver_error_metadata error in
            output
              ~status:Recoverable_error
              ~bytes
              ~presentation_id:result.presentation_id
              ~revision:result.renderer_revision
              ~error_code
              ~error
              ()))
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let presentation_succeeded handle presentation_id revision monotonic_now_ns =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      (match
         Driver.presentation_succeeded
           driver
           ~presentation_id
           ~renderer_revision:revision
           ~monotonic_now_ns
       with
       | Result.Ok () -> output ()
       | Result.Error error -> driver_error error)
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let rejection_reason = function
  | 0 -> Result.Ok Driver.Decode_failed
  | 1 -> Result.Ok Driver.Frame_validation_failed
  | 2 -> Result.Ok Driver.Renderer_epoch_mismatch
  | 3 -> Result.Ok Driver.Renderer_revision_mismatch
  | _ -> Result.Error "Unknown presentation rejection reason"
;;

let presentation_rejected handle presentation_id revision reason =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      (match rejection_reason reason with
       | Result.Error error -> output ~status:Recoverable_error ~error_code:13 ~error ()
       | Result.Ok reason ->
         (match
            Driver.presentation_rejected
              driver
              ~presentation_id
              ~renderer_revision:revision
              ~reason
          with
          | Result.Ok () -> output ()
          | Result.Error error -> driver_error error))
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let destroy handle =
  match Hashtbl.find_opt runtimes handle with
  | None -> ()
  | Some driver ->
    Driver.shutdown driver;
    Hashtbl.remove runtimes handle
;;

module For_testing = struct
  let runtime_count () = Hashtbl.length runtimes
end

let callback_create config =
  let result = create (Bytes.of_string config) in
  status_code result.status, result.handle, result.error
;;

let callback_pump handle monotonic_now_ns input =
  let result = pump handle monotonic_now_ns (Bytes.of_string input) in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , result.presentation_id
  , result.revision
  , result.error_code
  , result.error )
;;

let callback_presentation_succeeded handle presentation_id revision monotonic_now_ns =
  let result = presentation_succeeded handle presentation_id revision monotonic_now_ns in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , result.presentation_id
  , result.revision
  , result.error_code
  , result.error )
;;

let callback_presentation_rejected handle presentation_id revision reason =
  let result = presentation_rejected handle presentation_id revision reason in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , result.presentation_id
  , result.revision
  , result.error_code
  , result.error )
;;

let () =
  Callback.register "bonsai_flutter.create" callback_create;
  Callback.register "bonsai_flutter.pump" callback_pump;
  Callback.register
    "bonsai_flutter.presentation_succeeded"
    callback_presentation_succeeded;
  Callback.register "bonsai_flutter.presentation_rejected" callback_presentation_rejected;
  Callback.register "bonsai_flutter.destroy" destroy
;;
