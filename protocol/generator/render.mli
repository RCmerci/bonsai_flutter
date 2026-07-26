type outputs =
  { ocaml_interface : string
  ; ocaml_implementation : string
  ; dart : string
  ; markdown : string
  }

val all : Schema.t -> outputs
