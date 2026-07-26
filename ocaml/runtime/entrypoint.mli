(** Process-wide registry of applications linked into the native artifact. *)

val register : name:string -> App.t -> unit

module Private : sig
  val find : string -> App.t option
end

module For_testing : sig
  val clear : unit -> unit
  val find : string -> App.t option
end
