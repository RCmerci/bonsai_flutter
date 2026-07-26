let require condition message = if not condition then failwith message

let component ~activations ~after_displays graph =
  let state, toggle_effect = Bonsai.toggle ~default_model:false graph in
  let on_activate =
    Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr activations))
  in
  let after_display =
    Bonsai.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr after_displays))
  in
  Bonsai.Edge.lifecycle ~on_activate ~after_display graph;
  Bonsai.map2 state toggle_effect ~f:(fun state toggle_effect -> state, toggle_effect)
;;

let () =
  let activations = ref 0 in
  let after_displays = ref 0 in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let adapter =
    Bonsai_runtime_adapter.create ~time_source (component ~activations ~after_displays)
  in
  Bonsai_runtime_adapter.flush adapter;
  let state, toggle_effect = Bonsai_runtime_adapter.result adapter in
  require (not state) "the initial Bonsai state must be false";
  require
    (!activations = 0 && !after_displays = 0)
    "flush must not trigger after-display lifecycle events";
  require
    (Bonsai_runtime_adapter.has_after_display_events adapter)
    "the initial frame must report pending after-display lifecycle events";
  Bonsai_runtime_adapter.schedule_event adapter toggle_effect;
  Bonsai_runtime_adapter.flush adapter;
  let state, _ = Bonsai_runtime_adapter.result adapter in
  require state "the scheduled Bonsai effect must be applied by flush";
  require
    (!activations = 0 && !after_displays = 0)
    "state updates must not trigger lifecycle events before frame presentation";
  Bonsai_runtime_adapter.frame_presented adapter;
  require (!activations = 1) "activation must run after frame presentation";
  require (!after_displays = 1) "after-display must run after frame presentation";
  Bonsai_runtime_adapter.shutdown adapter;
  Bonsai_runtime_adapter.shutdown adapter;
  require
    (Bonsai_runtime_adapter.is_shutdown adapter)
    "shutdown must be idempotent and observable"
;;
