(** UTF-8 text with Flutter-compatible UTF-16 selection and composing ranges. *)

module Utf16 : sig
  val length : string -> int
  val to_utf8_byte_offset : string -> int -> int option
  val of_utf8_byte_offset : string -> int -> int option
end

module Range : sig
  type t

  val create : text:string -> start_utf16:int -> end_utf16:int -> t
  val start_utf16 : t -> int
  val end_utf16 : t -> int
  val equal : t -> t -> bool
end

module Value : sig
  type t

  val create : text:string -> selection:Range.t -> ?composing:Range.t -> unit -> t
  val text : t -> string
  val selection : t -> Range.t
  val composing : t -> Range.t option
  val equal : t -> t -> bool
end

type update_mode =
  | Ack
  | Correction
  | Force_replace

type keyboard_type =
  | Text
  | Multiline
  | Number
  | Email
  | Phone
  | Url

type input_action =
  | Done
  | Newline
  | Next
  | Previous
  | Search
  | Send
  | Go
