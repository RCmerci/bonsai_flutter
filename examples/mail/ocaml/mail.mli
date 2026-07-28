val component : Driver.Handler.t -> Bonsai.graph -> Bonsai_flutter_ui.Widget.t Bonsai.t
val app : App.t

module For_testing : sig
  val initial_inbox_ids : int list
end
