module Ui = Bonsai_flutter

let require condition message = if not condition then failwith message

let component context _graph =
  let environment = Ui.App.Context.environment context in
  Bonsai.Cont.map environment ~f:(fun environment ->
    Ui.Widget.text
      (Printf.sprintf
         "%.0fx%.0f"
         environment.Ui.Environment.viewport_width
         environment.viewport_height))
;;

let () =
  let (_ : Ui.Host_effect.native_menu_item) =
    { item_id = "copy"; label = "Copy"; enabled = true }
  in
  let (_ : Ui.Host_effect.haptic_kind) = Ui.Host_effect.Haptic_selection in
  let app = Ui.App.create ~name:"public-api-test" component in
  Ui.Entrypoint.For_testing.clear ();
  Ui.Entrypoint.register ~name:"public-api-test" app;
  require
    (Option.is_some (Ui.Entrypoint.For_testing.find "public-api-test"))
    "registered public App was not discoverable";
  ignore (Ui.Effect.return ());
  ignore Ui.Cupertino.button
;;
