module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let text value = Ui.Widget.text value
let expect condition message = if not condition then failwith message

let expect_invalid_arg label f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith (label ^ " did not reject invalid input")
;;

let destinations =
  [ Ui.Material.Navigation_destination.create
      ~icon:(text "Home icon")
      ~selected_icon:(text "Selected home icon")
      ~label:"Home"
      ()
  ; Ui.Material.Navigation_destination.create
      ~enabled:false
      ~icon:(text "Settings icon")
      ~label:"Settings"
      ()
  ]
;;

let radio_options =
  [ Ui.Material.Radio_group.option ~id:10L ~label:(text "First") ()
  ; Ui.Material.Radio_group.option ~id:20L ~enabled:false ~label:(text "Second") ()
  ]
;;

let widgets =
  [ Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(text "Title") ())
      ~floating_action_button:
        (Ui.Material.Floating_action_button.icon
           ~size:Ui.Material.Floating_action_button.Large
           ~on_press:handler
           ~icon:(text "Add")
           ())
      ~floating_action_button_location:Ui.Material.End_docked
      ~bottom_navigation_bar:
        (Ui.Material.navigation_bar ~selected_index:0 ~on_select:handler destinations ())
      ~bottom_sheet:(text "Persistent sheet")
      ~body:(Ui.Widget.Body.static (text "Body"))
      ()
  ; Ui.Material.filled_button ~on_press:handler ~child:(text "Filled") ()
  ; Ui.Material.filled_tonal_button ~on_press:handler ~child:(text "Tonal") ()
  ; Ui.Material.outlined_button ~on_press:handler ~child:(text "Outlined") ()
  ; Ui.Material.elevated_button ~on_press:handler ~child:(text "Elevated") ()
  ; Ui.Material.text_button ~on_press:handler ~child:(text "Text") ()
  ; Ui.Material.icon_button ~on_press:handler ~icon:(text "Icon") ()
  ; Ui.Material.Floating_action_button.icon
      ~size:Small
      ~on_press:handler
      ~icon:(text "Small")
      ()
  ; Ui.Material.Floating_action_button.icon ~on_press:handler ~icon:(text "Standard") ()
  ; Ui.Material.Floating_action_button.extended
      ~on_press:handler
      ~icon:(text "Extended icon")
      ~label:(text "Extended")
      ()
  ; Ui.Material.navigation_bar ~selected_index:0 ~on_select:handler destinations ()
  ; Ui.Material.alert_dialog
      ~icon:(text "Warning")
      ~title:(text "Delete item?")
      ~content:(text "This cannot be undone")
      ~actions:[ text "Cancel"; text "Delete" ]
      ()
  ; Ui.Material.Radio_group.create
      ~selected_id:(Some 10L)
      ~on_select:handler
      radio_options
      ()
  ; Ui.Material.slider
      ~value:0.25
      ~min:0.
      ~max:1.
      ~divisions:4
      ~label:"Quarter"
      ~on_change:handler
      ~on_change_end:handler
      ()
  ; Ui.Material.range_slider
      ~value:(Ui.Material.Range.create ~start:0.25 ~end_:0.75)
      ~min:0.
      ~max:1.
      ~divisions:4
      ~on_change:handler
      ~on_change_end:handler
      ()
  ; Ui.Material.action_chip ~on_press:handler ~label:(text "Action") ()
  ; Ui.Material.filter_chip ~selected:true ~on_selected:handler ~label:(text "Filter") ()
  ; Ui.Material.choice_chip ~selected:false ~on_selected:handler ~label:(text "Choice") ()
  ; Ui.Material.input_chip
      ~selected:true
      ~on_press:handler
      ~on_selected:handler
      ~on_delete:handler
      ~label:(text "Input")
      ()
  ; Ui.Material.switch ~value:true ~on_changed:handler ()
  ; Ui.Material.list_tile
      ~selected:true
      ~on_press:handler
      ~title:(text "Item")
      ~subtitle:(text "Subtitle")
      ()
  ; Ui.Material.divider ~thickness:2. ()
  ; Ui.Material.card ~elevation:4. (text "Card")
  ; Ui.Material.circular_progress_indicator ~value:0.5 ()
  ; Ui.Cupertino.button handler ~child:(text "Cupertino") ()
  ; Ui.Cupertino.switch ~value:true ~on_changed:handler ()
  ]
;;

let expected =
  [ "Material_scaffold"
  ; "Material_filled_button"
  ; "Material_filled_tonal_button"
  ; "Material_outlined_button"
  ; "Material_elevated_button"
  ; "Material_text_button"
  ; "Material_icon_button"
  ; "Material_floating_action_button"
  ; "Material_floating_action_button"
  ; "Material_floating_action_button"
  ; "Material_navigation_bar"
  ; "Material_alert_dialog"
  ; "Material_radio_group"
  ; "Material_slider"
  ; "Material_range_slider"
  ; "Material_action_chip"
  ; "Material_filter_chip"
  ; "Material_choice_chip"
  ; "Material_input_chip"
  ; "Material_switch"
  ; "Material_list_tile"
  ; "Material_divider"
  ; "Material_card"
  ; "Material_circular_progress_indicator"
  ; "Cupertino_button"
  ; "Cupertino_switch"
  ]
;;

let test_constructor_kinds () =
  let actual = List.map Ui.Widget.For_testing.kind_name widgets in
  expect (actual = expected) "Material constructors produced incorrect logical kinds"
;;

let test_navigation_validation () =
  expect_invalid_arg "empty destination label" (fun () ->
    Ui.Material.Navigation_destination.create ~icon:(text "icon") ~label:"  " ());
  expect_invalid_arg "one navigation destination" (fun () ->
    Ui.Material.navigation_bar
      ~selected_index:0
      ~on_select:handler
      [ List.hd destinations ]
      ());
  expect_invalid_arg "out-of-range selected index" (fun () ->
    Ui.Material.navigation_bar ~selected_index:2 ~on_select:handler destinations ())
;;

let test_radio_validation () =
  expect_invalid_arg "duplicate radio option IDs" (fun () ->
    Ui.Material.Radio_group.create
      ~selected_id:(Some 10L)
      ~on_select:handler
      [ Ui.Material.Radio_group.option ~id:10L ()
      ; Ui.Material.Radio_group.option ~id:10L ()
      ]
      ());
  expect_invalid_arg "missing selected radio option" (fun () ->
    Ui.Material.Radio_group.create
      ~selected_id:(Some 99L)
      ~on_select:handler
      radio_options
      ())
;;

let test_slider_validation () =
  let slider ?(value = 0.5) ?(min = 0.) ?(max = 1.) ?divisions () =
    Ui.Material.slider ~value ~min ~max ?divisions ~on_change_end:handler ()
  in
  expect_invalid_arg "non-finite slider value" (fun () -> slider ~value:nan ());
  expect_invalid_arg "reversed slider domain" (fun () -> slider ~min:2. ~max:1. ());
  expect_invalid_arg "out-of-range slider value" (fun () -> slider ~value:2. ());
  expect_invalid_arg "non-positive slider divisions" (fun () -> slider ~divisions:0 ());
  expect_invalid_arg "reversed range selection" (fun () ->
    Ui.Material.range_slider
      ~value:(Ui.Material.Range.create ~start:0.8 ~end_:0.2)
      ~on_change_end:handler
      ())
;;

let test_fingerprints_include_controlled_values () =
  let first = Ui.Material.slider ~value:0.2 ~on_change_end:handler () in
  let second = Ui.Material.slider ~value:0.8 ~on_change_end:handler () in
  expect
    (not (Ui.Widget.Private.node_equal_widgets first second))
    "slider controlled value was omitted from logical equality"
;;

let () =
  test_constructor_kinds ();
  test_navigation_validation ();
  test_radio_validation ();
  test_slider_validation ();
  test_fingerprints_include_controlled_values ()
;;
