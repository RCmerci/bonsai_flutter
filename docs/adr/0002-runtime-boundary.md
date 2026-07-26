# ADR 0002: Pull-based runtime boundary

- Status: Accepted
- Date: 2026-07-25

## Context

Dart UI isolates must not be called from arbitrary OCaml or native threads.
Fine-grained widget FFI would multiply transitions, expose native lifetimes,
and make a frame only partially observable.

## Decision

Use one serialized, pull-based runtime per `bf_runtime`:

1. The Dart runtime isolate sends one typed input batch to
   `bf_runtime_step`.
2. OCaml schedules all effects, flushes Bonsai once, reconciles once, and
   returns zero or one atomic binary frame.
3. Dart validates and commits the frame in one `NodeStore` transaction.
4. Dart calls `bf_runtime_frame_presented` only after Flutter presents the
   revision.

The C ABI contains runtime lifecycle, batched step, frame acknowledgment,
buffer release, protocol inspection, resync, and error inspection operations.
It contains no per-widget functions.

All exceptions are caught before returning through C. Input buffers remain
Dart-owned for the duration of a call. Output buffers are native-owned until
released through `bf_buffer_free`; no Dart object retains an OCaml heap
pointer.

## Consequences

The UI isolate never blocks on a long Bonsai step. Backpressure and event
coalescing are explicit at the isolate boundary. Lifecycle is tied to actual
presentation, and frames cannot become partially visible.

Every operation for one runtime must be serialized. Multiple runtimes may
exist in one process, but they do not share node IDs, handler IDs, revisions,
or epochs.

