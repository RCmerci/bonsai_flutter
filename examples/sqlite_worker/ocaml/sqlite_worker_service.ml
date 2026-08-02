module Protocol = Sqlite_worker_protocol
module Store = Sqlite_worker_store

type state =
  { store : Store.t
  ; mutable snapshot_dirty : bool
  ; startup_started_us : int64
  ; sqlite_open_us : int64
  ; mutable startup_timing_pending : bool
  }

let now_us () = Int64.of_float (Unix.gettimeofday () *. 1_000_000.)

let elapsed_us started =
  let elapsed = Int64.sub (now_us ()) started in
  if Int64.compare elapsed 0L < 0 then 0L else elapsed
;;

let completed query_generation database_revision payload =
  Protocol.Completed { query_generation; database_revision; payload }
;;

let failed query_generation error = Protocol.Failed { query_generation; error }

let response_of_result
      query_generation
      payload
      (result : (Protocol.mutation_result, Protocol.error) result)
  =
  match result with
  | Ok result ->
    completed query_generation result.Protocol.database_revision (payload result)
  | Error error -> failed query_generation error
;;

let service =
  Worker.Service.create
    ~push_topic_count:Protocol.Topic.count
    ~init:(fun ~emit path ->
      let startup_started_us = now_us () in
      match Store.open_ ~path with
      | Error error -> Error (Protocol.error_to_string error)
      | Ok store ->
        let sqlite_open_us = elapsed_us startup_started_us in
        emit
          ~topic:Protocol.Topic.ready
          (Protocol.Ready
             { schema_version = Store.schema_version store
             ; database_revision = Store.database_revision store
             ; sqlite_open_us
             });
        Ok
          { store
          ; snapshot_dirty = false
          ; startup_started_us
          ; sqlite_open_us
          ; startup_timing_pending = true
          })
    ~handle_request:(fun state ~cancelled:_ ~emit request ->
      match request.Protocol.operation with
      | Protocol.List_todos ->
        let list_started_us = now_us () in
        let result = Store.list_todos state.store in
        let initial_list_us = elapsed_us list_started_us in
        if state.startup_timing_pending
        then (
          state.startup_timing_pending <- false;
          emit
            ~topic:Protocol.Topic.startup_timing
            (Protocol.Startup_timing
               { sqlite_open_us = state.sqlite_open_us
               ; initial_list_us
               ; total_us = elapsed_us state.startup_started_us
               }));
        let response =
          match result with
          | Ok snapshot ->
            completed
              request.query_generation
              snapshot.database_revision
              (Protocol.Snapshot snapshot)
          | Error error -> failed request.query_generation error
        in
        Ok response, `Idle
      | Create_todo { mutation_id; title } ->
        let result = Store.create_todo state.store ~mutation_id ~title in
        (match result with
         | Ok { status = `Applied; _ } -> state.snapshot_dirty <- true
         | Ok { status = `Duplicate; _ } | Error _ -> ());
        ( Ok
            (response_of_result
               request.query_generation
               (fun value -> Protocol.Mutation value)
               result)
        , if state.snapshot_dirty then `Continue else `Idle )
      | Set_completed { mutation_id; todo_id; completed } ->
        let result = Store.set_completed state.store ~mutation_id ~todo_id ~completed in
        (match result with
         | Ok { status = `Applied; _ } -> state.snapshot_dirty <- true
         | Ok { status = `Duplicate; _ } | Error _ -> ());
        ( Ok
            (response_of_result
               request.query_generation
               (fun value -> Protocol.Mutation value)
               result)
        , if state.snapshot_dirty then `Continue else `Idle ))
    ~step:(fun state ~cancelled:_ ~emit ->
      if not state.snapshot_dirty
      then `Idle
      else (
        state.snapshot_dirty <- false;
        match Store.list_todos state.store with
        | Error error ->
          emit ~topic:Protocol.Topic.fatal (Protocol.Fatal error);
          `Idle
        | Ok snapshot ->
          let open_count, completed_count =
            List.fold_left
              (fun (open_count, completed_count) (todo : Protocol.todo) ->
                 if todo.completed
                 then open_count, completed_count + 1
                 else open_count + 1, completed_count)
              (0, 0)
              snapshot.todos
          in
          emit ~topic:Protocol.Topic.store (Protocol.Store_changed snapshot);
          emit
            ~topic:Protocol.Topic.summary
            (Protocol.Summary_changed
               { database_revision = snapshot.database_revision
               ; open_count
               ; completed_count
               });
          `Idle))
    ~cancel:(fun _state ~request_id:_ -> ())
    ~shutdown:(fun state -> Store.close state.store)
;;
