module Ui = Bonsai_flutter_ui

let component handlers graph =
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "No host request has run" graph
  in
  let host = Driver.Handler.host_effects handlers in
  let read_clipboard =
    Driver.Handler.create
      handlers
      ~name:"host-effects-read"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind (Host_effect.Clipboard.read host ()) ~f:(function
          | Ok text -> set_status (fun _ -> "Clipboard: " ^ text)
          | Error _ -> set_status (fun _ -> "Clipboard read failed")))
  in
  let write_clipboard =
    Driver.Handler.create
      handlers
      ~name:"host-effects-write"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (Host_effect.Clipboard.write host "Written by bonsai_flutter")
          ~f:(function
          | Ok () -> set_status (fun _ -> "Clipboard write completed")
          | Error _ -> set_status (fun _ -> "Clipboard write failed")))
  in
  let handlers =
    Bonsai.Cont.map2 read_clipboard write_clipboard ~f:(fun read write -> read, write)
  in
  Bonsai.Cont.map2 status handlers ~f:(fun status (read_clipboard, write_clipboard) ->
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Host effects") ())
      ~body:
        (Ui.Widget.Body.static
           (Ui.Widget.padding
              ~insets:(Ui.Layout.Edge_insets.all 24.)
              (Ui.Widget.column
                 [ Ui.Widget.text status
                 ; Ui.Material.elevated_button
                     ~on_press:read_clipboard
                     ~child:(Ui.Widget.text "Read clipboard")
                     ()
                 ; Ui.Material.text_button
                     ~on_press:write_clipboard
                     ~child:(Ui.Widget.text "Write clipboard")
                     ()
                 ])))
      ())
;;
