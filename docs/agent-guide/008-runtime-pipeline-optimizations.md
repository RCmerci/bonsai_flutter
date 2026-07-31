# Runtime Pipeline Optimization Design

Status: proposed

Recorded on 2026-07-31.

## Summary

This document refines five optimization opportunities in the OCaml-to-Flutter
runtime pipeline:

1. Do not construct trace messages when no trace sink is installed.
2. Encode an OCaml frame once and patch fixed-width runtime statistics in
   place.
3. Share one Dart `ByteData` view across `_Reader` instances and decode strings
   directly from byte ranges.
4. Add leaf and unkeyed fast paths to `validate_unique_keys`.
5. Derive handler frames with a persistent map and handler deltas instead of
   rebuilding or copying a complete hash table for every revision.

The first four changes remove avoidable work while preserving the current data
model. The fifth change alters the handler-frame representation and
reconciliation contract, so it requires a more cautious rollout.

The scenario benchmark shows that Flutter build, layout, and paint dominate
the 1,000-item render and reverse scenarios. These five changes therefore are
not expected to eliminate the end-to-end Flutter presentation cost. Their
primary goals are to reduce OCaml and Dart CPU time, temporary allocation, GC
pressure, and tail latency inside the runtime pipeline.

## Baseline

The performance investigation that motivated this design produced the
following relevant median values:

| Scenario | OCaml reconcile | OCaml frame encode | Dart frame decode | FFI and OCaml callback |
| --- | ---: | ---: | ---: | ---: |
| Click button | 6.912 us | 2.048 us | 25 us | 36 us |
| Render 1,000 keyed items | 119.808 us | 165.888 us | 308 us | 3,564 us |
| Reverse 1,000 keyed items | 244.224 us | 20.992 us | 47 us | 632 us |
| Update one of 1,000 | 298.240 us | 2.048 us | 32 us | 639 us |
| Remove 500 of 1,000 | 169.984 us | 45.824 us | 66 us | 1,691 us |

`OCaml frame encode` currently measures only the first of two complete encode
passes. The actual serialization cost is therefore larger than that column
reports.

For the 1,000-item initial render, the measured OCaml substeps do not explain
most of the 3.564 ms FFI callback. Eager trace construction and the unmeasured
second encode are plausible contributors, but additional instrumentation is
required before assigning the entire remainder to either one.

## Goals

- Avoid work whose result cannot be observed.
- Preserve the binary protocol and all existing Dart/OCaml fixtures.
- Reduce allocation in hot frame production and decoding paths.
- Preserve presentation atomicity and handler revision safety.
- Make unchanged or sparsely changed handler sets proportional to the change
  size instead of the total handler count.
- Add measurements that include all work introduced by each optimized path.

## Non-goals

- Changing Flutter widget build, layout, paint, or raster behavior.
- Changing isolate scheduling or message-delivery policy.
- Compressing frame payloads or changing the wire format.
- Replacing every binary writer allocation in the OCaml codec.
- Eliminating per-operation Dart `_Reader` objects in the first iteration.
- Replacing the small outer `revision -> handler frame` registry.

## Correctness invariants

Every implementation must preserve the following behavior:

- A frame is not displayed until its presentation acknowledgement succeeds.
- A rejected candidate must not change the displayed tree, displayed revision,
  or installed handler frames.
- The current displayed handler frame and the bounded previous revision remain
  independently queryable during the existing grace period.
- A duplicate-key failure occurs before node or handler IDs are consumed.
- Handler IDs remain monotonic and unique within a runtime epoch.
- Existing protocol limits, validation errors, and trailing-byte checks remain
  unchanged.
- Trace sink exceptions remain isolated from runtime execution.

## 1. Lazy trace construction

### Current behavior

`ocaml/runtime/driver.ml` stores:

```ocaml
trace : (string -> unit) option
```

The current `trace` function ignores a message when the sink is `None`.
However, OCaml evaluates the message argument before calling `trace`. Expensive
call sites therefore still construct their complete strings:

- `trace_widget_diff` calls `Ui.Debug.dump_tree` for a full snapshot.
- Incremental widget tracing searches mounted trees and renders changed
  widgets.
- Outbound frame tracing scans every operation to build
  `operation_summary`.
- Other inbound and presentation messages allocate `Printf.sprintf` results
  even when tracing is disabled.

The scenario benchmark application does not install a trace sink, so none of
this output is observable in the measured configuration.

### Proposed design

Add a lazy trace helper:

```ocaml
let trace_lazy t make_message =
  match t.trace with
  | None -> ()
  | Some sink ->
    (try sink (make_message ()) with
     | _ -> ())
;;
```

Convert expensive trace sites first:

```ocaml
trace_lazy t (fun () ->
  let diff = build_widget_diff ... in
  Printf.sprintf
    "[widget-diff] targetRevision=%Ld kind=%s\n%s"
    target_revision
    (frame_kind_name frame_kind)
    diff)
```

The widget-diff guard should test both conditions before building the thunk:

```ocaml
match t.trace with
| None -> ()
| Some _ when Runtime.Frame_patch.is_empty frame_patch -> ()
| Some _ -> trace_lazy t (fun () -> ...)
```

An explicit `match t.trace` at the call site is also acceptable for the most
frequent paths if profiling shows that closure allocation is measurable. The
required semantic property is that no tree walk, operation scan, widget dump,
or formatted string is created when the sink is absent.

Cheap, uncommon trace calls may continue to use the eager helper initially.
An audit should later classify every call site as:

- constant or cheap eager message;
- expensive message that must use `trace_lazy`; or
- structured trace data that should be generated only by the sink.

### Complexity and allocation

| Case | Current | Proposed |
| --- | --- | --- |
| No sink, full snapshot trace | `O(nodes + output bytes)` | `O(1)` |
| No sink, operation summary | `O(operations)` | `O(1)` |
| Sink installed | Unchanged asymptotically | Unchanged asymptotically |

### Tests

- A thunk with a counter is not evaluated when the sink is absent.
- A thunk is evaluated exactly once when the sink is installed.
- The sink receives the existing message content.
- A sink exception remains swallowed.
- An empty frame patch does not build a widget diff.
- Full and incremental trace golden tests remain unchanged.

### Measurement

Add counters or scoped timers for widget-diff construction and operation
summary construction. Rerun the five scenario benchmarks with:

- no trace sink;
- a sink that discards the completed string; and
- the current development sink, if one exists.

The no-sink result must report zero expensive trace constructions. The FFI
callback reduction is the useful scenario-level result; it must not be inferred
solely from the trace microbenchmark.

### Risk

Low. The main risk is accidentally changing trace formatting or exception
isolation.

## 2. Single-pass OCaml encode with fixed-width backpatching

### Current behavior

`produce_candidate` in `ocaml/runtime/driver.ml` performs these steps:

1. Build runtime stats with `encode_ns = 0` and `patch_bytes = 0`.
2. Encode the complete frame.
3. Measure the first encode and read the provisional byte length.
4. Rebuild runtime stats with those values.
5. Encode the complete frame a second time.

Only step 2 is recorded as `encode_ns`. The second traversal and its
allocations are real runtime work but are not included in that statistic.

The two fields that require backpatching are fixed-width in
`ocaml/protocol/binary_codec.ml`:

- `encode_ns`: little-endian `u64`;
- `patch_bytes`: little-endian `u32`.

Updating their values cannot change the frame length.

### Proposed design

Keep the existing general `Binary_codec.encode` API. Add a runtime-specific
internal entry point that returns the encoded bytes and validated patch
locations:

```ocaml
module Runtime_encoded_frame : sig
  type stats_offsets =
    { encode_ns : int
    ; patch_bytes : int
    }

  type t =
    { bytes : bytes
    ; stats_offsets : stats_offsets
    }
end

val encode_runtime_frame :
  Wire_frame.t -> (Runtime_encoded_frame.t, error) result

val patch_runtime_stats :
  Runtime_encoded_frame.t ->
  encode_ns:int64 ->
  patch_bytes:int ->
  (unit, error) result
```

The writer records the payload-relative offsets at the exact points where it
writes the two runtime-stat fields. After the header and payload are joined,
the codec translates them to output-relative offsets. The driver never
calculates offsets from magic constants.

The driver flow becomes:

```ocaml
let encode_started = now_ns () in
match Binary_codec.encode_runtime_frame (wire_frame zero_stats) with
| Error error -> Error (Codec_error error)
| Ok encoded ->
  let encode_ns = elapsed_ns encode_started in
  let patch_bytes = Bytes.length encoded.bytes in
  (match
     Binary_codec.patch_runtime_stats encoded ~encode_ns ~patch_bytes
   with
   | Error error -> Error (Codec_error error)
   | Ok () -> ...)
```

`encode_ns` should mean the duration of the one complete serialization pass.
The constant-time backpatch itself is excluded by definition. If total frame
production time is also required, it should be measured under a separate name
instead of making `encode_ns` recursively include the time needed to write
itself.

### Codec constraints

- `encode_runtime_frame` must require exactly one runtime-stats operation.
- Both offsets must be captured by the writer that emits the fields.
- Patch helpers must check bounds and encode in little-endian order.
- Bytes must not be exposed to the driver if offset discovery fails.
- The runtime-stats operation envelope length remains unchanged.
- The final decoded stats must contain the measured encode duration and exact
  final frame length.
- The ordinary `encode` path remains available for fixtures and callers that
  do not need backpatching.

### Complexity and allocation

For a frame of `B` bytes:

| Metric | Current | Proposed |
| --- | --- | --- |
| Complete serialization passes | 2 | 1 |
| Serialization work | Approximately `2 * O(B)` | `O(B) + O(1)` |
| Complete output allocations | 2 | 1 |
| Stats update | Re-encode entire frame | Patch 12 fixed-width bytes |

### Tests

- Decode a backpatched frame and assert both updated statistics.
- Assert `patch_bytes = Bytes.length bytes`.
- After normalizing the two patched fields, assert all remaining bytes match
  the ordinary encoder output.
- Run the Dart/OCaml cross-language golden fixtures.
- Test maximum valid `u32` and positive `int64` values.
- Reject a missing or duplicate runtime-stats operation.
- Reject corrupted or out-of-bounds patch locations.
- Verify full-snapshot, incremental, host-operation, and empty-patch variants.

### Measurement

The benchmark must distinguish:

- one-pass serialization time;
- constant-time backpatch time; and
- total codec call time.

The acceptance criterion is exactly one full encode call per emitted frame and
no protocol fixture change. A full-frame microbenchmark should demonstrate a
material reduction in CPU and allocated bytes; a tentative target is at least
a 35% reduction in total frame encoding time for the 1,000-node full frame.

### Risk

Medium. Incorrect offsets can silently corrupt a frame. Offset ownership must
remain inside the codec, with bounds checks and cross-language decode tests.

## 3. Shared Dart `ByteData` and range-based string decoding

### Current behavior

`_Reader` in
`flutter/packages/bonsai_flutter/lib/src/protocol/binary_codec.dart` stores a
`Uint8List`, position, and limit. Every `uint16`, `uint32`, `uint64`, and
`finiteFloat64` read creates a new `ByteData.sublistView`.

`string()` currently:

1. reads the byte length;
2. creates a `Uint8List.sublistView` through `bytes(length)`;
3. passes that temporary view to UTF-8 decoding.

Every operation body also creates a child `_Reader`, although it points into
the same `Uint8List`.

### Proposed design

Create one `ByteData` view in the root reader and share it with every child:

```dart
final class _Reader {
  _Reader.root(Uint8List bytes)
    : _bytes = bytes,
      _data = ByteData.sublistView(bytes),
      _position = 0,
      _limit = bytes.length;

  _Reader._slice(
    this._bytes,
    this._data,
    this._position,
    this._limit,
  );

  final Uint8List _bytes;
  final ByteData _data;
  int _position;
  final int _limit;
}
```

Primitive reads use absolute indexes in the shared `ByteData`:

```dart
int uint32() {
  _require(4);
  final result = _data.getUint32(_position, Endian.little);
  _position += 4;
  return result;
}
```

`subReader` shares both backing views:

```dart
_Reader subReader(int length) {
  _require(length);
  final result = _Reader._slice(
    _bytes,
    _data,
    _position,
    _position + length,
  );
  _position += length;
  return result;
}
```

Decode strings from a range without first creating a `Uint8List` view:

```dart
String string() {
  final length = uint32();
  if (length > ProtocolLimits.maxStringBytes) {
    _fail(ProtocolErrorCode.stringTooLarge, 'String is $length bytes');
  }
  _require(length);
  final start = _position;
  final end = start + length;
  _position = end;
  try {
    return const Utf8Decoder(allowMalformed: false)
        .convert(_bytes, start, end);
  } on FormatException {
    _fail(ProtocolErrorCode.invalidUtf8, 'String is not valid UTF-8');
  }
}
```

`bytes(length)` should continue returning `Uint8List.sublistView` for actual
binary values. That API intentionally exposes a zero-copy byte range and is
not equivalent to string decoding.

### Offset correctness

The root must use `ByteData.sublistView(bytes)`, not
`ByteData.view(bytes.buffer)` without an offset. A caller may provide a
`Uint8List` that is itself a view with a non-zero offset in its underlying
buffer. With `sublistView`, reader position zero correctly maps to the first
byte visible through the supplied list.

All child positions and limits remain relative to that same visible root
range. Existing `_require` and `requireDone` checks remain the authority for
body boundaries.

### Complexity and allocation

Asymptotic decode complexity remains `O(B + P)`, where `B` is decoded bytes
and `P` is the number of operations. The optimization removes:

- one `ByteData` view per multi-byte primitive;
- one temporary `Uint8List` view per decoded string.

One small `_Reader` object per operation body remains in this phase. Removing
it would require a scoped-limit stack or manual boundary management and should
be evaluated separately.

### Tests

- Decode a frame supplied as a non-zero-offset `Uint8List.sublistView`.
- Cover every multi-byte primitive at unaligned positions.
- Preserve truncated-input behavior for every primitive and string.
- Preserve invalid UTF-8 and oversized-string errors.
- Preserve operation trailing-byte checks.
- Verify nested child readers cannot read beyond their own limits.
- Verify `bytes(length)` remains a view with the existing aliasing behavior.
- Run all Dart/OCaml binary fixtures.

### Measurement

Run the existing 1,000-node full-frame and incremental decode benchmarks in
profile or AOT mode after warm-up. Record median, p95, and allocated bytes or
GC counts when the Dart tooling makes those metrics available.

A tentative success target is at least a 15% reduction in full-frame Dart
decode time with no small-frame regression outside normal benchmark noise.
Allocation evidence is more important than a single debug/JIT timing result.

### Risk

Low to medium. The main hazards are incorrect handling of a non-zero backing
buffer offset and accidentally weakening operation-body limits.

## 4. `validate_unique_keys` leaf and unkeyed fast paths

### Current behavior

`validate_unique_keys` in `ocaml/runtime/reconciler.ml` creates a `Key_table`
for every widget node, including:

- leaves with no children;
- parents with one child, where a sibling duplicate is impossible; and
- parents whose children are all unkeyed.

It still must traverse every descendant because duplicate keys may exist at
any nested parent.

### Proposed design

Use child-count fast paths and allocate a key table only when it is needed:

```ocaml
let rec validate widget =
  let view = Widget.Private.view widget in
  match Array.length view.children with
  | 0 -> Ok ()
  | 1 -> validate view.children.(0).widget
  | _ -> validate_children view
```

For two or more children, initialize the table lazily on the first keyed
child:

```ocaml
let validate_children view =
  let keys = ref None in
  let observe_key key =
    match !keys with
    | None ->
      let table = Key_table.create (Array.length view.children) in
      Key_table.add table key ();
      keys := Some table;
      Ok ()
    | Some table when Key_table.mem table key ->
      Error
        (Runtime_error.Duplicate_key
           { parent_kind = Widget.Private.Kind.to_string view.kind; key })
    | Some table ->
      Key_table.add table key ();
      Ok ()
  in
  ...
```

The traversal order remains the current left-to-right, depth-first order.
Validation must still finish before any node or handler ID allocation starts.

The one-child path must recurse into the child. Returning `Ok ()` immediately
would skip nested duplicate validation and is incorrect.

### Complexity and allocation

Traversal remains `O(N)`. Key lookup remains expected `O(K)` across all keyed
siblings. The number of allocated key tables changes from approximately one
per node to one per parent with at least two children and at least one keyed
child.

For a list of 1,000 leaf items, the root still allocates one table, but the
1,000 leaves allocate none.

### Tests

- A leaf succeeds without allocating a key table.
- A chain of single-child nodes validates all descendants.
- A nested duplicate in a single-child ancestor is still rejected.
- A multi-child all-unkeyed parent allocates no table.
- Mixed keyed and unkeyed siblings preserve duplicate detection.
- The first reported duplicate and error message remain deterministic.
- Duplicate-key failure still consumes no node or handler IDs.
- Property tests compare the optimized result with a simple reference
  validator over generated trees.

Allocation-specific assertions should use a small injectable table factory or
a private test counter rather than relying on process-wide GC statistics.

### Measurement

Add a validation-only microbenchmark for:

- 1,000 keyed leaf children;
- 1,000 unkeyed leaf children;
- a deep single-child tree; and
- nested keyed parents.

Also rerun reconcile benchmarks because the user-visible metric is total
reconciliation time, not validation in isolation.

### Risk

Low. The critical mistake to avoid is skipping descendant validation in the
zero- or one-key cases.

## 5. Persistent handler map with incremental deltas

### Current behavior

`Handler_registry.Frame.t` currently stores:

```ocaml
{ revision : int64
; entries : (Handler_id.t, entry) Hashtbl.t
}
```

After every successful reconcile candidate,
`ocaml/runtime/reconciler.ml` traverses the complete mounted tree, collects all
handler entries into a list, and builds a new hash table. A sparse UI update
therefore performs `O(H)` work and allocates a new table even when no handler
changed.

Copying the previous hash table and mutating the copy would still be `O(H)` and
would duplicate its complete backing storage. It also makes revision sharing
implicit and fragile.

The proposed representation uses an immutable persistent map. Each update
copies only the balanced-tree paths affected by added or removed handler IDs;
all unaffected structure is shared safely between revision frames.

### Data structure choice

Use the OCaml standard library:

```ocaml
module Handler_map = Map.Make (struct
    type t = Handler_id.t

    let compare = Handler_id.compare
  end)
```

The first implementation should prefer `Map.Make` because it requires no new
dependency and provides immutable structural sharing. A HAMT may be evaluated
later if event lookup benchmarks show that balanced-tree lookup is too
expensive.

Change the private frame representation:

```ocaml
module Frame = struct
  type entries = entry Handler_map.t

  type t =
    { revision : int64
    ; entries : entries
    }

  let revision t = t.revision
  let find t handler_id = Handler_map.find_opt handler_id t.entries
end
```

The outer `Handler_registry.frames : (int64, Frame.t) Hashtbl.t` should remain
unchanged. It contains only the currently displayed revision and the bounded
previous revision, so it is not the source of per-handler copying.

### Reconciliation delta

Persistent storage alone is insufficient if reconciliation still traverses
the full tree to rebuild a map. The reconciler must record handler changes
while it is already mounting, reconciling, and dropping nodes:

```ocaml
type handler_delta =
  { additions : Handler_registry.Frame.entry list
  ; removals : Handler_id.t list
  }
```

Delta production follows the mounted-tree lifecycle:

| Reconcile action | Handler delta |
| --- | --- |
| Mount a binding | Add its new handler entry |
| Reuse the same physical handler and binding | No change |
| Replace a handler for the same event tag | Remove old ID, add new entry |
| Remove an old event tag | Remove old ID |
| Add a new event tag | Add new entry |
| Reorder or move a reused keyed node | No change |
| Drop a subtree | Remove every binding in the dropped subtree |
| Full snapshot | Add every mounted binding to an empty base |

`queue_drop` already walks a dropped subtree. It should record handler removals
during that same traversal instead of requiring a second full-tree pass.
`mount` and `reconcile_bindings` already have the node ID, event tag, handler
ID, and handler value required to record additions.

The target map is derived by folding only the delta:

```ocaml
let derive_entries ~base ~removals ~additions =
  let without_removed =
    List.fold_left
      (fun entries handler_id -> Handler_map.remove handler_id entries)
      base
      removals
  in
  List.fold_left
    (fun entries entry ->
      if Handler_map.mem entry.handler_id entries
      then invalid_arg "Handler_registry.Frame: duplicate handler ID";
      Handler_map.add entry.handler_id entry entries)
    without_removed
    additions
```

The concrete private API can hide the map and delta representation:

```ocaml
module Frame.Private : sig
  val empty : revision:int64 -> t

  val derive :
    revision:int64 ->
    base:t ->
    removals:Handler_id.t list ->
    additions:entry list ->
    t
end
```

`derive` creates a new frame record even when the delta is empty, because the
revision changes. In that case, the new frame's `entries` field is physically
the same persistent map root as the base frame.

### Selecting the base frame

The base must correspond to `Driver.displayed_revision`.

Current presentation semantics are:

1. `produce_candidate` reconciles against `displayed_tree`.
2. The candidate tree and candidate handler frame are stored in
   `pending_presentation`.
3. `presentation_succeeded` installs the handler frame and advances
   `displayed_revision`.
4. `presentation_rejected` discards the candidate and forces the next
   reconciliation to produce a full snapshot.

Therefore, the driver should explicitly retain:

```ocaml
mutable displayed_handler_frame : Handler_registry.Frame.t option
```

It passes this frame to incremental reconciliation as the persistent-map base.
It updates the field only after the candidate handler frame has been installed
and marked displayed successfully. `displayed_tree`,
`displayed_handler_frame`, and `displayed_revision` must then advance as one
commit step. Candidate validation and registry installation should occur
before mutating those three driver fields so an internal installation failure
cannot leave them inconsistent. A rejected candidate never becomes a base.

For a forced full snapshot, reconciliation uses an empty map even if a
displayed frame exists. This keeps the full-snapshot output independent of
stale mounted-tree or handler state.

An alternative is storing the map inside `Mounted_tree.t`, but that mixes
event revision state with renderer tree state and makes handler frame
retention less explicit. Driver ownership is preferred because the driver
already controls presentation commit and revision retirement.

### Immutable revision safety

Persistent maps make the current and previous frames safe to retain
simultaneously:

- Deriving a candidate never mutates the displayed frame.
- Installing a candidate stores a new immutable root.
- The previous revision continues to find its original handler entries during
  the grace period.
- Retiring a revision drops only that frame's root reference.
- The GC reclaims nodes that are not shared by any retained revision.

Handler entry values are also treated as immutable. Reusing a binding reuses
the existing entry. Replacing a handler creates a new handler ID and entry, as
it does today.

### Complexity and memory

Let:

- `H` be the total number of handlers;
- `A` be added handlers;
- `R` be removed handlers.

| Operation | Current hash-table frame | Persistent-map delta |
| --- | --- | --- |
| Unchanged handler set | `O(H)` traversal and rebuild | `O(1)` map reuse |
| Sparse changes | `O(H)` traversal and rebuild | `O((A + R) log H)` |
| Full snapshot | Expected `O(H)` | `O(H log H)` initially |
| Event lookup | Expected `O(1)` | `O(log H)` |
| New frame storage | `O(H)` | `O((A + R) log H)` shared paths |

The full-snapshot build and event lookup tradeoffs are explicit. Most frames
are expected to be incremental, while event lookup remains small compared
with Flutter presentation work, but this assumption must be validated by
benchmarks.

If `Map.Make` lookup or full-build cost is unacceptable, evaluate a persistent
HAMT behind the same `Frame.find` and `Frame.Private.derive` API. Do not return
to complete mutable hash-table copying.

### Delta validation

The private derivation path should reject internal inconsistencies:

- an addition whose handler ID already exists after removals;
- a removal whose ID is absent, unless the implementation explicitly defines
  repeated removal as idempotent;
- duplicate additions or removals within one delta;
- a base frame whose revision differs from the reconciliation base revision.

Failing fast is preferable to installing a frame that disagrees with its
mounted tree. These are runtime implementation errors, not user protocol
errors.

Handler IDs are monotonic, so a valid addition should never collide with an
unchanged entry. A changed binding removes its old ID and adds a newly
allocated ID.

### API migration

1. Add `Frame.find` and route event validation through it instead of accessing
   `frame.entries` directly.
2. Introduce `Handler_map` privately while keeping `Frame.Private.create` for
   existing tests and full-frame construction.
3. Add `Frame.Private.derive`.
4. Add `displayed_handler_frame` to the driver and pass the base frame into
   reconciliation.
5. Produce additions and removals during reconciliation.
6. Remove the final `collect_handlers` full-tree traversal.
7. Retain `Frame.Private.create` only if it remains useful for fixtures;
   otherwise migrate fixtures to `empty` plus `derive`.

This sequence allows lookup behavior and persistent storage to be tested
before changing reconciliation.

### Tests

Unit tests:

- `Frame.find` returns the expected entry.
- Empty delta creates a new revision whose map root is physically shared.
- One addition or removal does not mutate the base frame.
- Duplicate delta entries are rejected.
- Full construction and incremental derivation produce equivalent lookup
  results.

Reconciler tests:

- A property-only update produces an empty handler delta.
- Reversing keyed nodes produces an empty handler delta.
- Replacing one handler removes the old ID and adds the new ID.
- Adding or removing an event tag produces the correct delta.
- Dropping a subtree removes every handler in that subtree.
- Remounting creates fresh handler IDs.

Driver and event tests:

- The previous displayed revision still dispatches its old handler during the
  grace period.
- The new revision dispatches the replacement handler.
- A retired revision is rejected as stale.
- A rejected candidate is never installed and never becomes the next base.
- A no-frame pump does not install a redundant handler frame.
- Runtime epoch, node ID, event tag, duplicate sequence, and out-of-order
  sequence checks remain unchanged.
- Presentation failure paths do not leave
  `displayed_tree`, `displayed_revision`, and
  `displayed_handler_frame` inconsistent.

### Measurement

Add OCaml microbenchmarks at `H = 1,000` and `H = 10,000` for:

- initial full construction;
- zero-change derivation;
- one addition and one removal;
- ten additions and ten removals;
- random handler lookup;
- retained memory for two adjacent revisions.

Record time and `Gc.allocated_bytes`. The important acceptance properties are:

- zero-change derivation is `O(1)` and reuses the map root;
- sparse-change allocation does not grow linearly with `H`;
- revision grace-period behavior remains correct;
- event lookup regression is bounded and documented.

As a provisional guardrail, random lookup at 10,000 handlers should not regress
by more than 2x. If it does, preserve the delta API and evaluate a persistent
HAMT before merging the representation change.

Rerun the scenario benchmark with handler-heavy variants. The existing list
scenarios may contain too few event bindings to demonstrate this optimization
clearly.

### Risk

Medium to high. The data structure is straightforward, but a base-frame or
delta-lifecycle mistake could dispatch a stale handler or reject a valid
event. This optimization should be implemented after the four local changes
and guarded by revision-level tests.

## Rollout order

The recommended implementation order is:

1. Lazy trace construction.
2. `validate_unique_keys` fast paths.
3. Shared Dart `ByteData` and range string decoding.
4. Single-pass OCaml encode and backpatching.
5. Persistent handler map and incremental deltas.

This order starts with isolated, low-risk allocation removal and leaves the
revision-sensitive change until the benchmark and correctness harnesses are in
place.

Each optimization should land independently with:

- focused unit tests;
- relevant microbenchmarks;
- the five scenario benchmark results before and after;
- allocated-byte or allocation-count evidence where available; and
- no unexplained protocol fixture changes.

## Aggregate acceptance criteria

- All OCaml, Dart, native bridge, and integration tests pass.
- Dart and OCaml decode the same binary fixtures as before.
- No expensive trace payload is constructed without a sink.
- Exactly one complete OCaml encode pass occurs per emitted frame.
- Dart primitive reads share one root `ByteData`.
- Leaf and all-unkeyed validation paths allocate no key table.
- A zero-handler-change frame does not traverse the mounted tree to rebuild
  handler metadata.
- Candidate rejection and previous-revision event dispatch retain their
  current semantics.
- Any benchmark regression is reported rather than hidden by an aggregate
  end-to-end number.

## Open questions

- Should a new `frame_encode_total_ns` statistic be added, or is an external
  scoped timer sufficient to expose backpatch overhead?
- Does the trace audit include development-only widget dumps outside
  `Driver`, or should that be a follow-up?
- Is a 2x lookup guardrail acceptable for the initial `Map.Make`
  implementation, or must event lookup remain closer to current hash-table
  performance?
- Should full-snapshot persistent-map construction use a bulk builder if
  `O(H log H)` becomes visible for handler-heavy trees?
- Should handler delta lists become arrays or transient builders after the
  persistent representation is proven correct?
