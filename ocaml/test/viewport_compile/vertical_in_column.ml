module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let viewport =
  Ui.Widget.Scroll_view.vertical
    ~on_scroll:handler
    [ Ui.Widget.Sliver.varied_extent
        ~total_count:1
        ~first_index:0
        ~default_item_extent:48.
        ~extent_overrides:[]
        ~items:
          [ Ui.Widget.Keyed.create ~key:(Ui.Key.string "row") (Ui.Widget.text "Row") ]
        ~on_visible_range:handler
        ()
    ]
    ()
;;

let _ = Ui.Widget.column [ Ui.Widget.text "Search"; viewport ]
