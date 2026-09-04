module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let text value = Ui.Widget.text value
let expect condition message = if not condition then failwith message

let text_value text =
  let offset = Ui.Text_editing.Utf16.length text in
  let selection =
    Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text ~selection ()
;;

let material_text_field ?(read_only = false) ?(autofocus = false) () =
  Ui.Material.text_field
    ~read_only
    ~autofocus
    ~session_id:(Bonsai_flutter_spec.Id.Text_input.Session_id.of_int64 9L)
    ~document_revision:(Bonsai_flutter_spec.Id.Text_input.Document_revision.of_int64 3L)
    ~accepted_local_revision:
      (Bonsai_flutter_spec.Id.Text_input.Local_revision.of_int64 2L)
    ~update_mode:Ui.Text_editing.Ack
    ~value:(text_value "draft")
    ~on_edit:handler
    ~on_submit:handler
    ~on_focus_changed:handler
    ()
;;

let expressive_widgets =
  let menu_entries =
    [ Ui.Material.Menu.entry ~id:1L ~label:"Open" ()
    ; Ui.Material.Menu.divider
    ; Ui.Material.Menu.toggleable ~id:2L ~label:"Pinned" ~checked:true ()
    ]
  in
  [ Ui.Material.Fab_menu.create
      ~expand_icon:(text "Add")
      ~collapse_icon:(text "Close")
      ~on_select:handler
      [ Ui.Material.Fab_menu.item ~id:1L ~icon:(text "Edit") ~label:"Edit" () ]
      ()
  ; Ui.Material.Button_group.create
      ~selection:(Ui.Material.Button_group.Single (Some 1L))
      ~on_selection_changed:handler
      [ Ui.Material.Button_group.action ~id:1L ~label:"One" ()
      ; Ui.Material.Button_group.action ~id:2L ~label:"Two" ()
      ]
      ()
  ; Ui.Material.Toggle_button.create
      ~checked:true
      ~on_changed:handler
      ~icon:(text "Favorite")
      ~checked_icon:(text "Favorited")
      ~label:(text "Favorite")
      ()
  ; Ui.Material.Split_button.create
      ~label:"Save"
      ~on_press:handler
      ~on_select:handler
      ~menu:menu_entries
      ()
  ; Ui.Material.Dropdown_menu.create
      ~selection:(Ui.Material.Dropdown_menu.Single (Some 1L))
      ~on_selection_changed:handler
      (Ui.Material.Dropdown_menu.Items
         [ Ui.Material.Dropdown_menu.item ~id:1L ~label:"One" () ])
      ()
  ; Ui.Material.Date_picker.calendar
      ~selected:(Ui.Material.Date.create ~year:2026 ~month:9 ~day:3)
      ~first:(Ui.Material.Date.create ~year:2020 ~month:1 ~day:1)
      ~last:(Ui.Material.Date.create ~year:2030 ~month:12 ~day:31)
      ~on_select:handler
      ()
  ; Ui.Material.Time_picker.dial
      ~value:(Ui.Material.Time.create ~hour:9 ~minute:30)
      ~on_changed:handler
      ()
  ; Ui.Material.Carousel.create
      ~on_select:handler
      ~on_layout_changed:handler
      [ Ui.Material.Carousel.item ~id:1L (text "Card one")
      ; Ui.Material.Carousel.item ~id:2L (text "Card two")
      ]
      ()
  ; Ui.Material.Card_list.finite
      ~on_select:handler
      [ Ui.Material.Card_list.item ~id:1L (text "List one")
      ; Ui.Material.Card_list.item ~id:2L (text "List two")
      ]
      ()
  ; Ui.Material.Selection.create
      ~item_ids:[ 1L ]
      ~selected_ids:[ 1L ]
      ~on_selection_changed:handler
      (text "Selectable content")
  ; Ui.Material.Dismissible_list.column
      ~request_token:1L
      ~request_state:Ui.Material.Dismissible_list.Ready
      ~on_dismiss_request:handler
      [ Ui.Material.Dismissible_list.item ~id:1L (text "Dismiss one") ]
      ()
  ; Ui.Material.Dismissible_list.horizontal
      ~request_token:2L
      ~request_state:Ui.Material.Dismissible_list.Pending
      ~on_dismiss_request:handler
      [ Ui.Material.Dismissible_list.item ~id:1L (text "Dismiss two") ]
      ()
  ; Ui.Material.Expandable_list.finite
      ~expanded_ids:[ 1L ]
      ~on_expansion_changed:handler
      [ Ui.Material.Expandable_list.item
          ~id:1L
          ~header:"Details"
          ~body:(text "Expanded body")
          ()
      ]
      ()
  ; Ui.Material.Bottom_sheet.surface (text "Bottom sheet")
  ; Ui.Material.Side_sheet.surface ~title:(text "Side sheet") ~body:(text "Body") ()
  ; Ui.Material.App_bar.bottom ~actions:[ text "Action" ] ()
  ; Ui.Material.Tabs.create
      ~selected_id:1L
      ~on_select:handler
      [ Ui.Material.Tabs.tab ~id:1L ~label:"Overview" ()
      ; Ui.Material.Tabs.tab ~id:2L ~label:"Activity" ()
      ]
      ()
  ; Ui.Material.Navigation_rail.create
      ~expanded:false
      ~selected_id:1L
      ~on_select:handler
      ~on_expanded_changed:handler
      [ Ui.Material.Navigation_rail.section
          [ Ui.Material.Navigation_rail.destination
              ~id:1L
              ~icon:(text "Home")
              ~label:"Home"
              ()
          ]
      ]
      ()
  ; Ui.Material.Navigation_drawer.create
      ~headline:"Mail"
      ~selected_id:1L
      ~on_select:handler
      [ Ui.Material.Navigation_drawer.destination
          ~id:1L
          ~icon:(text "Inbox")
          ~label:"Inbox"
          ()
      ]
      ()
  ; Ui.Material.Toolbar.create
      ~expanded:true
      ~active_action_id:(Some 1L)
      ~on_action:handler
      ~on_expanded_changed:handler
      ~on_active_action_changed:handler
      [ Ui.Material.Toolbar.action ~id:1L ~icon:Ui.Material.Toolbar.Edit ~label:"Edit" ()
      ]
      ()
  ; Ui.Material.Menu.create
      ~on_select:handler
      ~entries:menu_entries
      ~anchor:(text "Menu")
      ()
  ; Ui.Material.badge ~count:3 (text "Notifications")
  ; Ui.Material.loading_indicator ()
  ; Ui.Material.Refresh_indicator.create
      ~request_token:3L
      ~request_state:Ui.Material.Refresh_indicator.Ready
      ~on_refresh_request:handler
      (text "Refresh body")
  ; Ui.Material.Search_anchor.create
      ~session_id:(Bonsai_flutter_spec.Id.Text_input.Session_id.of_int64 1L)
      ~document_revision:(Bonsai_flutter_spec.Id.Text_input.Document_revision.of_int64 1L)
      ~accepted_local_revision:
        (Bonsai_flutter_spec.Id.Text_input.Local_revision.of_int64 0L)
      ~update_mode:Ui.Text_editing.Force_replace
      ~value:(text_value "bon")
      ~on_edit:handler
      ~on_submit:handler
      ~on_focus_changed:handler
      ~on_select:handler
      [ Ui.Material.Search_anchor.suggestion ~id:1L ~label:"Bonsai" () ]
      ()
  ]
;;

let expect_invalid_arg label f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith (label ^ " did not reject invalid input")
;;

let destinations =
  [ Ui.Material.Navigation_destination.create
      ~icon:(text "Home icon")
      ~selected_icon:(text "Selected home icon")
      ~badge_count:3
      ~semantic_label:"Home destination"
      ~label:"Home"
      ()
  ; Ui.Material.Navigation_destination.create
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
      ~label:"List"
      ()
  ; Ui.Material.Segmented_button.segment ~id:20L ~label:"Grid" ()
  ]
;;

let text_value text =
  let offset = Ui.Text_editing.Utf16.length text in
  let selection =
    Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text ~selection ()
;;

let data_columns =
  [ Ui.Material.Data_table.column ~id:10L ~sortable:true ~label:(text "Name") ()
  ; Ui.Material.Data_table.column ~id:20L ~numeric:true ~label:(text "Score") ()
  ]
;;

let data_rows =
  [ Ui.Material.Data_table.row
      ~id:100L
      ~selected:true
      [ Ui.Material.Data_table.cell ~activatable:true (text "Ada")
      ; Ui.Material.Data_table.cell (text "42")
      ]
  ]
;;

let steps =
  [ Ui.Material.Stepper.step
      ~id:1L
      ~title:(text "Account")
      ~content:(text "Account form")
      ()
  ; Ui.Material.Stepper.step
      ~id:2L
      ~state:Ui.Material.Stepper.Complete
      ~title:(text "Review")
      ~content:(text "Review form")
      ()
  ]
;;

let panels =
  [ Ui.Material.Expansion_panel_list.panel
      ~id:11L
      ~header:(text "First")
      ~body:(text "First body")
      ()
  ; Ui.Material.Expansion_panel_list.panel
      ~id:22L
      ~header:(text "Second")
      ~body:(text "Second body")
      ()
  ]
;;

let widgets =
  [ Ui.Material.scaffold
      ~app_bar:(Ui.Material.App_bar.top ~title:(text "Title") ())
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
      ~label:"Extended"
      ()
  ; Ui.Material.navigation_bar ~selected_index:0 ~on_select:handler destinations ()
  ; Ui.Material.Dialog.alert
      ~icon:(text "Warning")
      ~title:"Delete item?"
      ~content:(text "This cannot be undone")
      ~actions:[ text "Cancel"; text "Delete" ]
      ()
  ; Ui.Material.search_bar
      ~session_id:(Bonsai_flutter_spec.Id.Text_input.Session_id.of_int64 7L)
      ~document_revision:(Bonsai_flutter_spec.Id.Text_input.Document_revision.of_int64 2L)
      ~accepted_local_revision:
        (Bonsai_flutter_spec.Id.Text_input.Local_revision.of_int64 1L)
      ~update_mode:Ui.Text_editing.Correction
      ~value:(text_value "query")
      ~on_edit:handler
      ~on_submit:handler
      ~on_focus_changed:handler
      ~leading:(text "Search")
      ~trailing:[ text "Clear" ]
      ~hint_text:"Search items"
      ~on_tap:handler
      ()
  ; material_text_field ~read_only:true ~autofocus:true ()
  ; Ui.Material.Tooltip.rich
      ~title:"Details"
      ~message:"More information"
      ~actions:[ text "Dismiss" ]
      (text "Info")
  ; Ui.Material.Data_table.create
      ~sort_column_id:10L
      ~selected_row_ids:[ 100L ]
      ~on_sort:handler
      ~on_row_selected:handler
      ~on_select_all:handler
      ~on_cell_activate:handler
      ~columns:data_columns
      ~rows:data_rows
      ()
  ; Ui.Material.Stepper.create
      ~orientation:Ui.Material.Stepper.Horizontal
      ~current_step_id:1L
      ~on_step_selected:handler
      ~on_continue:handler
      ~on_cancel:handler
      steps
      ()
  ; Ui.Material.Expansion_panel_list.create
      ~policy:Ui.Material.Expansion_panel_list.Multiple
      ~expanded_ids:[ 11L ]
      ~on_expansion_changed:handler
      panels
      ()
  ; Ui.Material.Dialog.simple
      ~title:(text "Choose")
      ~on_select:handler
      [ Ui.Material.Dialog.option ~id:5L ~label:(text "Five") () ]
      ()
  ; Ui.Material.Dialog.fullscreen (text "Fullscreen")
  ; Ui.Material.Radio_group.create
      ~selected_id:(Some 10L)
      ~on_select:handler
      radio_options
      ()
  ; Ui.Material.Segmented_button.create
      ~multi_selection_enabled:true
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
  ; Ui.Material.Chip.assist
      ~presentation:Ui.Material.Chip.Elevated
      ~on_press:handler
      ~label:"Assist"
      ()
  ; Ui.Material.Chip.filter
      ~presentation:Ui.Material.Chip.Elevated
      ~selected:true
      ~on_press:handler
      ~label:"Filter"
      ()
  ; Ui.Material.Chip.suggestion
      ~presentation:Ui.Material.Chip.Elevated
      ~selected:false
      ~on_press:handler
      ~label:"Suggestion"
      ()
  ; Ui.Material.Chip.input
      ~selected:true
      ~on_press:handler
      ~on_delete:handler
      ~label:"Input"
      ()
  ; Ui.Material.switch ~value:true ~on_changed:handler ()
  ; Ui.Material.list_tile
      ~selected:true
      ~on_press:handler
      ~headline:"Item"
      ~supporting_text:"Subtitle"
      ~overline:"Category"
      ()
  ; Ui.Material.divider
      ~orientation:Ui.Material.Vertical
      ~thickness:2.
      ~spacing:16.
      ~indent:4.
      ~end_indent:6.
      ()
  ; Ui.Material.card ~variant:Ui.Material.Outlined ~elevation:4. (text "Card")
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
  ; "Material_expressive"
  ; "Material_search_bar"
  ; "Material_text_field"
  ; "Material_expressive"
  ; "Material_data_table"
  ; "Material_stepper"
  ; "Material_expansion_panel_list"
  ; "Material_simple_dialog"
  ; "Material_fullscreen_dialog"
  ; "Material_radio_group"
  ; "Material_segmented_button"
  ; "Material_slider"
  ; "Material_range_slider"
  ; "Material_action_chip"
  ; "Material_filter_chip"
  ; "Material_choice_chip"
  ; "Material_input_chip"
  ; "Material_switch"
  ; "Material_expressive"
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
  if List.length actual <> List.length expected
  then failwith "Material constructor-kind list lengths differ";
  List.iteri
    (fun index actual ->
       let expected = List.nth expected index in
       if not (String.equal actual expected)
       then
         failwith
           (Printf.sprintf
              "Material constructor kind %d is %s, expected %s"
              index
              actual
              expected))
    actual
;;

let test_navigation_validation () =
  expect_invalid_arg "empty destination label" (fun () ->
    Ui.Material.Navigation_destination.create ~icon:(text "icon") ~label:"  " ());
  expect_invalid_arg "negative navigation badge" (fun () ->
    Ui.Material.Navigation_destination.create
      ~icon:(text "icon")
      ~label:"Home"
      ~badge_count:(-1)
      ());
  expect_invalid_arg "ambiguous navigation badge" (fun () ->
    Ui.Material.Navigation_destination.create
      ~icon:(text "icon")
      ~label:"Home"
      ~badge_count:1
      ~badge_dot:true
      ());
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
      ()
  =
  Ui.Material.Segmented_button.create
    ~multi_selection_enabled
    ~selected_ids
    ~on_selection_changed:handler
    segments
    ()
;;

let test_segmented_button_validation () =
  expect_invalid_arg "empty segmented button" (fun () -> segmented ~segments:[] ());
  expect_invalid_arg "segment without label" (fun () ->
    segmented ~segments:[ Ui.Material.Segmented_button.segment ~id:1L ~label:"" () ] ());
  expect_invalid_arg "duplicate segment IDs" (fun () ->
    segmented
      ~segments:
        [ Ui.Material.Segmented_button.segment ~id:1L ~label:"A" ()
        ; Ui.Material.Segmented_button.segment ~id:1L ~label:"B" ()
        ]
      ~selected_ids:[ 1L ]
      ());
  expect_invalid_arg "duplicate selected IDs" (fun () ->
    segmented ~selected_ids:[ -10L; -10L ] ());
  expect_invalid_arg "unknown selected ID" (fun () -> segmented ~selected_ids:[ 99L ] ());
  expect_invalid_arg "multiple selections in single mode" (fun () ->
    segmented ~selected_ids:[ -10L; 20L ] ());
  expect_invalid_arg "empty selection when forbidden" (fun () ->
    segmented ~selected_ids:[] ())
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

let test_text_field_identity_includes_read_only_and_autofocus () =
  let default = material_text_field () in
  expect
    (not
       (Ui.Widget.Private.node_equal_widgets
          default
          (material_text_field ~read_only:true ())))
    "text field read_only was omitted from logical equality";
  expect
    (not
       (Ui.Widget.Private.node_equal_widgets
          default
          (material_text_field ~autofocus:true ())))
    "text field autofocus was omitted from logical equality"
;;

let test_additional_component_validation () =
  expect_invalid_arg "empty tooltip message" (fun () ->
    Ui.Material.Tooltip.plain ~message:"  " (text "child"));
  expect_invalid_arg "empty table columns" (fun () ->
    Ui.Material.Data_table.create ~columns:[] ~rows:[] ());
  expect_invalid_arg "duplicate table column IDs" (fun () ->
    Ui.Material.Data_table.create
      ~columns:
        [ Ui.Material.Data_table.column ~id:1L ~label:(text "A") ()
        ; Ui.Material.Data_table.column ~id:1L ~label:(text "B") ()
        ]
      ~rows:[]
      ());
  expect_invalid_arg "wrong table row width" (fun () ->
    Ui.Material.Data_table.create
      ~columns:data_columns
      ~rows:
        [ Ui.Material.Data_table.row ~id:1L [ Ui.Material.Data_table.cell (text "A") ] ]
      ());
  expect_invalid_arg "unknown table sort column" (fun () ->
    Ui.Material.Data_table.create
      ~sort_column_id:99L
      ~columns:data_columns
      ~rows:data_rows
      ());
  expect_invalid_arg "duplicate step IDs" (fun () ->
    Ui.Material.Stepper.create
      ~current_step_id:1L
      [ Ui.Material.Stepper.step ~id:1L ~title:(text "A") ~content:(text "A") ()
      ; Ui.Material.Stepper.step ~id:1L ~title:(text "B") ~content:(text "B") ()
      ]
      ());
  expect_invalid_arg "unknown current step" (fun () ->
    Ui.Material.Stepper.create ~current_step_id:99L steps ());
  expect_invalid_arg "multiple expanded panels in single mode" (fun () ->
    Ui.Material.Expansion_panel_list.create
      ~policy:Ui.Material.Expansion_panel_list.Single
      ~expanded_ids:[ 11L; 22L ]
      ~on_expansion_changed:handler
      panels
      ());
  expect_invalid_arg "empty simple dialog" (fun () ->
    Ui.Material.Dialog.simple ~on_select:handler [] ());
  expect_invalid_arg "duplicate simple dialog option IDs" (fun () ->
    Ui.Material.Dialog.simple
      ~on_select:handler
      [ Ui.Material.Dialog.option ~id:1L ~label:(text "A") ()
      ; Ui.Material.Dialog.option ~id:1L ~label:(text "B") ()
      ]
      ());
  expect_invalid_arg "negative divider geometry" (fun () ->
    Ui.Material.divider ~spacing:(-1.) ())
;;

let test_additional_component_identity () =
  let table selected_row_ids =
    Ui.Material.Data_table.create
      ~selected_row_ids
      ~columns:data_columns
      ~rows:data_rows
      ()
  in
  expect
    (not (Ui.Widget.Private.node_equal_widgets (table []) (table [ 100L ])))
    "data table controlled selection was omitted from logical equality";
  let expansion expanded_ids =
    Ui.Material.Expansion_panel_list.create
      ~policy:Ui.Material.Expansion_panel_list.Multiple
      ~expanded_ids
      ~on_expansion_changed:handler
      panels
      ()
  in
  expect
    (Ui.Widget.Private.node_equal_widgets
       (expansion [ 22L; 11L ])
       (expansion [ 11L; 22L ]))
    "expanded panel IDs were not canonicalized";
  expect
    (not
       (Ui.Widget.Private.node_equal_widgets
          (Ui.Material.card ~variant:Ui.Material.Filled (text "card"))
          (Ui.Material.card ~variant:Ui.Material.Outlined (text "card"))))
    "card variant was omitted from logical equality"
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

let test_expressive_catalog_kinds () =
  List.iter
    (fun widget ->
       expect
         (String.equal (Ui.Widget.For_testing.kind_name widget) "Material_expressive")
         "expressive catalog entry did not create the typed expressive node")
    expressive_widgets
;;

let () =
  test_constructor_kinds ();
  test_navigation_validation ();
  test_radio_validation ();
  test_segmented_button_validation ();
  test_segmented_button_canonical_identity ();
  test_slider_validation ();
  test_fingerprints_include_controlled_values ();
  test_text_field_identity_includes_read_only_and_autofocus ();
  test_additional_component_validation ();
  test_additional_component_identity ();
  test_linear_progress_validation ();
  test_linear_progress_identity_includes_kind_and_value ();
  test_expressive_catalog_kinds ()
;;
