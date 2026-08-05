(** Worker Domain service that exclusively owns the SQLite store. *)

val service
  : ( Sqlite_worker_config.t
      , Sqlite_worker_protocol.request
      , Sqlite_worker_protocol.response
      , Sqlite_worker_protocol.push )
      Worker.Service.t
