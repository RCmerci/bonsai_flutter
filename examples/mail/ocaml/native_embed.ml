module ID = Bonsai_flutter_spec.Id

let trace message = Printf.eprintf "[Bonsai Mail][ocaml]%s\n%!" message

let embed () =
  Native_backend.embed ~name:(ID.Application.Entrypoint_name.of_string "mail") Mail.app;
  Trace.trace (fun () ->
    let debug_app = App.create ~name:"Bonsai Mail" ~trace Mail.component in
    Native_backend.embed
      ~name:(ID.Application.Entrypoint_name.of_string "mail-debug")
      debug_app)
;;
