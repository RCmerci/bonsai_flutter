let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "host_effects")
    (App.create Host_effects.component)
;;
