# Upstream baseline

This baseline was revalidated on 2026-08-04 in Asia/Shanghai. Versions are
recorded build inputs rather than floating branch references.

## Host toolchain

| Component | Measured version | Notes |
| --- | --- | --- |
| Host | macOS 26.5.2 (25F84) | Darwin 25.5.0 |
| Architecture | arm64 | Apple silicon |
| OCaml | 5.1.1 | Project compiler baseline |
| opam | 2.3.0 | Default repository |
| Dune | 3.23.1 | Bonsai v0.17 requires Dune below 3.24 |
| Xcode | 26.1.1 | Selected by `xcode-select` |
| Apple clang | 17.0.0 | Target `arm64-apple-darwin25.5.0` |
| Flutter SDK | 3.44.8 | Stable revision `058e0af2c2b57e369d905a03ac9748b0ebf543c6` |
| Dart SDK | 3.12.2 | Bundled by Flutter 3.44.8 |
| iPhoneOS object | arm64, iOS 15.0 | Unsigned build and audit passed |

## Jane Street release line

All installed Jane Street release-train packages use `v0.17.x`. Direct
runtime dependencies resolve to:

| Package | Version |
| --- | --- |
| Bonsai | v0.17.0 |
| Incremental | v0.17.0 |
| Incr_dom | v0.17.0 |
| Virtual_dom | v0.17.0 |
| Core | v0.17.2 |
| Base | v0.17.3 |

The patch releases for Core and Base are part of the `v0.17` release line.
Manifests constrain every direct Jane Street dependency to versions greater
than or equal to `v0.17` and strictly below `v0.18`.

The default opam repository supplies immutable release-tag archives. CI does
not use the Jane Street bleeding repositories and does not pin local Bonsai,
Incremental, or Incr_dom source trees.

## Compiler and API selection

OCaml 5.1.1 is exact in `.ocaml-version`, `dune-project`, both opam manifests,
and the iOS toolchain lock. No `OCAMLPARAM=keywords=4.14` compatibility mode is
required.

Bonsai v0.17 exposes the continuation API through `Bonsai.Cont`:

```ocaml
val component
  : Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_flutter_ui.Widget.t Bonsai.Cont.t
```

`Bonsai_v017.state` is the project-owned compatibility helper for the v0.17
state-machine shape. Runtime scheduling uses the public `Bonsai_driver`
surface and a retained public `Bonsai.Time_source`.

The v0.17 driver does not expose the newer before-display helper used by the
previous preview baseline. `Driver.Handler.wait_before_display` therefore
owns a small callback queue and drains it to a fixed point during the logical
frame flush. After-display work is still released only after Flutter
acknowledges the matching presentation token.

## Flutter package baseline

Flutter 3.44.8 uses the `package_ffi` build-hook model. The native package
build hook has produced an arm64 Mach-O artifact exporting the `bf_runtime_*`
C ABI. Debug, Profile, and Release application builds and real FFI integration
tests use staged complete objects rather than manually copied dynamic
libraries.

Flutter runtime-control events are stamped with the revision at the
presentation handoff. UI events retain their source revision and handler
identity. This prevents a queued environment or host-response control from
atomically rejecting a valid previous-frame UI event during a continuously
updating clock.

## iPhoneOS cross-build baseline

The isolated cross environments pin:

- OCaml 5.1.1 for both host and `ocaml-ios64`;
- opam-cross-ios commit
  `8380b52b0154752c26c6e221c04fbced3320aa48`;
- Dune 3.23.1;
- Bonsai v0.17.0 and the complete Jane Street v0.17.x runtime closure;
- iPhoneOS arm64 with minimum iOS 15.0.

The repository-owned `ocaml-ios64.5.1.1` overlay derives from the locked
opam-cross-ios recipe and installs an `ios-cc` wrapper carrying the iPhoneOS
architecture, sysroot, and minimum-version flags. Target objects therefore
retain `LC_BUILD_VERSION platform IOS` metadata even for package C stubs.

The target closure is resolved per application from pinned opam metadata and
Dune library roots. The checked-in DataScript SQLite fixture lock currently
contains 121 packages: 69 target packages, 51 host-only packages, one
target-build package, and 106 target findlib components. Those values are
lock-derived metadata that the verifier recomputes, not fixed policy. The
fixture includes exact Eio `1.2`, `eio_posix` `1.2`, SQLite `5.4.0`, the pinned
DataScript native stack, and an extra pure OCaml `astring` root. Host PPX
executables remain macOS processes. Supported Dune and Topkg pure OCaml
packages compile generically; platform capabilities require an explicit
iPhoneOS recipe and feature gate.

All standalone examples and the aggregate integration entrypoint build as 12
arm64 iPhoneOS complete objects, including separate Mail debug and release
objects. Every object is verified as iPhoneOS arm64 with minimum iOS 15.0. An
unsigned Counter application build and its embedded native framework pass the
final bundle audit. iOS Simulator remains outside the repository support
boundary.

## Verification boundary

The validated gates are:

- complete OCaml `@all`, `runtest`, and the 15-test Clock suite;
- Flutter unit tests for runtime-control revision handoff;
- a real macOS OCaml/FFI/Flutter Clock test covering exact and approximate
  time, a three-second sleep, and recurring schedules;
- the locked iOS closure audit and iPhoneOS complete-object build.

Host proxy variables may require
`NO_PROXY=127.0.0.1,localhost` for Flutter's local test harness.
