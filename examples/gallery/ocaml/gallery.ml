module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

type gallery_card_event = Activate

type model =
  { checked : bool
  ; press_count : int
  ; native_count : int
  ; text : string
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  ; interaction_status : string
  ; segmented_single_ids : int64 list
  ; segmented_multi_ids : int64 list
  }

type handlers =
  { press : Ui.Event.Handler.t
  ; toggle : Ui.Event.Handler.t
  ; text_edit : Ui.Event.Handler.t
  ; text_submit : Ui.Event.Handler.t
  ; focus_changed : Ui.Event.Handler.t
  ; interaction : Ui.Event.Handler.t
  ; native : Ui.Event.Handler.t
  ; scroll : Ui.Event.Handler.t
  ; segmented_single : Ui.Event.Handler.t
  ; segmented_multi : Ui.Event.Handler.t
  }

let equal_model left right =
  Bool.equal left.checked right.checked
  && Int.equal left.press_count right.press_count
  && Int.equal left.native_count right.native_count
  && String.equal left.text right.text
  && ID.Text_input.Document_revision.equal left.document_revision right.document_revision
  && ID.Text_input.Local_revision.equal
       left.accepted_local_revision
       right.accepted_local_revision
  && String.equal left.interaction_status right.interaction_status
  && List.equal Int64.equal left.segmented_single_ids right.segmented_single_ids
  && List.equal Int64.equal left.segmented_multi_ids right.segmented_multi_ids
;;

let initial_model =
  { checked = false
  ; press_count = 0
  ; native_count = 0
  ; text = "Type 中文 or 😀"
  ; document_revision = ID.Text_input.Document_revision.zero
  ; accepted_local_revision = ID.Text_input.Local_revision.zero
  ; interaction_status = "Move, focus, tap, or press a key"
  ; segmented_single_ids = [ 1L ]
  ; segmented_multi_ids = []
  }
;;

let gallery_card =
  Ui.Native_widget.Extension.create
    ~kind_id:(ID.Native_widget.Kind_id.of_int 1001)
    ~version:1
    ~capabilities:[ Ui.Native_widget.Capability.Stateful; Resource; Semantics ]
    ~encode_props:Bytes.of_string
    ~decode_event:(fun ~event_id payload ->
      if
        ID.Native_widget.Event_id.equal event_id (ID.Native_widget.Event_id.of_int 1)
        && Bytes.length payload = 0
      then Ok Activate
      else Error "unknown gallery card event")
    ()
;;

let interaction_label = function
  | Ui.Event.Payload.Tap _ -> "Tap received in OCaml"
  | Pointer _ -> "Pointer event received in OCaml"
  | Key _ -> "Key event received in OCaml"
  | Bool true -> "Focus entered"
  | Bool false -> "Focus left"
  | _ -> "Typed interaction received in OCaml"
;;

let make_handlers registry set_model =
  let update name f =
    Driver.Handler.create
      registry
      ~name
      ~equal:( == )
      set_model
      ~f:(fun set_model payload -> set_model (fun model -> f model payload))
  in
  let press =
    update "gallery-press" (fun model _ ->
      { model with press_count = model.press_count + 1 })
  in
  let toggle =
    update "gallery-toggle" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool checked -> { model with checked }
      | Unit -> { model with checked = not model.checked }
      | _ -> model)
  in
  let text_edit =
    update "gallery-text-edit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text_edit edit ->
        { model with
          text = edit.text
        ; document_revision = ID.Text_input.Document_revision.succ model.document_revision
        ; accepted_local_revision = edit.local_revision
        }
      | _ -> model)
  in
  let text_submit =
    update "gallery-text-submit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text value ->
        { model with interaction_status = "Submitted: " ^ value }
      | _ -> model)
  in
  let focus_changed =
    update "gallery-focus" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool focused ->
        { model with
          interaction_status =
            (if focused then "Text field focused" else "Text field blurred")
        }
      | _ -> model)
  in
  let interaction =
    update "gallery-interaction" (fun model payload ->
      { model with interaction_status = interaction_label payload })
  in
  let native =
    Driver.Handler.create_native
      registry
      ~name:"gallery-native-card"
      gallery_card
      ~equal:( == )
      set_model
      ~f:(fun set_model Activate ->
        set_model (fun model -> { model with native_count = model.native_count + 1 }))
  in
  let scroll =
    update "gallery-scroll" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Scroll { pixels; _ } ->
        { model with interaction_status = Printf.sprintf "Scroll offset: %.0f" pixels }
      | _ -> model)
  in
  let segmented_single =
    update "gallery-segmented-single" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Int64_list segmented_single_ids ->
        { model with segmented_single_ids }
      | _ -> model)
  in
  let segmented_multi =
    update "gallery-segmented-multi" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Int64_list segmented_multi_ids ->
        { model with segmented_multi_ids }
      | _ -> model)
  in
  let first_pair = Bonsai.Cont.map2 press toggle ~f:(fun press toggle -> press, toggle) in
  let second_pair =
    Bonsai.Cont.map2 text_edit text_submit ~f:(fun text_edit text_submit ->
      text_edit, text_submit)
  in
  let third_pair =
    Bonsai.Cont.map2 focus_changed interaction ~f:(fun focus_changed interaction ->
      focus_changed, interaction)
  in
  let fourth_pair =
    Bonsai.Cont.map2 native scroll ~f:(fun native scroll -> native, scroll)
  in
  let first_half =
    Bonsai.Cont.map2
      first_pair
      second_pair
      ~f:(fun (press, toggle) (text_edit, text_submit) ->
        press, toggle, text_edit, text_submit)
  in
  let second_half =
    Bonsai.Cont.map2
      third_pair
      fourth_pair
      ~f:(fun (focus_changed, interaction) (native, scroll) ->
        focus_changed, interaction, native, scroll)
  in
  let existing =
    Bonsai.Cont.map2
      first_half
      second_half
      ~f:
        (fun
          (press, toggle, text_edit, text_submit)
          (focus_changed, interaction, native, scroll)
        ->
        press, toggle, text_edit, text_submit, focus_changed, interaction, native, scroll)
  in
  let segmented =
    Bonsai.Cont.map2 segmented_single segmented_multi ~f:(fun single multi ->
      single, multi)
  in
  Bonsai.Cont.map2
    existing
    segmented
    ~f:
      (fun
        (press, toggle, text_edit, text_submit, focus_changed, interaction, native, scroll)
        (segmented_single, segmented_multi)
      ->
      { press
      ; toggle
      ; text_edit
      ; text_submit
      ; focus_changed
      ; interaction
      ; native
      ; scroll
      ; segmented_single
      ; segmented_multi
      })
;;

let section title children =
  Ui.Material.card
    ~elevation:2.
    (Ui.Widget.padding
       ~insets:(Ui.Layout.Edge_insets.all 16.)
       (Ui.Widget.column (Ui.Widget.text title :: children)))
;;

let text_value model =
  let offset = Ui.Text_editing.Utf16.length model.text in
  let selection =
    Ui.Text_editing.Range.create ~text:model.text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text:model.text ~selection ()
;;

let core_section handlers =
  let decorated =
    Ui.Widget.decorated_box
      ~decoration:
        (Ui.Style.Decoration.create
           ~background:(Ui.Style.Color.rgb ~red:35 ~green:105 ~blue:170)
           ~border_radius:12.
           ())
      (Ui.Widget.padding
         ~insets:(Ui.Layout.Edge_insets.all 12.)
         (Ui.Widget.rich_text [ "Typed "; "core "; "primitives" ]))
  in
  let stack =
    Ui.Widget.Stack.create
      [ Ui.Widget.Stack.child
          (Ui.Widget.sized_box ~width:180. ~height:54. (Ui.Widget.empty ()))
      ; Ui.Widget.Stack.positioned ~left:8. ~top:8. (Ui.Widget.text "Stack")
      ; Ui.Widget.Stack.positioned ~right:8. ~bottom:8. (Ui.Widget.text "positioned")
      ]
  in
  section
    "Core layout and visuals"
    [ Ui.Widget.Flex.row
        [ Ui.Widget.Flex.expanded decorated
        ; Ui.Widget.Flex.fixed
            (Ui.Widget.padding
               ~insets:(Ui.Layout.Edge_insets.only ~left:12. ())
               (Ui.Widget.icon
                  ~font_family:"MaterialIcons"
                  ~size:28.
                  ~color:(Ui.Style.Color.rgb ~red:244 ~green:180 ~blue:0)
                  ~code_point:0xe838
                  ()))
        ]
    ; Ui.Widget.center
        (Ui.Widget.constrained_box
           ~constraints:
             (Ui.Layout.Box_constraints.create ~min_width:180. ~max_width:320. ())
           (Ui.Widget.clip
              ~behavior:Ui.Style.Clip.Anti_alias
              (Ui.Widget.opacity
                 0.92
                 (Ui.Widget.transform
                    ~transform:(Ui.Style.Transform.translate ~x:4. ())
                    stack))))
    ; Ui.Widget.safe_area
        ~minimum:(Ui.Layout.Edge_insets.only ~top:4. ())
        (Ui.Widget.environment_boundary
           (Ui.Widget.text "SafeArea and Environment boundary"))
    ; Ui.Material.elevated_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Core typed button")
        ()
    ]
;;

let material_section model handlers =
  let icon code_point = Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point () in
  let destinations =
    [ Ui.Material.Navigation_destination.create
        ~icon:(icon 0xe88a)
        ~selected_icon:(icon 0xe88a)
        ~label:"Home"
        ()
    ; Ui.Material.Navigation_destination.create ~icon:(icon 0xe8b8) ~label:"Settings" ()
    ]
  in
  let radio_options =
    [ Ui.Material.Radio_group.option ~id:1L ~label:(Ui.Widget.text "First") ()
    ; Ui.Material.Radio_group.option ~id:2L ~label:(Ui.Widget.text "Second") ()
    ]
  in
  let segmented_options =
    [ Ui.Material.Segmented_button.segment ~id:1L ~icon:(icon 0xe8ef) ~label:"List" ()
    ; Ui.Material.Segmented_button.segment ~id:2L ~icon:(icon 0xe3ec) ~label:"Grid" ()
    ; Ui.Material.Segmented_button.segment ~id:3L ~label:"Disabled" ()
    ]
  in
  section
    "Material"
    [ Ui.Material.filled_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Filled button")
        ()
    ; Ui.Material.filled_tonal_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Filled tonal button")
        ()
    ; Ui.Material.outlined_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Outlined button")
        ()
    ; Ui.Material.elevated_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text (Printf.sprintf "Pressed %d times" model.press_count))
        ()
    ; Ui.Material.text_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Text button")
        ()
    ; Ui.Material.icon_button
        ~on_press:handlers.press
        ~icon:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe87d ())
        ()
    ; Ui.Widget.column
        [ Ui.Widget.row
            [ Ui.Material.Floating_action_button.icon
                ~size:Ui.Material.Floating_action_button.Small
                ~on_press:handlers.press
                ~icon:(icon 0xe145)
                ()
            ; Ui.Material.Floating_action_button.icon
                ~on_press:handlers.press
                ~icon:(icon 0xe145)
                ()
            ]
        ; Ui.Widget.row
            [ Ui.Material.Floating_action_button.icon
                ~size:Ui.Material.Floating_action_button.Large
                ~on_press:handlers.press
                ~icon:(icon 0xe145)
                ()
            ; Ui.Material.Floating_action_button.extended
                ~on_press:handlers.press
                ~icon:(icon 0xe145)
                ~label:"Create"
                ()
            ]
        ]
    ; Ui.Material.navigation_bar
        ~selected_index:0
        ~on_select:handlers.press
        destinations
        ()
    ; Ui.Material.Radio_group.create
        ~selected_id:(Some 1L)
        ~on_select:handlers.press
        radio_options
        ()
    ; Ui.Material.Segmented_button.create
        ~selected_ids:model.segmented_single_ids
        ~on_selection_changed:handlers.segmented_single
        segmented_options
        ()
    ; Ui.Material.Segmented_button.create
        ~multi_selection_enabled:true
        ~selected_ids:model.segmented_multi_ids
        ~on_selection_changed:handlers.segmented_multi
        segmented_options
        ()
    ; Ui.Material.Segmented_button.create
        ~enabled:false
        ~selected_ids:[ 1L ]
        ~on_selection_changed:handlers.segmented_single
        segmented_options
        ()
    ; Ui.Material.slider
        ~value:0.35
        ~divisions:10
        ~label:"Single value"
        ~on_change:handlers.press
        ~on_change_end:handlers.press
        ()
    ; Ui.Material.range_slider
        ~value:(Ui.Material.Range.create ~start:0.2 ~end_:0.8)
        ~divisions:10
        ~label_start:"Low"
        ~label_end:"High"
        ~on_change:handlers.press
        ~on_change_end:handlers.press
        ()
    ; Ui.Widget.column
        [ Ui.Widget.row
            [ Ui.Material.Chip.assist
                ~leading:(icon 0xe8b6)
                ~on_press:handlers.press
                ~label:"Assist"
                ()
            ; Ui.Material.Chip.suggestion
                ~presentation:Ui.Material.Chip.Elevated
                ~on_press:handlers.press
                ~label:"Suggestion"
                ()
            ]
        ; Ui.Widget.row
            [ Ui.Material.Chip.filter
                ~presentation:Ui.Material.Chip.Elevated
                ~selected:model.checked
                ~on_press:handlers.toggle
                ~label:"Filter"
                ()
            ; Ui.Material.Chip.suggestion
                ~presentation:Ui.Material.Chip.Elevated
                ~selected:(not model.checked)
                ~on_press:handlers.toggle
                ~label:"Suggestion selected"
                ()
            ]
        ; Ui.Material.Chip.input
            ~selected:model.checked
            ~on_press:handlers.press
            ~on_delete:handlers.press
            ~label:"Input"
            ()
        ]
    ; Ui.Material.Dialog.alert
        ~icon:(icon 0xe002)
        ~title:"Alert dialog"
        ~top_divider:true
        ~bottom_divider:true
        ~content:(Ui.Widget.text "Declarative dialog content")
        ~actions:
          [ Ui.Material.text_button
              ~on_press:handlers.press
              ~child:(Ui.Widget.text "Cancel")
              ()
          ; Ui.Material.filled_button
              ~on_press:handlers.press
              ~child:(Ui.Widget.text "Confirm")
              ()
          ]
        ()
    ; Ui.Material.Dialog.simple
        ~title:(Ui.Widget.text "Simple dialog")
        ~on_select:handlers.interaction
        [ Ui.Material.Dialog.option ~id:1L ~label:(Ui.Widget.text "First option") ()
        ; Ui.Material.Dialog.option ~id:2L ~label:(Ui.Widget.text "Second option") ()
        ]
        ()
    ; Ui.Material.Dialog.fullscreen (Ui.Widget.text "Fullscreen dialog surface")
    ; Ui.Material.Tooltip.plain
        ~message:"General Material tooltip"
        (Ui.Widget.text "Long-press for tooltip")
    ; Ui.Material.Tooltip.rich
        ~title:"Expressive tooltip"
        ~message:"Rich tooltips can include logical action children."
        ~actions:
          [ Ui.Material.text_button
              ~on_press:handlers.press
              ~child:(Ui.Widget.text "Action")
              ()
          ]
        (Ui.Widget.text "Long-press for rich tooltip")
    ; Ui.Material.search_bar
        ~session_id:(ID.Text_input.Session_id.of_int64 2L)
        ~document_revision:model.document_revision
        ~accepted_local_revision:model.accepted_local_revision
        ~update_mode:Ui.Text_editing.Ack
        ~value:
          (let selection =
             Ui.Text_editing.Range.create
               ~text:model.text
               ~start_utf16:(Ui.Text_editing.Utf16.length model.text)
               ~end_utf16:(Ui.Text_editing.Utf16.length model.text)
           in
           Ui.Text_editing.Value.create ~text:model.text ~selection ())
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ~leading:(icon 0xe8b6)
        ~hint_text:"Standalone SearchBar"
        ()
    ; Ui.Material.Data_table.create
        ~sort_column_id:1L
        ~selected_row_ids:[ 10L ]
        ~on_sort:handlers.interaction
        ~on_row_selected:handlers.interaction
        ~on_cell_activate:handlers.interaction
        ~columns:
          [ Ui.Material.Data_table.column
              ~id:1L
              ~sortable:true
              ~label:(Ui.Widget.text "Name")
              ()
          ; Ui.Material.Data_table.column
              ~id:2L
              ~numeric:true
              ~label:(Ui.Widget.text "Score")
              ()
          ]
        ~rows:
          [ Ui.Material.Data_table.row
              ~id:10L
              ~selected:true
              [ Ui.Material.Data_table.cell ~activatable:true (Ui.Widget.text "Ada")
              ; Ui.Material.Data_table.cell (Ui.Widget.text "42")
              ]
          ]
        ()
    ; Ui.Widget.sized_box
        ~height:280.
        (Ui.Material.Stepper.create
           ~orientation:Ui.Material.Stepper.Horizontal
           ~current_step_id:1L
           ~on_step_selected:handlers.interaction
           ~on_continue:handlers.press
           ~on_cancel:handlers.press
           [ Ui.Material.Stepper.step
               ~id:1L
               ~title:(Ui.Widget.text "Edit")
               ~content:(Ui.Widget.text "Edit content")
               ()
           ; Ui.Material.Stepper.step
               ~id:2L
               ~state:Ui.Material.Stepper.Complete
               ~title:(Ui.Widget.text "Review")
               ~content:(Ui.Widget.text "Review content")
               ()
           ]
           ())
    ; Ui.Material.Expansion_panel_list.create
        ~policy:Ui.Material.Expansion_panel_list.Single
        ~expanded_ids:[ 1L ]
        ~on_expansion_changed:handlers.interaction
        [ Ui.Material.Expansion_panel_list.panel
            ~id:1L
            ~header:(Ui.Widget.text "Panel one")
            ~body:(Ui.Widget.text "Panel body")
            ()
        ; Ui.Material.Expansion_panel_list.panel
            ~id:2L
            ~header:(Ui.Widget.text "Panel two")
            ~body:(Ui.Widget.text "Second body")
            ()
        ]
        ()
    ; Ui.Widget.row
        [ Ui.Material.checkbox ~value:model.checked ~on_changed:handlers.toggle ()
        ; Ui.Material.switch ~value:model.checked ~on_changed:handlers.toggle ()
        ; Ui.Cupertino.switch ~value:model.checked ~on_changed:handlers.toggle ()
        ]
    ; Ui.Material.list_tile
        ~selected:model.checked
        ~supporting_text:"Selection truth lives in Bonsai"
        ~overline:"Expressive list"
        ~leading:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe88a ())
        ~trailing:(Ui.Widget.text "OCaml")
        ~on_press:handlers.toggle
        ~headline:"Typed list item"
        ()
    ; Ui.Widget.row
        [ Ui.Material.card ~variant:Ui.Material.Elevated (Ui.Widget.text "Elevated card")
        ; Ui.Material.card ~variant:Ui.Material.Filled (Ui.Widget.text "Filled card")
        ; Ui.Material.card ~variant:Ui.Material.Outlined (Ui.Widget.text "Outlined card")
        ; Ui.Material.divider ~orientation:Ui.Material.Vertical ~spacing:32. ()
        ]
    ; Ui.Material.divider ~thickness:1. ()
    ; Ui.Widget.row
        [ Ui.Material.circular_progress_indicator ~value:0.68 ()
        ; Ui.Cupertino.button handlers.press ~child:(Ui.Widget.text "Cupertino") ()
        ]
    ; Ui.Widget.column
        [ Ui.Widget.text "Determinate linear progress"
        ; Ui.Widget.sized_box
            ~width:240.
            (Ui.Material.linear_progress_indicator ~value:0.68 ())
        ; Ui.Widget.text "Indeterminate linear progress"
        ; Ui.Widget.sized_box ~width:240. (Ui.Material.linear_progress_indicator ())
        ]
    ]
;;

let expressive_catalog_section handlers =
  let icon code_point = Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point () in
  let search_value text =
    let offset = Ui.Text_editing.Utf16.length text in
    let selection =
      Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
    in
    Ui.Text_editing.Value.create ~text ~selection ()
  in
  let menu =
    [ Ui.Material.Menu.entry ~id:100L ~label:"Open" ()
    ; Ui.Material.Menu.selectable ~id:101L ~label:"Selected" ~selected:true ()
    ; Ui.Material.Menu.toggleable ~id:102L ~label:"Pinned" ~checked:false ()
    ; Ui.Material.Menu.divider
    ; Ui.Material.Menu.group
        ~label:"Export"
        [ Ui.Material.Menu.submenu
            ~id:103L
            ~label:"Format"
            [ Ui.Material.Menu.entry ~id:104L ~label:"PDF" () ]
        ]
    ]
  in
  let date = Ui.Material.Date.create ~year:2026 ~month:9 ~day:3 in
  let cards =
    [ Ui.Material.Card_list.item ~id:120L (Ui.Widget.text "First expressive card")
    ; Ui.Material.Card_list.item ~id:121L (Ui.Widget.text "Second expressive card")
    ]
  in
  let expandable =
    [ Ui.Material.Expandable_list.item
        ~id:130L
        ~header:"Expandable item"
        ~body:(Ui.Widget.text "Expanded content")
        ()
    ]
  in
  section
    "Material 3 Expressive catalog"
    [ Ui.Material.Fab_menu.create
        ~position:Ui.Material.Fab_menu.Right
        ~expand_icon:(icon 0xe145)
        ~collapse_icon:(icon 0xe5cd)
        ~on_select:handlers.interaction
        [ Ui.Material.Fab_menu.item ~id:105L ~icon:(icon 0xe0be) ~label:"Compose" () ]
        ()
    ; Ui.Material.Button_group.create
        ~group_type:Ui.Material.Button_group.Connected
        ~style:Ui.Material.Button_group.Tonal
        ~overflow:Ui.Material.Button_group.Menu
        ~selection:(Ui.Material.Button_group.Multiple [ 106L ])
        ~on_selection_changed:handlers.interaction
        [ Ui.Material.Button_group.action ~id:106L ~icon:(icon 0xe8ef) ~label:"List" ()
        ; Ui.Material.Button_group.action ~id:107L ~icon:(icon 0xe3ec) ~label:"Grid" ()
        ]
        ()
    ; Ui.Material.Toggle_button.create
        ~style:Ui.Material.Toggle_button.Tonal
        ~checked:true
        ~on_changed:handlers.toggle
        ~icon:(icon 0xe8ef)
        ~checked_icon:(icon 0xe5ca)
        ~label:(Ui.Widget.text "Toggle")
        ()
    ; Ui.Material.Split_button.create
        ~label:"Export"
        ~on_press:handlers.press
        ~on_select:handlers.interaction
        ~menu
        ()
    ; Ui.Material.Dropdown_menu.create
        ~searchable:true
        ~query:"ma"
        ~on_query_changed:handlers.text_submit
        ~selection:(Ui.Material.Dropdown_menu.Single (Some 108L))
        ~on_selection_changed:handlers.interaction
        (Ui.Material.Dropdown_menu.Items
           [ Ui.Material.Dropdown_menu.item ~id:108L ~label:"Mail" ()
           ; Ui.Material.Dropdown_menu.item ~id:109L ~label:"Maps" ()
           ])
        ()
    ; Ui.Widget.row
        [ Ui.Widget.sized_box
            ~width:180.
            (Ui.Material.slider
               ~kind:Ui.Material.Centered
               ~value:0.35
               ~on_change_end:handlers.interaction
               ())
        ; Ui.Widget.sized_box
            ~width:180.
            (Ui.Material.slider
               ~kind:Ui.Material.Wavy
               ~value:0.65
               ~on_change_end:handlers.interaction
               ())
        ; Ui.Widget.sized_box
            ~width:80.
            ~height:180.
            (Ui.Material.slider
               ~kind:Ui.Material.Vertical_centered
               ~value:0.5
               ~on_change_end:handlers.interaction
               ())
        ]
    ; Ui.Material.range_slider
        ~kind:Ui.Material.Wavy
        ~value:(Ui.Material.Range.create ~start:0.2 ~end_:0.8)
        ~on_change_end:handlers.interaction
        ()
    ; Ui.Material.Date_picker.calendar
        ~mode:Ui.Material.Date_picker.Year
        ~selected:date
        ~current:date
        ~first:(Ui.Material.Date.create ~year:2026 ~month:1 ~day:1)
        ~last:(Ui.Material.Date.create ~year:2026 ~month:12 ~day:31)
        ~selectable_dates:[ date ]
        ~on_select:handlers.interaction
        ()
    ; Ui.Material.Time_picker.dial
        ~format:Ui.Material.Time_picker.Hour_24
        ~value:(Ui.Material.Time.create ~hour:14 ~minute:30)
        ~on_changed:handlers.interaction
        ()
    ; Ui.Widget.sized_box
        ~height:240.
        (Ui.Material.Carousel.create
           ~layout:Ui.Material.Carousel.Hero
           ~on_select:handlers.interaction
           ~on_layout_changed:handlers.interaction
           [ Ui.Material.Carousel.item ~id:110L (Ui.Widget.text "Hero card")
           ; Ui.Material.Carousel.item ~id:111L (Ui.Widget.text "Second card")
           ]
           ())
    ; Ui.Material.Card_list.finite ~on_select:handlers.interaction cards ()
    ; Ui.Material.Selection.create
        ~item_ids:[ 112L ]
        ~selected_ids:[ 112L ]
        ~on_selection_changed:handlers.interaction
        (Ui.Material.Selection.leading
           ~id:112L
           ~selected:true
           ~on_toggle:handlers.interaction
           ~unselected:(Ui.Widget.text "Select")
           ~selected_child:(Ui.Widget.text "Selected")
           ())
    ; Ui.Material.Dismissible_list.column
        ~request_token:1L
        ~request_state:Ui.Material.Dismissible_list.Ready
        ~on_dismiss_request:handlers.interaction
        [ Ui.Material.Dismissible_list.item ~id:113L (Ui.Widget.text "Swipe vertically") ]
        ()
    ; Ui.Material.Dismissible_list.horizontal
        ~request_token:2L
        ~request_state:Ui.Material.Dismissible_list.Ready
        ~on_dismiss_request:handlers.interaction
        [ Ui.Material.Dismissible_list.item ~id:114L (Ui.Widget.text "Swipe horizontally")
        ]
        ()
    ; Ui.Material.Expandable_list.finite
        ~expanded_ids:[ 130L ]
        ~on_expansion_changed:handlers.interaction
        expandable
        ()
    ; Ui.Material.Bottom_sheet.surface (Ui.Widget.text "Bottom sheet surface")
    ; Ui.Material.Side_sheet.surface
        ~title:(Ui.Widget.text "Side sheet")
        ~body:(Ui.Widget.text "Side sheet surface")
        ()
    ; Ui.Material.App_bar.bottom
        ~actions:[ icon 0xe8b6 ]
        ~floating_action_button:
          (Ui.Material.Floating_action_button.icon
             ~on_press:handlers.press
             ~icon:(icon 0xe145)
             ())
        ()
    ; Ui.Material.App_bar.search
        ~session_id:(ID.Text_input.Session_id.of_int64 10L)
        ~document_revision:(ID.Text_input.Document_revision.of_int64 1L)
        ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
        ~update_mode:Ui.Text_editing.Force_replace
        ~value:(search_value "expressive")
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ~on_select:handlers.interaction
        [ Ui.Material.App_bar.search_suggestion ~id:115L ~label:"Expressive result" () ]
        ()
    ; Ui.Material.Tabs.create
        ~selected_id:116L
        ~on_select:handlers.interaction
        [ Ui.Material.Tabs.tab ~id:116L ~label:"Primary" ~icon:(icon 0xe88a) ()
        ; Ui.Material.Tabs.tab ~id:120L ~label:"Secondary" ~icon:(icon 0xe8b8) ()
        ]
        ()
    ; Ui.Material.Navigation_rail.create
        ~modality:Ui.Material.Navigation_rail.Modal
        ~expanded:true
        ~selected_id:117L
        ~on_select:handlers.interaction
        ~on_expanded_changed:handlers.interaction
        ~trailing:(Ui.Widget.text "Trailing")
        ~fab:
          (Ui.Material.Navigation_rail.fab ~id:118L ~icon:(icon 0xe145) ~label:"New" ())
        [ Ui.Material.Navigation_rail.section
            [ Ui.Material.Navigation_rail.destination
                ~id:117L
                ~icon:(icon 0xe88a)
                ~label:"Home"
                ()
            ]
        ]
        ()
    ; Ui.Material.Navigation_drawer.create
        ~headline:"Navigation"
        ~selected_id:119L
        ~on_select:handlers.interaction
        [ Ui.Material.Navigation_drawer.destination
            ~id:119L
            ~icon:(icon 0xe88a)
            ~label:"Home"
            ()
        ]
        ()
    ; Ui.Material.Toolbar.create
        ~placement:Ui.Material.Toolbar.Floating
        ~expanded:true
        ~active_action_id:(Some 122L)
        ~on_action:handlers.interaction
        ~on_expanded_changed:handlers.interaction
        ~on_active_action_changed:handlers.interaction
        ~fab:
          (Ui.Material.Toolbar.fab ~id:123L ~icon:(icon 0xe145) ~label:"Create" ())
        [ Ui.Material.Toolbar.action
            ~id:122L
            ~icon:Ui.Material.Toolbar.Edit
            ~label:"Edit"
            ()
        ]
        ()
    ; Ui.Material.Menu.create
        ~on_select:handlers.interaction
        ~entries:menu
        ~anchor:(Ui.Widget.text "Open nested menu")
        ()
    ; Ui.Widget.row
        [ Ui.Material.badge ~count:8 (icon 0xe7f4)
        ; Ui.Material.loading_indicator ~variant:Ui.Material.Contained ~progress:0.25 ()
        ; Ui.Material.circular_progress_indicator ~kind:Ui.Material.Wavy ~value:0.6 ()
        ]
    ; Ui.Material.linear_progress_indicator ~kind:Ui.Material.Wavy ~value:0.6 ()
    ; Ui.Material.Refresh_indicator.create
        ~request_token:3L
        ~request_state:Ui.Material.Refresh_indicator.Ready
        ~on_refresh_request:handlers.interaction
        (Ui.Widget.text "Pull to refresh")
    ; Ui.Material.Search_anchor.create
        ~presentation:Ui.Material.Search_anchor.Docked
        ~session_id:(ID.Text_input.Session_id.of_int64 11L)
        ~document_revision:(ID.Text_input.Document_revision.of_int64 1L)
        ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
        ~update_mode:Ui.Text_editing.Force_replace
        ~value:(search_value "query")
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ~on_select:handlers.interaction
        [ Ui.Material.Search_anchor.suggestion ~id:123L ~label:"Suggestion" () ]
        ()
    ]
;;

let interaction_section model handlers =
  let target =
    Ui.Widget.keyboard_listener
      ~autofocus:true
      ~key_policy:Ui.Event.Key_policy.Ignored
      ~on_key:handlers.interaction
      (Ui.Widget.focus_scope
         ~on_focus_changed:handlers.interaction
         (Ui.Widget.mouse_region
            ~on_enter:handlers.interaction
            ~on_leave:handlers.interaction
            (Ui.Widget.gesture
               ~on_tap:handlers.interaction
               ~on_double_tap:handlers.interaction
               ~on_long_press:handlers.interaction
               ~on_pointer_down:handlers.interaction
               ~on_pointer_up:handlers.interaction
               (Ui.Widget.padding
                  ~insets:(Ui.Layout.Edge_insets.all 14.)
                  (Ui.Widget.text model.interaction_status)))))
  in
  section "Interactions" [ target ]
;;

let text_input_section model handlers =
  section
    "Text input and IME"
    [ Ui.Material.text_field
        ~session_id:(ID.Text_input.Session_id.of_int64 1L)
        ~document_revision:model.document_revision
        ~accepted_local_revision:model.accepted_local_revision
        ~update_mode:Ui.Text_editing.Ack
        ~value:(text_value model)
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ()
    ; Ui.Widget.text ("Canonical OCaml value: " ^ model.text)
    ]
;;

let native_section model handlers =
  section
    "Native extension"
    [ Ui.Native_widget.widget_with_handler
        gallery_card
        ~key:(Ui.Key.string "gallery-native-card")
        ~props:(Printf.sprintf "Native card: %d" model.native_count)
        ~on_event:handlers.native
        ()
    ]
;;

let view model handlers =
  let icon code_point = Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point () in
  let bottom_destinations =
    [ Ui.Material.Navigation_destination.create
        ~icon:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe88a ())
        ~label:"Home"
        ()
    ; Ui.Material.Navigation_destination.create
        ~icon:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe8b8 ())
        ~label:"Settings"
        ()
    ]
  in
  let body =
    Ui.Widget.column
      [ Ui.Widget.text "OCaml owns every value and handler on this page"
      ; core_section handlers
      ; material_section model handlers
      ; expressive_catalog_section handlers
      ; interaction_section model handlers
      ; text_input_section model handlers
      ; native_section model handlers
      ]
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~key:(Ui.Key.string "gallery-scroll")
      ~on_scroll:handlers.scroll
      [ Ui.Material.App_bar.sliver
          ~variant:Ui.Material.App_bar.Large
          ~shape:Ui.Material.App_bar.Round
          ~density:Ui.Material.App_bar.Compact
          ~semantic_label:"Expressive gallery app bar"
          ~title:(Ui.Widget.text "Material 3 Expressive")
          ()
      ; Ui.Widget.Sliver.box body
      ]
      ()
    |> Ui.Widget.Viewport.Vertical.padding
         ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:24. ~vertical:16. ())
    |> Ui.Widget.Viewport.Vertical.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:"Bonsai Flutter gallery"
              ~role:Ui.Semantics.Role.Generic
              ~enabled:true
              ~checked:model.checked
              ())
  in
  let body = Ui.Widget.Body.Vertical.create [ Ui.Widget.Body.Vertical.fill viewport ] in
  Ui.Material.scaffold
    ~app_bar:
      (Ui.Material.App_bar.top
         ~actions:[ icon 0xe8b6; icon 0xe5d4 ]
         ~safe_area:true
         ~semantic_label:"Bonsai Flutter gallery app bar"
         ~title:(Ui.Widget.text "Bonsai Flutter Gallery")
         ())
    ~floating_action_button:
      (Ui.Material.Floating_action_button.extended
         ~on_press:handlers.press
         ~icon:(icon 0xe145)
         ~label:"New"
         ())
    ~floating_action_button_location:Ui.Material.End_docked
    ~bottom_navigation_bar:
      (Ui.Material.navigation_bar
         ~selected_index:0
         ~on_select:handlers.press
         bottom_destinations
         ())
    ~bottom_sheet:
      (Ui.Widget.sized_box
         ~height:24.
         (Ui.Widget.center (Ui.Widget.text "Persistent bottom sheet")))
    ~body
    ()
;;

let component registry graph =
  let model, set_model = Bonsai_v017.state ~equal:equal_model initial_model graph in
  let handlers = make_handlers registry set_model in
  Bonsai.Cont.map2 model handlers ~f:view
;;
