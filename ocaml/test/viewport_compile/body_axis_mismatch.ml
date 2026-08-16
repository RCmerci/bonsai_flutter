module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let viewport =
  Ui.Widget.Scroll_view.horizontal ~on_scroll:handler [ Ui.Widget.Sliver.list [] ] ()
;;

let _ = Ui.Widget.Body.Vertical.create [ Ui.Widget.Body.Vertical.fill viewport ]
