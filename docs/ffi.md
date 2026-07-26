# Native runtime boundary

## ABI surface

`bonsai_flutter_native.h` is the stable C boundary. It exposes protocol-version
queries and these runtime-level operations:

```c
bf_runtime *bf_runtime_create(const uint8_t *config, size_t config_length);
bf_status bf_runtime_step(
  bf_runtime *runtime,
  const uint8_t *input,
  size_t input_length,
  bf_output_buffer *output);
bf_status bf_runtime_frame_presented(
  bf_runtime *runtime,
  uint64_t revision,
  bf_output_buffer *output);
bf_status bf_runtime_get_last_error(
  bf_runtime *runtime,
  bf_output_buffer *output);
void bf_buffer_free(bf_runtime *runtime, const uint8_t *data);
void bf_runtime_destroy(bf_runtime *runtime);
```

`bf_status` is a fixed-width `int32_t`, not a C enum with
implementation-defined width. All public symbols have explicit default
visibility. No node- or widget-level operation crosses this boundary.

## Ownership

- Dart owns input memory and keeps it valid only for the duration of a call.
- The native runtime owns every non-null output pointer.
- Dart validates the pointer/length pair, caps it at 16 MiB, copies it into a
  Dart `Uint8List`, and calls `bf_buffer_free` in the same synchronous call.
- The native runtime tracks outstanding allocations. Destroying a runtime
  releases any allocation that its caller did not return.
- `bf_runtime` is opaque. Dart never retains an OCaml heap pointer.
- `NativeRuntime.dispose` is idempotent, and every later call is rejected.

The generated FFI declarations remain private to the native package. Public
Dart code uses `NativeRuntime`, `NativeOutput`, and `NativeStatus`.

## Isolate serialization

`RuntimeClient` spawns one dedicated isolate. That isolate creates and owns the
native runtime and performs every `step`, `frame_presented`, and `destroy`
operation. The UI isolate sends commands with monotonically increasing request
sequences. Byte payloads and responses use `TransferableTypedData`.

The worker consumes its `ReceivePort` with one `await for` loop. Calls for one
runtime therefore cannot overlap. Shutdown is an ordered command: earlier
requests finish first, native destroy runs once, and the UI side waits for an
acknowledgment before closing its response port.

`sendEventBatch` accepts the typed protocol model, encodes it on the UI side,
and transfers only its bytes. Event queuing is bounded before this point:
ordered events apply backpressure, while supported high-frequency state events
use explicit per-tag coalescing.

## Error boundary and current status

The ABI never throws across C. Each call returns `OK`, `RECOVERABLE_ERROR`, or
`FATAL_ERROR`; `bf_runtime_get_last_error` returns a native-owned diagnostic
buffer through the same ownership path.

The opt-in embedded route starts the OCaml runtime once with
`caml_startup_exn`, resolves four named callbacks, and releases the runtime
lock between calls:

```text
bonsai_flutter.create
bonsai_flutter.step
bonsai_flutter.frame_presented
bonsai_flutter.destroy
```

Foreign Dart threads register with the OCaml runtime, acquire its lock for one
callback, copy all returned bytes and diagnostics to C-owned memory, and
release the lock. No OCaml value survives a callback. C retains only a random
positive `int64` handle; the process-wide OCaml table maps that handle to a
`Driver.t`.

The create configuration is currently a registered entrypoint name. An
unknown entrypoint, unknown handle, malformed event batch, driver error, or
callback exception becomes status data rather than crossing the ABI as an
exception. The create API still returns only a null pointer on failure, so a
structured create diagnostic is a remaining ABI refinement.

The C boundary, generated bindings, owned-buffer wrapper, package build hook,
dedicated isolate, and embedded route have been exercised on the macOS arm64
host. A Flutter widget integration test clicks a real `ElevatedButton`, sends
the typed batch through the isolate and FFI, runs the real Bonsai driver, and
applies exactly one incremental `Count: 1` property update while preserving
unaffected Elements.

This establishes the vertical slice on the project OCaml 5.3.0 baseline. The
complete object is selected explicitly by application packages because it
contains their linked entrypoints. The default hook continues to build the
truthful fatal-status fallback when no application object is supplied.
