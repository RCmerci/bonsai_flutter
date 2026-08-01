let trace message = Printf.eprintf "[Bonsai Mail][ocaml]%s\n%!" message

let embed () =
  Native_backend.embed ~name:"mail" Mail.app;
  Trace.trace (fun () ->
    let debug_app = App.create ~name:"Bonsai Mail" ~trace Mail.component in
    Native_backend.embed ~name:"mail-debug" debug_app)
;;
