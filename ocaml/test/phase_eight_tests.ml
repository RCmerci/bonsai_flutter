module Protocol = Bonsai_flutter_protocol

let fail message = raise (Failure message)
let check condition message = if not condition then fail message

let test_runtime_stats_round_trip () =
  let stats : Protocol.Wire_frame.runtime_stats =
    { event_batch_size = 3
    ; bonsai_flush_ns = 11L
    ; result_read_ns = 12L
    ; reconcile_ns = 13L
    ; encode_ns = 14L
    ; patch_count = 2
    ; patch_bytes = 80
    ; lifecycle_ns = 15L
    ; full_snapshot_count = 1
    ; resync_count = 0
    }
  in
  let frame : Protocol.Wire_frame.t =
    { runtime_epoch = 9L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = 1L
            ; kind = Empty
            ; props = Empty_props
            ; event_bindings = []
            ; parent_data = No_parent_data
            }
        ; Set_root 1L
        ; Runtime_stats stats
        ]
    }
  in
  let encoded =
    match Protocol.Binary_codec.encode frame with
    | Ok bytes -> bytes
    | Error error -> fail error.message
  in
  let decoded =
    match Protocol.Binary_codec.decode encoded with
    | Ok frame -> frame
    | Error error -> fail error.message
  in
  check (Int64.equal decoded.runtime_epoch frame.runtime_epoch) "runtime epoch";
  check (decoded.kind = frame.kind) "frame kind";
  match List.rev decoded.operations with
  | Protocol.Wire_frame.Runtime_stats decoded_stats :: _ ->
    check
      (decoded_stats.event_batch_size = stats.event_batch_size)
      "runtime event batch size";
    check (Int64.equal decoded_stats.bonsai_flush_ns stats.bonsai_flush_ns) "flush";
    check (Int64.equal decoded_stats.result_read_ns stats.result_read_ns) "result";
    check (Int64.equal decoded_stats.reconcile_ns stats.reconcile_ns) "reconcile";
    check (Int64.equal decoded_stats.encode_ns stats.encode_ns) "encode";
    check (decoded_stats.patch_count = stats.patch_count) "patch count";
    check (decoded_stats.patch_bytes = stats.patch_bytes) "patch bytes";
    check (Int64.equal decoded_stats.lifecycle_ns stats.lifecycle_ns) "lifecycle";
    check
      (decoded_stats.full_snapshot_count = stats.full_snapshot_count)
      "full snapshot count";
    check (decoded_stats.resync_count = stats.resync_count) "resync count"
  | _ -> fail "runtime stats operation"
;;

let test_debug_tree () =
  let tree =
    Bonsai_flutter_ui.Widget.column
      ~key:(Bonsai_flutter_ui.Key.string "main")
      [ Bonsai_flutter_ui.Widget.text "Count: 0"
      ; Bonsai_flutter_ui.Widget.button
          ~on_press:(Bonsai_flutter_ui.Event.Handler.create (fun _ -> ()))
          ~child:(Bonsai_flutter_ui.Widget.text "Increment")
          ()
      ]
  in
  check
    (String.equal
       (Bonsai_flutter_ui.Debug.dump_tree tree)
       "Column key=\"main\"\n\
       \  Text \"Count: 0\"\n\
       \  Button events=[press]\n\
       \    Text \"Increment\"")
    "deterministic debug tree"
;;

let test_full_semantics () =
  let semantics =
    Bonsai_flutter_ui.Semantics.create
      ~label:"Accept terms"
      ~hint:"Double tap to toggle"
      ~value:"Not accepted"
      ~role:Bonsai_flutter_ui.Semantics.Role.Checkbox
      ~enabled:true
      ~selected:false
      ~checked:false
      ~focusable:true
      ~live_region:true
      ~heading_level:2
      ~sort_key:3.5
      ~actions:[ Bonsai_flutter_ui.Semantics.Action.Tap ]
      ()
  in
  let view = Bonsai_flutter_ui.Semantics.Private.view semantics in
  check
    (view.role = Bonsai_flutter_ui.Semantics.Role.Checkbox
     && view.heading_level = Some 2
     && view.actions = [ Bonsai_flutter_ui.Semantics.Action.Tap ])
    "full accessibility semantics"
;;

let () =
  test_runtime_stats_round_trip ();
  test_debug_tree ();
  test_full_semantics ()
;;
