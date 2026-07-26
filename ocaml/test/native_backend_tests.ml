module Protocol = Bonsai_flutter_protocol
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let counter handlers graph =
  let count, increment = Bonsai.state' ~equal:Int.equal 0 graph in
  let increment_handler =
    Bonsai.map increment ~f:(fun increment ->
      Driver.Handler.create handlers ~name:"increment" (function
        | Ui.Event.Payload.Unit -> increment (fun value -> value + 1)
        | _ -> increment Fun.id))
  in
  Bonsai.map2 count increment_handler ~f:(fun count increment_handler ->
    Ui.Widget.column
      [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
      ; Ui.Widget.button
          ~on_press:increment_handler
          ~child:(Ui.Widget.text "Increment")
          ()
      ])
;;

let () =
  Entrypoint.For_testing.clear ();
  Entrypoint.register ~name:"counter" (App.create counter);
  let created = Native_backend.create (Bytes.of_string "counter") in
  require (created.status = Native_backend.Ok) "registered entrypoint did not create";
  require (Int64.compare created.handle 0L > 0) "native handle must be positive";
  let initial = Native_backend.step created.handle Bytes.empty in
  require (initial.status = Native_backend.Ok) "initial native step failed";
  require (Bytes.length initial.bytes > 0) "initial native step returned no frame";
  require (initial.revision = 1L) "initial native revision must be one";
  (match Protocol.Binary_codec.decode initial.bytes with
   | Ok { kind = Full_snapshot; _ } -> ()
   | Ok _ -> fail "initial native frame was not a full snapshot"
   | Error error -> fail "initial native frame did not decode: %s" error.message);
  let presented = Native_backend.frame_presented created.handle initial.revision in
  require (presented.status = Native_backend.Ok) "frame presentation failed";
  Native_backend.destroy created.handle;
  Native_backend.destroy created.handle;
  let after_destroy = Native_backend.step created.handle Bytes.empty in
  require
    (after_destroy.status = Native_backend.Fatal_error)
    "destroyed native handle accepted a step";
  require
    (String.length after_destroy.error > 0)
    "destroyed native handle returned no diagnostic";
  require (after_destroy.error_code = 9) "destroyed handle error was not structured";
  for _iteration = 1 to 100 do
    let runtime = Native_backend.create (Bytes.of_string "counter") in
    require (runtime.status = Native_backend.Ok) "soak runtime did not create";
    ignore (Native_backend.step runtime.handle Bytes.empty);
    Native_backend.destroy runtime.handle
  done;
  require
    (Native_backend.For_testing.runtime_count () = 0)
    "runtime destroy retained native backend handles";
  let missing = Native_backend.create (Bytes.of_string "missing") in
  require (missing.status = Native_backend.Fatal_error) "unknown entrypoint was accepted"
;;
