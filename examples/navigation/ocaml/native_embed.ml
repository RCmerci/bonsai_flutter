module Ui = Bonsai_flutter_ui

let application_theme =
  let color_scheme =
    Ui.Theme.Color_scheme.from_seed
      ~color:(Ui.Style.Color.rgb ~red:63 ~green:81 ~blue:181)
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
  Bonsai.Cont.map (Navigation.component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_flutter_spec.Id.Application.Entrypoint_name.of_string "navigation")
    (App.create ~name:"Navigation" application_component)
;;
