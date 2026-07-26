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
  { item_id : string
  ; label : string
  ; enabled : bool
  }

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

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
  -> node_id:int64
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
  -> node_id:int64
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
  -> (string option, error) result Bonsai.Effect.t

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
  -> node_id:int64
  -> (layout, error) result Bonsai.Effect.t

module Private : sig
  val create : schedule:(unit Bonsai.Effect.t -> unit) -> t
  val take_operations : t -> Bonsai_flutter_protocol.Wire_frame.operation list

  val resolve
    :  t
    -> Bonsai_flutter_protocol.Inbound_event.host_response
    -> (unit, string) result

  val shutdown : t -> unit
  val pending_count : t -> int
end
