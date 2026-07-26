module Protocol = Bonsai_flutter_protocol

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

let counter_frame : Protocol.Wire_frame.t =
  { runtime_epoch = 7L
  ; base_revision = 0L
  ; target_revision = 1L
  ; kind = Full_snapshot
  ; operations =
      [ Create_node
          { node_id = 1L
          ; kind = Column
          ; props = Linear_props
          ; event_bindings = []
          ; parent_data = No_parent_data
          }
      ; Create_node
          { node_id = 2L
          ; kind = Text
          ; props = Text_props { value = "Count: 0" }
          ; event_bindings = []
          ; parent_data = No_parent_data
          }
      ; Set_children { node_id = 1L; children = [ 2L ] }
      ; Set_root 1L
      ]
  }
;;

let fixtures : (string * Protocol.Wire_frame.t) list =
  let open Protocol.Wire_frame in
  [ ( "ocaml_empty_incremental.hex"
    , { runtime_epoch = 7L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations = []
      } )
  ; "ocaml_counter_full.hex", counter_frame
  ; "counter_full.hex", counter_frame
  ; ( "ocaml_unicode_update.hex"
    , { runtime_epoch = 7L
      ; base_revision = 1L
      ; target_revision = 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props { node_id = 2L; props = Text_props { value = "计数: 😀" } } ]
      } )
  ; ( "ocaml_reordered_children.hex"
    , { runtime_epoch = 7L
      ; base_revision = 2L
      ; target_revision = 3L
      ; kind = Incremental_frame
      ; operations = [ Set_children { node_id = 1L; children = [ 3L; 2L ] } ]
      } )
  ; ( "ocaml_host_request.hex"
    , { runtime_epoch = 31L
      ; base_revision = 2L
      ; target_revision = 3L
      ; kind = Incremental_frame
      ; operations =
          [ Host_request { request_id = 41L; payload = Clipboard_write { text = "剪贴板😀" } }
          ]
      } )
  ; ( "ocaml_animated_opacity.hex"
    , { runtime_epoch = 7L
      ; base_revision = 3L
      ; target_revision = 4L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.25
                    ; animation = { id = 7001L; duration_ms = 250; curve = Ease_in_out }
                    }
              }
          ]
      } )
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
