(** Structured errors that may safely cross the runtime boundary. *)

type t =
  | Duplicate_key of
      { parent_kind : string
      ; key : Bonsai_flutter_ui.Key.t
      }
  | Invalid_patch of string
  | Revision_mismatch of
      { expected : Bonsai_flutter_spec.Id.Runtime.renderer_revision
      ; actual : Bonsai_flutter_spec.Id.Runtime.renderer_revision
      }
  | Wrong_runtime_epoch of
      { expected : Bonsai_flutter_spec.Id.Runtime.epoch
      ; actual : Bonsai_flutter_spec.Id.Runtime.epoch
      }
  | Stale_event of { revision : Bonsai_flutter_spec.Id.Runtime.renderer_revision }
  | Duplicate_or_out_of_order_event of
      { sequence : Bonsai_flutter_spec.Id.Runtime.event_sequence }
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
