(** Small Cupertino semantic surface.

    These constructors preserve the typed OCaml event and value model. *)

val button
  :  ?key:Key.t
  -> ?enabled:bool
  -> Event.Handler.t
  -> child:Widget.t
  -> unit
  -> Widget.t

val switch
  :  ?key:Key.t
  -> ?enabled:bool
  -> value:bool
  -> on_changed:Event.Handler.t
  -> unit
  -> Widget.t
