(** OCaml-owned runtime table behind the stable C ABI.

    C stores only the positive [int64] handle returned here. It never stores an
    OCaml heap value. *)

type status =
  | Ok
  | Recoverable_error
  | Fatal_error

type create_result =
  { status : status
  ; handle : int64
  ; error : string
  }

type output =
  { status : status
  ; bytes : bytes
  ; presentation_id : int64
  ; revision : int64
  ; error_code : int
  ; error : string
  }

(** Registers an application runtime entrypoint and forces the shared native
    bridge into its complete object. *)
val embed : name:string -> App.t -> unit

val create : bytes -> create_result
val pump : int64 -> int64 -> bytes -> output
val presentation_succeeded : int64 -> int64 -> int64 -> int64 -> output
val presentation_rejected : int64 -> int64 -> int64 -> int -> output
val destroy : int64 -> unit

module For_testing : sig
  val runtime_count : unit -> int
end
