(** Typed asynchronous requests executed by the Flutter host. *)

type t

type error =
  | Failed of string
  | Cancelled
  | Shutdown
  | Invalid_response of string

type file =
  { path : string option
  ; data : bytes option
  }

type platform_information =
  { operating_system : string
  ; operating_system_version : string
  ; locale_name : string
  }

type layout =
  { left : float
  ; top : float
  ; width : float
  ; height : float
  }

type native_menu_item =
  { item_id : Bonsai_flutter_spec.Id.Host.native_menu_item_id
  ; label : string
  ; enabled : bool
  }

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

type snack_bar_close_reason =
  | Action
  | Dismiss
  | Swipe
  | Hide
  | Remove
  | Timeout

type civil_date =
  { year : int
  ; month : int
  ; day : int
  }

type civil_date_range =
  { start : civil_date
  ; end_ : civil_date
  }

type civil_time =
  { hour : int
  ; minute : int
  }

type picker_entry_mode =
  | Calendar_or_dial
  | Input

val civil_date : year:int -> month:int -> day:int -> civil_date
val civil_date_range : start:civil_date -> end_:civil_date -> civil_date_range
val civil_time : hour:int -> minute:int -> civil_time

module Application_platform : sig
  type t

  type error =
    | Unavailable
    | Payload_too_large
    | Handler_failed of string
    | Cancelled
    | Shutdown
    | Runtime_replaced
    | Invalid_response of string

  val maximum_payload_bytes : int

  module Cancellation : sig
    type t

    val create : unit -> t
    val cancel : t -> unit
  end

  val request
    :  ?cancellation:Cancellation.t
    -> t
    -> bytes
    -> (bytes, error) result Bonsai.Effect.t

  val on_event : t -> (bytes -> unit Bonsai.Effect.t) -> unit

  module Prepared_operations : sig
    type t

    val operations : t -> Bonsai_flutter_protocol.Wire_frame.operation list
  end

  val prepare_operations : t -> Prepared_operations.t
  val commit_operations : t -> Prepared_operations.t -> (unit, string) result

  module Private : sig
    val create : schedule:(unit Bonsai.Effect.t -> unit) -> t

    module Validated_input : sig
      type t

      val request_id : t -> int64 option
    end

    val validate_input
      :  t
      -> Bonsai_flutter_protocol.Inbound_event.payload
      -> (Validated_input.t, string) result

    val resolve_validated : t -> Validated_input.t -> (unit, string) result
    val shutdown : t -> error -> unit
    val pending_count : t -> int
  end
end

module Cancellation : sig
  type t

  val create : unit -> t
  val cancel : t -> unit
  val is_cancelled : t -> bool
end

module Clipboard : sig
  val read
    :  ?cancellation:Cancellation.t
    -> t
    -> unit
    -> (string, error) result Bonsai.Effect.t

  val write
    :  ?cancellation:Cancellation.t
    -> t
    -> string
    -> (unit, error) result Bonsai.Effect.t
end

val open_url
  :  ?cancellation:Cancellation.t
  -> t
  -> string
  -> (unit, error) result Bonsai.Effect.t

val pick_file
  :  ?cancellation:Cancellation.t
  -> ?allowed_extensions:string list
  -> ?allow_multiple:bool
  -> t
  -> unit
  -> (file option, error) result Bonsai.Effect.t

val save_file
  :  ?cancellation:Cancellation.t
  -> ?suggested_name:string
  -> data:bytes
  -> t
  -> unit
  -> (file option, error) result Bonsai.Effect.t

val request_focus
  :  ?cancellation:Cancellation.t
  -> t
  -> node_id:Bonsai_flutter_spec.Id.Ui.node_id
  -> (unit, error) result Bonsai.Effect.t

val clear_focus
  :  ?cancellation:Cancellation.t
  -> t
  -> unit
  -> (unit, error) result Bonsai.Effect.t

val scroll_to
  :  ?cancellation:Cancellation.t
  -> ?alignment:float
  -> ?animated:bool
  -> t
  -> node_id:Bonsai_flutter_spec.Id.Ui.node_id
  -> (unit, error) result Bonsai.Effect.t

val set_window_title
  :  ?cancellation:Cancellation.t
  -> t
  -> string
  -> (unit, error) result Bonsai.Effect.t

val set_window_size
  :  ?cancellation:Cancellation.t
  -> t
  -> width:float
  -> height:float
  -> (unit, error) result Bonsai.Effect.t

val show_native_menu
  :  ?cancellation:Cancellation.t
  -> t
  -> native_menu_item list
  -> (Bonsai_flutter_spec.Id.Host.native_menu_item_id option, error) result
       Bonsai.Effect.t

val haptic_feedback
  :  ?cancellation:Cancellation.t
  -> t
  -> haptic_kind
  -> (unit, error) result Bonsai.Effect.t

val platform_information
  :  ?cancellation:Cancellation.t
  -> t
  -> unit
  -> (platform_information, error) result Bonsai.Effect.t

val measure_layout
  :  ?cancellation:Cancellation.t
  -> t
  -> node_id:Bonsai_flutter_spec.Id.Ui.node_id
  -> (layout, error) result Bonsai.Effect.t

val show_snack_bar
  :  ?cancellation:Cancellation.t
  -> ?action_label:string
  -> ?duration_ms:int
  -> t
  -> message:string
  -> unit
  -> (snack_bar_close_reason, error) result Bonsai.Effect.t

val pick_date
  :  ?cancellation:Cancellation.t
  -> ?initial:civil_date
  -> ?current:civil_date
  -> ?entry_mode:picker_entry_mode
  -> first:civil_date
  -> last:civil_date
  -> t
  -> unit
  -> (civil_date option, error) result Bonsai.Effect.t

val pick_date_range
  :  ?cancellation:Cancellation.t
  -> ?initial:civil_date_range
  -> ?current:civil_date
  -> ?entry_mode:picker_entry_mode
  -> first:civil_date
  -> last:civil_date
  -> t
  -> unit
  -> (civil_date_range option, error) result Bonsai.Effect.t

val pick_time
  :  ?cancellation:Cancellation.t
  -> ?entry_mode:picker_entry_mode
  -> ?use_24_hour:bool
  -> initial:civil_time
  -> t
  -> unit
  -> (civil_time option, error) result Bonsai.Effect.t

module Prepared_operations : sig
  type t

  val operations : t -> Bonsai_flutter_protocol.Wire_frame.operation list
end

val prepare_operations : t -> Prepared_operations.t
val commit_operations : t -> Prepared_operations.t -> (unit, string) result

module Private : sig
  val create : schedule:(unit Bonsai.Effect.t -> unit) -> t

  module Validated_response : sig
    type t

    val request_id : t -> Bonsai_flutter_spec.Id.Host.request_id
  end

  val validate_response
    :  t
    -> Bonsai_flutter_protocol.Inbound_event.host_response
    -> (Validated_response.t, string) result

  val resolve_validated : t -> Validated_response.t -> (unit, string) result

  val resolve
    :  t
    -> Bonsai_flutter_protocol.Inbound_event.host_response
    -> (unit, string) result

  val shutdown : t -> unit
  val pending_count : t -> int
end
