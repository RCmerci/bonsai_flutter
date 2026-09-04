(* Temporary compile-checked catalog for the Material 3 Expressive integration. *)

module Ui = Bonsai_flutter
module ID = Bonsai_flutter_spec.Id

let ignore_event = Ui.Event.Handler.create (fun _ -> ())
let icon code_point = Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point ()

let text_value text =
  let offset = Ui.Text_editing.Utf16.length text in
  let selection =
    Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text ~selection ()
;;

let menu =
  [ Ui.Material.Menu.entry ~id:1L ~label:"Open" ()
  ; Ui.Material.Menu.selectable ~id:2L ~label:"Selected" ~selected:true ()
  ; Ui.Material.Menu.toggleable ~id:3L ~label:"Pinned" ~checked:false ()
  ; Ui.Material.Menu.divider
  ; Ui.Material.Menu.group
      ~label:"Export"
      [ Ui.Material.Menu.submenu
          ~id:4L
          ~label:"Format"
          [ Ui.Material.Menu.entry ~id:5L ~label:"PDF" () ]
      ]
  ]
;;

let destinations =
  [ Ui.Material.Navigation_destination.create
      ~icon:(icon 0xe88a)
      ~selected_icon:(icon 0xe88a)
      ~badge_count:3
      ~semantic_label:"Home destination"
      ~label:"Home"
      ()
  ; Ui.Material.Navigation_destination.create
      ~icon:(icon 0xe8b8)
      ~badge_dot:true
      ~label:"Settings"
      ()
  ]
;;

let date = Ui.Material.Date.create ~year:2026 ~month:9 ~day:3
let first_date = Ui.Material.Date.create ~year:2026 ~month:1 ~day:1
let last_date = Ui.Material.Date.create ~year:2026 ~month:12 ~day:31
let time = Ui.Material.Time.create ~hour:14 ~minute:30

let cards =
  [ Ui.Material.Card_list.item ~id:10L (Ui.Widget.text "First card")
  ; Ui.Material.Card_list.item ~id:11L (Ui.Widget.text "Second card")
  ]
;;

let expandable_items =
  [ Ui.Material.Expandable_list.item
      ~id:20L
      ~header:"Details"
      ~body:(Ui.Widget.text "Expanded body")
      ()
  ]
;;

let material_widgets () =
  [ Ui.Material.elevated_button
      ~on_press:ignore_event
      ~child:(Ui.Widget.text "Elevated")
      ()
  ; Ui.Material.filled_button ~on_press:ignore_event ~child:(Ui.Widget.text "Filled") ()
  ; Ui.Material.filled_tonal_button
      ~on_press:ignore_event
      ~child:(Ui.Widget.text "Tonal")
      ()
  ; Ui.Material.outlined_button
      ~on_press:ignore_event
      ~child:(Ui.Widget.text "Outlined")
      ()
  ; Ui.Material.text_button ~on_press:ignore_event ~child:(Ui.Widget.text "Text") ()
  ; Ui.Material.icon_button ~on_press:ignore_event ~icon:(icon 0xe145) ()
  ; Ui.Material.Floating_action_button.icon
      ~size:Ui.Material.Floating_action_button.Large
      ~on_press:ignore_event
      ~icon:(icon 0xe145)
      ()
  ; Ui.Material.Floating_action_button.extended
      ~icon:(icon 0xe145)
      ~on_press:ignore_event
      ~label:"Create"
      ()
  ; Ui.Material.navigation_bar
      ~layout:Ui.Material.Wide
      ~alignment:Ui.Material.Start
      ~label_behavior:Ui.Material.Selected
      ~icon_behavior:Ui.Material.Always
      ~size:Ui.Material.Small
      ~shape:Ui.Material.Round
      ~density:Ui.Material.Compact_density
      ~selected_index:0
      ~on_select:ignore_event
      destinations
      ()
  ; Ui.Material.Radio_group.create
      ~selected_id:(Some 1L)
      ~on_select:ignore_event
      [ Ui.Material.Radio_group.option ~id:1L ~label:(Ui.Widget.text "Radio") () ]
      ()
  ; Ui.Material.Segmented_button.create
      ~selected_ids:[ 1L ]
      ~on_selection_changed:ignore_event
      [ Ui.Material.Segmented_button.segment ~id:1L ~icon:(icon 0xe8ef) ~label:"List" ()
      ; Ui.Material.Segmented_button.segment ~id:2L ~label:"Grid" ()
      ]
      ()
  ; Ui.Material.slider
      ~kind:Ui.Material.Standard
      ~value:0.4
      ~on_change:ignore_event
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.slider
      ~kind:Ui.Material.Centered
      ~value:0.4
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.slider ~kind:Ui.Material.Wavy ~value:0.4 ~on_change_end:ignore_event ()
  ; Ui.Material.slider
      ~kind:Ui.Material.Wavy_centered
      ~value:0.4
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.slider
      ~kind:Ui.Material.Vertical
      ~value:0.4
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.slider
      ~kind:Ui.Material.Vertical_centered
      ~value:0.4
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.range_slider
      ~kind:Ui.Material.Wavy
      ~value:(Ui.Material.Range.create ~start:0.2 ~end_:0.8)
      ~on_change_end:ignore_event
      ()
  ; Ui.Material.Chip.assist ~on_press:ignore_event ~label:"Assist" ()
  ; Ui.Material.Chip.suggestion ~on_press:ignore_event ~label:"Suggestion" ()
  ; Ui.Material.Chip.filter ~selected:true ~on_press:ignore_event ~label:"Filter" ()
  ; Ui.Material.Chip.input
      ~selected:false
      ~on_press:ignore_event
      ~on_delete:ignore_event
      ~label:"Input"
      ()
  ; Ui.Material.checkbox ~value:true ~on_changed:ignore_event ()
  ; Ui.Material.switch ~value:false ~on_changed:ignore_event ()
  ; Ui.Material.search_bar
      ~session_id:(ID.Text_input.Session_id.of_int64 1L)
      ~document_revision:ID.Text_input.Document_revision.zero
      ~accepted_local_revision:ID.Text_input.Local_revision.zero
      ~update_mode:Ui.Text_editing.Ack
      ~value:(text_value "Search")
      ~on_edit:ignore_event
      ~on_submit:ignore_event
      ~on_focus_changed:ignore_event
      ~leading:(icon 0xe8b6)
      ()
  ; Ui.Material.text_field
      ~variant:Ui.Material.Outlined
      ~label:"Message"
      ~supporting_text:"Revisioned text input"
      ~leading:(icon 0xe0be)
      ~max_lines:4
      ~session_id:(ID.Text_input.Session_id.of_int64 2L)
      ~document_revision:ID.Text_input.Document_revision.zero
      ~accepted_local_revision:ID.Text_input.Local_revision.zero
      ~update_mode:Ui.Text_editing.Ack
      ~value:(text_value "Hello")
      ~on_edit:ignore_event
      ~on_submit:ignore_event
      ~on_focus_changed:ignore_event
      ()
  ; Ui.Material.list_tile
      ~headline:"List item"
      ~supporting_text:"Supporting text"
      ~overline:"Overline"
      ~leading:(icon 0xe88a)
      ~trailing:(icon 0xe5cc)
      ~selected:true
      ~on_press:ignore_event
      ()
  ; Ui.Material.divider ~thickness:1. ~spacing:8. ()
  ; Ui.Material.card ~variant:Ui.Material.Elevated (Ui.Widget.text "Elevated card")
  ; Ui.Material.card ~variant:Ui.Material.Filled (Ui.Widget.text "Filled card")
  ; Ui.Material.card ~variant:Ui.Material.Outlined (Ui.Widget.text "Outlined card")
  ; Ui.Material.circular_progress_indicator ~kind:Ui.Material.Flat ~value:0.6 ()
  ; Ui.Material.circular_progress_indicator ~kind:Ui.Material.Wavy ~value:0.6 ()
  ; Ui.Material.linear_progress_indicator ~kind:Ui.Material.Flat ~value:0.6 ()
  ; Ui.Material.linear_progress_indicator ~kind:Ui.Material.Wavy ~value:0.6 ()
  ; Ui.Material.Dialog.alert
      ~title:"Delete draft?"
      ~top_divider:true
      ~bottom_divider:true
      ~content:(Ui.Widget.text "This cannot be undone.")
      ~actions:[ Ui.Widget.text "Cancel"; Ui.Widget.text "Delete" ]
      ()
  ; Ui.Material.Tooltip.plain ~message:"Plain tooltip" (Ui.Widget.text "Anchor")
  ; Ui.Material.Tooltip.rich
      ~title:"Rich tooltip"
      ~message:"Supporting message"
      ~actions:[ Ui.Widget.text "Action" ]
      (Ui.Widget.text "Anchor")
  ; Ui.Material.Fab_menu.create
      ~position:Ui.Material.Fab_menu.Right
      ~expand_icon:(icon 0xe145)
      ~collapse_icon:(icon 0xe5cd)
      ~on_select:ignore_event
      [ Ui.Material.Fab_menu.item ~id:30L ~icon:(icon 0xe0be) ~label:"Compose" () ]
      ()
  ; Ui.Material.Button_group.create
      ~group_type:Ui.Material.Button_group.Connected
      ~style:Ui.Material.Button_group.Tonal
      ~overflow:Ui.Material.Button_group.Menu
      ~selection:(Ui.Material.Button_group.Multiple [ 31L ])
      ~on_selection_changed:ignore_event
      [ Ui.Material.Button_group.action ~id:31L ~icon:(icon 0xe8ef) ~label:"List" ()
      ; Ui.Material.Button_group.action ~id:32L ~icon:(icon 0xe3ec) ~label:"Grid" ()
      ]
      ()
  ; Ui.Material.Toggle_button.create
      ~style:Ui.Material.Toggle_button.Tonal
      ~checked:true
      ~on_changed:ignore_event
      ~icon:(icon 0xe8ef)
      ~checked_icon:(icon 0xe5ca)
      ~label:(Ui.Widget.text "Toggle")
      ()
  ; Ui.Material.Split_button.create
      ~label:"Export"
      ~on_press:ignore_event
      ~on_select:ignore_event
      ~menu
      ()
  ; Ui.Material.Dropdown_menu.create
      ~searchable:true
      ~query:"ma"
      ~on_query_changed:ignore_event
      ~selection:(Ui.Material.Dropdown_menu.Single (Some 40L))
      ~on_selection_changed:ignore_event
      (Ui.Material.Dropdown_menu.Items
         [ Ui.Material.Dropdown_menu.item ~id:40L ~label:"Mail" ()
         ; Ui.Material.Dropdown_menu.item ~id:41L ~label:"Maps" ()
         ])
      ()
  ; Ui.Material.Date_picker.calendar
      ~mode:Ui.Material.Date_picker.Year
      ~selected:date
      ~current:date
      ~first:first_date
      ~last:last_date
      ~selectable_dates:[ date ]
      ~on_select:ignore_event
      ()
  ; Ui.Material.Time_picker.dial
      ~format:Ui.Material.Time_picker.Hour_24
      ~value:time
      ~on_changed:ignore_event
      ()
  ; Ui.Material.Carousel.create
      ~layout:Ui.Material.Carousel.Hero
      ~on_select:ignore_event
      ~on_layout_changed:ignore_event
      [ Ui.Material.Carousel.item ~id:50L (Ui.Widget.text "Hero") ]
      ()
  ; Ui.Material.Card_list.finite ~on_select:ignore_event cards ()
  ; Ui.Material.Card_list.scrollable ~on_select:ignore_event cards ()
  ; Ui.Material.Selection.create
      ~item_ids:[ 60L ]
      ~selected_ids:[ 60L ]
      ~on_selection_changed:ignore_event
      (Ui.Material.Selection.leading
         ~id:60L
         ~selected:true
         ~on_toggle:ignore_event
         ~unselected:(Ui.Widget.text "Select")
         ~selected_child:(Ui.Widget.text "Selected")
         ())
  ; Ui.Material.Dismissible_list.column
      ~request_token:1L
      ~request_state:Ui.Material.Dismissible_list.Pending
      ~on_dismiss_request:ignore_event
      [ Ui.Material.Dismissible_list.item ~id:61L (Ui.Widget.text "Swipe vertically") ]
      ()
  ; Ui.Material.Dismissible_list.horizontal
      ~request_token:2L
      ~request_state:Ui.Material.Dismissible_list.Rejected
      ~on_dismiss_request:ignore_event
      [ Ui.Material.Dismissible_list.item ~id:62L (Ui.Widget.text "Swipe horizontally") ]
      ()
  ; Ui.Material.Expandable_list.finite
      ~expanded_ids:[ 20L ]
      ~on_expansion_changed:ignore_event
      expandable_items
      ()
  ; Ui.Material.Expandable_list.scrollable
      ~expanded_ids:[]
      ~on_expansion_changed:ignore_event
      expandable_items
      ()
  ; Ui.Material.Bottom_sheet.surface (Ui.Widget.text "Bottom sheet")
  ; Ui.Material.Side_sheet.surface
      ~title:(Ui.Widget.text "Side sheet")
      ~body:(Ui.Widget.text "Side sheet body")
      ()
  ; Ui.Material.App_bar.top
      ~leading:(icon 0xe5c4)
      ~actions:[ icon 0xe8b6; icon 0xe5d4 ]
      ~center_title:true
      ~safe_area:true
      ~semantic_label:"Expressive top app bar"
      ~title:(Ui.Widget.text "Top app bar")
      ()
  ; Ui.Material.App_bar.bottom
      ~actions:[ icon 0xe8b6 ]
      ~floating_action_button:
        (Ui.Material.Floating_action_button.icon
           ~on_press:ignore_event
           ~icon:(icon 0xe145)
           ())
      ()
  ; Ui.Material.App_bar.search
      ~session_id:(ID.Text_input.Session_id.of_int64 10L)
      ~document_revision:(ID.Text_input.Document_revision.of_int64 1L)
      ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
      ~update_mode:Ui.Text_editing.Force_replace
      ~value:(text_value "expressive")
      ~on_edit:ignore_event
      ~on_submit:ignore_event
      ~on_focus_changed:ignore_event
      ~on_select:ignore_event
      [ Ui.Material.App_bar.search_suggestion ~id:70L ~label:"Expressive result" () ]
      ()
  ; Ui.Material.Tabs.create
      ~selected_id:71L
      ~on_select:ignore_event
      [ Ui.Material.Tabs.tab ~id:71L ~label:"Primary" ~icon:(icon 0xe88a) ()
      ; Ui.Material.Tabs.tab ~id:79L ~label:"Secondary" ~icon:(icon 0xe8b8) ()
      ]
      ()
  ; Ui.Material.Navigation_rail.create
      ~modality:Ui.Material.Navigation_rail.Modal
      ~expanded:true
      ~selected_id:72L
      ~on_select:ignore_event
      ~on_expanded_changed:ignore_event
      ~trailing:(Ui.Widget.text "Trailing")
      ~fab:(Ui.Material.Navigation_rail.fab ~id:73L ~icon:(icon 0xe145) ~label:"New" ())
      [ Ui.Material.Navigation_rail.section
          [ Ui.Material.Navigation_rail.destination
              ~id:72L
              ~icon:(icon 0xe88a)
              ~label:"Home"
              ()
          ]
      ]
      ()
  ; Ui.Material.Navigation_drawer.create
      ~headline:"Navigation"
      ~selected_id:74L
      ~on_select:ignore_event
      [ Ui.Material.Navigation_drawer.destination
          ~id:74L
          ~icon:(icon 0xe88a)
          ~label:"Home"
          ()
      ]
      ()
  ; Ui.Material.Toolbar.create
      ~placement:Ui.Material.Toolbar.Floating
      ~expanded:true
      ~active_action_id:(Some 75L)
      ~on_action:ignore_event
      ~on_expanded_changed:ignore_event
      ~on_active_action_changed:ignore_event
      ~fab:(Ui.Material.Toolbar.fab ~id:76L ~icon:(icon 0xe145) ~label:"Create" ())
      [ Ui.Material.Toolbar.action ~id:75L ~icon:Ui.Material.Toolbar.Edit ~label:"Edit" ()
      ]
      ()
  ; Ui.Material.Menu.create
      ~on_select:ignore_event
      ~entries:menu
      ~anchor:(Ui.Widget.text "Open menu")
      ()
  ; Ui.Material.badge ~alignment:Ui.Material.Top_right ~count:8 (icon 0xe7f4)
  ; Ui.Material.loading_indicator ~variant:Ui.Material.Contained ~progress:0.25 ()
  ; Ui.Material.Refresh_indicator.create
      ~variant:Ui.Material.Refresh_indicator.Expressive
      ~show_token:1L
      ~request_token:3L
      ~request_state:Ui.Material.Refresh_indicator.Completed
      ~on_refresh_request:ignore_event
      (Ui.Widget.text "Pull to refresh")
  ; Ui.Material.Search_anchor.create
      ~presentation:Ui.Material.Search_anchor.Docked
      ~session_id:(ID.Text_input.Session_id.of_int64 11L)
      ~document_revision:(ID.Text_input.Document_revision.of_int64 1L)
      ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
      ~update_mode:Ui.Text_editing.Force_replace
      ~value:(text_value "query")
      ~on_edit:ignore_event
      ~on_submit:ignore_event
      ~on_focus_changed:ignore_event
      ~on_select:ignore_event
      [ Ui.Material.Search_anchor.suggestion ~id:76L ~label:"Suggestion" () ]
      ()
  ]
;;

let expressive_slivers () =
  [ Ui.Material.App_bar.sliver
      ~variant:Ui.Material.App_bar.Large
      ~shape:Ui.Material.App_bar.Round
      ~density:Ui.Material.App_bar.Compact
      ~semantic_label:"Catalog app bar"
      ~title:(Ui.Widget.text "Expressive catalog")
      ()
  ; Ui.Material.Card_list.sliver ~on_select:ignore_event cards ()
  ; Ui.Material.Expandable_list.sliver
      ~expanded_ids:[ 20L ]
      ~on_expansion_changed:ignore_event
      expandable_items
      ()
  ]
;;

let modal_side_sheet =
  Ui.Navigation.Modal_side_sheet
    (Ui.Navigation.Modal_side_sheet.create ~barrier_dismissible:true ())
;;

let date_picker_effect host =
  Ui.Host_effect.pick_date
    ~initial:(Ui.Host_effect.civil_date ~year:2026 ~month:9 ~day:3)
    ~first:(Ui.Host_effect.civil_date ~year:2026 ~month:1 ~day:1)
    ~last:(Ui.Host_effect.civil_date ~year:2026 ~month:12 ~day:31)
    host
    ()
;;

let date_range_picker_effect host =
  Ui.Host_effect.pick_date_range
    ~first:(Ui.Host_effect.civil_date ~year:2026 ~month:1 ~day:1)
    ~last:(Ui.Host_effect.civil_date ~year:2026 ~month:12 ~day:31)
    host
    ()
;;

let time_picker_effect host =
  Ui.Host_effect.pick_time
    ~initial:(Ui.Host_effect.civil_time ~hour:14 ~minute:30)
    host
    ()
;;
