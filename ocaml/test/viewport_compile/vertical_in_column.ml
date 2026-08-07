module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let viewport =
  Ui.Native_widget.Sparse_extent_list.vertical
    ~total_count:1
    ~first_index:0
    ~default_item_extent:48.
    ~extent_overrides:[]
    ~items:[ Ui.Widget.text "Row" ]
    ~on_visible_range:handler
    ()
;;

let _ = Ui.Widget.column [ Ui.Widget.text "Search"; viewport ]
