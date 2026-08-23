(** Renderer-neutral Material theme tokens. *)

module Color_scheme : sig
  type dynamic_variant =
    | Tonal_spot
    | Fidelity
    | Content
    | Monochrome
    | Neutral
    | Vibrant
    | Expressive

  type t

  val from_seed
    :  color:Style.Color.t
    -> ?variant:dynamic_variant
    -> ?contrast_level:float
    -> unit
    -> t
end

module Typography : sig
  type t

  val material
    :  ?font_family:string
    -> ?font_family_fallback:string list
    -> ?display_large:Style.Text_style.t
    -> ?display_medium:Style.Text_style.t
    -> ?display_small:Style.Text_style.t
    -> ?headline_large:Style.Text_style.t
    -> ?headline_medium:Style.Text_style.t
    -> ?headline_small:Style.Text_style.t
    -> ?title_large:Style.Text_style.t
    -> ?title_medium:Style.Text_style.t
    -> ?title_small:Style.Text_style.t
    -> ?body_large:Style.Text_style.t
    -> ?body_medium:Style.Text_style.t
    -> ?body_small:Style.Text_style.t
    -> ?label_large:Style.Text_style.t
    -> ?label_medium:Style.Text_style.t
    -> ?label_small:Style.Text_style.t
    -> unit
    -> t
end

module Shape : sig
  type t

  val create
    :  ?extra_small:float
    -> ?small:float
    -> ?medium:float
    -> ?large:float
    -> ?extra_large:float
    -> unit
    -> t
end

type visual_density =
  | Adaptive
  | Standard
  | Comfortable
  | Compact

type tap_target_size =
  | Padded
  | Shrink_wrap

type data

val material
  :  brightness:Style.Brightness.t
  -> color_scheme:Color_scheme.t
  -> ?typography:Typography.t
  -> ?shape:Shape.t
  -> ?visual_density:visual_density
  -> ?tap_target_size:tap_target_size
  -> unit
  -> data

type mode =
  | System
  | Light
  | Dark

type application

val application
  :  mode:mode
  -> light:data
  -> dark:data
  -> ?high_contrast_light:data
  -> ?high_contrast_dark:data
  -> unit
  -> application

module Private : sig
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

  val view_data : data -> data_view
  val view_application : application -> application_view
  val equal_application : application -> application -> bool
end
