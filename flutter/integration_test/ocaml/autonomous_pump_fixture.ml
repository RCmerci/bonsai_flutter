module Ui = Bonsai_flutter_ui

let patch_size_counts =
  [ 32
  ; 64
  ; 128
  ; 256
  ; 288
  ; 320
  ; 352
  ; 360
  ; 368
  ; 376
  ; 384
  ; 416
  ; 448
  ; 480
  ; 512
  ; 1024
  ; 2048
  ; 4096
  ]
;;

let patch_size_component handlers graph =
  let visible_count, set_visible_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let set_count count =
    Driver.Handler.create
      handlers
      ~name:(Printf.sprintf "show-%d-patch-items" count)
      ~equal:( == )
      set_visible_count
      ~f:(fun set_visible_count -> function
      | Ui.Event.Payload.Unit -> set_visible_count (fun _ -> count)
      | _ -> Bonsai.Effect.Ignore)
  in
  let expand_handlers = Bonsai.Cont.all (List.map set_count patch_size_counts) in
  let collapse =
    Driver.Handler.create
      handlers
      ~name:"hide-patch-items"
      ~equal:( == )
      set_visible_count
      ~f:(fun set_visible_count -> function
      | Ui.Event.Payload.Unit -> set_visible_count (fun _ -> 0)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map3
    visible_count
    expand_handlers
    collapse
    ~f:(fun count expand_handlers collapse ->
      let children =
        if count = 0
        then
          List.map2
            (fun count on_press ->
               Ui.Material.elevated_button
                 ~on_press
                 ~child:(Ui.Widget.text (Printf.sprintf "Expand %d" count))
                 ())
            patch_size_counts
            expand_handlers
        else
          Ui.Material.elevated_button
            ~on_press:collapse
            ~child:(Ui.Widget.text (Printf.sprintf "Collapse %d" count))
            ()
          :: List.init count (fun index ->
            Ui.Widget.text
              ~key:(Ui.Key.int index)
              (Printf.sprintf
                 "Patch item %06d: OCaml to Flutter visible text payload"
                 index))
      in
      let viewport =
        Ui.Widget.Scroll_view.vertical
          ~on_scroll:(Ui.Event.Handler.create (fun _ -> ()))
          [ Ui.Widget.Sliver.box (Ui.Widget.column children) ]
          ()
      in
      Ui.Material.scaffold
        ~body:(Ui.Widget.Body.Vertical.create [ Ui.Widget.Body.Vertical.fill viewport ])
        ())
;;

let component _handlers graph =
  let phase, set_phase = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let sleep = Bonsai.Cont.Clock.sleep graph in
  let after_display =
    Bonsai.Cont.map2
      phase
      (Bonsai.Cont.map2 set_phase sleep ~f:(fun set_phase sleep -> set_phase, sleep))
      ~f:(fun phase (set_phase, sleep) ->
        if phase = 0
        then
          Bonsai.Effect.Many
            [ set_phase (fun _ -> 1)
            ; Bonsai.Effect.bind
                (sleep (Core.Time_ns.Span.of_ms 50.))
                ~f:(fun () -> set_phase (fun _ -> 2))
            ]
        else Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.Edge.lifecycle ~after_display graph;
  Bonsai.Cont.map phase ~f:(fun phase ->
    Ui.Widget.text (Printf.sprintf "Autonomous phase %d" phase))
;;
