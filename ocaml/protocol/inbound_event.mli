(** Typed events sent from the Flutter renderer to the OCaml runtime. *)

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

type host_response_status =
  | Host_ok
  | Host_error
  | Host_cancelled

type host_response =
  { request_id : int64
  ; status : host_response_status
  ; value : bytes
  }

type edge_insets =
  { left : float
  ; top : float
  ; right : float
  ; bottom : float
  }

type environment_brightness =
  | Environment_light
  | Environment_dark

type orientation =
  | Portrait
  | Landscape

type environment =
  { viewport_width : float
  ; viewport_height : float
  ; device_pixel_ratio : float
  ; text_scale : float
  ; brightness : environment_brightness
  ; platform : string
  ; locale : string
  ; safe_area : edge_insets
  ; keyboard_insets : edge_insets
  ; accessible_navigation : bool
  ; bold_text : bool
  ; invert_colors : bool
  ; disable_animations : bool
  ; reduced_motion : bool
  ; high_contrast : bool
  ; orientation : orientation
  ; pointer_kinds : int
  }

type payload =
  | Unit
  | Bool of bool
  | Text of string
  | Text_edit of text_edit
  | Int64 of int64
  | Tap of tap
  | Pointer of pointer
  | Key of key
  | Scroll of
      { pixels : float
      ; delta : float
      }
  | Visible_range of
      { first_index : int64
      ; last_exclusive : int64
      }
  | Route_pop of route_pop
  | Host_response of host_response
  | Environment_changed of environment
  | Native_event of native_event

type t =
  { sequence : int64
  ; displayed_revision : int64
  ; node_id : int64
  ; handler_id : int64
  ; event_tag : int
  ; payload : payload
  }

type batch =
  { runtime_epoch : int64
  ; events : t list
  }
