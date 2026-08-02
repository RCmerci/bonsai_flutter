module ID = Bonsai_flutter_spec.Id

module Role = struct
  type t =
    | Generic
    | Button
    | Link
    | Image
    | Header
    | Text_field
    | Checkbox
    | Switch
    | Slider

  let equal left right = left = right

  let to_string = function
    | Generic -> "generic"
    | Button -> "button"
    | Link -> "link"
    | Image -> "image"
    | Header -> "header"
    | Text_field -> "text_field"
    | Checkbox -> "checkbox"
    | Switch -> "switch"
    | Slider -> "slider"
  ;;
end

module Action = struct
  type t =
    | Tap
    | Long_press
    | Focus
    | Increase
    | Decrease
    | Copy
    | Cut
    | Paste
    | Dismiss

  let equal left right = left = right

  let to_wire_id = function
    | Tap -> ID.Input.Semantics_action_id.of_int64 1L
    | Long_press -> ID.Input.Semantics_action_id.of_int64 2L
    | Focus -> ID.Input.Semantics_action_id.of_int64 3L
    | Increase -> ID.Input.Semantics_action_id.of_int64 4L
    | Decrease -> ID.Input.Semantics_action_id.of_int64 5L
    | Copy -> ID.Input.Semantics_action_id.of_int64 6L
    | Cut -> ID.Input.Semantics_action_id.of_int64 7L
    | Paste -> ID.Input.Semantics_action_id.of_int64 8L
    | Dismiss -> ID.Input.Semantics_action_id.of_int64 9L
  ;;

  let of_wire_id id =
    match ID.Input.Semantics_action_id.to_int64 id with
    | 1L -> Some Tap
    | 2L -> Some Long_press
    | 3L -> Some Focus
    | 4L -> Some Increase
    | 5L -> Some Decrease
    | 6L -> Some Copy
    | 7L -> Some Cut
    | 8L -> Some Paste
    | 9L -> Some Dismiss
    | _ -> None
  ;;
end

type t =
  { label : string option
  ; hint : string option
  ; value : string option
  ; role : Role.t
  ; enabled : bool option
  ; selected : bool option
  ; checked : bool option
  ; focusable : bool option
  ; obscured : bool
  ; live_region : bool
  ; heading_level : int option
  ; sort_key : float option
  ; actions : Action.t list
  }

let role_to_wire = function
  | Role.Generic -> 0
  | Button -> 1
  | Link -> 2
  | Image -> 3
  | Header -> 4
  | Text_field -> 5
  | Checkbox -> 6
  | Switch -> 7
  | Slider -> 8
;;

let role_of_wire = function
  | 0 -> Some Role.Generic
  | 1 -> Some Button
  | 2 -> Some Link
  | 3 -> Some Image
  | 4 -> Some Header
  | 5 -> Some Text_field
  | 6 -> Some Checkbox
  | 7 -> Some Switch
  | 8 -> Some Slider
  | _ -> None
;;

let actions_to_bits actions =
  List.fold_left
    (fun bits action ->
       let shift =
         ID.Input.Semantics_action_id.to_int64 (Action.to_wire_id action)
         |> Int64.to_int
         |> fun id -> id - 1
       in
       bits lor (1 lsl shift))
    0
    actions
;;

let actions_of_bits bits =
  if bits land lnot 0x1ff <> 0
  then None
  else (
    let rec collect wire_id reversed =
      if wire_id > 9
      then Some (List.rev reversed)
      else (
        let reversed =
          if bits land (1 lsl (wire_id - 1)) = 0
          then reversed
          else (
            match
              Action.of_wire_id
                (ID.Input.Semantics_action_id.of_int64 (Int64.of_int wire_id))
            with
            | Some action -> action :: reversed
            | None -> reversed)
        in
        collect (wire_id + 1) reversed)
    in
    collect 1 [])
;;

let normalize_actions actions =
  match actions_of_bits (actions_to_bits actions) with
  | Some actions -> actions
  | None -> assert false
;;

let create
      ?label
      ?hint
      ?value
      ?(role = Role.Generic)
      ?enabled
      ?selected
      ?checked
      ?focusable
      ?(obscured = false)
      ?(live_region = false)
      ?heading_level
      ?sort_key
      ?(actions = [])
      ()
  =
  Option.iter
    (fun level ->
       if level < 1 || level > 6
       then invalid_arg "Semantics.create: heading_level must be between 1 and 6")
    heading_level;
  Option.iter
    (fun value ->
       if not (Float.is_finite value)
       then invalid_arg "Semantics.create: sort_key must be finite")
    sort_key;
  { label
  ; hint
  ; value
  ; role
  ; enabled
  ; selected
  ; checked
  ; focusable
  ; obscured
  ; live_region
  ; heading_level
  ; sort_key
  ; actions = normalize_actions actions
  }
;;

module Private = struct
  type view = t =
    { label : string option
    ; hint : string option
    ; value : string option
    ; role : Role.t
    ; enabled : bool option
    ; selected : bool option
    ; checked : bool option
    ; focusable : bool option
    ; obscured : bool
    ; live_region : bool
    ; heading_level : int option
    ; sort_key : float option
    ; actions : Action.t list
    }

  let view t = t
  let role_to_wire = role_to_wire
  let role_of_wire = role_of_wire
  let actions_to_bits = actions_to_bits
  let actions_of_bits = actions_of_bits
end
