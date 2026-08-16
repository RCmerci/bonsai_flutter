module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let viewport =
  Ui.Widget.Scroll_view.vertical ~on_scroll:handler [ Ui.Widget.Sliver.box (Ui.Widget.text "Rows") ] ()
;;

let _ = Ui.Widget.Flex.column [ Ui.Widget.Flex.fixed viewport ]
