# Lifecycle

Flutter presentation is the commit point for Bonsai after-display lifecycle
effects. Decoding bytes or committing a `NodeStore` transaction is not
equivalent to presentation.

## Singleton startup and replacement

Domain 0 serializes runtime ownership through
`Empty | Creating | Active | Destroying | Finalized`. A versioned startup
envelope selects `Fresh` or `Replace_existing`. `Fresh` rejects an occupied
slot before allocating a Driver or attaching a worker session. Explicit
replacement completes this sequence synchronously:

```text
Active(old) -> Destroying(old) -> Empty -> Creating(new) -> Active(new)
```

The old worker session closes its resources and is removed before its Driver
is shut down and before any replacement Driver or session exists. Its handle
is tombstoned, so stale pump, presentation, destroy, and buffer-release calls
cannot address the replacement. The UI-isolate coordinator lease is acquired
before `Isolate.spawn` and is released only by its matching startup failure,
isolate exit, or completed disposal.

## Foreground pump loop

`BonsaiFlutterRoot` owns a recursive
`SchedulerBinding.scheduleFrameCallback` loop. While Flutter is `resumed` or
`inactive` and `framesEnabled` is true, each callback registers one successor
and grants at most one logical pump to the dedicated runtime isolate. A
visually idle foreground runtime therefore continues pumping.

The loop stops for `hidden`, `paused`, `detached`, or independent loss of
`framesEnabled`. It uses no periodic timer, forced frame, native callback
thread, busy loop, or background fallback. Resume starts a new scheduler
generation and catches up elapsed work on later foreground frames.

```text
Flutter UI isolate       Dart runtime isolate          OCaml runtime
        |                         |                         |
        | VsyncGranted(generation)                         |
        |------------------------>|                         |
        |                         | pump(now_ns, events)    |
        |                         |------------------------>|
        |                         |<------------------------|
        |<------------------------| CycleReady(token)       |
        | validate + prepare + commit                       |
        | build/layout/paint                                |
        | post-frame success(generation, token, revision)   |
        |------------------------>|                         |
        |                         | presentation_succeeded  |
        |                         |------------------------>|
        |                         |   commit + lifecycle    |
        |                         |<------------------------|
```

The runtime worker serializes all native calls. While a presentation is
unresolved, later frame grants coalesce to one pending grant. Visibility loss
invalidates queued grants but retains the unresolved presentation token.

## Logical pump

One accepted pump performs this order:

1. Validate the nonnegative, nondecreasing monotonic sample.
2. Decode and validate the complete input batch without input-derived
   mutation.
3. Advance the retained public Bonsai time source.
4. Apply a valid environment update, host responses, and UI events atomically,
   or drop the complete invalid batch as a recoverable error.
5. Flush Bonsai, including due clock alarms and before-display work, to the
   required fixed point.
6. Reconcile against the last successfully presented mounted tree.
7. Prepare the handler frame and host-operation prefix without committing
   either.
8. Reserve one positive, non-reusable presentation ID.
9. If renderer state changed, reserve a new renderer revision and encode one
   full snapshot or incremental frame.
10. Retain the complete candidate behind the presentation barrier.

For a worker-backed application, validated Flutter input precedes a bounded
snapshot of worker responses and coalesced pushes. Stale epoch, worker
generation, request, push sequence, query generation, and database revision
messages are rejected. Accepted worker events become domain-0 Bonsai effects;
the complete effect queue is then drained before the single Bonsai flush and
single reconcile. Output arriving after the snapshot waits for a later pump.
Normal pumps never block on the Worker Domain.

Every successful logical pump produces a presentation token, including a
no-diff pump and a recoverable dropped-input pump. Renderer revision advances
only when bytes are emitted. No second pump is accepted before the exact
outstanding token is resolved.

## Presentation success

The token is `(presentation_id, renderer_revision)`. The Flutter root applies
frame bytes with a two-phase `NodeStore.prepare` and `commit` transaction,
starts host dispatch only after live renderer commit, and sends success from a
guarded post-frame callback after a real Flutter frame.

On exact success, OCaml validates a fresh monotonic sample, commits the
candidate tree, handler frame, and prepared host-operation prefix, advances
time without flushing, marks the revision displayed, and triggers lifecycle
work exactly once. The next granted pump flushes actions scheduled by
activation or after-display.

The displayed handler frame and its immediate predecessor remain available
for events created across one Flutter rebuild boundary. A replaced handler
can resolve only against the source revision captured by its old callback.

## Presentation rejection

Decode failure, frame validation failure, renderer epoch mismatch, and
renderer revision mismatch reject the exact unresolved token before live
commit. Rejection runs no lifecycle, preserves the prior mounted and handler
state, leaves prepared host operations queued, burns any issued renderer
revision, and forces the next wire frame to be a full snapshot.

A failure after live renderer commit or after host dispatch starts is
terminal. It must not be reported as a recoverable rejection because the
candidate may already be externally visible.

## Timers and observed time

The worker owns one `Stopwatch` and samples checked elapsed nanoseconds
immediately before each native pump and accepted presentation success.
Flutter frame timestamps and wall-clock time are not clock authority.

OCaml maps elapsed nanoseconds onto the retained `Bonsai.Time_source`.
`Bonsai.Clock.at`, `every`, `sleep`, `until`, `approx_now`,
`get_current_time`, `Bonsai.Clock.Expert.now`, and the corresponding public
time-source operations advance during foreground logical pumps without
external input. The [`Clock` example](../examples/clock/README.md) presents
their distinct reactive, sampled, one-shot, recurring, and frame-boundary
semantics in one OCaml-owned application.

There is no deadline query or timer registry at the native boundary.
Background suspension performs no logical pumping and promises no background
timer execution. On resume, an unresolved token is presented first; relative
timers created by its after-display work start at that acknowledgment time,
and later foreground pumps catch up older overdue work.

## Shutdown

Shutdown is serialized with normal commands and is idempotent. It rejects new
commands, closes the update stream once, destroys the native runtime once,
invalidates Bonsai observers, clears runtime state, and lets Flutter dispose
renderer resources.

The selected public `Bonsai_driver` has no dedicated destroy operation.
`Bonsai_driver.Expert.invalidate_observers` remains isolated in
`Bonsai_runtime_adapter` as the release mechanism.

Destroying a worker-backed runtime first tombstones its lease and rejects new
requests, then completes pending requests as shutdown and sends out-of-band
Stop. The Worker Domain fails the session Eio switch, structurally cancels
request and background fibers, waits for switch-owned Eio resources to unwind,
finalizes SQLite statements, closes the connection, removes the session, and
returns to `Idle`. Only then does domain 0 shut down the Driver
and clear the singleton slot. Ordinary destroy and replacement never call
`Domain.join`; later sessions reuse the same Worker Domain and process-wide
Eio backend loop.

Controlled tests and embedders may invoke final runtime shutdown. It destroys
an active runtime if necessary, moves the backend slot to the absorbing
`Finalized` state, and joins a successfully spawned Worker Domain exactly
once. Shutdown from `Not_started` joins zero Domains, repeated final shutdown
is idempotent, and every later create fails.

## Widget-test contract

A mounted foreground root intentionally keeps scheduling frames, so
`pumpAndSettle` is not a valid completion primitive. Widget and FFI tests use
bounded frame counts or predicate-based helpers with explicit timeouts and
diagnostic snapshots. Real-isolate timer tests alternate a bounded wall-clock
delay in `tester.runAsync` with one `tester.pump()`.
