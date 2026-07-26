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

let to_string = function
  | Duplicate_key { parent_kind; key } ->
    Printf.sprintf
      "duplicate key %s below %s"
      (Bonsai_flutter_ui.Key.to_debug_string key)
      parent_kind
  | Invalid_patch message -> "invalid patch: " ^ message
  | Revision_mismatch { expected; actual } ->
    Printf.sprintf "revision mismatch: expected %Ld, got %Ld" expected actual
  | Wrong_runtime_epoch { expected; actual } ->
    Printf.sprintf "runtime epoch mismatch: expected %Ld, got %Ld" expected actual
  | Stale_event { revision } -> Printf.sprintf "stale event for revision %Ld" revision
  | Duplicate_or_out_of_order_event { sequence } ->
    Printf.sprintf "duplicate or out-of-order event sequence %Ld" sequence
  | Handler_missing { handler_id } ->
    Printf.sprintf "missing handler %Ld" (Handler_id.to_int64 handler_id)
  | Handler_mismatch { handler_id; node_id; event_tag } ->
    Printf.sprintf
      "handler %Ld does not match node %Ld and event %s"
      (Handler_id.to_int64 handler_id)
      (Node_id.to_int64 node_id)
      (Bonsai_flutter_ui.Event.Tag.to_string event_tag)
  | Handler_exception { handler_id; message; backtrace = _ } ->
    Printf.sprintf "handler %Ld raised: %s" (Handler_id.to_int64 handler_id) message
;;
