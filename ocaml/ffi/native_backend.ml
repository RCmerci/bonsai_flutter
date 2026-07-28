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
  ; revision : int64
  ; next_wakeup_ns : int64
  ; error_code : int
  ; error : string
  }

let no_wakeup = -1L
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
      ?(revision = 0L)
      ?(error_code = 0)
      ?(error = "")
      ()
  =
  { status; bytes; revision; next_wakeup_ns = no_wakeup; error_code; error }
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

let driver_error error =
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
    | Invalid_state _ -> Fatal_error, 5
    | Lifecycle_error _ -> Fatal_error, 11
    | Host_response_error _ -> Fatal_error, 8
    | Shutdown -> Fatal_error, 9
  in
  output ~status ~error_code ~error:(Driver.error_to_string error) ()
;;

let find_runtime handle =
  match Hashtbl.find_opt runtimes handle with
  | Some runtime -> Result.Ok runtime
  | None ->
    Result.Error
      (output ~status:Fatal_error ~error_code:9 ~error:"Unknown native runtime handle" ())
;;

let step handle input =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      let result =
        if Bytes.length input = 0
        then Driver.step driver ()
        else (
          match Protocol.Event_batch_codec.decode input with
          | Result.Error error ->
            Result.Error
              (Driver.Event_error
                 (Bonsai_flutter_runtime.Event_dispatcher.Invalid_event error.message))
          | Result.Ok events -> Driver.step driver ~events ())
      in
      (match result with
       | Result.Error error -> driver_error error
       | Result.Ok None -> output ()
       | Result.Ok (Some frame) -> output ~bytes:frame.bytes ~revision:frame.revision ())
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let frame_presented handle revision =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      (match Driver.frame_presented driver ~revision with
       | Result.Ok () -> output ~revision ()
       | Result.Error error -> driver_error error)
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

let callback_step handle input =
  let result = step handle (Bytes.of_string input) in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , result.revision
  , result.next_wakeup_ns
  , result.error_code
  , result.error )
;;

let callback_frame_presented handle revision =
  let result = frame_presented handle revision in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , result.revision
  , result.next_wakeup_ns
  , result.error_code
  , result.error )
;;

let () =
  Callback.register "bonsai_flutter.create" callback_create;
  Callback.register "bonsai_flutter.step" callback_step;
  Callback.register "bonsai_flutter.frame_presented" callback_frame_presented;
  Callback.register "bonsai_flutter.destroy" destroy
;;
