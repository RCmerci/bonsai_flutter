module Ui = Bonsai_flutter_ui
module Runtime = Bonsai_flutter_runtime
module Widget = Ui.Widget
module Key = Ui.Key
module Event = Ui.Event
module Mounted_tree = Runtime.Mounted_tree
module Frame_patch = Runtime.Frame_patch
module Handler_registry = Runtime.Handler_registry
module Reconciler = Runtime.Reconciler
module Runtime_error = Runtime.Runtime_error

exception Test_failure of string

let fail format = Printf.ksprintf (fun message -> raise (Test_failure message)) format
let check condition format = if not condition then fail "%s" format

let check_int ~expected ~actual label =
  if expected <> actual then fail "%s: expected %d, got %d" label expected actual
;;

let check_int64 ~expected ~actual label =
  if not (Int64.equal expected actual)
  then fail "%s: expected %Ld, got %Ld" label expected actual
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected error: %s" (Runtime_error.to_string error)
;;

let reconcile_exn reconciler ~base_revision ~target_revision ~old widget =
  Reconciler.reconcile reconciler ~base_revision ~target_revision ~old widget |> ok
;;

let count_operations patch predicate =
  Frame_patch.operations patch
  |> List.fold_left
       (fun count operation -> if predicate operation then count + 1 else count)
       0
;;

let is_create = function
  | Frame_patch.Operation.Create_node _ -> true
  | _ -> false
;;

let is_update_props = function
  | Frame_patch.Operation.Update_props _ -> true
  | _ -> false
;;

let is_update_event_bindings = function
  | Frame_patch.Operation.Update_event_bindings _ -> true
  | _ -> false
;;

let is_set_children = function
  | Frame_patch.Operation.Set_children _ -> true
  | _ -> false
;;

let is_set_root = function
  | Frame_patch.Operation.Set_root _ -> true
  | _ -> false
;;

let is_drop = function
  | Frame_patch.Operation.Drop_node _ -> true
  | _ -> false
;;

let apply_and_compare ~old_snapshot output =
  let applied = Frame_patch.apply ~old:old_snapshot output.Reconciler.frame_patch |> ok in
  let expected = Mounted_tree.snapshot output.mounted_tree in
  check
    (Mounted_tree.Snapshot.equal applied expected)
    "patch application did not reproduce the mounted snapshot"
;;

let node_by_key snapshot key =
  match Mounted_tree.Snapshot.find_by_key snapshot key with
  | Some node -> node
  | None -> fail "missing mounted node for key %s" (Key.to_debug_string key)
;;

let node_by_text snapshot text =
  match Mounted_tree.Snapshot.find_by_text snapshot text with
  | Some node -> node
  | None -> fail "missing mounted text node %S" text
;;

let binding_exn node tag =
  let matching =
    Array.to_list node.Mounted_tree.Snapshot.event_bindings
    |> List.filter (fun binding ->
      Event.Tag.equal binding.Mounted_tree.Mounted_binding.event_tag tag)
  in
  match matching with
  | [ binding ] -> binding
  | _ -> fail "expected exactly one %s binding" (Event.Tag.to_string tag)
;;

let press_handler ?name callback = Event.Handler.create ?name (fun _ -> callback ())

let test_initial_mount_is_full_snapshot () =
  let reconciler = Reconciler.create ~runtime_epoch:41L in
  let widget = Widget.column [ Widget.text "hello"; Widget.text "world" ] in
  let output =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None widget
  in
  check
    (Frame_patch.kind output.frame_patch = Frame_patch.Full_snapshot)
    "initial mount must be a full snapshot";
  check_int ~expected:3 ~actual:(Mounted_tree.node_count output.mounted_tree) "node count";
  check_int
    ~expected:3
    ~actual:(count_operations output.frame_patch is_create)
    "create count";
  check_int
    ~expected:1
    ~actual:(count_operations output.frame_patch is_set_root)
    "set root count";
  apply_and_compare ~old_snapshot:None output
;;

let test_physical_equality_emits_no_patch () =
  let reconciler = Reconciler.create ~runtime_epoch:42L in
  let widget = Widget.column [ Widget.text "unchanged" ] in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None widget
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      widget
  in
  check (Frame_patch.is_empty second.frame_patch) "physical equality emitted a patch";
  check_int64
    ~expected:(Mounted_tree.root_id first.mounted_tree)
    ~actual:(Mounted_tree.root_id second.mounted_tree)
    "root identity";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_one_text_change_is_one_prop_update () =
  let reconciler = Reconciler.create ~runtime_epoch:43L in
  let key = Key.string "counter" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.text ~key "Count: 0")
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.text ~key "Count: 1")
  in
  check_int
    ~expected:1
    ~actual:(List.length (Frame_patch.operations second.frame_patch))
    "patch operation count";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "prop update count";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let keyed_text key value = Widget.text ~key:(Key.string key) value

let test_keyed_reorder_preserves_identity () =
  let reconciler = Reconciler.create ~runtime_epoch:44L in
  let old_widget =
    Widget.column [ keyed_text "a" "A"; keyed_text "b" "B"; keyed_text "c" "C" ]
  in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None old_widget
  in
  let first_snapshot = Mounted_tree.snapshot first.mounted_tree in
  let ids_before =
    List.map
      (fun key -> (node_by_key first_snapshot (Key.string key)).node_id)
      [ "a"; "b"; "c" ]
  in
  let new_widget =
    Widget.column [ keyed_text "c" "C"; keyed_text "a" "A"; keyed_text "b" "B" ]
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      new_widget
  in
  let second_snapshot = Mounted_tree.snapshot second.mounted_tree in
  let ids_after =
    List.map
      (fun key -> (node_by_key second_snapshot (Key.string key)).node_id)
      [ "a"; "b"; "c" ]
  in
  check (ids_before = ids_after) "keyed reorder changed node identities";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_children)
    "set children";
  apply_and_compare ~old_snapshot:(Some first_snapshot) second
;;

let test_keyed_insert_and_delete_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:45L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.column [ keyed_text "a" "A"; keyed_text "b" "B" ])
  in
  let first_snapshot = Mounted_tree.snapshot first.mounted_tree in
  let a_before = (node_by_key first_snapshot (Key.string "a")).node_id in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.column [ keyed_text "x" "X"; keyed_text "a" "A" ])
  in
  let second_snapshot = Mounted_tree.snapshot second.mounted_tree in
  let a_after = (node_by_key second_snapshot (Key.string "a")).node_id in
  check_int64 ~expected:a_before ~actual:a_after "surviving keyed child";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_drop) "drops";
  apply_and_compare ~old_snapshot:(Some first_snapshot) second
;;

let test_kind_replacement_remounts () =
  let reconciler = Reconciler.create ~runtime_epoch:46L in
  let key = Key.string "root" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.text ~key "old")
  in
  let old_id = Mounted_tree.root_id first.mounted_tree in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.column ~key [ Widget.text "new" ])
  in
  let new_id = Mounted_tree.root_id second.mounted_tree in
  check (not (Int64.equal old_id new_id)) "kind replacement reused node ID";
  check_int ~expected:2 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_root)
    "root replacement";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_duplicate_keys_fail_without_consuming_ids () =
  let reconciler = Reconciler.create ~runtime_epoch:47L in
  let duplicate = Key.string "duplicate" in
  let invalid =
    Widget.column [ Widget.text ~key:duplicate "one"; Widget.text ~key:duplicate "two" ]
  in
  (match
     Reconciler.reconcile
       reconciler
       ~base_revision:0L
       ~target_revision:1L
       ~old:None
       invalid
   with
   | Error (Runtime_error.Duplicate_key { key; _ }) ->
     check (Key.equal key duplicate) "duplicate error reported the wrong key"
   | Error error -> fail "wrong duplicate-key error: %s" (Runtime_error.to_string error)
   | Ok _ -> fail "duplicate keys reconciled successfully");
  let valid =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.empty ())
  in
  check_int64
    ~expected:1L
    ~actual:(Mounted_tree.root_id valid.mounted_tree)
    "failed reconciliation consumed a node ID"
;;

let test_nested_duplicate_keys_fail () =
  let reconciler = Reconciler.create ~runtime_epoch:48L in
  let key = Key.int 7 in
  let invalid =
    Widget.column
      [ Widget.column [ Widget.empty ~key (); Widget.text ~key "same nested parent" ] ]
  in
  match
    Reconciler.reconcile
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      invalid
  with
  | Error (Runtime_error.Duplicate_key _) -> ()
  | Error error -> fail "wrong nested duplicate error: %s" (Runtime_error.to_string error)
  | Ok _ -> fail "nested duplicate keys reconciled successfully"
;;

let test_mixed_keyed_and_unkeyed_match_by_index () =
  let reconciler = Reconciler.create ~runtime_epoch:49L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.column
         [ Widget.text "first"; keyed_text "stable" "keyed"; Widget.text "last" ])
  in
  let before = Mounted_tree.snapshot first.mounted_tree in
  let last_before = (node_by_text before "last").node_id in
  let first_before = (node_by_text before "first").node_id in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.column
         [ keyed_text "stable" "keyed"; Widget.text "first"; Widget.text "last" ])
  in
  let after = Mounted_tree.snapshot second.mounted_tree in
  let last_after = (node_by_text after "last").node_id in
  let first_after = (node_by_text after "first").node_id in
  check_int64 ~expected:last_before ~actual:last_after "same-index unkeyed child";
  check
    (not (Int64.equal first_before first_after))
    "unkeyed child moved to a different index without remounting";
  apply_and_compare ~old_snapshot:(Some before) second
;;

let test_nested_removal_drops_complete_subtree () =
  let reconciler = Reconciler.create ~runtime_epoch:50L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.column [ Widget.column ~key:(Key.string "branch") [ Widget.text "leaf" ] ])
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.column [])
  in
  check_int
    ~expected:2
    ~actual:(count_operations second.frame_patch is_drop)
    "nested drops";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_handler_change_gets_new_id_and_one_revision_grace () =
  let reconciler = Reconciler.create ~runtime_epoch:51L in
  let registry = Handler_registry.create ~runtime_epoch:51L in
  let old_calls = ref 0 in
  let new_calls = ref 0 in
  let old_handler = press_handler ~name:"old" (fun () -> incr old_calls) in
  let new_handler = press_handler ~name:"new" (fun () -> incr new_calls) in
  let key = Key.string "button" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.button ~key ~on_press:old_handler ~child:(Widget.text "save") ())
  in
  ok (Handler_registry.install registry first.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:1L);
  let first_node = node_by_key (Mounted_tree.snapshot first.mounted_tree) key in
  let first_binding = binding_exn first_node Event.Tag.Press in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.button ~key ~on_press:new_handler ~child:(Widget.text "save") ())
  in
  ok (Handler_registry.install registry second.handler_frame);
  let second_node = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let second_binding = binding_exn second_node Event.Tag.Press in
  check
    (not (Int64.equal first_binding.handler_id second_binding.handler_id))
    "changed handler reused a handler ID";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_event_bindings)
    "event binding update";
  (match
     Handler_registry.dispatch
       registry
       { runtime_epoch = 51L
       ; displayed_revision = 2L
       ; node_id = second_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = second_binding.handler_id
       ; event_sequence = 1L
       ; payload = Event.Payload.Unit
       }
   with
   | Error (Runtime_error.Stale_event _) -> ()
   | Error error ->
     fail "wrong unpresented-frame error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "event from an unpresented frame invoked its handler");
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = 51L
       ; displayed_revision = 1L
       ; node_id = first_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = first_binding.handler_id
       ; event_sequence = 1L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:1 ~actual:!old_calls "old handler before presentation";
  check_int ~expected:0 ~actual:!new_calls "new handler before presentation";
  ok (Handler_registry.frame_presented registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = 51L
       ; displayed_revision = 1L
       ; node_id = first_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = first_binding.handler_id
       ; event_sequence = 2L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:2 ~actual:!old_calls "previous-frame handler during grace period";
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = 51L
       ; displayed_revision = 2L
       ; node_id = second_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = second_binding.handler_id
       ; event_sequence = 3L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:1 ~actual:!new_calls "new handler after presentation";
  let third =
    reconcile_exn
      reconciler
      ~base_revision:2L
      ~target_revision:3L
      ~old:(Some second.mounted_tree)
      (Widget.button ~key ~on_press:new_handler ~child:(Widget.text "save") ())
  in
  ok (Handler_registry.install registry third.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:3L);
  match
    Handler_registry.dispatch
      registry
      { runtime_epoch = 51L
      ; displayed_revision = 1L
      ; node_id = first_node.node_id
      ; event_tag = Event.Tag.Press
      ; handler_id = first_binding.handler_id
      ; event_sequence = 4L
      ; payload = Event.Payload.Unit
      }
  with
  | Error (Runtime_error.Stale_event _) -> ()
  | Error error -> fail "wrong stale-handler error: %s" (Runtime_error.to_string error)
  | Ok () -> fail "event exceeded the one-revision grace period"
;;

let test_unchanged_handler_reuses_id () =
  let reconciler = Reconciler.create ~runtime_epoch:52L in
  let handler = press_handler (fun () -> ()) in
  let key = Key.string "button" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.button ~key ~on_press:handler ~child:(Widget.text "one") ())
  in
  let first_binding =
    binding_exn
      (node_by_key (Mounted_tree.snapshot first.mounted_tree) key)
      Event.Tag.Press
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.button ~key ~on_press:handler ~child:(Widget.text "two") ())
  in
  let second_binding =
    binding_exn
      (node_by_key (Mounted_tree.snapshot second.mounted_tree) key)
      Event.Tag.Press
  in
  check_int64
    ~expected:first_binding.handler_id
    ~actual:second_binding.handler_id
    "unchanged handler ID";
  check_int
    ~expected:0
    ~actual:(count_operations second.frame_patch is_update_event_bindings)
    "unchanged binding patch"
;;

let test_handler_registry_validates_epoch_sequence_and_binding () =
  let reconciler = Reconciler.create ~runtime_epoch:53L in
  let registry = Handler_registry.create ~runtime_epoch:53L in
  let calls = ref 0 in
  let key = Key.string "button" in
  let output =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.button
         ~key
         ~on_press:(press_handler (fun () -> incr calls))
         ~child:(Widget.text "go")
         ())
  in
  ok (Handler_registry.install registry output.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:1L);
  let node = node_by_key (Mounted_tree.snapshot output.mounted_tree) key in
  let binding = binding_exn node Event.Tag.Press in
  let event =
    { Handler_registry.runtime_epoch = 53L
    ; displayed_revision = 1L
    ; node_id = node.node_id
    ; event_tag = Event.Tag.Press
    ; handler_id = binding.handler_id
    ; event_sequence = 10L
    ; payload = Event.Payload.Unit
    }
  in
  (match Handler_registry.dispatch registry { event with runtime_epoch = 999L } with
   | Error (Runtime_error.Wrong_runtime_epoch _) -> ()
   | Error error -> fail "wrong epoch error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "wrong-epoch event was accepted");
  ok (Handler_registry.dispatch registry event);
  (match Handler_registry.dispatch registry event with
   | Error (Runtime_error.Duplicate_or_out_of_order_event _) -> ()
   | Error error -> fail "wrong duplicate error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "duplicate event sequence was accepted");
  (match
     Handler_registry.dispatch
       registry
       { event with event_sequence = 11L; node_id = Int64.succ event.node_id }
   with
   | Error (Runtime_error.Handler_mismatch _) -> ()
   | Error error ->
     fail "wrong binding mismatch error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "mismatched node invoked a handler");
  check_int ~expected:1 ~actual:!calls "validated handler call count"
;;

let test_handler_exception_is_structured () =
  let reconciler = Reconciler.create ~runtime_epoch:54L in
  let registry = Handler_registry.create ~runtime_epoch:54L in
  let key = Key.string "button" in
  let output =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.button
         ~key
         ~on_press:(press_handler (fun () -> failwith "handler exploded"))
         ~child:(Widget.text "go")
         ())
  in
  ok (Handler_registry.install registry output.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:1L);
  let node = node_by_key (Mounted_tree.snapshot output.mounted_tree) key in
  let binding = binding_exn node Event.Tag.Press in
  match
    Handler_registry.dispatch
      registry
      { runtime_epoch = 54L
      ; displayed_revision = 1L
      ; node_id = node.node_id
      ; event_tag = Event.Tag.Press
      ; handler_id = binding.handler_id
      ; event_sequence = 1L
      ; payload = Event.Payload.Unit
      }
  with
  | Error (Runtime_error.Handler_exception { message; _ }) ->
    check (String.equal message "handler exploded") "handler exception message changed"
  | Error error ->
    fail "wrong handler exception error: %s" (Runtime_error.to_string error)
  | Ok () -> fail "handler exception escaped structured handling"
;;

let test_handler_retirement_is_separate_from_presentation_marking () =
  let reconciler = Reconciler.create ~runtime_epoch:58L in
  let registry = Handler_registry.create ~runtime_epoch:58L in
  let handler = press_handler (fun () -> ()) in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.button ~on_press:handler ~child:(Widget.text "one") ())
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.button ~on_press:handler ~child:(Widget.text "two") ())
  in
  ok (Handler_registry.install registry first.handler_frame);
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.mark_frame_presented registry ~revision:2L);
  check_int
    ~expected:2
    ~actual:(Handler_registry.retained_frame_count registry)
    "presentation marking retired a handler frame";
  Handler_registry.retire_before registry ~revision:2L;
  check_int
    ~expected:1
    ~actual:(Handler_registry.retained_frame_count registry)
    "explicit handler retirement"
;;

let test_node_ids_are_never_reused () =
  let reconciler = Reconciler.create ~runtime_epoch:55L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (keyed_text "old" "old")
  in
  let old_id = Mounted_tree.root_id first.mounted_tree in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (keyed_text "new" "new")
  in
  let new_id = Mounted_tree.root_id second.mounted_tree in
  check (Int64.compare new_id old_id > 0) "node ID was reused or moved backwards"
;;

let test_ten_thousand_keyed_children_reverse_in_linear_shape () =
  let count = 10_000 in
  let child index =
    let key = Printf.sprintf "item-%05d" index in
    keyed_text key key
  in
  let reconciler = Reconciler.create ~runtime_epoch:56L in
  let old_children = List.init count child in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Widget.column old_children)
  in
  let before = Mounted_tree.snapshot first.mounted_tree in
  let reversed_children = List.init count (fun index -> child (count - index - 1)) in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Widget.column reversed_children)
  in
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_children)
    "set children";
  apply_and_compare ~old_snapshot:(Some before) second
;;

let random_unique_tree state generation =
  let root_children = 1 + Random.State.int state 24 in
  let keys = Array.init root_children (fun index -> (generation * 1000) + index) in
  for index = root_children - 1 downto 1 do
    let other = Random.State.int state (index + 1) in
    let temporary = keys.(index) in
    keys.(index) <- keys.(other);
    keys.(other) <- temporary
  done;
  let retained = Random.State.int state (root_children + 1) in
  Array.to_list (Array.sub keys 0 retained)
  |> List.map (fun key ->
    let text = Printf.sprintf "g%d-k%d" generation key in
    Widget.text ~key:(Key.int key) text)
  |> Widget.column
;;

let test_randomized_patch_invariant () =
  let random = Random.State.make [| 0xB0; 0x5A; 0x1 |] in
  let reconciler = Reconciler.create ~runtime_epoch:57L in
  let mounted = ref None in
  let snapshot = ref None in
  for generation = 0 to 249 do
    let widget = random_unique_tree random generation in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:(Int64.of_int generation)
        ~target_revision:(Int64.of_int (generation + 1))
        ~old:!mounted
        widget
    in
    apply_and_compare ~old_snapshot:!snapshot output;
    mounted := Some output.mounted_tree;
    snapshot := Some (Mounted_tree.snapshot output.mounted_tree)
  done
;;

let test_layout_material_and_semantics_widgets_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:59L in
  let changed_to = ref None in
  let on_changed =
    Event.Handler.create ~name:"checkbox-change" (function
      | Event.Payload.Bool value -> changed_to := Some value
      | _ -> ())
  in
  let on_scroll = Event.Handler.create ~name:"scroll" (fun _ -> ()) in
  let key = Key.string "checkbox" in
  let tree value =
    Widget.theme
      ~data:
        (Ui.Theme.material
           ~brightness:Ui.Style.Brightness.Dark
           ~color_seed:(Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160)
           ())
      (Widget.semantics
         ~properties:
           (Ui.Semantics.create ~label:"Accept terms" ~enabled:true ~checked:false ())
         (Widget.padding
            ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:12. ~vertical:8. ())
            (Widget.center
               (Widget.scroll_view
                  ~axis:Ui.Layout.Axis.Vertical
                  ~on_scroll
                  (Ui.Material.checkbox ~key ~value ~on_changed ())
                  ()))))
  in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None (tree false)
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (tree true)
  in
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "checkbox prop updates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  let checkbox = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let binding = binding_exn checkbox Event.Tag.Value_changed in
  let registry = Handler_registry.create ~runtime_epoch:59L in
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = 59L
       ; displayed_revision = 2L
       ; node_id = checkbox.node_id
       ; event_tag = Event.Tag.Value_changed
       ; handler_id = binding.handler_id
       ; event_sequence = 1L
       ; payload = Event.Payload.Bool false
       });
  check (!changed_to = Some false) "checkbox did not receive the typed bool payload";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_text_input_props_and_typed_edit_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:60L in
  let edits = ref [] in
  let on_edit =
    Event.Handler.create ~name:"text-edit" (function
      | Event.Payload.Text_edit edit -> edits := edit :: !edits
      | _ -> ())
  in
  let on_submit = Event.Handler.create ~name:"text-submit" (fun _ -> ()) in
  let on_focus_changed = Event.Handler.create ~name:"focus-changed" (fun _ -> ()) in
  let key = Key.string "editor" in
  let value text offset =
    let selection =
      Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
    in
    Ui.Text_editing.Value.create ~text ~selection ()
  in
  let tree ~document_revision ~accepted_local_revision ~update_mode value =
    Widget.text_input
      ~key
      ~session_id:7L
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ()
  in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (tree
         ~document_revision:1L
         ~accepted_local_revision:0L
         ~update_mode:Ui.Text_editing.Force_replace
         (value "A😀" 3))
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (tree
         ~document_revision:2L
         ~accepted_local_revision:1L
         ~update_mode:Ui.Text_editing.Correction
         (value "A😀!" 4))
  in
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "text input prop updates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  let editor = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let binding = binding_exn editor Event.Tag.Text_edit in
  let registry = Handler_registry.create ~runtime_epoch:60L in
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.frame_presented registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = 60L
       ; displayed_revision = 2L
       ; node_id = editor.node_id
       ; event_tag = Event.Tag.Text_edit
       ; handler_id = binding.handler_id
       ; event_sequence = 1L
       ; payload =
           Event.Payload.Text_edit
             { session_id = 7L
             ; local_revision = 2L
             ; base_document_revision = 2L
             ; text = "A😀!!"
             ; selection = { start_utf16 = 5; end_utf16 = 5 }
             ; composing = None
             }
       });
  check_int ~expected:1 ~actual:(List.length !edits) "typed text edit count";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let tests =
  [ "initial mount is a full snapshot", test_initial_mount_is_full_snapshot
  ; "physical equality emits no patch", test_physical_equality_emits_no_patch
  ; "one text change is one prop update", test_one_text_change_is_one_prop_update
  ; "keyed reorder preserves identity", test_keyed_reorder_preserves_identity
  ; ( "keyed insert and delete are incremental"
    , test_keyed_insert_and_delete_are_incremental )
  ; "kind replacement remounts", test_kind_replacement_remounts
  ; ( "duplicate keys fail without consuming IDs"
    , test_duplicate_keys_fail_without_consuming_ids )
  ; "nested duplicate keys fail", test_nested_duplicate_keys_fail
  ; ( "mixed keyed and unkeyed children match by index"
    , test_mixed_keyed_and_unkeyed_match_by_index )
  ; "nested removal drops complete subtree", test_nested_removal_drops_complete_subtree
  ; ( "handler change gets a new ID and one-revision grace"
    , test_handler_change_gets_new_id_and_one_revision_grace )
  ; "unchanged handler reuses ID", test_unchanged_handler_reuses_id
  ; ( "handler registry validates epoch, sequence, and binding"
    , test_handler_registry_validates_epoch_sequence_and_binding )
  ; "handler exception is structured", test_handler_exception_is_structured
  ; ( "handler retirement is separate from presentation marking"
    , test_handler_retirement_is_separate_from_presentation_marking )
  ; "node IDs are never reused", test_node_ids_are_never_reused
  ; ( "10,000 keyed children reverse in linear shape"
    , test_ten_thousand_keyed_children_reverse_in_linear_shape )
  ; "randomized patch invariant", test_randomized_patch_invariant
  ; ( "layout, Material, and semantics widgets update incrementally"
    , test_layout_material_and_semantics_widgets_are_incremental )
  ; ( "text input props and typed edit are incremental"
    , test_text_input_props_and_typed_edit_are_incremental )
  ]
;;

let () =
  Printexc.record_backtrace true;
  let failures = ref [] in
  List.iter
    (fun (name, test) ->
       try
         test ();
         Printf.printf "ok - %s\n%!" name
       with
       | exception_ ->
         failures := (name, exception_, Printexc.get_backtrace ()) :: !failures;
         Printf.eprintf "not ok - %s\n%!" name)
    tests;
  match List.rev !failures with
  | [] -> ()
  | failures ->
    List.iter
      (fun (name, exception_, backtrace) ->
         Printf.eprintf "\n%s\n%s\n%s\n%!" name (Printexc.to_string exception_) backtrace)
      failures;
    exit 1
;;
