(** Declarative navigation and overlay intents owned by OCaml. *)

type page_transition =
  | None
  | Fade
  | Slide

module Modal_bottom_sheet : sig
  module Detent : sig
    type t =
      | Medium
      | Large
  end

  module Handle_semantics : sig
    type t

    val create : label:string -> medium_value:string -> large_value:string -> t

    module Private : sig
      type view =
        { label : string
        ; medium_value : string
        ; large_value : string
        }

      val view : t -> view
    end
  end

  module Detents : sig
    type t

    val create
      :  ?initial:Detent.t
      -> ?dismiss_on_drag:bool
      -> semantics:Handle_semantics.t
      -> Detent.t list
      -> t

    module Private : sig
      type view =
        { detents : Detent.t list
        ; initial : Detent.t
        ; dismiss_on_drag : bool
        ; semantics : Handle_semantics.t
        }

      val view : t -> view
    end
  end

  module Sizing : sig
    type t =
      | Content_bounded
      | Scroll_controlled
      | Detented of Detents.t
  end

  type t

  (** [create ()] describes route-owned modal bottom sheet mechanics. The
      defaults are a dismissible theme-colored barrier, localized barrier
      semantics, content-bounded height, no top/side safe area, route focus, a
      250 ms entrance, and a 200 ms exit. *)
  val create
    :  ?barrier_dismissible:bool
    -> ?barrier_color:Style.Color.t
    -> ?barrier_label:string
    -> ?sizing:Sizing.t
    -> ?use_safe_area:bool
    -> ?request_focus:bool
    -> ?transition_duration_ms:int
    -> ?reverse_transition_duration_ms:int
    -> unit
    -> t

  module Private : sig
    type view =
      { barrier_dismissible : bool
      ; barrier_color : Style.Color.t option
      ; barrier_label : string option
      ; sizing : Sizing.t
      ; use_safe_area : bool
      ; request_focus : bool
      ; transition_duration_ms : int
      ; reverse_transition_duration_ms : int
      }

    val view : t -> view
  end
end

module Modal_dialog : sig
  type t

  val create
    :  ?barrier_dismissible:bool
    -> ?barrier_color:Style.Color.t
    -> ?barrier_label:string
    -> ?use_safe_area:bool
    -> ?request_focus:bool
    -> ?transition_duration_ms:int
    -> ?reverse_transition_duration_ms:int
    -> unit
    -> t

  module Private : sig
    type view =
      { barrier_dismissible : bool
      ; barrier_color : Style.Color.t option
      ; barrier_label : string option
      ; use_safe_area : bool
      ; request_focus : bool
      ; transition_duration_ms : int
      ; reverse_transition_duration_ms : int
      }

    val view : t -> view
  end
end

(** Route-owned side-sheet mechanics. The logical page child should be a
    [Material.Side_sheet.surface]. *)
module Modal_side_sheet : module type of Modal_dialog

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
