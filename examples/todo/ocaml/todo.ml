module Ui = Bonsai_flutter_ui

type item =
  { id : int
  ; title : string
  ; completed : bool
  ; document_revision : int64
  ; accepted_local_revision : int64
  }

type state =
  { next_id : int
  ; selected : int option
  ; items : item list
  }

let equal = ( = )

let initial =
  { next_id = 4
  ; selected = Some 1
  ; items =
      [ { id = 1
        ; title = "Keep identity"
        ; completed = false
        ; document_revision = 1L
        ; accepted_local_revision = 0L
        }
      ; { id = 2
        ; title = "Preserve focus"
        ; completed = false
        ; document_revision = 1L
        ; accepted_local_revision = 0L
        }
      ; { id = 3
        ; title = "Dispose deleted resources"
        ; completed = true
        ; document_revision = 1L
        ; accepted_local_revision = 0L
        }
      ]
  }
;;

let value title =
  let cursor = Ui.Text_editing.Utf16.length title in
  let selection =
    Ui.Text_editing.Range.create ~text:title ~start_utf16:cursor ~end_utf16:cursor
  in
  Ui.Text_editing.Value.create ~text:title ~selection ()
;;

let update_item state id update =
  { state with
    items = List.map (fun item -> if item.id = id then update item else item) state.items
  }
;;

let component handlers graph =
  let state, set_state = Bonsai.state' ~equal initial graph in
  let add =
    Bonsai.map set_state ~f:(fun set_state ->
      Driver.Handler.create handlers ~name:"todo-add" (fun _ ->
        set_state (fun state ->
          let item =
            { id = state.next_id
            ; title = Printf.sprintf "Todo %d" state.next_id
            ; completed = false
            ; document_revision = 1L
            ; accepted_local_revision = 0L
            }
          in
          { next_id = state.next_id + 1
          ; selected = Some item.id
          ; items = state.items @ [ item ]
          })))
  in
  let reverse =
    Bonsai.map set_state ~f:(fun set_state ->
      Driver.Handler.create handlers ~name:"todo-reverse" (fun _ ->
        set_state (fun state -> { state with items = List.rev state.items })))
  in
  let scroll =
    Driver.Handler.create handlers ~name:"todo-scroll" (fun _ -> Bonsai.Effect.Ignore)
  in
  let static_handlers = Bonsai.map2 add reverse ~f:(fun add reverse -> add, reverse) in
  let dynamic =
    Bonsai.map2 state set_state ~f:(fun state set_state -> state, set_state)
  in
  Bonsai.map2 dynamic static_handlers ~f:(fun (state, set_state) (add, reverse) ->
    let row item =
      let key = Ui.Key.int item.id in
      let select =
        Driver.Handler.create handlers ~name:"todo-select" (fun _ ->
          set_state (fun state -> { state with selected = Some item.id }))
      in
      let toggle =
        Driver.Handler.create handlers ~name:"todo-toggle" (function
          | Ui.Event.Payload.Bool completed ->
            set_state (fun state ->
              update_item state item.id (fun item -> { item with completed }))
          | _ -> Bonsai.Effect.Ignore)
      in
      let delete =
        Driver.Handler.create handlers ~name:"todo-delete" (fun _ ->
          set_state (fun state ->
            { state with
              selected = (if state.selected = Some item.id then None else state.selected)
            ; items = List.filter (fun candidate -> candidate.id <> item.id) state.items
            }))
      in
      let edit =
        Driver.Handler.create handlers ~name:"todo-edit" (function
          | Ui.Event.Payload.Text_edit edit ->
            set_state (fun state ->
              update_item state item.id (fun item ->
                { item with
                  title = edit.text
                ; document_revision = Int64.succ item.document_revision
                ; accepted_local_revision = edit.local_revision
                }))
          | _ -> Bonsai.Effect.Ignore)
      in
      let submit =
        Driver.Handler.create handlers ~name:"todo-submit" (fun _ -> Bonsai.Effect.Ignore)
      in
      let focus =
        Driver.Handler.create handlers ~name:"todo-focus" (function
          | Ui.Event.Payload.Bool true ->
            set_state (fun state -> { state with selected = Some item.id })
          | Ui.Event.Payload.Bool false | _ -> Bonsai.Effect.Ignore)
      in
      Ui.Widget.Flex.row
        ~key
        [ Ui.Widget.Flex.fixed
            (Ui.Material.checkbox ~value:item.completed ~on_changed:toggle ())
        ; Ui.Widget.Flex.expanded
            (Ui.Material.text_field
               ~key:(Ui.Key.string (Printf.sprintf "todo-editor-%d" item.id))
               ~session_id:(Int64.of_int item.id)
               ~document_revision:item.document_revision
               ~accepted_local_revision:item.accepted_local_revision
               ~update_mode:Ui.Text_editing.Ack
               ~value:(value item.title)
               ~on_edit:edit
               ~on_submit:submit
               ~on_focus_changed:focus
               ())
        ; Ui.Widget.Flex.fixed
            (Ui.Material.text_button ~on_press:delete ~child:(Ui.Widget.text "Delete") ())
        ]
      |> Ui.Widget.semantics
           ~properties:
             (Ui.Semantics.create
                ~label:item.title
                ~selected:(state.selected = Some item.id)
                ~checked:item.completed
                ())
      |> Ui.Widget.with_test_id (Ui.Test_id.string (Printf.sprintf "todo-%d" item.id))
      |> fun row ->
      Ui.Material.card ~elevation:1. row
      |> fun card ->
      Ui.Material.list_tile ~key ~on_press:select ~title:card ~selected:false ()
    in
    let list =
      Ui.Widget.column (List.map row state.items)
      |> fun content -> Ui.Widget.scroll_view ~on_scroll:scroll content ()
    in
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Todo") ())
      ~body:
        (Ui.Widget.column
           [ Ui.Widget.Flex.row
               [ Ui.Widget.Flex.expanded
                   (Ui.Material.elevated_button
                      ~on_press:add
                      ~child:(Ui.Widget.text "Add")
                      ())
               ; Ui.Widget.Flex.expanded
                   (Ui.Material.text_button
                      ~on_press:reverse
                      ~child:(Ui.Widget.text "Reverse")
                      ())
               ]
           ; list
           ])
      ())
;;

let app = App.create ~name:"Todo" component
