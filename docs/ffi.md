# Native runtime boundary

## Version contract

`bonsai_flutter_native.h` defines native ABI `2.0`. The renderer wire protocol
is `1.14`; ABI and protocol versions are queried and validated independently.
The Dart wrapper requires exact ABI and renderer-protocol matches before
runtime creation.

ABI v2 intentionally has no compatibility fallback for the removed
`bf_runtime_step` and `bf_runtime_frame_presented` operations.

## ABI surface

The stable runtime-driving operations are:

```c
bf_runtime *bf_runtime_create(
    const uint8_t *config,
    size_t config_length);

bf_status bf_runtime_pump(
    bf_runtime *runtime,
    int64_t monotonic_now_ns,
    const uint8_t *input,
    size_t input_length,
    bf_output_buffer *output);

bf_status bf_runtime_presentation_succeeded(
    bf_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int64_t monotonic_now_ns,
    bf_output_buffer *output);

bf_status bf_runtime_presentation_rejected(
    bf_runtime *runtime,
    uint64_t presentation_id,
    uint64_t revision,
    int32_t rejection_reason,
    bf_output_buffer *output);

bf_status bf_runtime_get_last_error(
    bf_runtime *runtime,
    bf_output_buffer *output);

void bf_buffer_free(bf_runtime *runtime, const uint8_t *data);
void bf_runtime_destroy(bf_runtime *runtime);
```

Version queries, outstanding-buffer diagnostics, and the declarations above
are the complete public C surface. Status and error codes use fixed-width
`int32_t` values, and every public symbol has explicit default visibility.
No node- or widget-level operation crosses this boundary.

## Output and presentation identity

Every call initializes the same `bf_output_buffer` layout:

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

Every successful logical pump returns a positive presentation ID, even when
`data == NULL` and `length == 0`. The presentation ID identifies the
lifecycle transaction; the renderer revision identifies wire state and
changes only when frame bytes are emitted. Success or rejection must echo the
exact unresolved pair.

A recoverable input error may still return a valid token and optional recovery
bytes. Fatal status terminates the ordered runtime session.

## Buffer ownership

- Dart owns input memory and keeps it valid only for the synchronous call.
- The native runtime owns every non-null output pointer.
- Dart validates the pointer/length pair, caps it at 16 MiB, copies it into a
  `Uint8List`, and calls `bf_buffer_free` before returning from the wrapper.
- The same ownership rule applies to success, recoverable, fatal, and
  diagnostic outputs.
- The native runtime tracks outstanding allocations; destroy releases any
  allocation its caller did not return.
- `bf_runtime` is opaque. Dart never retains an OCaml heap pointer.
- `NativeRuntime.dispose` is idempotent, and every later operation is
  rejected.

Generated FFI declarations remain private to the native package. Public Dart
code uses `NativeRuntime`, `NativeOutput`, `NativeStatus`, and typed rejection
reasons.

## Ordered isolate session

`RuntimeClient` spawns one dedicated isolate that creates and owns the native
runtime. UI-to-worker commands form one ordered stream of visibility changes,
vsync grants, exact presentation results, debug barriers, and disposal.
Worker-to-UI updates form one ordered stream of readiness, `CycleReady`, fatal
diagnostics, debug snapshots, and disposal completion.

The worker consumes one `ReceivePort` sequentially, so native calls cannot
overlap. Grants coalesce while a presentation is unresolved. Shutdown is an
ordered exact-once command: earlier work finishes first, native destroy runs
once, and both sides close their ports and update streams once.

Event bytes are prepared by the bounded UI-side queue. Ordered events apply
backpressure; supported high-frequency state events coalesce only by their
explicit node, handler, and tag identity. The prepared prefix is committed
only after synchronous presentation handoff succeeds.

The Dart isolate above is the **Dart runtime coordinator isolate**. It is not
the OCaml Worker Domain. It owns the singleton coordinator lease and serializes
FFI calls, but every such call registers the foreign thread and enters OCaml
domain 0 through the unchanged ABI.

The **OCaml Worker Domain** is created and managed inside OCaml. Domain 0 sends
it typed immutable requests over a bounded FIFO and receives guaranteed
correlated responses plus latest-wins push topics. This traffic never crosses
FFI and adds no C export, Dart isolate command, or renderer-protocol command.
SQLite handles and worker mutable state never appear in a native output buffer
or cross to Dart.

## OCaml callback bridge

The embedded route starts OCaml once with `caml_startup_exn` and resolves five
named callbacks:

```text
bonsai_flutter.create
bonsai_flutter.pump
bonsai_flutter.presentation_succeeded
bonsai_flutter.presentation_rejected
bonsai_flutter.destroy
```

Foreign Dart threads register with the OCaml runtime, acquire its lock for one
callback, copy all returned bytes and diagnostics into C-owned memory, and
release the lock. No OCaml value survives a callback. C retains only a random
positive `int64` handle; the process-wide OCaml table maps it to a `Driver.t`.

The ABI never throws across C. Unknown entrypoints or handles, invalid clocks,
malformed event batches, presentation mismatches, driver failures, and OCaml
exceptions become stable status and error-code data.

The complete-object symbol audit requires every ABI v2 operation and rejects
the removed v1 runtime-driving symbols. The generated Dart binding check
guards the C/Dart struct layout and declarations.
