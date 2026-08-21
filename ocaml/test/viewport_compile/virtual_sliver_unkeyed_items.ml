module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let _ =
  Ui.Widget.Sliver.fixed_extent
    ~total_count:1
    ~first_index:0
    ~item_extent:48.
    ~items:[ Ui.Widget.text "Unkeyed" ]
    ~on_visible_range:handler
    ()
;;
