(** Structured errors that may safely cross the runtime boundary. *)

type t =
  | Duplicate_key of
      { parent_kind : string
      ; key : Bonsai_flutter_ui.Key.t
      }
  | Invalid_patch of string
  | Revision_mismatch of
      { expected : int64
      ; actual : int64
      }
  | Wrong_runtime_epoch of
      { expected : int64
      ; actual : int64
      }
  | Stale_event of { revision : int64 }
  | Duplicate_or_out_of_order_event of { sequence : int64 }
  | Handler_missing of { handler_id : Handler_id.t }
  | Handler_mismatch of
      { handler_id : Handler_id.t
      ; node_id : Node_id.t
      ; event_tag : Bonsai_flutter_ui.Event.Tag.t
      }
  | Handler_exception of
      { handler_id : Handler_id.t
      ; message : string
      ; backtrace : string
      }

val to_string : t -> string
