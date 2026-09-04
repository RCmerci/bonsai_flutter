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

let icon_button ?key ?enabled ~on_press ~icon () =
  button
    Widget.Private.Icon_button
    ?key
    ?enabled
    ~autofocus:false
    ~on_press
    ~child:icon
    ()
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

  let extended ?key ?enabled ?autofocus ~icon ~on_press ~label () =
    Widget.Private.material_floating_action_button
      ?key
      ?enabled
      ?autofocus
      ~variant:Widget.Private.Extended
      ~on_press
      ~icon
      ~label:(Widget.text label)
      ()
  ;;
end

module Navigation_destination = struct
  type t =
    { label : string
    ; icon : Widget.t
    ; selected_icon : Widget.t option
    ; badge_count : int option
    ; badge_dot : bool
    ; semantic_label : string option
    }

  let create
        ?selected_icon
        ?badge_count
        ?(badge_dot = false)
        ?semantic_label
        ~icon
        ~label
        ()
    =
    if String.length (String.trim label) = 0
    then invalid_arg "Material.Navigation_destination.create: label must not be empty";
    (match badge_count with
     | Some count when count < 0 ->
       invalid_arg
         "Material.Navigation_destination.create: badge_count must be non-negative"
     | Some _ when badge_dot ->
       invalid_arg
         "Material.Navigation_destination.create: choose badge_count or badge_dot"
     | None | Some _ -> ());
    { label; icon; selected_icon; badge_count; badge_dot; semantic_label }
  ;;
end

type navigation_bar_layout =
  | Auto
  | Compact
  | Wide

type navigation_bar_visibility =
  | Always
  | Selected
  | Never

type navigation_bar_alignment =
  | Start
  | Center
  | End

type navigation_bar_size =
  | Small
  | Medium

type navigation_bar_shape =
  | Round
  | Square

type navigation_bar_density =
  | Regular
  | Compact_density

let navigation_bar
      ?key
      ?(layout = Auto)
      ?(alignment = Center)
      ?(label_behavior = Always)
      ?(icon_behavior = Always)
      ?(size = Medium)
      ?(shape = Square)
      ?(density = Regular)
      ?(safe_area = true)
      ?semantic_label
      ~selected_index
      ~on_select
      destinations
      ()
  =
  if List.length destinations < 2
  then invalid_arg "Material.navigation_bar: at least two destinations are required";
  if selected_index < 0 || selected_index >= List.length destinations
  then invalid_arg "Material.navigation_bar: selected_index is out of range";
  let metadata, children =
    List.fold_left
      (fun (metadata, children) (destination : Navigation_destination.t) ->
         ( Widget.Private.
             { label = destination.label
             ; has_selected_icon = Option.is_some destination.selected_icon
             ; badge_count = destination.badge_count
             ; badge_dot = destination.badge_dot
             ; semantic_label = destination.semantic_label
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
    ~layout:
      (match layout with
       | Auto -> Auto
       | Compact -> Compact
       | Wide -> Wide)
    ~alignment:
      (match alignment with
       | Start -> Start
       | Center -> Center
       | End -> End)
    ~label_behavior:
      (match label_behavior with
       | Always -> Always
       | Selected -> Selected
       | Never -> Never)
    ~icon_behavior:
      (match icon_behavior with
       | Always -> Always
       | Selected -> Selected
       | Never -> Never)
    ~size:
      (match size with
       | Small -> Small_bar
       | Medium -> Medium_bar)
    ~shape:
      (match shape with
       | Round -> Round_bar
       | Square -> Square_bar)
    ~density:
      (match density with
       | Regular -> Regular_bar
       | Compact_density -> Compact_bar)
    ~safe_area
    ~semantic_label
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
    ; icon : Widget.t option
    ; label : string
    }

  let segment ~id ?icon ~label () =
    if String.length (String.trim label) = 0
    then invalid_arg "Material.Segmented_button.segment: label must not be empty";
    { id; icon; label }
  ;;

  let create
        ?key
        ?(enabled = true)
        ?(multi_selection_enabled = false)
        ~selected_ids
        ~on_selection_changed
        segments
        ()
    =
    if List.is_empty segments
    then invalid_arg "Material.Segmented_button.create: segments must not be empty";
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
    if (not multi_selection_enabled) && List.is_empty selected_ids
    then
      invalid_arg "Material.Segmented_button.create: single selection must not be empty";
    let metadata =
      List.map
        (fun segment ->
           Widget.Private.
             { segment_id = segment.id; has_icon = Option.is_some segment.icon })
        segments
    in
    let children =
      List.concat_map
        (fun segment -> Option.to_list segment.icon @ [ Widget.text segment.label ])
        segments
    in
    Widget.Private.material_segmented_button
      ?key
      ~selected_ids
      ~enabled
      ~multi_selection_enabled
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

type slider_kind =
  | Standard
  | Centered
  | Wavy
  | Wavy_centered
  | Vertical
  | Vertical_centered

type range_slider_kind =
  | Flat
  | Wavy

let slider
      ?key
      ?(min = 0.)
      ?(max = 1.)
      ?divisions
      ?label
      ?(enabled = true)
      ?(kind = Standard)
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
    ~kind:
      (match kind with
       | Standard -> 0
       | Centered -> 1
       | Wavy -> 2
       | Wavy_centered -> 3
       | Vertical -> 4
       | Vertical_centered -> 5)
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
      ?(kind = Flat)
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
    ~kind:
      (match kind with
       | Flat -> 0
       | Wavy -> 1)
    ~on_change
    ~on_change_end
    ()
;;

module Chip = struct
  type presentation =
    | Flat
    | Elevated

  let widget_presentation = function
    | Flat -> Widget.Private.Flat_chip
    | Elevated -> Elevated_chip
  ;;

  let create
        variant
        ?key
        ?(presentation = Flat)
        ?(enabled = true)
        ?leading
        ?(selected = false)
        ?on_delete
        ~on_press
        ~label
        ()
    =
    if String.length (String.trim label) = 0
    then invalid_arg "Material.Chip: label must not be empty";
    Widget.Private.material_chip
      ?key
      ~variant
      ~presentation:(widget_presentation presentation)
      ~enabled
      ~selected
      ?avatar:leading
      ~on_press
      ?on_delete
      ~label:(Widget.text label)
      ()
  ;;

  let assist ?key ?presentation ?enabled ?leading ?selected ~on_press ~label () =
    create
      Widget.Private.Action
      ?key
      ?presentation
      ?enabled
      ?leading
      ?selected
      ~on_press
      ~label
      ()
  ;;

  let suggestion ?key ?presentation ?enabled ?leading ?selected ~on_press ~label () =
    create
      Widget.Private.Choice
      ?key
      ?presentation
      ?enabled
      ?leading
      ?selected
      ~on_press
      ~label
      ()
  ;;

  let filter ?key ?presentation ?enabled ?leading ~selected ~on_press ~label () =
    create
      Widget.Private.Filter
      ?key
      ?presentation
      ?enabled
      ?leading
      ~selected
      ~on_press
      ~label
      ()
  ;;

  let input ?key ?presentation ?enabled ?leading ~selected ~on_press ?on_delete ~label () =
    create
      Widget.Private.Input
      ?key
      ?presentation
      ?enabled
      ?leading
      ~selected
      ~on_press
      ?on_delete
      ~label
      ()
  ;;
end

module Tooltip = struct
  let validate label value =
    if String.length (String.trim value) = 0
    then invalid_arg (label ^ " must not be empty")
  ;;

  let plain ?key ~message child =
    validate "Material.Tooltip.plain message" message;
    Widget.Private.material_expressive
      ?key
      ~component:25
      ~secondary_text:message
      ~children:[ child ]
      ()
  ;;

  let rich ?key ?title ~message ~actions child =
    validate "Material.Tooltip.rich message" message;
    Option.iter (validate "Material.Tooltip.rich title") title;
    Widget.Private.material_expressive
      ?key
      ~component:25
      ~variant:1
      ?primary_text:title
      ~secondary_text:message
      ~flags:(Int64.of_int (List.length actions))
      ~children:(child :: actions)
      ()
  ;;
end

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

  let alert
        ?key
        ?icon
        ?content
        ?(top_divider = false)
        ?(bottom_divider = false)
        ~title
        ~actions
        ()
    =
    if String.length (String.trim title) = 0
    then invalid_arg "Material.Dialog.alert: title must not be empty";
    Widget.Private.material_expressive
      ?key
      ~component:27
      ~primary_text:title
      ~flags:
        (Int64.of_int
           ((if Option.is_some icon then 1 else 0)
            lor (if Option.is_some content then 2 else 0)
            lor (if top_divider then 4 else 0)
            lor if bottom_divider then 8 else 0))
      ~items:
        [ Widget.Private.
            { item_id = 0L
            ; kind = 0
            ; label = ""
            ; enabled = true
            ; selected = false
            ; child_count = List.length actions
            }
        ]
      ~children:(Option.to_list icon @ Option.to_list content @ actions)
      ()
  ;;

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

type text_field_variant =
  | Filled
  | Outlined

let text_field
      ?key
      ?(enabled = true)
      ?(read_only = false)
      ?(obscure_text = false)
      ?(keyboard_type = Text_editing.Text)
      ?(input_action = Text_editing.Done)
      ?max_utf8_bytes
      ?(variant = Filled)
      ?label
      ?supporting_text
      ?error_text
      ?leading
      ?trailing
      ?(max_lines = 1)
      ?(autofocus = false)
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ?on_limit_reached
      ()
  =
  if
    Bonsai_flutter_spec.Id.Text_input.Session_id.compare
      session_id
      Bonsai_flutter_spec.Id.Text_input.Session_id.zero
    < 0
  then invalid_arg "Material.text_field: session_id must be non-negative";
  if
    Bonsai_flutter_spec.Id.Text_input.Document_revision.compare
      document_revision
      Bonsai_flutter_spec.Id.Text_input.Document_revision.zero
    < 0
  then invalid_arg "Material.text_field: document_revision must be non-negative";
  if
    Bonsai_flutter_spec.Id.Text_input.Local_revision.compare
      accepted_local_revision
      Bonsai_flutter_spec.Id.Text_input.Local_revision.zero
    < 0
  then invalid_arg "Material.text_field: accepted_local_revision must be non-negative";
  (match max_utf8_bytes with
   | Some value when value <= 0 || value > 0xffff_ffff ->
     invalid_arg "Material.text_field: max_utf8_bytes must fit positive uint32"
   | None | Some _ -> ());
  if max_lines <= 0 then invalid_arg "Material.text_field: max_lines must be positive";
  Widget.Private.material_text_field
    ?key
    ~session_id
    ~document_revision
    ~accepted_local_revision
    ~update_mode
    ~value
    ~enabled
    ~read_only
    ~obscure_text
    ~keyboard_type
    ~input_action
    ~max_utf8_bytes
    ~variant:
      (match variant with
       | Filled -> 0
       | Outlined -> 1)
    ~label
    ~supporting_text
    ~error_text
    ~leading
    ~trailing
    ~max_lines
    ~autofocus
    ~on_edit
    ~on_submit
    ~on_focus_changed
    ~on_limit_reached
    ()
;;

let list_tile
      ?key
      ?(enabled = true)
      ?(selected = false)
      ?supporting_text
      ?overline
      ?leading
      ?trailing
      ~on_press
      ~headline
      ()
  =
  if String.length (String.trim headline) = 0
  then invalid_arg "Material.list_tile: headline must not be empty";
  Widget.Private.material_expressive
    ?key
    ~component:26
    ~primary_text:headline
    ?secondary_text:supporting_text
    ~flags:
      (Int64.of_int
         ((if enabled then 1 else 0)
          lor (if selected then 2 else 0)
          lor (if Option.is_some leading then 4 else 0)
          lor if Option.is_some trailing then 8 else 0))
    ~items:
      [ Widget.Private.
          { item_id = 0L
          ; kind = 0
          ; label = Option.value overline ~default:""
          ; enabled = true
          ; selected = false
          ; child_count = 0
          }
      ]
    ~on_press
    ~children:(Option.to_list leading @ Option.to_list trailing)
    ()
;;

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

type progress_kind =
  | Flat
  | Wavy

let circular_progress_indicator ?key ?(kind = Flat) ?value () =
  Widget.Private.material_circular_progress
    ?key
    ?value
    ~wavy:
      (match kind with
       | Flat -> false
       | Wavy -> true)
    ()
;;

let linear_progress_indicator ?key ?(kind = Flat) ?value () =
  Widget.Private.material_linear_progress
    ?key
    ?value
    ~wavy:
      (match kind with
       | Flat -> false
       | Wavy -> true)
    ()
;;

let expressive_item ?(kind = 0) ?(enabled = true) ?(selected = false) ~id ~label children =
  let metadata =
    Widget.Private.
      { item_id = id; kind; label; enabled; selected; child_count = List.length children }
  in
  metadata, children
;;

let expressive
      ?key
      ~component
      ?variant
      ?flags
      ?primary_text
      ?secondary_text
      ?value
      ?end_value
      ?selected_ids
      ?items
      ?text_input
      ?on_press
      ?on_select
      ?on_selection_changed
      ?on_active_changed
      ?on_value_changed
      ?on_change_end
      ?on_text_changed
      ?on_text_edit
      ?on_text_submit
      ?on_focus_changed
      ?on_limit_reached
      ?on_civil_date_changed
      ?on_civil_time_changed
      ?on_search_opened
      ?on_search_closed
      children
  =
  Widget.Private.material_expressive
    ?key
    ~component
    ?variant
    ?flags
    ?primary_text
    ?secondary_text
    ?value
    ?end_value
    ?selected_ids
    ?items
    ?text_input
    ?on_press
    ?on_select
    ?on_selection_changed
    ?on_active_changed
    ?on_value_changed
    ?on_change_end
    ?on_text_changed
    ?on_text_edit
    ?on_text_submit
    ?on_focus_changed
    ?on_limit_reached
    ?on_civil_date_changed
    ?on_civil_time_changed
    ?on_search_opened
    ?on_search_closed
    ~children
    ()
;;

let expressive_text_input
      ?(enabled = true)
      ?(keyboard_type = Text_editing.Text)
      ?(input_action = Text_editing.Search)
      ?max_utf8_bytes
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ()
  =
  Option.iter
    (fun limit ->
       if limit <= 0
       then invalid_arg "Material expressive search: max_utf8_bytes must be positive")
    max_utf8_bytes;
  Widget.Private.
    { session_id
    ; document_revision
    ; value
    ; enabled
    ; read_only = false
    ; obscure_text = false
    ; keyboard_type
    ; input_action
    ; accepted_local_revision
    ; update_mode
    ; autofocus = false
    ; max_utf8_bytes
    }
;;

let require_nonempty context value =
  if String.length (String.trim value) = 0
  then invalid_arg (context ^ ": value must not be empty")
;;

let validate_items context entries =
  if List.is_empty entries then invalid_arg (context ^ ": items must not be empty");
  ignore (reject_duplicate_ids context (List.map fst entries))
;;

module Menu = struct
  type entry =
    { id : int64
    ; kind : int
    ; label : string
    ; enabled : bool
    ; selected : bool
    ; children : entry list
    }

  let leaf kind ~id ~label ?(enabled = true) ?(selected = false) () =
    require_nonempty "Material.Menu entry label" label;
    { id; kind; label; enabled; selected; children = [] }
  ;;

  let entry ~id ~label ?enabled () = leaf 0 ~id ~label ?enabled ()

  let selectable ~id ~label ~selected ?enabled () =
    leaf 1 ~id ~label ~selected ?enabled ()
  ;;

  let toggleable ~id ~label ~checked ?enabled () =
    leaf 2 ~id ~label ~selected:checked ?enabled ()
  ;;

  let divider =
    { id = 0L; kind = 3; label = ""; enabled = false; selected = false; children = [] }
  ;;

  let group ?(label = "") children =
    { id = 0L; kind = 4; label; enabled = true; selected = false; children }
  ;;

  let submenu ~id ~label ?(enabled = true) children =
    require_nonempty "Material.Menu submenu label" label;
    if List.is_empty children
    then invalid_arg "Material.Menu.submenu: entries must not be empty";
    { id; kind = 5; label; enabled; selected = false; children }
  ;;

  let rec flatten entry =
    let metadata =
      Widget.Private.
        { item_id = entry.id
        ; kind = entry.kind
        ; label = entry.label
        ; enabled = entry.enabled
        ; selected = entry.selected
        ; child_count = List.length entry.children
        }
    in
    metadata :: List.concat_map flatten entry.children
  ;;

  let metadata entries = List.concat_map flatten entries

  let validate context entries =
    if List.is_empty entries then invalid_arg (context ^ ": entries must not be empty");
    let rec interactive_ids acc = function
      | [] -> acc
      | entry :: rest ->
        let acc = if entry.kind = 3 || entry.kind = 4 then acc else entry.id :: acc in
        interactive_ids (interactive_ids acc entry.children) rest
    in
    ignore (reject_duplicate_ids context (interactive_ids [] entries))
  ;;

  let create ?key ~on_select ~entries ~anchor () =
    validate "Material.Menu.create" entries;
    expressive ?key ~component:20 ~items:(metadata entries) ~on_select [ anchor ]
  ;;
end

module Fab_menu = struct
  type position =
    | Left
    | Right

  type item =
    { id : int64
    ; icon : Widget.t
    ; label : string
    ; enabled : bool
    }

  let item ~id ~icon ~label ?(enabled = true) () =
    require_nonempty "Material.Fab_menu.item label" label;
    { id; icon; label; enabled }
  ;;

  let create ?key ?(position = Right) ~expand_icon ~collapse_icon ~on_select items () =
    validate_items "Material.Fab_menu.create" (List.map (fun item -> item.id, ()) items);
    let encoded =
      List.map
        (fun item ->
           expressive_item
             ~id:item.id
             ~label:item.label
             ~enabled:item.enabled
             [ item.icon ])
        items
    in
    expressive
      ?key
      ~component:0
      ~variant:
        (match position with
         | Left -> 0
         | Right -> 1)
      ~items:(List.map fst encoded)
      ~on_select
      (expand_icon :: collapse_icon :: List.concat_map snd encoded)
  ;;
end

module Button_group = struct
  type group_type =
    | Standard
    | Connected

  type button_style =
    | Filled
    | Tonal
    | Elevated
    | Outlined
    | Text

  type size =
    | Extra_small
    | Small
    | Medium
    | Large
    | Extra_large

  type shape =
    | Round
    | Square

  type overflow =
    | Wrap
    | Scroll
    | Menu

  type selection =
    | No_selection
    | Single of int64 option
    | Multiple of int64 list

  type action =
    { id : int64
    ; icon : Widget.t option
    ; label : string option
    ; enabled : bool
    }

  let action ~id ?icon ?label ?(enabled = true) () =
    if Option.is_none icon && Option.is_none label
    then invalid_arg "Material.Button_group.action: icon or label is required";
    Option.iter (require_nonempty "Material.Button_group.action label") label;
    { id; icon; label; enabled }
  ;;

  let create
        ?key
        ?(group_type = Standard)
        ?(style = Filled)
        ?(size = Small)
        ?(shape = Round)
        ?(axis = Layout.Axis.Horizontal)
        ?(overflow = Wrap)
        ~selection
        ~on_selection_changed
        actions
        ()
    =
    validate_items
      "Material.Button_group.create"
      (List.map (fun action -> action.id, ()) actions);
    let selected_ids, multiple =
      match selection with
      | No_selection -> [], false
      | Single value -> Option.to_list value, false
      | Multiple values -> List.sort Int64.compare values, true
    in
    List.iter
      (fun id ->
         if not (List.exists (fun action -> Int64.equal action.id id) actions)
         then invalid_arg "Material.Button_group.create: selected ID must name an action")
      selected_ids;
    let encoded =
      List.map
        (fun action ->
           expressive_item
             ~id:action.id
             ~label:(Option.value action.label ~default:"")
             ~enabled:action.enabled
             ~selected:(List.mem action.id selected_ids)
             (Option.to_list action.icon))
        actions
    in
    let enum value variants =
      let rec find index = function
        | [] -> assert false
        | head :: tail -> if value = head then index else find (index + 1) tail
      in
      find 0 variants
    in
    let flags =
      Int64.of_int
        ((enum size [ Extra_small; Small; Medium; Large; Extra_large ] lsl 0)
         lor (enum shape [ Round; Square ] lsl 3)
         lor (enum axis [ Layout.Axis.Horizontal; Vertical ] lsl 4)
         lor (enum overflow [ Wrap; Scroll; Menu ] lsl 5)
         lor if multiple then 1 lsl 7 else 0)
    in
    expressive
      ?key
      ~component:1
      ~variant:
        (((match group_type with
           | Standard -> 0
           | Connected -> 1)
          * 5)
         + enum style [ Filled; Tonal; Elevated; Outlined; Text ])
      ~flags
      ~selected_ids
      ~items:(List.map fst encoded)
      ~on_selection_changed
      (List.concat_map snd encoded)
  ;;
end

module Toggle_button = struct
  type style =
    | Filled
    | Tonal
    | Elevated
    | Outlined
    | Text

  let create
        ?key
        ?(style = Filled)
        ?(enabled = true)
        ~checked
        ~on_changed
        ?icon
        ?checked_icon
        ?label
        ()
    =
    if Option.is_none icon && Option.is_none checked_icon && Option.is_none label
    then invalid_arg "Material.Toggle_button.create: content is required";
    expressive
      ?key
      ~component:2
      ~variant:
        (match style with
         | Filled -> 0
         | Tonal -> 1
         | Elevated -> 2
         | Outlined -> 3
         | Text -> 4)
      ~flags:
        (Int64.of_int
           ((if enabled then 1 else 0)
            lor (if checked then 2 else 0)
            lor (if Option.is_some icon then 4 else 0)
            lor (if Option.is_some checked_icon then 8 else 0)
            lor if Option.is_some label then 16 else 0))
      ~on_value_changed:on_changed
      (Option.to_list icon @ Option.to_list checked_icon @ Option.to_list label)
  ;;
end

module Split_button = struct
  type style =
    | Filled
    | Tonal
    | Elevated
    | Outlined

  let create ?key ?(style = Filled) ?(enabled = true) ~label ~on_press ~on_select ~menu ()
    =
    require_nonempty "Material.Split_button label" label;
    Menu.validate "Material.Split_button.create" menu;
    expressive
      ?key
      ~component:3
      ~variant:
        (match style with
         | Filled -> 0
         | Tonal -> 1
         | Elevated -> 2
         | Outlined -> 3)
      ~flags:(if enabled then 1L else 0L)
      ~primary_text:label
      ~items:(Menu.metadata menu)
      ~on_press
      ~on_select
      []
  ;;
end

module Dropdown_menu = struct
  type item =
    { id : int64
    ; label : string
    ; enabled : bool
    }

  type content =
    | Items of item list
    | Loading
    | Empty of string
    | Error of string

  type selection =
    | Single of int64 option
    | Multiple of int64 list

  let item ~id ~label ?(enabled = true) () =
    require_nonempty "Material.Dropdown_menu.item label" label;
    { id; label; enabled }
  ;;

  let create
        ?key
        ?(searchable = false)
        ?(query = "")
        ?on_query_changed
        ~selection
        ~on_selection_changed
        content
        ()
    =
    let content_variant, message, items =
      match content with
      | Items items -> 0, None, items
      | Loading -> 1, None, []
      | Empty message -> 2, Some message, []
      | Error message -> 3, Some message, []
    in
    if content_variant = 0
    then
      validate_items
        "Material.Dropdown_menu.create"
        (List.map (fun item -> item.id, ()) items);
    let selected_ids, multiple =
      match selection with
      | Single value -> Option.to_list value, false
      | Multiple values -> List.sort Int64.compare values, true
    in
    let metadata =
      List.map
        (fun item ->
           fst
             (expressive_item
                ~id:item.id
                ~label:item.label
                ~enabled:item.enabled
                ~selected:(List.mem item.id selected_ids)
                []))
        items
    in
    expressive
      ?key
      ~component:4
      ~variant:content_variant
      ~flags:(Int64.of_int ((if searchable then 1 else 0) lor if multiple then 2 else 0))
      ~primary_text:query
      ?secondary_text:message
      ~selected_ids
      ~items:metadata
      ~on_selection_changed
      ?on_text_changed:on_query_changed
      []
  ;;
end

module Date = struct
  type t =
    { year : int
    ; month : int
    ; day : int
    }

  let is_leap year = year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0)

  let create ~year ~month ~day =
    if year < 1 || year > 9999
    then invalid_arg "Material.Date.create: year must be in 1..9999";
    if month < 1 || month > 12
    then invalid_arg "Material.Date.create: month must be in 1..12";
    let days =
      [| 31; (if is_leap year then 29 else 28); 31; 30; 31; 30; 31; 31; 30; 31; 30; 31 |]
    in
    if day < 1 || day > days.(month - 1)
    then invalid_arg "Material.Date.create: day is outside the month";
    { year; month; day }
  ;;

  let compare left right =
    Stdlib.compare (left.year, left.month, left.day) (right.year, right.month, right.day)
  ;;

  let encode value = Printf.sprintf "%04d-%02d-%02d" value.year value.month value.day
end

module Date_picker = struct
  type mode =
    | Day
    | Year

  let calendar
        ?key
        ?current
        ?(mode = Day)
        ?(selectable_dates = [])
        ~selected
        ~first
        ~last
        ~on_select
        ()
    =
    if Date.compare first last > 0
    then invalid_arg "Material.Date_picker.calendar: bounds are reversed";
    if Date.compare selected first < 0 || Date.compare selected last > 0
    then invalid_arg "Material.Date_picker.calendar: selected date is outside bounds";
    Option.iter
      (fun value ->
         if Date.compare value first < 0 || Date.compare value last > 0
         then invalid_arg "Material.Date_picker.calendar: current date is outside bounds")
      current;
    List.iter
      (fun value ->
         if Date.compare value first < 0 || Date.compare value last > 0
         then
           invalid_arg "Material.Date_picker.calendar: selectable date is outside bounds")
      selectable_dates;
    let selectable_dates = List.sort_uniq Date.compare selectable_dates in
    if
      (not (List.is_empty selectable_dates))
      && not (List.exists (fun date -> Date.compare date selected = 0) selectable_dates)
    then invalid_arg "Material.Date_picker.calendar: selected date is not selectable";
    let item kind id date =
      fst (expressive_item ~kind ~id ~label:(Date.encode date) [])
    in
    let items =
      [ item 0 0L first; item 1 1L last ]
      @ Option.to_list (Option.map (item 2 2L) current)
      @ List.mapi
          (fun index date -> item 3 (Int64.of_int (index + 3)) date)
          selectable_dates
    in
    expressive
      ?key
      ~component:5
      ~variant:
        (match mode with
         | Day -> 0
         | Year -> 1)
      ~primary_text:(Date.encode selected)
      ~items
      ~on_civil_date_changed:on_select
      []
  ;;
end

module Time = struct
  type t =
    { hour : int
    ; minute : int
    }

  let create ~hour ~minute =
    if hour < 0 || hour > 23
    then invalid_arg "Material.Time.create: hour must be in 0..23";
    if minute < 0 || minute > 59
    then invalid_arg "Material.Time.create: minute must be in 0..59";
    { hour; minute }
  ;;

  let encode value = Printf.sprintf "%02d:%02d" value.hour value.minute
end

module Time_picker = struct
  type format =
    | Hour_12
    | Hour_24

  let dial ?key ?(format = Hour_24) ~value ~on_changed () =
    expressive
      ?key
      ~component:6
      ~variant:
        (match format with
         | Hour_12 -> 0
         | Hour_24 -> 1)
      ~primary_text:(Time.encode value)
      ~on_civil_time_changed:on_changed
      []
  ;;
end

module Carousel = struct
  type layout =
    | Hero
    | Contained
    | Uncontained

  type hero_alignment =
    | Start
    | Center
    | End

  type item =
    { id : int64
    ; child : Widget.t
    }

  let item ~id child = { id; child }

  let create
        ?key
        ?(layout = Hero)
        ?(axis = Layout.Axis.Horizontal)
        ?(hero_alignment = Center)
        ~on_select
        ~on_layout_changed
        items
        ()
    =
    validate_items "Material.Carousel.create" (List.map (fun item -> item.id, ()) items);
    let metadata =
      List.map
        (fun item -> fst (expressive_item ~id:item.id ~label:"" [ item.child ]))
        items
    in
    let flags =
      Int64.of_int
        ((match axis with
          | Layout.Axis.Horizontal -> 0
          | Vertical -> 1)
         lor ((match hero_alignment with
               | Start -> 0
               | Center -> 1
               | End -> 2)
              lsl 1))
    in
    expressive
      ?key
      ~component:7
      ~variant:
        (match layout with
         | Hero -> 0
         | Contained -> 1
         | Uncontained -> 2)
      ~flags
      ~items:metadata
      ~on_select
      ~on_active_changed:on_layout_changed
      (List.map (fun item -> item.child) items)
  ;;
end

module Card_list = struct
  type item =
    { id : int64
    ; child : Widget.t
    }

  let item ~id child = { id; child }

  let create variant ?key ~on_select items () =
    validate_items "Material.Card_list" (List.map (fun item -> item.id, ()) items);
    expressive
      ?key
      ~component:8
      ~variant
      ~items:
        (List.map
           (fun item -> fst (expressive_item ~id:item.id ~label:"" [ item.child ]))
           items)
      ~on_select
      (List.map (fun item -> item.child) items)
  ;;

  let finite = create 0
  let scrollable = create 1

  let sliver ?key ~on_select items () =
    Widget.Sliver.box (create 2 ?key ~on_select items ())
  ;;
end

module Selection = struct
  let leading ?key ~id ~selected ~on_toggle ~unselected ~selected_child () =
    expressive
      ?key
      ~component:29
      ~flags:(if selected then 1L else 0L)
      ~items:
        [ fst (expressive_item ~id ~selected ~label:"" [ unselected; selected_child ]) ]
      ~on_select:on_toggle
      [ unselected; selected_child ]
  ;;

  let create
        ?key
        ?(idle = Widget.empty ())
        ?(actions = [])
        ?(show_select_all = true)
        ~item_ids
        ~selected_ids
        ~on_selection_changed
        body
    =
    ignore (reject_duplicate_ids "Material.Selection.create item IDs" item_ids);
    let selected_ids = List.sort_uniq Int64.compare selected_ids in
    List.iter
      (fun id ->
         if not (List.mem id item_ids)
         then invalid_arg "Material.Selection.create: selected ID must name an item")
      selected_ids;
    expressive
      ?key
      ~component:9
      ~flags:
        (Int64.of_int
           ((if show_select_all then 1 else 0) lor (List.length actions lsl 8)))
      ~selected_ids
      ~items:
        (List.map
           (fun id ->
              fst (expressive_item ~id ~selected:(List.mem id selected_ids) ~label:"" []))
           item_ids)
      ~on_selection_changed
      ((idle :: actions) @ [ body ])
  ;;
end

module Dismissible_list = struct
  type request_state =
    | Ready
    | Pending
    | Accepted
    | Rejected

  type item =
    { id : int64
    ; child : Widget.t
    }

  let item ~id child = { id; child }

  let create component ?key ~request_token ~request_state ~on_dismiss_request items () =
    validate_items "Material.Dismissible_list" (List.map (fun item -> item.id, ()) items);
    expressive
      ?key
      ~component
      ~variant:
        (match request_state with
         | Ready -> 0
         | Pending -> 1
         | Accepted -> 2
         | Rejected -> 3)
      ~secondary_text:(Int64.to_string request_token)
      ~items:
        (List.map
           (fun item -> fst (expressive_item ~id:item.id ~label:"" [ item.child ]))
           items)
      ~on_selection_changed:on_dismiss_request
      (List.map (fun item -> item.child) items)
  ;;

  let column = create 10
  let horizontal = create 11
end

module Expandable_list = struct
  type policy =
    | Multiple
    | Single

  type item =
    { id : int64
    ; header : string
    ; body : Widget.t
    }

  let item ~id ~header ~body () =
    require_nonempty "Material.Expandable_list.item header" header;
    { id; header; body }
  ;;

  let create layout ?key ?(policy = Multiple) ~expanded_ids ~on_expansion_changed items ()
    =
    validate_items "Material.Expandable_list" (List.map (fun item -> item.id, ()) items);
    let expanded_ids = List.sort Int64.compare expanded_ids in
    if policy = Single && List.length expanded_ids > 1
    then invalid_arg "Material.Expandable_list: single mode accepts at most one ID";
    expressive
      ?key
      ~component:12
      ~variant:
        (match policy with
         | Multiple -> 0
         | Single -> 1)
      ~flags:(Int64.of_int layout)
      ~selected_ids:expanded_ids
      ~items:
        (List.map
           (fun item ->
              fst
                (expressive_item
                   ~id:item.id
                   ~label:item.header
                   ~selected:(List.mem item.id expanded_ids)
                   [ item.body ]))
           items)
      ~on_selection_changed:on_expansion_changed
      (List.map (fun item -> item.body) items)
  ;;

  let finite = create 0
  let scrollable = create 1

  let sliver ?key ?policy ~expanded_ids ~on_expansion_changed items () =
    Widget.Sliver.box (create 2 ?key ?policy ~expanded_ids ~on_expansion_changed items ())
  ;;
end

module Bottom_sheet = struct
  let surface ?key ?(show_handle = true) child =
    expressive ?key ~component:13 ~flags:(if show_handle then 1L else 0L) [ child ]
  ;;
end

module Side_sheet = struct
  let surface ?key ~title ~body () = expressive ?key ~component:14 [ title; body ]
end

module App_bar = struct
  type search_suggestion =
    { id : int64
    ; label : string
    ; enabled : bool
    }

  let search_suggestion ~id ~label ?(enabled = true) () =
    require_nonempty "Material.App_bar.search_suggestion label" label;
    { id; label; enabled }
  ;;

  type sliver_variant =
    | Small
    | Medium
    | Large

  type sliver_shape =
    | Round
    | Square

  type sliver_density =
    | Regular
    | Compact

  let top
        ?key
        ?(center_title = false)
        ?leading
        ?(actions = [])
        ?(safe_area = true)
        ?semantic_label
        ~title
        ()
    =
    expressive
      ?key
      ~component:30
      ~flags:
        (Int64.of_int
           ((if center_title then 1 else 0)
            lor (if Option.is_some leading then 2 else 0)
            lor (if safe_area then 4 else 0)
            lor (List.length actions lsl 8)))
      ?primary_text:semantic_label
      (Option.to_list leading @ [ title ] @ actions)
  ;;

  let sliver
        ?key
        ?(pinned = true)
        ?(floating = false)
        ?(snap = false)
        ?(center_title = false)
        ?background_color
        ?foreground_color
        ?leading
        ?(actions = [])
        ?(variant = Medium)
        ?(shape = Round)
        ?(density = Regular)
        ?semantic_label
        ~title
        ()
    =
    Widget.Private.material_sliver_app_bar
      ?key
      ~pinned
      ~floating
      ~snap
      ~center_title
      ?background_color
      ?foreground_color
      ?leading
      ~actions
      ~variant:
        (match variant with
         | Small -> 0
         | Medium -> 1
         | Large -> 2)
      ~shape:
        (match shape with
         | Round -> 0
         | Square -> 1)
      ~density:
        (match density with
         | Regular -> 0
         | Compact -> 1)
      ?semantic_label
      ~title
      ()
  ;;

  let bottom ?key ?floating_action_button ?(safe_area = true) ~actions () =
    expressive
      ?key
      ~component:15
      ~flags:
        (Int64.logor
           (if safe_area then 1L else 0L)
           (if Option.is_some floating_action_button then 2L else 0L))
      (actions @ Option.to_list floating_action_button)
  ;;

  let search
        ?key
        ?(full_screen = true)
        ?(center_title = false)
        ?leading
        ?(actions = [])
        ?bar_leading
        ?(bar_trailing = [])
        ?hint_text
        ?enabled
        ?keyboard_type
        ?input_action
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
        ?on_open
        ?on_close
        ~on_select
        suggestions
        ()
    =
    validate_items
      "Material.App_bar.search"
      (List.map (fun suggestion -> suggestion.id, ()) suggestions);
    let flags =
      (if center_title then 1 else 0)
      lor (if full_screen then 2 else 0)
      lor (if Option.is_some leading then 4 else 0)
      lor (if Option.is_some bar_leading then 8 else 0)
      lor (List.length actions lsl 8)
      lor (List.length bar_trailing lsl 16)
    in
    let text_input =
      expressive_text_input
        ?enabled
        ?keyboard_type
        ?input_action
        ?max_utf8_bytes
        ~session_id
        ~document_revision
        ~accepted_local_revision
        ~update_mode
        ~value
        ()
    in
    expressive
      ?key
      ~component:28
      ~flags:(Int64.of_int flags)
      ?primary_text:hint_text
      ~text_input
      ~items:
        (List.map
           (fun suggestion ->
              fst
                (expressive_item
                   ~id:suggestion.id
                   ~label:suggestion.label
                   ~enabled:suggestion.enabled
                   []))
           suggestions)
      ~on_select
      ~on_text_edit:on_edit
      ~on_text_submit:on_submit
      ~on_focus_changed
      ?on_limit_reached
      ?on_search_opened:on_open
      ?on_search_closed:on_close
      (Option.to_list leading @ actions @ Option.to_list bar_leading @ bar_trailing)
  ;;
end

module Tabs = struct
  type variant =
    | Primary
    | Secondary

  type tab =
    { id : int64
    ; label : string
    ; icon : Widget.t option
    }

  let tab ~id ~label ?icon () =
    require_nonempty "Material.Tabs.tab label" label;
    { id; label; icon }
  ;;

  let create ?key ?(variant = Primary) ~selected_id ~on_select tabs () =
    if List.length tabs < 2
    then invalid_arg "Material.Tabs.create: at least two tabs are required";
    validate_items "Material.Tabs.create" (List.map (fun tab -> tab.id, ()) tabs);
    if not (List.exists (fun tab -> Int64.equal tab.id selected_id) tabs)
    then invalid_arg "Material.Tabs.create: selected_id must name a tab";
    let encoded =
      List.map
        (fun tab ->
           expressive_item
             ~id:tab.id
             ~label:tab.label
             ~selected:(Int64.equal tab.id selected_id)
             (Option.to_list tab.icon))
        tabs
    in
    expressive
      ?key
      ~component:16
      ~variant:
        (match variant with
         | Primary -> 0
         | Secondary -> 1)
      ~selected_ids:[ selected_id ]
      ~items:(List.map fst encoded)
      ~on_select
      (List.concat_map snd encoded)
  ;;
end

module Navigation_rail = struct
  type modality =
    | Standard
    | Modal

  type destination =
    { id : int64
    ; icon : Widget.t
    ; label : string
    }

  type section = destination list

  type fab =
    { id : int64
    ; icon : Widget.t
    ; label : string
    ; enabled : bool
    }

  let destination ~id ~icon ~label () =
    require_nonempty "Material.Navigation_rail.destination label" label;
    { id; icon; label }
  ;;

  let section destinations =
    if List.is_empty destinations
    then invalid_arg "Material.Navigation_rail.section: destinations must not be empty";
    destinations
  ;;

  let fab ~id ~icon ~label ?(enabled = true) () =
    require_nonempty "Material.Navigation_rail.fab label" label;
    { id; icon; label; enabled }
  ;;

  let create
        ?key
        ?(modality = Standard)
        ?trailing
        ?(trailing_at_bottom = true)
        ?fab
        ~expanded
        ~selected_id
        ~on_select
        ~on_expanded_changed
        (sections : section list)
        ()
    =
    if List.is_empty sections
    then invalid_arg "Material.Navigation_rail.create: sections must not be empty";
    let destinations = List.concat sections in
    validate_items
      "Material.Navigation_rail.create"
      (List.map (fun (item : destination) -> item.id, ()) destinations);
    let encoded =
      List.mapi
        (fun section_index section ->
           List.map
             (fun (item : destination) ->
                expressive_item
                  ~kind:section_index
                  ~id:item.id
                  ~label:item.label
                  ~selected:(Int64.equal item.id selected_id)
                  [ item.icon ])
             section)
        sections
      |> List.concat
    in
    let flags =
      (if expanded then 1 else 0)
      lor (if modality = Modal then 2 else 0)
      lor (if Option.is_some trailing then 4 else 0)
      lor (if Option.is_some fab then 8 else 0)
      lor (if trailing_at_bottom then 16 else 0)
      lor
      if
        match fab with
        | Some fab -> fab.enabled
        | None -> false
      then 32
      else 0
    in
    expressive
      ?key
      ~component:17
      ~flags:(Int64.of_int flags)
      ?primary_text:(Option.map (fun (fab : fab) -> fab.label) fab)
      ?secondary_text:(Option.map (fun (fab : fab) -> Int64.to_string fab.id) fab)
      ~selected_ids:[ selected_id ]
      ~items:(List.map fst encoded)
      ~on_select
      ~on_value_changed:on_expanded_changed
      (List.concat_map snd encoded
       @ Option.to_list trailing
       @ Option.to_list (Option.map (fun (fab : fab) -> fab.icon) fab))
  ;;
end

module Navigation_drawer = struct
  type destination =
    { id : int64
    ; icon : Widget.t
    ; label : string
    }

  let destination ~id ~icon ~label () =
    require_nonempty "Material.Navigation_drawer.destination label" label;
    { id; icon; label }
  ;;

  let create ?key ~headline ~selected_id ~on_select destinations () =
    require_nonempty "Material.Navigation_drawer headline" headline;
    validate_items
      "Material.Navigation_drawer.create"
      (List.map (fun item -> item.id, ()) destinations);
    let encoded =
      List.map
        (fun item ->
           expressive_item
             ~id:item.id
             ~label:item.label
             ~selected:(Int64.equal item.id selected_id)
             [ item.icon ])
        destinations
    in
    expressive
      ?key
      ~component:18
      ~primary_text:headline
      ~selected_ids:[ selected_id ]
      ~items:(List.map fst encoded)
      ~on_select
      (List.concat_map snd encoded)
  ;;
end

module Toolbar = struct
  type placement =
    | Floating
    | Docked

  type icon =
    | Add
    | Edit
    | Delete
    | Favorite
    | More
    | Search
    | Share

  type action =
    { id : int64
    ; icon : icon
    ; label : string option
    ; enabled : bool
    }

  type fab =
    { id : int64
    ; icon : Widget.t
    ; label : string
    ; enabled : bool
    }

  let action ~id ~icon ?label ?(enabled = true) () =
    Option.iter (require_nonempty "Material.Toolbar.action label") label;
    ({ id; icon; label; enabled } : action)
  ;;

  let fab ~id ~icon ~label ?(enabled = true) () =
    require_nonempty "Material.Toolbar.fab label" label;
    ({ id; icon; label; enabled } : fab)
  ;;

  let create
        ?key
        ?(placement = Floating)
        ?(axis = Layout.Axis.Horizontal)
        ?(max_inline_actions = 4)
        ?fab
        ~expanded
        ~active_action_id
        ~on_action
        ~on_expanded_changed
        ~on_active_action_changed
        actions
        ()
    =
    if max_inline_actions < 0 || max_inline_actions > 255
    then invalid_arg "Material.Toolbar.create: max_inline_actions must be in 0..255";
    validate_items
      "Material.Toolbar.create"
      (List.map (fun (item : action) -> item.id, ()) actions);
    Option.iter
      (fun id ->
         if not (List.exists (fun (item : action) -> Int64.equal item.id id) actions)
         then invalid_arg "Material.Toolbar.create: active ID must name an action")
      active_action_id;
    Option.iter
      (fun (fab : fab) ->
         if List.exists (fun (item : action) -> Int64.equal item.id fab.id) actions
         then invalid_arg "Material.Toolbar.create: FAB ID must be unique")
      fab;
    let encoded =
      List.map
        (fun (item : action) ->
           let kind =
             match item.icon with
             | Add -> 0
             | Edit -> 1
             | Delete -> 2
             | Favorite -> 3
             | More -> 4
             | Search -> 5
             | Share -> 6
           in
           expressive_item
             ~kind
             ~id:item.id
             ~label:(Option.value item.label ~default:"")
             ~enabled:item.enabled
             ~selected:(Option.equal Int64.equal active_action_id (Some item.id))
             [])
        actions
    in
    expressive
      ?key
      ~component:19
      ~variant:
        (match placement with
         | Floating -> 0
         | Docked -> 1)
      ~flags:
        (Int64.of_int
           ((match axis with
             | Layout.Axis.Horizontal -> 0
             | Vertical -> 1)
            lor (if expanded then 2 else 0)
            lor (if Option.is_some fab then 4 else 0)
            lor (if Option.fold ~none:false ~some:(fun (fab : fab) -> fab.enabled) fab
                 then 8
                 else 0)
            lor (max_inline_actions lsl 8)))
      ?primary_text:(Option.map (fun (fab : fab) -> fab.label) fab)
      ?secondary_text:(Option.map (fun (fab : fab) -> Int64.to_string fab.id) fab)
      ~selected_ids:(Option.to_list active_action_id)
      ~items:(List.map fst encoded)
      ~on_select:on_action
      ~on_active_changed:on_active_action_changed
      ~on_value_changed:on_expanded_changed
      (List.concat_map snd encoded
       @ Option.to_list (Option.map (fun (fab : fab) -> fab.icon) fab))
  ;;
end

type badge_alignment =
  | Top_left
  | Top_center
  | Top_right

let badge ?key ?(alignment = Top_right) ?count child =
  Option.iter
    (fun value ->
       if value < 0 then invalid_arg "Material.badge: count must be non-negative")
    count;
  expressive
    ?key
    ~component:21
    ~variant:
      (match alignment with
       | Top_left -> 0
       | Top_center -> 1
       | Top_right -> 2)
    ?value:(Option.map Float.of_int count)
    [ child ]
;;

type loading_indicator_variant =
  | Uncontained
  | Contained

let loading_indicator ?key ?(variant = Uncontained) ?progress () =
  Option.iter
    (fun value ->
       if not (Float.is_finite value)
       then invalid_arg "Material.loading_indicator: progress must be finite")
    progress;
  expressive
    ?key
    ~component:22
    ~variant:
      (match variant with
       | Uncontained -> 0
       | Contained -> 1)
    ?value:progress
    []
;;

module Refresh_indicator = struct
  type variant =
    | Expressive
    | Contained
    | Material
    | Adaptive
    | No_spinner

  type request_state =
    | Ready
    | Pending
    | Completed

  let create
        ?key
        ?(variant = Expressive)
        ?show_token
        ~request_token
        ~request_state
        ~on_refresh_request
        child
    =
    expressive
      ?key
      ~component:23
      ~variant:
        (match variant with
         | Expressive -> 0
         | Contained -> 1
         | Material -> 2
         | Adaptive -> 3
         | No_spinner -> 4)
      ?primary_text:(Option.map Int64.to_string show_token)
      ~flags:
        (Int64.of_int
           (match request_state with
            | Ready -> 0
            | Pending -> 1
            | Completed -> 2))
      ~secondary_text:(Int64.to_string request_token)
      ~on_selection_changed:on_refresh_request
      [ child ]
  ;;
end

module Search_anchor = struct
  type presentation =
    | Full_screen
    | Docked

  type suggestion =
    { id : int64
    ; label : string
    ; enabled : bool
    }

  let suggestion ~id ~label ?(enabled = true) () =
    require_nonempty "Material.Search_anchor.suggestion label" label;
    { id; label; enabled }
  ;;

  let create
        ?key
        ?(presentation = Full_screen)
        ?bar_leading
        ?(bar_trailing = [])
        ?hint_text
        ?enabled
        ?keyboard_type
        ?input_action
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
        ?on_open
        ?on_close
        ~on_select
        suggestions
        ()
    =
    validate_items
      "Material.Search_anchor.create"
      (List.map (fun item -> item.id, ()) suggestions);
    let text_input =
      expressive_text_input
        ?enabled
        ?keyboard_type
        ?input_action
        ?max_utf8_bytes
        ~session_id
        ~document_revision
        ~accepted_local_revision
        ~update_mode
        ~value
        ()
    in
    expressive
      ?key
      ~component:24
      ~variant:
        (match presentation with
         | Full_screen -> 0
         | Docked -> 1)
      ~flags:
        (Int64.of_int
           ((if text_input.enabled then 1 else 0)
            lor (if Option.is_some bar_leading then 2 else 0)
            lor (List.length bar_trailing lsl 8)))
      ?primary_text:hint_text
      ~text_input
      ~items:
        (List.map
           (fun item ->
              fst (expressive_item ~id:item.id ~label:item.label ~enabled:item.enabled []))
           suggestions)
      ~on_select
      ~on_text_edit:on_edit
      ~on_text_submit:on_submit
      ~on_focus_changed
      ?on_limit_reached
      ?on_search_opened:on_open
      ?on_search_closed:on_close
      (Option.to_list bar_leading @ bar_trailing)
  ;;
end
