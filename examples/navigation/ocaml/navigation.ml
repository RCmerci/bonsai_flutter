module Ui = Bonsai_flutter_ui

let component handlers graph =
  let details_open, set_details_open = Bonsai.state' ~equal:Bool.equal false graph in
  let open_details =
    Driver.Handler.create
      handlers
      ~name:"navigation-open"
      ~equal:( == )
      set_details_open
      ~f:(fun set_open _ -> set_open (fun _ -> true))
  in
  let close_details =
    Driver.Handler.create
      handlers
      ~name:"navigation-close"
      ~equal:( == )
      set_details_open
      ~f:(fun set_open -> function
        | Ui.Event.Payload.Route_pop { page_key = "details"; _ } | Ui.Event.Payload.Unit
          -> set_open (fun _ -> false)
        | _ -> Bonsai.Effect.Ignore)
  in
  let handlers =
    Bonsai.map2 open_details close_details ~f:(fun open_details close_details ->
      open_details, close_details)
  in
  Bonsai.map2 details_open handlers ~f:(fun details_open (open_details, close_details) ->
    let home =
      Ui.Widget.page
        ~page_key:"home"
        ~can_pop:false
        (Ui.Material.scaffold
           ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Navigation") ())
           ~body:
             (Ui.Widget.center
                (Ui.Material.elevated_button
                   ~on_press:open_details
                   ~child:(Ui.Widget.text "Open details")
                   ()))
           ())
    in
    let pages =
      if details_open
      then
        [ home
        ; Ui.Widget.page
            ~page_key:"details"
            ~transition:Ui.Navigation.Slide
            (Ui.Material.scaffold
               ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Details") ())
               ~body:
                 (Ui.Widget.center
                    (Ui.Material.text_button
                       ~on_press:close_details
                       ~child:(Ui.Widget.text "Close details")
                       ()))
               ())
        ]
      else [ home ]
    in
    Ui.Widget.navigator
      ~restoration_scope_id:"navigation-example"
      ~on_pop:close_details
      pages)
;;
