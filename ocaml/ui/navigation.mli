(** Declarative navigation and overlay intents owned by OCaml. *)

type page_transition =
  | None
  | Fade
  | Slide

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
