type page_transition =
  | None
  | Fade
  | Slide

module Modal_bottom_sheet = struct
  module Detent = struct
    type t =
      | Medium
      | Large
  end

  module Handle_semantics = struct
    type t =
      { label : string
      ; medium_value : string
      ; large_value : string
      }

    let require_nonempty name value =
      if String.length (String.trim value) = 0
      then
        invalid_arg
          (Printf.sprintf
             "Navigation.Modal_bottom_sheet.Handle_semantics.create: %s must not be empty"
             name)
    ;;

    let create ~label ~medium_value ~large_value =
      require_nonempty "label" label;
      require_nonempty "medium_value" medium_value;
      require_nonempty "large_value" large_value;
      { label; medium_value; large_value }
    ;;

    module Private = struct
      type view = t =
        { label : string
        ; medium_value : string
        ; large_value : string
        }

      let view t = t
    end
  end

  module Detents = struct
    type t =
      { detents : Detent.t list
      ; initial : Detent.t
      ; dismiss_on_drag : bool
      ; semantics : Handle_semantics.t
      }

    let create ?initial ?(dismiss_on_drag = true) ~semantics detents =
      let has_medium = List.mem Detent.Medium detents in
      let has_large = List.mem Detent.Large detents in
      if detents = []
      then
        invalid_arg
          "Navigation.Modal_bottom_sheet.Detents.create: detents must not be empty";
      if List.length detents <> Bool.to_int has_medium + Bool.to_int has_large
      then
        invalid_arg "Navigation.Modal_bottom_sheet.Detents.create: detents must be unique";
      let detents =
        match has_medium, has_large with
        | true, true -> [ Detent.Medium; Detent.Large ]
        | true, false -> [ Detent.Medium ]
        | false, true -> [ Detent.Large ]
        | false, false -> assert false
      in
      let initial = Option.value initial ~default:(List.hd detents) in
      if not (List.mem initial detents)
      then
        invalid_arg
          "Navigation.Modal_bottom_sheet.Detents.create: initial must be one of detents";
      { detents; initial; dismiss_on_drag; semantics }
    ;;

    module Private = struct
      type view = t =
        { detents : Detent.t list
        ; initial : Detent.t
        ; dismiss_on_drag : bool
        ; semantics : Handle_semantics.t
        }

      let view t = t
    end
  end

  module Sizing = struct
    type t =
      | Content_bounded
      | Scroll_controlled
      | Detented of Detents.t
  end

  type t =
    { barrier_dismissible : bool
    ; barrier_color : Style.Color.t option
    ; barrier_label : string option
    ; sizing : Sizing.t
    ; use_safe_area : bool
    ; request_focus : bool
    ; transition_duration_ms : int
    ; reverse_transition_duration_ms : int
    }

  let validate_duration label value =
    if value < 0 || Int64.compare (Int64.of_int value) 0xffff_ffffL > 0
    then
      invalid_arg
        (Printf.sprintf
           "Navigation.Modal_bottom_sheet.create: %s must fit an unsigned 32-bit integer"
           label)
  ;;

  let create
        ?(barrier_dismissible = true)
        ?barrier_color
        ?barrier_label
        ?(sizing = Sizing.Content_bounded)
        ?(use_safe_area = false)
        ?(request_focus = true)
        ?(transition_duration_ms = 250)
        ?(reverse_transition_duration_ms = 200)
        ()
    =
    validate_duration "transition_duration_ms" transition_duration_ms;
    validate_duration "reverse_transition_duration_ms" reverse_transition_duration_ms;
    { barrier_dismissible
    ; barrier_color
    ; barrier_label
    ; sizing
    ; use_safe_area
    ; request_focus
    ; transition_duration_ms
    ; reverse_transition_duration_ms
    }
  ;;

  module Private = struct
    type view = t =
      { barrier_dismissible : bool
      ; barrier_color : Style.Color.t option
      ; barrier_label : string option
      ; sizing : Sizing.t
      ; use_safe_area : bool
      ; request_focus : bool
      ; transition_duration_ms : int
      ; reverse_transition_duration_ms : int
      }

    let view t = t
  end
end

module Modal_dialog = struct
  type t =
    { barrier_dismissible : bool
    ; barrier_color : Style.Color.t option
    ; barrier_label : string option
    ; use_safe_area : bool
    ; request_focus : bool
    ; transition_duration_ms : int
    ; reverse_transition_duration_ms : int
    }

  let validate_duration label value =
    if value < 0 || Int64.compare (Int64.of_int value) 0xffff_ffffL > 0
    then
      invalid_arg
        (Printf.sprintf
           "Navigation.Modal_dialog.create: %s must fit an unsigned 32-bit integer"
           label)
  ;;

  let create
        ?(barrier_dismissible = true)
        ?barrier_color
        ?barrier_label
        ?(use_safe_area = true)
        ?(request_focus = true)
        ?(transition_duration_ms = 150)
        ?(reverse_transition_duration_ms = 75)
        ()
    =
    validate_duration "transition_duration_ms" transition_duration_ms;
    validate_duration "reverse_transition_duration_ms" reverse_transition_duration_ms;
    { barrier_dismissible
    ; barrier_color
    ; barrier_label
    ; use_safe_area
    ; request_focus
    ; transition_duration_ms
    ; reverse_transition_duration_ms
    }
  ;;

  module Private = struct
    type view = t =
      { barrier_dismissible : bool
      ; barrier_color : Style.Color.t option
      ; barrier_label : string option
      ; use_safe_area : bool
      ; request_focus : bool
      ; transition_duration_ms : int
      ; reverse_transition_duration_ms : int
      }

    let view t = t
  end
end

module Modal_side_sheet = Modal_dialog

type page_presentation =
  | Standard of page_transition
  | Modal_bottom_sheet of Modal_bottom_sheet.t
  | Modal_dialog of Modal_dialog.t
  | Modal_side_sheet of Modal_side_sheet.t

type overlay_alignment =
  | Top_start
  | Top_center
  | Top_end
  | Center_start
  | Center
  | Center_end
  | Bottom_start
  | Bottom_center
  | Bottom_end
