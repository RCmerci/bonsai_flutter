module Ui = Bonsai_flutter_ui
module ID = Bonsai_flutter_spec.Id

type gallery_card_event = Activate

type model =
  { checked : bool
  ; press_count : int
  ; native_count : int
  ; text : string
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  ; interaction_status : string
  }

type handlers =
  { press : Ui.Event.Handler.t
  ; toggle : Ui.Event.Handler.t
  ; text_edit : Ui.Event.Handler.t
  ; text_submit : Ui.Event.Handler.t
  ; focus_changed : Ui.Event.Handler.t
  ; interaction : Ui.Event.Handler.t
  ; native : Ui.Event.Handler.t
  ; scroll : Ui.Event.Handler.t
  }

let equal_model left right =
  Bool.equal left.checked right.checked
  && Int.equal left.press_count right.press_count
  && Int.equal left.native_count right.native_count
  && String.equal left.text right.text
  && ID.Text_input.Document_revision.equal left.document_revision right.document_revision
  && ID.Text_input.Local_revision.equal
       left.accepted_local_revision
       right.accepted_local_revision
  && String.equal left.interaction_status right.interaction_status
;;

let initial_model =
  { checked = false
  ; press_count = 0
  ; native_count = 0
  ; text = "Type 中文 or 😀"
  ; document_revision = ID.Text_input.Document_revision.zero
  ; accepted_local_revision = ID.Text_input.Local_revision.zero
  ; interaction_status = "Move, focus, tap, or press a key"
  }
;;

let gallery_card =
  Ui.Native_widget.Extension.create
    ~kind_id:(ID.Native_widget.Kind_id.of_int 1001)
    ~version:1
    ~capabilities:[ Ui.Native_widget.Capability.Stateful; Resource; Semantics ]
    ~encode_props:Bytes.of_string
    ~decode_event:(fun ~event_id payload ->
      if
        ID.Native_widget.Event_id.equal event_id (ID.Native_widget.Event_id.of_int 1)
        && Bytes.length payload = 0
      then Ok Activate
      else Error "unknown gallery card event")
    ()
;;

let interaction_label = function
  | Ui.Event.Payload.Tap _ -> "Tap received in OCaml"
  | Pointer _ -> "Pointer event received in OCaml"
  | Key _ -> "Key event received in OCaml"
  | Bool true -> "Focus entered"
  | Bool false -> "Focus left"
  | _ -> "Typed interaction received in OCaml"
;;

let make_handlers registry set_model =
  let update name f =
    Driver.Handler.create
      registry
      ~name
      ~equal:( == )
      set_model
      ~f:(fun set_model payload -> set_model (fun model -> f model payload))
  in
  let press =
    update "gallery-press" (fun model _ ->
      { model with press_count = model.press_count + 1 })
  in
  let toggle =
    update "gallery-toggle" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool checked -> { model with checked }
      | Unit -> { model with checked = not model.checked }
      | _ -> model)
  in
  let text_edit =
    update "gallery-text-edit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text_edit edit ->
        { model with
          text = edit.text
        ; document_revision = ID.Text_input.Document_revision.succ model.document_revision
        ; accepted_local_revision = edit.local_revision
        }
      | _ -> model)
  in
  let text_submit =
    update "gallery-text-submit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text value ->
        { model with interaction_status = "Submitted: " ^ value }
      | _ -> model)
  in
  let focus_changed =
    update "gallery-focus" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool focused ->
        { model with
          interaction_status =
            (if focused then "Text field focused" else "Text field blurred")
        }
      | _ -> model)
  in
  let interaction =
    update "gallery-interaction" (fun model payload ->
      { model with interaction_status = interaction_label payload })
  in
  let native =
    Driver.Handler.create_native
      registry
      ~name:"gallery-native-card"
      gallery_card
      ~equal:( == )
      set_model
      ~f:(fun set_model Activate ->
        set_model (fun model -> { model with native_count = model.native_count + 1 }))
  in
  let scroll =
    update "gallery-scroll" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Scroll { pixels; _ } ->
        { model with interaction_status = Printf.sprintf "Scroll offset: %.0f" pixels }
      | _ -> model)
  in
  let first_pair = Bonsai.Cont.map2 press toggle ~f:(fun press toggle -> press, toggle) in
  let second_pair =
    Bonsai.Cont.map2 text_edit text_submit ~f:(fun text_edit text_submit ->
      text_edit, text_submit)
  in
  let third_pair =
    Bonsai.Cont.map2 focus_changed interaction ~f:(fun focus_changed interaction ->
      focus_changed, interaction)
  in
  let fourth_pair =
    Bonsai.Cont.map2 native scroll ~f:(fun native scroll -> native, scroll)
  in
  let first_half =
    Bonsai.Cont.map2
      first_pair
      second_pair
      ~f:(fun (press, toggle) (text_edit, text_submit) ->
        press, toggle, text_edit, text_submit)
  in
  let second_half =
    Bonsai.Cont.map2
      third_pair
      fourth_pair
      ~f:(fun (focus_changed, interaction) (native, scroll) ->
        focus_changed, interaction, native, scroll)
  in
  Bonsai.Cont.map2
    first_half
    second_half
    ~f:
      (fun
        (press, toggle, text_edit, text_submit)
        (focus_changed, interaction, native, scroll)
      ->
      { press
      ; toggle
      ; text_edit
      ; text_submit
      ; focus_changed
      ; interaction
      ; native
      ; scroll
      })
;;

let section title children =
  Ui.Material.card
    ~elevation:2.
    (Ui.Widget.padding
       ~insets:(Ui.Layout.Edge_insets.all 16.)
       (Ui.Widget.column (Ui.Widget.text title :: children)))
;;

let text_value model =
  let offset = Ui.Text_editing.Utf16.length model.text in
  let selection =
    Ui.Text_editing.Range.create ~text:model.text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text:model.text ~selection ()
;;

let core_section handlers =
  let decorated =
    Ui.Widget.decorated_box
      ~decoration:
        (Ui.Style.Decoration.create
           ~background:(Ui.Style.Color.rgb ~red:35 ~green:105 ~blue:170)
           ~border_radius:12.
           ())
      (Ui.Widget.padding
         ~insets:(Ui.Layout.Edge_insets.all 12.)
         (Ui.Widget.rich_text [ "Typed "; "core "; "primitives" ]))
  in
  let stack =
    Ui.Widget.Stack.create
      [ Ui.Widget.Stack.child
          (Ui.Widget.sized_box ~width:180. ~height:54. (Ui.Widget.empty ()))
      ; Ui.Widget.Stack.positioned ~left:8. ~top:8. (Ui.Widget.text "Stack")
      ; Ui.Widget.Stack.positioned ~right:8. ~bottom:8. (Ui.Widget.text "positioned")
      ]
  in
  section
    "Core layout and visuals"
    [ Ui.Widget.Flex.row
        [ Ui.Widget.Flex.expanded decorated
        ; Ui.Widget.Flex.fixed
            (Ui.Widget.padding
               ~insets:(Ui.Layout.Edge_insets.only ~left:12. ())
               (Ui.Widget.icon
                  ~font_family:"MaterialIcons"
                  ~size:28.
                  ~color:(Ui.Style.Color.rgb ~red:244 ~green:180 ~blue:0)
                  ~code_point:0xe838
                  ()))
        ]
    ; Ui.Widget.center
        (Ui.Widget.constrained_box
           ~constraints:
             (Ui.Layout.Box_constraints.create ~min_width:180. ~max_width:320. ())
           (Ui.Widget.clip
              ~behavior:Ui.Style.Clip.Anti_alias
              (Ui.Widget.opacity
                 0.92
                 (Ui.Widget.transform
                    ~transform:(Ui.Style.Transform.translate ~x:4. ())
                    stack))))
    ; Ui.Widget.safe_area
        ~minimum:(Ui.Layout.Edge_insets.only ~top:4. ())
        (Ui.Widget.environment_boundary
           (Ui.Widget.text "SafeArea and Environment boundary"))
    ; Ui.Widget.button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Core typed button")
        ()
    ]
;;

let material_section model handlers =
  section
    "Material"
    [ Ui.Material.elevated_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text (Printf.sprintf "Pressed %d times" model.press_count))
        ()
    ; Ui.Material.text_button
        ~on_press:handlers.press
        ~child:(Ui.Widget.text "Text button")
        ()
    ; Ui.Material.icon_button
        ~on_press:handlers.press
        ~icon:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe87d ())
        ()
    ; Ui.Widget.row
        [ Ui.Material.checkbox ~value:model.checked ~on_changed:handlers.toggle ()
        ; Ui.Material.switch ~value:model.checked ~on_changed:handlers.toggle ()
        ; Ui.Cupertino.switch ~value:model.checked ~on_changed:handlers.toggle ()
        ]
    ; Ui.Material.list_tile
        ~selected:model.checked
        ~subtitle:(Ui.Widget.text "Selection truth lives in Bonsai")
        ~leading:(Ui.Widget.icon ~font_family:"MaterialIcons" ~code_point:0xe88a ())
        ~trailing:(Ui.Widget.text "OCaml")
        ~on_press:handlers.toggle
        ~title:(Ui.Widget.text "Typed ListTile")
        ()
    ; Ui.Material.divider ~thickness:1. ()
    ; Ui.Widget.row
        [ Ui.Material.circular_progress_indicator ~value:0.68 ()
        ; Ui.Cupertino.button handlers.press ~child:(Ui.Widget.text "Cupertino button") ()
        ]
    ]
;;

let interaction_section model handlers =
  let target =
    Ui.Widget.keyboard_listener
      ~autofocus:true
      ~key_policy:Ui.Event.Key_policy.Ignored
      ~on_key:handlers.interaction
      (Ui.Widget.focus_scope
         ~on_focus_changed:handlers.interaction
         (Ui.Widget.mouse_region
            ~on_enter:handlers.interaction
            ~on_leave:handlers.interaction
            (Ui.Widget.gesture
               ~on_tap:handlers.interaction
               ~on_double_tap:handlers.interaction
               ~on_long_press:handlers.interaction
               ~on_pointer_down:handlers.interaction
               ~on_pointer_up:handlers.interaction
               (Ui.Widget.padding
                  ~insets:(Ui.Layout.Edge_insets.all 14.)
                  (Ui.Widget.text model.interaction_status)))))
  in
  section "Interactions" [ target ]
;;

let text_input_section model handlers =
  section
    "Text input and IME"
    [ Ui.Material.text_field
        ~session_id:(ID.Text_input.Session_id.of_int64 1L)
        ~document_revision:model.document_revision
        ~accepted_local_revision:model.accepted_local_revision
        ~update_mode:Ui.Text_editing.Ack
        ~value:(text_value model)
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ()
    ; Ui.Widget.text ("Canonical OCaml value: " ^ model.text)
    ]
;;

let native_section model handlers =
  section
    "Native extension"
    [ Ui.Native_widget.widget_with_handler
        gallery_card
        ~key:(Ui.Key.string "gallery-native-card")
        ~props:(Printf.sprintf "Native card: %d" model.native_count)
        ~on_event:handlers.native
        ()
    ]
;;

let view model handlers =
  let body =
    Ui.Widget.column
      [ Ui.Widget.text "OCaml owns every value and handler on this page"
      ; core_section handlers
      ; material_section model handlers
      ; interaction_section model handlers
      ; text_input_section model handlers
      ; native_section model handlers
      ]
  in
  let body =
    Ui.Widget.scroll_view
      ~key:(Ui.Key.string "gallery-scroll")
      ~axis:Ui.Layout.Axis.Vertical
      ~on_scroll:handlers.scroll
      body
      ()
  in
  let body =
    Ui.Widget.padding
      ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:24. ~vertical:16. ())
      body
  in
  let body =
    Ui.Widget.semantics
      ~properties:
        (Ui.Semantics.create
           ~label:"Bonsai Flutter gallery"
           ~role:Ui.Semantics.Role.Generic
           ~enabled:true
           ~checked:model.checked
           ())
      body
  in
  Ui.Widget.theme
    ~data:
      (Ui.Theme.material
         ~brightness:Ui.Style.Brightness.Dark
         ~color_seed:(Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160)
         ())
    (Ui.Material.scaffold
       ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Bonsai Flutter Gallery") ())
       ~body
       ())
;;

let component registry graph =
  let model, set_model = Bonsai_v017.state ~equal:equal_model initial_model graph in
  let handlers = make_handlers registry set_model in
  Bonsai.Cont.map2 model handlers ~f:view
;;
