module ID = Bonsai_flutter_spec.Id
module Ui = Bonsai_flutter

let require condition message = if not condition then failwith message

let application_theme =
  let seed = Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164 in
  let color_scheme =
    Ui.Theme.Color_scheme.from_seed
      ~color:seed
      ~variant:Ui.Theme.Color_scheme.Tonal_spot
      ~contrast_level:0.
      ()
  in
  let typography =
    Ui.Theme.Typography.material
      ~font_family:"Inter"
      ~font_family_fallback:[ "Noto Sans"; "sans-serif" ]
      ~display_large:(Ui.Style.Text_style.create ~font_size:57. ())
      ~headline_medium:(Ui.Style.Text_style.create ~font_size:28. ())
      ~body_large:(Ui.Style.Text_style.create ~font_size:16. ())
      ~label_small:(Ui.Style.Text_style.create ~font_size:11. ())
      ()
  in
  let shape =
    Ui.Theme.Shape.create
      ~extra_small:4.
      ~small:8.
      ~medium:12.
      ~large:16.
      ~extra_large:28.
      ()
  in
  let light =
    Ui.Theme.material
      ~brightness:Ui.Style.Brightness.Light
      ~color_scheme
      ~typography
      ~shape
      ~visual_density:Ui.Theme.Adaptive
      ~tap_target_size:Ui.Theme.Padded
      ()
  in
  let dark =
    Ui.Theme.material
      ~brightness:Ui.Style.Brightness.Dark
      ~color_scheme
      ~typography
      ~shape
      ~visual_density:Ui.Theme.Compact
      ~tap_target_size:Ui.Theme.Shrink_wrap
      ()
  in
  Ui.Theme.application ~mode:Ui.Theme.System ~light ~dark ()
;;

let component context _graph =
  let environment = Ui.App.Context.environment context in
  let application_platform = Ui.App.Context.application_platform context in
  Ui.Application_platform.on_event application_platform (fun _payload ->
    Ui.Effect.return ());
  ignore
    (Ui.Application_platform.request
       application_platform
       (Bytes.of_string "compile-surface"));
  Bonsai.Cont.map environment ~f:(fun environment ->
    Ui.App.View.create
      ~theme:application_theme
      ~body:
        (Ui.Widget.text
           (Printf.sprintf
              "%.0fx%.0f"
              environment.Ui.Environment.viewport_width
              environment.viewport_height)))
;;

let worker_service =
  Ui.Worker.Service.create
    ~push_topic_count:1
    ~concurrency:Ui.Worker.Service.Serial
    ~init:(fun _session () -> Ok ())
    ~handle:(fun _request () request -> Ok request)
    ~shutdown:(fun () -> ())
    ()
;;

let worker_component client _context _graph =
  ignore (Ui.Worker.runtime_epoch client);
  ignore (Ui.Worker.worker_generation client);
  ignore (Ui.Worker.send client "compile-surface");
  Ui.Worker.on_event client (fun _ -> Ui.Effect.return ());
  Bonsai.Cont.return
    (Ui.App.View.create
       ~theme:application_theme
       ~body:(Ui.Widget.text "worker public API"))
;;

let viewport_handler = Ui.Event.Handler.create (fun _ -> ())

let modal_handle_semantics =
  Ui.Navigation.Modal_bottom_sheet.Handle_semantics.create
    ~label:"Adjust sheet height"
    ~medium_value:"Half height"
    ~large_value:"Full height"
;;

let modal_detents =
  Ui.Navigation.Modal_bottom_sheet.Detents.create
    ~initial:Ui.Navigation.Modal_bottom_sheet.Detent.Medium
    ~semantics:modal_handle_semantics
    [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
    ; Ui.Navigation.Modal_bottom_sheet.Detent.Large
    ]
;;

let (_ : Ui.Navigation.page_presentation) =
  Ui.Navigation.Modal_bottom_sheet
    (Ui.Navigation.Modal_bottom_sheet.create
       ~barrier_dismissible:true
       ~barrier_color:(Ui.Style.Color.rgb ~red:1 ~green:2 ~blue:3)
       ~barrier_label:"Close filter"
       ~sizing:(Ui.Navigation.Modal_bottom_sheet.Sizing.Detented modal_detents)
       ~use_safe_area:true
       ~request_focus:true
       ~transition_duration_ms:250
       ~reverse_transition_duration_ms:200
       ())
;;

let (_ : Ui.Navigation.page_presentation) =
  Ui.Navigation.Modal_dialog
    (Ui.Navigation.Modal_dialog.create
       ~barrier_dismissible:false
       ~barrier_color:(Ui.Style.Color.rgb ~red:17 ~green:34 ~blue:51)
       ~barrier_label:"Close confirmation"
       ~use_safe_area:true
       ~request_focus:true
       ~transition_duration_ms:180
       ~reverse_transition_duration_ms:120
       ())
;;

let (_ : Ui.Navigation.page_presentation) =
  Ui.Navigation.Modal_side_sheet
    (Ui.Navigation.Modal_side_sheet.create
       ~barrier_label:"Close side sheet"
       ~use_safe_area:true
       ())
;;

let (_ : Ui.Viewport.Vertical.t) =
  Ui.Widget.Scroll_view.vertical
    ~primary:true
    ~on_scroll:viewport_handler
    [ Ui.Widget.Sliver.list [ Ui.Widget.text "Public row" ] ]
    ()
;;

let (_ : Ui.Viewport.Vertical.t) =
  let fixed_item =
    Ui.Widget.Keyed.create
      ~key:(Bonsai_flutter_ui.Key.string "public-fixed-row")
      (Ui.Widget.text "Public fixed row")
  in
  let varied_item =
    Ui.Widget.Keyed.create
      ~key:(Bonsai_flutter_ui.Key.string "public-varied-row")
      (Ui.Widget.text "Public varied row")
  in
  Ui.Widget.Scroll_view.vertical
    ~on_scroll:viewport_handler
    [ Ui.Widget.Sliver.fixed_extent
        ~total_count:1
        ~first_index:0
        ~item_extent:48.
        ~items:[ fixed_item ]
        ~on_visible_range:viewport_handler
        ()
    ; Ui.Widget.Sliver.varied_extent
        ~total_count:1
        ~first_index:0
        ~default_item_extent:48.
        ~extent_overrides:[]
        ~items:[ varied_item ]
        ~on_visible_range:viewport_handler
        ()
    ]
    ()
;;

let (_ : Ui.Body.t) =
  Ui.Body.Vertical.create
    [ Ui.Body.Vertical.fixed (Ui.Widget.text "Search")
    ; Ui.Body.Vertical.fill
        (Ui.Widget.Scroll_view.vertical
           ~on_scroll:viewport_handler
           [ Ui.Widget.Sliver.list [] ]
           ())
    ]
;;

let () =
  let cancellation = Ui.Application_platform.Cancellation.create () in
  Ui.Application_platform.Cancellation.cancel cancellation;
  require
    (Ui.Application_platform.maximum_payload_bytes = 1_048_576)
    "unexpected public application payload limit";
  let (_ : Ui.Application_platform.error) = Ui.Application_platform.Runtime_replaced in
  let (_ : Ui.Host_effect.native_menu_item) =
    { item_id = ID.Host.Native_menu_item_id.of_string "copy"
    ; label = "Copy"
    ; enabled = true
    }
  in
  let (_ : Ui.Host_effect.haptic_kind) = Ui.Host_effect.Haptic_selection in
  let (_ : Ui.Host_effect.snack_bar_close_reason) = Ui.Host_effect.Action in
  ignore Ui.Host_effect.show_snack_bar;
  let app = Ui.App.create ~name:"public-api-test" component in
  let worker_app =
    Ui.App.create_with_worker
      ~name:"public-worker-api-test"
      ~decode_config:(fun payload ->
        if Bytes.length payload = 0 then Ok () else Error "unexpected payload")
      ~service:worker_service
      worker_component
  in
  Ui.Entrypoint.For_testing.clear ();
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-api-test")
    app;
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-worker-api-test")
    worker_app;
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-api-test")))
    "registered public App was not discoverable";
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-worker-api-test")))
    "registered public worker App was not discoverable";
  ignore (Ui.Effect.return ());
  ignore Ui.Cupertino.button
;;
