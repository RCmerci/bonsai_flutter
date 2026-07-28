let () =
  Native_backend.embed ~name:"counter" Counter.app;
  Native_backend.embed ~name:"todo" Todo.app;
  Native_backend.embed ~name:"gallery" (App.create Gallery.component);
  Native_backend.embed ~name:"text_input" (App.create Text_input_example.component);
  Native_backend.embed ~name:"host_navigation" (App.create Host_navigation.component);
  Native_backend.embed ~name:"mail" Mail.app
;;
