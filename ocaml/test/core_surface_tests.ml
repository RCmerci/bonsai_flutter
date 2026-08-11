module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

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
      ~animation:
        (Ui.Animation.create ~id:(ID.Ui.Animation_id.of_int64 7L) ~duration_ms:250 ())
      ~opacity:0.75
      ~on_completed:handler
      child
  ; Ui.Widget.transform ~transform:(Ui.Style.Transform.scale ~x:2. ~y:3. ()) child
  ; Ui.Widget.List_view.vertical ~on_scroll:handler [ child ] ()
    |> Ui.Widget.Viewport.Vertical.with_height ~height:120.
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
  ; "Sized_box"
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
      ~page_key:(ID.Navigation.Page_key.of_string "settings")
      ~presentation:(Ui.Navigation.Standard Ui.Navigation.Fade)
      ~can_pop:true
      ~restoration_id:(ID.Navigation.Restoration_id.of_string "settings-page")
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
  (match (Ui.Widget.Private.view children.(0)).props with
   | Ui.Widget.Private.Page_props
       { presentation = Ui.Navigation.Standard Ui.Navigation.Fade; _ } -> ()
   | _ -> failwith "standard page presentation or transition was not preserved");
  let barrier_color = Ui.Style.Color.argb ~alpha:128 ~red:10 ~green:20 ~blue:30 in
  let handle_semantics =
    Ui.Navigation.Modal_bottom_sheet.Handle_semantics.create
      ~label:"Adjust sheet height"
      ~medium_value:"Half height"
      ~large_value:"Full height"
  in
  let detents =
    Ui.Navigation.Modal_bottom_sheet.Detents.create
      ~initial:Ui.Navigation.Modal_bottom_sheet.Detent.Medium
      ~semantics:handle_semantics
      [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
      ; Ui.Navigation.Modal_bottom_sheet.Detent.Large
      ]
  in
  let modal =
    Ui.Navigation.Modal_bottom_sheet.create
      ~barrier_dismissible:false
      ~barrier_color
      ~barrier_label:"Close editor"
      ~sizing:(Ui.Navigation.Modal_bottom_sheet.Sizing.Detented detents)
      ~use_safe_area:true
      ~request_focus:false
      ~transition_duration_ms:310
      ~reverse_transition_duration_ms:190
      ()
  in
  let modal_page =
    Ui.Widget.page
      ~page_key:(ID.Navigation.Page_key.of_string "editor")
      ~presentation:(Ui.Navigation.Modal_bottom_sheet modal)
      ~can_pop:false
      ~restoration_id:(ID.Navigation.Restoration_id.of_string "editor-page")
      (Ui.Widget.text "Editor")
  in
  (match (Ui.Widget.Private.view modal_page).props with
   | Ui.Widget.Private.Page_props
       { page_key
       ; presentation = Ui.Navigation.Modal_bottom_sheet modal
       ; can_pop
       ; restoration_id
       } ->
     let modal = Ui.Navigation.Modal_bottom_sheet.Private.view modal in
     check
       (ID.Navigation.Page_key.equal page_key (ID.Navigation.Page_key.of_string "editor"))
       "modal page key was not preserved";
     check (not can_pop) "modal can_pop was not preserved";
     check
       (Option.equal
          ID.Navigation.Restoration_id.equal
          restoration_id
          (Some (ID.Navigation.Restoration_id.of_string "editor-page")))
       "modal restoration ID was not preserved";
     check (not modal.barrier_dismissible) "modal barrier policy was not preserved";
     check
       (Option.equal
          Int32.equal
          (Option.map Ui.Style.Color.Private.to_argb32 modal.barrier_color)
          (Some (Int32.of_string "0x800a141e")))
       "modal barrier color was not preserved";
     check
       (modal.barrier_label = Some "Close editor")
       "modal barrier label was not preserved";
     (match modal.sizing with
      | Ui.Navigation.Modal_bottom_sheet.Sizing.Detented detents ->
        let detents = Ui.Navigation.Modal_bottom_sheet.Detents.Private.view detents in
        check
          (detents.detents
           = [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
             ; Ui.Navigation.Modal_bottom_sheet.Detent.Large
             ])
          "modal detents were not canonicalized";
        check
          (detents.initial = Ui.Navigation.Modal_bottom_sheet.Detent.Medium)
          "modal initial detent was not preserved";
        check detents.dismiss_on_drag "modal drag dismissal should default on";
        let semantics =
          Ui.Navigation.Modal_bottom_sheet.Handle_semantics.Private.view detents.semantics
        in
        check
          (String.equal semantics.label "Adjust sheet height"
           && String.equal semantics.medium_value "Half height"
           && String.equal semantics.large_value "Full height")
          "modal handle semantics were not preserved"
      | _ -> failwith "modal detented sizing was not preserved");
     check modal.use_safe_area "modal safe-area policy was not preserved";
     check (not modal.request_focus) "modal focus policy was not preserved";
     check
       (modal.transition_duration_ms = 310 && modal.reverse_transition_duration_ms = 190)
       "modal durations were not preserved"
   | _ -> failwith "modal page presentation was not emitted");
  let default_modal =
    Ui.Navigation.Modal_bottom_sheet.create ()
    |> Ui.Navigation.Modal_bottom_sheet.Private.view
  in
  check default_modal.barrier_dismissible "modal barrier should default dismissible";
  check
    (Option.is_none default_modal.barrier_color)
    "modal barrier color should use theme";
  check
    (Option.is_none default_modal.barrier_label)
    "modal barrier label should be localized";
  check
    (default_modal.sizing = Ui.Navigation.Modal_bottom_sheet.Sizing.Content_bounded)
    "modal should use the bounded default height policy";
  let scroll_controlled_modal =
    Ui.Navigation.Modal_bottom_sheet.create
      ~sizing:Ui.Navigation.Modal_bottom_sheet.Sizing.Scroll_controlled
      ()
    |> Ui.Navigation.Modal_bottom_sheet.Private.view
  in
  check
    (scroll_controlled_modal.sizing
     = Ui.Navigation.Modal_bottom_sheet.Sizing.Scroll_controlled)
    "modal scroll-controlled sizing was not preserved";
  let detents_view detents =
    Ui.Navigation.Modal_bottom_sheet.Detents.Private.view detents
  in
  let medium_only =
    Ui.Navigation.Modal_bottom_sheet.Detents.create
      ~semantics:handle_semantics
      [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium ]
    |> detents_view
  in
  check
    (medium_only.detents = [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium ]
     && medium_only.initial = Ui.Navigation.Modal_bottom_sheet.Detent.Medium)
    "medium-only detents did not default to Medium";
  let large_only =
    Ui.Navigation.Modal_bottom_sheet.Detents.create
      ~dismiss_on_drag:false
      ~semantics:handle_semantics
      [ Ui.Navigation.Modal_bottom_sheet.Detent.Large ]
    |> detents_view
  in
  check
    (large_only.detents = [ Ui.Navigation.Modal_bottom_sheet.Detent.Large ]
     && large_only.initial = Ui.Navigation.Modal_bottom_sheet.Detent.Large
     && not large_only.dismiss_on_drag)
    "large-only detents did not preserve defaults and dismissal policy";
  let reversed =
    Ui.Navigation.Modal_bottom_sheet.Detents.create
      ~semantics:handle_semantics
      [ Ui.Navigation.Modal_bottom_sheet.Detent.Large
      ; Ui.Navigation.Modal_bottom_sheet.Detent.Medium
      ]
    |> detents_view
  in
  check
    (reversed.detents
     = [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
       ; Ui.Navigation.Modal_bottom_sheet.Detent.Large
       ])
    "modal detents were not canonicalized smallest-to-largest";
  check (not default_modal.use_safe_area) "modal safe area should default off";
  check default_modal.request_focus "modal should request route focus by default";
  check
    (default_modal.transition_duration_ms = 250
     && default_modal.reverse_transition_duration_ms = 200)
    "modal should use documented Material durations";
  List.iter
    (fun duration_ms ->
       match
         Ui.Navigation.Modal_bottom_sheet.create ~transition_duration_ms:duration_ms ()
       with
       | exception Invalid_argument _ -> ()
       | _ -> failwith "modal accepted an invalid transition duration")
    [ -1; 0x1_0000_0000 ];
  let expect_invalid_detents f message =
    match f () with
    | exception Invalid_argument _ -> ()
    | _ -> failwith message
  in
  expect_invalid_detents
    (fun () ->
       Ui.Navigation.Modal_bottom_sheet.Detents.create ~semantics:handle_semantics [])
    "modal accepted an empty detent set";
  expect_invalid_detents
    (fun () ->
       Ui.Navigation.Modal_bottom_sheet.Detents.create
         ~semantics:handle_semantics
         [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
         ; Ui.Navigation.Modal_bottom_sheet.Detent.Medium
         ])
    "modal accepted duplicate detents";
  expect_invalid_detents
    (fun () ->
       Ui.Navigation.Modal_bottom_sheet.Detents.create
         ~initial:Ui.Navigation.Modal_bottom_sheet.Detent.Large
         ~semantics:handle_semantics
         [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium ])
    "modal accepted an initial detent outside its set";
  List.iter
    (fun (label, medium_value, large_value) ->
       expect_invalid_detents
         (fun () ->
            Ui.Navigation.Modal_bottom_sheet.Handle_semantics.create
              ~label
              ~medium_value
              ~large_value)
         "modal accepted empty handle semantics")
    [ "", "Half height", "Full height"
    ; "Adjust sheet height", "", "Full height"
    ; "Adjust sheet height", "Half height", ""
    ];
  List.iter
    (fun duration_ms ->
       match
         Ui.Navigation.Modal_bottom_sheet.create
           ~reverse_transition_duration_ms:duration_ms
           ()
       with
       | exception Invalid_argument _ -> ()
       | _ -> failwith "modal accepted an invalid reverse transition duration")
    [ -1; 0x1_0000_0000 ];
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

let expect_invalid create message =
  match create () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith message
;;

let test_typed_viewport_body_encoding () =
  let viewport =
    Ui.Widget.List_view.vertical ~on_scroll:handler [ Ui.Widget.text "Row" ] ()
  in
  let body =
    Ui.Widget.Body.Vertical.create
      [ Ui.Widget.Body.Vertical.fixed (Ui.Widget.text "Search")
      ; Ui.Widget.Body.Vertical.fill ~flex:2 viewport
      ]
  in
  let scaffold = Ui.Material.scaffold ~body () in
  let scaffold_children = Ui.Widget.For_testing.children scaffold in
  check (Array.length scaffold_children = 1) "scaffold lost its typed body";
  let column = scaffold_children.(0) in
  check
    (String.equal (Ui.Widget.For_testing.kind_name column) "Flex_column")
    "vertical body did not encode as a flex column";
  let children = (Ui.Widget.Private.view column).children in
  check (Array.length children = 2) "vertical body lost a child";
  (match children.(0).parent_data, children.(1).parent_data with
   | Ui.Widget.Private.No_parent_data, Flex_parent_data { flex = 2; fit = Tight } -> ()
   | _ -> failwith "vertical body encoded incorrect flex parent data");
  let overlay =
    Ui.Widget.Body.overlay
      ~base:body
      ~overlays:
        [ Ui.Widget.Stack.positioned ~right:16. ~bottom:16. (Ui.Widget.text "Capture") ]
      ()
  in
  let overlay_scaffold = Ui.Material.scaffold ~body:overlay () in
  let stack = (Ui.Widget.For_testing.children overlay_scaffold).(0) in
  check
    (String.equal (Ui.Widget.For_testing.kind_name stack) "Stack")
    "body overlay did not encode as a stack";
  let stack_children = (Ui.Widget.Private.view stack).children in
  match stack_children.(0).parent_data, stack_children.(1).parent_data with
  | ( Stack_position { left = Some 0.; top = Some 0.; right = Some 0.; bottom = Some 0. }
    , Stack_position { right = Some 16.; bottom = Some 16.; _ } ) -> ()
  | _ -> failwith "body overlay did not keep its base tight and overlay positioned"
;;

let test_viewport_extent_and_body_validation () =
  let vertical = Ui.Widget.List_view.vertical ~on_scroll:handler [] () in
  List.iter
    (fun height ->
       expect_invalid
         (fun () -> Ui.Widget.Viewport.Vertical.with_height ~height vertical)
         "invalid explicit viewport height was accepted")
    [ nan; infinity; neg_infinity; 0.; -1. ];
  let horizontal = Ui.Widget.List_view.horizontal ~on_scroll:handler [] () in
  List.iter
    (fun width ->
       expect_invalid
         (fun () -> Ui.Widget.Viewport.Horizontal.with_width ~width horizontal)
         "invalid explicit viewport width was accepted")
    [ nan; infinity; neg_infinity; 0.; -1. ];
  expect_invalid
    (fun () -> Ui.Widget.Body.Vertical.fill ~flex:0 vertical)
    "zero body flex was accepted";
  expect_invalid
    (fun () -> Ui.Widget.Body.Vertical.create [])
    "empty vertical body was accepted";
  expect_invalid
    (fun () -> Ui.Widget.Body.Horizontal.create [])
    "empty horizontal body was accepted"
;;

let () =
  test_core_constructors ();
  test_navigation_constructors ();
  test_debug_tree ();
  test_semantics_properties ();
  test_styled_text_constructor_and_validation ();
  test_typed_viewport_body_encoding ();
  test_viewport_extent_and_body_validation ()
;;
