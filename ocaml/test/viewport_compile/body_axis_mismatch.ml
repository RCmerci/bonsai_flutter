module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let viewport = Ui.Widget.List_view.horizontal ~on_scroll:handler [] ()
let _ = Ui.Widget.Body.Vertical.create [ Ui.Widget.Body.Vertical.fill viewport ]
