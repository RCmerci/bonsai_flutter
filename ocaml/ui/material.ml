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

let action_chip ?key ?(enabled = true) ?avatar ~on_press ~label () =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Action
    ~enabled
    ~selected:false
    ?avatar
    ~on_press
    ~label
    ()
;;

let filter_chip ?key ?(enabled = true) ?avatar ~selected ~on_selected ~label () =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Filter
    ~enabled
    ~selected
    ?avatar
    ~on_selected
    ~label
    ()
;;

let choice_chip ?key ?(enabled = true) ?avatar ~selected ~on_selected ~label () =
  Widget.Private.material_chip
    ?key
    ~variant:Widget.Private.Choice
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

let alert_dialog = Widget.Private.material_alert_dialog

let checkbox ?key ?enabled ~value ~on_changed () =
  Widget.Private.material_checkbox ?key ?enabled ~value ~on_changed ()
;;

let switch = Widget.Private.material_switch
let text_field = Widget.text_input
let list_tile = Widget.Private.material_list_tile
let divider = Widget.Private.material_divider
let card = Widget.Private.material_card
let circular_progress_indicator = Widget.Private.material_progress
