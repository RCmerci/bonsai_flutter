type floating_action_button_location =
  | Start_float
  | Center_float
  | End_float
  | Start_docked
  | Center_docked
  | End_docked

let widget_fab_location = function
  | Start_float -> Widget.Private.Start_float
  | Center_float -> Center_float
  | End_float -> End_float
  | Start_docked -> Start_docked
  | Center_docked -> Center_docked
  | End_docked -> End_docked
;;

let scaffold
      ?key
      ?app_bar
      ?floating_action_button
      ?(floating_action_button_location = End_float)
      ?bottom_navigation_bar
      ?bottom_sheet
      ~body
      ()
  =
  Widget.Private.material_scaffold
    ?key
    ?app_bar
    ?floating_action_button
    ~floating_action_button_location:(widget_fab_location floating_action_button_location)
    ?bottom_navigation_bar
    ?bottom_sheet
    ~body
    ()
;;

let app_bar = Widget.Private.material_app_bar

let button variant ?key ?enabled ?autofocus ~on_press ~child () =
  Widget.Private.material_button ?key ?enabled ?autofocus ~variant ~on_press ~child ()
;;

let filled_button = button Widget.Private.Filled
let filled_tonal_button = button Widget.Private.Filled_tonal
let outlined_button = button Widget.Private.Outlined

let elevated_button ?key ?enabled ?autofocus ~on_press ~child () =
  button Widget.Private.Elevated ?key ?enabled ?autofocus ~on_press ~child ()
;;

let text_button ?key ?enabled ?autofocus ~on_press ~child () =
  button Widget.Private.Text_button ?key ?enabled ?autofocus ~on_press ~child ()
;;

let icon_button ?key ?enabled ?autofocus ~on_press ~icon () =
  button Widget.Private.Icon_button ?key ?enabled ?autofocus ~on_press ~child:icon ()
;;

module Floating_action_button = struct
  type size =
    | Small
    | Standard
    | Large

  let variant = function
    | Small -> Widget.Private.Small
    | Standard -> Standard
    | Large -> Large
  ;;

  let icon ?key ?enabled ?autofocus ?(size = Standard) ~on_press ~icon () =
    Widget.Private.material_floating_action_button
      ?key
      ?enabled
      ?autofocus
      ~variant:(variant size)
      ~on_press
      ~icon
      ~label:icon
      ()
  ;;

  let extended ?key ?enabled ?autofocus ?icon ~on_press ~label () =
    Widget.Private.material_floating_action_button
      ?key
      ?enabled
      ?autofocus
      ~variant:Widget.Private.Extended
      ~on_press
      ?icon
      ~label
      ()
  ;;
end

module Navigation_destination = struct
  type t =
    { label : string
    ; enabled : bool
    ; icon : Widget.t
    ; selected_icon : Widget.t option
    }

  let create ?(enabled = true) ?selected_icon ~icon ~label () =
    if String.length (String.trim label) = 0
    then invalid_arg "Material.Navigation_destination.create: label must not be empty";
    { label; enabled; icon; selected_icon }
  ;;
end

let navigation_bar ?key ~selected_index ~on_select destinations () =
  if List.length destinations < 2
  then invalid_arg "Material.navigation_bar: at least two destinations are required";
  if selected_index < 0 || selected_index >= List.length destinations
  then invalid_arg "Material.navigation_bar: selected_index is out of range";
  let metadata, children =
    List.fold_left
      (fun (metadata, children) (destination : Navigation_destination.t) ->
         ( Widget.Private.
             { label = destination.label
             ; enabled = destination.enabled
             ; has_selected_icon = Option.is_some destination.selected_icon
             }
           :: metadata
         , List.rev_append
             (destination.icon :: Option.to_list destination.selected_icon)
             children ))
      ([], [])
      destinations
  in
  Widget.Private.material_navigation_bar
    ?key
    ~selected_index
    ~destinations:(List.rev metadata)
    ~children:(List.rev children)
    ~on_select
    ()
;;

module Radio_group = struct
  type t =
    { id : int64
    ; enabled : bool
    ; label : Widget.t option
    }

  let option ~id ?(enabled = true) ?label () = { id; enabled; label }

  let create ?key ~selected_id ~on_select options () =
    let ids = Hashtbl.create (List.length options) in
    List.iter
      (fun option ->
         if Hashtbl.mem ids option.id
         then invalid_arg "Material.Radio_group.create: option IDs must be unique";
         Hashtbl.add ids option.id ())
      options;
    (match selected_id with
     | Some id when not (Hashtbl.mem ids id) ->
       invalid_arg "Material.Radio_group.create: selected_id must name an option"
     | None | Some _ -> ());
    Widget.Private.material_radio_group
      ?key
      ~selected_id
      ~options:
        (List.map
           (fun option ->
              Widget.Private.
                { option_id = option.id
                ; enabled = option.enabled
                ; has_label = Option.is_some option.label
                })
           options)
      ~children:(List.filter_map (fun option -> option.label) options)
      ~on_select
      ()
  ;;
end

module Segmented_button = struct
  type segment =
    { id : int64
    ; enabled : bool
    ; icon : Widget.t option
    ; label : Widget.t option
    ; tooltip : string option
    }

  let segment ~id ?(enabled = true) ?icon ?label ?tooltip () =
    if Option.is_none icon && Option.is_none label
    then invalid_arg "Material.Segmented_button.segment: icon or label is required";
    { id; enabled; icon; label; tooltip }
  ;;

  let create
        ?key
        ?(enabled = true)
        ?(direction = Layout.Axis.Horizontal)
        ?(multi_selection_enabled = false)
        ?(empty_selection_allowed = false)
        ?expanded_insets
        ?(show_selected_icon = true)
        ?selected_icon
        ~selected_ids
        ~on_selection_changed
        segments
        ()
    =
    if List.is_empty segments
    then invalid_arg "Material.Segmented_button.create: segments must not be empty";
    if Option.is_some selected_icon && not show_selected_icon
    then
      invalid_arg
        "Material.Segmented_button.create: selected_icon requires show_selected_icon";
    let segment_ids = Hashtbl.create (List.length segments) in
    List.iter
      (fun segment ->
         if Hashtbl.mem segment_ids segment.id
         then invalid_arg "Material.Segmented_button.create: segment IDs must be unique";
         Hashtbl.add segment_ids segment.id ())
      segments;
    let selected_ids = List.sort Int64.compare selected_ids in
    let rec reject_duplicates = function
      | [] | [ _ ] -> ()
      | left :: (right :: _ as tail) ->
        if Int64.equal left right
        then invalid_arg "Material.Segmented_button.create: selected IDs must be unique";
        reject_duplicates tail
    in
    reject_duplicates selected_ids;
    List.iter
      (fun id ->
         if not (Hashtbl.mem segment_ids id)
         then
           invalid_arg "Material.Segmented_button.create: selected IDs must name segments")
      selected_ids;
    if (not multi_selection_enabled) && List.length selected_ids > 1
    then
      invalid_arg
        "Material.Segmented_button.create: single-selection mode accepts at most one ID";
    if (not empty_selection_allowed) && List.is_empty selected_ids
    then invalid_arg "Material.Segmented_button.create: selection must not be empty";
    let expanded_insets =
      Option.map Layout.Edge_insets.Private.to_sides expanded_insets
    in
    let metadata =
      List.map
        (fun segment ->
           Widget.Private.
             { segment_id = segment.id
             ; enabled = segment.enabled
             ; tooltip = segment.tooltip
             ; has_icon = Option.is_some segment.icon
             ; has_label = Option.is_some segment.label
             })
        segments
    in
    let children =
      Option.to_list selected_icon
      @ List.concat_map
          (fun segment -> Option.to_list segment.icon @ Option.to_list segment.label)
          segments
    in
    Widget.Private.material_segmented_button
      ?key
      ~selected_ids
      ~enabled
      ~direction
      ~multi_selection_enabled
      ~empty_selection_allowed
      ~expanded_insets
      ~show_selected_icon
      ~has_selected_icon:(Option.is_some selected_icon)
      ~segments:metadata
      ~children
      ~on_selection_changed
      ()
  ;;
end

module Range = struct
  type t =
    { start : float
    ; end_ : float
    }

  let create ~start ~end_ = { start; end_ }
end

let finite name value =
  if not (Float.is_finite value)
  then invalid_arg (Printf.sprintf "Material slider: %s must be finite" name)
;;

let validate_slider ~value ~min ~max ~divisions =
  finite "value" value;
  finite "min" min;
  finite "max" max;
  if min >= max then invalid_arg "Material slider: min must be less than max";
  if value < min || value > max
  then invalid_arg "Material slider: value must be within min and max";
  match divisions with
  | Some value when value <= 0 ->
    invalid_arg "Material slider: divisions must be positive"
  | None | Some _ -> ()
;;

let slider
      ?key
      ?(min = 0.)
      ?(max = 1.)
      ?divisions
      ?label
      ?(enabled = true)
      ?on_change
      ~value
      ~on_change_end
      ()
  =
  validate_slider ~value ~min ~max ~divisions;
  Widget.Private.material_slider
    ?key
    ~value
    ~min
    ~max
    ~divisions
    ~label
    ~enabled
    ~on_change
    ~on_change_end
    ()
;;

let range_slider
      ?key
      ?(min = 0.)
      ?(max = 1.)
      ?divisions
      ?label_start
      ?label_end
      ?(enabled = true)
      ?on_change
      ~(value : Range.t)
      ~on_change_end
      ()
  =
  validate_slider ~value:value.start ~min ~max ~divisions;
  validate_slider ~value:value.end_ ~min ~max ~divisions;
  if value.start > value.end_
  then invalid_arg "Material.range_slider: selection must not be reversed";
  Widget.Private.material_range_slider
    ?key
    ~start:value.start
    ~end_:value.end_
    ~min
    ~max
    ~divisions
    ~label_start
    ~label_end
    ~enabled
    ~on_change
    ~on_change_end
    ()
;;

type chip_presentation =
  | Flat
  | Elevated

let widget_chip_presentation = function
  | Flat -> Widget.Private.Flat_chip
  | Elevated -> Elevated_chip
;;

let action_chip ?key ?(presentation = Flat) ?(enabled = true) ?avatar ~on_press ~label () =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Action
    ~presentation:(widget_chip_presentation presentation)
    ~enabled
    ~selected:false
    ?avatar
    ~on_press
    ~label
    ()
;;

let filter_chip
      ?key
      ?(presentation = Flat)
      ?(enabled = true)
      ?avatar
      ~selected
      ~on_selected
      ~label
      ()
  =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Filter
    ~presentation:(widget_chip_presentation presentation)
    ~enabled
    ~selected
    ?avatar
    ~on_selected
    ~label
    ()
;;

let choice_chip
      ?key
      ?(presentation = Flat)
      ?(enabled = true)
      ?avatar
      ~selected
      ~on_selected
      ~label
      ()
  =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Choice
    ~presentation:(widget_chip_presentation presentation)
    ~enabled
    ~selected
    ?avatar
    ~on_selected
    ~label
    ()
;;

let input_chip
      ?key
      ?(enabled = true)
      ?avatar
      ?delete_icon
      ?on_press
      ?on_selected
      ?on_delete
      ~selected
      ~label
      ()
  =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Input
    ~presentation:Widget.Private.Flat_chip
    ~enabled
    ~selected
    ?avatar
    ?delete_icon
    ?on_press
    ?on_selected
    ?on_delete
    ~label
    ()
;;

module Tooltip = struct
  type placement =
    | Above
    | Below

  type trigger_mode =
    | Long_press
    | Tap
end

let nonnegative_int label value =
  if value < 0 || value > 0xffff_ffff
  then invalid_arg (Printf.sprintf "%s must fit non-negative uint32" label)
;;

let tooltip
      ?key
      ?(enabled = true)
      ?(exclude_from_semantics = false)
      ?(placement = Tooltip.Below)
      ?(trigger_mode = Tooltip.Long_press)
      ?(wait_duration_ms = 0)
      ?(show_duration_ms = 1500)
      ?(exit_duration_ms = 100)
      ?(enable_tap_to_dismiss = true)
      ?(enable_feedback = true)
      ?on_triggered
      ~message
      child
  =
  if String.length (String.trim message) = 0
  then invalid_arg "Material.tooltip: message must not be empty";
  List.iter
    (fun (label, value) -> nonnegative_int ("Material.tooltip: " ^ label) value)
    [ "wait_duration_ms", wait_duration_ms
    ; "show_duration_ms", show_duration_ms
    ; "exit_duration_ms", exit_duration_ms
    ];
  Widget.Private.material_tooltip
    ?key
    ~message
    ~enabled
    ~exclude_from_semantics
    ~prefer_below:(placement = Tooltip.Below)
    ~trigger_mode:
      (match trigger_mode with
       | Tooltip.Long_press -> Widget.Private.Tooltip_long_press
       | Tooltip.Tap -> Tooltip_tap)
    ~wait_duration_ms
    ~show_duration_ms
    ~exit_duration_ms
    ~enable_tap_to_dismiss
    ~enable_feedback
    ~on_triggered
    child
;;

let search_bar
      ?key
      ?(enabled = true)
      ?(read_only = false)
      ?(keyboard_type = Text_editing.Text)
      ?(input_action = Text_editing.Search)
      ?(autofocus = false)
      ?max_utf8_bytes
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ?on_limit_reached
      ?leading
      ?(trailing = [])
      ?hint_text
      ?on_tap
      ()
  =
  if
    Bonsai_flutter_spec.Id.Text_input.Session_id.compare
      session_id
      Bonsai_flutter_spec.Id.Text_input.Session_id.zero
    < 0
  then invalid_arg "Material.search_bar: session_id must be non-negative";
  if
    Bonsai_flutter_spec.Id.Text_input.Document_revision.compare
      document_revision
      Bonsai_flutter_spec.Id.Text_input.Document_revision.zero
    < 0
  then invalid_arg "Material.search_bar: document_revision must be non-negative";
  if
    Bonsai_flutter_spec.Id.Text_input.Local_revision.compare
      accepted_local_revision
      Bonsai_flutter_spec.Id.Text_input.Local_revision.zero
    < 0
  then invalid_arg "Material.search_bar: accepted_local_revision must be non-negative";
  (match max_utf8_bytes with
   | Some value when value <= 0 || value > 0xffff_ffff ->
     invalid_arg "Material.search_bar: max_utf8_bytes must fit positive uint32"
   | None | Some _ -> ());
  Widget.Private.material_search_bar
    ?key
    ~session_id
    ~document_revision
    ~accepted_local_revision
    ~update_mode
    ~value
    ~enabled
    ~read_only
    ~keyboard_type
    ~input_action
    ~autofocus
    ~max_utf8_bytes
    ~on_edit
    ~on_submit
    ~on_focus_changed
    ~on_limit_reached
    ~leading
    ~trailing
    ~hint_text
    ~on_tap
    ()
;;

let reject_duplicate_ids context ids =
  let seen = Hashtbl.create (List.length ids) in
  List.iter
    (fun id ->
       if Hashtbl.mem seen id then invalid_arg (context ^ ": IDs must be unique");
       Hashtbl.add seen id ())
    ids;
  seen
;;

module Data_table = struct
  type column =
    { id : int64
    ; tooltip : string option
    ; numeric : bool
    ; sortable : bool
    ; label : Widget.t
    }

  type cell =
    { content : Widget.t
    ; placeholder : bool
    ; show_edit_icon : bool
    ; activatable : bool
    }

  type row =
    { id : int64
    ; selected : bool
    ; selection_enabled : bool
    ; cells : cell list
    }

  let column ~id ?tooltip ?(numeric = false) ?(sortable = false) ~label () =
    Option.iter
      (fun value ->
         if String.length (String.trim value) = 0
         then invalid_arg "Material.Data_table.column: tooltip must not be empty")
      tooltip;
    { id; tooltip; numeric; sortable; label }
  ;;

  let cell ?(placeholder = false) ?(show_edit_icon = false) ?(activatable = false) content
    =
    { content; placeholder; show_edit_icon; activatable }
  ;;

  let row ~id ?(selected = false) ?(selection_enabled = true) cells =
    { id; selected; selection_enabled; cells }
  ;;

  let create
        ?key
        ?sort_column_id
        ?(sort_ascending = true)
        ?(selected_row_ids = [])
        ?on_sort
        ?on_row_selected
        ?on_select_all
        ?on_cell_activate
        ~columns
        ~rows
        ()
    =
    if List.is_empty columns
    then invalid_arg "Material.Data_table.create: columns must not be empty";
    let column_ids =
      reject_duplicate_ids
        "Material.Data_table.create columns"
        (List.map (fun (column : column) -> column.id) columns)
    in
    let row_ids =
      reject_duplicate_ids
        "Material.Data_table.create rows"
        (List.map (fun (row : row) -> row.id) rows)
    in
    List.iter
      (fun row ->
         if List.length row.cells <> List.length columns
         then
           invalid_arg
             "Material.Data_table.create: every row must have one cell per column")
      rows;
    Option.iter
      (fun id ->
         if not (Hashtbl.mem column_ids id)
         then invalid_arg "Material.Data_table.create: sort_column_id must name a column")
      sort_column_id;
    ignore (reject_duplicate_ids "Material.Data_table.create selection" selected_row_ids);
    let selected_row_ids = List.sort Int64.compare selected_row_ids in
    List.iter
      (fun id ->
         if not (Hashtbl.mem row_ids id)
         then invalid_arg "Material.Data_table.create: selected row IDs must name rows")
      selected_row_ids;
    let wire_columns =
      List.map
        (fun (column : column) ->
           Widget.Private.
             { column_id = column.id
             ; tooltip = column.tooltip
             ; numeric = column.numeric
             ; sortable = column.sortable
             })
        columns
    in
    let wire_rows =
      List.map
        (fun (row : row) ->
           Widget.Private.
             { row_id = row.id
             ; selected = row.selected
             ; selection_enabled = row.selection_enabled
             ; cells =
                 List.map
                   (fun (cell : cell) ->
                      Widget.Private.
                        { placeholder = cell.placeholder
                        ; show_edit_icon = cell.show_edit_icon
                        ; activatable = cell.activatable
                        })
                   row.cells
             })
        rows
    in
    Widget.Private.material_data_table
      ?key
      ~columns:wire_columns
      ~rows:wire_rows
      ~sort_column_id
      ~sort_ascending
      ~selected_row_ids
      ~on_sort
      ~on_row_selected
      ~on_select_all
      ~on_cell_activate
      ~children:
        (List.map (fun column -> column.label) columns
         @ List.concat_map (fun row -> List.map (fun cell -> cell.content) row.cells) rows
        )
      ()
  ;;
end

module Stepper = struct
  type orientation =
    | Vertical
    | Horizontal

  type state =
    | Indexed
    | Editing
    | Complete
    | Disabled
    | Error

  type step =
    { id : int64
    ; title : Widget.t
    ; content : Widget.t
    ; subtitle : Widget.t option
    ; label : Widget.t option
    ; active : bool
    ; state : state
    }

  let step ~id ~title ~content ?subtitle ?label ?(active = false) ?(state = Indexed) () =
    { id; title; content; subtitle; label; active; state }
  ;;

  let create
        ?key
        ?(orientation = Vertical)
        ~current_step_id
        ?on_step_selected
        ?on_continue
        ?on_cancel
        steps
        ()
    =
    if List.is_empty steps
    then invalid_arg "Material.Stepper.create: steps must not be empty";
    let ids =
      reject_duplicate_ids
        "Material.Stepper.create"
        (List.map (fun step -> step.id) steps)
    in
    if not (Hashtbl.mem ids current_step_id)
    then invalid_arg "Material.Stepper.create: current_step_id must name a step";
    let state = function
      | Indexed -> Widget.Private.Step_indexed
      | Editing -> Step_editing
      | Complete -> Step_complete
      | Disabled -> Step_disabled
      | Error -> Step_error
    in
    Widget.Private.material_stepper
      ?key
      ~orientation:
        (match orientation with
         | Vertical -> Layout.Axis.Vertical
         | Horizontal -> Horizontal)
      ~current_step_id
      ~steps:
        (List.map
           (fun step ->
              Widget.Private.
                { step_id = step.id
                ; active = step.active
                ; state = state step.state
                ; has_subtitle = Option.is_some step.subtitle
                ; has_label = Option.is_some step.label
                })
           steps)
      ~on_step_selected
      ~on_continue
      ~on_cancel
      ~children:
        (List.concat_map
           (fun step ->
              [ step.title; step.content ]
              @ Option.to_list step.subtitle
              @ Option.to_list step.label)
           steps)
      ()
  ;;
end

module Expansion_panel_list = struct
  type policy =
    | Multiple
    | Single

  type panel =
    { id : int64
    ; header : Widget.t
    ; body : Widget.t
    ; enabled : bool
    ; can_tap_on_header : bool
    }

  let panel ~id ~header ~body ?(enabled = true) ?(can_tap_on_header = false) () =
    { id; header; body; enabled; can_tap_on_header }
  ;;

  let create ?key ?(policy = Multiple) ~expanded_ids ~on_expansion_changed panels () =
    let ids =
      reject_duplicate_ids
        "Material.Expansion_panel_list.create"
        (List.map (fun panel -> panel.id) panels)
    in
    ignore
      (reject_duplicate_ids "Material.Expansion_panel_list.create expansion" expanded_ids);
    let expanded_ids = List.sort Int64.compare expanded_ids in
    List.iter
      (fun id ->
         if not (Hashtbl.mem ids id)
         then
           invalid_arg
             "Material.Expansion_panel_list.create: expanded IDs must name panels")
      expanded_ids;
    if policy = Single && List.length expanded_ids > 1
    then
      invalid_arg
        "Material.Expansion_panel_list.create: single mode accepts at most one expanded \
         ID";
    Widget.Private.material_expansion_panel_list
      ?key
      ~policy:
        (match policy with
         | Multiple -> Widget.Private.Multiple_panels
         | Single -> Single_panel)
      ~expanded_ids
      ~panels:
        (List.map
           (fun panel ->
              Widget.Private.
                { panel_id = panel.id
                ; enabled = panel.enabled
                ; can_tap_on_header = panel.can_tap_on_header
                })
           panels)
      ~on_expansion_changed
      ~children:(List.concat_map (fun panel -> [ panel.header; panel.body ]) panels)
      ()
  ;;
end

module Dialog = struct
  type option_ =
    { id : int64
    ; enabled : bool
    ; label : Widget.t
    }

  let option ~id ?(enabled = true) ~label () = { id; enabled; label }
  let alert = Widget.Private.material_alert_dialog

  let simple ?key ?title ~on_select options () =
    if List.is_empty options
    then invalid_arg "Material.Dialog.simple: options must not be empty";
    ignore
      (reject_duplicate_ids
         "Material.Dialog.simple"
         (List.map (fun option -> option.id) options));
    Widget.Private.material_simple_dialog
      ?key
      ?title
      ~options:
        (List.map
           (fun option ->
              Widget.Private.{ option_id = option.id; enabled = option.enabled })
           options)
      ~on_select
      ~children:(List.map (fun option -> option.label) options)
      ()
  ;;

  let fullscreen = Widget.Private.material_fullscreen_dialog
end

let checkbox ?key ?enabled ~value ~on_changed () =
  Widget.Private.material_checkbox ?key ?enabled ~value ~on_changed ()
;;

let switch = Widget.Private.material_switch
let text_field = Widget.text_input
let list_tile = Widget.Private.material_list_tile

type divider_orientation =
  | Horizontal
  | Vertical

type card_variant =
  | Elevated
  | Filled
  | Outlined

let divider ?key ?(orientation = Horizontal) ?thickness ?spacing ?indent ?end_indent () =
  Widget.Private.material_divider
    ?key
    ~orientation:
      (match orientation with
       | Horizontal -> Layout.Axis.Horizontal
       | Vertical -> Vertical)
    ?thickness
    ?spacing
    ?indent
    ?end_indent
    ()
;;

let card ?key ?(variant = Elevated) ?elevation child =
  Widget.Private.material_card
    ?key
    ~variant:
      (match variant with
       | Elevated -> Widget.Private.Elevated_card
       | Filled -> Filled_card
       | Outlined -> Outlined_card)
    ?elevation
    child
;;

let circular_progress_indicator = Widget.Private.material_circular_progress
let linear_progress_indicator = Widget.Private.material_linear_progress
