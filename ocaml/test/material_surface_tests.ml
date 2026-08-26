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

let segmented_segments =
  [ Ui.Material.Segmented_button.segment
      ~id:(-10L)
      ~icon:(text "List icon")
      ~label:(text "List")
      ~tooltip:"List view"
      ()
  ; Ui.Material.Segmented_button.segment ~id:20L ~enabled:false ~label:(text "Grid") ()
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
  ; Ui.Material.Segmented_button.create
      ~direction:Ui.Layout.Axis.Vertical
      ~multi_selection_enabled:true
      ~empty_selection_allowed:true
      ~expanded_insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:8. ())
      ~selected_icon:(text "Selected")
      ~selected_ids:[ 20L; -10L ]
      ~on_selection_changed:handler
      segmented_segments
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
  ; Ui.Material.linear_progress_indicator ~value:0.5 ()
  ; Ui.Material.linear_progress_indicator ()
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
  ; "Material_segmented_button"
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
  ; "Material_linear_progress_indicator"
  ; "Material_linear_progress_indicator"
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

let segmented
      ?(segments = segmented_segments)
      ?(selected_ids = [ -10L ])
      ?(multi_selection_enabled = false)
      ?(empty_selection_allowed = false)
      ?(show_selected_icon = true)
      ?selected_icon
      ()
  =
  Ui.Material.Segmented_button.create
    ~multi_selection_enabled
    ~empty_selection_allowed
    ~show_selected_icon
    ?selected_icon
    ~selected_ids
    ~on_selection_changed:handler
    segments
    ()
;;

let test_segmented_button_validation () =
  expect_invalid_arg "empty segmented button" (fun () -> segmented ~segments:[] ());
  expect_invalid_arg "segment without icon or label" (fun () ->
    segmented ~segments:[ Ui.Material.Segmented_button.segment ~id:1L () ] ());
  expect_invalid_arg "duplicate segment IDs" (fun () ->
    segmented
      ~segments:
        [ Ui.Material.Segmented_button.segment ~id:1L ~label:(text "A") ()
        ; Ui.Material.Segmented_button.segment ~id:1L ~label:(text "B") ()
        ]
      ~selected_ids:[ 1L ]
      ());
  expect_invalid_arg "duplicate selected IDs" (fun () ->
    segmented ~selected_ids:[ -10L; -10L ] ());
  expect_invalid_arg "unknown selected ID" (fun () -> segmented ~selected_ids:[ 99L ] ());
  expect_invalid_arg "multiple selections in single mode" (fun () ->
    segmented ~selected_ids:[ -10L; 20L ] ());
  expect_invalid_arg "empty selection when forbidden" (fun () ->
    segmented ~selected_ids:[] ());
  expect_invalid_arg "selected icon while hidden" (fun () ->
    segmented ~show_selected_icon:false ~selected_icon:(text "Selected") ());
  ignore
    (segmented
       ~multi_selection_enabled:true
       ~empty_selection_allowed:true
       ~selected_ids:[]
       ());
  ignore (segmented ~show_selected_icon:false ())
;;

let test_segmented_button_canonical_identity () =
  let first = segmented ~multi_selection_enabled:true ~selected_ids:[ 20L; -10L ] () in
  let same = segmented ~multi_selection_enabled:true ~selected_ids:[ -10L; 20L ] () in
  let changed = segmented ~multi_selection_enabled:true ~selected_ids:[ -10L ] () in
  expect
    (Ui.Widget.Private.node_equal_widgets first same)
    "segmented selection was not canonicalized as a set";
  expect
    (not (Ui.Widget.Private.node_equal_widgets first changed))
    "segmented controlled selection was omitted from logical equality"
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

let test_linear_progress_validation () =
  List.iter
    (fun value -> ignore (Ui.Material.linear_progress_indicator ~value ()))
    [ 0.; 1. ];
  List.iter
    (fun value ->
       expect_invalid_arg "invalid linear progress value" (fun () ->
         Ui.Material.linear_progress_indicator ~value ()))
    [ -0.01; 1.01; Float.nan; Float.infinity; Float.neg_infinity ]
;;

let test_linear_progress_identity_includes_kind_and_value () =
  let fingerprint widget =
    let (Ui.Widget.Private.Av view) = Ui.Widget.Private.view widget in
    view.fingerprint
  in
  let indeterminate = Ui.Material.linear_progress_indicator () in
  let determinate = Ui.Material.linear_progress_indicator ~value:0.5 () in
  let circular = Ui.Material.circular_progress_indicator ~value:0.5 () in
  expect
    (not (Ui.Widget.Private.node_equal_widgets indeterminate determinate))
    "linear progress value was omitted from logical equality";
  expect
    (not (Int64.equal (fingerprint indeterminate) (fingerprint determinate)))
    "linear progress value was omitted from its fingerprint";
  expect
    (not (Ui.Widget.Private.node_equal_widgets determinate circular))
    "linear and circular progress shared logical identity";
  expect
    (not (Int64.equal (fingerprint determinate) (fingerprint circular)))
    "linear and circular progress shared a fingerprint"
;;

let () =
  test_constructor_kinds ();
  test_navigation_validation ();
  test_radio_validation ();
  test_segmented_button_validation ();
  test_segmented_button_canonical_identity ();
  test_slider_validation ();
  test_fingerprints_include_controlled_values ();
  test_linear_progress_validation ();
  test_linear_progress_identity_includes_kind_and_value ()
;;
