let scaffold = Widget.Private.material_scaffold
let app_bar = Widget.Private.material_app_bar

let elevated_button ?key ?enabled ?autofocus ~on_press ~child () =
  Widget.Private.material_button
    ?key
    ?enabled
    ?autofocus
    ~variant:Widget.Private.Elevated
    ~on_press
    ~child
    ()
;;

let text_button ?key ?enabled ?autofocus ~on_press ~child () =
  Widget.Private.material_button
    ?key
    ?enabled
    ?autofocus
    ~variant:Widget.Private.Text_button
    ~on_press
    ~child
    ()
;;

let icon_button ?key ?enabled ?autofocus ~on_press ~icon () =
  Widget.Private.material_button
    ?key
    ?enabled
    ?autofocus
    ~variant:Widget.Private.Icon_button
    ~on_press
    ~child:icon
    ()
;;

let checkbox ?key ?enabled ~value ~on_changed () =
  Widget.Private.material_checkbox ?key ?enabled ~value ~on_changed ()
;;

let switch = Widget.Private.material_switch
let text_field = Widget.text_input
let list_tile = Widget.Private.material_list_tile
let divider = Widget.Private.material_divider
let card = Widget.Private.material_card
let dialog = Widget.material_dialog
let circular_progress_indicator = Widget.Private.material_progress
