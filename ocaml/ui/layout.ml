module Axis = struct
  type t =
    | Horizontal
    | Vertical
end

module Alignment = struct
  type t =
    | Top_start
    | Top_center
    | Top_end
    | Center_start
    | Center
    | Center_end
    | Bottom_start
    | Bottom_center
    | Bottom_end
end

module Box_constraints = struct
  type t =
    { min_width : float
    ; max_width : float option
    ; min_height : float
    ; max_height : float option
    }

  let finite_nonnegative label value =
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then
      invalid_arg
        (Printf.sprintf "Layout.Box_constraints.%s must be finite and non-negative" label);
    value
  ;;

  let validate_maximum minimum = function
    | Some maximum when Float.compare minimum maximum > 0 ->
      invalid_arg "Layout.Box_constraints.create: minimum exceeds maximum"
    | None | Some _ -> ()
  ;;

  let create ?(min_width = 0.) ?max_width ?(min_height = 0.) ?max_height () =
    let min_width = finite_nonnegative "min_width" min_width in
    let max_width = Option.map (finite_nonnegative "max_width") max_width in
    let min_height = finite_nonnegative "min_height" min_height in
    let max_height = Option.map (finite_nonnegative "max_height") max_height in
    validate_maximum min_width max_width;
    validate_maximum min_height max_height;
    { min_width; max_width; min_height; max_height }
  ;;

  module Private = struct
    let to_values t = t.min_width, t.max_width, t.min_height, t.max_height
  end
end

module Edge_insets = struct
  type t =
    { left : float
    ; top : float
    ; right : float
    ; bottom : float
    }

  let validate label value =
    match Float.classify_float value with
    | FP_normal | FP_subnormal | FP_zero ->
      if Float.compare value 0. < 0
      then invalid_arg (Printf.sprintf "Layout.Edge_insets.%s must be non-negative" label);
      value
    | FP_infinite | FP_nan ->
      invalid_arg (Printf.sprintf "Layout.Edge_insets.%s must be finite" label)
  ;;

  let only ?(left = 0.) ?(top = 0.) ?(right = 0.) ?(bottom = 0.) () =
    { left = validate "left" left
    ; top = validate "top" top
    ; right = validate "right" right
    ; bottom = validate "bottom" bottom
    }
  ;;

  let all value = only ~left:value ~top:value ~right:value ~bottom:value ()

  let symmetric ?(horizontal = 0.) ?(vertical = 0.) () =
    only ~left:horizontal ~top:vertical ~right:horizontal ~bottom:vertical ()
  ;;

  module Private = struct
    let to_sides t = t.left, t.top, t.right, t.bottom
  end
end
