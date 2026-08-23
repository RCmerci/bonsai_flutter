module Color_scheme = struct
  type dynamic_variant =
    | Tonal_spot
    | Fidelity
    | Content
    | Monochrome
    | Neutral
    | Vibrant
    | Expressive

  type t =
    { color : Style.Color.t
    ; variant : dynamic_variant
    ; contrast_level : float
    }

  let from_seed ~color ?(variant = Tonal_spot) ?(contrast_level = 0.) () =
    if
      (not (Float.is_finite contrast_level))
      || contrast_level < -1.
      || contrast_level > 1.
    then
      invalid_arg "Theme.Color_scheme.contrast_level must be finite and between -1 and 1";
    { color; variant; contrast_level }
  ;;
end

module Typography = struct
  type t =
    { font_family : string option
    ; font_family_fallback : string list
    ; display_large : Style.Text_style.t option
    ; display_medium : Style.Text_style.t option
    ; display_small : Style.Text_style.t option
    ; headline_large : Style.Text_style.t option
    ; headline_medium : Style.Text_style.t option
    ; headline_small : Style.Text_style.t option
    ; title_large : Style.Text_style.t option
    ; title_medium : Style.Text_style.t option
    ; title_small : Style.Text_style.t option
    ; body_large : Style.Text_style.t option
    ; body_medium : Style.Text_style.t option
    ; body_small : Style.Text_style.t option
    ; label_large : Style.Text_style.t option
    ; label_medium : Style.Text_style.t option
    ; label_small : Style.Text_style.t option
    }

  let validate_font_name name =
    if String.length (String.trim name) = 0 || String.contains name '\000'
    then invalid_arg "Theme.Typography font names must be non-empty and contain no NUL"
  ;;

  let material
        ?font_family
        ?(font_family_fallback = [])
        ?display_large
        ?display_medium
        ?display_small
        ?headline_large
        ?headline_medium
        ?headline_small
        ?title_large
        ?title_medium
        ?title_small
        ?body_large
        ?body_medium
        ?body_small
        ?label_large
        ?label_medium
        ?label_small
        ()
    =
    Option.iter validate_font_name font_family;
    if List.length font_family_fallback > 16
    then invalid_arg "Theme.Typography supports at most 16 fallback font families";
    List.iter validate_font_name font_family_fallback;
    { font_family
    ; font_family_fallback
    ; display_large
    ; display_medium
    ; display_small
    ; headline_large
    ; headline_medium
    ; headline_small
    ; title_large
    ; title_medium
    ; title_small
    ; body_large
    ; body_medium
    ; body_small
    ; label_large
    ; label_medium
    ; label_small
    }
  ;;
end

module Shape = struct
  type t =
    { extra_small : float
    ; small : float
    ; medium : float
    ; large : float
    ; extra_large : float
    }

  let radius label value =
    if (not (Float.is_finite value)) || value < 0.
    then
      invalid_arg (Printf.sprintf "Theme.Shape.%s must be finite and non-negative" label);
    value
  ;;

  let create
        ?(extra_small = 4.)
        ?(small = 8.)
        ?(medium = 12.)
        ?(large = 16.)
        ?(extra_large = 28.)
        ()
    =
    { extra_small = radius "extra_small" extra_small
    ; small = radius "small" small
    ; medium = radius "medium" medium
    ; large = radius "large" large
    ; extra_large = radius "extra_large" extra_large
    }
  ;;
end

type visual_density =
  | Adaptive
  | Standard
  | Comfortable
  | Compact

type tap_target_size =
  | Padded
  | Shrink_wrap

type data =
  { brightness : Style.Brightness.t
  ; color_scheme : Color_scheme.t
  ; typography : Typography.t
  ; shape : Shape.t
  ; visual_density : visual_density
  ; tap_target_size : tap_target_size
  }

let material
      ~brightness
      ~color_scheme
      ?(typography = Typography.material ())
      ?(shape = Shape.create ())
      ?(visual_density = Adaptive)
      ?(tap_target_size = Padded)
      ()
  =
  { brightness; color_scheme; typography; shape; visual_density; tap_target_size }
;;

type mode =
  | System
  | Light
  | Dark

type application =
  { mode : mode
  ; light : data
  ; dark : data
  ; high_contrast_light : data option
  ; high_contrast_dark : data option
  }

let expect_brightness label expected data =
  if data.brightness <> expected
  then
    invalid_arg (Printf.sprintf "Theme.application %s has inconsistent brightness" label)
;;

let application ~mode ~light ~dark ?high_contrast_light ?high_contrast_dark () =
  expect_brightness "light" Style.Brightness.Light light;
  expect_brightness "dark" Style.Brightness.Dark dark;
  Option.iter
    (expect_brightness "high_contrast_light" Style.Brightness.Light)
    high_contrast_light;
  Option.iter
    (expect_brightness "high_contrast_dark" Style.Brightness.Dark)
    high_contrast_dark;
  { mode; light; dark; high_contrast_light; high_contrast_dark }
;;

module Private = struct
  type color_scheme_view =
    { seed_argb : int32
    ; variant : Color_scheme.dynamic_variant
    ; contrast_level : float
    }

  type typography_view =
    { font_family : string option
    ; font_family_fallback : string list
    ; display_large : Style.Text_style.Private.view option
    ; display_medium : Style.Text_style.Private.view option
    ; display_small : Style.Text_style.Private.view option
    ; headline_large : Style.Text_style.Private.view option
    ; headline_medium : Style.Text_style.Private.view option
    ; headline_small : Style.Text_style.Private.view option
    ; title_large : Style.Text_style.Private.view option
    ; title_medium : Style.Text_style.Private.view option
    ; title_small : Style.Text_style.Private.view option
    ; body_large : Style.Text_style.Private.view option
    ; body_medium : Style.Text_style.Private.view option
    ; body_small : Style.Text_style.Private.view option
    ; label_large : Style.Text_style.Private.view option
    ; label_medium : Style.Text_style.Private.view option
    ; label_small : Style.Text_style.Private.view option
    }

  type shape_view =
    { extra_small : float
    ; small : float
    ; medium : float
    ; large : float
    ; extra_large : float
    }

  type data_view =
    { brightness : Style.Brightness.t
    ; color_scheme : color_scheme_view
    ; typography : typography_view
    ; shape : shape_view
    ; visual_density : visual_density
    ; tap_target_size : tap_target_size
    }

  type application_view =
    { mode : mode
    ; light : data_view
    ; dark : data_view
    ; high_contrast_light : data_view option
    ; high_contrast_dark : data_view option
    }

  let view_text_style = Option.map Style.Text_style.Private.view

  let view_typography (t : Typography.t) : typography_view =
    { font_family = t.font_family
    ; font_family_fallback = t.font_family_fallback
    ; display_large = view_text_style t.display_large
    ; display_medium = view_text_style t.display_medium
    ; display_small = view_text_style t.display_small
    ; headline_large = view_text_style t.headline_large
    ; headline_medium = view_text_style t.headline_medium
    ; headline_small = view_text_style t.headline_small
    ; title_large = view_text_style t.title_large
    ; title_medium = view_text_style t.title_medium
    ; title_small = view_text_style t.title_small
    ; body_large = view_text_style t.body_large
    ; body_medium = view_text_style t.body_medium
    ; body_small = view_text_style t.body_small
    ; label_large = view_text_style t.label_large
    ; label_medium = view_text_style t.label_medium
    ; label_small = view_text_style t.label_small
    }
  ;;

  let view_data (d : data) : data_view =
    { brightness = d.brightness
    ; color_scheme =
        { seed_argb = Style.Color.Private.to_argb32 d.color_scheme.color
        ; variant = d.color_scheme.variant
        ; contrast_level = d.color_scheme.contrast_level
        }
    ; typography = view_typography d.typography
    ; shape =
        { extra_small = d.shape.extra_small
        ; small = d.shape.small
        ; medium = d.shape.medium
        ; large = d.shape.large
        ; extra_large = d.shape.extra_large
        }
    ; visual_density = d.visual_density
    ; tap_target_size = d.tap_target_size
    }
  ;;

  let view_application (a : application) : application_view =
    { mode = a.mode
    ; light = view_data a.light
    ; dark = view_data a.dark
    ; high_contrast_light = Option.map view_data a.high_contrast_light
    ; high_contrast_dark = Option.map view_data a.high_contrast_dark
    }
  ;;

  let equal_application = ( = )
end
