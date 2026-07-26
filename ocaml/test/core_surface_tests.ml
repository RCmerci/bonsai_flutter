module Ui = Bonsai_flutter_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let child = Ui.Widget.text "child"

let widgets =
  [ Ui.Widget.rich_text [ "Hello"; " world" ]
  ; Ui.Widget.icon
      ~size:20.
      ~color:(Ui.Style.Color.rgb ~red:10 ~green:20 ~blue:30)
      ~code_point:0xe145
      ()
  ; Ui.Widget.image
      ~fit:Ui.Style.Image_fit.Contain
      ~width:120.
      ~height:80.
      ~uri:"https://example.invalid/image.png"
      ()
  ; Ui.Widget.align ~alignment:Ui.Layout.Alignment.Bottom_end child
  ; Ui.Widget.sized_box ~width:100. ~height:40. child
  ; Ui.Widget.constrained_box
      ~constraints:
        (Ui.Layout.Box_constraints.create
           ~min_width:10.
           ~max_width:100.
           ~min_height:20.
           ~max_height:200.
           ())
      child
  ; Ui.Widget.decorated_box
      ~decoration:
        (Ui.Style.Decoration.create
           ~background:(Ui.Style.Color.rgb ~red:40 ~green:50 ~blue:60)
           ~border_radius:8.
           ())
      child
  ; Ui.Widget.clip ~behavior:Ui.Style.Clip.Anti_alias child
  ; Ui.Widget.opacity 0.5 child
  ; Ui.Widget.animated_opacity
      ~animation:(Ui.Animation.create ~id:7L ~duration_ms:250 ())
      ~opacity:0.75
      ~on_completed:handler
      child
  ; Ui.Widget.transform ~transform:(Ui.Style.Transform.scale ~x:2. ~y:3. ()) child
  ; Ui.Widget.list_view ~on_scroll:handler [ child ] ()
  ; Ui.Widget.safe_area child
  ; Ui.Widget.environment_boundary child
  ; Ui.Widget.gesture ~on_tap:handler ~on_double_tap:handler ~on_long_press:handler child
  ; Ui.Widget.focus_scope ~autofocus:true ~on_focus_changed:handler child
  ; Ui.Widget.mouse_region ~on_enter:handler ~on_leave:handler child
  ; Ui.Widget.keyboard_listener
      ~autofocus:true
      ~key_policy:Ui.Event.Key_policy.Handled
      ~on_key:handler
      child
  ]
;;

let expected =
  [ "Rich_text"
  ; "Icon"
  ; "Image"
  ; "Align"
  ; "Sized_box"
  ; "Constrained_box"
  ; "Decorated_box"
  ; "Clip"
  ; "Opacity"
  ; "Animated_opacity"
  ; "Transform"
  ; "List_view"
  ; "Safe_area"
  ; "Environment_boundary"
  ; "Gesture"
  ; "Focus_scope"
  ; "Mouse_region"
  ; "Keyboard_listener"
  ]
;;

let () =
  let actual = List.map Ui.Widget.For_testing.kind_name widgets in
  if actual <> expected then failwith "core constructors produced incorrect logical kinds"
;;
