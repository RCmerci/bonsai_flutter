module Ui = Bonsai_flutter_ui

let application_theme =
  let color_scheme =
    Ui.Theme.Color_scheme.from_seed
      ~color:(Ui.Style.Color.rgb ~red:198 ~green:40 ~blue:40)
      ()
  in
  let data brightness = Ui.Theme.material ~brightness ~color_scheme () in
  Ui.Theme.application
    ~mode:Ui.Theme.System
    ~light:(data Ui.Style.Brightness.Light)
    ~dark:(data Ui.Style.Brightness.Dark)
    ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (Host_effects.component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "host_effects")
    (App.create ~name:"Host Effects" application_component)
;;
