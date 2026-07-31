val component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_flutter_ui.Widget.t Bonsai.Cont.t

val app : App.t

module For_testing : sig
  val initial_inbox_ids : int list
end
