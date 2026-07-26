module Protocol = Bonsai_flutter_protocol
module Runtime = Bonsai_flutter_runtime
module Ui = Bonsai_flutter_ui

let fail format = Printf.ksprintf failwith format

let reconcile_exn reconciler ~base_revision ~target_revision ~old widget =
  match
    Runtime.Reconciler.reconcile reconciler ~base_revision ~target_revision ~old widget
  with
  | Ok output -> output
  | Error error -> fail "%s" (Runtime.Runtime_error.to_string error)
;;

let benchmark name iterations operation =
  Gc.compact ();
  let started = Unix.gettimeofday () in
  for iteration = 1 to iterations do
    operation iteration
  done;
  let elapsed = Unix.gettimeofday () -. started in
  let microseconds = elapsed *. 1_000_000. /. Float.of_int iterations in
  Printf.printf "%-34s %10.2f us/op  (%d iterations)\n%!" name microseconds iterations
;;

let text_children count =
  List.init count (fun index ->
    Ui.Widget.text ~key:(Ui.Key.int index) (Printf.sprintf "Item %d" index))
;;

let mount widget =
  let reconciler = Runtime.Reconciler.create ~runtime_epoch:1L in
  let output =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None widget
  in
  reconciler, output.mounted_tree
;;

let benchmark_unchanged () =
  let widget = Ui.Widget.column (text_children 1000) in
  let reconciler, initial = mount widget in
  let tree = ref initial in
  let revision = ref 1L in
  benchmark "unchanged tree physical equality" 1000 (fun _ ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        widget
    in
    if not (Runtime.Frame_patch.is_empty output.frame_patch)
    then fail "unchanged tree emitted a patch";
    tree := output.mounted_tree;
    revision := target)
;;

let benchmark_one_prop () =
  let reconciler, initial = mount (Ui.Widget.text "Value 0") in
  let tree = ref initial in
  let revision = ref 1L in
  benchmark "one prop changed" 10000 (fun iteration ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        (Ui.Widget.text (Printf.sprintf "Value %d" (iteration land 1)))
    in
    tree := output.mounted_tree;
    revision := target)
;;

let benchmark_full_snapshot count iterations =
  benchmark (Printf.sprintf "%d siblings full snapshot" count) iterations (fun _ ->
    ignore (mount (Ui.Widget.column (text_children count))))
;;

let benchmark_keyed_reverse count iterations =
  let ascending = List.init count Fun.id in
  let descending = List.rev ascending in
  let view indices =
    Ui.Widget.column
      (List.map
         (fun index ->
            Ui.Widget.text ~key:(Ui.Key.int index) (Printf.sprintf "Item %d" index))
         indices)
  in
  let reconciler, initial = mount (view ascending) in
  let tree = ref initial in
  let revision = ref 1L in
  benchmark
    (Printf.sprintf "%d keyed siblings reverse" count)
    iterations
    (fun iteration ->
       let target = Int64.succ !revision in
       let output =
         reconcile_exn
           reconciler
           ~base_revision:!revision
           ~target_revision:target
           ~old:(Some !tree)
           (view (if iteration land 1 = 0 then ascending else descending))
       in
       tree := output.mounted_tree;
       revision := target)
;;

let benchmark_keyed_edit name edit =
  let base = List.init 1000 Fun.id in
  let changed = edit base in
  let view indices =
    Ui.Widget.column
      (List.map
         (fun index -> Ui.Widget.text ~key:(Ui.Key.int index) (Int.to_string index))
         indices)
  in
  benchmark name 200 (fun iteration ->
    let reconciler, initial = mount (view base) in
    ignore
      (reconcile_exn
         reconciler
         ~base_revision:1L
         ~target_revision:2L
         ~old:(Some initial)
         (view (if iteration land 1 = 0 then changed else base))))
;;

let benchmark_handler_change () =
  let view () =
    Ui.Widget.button
      ~on_press:(Ui.Event.Handler.create (fun _ -> ()))
      ~child:(Ui.Widget.text "Press")
      ()
  in
  let reconciler, initial = mount (view ()) in
  let tree = ref initial in
  let revision = ref 1L in
  benchmark "handler-only change" 10000 (fun _ ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        (view ())
    in
    tree := output.mounted_tree;
    revision := target)
;;

let protocol_frame count =
  let operations =
    List.init count (fun index ->
      Protocol.Wire_frame.Create_node
        { node_id = Int64.of_int (index + 1)
        ; kind = Text
        ; props = Text_props { value = Printf.sprintf "Item %d" index }
        ; event_bindings = []
        ; parent_data = No_parent_data
        })
  in
  Protocol.Wire_frame.
    { runtime_epoch = 1L
    ; base_revision = 0L
    ; target_revision = 1L
    ; kind = Full_snapshot
    ; operations
    }
;;

let encode_exn frame =
  match Protocol.Binary_codec.encode frame with
  | Ok bytes -> bytes
  | Error error -> fail "%s" error.message
;;

let decode_exn bytes =
  match Protocol.Binary_codec.decode bytes with
  | Ok frame -> frame
  | Error error -> fail "%s" error.message
;;

let benchmark_protocol () =
  let full = protocol_frame 1000 in
  let encoded = encode_exn full in
  let incremental =
    Protocol.Wire_frame.
      { runtime_epoch = 1L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props { node_id = 1L; props = Text_props { value = "Changed" } } ]
      }
  in
  benchmark "protocol encode full snapshot" 500 (fun _ -> ignore (encode_exn full));
  benchmark "protocol decode full snapshot" 500 (fun _ -> ignore (decode_exn encoded));
  benchmark "protocol encode incremental" 10000 (fun _ -> ignore (encode_exn incremental));
  let encoded_incremental = encode_exn incremental in
  benchmark "protocol decode incremental" 10000 (fun _ ->
    ignore (decode_exn encoded_incremental))
;;

let () =
  Printf.printf "bonsai_flutter OCaml benchmark\n%!";
  benchmark_unchanged ();
  benchmark_one_prop ();
  benchmark_full_snapshot 1000 100;
  benchmark_full_snapshot 10000 10;
  benchmark_keyed_edit "insert at front (1000 keyed)" (fun values -> -1 :: values);
  benchmark_keyed_edit "delete middle (1000 keyed)" (fun values ->
    List.filteri (fun index _ -> index <> 500) values);
  benchmark_keyed_reverse 1000 100;
  benchmark_keyed_reverse 10000 10;
  benchmark_handler_change ();
  benchmark_protocol ()
;;
