module Brightness = struct
  type t =
    | Light
    | Dark
end

module Color = struct
  type t = int32

  let component label value =
    if value < 0 || value > 255
    then invalid_arg (Printf.sprintf "Style.Color.%s must be between 0 and 255" label);
    value
  ;;

  let argb ~alpha ~red ~green ~blue =
    let alpha = component "alpha" alpha in
    let red = component "red" red in
    let green = component "green" green in
    let blue = component "blue" blue in
    Int32.(
      logor
        (shift_left (of_int alpha) 24)
        (logor
           (shift_left (of_int red) 16)
           (logor (shift_left (of_int green) 8) (of_int blue))))
  ;;

  let rgb ~red ~green ~blue = argb ~alpha:255 ~red ~green ~blue

  module Private = struct
    let to_argb32 t = t
  end
end

module Font_weight = struct
  type t =
    | Normal
    | Medium
    | Semi_bold
    | Bold
end

module Text_align = struct
  type t =
    | Start
    | Center
    | End
end

module Text_overflow = struct
  type t =
    | Clip
    | Fade
    | Ellipsis
    | Visible
end

module Text_style = struct
  type t =
    { font_size : float option
    ; font_weight : Font_weight.t option
    ; line_height : float option
    ; color : Color.t option
    }

  let positive_finite label = function
    | None -> None
    | Some value ->
      if (not (Float.is_finite value)) || Float.compare value 0. <= 0
      then
        invalid_arg
          (Printf.sprintf "Style.Text_style.%s must be finite and positive" label);
      Some value
  ;;

  let create ?font_size ?font_weight ?line_height ?color () =
    { font_size = positive_finite "font_size" font_size
    ; font_weight
    ; line_height = positive_finite "line_height" line_height
    ; color
    }
  ;;

  module Private = struct
    type view =
      { font_size : float option
      ; font_weight : Font_weight.t option
      ; line_height : float option
      ; color : int32 option
      }

    let view (t : t) : view =
      { font_size = t.font_size
      ; font_weight = t.font_weight
      ; line_height = t.line_height
      ; color = Option.map Color.Private.to_argb32 t.color
      }
    ;;
  end
end

module Image_fit = struct
  type t =
    | Fill
    | Contain
    | Cover
    | Fit_width
    | Fit_height
    | None
    | Scale_down
end

module Clip = struct
  type t =
    | Hard_edge
    | Anti_alias
    | Anti_alias_with_save_layer
end

module Decoration = struct
  type t =
    { background : Color.t option
    ; border_radius : float
    }

  let create ?background ?(border_radius = 0.) () =
    if (not (Float.is_finite border_radius)) || Float.compare border_radius 0. < 0
    then invalid_arg "Style.Decoration.border_radius must be finite and non-negative";
    { background; border_radius }
  ;;

  module Private = struct
    let to_values t = Option.map Color.Private.to_argb32 t.background, t.border_radius
  end
end

module Transform = struct
  type t = float array

  let matrix4 values =
    if Array.length values <> 16
    then invalid_arg "Style.Transform.matrix4 requires exactly 16 values";
    Array.iter
      (fun value ->
         if not (Float.is_finite value)
         then invalid_arg "Style.Transform.matrix4 values must be finite")
      values;
    Array.copy values
  ;;

  let identity =
    matrix4 [| 1.; 0.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 0.; 1. |]
  ;;

  let scale ?(x = 1.) ?(y = 1.) () =
    matrix4 [| x; 0.; 0.; 0.; 0.; y; 0.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 0.; 1. |]
  ;;

  let translate ?(x = 0.) ?(y = 0.) () =
    matrix4 [| 1.; 0.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 0.; 1.; 0.; x; y; 0.; 1. |]
  ;;

  module Private = struct
    let to_array = Array.copy
  end
end
