# Foreground Vsync Pump Implementation Plan

Goal: Make Bonsai timers, observed time, lifecycle transitions, and after-display actions advance without external Flutter input while changing no upstream source.
Architecture: Flutter owns a recursive foreground `scheduleFrameCallback` loop, the Dart worker isolate serializes frame grants and native calls, and the OCaml Driver advances its retained `Bonsai.Time_source` before every logical pump.
Every successful pump issues an independent presentation token, including no-diff pumps, and the next real Flutter frame acknowledges that token before the Driver runs lifecycle work.
Tech Stack: OCaml 5.3.0, Jane Street Bonsai `v0.18~preview.130.106+341`, Core `Time_ns`, C11 FFI ABI v2, Dart 3.12.2 isolates and `Stopwatch`, Flutter 3.44.8 scheduler APIs, Dune, ffigen, and Flutter widget and integration tests.
Related: Supersedes `/Users/rcmerci/gh-repos/bonsai_flutter/docs/agent-guide/004-autonomous-runtime-pump.md` and extends `/Users/rcmerci/gh-repos/bonsai_flutter/docs/architecture.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/docs/lifecycle.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/docs/ffi.md`, and `/Users/rcmerci/gh-repos/bonsai_flutter/docs/adr/0002-runtime-boundary.md`.

## Problem statement

The current runtime advances only when Flutter starts it, submits an input batch, or acknowledges a renderer revision.
`Driver.step` flushes Bonsai without advancing its time source, and `Driver.frame_presented` triggers lifecycle work without automatically performing the next flush.
Consequently, a timer can remain dormant forever while the user supplies no input, and an after-display action can wait for an unrelated later event before producing another revision.


The previous plan attempted to stop all idle pumping by obtaining an exact next deadline and complete pending-work state from upstream Bonsai.
That design requires APIs which are not exposed by the pinned upstream revisions and is disallowed by the new requirement that upstream source must remain unchanged.


The replacement design uses the same fundamental trade-off as `bonsai_web`.
It advances the complete Bonsai runtime on every eligible display cycle instead of trying to infer whether opaque upstream work exists.
This preserves full timer, lifecycle, before-display, after-display, and observed-clock semantics through existing public APIs.


The trade-off is structural rather than an implementation detail.
Without upstream deadline and observability APIs, complete semantics and zero foreground idle pumping cannot both be provided.
This plan therefore replaces the old no-60-Hz-polling acceptance with an explicit foreground-vsync contract.

## Document status

Research is complete against the pinned Bonsai, Bonsai Concrete, Bonsai Web, Incr_dom, Flutter, and Dart revisions recorded by this repository as of 2026-07-29.
Implementation is complete as of 2026-07-29.
Phase 1 and the complete Phase 2 RED suite were completed on 2026-07-29.
All implementation tasks in this plan use repository-local code and existing public upstream APIs.


`/Users/rcmerci/gh-repos/bonsai_flutter/docs/agent-guide/004-autonomous-runtime-pump.md` is superseded and must not be implemented.

### GREEN completion evidence

- `make ci-contract`, `make ci-ocaml`, `make ci-flutter`, and
  `make ci-sanitizers` pass.
- `make ci-macos` passes all complete-object audits, Counter Debug/Profile/
  Release builds, and the nine-test real FFI integration suite.
- `make ci-ios` passes the iPhoneOS runtime closure, nine complete-object
  audits, and Counter Debug/Profile/Release unsigned bundle audits.
- `git diff --check` passes, generated protocol and FFI bindings are
  reproducible, and the final forbidden-source scan has no match.
- No upstream source, overlay, dependency constraint, lockfile, or pinned
  revision changed.

### Preserved RED evidence

- `dune runtest ocaml/test` fails on the intentionally absent
  `Driver.pump_result`, presentation transaction, and token-bearing result
  fields.
- `make integration-native-object` and `make ci-sanitizers` fail on the
  intentionally absent ABI 2.0 symbols, presentation fields, rejection
  reasons, and monotonic-time errors.
- The native Dart suite fails on the intentionally absent exact ABI-version
  facade and presentation-aware native methods.
- The worker suite fails because `runtime_protocol.dart`,
  `runtime_worker.dart`, typed commands, the token barrier, and monotonic
  conversion do not exist.
- The frame-loop and root suites fail because the scheduler loop, prepared
  event/store transactions, ordered runtime session, and presented-revision
  state do not exist.
- The real FFI acceptance fails before execution because the ABI 2.0 object
  and ordered `RuntimeClient.debugSnapshot` surface do not exist. Once those
  lower boundaries are GREEN, this suite remains the behavior-level RED gate
  for autonomous Phase 1 and Phase 2 progress.
- `make ci-contract` and `git diff --check` pass against the preimplementation
  production tree.

## Non-negotiable constraints

- Do not modify, overlay, fork, vendor, or monkey-patch upstream Bonsai, Bonsai Concrete, Incremental, Incr_dom, or Flutter source.
- Do not use `Obj.magic`, upstream record-field access, `Bonsai.Time_source.Private`, a shadow timer registry, or partial timer emulation.
- Preserve complete behavior for public Bonsai timers, observed clock values, before-display work, lifecycle deltas, persistent after-display effects, and `wait_after_display`.
- Use a foreground Flutter frame loop based on `SchedulerBinding.scheduleFrameCallback`.
- Do not use `Timer.periodic`, a fixed 16 millisecond timer, a busy loop, `Ticker.forceFrames`, `scheduleForcedFrame`, `scheduleWarmUpFrame`, or a native callback thread.
- Stop requesting logical pumps while Flutter frames are disabled and do not add a background timer fallback.
- Keep every OCaml FFI call on the dedicated runtime isolate.
- Permit at most one issued but unresolved presentation token.
- Introduce a hard native ABI v2 boundary with exact version checks and no compatibility shim for the existing `step` ABI.
- Keep the renderer binary protocol at version 1.12 unless implementation evidence proves that a wire-frame schema change is unavoidable.

## Decision record

### Compatibility equation

```text
No upstream changes
+ complete Bonsai timer, lifecycle, and observed-now semantics
= continuous foreground vsync pump

No upstream changes
+ no continuous foreground pump
= restricted Bonsai semantics

Complete semantics
+ zero foreground idle pump
= new upstream deadline and pending-work APIs
```


The first equation is selected.
The other two outcomes violate explicit requirements and are not fallback modes.

### Replacement acceptance

The old statement that a quiescent runtime performs no fixed-rate native calls is removed.
The new scheduling acceptance is the following contract.

- There is no fixed-period Dart timer, native timer, or busy polling loop.
- The pump follows actual Flutter frames and therefore follows device and operating-system cadence such as 60, 90, or 120 Hz.
- At most one Bonsai pump is consumed per eligible Flutter frame grant.
- Presentation backpressure prevents concurrent pumps and prevents more than one unresolved presentation.
- After the worker processes an ineligible generation for `hidden`, `paused`, or `detached`, it starts no new runtime pump.
- A native pump already executing when visibility changes may finish and leave one unresolved token for resume.
- A callback canceled after it requested an engine frame may leave one empty Flutter frame, but generation checks must make that frame perform zero runtime calls.
- A foreground runtime whose UI is visually unchanged still performs logical pumps and presentation acknowledgments.

### Why this is not a literal `bonsai_web` port

The implementation copies the semantic ordering and continuous-frame principle, not the browser runtime.

| Concern | `bonsai_web` | `bonsai_flutter` decision |
| --- | --- | --- |
| Frame source | Browser `requestAnimationFrame` | Flutter `scheduleFrameCallback` |
| Driver location | JavaScript main thread | Dedicated Dart runtime isolate and native OCaml runtime |
| Patch target | DOM | Revisioned Flutter `NodeStore` |
| Display boundary | DOM patch followed by `on_display` | Matching Flutter post-frame callback |
| Empty visual diff | Still completes the logical frame | Issues a lightweight `presentation_id` without a wire frame |
| Backpressure | Browser callback serialization | Explicit one-presentation barrier across isolates |
| Background fallback | Incr_dom races RAF with a one-second timeout | No fallback because mobile background execution is not reliable |
| Clock input | Browser or wall-clock sample | Worker-owned monotonic elapsed time mapped onto the Bonsai time origin |

## Research findings

### Current repository behavior

| Layer | Current file | Finding |
| --- | --- | --- |
| Bonsai adapter | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/bonsai_runtime_adapter.ml` | Wraps public Driver operations but does not retain or advance the supplied time source. |
| OCaml Driver | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/driver.ml` | Flushes only on explicit commands and creates no presentation boundary when both UI patch and host operations are empty. |
| Handler registry | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/handler_registry.ml` | Uses renderer revision for handler lookup and cannot identify multiple no-diff presentation cycles. |
| Native backend | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ffi/native_backend.ml` | Always returns `next_wakeup_ns = -1L`. |
| C ABI | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.h` | Has protocol version functions but no independent ABI version or presentation identifier. |
| Runtime client | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_client.dart` | Implements request-response `step` and `framePresented` commands only. |
| Flutter root | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/root/bonsai_flutter_root.dart` | Pumps on startup and external input, and registers a post-frame callback without independently requesting a frame. |
| Event revision | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/event_batch_queue.dart` | Reads the applied `NodeStore.revision` rather than the last revision actually presented. |
| Lifecycle documentation | `/Users/rcmerci/gh-repos/bonsai_flutter/docs/lifecycle.md` | Describes a one-shot `next_wakeup_ns` timer which is not implemented. |


The reserved `next_wakeup_ns` field already crosses OCaml, C, generated Dart bindings, and the runtime client.
It carries no semantic information and must be removed rather than repurposed as an inaccurate deadline.

### Pinned `bonsai_web` behavior

The public `Bonsai_web.Start` entry point defaults to `Start_via_incr_dom`.
The matching Incr_dom frame loop runs an update and schedules the next `requestAnimationFrame` without consulting dirty state or a pending-work query.


The default path samples time, advances clocks, stabilizes, applies actions, recursively executes before-display work, patches the DOM, and then runs display lifecycle work.
The experimental `Bonsai_driver` path likewise advances clocks on every frame, calls `Bonsai_driver.flush`, reads and patches the result, and calls `Bonsai_driver.trigger_lifecycles`.


This establishes two relevant facts.

- `bonsai_web` does not infer idleness from `has_after_display_events`.
- Complete Bonsai web behavior is intentionally frame-driven while the page can receive frames.

### Public upstream API sufficiency

The pinned upstream exposes all operations required by a continuous-frame design.

```ocaml
Bonsai.Time_source.now
Bonsai.Time_source.advance_clock
Bonsai_driver.flush
Bonsai_driver.result
Bonsai_driver.schedule_event
Bonsai_driver.trigger_lifecycles
Bonsai_driver.Expert.invalidate_observers
```


`Bonsai.Time_source.advance_clock` requests advancement but does not itself execute alarms.
`Bonsai_driver.flush` performs the private time-source flush internally, stabilizes the graph, drains actions, and reaches the lifecycle collection's before-display fixed point.
Time-source `wait_before_display` callbacks are triggered later in the same flush, but an action from that stage which creates new lifecycle before-display work is observed by the next pump.
The repository must call the public advance operation followed by the public Driver flush and must not duplicate internal recursion.


`Bonsai_driver.trigger_lifecycles` compares lifecycle collections, updates the displayed lifecycle baseline, and schedules deactivation, activation, after-display, and time-source after-display work.
It does not flush the scheduled actions.
The next logical pump must therefore follow every successful presentation acknowledgment.

### Why upstream pending-work queries are unnecessary

The pinned `has_after_display_events` value is not a complete lifecycle presentation predicate.
It does not independently reveal a pure activation, a pure deactivation, a future-only `on_deactivate` registration, or replacement of same-path lifecycle callbacks.


The pinned time source also does not expose one exact public deadline spanning all Incremental alarms, effect-wheel alarms, and staged alarms.
An observed `Clock.Expert.now` can require a new value on every logical frame without owning any deadline.


The new design never asks either incomplete question.
Every successful pump receives one later real presentation boundary, and every eligible frame advances and flushes the entire upstream Driver.

### Timer and observed-time coverage

Continuous public advance-and-flush covers the following families without a local timer model.

- `Bonsai.Clock.at`
- `Bonsai.Clock.approx_now`
- `Bonsai.Clock.every`
- `Bonsai.Clock.sleep`
- `Bonsai.Clock.until`
- `Bonsai.Clock.Expert.now`
- `Bonsai.Time_source.sleep`
- `Bonsai.Time_source.until`
- Timers staged from before-display and after-display effects


A timer fires on the first logical pump whose mapped time is at or after its deadline.
Its granularity is the available foreground display cadence, and it never requires an external input batch.

### Flutter scheduler behavior

`scheduleFrameCallback` registers a one-shot transient callback and requests a new frame by default.
Its `rescheduling: true` argument does not make it periodic and only preserves useful debug-stack information for a callback which registers its successor.


The callback must explicitly register the next callback.
It must do so from the current callback so the new registration belongs to a later frame.


`addPostFrameCallback` runs after persistent rendering callbacks, does not request a frame, cannot be canceled, and runs once.
The root must register it from the begin-frame callback only when the target presentation was already decoded and applied before that begin frame.
Registering it immediately when an asynchronous runtime result arrives could attach it to a frame which never built that result.


`resumed` and `inactive` keep ordinary frames enabled.
`hidden`, `paused`, and `detached` disable ordinary frames on the supported mobile lifecycle path.
The implementation must also consult `SchedulerBinding.framesEnabled` because lifecycle notifications can be skipped.


`cancelFrameCallbackWithId` removes the transient callback but cannot retract an engine frame already requested.
Every transient and post-frame closure therefore needs an exact cycle identity and generation guard.

## Architecture

### End-to-end topology

```text
Flutter UI isolate
  ForegroundFrameLoop
    scheduleFrameCallback
      |
      | VsyncGrant(generation)
      v
Dart runtime isolate
  RuntimeWorker
    one serialized native call at a time
      |
      | monotonic_elapsed_ns + optional input batch
      v
C ABI v2
  bf_runtime_pump
      |
      v
OCaml Driver
  advance_clock
  flush
  reconcile
  issue presentation_id
      |
      | CycleReady(presentation_id, revision, optional bytes)
      v
Flutter UI isolate
  decode and apply optional wire frame
  next begin-frame arms a matching post-frame callback
  build, layout, paint
      |
      | PresentationSucceeded or PresentationRejected
      v
OCaml Driver
  validate exact token
  commit or discard candidate
  advance_clock without flush on success
  trigger_lifecycles on success only
      |
      v
next granted pump
```

### Definition of pump

A pump is one OCaml transaction which consumes at most one validated input batch, advances the Bonsai logical clock, flushes the upstream Driver, reads its current result, reconciles against the last successfully presented renderer state, and issues exactly one presentation token.


A pump is not a Flutter `pump`, a native busy loop, or a fixed-period timer.
The foreground scheduler grants at most one logical pump opportunity per Flutter frame.

### Presentation identity and renderer revision

`presentation_id` and renderer revision serve different purposes and must never be conflated.

| Value | Meaning | Advancement rule |
| --- | --- | --- |
| `presentation_id` | Exactly-once lifecycle and display transaction identity | Advances after every successful OCaml pump. |
| Renderer revision | Version of the last emitted wire-frame state | Advances only when the pump emits a protocol frame. |
| `lastPresentedRevision` | Revision safe for new renderer events | Advances synchronously in the matching post-frame callback. |
| `NodeStore.revision` | Most recently applied local renderer state | May advance before presentation. |


A no-diff pump returns a new `presentation_id`, the existing renderer revision, and no bytes.
Flutter still waits for a later real frame and acknowledges the presentation token.
The Driver then triggers lifecycle work without incrementing renderer revision or installing a redundant handler frame.


A host-operation-only output remains a normal wire frame under protocol 1.12 and therefore advances renderer revision.
This decision avoids splitting the existing wire envelope and keeps host-operation ordering unchanged.

### Driver state ownership

The OCaml Driver becomes authoritative for the following state.

```ocaml
type pending_presentation =
  { presentation_id : int64
  ; renderer_revision : int64
  ; candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; emitted_frame : frame option
  }

type t =
  { time_source : Bonsai.Time_source.t
  ; logical_time_origin : Core.Time_ns.t
  ; mutable last_monotonic_ns : int64
  ; mutable next_presentation_id : int64
  ; mutable next_renderer_revision : int64
  ; mutable pending_presentation : pending_presentation option
  ; mutable displayed_tree : Runtime.Mounted_tree.t option
  ; mutable displayed_revision : int64
  ; mutable force_full_snapshot_next : bool
  ; ...
  }
```


The exact handler-frame type can remain private to the reconciliation layer.
The important invariant is that a candidate is not treated as presented until its exact token succeeds.

### Logical clock mapping

The runtime isolate starts one `Stopwatch` immediately after `NativeRuntime.create` succeeds.
It samples elapsed time from that same clock domain immediately before every native pump and every successful-presentation native call.
The UI-isolate presentation command carries no timestamp; the worker owns and adds the authoritative sample.


The Flutter callback `Duration` is not the runtime clock authority because Flutter frame timestamps can be adjusted by scheduler epochs and `timeDilation`.
The callback parameter remains useful for diagnostics only.


The Driver records `Bonsai.Time_source.now time_source` as `logical_time_origin`.
It maps the nonnegative runtime-relative nanosecond value onto that origin.

```ocaml
let logical_time t monotonic_now_ns =
  let span =
    monotonic_now_ns
    |> Int63.of_int64_exn
    |> Time_ns.Span.of_int63_ns
  in
  Time_ns.add t.logical_time_origin span
```


The Driver rejects a negative, decreasing, or unrepresentable elapsed value before mutating the time source, input queues, lifecycle baseline, handler registry, or mounted tree.
The origin plus elapsed span must also be checked for overflow.

### Pump transaction

`Driver.pump` replaces the public `Driver.step` operation.

```ocaml
type pump_result =
  { presentation_id : int64
  ; renderer_revision : int64
  ; frame : frame option
  ; recoverable_error : error option
  }

val pump
  :  t
  -> monotonic_now_ns:int64
  -> ?events:Bonsai_flutter_protocol.Inbound_event.batch
  -> unit
  -> (pump_result, error) result
```


The operation performs the following ordered steps.

1. Reject shutdown, an existing unresolved presentation, or an invalid clock value before mutation.
2. Validate the complete optional input batch and retain one recoverable diagnostic if the complete batch must be dropped.
3. Map and request `Bonsai.Time_source.advance_clock`.
4. Execute the fully validated input batch in wire order, or execute no input when validation failed.
5. Drain UI-handler effects into the upstream Driver.
6. Call `Bonsai_driver.flush` exactly once.
7. Read the current Bonsai result.
8. Reconcile against the last successfully presented mounted tree.
9. Prepare the current host-operation prefix without removing it from the host-effect manager.
10. Encode a full or incremental wire frame only when UI operations or prepared host operations exist.
11. Reserve a non-reusable renderer revision only when a wire frame is emitted.
12. Reserve a non-reusable `presentation_id` for every successful logical pump.
13. Store one candidate presentation and its prepared host-operation prefix without marking either presented.
14. Return the token, authoritative renderer revision, optional bytes, and optional recoverable input diagnostic.


The operation must not use `has_before_display_events` or `has_after_display_events` as a scheduling gate.
`Bonsai_driver.flush` already reaches the lifecycle collection's before-display fixed point and performs the pinned one-pass time-source before-display stage.

### Successful presentation

```ocaml
val presentation_succeeded
  :  t
  -> presentation_id:int64
  -> renderer_revision:int64
  -> monotonic_now_ns:int64
  -> (unit, error) result
```


The operation performs the following ordered steps.

1. Validate shutdown state, exact `presentation_id`, exact renderer revision, and the mapped monotonic value before any mutation.
2. Commit the exact prepared host-operation prefix so it cannot be emitted again.
3. Commit candidate mounted-tree metadata.
4. Install and mark the candidate handler frame through the existing registry API only when a wire frame was emitted.
5. Promote the displayed renderer revision only when a wire frame was emitted.
6. Retire superseded handler frames after the new handler frame is marked.
7. Request `Bonsai.Time_source.advance_clock` to the successful presentation time and update `last_monotonic_ns`, but do not flush or stabilize.
8. Clear the one-presentation barrier.
9. Call `Bonsai_driver.trigger_lifecycles` exactly once.
10. Record lifecycle timing and return to the ready state.


The acknowledgment-time advance is required when a token remains unresolved across suspension.
`Bonsai.Time_source.now` observes the pending public `advance_clock` target, so an after-display effect which creates a relative timer uses the actual successful-presentation time instead of the earlier pump time.
The acknowledgment must not call `Bonsai_driver.flush` or otherwise execute alarms.
The subsequent pump takes a fresh worker-clock sample, advances and flushes time, applies lifecycle-injected actions, catches up timers which expired while suspended, and leaves newly created relative timers pending until their presentation-relative deadlines.


If lifecycle execution raises, the runtime becomes terminal.
Upstream lifecycle baseline and effects may already be partially committed and cannot be rolled back safely.
Any error after `commit_operations` succeeds, or after candidate or handler state begins committing, is likewise fatal.
It must not enter the presentation-rejection path or replay the prepared host-operation prefix.

### Rejected presentation

```ocaml
type rejection_reason =
  | Decode_failed
  | Frame_validation_failed
  | Renderer_epoch_mismatch
  | Renderer_revision_mismatch

val presentation_rejected
  :  t
  -> presentation_id:int64
  -> renderer_revision:int64
  -> reason:rejection_reason
  -> (unit, error) result
```


The operation validates the exact unresolved token before mutation.
It does not trigger lifecycle work and does not promote the candidate tree or handler frame.
It clears the barrier, discards the candidate, leaves its prepared host-operation prefix queued in original order, burns any issued renderer revision, and forces the next emitted wire frame to be a full snapshot.
Flutter may invoke rejection only before live renderer commit and before any candidate host operation is dispatched.
Any failure after either boundary is terminal and cannot request replay.


The Bonsai model itself is not rolled back because `flush` has already advanced it.
The next full snapshot reconciles the current model against a fresh renderer base, re-emits the retained host operations, and its successful presentation becomes the lifecycle boundary.

### No-diff safety invariant

The current reconciler reuses a handler identifier only when the handler object has the same physical identity.
A changed handler identity produces `Update_event_bindings`, so an empty frame patch implies that renderer-visible handler bindings have not changed.


The implementation must encode this as a test rather than rely on an undocumented assumption.
When the complete wire operation list is empty, the candidate mounted-tree metadata may be promoted on token acknowledgment without installing a new handler frame or advancing renderer revision.

### Input atomicity

The new pump barrier makes partial input mutation especially dangerous.
The Driver must validate runtime epoch, event sequence, displayed revision, handler existence, payload tag, host-response shape, environment payload, and resync shape for the complete batch before it invokes a handler or resolves a host request.


The local validation and execution split may require changes in the following files.

- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/event_dispatcher.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/event_dispatcher.mli`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/host_effect.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/host_effect.mli`


A validation failure is recoverable, drops the complete batch, performs no input-derived mutation, and still lets the same logical pump advance time and issue a presentation token.
This rule prevents malformed or stale input from starving timers and lifecycle progress.
An exception after validated execution starts is fatal because action and host-effect execution cannot be rolled back.


`Host_effect.Private.take_operations` must be replaced by a local two-phase API equivalent to the following shape.

```ocaml
module Prepared_operations : sig
  type t

  val operations
    :  t
    -> Bonsai_flutter_protocol.Wire_frame.operation list
end

val prepare_operations : t -> Prepared_operations.t
val commit_operations : t -> Prepared_operations.t -> (unit, string) result
```


Preparation snapshots the current ordered prefix without removing it.
Successful presentation commits exactly that prefix.
Rejection or pre-candidate failure leaves the prefix available for the next pump, and shutdown clears it with the rest of the host-effect manager.

## Native ABI v2

### Version boundary

The C library must expose an ABI version independently from the renderer protocol version.

```c
#define BF_ABI_MAJOR 2
#define BF_ABI_MINOR 0

BF_EXPORT uint16_t bf_abi_version_major(void);
BF_EXPORT uint16_t bf_abi_version_minor(void);
BF_EXPORT uint16_t bf_protocol_version_major(void);
BF_EXPORT uint16_t bf_protocol_version_minor(void);
```


The Dart package must resolve and require ABI `2.0` before creating a runtime.
A missing symbol or any major or minor mismatch is a fatal native-library-loading error.
There is no lookup fallback to the ABI v1 symbols.

### Output shape

```c
typedef struct bf_output_buffer {
  const uint8_t *data;
  size_t length;
  uint64_t presentation_id;
  uint64_t revision;
  bf_status status;
  bf_error_code error_code;
} bf_output_buffer;
```


`next_wakeup_ns` is deleted from C, the OCaml callback tuple, the bridge response, generated bindings, `NativeOutput`, and `RuntimeResponse`.
A successful logical pump always returns a positive `presentation_id`.
An `OK` pump and a `RECOVERABLE_ERROR` pump with a dropped input batch both carry an authoritative presentation token and optional frame bytes.
Only a fatal result or a presentation command carries no new token.
Its data pointer may be null only when length is zero.
The C bridge must copy and validate payload fields for both token-bearing statuses instead of discarding every non-`OK` response as the current bridge does.

### Runtime operations

```c
BF_EXPORT bf_status bf_runtime_pump(
    bf_runtime *runtime,
    int64_t monotonic_now_ns,
    const uint8_t *input,
    size_t input_length,
    bf_output_buffer *output);

BF_EXPORT bf_status bf_runtime_presentation_succeeded(
    bf_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bf_output_buffer *output);

BF_EXPORT bf_status bf_runtime_presentation_rejected(
    bf_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bf_output_buffer *output);
```


`bf_runtime_step` and `bf_runtime_frame_presented` are removed from the export list.
The existing create, error-buffer, output-buffer, outstanding-allocation, and destroy ownership rules remain unchanged.


Presentation success and rejection return an empty output buffer on success.
The runtime worker performs the next granted `bf_runtime_pump` as a separate serialized call.
This separation lets a visibility transition invalidate a pending grant without suppressing acknowledgment of a frame which actually completed.

### OCaml callback names

```text
bonsai_flutter.create
bonsai_flutter.pump
bonsai_flutter.presentation_succeeded
bonsai_flutter.presentation_rejected
bonsai_flutter.destroy
```


The bridge must resolve all callbacks once during initialization and fail runtime creation if any callback is absent.
No OCaml heap value may survive a callback.

### Error additions

ABI v2 must add stable error codes for invalid presentation identity, invalid monotonic time, and invalid scheduler state.
Old, duplicate, future, or unsolicited presentation acknowledgments return before lifecycle mutation.
The Dart coordinator treats such framework-internal protocol errors as terminal even if the C status is recoverable for diagnostic tests.

## Dart runtime isolate

### Files and responsibilities

Add `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_protocol.dart`.
This file owns typed isolate commands and updates without importing Flutter scheduler classes.


Add `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_worker.dart`.
This file owns the worker state machine, monotonic clock abstraction, grant coalescing, native call serialization, and terminal cleanup.


Refactor `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_client.dart`.
This file owns isolate startup, typed public session methods, stream delivery, `onError` and `onExit`, transferable-byte ownership, and exact-once disposal.

### Isolate protocol

The concrete names may follow repository style, but the protocol must represent the following values.

```dart
sealed class RuntimeCommand {}

final class VsyncGranted extends RuntimeCommand {
  VsyncGranted(this.generation);
  final int generation;
}

final class VisibilityChanged extends RuntimeCommand {
  VisibilityChanged({required this.generation, required this.eligible});
  final int generation;
  final bool eligible;
}

final class PresentationSucceeded extends RuntimeCommand {
  PresentationSucceeded({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.events,
  });
  final int generation;
  final int presentationId;
  final int revision;
  final TransferableTypedData events;
}

final class PresentationRejected extends RuntimeCommand {
  PresentationRejected({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.reason,
  });
  final int generation;
  final int presentationId;
  final int revision;
  final PresentationRejectionReason reason;
}

sealed class RuntimeUpdate {}

final class CycleReady extends RuntimeUpdate {
  CycleReady({
    required this.presentationId,
    required this.revision,
    required this.bytes,
    required this.recoverableDiagnostic,
  });
  final int presentationId;
  final int revision;
  final TransferableTypedData bytes;
  final RuntimeDiagnostic? recoverableDiagnostic;
}
```


Recoverable diagnostics, fatal diagnostics, startup readiness, and disposal completion must also be represented explicitly.
Sequence numbers remain useful for diagnostics but must not substitute for presentation identity.

### Worker state machine

```text
Booting
  create native runtime
  start Stopwatch
  -> Ready

Ready
  eligible grant
    -> Pumping
       native pump
       drop any fully invalid input without blocking clock progress
       -> AwaitingPresentation(token)

AwaitingPresentation(token)
  more eligible grants
    -> keep one pending grant, zero native pump calls

  exact success for current live eligible generation
    -> sample Stopwatch
       native presentation_succeeded
       -> Ready
       -> consume one pending grant if still eligible

  exact rejection for current live eligible generation
    -> native presentation_rejected
       -> Ready
       -> consume one pending grant if still eligible

Any live state
  hidden, paused, or detached
    -> invalidate stored grants
       retain unresolved presentation
       allow an already-started synchronous pump to finish
       start no pump after the ineligible command is processed

Any state
  fatal error, worker exit, or dispose
    -> Terminal
```


The worker must never call `bf_runtime_pump` while a presentation is unresolved.
Multiple grants behind the barrier coalesce to one boolean and the latest live generation.
The worker accepts a presentation result only when its generation equals the current live eligible generation and its token and renderer revision match the unresolved presentation.
The accepted generation deliberately does not have to equal the generation under which the token was issued: a retained token issued before suspension is presented by the new eligible generation after resume.
An old-generation success or rejection is a protocol error and reaches no native call.
Input remains on the UI `EventBatchQueue` until the matching post-frame command, so the native pump receives one ordered encoded batch after presentation.
Every grant, visibility transition, presentation result, and disposal command for one session must use the same UI-to-worker `SendPort` so begin-frame grant order is preserved before the matching post-frame result.
Every worker update and debug response must likewise use one worker-to-UI `SendPort`, so a debug barrier cannot overtake the `CycleReady` produced by an earlier in-flight call.


The worker samples its `Stopwatch` immediately before each native pump and immediately before each accepted successful-presentation call.
It takes a new sample again when a coalesced grant is consumed after acknowledgment and never reuses the begin-frame callback timestamp or the acknowledgment sample.
Tests inject a fake clock, but production has no wall-clock or test-binding branch.

```dart
int readMonotonicNanoseconds(Stopwatch stopwatch) {
  const maxInt64 = 0x7fffffffffffffff;
  final microseconds = stopwatch.elapsedMicroseconds;
  if (microseconds < 0 || microseconds > maxInt64 ~/ 1000) {
    throw StateError('Runtime monotonic clock exceeds int64 nanoseconds');
  }
  return microseconds * 1000;
}
```


Microsecond resolution is finer than the foreground display cadence and avoids overflowing an intermediate `elapsedTicks * 1_000_000_000` multiplication after only seconds of uptime.
Clock conversion tests must cover more than ten seconds of ticks and the final valid and first invalid int64-microsecond boundaries.

### Runtime session API

The old request-response `step`, `sendEventBatch`, and `framePresented` surface is removed.
The replacement is an ordered update session.

```dart
abstract interface class RuntimeSession {
  Stream<RuntimeUpdate> get updates;

  void grantVsync({required int generation});

  void setFrameEligibility({
    required int generation,
    required bool eligible,
  });

  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  });

  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  });

  Future<RuntimeDebugSnapshot> debugSnapshot();

  Future<void> dispose();
}
```


Public methods must synchronously reject use after disposal.
The session stream must emit one terminal diagnostic and close exactly once on native fatal status, isolate error, isolate exit, startup failure, or explicit disposal.
`debugSnapshot` is a diagnostic barrier on the same command port and reports worker state, live generation, eligibility, pump count, coalesced-grant state, and unresolved presentation identity.
Because the worker processes commands serially, a snapshot requested after `setFrameEligibility(eligible: false)` observes completion of any earlier synchronous FFI call and proves that no later pump has started.

## Flutter frame coordinator

### New scheduler abstraction

Add `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/foreground_frame_loop.dart`.
Its production implementation wraps the following SchedulerBinding operations.

```dart
abstract interface class RuntimeFrameScheduler {
  bool get framesEnabled;

  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
  });

  void cancelFrameCallbackWithId(int id);

  void addPostFrameCallback(FrameCallback callback);
}

abstract interface class FrameEligibilitySource {
  bool get isEligible;

  void start(void Function(bool isEligible) onChanged);

  void dispose();
}
```


`SchedulerBindingFrameScheduler` is the production frame adapter.
`AppLifecycleFrameEligibilitySource` is the production eligibility adapter and owns one disposable `AppLifecycleListener`.
The abstractions enable deterministic unit tests but must not contain a switch which disables production looping under `flutter_test`.


Ownership is deliberately split.

| Owner | State |
| --- | --- |
| `ForegroundFrameLoop` | Callback ID, callback generation, running or stopped state, frame scheduler, eligibility source, and guarded post-frame registration. |
| `BonsaiFlutterRoot` | Pending presentation, one optional held raw update, armed generation, event queue, applied revision, presented revision, and runtime session. |
| `RuntimeWorker` | Native runtime, monotonic clock, coalesced grant, and unresolved native presentation barrier. |


`ForegroundFrameLoop` reports eligible begin frames and generation invalidation to the root.
It never reads or mutates a presentation token, event batch, renderer revision, or runtime session.
It exposes `addGuardedPostFrameCallback` so the root can supply token logic without sharing direct ownership of `RuntimeFrameScheduler`.

### Foreground loop state

```text
Stopped
  start or resume while framesEnabled
    -> Running(generation, callbackId)

Running
  begin-frame callback
    -> clear only the matching captured callbackId
       recheck generation, eligibility, and framesEnabled
       register one successor with rescheduling: true
       notify the root of the eligible begin frame
       -> Running

Running
  hidden, paused, detached, frames disabled, fatal, or dispose
    -> increment generation
       cancel callbackId if present
       notify the root that the old generation is invalid
       -> Stopped or Terminal

Stopped
  resumed or inactive and framesEnabled
    -> increment generation
       register one callback with rescheduling: false
       -> Running
```


The first registration and every lifecycle restart use `rescheduling: false`.
Only the callback's recursive successor uses `rescheduling: true`.
There must be at most one stored callback identifier per root.
The root resets an unclaimed pending cycle's armed flag when it receives generation invalidation so resume can attach a new post-frame callback.
On an eligible transition, the loop invokes the root's synchronous eligibility hook before registering its first transient callback; a terminal hook result prevents registration.

### Begin-frame algorithm

```dart
void _scheduleNext({required bool rescheduling}) {
  if (!_running ||
      !_eligibility.isEligible ||
      !_scheduler.framesEnabled ||
      _callbackId != null) {
    return;
  }

  final scheduledGeneration = _generation;
  late final int scheduledId;
  scheduledId = _scheduler.scheduleFrameCallback((timestamp) {
    if (_callbackId != scheduledId) return;
    _callbackId = null;

    if (!_running ||
        _generation != scheduledGeneration ||
        !_eligibility.isEligible ||
        !_scheduler.framesEnabled) {
      _stopAndInvalidate();
      return;
    }

    _scheduleNext(rescheduling: true);
    _onBeginFrame(scheduledGeneration, timestamp);
  }, rescheduling: rescheduling);
  _callbackId = scheduledId;
}
```


The captured-ID comparison prevents an old callback from clearing the callback ID installed by a resumed generation.
If `framesEnabled` becomes false without a lifecycle callback, the saved closure performs zero grant, registers zero successor, and invalidates the old generation.
The final code must handle a scheduling exception as terminal.


The loop owns guarded post-frame registration.

```dart
void addGuardedPostFrameCallback({
  required int generation,
  required FrameCallback callback,
}) {
  _scheduler.addPostFrameCallback((timestamp) {
    if (!_running ||
        _generation != generation ||
        !_eligibility.isEligible ||
        !_scheduler.framesEnabled) {
      return;
    }
    callback(timestamp);
  });
}
```


The root still performs its exact token reservation inside `callback`; both the scheduler generation and presentation identity must match.


The root handles an eligible begin frame with the following synchronous algorithm.

```dart
void _onRuntimeBeginFrame(int generation, Duration diagnosticTimestamp) {
  final cycle = _pendingCycle;
  if (cycle != null && cycle.tryArm(generation)) {
    _frameLoop.addGuardedPostFrameCallback(
      generation: generation,
      callback: (_) => _onPostFrame(cycle, generation),
    );
  }

  _runtime.grantVsync(generation: generation);
}
```


An update received after this root callback has begun remains pending until a later begin frame and cannot be acknowledged by the current frame.

### Post-frame algorithm

```dart
void _onPostFrame(PendingCycle cycle, int generation) {
  final reservation = cycle.tryReserve(generation: generation, owner: this);
  if (reservation == null) return;
  final preparedEvents = _events.prepareBatch();

  try {
    _runtime.presentationSucceeded(
      generation: generation,
      presentationId: cycle.presentationId,
      revision: cycle.revision,
      eventBatch: preparedEvents.encodedBytes,
    );
  } catch (error, stackTrace) {
    cycle.releaseAndDisarm(reservation);
    _reportTerminalHandoffError(error, stackTrace);
    return;
  }

  cycle.commit(reservation);
  _events.commit(preparedEvents);
  _lastPresentedPresentationId = cycle.presentationId;
  _lastPresentedRevision = cycle.revision;
  _pendingCycle = null;
}
```


Reservation must provide exactly-once protection across a stale uncancelable post-frame callback and a resumed replacement callback.
It binds the exact token to the current eligible generation, not to the generation under which the token was issued.
The token, presented revision, and event prefix commit only after the live session has synchronously copied or enqueued the command to its worker `SendPort`.
The session handoff contract is synchronous and non-reentrant.


The post-frame callback is synchronous.
No UI-isolate event can interleave between successful handoff and the local commits, so `lastPresentedRevision` still advances before any later renderer event is encoded.
The callback does not `await` an isolate response.
This callback is the framework-level display boundary after Flutter build, layout, paint, and persistent callbacks have flushed.
It is not evidence that GPU rasterization or physical display scanout has completed.


`EventBatchQueue` must replace destructive `takeBatch` use in this path with a two-phase prefix snapshot.

```dart
final class PreparedEventBatch {
  final int prefixLength;
  final Uint8List encodedBytes;
  // The implementation also retains the debug-counter snapshot.
}

PreparedEventBatch prepareBatch();

void commit(PreparedEventBatch prepared);
```


`prepareBatch` does not remove events or advance reported coalescing counters.
`commit` verifies that the captured prefix still matches, removes only that prefix, advances its debug counters, and preserves any event appended after preparation.
Although production handoff is non-reentrant, the prefix rule makes failure and test behavior explicit.

### Root update pipeline

Refactor `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/root/bonsai_flutter_root.dart` around one update subscriber.


The following apply pipeline runs only while the root is eligible.
If `CycleReady` arrives while ineligible, the root stores the single raw update without materializing its `TransferableTypedData` and performs no decode, store preparation, store commit, resource synchronization, host dispatch, or `setState`.
A second held update is a fatal protocol violation because the native one-token barrier permits only one.
When eligibility returns, the synchronous eligibility hook first enqueues `setFrameEligibility` for the new generation, then runs this pipeline on the held update, and only then allows `ForegroundFrameLoop` to register the first resumed callback.


For each eligible or resumed-held `CycleReady`, the root performs the following steps.

1. Reject a second pending cycle as a fatal protocol violation.
2. Validate positive presentation identity and nondecreasing renderer revision.
3. Decode bytes when they are nonempty.
4. Require the first emitted frame to be a full snapshot.
5. Call `NodeStore.prepare(frame)` to build and validate a shadow transaction without live mutation.
6. Reject decode or prepare failures before any live-store commit.
7. Call `NodeStore.commit(prepared)` exactly once.
8. Treat any exception from commit or later as fatal.
9. Synchronize renderer resources and treat any synchronization exception as fatal because resource disposal cannot be rolled back.
10. Start `HostEffectDispatcher.dispatch` only after store and resource commit, immediately attach its returned `Future` to terminal-error handling, and never classify a later Future failure as rejectable.
11. Store the cycle as applied but not presented.
12. Call `setState` only when the wire frame changed renderer-visible state.
13. Let the next begin-frame callback arm its post-frame acknowledgment.


A no-byte cycle skips decode, store mutation, resource synchronization, host dispatch, and `setState`.
It still becomes the one applied pending cycle and must receive a real post-frame acknowledgment.


`NodeStore` must expose a local two-phase transaction while preserving `apply` as a prepare-and-commit convenience for callers outside the runtime root.

```dart
PreparedNodeStoreFrame prepare(Frame frame);

ApplyResult commit(PreparedNodeStoreFrame prepared);
```


The prepared value binds the store epoch, base revision, resource generation, shadow node map, shadow root, dirty set, and dropped set.
Commit rejects reuse or a changed base before mutation, then performs the existing live assignment, notifications, and instrumentation.


Decode and `NodeStore.prepare` failures send `presentationRejected` with the current eligible generation.
The root retains its last successfully applied store for those pre-commit failures until a later full snapshot succeeds.
`NodeStore.commit` verifies that its prepared base still matches, mutates live state, notifies listeners, and cannot be rolled back.
Commit, listener, debug-recorder, resource synchronization, a synchronous dispatch-start defect, any later host-dispatch `Future` failure, or any other exception after live-store commit is terminal and must not reject or replay the candidate.

### Event revision correction

Add `_lastPresentedRevision` to the root and initialize it to zero.
Pass it to `EventBatchQueue.displayedRevision`.


Applying a wire frame must not advance the event-visible revision.
Only the exact matching post-frame callback advances it.
Events queued before that callback retain the previous displayed revision, while events created afterward use the newly presented revision.

### Application lifecycle

Use `AppLifecycleListener` behind the frame-loop abstraction and dispose it with the loop.
The scheduler wrapper and lifecycle callback entry point must remain independently testable.
Every eligibility transition increments or confirms the loop generation and synchronously notifies the root.
The root resets any unclaimed armed cycle for an invalidated generation and sends `setFrameEligibility` before it can send a grant for a resumed generation.
For an eligible transition, the root processes any held `CycleReady` before `ForegroundFrameLoop` registers the first resumed callback.


The eligibility table is exact.

| Lifecycle state | Frame-loop behavior |
| --- | --- |
| `resumed` | Run when `framesEnabled` is true. |
| `inactive` | Continue because frames remain enabled and content may still be visible. |
| `hidden` | Cancel the transient callback and invalidate grants. |
| `paused` | Cancel the transient callback and invalidate grants. |
| `detached` | Stop scheduling and retain no expectation of another callback. |
| Initial null state | Run only when `framesEnabled` is true. |


An unresolved presentation is retained across `hidden` and `paused`.
An in-flight pump which completes before the worker processes the ineligible command may also deliver one token.
If that token was not already applied, the root holds its `CycleReady` without decode, store commit, resource synchronization, or host dispatch until eligibility returns.
On eligibility return, the root processes the held update before the frame loop registers its first callback.
On resume, a new real frame presents and acknowledges any retained token using the new current generation before a later candidate is pumped.


No timer is promised to execute while the application is suspended.
If a token is retained, its resume-frame success call first advances the public time source without flushing, and the following freshly sampled native pump processes every older deadline which the mapped clock has passed.
If no token is retained, the first granted native pump after resume performs that catch-up.

## Error and shutdown policy

| Failure | Classification | Required state |
| --- | --- | --- |
| Invalid input batch before execution | Recoverable cycle | Drop the complete batch, advance the logical frame without that input, and emit a token plus diagnostic. |
| Old, duplicate, future, or unsolicited token | Protocol violation | Mutate nothing and terminate the root coordinator. |
| Decreasing or invalid monotonic clock | Protocol violation | Mutate nothing and terminate the runtime. |
| Frame decode or `NodeStore.prepare` failure before live commit | Recoverable presentation rejection | Keep last renderer state and force a full snapshot. |
| Listener, resource synchronization, or host dispatch failure after live commit | Fatal | Stop without rejection because renderer or external state cannot be rolled back. |
| Handler or action exception after execution begins | Fatal | Stop grants, close update stream, and dispose native runtime. |
| Lifecycle exception | Fatal | Stop because baseline or effects may be partially committed. |
| Worker isolate exit or error | Fatal | Complete pending operations and stream closure exactly once. |
| Widget dispose | Ordered shutdown | Cancel scheduling, invalidate callbacks, cancel subscription, and destroy runtime once. |


`dispose` does not wait for an operating-system lifecycle notification.
Stale transient and post-frame closures observe terminal state and perform zero session calls.

## Performance and power boundary

The design deliberately spends foreground work to obtain complete semantics without upstream introspection.
It performs no periodic work when Flutter cannot deliver frames.


The following counters must be added to diagnostics or tests.

- Eligible begin-frame callbacks
- Vsync grants sent
- Vsync grants coalesced
- Native pumps started
- Presentation tokens issued
- Successful presentation acknowledgments
- No-byte presentation tokens
- Rejected presentations
- Maximum unresolved-presentation count
- Pumps attempted while frames are disabled


The last two values must remain at one and zero respectively.
Benchmark reports must separate scheduler-message cost, native pump cost, reconciliation cost, encoding cost, and Flutter frame cost.

## Upstream modification audit

The implementation must not add any file under a new upstream feature-patch directory.
It must not change Bonsai, Bonsai Concrete, Incremental, Incr_dom, or Flutter dependency revisions for this feature.


The only accepted upstream-facing code is the local adapter around already public symbols.
The repository's existing `Bonsai.Private.Instrumentation` construction remains confined to `bonsai_runtime_adapter.ml` because it is already required by the pinned Driver constructor, but this feature adds no private API use.


`tool/test_ci_contract.sh` must enforce this as repository state, not as a working-tree diff.
It must perform all of the following reproducible checks.

- Assert the exact Bonsai version and commits already recorded in `dune-project`, both opam files, `tool/ios/toolchain.lock`, and `vendor/opam-ios/runtime-closure.lock`.
- Assert the exact Flutter version and commit already recorded in `tool/ios/toolchain.lock`.
- Enumerate `vendor/patches` with `find`, including untracked local files, and allow only the three existing paths: `README.md`, `basement-macos.patch`, and `ios/jst-config-host-discover.patch`.
- Verify the SHA-256 values of those three existing files so this feature cannot hide an upstream edit inside an allowed path.
- Reject new Bonsai, Bonsai Concrete, Incremental, Incr_dom, or Flutter source trees, local opam pins, dependency-source overrides, or feature-patch directories anywhere outside the existing allowlist.
- Reject new runtime use of `Bonsai.Time_source.Private`, `Obj.magic`, fixed-period timers, or forced frames.


The recorded patch hashes are `808499a89ac9c02b545c8a011c365bbad1c1846a5c9564c1161d8fc9fe41f6f6`, `1c97bd1e3ad6eeefe30fce6a81a06ed4685fdef95efb53e67cd9389b6201327b`, and `d1d9fbbf8df8f8e315fad1a834352a5a80e948e62012a104d5362461f195df78` in the path order above.
Because these assertions inspect declared baselines and the filesystem itself, they remain effective for staged, committed, and untracked files and in a clean CI checkout.

## Compatibility and migration

This is an intentional internal and package-development API break.
It does not preserve callers which manually drive `RuntimeSession.step` or `framePresented`.


The renderer protocol remains 1.12, so application components and committed frame or event fixtures do not change solely because of this feature.
The C ABI changes to 2.0 and rejects older native artifacts before runtime creation.


The following direct runtime wrappers must migrate.

- `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/flutter/lib/mail_runtime_trace.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/flutter/test/mail_runtime_trace_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/counter_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/gallery_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/host_navigation_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/mail_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/text_input_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/todo_ffi_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/integration_test/ios_lifecycle_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/benchmark/runtime_benchmark_test.dart`


Continuous frame scheduling makes `pumpAndSettle` nonterminating while a live root is mounted.
Tests must use bounded frame counts or predicate-based helpers and then dispose the root explicitly.
There is no test-only switch which restores the old event-driven runtime.

## File change inventory

### New implementation files

| File | Responsibility |
| --- | --- |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_protocol.dart` | Typed isolate commands and runtime updates. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_worker.dart` | Worker state machine, clock, grant coalescing, and serialized native ownership. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/foreground_frame_loop.dart` | Flutter scheduler and lifecycle coordinator. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/frame_driven_pump_tests.ml` | OCaml behavior-level pump tests. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/runtime_worker_test.dart` | Worker barrier, clock, and failure tests. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/foreground_frame_loop_test.dart` | Scheduler generation and lifecycle tests. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/support/pump_bonsai.dart` | Bounded widget-test helpers. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/ocaml/autonomous_pump_fixture.ml` | Real timer and after-display fixture. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/autonomous_pump_ffi_test.dart` | Real cross-language autonomous-pump acceptance. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/docs/adr/0006-foreground-vsync-pump.md` | Superseding scheduling decision. |

### Modified OCaml files

| File | Change |
| --- | --- |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/bonsai_runtime_adapter.ml` | Retain the time source and wrap public clock advancement and lifecycle triggering. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/bonsai_runtime_adapter.mli` | Replace incomplete scheduling predicates with the new local operations. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/driver.ml` | Add pump, presentation token, candidate commit, clock, rejection, and barrier semantics. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/driver.mli` | Publish the new Driver transaction API. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/event_dispatcher.ml` | Split full-batch validation from execution. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/event_dispatcher.mli` | Expose local validated-batch representation. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/host_effect.ml` | Validate responses and add prepared-operation prefix commit without destructive candidate dequeue. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/host_effect.mli` | Expose local response validation and prepared-operation ownership. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ffi/native_backend.ml` | Implement ABI v2 callback outcomes and presentation identity. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ffi/native_backend.mli` | Publish the new backend functions. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test_support/handle.ml` | Drive explicit fake monotonic ticks and presentation tokens. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test_support/handle.mli` | Expose deterministic pump helpers. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/dune` | Register the new test executable or module. |

### Modified native and Dart files

| File | Change |
| --- | --- |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.h` | Define ABI v2, output shape, and new runtime functions. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_native.c` | Validate and transport presentation and time fields. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_ocaml_bridge.h` | Update bridge response and declarations. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_ocaml_bridge.c` | Resolve and invoke the five ABI v2 callbacks. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/src/bonsai_flutter_exports.txt` | Export ABI v2 symbols and remove v1 pump symbols. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/lib/bonsai_flutter_native_bindings_generated.dart` | Regenerate declarations with ffigen. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/lib/bonsai_flutter_native.dart` | Enforce ABI version and expose token-aware native methods. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/runtime_client.dart` | Replace command-response driving with the ordered update session. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/event_batch_queue.dart` | Add non-destructive prepare and exact-prefix commit for atomic post-frame handoff. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/root/bonsai_flutter_root.dart` | Integrate the frame loop, update stream, token apply, ack, rejection, and shutdown. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/debug/frame_stats.dart` | Record presentation identity and grant or coalescing counters. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart` | Export only the intended new public runtime types. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/store/node_store.dart` | Add prepare and commit transactions so only pre-commit failures are rejectable. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/tool/ios/verify_complete_object.sh` | Audit the ABI v2 symbol set. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ci_contract.sh` | Enforce pinned upstream baselines, the existing patch allowlist and hashes, and forbidden local implementations. |

### Modified tests and fixtures

Update all existing OCaml Driver tests which call `step` or acknowledge a raw revision.
Update all native C mocks and bridge tests for the ABI v2 layout.
Update runtime client and root widget tests for ordered updates and bounded frame pumping.
Update every FFI integration test and benchmark which manually calls `step` or `framePresented`.


The minimum directly affected files include the following paths.

- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/bonsai_runtime_adapter_tests.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/driver_counter_tests.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/layout_driver_tests.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/native_backend_tests.ml`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/native_bridge_test.c`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/bonsai_flutter_native_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/runtime_client_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/bonsai_flutter_root_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/node_store_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/integration_test/mail_profile_test.dart`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/integration_test/ios_ffi_test.dart`

### Modified documentation

- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/architecture.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/lifecycle.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/ffi.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/testing.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/upstream-baseline.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/docs/adr/0002-runtime-boundary.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/examples/mail/README.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/CHANGES.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/CHANGELOG.md`
- `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/CHANGELOG.md`

## Testing Plan

All behavior tests are added before implementation behavior changes.
Every test uses fake monotonic ticks or bounded real Flutter frames and asserts externally observable behavior or explicit runtime state.

### OCaml clock behavior

- A `Bonsai.Clock.at` computation changes only on the first pump at or after its deadline.
- `Bonsai.Clock.approx_now` and `Bonsai.Clock.Expert.now` observe later values on later logical frames.
- `Bonsai.Clock.every` produces the expected catch-up behavior after a large monotonic jump.
- `Bonsai.Clock.sleep`, `Bonsai.Clock.until`, `Bonsai.Time_source.sleep`, and `Bonsai.Time_source.until` complete without input events.
- A timer created by after-display uses the successful presentation acknowledgment time, including when its token was retained across suspension.
- A retained token acknowledged after a large monotonic jump does not make a newly created relative after-display timer expire immediately.
- A negative or decreasing clock sample fails before Driver state changes.
- A malformed or stale input batch is dropped atomically but cannot prevent a due timer from advancing in the same logical pump.

### OCaml lifecycle behavior

- A first presentation runs activation only after its exact token is acknowledged.
- An after-display action changes the result on the following pump without external input.
- Persistent after-display runs exactly once for every successful presentation token.
- `wait_after_display` completes exactly once.
- A lifecycle-only activation or deactivation with an unchanged widget tree still runs.
- Adding only a future deactivation callback and later removing it runs the callback.
- Replacing a same-path lifecycle closure and later removing it runs the replacement.
- Lifecycle collection before-display work which installs another lifecycle before-display callback reaches its fixed point in one pump.
- A time-source `wait_before_display` action which creates new lifecycle before-display work runs that new work on the next pump.

### OCaml token and revision behavior

- One hundred no-diff pumps issue one hundred increasing presentation identifiers while renderer revision and handler-frame count remain stable.
- A changed handler identity emits `Update_event_bindings` and advances renderer revision.
- A duplicate, old, future, or unsolicited token cannot trigger lifecycle.
- No second pump is accepted while one presentation is unresolved.
- A successful wire-frame acknowledgment promotes the candidate tree and handler frame.
- A rejected candidate does not run lifecycle and forces a later full snapshot.
- A rejected renderer revision is never reused.
- Rejected host-request and cancel operations remain queued and reappear once in original order on the recovery snapshot.
- Successfully presented host operations commit once and are never emitted by a later pump.
- Presentation identifier and renderer revision overflow are fatal.

### Native ABI behavior

- ABI version `2.0` and protocol version `1.12` are reported independently.
- The C and generated Dart layouts agree on every `bf_output_buffer` field.
- A successful no-byte pump returns a positive presentation identifier and a null zero-length buffer.
- A recoverable dropped-input result preserves its token and optional bytes across OCaml, C, and Dart.
- A nonempty output preserves allocation ownership and is freed exactly once.
- An injected native-version facade proves exact mismatch rejection before runtime creation.
- The complete-object symbol audit proves every v2 symbol is present and every v1 runtime-driving symbol is absent.
- Old v1 pump symbols are absent from the audited export list.
- Invalid presentation or monotonic values cross C as stable status and error codes.

### Runtime worker behavior

- The first eligible grant performs exactly one native pump.
- One hundred grants while awaiting presentation cause no additional native pump.
- An `OK` or recoverable no-byte logical-pump result still emits `CycleReady` and enters the barrier.
- One exact success acknowledgment invokes lifecycle once and releases one coalesced grant.
- A wrong token invokes no lifecycle or pump.
- Visibility loss invalidates queued grants while retaining the unresolved token.
- A pump started before the ineligible command may finish, but a same-port debug snapshot proves that no later pump starts.
- Resume first presents any retained token, its success call samples the elapsed stopwatch jump without flushing, and the next native pump takes another fresh sample.
- An after-display timer created by that resume acknowledgment starts at acknowledgment time while older overdue timers catch up in the next pump.
- An old-generation result for a retained token reaches no native call, while the exact result using the new current eligible generation succeeds.
- Monotonic conversion remains correct beyond ten seconds and rejects only values beyond the int64 nanosecond boundary.
- A native fatal status, isolate error, isolate exit, and explicit disposal each close the update stream once.
- Post-dispose commands fail synchronously and no native call follows.

### Foreground frame-loop behavior

- Start registers exactly one transient callback with `rescheduling: false`.
- Each executed callback registers exactly one successor with `rescheduling: true`.
- Each bounded Flutter frame sends at most one grant.
- `inactive` continues the loop.
- `hidden`, `paused`, and `detached` cancel the pending callback and send no later grant.
- Resume after any stopped state registers one callback and does not duplicate the loop.
- An engine frame left after cancellation performs zero runtime calls.
- A saved callback executed with `framesEnabled == false` clears only its own ID, sends zero grant, and registers zero successor.
- A stale callback from an old generation cannot clear a newer generation's callback ID.
- A stale post-frame closure cannot acknowledge after generation changes; the resumed replacement callback can reserve the retained exact token under the new current generation.
- Disposal leaves no live callback identifier and no runtime commands.

### Flutter root behavior

- An initial full snapshot is decoded and applied before its post-frame acknowledgment.
- A no-byte cycle receives a real later post-frame acknowledgment.
- A runtime update arriving after begin-frame does not attach to that frame's post-frame callback.
- `NodeStore.revision` can advance while new events still use the previous `lastPresentedRevision`.
- After the synchronous presentation handoff returns successfully, the matching post-frame callback commits the event revision before any later renderer event can be encoded.
- Decode or `NodeStore.prepare` failure rejects the exact token and preserves the prior store.
- A post-frame session handoff failure preserves the token, presented revision, and prepared event prefix before terminal shutdown.
- A `NodeStore.prepare` failure rejects, while a commit, listener, resource, dispatch-start, or later host-dispatch `Future` failure is fatal and never replays the candidate.
- A cycle delivered after ineligibility is held without store, resource, or host mutation, then applied before the first resumed callback.
- A pending cycle is not acknowledged while backgrounded and is acknowledged on the first matching resume frame using the new eligible generation.
- A stale callback after root disposal sends no session command.

### Real FFI acceptance

Add one fixture with the following observable phases.

```text
Phase 0
  initial full snapshot

successful presentation
  one-shot after-display action sets Phase 1
  the same after-display action starts a 50 ms sleep

later foreground frame
  automatic pump emits Phase 1

first logical frame at or after the timer deadline
  automatic pump emits Phase 2
```


The test supplies no tap, host response, environment update, or manual runtime pump.
It verifies that Phase 1 is actually presented before Phase 2.


This real-isolate test cannot advance the production worker `Stopwatch` with `tester.pump(Duration(...))`.
Its bounded helper must alternate `tester.runAsync(() => Future<void>.delayed(realSlice))` with one `tester.pump()`, stop on an explicit UI predicate, and enforce a wall-clock timeout with diagnostic snapshots.


A second lifecycle scenario uses the valid mobile transition sequence `resumed -> inactive -> hidden -> paused -> hidden -> inactive -> resumed`.
After the ineligible command and a same-port debug snapshot barrier, it proves that pump count stops changing.
It then resumes, acknowledges any retained token on a real Flutter frame, and proves that the first subsequent native pump catches up overdue work before a later frame presents the resulting revision.

### Test ergonomics and source contracts

- Replace `pumpAndSettle` while a live `BonsaiFlutterRoot` is mounted with `pumpBonsaiUntil(predicate, maxFrames: N)`.
- Make bounded helper failure messages include cycle ID, applied revision, presented revision, scheduler generation, and native pump count.
- Do not detect `TestWidgetsFlutterBinding` in production scheduling code.
- Add a source scan which rejects fixed timers, forced frames, private time-source calls, and upstream feature patches.

NOTE: I will write *all* tests before I add any implementation behavior.

## Implementation plan

### Phase 1: Freeze the local contract

#### Task 1: Add the superseding ADR and public transaction shapes

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/docs/adr/0006-foreground-vsync-pump.md`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/docs/adr/0002-runtime-boundary.md`.

Steps:

1. Record continuous foreground pumping, presentation-token separation, background suspension, and no-upstream-change constraints in ADR 0006.
2. Mark ADR 0002's command-driven scheduling portion as superseded by ADR 0006.
3. Record the exact token, rejection reason, worker command, update, and clock contracts which the RED tests will target.
4. Do not change production interfaces or implementation before the RED suites are written and observed failing.

Verify:

```sh
rg -n "upstream|presentation_id|scheduleFrameCallback|background" \
  docs/adr/0006-foreground-vsync-pump.md
```

Expected result:

```text
The ADR contains all four decisions and contains no deadline-timer fallback.
```

### Phase 2: Write the complete RED suite

#### Task 2: Write OCaml timer, lifecycle, token, and rejection tests

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/frame_driven_pump_tests.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test_support/handle.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test_support/handle.mli`.

Steps:

1. Add deterministic fake elapsed-time helpers.
2. Add the clock-family tests from the Testing Plan.
3. Add lifecycle-only and after-display tests.
4. Add presentation-token, no-diff, handler-invariant, and rejection tests.
5. Assert exact states and output rather than internal helper call order where behavior is observable.

Verify RED:

```sh
dune runtest ocaml/test
```

Expected failure:

```text
Compilation fails because Driver.pump and presentation-token APIs do not exist, or the new behavioral assertions fail against the command-driven Driver.
```

#### Task 3: Write native ABI v2 tests

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/mock_ocaml_bridge.c`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/native_bridge_test.c`.
- Delete `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/native_ocaml_embed_test.c` because it has no test runner and the real embedded path is covered by the integration suite.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native/test/bonsai_flutter_native_test.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/ios/verify_complete_object.sh`.

Steps:

1. Assert independent ABI and protocol versions.
2. Assert exact output layout, token propagation, clock propagation, and rejection reason propagation.
3. Assert zero-length and allocated-buffer ownership.
4. Add an injectable private native-version facade and assert exact-version mismatch without attempting to swap package code assets in one Dart process.
5. Change the complete-object verifier into a RED contract which requires every ABI v2 symbol and rejects `bf_runtime_step` and `bf_runtime_frame_presented`.
6. Build and stage the integration complete object so the verifier actually executes during this task.

Verify RED:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make integration-native-object
make ci-sanitizers
cd flutter/packages/bonsai_flutter_native
dart test
```

Expected failure:

```text
The complete-object audit, C sanitizer test, and Dart facade tests fail because the ABI version and presentation-aware symbols do not exist.
```

#### Task 4: Write runtime worker tests

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/runtime_worker_test.dart`.
- Add test fakes under `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/support/`.

Steps:

1. Implement fake native runtime, fake monotonic clock, and update recorder test doubles.
2. Add state, barrier, grant-coalescing, lifecycle, visibility, fatal, and disposal assertions.
3. Assert same-port debug snapshots form an ordered barrier after visibility commands and in-flight FFI completion.
4. Assert that an old-generation result for a retained token makes no native call while an exact result from the new live eligible generation succeeds.
5. Assert fresh, distinct worker-clock reads for success acknowledgment and a subsequently consumed coalesced grant.
6. Assert native call counts after every command boundary.

Verify RED:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter
flutter test test/runtime_worker_test.dart
```

Expected failure:

```text
Compilation fails because RuntimeWorker and the typed isolate protocol do not exist.
```

#### Task 5: Write frame-loop and root tests

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/foreground_frame_loop_test.dart`.
- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/support/pump_bonsai.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/bonsai_flutter_root_test.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/event_batch_test.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/node_store_test.dart`.

Steps:

1. Test the scheduler wrapper with an explicit fake callback queue.
2. Test the injectable lifecycle source and the valid mobile state-transition sequence.
3. Test real widget binding behavior with a fixed number of `tester.pump` calls.
4. Test captured callback IDs, independent `framesEnabled` loss, begin-frame versus post-frame ordering, and stale generation guards.
5. Test applied-versus-presented event revisions.
6. Test event-prefix prepare, failed handoff preservation, exact commit, and concurrent append preservation.
7. Test that an ineligible raw update is not decoded or applied and is processed before the first resumed callback.
8. Test NodeStore prepare without mutation, single commit, stale prepared-value rejection, and fatal post-commit listener behavior.
9. Test that a later `HostEffectDispatcher.dispatch` Future failure is terminal and never rejects or replays the candidate.
10. Replace every affected `pumpAndSettle` use with bounded helpers.

Verify RED:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter
flutter test \
  test/foreground_frame_loop_test.dart \
  test/event_batch_test.dart \
  test/node_store_test.dart \
  test/bonsai_flutter_root_test.dart
```

Expected failure:

```text
Tests fail because the foreground loop, token-aware session, and presented revision state do not exist.
```

#### Task 6: Write real FFI acceptance tests

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/ocaml/autonomous_pump_fixture.ml`.
- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test/autonomous_pump_ffi_test.dart`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/ocaml/dune`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/ocaml/native_integration_embed.ml`.

Steps:

1. Register the Phase 0, Phase 1, and Phase 2 fixture.
2. Drive bounded real elapsed slices with `tester.runAsync(() => Future<void>.delayed(...))` followed by one `tester.pump()`.
3. Assert after-display and timer transitions without events.
4. Add a wall-clock timeout and include `RuntimeDebugSnapshot` fields in timeout diagnostics.
5. Add the ordered mobile lifecycle sequence, hidden debug barrier, retained-token acknowledgment under the new generation, and resume catch-up scenario.
6. Prove that an after-display `sleep` created by the retained token starts at resume acknowledgment time rather than expiring immediately from the pre-suspension pump time.

Verify RED:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make integration-test
```

Expected failure:

```text
The new acceptance test times out before Phase 1 or Phase 2 because no autonomous pump exists.
```

#### Task 7: Preserve RED evidence

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/tool/test_ci_contract.sh`.

Steps:

1. Add exact pinned-version and commit checks for Bonsai, Bonsai Concrete, Incremental, and Flutter.
2. Add the filesystem patch allowlist and SHA-256 checks, local-pin and source-overlay rejection, no-private-time-source guard, and no-fixed-scheduler guard.
3. Run every command from Tasks 2 through 6.
4. Confirm each new behavior test fails for its stated missing behavior and not because of a malformed fixture or unrelated environment issue.
5. Confirm the source guards pass against the preimplementation tree.
6. Correct faulty tests before implementation.
7. Save concise failure summaries in the implementation task notes or PR description.

Verify:

```sh
make ci-contract
git diff --check
```

Expected result:

```text
The source guards pass, no whitespace errors are reported, and every new behavioral suite has observed a relevant RED failure.
```

### Phase 3: Implement the minimum GREEN behavior

#### Task 8: Add local public time-source driving

Files:

- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/bonsai_runtime_adapter.ml`.
- Modify `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/runtime/bonsai_runtime_adapter.mli`.

Steps:

1. Retain the `Bonsai.Time_source.t` supplied at adapter creation.
2. Add a wrapper for public `Bonsai.Time_source.advance_clock`.
3. Rename the local lifecycle operation so it cannot be confused with protocol acknowledgment.
4. Remove runtime scheduling dependence on `has_before_display_events` and `has_after_display_events`.
5. Keep existing observer invalidation behavior.

Verify GREEN:

```sh
dune exec ocaml/test/bonsai_runtime_adapter_tests.exe
```

Expected result:

```text
The adapter suite passes using only public clock and Driver operations.
```

#### Task 9: Implement Driver pump and presentation transactions

Files:

- Modify all OCaml runtime files listed in the inventory.

Steps:

1. Add clock origin, monotonic validation, presentation sequence, renderer sequence, and one-candidate state.
2. Split complete input validation from execution.
3. Replace destructive host-operation take with prepare and exact-prefix commit.
4. Refactor reconciliation so candidate tree and handler state commit only on success acknowledgment.
5. Make every successful pump issue a presentation token.
6. On exact success, validate a fresh monotonic sample before mutation, commit the candidate, advance the public time source without flushing, and then trigger lifecycle.
7. Implement exact rejection transitions, including ordered host-operation replay and no clock advancement.
8. Make lifecycle exceptions terminal and force a full snapshot after rejection.
9. Add tracing for pump, token, revision, clock, acknowledgment, rejection, and barrier state.

Verify GREEN:

```sh
dune runtest ocaml/test
```

Expected result:

```text
All OCaml tests pass, including timer-without-input and after-display-follow-up behavior.
```

#### Task 10: Implement and generate ABI v2

Files:

- Modify all native files listed in the inventory.

Steps:

1. Change the C header and OCaml bridge response shape.
2. Register and resolve the v2 callback names.
3. Validate pointer, length, clock, token, revision, status, and output invariants at the C boundary.
4. Update exported symbols and complete-object verification.
5. Regenerate Dart bindings instead of editing generated declarations by hand.
6. Add exact ABI checks in `NativeRuntime`.

Verify GREEN:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter_native
dart run ffigen --config ffigen.yaml
dart test
dart analyze
cd /Users/rcmerci/gh-repos/bonsai_flutter
make ci-sanitizers
make integration-native-object
```

Expected result:

```text
Generation succeeds, native tests pass, and analysis reports no issues.
```

#### Task 11: Implement the runtime worker

Files:

- Create and modify the runtime Dart files listed in the inventory.

Steps:

1. Move worker code out of `runtime_client.dart`.
2. Start the stopwatch after native creation.
3. Implement typed commands, updates, generation validation, one-token barrier, and grant coalescing.
4. Convert elapsed microseconds to checked int64 nanoseconds without an overflowing intermediate multiplication.
5. Validate results against the current live eligible generation while allowing a retained token to cross from its issuance generation.
6. Take a fresh stopwatch sample for success acknowledgment and another fresh sample before any subsequent pump.
7. Serialize success acknowledgment before the next pump.
8. Implement same-port debug snapshots, rejection recovery, and terminal cleanup.
9. Wire isolate `onError` and `onExit` so no Future or stream remains open.

Verify GREEN:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter
flutter test test/runtime_client_test.dart test/runtime_worker_test.dart
```

Expected result:

```text
The runtime client and worker suites pass with one native owner and at most one unresolved presentation.
```

#### Task 12: Implement the Flutter frame loop and root pipeline

Files:

- Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/runtime/foreground_frame_loop.dart`.
- Modify root, event queue, debug, and package export files listed in the inventory.

Steps:

1. Implement one recursive transient callback with exact callback ID and generation ownership.
2. Implement the disposable AppLifecycleListener eligibility source and integrate `framesEnabled`.
3. Keep the scheduler adapter private to the loop and expose generation-guarded post-frame registration to the root.
4. Add NodeStore prepare and commit and EventBatchQueue prefix prepare and commit.
5. Subscribe to runtime updates before starting the loop.
6. Apply each optional frame before exposing a pending presentation.
7. Arm a post-frame callback only from a later matching begin frame.
8. Hand off presentation success before atomically committing token, event prefix, and presented revision.
9. Maintain applied and presented revisions separately.
10. Route all external events into the next post-presentation batch.
11. Hold raw updates delivered while ineligible and apply them before scheduling the first resumed callback.
12. Attach host-dispatch Futures to terminal handling and reject only pre-commit frame failures.
13. Stop cleanly on every post-commit failure, fatal state, or disposal.

Verify GREEN:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter
flutter test \
  test/foreground_frame_loop_test.dart \
  test/runtime_client_test.dart \
  test/runtime_worker_test.dart \
  test/bonsai_flutter_root_test.dart
```

Expected result:

```text
All selected tests pass without pumpAndSettle and without a test-only scheduler bypass.
```

#### Task 13: Complete the real acceptance slice

Files:

- Complete the fixture and integration files from Task 6.
- Update every direct runtime API caller listed under Compatibility and migration.

Steps:

1. Link the new fixture into the aggregate native object.
2. Migrate direct `step` callers to the frame-grant and ordered-update API.
3. Run Phase 0 through Phase 2 with no external event.
4. Run the background and resume scenario.
5. Migrate benchmarks to report presentation and pump metrics separately.

Verify GREEN:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make integration-test
```

Expected result:

```text
The timer and after-display acceptance passes through Flutter, the isolate, C, OCaml, and back with no external event.
```

### Phase 4: Refactor without changing behavior

#### Task 14: Simplify state ownership and diagnostics

Files:

- Review every modified OCaml, C, and Dart implementation file.

Steps:

1. Remove obsolete step, raw revision acknowledgment, and wakeup-deadline code.
2. Centralize token and generation validation.
3. Keep scheduler, worker, and Driver transitions as small exhaustive functions.
4. Remove duplicated error completion and buffer ownership paths.
5. Preserve every GREEN test while simplifying.

Verify:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
dune build @fmt
cd flutter/packages/bonsai_flutter
dart format --output=none --set-exit-if-changed lib test benchmark tool
flutter analyze
cd ../bonsai_flutter_native
dart format --output=none --set-exit-if-changed hook lib test
dart analyze
```

Expected result:

```text
Formatting and analysis pass with no behavior-test changes.
```

#### Task 15: Update architecture and operational documentation

Files:

- Modify all documentation and changelog files listed in the inventory.

Steps:

1. Replace deadline and one-shot-timer claims with the foreground-vsync state machine.
2. Document that visible idle runtimes continue pumping.
3. Document background suspension and resume catch-up.
4. Document ABI 2.0, protocol 1.12, presentation identity, and buffer ownership.
5. Document bounded widget-test pumping.
6. Record that no upstream feature patch or dependency change is required.

Verify:

```sh
rg -n "next_wakeup|one-shot timer|Timer\\.periodic" \
  docs flutter/packages/bonsai_flutter/README.md examples/mail/README.md
```

Expected result:

```text
No active documentation claims deadline scheduling, and any historical reference is explicitly marked superseded.
```

### Phase 5: Run complete regression gates

#### Task 16: Run local and cross-language gates

Files:

- No behavior changes unless a failing test identifies a defect.

Steps:

1. Run protocol and generated-binding checks.
2. Run OCaml, Flutter, native, sanitizer, and integration suites.
3. Run macOS packaging and iOS unsigned build gates where the required toolchains are available.
4. Inspect native symbols and ensure no ABI v1 runtime-driving symbol remains.

Verify:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make ci-contract
make ci-ocaml
make ci-flutter
make ci-sanitizers
make ci-macos
make ci-ios
```

Expected result:

```text
Every available gate exits zero, generated files are clean, and the ABI v2 symbol audit passes.
```

#### Task 17: Verify the final source contract

Files:

- Review the complete feature diff.

Steps:

1. Confirm that upstream dependency sources and revisions did not change.
2. Confirm that runtime scheduling contains no periodic timer, forced frame, or background fallback.
3. Confirm that no-diff cycles still produce presentation tokens.
4. Confirm that hidden and paused tests report zero new native pumps after the same-port ineligible snapshot barrier.
5. Confirm that foreground idle tests report increasing pump and presentation counts.

Verify:

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make ci-contract
git diff --check
git status --short
rg -n \
  "Timer\\.periodic|scheduleForcedFrame|scheduleWarmUpFrame|forceFrames|Time_source\\.Private|Obj\\.magic" \
  ocaml flutter/packages
```

Expected result:

```text
The feature diff is clean, contains no forbidden scheduler or private-time implementation, and changes no upstream dependency source.
```

## Acceptance criteria

- A real FFI timer reaches its due state without tap, environment change, host response, or manual pump command.
- A one-shot after-display action automatically produces a later presentation cycle and renderer revision when its result changes.
- Persistent after-display and lifecycle-only deltas run once per successful presentation even when no wire frame is emitted.
- `Clock.Expert.now` and the complete supported timer family advance on foreground logical frames.
- At most one presentation token is unresolved at every layer.
- Duplicate, old, future, rejected, and stale-generation tokens cannot run lifecycle; a retained exact token can be acknowledged only by the new current eligible generation after resume.
- Renderer events use only the last presented revision.
- After the ineligible command barrier, `hidden`, `paused`, and `detached` produce no new native pumps.
- Resume first acknowledges any retained token and then catches up overdue work on the next native pump without a background timer.
- Foreground scheduling uses recursive `scheduleFrameCallback` and no fixed-period timer.
- ABI v2 is checked exactly and no v1 runtime-driving fallback remains.
- Renderer binary protocol remains 1.12.
- No upstream source, overlay, dependency revision, or private time-source API is added.
- All RED tests are observed before implementation and all complete regression gates pass afterward.

## Sources

- [Bonsai Web start selection](https://github.com/janestreet/bonsai_web/blob/989c18b5381cad767365923d4f0b758c6f3c602c/web/bonsai_web.ml#L53-L85)
- [Incr_dom continuous frame loop](https://github.com/janestreet/incr_dom/blob/17a039c609b73a672084a690f166a9634482a5cd/src/frame_loop.ml#L57-L112)
- [Incr_dom update ordering](https://github.com/janestreet/incr_dom/blob/17a039c609b73a672084a690f166a9634482a5cd/src/start_app.ml#L256-L363)
- [Bonsai Web default time and lifecycle adapter](https://github.com/janestreet/bonsai_web/blob/989c18b5381cad767365923d4f0b758c6f3c602c/web/start_via_incr_dom.ml#L185-L266)
- [Bonsai Web experimental frame driver](https://github.com/janestreet/bonsai_web/blob/989c18b5381cad767365923d4f0b758c6f3c602c/web/start_experimental.ml#L217-L230)
- [Bonsai Web experimental recompute ordering](https://github.com/janestreet/bonsai_web/blob/989c18b5381cad767365923d4f0b758c6f3c602c/web/driver.ml#L165-L235)
- [Pinned Bonsai Driver public interface](https://github.com/janestreet/bonsai/blob/f31661450eb133fe89564219d97669c2735c6622/src/driver/bonsai_driver.mli#L17-L48)
- [Pinned Bonsai Driver flush and lifecycle implementation](https://github.com/janestreet/bonsai/blob/f31661450eb133fe89564219d97669c2735c6622/src/driver/bonsai_driver.ml#L281-L366)
- [Pinned Bonsai lifecycle collection semantics](https://github.com/janestreet/bonsai/blob/f31661450eb133fe89564219d97669c2735c6622/src/private_base/lifecycle.ml#L11-L67)
- [Pinned Bonsai Concrete time source](https://github.com/janestreet/bonsai_concrete/blob/10601f857306e691462fa049cb8b58c162d86cca/ui_time_source/ui_time_source.ml#L67-L129)
- [Flutter scheduleFrameCallback API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/scheduleFrameCallback.html)
- [Flutter cancelFrameCallbackWithId API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/cancelFrameCallbackWithId.html)
- [Flutter addPostFrameCallback API](https://api.flutter.dev/flutter/widgets/WidgetsBinding/addPostFrameCallback.html)
- [Flutter scheduleFrame API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/scheduleFrame.html)
- [Flutter framesEnabled API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/framesEnabled.html)
- [Flutter AppLifecycleState API](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html)
- [Flutter AppLifecycleListener API](https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html)
- [Flutter Ticker API](https://api.flutter.dev/flutter/scheduler/Ticker-class.html)
- [Flutter pumpAndSettle API](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html)
- [Dart Stopwatch API](https://api.dart.dev/dart-core/Stopwatch-class.html)
- [Dart SendPort API](https://api.dart.dev/dart-isolate/SendPort/send.html)
- [Dart ReceivePort API](https://api.dart.dev/dart-isolate/ReceivePort-class.html)

## Testing Details

Tests are organized by semantic boundary and use deterministic clocks, exact presentation identities, bounded Flutter frames, real cross-language fixtures, and complete platform regression gates.
The real acceptance fixture proves the requested timer and after-display behavior without any external event.

## Implementation Details

- Replace deadline inference with one complete public `advance_clock` and `flush` per consumed foreground frame grant.
- Separate `presentation_id` from renderer revision so no-diff lifecycle frames do not churn renderer state.
- Commit mounted-tree and handler candidates only after exact post-frame acknowledgment.
- Advance and flush inside each pump; on success acknowledgment, advance without flushing before presentation lifecycle so new relative timers use presentation time.
- Serialize all native calls and coalesce grants behind one presentation barrier in the runtime isolate.
- Recursively register one `scheduleFrameCallback` and guard every transient and post-frame callback by generation and token.
- Stop on hidden, paused, and detached states and catch up overdue work after resume.
- Introduce ABI 2.0, remove `next_wakeup_ns`, and keep renderer protocol 1.12.
- Reject failed presentations without lifecycle and recover with a non-reused full-snapshot revision.
- Change no upstream source, dependency revision, or private time-source implementation.

## Question

No implementation question remains after accepting the explicit foreground-vsync trade-off.
If zero foreground idle pumping is reinstated as a hard requirement, this plan becomes impossible under the simultaneous no-upstream-change and complete-semantics constraints.

---
