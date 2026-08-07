# OCaml-First Tooling for Bonsai Flutter Applications

Status: Proposal

Date: 2026-08-06

## Summary

Applications built with `bonsai_flutter` should feel like OCaml projects that
happen to use Flutter as a mechanical host. Application developers should use
`opam`, Dune, OCaml tests, and an OCaml command-line tool as their primary
workflow. Dart tooling, Native Assets hooks, Apple cross-compilation patches,
and Flutter host generation should remain implementation details.

This document proposes an opam package named `bonsai_flutter_tool` that installs
an OCaml executable named `bonsai-flutter`. The executable coordinates Dune,
the versioned Bonsai Flutter native SDK, native-object staging, Flutter, Xcode,
and physical-device commands.

The intended steady-state workflow is:

```sh
opam install . --deps-only --with-test
dune runtest
bonsai-flutter run macos
bonsai-flutter build ios --profile release
```

Application repositories must not copy or manually apply the iOS patches from
the `bonsai_flutter` repository.

## Motivation

The current repository proves that OCaml applications can be embedded in
Flutter on macOS arm64 and physical iPhoneOS arm64. It also exposes several
integration details that are unsuitable as a public application workflow:

- application developers must build and stage an OCaml complete object before
  invoking Flutter;
- Flutter `pubspec.yaml` files contain repository-relative
  `native_artifact_root` paths;
- the iPhoneOS closure requires a pinned cross compiler, target libraries,
  source patches, and custom GMP and Zarith recipes;
- build commands are expressed as repository-specific Make targets; and
- a clean external repository does not inherit those tools merely by depending
  on the Flutter packages.

These details should be owned by the framework toolchain. The application
should own its OCaml source, Dune rules, opam manifest, tests, feature selection,
and deployment configuration.

## Goals

- Make OCaml the primary application language and development environment.
- Use `opam`, Dune, S-expressions, and an OCaml CLI in the public workflow.
- Reduce macOS and iPhoneOS application builds to one framework command.
- Keep the Flutter host mechanical and reproducibly generated.
- Keep `bonsai_flutter_native` and its Dart Native Assets hook internal.
- Centralize target closures, patches, custom recipes, and artifact validation.
- Cache the expensive target SDK independently from application source builds.
- Support deterministic source builds and optionally prebuilt signed SDKs.
- Preserve explicit architecture, deployment-target, symbol, and dependency
  audits.

## Non-goals

- Supporting arbitrary opam packages on iPhoneOS without a validated target
  recipe.
- Moving application behavior, networking, retries, persistence, or lifecycle
  policy into Dart.
- Replacing Dune as the OCaml build system.
- Teaching Dune to parse a custom project stanza in the first version.
- Running a full opam closure build inside the Flutter Native Assets hook.
- Adding iOS Simulator, Linux, Windows, or Android support in the first release.
- Creating a public framework-owned HTTP or WebSocket abstraction merely to
  implement the `network` feature profile.

## User-facing repository layout

An external application repository is rooted in its OCaml workspace:

```text
my_app/
├── dune-project
├── my_app.opam
├── bonsai-flutter.sexp
├── app/
│   ├── dune
│   ├── app.ml
│   ├── app.mli
│   └── native_embed.ml
├── test/
│   ├── dune
│   └── app_test.ml
└── flutter/
    ├── pubspec.yaml
    ├── lib/main.dart
    ├── macos/
    └── ios/
```

The application developer normally edits `app/`, `test/`, `dune-project`, the
opam manifest, and `bonsai-flutter.sexp`. The `flutter/` directory is a
generated or synchronized host. It may be checked in for Xcode signing and
platform metadata, but it must contain no application state or transport logic.

## Package boundaries

### `bonsai_flutter` opam package

`bonsai_flutter` remains the OCaml framework package. It provides the runtime,
driver, protocol implementation, UI libraries, and native embedding boundary.

### `bonsai_flutter_tool`

`bonsai_flutter_tool` is an opam package containing the OCaml CLI. It may depend
on:

- `cmdliner` for command parsing;
- `sexplib` for configuration;
- `fpath` for paths;
- `digestif` for cache keys and integrity checks;
- `logs` for structured diagnostics; and
- `eio` for process execution and concurrency.

The installed executable is named `bonsai-flutter`.

### `bonsai_flutter` Flutter package

The Flutter renderer remains a Flutter package. It should transitively depend
on the Dart package that provides FFI bindings and the Native Assets hook, so
ordinary application developers do not need to declare that package directly.

### `bonsai_flutter_native`

`bonsai_flutter_native` remains a Dart package because Flutter Native Assets
hooks use Dart APIs. It is not a public development tool. Its responsibilities
are deliberately narrow:

- locate the staged OCaml complete object;
- verify platform, SDK, architecture, and deployment target;
- link the object into the application native framework;
- export the stable Bonsai Flutter C ABI; and
- add explicitly requested Apple system libraries.

It must not resolve opam packages or build the iPhoneOS runtime closure.

## Project configuration

The project uses a checked-in S-expression file named
`bonsai-flutter.sexp`:

```lisp
(lang 1)

(app
 (name my_app)
 (flutter_root flutter)
 (native_target app/native_embed.exe.o)
 (features network)
 (host
  (mode managed_adapter)
  (adapter lib/application_host_adapter.dart)
  (entrypoint my_app)
  (launch_policy replace_existing))
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
```

The `core` feature is implicit. An application using both secure networking
and SQLite writes:

```lisp
(features network sqlite)
```

Unknown fields, duplicate fields, unsupported schema versions, invalid target
names, and unsupported architectures must fail before any build starts.
macOS supports only minimum version 26.0 on Apple Silicon arm64. Intel Mac and
universal macOS builds are unsupported. iPhoneOS remains minimum 15.0 on
arm64.

### Managed host adapter mode

Every configuration selects the managed adapter mode explicitly:

```lisp
(host
 (mode managed_adapter)
 (adapter lib/application_host_adapter.dart)
 (entrypoint my_app)
 (launch_policy replace_existing))
```

The contract is intentionally small and deterministic:

- `mode` must be `managed_adapter`;
- `adapter` is relative to `flutter_root`, must be a lower-snake-case `.dart`
  path below `lib/`, and must not be `lib/main.dart`;
- `entrypoint` is a non-empty, valid UTF-8 runtime entrypoint of at most 255
  bytes without control characters; and
- `launch_policy` is `fresh` or `replace_existing`.

Absolute paths, parent traversal, backslashes, generated-host ownership,
missing fields, duplicate fields, and unknown fields or enum values are
rejected during configuration parsing. The adapter must export
`BonsaiFlutterHostAdapter createBonsaiFlutterHostAdapter()`. The tool owns
`lib/main.dart` and `test/widget_test.dart`; the application owns the adapter
and every service or codec reachable from it. Fresh `init` creates a minimal
starter only if the configured adapter does not exist. Repeated `init` and
every `sync-host` invocation preserve it byte-for-byte. A configuration that
omits `host` is rejected with an explicit managed-adapter migration error.

## Feature profiles

Feature profiles select validated target capabilities. They are not a
replacement for the application's Dune dependencies.

### `core`

The implicit `core` profile enables the pinned OCaml, Bonsai, Eio, and Bonsai
Flutter platform recipes. The actual target closure is computed from each
application's pinned opam metadata and Dune libraries.

### `network`

The `network` profile authorizes validated iPhoneOS recipes when an
application's resolved closure includes TLS, HTTPS, or WSS packages, including:

- `tls` and `tls-eio`;
- `ca-certs-nss` and `x509`;
- `mirage-crypto-rng`;
- `httpun`, `httpun-eio`, and `httpun-ws`;
- `gluten-eio`; and
- their locked transitive dependencies.

It also selects the framework-owned iPhoneOS recipes for Apple entropy, Darwin
DNS behavior, GMP, and Zarith. Application network ownership and policy remain
in the application OCaml modules.

### `sqlite`

The `sqlite` profile authorizes any selected native archive whose linker
metadata requests Apple system `libsqlite3`. Capability discovery inspects the
artifact for `-lsqlite3`; it does not check for `sqlite3`, DataScript, or any
other package name, and it does not add packages to the application closure.

### Profile validation

The CLI fails during closure resolution when application dependencies require
a capability not present in the selected profile. Pure OCaml libraries using a
supported Dune or Topkg build mechanism are accepted without a package
allowlist. A package that requires an unregistered platform recipe fails before
compilation:

```text
Package foo uses unsupported capability foreign stubs.
Required cross-build recipe: add an explicit entry to closure_capabilities.lock.
```

The generated lock separates host-only PPX executables and generators from
target libraries. Its digest, canonical selected features, and the toolchain
lock digest form the SDK cache identity.

## Command-line interface

### Initialization

```sh
bonsai-flutter init \
  --name my_app \
  --features network \
  --ios-deployment-target 15.0
```

This command creates missing OCaml scaffolding, configuration, and the
mechanical Flutter host. It must not overwrite existing application source.

An adoption mode should support existing repositories:

```sh
bonsai-flutter init --adopt
```

### Environment diagnostics

```sh
bonsai-flutter doctor
bonsai-flutter doctor --target iphoneos
```

Diagnostics cover opam, Dune, Flutter, Xcode, Apple SDKs, supported
architectures, signing readiness, cache integrity, and configured feature
profiles.

### Native build

```sh
bonsai-flutter build-native --target macos
bonsai-flutter build-native --target iphoneos --profile release
```

This command builds and stages only the OCaml complete object. It is useful for
OCaml-focused iteration and CI separation.

### Application run

```sh
bonsai-flutter run macos
bonsai-flutter run ios --device <device-id>
```

The command prepares the correct native artifact and then invokes Flutter with
the generated host.

### Application build

```sh
bonsai-flutter build macos --profile release
bonsai-flutter build ios --profile release
bonsai-flutter build ios --profile release --no-codesign
```

Unknown trailing arguments may be forwarded after `--`:

```sh
bonsai-flutter run macos -- --dart-define=environment=development
```

### Host synchronization

```sh
bonsai-flutter sync-host
bonsai-flutter sync-host --check
```

`--check` must fail when checked-in generated host files differ from the
current tool version without modifying the repository.

### SDK commands

```sh
bonsai-flutter sdk fetch --target iphoneos --features network
bonsai-flutter sdk verify --target iphoneos
bonsai-flutter sdk build-from-source --target iphoneos --features network
```

These commands make downloads and expensive source builds explicit and
cacheable.

## Build orchestration

### macOS

`bonsai-flutter run macos` performs the following steps:

1. Parse and validate `bonsai-flutter.sexp`.
2. Verify the opam switch and exact framework compatibility.
3. Select the validated feature closure.
4. Run Dune for the configured native object target.
5. Stage and audit the complete object.
6. Synchronize the Flutter host if required.
7. Run `flutter pub get` when its inputs changed.
8. Run `flutter run -d macos`.

### iPhoneOS

`bonsai-flutter build ios` performs the following steps:

1. Parse and validate project configuration.
2. Resolve a compatible iPhoneOS native SDK from the cache.
3. Fetch or source-build the SDK when explicitly permitted.
4. Compile only the application OCaml modules against the target sysroot.
5. Produce an arm64 iPhoneOS complete object.
6. Verify Mach-O platform, architecture, and minimum deployment target.
7. Reject prohibited TLS backends and host-path leakage.
8. Stage the object in the Native Assets artifact layout.
9. Synchronize the Flutter host configuration.
10. Invoke `flutter build ios` or `flutter run`.

Code signing remains owned by the generated Xcode project and Flutter/Xcode
commands. The OCaml CLI must not invent signing identities or provisioning
profiles.

## Dune integration

Dune remains responsible for compiling and testing OCaml source:

```sh
dune build
dune runtest
dune build app/native_embed.exe.o
```

The CLI invokes Dune from outside the Dune action graph. Generated Dune rules
must not call `bonsai-flutter` if the CLI would recursively invoke Dune.

The initial implementation should use the explicit `native_target` path in
`bonsai-flutter.sexp`. A future Dune extension may provide a custom stanza only
if it can preserve a non-recursive build graph and stable editor tooling.

## Native artifact layout

The CLI stages artifacts under the OCaml workspace build directory:

```text
_build/bonsai-flutter/native-artifacts/my_app/
├── macos/
│   └── arm64/
│       └── native_embed.exe.o
└── ios/
    └── iphoneos/
        └── arm64/
            └── native_embed.exe.o
```

Mode-specific applications may add `debug/` and `release/` between the
architecture and object name.

The generated Flutter host points `native_artifact_root` at the application
directory above. External repositories must not need absolute paths or paths
into the `bonsai_flutter` source checkout.

## Native SDK distribution

### Preferred path: prebuilt SDK

Each compatible Bonsai Flutter release should publish versioned Apple native
SDK archives such as:

```text
bonsai-flutter-sdk-<version>-macos-arm64.tar.zst
bonsai-flutter-sdk-<version>-iphoneos-arm64.tar.zst
```

An SDK archive contains:

- the compatible OCaml compiler or cross compiler;
- target OCaml standard libraries;
- the validated feature-profile libraries and findlib metadata;
- target GMP and Zarith static libraries when required;
- a machine-readable closure manifest;
- recipe revisions and applied-patch identities; and
- checksums for every staged artifact.

The CLI verifies archive digests before extraction. A release-signature scheme
should be added before third-party binary distribution is considered stable.

### Required fallback: source build

The complete SDK must remain reproducible from locked sources:

```sh
bonsai-flutter sdk build-from-source \
  --target iphoneos \
  --features network
```

The source builder owns all patches and custom recipes. It may reuse the
current repository implementation initially, but no path may assume that the
application lives inside the `bonsai_flutter` checkout.

## Patch ownership

Upstream compatibility patches belong to the versioned native SDK recipe, not
to application repositories. The recipe manifest records the source version,
source digest, patch digest, target, and recipe revision.

For a clean SDK build, the framework tool applies the required patches exactly
once. For a prebuilt SDK, the patches have already been applied and the
application sees only verified target libraries.

When an upstream release includes a fix, the framework should update the
closure, remove the obsolete patch, increment the recipe revision, and rebuild
the SDK. Applications must not carry stale copies of framework patches.

## Caching

The build uses two cache layers.

### Global SDK cache

The global cache stores downloaded or source-built SDKs. Its key includes:

- Bonsai Flutter release and native SDK format version;
- OCaml, Dune, opam, and recipe revisions;
- operating system, SDK, architecture, and deployment target;
- selected feature-profile closure;
- source and patch digests; and
- relevant Xcode SDK identity.

### Project build cache

The project cache stores application compilation outputs. Its key includes:

- the native SDK identity;
- Dune and opam manifest contents;
- application source digests;
- build profile; and
- target configuration.

Changing Flutter-only source must not rebuild OCaml. Changing one application
OCaml module must not rebuild the target dependency closure.

Concurrent builds must use per-key locks and atomic cache publication.

## Generated Flutter host

The generated `flutter/pubspec.yaml` declares the Flutter renderer dependency.
The renderer brings in the internal Native Assets package transitively. The
tool also emits user defines for that internal package, similar to:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      native_artifact_root: ../_build/bonsai-flutter/native-artifacts/my_app/
      ios_deployment_target: '15.0'
      require_ocaml_backend: true
```

When the `sqlite` feature is selected, the tool also emits:

```yaml
      link_system_sqlite3: true
```

The generated `lib/main.dart` selects the configured native entrypoint and
mounts the standard Bonsai Flutter host. It contains no application model,
network client, database policy, retry state, or transport state.

In `managed_adapter` mode, generated startup is equivalent to:

```dart
final applicationPayload = await adapter.createApplicationPayload();
final runtimeConfig = RuntimeBootstrapConfig(
  entrypoint: 'my_app',
  launchPolicy: RuntimeLaunchPolicy.replaceExisting,
  applicationPayload: applicationPayload,
).encode();

final root = BonsaiFlutterRoot(config: runtimeConfig);
return adapter.buildHost(context: context, child: root);
```

The actual generated wrapper supplies loading and bootstrap-error UI and puts
the root in its generated `MaterialApp`. The application payload remains
opaque and may contain any bytes up to the 1 MiB boundary. Application-owned
code validates its inner format. The generated host alone creates the exact
`BFR1` outer envelope, so adapters return only the inner application payload.
This separation leaves Application Support lookup, platform snapshots,
locale/time-zone observation, and application codecs in the application
repository.

Synchronization renders the same managed files for check and write modes.
Repeated writes are idempotent, check mode reports drift without modifying
files, and the configured adapter is never part of the generated output set.

## Continuous integration

A source-based CI workflow can use:

```sh
opam install . --deps-only --with-test --yes
dune build @all
dune runtest
dune build @fmt

bonsai-flutter doctor --target macos
bonsai-flutter build macos --profile release

bonsai-flutter doctor --target iphoneos
bonsai-flutter build ios --profile release --no-codesign
```

A prebuilt-SDK workflow may fetch and verify the SDK in a separate cache step:

```sh
bonsai-flutter sdk fetch --target iphoneos --features network
bonsai-flutter sdk verify --target iphoneos
bonsai-flutter build ios --profile release --no-codesign --offline
```

Public HTTPS and WebSocket services must not become CI dependencies. Network
behavior remains covered by deterministic loopback tests, while explicit public
and signed-device smoke tests remain release gates.

## Diagnostics

Errors should identify the layer, attempted command, relevant target, and a
specific recovery command. Examples include:

```text
The iPhoneOS SDK for Bonsai Flutter 0.1.0 is not cached.
Run:
  bonsai-flutter sdk fetch --target iphoneos --features network
```

```text
The OCaml complete object targets iOS 16.0, but the project requires 15.0.
Set (ios (minimum_version 15.0)) in bonsai-flutter.sexp, then run:
  bonsai-flutter build-native --target iphoneos
```

```text
Package foo is not supported by the selected iPhoneOS feature closure.
Selected features: core, network
```

The CLI must preserve the underlying log in a stable project build directory
while printing a concise terminal summary.

## Migration from the current workflow

The first implementation should consume the existing artifact layout and build
scripts behind a parameterized interface:

1. Remove assumptions about repository-relative example names.
2. Accept an external project root, Dune target, application name, artifact
   root, feature profile, and target.
3. Move closure and patch selection behind a versioned SDK recipe API.
4. Implement `build-native` before wrapping Flutter commands.
5. Generate or adopt the Flutter host and its `native_artifact_root`.
6. Add `run`, `build`, `doctor`, `sync-host`, and SDK commands.
7. Publish prebuilt SDKs only after source reproducibility and integrity checks
   pass in CI.

Existing applications can adopt the tool with:

```sh
bonsai-flutter init --adopt
bonsai-flutter sync-host --check
bonsai-flutter build-native --target macos
```

## Testing strategy

### CLI unit tests

- Parse valid and invalid configuration files.
- Produce stable command plans without running external commands.
- Compute deterministic SDK and application cache keys.
- Validate feature and package compatibility.
- Reject unsupported targets and architectures.
- Preserve user-owned files during initialization and host synchronization.

### Build integration tests

- Create a fixture outside the `bonsai_flutter` repository layout.
- Build a core-only macOS application from a cold cache.
- Rebuild it from a warm cache without rebuilding the closure.
- Build the network profile for macOS arm64.
- Build core, network, and SQLite profiles for iPhoneOS arm64.
- Verify complete-object and final-framework metadata.
- Verify that an application repository contains no copied framework patch.
- Verify offline builds after an explicit SDK fetch.

### Release gates

- Rebuild each published SDK from locked source inputs.
- Compare the rebuilt closure manifest and artifact digests.
- Run deterministic OCaml and Flutter tests.
- Build macOS debug, profile, and release applications.
- Build unsigned iPhoneOS debug, profile, and release applications.
- Run a signed physical-iPhone probe for each capability profile affected by a
  release.

## Security and reproducibility requirements

- Every downloaded SDK and source archive has a locked digest.
- SDK extraction rejects absolute paths and parent traversal.
- Patches have locked digests and explicit source-version applicability.
- iPhoneOS objects are arm64-only and carry the configured minimum version.
- Target objects and frameworks are audited for prohibited host paths and CPU
  flags.
- The network profile rejects OpenSSL, `libssl`, `libcrypto`, `eio-ssl`, Piaf,
  and Secure Transport wrapper dependencies.
- The generated Flutter host contains no Dart networking API.
- Certificate verification cannot be disabled by a feature or CLI flag.
- Offline mode performs no network access.
- Code-signing credentials never enter the SDK cache or build manifest.

## Rejected alternatives

### Dart-first CLI

A `dart run bonsai_flutter_tool ...` workflow would work technically, but it
makes an OCaml application feel like a Dart application and forces developers
to use a secondary ecosystem for core build operations.

### Full compilation in the Native Assets hook

Flutter invokes build hooks frequently and may invoke them concurrently. A full
opam and iPhoneOS closure build inside the hook would create opaque errors,
cache contention, long unexpected builds, and difficult offline behavior.

### Copying patches into every application

This duplicates security-sensitive build logic, prevents coordinated upgrades,
and makes application repositories responsible for upstream source versions
they do not own.

### Dune rules that invoke Flutter

This risks recursive build graphs when the coordinator also invokes Dune and
makes Flutter/Xcode failures appear as opaque Dune action failures.

### Unrestricted target opam solver

An arbitrary host opam solution does not prove that every package has a valid
iPhoneOS build recipe. The public workflow must select a validated target
closure.

## Rollout phases

### Phase 1: Parameterized source builder

- Add the OCaml configuration parser and command planner.
- Parameterize the current macOS and iPhoneOS scripts for external roots.
- Implement `doctor`, `build-native`, and artifact audits.
- Add an external application fixture.

### Phase 2: Managed Flutter host

- Implement `init --adopt` and `sync-host`.
- Generate stable `pubspec.yaml` hook configuration.
- Make the renderer package depend transitively on the Native Assets package.
- Implement `run` and `build` wrappers.

### Phase 3: Feature SDKs and caching

- Define core, network, and SQLite SDK manifests.
- Add global and project cache keys, locks, and atomic publication.
- Add explicit offline behavior.
- Verify cold-cache and warm-cache builds in CI.

### Phase 4: Prebuilt SDK distribution

- Produce versioned macOS arm64 and iPhoneOS arm64 SDK archives.
- Add digest and release-signature verification.
- Preserve the source-build fallback.
- Document license and source-correspondence obligations for redistributed
  static libraries.

## Acceptance criteria

- A clean external application can be initialized without copying framework
  scripts or patches.
- The application uses `opam`, Dune, and `bonsai-flutter` as its documented
  development commands.
- A developer can run macOS with one `bonsai-flutter run macos` command.
- A developer can build iPhoneOS with one `bonsai-flutter build ios` command.
- The generated Flutter host contains no application behavior.
- Application developers do not manually declare or invoke
  `bonsai_flutter_native`; the generated host and transitive renderer dependency
  own that integration.
- Core, network, and SQLite profiles select exact validated target closures.
- A warm build does not rebuild unchanged target dependencies.
- Prebuilt and source-built SDKs expose the same locked manifest.
- macOS and iPhoneOS artifacts pass platform, architecture, deployment-target,
  dependency, and prohibited-symbol audits.
- CI can run completely offline after an explicit SDK fetch.
- Signed physical-device release gates remain available through the OCaml CLI.

## Open questions

- Should `bonsai_flutter_tool` be a separate opam package or ship with the main
  `bonsai_flutter` package?
- Should prebuilt SDKs contain the union of all supported profiles or separate
  archives per profile?
- What release-signature format should protect binary SDK distribution?
- Which package metadata should the CLI inspect to validate feature coverage?
- Should generated Flutter platform directories be committed or regenerated in
  CI?
- What compatibility policy relates CLI, Flutter package, native ABI, SDK
  manifest, and OCaml framework versions?
- What license and source-distribution process is required for static GMP and
  other redistributed libraries?
