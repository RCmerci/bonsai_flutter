module Ui = Bonsai_flutter_ui

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
