let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "host_navigation")
    (App.create Host_navigation.component)
;;
