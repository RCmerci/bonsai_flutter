(** Converts validated protocol events and dispatches revision-scoped handlers. *)

type error =
  | Invalid_event of string
  | Handler_error of Runtime_error.t

val dispatch_batch
  :  Handler_registry.t
  -> Bonsai_flutter_protocol.Inbound_event.batch
  -> (unit, error) result
