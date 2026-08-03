module ID = Bonsai_flutter_spec.Id

let entrypoint_name = ID.Application.Entrypoint_name.of_string

let () =
  Native_backend.embed ~name:(entrypoint_name "counter") Counter.app;
  Native_backend.embed ~name:(entrypoint_name "todo") Todo.app;
  Native_backend.embed ~name:(entrypoint_name "gallery") (App.create Gallery.component);
  Native_backend.embed
    ~name:(entrypoint_name "text_input")
    (App.create Text_input_example.component);
  Native_backend.embed
    ~name:(entrypoint_name "host_navigation")
    (App.create Host_navigation.component);
  Native_backend.embed ~name:(entrypoint_name "mail") Mail.app;
  Native_backend.embed ~name:(entrypoint_name "sqlite_worker") Sqlite_worker_example.app;
  Native_backend.embed
    ~name:(entrypoint_name "autonomous_pump")
    (App.create Autonomous_pump_fixture.component)
;;
