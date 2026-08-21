module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let _ =
  Ui.Widget.Sliver.varied_extent
    ~total_count:1
    ~first_index:0
    ~default_item_extent:48.
    ~extent_overrides:[]
    ~items:[ Ui.Widget.text ~key:(Ui.Key.string "direct") "Direct key" ]
    ~on_visible_range:handler
    ()
;;
