# Eio Worker Service Redesign

## Document status

| Field | Value |
| --- | --- |
| Date | 2026-08-04 |
| Status | Implemented; Phases 0-5 complete |
| Target | `bonsai_flutter.runtime` Worker Service and Worker Domain runtime |
| Current baseline | Direct-style Eio `Worker.Service` handlers with structural cancellation |
| Related documents | `docs/adr/0007-ocaml-worker-domain.md`, `docs/architecture.md`, `docs/lifecycle.md` |

## Executive summary

The Worker Service is built around one long-lived Eio event loop on
the existing singleton OCaml Worker Domain. Application code should use Eio's
direct style: synchronous operations such as SQLite calls execute normally,
while asynchronous Eio operations suspend only the current fiber.
Applications should not construct promises, call `Lwt_main.run`, implement a
manual `step` state machine, or spawn an OCaml Domain per request.

The redesign preserves the process topology, domain ownership, bounded
cross-domain mailboxes, response correlation, latest-wins pushes, and
domain-0 pump boundary accepted by ADR 0007. Eio replaces only the internal
Worker Service execution model.

The Worker Domain runs the Eio backend exactly once for its process lifetime:

```text
OCaml Worker Domain
  Eio_posix.run
    supervisor fiber
      idle or one attached session switch
        coordinator fiber
        zero or more request fibers and request switches
        zero or more application background fibers
        request-owned I/O child fibers and resources
        session-owned SQLite and file resources
```

Each attached worker session owns an Eio `Switch`. Each live dispatched request
owns a nested request `Switch`; a request cancelled before dispatch never needs
one. Request cancellation fails only the request switch when it exists, while
runtime destruction fails the complete session switch. Structured concurrency
therefore replaces application-defined cancellation callbacks and autonomous
`step` callbacks.

The default request policy is `Serial`. It keeps the current simple mutable
state and single SQLite connection model while still allowing an in-flight
Eio operation to suspend without blocking control, cancellation, timeout, or
shutdown processing. Services that are explicitly safe under fiber
interleaving may opt into bounded concurrent requests.

## Decision

Adopt Eio as the Worker Domain concurrency and I/O runtime with the following
normative choices:

1. Start one Eio backend loop when the process-wide Worker Domain starts, not
   once per session or request.
2. Use `Eio_posix.run` explicitly for the supported Apple native artifacts,
   behind an internal backend module that tests can replace.
3. Keep the existing non-blocking bounded request mailbox between domain 0 and
   the Worker Domain. Do not replace domain-0 enqueue with a potentially
   blocking `Eio.Stream.add` call.
4. Use an Eio condition as a wake-up signal after mailbox mutation. The waiter
   always rechecks mailbox and control state, so notifications are hints rather
   than data and cannot be lost semantically.
5. Execute every application handler in a request fiber with a request-owned
   `Switch`.
6. Make `Serial` the default concurrency policy and require an explicit,
   bounded `Concurrent` policy for interleaved handlers.
7. Use one session `Coordinator` fiber for control intake and request dispatch.
   It prioritizes Stop/Fatal, then Cancel, then a bounded batch of normal
   requests before yielding.
8. Remove the application-facing `step`, `cancel`, and `computation` concepts.
9. Replace autonomous steps with session-scoped background fibers.
10. Keep SQLite connections and statements on the Worker Domain. Short SQLite
   calls remain synchronous and must not be moved to a system thread.
11. Use Eio directly. Do not add a framework-specific `Task.t`, `Future.t`, or
    `await` abstraction over Eio.
12. Preserve exactly one terminal outcome for every accepted request and the
    existing domain-0 pump visibility boundary.
13. Give services an optional runtime-opened, directory-confined Eio
    filesystem capability rather than the process filesystem root.
14. Extend `examples/sqlite_worker` with bounded write and read operations
    that demonstrate file I/O, fiber suspension, progress, and cancellation.

## Version and platform baseline

The repository currently pins OCaml `5.1.1`. Eio `1.2` supports OCaml
`>= 5.1.0`, while the current Eio development documentation requires OCaml
`5.2.0` or later. The first implementation should therefore pin the Eio
package family to `1.2` rather than silently selecting a newer incompatible
release:

```text
eio       = 1.2
eio_posix = 1.2
```

`eio_main` is not required by the runtime design because the supported native
backend is selected explicitly. Avoiding `eio_main` also makes cross-compiled
backend selection independent of the host opam platform.

This compatibility pin is deliberate technical debt. A later coordinated
OCaml, Bonsai, and Eio upgrade should move the project to a supported current
Eio release. The Eio version must never float independently of the pinned
compiler and Jane Street package set.

The published `eio_posix` package describes support for most Unix-like
platforms, but does not explicitly promise iOS support. macOS and physical
iPhoneOS arm64 compatibility are therefore acceptance gates, not assumptions.
No production migration may complete until the platform spike defined below
passes.

## Goals

- Let synchronous application code remain ordinary direct-style OCaml.
- Let timers, sockets, files, and other Eio operations suspend a fiber without
  blocking the Worker Domain event loop.
- Keep Worker Service construction concise and remove manual progress state
  machines from normal application code.
- Make request and session cancellation structural and deterministic.
- Preserve exclusive Worker Domain ownership of SQLite and other native
  resources.
- Preserve the singleton runtime and Worker Domain topology.
- Preserve bounded request and response memory use.
- Preserve immutable cross-domain message requirements.
- Keep domain 0 and Bonsai free of Eio effects and worker-owned resources.
- Support deterministic unit tests with injected Eio capabilities and mock
  backends.
- Demonstrate real Eio file APIs and deterministic suspension behavior in the
  SQLite Worker example.
- Provide explicit concurrency and backpressure policies.
- Make shutdown close every request, child fiber, statement, connection, and
  session resource before the Worker Domain returns to `Idle`.

## Non-goals

- Running Eio on OCaml domain 0.
- Replacing the Dart runtime coordinator isolate or synchronous C ABI.
- Calling Dart, Flutter, Bonsai, or the Driver from the Worker Domain.
- Adding a native-to-Dart callback path for Worker I/O completion.
- Supporting multiple active logical runtimes or worker sessions.
- Creating a Domain, Eio event loop, or thread pool per request.
- Making SQLite itself asynchronous.
- Preempting an uninterruptible SQLite or C call.
- Exposing the complete Eio standard environment as application-global
  ambient state.
- Guaranteeing iOS background execution while the process is suspended.
- Automatically making arbitrary mutable service state safe under concurrent
  request interleaving.
- Hiding expected application errors behind exceptions.

## Removed service model

Before Phase 2, the service API required synchronous callbacks:

```ocaml
val create
  :  push_topic_count:int
  -> init:(... -> ('state, string) result)
  -> handle_request:
       ('state
        -> cancelled:(unit -> bool)
        -> emit:(... -> unit)
        -> 'request
        -> ('response, string) result * computation)
  -> step:(... -> computation)
  -> cancel:(... -> unit)
  -> shutdown:('state -> unit)
  -> service
```

This contract is suitable for short synchronous operations but makes genuine
asynchronous work awkward:

- `handle_request` must return a response immediately;
- `step` is a manual cooperative scheduler;
- an asynchronous request requires application-owned pending-job state;
- polling from `step` can busy-spin;
- the final result must be modeled as a push rather than the original request
  response;
- `cancelled` is only a predicate and cannot interrupt a suspended I/O
  operation; and
- every service must reproduce lifecycle and cleanup logic that Eio switches
  already provide.

Phase 2 deleted this API and its runtime implementation. There is no legacy
constructor, dual dispatch path, or compatibility adapter. All in-tree
services now construct the direct-style service described below.

## Preserved architecture invariants

The following ADR 0007 invariants remain normative:

- one embedded OCaml runtime;
- one OCaml UI domain 0;
- one process-wide OCaml Worker Domain;
- zero or one attached Worker Service session;
- one active logical `bf_runtime` and Driver;
- domain 0 never blocks while sending a normal request or draining output;
- the Worker Domain never executes Bonsai effects;
- mutable UI state and worker-owned native handles never cross Domains;
- accepted requests produce exactly one terminal outcome;
- stop and cancel controls bypass normal request backpressure;
- responses are reserved and never dropped;
- pushes remain bounded and latest-wins per topic;
- epochs, worker generations, request IDs, and push sequences retain their
  current fencing semantics;
- worker output becomes visible to Bonsai only at an accepted domain-0 pump;
  and
- ordinary runtime destroy removes a session but does not join the
  process-wide Worker Domain.

Eio fibers add concurrency within the Worker Domain. They do not add memory
isolation or another OCaml Domain.

## Runtime architecture

### Process-wide Worker Domain

The Worker Domain entrypoint starts the selected Eio backend exactly once:

```ocaml
let worker_entrypoint () =
  Worker_eio_backend.run (fun environment ->
    Worker_supervisor.run environment process_control)
;;
```

For Apple production builds, `Worker_eio_backend.run` delegates to
`Eio_posix.run`. Tests may supply a mock or deterministic backend. Application
code never calls `Eio_posix.run` or `Eio_main.run`.

The root Eio event loop remains alive across sequential worker sessions. The
process supervisor alternates between:

```text
Idle
  wait for Attach or Final_stop

Attached
  run exactly one session switch
  return to Idle after complete cleanup
```

Final runtime shutdown fails the process root scope, lets the backend loop
return, and joins the Worker Domain exactly once.

### Structured scope hierarchy

The Eio cancellation tree mirrors runtime ownership:

```text
supervisor fiber in the process scope
  |
  +-- session switch
        |
        +-- coordinator fiber
        +-- application background fibers
        +-- request fiber 1 in request switch 1
        |     +-- request-owned I/O child fibers
        |     +-- request-owned connections and timers
        +-- request fiber 2 in request switch 2
              +-- request-owned I/O child fibers
              +-- request-owned file flows
```

The scopes have these meanings:

| Scope | Created | Cancelled | Owns |
| --- | --- | --- | --- |
| Process | Worker Domain startup | Explicit final shutdown | Eio backend and supervisor |
| Session | Worker-backed runtime attach | Runtime destroy, replacement, startup failure, or terminal service failure | Service state, session resources, background fibers |
| Request | Accepted request dispatch | Request cancel, session cancel, timeout, or handler completion | Handler and request-scoped resources |

Application code may create child resources only under the `Switch` exposed
by its session or request context. Detached fibers are not part of the public
API.

### Fiber inventory and responsibilities

The implementation uses the following logical fibers. An Eio `Switch`,
semaphore, mailbox, SQLite connection, and Eio backend event loop are not
fibers.

| Fiber | Cardinality | Lifetime | Responsibility |
| --- | ---: | --- | --- |
| Supervisor | Exactly 1 per started Worker Domain | Process Worker Domain lifetime | Run the process state machine, attach one session, wait for complete cleanup, return to `Idle`, and exit on final shutdown |
| Coordinator | Exactly 1 per attached or initializing session | Session switch lifetime | Prioritize and drain session controls, consume the bounded request FIFO in bounded batches, maintain pending-request state, and fork Request fibers |
| Request | At most 1 per dispatched outstanding request | Coordinator dispatch through terminal outcome | Create and attach its request switch, wait for a concurrency permit, run `handle`, own request resources, and publish exactly one response |
| Background | Zero or a bounded application-defined number per session | Session switch lifetime | Run explicitly registered periodic or subscription work and emit pushes |
| I/O child | Zero or a bounded provider-defined number per request | Request switch lifetime | Implement request-owned streaming, timeout, and other I/O internals |

The Supervisor is the root fiber passed to `Eio_posix.run`; it need not be
created with `Eio.Fiber.fork`. While a session is attached, the same root fiber
runs the session coordinator and waits for its switch to finish. It never runs
an application request handler.

The Coordinator fiber is started before `init`. It owns two logical inputs: an
out-of-band control lane and the bounded normal-request FIFO. Before the
session becomes `Ready`, it processes session controls but does not dispatch
normal requests. After readiness, every loop iteration applies this priority:
Stop/Fatal, Cancel, then normal request dispatch. It rechecks control between
normal requests, limits each dispatch batch, and yields after a batch.

The Coordinator never calls `handle` inline and never acquires a handler
permit. For each live accepted request, it completes pending registration and
forks a Request fiber. Therefore a suspended handler does not block control
intake or dispatch, while a request burst cannot monopolize the Worker Domain.

A Request fiber enters `Eio.Switch.run`, atomically attaches the resulting
request switch to its outstanding-request record, and owns the complete
application handler call. Under `Serial`, multiple dispatched Request fibers
may exist, but only one holds the handler permit; the rest are suspended in
`Eio.Semaphore.acquire`. The total remains bounded by accepted-outstanding
response reservations. Under `Concurrent n`, at most `n` Request fibers hold
permits.

Background fibers are created only through `Session_context.fork_daemon` and
belong to the session switch. Detached application fibers are prohibited. An
unhandled Background fiber exception fails the session.

I/O child fibers are an implementation detail of the selected
provider. Every child must belong to its request switch, obey provider
connection limits, and unwind before the Request fiber publishes its terminal
outcome.

There is no dedicated SQLite fiber. A synchronous SQLite operation executes
inside the current Request fiber and occupies the Worker Domain until it
returns. There is also no dedicated response fiber: the Request fiber reserves
and publishes its own single response. Eio backend polling and timer queues are
scheduler facilities rather than application-visible fibers.

The logical fiber count is therefore:

```text
Idle Worker Domain:
  1 Supervisor

Attached session with no requests:
  1 Supervisor
  1 Coordinator
  0..B Background

Attached session with outstanding requests:
  the above
  + 0..N Request
  + 0..M bounded I/O children
```

### Cross-domain ingress and wake-up

The existing bounded request mailbox remains the source of truth for normal
requests. A separate out-of-band control lane remains the source of truth for
Cancel, Stop, replacement, and fatal control. These are logical lanes consumed
by the same Coordinator fiber; combining the consumer does not combine their
capacity or backpressure policy. Domain 0 performs a non-blocking response
reservation and request `try_push`; control publication never waits for request
capacity. After a successful state transition or enqueue, domain 0 calls
`Eio.Condition.broadcast` on the shared Worker Domain wake condition.

The outstanding-request registry contains only bounded coordination metadata
and an atomic terminal state; request payloads in cross-domain envelopes remain
immutable. A registry entry is created as part of response reservation before
the corresponding FIFO publication and is removed only after its reserved
terminal response is published.

The Coordinator uses a priority recheck loop conceptually equivalent to:

```ocaml
let await_next condition take_control take_request =
  Eio.Condition.loop_no_mutex condition (fun () ->
    match take_control () with
    | Some control -> Some (`Control control)
    | None ->
      (match take_request () with
       | Some request -> Some (`Request request)
       | None -> None))
;;
```

Each queue or atomic state contains the data. A condition only makes the Eio
scheduler runnable. A broadcast before a waiter sleeps is safe because the
Coordinator rechecks both lanes before waiting. Within the control lane it
handles Stop/Fatal before Cancel. It rechecks control after every normal
request dispatch, caps each normal dispatch batch, and then calls
`Eio.Fiber.yield`. Thus neither a request burst nor repeated normal wake-ups
can delay available control work. A synchronous SQLite call still occupies the
Worker Domain until it returns; an extra control fiber on the same Domain would
not change that limitation.

`Eio.Stream` is suitable inside the Worker Domain but is not the domain-0
request boundary. `Eio.Stream.add` waits when capacity is full, which would
violate the non-blocking domain-0 send contract. Internal fibers may use
bounded streams where suspension is acceptable.

### Session startup

Session attachment follows this order:

```text
reserve the singleton Worker Domain session slot
-> create the session switch
-> start the coordinator fiber in control-only mode
-> build a capability-limited session context
-> run application init in the session scope
-> on success, publish Ready
-> enable normal request dispatch
-> on failure, cancel the session scope and release all resources
```

The Coordinator starts before application initialization so Stop can cancel
initialization while it is waiting on Eio I/O. It rejects or leaves normal
requests undispatched until readiness according to the existing client
contract. A synchronous native call inside initialization remains
non-preemptible, matching the current runtime limitation.

`init` must not publish the service as ready before its durable migrations and
required resource construction have completed.

### Request dispatch

Each accepted request already has reserved response capacity and a bounded
outstanding-request record keyed by epoch, generation, and request ID. The
record exists before the request becomes visible in the normal FIFO, allowing
Cancel to win even before dispatch. The Coordinator then:

1. selects the accepted request after rechecking higher-priority controls;
2. if its record is already Cancelled or Shutdown, publishes that reserved
   terminal outcome without creating a Request fiber;
3. otherwise marks it dispatched with no request switch attached;
4. forks one Request fiber under the session switch;
5. enters `Eio.Switch.run` inside that Request fiber;
6. atomically attaches the resulting request switch to the pending record, or
   observes a Cancel or Shutdown that arrived before attachment;
7. acquires the service concurrency permit only if the request remains live;
8. runs `handle` in direct style while retaining the permit, including across
   Eio suspension points;
9. maps its returned result, cancellation, or exception to one terminal
   outcome;
10. releases the concurrency permit if it was acquired;
11. atomically claims the request's one terminal state;
12. publishes the corresponding reserved response; and
13. removes the request from the outstanding registry after publication.

The outstanding record plus two-stage switch attachment closes both early
cancellation races: Cancel may arrive before the Coordinator pops the request,
or after dispatch but before the Request fiber attaches its switch. In the
first case the Coordinator publishes `Cancelled` without forking. In the
second case it records the cause; switch attachment observes it and exits
without acquiring a permit or invoking `handle`. The registry cannot grow
beyond the already bounded accepted-outstanding response reservations.

The Coordinator remains runnable while a handler waits for Eio I/O, including
under `Serial`, because handlers run only in Request fibers.

### Concurrency policy

```ocaml
type concurrency =
  | Serial
  | Concurrent of
      { max_in_flight : int
      }
```

The runtime normalizes the policy to one session-owned Eio semaphore:

```ocaml
let handler_slots = function
  | Serial -> Eio.Semaphore.make 1
  | Concurrent { max_in_flight } ->
    if max_in_flight <= 0
    then invalid_arg "Worker concurrency must be positive";
    Eio.Semaphore.make max_in_flight
;;
```

Every Request fiber acquires a permit before `handle` and releases it with
`Fun.protect`:

```ocaml
let with_handler_permit semaphore run =
  Eio.Semaphore.acquire semaphore;
  Fun.protect
    ~finally:(fun () -> Eio.Semaphore.release semaphore)
    run
;;
```

`Serial` therefore means exactly one application handler holds the permit.
The permit intentionally remains held while that handler is suspended on
socket I/O, file I/O, a timer, or another Eio operation. Later Request fibers wait
in `Eio.Semaphore.acquire`; they do not enter application code or observe
partially updated service state.

The Supervisor, Coordinator, Background, and provider-internal fibers do not
acquire the handler semaphore. They remain runnable while the single handler
is suspended. `Serial` serializes application request handlers, not the Eio
event loop or Worker Domain control plane.

`Concurrent` permits at most `max_in_flight` active request handlers. The
request mailbox capacity still bounds accepted queued work. The runtime must
reject zero or negative limits during service construction.

Concurrent handlers execute on the same OCaml Domain and therefore do not
have simultaneous CPU access to service state. They can nevertheless
interleave whenever either handler performs an Eio effect. Application state
invariants must account for that reentrancy.

The initial public release should document `Concurrent` as an advanced mode.
SQLite-backed examples use `Serial`.

Cancellation while waiting for the semaphore prevents the handler from
starting. Cancellation while suspended in Eio I/O unwinds the handler and
releases its permit. Cancellation during synchronous SQLite is recorded but
cannot run until SQLite returns; the Request fiber then releases the permit
and the terminal-state arbitration prevents a normal result from overwriting
the cancellation.

## Application API

The following signatures describe the implemented public API through Phase 3.

```ocaml
type mono_clock = Eio.Time.Mono.ty Eio.Resource.t
type net = [ `Generic ] Eio.Net.ty Eio.Resource.t
type data_dir = Eio.Fs.dir_ty Eio.Path.t

module Session_context : sig
  type 'push t

  val switch : 'push t -> Eio.Switch.t
  val clock : 'push t -> mono_clock
  val net : 'push t -> net
  val data_dir : 'push t -> data_dir option

  val emit
    :  'push t
    -> topic:Bonsai_flutter_spec.Id.Worker.push_topic
    -> 'push
    -> unit

  val fork_daemon
    :  'push t
    -> name:string
    -> (unit -> unit)
    -> unit
end

module Request_context : sig
  type 'push t

  val request_id
    :  'push t
    -> Bonsai_flutter_spec.Id.Worker.request_id

  val switch : 'push t -> Eio.Switch.t
  val clock : 'push t -> mono_clock
  val net : 'push t -> net
  val data_dir : 'push t -> data_dir option

  val emit
    :  'push t
    -> topic:Bonsai_flutter_spec.Id.Worker.push_topic
    -> 'push
    -> unit
end

module Service : sig
  type concurrency =
    | Serial
    | Concurrent of
        { max_in_flight : int
        }

  type ('config, 'request, 'response, 'push) t

  val create
    :  push_topic_count:int
    -> concurrency:concurrency
    -> ?data_directory:('config -> (string, string) result)
    -> init:
         ('push Session_context.t
          -> 'config
          -> ('state, string) result)
    -> handle:
         ('push Request_context.t
          -> 'state
          -> 'request
          -> ('response, string) result)
    -> shutdown:('state -> unit)
    -> unit
    -> ('config, 'request, 'response, 'push) t
end
```

The service keeps a string error at the infrastructure boundary for
compatibility with existing terminal diagnostics. Application protocols
should continue to represent expected business errors with typed variants in
their response payloads. An `Error string` returned by `handle` is a failed
request whose service state remains valid. An unexpected exception means the
service may be inconsistent and terminates the complete session.

No public `computation`, `step`, `cancel`, `Task`, `Future`, or `await` type is
required.

### Why the context exposes capabilities

Eio resources are capability values. A service should receive only what its
runtime supports and tests can replace:

- the request or session `Switch` for resource lifetime;
- a monotonic clock for sleep and timeout;
- a network capability for Eio-native clients;
- an optional directory-confined filesystem capability; and
- an emit capability for typed push output.

The public context does not expose filesystem root access. If
`data_directory` is provided, the trusted runtime evaluates it against the
immutable startup configuration, validates the returned absolute path, opens
that one directory under the session switch, and exposes only the resulting
directory capability. Relative Eio paths built from that capability cannot
escape to parent directories. SQLite may continue to receive its absolute
database path separately because its binding does not consume an Eio path.

The Eio domain manager and executor pool must not be exposed. Application code
remains prohibited from creating additional Domains.

## Application programming model

### Synchronous SQLite request

SQLite remains ordinary synchronous code:

```ocaml
let handle _context state = function
  | List_todos ->
    Store.list_todos state.store
    |> Result.map (fun snapshot -> Protocol.Snapshot snapshot)
  | request -> handle_non_query state request
;;
```

The call occupies the Worker Domain until SQLite returns. This is acceptable
only for bounded statements and transactions. It does not block Flutter or
domain 0.

### Background work

The current autonomous `step` callback is replaced by a session-scoped daemon:

```ocaml
let init context path =
  match Store.open_ ~path with
  | Error error -> Error (Protocol.error_to_string error)
  | Ok store ->
    let state = { store } in
    Worker.Session_context.fork_daemon
      context
      ~name:"remote-refresh"
      (fun () ->
        let clock = Worker.Session_context.clock context in
        while true do
          Eio.Time.Mono.sleep clock 60.0;
          refresh_and_emit context state
        done);
    Ok state
;;
```

The daemon is attached to the session switch and is cancelled before
`shutdown` runs. An unhandled daemon exception terminates the session because
the consistency of shared service state can no longer be assumed.

For a one-off action following a mutation, emitting from the request handler
is simpler than spawning a daemon.

### SQLite Worker file I/O demonstration

`examples/sqlite_worker` includes a small, explicitly educational file
transfer panel. It demonstrates that one request can perform direct-style Eio
file operations, report progress, suspend cooperatively, and be cancelled
without adding a manual `step` state machine.

The demo adds these request operations:

```ocaml
type operation =
  | List_todos
  | Create_todo of create_todo
  | Set_completed of set_completed
  | Write_demo_file of
      { total_bytes : int
      }
  | Read_demo_file
```

The generated file is not application data and is never used by SQLite:

```text
<Application Support>/sqlite_worker/eio-worker-demo.bin
```

The write operation uses a temporary file in the same directory and renames
it only after the complete payload is written:

```text
eio-worker-demo.<request-id>.tmp
  -> eio-worker-demo.bin
```

Cancellation or failure removes the temporary file. The previously completed
demo file, if any, remains intact. The demo does not claim crash-durable export
semantics and does not alter Todo database revisions.

The Flutter bootstrap passes both the database path and the absolute
`sqlite_worker` Application Support directory in the versioned startup
payload. The `SWC1` payload contains a 12-byte header followed by two
length-prefixed UTF-8 paths. The OCaml decoder rejects malformed, relative,
empty, or NUL-containing paths before service startup. Service construction
requests a confined directory capability:

```ocaml
let service =
  Worker.Service.create
    ~push_topic_count:Protocol.Topic.count
    ~concurrency:Worker.Service.Serial
    ~data_directory:(fun config -> Ok config.application_support_directory)
    ~init
    ~handle
    ~shutdown
;;
```

The runtime opens that directory once under the session switch.
`Request_context.data_dir` returns the same confined capability to request
fibers. The service builds only relative child paths from it.

The file implementation belongs in a separate application module rather than
the SQLite store:

```ocaml
module File_demo : sig
  type progress =
    { completed_bytes : int
    ; total_bytes : int
    }

  type read_result =
    { total_bytes : int
    ; checksum : int64
    }

  val write
    :  sw:Eio.Switch.t
    -> directory:Worker.data_dir
    -> request_id:Bonsai_flutter_spec.Id.Worker.request_id
    -> total_bytes:int
    -> progress:(progress -> unit)
    -> (unit, string) result

  val read
    :  sw:Eio.Switch.t
    -> directory:Worker.data_dir
    -> progress:(progress -> unit)
    -> (read_result, string) result
end
```

The implementation uses `Eio.Path.with_open_out`,
`Eio.Path.with_open_in`, and bounded chunked `Eio.Flow` operations. Normative
demo limits are:

| Limit | Value |
| --- | ---: |
| Default generated size | 4 MiB |
| Maximum generated or accepted size | 16 MiB |
| Chunk size | 64 KiB |
| Simultaneous file operations | 1 under the default `Serial` service |
| Progress topic retention | One latest-wins value |

The write pattern is deterministic, allowing the read operation to compute a
small rolling checksum without introducing another native dependency. Every
read validates the maximum file size before allocation and while streaming;
it never loads an unbounded file into one string.

Regular-file operations may complete immediately when the OS and page cache
are ready. Therefore, merely calling `Eio.Path.load` or `Eio.Path.save` does
not prove that another fiber ran. The example intentionally performs chunked
I/O and calls `Eio.Fiber.yield ()` after each completed chunk:

```ocaml
let rec write_chunks sink ~remaining ~progress =
  if remaining > 0
  then (
    let length = Int.min chunk_size remaining in
    Eio.Flow.write sink [ make_chunk length ];
    progress length;
    Eio.Fiber.yield ();
    write_chunks sink ~remaining:(remaining - length) ~progress)
;;
```

The explicit yield is teaching instrumentation. It guarantees observable
cooperative suspension without adding artificial wall-clock delay. Production
file code should yield only when fairness requires it; it should not copy this
instrumentation blindly.

Tests must additionally use a mock source and sink that suspend on controlled
read and write points. That proves cancellation and continuation behavior
without relying on filesystem speed, cache state, or file size.

The protocol adds one latest-wins progress push and typed responses:

```ocaml
type file_operation =
  | Writing
  | Reading

type file_push =
  | File_progress of
      { operation : file_operation
      ; completed_bytes : int
      ; total_bytes : int
      }

type file_response =
  | File_written of
      { total_bytes : int
      }
  | File_read of
      { total_bytes : int
      ; checksum : int64
      }
```

These constructors are incorporated into the example's existing closed push
and response payload variants; they do not require extensible variants.

The UI panel contains:

- `Write 4 MiB demo file`;
- `Read demo file`;
- `Cancel file operation`, enabled only while its request ID is pending;
- a determinate progress indicator;
- completed byte count and checksum; and
- the latest completed, cancelled, or failed status.

Cancel uses the existing out-of-band `Worker.cancel` path. While the file
fiber is suspended or has yielded, the Coordinator processes cancellation
and fails the request switch. The application receives the ordinary typed
`Cancelled` outcome; it does not invent a separate file cancellation
protocol.

The demo remains `Serial` so its SQLite state and teaching code stay simple.
Normal requests submitted during the transfer remain queued, while Cancel,
Stop, progress coalescing, timers, and session control continue to run. A
later example may demonstrate `Concurrent`, but concurrency is not required
to prove Eio suspension.

## State and resource ownership

### Session state

`init` constructs service state on the Worker Domain. The state remains owned
by that Domain until `shutdown` completes. It must never be captured by a
domain-0 closure or included in a cross-domain message.

Under `Serial`, request handlers cannot interleave with each other. Background
session fibers can still interleave at Eio suspension points and must either:

- avoid mutable request-owned state;
- communicate through an application-owned bounded Eio stream; or
- use an Eio mutex around a documented invariant.

Under `Concurrent`, every shared mutable invariant requires the same explicit
discipline.

### SQLite

A SQLite connection, its statements, and transactions stay on the Worker
Domain. They must not be passed to `Eio_unix.run_in_systhread`, an executor
pool, another Domain, or a callback invoked by a foreign thread.

`Serial` services may use one connection directly. A `Concurrent` service that
shares one connection must serialize complete database operations with a
service-owned gate and must never suspend while a transaction holds that gate.
The first implementation should not provide an automatic SQLite pool.

### Other blocking calls

Eio can run an audited blocking operation in a system thread, but that is an
escape hatch rather than the default Worker API. Such an operation is allowed
only when:

- the binding is safe on a registered system thread;
- it owns no Worker-Domain-affine OCaml or native handle;
- its input and output ownership is explicit;
- cancellation behavior is documented; and
- concurrency is bounded.

The public Worker context should not initially expose a generic
`run_in_systhread` helper.

## Cancellation and timeout semantics

### Request cancellation

Domain 0 cancellation identifies a pending request by epoch, generation, and
request ID. The Coordinator locates the bounded outstanding-request record. If
the request has not been dispatched, it records cancellation so later dispatch
publishes `Cancelled` without creating a Request fiber. If the request has
been dispatched and its switch is attached, the Coordinator fails that switch
with an internal cancellation exception. If the Request fiber has not attached
its switch yet, the Coordinator records the cause in the request record; later
attachment observes it and prevents the handler from starting.

If the handler is suspended in an Eio operation, cancellation becomes visible
at that suspension point and request-owned resources unwind through their
switch. If the handler is inside a synchronous SQLite or C call, cancellation
waits until the call returns. The runtime checks the terminal state before
publishing a normal result, so a late successful return cannot overwrite an
already accepted cancellation.

The request state machine is:

```text
Accepted -> Dispatched -> Waiting_for_permit -> Running -> Completing -> Completed
   |            |                |             |            |
   +------------+----------------+-------------+------------+-> Cancelled
   +------------+----------------+-------------+------------+-> Shutdown
                +----------------+-------------+------------+-> Failed
```

Exactly one terminal transition wins atomically.

### Timeouts

Timeouts are implemented with the monotonic Eio clock and request child
scopes. The infrastructure should distinguish:

- application-defined I/O timeout, represented as a typed business error;
- optional service request deadline, represented as a failed request; and
- runtime shutdown cancellation, represented as `Shutdown`.

A timeout must never be derived from Flutter frame timestamps or wall-clock
time.

### Session stop

Normal runtime destruction performs:

```text
reject new requests
-> mark mailbox-queued and permit-waiting requests Shutdown
-> fail the session switch
-> cancel running requests and background fibers
-> wait for structured children to unwind
-> run shutdown once in a protected cleanup region
-> close worker-owned resources
-> publish terminal outcomes already reserved
-> detach the session
-> return the Worker Domain supervisor to Idle
```

`shutdown` may perform short synchronous cleanup such as finalizing statements
and closing SQLite. It must not start durable background work. If cleanup is
stuck in an uninterruptible native call, the backend remains `Destroying`, as
it does today.

## Failure policy

| Failure | Outcome |
| --- | --- |
| `init` returns `Error` | Typed startup failure; cancel partial session resources; return Worker Domain to `Idle` |
| `handle` returns `Error` | Failed request; service remains attached |
| Request switch cancelled | `Cancelled` or `Shutdown`, according to controlling cause |
| Unhandled handler exception | Fail the session, cancel siblings, run shutdown, publish terminal service event |
| Unhandled background fiber exception | Fail the session, cancel requests, run shutdown, publish terminal service event |
| `shutdown` exception | Append cleanup diagnostic and terminate the session |
| Eio backend or supervisor invariant failure | Worker Domain subsystem becomes `Terminal` |
| Bounded response invariant failure | Worker Domain subsystem becomes `Terminal` |

Expected database, validation, and domain errors belong in typed
application responses. Exceptions are reserved for violated invariants,
unexpected library failures, and Eio cancellation.

## Response and push semantics

Eio does not change the client-visible protocol:

- `Worker.send` remains a non-blocking domain-0 enqueue;
- an accepted request still reserves one response slot;
- completion order may differ from request order under `Concurrent`;
- request ID correlation remains mandatory;
- every accepted request gets one of `Completed`, `Failed`, `Cancelled`, or
  `Shutdown`;
- push topics remain bounded and latest-wins;
- push sequence remains monotonic within a worker generation; and
- domain 0 drains a bounded output snapshot only during a valid pump.

`Session_context.emit` and `Request_context.emit` may be called only from
fibers belonging to the attached Worker Domain session. An external C callback
or system thread must resolve an Eio promise or enqueue an internal completion;
it must not call application emit code directly.

## Observability

The Worker diagnostics retain existing lifecycle counters and now expose the
following Phase 3 runtime measurements:

- logical live fiber count for the backend Supervisor, Coordinator, Request,
  and Background fibers;
- Supervisor and Coordinator liveness;
- queued and active request counts;
- Request fibers waiting for a handler permit;
- configured concurrency limit;
- request queue wait sample count and maximum duration;
- handler wall sample count and maximum duration;
- cancellation-to-unwind sample count and maximum duration;
- active background fiber count;
- session cancellation duration;
- shutdown duration; and
- Eio backend identity and pinned version.

Eio `1.2` does not expose scheduler runnable time or per-fiber CPU time through
its public API. The runtime therefore reports logical live fibers and wall
durations without presenting either as runnable CPU duration.

Tracing must not serialize application payloads or SQL parameters. Request IDs,
operation categories, durations, and bounded byte counts are sufficient.

## Testing strategy

### Pure service tests

Run direct-style service code under an Eio mock backend with injected clock and
resources. Prove:

- synchronous handlers return normally;
- an Eio wait suspends the request fiber;
- cancellation unwinds request-owned resources;
- timeout uses the monotonic clock;
- background fibers end with the session switch;
- expected errors do not terminate the session;
- unexpected exceptions do terminate the session; and
- no resource survives its owning switch.

### Runtime contract tests

Adapt the existing Worker runtime suites to prove:

- one Worker Domain and one Eio backend loop across sequential sessions;
- one Supervisor fiber and one Coordinator fiber have the documented lifetimes
  without duplicate session infrastructure;
- the Supervisor and Coordinator never invoke application handlers;
- the Coordinator processes Stop/Fatal before Cancel and Cancel before normal
  request dispatch;
- bounded dispatch batches and explicit yields prevent request intake from
  starving other runnable fibers;
- `Serial` never overlaps application handlers;
- a `Serial` handler retains its sole semaphore permit while suspended;
- later Request fibers wait without entering application code;
- `Concurrent n` never exceeds `n` active handlers;
- the Coordinator cancels a suspended handler promptly;
- cancellation before FIFO dispatch publishes `Cancelled` without creating a
  Request fiber;
- cancellation between dispatch and switch attachment prevents the handler
  from starting;
- cancelling a Request fiber waiting for a permit prevents its handler from
  starting and does not over-release the semaphore;
- Cancel and Stop bypass a full request queue;
- every accepted request receives exactly one terminal outcome;
- response reservation and push coalescing remain bounded;
- request/completion races do not double-publish;
- normal destroy returns to `Idle` without joining;
- final shutdown joins once; and
- an unrecoverable backend failure leaves the subsystem `Terminal`.

### SQLite tests

Preserve existing store tests and add Worker-level tests for:

- SQLite calls execute on the Worker Domain;
- one connection never crosses to a system thread;
- a cancelled request completing a SQLite call cannot publish success;
- short transactions complete before another `Serial` handler starts;
- stop closes the database before the next session opens it.

### File I/O tests

Test `File_demo` with a temporary confined directory and Eio mock flows. Prove:

- writing uses bounded 64 KiB chunks;
- progress is monotonic and never exceeds the declared total;
- a successful write atomically replaces the final demo file;
- cancellation removes only the request's temporary file;
- cancellation preserves an older completed demo file;
- reading is bounded to 16 MiB even if the file changes while being read;
- the deterministic payload produces the expected checksum;
- mock read and write suspension allows the Coordinator to run;
- cancelling at every chunk boundary produces one `Cancelled` outcome;
- Stop closes open flows and returns the session to `Idle`; and
- a late completion from an old request or generation cannot publish progress
  or a response.

### Flutter and pump tests

Existing Flutter tests must continue to prove that Worker output is invisible
until a later accepted pump. Worker completion must not call Flutter, schedule
a frame directly, or mutate Bonsai state from the Worker Domain.

## Apple platform feasibility gate

Before changing the public Worker API, build a minimal isolated spike that
proves all of the following:

1. Eio `1.2` and `eio_posix` `1.2` compile with the repository's OCaml `5.1.1`
   toolchains.
2. `Eio_posix.run` starts successfully from the spawned OCaml Worker Domain,
   not only from the process main thread.
3. A domain-0 bounded mailbox enqueue plus Eio condition broadcast wakes the
   Worker Domain without polling or busy-spin.
4. The Worker Domain becomes idle without consuming CPU when no request,
   timer, or I/O event is pending.
5. The complete native object links into macOS arm64 and physical iPhoneOS
   arm64 artifacts.
6. A timer, socketpair, confined directory open, chunked file read/write,
   atomic rename, DNS lookup, and TCP request complete on macOS.
7. The same bounded operations complete on a signed physical iPhone.
8. Request cancellation closes a waiting socket and returns the session to a
   usable state.
9. Suspend and resume do not corrupt the Eio backend, session switches, or
   Worker generation fencing.
10. Eio does not spawn unbounded Domains or system threads.
11. Final shutdown returns from the Eio backend and joins the Worker Domain
    exactly once.

Failure of items 1 through 5 blocks this design.

## Migration plan

### Phase 0: dependency and platform spike

- Pin and build Eio `1.2` and `eio_posix` `1.2` with OCaml `5.1.1`.
  **Complete.**
- Implement only the minimum backend entrypoint and wake-up bridge.
  **Complete.**
- Complete macOS and physical iPhoneOS feasibility tests. **Complete.**
- Record dependency size, native symbols, system threads, idle CPU, and binary
  size impact. **Complete.**

The public Worker Service cutover began only after this phase passed.

### Phase 1: Eio supervisor behind the current client contract

- Add the process root backend loop. **Complete.**
- Preserve current bounded request, response, and push mailboxes. **Complete.**
- Add one session Coordinator with separate control and request lanes, control
  priority, and bounded request-dispatch batches. **Complete.**
- Implement attach, idle, stop, terminal, and final shutdown transitions.
  **Complete.**
- Re-run all singleton and lifecycle tests before introducing application
  fibers. **Complete.**

### Phase 2: request switches and direct-style handlers

- Introduce session and request contexts. **Complete.**
- Add `Serial` dispatch first. **Complete.**
- Map Cancel and Stop to Eio switch cancellation. **Complete.**
- Preserve exactly-once response reservation and publication. **Complete.**
- Replace callback exceptions with the failure policy in this document.
  **Complete.**
- Delete the old `computation`, `step`, application cancellation callback, and
  synchronous handler implementation without a compatibility path.
  **Complete.**

### Phase 3: background fibers and bounded concurrency

- Replace `step` with session-scoped daemon support. **Complete.**
- Add `Concurrent { max_in_flight }` and its semaphore. **Complete.**
- Add metrics and race tests. **Complete.**
- Keep `Serial` as the documented default. **Complete.**

### Phase 4: application migration

- Migrate `examples/sqlite_worker` to the new direct-style API. **Complete.**
- Keep SQLite operations synchronous and transactions short. **Complete.**
- Add the bounded `File_demo` module, confined Application Support directory,
  progress push, cancellation path, and Flutter demonstration panel.
  **Complete.**
- Prove file read and write suspension with controlled mock flows rather than
  relying on physical filesystem latency. **Complete.**
### Phase 5: documentation cleanup

- Update ADR 0007's Worker Service contract while preserving its topology and
  communication decisions. **Complete.**
- Update `docs/architecture.md`, `docs/lifecycle.md`, `docs/testing.md`, and the
  SQLite Worker example README. **Complete.**
- Document the Eio version pin and future compiler-upgrade requirement.
  **Complete.**
- Confirm no temporary migration modules or dual-path tests remain.
  **Complete.**

The old service
record, `computation`, `step`, application cancellation callback, legacy
runner, and compatibility-only test were deleted in Phase 2. Phase 5 did not
reintroduce a legacy constructor, adapter, or dual dispatch path.

## Expected file impact

| Area | Expected change |
| --- | --- |
| `bonsai_flutter.opam`, `bonsai_flutter_test.opam`, and `dune-project` | Pin compatible Eio packages after the platform spike |
| `ocaml/runtime/dune` and `ocaml/test/dune` | Link the Eio runtime and mock test libraries after explicit build approval |
| `ocaml/runtime/worker.ml` and `.mli` | Replace callback stepping with contexts, direct-style handlers, structured cancellation, and concurrency policy |
| `ocaml/runtime/worker_runtime.ml` and `.mli` | Run one Eio backend loop and manage process/session scopes |
| `ocaml/runtime/bounded_mailbox.ml` and `.mli` | Preserve queues; add an Eio-compatible wake notification if needed |
| `ocaml/runtime/app.ml` and `.mli` | Accept the redesigned service type without changing domain-0 component ownership |
| `ocaml/test/worker_runtime_tests.ml` | Replace step fairness tests with fiber, cancellation, and concurrency tests |
| `ocaml/test/native_backend_worker_tests.ml` | Preserve singleton lifecycle and replacement coverage under Eio |
| `examples/sqlite_worker/ocaml/sqlite_worker_service.ml` | Use direct-style init, request handling, file progress emit, and shutdown |
| `examples/sqlite_worker/ocaml/sqlite_worker_file_demo.ml` and `.mli` | Implement bounded, cancellable Eio file read and write operations |
| `examples/sqlite_worker/ocaml/sqlite_worker_protocol.ml` and `.mli` | Add file requests, responses, and latest-wins progress payloads |
| `examples/sqlite_worker/ocaml/sqlite_worker_store.ml` | Keep synchronous SQLite implementation; add no Eio dependency |
| `examples/sqlite_worker/flutter/lib/application_support_bootstrap.dart` | Pass the confined data-directory path alongside the SQLite path |
| `examples/sqlite_worker/flutter/lib/main.dart` | Add write, read, cancel, progress, byte-count, and checksum UI |
| Apple build tooling | Stage Eio native dependencies into complete objects |

No `.mli` file under `spec/` needs to change unless later protocol work finds
a missing identifier or contract. No renderer wire-format change is required.

## Acceptance criteria

The redesign is complete only when:

- application code performs synchronous SQLite and direct-style Eio file I/O
  without a manual state machine;
- the SQLite Worker example performs real bounded Eio file reads and writes,
  exposes progress, and cancels an operation without a manual state machine;
- file operations use only the runtime-opened Application Support directory
  capability and leave no temporary file after cancellation;
- the Worker Domain starts one Eio backend loop per process;
- sequential worker sessions reuse that loop and Domain;
- `Serial` preserves non-overlapping handler semantics;
- a suspended Eio operation does not delay Cancel or Stop processing;
- no request or session resource survives its Eio switch;
- all accepted requests produce exactly one terminal outcome;
- bounded mailbox, response reservation, push coalescing, fencing, and pump
  semantics remain unchanged;
- SQLite connections never leave the Worker Domain;
- idle Worker CPU remains effectively zero;
- macOS and signed physical iPhoneOS cancellation, suspend/resume, and
  cleanup tests pass;
- existing UI-only applications remain unaffected; and
- all Worker, native backend, SQLite, Flutter, packaging, and lifecycle suites
  pass.

All criteria above are complete and covered by the focused runtime, file, and
platform tests listed in this document.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Eio `1.2` is older than the current release | Pin explicitly, use versioned APIs, and plan a coordinated OCaml/Bonsai/Eio upgrade |
| `eio_posix` is not validated on iPhoneOS | Make physical-device compile, link, DNS, cancellation, and resume tests a blocking Phase 0 gate |
| A synchronous native call blocks every Worker fiber | Keep such calls bounded; use Eio-native I/O; audit any system-thread escape hatch |
| Concurrent handlers interleave mutable state | Default to `Serial`; require explicit bounded opt-in and resource gates |
| Cross-domain wake-up loses a notification | Store data in bounded mailbox/atomic state and use a condition recheck loop |
| Cancellation races with completion | Use one atomic terminal state and one pre-reserved response slot |
| Background fibers leak | Attach every child to the session switch; expose no detached spawn API |
| Cached regular-file I/O never visibly suspends | Use chunked operations plus an explicit teaching yield; use controlled suspending mock flows in tests |
| File cancellation corrupts an older completed artifact | Write a request-specific temporary file and rename only after complete success |
| Eio backend creates unexpected threads or Domains | Instrument topology and make bounded thread/domain counts an acceptance gate |

## Rejected alternatives

| Alternative | Reason rejected |
| --- | --- |
| Use separate Control and Ingress/dispatcher fibers | Both consume small, bounded units on the same Domain; one priority Coordinator preserves control responsiveness with less wake-up coordination and pending-state synchronization |
| Wrap every operation in a framework `Task.t` | Eio already supplies the scheduler, suspension, switches, promises, and direct style; another task layer adds no ownership value |
| Base the new runtime on Lwt | It requires monadic service signatures or an additional effect bridge and does not meet the direct-style goal as cleanly |
| Call `Lwt_main.run` or `Eio_main.run` inside each handler | Nested or per-request loops break shared scheduling, cancellation, and lifecycle ownership |
| Keep `step` and poll asynchronous work | Polling is verbose, can busy-spin, and forces final results into push protocols |
| Run one Domain per request | It violates the singleton topology and complicates SQLite ownership and cleanup |
| Move SQLite calls to `run_in_systhread` | It moves a Worker-owned native handle across its ownership boundary and does not make the SQLite transaction model safer |
| Run Eio on domain 0 | Network and business work would share the Bonsai and FFI authority domain and weaken UI isolation |
| Replace the bounded request mailbox with blocking `Eio.Stream.add` | Domain 0 must never block or suspend while enqueueing a normal request |
| Start a new Eio backend for every session | The process-wide Worker Domain is reused; one root loop gives stable wake-up, timer, and shutdown ownership |
| Use unbounded concurrent request fibers | It removes backpressure and permits unbounded memory, socket, and response retention |

## References

- [ADR 0007: Singleton OCaml UI and worker runtime](../adr/0007-ocaml-worker-domain.md)
- [Eio project overview and direct-style model](https://github.com/ocaml-multicore/eio)
- [Eio 1.2 package and OCaml compatibility](https://opam.ocaml.org/packages/eio/eio.1.2/)
- [Eio POSIX 1.2 package](https://opam.ocaml.org/packages/eio_posix/eio_posix.1.2/)
- [Eio fibers, cancellation, and switches](https://github.com/ocaml-multicore/eio#readme)
- [Eio Stream API and cross-domain behavior](https://ocaml-multicore.github.io/eio/eio/Eio/Stream/index.html)
- [Eio Condition API](https://ocaml-multicore.github.io/eio/eio/Eio/Condition/index.html)
- [Eio Mutex API](https://ocaml-multicore.github.io/eio/eio/Eio/Mutex/index.html)
- [Eio Path file API](https://ocaml-multicore.github.io/eio/eio/Eio/Path/index.html)
- [Eio fiber scheduling API](https://ocaml-multicore.github.io/eio/eio/Eio/Fiber/index.html)
