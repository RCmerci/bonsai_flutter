module Ui = Bonsai_flutter_ui

let require condition message = if not condition then failwith message

let component handlers _graph =
  let noop =
    Driver.Handler.create
      handlers
      ~name:"noop"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.return ())
  in
  Bonsai.Cont.map noop ~f:(fun noop ->
    Ui.Widget.animated_opacity
      ~animation:
        (Ui.Animation.create
           ~id:7001L
           ~duration_ms:250
           ~curve:Ui.Animation.Curve.Ease_in_out
           ())
      ~opacity:0.75
      ~on_completed:noop
      (Ui.Widget.Stack.create
         [ Ui.Widget.Stack.child
             (Ui.Widget.Flex.row
                [ Ui.Widget.Flex.expanded (Ui.Widget.text "Expanded")
                ; Ui.Widget.Flex.fixed (Ui.Widget.text "Fixed")
                ])
         ; Ui.Widget.Stack.positioned
             ~left:8.
             ~top:12.
             (Ui.Widget.button ~on_press:noop ~child:(Ui.Widget.text "Overlay") ())
         ]))
;;

let () =
  let driver =
    Driver.create
      ~runtime_epoch:99L
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      component
  in
  let frame =
    match Driver.pump driver ~monotonic_now_ns:0L () with
    | Ok { frame = Some frame; _ } -> frame
    | Ok { frame = None; _ } -> failwith "initial layout frame was empty"
    | Error error -> failwith (Driver.error_to_string error)
  in
  let wire =
    match Bonsai_flutter_protocol.Binary_codec.decode frame.bytes with
    | Ok frame -> frame
    | Error error -> failwith error.message
  in
  let saw_stack, saw_expanded, saw_positioned, saw_animation =
    List.fold_left
      (fun (saw_stack, saw_expanded, saw_positioned, saw_animation) -> function
         | Bonsai_flutter_protocol.Wire_frame.Create_node
             { kind; props; event_bindings; parent_data; _ } ->
           let saw_stack = saw_stack || kind = Bonsai_flutter_protocol.Wire_frame.Stack in
           let saw_expanded =
             saw_expanded
             ||
             match parent_data with
             | Flex_parent_data { flex = 1; fit = Tight } -> true
             | _ -> false
           in
           let saw_positioned =
             saw_positioned
             ||
             match parent_data with
             | Stack_position _ -> true
             | _ -> false
           in
           let saw_animation =
             saw_animation
             ||
             match props, event_bindings with
             | ( Animated_opacity_props
                   { opacity = 0.75
                   ; animation = { id = 7001L; duration_ms = 250; curve = Ease_in_out }
                   }
               , [ { event_tag; _ } ] ) ->
               event_tag
               = Bonsai_flutter_protocol.Generated_protocol.Event_tag.animation_completed
             | _ -> false
           in
           saw_stack, saw_expanded, saw_positioned, saw_animation
         | _ -> saw_stack, saw_expanded, saw_positioned, saw_animation)
      (false, false, false, false)
      wire.operations
  in
  require saw_stack "Stack was not encoded as a native core node";
  require saw_expanded "Expanded parent data was not serialized";
  require saw_positioned "Positioned parent data was not serialized";
  require saw_animation "Semantic animation intent was not serialized"
;;
