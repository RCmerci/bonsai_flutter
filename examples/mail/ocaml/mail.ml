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

type app_destination =
  | Mail
  | Chat
  | Spaces
  | Meet

type mail_destination =
  | Inbox_view
  | Starred_view
  | Archived_view
  | Trash_view
  | Settings_view

type load_state =
  | Idle
  | Loading_more of
      { generation : int
      ; cursor : int
      }

type state =
  { messages : message list
  ; selected_id : int option
  ; notice : string option
  ; selected_app_destination : app_destination
  ; selected_mail_destination : mail_destination
  ; drawer_open : bool
  ; next_cursor : int
  ; next_generation : int
  ; load_state : load_state
  ; window_first : int
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

let curated_messages =
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

let generated_message id =
  message
    id
    (Printf.sprintf "Field Correspondent %d" id)
    (Printf.sprintf "dispatch-%d@fieldnotes.example" id)
    (Printf.sprintf "Field Dispatch %d" id)
    (Printf.sprintf "A concise update from field station %d." id)
    (Printf.sprintf
       "Hello,\n\n\
        This is the deterministic field dispatch for station %d. The notes are ready for \
        the next local review.\n\n\
        Field Correspondent %d"
       id
       id)
    "Earlier"
    ~read:(id mod 2 = 0)
    ~starred:(id mod 7 = 0)
    ~category:
      (match id mod 3 with
       | 0 -> Primary
       | 1 -> Promotions
       | _ -> Updates)
    ()
;;

let generated_messages ~first_id ~count =
  List.init count (fun offset -> generated_message (first_id + offset))
;;

let initial_messages = curated_messages @ generated_messages ~first_id:13 ~count:8

let messages_for_cursor cursor =
  generated_messages ~first_id:((cursor * 20) + 1) ~count:20
;;

let initial =
  { messages = initial_messages
  ; selected_id = None
  ; notice = None
  ; selected_app_destination = Mail
  ; selected_mail_destination = Inbox_view
  ; drawer_open = false
  ; next_cursor = 1
  ; next_generation = 0
  ; load_state = Idle
  ; window_first = 0
  }
;;

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
    (Bonsai.Cont.return ())
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

let search_header on_menu =
  Ui.Widget.sized_box
    ~height:56.
    (Ui.Widget.decorated_box
       ~decoration:
         (Ui.Style.Decoration.create ~background:search_surface ~border_radius:28. ())
       (Ui.Widget.Flex.row
          [ Ui.Widget.Flex.fixed
              (semantic_icon_button
                 ~test_id:"mail-menu"
                 ~label:"Menu"
                 ~selected:false
                 ~on_press:on_menu
                 ~code_point:0xe5d2
                 ~color:primary)
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
    Ui.Widget.decorated_box
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
               ])))
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
              ~role:Ui.Semantics.Role.Generic
              ())
    |> fun child ->
    Ui.Widget.pressable ~key:(Ui.Key.int message.id) ~child ~on_press:open_message ()
    |> Ui.Widget.with_test_id
         (Ui.Test_id.string (Printf.sprintf "mail-pressable-%d" message.id))
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
  let dependencies = Bonsai.Cont.both set_state message_id in
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
      ~f:(fun (set_state, message_id) payload ->
        match payload with
        | Ui.Event.Payload.Unit ->
          set_state (fun state ->
            update_message state message_id (fun message -> { message with read = true })
            |> fun state -> { state with selected_id = Some message_id; notice = None })
        | _ -> Bonsai.Effect.Ignore)
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
    Bonsai.Cont.map2
      (Bonsai.Cont.both toggle_star open_message)
      swipe_action
      ~f:(fun (toggle_star, open_message) swipe_action ->
        toggle_star, open_message, swipe_action)
  in
  Bonsai.Cont.map2
    message
    events
    ~f:(fun message (toggle_star, open_message, swipe_action) ->
      render_mail_row ~toggle_star ~open_message ~swipe_action message)
;;

let mail_destination_title = function
  | Inbox_view -> "Inbox"
  | Starred_view -> "Starred"
  | Archived_view -> "Archived"
  | Trash_view -> "Trash"
  | Settings_view -> "Settings"
;;

let placeholder destination =
  let verb = if String.equal destination "Settings" then "are" else "is" in
  Ui.Widget.center
    (padding
       ~horizontal:24.
       (styled_text
          ~size:17.
          ~color:text_secondary
          (Printf.sprintf
             "%s %s outside the scope of this local mail demo."
             destination
             verb)
        |> Ui.Widget.semantics
             ~properties:(Ui.Semantics.create ~label:(destination ^ " placeholder") ())))
;;

let loading_more_row =
  Ui.Widget.sized_box
    ~height:88.
    (Ui.Widget.center
       (Ui.Material.circular_progress_indicator ()
        |> Ui.Widget.sized_box ~width:24. ~height:24.))
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-loading-more")
  |> Ui.Widget.semantics
       ~properties:
         (Ui.Semantics.create ~label:"Loading more messages" ~live_region:true ())
;;

let render_mail_body ~state ~rows ~open_menu ~on_visible_range =
  match state.selected_mail_destination with
  | Settings_view -> placeholder "Settings"
  | (Inbox_view | Starred_view | Archived_view | Trash_view) as destination ->
    let rows =
      match rows with
      | `Ok rows -> rows
      | `Duplicate_key message_id ->
        invalid_arg (Printf.sprintf "Mail: duplicate message ID %d" message_id)
    in
    let rows =
      match state.load_state, destination with
      | Loading_more _, Inbox_view -> rows @ [ loading_more_row ]
      | Idle, Inbox_view -> rows
      | (Idle | Loading_more _), (Starred_view | Archived_view | Trash_view) -> rows
      | _, Settings_view -> assert false
    in
    let total_count =
      let messages =
        List.filter
          (fun message ->
             match destination with
             | Inbox_view -> message.mailbox = Inbox
             | Starred_view -> message.starred
             | Archived_view -> message.mailbox = Archived
             | Trash_view -> message.mailbox = Trash
             | Settings_view -> false)
          state.messages
      in
      List.length messages
      +
      match state.load_state, destination with
      | Loading_more _, Inbox_view -> 1
      | Idle, Inbox_view -> 0
      | (Idle | Loading_more _), (Starred_view | Archived_view | Trash_view) -> 0
      | _, Settings_view -> 0
    in
    let list =
      Ui.Native_widget.Virtual_list.create_with_handler
        ~total_count
        ~first_index:state.window_first
        ~item_extent:88.
        ~overscan:4
        ~items:rows
        ~on_visible_range
        ()
      |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-virtual-list")
      |> Ui.Widget.decorated_box
           ~decoration:
             (Ui.Style.Decoration.create ~background:surface ~border_radius:26. ())
    in
    let title = mail_destination_title destination in
    Ui.Widget.Flex.column
      [ Ui.Widget.Flex.fixed
          (padding ~horizontal:16. ~vertical:10. (search_header open_menu))
      ; Ui.Widget.Flex.fixed
          (padding
             ~horizontal:20.
             ~vertical:8.
             (styled_text
                ~size:15.
                ~weight:Ui.Style.Font_weight.Semi_bold
                ~color:text_primary
                title
              |> Ui.Widget.semantics
                   ~properties:
                     (Ui.Semantics.create
                        ~label:title
                        ~role:Ui.Semantics.Role.Header
                        ~heading_level:1
                        ())))
      ; Ui.Widget.Flex.expanded list
      ]
;;

let drawer_item ~test_id ~label ~selected ~on_press ~code_point =
  Ui.Material.text_button
    ~on_press
    ~child:
      (Ui.Widget.Flex.row
         [ Ui.Widget.Flex.fixed (icon ~size:21. ~color:primary code_point)
         ; Ui.Widget.Flex.expanded
             (padding
                ~horizontal:16.
                (styled_text
                   ~size:15.
                   ~weight:
                     (if selected
                      then Ui.Style.Font_weight.Semi_bold
                      else Ui.Style.Font_weight.Normal)
                   ~color:text_primary
                   label))
         ])
    ()
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

let render_drawer state ~inbox ~starred ~archived ~trash ~settings =
  let item destination test_id label handler code_point =
    drawer_item
      ~test_id
      ~label
      ~selected:(state.selected_mail_destination = destination)
      ~on_press:handler
      ~code_point
  in
  Ui.Widget.safe_area
    (Ui.Widget.column
       [ padding
           ~horizontal:20.
           ~vertical:20.
           (Ui.Widget.column
              [ styled_text
                  ~size:22.
                  ~weight:Ui.Style.Font_weight.Semi_bold
                  ~color:primary
                  "Bonsai Mail"
              ; styled_text ~size:13. ~color:text_secondary "BM • local@example.test"
              ])
       ; item Inbox_view "mail-drawer-inbox" "Inbox" inbox 0xe158
       ; item Starred_view "mail-drawer-starred" "Starred" starred 0xe5f9
       ; item Archived_view "mail-drawer-archived" "Archived" archived 0xe091
       ; item Trash_view "mail-drawer-trash" "Trash" trash 0xe1b9
       ; item Settings_view "mail-drawer-settings" "Settings" settings 0xe57f
       ])
;;

let bottom_destination ~test_id ~label ~selected ~on_press ~code_point =
  let icon =
    Ui.Widget.center
      (icon ~size:22. ~color:(if selected then primary else text_secondary) code_point)
  in
  let icon =
    if selected
    then
      Ui.Widget.decorated_box
        ~decoration:
          (Ui.Style.Decoration.create ~background:primary_container ~border_radius:14. ())
        icon
    else icon
  in
  Ui.Material.text_button
    ~on_press
    ~child:
      (Ui.Widget.column
         [ Ui.Widget.sized_box ~width:52. ~height:28. icon
         ; styled_text
             ~size:11.
             ~weight:
               (if selected
                then Ui.Style.Font_weight.Semi_bold
                else Ui.Style.Font_weight.Normal)
             ~color:(if selected then primary else text_secondary)
             label
         ])
    ()
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

let render_bottom_navigation state ~mail ~chat ~spaces ~meet =
  let item destination test_id label handler code_point =
    Ui.Widget.Flex.expanded
      (bottom_destination
         ~test_id
         ~label
         ~selected:(state.selected_app_destination = destination)
         ~on_press:handler
         ~code_point)
  in
  Ui.Widget.sized_box
    ~height:64.
    (Ui.Widget.Flex.row
       [ item Mail "mail-destination-mail" "Mail" mail 0xe158
       ; item Chat "mail-destination-chat" "Chat" chat 0xe0b7
       ; item Spaces "mail-destination-spaces" "Spaces" spaces 0xf233
       ; item Meet "mail-destination-meet" "Meet" meet 0xe04b
       ])
  |> Ui.Widget.safe_area ~top:false
  |> Ui.Widget.decorated_box
       ~decoration:(Ui.Style.Decoration.create ~background:surface ())
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-bottom-navigation")
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
  let dependencies = Bonsai.Cont.both set_state message_id in
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
    Bonsai.Cont.map2
      (Bonsai.Cont.both back archive)
      (Bonsai.Cont.both delete mark_unread)
      ~f:(fun (back, archive) (delete, mark_unread) -> back, archive, delete, mark_unread)
  in
  let message_actions =
    Bonsai.Cont.map2 toggle_star reply ~f:(fun toggle_star reply -> toggle_star, reply)
  in
  let page_events =
    Bonsai.Cont.map2
      toolbar_handlers
      (Bonsai.Cont.both message_actions scroll)
      ~f:(fun (back, archive, delete, mark_unread) ((toggle_star, reply), scroll) ->
        back, archive, delete, mark_unread, toggle_star, reply, scroll)
  in
  Bonsai.Cont.map2
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

let messages_for_destination state =
  List.filter
    (fun message ->
       match state.selected_mail_destination with
       | Inbox_view -> message.mailbox = Inbox
       | Starred_view -> message.starred
       | Archived_view -> message.mailbox = Archived
       | Trash_view -> message.mailbox = Trash
       | Settings_view -> false)
    state.messages
;;

let clamp_window_first state message_count =
  min state.window_first (max 0 (message_count - 1))
;;

let rec drop count values =
  if count <= 0
  then values
  else (
    match values with
    | [] -> []
    | _ :: tail -> drop (count - 1) tail)
;;

let rec take count values =
  if count <= 0
  then []
  else (
    match values with
    | [] -> []
    | head :: tail -> head :: take (count - 1) tail)
;;

let window_messages state =
  let messages = messages_for_destination state in
  let first_index = clamp_window_first state (List.length messages) in
  let capacity =
    match state.load_state, state.selected_mail_destination with
    | Loading_more _, Inbox_view -> 23
    | Idle, Inbox_view -> 24
    | (Idle | Loading_more _), (Starred_view | Archived_view | Trash_view | Settings_view)
      -> 24
  in
  messages |> drop first_index |> take capacity
;;

let selected_app_index = function
  | Mail -> 0
  | Chat -> 1
  | Spaces -> 2
  | Meet -> 3
;;

let render_mail_page
      state
      rows
      ~visible_range
      ~open_menu
      ~drawer_settled
      ~inbox
      ~starred
      ~archived
      ~trash
      ~settings
      ~mail
      ~chat
      ~spaces
      ~meet
  =
  let mail_body =
    render_mail_body ~state ~rows ~open_menu ~on_visible_range:visible_range
    |> Ui.Widget.decorated_box ~decoration:(Ui.Style.Decoration.create ~background ())
    |> Ui.Widget.safe_area ~bottom:false
    |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-content-safe-area")
  in
  let bodies =
    [ mail_body; placeholder "Chat"; placeholder "Spaces"; placeholder "Meet" ]
  in
  let drawer = render_drawer state ~inbox ~starred ~archived ~trash ~settings in
  let bottom_navigation = render_bottom_navigation state ~mail ~chat ~spaces ~meet in
  Ui.Native_widget.Navigation_shell.create_with_handler
    ~key:(Ui.Key.string "mail-navigation-shell")
    ~selected_index:(selected_app_index state.selected_app_destination)
    ~drawer_open:state.drawer_open
    ~drawer_enabled:(state.selected_app_destination = Mail)
    ~bodies
    ~drawer
    ~bottom_navigation
    ~on_drawer_state_changed:drawer_settled
    ()
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-navigation-shell")
  |> Ui.Widget.page ~key:(Ui.Key.string "mail-list") ~page_key:"mail-list" ~can_pop:false
  |> Ui.Widget.with_test_id (Ui.Test_id.string "mail-list-page")
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:equal_state initial graph in
  let sleep = Bonsai.Cont.Clock.sleep graph in
  let visible_messages = Bonsai.Cont.map state ~f:window_messages in
  let rows =
    Bonsai.Cont.assoc_list
      (module Core.Int)
      visible_messages
      ~get_key:(fun message -> message.id)
      ~f:(mail_row handlers set_state)
      graph
  in
  let visible_range_dependencies =
    Bonsai.Cont.map2
      state
      (Bonsai.Cont.both set_state sleep)
      ~f:(fun state (set_state, sleep) -> state, set_state, sleep)
  in
  let visible_range =
    Driver.Handler.create
      handlers
      ~name:"mail-visible-range"
      ~equal:(fun (left, left_set, left_sleep) (right, right_set, right_sleep) ->
        equal_state left right && left_set == right_set && left_sleep == right_sleep)
      visible_range_dependencies
      ~f:(fun (snapshot, set_state, sleep) payload ->
        match Ui.Native_widget.Virtual_list.visible_range_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some { first_index; last_exclusive } ->
          let count = List.length (messages_for_destination snapshot) in
          let bounded value = Int64.to_int (Int64.min value (Int64.of_int count)) in
          let first_index = bounded first_index in
          let last_exclusive = bounded last_exclusive in
          let window_first = min (max 0 (first_index - 12)) (max 0 (count - 1)) in
          let should_load =
            snapshot.selected_mail_destination = Inbox_view
            && snapshot.load_state = Idle
            && last_exclusive >= max 0 (count - 8)
          in
          if should_load
          then (
            let generation = snapshot.next_generation in
            let cursor = snapshot.next_cursor in
            Bonsai.Effect.Many
              [ set_state (fun state ->
                  if
                    state.load_state = Idle
                    && state.selected_mail_destination = Inbox_view
                    && Int.equal state.next_cursor cursor
                  then
                    { state with
                      window_first
                    ; load_state = Loading_more { generation; cursor }
                    ; next_generation = generation + 1
                    }
                  else state)
              ; Bonsai.Effect.bind
                  (sleep (Core.Time_ns.Span.of_ms 750.))
                  ~f:(fun () ->
                    set_state (fun state ->
                      match state.load_state with
                      | Loading_more loading
                        when Int.equal loading.generation generation
                             && Int.equal loading.cursor cursor ->
                        { state with
                          messages = state.messages @ messages_for_cursor cursor
                        ; next_cursor = cursor + 1
                        ; load_state = Idle
                        }
                      | Idle | Loading_more _ -> state))
              ])
          else set_state (fun state -> { state with window_first }))
  in
  let open_menu =
    Driver.Handler.create
      handlers
      ~name:"mail-open-drawer"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          if state.selected_app_destination = Mail
          then { state with drawer_open = true }
          else state))
  in
  let drawer_settled =
    Driver.Handler.create
      handlers
      ~name:"mail-drawer-settled"
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        match Ui.Native_widget.Navigation_shell.drawer_state_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some drawer_state ->
          set_state (fun state ->
            { state with
              drawer_open =
                (match drawer_state with
                 | Ui.Native_widget.Navigation_shell.Open -> true
                 | Closed -> false)
            }))
  in
  let mailbox_handler name destination =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state (fun state ->
        let next_generation, load_state =
          match state.load_state with
          | Idle -> state.next_generation, Idle
          | Loading_more _ -> state.next_generation + 1, Idle
        in
        { state with
          selected_mail_destination = destination
        ; drawer_open = false
        ; window_first = 0
        ; next_generation
        ; load_state
        }))
  in
  let inbox = mailbox_handler "mail-drawer-inbox" Inbox_view in
  let starred = mailbox_handler "mail-drawer-starred" Starred_view in
  let archived = mailbox_handler "mail-drawer-archived" Archived_view in
  let trash = mailbox_handler "mail-drawer-trash" Trash_view in
  let settings = mailbox_handler "mail-drawer-settings" Settings_view in
  let app_handler name destination =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state (fun state ->
        { state with selected_app_destination = destination; drawer_open = false }))
  in
  let mail = app_handler "mail-destination-mail" Mail in
  let chat = app_handler "mail-destination-chat" Chat in
  let spaces = app_handler "mail-destination-spaces" Spaces in
  let meet = app_handler "mail-destination-meet" Meet in
  let mailbox_handlers =
    Bonsai.Cont.map2
      (Bonsai.Cont.both inbox starred)
      (Bonsai.Cont.map2
         (Bonsai.Cont.both archived trash)
         settings
         ~f:(fun (archived, trash) settings -> archived, trash, settings))
      ~f:(fun (inbox, starred) (archived, trash, settings) ->
        inbox, starred, archived, trash, settings)
  in
  let app_handlers =
    Bonsai.Cont.map2
      (Bonsai.Cont.both mail chat)
      (Bonsai.Cont.both spaces meet)
      ~f:(fun (mail, chat) (spaces, meet) -> mail, chat, spaces, meet)
  in
  let shell_handlers =
    Bonsai.Cont.map2
      (Bonsai.Cont.both open_menu drawer_settled)
      (Bonsai.Cont.both mailbox_handlers app_handlers)
      ~f:
        (fun
          (open_menu, drawer_settled)
          ((inbox, starred, archived, trash, settings), (mail, chat, spaces, meet))
        ->
        ( open_menu
        , drawer_settled
        , inbox
        , starred
        , archived
        , trash
        , settings
        , mail
        , chat
        , spaces
        , meet ))
  in
  let inbox =
    Bonsai.Cont.map2
      (Bonsai.Cont.both state rows)
      (Bonsai.Cont.both visible_range shell_handlers)
      ~f:
        (fun
          (state, rows)
          ( visible_range
          , ( open_menu
            , drawer_settled
            , inbox
            , starred
            , archived
            , trash
            , settings
            , mail
            , chat
            , spaces
            , meet ) )
        ->
        render_mail_page
          state
          rows
          ~visible_range
          ~open_menu
          ~drawer_settled
          ~inbox
          ~starred
          ~archived
          ~trash
          ~settings
          ~mail
          ~chat
          ~spaces
          ~meet)
  in
  let selected_details =
    Bonsai.Cont.map state ~f:(fun state ->
      match state.selected_id with
      | None -> []
      | Some message_id ->
        (match find_message state.messages message_id with
         | None -> []
         | Some message -> [ message, state.notice ]))
  in
  let detail_pages =
    Bonsai.Cont.assoc_list
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
    Bonsai.Cont.map2 inbox detail_pages ~f:(fun inbox detail_pages ->
      match detail_pages with
      | `Ok detail_pages -> inbox :: detail_pages
      | `Duplicate_key message_id ->
        invalid_arg (Printf.sprintf "Mail: duplicate selected message ID %d" message_id))
  in
  Bonsai.Cont.map2 pages on_pop ~f:(fun pages on_pop ->
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

let app = App.create ~name:"Bonsai Mail" component

module For_testing = struct
  let initial_inbox_ids = List.map (fun message -> message.id) initial_messages
end
