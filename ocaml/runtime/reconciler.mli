(** Stateful allocator and expected-linear tree reconciler. *)

type t

type output =
  { mounted_tree : Mounted_tree.t
  ; frame_patch : Frame_patch.t
  ; handler_frame : Handler_registry.Frame.t
  }

val create : runtime_epoch:int64 -> t

val reconcile
  :  t
  -> base_revision:int64
  -> target_revision:int64
  -> old:Mounted_tree.t option
  -> Bonsai_flutter_ui.Widget.t
  -> (output, Runtime_error.t) result
