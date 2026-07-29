module Ui = Bonsai_flutter_ui

type mailbox =
  | Inbox
  | Archived
  | Trash

type category =
  | Primary
  | Promotions
  | Updates

type attachment =
  { name : string
  ; kind : string
  ; size : string
  }

type message =
  { id : int
  ; sender : string
  ; address : string
  ; subject : string
  ; preview : string
  ; body : string
  ; timestamp : string
  ; read : bool
  ; starred : bool
  ; mailbox : mailbox
  ; category : category
  ; attachment : attachment option
  }

type state =
  { messages : message list
  ; selected_id : int option
  ; notice : string option
  }

let message
      id
      sender
      address
      subject
      preview
      body
      timestamp
      ~read
      ~starred
      ?(category = Primary)
      ?attachment
      ()
  =
  { id
  ; sender
  ; address
  ; subject
  ; preview
  ; body
  ; timestamp
  ; read
  ; starred
  ; mailbox = Inbox
  ; category
  ; attachment
  }
;;

let initial_messages =
  [ message
      1
      "Mara Vale"
      "mara@willowpost.example"
      "The field notes are ready"
      "I gathered the last observations from the north plot."
      "Hello,\n\n\
       I gathered the last observations from the north plot and organized them into a \
       short set of field notes. The new growth is holding steady after the rain.\n\n\
       Highlights:\n\
       • Five young maples are ready for wiring.\n\
       • The cedar bench needs fresh shade cloth.\n\
       • Watering can move to the summer schedule.\n\n\
       I will bring the printed notes to our next workshop.\n\n\
       Mara"
      "9:42 AM"
      ~read:false
      ~starred:true
      ()
  ; message
      2
      "River Tan"
      "river@smallhours.example"
      "A quieter plan for Thursday"
      "Could we move the review to the garden table?"
      "Hi,\n\n\
       Could we move Thursday's review to the garden table at 3 PM? I simplified the \
       agenda to the three decisions that need us both.\n\n\
       River"
      "8:16 AM"
      ~read:true
      ~starred:false
      ()
  ; message
      3
      "Orin Studio"
      "notes@orinstudio.example"
      "Your kiln shelf reservation"
      "The west shelf is held through Monday afternoon."
      "Your west kiln shelf reservation is confirmed through Monday at 4 PM. Reply at \
       the studio desk if you need a longer firing window."
      "Yesterday"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      4
      "Juniper Works"
      "hello@juniperworks.example"
      "Workshop guide and material list"
      "Everything for the miniature landscape session is attached."
      "Hello,\n\n\
       The guide for Saturday's miniature landscape session is attached. Please bring a \
       small towel and wear something comfortable for working with soil.\n\n\
       See you there,\n\
       Juniper Works"
      "Yesterday"
      ~read:false
      ~starred:false
      ~attachment:
        { name = "Miniature-landscape-guide.pdf"; kind = "PDF"; size = "1.8 MB" }
      ()
  ; message
      5
      "Eli North"
      "eli@copperfern.example"
      "Three sketches from the station"
      "The second study has the strongest silhouette."
      "I made three small sketches while waiting at the station. The second one has the \
       strongest silhouette, so I think we should develop that direction."
      "Jul 24"
      ~read:false
      ~starred:true
      ()
  ; message
      6
      "Bramble Library"
      "desk@bramblelibrary.example"
      "Reserved book is available"
      "We will hold The Shape of Small Gardens for seven days."
      "The Shape of Small Gardens is ready for pickup at the main desk. We will hold it \
       for seven days."
      "Jul 23"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      7
      "Nia Moss"
      "nia@papertrail.example"
      "Photos from the morning walk"
      "The fog made the old footbridge look completely new."
      "The fog made the old footbridge look completely new. I selected six photos that \
       tell the story without repeating the same view."
      "Jul 22"
      ~read:true
      ~starred:false
      ()
  ; message
      8
      "Lantern Market"
      "news@lanternmarket.example"
      "Handmade tools this weekend"
      "Local makers are bringing carving knives and wire cutters."
      "This weekend's market includes a small collection of handmade garden tools from \
       local makers."
      "Jul 21"
      ~read:false
      ~starred:false
      ~category:Promotions
      ()
  ; message
      9
      "Aster Quinn"
      "aster@quietledger.example"
      "Budget notes, revised"
      "I moved the display stands into the optional column."
      "I revised the workshop budget and moved the display stands into the optional \
       column. The new total leaves a comfortable reserve."
      "Jul 19"
      ~read:true
      ~starred:true
      ()
  ; message
      10
      "Stone & Stem"
      "orders@stoneandstem.example"
      "Order packed for collection"
      "Your glazed trays will be ready after noon."
      "Your set of glazed trays has been packed and will be ready for collection after \
       noon tomorrow."
      "Jul 18"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      11
      "Tomas Reed"
      "tomas@longtable.example"
      "Notes on the patient pine"
      "I agree that one more season is the right call."
      "I agree that one more season is the right call. The trunk is gaining character, \
       and the lower branch can wait before the next decision."
      "Jul 16"
      ~read:false
      ~starred:false
      ()
  ; message
      12
      "Lumen House"
      "events@lumenhouse.example"
      "Courtyard supper confirmation"
      "Your table for four is confirmed for Friday."
      "Your courtyard table for four is confirmed for Friday at 7 PM. We look forward to \
       welcoming you."
      "Jul 14"
      ~read:true
      ~starred:false
      ()
  ]
;;

let initial = { messages = initial_messages; selected_id = None; notice = None }
let equal_state = ( = )

let update_message state id update =
  { state with
    messages =
      List.map
        (fun candidate -> if candidate.id = id then update candidate else candidate)
        state.messages
  }
;;

let find_message messages id =
  List.find_opt (fun message -> Int.equal message.id id) messages
;;

let category_label = function
  | Primary -> "Primary"
  | Promotions -> "Promotions"
  | Updates -> "Updates"
;;

let color red green blue = Ui.Style.Color.rgb ~red ~green ~blue
let background = color 241 246 251
let surface = color 253 253 255
let search_surface = color 255 255 255
let primary = color 67 95 138
let primary_container = color 220 231 248
let text_primary = color 28 32 38
let text_secondary = color 91 99 110
let unread_surface = color 239 246 255
let star_color = color 218 154 34
let archive_surface = color 80 125 88

let style ?size ?weight ?height ?color () =
  Ui.Style.Text_style.create
    ?font_size:size
    ?font_weight:weight
    ?line_height:height
    ?color
    ()
;;

let styled_text
      ?size
      ?weight
      ?height
      ?color
      ?max_lines
      ?(overflow = Ui.Style.Text_overflow.Clip)
      value
  =
  Ui.Widget.text ~style:(style ?size ?weight ?height ?color ()) ?max_lines ~overflow value
;;

let padding ?(horizontal = 0.) ?(vertical = 0.) child =
  Ui.Widget.padding
    ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal ~vertical ())
    child
;;

let icon ?size ?color code_point =
  Ui.Widget.icon ?size ?color ~font_family:"MaterialIcons" ~code_point ()
;;

let inert_handler handlers name =
  Driver.Handler.create
    handlers
    ~name
    ~equal:Unit.equal
    (Bonsai.return ())
    ~f:(fun () _ -> Bonsai.Effect.Ignore)
;;

let avatar message =
  let avatar_colors =
    [ color 214 229 246
    ; color 229 219 242
    ; color 211 235 224
    ; color 244 224 210
    ; color 226 229 204
    ]
  in
  let background = List.nth avatar_colors (message.id mod List.length avatar_colors) in
  let initial =
    if String.length message.sender = 0 then "?" else String.make 1 message.sender.[0]
  in
  Ui.Widget.sized_box
    ~width:40.
    ~height:40.
    (Ui.Widget.decorated_box
       ~decoration:(Ui.Style.Decoration.create ~background ~border_radius:20. ())
       (Ui.Widget.center
          (styled_text
             ~size:16.
             ~weight:Ui.Style.Font_weight.Medium
             ~color:primary
             initial)))
;;

let semantic_icon_button ~test_id ~label ~selected ~on_press ~code_point ~color =
  Ui.Material.icon_button ~on_press ~icon:(icon ~size:22. ~color code_point) ()
  |> Ui.Widget.with_test_id (Ui.Test_id.string test_id)
  |> Ui.Widget.semantics
       ~properties:
         (Ui.Semantics.create
            ~label
            ~role:Ui.Semantics.Role.Button
            ~enabled:true
            ~selected
            ())
;;

let star_control on_press message ~detail =
  semantic_icon_button
    ~test_id:
      (if detail then "mail-detail-star" else Printf.sprintf "mail-star-%d" message.id)
    ~label:
      (Printf.sprintf
         "%s message from %s"
         (if message.starred then "Starred" else "Not starred")
         message.sender)
    ~selected:message.starred
    ~on_press
    ~code_point:(if message.starred then 0xe5f9 else 0xe5fa)
    ~color:(if message.starred then star_color else text_secondary)
;;

let search_header =
  Ui.Widget.sized_box
    ~height:56.
    (Ui.Widget.decorated_box
       ~decoration:
         (Ui.Style.Decoration.create ~background:search_surface ~border_radius:28. ())
       (Ui.Widget.Flex.row
          [ Ui.Widget.Flex.fixed
              (padding ~horizontal:16. (icon ~size:22. ~color:primary 0xe3c3))
          ; Ui.Widget.Flex.expanded
              (styled_text ~size:16. ~color:text_secondary "Search in mail")
          ; Ui.Widget.Flex.fixed
              (Ui.Widget.sized_box
                 ~width:40.
                 ~height:40.
                 (Ui.Widget.decorated_box
                    ~decoration:
                      (Ui.Style.Decoration.create
                         ~background:primary_container
                         ~border_radius:20.
                         ())
                    (Ui.Widget.center
                       (styled_text
                          ~size:14.
                          ~weight:Ui.Style.Font_weight.Semi_bold
                          ~color:primary
                          "BM"))))
          ; Ui.Widget.Flex.fixed (Ui.Widget.sized_box ~width:8. (Ui.Widget.empty ()))
          ]))
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-search-header")
  |> Ui.Widget.semantics
       ~properties:(Ui.Semantics.create ~label:"Search in mail" ~role:Generic ())
;;

let render_mail_row ~toggle_star ~open_message ~swipe_action message =
  let sender_weight = if message.read then Ui.Style.Font_weight.Normal else Semi_bold in
  let text_column =
    Ui.Widget.column
      [ styled_text
          ~size:15.
          ~weight:sender_weight
          ~color:text_primary
          ~max_lines:1
          ~overflow:Ellipsis
          message.sender
      ; styled_text
          ~size:13.5
          ~weight:(if message.read then Normal else Semi_bold)
          ~color:text_primary
          ~max_lines:1
          ~overflow:Ellipsis
          message.subject
      ; styled_text
          ~size:13.
          ~color:text_secondary
          ~max_lines:1
          ~overflow:Ellipsis
          message.preview
      ]
  in
  let trailing =
    Ui.Widget.column
      [ styled_text
          ~size:11.5
          ~weight:(if message.read then Normal else Semi_bold)
          ~color:text_secondary
          message.timestamp
      ; star_control toggle_star message ~detail:false
      ]
  in
  let content =
    Ui.Widget.gesture
      ~on_tap:open_message
      (Ui.Widget.decorated_box
         ~decoration:
           (Ui.Style.Decoration.create
              ~background:(if message.read then surface else unread_surface)
              ())
         (Ui.Widget.sized_box
            ~height:88.
            (padding
               ~horizontal:16.
               ~vertical:8.
               (Ui.Widget.Flex.row
                  [ Ui.Widget.Flex.fixed (avatar message)
                  ; Ui.Widget.Flex.expanded (padding ~horizontal:12. text_column)
                  ; Ui.Widget.Flex.fixed trailing
                  ]))))
    |> Ui.Widget.with_test_id
         (Ui.Test_id.string (Printf.sprintf "mail-row-%d" message.id))
    |> Ui.Widget.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:
                (Printf.sprintf
                   "%s message from %s"
                   (if message.read then "Read" else "Unread")
                   message.sender)
              ~hint:message.subject
              ~value:(category_label message.category)
              ~role:Ui.Semantics.Role.Button
              ~enabled:true
              ())
  in
  let archive_icon =
    icon ~size:24. ~color:surface 0xe091
    |> Ui.Widget.with_test_id
         (Ui.Test_id.string (Printf.sprintf "mail-swipe-archive-%d" message.id))
  in
  let end_label, end_test_id =
    if message.read
    then "Mark unread", Printf.sprintf "mail-swipe-mark-unread-%d" message.id
    else "Mark read", Printf.sprintf "mail-swipe-mark-read-%d" message.id
  in
  let end_icon =
    icon ~size:24. ~color:surface 0xe3d0
    |> Ui.Widget.with_test_id (Ui.Test_id.string end_test_id)
  in
  let start_action =
    Ui.Native_widget.Swipe_action.action
      ~label:"Archive"
      ~background:archive_surface
      ~disposition:Dismiss
      ~icon:archive_icon
  in
  let end_action =
    Ui.Native_widget.Swipe_action.action
      ~label:end_label
      ~background:primary
      ~disposition:Rebound
      ~icon:end_icon
  in
  Ui.Native_widget.Swipe_action.create_with_handler
    ~key:(Ui.Key.int message.id)
    ~start_action
    ~end_action
    ~content
    ~on_commit:swipe_action
    ()
  |> Ui.Widget.with_test_id
       (Ui.Test_id.string (Printf.sprintf "mail-swipe-%d" message.id))
;;

let mail_row handlers set_state message_id message _graph =
  let dependencies = Bonsai.both set_state message_id in
  let equal_dependencies (left_set_state, left_id) (right_set_state, right_id) =
    left_set_state == right_set_state && Int.equal left_id right_id
  in
  let toggle_star =
    Driver.Handler.create
      handlers
      ~name:"mail-toggle-star"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update_message state message_id (fun message ->
            { message with starred = not message.starred })))
  in
  let open_message =
    Driver.Handler.create
      handlers
      ~name:"mail-open-message"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update_message state message_id (fun message -> { message with read = true })
          |> fun state -> { state with selected_id = Some message_id; notice = None }))
  in
  let swipe_action =
    Driver.Handler.create
      handlers
      ~name:"mail-swipe-action"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) payload ->
        match Ui.Native_widget.Swipe_action.direction_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some Start_to_end ->
          set_state (fun state ->
            update_message state message_id (fun message ->
              { message with mailbox = Archived }))
        | Some End_to_start ->
          set_state (fun state ->
            update_message state message_id (fun message ->
              { message with read = not message.read })))
  in
  let events =
    Bonsai.map2
      (Bonsai.both toggle_star open_message)
      swipe_action
      ~f:(fun (toggle_star, open_message) swipe_action ->
        toggle_star, open_message, swipe_action)
  in
  Bonsai.map2 message events ~f:(fun message (toggle_star, open_message, swipe_action) ->
    render_mail_row ~toggle_star ~open_message ~swipe_action message)
;;

let inbox_page handlers rows =
  let scroll = inert_handler handlers "mail-list-scroll" in
  Bonsai.map2 rows scroll ~f:(fun rows scroll ->
    let rows =
      match rows with
      | `Ok rows -> rows
      | `Duplicate_key message_id ->
        invalid_arg (Printf.sprintf "Mail: duplicate message ID %d" message_id)
    in
    let list =
      Ui.Widget.list_view ~on_scroll:scroll rows ()
      |> Ui.Widget.decorated_box
           ~decoration:
             (Ui.Style.Decoration.create ~background:surface ~border_radius:26. ())
    in
    let content =
      Ui.Widget.Flex.column
        [ Ui.Widget.Flex.fixed (padding ~horizontal:16. ~vertical:10. search_header)
        ; Ui.Widget.Flex.fixed
            (padding
               ~horizontal:20.
               ~vertical:8.
               (styled_text
                  ~size:15.
                  ~weight:Ui.Style.Font_weight.Semi_bold
                  ~color:text_primary
                  "Inbox"
                |> Ui.Widget.semantics
                     ~properties:
                       (Ui.Semantics.create
                          ~label:"Inbox"
                          ~role:Ui.Semantics.Role.Header
                          ~heading_level:1
                          ())))
        ; Ui.Widget.Flex.expanded list
        ]
    in
    Ui.Widget.page
      ~key:(Ui.Key.string "mail-list")
      ~page_key:"mail-list"
      ~can_pop:false
      (Ui.Material.scaffold
         ~body:
           (Ui.Widget.decorated_box
              ~decoration:(Ui.Style.Decoration.create ~background ())
              (Ui.Widget.safe_area content))
         ())
    |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-list-page"))
;;

let toolbar_action ~test_id ~label ~on_press code_point =
  semantic_icon_button
    ~test_id
    ~label
    ~selected:false
    ~on_press
    ~code_point
    ~color:text_secondary
;;

let reply_action on_press ~test_id ~label code_point =
  Ui.Material.text_button
    ~on_press
    ~child:
      (Ui.Widget.Flex.row
         [ Ui.Widget.Flex.fixed (icon ~size:18. ~color:primary code_point)
         ; Ui.Widget.Flex.expanded
             (padding
                ~horizontal:4.
                (styled_text
                   ~size:13.
                   ~weight:Ui.Style.Font_weight.Medium
                   ~color:primary
                   ~max_lines:1
                   ~overflow:Ellipsis
                   label))
         ])
    ()
  |> Ui.Widget.with_test_id (Ui.Test_id.string test_id)
  |> Ui.Widget.semantics
       ~properties:
         (Ui.Semantics.create ~label ~role:Ui.Semantics.Role.Button ~enabled:true ())
;;

let render_detail_page
      ~back
      ~archive
      ~delete
      ~mark_unread
      ~toggle_star
      ~reply
      ~scroll
      ~notice
      message
  =
  let toolbar =
    Ui.Widget.row
      [ toolbar_action ~test_id:"mail-back" ~label:"Back" ~on_press:back 0xe092
      ; Ui.Widget.Flex.row
          [ Ui.Widget.Flex.fixed
              (toolbar_action
                 ~test_id:"mail-archive"
                 ~label:"Archive"
                 ~on_press:archive
                 0xe091)
          ; Ui.Widget.Flex.fixed
              (toolbar_action
                 ~test_id:"mail-delete"
                 ~label:"Delete"
                 ~on_press:delete
                 0xe1b9)
          ; Ui.Widget.Flex.fixed
              (toolbar_action
                 ~test_id:"mail-mark-unread"
                 ~label:"Mark unread"
                 ~on_press:mark_unread
                 0xe3d0)
          ]
      ]
  in
  let subject =
    Ui.Widget.Flex.row
      [ Ui.Widget.Flex.expanded
          (styled_text
             ~size:23.
             ~weight:Ui.Style.Font_weight.Medium
             ~height:1.25
             ~color:text_primary
             ~max_lines:2
             ~overflow:Ellipsis
             message.subject
           |> Ui.Widget.semantics
                ~properties:
                  (Ui.Semantics.create
                     ~label:message.subject
                     ~role:Ui.Semantics.Role.Header
                     ~heading_level:1
                     ()))
      ; Ui.Widget.Flex.fixed (star_control toggle_star message ~detail:true)
      ]
  in
  let sender =
    Ui.Widget.Flex.row
      [ Ui.Widget.Flex.fixed (avatar message)
      ; Ui.Widget.Flex.expanded
          (padding
             ~horizontal:12.
             (Ui.Widget.column
                [ styled_text
                    ~size:15.
                    ~weight:Ui.Style.Font_weight.Semi_bold
                    ~color:text_primary
                    message.sender
                ; styled_text ~size:12. ~color:text_secondary message.address
                ; styled_text ~size:12. ~color:text_secondary "to me"
                ]))
      ; Ui.Widget.Flex.fixed
          (styled_text ~size:12. ~color:text_secondary message.timestamp)
      ]
    |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-sender-header")
  in
  let body =
    styled_text ~size:15.5 ~height:1.5 ~color:text_primary message.body
    |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-body")
  in
  let attachment =
    Option.map
      (fun attachment ->
         Ui.Widget.decorated_box
           ~decoration:
             (Ui.Style.Decoration.create
                ~background:primary_container
                ~border_radius:16.
                ())
           (padding
              ~horizontal:14.
              ~vertical:12.
              (Ui.Widget.Flex.row
                 [ Ui.Widget.Flex.fixed (icon ~size:24. ~color:primary 0xe0b1)
                 ; Ui.Widget.Flex.expanded
                     (padding
                        ~horizontal:12.
                        (Ui.Widget.column
                           [ styled_text
                               ~size:13.5
                               ~weight:Ui.Style.Font_weight.Medium
                               ~color:text_primary
                               attachment.name
                           ; styled_text
                               ~size:12.
                               ~color:text_secondary
                               (attachment.kind ^ " • " ^ attachment.size)
                           ]))
                 ]))
         |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-attachment")
         |> Ui.Widget.semantics
              ~properties:
                (Ui.Semantics.create
                   ~label:
                     (Printf.sprintf
                        "Attachment %s, %s, %s"
                        attachment.name
                        attachment.kind
                        attachment.size)
                   ()))
      message.attachment
  in
  let notice =
    Option.map
      (fun notice ->
         Ui.Widget.decorated_box
           ~decoration:
             (Ui.Style.Decoration.create
                ~background:primary_container
                ~border_radius:16.
                ())
           (padding
              ~horizontal:14.
              ~vertical:12.
              (styled_text ~size:13. ~color:primary notice))
         |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-inline-notice")
         |> Ui.Widget.semantics
              ~properties:(Ui.Semantics.create ~label:notice ~live_region:true ()))
      notice
  in
  let replies =
    Ui.Widget.Flex.row
      [ Ui.Widget.Flex.expanded
          (reply_action reply ~test_id:"mail-reply" ~label:"Reply" 0xe528)
      ; Ui.Widget.Flex.expanded
          (reply_action reply ~test_id:"mail-reply-all" ~label:"Reply all" 0xe529)
      ; Ui.Widget.Flex.expanded
          (reply_action reply ~test_id:"mail-forward" ~label:"Forward" 0xe2c4)
      ]
  in
  let blocks =
    [ Some (padding ~horizontal:20. ~vertical:12. subject)
    ; Some (padding ~horizontal:20. ~vertical:12. sender)
    ; Some
        (Ui.Widget.decorated_box
           ~decoration:
             (Ui.Style.Decoration.create ~background:surface ~border_radius:20. ())
           (padding ~horizontal:20. ~vertical:20. body))
    ; Option.map (padding ~horizontal:20. ~vertical:10.) attachment
    ; Option.map (padding ~horizontal:20. ~vertical:10.) notice
    ; Some (padding ~horizontal:12. ~vertical:16. replies)
    ]
    |> List.filter_map Fun.id
  in
  let content =
    Ui.Widget.Flex.column
      [ Ui.Widget.Flex.fixed toolbar
      ; Ui.Widget.Flex.expanded
          (Ui.Widget.scroll_view ~on_scroll:scroll (Ui.Widget.column blocks) ())
      ]
  in
  let page_key = Printf.sprintf "mail-detail-%d" message.id in
  Ui.Widget.page
    ~key:(Ui.Key.string page_key)
    ~page_key
    ~transition:Ui.Navigation.Slide
    (Ui.Material.scaffold
       ~body:
         (Ui.Widget.decorated_box
            ~decoration:(Ui.Style.Decoration.create ~background ())
            (Ui.Widget.safe_area content))
       ())
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-detail-page")
;;

let detail_page handlers set_state message_id detail _graph =
  let dependencies = Bonsai.both set_state message_id in
  let equal_dependencies (left_set_state, left_id) (right_set_state, right_id) =
    left_set_state == right_set_state && Int.equal left_id right_id
  in
  let back =
    Driver.Handler.create
      handlers
      ~name:"mail-back"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state -> { state with selected_id = None; notice = None }))
  in
  let close name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update state message_id
          |> fun state -> { state with selected_id = None; notice = None }))
  in
  let archive =
    close "mail-archive" (fun state message_id ->
      update_message state message_id (fun message -> { message with mailbox = Archived }))
  in
  let delete =
    close "mail-delete" (fun state message_id ->
      update_message state message_id (fun message -> { message with mailbox = Trash }))
  in
  let mark_unread =
    close "mail-mark-unread" (fun state message_id ->
      update_message state message_id (fun message -> { message with read = false }))
  in
  let toggle_star =
    Driver.Handler.create
      handlers
      ~name:"mail-toggle-star"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update_message state message_id (fun message ->
            { message with starred = not message.starred })))
  in
  let reply =
    Driver.Handler.create
      handlers
      ~name:"mail-reply-scope-notice"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          { state with notice = Some "Composing is outside the scope of this demo." }))
  in
  let scroll = inert_handler handlers "mail-detail-scroll" in
  let toolbar_handlers =
    Bonsai.map2
      (Bonsai.both back archive)
      (Bonsai.both delete mark_unread)
      ~f:(fun (back, archive) (delete, mark_unread) -> back, archive, delete, mark_unread)
  in
  let message_actions =
    Bonsai.map2 toggle_star reply ~f:(fun toggle_star reply -> toggle_star, reply)
  in
  let page_events =
    Bonsai.map2
      toolbar_handlers
      (Bonsai.both message_actions scroll)
      ~f:(fun (back, archive, delete, mark_unread) ((toggle_star, reply), scroll) ->
        back, archive, delete, mark_unread, toggle_star, reply, scroll)
  in
  Bonsai.map2
    detail
    page_events
    ~f:
      (fun
        (message, notice)
        (back, archive, delete, mark_unread, toggle_star, reply, scroll)
      ->
      render_detail_page
        ~back
        ~archive
        ~delete
        ~mark_unread
        ~toggle_star
        ~reply
        ~scroll
        ~notice
        message)
;;

let component handlers graph =
  let state, set_state = Bonsai.state' ~equal:equal_state initial graph in
  let visible_messages =
    Bonsai.map state ~f:(fun state ->
      List.filter (fun message -> message.mailbox = Inbox) state.messages)
  in
  let rows =
    Bonsai.assoc_list
      (module Core.Int)
      visible_messages
      ~get_key:(fun message -> message.id)
      ~f:(mail_row handlers set_state)
      graph
  in
  let inbox = inbox_page handlers rows in
  let selected_details =
    Bonsai.map state ~f:(fun state ->
      match state.selected_id with
      | None -> []
      | Some message_id ->
        (match find_message state.messages message_id with
         | None -> []
         | Some message -> [ message, state.notice ]))
  in
  let detail_pages =
    Bonsai.assoc_list
      (module Core.Int)
      selected_details
      ~get_key:(fun (message, _) -> message.id)
      ~f:(detail_page handlers set_state)
      graph
  in
  let on_pop =
    Driver.Handler.create
      handlers
      ~name:"mail-route-pop"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Route_pop { page_key; _ } ->
        set_state (fun state ->
          match state.selected_id with
          | Some id when String.equal page_key (Printf.sprintf "mail-detail-%d" id) ->
            { state with selected_id = None; notice = None }
          | None | Some _ -> state)
      | _ -> Bonsai.Effect.Ignore)
  in
  let pages =
    Bonsai.map2 inbox detail_pages ~f:(fun inbox detail_pages ->
      match detail_pages with
      | `Ok detail_pages -> inbox :: detail_pages
      | `Duplicate_key message_id ->
        invalid_arg (Printf.sprintf "Mail: duplicate selected message ID %d" message_id))
  in
  Bonsai.map2 pages on_pop ~f:(fun pages on_pop ->
    Ui.Widget.navigator ~restoration_scope_id:"bonsai-mail" ~on_pop pages
    |> Ui.Widget.constrained_box
         ~constraints:(Ui.Layout.Box_constraints.create ~max_width:720. ())
    |> Ui.Widget.center
    |> Ui.Widget.theme
         ~data:
           (Ui.Theme.material
              ~brightness:Ui.Style.Brightness.Light
              ~color_seed:primary
              ()))
;;

let trace message = Printf.eprintf "[Bonsai Mail][ocaml]%s\n%!" message
let app = App.create ~name:"Bonsai Mail" ~trace component

module For_testing = struct
  let initial_inbox_ids = List.map (fun message -> message.id) initial_messages
end
