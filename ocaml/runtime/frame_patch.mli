(** Atomic logical patches emitted by the OCaml reconciler. *)

module Operation : sig
  type create_node =
    { node_id : Node_id.t
    ; key : Bonsai_flutter_ui.Key.t option
    ; test_id : Bonsai_flutter_ui.Test_id.t option
    ; kind : Bonsai_flutter_ui.Widget.Private.Kind.t
    ; props : Bonsai_flutter_ui.Widget.Private.props
    ; event_bindings : Mounted_tree.Mounted_binding.t array
    ; parent_data : Bonsai_flutter_ui.Widget.Private.child_parent_data
    }

  type t =
    | Create_node of create_node
    | Update_props of
        { node_id : Node_id.t
        ; props : Bonsai_flutter_ui.Widget.Private.props
        }
    | Update_event_bindings of
        { node_id : Node_id.t
        ; event_bindings : Mounted_tree.Mounted_binding.t array
        }
    | Set_children of
        { node_id : Node_id.t
        ; children : Node_id.t array
        }
    | Set_root of Node_id.t
    | Drop_node of Node_id.t
end

type kind =
  | Full_snapshot
  | Incremental_frame

type t

val kind : t -> kind
val base_revision : t -> int64
val target_revision : t -> int64
val operations : t -> Operation.t list
val is_empty : t -> bool

val apply
  :  old:Mounted_tree.Snapshot.t option
  -> t
  -> (Mounted_tree.Snapshot.t, Runtime_error.t) result

module Private : sig
  val create
    :  kind:kind
    -> base_revision:int64
    -> target_revision:int64
    -> Operation.t list
    -> t
end
