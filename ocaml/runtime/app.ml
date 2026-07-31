module Context = struct
  type t = Driver.Handler.t

  let environment context = Driver.Handler.environment context |> Environment.value
  let host_effects = Driver.Handler.host_effects
  let event_handler = Driver.Handler.create
  let native_event_handler = Driver.Handler.create_native
end

type t =
  { name : string option
  ; trace : (string -> unit) option
  ; component : Context.t -> Bonsai.Cont.graph -> Bonsai_flutter_ui.Widget.t Bonsai.Cont.t
  }

let validate_name = function
  | None -> ()
  | Some name ->
    if String.length name = 0 then invalid_arg "App.create: name must not be empty";
    if String.contains name '\000'
    then invalid_arg "App.create: name must not contain NUL"
;;

let create ?name ?trace component =
  validate_name name;
  { name; trace; component }
;;

let name t = t.name

module Private = struct
  let component t = t.component
  let trace t = t.trace
end
