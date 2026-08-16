module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let row = Ui.Widget.text "Row"

let vertical =
  Ui.Widget.Scroll_view.vertical ~on_scroll:handler [ Ui.Widget.Sliver.list [ row ] ] ()
  |> Ui.Widget.Viewport.Vertical.padding ~insets:(Ui.Layout.Edge_insets.all 8.)
  |> Ui.Widget.Viewport.Vertical.with_test_id (Ui.Test_id.string "feed")
  |> Ui.Widget.Viewport.Vertical.semantics
       ~properties:(Ui.Semantics.create ~label:"Feed" ())
  |> Ui.Widget.Viewport.Vertical.safe_area ~minimum:(Ui.Layout.Edge_insets.all 4.)
  |> Ui.Widget.Viewport.Vertical.theme ~data:(Ui.Theme.material ())
;;

let horizontal = Ui.Widget.Scroll_view.horizontal ~on_scroll:handler [ Ui.Widget.Sliver.list [ row ] ] ()

let (_ : Ui.Widget.Body.t) =
  Ui.Widget.Body.Vertical.create
    [ Ui.Widget.Body.Vertical.fixed (Ui.Widget.text "Search")
    ; Ui.Widget.Body.Vertical.fill ~flex:2 vertical
    ]
;;

let (_ : Ui.Widget.t) = Ui.Widget.Viewport.Horizontal.with_width ~width:240. horizontal

let (_ : Ui.Widget.Body.t) =
  Ui.Widget.Body.Horizontal.create
    [ Ui.Widget.Body.Horizontal.fixed (Ui.Widget.text "Leading")
    ; Ui.Widget.Body.Horizontal.fill horizontal
    ]
;;

let (_ : Ui.Widget.Body.t) = Ui.Widget.Body.static (Ui.Widget.text "Static body")
