module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

let native_kind_id = ID.Native_widget.Kind_id.of_int
let native_event_id = ID.Native_widget.Event_id.of_int
let check condition message = if not condition then failwith message

let expect_invalid_argument f message =
  match f () with
  | exception Invalid_argument _ -> ()
  | exception error -> raise error
  | () -> failwith message
;;

let widget_of_vertical_viewport viewport =
  viewport
  |> Ui.Widget.Viewport.Vertical.with_height ~height:240.
  |> Ui.Widget.For_testing.children
  |> fun children -> children.(0)
;;

let sliver_range_handler callback =
  Ui.Event.Handler.create (fun payload ->
    Option.iter callback (Ui.Widget.Sliver.visible_range_of_payload payload))
;;

let sliver_override index extent : Ui.Widget.Sparse_extent_override.t = { index; extent }

let scroll_view_child viewport =
  let (Av view) = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  view.children.(0).widget
;;

let keyed ~key widget = Ui.Widget.Keyed.create ~key widget

let test_keyed_widget_root_evidence () =
  let old_key = Ui.Key.string "old-root" in
  let new_key = Ui.Key.string "new-root" in
  let test_id = Ui.Test_id.string "keyed-root" in
  let original =
    Ui.Widget.text ~key:old_key "Keyed row" |> Ui.Widget.with_test_id test_id
  in
  let canonical =
    Ui.Widget.text ~key:new_key "Keyed row" |> Ui.Widget.with_test_id test_id
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:1
          ~first_index:0
          ~item_extent:48.
          ~items:[ keyed ~key:new_key original ]
          ~on_visible_range:(sliver_range_handler (fun _ -> ()))
          ()
      ]
      ()
  in
  let (Av original_view) = Ui.Widget.Private.view original in
  let (Av canonical_view) = Ui.Widget.Private.view canonical in
  let (Av sliver_view) = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length sliver_view.children = 1) "keyed item added a wrapper node";
  let (Av keyed_view) = Ui.Widget.Private.view sliver_view.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag keyed_view.node)
       Ui.Widget.Private.K_text)
    "keyed item changed the root widget kind";
  check (Array.length keyed_view.children = 0) "keyed item changed root children";
  check
    (Option.equal Ui.Key.equal original_view.key (Some old_key))
    "keyed construction mutated the input widget";
  check
    (Option.equal Ui.Key.equal keyed_view.key (Some new_key))
    "keyed construction did not replace the root key";
  check
    (Option.equal Ui.Test_id.equal keyed_view.test_id (Some test_id))
    "keyed construction lost the root test ID";
  check
    (Int64.equal keyed_view.fingerprint canonical_view.fingerprint)
    "keyed construction did not recompute the canonical root fingerprint"
;;

let test_sliver_box_and_scroll_view () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.box (Ui.Widget.text "Hi") ]
      ()
  in
  let (Av sv) = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag sv.node)
       Ui.Widget.Private.K_scroll_view)
    "scroll view kind";
  check (Array.length sv.children = 1) "scroll view has one sliver child";
  let (Av bv) = Ui.Widget.Private.view sv.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag bv.node)
       Ui.Widget.Private.K_sliver_box)
    "sliver box kind";
  check (Array.length bv.children = 1) "sliver box has one child"
;;

let test_sliver_fixed_extent_contract () =
  let received = ref None in
  let items =
    List.init 20 (fun i ->
      let logical_index = 100 + i in
      keyed ~key:(Ui.Key.int logical_index) (Ui.Widget.text (string_of_int logical_index)))
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.fixed_extent
          ~key:(Ui.Key.string "large-list")
          ~total_count:50_000
          ~first_index:100
          ~item_extent:48.
          ~overscan:4
          ~items
          ~on_visible_range:(sliver_range_handler (fun range -> received := Some range))
          ()
      ]
      ()
  in
  let (Av fv) = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length fv.children = 20) "only the supplied window is mounted";
  Array.iteri
    (fun index (child : Ui.Widget.Private.child) ->
       let (Av child_view) = Ui.Widget.Private.view child.widget in
       check
         (Option.equal Ui.Key.equal child_view.key (Some (Ui.Key.int (100 + index))))
         "fixed extent lost a keyed item root")
    fv.children;
  (match fv.node with
   | Ui.Widget.Private.Sliver_fixed_extent
       { total_count; first_index; item_extent; overscan } ->
     check (total_count = 50_000) "fixed total count";
     check (first_index = 100) "fixed first index";
     check (Float.equal item_extent 48.) "fixed item extent";
     check (overscan = 4) "fixed overscan"
   | _ -> failwith "fixed extent node");
  let binding = fv.event_bindings.(0) in
  check
    (Ui.Event.Tag.equal binding.tag Ui.Event.Tag.Visible_range_changed)
    "fixed extent visible range binding";
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Visible_range { first_index = 104L; last_exclusive = 116L });
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 104L) "visible first index";
    check (Int64.equal last_exclusive 116L) "visible last index"
  | None -> failwith "visible range callback"
;;

let test_sliver_window_materialization_ranges () =
  let check_range
        ~label
        ~total_count
        ~overscan
        ~visible_first_index
        ~visible_last_exclusive
        ~expected_first_index
        ~expected_last_exclusive
    =
    let range =
      Ui.Widget.Sliver.Window.create
        ~total_count
        ~overscan
        ~visible_first_index
        ~visible_last_exclusive
    in
    check
      (range.first_index = expected_first_index
       && range.last_exclusive = expected_last_exclusive)
      label
  in
  check_range
    ~label:"empty collection window"
    ~total_count:0
    ~overscan:4
    ~visible_first_index:0
    ~visible_last_exclusive:0
    ~expected_first_index:0
    ~expected_last_exclusive:0;
  check_range
    ~label:"leading window clamp"
    ~total_count:100
    ~overscan:4
    ~visible_first_index:1
    ~visible_last_exclusive:8
    ~expected_first_index:0
    ~expected_last_exclusive:12;
  check_range
    ~label:"middle window expansion"
    ~total_count:100
    ~overscan:4
    ~visible_first_index:20
    ~visible_last_exclusive:28
    ~expected_first_index:16
    ~expected_last_exclusive:32;
  check_range
    ~label:"trailing window clamp"
    ~total_count:100
    ~overscan:4
    ~visible_first_index:95
    ~visible_last_exclusive:100
    ~expected_first_index:91
    ~expected_last_exclusive:100;
  check_range
    ~label:"overscan larger than collection"
    ~total_count:5
    ~overscan:100
    ~visible_first_index:2
    ~visible_last_exclusive:3
    ~expected_first_index:0
    ~expected_last_exclusive:5;
  List.iter
    (fun build -> expect_invalid_argument build "invalid materialization range accepted")
    [ (fun () ->
        ignore
          (Ui.Widget.Sliver.Window.create
             ~total_count:(-1)
             ~overscan:0
             ~visible_first_index:0
             ~visible_last_exclusive:0))
    ; (fun () ->
        ignore
          (Ui.Widget.Sliver.Window.create
             ~total_count:10
             ~overscan:(-1)
             ~visible_first_index:0
             ~visible_last_exclusive:1))
    ; (fun () ->
        ignore
          (Ui.Widget.Sliver.Window.create
             ~total_count:10
             ~overscan:0
             ~visible_first_index:5
             ~visible_last_exclusive:4))
    ; (fun () ->
        ignore
          (Ui.Widget.Sliver.Window.create
             ~total_count:10
             ~overscan:0
             ~visible_first_index:0
             ~visible_last_exclusive:11))
    ]
;;

let test_sliver_varied_extent_contract () =
  let received = ref None in
  let items =
    List.init 6 (fun i ->
      let logical_index = 40 + i in
      keyed ~key:(Ui.Key.int logical_index) (Ui.Widget.text (string_of_int logical_index)))
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.varied_extent
          ~key:(Ui.Key.string "sparse-list")
          ~total_count:50_000
          ~first_index:40
          ~default_item_extent:48.
          ~extent_overrides:[ sliver_override 3 120.; sliver_override 42 312. ]
          ~overscan:5
          ~items
          ~on_visible_range:(sliver_range_handler (fun range -> received := Some range))
          ()
      ]
      ()
  in
  let (Av vv) = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length vv.children = 6) "varied extent mounted window";
  Array.iteri
    (fun index (child : Ui.Widget.Private.child) ->
       let (Av child_view) = Ui.Widget.Private.view child.widget in
       check
         (Option.equal Ui.Key.equal child_view.key (Some (Ui.Key.int (40 + index))))
         "varied extent lost a keyed item root")
    vv.children;
  (match vv.node with
   | Ui.Widget.Private.Sliver_varied_extent
       { total_count
       ; first_index
       ; default_item_extent
       ; extent_overrides
       ; overscan
       ; transition
       } ->
     check (total_count = 50_000) "varied total count";
     check (first_index = 40) "varied first index";
     check (Float.equal default_item_extent 48.) "varied default extent";
     check (overscan = 5) "varied overscan";
     check (transition = None) "varied default transition";
     check
       (extent_overrides = [ sliver_override 3 120.; sliver_override 42 312. ])
       "varied overrides round trip"
   | _ -> failwith "varied extent node");
  let binding = vv.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Visible_range { first_index = 41L; last_exclusive = 44L });
  match !received with
  | Some { Ui.Event.Payload.first_index; last_exclusive } ->
    check (Int64.equal first_index 41L) "varied visible first index";
    check (Int64.equal last_exclusive 44L) "varied visible last index"
  | None -> failwith "varied visible range callback"
;;

let test_sliver_varied_extent_transition () =
  let transition =
    Ui.Widget.Sparse_extent_transition.create
      ~expand_duration_ms:240
      ~collapse_duration_ms:190
      ~expand_curve:Ease_out_cubic
      ~collapse_curve:Ease_in_out_cubic
      ()
  in
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.varied_extent
          ~total_count:20
          ~first_index:4
          ~default_item_extent:88.
          ~extent_overrides:[ sliver_override 6 320. ]
          ~overscan:4
          ~transition
          ~items:[ keyed ~key:(Ui.Key.string "transition-item") (Ui.Widget.empty ()) ]
          ~on_visible_range:(sliver_range_handler (fun _ -> ()))
          ()
      ]
      ()
  in
  let (Av vv) = Ui.Widget.Private.view (scroll_view_child viewport) in
  match vv.node with
  | Ui.Widget.Private.Sliver_varied_extent { transition = Some decoded; _ } ->
    let open Ui.Widget.Sparse_extent_transition in
    check (enabled decoded) "transition enabled";
    check (expand_duration_ms decoded = 240) "expand duration";
    check (collapse_duration_ms decoded = 190) "collapse duration";
    check (expand_curve decoded = Ease_out_cubic) "expand curve";
    check (collapse_curve decoded = Ease_in_out_cubic) "collapse curve"
  | _ -> failwith "varied extent transition node"
;;

let test_sliver_varied_extent_validation () =
  let create
        ?(total_count = 10)
        ?(first_index = 0)
        ?(default_item_extent = 48.)
        ?(extent_overrides = [])
        ?(overscan = 2)
        ?(items = [])
        ()
    =
    ignore
      (Ui.Widget.Scroll_view.vertical
         ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
         [ Ui.Widget.Sliver.varied_extent
             ~total_count
             ~first_index
             ~default_item_extent
             ~extent_overrides
             ~overscan
             ~items
             ~on_visible_range:(sliver_range_handler (fun _ -> ()))
             ()
         ]
         ())
  in
  List.iter
    (fun (build, message) -> expect_invalid_argument build message)
    [ (fun () -> create ~total_count:(-1) ()), "sliver accepted a negative total"
    ; (fun () -> create ~first_index:11 ()), "sliver accepted an invalid first index"
    ; ( (fun () -> create ~default_item_extent:Float.nan ())
      , "sliver accepted a non-finite default extent" )
    ; ( (fun () -> create ~default_item_extent:0. ())
      , "sliver accepted a non-positive default extent" )
    ; (fun () -> create ~overscan:(-1) ()), "sliver accepted negative overscan"
    ; (fun () -> create ~overscan:0x1_0000_0000 ()), "sliver accepted overscan above u32"
    ; ( (fun () -> create ~extent_overrides:[ sliver_override (-1) 80. ] ())
      , "sliver accepted a negative override index" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 10 80. ] ())
      , "sliver accepted an out-of-bounds override index" )
    ; ( (fun () ->
          create ~extent_overrides:[ sliver_override 4 80.; sliver_override 3 90. ] ())
      , "sliver accepted unsorted overrides" )
    ; ( (fun () ->
          create ~extent_overrides:[ sliver_override 3 80.; sliver_override 3 90. ] ())
      , "sliver accepted duplicate overrides" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 3 Float.infinity ] ())
      , "sliver accepted a non-finite override extent" )
    ; ( (fun () -> create ~extent_overrides:[ sliver_override 3 0. ] ())
      , "sliver accepted a non-positive override extent" )
    ; ( (fun () ->
          create
            ~total_count:2
            ~first_index:1
            ~items:
              [ keyed ~key:(Ui.Key.string "first") (Ui.Widget.empty ())
              ; keyed ~key:(Ui.Key.string "second") (Ui.Widget.empty ())
              ]
            ())
      , "sliver accepted a child window beyond total_count" )
    ]
;;

let test_sliver_fixed_extent_wire_validation () =
  let create overscan =
    Ui.Widget.Sliver.fixed_extent
      ~total_count:1
      ~first_index:0
      ~item_extent:48.
      ~overscan
      ~items:[]
      ~on_visible_range:(sliver_range_handler (fun _ -> ()))
      ()
  in
  ignore (create 0);
  ignore (create 0xffff_ffff);
  expect_invalid_argument
    (fun () -> ignore (create (-1)))
    "fixed sliver accepted negative overscan";
  expect_invalid_argument
    (fun () -> ignore (create 0x1_0000_0000))
    "fixed sliver accepted overscan above u32"
;;

let test_sparse_extent_transition_wire_validation () =
  let create duration =
    Ui.Widget.Sparse_extent_transition.create
      ~expand_duration_ms:duration
      ~collapse_duration_ms:duration
      ()
  in
  ignore (create 0);
  ignore (create 0xffff_ffff);
  expect_invalid_argument
    (fun () -> ignore (create (-1)))
    "transition accepted a negative duration";
  expect_invalid_argument
    (fun () -> ignore (create 0x1_0000_0000))
    "transition accepted a duration above u32"
;;

let test_sliver_fill_and_padding () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Widget.Sliver.padding
          ~insets:(Ui.Layout.Edge_insets.all 8.)
          (Ui.Widget.Sliver.fill (Ui.Widget.text "Fill"))
      ]
      ()
  in
  let (Av sv) = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  let (Av pad) = Ui.Widget.Private.view sv.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag pad.node)
       Ui.Widget.Private.K_sliver_padding)
    "sliver padding kind";
  let (Av fill) = Ui.Widget.Private.view pad.children.(0).widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag fill.node)
       Ui.Widget.Private.K_sliver_fill)
    "sliver fill kind";
  match fill.node with
  | Ui.Widget.Private.Sliver_fill -> ()
  | _ -> failwith "sliver fill node"
;;

let test_sliver_app_bar_contract () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Material.App_bar.sliver
          ~pinned:true
          ~variant:Ui.Material.App_bar.Large
          ~shape:Ui.Material.App_bar.Square
          ~density:Ui.Material.App_bar.Compact
          ~actions:[ Ui.Widget.text "Search"; Ui.Widget.text "Settings" ]
          ~title:(Ui.Widget.text "Title")
          ()
      ]
      ()
  in
  let (Av app_bar) = Ui.Widget.Private.view (scroll_view_child viewport) in
  check (Array.length app_bar.children = 3) "app bar exposes every action";
  (match app_bar.node with
   | Ui.Widget.Private.Sliver_app_bar { action_count; variant; shape; density; _ } ->
     check (action_count = 2) "app bar action count";
     check (variant = 2 && shape = 1 && density = 1) "app bar expressive variants"
   | _ -> failwith "sliver app bar node");
  let child_text index =
    let (Av child) = Ui.Widget.Private.view app_bar.children.(index).widget in
    match child.node with
    | Ui.Widget.Private.Text { value; _ } -> Some value
    | _ -> None
  in
  check (child_text 0 = Some "Title") "app bar title order";
  check (child_text 1 = Some "Search") "app bar first action order";
  check (child_text 2 = Some "Settings") "app bar second action order";
  let empty_actions =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
      [ Ui.Material.App_bar.sliver ~actions:[] ~title:(Ui.Widget.text "Title") () ]
      ()
  in
  let (Av empty) = Ui.Widget.Private.view (scroll_view_child empty_actions) in
  match empty.node with
  | Ui.Widget.Private.Sliver_app_bar { action_count; _ } ->
    check (action_count = 0) "empty actions have a zero action count"
  | _ -> failwith "sliver app bar empty actions node"
;;

let test_sliver_app_bar_validation () =
  let create ?(floating = false) ?(snap = false) () =
    ignore (Ui.Material.App_bar.sliver ~floating ~snap ~title:(Ui.Widget.text "Title") ())
  in
  expect_invalid_argument
    (fun () -> create ~snap:true ())
    "sliver app bar accepted snap without floating"
;;

(* ------------------------------------------------------------------ *)
(* Scroll_view cache_extent auto-calculation (plan B, issues #2 / #3). *)
(* overscan on each virtualized sliver must drive the viewport-level    *)
(* cache_extent = max(child overscan * extent) so Flutter pre-renders   *)
(* the overscan window instead of running on the ~250px default.        *)
(* ------------------------------------------------------------------ *)

let scroll_view_cache_extent viewport =
  let (Av sv) = Ui.Widget.Private.view (widget_of_vertical_viewport viewport) in
  match sv.node with
  | Ui.Widget.Private.Scroll_view { cache_extent; _ } -> cache_extent
  | _ -> failwith "expected scroll view node"
;;

let widget_of_horizontal_viewport viewport =
  viewport
  |> Ui.Widget.Viewport.Horizontal.with_width ~width:240.
  |> Ui.Widget.For_testing.children
  |> fun children -> children.(0)
;;

let horizontal_scroll_view_cache_extent viewport =
  let (Av sv) = Ui.Widget.Private.view (widget_of_horizontal_viewport viewport) in
  match sv.node with
  | Ui.Widget.Private.Scroll_view { cache_extent; _ } -> cache_extent
  | _ -> failwith "expected scroll view node"
;;

let no_scroll = Ui.Event.Handler.create (fun _ -> ())
let no_range = sliver_range_handler (fun _ -> ())

let test_scroll_view_cache_extent_auto_fixed () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:50_000
          ~first_index:0
          ~item_extent:48.
          ~overscan:4
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 192.) "fixed overscan*extent cache extent (4*48)"
  | None -> failwith "expected auto cache extent for fixed sliver"
;;

let test_scroll_view_cache_extent_auto_varied () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.varied_extent
          ~total_count:50_000
          ~first_index:0
          ~default_item_extent:48.
          ~extent_overrides:[]
          ~overscan:5
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 240.) "varied overscan*extent cache extent (5*48)"
  | None -> failwith "expected auto cache extent for varied sliver"
;;

let test_scroll_view_cache_extent_auto_max () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.box (Ui.Widget.text "header")
      ; Ui.Widget.Sliver.fixed_extent
          ~total_count:50_000
          ~first_index:0
          ~item_extent:48.
          ~overscan:4
          ~items:[]
          ~on_visible_range:no_range
          ()
      ; Ui.Widget.Sliver.varied_extent
          ~total_count:50_000
          ~first_index:0
          ~default_item_extent:48.
          ~extent_overrides:[]
          ~overscan:5
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 240.) "max overscan*extent across slivers"
  | None -> failwith "expected auto cache extent for mixed slivers"
;;

let test_scroll_view_cache_extent_auto_none () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.box (Ui.Widget.text "Hi") ]
      ()
  in
  check
    (scroll_view_cache_extent viewport = None)
    "no virtualized sliver leaves cache extent None"
;;

let test_scroll_view_cache_extent_explicit_wins () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      ~cache_extent:500.
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:50_000
          ~first_index:0
          ~item_extent:48.
          ~overscan:4
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 500.) "explicit cache extent overrides auto-calc"
  | None -> failwith "expected explicit cache extent to be preserved"
;;

let test_scroll_view_cache_extent_padding_recurse () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.padding
          ~insets:(Ui.Layout.Edge_insets.all 8.)
          (Ui.Widget.Sliver.fixed_extent
             ~total_count:50_000
             ~first_index:0
             ~item_extent:80.
             ~overscan:3
             ~items:[]
             ~on_visible_range:no_range
             ())
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 240.) "padding-wrapped sliver recurses (3*80)"
  | None -> failwith "expected auto cache extent for padded sliver"
;;

let test_scroll_view_cache_extent_default_overscan () =
  let viewport =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:50_000
          ~first_index:0
          ~item_extent:80.
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match scroll_view_cache_extent viewport with
  | Some ce -> check (Float.equal ce 160.) "default overscan 2 drives cache extent (2*80)"
  | None -> failwith "expected auto cache extent for default overscan"
;;

let test_scroll_view_cache_extent_horizontal () =
  let viewport =
    Ui.Widget.Scroll_view.horizontal
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:100
          ~first_index:0
          ~item_extent:50.
          ~overscan:3
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  match horizontal_scroll_view_cache_extent viewport with
  | Some ce ->
    check (Float.equal ce 150.) "horizontal overscan*extent cache extent (3*50)"
  | None -> failwith "expected auto cache extent for horizontal fixed sliver"
;;

let test_scroll_view_cache_extent_wire_validation () =
  let vertical cache_extent =
    Ui.Widget.Scroll_view.vertical ~cache_extent ~on_scroll:no_scroll [] ()
  in
  let horizontal cache_extent =
    Ui.Widget.Scroll_view.horizontal ~cache_extent ~on_scroll:no_scroll [] ()
  in
  ignore (vertical 0.);
  ignore (horizontal 0.);
  List.iter
    (fun cache_extent ->
       expect_invalid_argument
         (fun () -> ignore (vertical cache_extent))
         "vertical scroll view accepted invalid cache extent";
       expect_invalid_argument
         (fun () -> ignore (horizontal cache_extent))
         "horizontal scroll view accepted invalid cache extent")
    [ -1.; Float.nan; Float.infinity; Float.neg_infinity ];
  let max_u32 = 0xffff_ffff in
  let finite =
    Ui.Widget.Scroll_view.vertical
      ~on_scroll:no_scroll
      [ Ui.Widget.Sliver.fixed_extent
          ~total_count:1
          ~first_index:0
          ~item_extent:Float.max_float
          ~overscan:1
          ~items:[]
          ~on_visible_range:no_range
          ()
      ]
      ()
  in
  (match scroll_view_cache_extent finite with
   | Some extent ->
     check (Float.is_finite extent) "largest derived cache extent is finite"
   | None -> failwith "largest finite derived cache extent was omitted");
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Widget.Scroll_view.vertical
            ~on_scroll:no_scroll
            [ Ui.Widget.Sliver.fixed_extent
                ~total_count:1
                ~first_index:0
                ~item_extent:Float.max_float
                ~overscan:max_u32
                ~items:[]
                ~on_visible_range:no_range
                ()
            ]
            ()))
    "derived cache extent overflow was accepted"
;;

type dial_event = Changed of int

let dial_extension =
  Ui.Native_widget.Extension.create
    ~kind_id:(native_kind_id 42)
    ~version:3
    ~capabilities:[ Ui.Native_widget.Capability.Stateful ]
    ~encode_props:(fun value -> Bytes.of_string (string_of_int value))
    ~decode_event:(fun ~event_id payload ->
      if ID.Native_widget.Event_id.equal event_id (native_event_id 7)
      then Ok (Changed (int_of_string (Bytes.to_string payload)))
      else Error "unknown dial event")
    ()
;;

let test_typed_native_widget () =
  let received = ref None in
  let widget =
    Ui.Native_widget.widget
      dial_extension
      ~key:(Ui.Key.string "dial")
      ~props:17
      ~on_event:(fun event -> received := Some event)
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check
    (Ui.Widget.Private.kind_tag_equal
       (Ui.Widget.Private.node_kind_tag view.node)
       Ui.Widget.Private.K_native_widget)
    "native widget kind";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 42)) "native kind ID";
     check (version = 3) "native version";
     check (Int64.equal capabilities 1L) "native capabilities";
     check (Bytes.equal payload (Bytes.of_string "17")) "native props payload"
   | _ -> failwith "native widget props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 42
       ; version = 3
       ; event_id = native_event_id 7
       ; payload = Bytes.of_string "23"
       });
  check (!received = Some (Changed 23)) "typed native event"
;;

let test_morphing_surface_contract () =
  let widget =
    Ui.Native_widget.Morphing_surface.create
      ~expanded:true
      ~compact_content:(Ui.Widget.text "Compact")
      ~expanded_content:(Ui.Widget.text "Expanded")
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check (Array.length view.children = 2) "morphing surface child slots";
  match view.node with
  | Native_widget { kind_id; version; capabilities; payload } ->
    check (kind_id = native_kind_id 5) "morphing surface kind ID";
    check (version = 1) "morphing surface version";
    check (Int64.equal capabilities 4L) "morphing surface capabilities";
    let props = Ui.Native_widget.Morphing_surface.For_testing.decode_props_exn payload in
    check props.expanded "morphing surface expanded state"
  | _ -> failwith "morphing surface native props"
;;

let slidable_background = Ui.Style.Color.rgb ~red:80 ~green:125 ~blue:88
let slidable_foreground = Ui.Style.Color.rgb ~red:250 ~green:250 ~blue:250

let slidable_action
      ?(enabled = true)
      ?(flex = 1)
      ?foreground
      ?(auto_close = true)
      ?(border_radius = 0.)
      ?padding
      ?alignment
      id
  =
  Ui.Native_widget.Slidable.action
    ~id
    ~enabled
    ~flex
    ?foreground
    ~background:slidable_background
    ~auto_close
    ~border_radius
    ?padding
    ?alignment
    ~child:(Ui.Widget.text (Printf.sprintf "Action %d" id))
    ()
;;

let slidable_pane
      ?dismissible
      ?(extent_ratio = 0.5)
      ?open_threshold
      ?close_threshold
      motion
      actions
  =
  Ui.Native_widget.Slidable.action_pane
    ~extent_ratio
    ~motion
    ?dismissible
    ?open_threshold
    ?close_threshold
    ~actions
    ()
;;

let test_slidable_props_children_and_events () =
  let module S = Ui.Native_widget.Slidable in
  let padding = Ui.Layout.Edge_insets.only ~left:1. ~top:2. ~right:3. ~bottom:4. () in
  let dismissible =
    S.dismissible
      ~dismiss_threshold:0.8
      ~dismissal_duration_ms:240
      ~resize_duration_ms:180
      ~close_on_cancel:true
      ~motion:Inversed_drawer
      ()
  in
  let start_action = slidable_action 1 in
  let icon_label_action =
    S.icon_label_action
      ~id:2
      ~flex:2
      ~foreground:slidable_foreground
      ~background:slidable_background
      ~auto_close:false
      ~border_radius:12.
      ~padding
      ~alignment:Ui.Layout.Alignment.Center_end
      ~spacing:6.
      ~icon:(Ui.Widget.icon ~code_point:0xe091 ())
      ~label:"Archive ✓"
      ()
  in
  let end_action = slidable_action ~enabled:false 3 in
  let events = ref [] in
  let widget =
    S.create
      ~key:(Ui.Key.string "slidable")
      ~enabled:true
      ~close_on_scroll:false
      ~direction:Ui.Layout.Axis.Vertical
      ~use_text_direction:false
      ~group_tag:"inbox-收件箱"
      ~start_action_pane:
        (slidable_pane
           ~dismissible
           ~extent_ratio:0.4
           ~open_threshold:0.2
           ~close_threshold:0.1
           Drawer
           [ start_action; icon_label_action ])
      ~end_action_pane:(slidable_pane ~extent_ratio:0.6 Stretch [ end_action ])
      ~content:(Ui.Widget.text "Message")
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check (Array.length view.children = 4) "slidable child slots are not canonical";
  check
    (Ui.Widget.For_testing.text_content view.children.(0).widget = Some "Message")
    "slidable content is not the first child";
  check
    (Ui.Widget.For_testing.text_content view.children.(1).widget = Some "Action 1")
    "start action order changed";
  let icon_label_child = view.children.(2).widget in
  check
    (String.equal (Ui.Widget.For_testing.kind_name icon_label_child) "Column")
    "icon-label action did not build a logical column";
  let icon_label_children = Ui.Widget.For_testing.children icon_label_child in
  check (Array.length icon_label_children = 3) "icon-label action child count";
  check
    (Ui.Widget.For_testing.text_content icon_label_children.(2) = Some "Archive ✓")
    "icon-label action label child";
  check
    (Ui.Widget.For_testing.text_content view.children.(3).widget = Some "Action 3")
    "end action order changed";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 2) "slidable kind ID";
     check (version = 3) "slidable schema version";
     check (Int64.equal capabilities 7L) "slidable capabilities";
     let props = S.For_testing.decode_props_exn payload in
     check props.enabled "slidable enabled";
     check (not props.close_on_scroll) "slidable close-on-scroll";
     check (props.direction = Ui.Layout.Axis.Vertical) "slidable axis";
     check (not props.use_text_direction) "slidable text-direction policy";
     check (props.group_tag = Some "inbox-收件箱") "slidable UTF-8 group tag";
     let start = Option.get props.start_action_pane in
     check (start.motion = Drawer) "start pane motion";
     check (Float.equal start.extent_ratio 0.4) "start pane extent";
     check (start.open_threshold = Some 0.2) "start pane open threshold";
     check (start.close_threshold = Some 0.1) "start pane close threshold";
     let dismissible = Option.get start.dismissible in
     check (Float.equal dismissible.dismiss_threshold 0.8) "dismiss threshold";
     check (dismissible.dismissal_duration_ms = 240) "dismiss duration";
     check (dismissible.resize_duration_ms = 180) "resize duration";
     check dismissible.close_on_cancel "dismiss close-on-cancel";
     check (List.length start.actions = 2) "start action count";
     let second = List.nth start.actions 1 in
     check (second.id = 2) "action ID";
     check (second.flex = 2) "action flex";
     check (not second.auto_close) "action auto-close";
     check (second.foreground = Some slidable_foreground) "action foreground";
     check (second.padding = Some padding) "action padding";
     check (second.alignment = Some Ui.Layout.Alignment.Center_end) "action alignment";
     let end_ = Option.get props.end_action_pane in
     check (end_.motion = Stretch) "end pane motion";
     check (not (List.hd end_.actions).enabled) "disabled action"
   | _ -> failwith "slidable native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 2
       ; version = 3
       ; event_id = S.action_pressed_event_id
       ; payload = S.For_testing.encode_action_pressed 2
       });
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 2
       ; version = 3
       ; event_id = S.dismissed_event_id
       ; payload = S.For_testing.encode_dismissed End
       });
  check
    (!events = [ S.Dismissed End; S.Action_pressed 2 ])
    "slidable typed event decoding"
;;

let test_slidable_defaults_all_motions_and_validation () =
  let module S = Ui.Native_widget.Slidable in
  let action = slidable_action 1 in
  List.iter
    (fun motion ->
       let widget =
         S.create
           ~key:(Ui.Key.int (Hashtbl.hash motion))
           ~start_action_pane:(slidable_pane motion [ action ])
           ~content:(Ui.Widget.empty ())
           ~on_event:(fun _ -> ())
           ()
       in
       let (Av view) = Ui.Widget.Private.view widget in
       match view.node with
       | Native_widget { payload; _ } ->
         let props = S.For_testing.decode_props_exn payload in
         check props.enabled "slidable enabled default";
         check props.close_on_scroll "slidable close-on-scroll default";
         check props.use_text_direction "slidable text direction default";
         check (props.direction = Ui.Layout.Axis.Horizontal) "slidable axis default";
         check ((Option.get props.start_action_pane).motion = motion) "pane motion"
       | _ -> failwith "slidable native props")
    [ Behind; Drawer; Scroll; Stretch ];
  expect_invalid_argument
    (fun () ->
       ignore
         (S.create
            ~key:(Ui.Key.string "none")
            ~content:(Ui.Widget.empty ())
            ~on_event:(fun _ -> ())
            ()))
    "slidable accepted no panes";
  expect_invalid_argument
    (fun () -> ignore (S.action_pane ~motion:Behind ~actions:[] ()))
    "slidable accepted an empty pane";
  List.iter
    (fun value ->
       expect_invalid_argument
         (fun () -> ignore (slidable_pane ~extent_ratio:value Behind [ action ]))
         "slidable accepted an invalid extent ratio";
       expect_invalid_argument
         (fun () -> ignore (slidable_pane ~open_threshold:value Behind [ action ]))
         "slidable accepted an invalid open threshold";
       expect_invalid_argument
         (fun () -> ignore (slidable_pane ~close_threshold:value Behind [ action ]))
         "slidable accepted an invalid close threshold";
       expect_invalid_argument
         (fun () -> ignore (S.dismissible ~dismiss_threshold:value ()))
         "slidable accepted an invalid dismiss threshold")
    [ 0.; -1.; Float.nan; Float.infinity ];
  List.iter
    (fun build -> expect_invalid_argument build "slidable accepted threshold 1")
    [ (fun () -> ignore (slidable_pane ~open_threshold:1. Behind [ action ]))
    ; (fun () -> ignore (slidable_pane ~close_threshold:1. Behind [ action ]))
    ; (fun () -> ignore (S.dismissible ~dismiss_threshold:1. ()))
    ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () -> ignore (slidable_action id))
         "slidable accepted an invalid action ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (slidable_action ~flex:0 1))
    "slidable accepted zero flex";
  List.iter
    (fun radius ->
       expect_invalid_argument
         (fun () -> ignore (slidable_action ~border_radius:radius 1))
         "slidable accepted an invalid action radius")
    [ -1.; Float.nan; Float.infinity ];
  List.iter
    (fun spacing ->
       expect_invalid_argument
         (fun () ->
            ignore
              (S.icon_label_action
                 ~id:1
                 ~background:slidable_background
                 ~spacing
                 ~icon:(Ui.Widget.empty ())
                 ~label:"Archive"
                 ()))
         "slidable accepted invalid icon-label spacing")
    [ -1.; Float.nan; Float.infinity ];
  expect_invalid_argument
    (fun () ->
       ignore
         (S.icon_label_action
            ~id:1
            ~background:slidable_background
            ~icon:(Ui.Widget.empty ())
            ~label:""
            ()))
    "slidable accepted an empty icon-label label";
  List.iter
    (fun duration ->
       expect_invalid_argument
         (fun () -> ignore (S.dismissible ~dismissal_duration_ms:duration ()))
         "slidable accepted an invalid dismiss duration";
       expect_invalid_argument
         (fun () -> ignore (S.dismissible ~resize_duration_ms:duration ()))
         "slidable accepted an invalid resize duration")
    [ -1; 0x1_0000_0000 ];
  let duplicate = slidable_action 7 in
  expect_invalid_argument
    (fun () ->
       ignore
         (S.create
            ~key:(Ui.Key.string "duplicate")
            ~start_action_pane:(slidable_pane Behind [ duplicate ])
            ~end_action_pane:(slidable_pane Scroll [ duplicate ])
            ~content:(Ui.Widget.empty ())
            ~on_event:(fun _ -> ())
            ()))
    "slidable accepted duplicate action IDs";
  List.iter
    (fun group_tag ->
       expect_invalid_argument
         (fun () ->
            ignore
              (S.create
                 ~key:(Ui.Key.string "group")
                 ~group_tag
                 ~start_action_pane:(slidable_pane Behind [ action ])
                 ~content:(Ui.Widget.empty ())
                 ~on_event:(fun _ -> ())
                 ()))
         "slidable accepted an invalid group tag")
    [ ""; "\255" ]
;;

let test_slidable_event_filtering () =
  let module S = Ui.Native_widget.Slidable in
  let received = ref [] in
  let widget =
    S.create
      ~key:(Ui.Key.string "events")
      ~start_action_pane:(slidable_pane Behind [ slidable_action 1 ])
      ~content:(Ui.Widget.empty ())
      ~on_event:(fun event -> received := event :: !received)
      ()
  in
  let binding =
    (let (Av view) = Ui.Widget.Private.view widget in
     view.event_bindings).(0)
  in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke (native_kind_id 99) 3 S.action_pressed_event_id (Bytes.make 4 '\000');
  invoke (native_kind_id 2) 2 S.action_pressed_event_id (Bytes.make 4 '\000');
  invoke (native_kind_id 2) 3 (native_event_id 99) (Bytes.make 4 '\000');
  invoke (native_kind_id 2) 3 S.action_pressed_event_id Bytes.empty;
  invoke (native_kind_id 2) 3 S.action_pressed_event_id (Bytes.make 5 '\000');
  invoke (native_kind_id 2) 3 S.action_pressed_event_id (Bytes.make 4 '\000');
  invoke (native_kind_id 2) 3 S.dismissed_event_id Bytes.empty;
  invoke (native_kind_id 2) 3 S.dismissed_event_id (Bytes.of_string "\002");
  check (!received = []) "malformed slidable event was not ignored";
  invoke
    (native_kind_id 2)
    3
    S.action_pressed_event_id
    (S.For_testing.encode_action_pressed 1);
  check (!received = [ S.Action_pressed 1 ]) "valid slidable event was filtered";
  check
    (S.event_of_payload
       (Native_event
          { kind_id = native_kind_id 2
          ; version = 3
          ; event_id = S.dismissed_event_id
          ; payload = S.For_testing.encode_dismissed Start
          })
     = Some (S.Dismissed Start))
    "slidable event_of_payload"
;;

let test_slidable_auto_close_behavior_contract () =
  let module A = Ui.Native_widget.Slidable_auto_close_behavior in
  let widget =
    A.create
      ~key:(Ui.Key.string "auto-close")
      ~close_when_opened:false
      ~close_when_tapped:true
      ~child:(Ui.Widget.text "List")
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check (Array.length view.children = 1) "auto-close behavior child count";
  check
    (Ui.Widget.For_testing.text_content view.children.(0).widget = Some "List")
    "auto-close behavior child";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 8) "auto-close behavior kind ID";
     check (version = 1) "auto-close behavior schema version";
     check (Int64.equal capabilities 1L) "auto-close behavior capabilities";
     let props = A.For_testing.decode_props_exn payload in
     check (not props.close_when_opened) "auto-close opened policy";
     check props.close_when_tapped "auto-close tapped policy"
   | _ -> failwith "auto-close behavior native props");
  let default_widget = A.create ~child:(Ui.Widget.empty ()) () in
  let (Av default_view) = Ui.Widget.Private.view default_widget in
  match default_view.node with
  | Native_widget { payload; _ } ->
    let props = A.For_testing.decode_props_exn payload in
    check props.close_when_opened "auto-close opened default";
    check props.close_when_tapped "auto-close tapped default"
  | _ -> failwith "auto-close behavior native props"
;;

let test_navigation_shell_contract_and_events () =
  let received = ref None in
  let widget =
    Ui.Native_widget.Navigation_shell.create
      ~key:(Ui.Key.string "shell")
      ~selected_index:1
      ~drawer_open:true
      ~drawer_enabled:false
      ~bodies:
        [ Ui.Widget.Body.static (Ui.Widget.text "Primary")
        ; Ui.Widget.Body.static (Ui.Widget.text "Secondary")
        ]
      ~drawer:(Ui.Widget.text "Drawer")
      ~bottom_navigation:(Ui.Widget.text "Bottom")
      ~on_drawer_state_changed:(fun state -> received := Some state)
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check (Array.length view.children = 4) "navigation shell child shape";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check
       (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 3))
       "navigation shell kind ID";
     check (version = 1) "navigation shell schema version";
     check (Int64.equal capabilities 7L) "navigation shell capabilities";
     let props = Ui.Native_widget.Navigation_shell.For_testing.decode_props_exn payload in
     check (props.destination_count = 2) "navigation destination count";
     check (props.selected_index = 1) "navigation selected index";
     check props.drawer_open "navigation requested drawer state";
     check (not props.drawer_enabled) "navigation drawer enabled state"
   | _ -> failwith "navigation shell native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 3
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Ui.Native_widget.Navigation_shell.For_testing.encode_drawer_state Open
       });
  check
    (!received = Some Ui.Native_widget.Navigation_shell.Open)
    "navigation shell open event";
  received := None;
  List.iter
    (fun (kind_id, version, event_id, payload) ->
       Ui.Event.Handler.Private.invoke
         binding.handler
         (Native_event { kind_id; version; event_id; payload }))
    [ native_kind_id 99, 1, native_event_id 1, Bytes.of_string "\000"
    ; native_kind_id 3, 2, native_event_id 1, Bytes.of_string "\000"
    ; native_kind_id 3, 1, native_event_id 2, Bytes.of_string "\000"
    ; native_kind_id 3, 1, native_event_id 1, Bytes.empty
    ; native_kind_id 3, 1, native_event_id 1, Bytes.of_string "\002"
    ];
  check (!received = None) "malformed navigation-shell event was accepted";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Navigation_shell.create
            ~selected_index:0
            ~drawer_open:false
            ~drawer_enabled:true
            ~bodies:[]
            ~drawer:(Ui.Widget.empty ())
            ~bottom_navigation:(Ui.Widget.empty ())
            ~on_drawer_state_changed:(fun _ -> ())
            ()))
    "navigation shell accepted no destination bodies";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Navigation_shell.create
            ~selected_index:2
            ~drawer_open:false
            ~drawer_enabled:true
            ~bodies:
              [ Ui.Widget.Body.static (Ui.Widget.empty ())
              ; Ui.Widget.Body.static (Ui.Widget.empty ())
              ]
            ~drawer:(Ui.Widget.empty ())
            ~bottom_navigation:(Ui.Widget.empty ())
            ~on_drawer_state_changed:(fun _ -> ())
            ()))
    "navigation shell accepted an invalid selected index"
;;

let message_composer_button
      ?(position = Ui.Native_widget.Message_composer.Trailing)
      ?(visibility = Ui.Native_widget.Message_composer.Always)
      ?(style = Ui.Native_widget.Message_composer.Plain)
      ?(enabled = true)
      ~id
      ~tooltip
      label
  =
  Ui.Native_widget.Message_composer.button
    ~id
    ~tooltip
    ~position
    ~visibility
    ~style
    ~enabled
    ~child:(Ui.Widget.text label)
    ()
;;

let test_message_composer_contract_and_custom_buttons () =
  let events = ref [] in
  let buttons =
    [ message_composer_button
        ~id:10
        ~tooltip:"Add attachment"
        ~position:Leading
        "attachment"
    ; message_composer_button
        ~id:20
        ~tooltip:"Start voice input"
        ~visibility:When_empty
        ~style:Filled
        "voice"
    ; message_composer_button
        ~id:21
        ~tooltip:"Send message"
        ~visibility:When_non_empty
        ~style:Filled
        "send"
    ]
  in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~key:(Ui.Key.string "composer")
      ~autofocus:true
      ~max_lines:7
      ~hint_text:"Ask anything \226\156\168"
      ~buttons
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check (Array.length view.children = 3) "message composer custom button child count";
  Array.iteri
    (fun index expected ->
       let (Av child) = Ui.Widget.Private.view view.children.(index).widget in
       match child.node with
       | Ui.Widget.Private.Text { value; _ } ->
         check (String.equal value expected) "message composer custom button order"
       | _ -> failwith "message composer button child")
    [| "attachment"; "voice"; "send" |];
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 6) "message composer kind ID";
     check (version = 1) "message composer schema version";
     check (Int64.equal capabilities 5L) "message composer capabilities";
     let props = Ui.Native_widget.Message_composer.For_testing.decode_props_exn payload in
     check props.enabled "message composer enabled default";
     check props.autofocus "message composer autofocus";
     check (props.max_lines = 7) "message composer max lines";
     check
       (String.equal props.hint_text "Ask anything \226\156\168")
       "message composer UTF-8 hint";
     check (List.length props.buttons = 3) "message composer button metadata count";
     let attachment = List.nth props.buttons 0 in
     check (attachment.id = 10) "message composer button ID";
     check (attachment.position = Leading) "message composer leading button";
     let voice = List.nth props.buttons 1 in
     check (voice.visibility = When_empty) "message composer empty visibility";
     check (voice.style = Filled) "message composer filled style";
     let send = List.nth props.buttons 2 in
     check (send.visibility = When_non_empty) "message composer non-empty visibility"
   | _ -> failwith "message composer native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Bytes.of_string "hello \240\159\145\139"
       });
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 2
       ; payload =
           (let payload = Bytes.make 12 '\000' in
            Bytes.set_int32_le payload 0 21l;
            Bytes.blit_string "  send  " 0 payload 4 8;
            payload)
       });
  check
    (!events
     = [ Ui.Native_widget.Message_composer.Button_pressed
           { button_id = 21; text = "  send  " }
       ; Text_changed "hello \240\159\145\139"
       ])
    "message composer typed events"
;;

let test_message_composer_validation_and_event_filtering () =
  let button = message_composer_button ~id:1 ~tooltip:"One" "one" in
  List.iter
    (fun max_lines ->
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Message_composer.create
                 ~max_lines
                 ~buttons:[]
                 ~on_event:(fun _ -> ())
                 ()))
         "message composer accepted invalid max_lines")
    [ 0; -1; 0x1_0000 ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () -> ignore (message_composer_button ~id ~tooltip:"Invalid" "x"))
         "message composer accepted invalid button ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (message_composer_button ~id:2 ~tooltip:"" "empty"))
    "message composer accepted empty tooltip";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Message_composer.create
            ~buttons:[ button; button ]
            ~on_event:(fun _ -> ())
            ()))
    "message composer accepted duplicate button IDs";
  let received = ref [] in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~buttons:[ button ]
      ~on_event:(fun event -> received := event :: !received)
      ()
  in
  let binding =
    (let (Av v) = Ui.Widget.Private.view widget in
     v.event_bindings).(0)
  in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 2 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 1 (native_event_id 9) Bytes.empty;
  invoke (native_kind_id 6) 1 (native_event_id 2) (Bytes.make 3 '\000');
  check (!received = []) "message composer malformed event was accepted";
  invoke (native_kind_id 6) 1 (native_event_id 1) (Bytes.of_string "accepted");
  check
    (!received = [ Ui.Native_widget.Message_composer.Text_changed "accepted" ])
    "message composer valid event was filtered"
;;

let expandable_message_composer_button
      ?(position = Ui.Native_widget.Expandable_message_composer.Trailing)
      ?(visibility = Ui.Native_widget.Expandable_message_composer.Always)
      ?(style = Ui.Native_widget.Expandable_message_composer.Plain)
      ?(enabled = true)
      ~id
      ~tooltip
      label
  =
  Ui.Native_widget.Expandable_message_composer.button
    ~id
    ~tooltip
    ~position
    ~visibility
    ~style
    ~enabled
    ~child:(Ui.Widget.text label)
    ()
;;

let (_ :
      ?key:Ui.Key.t
      -> ?enabled:bool
      -> fab_presentation:Ui.Native_widget.Expandable_message_composer.fab_presentation
      -> fab_label:string
      -> fab_tooltip:string
      -> fab_icon:Ui.Widget.t
      -> ?animation_duration_ms:int
      -> ?animation_curve:Ui.Animation.Curve.t
      -> ?max_lines:int
      -> ?hint_text:string
      -> buttons:Ui.Native_widget.Expandable_message_composer.button list
      -> on_event:(Ui.Native_widget.Expandable_message_composer.event -> unit)
      -> unit
      -> Ui.Widget.t)
  =
  Ui.Native_widget.Expandable_message_composer.create
;;

let (_ :
      ?key:Ui.Key.t
      -> ?enabled:bool
      -> fab_presentation:Ui.Native_widget.Expandable_message_composer.fab_presentation
      -> fab_label:string
      -> fab_tooltip:string
      -> fab_icon:Ui.Widget.t
      -> ?animation_duration_ms:int
      -> ?animation_curve:Ui.Animation.Curve.t
      -> ?max_lines:int
      -> ?hint_text:string
      -> buttons:Ui.Native_widget.Expandable_message_composer.button list
      -> on_event:Ui.Event.Handler.t
      -> unit
      -> Ui.Widget.t)
  =
  Ui.Native_widget.Expandable_message_composer.create_with_handler
;;

let expandable_message_composer_payload widget =
  let (Av view) = Ui.Widget.Private.view widget in
  match view.node with
  | Native_widget { kind_id; version; capabilities; payload } ->
    check (kind_id = native_kind_id 7) "expandable composer kind ID";
    check (version = 2) "expandable composer schema version";
    check (Int64.equal capabilities 5L) "expandable composer capabilities";
    payload
  | _ -> failwith "expandable composer native props"
;;

let test_expandable_message_composer_contract_and_events () =
  let events = ref [] in
  let buttons =
    [ expandable_message_composer_button
        ~id:10
        ~tooltip:"Add attachment 📎"
        ~position:Leading
        "attachment"
    ; expandable_message_composer_button
        ~id:21
        ~tooltip:"Send message"
        ~visibility:When_non_empty
        ~style:Filled
        ~enabled:false
        "send"
    ]
  in
  let widget =
    Ui.Native_widget.Expandable_message_composer.create
      ~key:(Ui.Key.string "expandable-composer")
      ~enabled:false
      ~fab_presentation:Extended
      ~fab_label:"Capture ✨"
      ~fab_tooltip:"Open capture 🚀"
      ~fab_icon:(Ui.Widget.text "capture-icon")
      ~animation_duration_ms:375
      ~animation_curve:Ui.Animation.Curve.Ease_out
      ~max_lines:9
      ~hint_text:"Write 你好"
      ~buttons
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let (Av view) = Ui.Widget.Private.view widget in
  check
    (Option.equal Ui.Key.equal view.key (Some (Ui.Key.string "expandable-composer")))
    "expandable composer key";
  check (Array.length view.children = 3) "expandable composer child count";
  Array.iteri
    (fun index expected ->
       let (Av child) = Ui.Widget.Private.view view.children.(index).widget in
       match child.node with
       | Ui.Widget.Private.Text { value; _ } ->
         check (String.equal value expected) "expandable composer child order"
       | _ -> failwith "expandable composer child")
    [| "capture-icon"; "attachment"; "send" |];
  let props =
    widget
    |> expandable_message_composer_payload
    |> Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
  in
  check (not props.enabled) "expandable composer enabled";
  check (props.fab_presentation = Extended) "expandable FAB presentation";
  check (String.equal props.fab_label "Capture ✨") "expandable FAB label";
  check (String.equal props.fab_tooltip "Open capture 🚀") "expandable FAB tooltip";
  check (props.animation_duration_ms = 375) "expandable animation duration";
  check (props.animation_curve = Ui.Animation.Curve.Ease_out) "expandable curve";
  check (props.max_lines = 9) "expandable max lines";
  check (String.equal props.hint_text "Write 你好") "expandable hint";
  check (List.length props.buttons = 2) "expandable button count";
  let attachment = List.nth props.buttons 0 in
  check (attachment.id = 10 && attachment.position = Leading) "expandable leading button";
  let send = List.nth props.buttons 1 in
  check
    (send.visibility = When_non_empty && send.style = Filled && not send.enabled)
    "expandable button metadata";
  let binding = view.event_bindings.(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke
    (native_kind_id 7)
    2
    Ui.Native_widget.Expandable_message_composer.text_changed_event_id
    (Bytes.of_string "  hello 👋  ");
  let button_payload = Bytes.make 16 (Char.chr 0) in
  Bytes.set_int32_le button_payload 0 21l;
  Bytes.blit_string "  send  🚀" 0 button_payload 4 12;
  invoke
    (native_kind_id 7)
    2
    Ui.Native_widget.Expandable_message_composer.button_pressed_event_id
    button_payload;
  check
    (!events
     = [ Ui.Native_widget.Expandable_message_composer.Button_pressed
           { button_id = 21; text = "  send  🚀" }
       ; Text_changed "  hello 👋  "
       ])
    "expandable composer typed raw-text events";
  let payload_event event_id payload =
    Ui.Native_widget.Expandable_message_composer.event_of_payload
      (Native_event { kind_id = native_kind_id 7; version = 2; event_id; payload })
  in
  check
    (payload_event
       Ui.Native_widget.Expandable_message_composer.text_changed_event_id
       (Bytes.of_string "text")
     = Some (Ui.Native_widget.Expandable_message_composer.Text_changed "text"))
    "expandable event_of_payload";
  List.iter
    (fun (kind_id, version, event_id, payload) -> invoke kind_id version event_id payload)
    [ native_kind_id 6, 2, native_event_id 1, Bytes.of_string "wrong kind"
    ; native_kind_id 7, 1, native_event_id 1, Bytes.of_string "old version"
    ; native_kind_id 7, 3, native_event_id 1, Bytes.of_string "wrong version"
    ; native_kind_id 7, 2, native_event_id 9, Bytes.empty
    ; native_kind_id 7, 2, native_event_id 2, Bytes.make 3 (Char.chr 0)
    ; native_kind_id 7, 2, native_event_id 2, Bytes.make 4 (Char.chr 0)
    ; ( native_kind_id 7
      , 2
      , native_event_id 1
      , Bytes.of_string (String.make 1 (Char.chr 255)) )
    ];
  check (List.length !events = 2) "expandable malformed event was accepted"
;;

let test_expandable_message_composer_validation_and_malformed_props () =
  let create
        ?(fab_presentation = Ui.Native_widget.Expandable_message_composer.Extended)
        ?(fab_label = "Capture")
        ?(fab_tooltip = "Open capture")
        ?(animation_duration_ms = 200)
        ?(animation_curve = Ui.Animation.Curve.Ease_out)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ?(buttons = [])
        ()
    =
    Ui.Native_widget.Expandable_message_composer.create
      ~fab_presentation
      ~fab_label
      ~fab_tooltip
      ~fab_icon:(Ui.Widget.empty ())
      ~animation_duration_ms
      ~animation_curve
      ~max_lines
      ~hint_text
      ~buttons
      ~on_event:(fun _ -> ())
      ()
  in
  List.iter
    (fun duration ->
       expect_invalid_argument
         (fun () -> ignore (create ~animation_duration_ms:duration ()))
         "expandable composer accepted invalid duration")
    [ -1; 0x1_0000 ];
  List.iter
    (fun max_lines ->
       expect_invalid_argument
         (fun () -> ignore (create ~max_lines ()))
         "expandable composer accepted invalid max_lines")
    [ 0; -1; 0x1_0000 ];
  let invalid_utf8 = String.make 1 (Char.chr 255) in
  List.iter
    (fun (label, tooltip, hint) ->
       expect_invalid_argument
         (fun () ->
            ignore (create ~fab_label:label ~fab_tooltip:tooltip ~hint_text:hint ()))
         "expandable composer accepted invalid UTF-8 or empty required text")
    [ "", "tooltip", "hint"
    ; "label", "", "hint"
    ; invalid_utf8, "tooltip", "hint"
    ; "label", invalid_utf8, "hint"
    ; "label", "tooltip", invalid_utf8
    ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () ->
            ignore (expandable_message_composer_button ~id ~tooltip:"Invalid" "x"))
         "expandable composer accepted invalid button ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (expandable_message_composer_button ~id:1 ~tooltip:"" "x"))
    "expandable composer accepted empty button tooltip";
  expect_invalid_argument
    (fun () ->
       ignore (expandable_message_composer_button ~id:1 ~tooltip:invalid_utf8 "x"))
    "expandable composer accepted invalid button tooltip UTF-8";
  let duplicate = expandable_message_composer_button ~id:1 ~tooltip:"One" "one" in
  expect_invalid_argument
    (fun () -> ignore (create ~buttons:[ duplicate; duplicate ] ()))
    "expandable composer accepted duplicate button IDs";
  let valid = expandable_message_composer_payload (create ()) in
  let compact =
    expandable_message_composer_payload (create ~fab_presentation:Compact ())
  in
  let compact_props =
    Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn compact
  in
  check (Bytes.get_uint8 valid 20 = 0) "extended presentation byte";
  check (Bytes.get_uint8 compact 20 = 1) "compact presentation byte";
  check (compact_props.fab_presentation = Compact) "compact presentation round trip";
  let handler_widget =
    Ui.Native_widget.Expandable_message_composer.create_with_handler
      ~fab_presentation:Compact
      ~fab_label:"Capture"
      ~fab_tooltip:"Open capture"
      ~fab_icon:(Ui.Widget.empty ())
      ~buttons:[]
      ~on_event:(Ui.Event.Handler.create (fun _ -> ()))
      ()
  in
  let handler_props =
    handler_widget
    |> expandable_message_composer_payload
    |> Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
  in
  check
    (handler_props.fab_presentation = Compact)
    "create_with_handler compact presentation";
  let invalid_payloads =
    [ Bytes.sub valid 0 23
    ; Bytes.cat valid (Bytes.make 1 (Char.chr 0))
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 0 (Char.chr 2);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 1 (Char.chr 4);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 20 (Char.chr 2);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 21 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 22 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 23 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 4 (Char.chr 0);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 8 (Char.chr 0);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 24 (Char.chr 255);
       bytes)
    ]
  in
  List.iter
    (fun payload ->
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
                 payload))
         "expandable composer accepted malformed props")
    invalid_payloads
;;

let () =
  test_typed_native_widget ();
  test_sliver_box_and_scroll_view ();
  test_keyed_widget_root_evidence ();
  test_sliver_fixed_extent_contract ();
  test_sliver_window_materialization_ranges ();
  test_sliver_varied_extent_contract ();
  test_sliver_varied_extent_transition ();
  test_sliver_varied_extent_validation ();
  test_sliver_fixed_extent_wire_validation ();
  test_sparse_extent_transition_wire_validation ();
  test_sliver_fill_and_padding ();
  test_sliver_app_bar_contract ();
  test_sliver_app_bar_validation ();
  test_scroll_view_cache_extent_auto_fixed ();
  test_scroll_view_cache_extent_auto_varied ();
  test_scroll_view_cache_extent_auto_max ();
  test_scroll_view_cache_extent_auto_none ();
  test_scroll_view_cache_extent_explicit_wins ();
  test_scroll_view_cache_extent_padding_recurse ();
  test_scroll_view_cache_extent_default_overscan ();
  test_scroll_view_cache_extent_horizontal ();
  test_scroll_view_cache_extent_wire_validation ();
  test_morphing_surface_contract ();
  test_slidable_props_children_and_events ();
  test_slidable_defaults_all_motions_and_validation ();
  test_slidable_event_filtering ();
  test_slidable_auto_close_behavior_contract ();
  test_navigation_shell_contract_and_events ();
  test_message_composer_contract_and_custom_buttons ();
  test_message_composer_validation_and_event_filtering ();
  test_expandable_message_composer_contract_and_events ();
  test_expandable_message_composer_validation_and_malformed_props ()
;;
