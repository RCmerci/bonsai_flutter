# Architecture

## Mission

`bonsai_flutter` is a native Flutter backend for Bonsai. OCaml is the source of
truth for the application. Dart is a transactional renderer and host adapter,
not a second application runtime.

The framework deliberately does not share `bonsai_web`'s view type. It has no
DOM, HTML, CSS, JavaScript, WebView, Remote Flutter Widgets, or JSON production
rendering path.

## End-to-end pipeline

```text
Bonsai computation
        |
        v
immutable Widget.t
        |
        v
OCaml reconciler -----> mounted tree + handler frame
        |
        v
versioned binary frame patch
        |
        v
batched C ABI call
        |
        v
Dart runtime isolate
        |
        v
Flutter UI isolate
        |
        v
NodeStore transaction
        |
        v
NodeHost / WidgetRegistry
        |
        v
Flutter Widget / Element / RenderObject tree
```

Events travel in the opposite direction as typed batches. Dart supplies a
node ID, event tag, handler ID, displayed revision, runtime epoch, event
sequence, and typed payload. OCaml resolves the handler, schedules its Bonsai
effect, flushes once, reconciles once, and returns at most one atomic frame.
OCaml never calls back into a Dart UI isolate.

## Consumer build boundary

Every example and the aggregate integration harness is an independent consumer
workspace with its own `dune-project`, locked opam package, and
`bonsai-flutter.sexp`. Native-backed Flutter commands run through
`bonsai-flutter build`, `run`, or `exec`; the tool owns the platform/profile
artifact selection and stages complete objects only below the consumer's
`_build/bonsai-flutter` tree.

The consumer owns its pubspec metadata and non-framework dependencies. The
tool owns only the marked local-package and native-hook regions. Managed hosts
also give the tool ownership of generated `lib/main.dart` and widget tests;
custom hosts retain their Dart entrypoint and tests. Profile injection is
serialized, scoped to the native-hook region, and restores the original
pubspec bytes when the child command finishes or is interrupted.

## Three distinct trees

1. The logical UI tree is an immutable OCaml `Widget.t`. It contains typed
   properties and event closures but no renderer resources.
2. The mounted tree is owned by the OCaml runtime. It assigns monotonic node
   IDs and handler IDs, retains source widget identity, and is the basis of
   incremental reconciliation.
3. The Flutter framework tree is built mechanically from the committed
   `NodeStore`. Flutter owns `Element` and `RenderObject` lifecycles.

No layer reaches through another layer to manipulate its private tree.

## Shared ID contract

`bonsai_flutter.spec` is a virtual library that groups identity types by
ownership: `Runtime`, `Worker`, `Ui`, `Text_input`, `Navigation`, `Input`,
`Host`, `Native_widget`, `Application`, `Protocol`, and `Ffi`.
`bonsai_flutter.spec_impl` provides the production implementation.

Every primitive-backed ID is exposed as a private type. Code must use the
category-specific constructor, accessor, comparison, and monotonic helpers
instead of treating IDs as interchangeable `int64`, `int`, or `string`
values. Primitive conversion is explicit at wire, ABI, persistence, and
diagnostic boundaries. The runtime representation and protocol bytes remain
unchanged.

The native ABI error code is an `Ffi.error_code`, not a
`Protocol.runtime_error`: the ABI defines codes 0 through 15, while the
generated protocol runtime-error discriminants currently define codes 1
through 12.

## Ownership

OCaml owns:

- application state and Bonsai computations;
- complete declarative view structure;
- keys, navigation state, menus, selection truth, and command mapping;
- event handlers and host-effect orchestration;
- mounted identity, reconciliation, and incremental patches;
- semantic animation intent.

Flutter owns:

- widget, element, and render-object construction;
- layout, paint, hit testing, gesture-arena state, and accessibility mapping;
- IME connections and renderer-local controllers;
- animation interpolation, decoded resources, and platform plugins;
- atomic application of validated OCaml frames.

Renderer resources are keyed by `(runtime_epoch, node_id)`. A compatible
mounted update preserves them; a kind replacement, node drop, epoch reset, or
runtime shutdown disposes them.

## Semantic animation

`Animation.create` defines a stable animation ID, duration in milliseconds,
and a typed curve. `Widget.animated_opacity` publishes that intent, its target
opacity, and an OCaml completion handler as an `AnimatedOpacity` logical node.
The binary frame carries only the target and semantic intent.

Flutter retains one `AnimationController` for the mounted node in
`RendererResourceStore`. A compatible incremental property update interpolates
locally and rebuilds only the opacity host; no per-frame value crosses FFI.
When the controller reaches its target, Flutter sends one
`AnimationCompleted(animation_id)` event through the normal revision-scoped
handler path. Initial mount establishes the starting value without producing a
false completion. Reduced-motion or zero-duration updates jump to the target
and still report semantic completion. Replacement, node drop, full reset, and
runtime shutdown cancel the controller and dispose its ticker.

## Library boundaries

The OCaml libraries are deliberately split:

```text
bonsai_flutter.ui
        |
        v
bonsai_flutter.protocol
        |
        v
bonsai_flutter.runtime
        |
        v
bonsai_flutter.ffi

bonsai_flutter      public facade
bonsai_flutter_test headless test surface
```

`bonsai_flutter.ui` has no FFI, Dart, Flutter, DOM, or packaging dependency.
`bonsai_flutter.protocol` owns generated wire types and codecs.
`bonsai_flutter.runtime` owns reconciliation, handlers, the Bonsai adapter,
lifecycle, host effects, and instrumentation. `bonsai_flutter.ffi` alone owns
C ABI details.

All version-sensitive Bonsai integration is confined to
`Bonsai_runtime_adapter`. Public modules expose `Bonsai.t` and
`Bonsai.Effect.t` where appropriate, but never `Bonsai.Private` or Dart types.

## Runtime model

### Singleton worker topology

The runtime uses the four-stage topology accepted in ADR 0007:

```text
Flutter UI isolate
  -> Dart runtime coordinator isolate
  -> OCaml UI domain 0
  <-> OCaml Worker Domain
```

The Flutter UI isolate owns widgets, rendering, plugins, and Application
Support path discovery. One active Dart runtime coordinator isolate owns the
native lease and serializes the existing synchronous C ABI. Every Dart foreign
thread still enters the single embedded OCaml runtime through domain 0. The
Worker Domain is internal to OCaml and communicates with domain 0 only through
bounded immutable messages; it never calls Dart, Flutter, the C bridge,
Bonsai, or the Driver.

The following ownership rules are process-wide:

| Owner | Exclusive state and responsibilities |
| --- | --- |
| Flutter UI isolate | Widgets, render objects, plugins, platform channels, and platform path resolution. |
| Dart runtime coordinator isolate | The singleton coordinator lease, ordered FFI calls, presentation coordination, and native buffers while copying. |
| OCaml UI domain 0 | The singleton runtime state machine, one active `bf_runtime`, one `Driver.t`, Bonsai state and effects, reconciliation, handlers, and worker-client endpoint. |
| OCaml Worker Domain | One process-wide Eio backend, zero or one session switch, bounded request/background fibers, business computation, SQLite and confined-file resources, and worker-only cleanup. |

UI-only and worker-backed applications occupy the same singleton runtime and
Driver slot. The Worker Domain is spawned lazily, reused across sequential
worker sessions, and is never selected by `Domain.recommended_domain_count`.
An actual spawn failure is terminal for worker-backed startup; work never
falls back to domain 0.

Worker services use only the direct-style `init`/`handle`/`shutdown` API.
Each dispatched request has a nested Eio switch, and session daemons remain
children of the session switch. `Serial` is the default handler policy;
bounded `Concurrent` permits fiber interleaving on the same Domain. There is
no `step` scheduler, application cancellation callback, legacy runner, or
compatibility service path. Request and session contexts expose the Worker
Domain's Eio environment so applications can use ecosystem libraries directly.
The framework contains no HTTP client abstraction. File I/O can still use the
separate runtime-opened confined directory capability when ambient filesystem
access is unnecessary.

Each runtime has:

- a random nonzero 64-bit epoch;
- monotonically increasing node, handler, request, event, renderer-revision,
  and presentation counters;
- one Bonsai driver;
- one mounted root;
- a bounded set of handler frames retained until presentation acknowledgment;
- pending host requests;
- current environment;
- an explicit live, recovering, fatal, or destroyed state.

All calls for one runtime are serialized on its Dart runtime isolate. Every
successful logical pump reserves a presentation token, including no-diff and
recoverable dropped-input pumps. Renderer revision advances only when bytes
are emitted. At most one token is unresolved, and a frame is based on the last
revision successfully presented by Flutter. Rejection burns any candidate
revision and forces a full snapshot; it never causes partial mutation.

Duplicate sibling keys are terminal widget-tree invariant violations rather
than recoverable input errors. OCaml reports `Duplicate_key` with a structured,
deterministic root-to-parent widget path and both duplicate child occurrences.
The failed candidate is never presented: its fatal boundary result has token
zero, revision zero, and no bytes, while every non-fatal pump result has a
positive token. The path exists only as reconciliation error context and does
not affect identity, allocation, patches, fingerprints, or successful wire
frames.

## Foreground scheduling

Flutter owns a recursive `SchedulerBinding.scheduleFrameCallback` loop.
`resumed` and `inactive` runtimes with `framesEnabled == true` grant at most
one logical pump per eligible Flutter frame. The runtime worker coalesces
grants behind the unresolved-presentation barrier, so a visually idle
foreground runtime continues advancing Bonsai clocks and lifecycle work
without concurrent native calls.

`hidden`, `paused`, `detached`, and loss of `framesEnabled` stop the loop and
invalidate queued grants while retaining an unresolved token. Resume creates a
new scheduler generation, presents any retained token, and catches up overdue
work on later frames. There is no deadline scheduler, periodic timer, forced
frame, native callback thread, or background fallback.

The worker-owned monotonic `Stopwatch` is sampled immediately before native
pumps and accepted presentation success. OCaml maps elapsed nanoseconds onto a
retained public `Bonsai.Time_source`. This requires no upstream feature patch,
dependency revision change, private time-source API, or shadow timer registry.

## Public application shape

The selected component form follows current `Bonsai.Cont`:

```ocaml
module App : sig
  type t

  val create
    :  ?name:string
    -> (environment:Environment.t Bonsai.t
        -> Bonsai.graph
        -> Widget.t Bonsai.t)
    -> t
end
```

An entrypoint registry maps stable application names to `App.t` values at the
native link boundary. Business applications never encode protocol bytes.

## Extension boundary

The stable core consists of typed primitives and selected Material/Cupertino
semantic nodes. Specialized controls use `Native_widget`: a registered numeric
kind ID, versioned generated props, versioned typed events, capabilities, a
Dart factory, and explicit resource lifecycle. The renderer package never
imports an application module.

## Failure containment

Decoders treat native bytes as untrusted. Frame application validates every
reference, kind, property, root, and cycle before commit. An invalid frame is
rolled back and produces a structured resync or fatal response.

OCaml exceptions are caught before the C ABI and encoded with a safe error
category. Dart renderer exceptions are caught at the frame boundary with the
node ID, kind, and revision. Neither side exposes a partially applied state.

## Current implementation status

The headless OCaml foundation currently implements abstract application keys;
immutable typed Empty, Text, Row, Column, Flex, Stack, Button, Padding, Center,
ScrollView, Semantics, Theme, MaterialCheckbox, and revisioned TextInput nodes;
typed parent data; mounted node and handler identity; full and incremental logical patches;
expected-linear keyed child matching; atomic in-memory patch replay; and
revision-scoped handler dispatch.

The complete OCaml build graph targets OCaml 5.1.1 with the Jane Street
v0.17.x release line. The Bonsai driver adapter, public
library, examples, native backend, and their tests are unconditional members
of that graph. The exact constraints are recorded in `upstream-baseline.md`.

The Dart renderer now has a typed in-memory frame model and a copy-on-write
`NodeStore` transaction. It validates revisions, epochs, root and child
references, cycles, parent counts, and reachability before committing, retains
unchanged node objects, and notifies only dirty node subscribers. Its pure
Dart tests pass.

The binary-protocol vertical slices are also implemented. A validated
schema generator emits stable OCaml and Dart IDs and debug names plus readable
ID documentation. Independent OCaml and Dart codecs share a bounded
little-endian encoding. OCaml-generated output-frame fixtures are decoded by
Dart, and Dart-generated input event batches are decoded by OCaml; both
consumers match the producer byte for byte. Version 1.1 adds typed
finite floats, optional values, ARGB colors, multi-field masks, and
ValueChanged events. Version 1.2 adds revisioned TextInput properties and
UTF-16-indexed TextEdit events while retaining earlier-minor decode
compatibility. Version 1.3 adds typed host request/cancel/response operations,
dynamic environment snapshots, and Navigator/Page/Overlay/MaterialDialog
layouts. Version 1.4 adds the NativeWidget envelope, capability declarations,
opaque typed properties, and typed native events. Later compatible minors
extend the typed surface; current producers and consumers report protocol
1.14. The Dart decoder's output is accepted by the same atomic `NodeStore`.
Checksum negotiation, the remaining widget families, and supported-platform
packaging remain later vertical slices.

The Flutter renderer implements a typed `WidgetRegistry` and per-node
`NodeHost` for Empty, Text, Row, Column, Button, Padding, Center, ScrollView,
Semantics, Theme, MaterialCheckbox, TextInput, Navigator, Page, Overlay, and
MaterialDialog. Every host uses a
`ValueKey<NodeId>` and subscribes only to its node. A store-level subscription
is used only to detect root replacement. Widget tests verify that a text-only
patch preserves unaffected ancestor elements and that Button dispatch sends
the bound handler identity with no application logic in Dart. Semantics maps
to Flutter's accessibility tree, Theme builds a Material `ThemeData`, scroll
notifications remain typed, and Checkbox emits a typed bool value.

Native widgets are resolved by an application-supplied
`NativeWidgetRegistry`. The registry validates schema ranges and declared
capabilities before decoding typed properties. It renders an accessible
diagnostic fallback for unsupported extensions and binds factory resources to
node lifetime. `Sliver.fixed_extent` and `Sliver.varied_extent` are core
sliver kinds that mount only their supplied item window inside a
`Scroll_view` (CustomScrollView).

TextInput is a dedicated host rather than a stateless `TextField` adapter.
Flutter retains the TextEditingController, FocusNode, live selection,
composing state, and optimistic local revision. OCaml retains the canonical
document revision and accepts, corrects, or force-replaces typed editing
values. `RendererResourceStore` synchronizes resource lifetime with epoch,
full-snapshot generation, node ID, and node kind.

`BonsaiFlutterRoot` owns native runtime startup, the foreground frame loop,
ordered cycle updates, event-prefix preparation, two-phase store application,
guarded post-frame presentation acknowledgment, fatal-state rendering, and
disposal. It accepts a registry and runtime factory for renderer extensions
and deterministic tests, but it does not accept application state or reducers.

`BonsaiFlutterRoot` also owns a `HostEffectDispatcher` and an
`EnvironmentReporter`. Host operations are ignored by the `NodeStore` and
executed after frame decode by an injectable platform implementation, so
plugin latency never enters the atomic UI transaction. Responses re-enter the
event batch and resume the exact OCaml continuation. Root disposal cancels
Dart work; driver shutdown clears OCaml continuations and unsent requests.

The environment reporter derives viewport, scale, locale, brightness, insets,
accessibility, orientation, and pointer capabilities from Flutter. It compares
complete snapshots and sends only semantic changes. The driver writes accepted
snapshots to `Environment.value`, a Bonsai dynamic input.

Renderer events enter a bounded `EventBatchQueue`. Ordered events such as
Button presses are never coalesced and exert explicit backpressure when the
bound is full. Scroll and visible-range state updates replace an older pending
update for the same node, handler, and tag; a coalescible update is the only
kind that may be dropped. Accepted events receive monotonic sequences.
`NodeHost` uses the latest presented revision when the callback's handler ID still
matches the committed node. If the binding has changed before Flutter rebuilds
an existing stateful host, it uses the revision captured by the build that
created the old callback instead. This keeps a handler and revision from the
same frame without making unchanged callbacks stale after unrelated frames.
The root prepares an exact event prefix for each presentation success and
commits that prefix only after the ordered handoff succeeds.

On the OCaml side, `Event_dispatcher` converts validated wire tags and payloads
into the public UI event types, reconstructs opaque node and handler IDs
through a private boundary, and dispatches through the revision-scoped
`Handler_registry`. The registry retains the displayed revision and its
immediate predecessor, accepting events queued across one Flutter rebuild
boundary without ever dispatching them to a replacement handler. A headless
test drives the exact Flutter Counter press fixture through this path and
invokes only the expected handler.

`Driver` connects that event path to real Bonsai effect scheduling, one flush,
logical reconciliation, handler-frame installation, and binary encoding. Its
Counter test decodes an initial full
snapshot, acknowledges presentation, dispatches a press, and observes exactly
one incremental text-property operation for `Count: 1`. A rejected mixed-valid
event batch cannot leak a queued effect into a later pump.

The native-assets package exposes exact ABI 2.0 independently from renderer
protocol 1.14, generated FFI bindings, presentation identity, explicit native
output ownership, and an idempotent Dart wrapper. A dedicated Dart isolate
serializes pump, presentation-success, presentation-rejection, and destroy
calls and transfers byte payloads without exposing native pointers to the UI
isolate.

Each example owns a complete-object target that links only its application
entrypoint with the real Bonsai driver, native handle registry, OCaml runtime,
callback bridge, and public `bf_*` symbols. The package build hook consumes
that object as a standard code asset. The integration-test workspace owns a
separate aggregate object for multi-entrypoint tests; it is not an application
artifact. A macOS arm64 Flutter widget integration test renders its initial
full snapshot, clicks the Button, receives a single `Count: 1` property patch,
preserves unaffected Element identity, acknowledges presentation, and destroys
the runtime. The default native package still builds a truthful fatal-status
fallback when no complete object is selected.

The Phase 4 Gallery is an OCaml Bonsai component with a minimal Flutter shell
containing `BonsaiFlutterRoot`. Its integration test renders typed layout,
dark theme, accessibility semantics, scroll, Button, and Checkbox nodes. A
Checkbox click returns through the runtime isolate and FFI, changes Bonsai
state, and applies Semantics and MaterialCheckbox property updates without
creating or dropping nodes. Its Phase 7 custom native card registers only a
typed Flutter factory; the counter and handler remain in OCaml. The same test
proves typed native event dispatch, incremental property update, resource
retention, and shutdown disposal.

The Phase 5 Text Input example is also an OCaml Bonsai component with a
minimal `BonsaiFlutterRoot` shell. Its native test sends two rapid
Chinese/emoji composing edits in one batch and receives one Ack update for the
latest local revision without rewriting the controller.

The Phase 6 Host Effects and Navigation example keeps clipboard-result state,
the page stack, overlay visibility, and dialog visibility in OCaml. Flutter
executes the clipboard request and route animation, emits typed HostResponse
and RoutePop events, and contains no application reducer. Its real FFI test
exercises both directions and verifies the system-pop round trip.

This full vertical slice uses the project OCaml 5.1.1 baseline. Counter
packages have built, launched, and passed code-signing checks in Debug,
Profile, and Release on the recorded macOS arm64 host. The dependency objects
and generated hosts share an explicit macOS 26.0, Apple Silicon arm64-only
contract. Intel Mac, universal binaries, and lower macOS deployment targets
are unsupported. iPhoneOS remains minimum 15.0 on arm64. See `ffi.md` and
`packaging.md`.
