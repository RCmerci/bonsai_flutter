module Test = Bonsai_flutter_test
module Ui = Bonsai_flutter_ui
module Runtime = Bonsai_flutter_runtime

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let create_handle () =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  Test.Handle.create ~runtime_epoch:902L ~time_source Mail.component
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
           (Ui.Widget.Private.Kind.equal swipe.kind Native_widget)
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
    ~kind_id:2
    ~version:1
    ~event_id:1
    ~payload:(Bytes.make 1 (Char.chr direction))
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

let test_open_marks_read_and_platform_pop_preserves_state () =
  with_handle (fun handle ->
    let swipe_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 is missing before open"
    in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-row-1");
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
      ~page_key:"mail-detail-1"
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "platform pop did not return to the inbox";
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
    send 99 1 1 (Bytes.of_string "\000");
    send 2 2 1 (Bytes.of_string "\000");
    send 2 1 2 (Bytes.of_string "\000");
    send 2 1 1 Bytes.empty;
    send 2 1 1 (Bytes.of_string "\002");
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
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-row-1");
    Test.Handle.present handle;
    Test.Handle.route_pop
      handle
      (Test.Query.kind "Navigator")
      ~page_key:"mail-detail-999"
      ();
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "stale route-pop key cleared the selected detail";
    Test.Handle.present handle;
    Test.Handle.route_pop
      handle
      (Test.Query.kind "Navigator")
      ~page_key:"mail-detail-1"
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "matching route-pop key did not clear detail")
;;

let test_archive_delete_and_mark_unread () =
  let expect_removed action_id message_id =
    with_handle (fun handle ->
      Test.Handle.present handle;
      Test.Handle.click
        handle
        (Test.Query.test_id (Printf.sprintf "mail-row-%d" message_id));
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
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-row-3");
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
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-row-4");
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

let () =
  test_initial_inbox_and_semantics ();
  test_star_preserves_keyed_row_identity ();
  test_open_marks_read_and_platform_pop_preserves_state ();
  test_swipe_archive_removes_only_target_and_retains_following_identity ();
  test_swipe_read_action_updates_in_place_without_navigation ();
  test_swipe_event_filtering_and_nested_action_isolation ();
  test_stale_route_pop_is_ignored ();
  test_archive_delete_and_mark_unread ();
  test_detail_star_attachment_and_reply_notice ()
;;
