# Testing

Testing is split by boundary.

## Continuous integration

The repository has five required GitHub Actions workflows:

- `ocaml.yml` runs the complete OCaml 5.3.0 build, test, formatting, generated
  protocol and OCaml-frame fixture checks, release benchmark compilation, and
  opam metadata gates on Linux.
- `flutter.yml` runs renderer, native package, generated FFI binding, example,
  Dart-event fixture, malformed-input, and native sanitizer gates on Linux.
- `macos.yml` applies the pinned upstream `basement` portability patch, links
  the real OCaml object, builds the Counter application in Debug, Profile, and
  Release modes, and runs the cross-language integration suite on macOS arm64.
- `ios.yml` reproduces the pinned cross toolchain and builds and audits
  unsigned iPhoneOS applications on a hosted macOS runner.
- `ios-device.yml` is a serialized, protected-environment lane for one
  explicitly configured physical iPhone on a dedicated self-hosted arm64 Mac.
  It never runs pull-request code.

Run the same boundaries locally from the repository root:

```sh
make ci-contract
make ci-ocaml
make ci-flutter
make ci-sanitizers
make ci-macos
make ios-device-native-objects
make ci-ios
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

The equivalent `just ci-*` recipes delegate to these canonical Make targets.
`ci-macos` includes `ci-ocaml`; it requires the Flutter SDK, Xcode, and an
OCaml 5.3.0 switch prepared as described in the repository README.

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
`frame_presented`.

A second Counter test exercises the complete headless runtime
step: full-frame encoding, presentation acknowledgment, revision-scoped press
dispatch, Bonsai state update, and a single incremental text-property patch.
It also rejects a mixed-validity event batch and proves that its earlier valid
event cannot leak into a subsequent step.

The driver suite also suspends and resumes a Bonsai host effect,
checks pending-request cleanup, and applies EnvironmentChanged as a Bonsai
dynamic input. Sending the same environment twice produces no second frame.

`bonsai_flutter_test` queries nodes by test ID, application key, semantic role,
visible text, semantics label, and node kind. It does not implement CSS
selectors.

## Dart

Pure Dart tests validate binary decoding, atomic `NodeStore` transactions,
native buffer ownership, and runtime-isolate serialization. Current Flutter
widget tests validate `NodeHost`, stable keys, subtree-local invalidation, root
replacement, typed Button and Checkbox event dispatch, finite typed layout
values, dark Theme mapping, and the Flutter Semantics tree.

Text input tests cover UTF-16/UTF-8 conversion boundaries, Chinese, Japanese,
Korean, emoji, combining marks, composing, selection, paste, delete, submit,
focus switching, exact-revision correction, stale correction rejection, force
replacement, rapid edits, keyed reorder retention, and resource disposal.

The `BonsaiFlutterRoot` widget is tested with an injected deterministic runtime
session. The test covers startup, initial full-snapshot presentation, event
draining, incremental frame application, post-frame acknowledgment, and
runtime disposal without loading a native artifact.

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

## Cross-language

Fixture provenance is part of the test contract:

- OCaml generates empty incremental, Counter full-snapshot, Unicode update,
  child-reorder, typed host-request, and protocol 1.12 animated-opacity
  frames. Dart decodes their typed contents and matches its own encoding byte
  for byte.
- Dart generates Counter press, host-response, Unicode TextEdit, and complete
  EnvironmentChanged event batches. OCaml decodes their typed contents and
  matches its own encoding byte for byte.
- The legacy `counter_full.hex` and `counter_press.hex` files are generated
  compatibility aliases, not independently maintained sources.

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
- start the dedicated Dart runtime isolate with the `counter` OCaml
  entrypoint;
- decode and commit the initial full snapshot;
- render it with the standard Flutter registry;
- click the real `ElevatedButton`;
- send the renderer event as one binary batch through FFI;
- observe Bonsai state change and exactly one incremental text-property patch;
- preserve the root and Button Elements while changing `Count: 0` to
  `Count: 1`;
- acknowledge both presented revisions and destroy the runtime.

The Gallery integration test starts the `gallery` OCaml entrypoint, verifies
Padding, ScrollView, Button, Checkbox, dark Theme, and an accessibility label,
then taps the Checkbox. The event crosses the runtime isolate and FFI, updates
Bonsai state, and returns only Semantics and MaterialCheckbox property
updates—no node create or drop operations.

The Text Input integration test starts the `text_input` entrypoint and changes
the live controller twice before one runtime step. Its event batch preserves
the Chinese/emoji UTF-16 composing range. Bonsai accepts both edits in one
flush and emits one TextInput Ack for the latest local revision; Flutter keeps
the same controller and composing range.

The Host Effects and Navigation integration test starts the
`host_navigation` entrypoint, completes a clipboard HostRequest, resumes the
OCaml continuation, and applies the resulting text patch. It then opens an
OCaml-owned Settings page containing Overlay and MaterialDialog nodes and
returns a system pop to OCaml before the route is removed.

The macOS integration command is:

```sh
make integration-test
```

This builds the linked OCaml object with the active OCaml 5.3.0 switch, resolves
the Flutter workspace, and runs its real FFI tests. Counter Debug, Profile, and
Release packages have also built and launched on the recorded macOS arm64
host. Lower macOS deployment targets and other platforms remain unclaimed.

## iOS unsigned packaging

Create the isolated cross environments and target-qualified objects:

```sh
make ios-toolchains
make ios-device-native-objects
```

Run the complete hosted boundary:

```sh
make ci-ios
```

The repository has verified unsigned iPhoneOS arm64 builds for all seven
standalone examples and the aggregate integration application. Counter
Debug, Profile, and Release frameworks pass the artifact audit. That audit
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
It then runs Debug Flutter integration tests, a Debug hot-restart assertion,
Profile and Release XCTest, a Release archive/export audit, installation, and
cold launch.

On the measured host, hardware preflight passed but signing preflight stopped
before the build because no matching development/distribution identities,
profiles, and Team configuration were available. Consequently physical
interaction, background/foreground transitions, cold relaunch, hot restart,
signed archive export, and the physical device/OS matrix remain unverified.
