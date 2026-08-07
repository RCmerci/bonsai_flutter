module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let text value = Ui.Widget.text value

let widgets =
  [ Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(text "Title") ())
      ~body:(Ui.Widget.Body.static (text "Body"))
      ()
  ; Ui.Material.elevated_button ~on_press:handler ~child:(text "Elevated") ()
  ; Ui.Material.text_button ~on_press:handler ~child:(text "Text") ()
  ; Ui.Material.icon_button ~on_press:handler ~icon:(text "Icon") ()
  ; Ui.Material.switch ~value:true ~on_changed:handler ()
  ; Ui.Material.list_tile
      ~selected:true
      ~on_press:handler
      ~title:(text "Item")
      ~subtitle:(text "Subtitle")
      ()
  ; Ui.Material.divider ~thickness:2. ()
  ; Ui.Material.card ~elevation:4. (text "Card")
  ; Ui.Material.dialog (text "Dialog")
  ; Ui.Material.circular_progress_indicator ~value:0.5 ()
  ; Ui.Cupertino.button handler ~child:(text "Cupertino") ()
  ; Ui.Cupertino.switch ~value:true ~on_changed:handler ()
  ]
;;

let expected =
  [ "Material_scaffold"
  ; "Material_elevated_button"
  ; "Material_text_button"
  ; "Material_icon_button"
  ; "Material_switch"
  ; "Material_list_tile"
  ; "Material_divider"
  ; "Material_card"
  ; "Material_dialog"
  ; "Material_circular_progress_indicator"
  ; "Cupertino_button"
  ; "Cupertino_switch"
  ]
;;

let () =
  let actual = List.map Ui.Widget.For_testing.kind_name widgets in
  if actual <> expected
  then failwith "Material constructors produced incorrect logical kinds"
;;
