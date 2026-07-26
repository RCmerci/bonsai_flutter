(** Typed renderer events and opaque callback identity. *)

module Tag : sig
  type t =
    | Press
    | Long_press
    | Tap
    | Double_tap
    | Pointer_enter
    | Pointer_leave
    | Pointer_down
    | Pointer_up
    | Key
    | Focus_changed
    | Text_edit
    | Text_submit
    | Scroll_notification
    | Visible_range_changed
    | Animation_completed
    | Route_pop
    | Layout_observed
    | Value_changed
    | Native_event
    | Semantics_action

  val compare : t -> t -> int
  val equal : t -> t -> bool
  val to_string : t -> string
end

module Key_policy : sig
  type t =
    | Handled
    | Ignored
end

module Payload : sig
  type text_selection =
    { start_utf16 : int
    ; end_utf16 : int
    }

  type text_edit =
    { session_id : int64
    ; local_revision : int64
    ; base_document_revision : int64
    ; text : string
    ; selection : text_selection
    ; composing : text_selection option
    }

  type scroll =
    { pixels : float
    ; delta : float
    }

  type visible_range =
    { first_index : int64
    ; last_exclusive : int64
    }

  type route_pop =
    { page_key : string
    ; result : string option
    }

  type native_event =
    { kind_id : int
    ; version : int
    ; event_id : int
    ; payload : bytes
    }

  type pointer_kind =
    | Mouse
    | Touch
    | Stylus
    | Inverted_stylus
    | Trackpad
    | Unknown_pointer

  type tap =
    { local_x : float
    ; local_y : float
    ; global_x : float
    ; global_y : float
    ; pointer_kind : pointer_kind
    }

  type pointer =
    { pointer_id : int64
    ; local_x : float
    ; local_y : float
    ; global_x : float
    ; global_y : float
    ; pointer_kind : pointer_kind
    ; buttons : int
    }

  type key_action =
    | Key_down
    | Key_up
    | Key_repeat

  type key =
    { logical_key : int64
    ; physical_key : int64
    ; action : key_action
    ; modifiers : int
    }

  type t =
    | Unit
    | Bool of bool
    | Text of string
    | Text_edit of text_edit
    | Int64 of int64
    | Tap of tap
    | Pointer of pointer
    | Key of key
    | Scroll of scroll
    | Visible_range of visible_range
    | Route_pop of route_pop
    | Native_event of native_event
end

module Handler : sig
  type t

  (** [create] assigns callback identity. [name] is debug-only and never
      serialized as executable data. *)
  val create : ?name:string -> (Payload.t -> unit) -> t

  val name : t -> string option

  module Private : sig
    val same : t -> t -> bool
    val invoke : t -> Payload.t -> unit
  end
end
