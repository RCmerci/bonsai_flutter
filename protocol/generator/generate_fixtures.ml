module Protocol = Bonsai_flutter_protocol
module ID = Bonsai_flutter_spec.Id

let epoch = ID.Runtime.Epoch.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let node = ID.Ui.Node_id.of_int64
let request = ID.Host.Request_id.of_int64
let animation = ID.Ui.Animation_id.of_int64

let hex bytes =
  let output = Buffer.create (Bytes.length bytes * 3) in
  Bytes.iteri
    (fun index byte ->
       if index > 0
       then
         if index mod 12 = 0
         then Buffer.add_char output '\n'
         else Buffer.add_char output ' ';
       Printf.bprintf output "%02x" (Char.code byte))
    bytes;
  Buffer.add_char output '\n';
  Buffer.contents output
;;

let read path =
  try
    let channel = open_in_bin path in
    Some
      (Fun.protect
         ~finally:(fun () -> close_in channel)
         (fun () -> really_input_string channel (in_channel_length channel)))
  with
  | Sys_error _ -> None
;;

let write path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)
;;

let encode_frame frame =
  match Protocol.Binary_codec.encode frame with
  | Ok bytes -> bytes
  | Error error -> failwith error.message
;;

let set_u64 bytes offset value = Bytes.set_int64_le bytes offset value
let set_u32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.of_int value)
let set_f64 bytes offset value = set_u64 bytes offset (Int64.bits_of_float value)

let sparse_extent_list_payload () =
  let payload = Bytes.make 36 '\000' in
  set_u64 payload 0 100L;
  set_u64 payload 8 0L;
  set_f64 payload 16 48.;
  set_u32 payload 24 2;
  Bytes.set payload 28 '\001';
  set_u32 payload 32 0;
  payload
;;

let text_props value =
  Protocol.Wire_frame.Text_props
    { value; style = None; text_align = Start; max_lines = None; overflow = Clip_text }
;;

let viewport_body_frame : Protocol.Wire_frame.t =
  let open Protocol.Wire_frame in
  let create ?(parent_data = No_parent_data) node_id kind props =
    Create_node
      { node_id = node (Int64.of_int node_id)
      ; kind
      ; props
      ; event_bindings = []
      ; parent_data
      }
  in
  let row_ids = List.init 10 (fun index -> 9 + index) in
  { runtime_epoch = epoch 57L
  ; base_revision = revision 0L
  ; target_revision = revision 1L
  ; kind = Full_snapshot
  ; operations =
      [ create 1 Material_scaffold (Material_scaffold_props { has_app_bar = false })
      ; create 2 Stack Empty_props
      ; create
          ~parent_data:
            (Stack_position
               { left = Some 0.; top = Some 0.; right = Some 0.; bottom = Some 0. })
          3
          Column
          Linear_props
      ; create
          4
          Material_text_button
          (Material_button_props
             { variant = Text_button; enabled = true; autofocus = false })
      ; create 5 Text (text_props "Search")
      ; Create_node
          { node_id = node 6L
          ; kind = Native_widget
          ; props =
              Native_widget_props
                { kind_id = ID.Native_widget.Kind_id.of_int 4
                ; version = 1
                ; capabilities = 23L
                ; payload = sparse_extent_list_payload ()
                }
          ; event_bindings =
              [ { event_tag = Protocol.Generated_protocol.Event_tag.native_event
                ; handler_id = ID.Ui.Handler_id.of_int64 400L
                }
              ]
          ; parent_data = Flex_parent_data { flex = 1; fit = Tight }
          }
      ; create
          ~parent_data:
            (Stack_position
               { left = None; top = None; right = Some 16.; bottom = Some 16. })
          7
          Material_text_button
          (Material_button_props
             { variant = Text_button; enabled = true; autofocus = false })
      ; create 8 Text (text_props "Capture")
      ]
      @ List.mapi
          (fun index node_id ->
             create node_id Text (text_props (Printf.sprintf "Row %d" index)))
          row_ids
      @ [ Set_children { node_id = node 1L; children = [ node 2L ] }
        ; Set_children { node_id = node 2L; children = [ node 3L; node 7L ] }
        ; Set_children { node_id = node 3L; children = [ node 4L; node 6L ] }
        ; Set_children { node_id = node 4L; children = [ node 5L ] }
        ; Set_children
            { node_id = node 6L
            ; children = List.map (fun id -> node (Int64.of_int id)) row_ids
            }
        ; Set_children { node_id = node 7L; children = [ node 8L ] }
        ; Set_root (node 1L)
        ]
  }
;;

let counter_frame : Protocol.Wire_frame.t =
  { runtime_epoch = epoch 7L
  ; base_revision = revision 0L
  ; target_revision = revision 1L
  ; kind = Full_snapshot
  ; operations =
      [ Create_node
          { node_id = node 1L
          ; kind = Column
          ; props = Linear_props
          ; event_bindings = []
          ; parent_data = No_parent_data
          }
      ; Create_node
          { node_id = node 2L
          ; kind = Text
          ; props =
              Text_props
                { value = "Count: 0"
                ; style = None
                ; text_align = Start
                ; max_lines = None
                ; overflow = Clip_text
                }
          ; event_bindings = []
          ; parent_data = No_parent_data
          }
      ; Set_children { node_id = node 1L; children = [ node 2L ] }
      ; Set_root (node 1L)
      ]
  }
;;

let fixtures : (string * Protocol.Wire_frame.t) list =
  let open Protocol.Wire_frame in
  [ ( "ocaml_empty_incremental.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations = []
      } )
  ; "ocaml_counter_full.hex", counter_frame
  ; "counter_full.hex", counter_frame
  ; ( "ocaml_unicode_update.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 2L
              ; props =
                  Text_props
                    { value = "计数: 😀"
                    ; style = None
                    ; text_align = Start
                    ; max_lines = None
                    ; overflow = Clip_text
                    }
              }
          ]
      } )
  ; ( "ocaml_reordered_children.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 2L
      ; target_revision = revision 3L
      ; kind = Incremental_frame
      ; operations =
          [ Set_children { node_id = node 1L; children = [ node 3L; node 2L ] } ]
      } )
  ; ( "ocaml_host_request.hex"
    , { runtime_epoch = epoch 31L
      ; base_revision = revision 2L
      ; target_revision = revision 3L
      ; kind = Incremental_frame
      ; operations =
          [ Host_request
              { request_id = request 41L; payload = Clipboard_write { text = "剪贴板😀" } }
          ]
      } )
  ; ( "ocaml_application_request.hex"
    , { runtime_epoch = epoch 41L
      ; base_revision = revision 8L
      ; target_revision = revision 9L
      ; kind = Incremental_frame
      ; operations =
          [ Application_request
              { request_id = 501L
              ; payload = Bytes.of_string "\000opaque\255application\128"
              }
          ]
      } )
  ; ( "ocaml_animated_opacity.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 3L
      ; target_revision = revision 4L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.25
                    ; animation =
                        { id = animation 7001L; duration_ms = 250; curve = Ease_in_out }
                    }
              }
          ]
      } )
  ; ( "ocaml_bounded_text_input.hex"
    , { runtime_epoch = epoch 10L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 12L
              ; props =
                  Text_input_props
                    { session_id = ID.Text_input.Session_id.of_int64 7L
                    ; document_revision = ID.Text_input.Document_revision.of_int64 9L
                    ; value =
                        { text = "拼😀音"
                        ; selection = { start_utf16 = 4; end_utf16 = 4 }
                        ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
                        }
                    ; enabled = true
                    ; read_only = false
                    ; obscure_text = false
                    ; keyboard_type = Keyboard_text
                    ; input_action = Done
                    ; accepted_local_revision = ID.Text_input.Local_revision.of_int64 11L
                    ; update_mode = Correction
                    ; autofocus = true
                    ; max_utf8_bytes = Some 64
                    }
              }
          ]
      } )
  ; "ocaml_viewport_body.hex", viewport_body_frame
  ]
;;

let () =
  let check = Array.to_list Sys.argv |> List.exists (String.equal "--check") in
  let root = Sys.getcwd () in
  let fixture name = Filename.concat root ("protocol/generated/fixtures/" ^ name) in
  let stale = ref [] in
  List.iter
    (fun (name, frame) ->
       let path = fixture name in
       let expected = encode_frame frame |> hex in
       if check
       then (if read path <> Some expected then stale := path :: !stale)
       else write path expected)
    fixtures;
  match List.rev !stale with
  | [] -> ()
  | paths ->
    List.iter (fun path -> prerr_endline ("Generated fixture is stale: " ^ path)) paths;
    exit 1
;;
