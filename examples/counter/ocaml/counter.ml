module Ui = Bonsai_flutter_ui

let component handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      set_count
      ~f:(fun set_count -> function
      | Ui.Event.Payload.Unit -> set_count (fun count -> count + 1)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.App_bar.top ~title:(Ui.Widget.text "Counter") ())
      ~body:
        (Ui.Widget.Body.static
           (Ui.Widget.center
              (Ui.Widget.column
                 [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
                 ; Ui.Material.elevated_button
                     ~on_press:increment
                     ~child:(Ui.Widget.text "Increment")
                     ()
                   |> Ui.Widget.with_test_id (Ui.Test_id.string "increment")
                 ])))
      ())
;;

let application_theme =
  let color_scheme =
    Ui.Theme.Color_scheme.from_seed
      ~color:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164)
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
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let app = App.create ~name:"Counter" application_component
