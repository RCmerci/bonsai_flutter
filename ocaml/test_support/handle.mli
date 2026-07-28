(** A headless Bonsai runtime with logical-tree queries and renderer events. *)

type t

val create
  :  runtime_epoch:int64
  -> time_source:Bonsai.Time_source.t
  -> (Driver.Handler.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t)
  -> t

val show : t -> string
val show_diff : t -> string
val find : t -> Query.t -> Bonsai_flutter_runtime.Mounted_tree.Snapshot.node option
val find_all : t -> Query.t -> Bonsai_flutter_runtime.Mounted_tree.Snapshot.node list
val click : t -> Query.t -> unit
val long_press : t -> Query.t -> unit
val input_text : t -> Query.t -> string -> unit

val apply_text_edit
  :  t
  -> Query.t
  -> local_revision:int64
  -> base_document_revision:int64
  -> text:string
  -> selection_start:int
  -> selection_end:int
  -> ?composing_start:int
  -> ?composing_end:int
  -> unit
  -> unit

val key_down : t -> Query.t -> logical_key:int64 -> unit
val focus : t -> Query.t -> unit
val blur : t -> Query.t -> unit
val route_pop : t -> Query.t -> page_key:string -> ?result:string -> unit -> unit

val native_event
  :  t
  -> Query.t
  -> kind_id:int
  -> version:int
  -> event_id:int
  -> payload:bytes
  -> unit

val resize : t -> width:float -> height:float -> unit
val set_environment : t -> Environment.snapshot -> unit

val respond_to_host_effect
  :  t
  -> ?request_id:int64
  -> ?status:Bonsai_flutter_protocol.Inbound_event.host_response_status
  -> bytes
  -> unit

val trigger_frame_presented : t -> unit
val last_frame : t -> Driver.frame option
val revision : t -> int64
val pending_host_effect_count : t -> int
val shutdown : t -> unit
