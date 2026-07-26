type t =
  { brightness : Style.Brightness.t
  ; color_seed : Style.Color.t
  }

let default_seed = Style.Color.rgb ~red:103 ~green:80 ~blue:164

let material ?(brightness = Style.Brightness.Light) ?(color_seed = default_seed) () =
  { brightness; color_seed }
;;

module Private = struct
  type view =
    { brightness : Style.Brightness.t
    ; color_seed : int32
    }

  let view (theme : t) : view =
    { brightness = theme.brightness
    ; color_seed = Style.Color.Private.to_argb32 theme.color_seed
    }
  ;;
end
