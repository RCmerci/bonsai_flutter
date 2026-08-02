(** Versioned startup configuration transported through the existing runtime
    creation byte buffer. *)

type launch_policy =
  | Fresh
  | Replace_existing

type t =
  { entrypoint : Bonsai_flutter_spec.Id.Application.entrypoint_name
  ; launch_policy : launch_policy
  ; application_payload : bytes
  }

(** Decodes a version 1 envelope. A configuration without the [BFR1] magic is
    treated as a legacy raw entrypoint with [Replace_existing] policy. *)
val decode : bytes -> (t, string) result
