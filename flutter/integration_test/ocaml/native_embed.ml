module ID = Bonsai_flutter_spec.Id
module Ui = Bonsai_flutter_ui

let entrypoint_name = ID.Application.Entrypoint_name.of_string

let application_theme ~red ~green ~blue =
  let color_scheme =
    Ui.Theme.Color_scheme.from_seed ~color:(Ui.Style.Color.rgb ~red ~green ~blue) ()
  in
  let data brightness = Ui.Theme.material ~brightness ~color_scheme () in
  Ui.Theme.application
    ~mode:Ui.Theme.System
    ~light:(data Ui.Style.Brightness.Light)
    ~dark:(data Ui.Style.Brightness.Dark)
    ()
;;

let application ~name ~theme component =
  App.create ~name (fun handlers graph ->
    Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
      App.View.create ~theme ~body))
;;

let () =
  Native_backend.embed ~name:(entrypoint_name "counter") Counter.app;
  Native_backend.embed ~name:(entrypoint_name "todo") Todo.app;
  Native_backend.embed
    ~name:(entrypoint_name "gallery")
    (application
       ~name:"Bonsai Flutter Gallery"
       ~theme:(application_theme ~red:32 ~green:96 ~blue:160)
       Gallery.component);
  Native_backend.embed
    ~name:(entrypoint_name "text_input")
    (application
       ~name:"Text Input"
       ~theme:(application_theme ~red:94 ~green:53 ~blue:177)
       Text_input_example.component);
  Native_backend.embed
    ~name:(entrypoint_name "host_navigation")
    (application
       ~name:"Host Navigation"
       ~theme:(application_theme ~red:0 ~green:121 ~blue:107)
       Host_navigation.component);
  Native_backend.embed ~name:(entrypoint_name "mail") Mail.app;
  Native_backend.embed ~name:(entrypoint_name "sqlite_worker") Sqlite_worker_example.app;
  Native_backend.embed
    ~name:(entrypoint_name "autonomous_pump")
    (application
       ~name:"Autonomous Pump"
       ~theme:(application_theme ~red:3 ~green:169 ~blue:244)
       Autonomous_pump_fixture.component);
  Native_backend.embed
    ~name:(entrypoint_name "patch_size_profile")
    (application
       ~name:"Patch Size Profile"
       ~theme:(application_theme ~red:3 ~green:169 ~blue:244)
       Autonomous_pump_fixture.patch_size_component)
;;
