module Test = Bonsai_flutter_test
module Ui = Bonsai_flutter_ui
module Runtime = Bonsai_flutter_runtime
module ID = Bonsai_flutter_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let test_mail_app_disables_trace_by_default () =
  require
    (Option.is_none (App.Private.trace Mail.app))
    "the default mail app enables runtime tracing"
;;

let create_handle () =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  Test.Handle.create
    ~runtime_epoch:(ID.Runtime.Epoch.of_int64 902L)
    ~time_source
    Mail.component
;;

let require_present handle query message =
  require (Option.is_some (Test.Handle.find handle query)) message
;;

let require_absent handle query message =
  require (Option.is_none (Test.Handle.find handle query)) message
;;

let require_node handle query message =
  match Test.Handle.find handle query with
  | Some node -> node
  | None -> fail "%s" message
;;

let with_handle test =
  let handle = create_handle () in
  match test handle with
  | () -> Test.Handle.shutdown handle
  | exception error ->
    Test.Handle.shutdown handle;
    raise error
;;

let test_initial_inbox_and_semantics () =
  with_handle (fun handle ->
    require_present
      handle
      (Test.Query.test_id "mail-list-page")
      "mail list page is missing";
    require_present
      handle
      (Test.Query.test_id "mail-search-header")
      "static mail search header is missing";
    List.iter
      (fun id ->
         require_present
           handle
           (Test.Query.test_id (Printf.sprintf "mail-row-%d" id))
           (Printf.sprintf "visible inbox message %d is missing" id);
         let swipe =
           require_node
             handle
             (Test.Query.test_id (Printf.sprintf "mail-swipe-%d" id))
             (Printf.sprintf "swipe host for message %d is missing" id)
         in
         require
           (Ui.Widget.Private.kind_tag_equal
              swipe.Runtime.Mounted_tree.Snapshot.node_tag
              Ui.Widget.Private.K_native_widget)
           "mail swipe host is not a native widget";
         require
           (Array.length swipe.children = 3)
           "mail swipe host does not have the fixed three-child shape")
      Mail.For_testing.initial_inbox_ids;
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "initial inbox does not expose unread semantics";
    require_present
      handle
      (Test.Query.semantics_label "Read message from River Tan")
      "initial inbox does not expose read semantics")
;;

let native_swipe handle id direction =
  Test.Handle.present handle;
  Test.Handle.native_event
    handle
    (Test.Query.test_id (Printf.sprintf "mail-swipe-%d" id))
    ~kind_id:(ID.Native_widget.Kind_id.of_int 2)
    ~version:2
    ~event_id:(ID.Native_widget.Event_id.of_int 1)
    ~payload:(Bytes.make 1 (Char.chr direction))
;;

let press handle id =
  Test.Handle.present handle;
  Test.Handle.click handle (Test.Query.test_id (Printf.sprintf "mail-pressable-%d" id))
;;

let open_card handle id =
  Test.Handle.present handle;
  Test.Handle.click handle (Test.Query.test_id (Printf.sprintf "mail-card-open-%d" id))
;;

let native_visible_range handle ~first_index ~last_exclusive =
  Test.Handle.present handle;
  Test.Handle.visible_range
    handle
    (Test.Query.kind "Sliver_varied_extent")
    ~first_index:(Int64.of_int first_index)
    ~last_exclusive:(Int64.of_int last_exclusive)
;;

let advance_logical_time handle nanoseconds =
  Test.Handle.present handle;
  ignore (Test.Handle.pump handle ~monotonic_now_ns:nanoseconds ());
  Test.Handle.presentation_succeeded handle ~monotonic_now_ns:nanoseconds
;;

let navigation_props handle =
  let shell =
    require_node
      handle
      (Test.Query.test_id "mail-navigation-shell")
      "mail navigation shell is missing"
  in
  let Av view = Ui.Widget.Private.view shell.Runtime.Mounted_tree.Snapshot.widget in
  match view.node with
  | Ui.Widget.Private.Native_widget { kind_id; payload; _ }
    when ID.Native_widget.Kind_id.equal kind_id (ID.Native_widget.Kind_id.of_int 3) ->
    Ui.Native_widget.Navigation_shell.For_testing.decode_props_exn payload
  | _ -> fail "mail navigation shell has the wrong native contract"
;;

let find_child_by_kind handle (parent : Runtime.Mounted_tree.Snapshot.node) kind =
  Test.Handle.find_all handle (Test.Query.kind kind)
  |> List.find_opt (fun (candidate : Runtime.Mounted_tree.Snapshot.node) ->
    Array.exists (Runtime.Node_id.equal candidate.node_id) parent.children)
;;

let test_only_selected_bottom_destination_has_an_icon_indicator () =
  with_handle (fun handle ->
    let has_indicator test_id =
      let button =
        require_node handle (Test.Query.test_id test_id) "bottom destination is missing"
      in
      let column =
        match find_child_by_kind handle button "Column" with
        | Some node -> node
        | None -> fail "bottom destination has no column"
      in
      let icon_box =
        match find_child_by_kind handle column "Sized_box" with
        | Some node -> node
        | None -> fail "bottom destination has no icon box"
      in
      Option.is_some (find_child_by_kind handle icon_box "Decorated_box")
    in
    require
      (has_indicator "mail-destination-mail")
      "selected Mail destination does not have exactly one icon indicator";
    require
      (not (has_indicator "mail-destination-chat"))
      "unselected Chat destination paints an icon background over its hover state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-chat");
    require
      (not (has_indicator "mail-destination-mail"))
      "unselected Mail destination retained its icon indicator";
    require
      (has_indicator "mail-destination-chat")
      "selected Chat destination does not have exactly one icon indicator")
;;

let safe_area_props node =
  let Av view = Ui.Widget.Private.view node.Runtime.Mounted_tree.Snapshot.widget in
  match view.node with
  | Ui.Widget.Private.Safe_area { left; top; right; bottom; _ } ->
    left, top, right, bottom
  | _ -> fail "expected a safe area node"
;;

let test_navigation_shell_owns_one_colored_bottom_safe_area () =
  with_handle (fun handle ->
    let content_safe_area =
      require_node
        handle
        (Test.Query.test_id "mail-content-safe-area")
        "mail content safe area is missing"
      |> safe_area_props
    in
    let _, content_top, _, content_bottom = content_safe_area in
    require
      (content_top && not content_bottom)
      "mail content consumes the bottom system inset";
    let bottom_background =
      require_node
        handle
        (Test.Query.test_id "mail-bottom-navigation")
        "mail bottom navigation background is missing"
    in
    require
      (Ui.Widget.Private.kind_tag_equal
         bottom_background.Runtime.Mounted_tree.Snapshot.node_tag
         Ui.Widget.Private.K_decorated_box)
      "mail bottom navigation background is not outside its safe area";
    let bottom_safe_area =
      match find_child_by_kind handle bottom_background "Safe_area" with
      | Some node -> safe_area_props node
      | None -> fail "mail bottom navigation does not own a safe area"
    in
    let _, bottom_top, _, bottom_bottom = bottom_safe_area in
    require
      ((not bottom_top) && bottom_bottom)
      "mail bottom navigation has incorrect safe area edges")
;;

let test_star_preserves_keyed_row_identity () =
  with_handle (fun handle ->
    let row_before =
      match Test.Handle.find handle (Test.Query.test_id "mail-row-2") with
      | Some row -> row
      | None -> fail "mail row 2 is missing"
    in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-2");
    let row_after =
      match Test.Handle.find handle (Test.Query.test_id "mail-row-2") with
      | Some row -> row
      | None -> fail "mail row 2 disappeared after starring"
    in
    require
      (Runtime.Node_id.equal row_before.node_id row_after.node_id)
      "starring replaced the keyed mail row";
    require_present
      handle
      (Test.Query.semantics_label "Starred message from River Tan")
      "starred state is not exposed semantically")
;;

let test_expand_open_and_platform_pop_preserve_state () =
  with_handle (fun handle ->
    let swipe_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 is missing before open"
    in
    press handle 1;
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "row press did not expand the inline card";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "row expansion opened the detail page";
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "row expansion marked the message read";
    open_card handle 1;
    let swipe_while_open =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 disappeared behind detail"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_while_open.node_id)
      "opening an unread message replaced its keyed swipe host";
    require_present
      handle
      (Test.Query.key (Ui.Key.string "mail-detail-1"))
      "detail page key is missing or unstable";
    require_present
      handle
      (Test.Query.visible_text "The field notes are ready")
      "detail subject does not match the selected message";
    require_present
      handle
      (Test.Query.visible_text "Mara Vale")
      "detail sender does not match the selected message";
    Test.Handle.present handle;
    Test.Handle.route_pop
      handle
      (Test.Query.kind "Navigator")
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-1")
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "platform pop did not return to the inbox";
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "platform pop did not restore the expanded card";
    require_present
      handle
      (Test.Query.semantics_label "Read message from Mara Vale")
      "opened message did not remain read after platform pop";
    let swipe_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 disappeared after pop"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_after.node_id)
      "read-state change replaced the keyed swipe host")
;;

let test_swipe_archive_removes_only_target_and_retains_following_identity () =
  with_handle (fun handle ->
    let following_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-2")
        "following swipe host is missing before archive"
    in
    native_swipe handle 1 0;
    require_absent
      handle
      (Test.Query.test_id "mail-swipe-1")
      "archive swipe did not remove the target";
    require_absent
      handle
      (Test.Query.test_id "mail-row-1")
      "archive swipe left the target row mounted";
    let following_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-2")
        "archive removed the following row"
    in
    require
      (Runtime.Node_id.equal following_before.node_id following_after.node_id)
      "archiving a preceding row replaced the following keyed swipe host";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "archive swipe opened the detail page")
;;

let test_swipe_read_action_updates_in_place_without_navigation () =
  with_handle (fun handle ->
    let before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host is missing before mark read"
    in
    native_swipe handle 1 1;
    require_present
      handle
      (Test.Query.semantics_label "Read message from Mara Vale")
      "end swipe did not mark the unread message read";
    let after_read =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host disappeared after mark read"
    in
    require
      (Runtime.Node_id.equal before.node_id after_read.node_id)
      "mark read replaced the keyed swipe host";
    native_swipe handle 1 1;
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "second end swipe did not mark the read message unread";
    let after_unread =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host disappeared after mark unread"
    in
    require
      (Runtime.Node_id.equal before.node_id after_unread.node_id)
      "mark unread replaced the keyed swipe host";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "read-state swipe opened the detail page")
;;

let test_swipe_event_filtering_and_nested_action_isolation () =
  with_handle (fun handle ->
    let send kind_id version event_id payload =
      Test.Handle.present handle;
      Test.Handle.native_event
        handle
        (Test.Query.test_id "mail-swipe-1")
        ~kind_id
        ~version
        ~event_id
        ~payload
    in
    send
      (ID.Native_widget.Kind_id.of_int 99)
      1
      (ID.Native_widget.Event_id.of_int 1)
      (Bytes.of_string "\000");
    send
      (ID.Native_widget.Kind_id.of_int 2)
      99
      (ID.Native_widget.Event_id.of_int 1)
      (Bytes.of_string "\000");
    send
      (ID.Native_widget.Kind_id.of_int 2)
      2
      (ID.Native_widget.Event_id.of_int 2)
      (Bytes.of_string "\000");
    send
      (ID.Native_widget.Kind_id.of_int 2)
      2
      (ID.Native_widget.Event_id.of_int 1)
      Bytes.empty;
    send
      (ID.Native_widget.Kind_id.of_int 2)
      2
      (ID.Native_widget.Event_id.of_int 1)
      (Bytes.of_string "\002");
    require_present
      handle
      (Test.Query.test_id "mail-row-1")
      "malformed swipe event mutated the mailbox";
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "malformed swipe event changed read state";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "malformed swipe event opened detail")
;;

let test_stale_route_pop_is_ignored () =
  with_handle (fun handle ->
    press handle 1;
    open_card handle 1;
    Test.Handle.present handle;
    Test.Handle.route_pop
      handle
      (Test.Query.kind "Navigator")
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-999")
      ();
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "stale route-pop key cleared the selected detail";
    Test.Handle.present handle;
    Test.Handle.route_pop
      handle
      (Test.Query.kind "Navigator")
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-1")
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "matching route-pop key did not clear detail")
;;

let test_archive_delete_and_mark_unread () =
  let expect_removed action_id message_id =
    with_handle (fun handle ->
      press handle message_id;
      open_card handle message_id;
      Test.Handle.present handle;
      Test.Handle.click handle (Test.Query.test_id action_id);
      require_absent
        handle
        (Test.Query.test_id (Printf.sprintf "mail-row-%d" message_id))
        (Printf.sprintf
           "%s did not remove message %d from the inbox"
           action_id
           message_id);
      require_absent
        handle
        (Test.Query.test_id "mail-detail-page")
        (Printf.sprintf "%s did not pop detail" action_id))
  in
  expect_removed "mail-archive" 1;
  expect_removed "mail-delete" 2;
  with_handle (fun handle ->
    press handle 3;
    open_card handle 3;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-mark-unread");
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "mark unread did not pop detail";
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Orin Studio")
      "mark unread did not update row semantics")
;;

let test_detail_star_attachment_and_reply_notice () =
  with_handle (fun handle ->
    press handle 4;
    open_card handle 4;
    require_present
      handle
      (Test.Query.test_id "mail-attachment")
      "fixture attachment is missing";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-detail-star");
    require_present
      handle
      (Test.Query.semantics_label "Starred message from Juniper Works")
      "detail star did not update selected state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-reply-all");
    require_present
      handle
      (Test.Query.test_id "mail-inline-notice")
      "reply action did not create the inline notice";
    require_present
      handle
      (Test.Query.visible_text "Composing is outside the scope of this demo.")
      "reply scope notice has the wrong content")
;;

let sliver_varied_extent_node handle =
  let slivers =
    Test.Handle.find_all
      handle
      (Test.Query.kind "Sliver_varied_extent")
  in
  match slivers with
  | sliver :: _ -> sliver
  | [] -> fail "mail scroll view has no sliver_varied_extent child"
;;

let test_initial_virtual_inbox_has_twenty_unique_pressable_rows () =
  with_handle (fun handle ->
    require
      (List.length Mail.For_testing.initial_inbox_ids = 20)
      "initial inbox does not contain twenty messages";
    let unique = Hashtbl.create 20 in
    List.iter
      (fun id ->
         require (not (Hashtbl.mem unique id)) "initial inbox contains duplicate IDs";
         Hashtbl.add unique id ();
         require_present
           handle
           (Test.Query.test_id (Printf.sprintf "mail-pressable-%d" id))
           (Printf.sprintf "initial pressable row %d is missing" id))
      Mail.For_testing.initial_inbox_ids;
    let sliver = sliver_varied_extent_node handle in
    let Av view = Ui.Widget.Private.view sliver.widget in
    (match view.node with
     | Ui.Widget.Private.Sliver_varied_extent { total_count; _ } ->
       require (total_count = 20) "initial logical mail count is not twenty";
       require
         (Array.length sliver.children <= 24)
         "initial virtual window exceeds the supplied bound"
     | _ -> fail "mail virtual list has non-sliver-varied-extent node"))
;;

let test_three_sequential_pages_load_once_and_preserve_overlap_identity () =
  with_handle (fun handle ->
    let overlap_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-16")
        "overlap row is missing before pagination"
    in
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    require_present
      handle
      (Test.Query.test_id "mail-loading-more")
      "tail prefetch did not show the inline loader";
    require_present
      handle
      (Test.Query.semantics_label "Loading more messages")
      "inline loader semantics are missing";
    native_visible_range handle ~first_index:13 ~last_exclusive:20;
    advance_logical_time handle 750_000_010L;
    require_absent
      handle
      (Test.Query.test_id "mail-loading-more")
      "first append did not remove the loader";
    require_present
      handle
      (Test.Query.test_id "mail-pressable-21")
      "first append did not add the next deterministic page";
    require_absent
      handle
      (Test.Query.test_id "mail-pressable-41")
      "duplicate tail notifications appended more than one page";
    let first_page_sliver = sliver_varied_extent_node handle in
    let Av fp_view = Ui.Widget.Private.view first_page_sliver.widget in
    (match fp_view.node with
     | Ui.Widget.Private.Sliver_varied_extent { total_count; _ } ->
       require (total_count = 40) "first cursor appended more than one page"
     | _ -> fail "mail virtual list has non-sliver-varied-extent node");
    let overlap_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-16")
        "overlap row disappeared after pagination"
    in
    require
      (Runtime.Node_id.equal overlap_before.node_id overlap_after.node_id)
      "pagination replaced an overlapping keyed row";
    native_visible_range handle ~first_index:32 ~last_exclusive:40;
    advance_logical_time handle 1_500_000_020L;
    require_present
      handle
      (Test.Query.test_id "mail-pressable-41")
      "second append did not add a page";
    native_visible_range handle ~first_index:52 ~last_exclusive:60;
    advance_logical_time handle 2_250_000_030L;
    require_present
      handle
      (Test.Query.test_id "mail-pressable-61")
      "third append did not add a page";
    native_visible_range handle ~first_index:72 ~last_exclusive:80;
    require_present
      handle
      (Test.Query.test_id "mail-loading-more")
      "the feed stopped offering another page after three appends";
    let final_sliver = sliver_varied_extent_node handle in
    require
      (Array.length final_sliver.children <= 24)
      "rendered mail window grew with loaded session data")
;;

let test_drawer_mailboxes_settings_and_settled_state () =
  with_handle (fun handle ->
    let initial_props = navigation_props handle in
    require (not initial_props.drawer_open) "drawer starts open";
    require initial_props.drawer_enabled "Mail destination does not enable the drawer";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    require (navigation_props handle).drawer_open "Menu did not request drawer open";
    Test.Handle.present handle;
    Test.Handle.native_event
      handle
      (Test.Query.test_id "mail-navigation-shell")
      ~kind_id:(ID.Native_widget.Kind_id.of_int 3)
      ~version:1
      ~event_id:(ID.Native_widget.Event_id.of_int 1)
      ~payload:(Bytes.of_string "\001");
    require (navigation_props handle).drawer_open "settled-open event lost drawer state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-starred");
    require_absent
      handle
      (Test.Query.test_id "mail-row-2")
      "Starred mailbox retained an unstarred message";
    require_present
      handle
      (Test.Query.test_id "mail-row-1")
      "Starred mailbox hid a starred message";
    require_present
      handle
      (Test.Query.visible_text "Starred")
      "Starred mailbox title is missing";
    require
      (not (navigation_props handle).drawer_open)
      "mailbox selection did not close drawer";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-settings");
    require_present
      handle
      (Test.Query.visible_text "Settings are outside the scope of this local mail demo.")
      "Settings destination is a silent no-op";
    Test.Handle.present handle;
    Test.Handle.native_event
      handle
      (Test.Query.test_id "mail-navigation-shell")
      ~kind_id:(ID.Native_widget.Kind_id.of_int 3)
      ~version:1
      ~event_id:(ID.Native_widget.Event_id.of_int 1)
      ~payload:(Bytes.of_string "\000");
    require (not (navigation_props handle).drawer_open) "settled-close event was ignored")
;;

let test_drawer_archived_trash_and_inbox_views_are_functional () =
  with_handle (fun handle ->
    native_swipe handle 1 0;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-archived");
    require_present
      handle
      (Test.Query.test_id "mail-row-1")
      "Archived mailbox did not expose an archived message";
    require_absent
      handle
      (Test.Query.test_id "mail-row-2")
      "Archived mailbox retained an inbox message";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-inbox");
    press handle 2;
    open_card handle 2;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-delete");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-trash");
    require_present
      handle
      (Test.Query.test_id "mail-row-2")
      "Trash mailbox did not expose a deleted message";
    require_absent
      handle
      (Test.Query.test_id "mail-row-1")
      "Trash mailbox retained an archived message")
;;

let test_bottom_destinations_are_explicit_and_restore_mail_state () =
  with_handle (fun handle ->
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    advance_logical_time handle 750_000_010L;
    require_present
      handle
      (Test.Query.test_id "mail-pressable-21")
      "precondition append did not complete";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-2");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-chat");
    let chat_props = navigation_props handle in
    require (chat_props.selected_index = 1) "Chat destination was not selected";
    require (not chat_props.drawer_enabled) "placeholder destination exposes the drawer";
    require_present
      handle
      (Test.Query.visible_text "Chat is outside the scope of this local mail demo.")
      "Chat destination has no explicit placeholder";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-spaces");
    require_present
      handle
      (Test.Query.visible_text "Spaces is outside the scope of this local mail demo.")
      "Spaces destination has no explicit placeholder";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-meet");
    require_present
      handle
      (Test.Query.visible_text "Meet is outside the scope of this local mail demo.")
      "Meet destination has no explicit placeholder";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-mail");
    require ((navigation_props handle).selected_index = 0) "Mail was not restored";
    require_present
      handle
      (Test.Query.semantics_label "Starred message from River Tan")
      "returning to Mail lost message state";
    require_present
      handle
      (Test.Query.test_id "mail-pressable-21")
      "returning to Mail lost loaded messages")
;;

let test_rapid_activation_does_not_duplicate_expansion_or_detail () =
  with_handle (fun handle ->
    Test.Handle.present handle;
    press handle 1;
    require
      (List.length (Test.Handle.find_all handle (Test.Query.test_id "mail-card-1")) = 1)
      "rapid activation created duplicate expanded cards";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "rapid row activation opened detail";
    open_card handle 1;
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "Open did not open detail";
    require
      (List.length (Test.Handle.find_all handle (Test.Query.test_id "mail-detail-page"))
       = 1)
      "Open created duplicate detail pages")
;;

[@@@warning "-69"]

type sparse_list_props_record =
  { total_count : int
  ; first_index : int
  ; default_item_extent : float
  ; extent_overrides : Ui.Widget.Sparse_extent_override.t list
  ; overscan : int
  ; transition : Ui.Widget.Sparse_extent_transition.t option
  }

let sparse_list_props handle =
  let sliver = sliver_varied_extent_node handle in
  let Av view = Ui.Widget.Private.view sliver.widget in
  match view.node with
  | Ui.Widget.Private.Sliver_varied_extent
      { total_count; first_index; default_item_extent; extent_overrides; overscan; transition } ->
    require (Option.is_some transition) "mail list omitted its transition spec";
    { total_count
    ; first_index
    ; default_item_extent
    ; extent_overrides
    ; overscan
    ; transition
    }
  | _ -> fail "expected a sliver_varied_extent node"
;;

let test_expansion_accordion_outline_and_collapse () =
  with_handle (fun handle ->
    let initial_props = sparse_list_props handle in
    require
      (initial_props.extent_overrides = [])
      "initial mail list contains a stale extent override";
    press handle 1;
    let expanded_props = sparse_list_props handle in
    require
      (List.length expanded_props.extent_overrides = 1)
      "expansion did not publish exactly one extent override";
    let override = List.hd expanded_props.extent_overrides in
    require (override.index = 0) "expanded message override has the wrong logical index";
    require
      (Float.compare override.extent expanded_props.default_item_extent > 0)
      "expanded message override is not taller than a compact row";
    List.iter
      (fun test_id ->
         require_present
           handle
           (Test.Query.test_id test_id)
           (Printf.sprintf "outline node %s is missing" test_id))
      [ "mail-outline-1-0"
      ; "mail-outline-1-1"
      ; "mail-outline-1-1-0"
      ; "mail-outline-1-1-1"
      ; "mail-outline-1-1-2"
      ; "mail-outline-1-2"
      ];
    require_present
      handle
      (Test.Query.visible_text "Field notes from the north plot")
      "outline source order starts with the wrong node";
    require_present
      handle
      (Test.Query.visible_text "Printed notes at the next workshop — Mara")
      "muted final outline node is missing";
    press handle 2;
    require_absent
      handle
      (Test.Query.test_id "mail-card-1")
      "accordion left the previous card expanded";
    require_present
      handle
      (Test.Query.test_id "mail-card-2")
      "accordion did not expand the newly activated row";
    let second_props = sparse_list_props handle in
    require
      (List.map
         (fun (override : Ui.Widget.Sparse_extent_override.t) ->
            override.index)
         second_props.extent_overrides
       = [ 1 ])
      "accordion did not atomically replace the extent override";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-card-collapse-2");
    require_absent
      handle
      (Test.Query.test_id "mail-card-2")
      "expanded header did not collapse the card";
    require
      ((sparse_list_props handle).extent_overrides = [])
      "collapse left an extent override behind")
;;

let test_expanded_nested_actions_are_isolated () =
  with_handle (fun handle ->
    press handle 1;
    let swipe_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "expanded swipe host missing"
    in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-1");
    require_present handle (Test.Query.test_id "mail-card-1") "star collapsed the card";
    require_present
      handle
      (Test.Query.semantics_label "Not starred message from Mara Vale")
      "expanded star did not update state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-card-reply-1");
    require_present
      handle
      (Test.Query.test_id "mail-card-notice-1")
      "card Reply did not show its deterministic scope notice";
    require_present handle (Test.Query.test_id "mail-card-1") "Reply collapsed the card";
    require_absent handle (Test.Query.test_id "mail-detail-page") "Reply opened detail";
    native_swipe handle 1 1;
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "read swipe collapsed the card";
    let swipe_after =
      require_node handle (Test.Query.test_id "mail-swipe-1") "swipe host disappeared"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_after.node_id)
      "expanded state update replaced the keyed swipe host";
    native_swipe handle 1 0;
    require_absent handle (Test.Query.test_id "mail-card-1") "archive retained the card";
    require
      ((sparse_list_props handle).extent_overrides = [])
      "archive left the expanded extent override")
;;

let test_filter_cleanup_and_retained_app_destination () =
  with_handle (fun handle ->
    press handle 2;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-chat");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-destination-mail");
    require_present
      handle
      (Test.Query.test_id "mail-card-2")
      "returning to Mail did not preserve expansion";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-starred");
    require_absent
      handle
      (Test.Query.test_id "mail-card-2")
      "mailbox change retained an expanded card";
    require
      ((sparse_list_props handle).extent_overrides = [])
      "mailbox change retained a stale extent override")
;;

let () =
  test_mail_app_disables_trace_by_default ();
  test_initial_inbox_and_semantics ();
  test_initial_virtual_inbox_has_twenty_unique_pressable_rows ();
  test_star_preserves_keyed_row_identity ();
  test_expand_open_and_platform_pop_preserve_state ();
  test_expansion_accordion_outline_and_collapse ();
  test_expanded_nested_actions_are_isolated ();
  test_filter_cleanup_and_retained_app_destination ();
  test_swipe_archive_removes_only_target_and_retains_following_identity ();
  test_swipe_read_action_updates_in_place_without_navigation ();
  test_swipe_event_filtering_and_nested_action_isolation ();
  test_stale_route_pop_is_ignored ();
  test_archive_delete_and_mark_unread ();
  test_detail_star_attachment_and_reply_notice ();
  test_three_sequential_pages_load_once_and_preserve_overlap_identity ();
  test_drawer_mailboxes_settings_and_settled_state ();
  test_drawer_archived_trash_and_inbox_views_are_functional ();
  test_only_selected_bottom_destination_has_an_icon_indicator ();
  test_navigation_shell_owns_one_colored_bottom_safe_area ();
  test_bottom_destinations_are_explicit_and_restore_mail_state ();
  test_rapid_activation_does_not_duplicate_expansion_or_detail ()
;;
