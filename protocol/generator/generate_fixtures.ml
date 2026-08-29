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

let text_props value =
  Protocol.Wire_frame.Text_props
    { value; style = None; text_align = Start; max_lines = None; overflow = Clip_text }
;;

let counter_theme_operation =
  let open Protocol.Wire_frame in
  let typography font_family : theme_typography =
    { font_family
    ; font_family_fallback = []
    ; display_large = None
    ; display_medium = None
    ; display_small = None
    ; headline_large = None
    ; headline_medium = None
    ; headline_small = None
    ; title_large = None
    ; title_medium = None
    ; title_small = None
    ; body_large = None
    ; body_medium = None
    ; body_small = None
    ; label_large = None
    ; label_medium = None
    ; label_small = None
    }
  in
  let data
        brightness
        variant
        contrast_level
        typography
        shape
        visual_density
        tap_target_size
    =
    { brightness
    ; color_scheme = { seed_argb = 0xff6750a4l; variant; contrast_level }
    ; typography
    ; shape
    ; visual_density
    ; tap_target_size
    }
  in
  let light =
    data
      Light
      Tonal_spot
      0.
      (typography None)
      { extra_small = 4.; small = 8.; medium = 12.; large = 16.; extra_large = 28. }
      Adaptive
      Padded
  in
  let dark =
    data
      Dark
      Fidelity
      0.5
      (typography (Some "Inter"))
      { extra_small = 2.; small = 6.; medium = 10.; large = 14.; extra_large = 24. }
      Compact
      Shrink_wrap
  in
  Set_application_theme
    { title = Some "Counter"
    ; theme =
        { mode = System
        ; light
        ; dark
        ; high_contrast_light = None
        ; high_contrast_dark = None
        }
    }
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
  let row_ids = List.init 10 (fun index -> 10 + index) in
  { runtime_epoch = epoch 57L
  ; base_revision = revision 0L
  ; target_revision = revision 1L
  ; kind = Full_snapshot
  ; operations =
      [ counter_theme_operation
      ; create
          1
          Material_scaffold
          (Material_scaffold_props
             { has_app_bar = false
             ; has_floating_action_button = false
             ; floating_action_button_location = End_float
             ; has_bottom_navigation_bar = false
             ; has_bottom_sheet = false
             })
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
      ; create
          ~parent_data:(Flex_parent_data { flex = 1; fit = Tight })
          6
          Scroll_view
          (Scroll_view_props
             { axis = Vertical; reverse = false; primary = true; cache_extent = None })
      ; Create_node
          { node_id = node 9L
          ; kind = Sliver_varied_extent
          ; props =
              Sliver_varied_extent_props
                { total_count = 100
                ; first_index = 0
                ; default_item_extent = 48.
                ; overscan = 2
                ; extent_overrides = []
                ; transition = None
                }
          ; event_bindings =
              [ { event_tag = Protocol.Generated_protocol.Event_tag.visible_range_changed
                ; handler_id = ID.Ui.Handler_id.of_int64 400L
                }
              ]
          ; parent_data = No_parent_data
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
        ; Set_children { node_id = node 6L; children = [ node 9L ] }
        ; Set_children
            { node_id = node 9L
            ; children = List.map (fun id -> node (Int64.of_int id)) row_ids
            }
        ; Set_children { node_id = node 7L; children = [ node 8L ] }
        ; Set_root (node 1L)
        ]
  }
;;

let additional_material_frame : Protocol.Wire_frame.t =
  let open Protocol.Wire_frame in
  let props =
    [ Material_search_bar_props
        { session_id = ID.Text_input.Session_id.of_int64 3L
        ; document_revision = ID.Text_input.Document_revision.of_int64 8L
        ; value =
            { text = "find"
            ; selection = { start_utf16 = 1; end_utf16 = 4 }
            ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
            }
        ; enabled = true
        ; read_only = false
        ; keyboard_type = Keyboard_text
        ; input_action = Search
        ; accepted_local_revision = ID.Text_input.Local_revision.of_int64 5L
        ; update_mode = Correction
        ; autofocus = true
        ; max_utf8_bytes = Some 64
        ; has_leading = true
        ; trailing_count = 2
        ; hint_text = Some "Search"
        ; has_on_tap = true
        }
    ; Material_tooltip_props
        { message = "Details"
        ; enabled = true
        ; exclude_from_semantics = false
        ; prefer_below = false
        ; trigger_mode = Tooltip_tap
        ; wait_duration_ms = 20
        ; show_duration_ms = 1500
        ; exit_duration_ms = 100
        ; enable_tap_to_dismiss = true
        ; enable_feedback = false
        ; has_on_triggered = true
        }
    ; Material_data_table_props
        { columns =
            [ { column_id = 11L; tooltip = Some "Name"; numeric = false; sortable = true }
            ]
        ; rows =
            [ { row_id = 21L
              ; selected = true
              ; selection_enabled = true
              ; cells =
                  [ { placeholder = false; show_edit_icon = true; activatable = true } ]
              }
            ]
        ; sort_column_id = Some 11L
        ; sort_ascending = false
        ; selected_row_ids = [ 21L ]
        ; has_on_sort = true
        ; has_on_row_selected = true
        ; has_on_select_all = true
        ; has_on_cell_activate = true
        }
    ; Material_stepper_props
        { orientation = Horizontal
        ; current_step_id = 31L
        ; steps =
            [ { step_id = 31L
              ; active = true
              ; state = Step_editing
              ; has_subtitle = true
              ; has_label = true
              }
            ]
        }
    ; Material_expansion_panel_list_props
        { policy = Single_panel
        ; expanded_ids = [ 41L ]
        ; panels = [ { panel_id = 41L; enabled = true; can_tap_on_header = true } ]
        }
    ; Material_simple_dialog_props
        { has_title = true; options = [ { option_id = 51L; enabled = true } ] }
    ; Material_fullscreen_dialog_props
    ; Material_chip_props
        { variant = Action_chip
        ; presentation = Elevated_chip
        ; enabled = true
        ; selected = false
        ; has_avatar = true
        ; has_delete_icon = false
        ; has_on_press = true
        ; has_on_selected = false
        ; has_on_delete = false
        }
    ; Material_card_props { variant = Filled_card; elevation = 2. }
    ; Material_divider_props
        { orientation = Vertical
        ; thickness = 2.
        ; spacing = 24.
        ; indent = 4.
        ; end_indent = 8.
        }
    ]
  in
  { runtime_epoch = epoch 77L
  ; base_revision = revision 1L
  ; target_revision = revision 2L
  ; kind = Incremental_frame
  ; operations =
      List.mapi
        (fun index props ->
           Update_props { node_id = node (Int64.of_int (index + 1)); props })
        props
  }
;;

let counter_frame : Protocol.Wire_frame.t =
  { runtime_epoch = epoch 7L
  ; base_revision = revision 0L
  ; target_revision = revision 1L
  ; kind = Full_snapshot
  ; operations =
      [ counter_theme_operation
      ; Create_node
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
  ; ( "ocaml_modal_bottom_sheet_update.hex"
    , { runtime_epoch = epoch 73L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 30L
              ; props =
                  Page_props
                    { page_key = ID.Navigation.Page_key.of_string "editor"
                    ; presentation =
                        Modal_bottom_sheet
                          { barrier_dismissible = true
                          ; barrier_color_argb = Some (Int32.of_string "0x7f102030")
                          ; barrier_label = Some "Close editor"
                          ; sizing =
                              Detented_sizing
                                { detents = Medium_and_large
                                ; initial_detent = Medium_detent
                                ; dismiss_on_drag = true
                                ; handle_semantics_label = "Adjust sheet height"
                                ; medium_semantics_value = "Half height"
                                ; large_semantics_value = "Full height"
                                }
                          ; use_safe_area = true
                          ; request_focus = true
                          ; transition_duration_ms = 325
                          ; reverse_transition_duration_ms = 175
                          }
                    ; can_pop = true
                    ; restoration_id =
                        Some (ID.Navigation.Restoration_id.of_string "editor-page")
                    }
              }
          ]
      } )
  ; ( "ocaml_primary_scroll.hex"
    , { runtime_epoch = epoch 74L
      ; base_revision = revision 5L
      ; target_revision = revision 6L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 71L
              ; props =
                  Scroll_view_props
                    { axis = Vertical
                    ; reverse = false
                    ; primary = true
                    ; cache_extent = None
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
  ; "ocaml_additional_material_components.hex", additional_material_frame
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
