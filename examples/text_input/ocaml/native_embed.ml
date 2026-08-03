let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "text_input")
    (App.create Text_input_example.component)
;;
