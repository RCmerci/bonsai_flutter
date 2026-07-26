(** A renderer-independent Bonsai application.

    An [App.t] owns no Dart values and can be started by the native runtime or
    by [bonsai_flutter_test]. *)

module Context : sig
  type t = Driver.Handler.t

  val environment : t -> Environment.snapshot Bonsai.t
  val host_effects : t -> Host_effect.t

  val event_handler
    :  t
    -> ?name:string
    -> (Bonsai_flutter_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t

  val native_event_handler
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_flutter_ui.Native_widget.Extension.t
    -> ('event -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t
end

type t

val create
  :  ?name:string
  -> (Context.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t)
  -> t

val name : t -> string option

module Private : sig
  val component
    :  t
    -> Driver.Handler.t
    -> Bonsai.graph
    -> Bonsai_flutter_ui.Widget.t Bonsai.t
end
