# Testing

Testing is split by boundary.

Modal navigation behavior is covered at every boundary. OCaml public-surface
tests verify standard and modal typed presentation values, protocol tests cover
round trips and stable-node updates, and Flutter widget tests exercise real
Navigator routes, barriers, live pop vetoes, focus, semantics, keyboard insets,
safe areas, restoration identity, directionality, themes, and reduced motion.
The focused local command is:

```sh
dune runtest ocaml/test
cd flutter/packages/bonsai_flutter
flutter test test/navigation_host_test.dart test/binary_codec_test.dart \
  test/cross_language_fixture_test.dart
```

The supported desktop test boundary is macOS 26.0 or newer on Apple Silicon
arm64. Intel Mac and universal macOS builds are unsupported. The mobile
boundary remains physical-device iPhoneOS 15.0 or newer on arm64.

## Local verification

Run the supported verification boundaries locally from the repository root:

```sh
make ci-contract
make ci-ocaml
make ci-flutter
make ci-sanitizers
make ci-macos
make ci-ios
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

The equivalent `just ci-*` recipes delegate to these canonical Make targets.
`ci-macos` includes `ci-ocaml`; it requires the Flutter SDK, Xcode, and an
OCaml 5.1.1 switch prepared as described in the repository README.

The OCaml, Flutter, and macOS targets install the framework and consumer opam
packages from the current checkout before entering standalone Dune roots. This
keeps nested projects on the same installed-package boundary as external
consumers and prevents them from reaching through the repository root.

`ci-ios` builds and audits unsigned iPhoneOS Debug, Profile, and Release
applications. It does not install or execute them on hardware.

`ci-ios-device` requires repository-external certificates, profiles, export
options, an Apple Team, and an explicit device identifier. The command must
not be skipped or replaced with a simulator result before the public support
claim changes. iOS Simulator is outside the supported platform scope. See
`docs/ios-device-testing.md`.

## OCaml

Headless tests construct logical trees, reconcile them, apply generated
patches to an in-memory snapshot, and compare the result with the mounted tree.
The suite includes deterministic randomized mutations and a 10,000-keyed-child
case to detect accidental quadratic matching.

The mandatory adapter test links the selected upstream driver through
`Bonsai_runtime_adapter`. It verifies real Bonsai state application and proves
that activation and after-display effects remain pending until
the exact presentation token succeeds.

A second Counter test exercises the complete headless runtime
pump: full-frame encoding, presentation acknowledgment, revision-scoped press
dispatch, Bonsai state update, and a single incremental text-property patch.
It also rejects a mixed-validity event batch and proves that its earlier valid
event cannot leak into a subsequent pump.

The driver suite also suspends and resumes a Bonsai host effect,
checks pending-request cleanup, and applies EnvironmentChanged as a Bonsai
dynamic input. Sending the same environment twice produces no second frame.

The foreground-pump suite drives fake monotonic samples through the real
Bonsai adapter and covers `Clock.at`, `every`, `sleep`, `until`, observed time,
before-display fixed points, after-display, same-path lifecycle replacement,
no-diff tokens, exact token barriers, rejection recovery, atomic invalid
input, host-operation replay, and sequence overflow.

`bonsai_flutter_test` queries nodes by test ID, application key, semantic role,
visible text, semantics label, and node kind. It does not implement CSS
selectors.

The singleton and Worker Domain suites use real `Domain.spawn`, bounded
mailboxes, conditions, and deterministic synchronization. They prove that one
UI-only or worker-backed runtime occupies the process-wide slot, replacement
never overlaps Drivers or sessions, sequential recreation reuses the same
Worker Domain identifier, ordinary destroy performs zero joins, and final
shutdown joins a successfully spawned Domain exactly once. They also cover
spawn and service failures, out-of-band Stop and Cancel, bounded request
dispatch, backpressure, stale fencing, response reservation, push coalescing,
and idle waiting without polling. Direct-style Eio suites additionally cover
request-switch cancellation before dispatch, while waiting for a permit, and
while suspended; bounded concurrent handlers; session daemons; daemon/init
races; exactly-once outcomes; lifecycle duration metrics; and backend reuse.

SQLite store tests use temporary on-disk databases and a real worker session.
They cover migration and reopen, Unicode prepared values, list bounds, title
validation, mutation idempotency, transactional revisions, future schemas,
corruption, unopenable paths, finite lock contention, explicit close, and
same-path recreation. Service and application tests verify Ready, List, Add,
Toggle, Refresh, response-before-push ordering, snapshot and summary pushes,
persistence, and fresh mutation identities after process epoch changes.
The file demonstration tests bounded 64 KiB streaming, 16 MiB limits,
controlled suspension, cancellation at every chunk boundary, atomic rename,
temporary-file cleanup, progress, and checksum stability.

## Dart

Pure Dart tests validate binary decoding, atomic `NodeStore` transactions,
native buffer ownership, and runtime-isolate serialization. Current Flutter
widget tests validate `NodeHost`, stable keys, subtree-local invalidation, root
replacement, typed Button and Checkbox event dispatch, finite typed layout
values, dark Theme mapping, and the Flutter Semantics tree.

Application-theme tests cover the public OCaml token constructors, validation,
structured OCaml/Dart codec symmetry, exact full-snapshot fixtures, theme-only
driver frames, and rejected-presentation rollback. Dart transaction tests
prove that the application theme and node graph publish atomically and that a
theme-only frame preserves logical node identity. Root widget tests prove that
no `MaterialApp` exists before the first committed theme, exactly one exists
after commit, missing high-contrast variants reuse the supplied normal
variants, theme-only updates preserve `MaterialApp` state, and runtime
replacement cannot reuse the previous epoch's theme.

Text input tests cover UTF-16/UTF-8 conversion boundaries, Chinese, Japanese,
Korean, emoji, combining marks, composing, selection, paste, delete, submit,
focus switching, exact-revision correction, stale correction rejection, force
replacement, rapid edits, keyed reorder retention, and resource disposal.

The `BonsaiFlutterRoot` widget is tested with an injected deterministic runtime
session. The test covers startup, initial full-snapshot presentation, event
draining, incremental frame application, post-frame acknowledgment, and
runtime disposal without loading a native artifact.

Frame-loop tests prove one recursive `scheduleFrameCallback` chain, scheduler
generation guards, at most one grant per bounded Flutter frame, suspension for
hidden and paused states, retained-token resume, independent
`framesEnabled` loss, stale callback rejection, and exact disposal.
Worker tests prove grant coalescing behind the presentation barrier, ordered
success and rejection, checked monotonic conversion, visibility barriers, and
exact-once terminal cleanup.

A live foreground root intentionally does not settle. Widget tests use
bounded frame counts or predicate-based helpers instead of `pumpAndSettle`.
Real-isolate timer tests use a wall-clock timeout, alternate a short
`tester.runAsync` delay with one `tester.pump()`, and include worker debug
state in timeout diagnostics.

Host-effect tests use injected implementations and cover success, typed error,
cancellation, duplicate IDs, and disposal while work is pending. Navigation
widget tests build declarative pages, render Overlay and Dialog content, and
verify that a platform pop emits RoutePop rather than mutating an application
router in Dart. The built-in host-effect tests also drive a node-scoped
`FocusNode` and `ScrollController` through `RequestFocus` and `ScrollTo`, and
the root test proves that its renderer resource store is shared with the
implementation. Semantic animation tests verify midpoint interpolation,
completion identity, reduced-motion behavior, protocol round trips, and
controller disposal after node removal. Environment tests verify semantic
change filtering.

Navigation motion tests sample observable page positions rather than route
implementation types. They cover front-loaded monotonic entrance, exact
landing, inbox parallax, one-to-one edge tracking, cancel, distance and fling
commit, root and `canPop` guards, transition-in-progress guards, RTL, reduced
motion, and single typed RoutePop emission.

Swipe-action tests cover exact binary validation, built-in registration,
horizontal tracking and reversal, fixed full-row action surfaces, exposed-edge
rounding, threshold icon scaling, distance and velocity commits, one-shot
haptics, settle timing, vertical ListView arbitration, tap cancellation, custom
Semantics actions, disabled directions, keyed updates, node drop, RTL, and
reduced motion. Widget tests avoid wall-clock performance assertions.

## Cross-language

Fixture provenance is part of the test contract:

- OCaml generates empty incremental, Counter full-snapshot, Unicode update,
  child-reorder, typed host-request, and protocol 1.12 animated-opacity
  frames. Dart decodes their typed contents and matches its own encoding byte
  for byte.
- Dart generates Counter press, host-response, Unicode TextEdit, and complete
  EnvironmentChanged event batches. OCaml decodes their typed contents and
  matches its own encoding byte for byte.

The shared Unicode incremental frame is applied to mismatched epoch and
revision stores to verify transactional rejection. Decoder suites additionally
cover truncation, wrong versions, unknown kinds and event tags, malformed
lengths, and oversized strings.

Generate or verify all committed fixtures from the repository root:

```sh
make protocol-fixtures-generate
make protocol-fixtures-check
```

`ci-ocaml` checks the OCaml-produced frames and `ci-flutter` checks the
Dart-produced event batches. Neither check rewrites stale files. The OCaml
event-dispatch test installs a revision-scoped Counter handler and verifies
that the Dart press fixture invokes it exactly once.

## Integration

The opt-in macOS arm64 workspace at `flutter/integration_test` consumes its
own test-only aggregate Dune complete object through a build-hook user define.
Standalone examples do not use this artifact: each example builds and bundles
the `native_embed.exe.o` target in its own `ocaml/` directory. The integration
tests:

- load the generated package code asset;
- start the dedicated Dart runtime isolate and drive its ordered update
  session with foreground grants;
- decode and commit the initial full snapshot;
- render it with the standard Flutter registry;
- click the real `ElevatedButton`;
- send the renderer event as one binary batch through FFI;
- observe Bonsai state change and exactly one incremental text-property patch;
- preserve the root and Button Elements while changing `Count: 0` to
  `Count: 1`;
- acknowledge exact presentation tokens and destroy the runtime.

The Gallery integration test starts the `gallery` OCaml entrypoint, verifies
Padding, ScrollView, Button, Checkbox, dark Theme, and an accessibility label,
then taps the Checkbox. The event crosses the runtime isolate and FFI, updates
Bonsai state, and returns only Semantics and MaterialCheckbox property
updates—no node create or drop operations.

The Text Input integration test starts the `text_input` entrypoint and changes
the live controller twice before one runtime pump. Its event batch preserves
the Chinese/emoji UTF-16 composing range. Bonsai accepts both edits in one
flush and emits one TextInput Ack for the latest local revision; Flutter keeps
the same controller and composing range.

The Host Effects and Navigation integration test starts the
`host_navigation` entrypoint, completes a clipboard HostRequest, resumes the
OCaml continuation, and applies the resulting text patch. It then opens an
OCaml-owned Settings page containing Overlay and MaterialAlertDialog nodes and
returns a system pop to OCaml before the route is removed.

The Mail integration test starts the `mail` entrypoint, verifies that drag
deltas remain local, sends one Archive commit through FFI, applies the
incremental row removal while retaining the following keyed Element, opens an
unread detail page, drives an interactive leading-edge pop, and confirms that
the matching RoutePop returns to an inbox where the message remains read.

The autonomous-pump fixture supplies no tap, host response, environment
update, or manual native pump. It presents phase 0, advances through
after-display to phase 1, and reaches phase 2 after a 50 ms Bonsai sleep. A
second scenario follows the valid mobile background sequence, proves with a
same-port snapshot that pump count remains unchanged while hidden or paused,
then resumes and catches up using real foreground frames.

The SQLite Worker integration scenario resolves a real Application Support
path, starts the `sqlite_worker` entrypoint through FFI, waits for unsolicited
Ready and the initial List response, performs Add and Toggle, observes pushed
snapshots, and issues thirty foreground Refresh operations. It proves that
hidden and paused intervals grant no pumps, resume restores progress, explicit
disposal completes before unmount, and a sequential replacement recovers the
committed Todo from the same database. Host debug timing is diagnostic only;
the physical-device Profile lane is the authority for the 250 ms p95 and
500 ms p99 foreground response limits.

For interaction tuning, use a compact physical iPhone in Profile mode. The
dedicated driver warms every interaction twice, records twenty detail
entrances, edge-pop cancels, edge-pop commits, row-swipe cancels, and row-swipe
commits, then enforces a 16 ms p90 build and raster budget:

```sh
cd flutter/integration_test
flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/mail_profile_test.dart \
  --driver test_driver/mail_profile_test.dart \
  --timeout 600
```

The summary is written to `build/mail_profile_summary.json`. The recorded
physical-iPhone 13 acceptance run had zero missed build and raster budgets;
the worst p90 build and raster times across a second concurrent screen-capture
run were 3.641 ms and 0.012 ms. Shared CI widget-test timing is not a
performance acceptance signal.

The macOS integration command is:

```sh
make integration-test
```

This builds the linked OCaml object with the active OCaml 5.1.1 switch, resolves
the Flutter workspace, and runs its real FFI tests. Counter Debug, Profile, and
Release packages have also built and launched on the recorded macOS arm64
host. macOS deployment targets below 26.0, Intel Mac, and universal builds are
unsupported.

## iOS unsigned packaging

Create the isolated cross environment, then build a consumer through the
public tool:

```sh
dune build bonsai_flutter_tool/bin/main.exe
_build/default/bonsai_flutter_tool/bin/main.exe toolchain install iphoneos
cd examples/counter
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile release --no-codesign
```

Run the complete hosted boundary:

```sh
make ci-ios
```

`ci-ios` installs the locked SDK when the fixed switch is absent and verifies
an existing switch before building any consumer.

The repository contains eleven standalone consumer workspaces. The hosted
unsigned matrix builds Counter, SQLite Worker, and Network in Debug, Profile,
and Release through `bonsai-flutter`. Their frameworks pass their
artifact audits. The SQLite mode additionally requires Apple system SQLite
imports and rejects any change to the public `bf_*` export boundary. The audit
checks the final Mach-O platform, architecture, minimum version, Bitcode,
install name, linked libraries, exact public exports, Native Assets manifest,
prohibited process imports, privacy manifest, and Profile/Release dSYM UUIDs.

## iOS physical-device matrix

With signing inputs installed outside the repository, run:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

The canonical runner validates the explicit target as a physical, paired,
trusted, booted iPhone with Developer Mode enabled and unlocked since boot.
After signing preflight, `bonsai-flutter run ios` builds and audits the
integration consumer, installs it, and launches it on the selected device.

On the measured host, hardware preflight passed but signing preflight stopped
before the build because no matching development/distribution identities,
profiles, and Team configuration were available. Consequently physical
interaction, background/foreground transitions, cold relaunch, hot restart,
signed archive export, and the physical device/OS matrix remain unverified.

The SQLite Worker physical-device registration uses the same real-FFI
scenario and records singleton recreation, Worker Domain identity, push and
request ordering, persistence, suspension, resume, and Profile p95/p99
latencies when signing inputs and a reachable device are available. An
unsigned bundle is packaging evidence and is never substituted for these
device assertions.
