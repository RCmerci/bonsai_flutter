(** Versioned, bounded little-endian frame encoding. *)

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_flags
  | Invalid_payload_length
  | Frame_too_large
  | Too_many_operations
  | String_too_large
  | Unknown_operation
  | Unknown_node_kind
  | Invalid_props
  | Invalid_utf8
  | Invalid_operation_order
  | Truncated_input
  | Trailing_bytes

type error =
  { code : error_code
  ; message : string
  }

val encode : Wire_frame.t -> (bytes, error) result
val decode : bytes -> (Wire_frame.t, error) result
