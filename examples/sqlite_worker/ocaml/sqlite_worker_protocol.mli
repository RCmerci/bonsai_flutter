(** Immutable messages shared by the SQLite Worker Domain and domain 0. *)

type todo =
  { id : int64
  ; title : string
  ; completed : bool
  }

type snapshot =
  { todos : todo list
  ; database_revision : int64
  }

type mutation_status =
  [ `Applied
  | `Duplicate
  ]

type mutation_result =
  { status : mutation_status
  ; database_revision : int64
  }

type error =
  | Invalid_title
  | Title_too_long
  | Invalid_path of string
  | Unsupported_schema of int
  | Busy
  | Full
  | Read_only
  | Cannot_open of string
  | Corrupt of string
  | Todo_not_found of int64
  | Migration_failed of string
  | Storage_error of string

val error_to_string : error -> string

type operation =
  | List_todos
  | Create_todo of
      { mutation_id : string
      ; title : string
      }
  | Set_completed of
      { mutation_id : string
      ; todo_id : int64
      ; completed : bool
      }

type request =
  { query_generation : int64
  ; operation : operation
  }

type response_payload =
  | Snapshot of snapshot
  | Mutation of mutation_result

type response =
  | Completed of
      { query_generation : int64
      ; database_revision : int64
      ; payload : response_payload
      }
  | Failed of
      { query_generation : int64
      ; error : error
      }

type summary =
  { database_revision : int64
  ; open_count : int
  ; completed_count : int
  }

type startup_timing =
  { sqlite_open_us : int64
  ; initial_list_us : int64
  ; total_us : int64
  }

type push =
  | Ready of
      { schema_version : int
      ; database_revision : int64
      ; sqlite_open_us : int64
      }
  | Store_changed of snapshot
  | Summary_changed of summary
  | Startup_timing of startup_timing
  | Fatal of error

module Topic : sig
  val ready : int
  val store : int
  val summary : int
  val fatal : int
  val startup_timing : int
  val count : int
end
