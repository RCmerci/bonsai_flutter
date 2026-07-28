module Ui = Bonsai_flutter_ui

let component handlers graph =
  let settings_open, set_settings_open = Bonsai.state' ~equal:Bool.equal false graph in
  let clipboard, set_clipboard =
    Bonsai.state' ~equal:String.equal "Clipboard not read" graph
  in
  let open_settings =
    Driver.Handler.create
      handlers
      ~name:"open-settings"
      ~equal:( == )
      set_settings_open
      ~f:(fun set_settings_open _ -> set_settings_open (fun _ -> true))
  in
  let close_settings =
    Driver.Handler.create
      handlers
      ~name:"close-settings"
      ~equal:( == )
      set_settings_open
      ~f:(fun set_settings_open -> function
        | Ui.Event.Payload.Route_pop { page_key = "settings"; _ } | Ui.Event.Payload.Unit
          -> set_settings_open (fun _ -> false)
        | _ -> Bonsai.Effect.Ignore)
  in
  let host_effects = Driver.Handler.host_effects handlers in
  let read_clipboard =
    Driver.Handler.create
      handlers
      ~name:"read-clipboard"
      ~equal:( == )
      set_clipboard
      ~f:(fun set_clipboard _ ->
        Bonsai.Effect.bind (Host_effect.Clipboard.read host_effects ()) ~f:(function
          | Ok text -> set_clipboard (fun _ -> text)
          | Error _ -> set_clipboard (fun _ -> "Clipboard request failed")))
  in
  let state =
    Bonsai.map2 settings_open clipboard ~f:(fun settings_open clipboard ->
      settings_open, clipboard)
  in
  let navigation_handlers =
    Bonsai.map2 open_settings close_settings ~f:(fun open_settings close_settings ->
      open_settings, close_settings)
  in
  let handlers =
    Bonsai.map2
      navigation_handlers
      read_clipboard
      ~f:(fun (open_settings, close_settings) read_clipboard ->
        open_settings, close_settings, read_clipboard)
  in
  Bonsai.map2
    state
    handlers
    ~f:(fun (settings_open, clipboard) (open_settings, close_settings, read_clipboard) ->
      let home =
        Ui.Widget.page
          ~page_key:"home"
          ~transition:Ui.Navigation.None
          ~can_pop:false
          ~restoration_id:"home-page"
          (Ui.Widget.column
             [ Ui.Widget.text "Host effects and navigation"
             ; Ui.Widget.text clipboard
             ; Ui.Widget.button
                 ~on_press:read_clipboard
                 ~child:(Ui.Widget.text "Read clipboard")
                 ()
             ; Ui.Widget.button
                 ~on_press:open_settings
                 ~child:(Ui.Widget.text "Open settings")
                 ()
             ])
      in
      let pages =
        if settings_open
        then (
          let settings =
            Ui.Widget.page
              ~page_key:"settings"
              ~transition:Ui.Navigation.Fade
              ~restoration_id:"settings-page"
              (Ui.Widget.column
                 [ Ui.Widget.text "Settings"
                 ; Ui.Widget.overlay
                     ~alignment:Ui.Navigation.Center
                     [ Ui.Widget.text "Overlay owned by OCaml" ]
                 ; Ui.Widget.material_dialog
                     ~barrier_dismissible:false
                     (Ui.Widget.text "Dialog owned by OCaml")
                 ; Ui.Widget.button
                     ~on_press:close_settings
                     ~child:(Ui.Widget.text "Close settings")
                     ()
                 ])
          in
          [ home; settings ])
        else [ home ]
      in
      Ui.Widget.navigator
        ~restoration_scope_id:"host-navigation"
        ~on_pop:close_settings
        pages)
;;
