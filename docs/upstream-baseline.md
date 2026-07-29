# Upstream baseline

This baseline was measured on 2026-07-25 and updated on 2026-07-26 in
Asia/Shanghai. Versions and revisions are recorded inputs to the build.

## Host toolchain

| Component | Measured version | Notes |
| --- | --- | --- |
| Host | macOS 26.5.2 (25F84) | Darwin 25.5.0 |
| Architecture | arm64 | Apple silicon |
| OCaml | 5.3.0 | Project compiler baseline |
| opam | 2.3.0 | Default and Jane Street bleeding repositories |
| Dune | 3.24.0 | Project minimum is 3.17 |
| ocamlformat | 0.29.0 | Jane Street profile |
| Xcode | 26.1.1 at `/Applications/Xcode.app` | Selected by `xcode-select` |
| Apple clang | 17.0.0 (clang-1700.4.4.1) | Target `arm64-apple-darwin25.5.0` |
| Flutter SDK | 3.44.8 | Stable revision `058e0af2c2b57e369d905a03ac9748b0ebf543c6` |
| Dart SDK | 3.12.2 | Bundled by Flutter 3.44.8 |
| DevTools | 2.57.0 | Bundled by Flutter 3.44.8 |
| iPhoneOS object | arm64, iOS 13.0 | Unsigned build and audit passed |

## Selected upstream revisions

| Repository | Revision | Version or branch |
| --- | --- | --- |
| `janestreet/bonsai` | `f31661450eb133fe89564219d97669c2735c6622` | `v0.18~preview.130.106+341`, `master` |
| `janestreet/bonsai_web` | `989c18b5381cad767365923d4f0b758c6f3c602c` | Inspected only |
| `janestreet/bonsai_term` | `2457232d3aa144fb887a053748a920544db60f72` | Inspected only |
| `janestreet/bonsai_concrete` | `10601f857306e691462fa049cb8b58c162d86cca` | `v0.18~preview.130.106+341` |
| `janestreet/incremental` | `98b5750ec3c006641351bfd858a89136a5dbc52c` | `v0.18~preview.130.106+341` |
| `janestreet/virtual_dom` | `4e9549cdd71dc62f0e78917e088d607b219f1ba3` | Transitive `Ui_effect` provider |
| `janestreet/basement` | `5c640c230a3989f8e505cda7aa6aca9925a23a5b` | `v0.18~preview.130.106+341` |
| `janestreet/opam-repository` | `6789b91abef324f0f9dc2a07332afc4843c7dbe5` | Jane package index |
| `janestreet/opam-repository` | `a577fc24cba311814e5088a0f6851c65b5cf8dc1` | External-packages index |
| `flutter/flutter` | `058e0af2c2b57e369d905a03ac9748b0ebf543c6` | Stable 3.44.8 |
| Flutter engine | `0cd610717bde95fd88343c64f81c11ba4e5c0010` | Selected by Flutter 3.44.8 |
| Dart SDK | `d684a576a6aa954ae107a03b2b4e1d61c3bebe93` | Dart 3.12.2 |

The repository does not depend on `bonsai_web` or `bonsai_term`. They were
inspected only for established driver and lifecycle sequencing.

## Compiler selection

The selected Bonsai preview requires:

```text
ocaml >= 5.1.0
ppxlib >= 0.33.0 & < 0.36.0
```

`ppxlib` 0.35.0 requires OCaml below 5.4. OCaml 5.3.0 is therefore the newest
stable compiler accepted by the complete locked dependency graph. The project
pins that exact version in `.ocaml-version`, `dune-project`, and both opam
manifests.

Both Jane Street opam repository URLs are pinned to the commits in the table.
The bleeding index is not followed by branch name, so a new CI run resolves
the recorded preview instead of whichever preview happens to be current.

There is no alternate compiler build path. All Bonsai libraries, examples,
and driver tests are mandatory members of the default Dune graph.

On macOS, the selected `basement` source needs a small portability patch:
`caml_state` is replaced with the public `Caml_state` header macro, and the
OCaml-internal `fallthrough` macro is undefined before including Apple's
dispatch headers. The reviewed patch and its source revision are recorded in
`vendor/patches`.

## Bonsai API baseline

The supported Bonsai surface is the continuation API re-exported by the
top-level `Bonsai` module:

```ocaml
val component : Bonsai.graph -> Widget.t Bonsai.t
```

State uses `Bonsai.state` or `Bonsai.state'`. Effects use `Bonsai.Effect`, and
runtime scheduling goes through `Bonsai_driver.schedule_event`. Application
code never calls `Effect.Expert.handle`.

The selected driver surface is:

```ocaml
val Bonsai_driver.create
  :  ?here:Lexing.position
  -> ?optimize:bool
  -> instrumentation:
       (Bonsai_driver.Instrumentation.Timeable_event.t, _)
       Bonsai.Private.Instrumentation.Config.t
  -> time_source:Bonsai.Time_source.t
  -> (Bonsai.graph -> 'result Bonsai.t)
  -> 'result Bonsai_driver.t

val Bonsai_driver.flush : 'result Bonsai_driver.t -> unit
val Bonsai_driver.result : 'result Bonsai_driver.t -> 'result
val Bonsai_driver.schedule_event
  : 'result Bonsai_driver.t -> unit Bonsai.Effect.t -> unit
val Bonsai_driver.trigger_lifecycles : 'result Bonsai_driver.t -> unit
val Bonsai_driver.has_before_display_events : 'result Bonsai_driver.t -> bool
val Bonsai_driver.has_after_display_events : 'result Bonsai_driver.t -> bool
```

`Bonsai_driver.flush` handles pending clock and before-display work.
`trigger_lifecycles` performs deactivation, activation, and after-display
scheduling, so the Flutter backend calls it only after acknowledging the
corresponding presented revision.

The foreground-vsync pump retains the public `Bonsai.Time_source` supplied at
driver creation and advances it through the public clock API before each
logical flush. The selected revisions already provide the required clock,
flush, lifecycle, and observer-invalidation operations. This feature changes
no upstream source, overlay, package constraint, lockfile, or pinned revision
and uses no private time-source operation.

## Private API audit

The only direct `Bonsai.Private` use is construction of the instrumentation
configuration required by `Bonsai_driver.create`. It is confined to
`Bonsai_runtime_adapter`; no private type appears in a public `.mli`.

`Bonsai_driver.Expert.invalidate_observers` is a public expert operation and
is used for shutdown until the upstream driver exposes a dedicated destroy
operation.

## Flutter package baseline

Flutter 3.44.8's `package_ffi` build-hook model is used for native assets. The
matching template package versions are:

| Package | Constraint |
| --- | --- |
| `code_assets` | `^1.0.0` |
| `hooks` | `^1.0.0` |
| `native_toolchain_c` | `^0.17.4` |
| `ffigen` | `^20.1.1` |

The native build hook has produced an arm64 Mach-O artifact exporting the
`bf_runtime_*` C ABI. Debug, Profile, and Release Counter builds, native
symbol checks, code signing checks, and real FFI integration tests passed on
the recorded host.

## iOS cross-build baseline

The isolated cross environments pin opam-cross-ios commit
`8380b52b0154752c26c6e221c04fbced3320aa48`, OCaml 5.3.0, and the existing
Jane Street preview revisions. The recorded runtime closure contains 55
packages, 102 target runtime components, and one target-build package. Host
PPX executables remain macOS processes.

The iPhoneOS arm64 object and linked host are platform `IOS` with minimum
13.0. The original seven example applications and the aggregate integration
application build unsigned. The repository now contains eight standalone
examples; Bonsai Mail awaits the next full hosted packaging run. Counter Debug,
Profile, and Release pass the framework audit.

iOS Simulator is intentionally outside the repository support boundary.

One attached physical iPhone passed the hardware preflight for connection,
pairing, trust, boot, Developer Mode, and unlock state. No matching
development/distribution signing configuration was available, so no signed
application ran. No physical device model or iOS version is included in the
support matrix, and iOS remains unclaimed.

The final iOS application imports file-timestamp and system-boot-time
required-reason APIs. Every Runner includes the minimal privacy categories
and reasons selected for those linked symbols.

## Known upstream and host risks

- The selected Bonsai preview exposes `Bonsai.Effect` through the
  `virtual_dom.ui_effect` package. No Virtual DOM rendering type crosses the
  framework API.
- The selected `basement` revision needs the documented macOS source patch.
- The measured Jane Street and OCaml objects were compiled on macOS 26. A
  lower macOS deployment target is not claimed until dependencies are rebuilt
  and run on that target.
- Host proxy variables may need `NO_PROXY=127.0.0.1,localhost` for Flutter's
  local test harness.
- Linux, Windows, Android, and iOS remain architectural targets only until
  their platform builds and integration suites pass. The unsigned iPhoneOS
  evidence above does not change that support boundary.
