module Ui = Bonsai_flutter_ui

type state =
  { session_id : int64
  ; document_revision : int64
  ; accepted_local_revision : int64
  ; update_mode : Ui.Text_editing.update_mode
  ; value : Ui.Text_editing.Value.t
  }

let equal left right =
  Int64.equal left.session_id right.session_id
  && Int64.equal left.document_revision right.document_revision
  && Int64.equal left.accepted_local_revision right.accepted_local_revision
  && left.update_mode = right.update_mode
  && Ui.Text_editing.Value.equal left.value right.value
;;

let value_of_edit (edit : Ui.Event.Payload.text_edit) =
  let selection =
    Ui.Text_editing.Range.create
      ~text:edit.text
      ~start_utf16:edit.selection.start_utf16
      ~end_utf16:edit.selection.end_utf16
  in
  let composing =
    Option.map
      (fun (composing : Ui.Event.Payload.text_selection) ->
         Ui.Text_editing.Range.create
           ~text:edit.text
           ~start_utf16:composing.start_utf16
           ~end_utf16:composing.end_utf16)
      edit.composing
  in
  Ui.Text_editing.Value.create ~text:edit.text ~selection ?composing ()
;;

let initial_state =
  let text = "Type here" in
  let selection = Ui.Text_editing.Range.create ~text ~start_utf16:9 ~end_utf16:9 in
  { session_id = 1L
  ; document_revision = 1L
  ; accepted_local_revision = 0L
  ; update_mode = Ui.Text_editing.Force_replace
  ; value = Ui.Text_editing.Value.create ~text ~selection ()
  }
;;

let component handlers graph =
  let state, set_state = Bonsai.state' ~equal initial_state graph in
  let edit_handler =
    Driver.Handler.create
      handlers
      ~name:"text-input-edit"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
        | Ui.Event.Payload.Text_edit edit ->
          set_state (fun current ->
            if
              (not (Int64.equal edit.session_id current.session_id))
              || Int64.compare edit.local_revision current.accepted_local_revision <= 0
              || Int64.compare edit.base_document_revision current.document_revision > 0
            then current
            else
              { current with
                document_revision = Int64.succ current.document_revision
              ; accepted_local_revision = edit.local_revision
              ; update_mode = Ui.Text_editing.Ack
              ; value = value_of_edit edit
              })
        | _ -> Bonsai.Effect.Ignore)
  in
  let submit_handler =
    Driver.Handler.create
      handlers
      ~name:"text-input-submit"
      ~equal:Unit.equal
      (Bonsai.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  let focus_handler =
    Driver.Handler.create
      handlers
      ~name:"text-input-focus"
      ~equal:Unit.equal
      (Bonsai.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  let text_input_handlers =
    Bonsai.map2
      edit_handler
      (Bonsai.both submit_handler focus_handler)
      ~f:(fun edit_handler (submit_handler, focus_handler) ->
        edit_handler, submit_handler, focus_handler)
  in
  Bonsai.map2
    state
    text_input_handlers
    ~f:(fun state (edit_handler, submit_handler, focus_handler) ->
    Ui.Widget.text_input
      ~key:(Ui.Key.string "editor")
      ~session_id:state.session_id
      ~document_revision:state.document_revision
      ~accepted_local_revision:state.accepted_local_revision
      ~update_mode:state.update_mode
      ~value:state.value
      ~on_edit:edit_handler
      ~on_submit:submit_handler
      ~on_focus_changed:focus_handler
      ())
;;
