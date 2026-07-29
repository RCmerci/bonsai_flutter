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
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.t
    -> f:('dependencies -> Bonsai_flutter_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t Bonsai.t

  val native_event_handler
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_flutter_ui.Native_widget.Extension.t
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.t
    -> f:('dependencies -> 'event -> unit Bonsai.Effect.t)
    -> Bonsai_flutter_ui.Event.Handler.t Bonsai.t
end

type t

val create
  :  ?name:string
       (** [trace], when supplied, receives runtime diagnostic messages. Trace sink
      failures are ignored so diagnostics cannot interrupt rendering. *)
  -> ?trace:(string -> unit)
  -> (Context.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t)
  -> t

val name : t -> string option

module Private : sig
  val component
    :  t
    -> Driver.Handler.t
    -> Bonsai.graph
    -> Bonsai_flutter_ui.Widget.t Bonsai.t

  val trace : t -> (string -> unit) option
end
