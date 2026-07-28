module Ui = Bonsai_flutter_ui

let check condition message = if not condition then failwith message
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

let test_core_constructors () =
  let actual = List.map Ui.Widget.For_testing.kind_name widgets in
  check (actual = expected) "core constructors produced incorrect logical kinds"
;;

let test_navigation_constructors () =
  let on_pop =
    Ui.Event.Handler.create (function
      | Ui.Event.Payload.Route_pop _ -> ()
      | _ -> failwith "route pop handler received the wrong payload")
  in
  let page =
    Ui.Widget.page
      ~page_key:"settings"
      ~transition:Ui.Navigation.Fade
      ~can_pop:true
      ~restoration_id:"settings-page"
      (Ui.Widget.text "Settings")
  in
  let navigator = Ui.Widget.navigator ~on_pop [ page ] in
  check
    (String.equal (Ui.Widget.For_testing.kind_name navigator) "Navigator")
    "navigator kind is not typed";
  let children = Ui.Widget.For_testing.children navigator in
  check (Array.length children = 1) "navigator lost its page";
  check
    (String.equal (Ui.Widget.For_testing.kind_name children.(0)) "Page")
    "navigator child is not a Page";
  let overlay =
    Ui.Widget.overlay ~alignment:Ui.Navigation.Center [ Ui.Widget.text "Overlay content" ]
  in
  check
    (String.equal (Ui.Widget.For_testing.kind_name overlay) "Overlay")
    "overlay kind is not typed";
  let dialog =
    Ui.Widget.material_dialog ~barrier_dismissible:false (Ui.Widget.text "Confirm")
  in
  check
    (String.equal (Ui.Widget.For_testing.kind_name dialog) "Material_dialog")
    "dialog kind is not typed"
;;

let test_debug_tree () =
  let tree =
    Ui.Widget.column
      ~key:(Ui.Key.string "main")
      [ Ui.Widget.text "Count: 0"
      ; Ui.Widget.button
          ~on_press:(Ui.Event.Handler.create (fun _ -> ()))
          ~child:(Ui.Widget.text "Increment")
          ()
      ]
  in
  check
    (String.equal
       (Ui.Debug.dump_tree tree)
       "Column key=\"main\"\n\
       \  Text \"Count: 0\"\n\
       \  Button events=[press]\n\
       \    Text \"Increment\"")
    "debug tree is not deterministic"
;;

let test_semantics_properties () =
  let semantics =
    Ui.Semantics.create
      ~label:"Accept terms"
      ~hint:"Double tap to toggle"
      ~value:"Not accepted"
      ~role:Ui.Semantics.Role.Checkbox
      ~enabled:true
      ~selected:false
      ~checked:false
      ~focusable:true
      ~live_region:true
      ~heading_level:2
      ~sort_key:3.5
      ~actions:[ Ui.Semantics.Action.Tap ]
      ()
  in
  let view = Ui.Semantics.Private.view semantics in
  check
    (view.role = Ui.Semantics.Role.Checkbox
     && view.heading_level = Some 2
     && view.actions = [ Ui.Semantics.Action.Tap ])
    "semantics properties were not preserved"
;;

let test_styled_text_constructor_and_validation () =
  let color = Ui.Style.Color.rgb ~red:24 ~green:55 ~blue:88 in
  let style =
    Ui.Style.Text_style.create
      ~font_size:16.
      ~font_weight:Ui.Style.Font_weight.Semi_bold
      ~line_height:1.4
      ~color
      ()
  in
  let text =
    Ui.Widget.text
      ~style
      ~text_align:Ui.Style.Text_align.End
      ~max_lines:2
      ~overflow:Ui.Style.Text_overflow.Ellipsis
      "A long subject"
  in
  (match (Ui.Widget.Private.view text).props with
   | Text_props
       { value
       ; style =
           Some
             { font_size = Some font_size
             ; font_weight = Some Semi_bold
             ; line_height = Some line_height
             ; color = Some encoded_color
             }
       ; text_align = End
       ; max_lines = Some max_lines
       ; overflow = Ellipsis
       } ->
     check (String.equal value "A long subject") "styled text lost its value";
     check (Float.equal font_size 16.) "styled text lost its font size";
     check (Float.equal line_height 1.4) "styled text lost its line height";
     check (Int32.equal encoded_color 0xff183758l) "styled text lost its color";
     check (Int.equal max_lines 2) "styled text lost its line limit"
   | _ -> failwith "styled text properties were not preserved");
  let expect_invalid create message =
    match create () with
    | exception Invalid_argument _ -> ()
    | _ -> failwith message
  in
  expect_invalid
    (fun () -> Ui.Style.Text_style.create ~font_size:0. ())
    "zero font size was accepted";
  expect_invalid
    (fun () -> Ui.Style.Text_style.create ~line_height:nan ())
    "non-finite line height was accepted";
  expect_invalid
    (fun () -> Ui.Widget.text ~max_lines:0 "Invalid")
    "zero maximum lines was accepted"
;;

let () =
  test_core_constructors ();
  test_navigation_constructors ();
  test_debug_tree ();
  test_semantics_properties ();
  test_styled_text_constructor_and_validation ()
;;
