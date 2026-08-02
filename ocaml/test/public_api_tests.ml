module ID = Bonsai_flutter_spec.Id
module Ui = Bonsai_flutter

let require condition message = if not condition then failwith message

let component context _graph =
  let environment = Ui.App.Context.environment context in
  Bonsai.Cont.map environment ~f:(fun environment ->
    Ui.Widget.text
      (Printf.sprintf
         "%.0fx%.0f"
         environment.Ui.Environment.viewport_width
         environment.viewport_height))
;;

let worker_service =
  Ui.Worker.Service.create
    ~push_topic_count:1
    ~init:(fun ~emit:_ () -> Ok ())
    ~handle_request:(fun () ~cancelled:_ ~emit:_ request -> Ok request, `Idle)
    ~step:(fun () ~cancelled:_ ~emit:_ -> `Idle)
    ~cancel:(fun () ~request_id:_ -> ())
    ~shutdown:(fun () -> ())
;;

let worker_component client _context _graph =
  ignore (Ui.Worker.runtime_epoch client);
  ignore (Ui.Worker.worker_generation client);
  ignore (Ui.Worker.send client "compile-surface");
  Ui.Worker.on_event client (fun _ -> Ui.Effect.return ());
  Bonsai.Cont.return (Ui.Widget.text "worker public API")
;;

let () =
  let (_ : Ui.Host_effect.native_menu_item) =
    { item_id = ID.Host.Native_menu_item_id.of_string "copy"
    ; label = "Copy"
    ; enabled = true
    }
  in
  let (_ : Ui.Host_effect.haptic_kind) = Ui.Host_effect.Haptic_selection in
  let app = Ui.App.create ~name:"public-api-test" component in
  let worker_app =
    Ui.App.create_with_worker
      ~name:"public-worker-api-test"
      ~decode_config:(fun payload ->
        if Bytes.length payload = 0 then Ok () else Error "unexpected payload")
      ~service:worker_service
      worker_component
  in
  Ui.Entrypoint.For_testing.clear ();
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-api-test")
    app;
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-worker-api-test")
    worker_app;
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-api-test")))
    "registered public App was not discoverable";
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-worker-api-test")))
    "registered public worker App was not discoverable";
  ignore (Ui.Effect.return ());
  ignore Ui.Cupertino.button
;;
