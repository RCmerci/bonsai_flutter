module Ui = Bonsai_flutter_ui

let component handlers graph =
  let count, set_count = Bonsai.state' ~equal:Int.equal 0 graph in
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
  Bonsai.map2 count increment ~f:(fun count increment ->
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Counter") ())
      ~body:
        (Ui.Widget.center
           (Ui.Widget.column
              [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
              ; Ui.Material.elevated_button
                  ~on_press:increment
                  ~child:(Ui.Widget.text "Increment")
                  ()
                |> Ui.Widget.with_test_id (Ui.Test_id.string "increment")
              ]))
      ())
;;

let app = App.create ~name:"Counter" component
