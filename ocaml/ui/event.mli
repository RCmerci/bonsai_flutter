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
    | Text_limit_reached
    | Scroll_notification
    | Visible_range_changed
    | Animation_completed
    | Route_pop
    | Layout_observed
    | Value_changed
    | Native_event
    | Semantics_action
    | Navigation_destination_selected
    | Radio_selected
    | Slider_changed
    | Slider_change_end
    | Range_slider_changed
    | Range_slider_change_end
    | Delete
    | Segmented_selection_changed
    | Tooltip_triggered
    | Table_sort_requested
    | Table_row_selected
    | Table_select_all
    | Table_cell_activated
    | Step_selected
    | Step_continue
    | Step_cancel
    | Expansion_changed
    | Dialog_option_selected
    | Civil_date_changed
    | Civil_time_changed
    | Search_opened
    | Search_closed

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
    { session_id : Bonsai_flutter_spec.Id.Text_input.session_id
    ; local_revision : Bonsai_flutter_spec.Id.Text_input.local_revision
    ; base_document_revision : Bonsai_flutter_spec.Id.Text_input.document_revision
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
    { page_key : Bonsai_flutter_spec.Id.Navigation.page_key
    ; result : string option
    }

  type native_event =
    { kind_id : Bonsai_flutter_spec.Id.Native_widget.kind_id
    ; version : int
    ; event_id : Bonsai_flutter_spec.Id.Native_widget.event_id
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
    { pointer_id : Bonsai_flutter_spec.Id.Input.pointer_id
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
    { logical_key : Bonsai_flutter_spec.Id.Input.logical_key
    ; physical_key : Bonsai_flutter_spec.Id.Input.physical_key
    ; action : key_action
    ; modifiers : int
    }

  type t =
    | Unit
    | Bool of bool
    | Text of string
    | Text_edit of text_edit
    | Int64 of int64
    | Int64_list of int64 list
    | Int64_bool of
        { id : int64
        ; value : bool
        }
    | Int64_pair of
        { first : int64
        ; second : int64
        }
    | Float of float
    | Float_range of
        { start : float
        ; end_ : float
        }
    | Civil_date of
        { year : int
        ; month : int
        ; day : int
        }
    | Civil_time of
        { hour : int
        ; minute : int
        }
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
