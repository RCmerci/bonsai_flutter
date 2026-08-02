(** Typed events sent from the Flutter renderer to the OCaml runtime. *)

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

type host_response_status =
  | Host_ok
  | Host_error
  | Host_cancelled

type host_response =
  { request_id : Bonsai_flutter_spec.Id.Host.request_id
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
  { sequence : Bonsai_flutter_spec.Id.Runtime.event_sequence
  ; displayed_revision : Bonsai_flutter_spec.Id.Runtime.renderer_revision
  ; node_id : Bonsai_flutter_spec.Id.Ui.node_id
  ; handler_id : Bonsai_flutter_spec.Id.Ui.handler_id
  ; event_tag : Bonsai_flutter_spec.Id.Protocol.event_tag
  ; payload : payload
  }

type batch =
  { runtime_epoch : Bonsai_flutter_spec.Id.Runtime.epoch
  ; events : t list
  }
