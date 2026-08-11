# Bonsai Flutter Build Architecture

Status: Proposal

Date: 2026-08-08

## Summary

The Bonsai Flutter build system should treat every application as an ordinary
Dune workspace. Dune owns dependency discovery, compilation, linking, and
incremental rebuild decisions. The `bonsai-flutter` CLI selects the correct
Dune context, validates the toolchain, stages the resulting complete object,
and coordinates Flutter and Xcode.

The design has four strict ownership boundaries:

1. Installed Bonsai Flutter packages and assets are read-only.
2. The iPhoneOS cross-compilation toolchain is a named global opam switch.
3. Every application build output, log, manifest, lock, and temporary workspace
   is inside that application's directory.
4. A normal build never installs, upgrades, or mutates a toolchain.

The fixed iPhoneOS switch name is `bonsai-flutter-ios`. It is visible through
`opam switch list`, is never selected globally by the CLI, and is accessed only
through explicit `opam exec --switch=bonsai-flutter-ios -- ...` invocations.
The name is not configurable in the current design.

## Requirements

### Functional requirements

- macOS and iPhoneOS native complete objects are Dune targets.
- One Dune build command selects one platform alias.
- Dune performs fine-grained incremental compilation.
- An unchanged application build does not rewrite the complete object or its
  staged copy.
- The CLI works when `bonsai_flutter` and `bonsai_flutter_tool` are installed
  packages; a framework source checkout is not required.
- All application build outputs are below the application project directory.
- The iPhoneOS cross switch is a named global opam switch.
- Flutter and Xcode consume only project-local staged artifacts.
- Concurrent builds of different projects do not create shared mutable Dune
  workspaces or application locks.

### Path ownership requirements

The CLI may read installed package files and may read a global opam switch. A
normal build may write only below the application project directory.

The explicit `toolchain install` and `toolchain remove` commands are the only
commands authorized to mutate the global iPhoneOS switch.

### Non-goals

- Building arbitrary, unvalidated opam packages for iPhoneOS.
- Automatically changing the user's active opam switch.
- Selecting an application-local opam switch for iPhoneOS.
- Building framework source through a temporary symlink in an installed package
  directory.
- Maintaining obsolete framework-root build layouts.
- Falling back to a framework source checkout when installed target packages
  are missing.
- Hiding an incompatible or incomplete iPhoneOS toolchain by rebuilding it from
  a normal application build.

## Design principles

### Dune is the only OCaml build graph

The CLI must not maintain its own OCaml source dependency graph. It asks Dune to
build a platform-specific alias and trusts Dune to decide which modules,
libraries, PPX executables, foreign stubs, and link steps are stale.

The alias contains dependencies only. It never invokes `bonsai-flutter`,
Flutter, opam, or another Dune process.

### Installed packages are immutable inputs

An installed `bonsai_flutter` package provides compiled host libraries. The
global iPhoneOS switch provides compiled target libraries. An installed
`bonsai_flutter_tool` package provides the CLI and read-only validation assets.

No command creates `_build`, `external_apps`, locks, symlinks, SDK caches, or
application-specific files below an opam package prefix or its `share`
directory.

### Builds are project-local

The application project is the Dune workspace root for both platforms. The CLI
passes an absolute project-local `--build-dir`. Dune never uses the framework
repository or installed package directory as the workspace root.

### Toolchain changes are explicit

`build-native`, `build`, and `run` treat the iPhoneOS switch as read-only. If it
is missing or incompatible, they fail before invoking Dune and print the exact
recovery command.

## Component model

### Application project

The application owns:

- `dune-project`;
- its opam file;
- its committed `.opam.locked` file;
- `bonsai-flutter.sexp`;
- OCaml source and interfaces;
- the native entrypoint;
- Dune library, executable, and alias stanzas;
- tests;
- generated Flutter host files when those files are checked in; and
- all build output below `_build/`.

### `bonsai_flutter` host package

The host package is installed into the developer's normal application switch.
It supplies macOS-compatible libraries and metadata used for native macOS
builds, editor tooling, tests, and PPX execution.

### `bonsai_flutter-ios-sdk` package universe

The iPhoneOS switch contains one locked and validated package universe. It
includes:

- the OCaml compiler version required by Bonsai Flutter;
- Dune and `ocamlfind` host executables;
- host PPX executables and their host dependencies;
- the `ios` findlib toolchain;
- iPhoneOS arm64 standard-library artifacts;
- iPhoneOS arm64 builds of supported third-party packages;
- an iPhoneOS arm64 build of `bonsai_flutter` itself;
- required foreign archives and platform metadata; and
- a machine-readable SDK manifest.

The switch is not an application workspace. It contains installed packages,
not application source or application Dune output.

### `bonsai_flutter_tool`

The CLI:

- locates and validates an application project;
- resolves the host switch and the configured iPhoneOS switch;
- validates package and SDK manifests;
- computes project-local build paths;
- invokes one Dune build for the selected native target;
- validates and stages the complete object without rewriting identical files;
- synchronizes the mechanical Flutter host when requested; and
- invokes Flutter and Xcode after the native artifact is ready.

It does not compile OCaml source itself and does not resolve package source
during a normal build.

## Global iPhoneOS switch

### Fixed identity

The switch handle is always:

```text
bonsai-flutter-ios
```

With the default opam root, its prefix is normally:

```text
~/.opam/bonsai-flutter-ios/
```

The switch must appear in:

```sh
opam switch list
```

Applications cannot override the switch handle. One opam root contains at most
one active Bonsai Flutter iPhoneOS SDK package universe. Supporting concurrent,
incompatible SDK universes in one opam root is outside the current design.

### Switch layout

The logical layout is:

```text
~/.opam/bonsai-flutter-ios/
├── bin/
│   ├── dune
│   ├── ocamlc
│   ├── ocamlopt
│   ├── ocamlfind
│   └── host PPX executables
├── lib/
│   └── host libraries and metadata
├── lib/ios/
│   ├── target standard library
│   ├── target package metadata
│   ├── target .cmx and .cmxa files
│   └── target .a and foreign object files
└── share/bonsai_flutter_ios_sdk/
    ├── manifest.sexp
    └── package-lock.sexp
```

The exact physical target-library layout may follow the selected cross-compiler
packaging, but it must expose a working `ios` findlib toolchain. Dune must be
able to select it with `-x ios` without an application-specific
`OCAMLFIND_CONF` file.

### SDK manifest

`manifest.sexp` records at least:

- SDK format version;
- Bonsai Flutter version, exact source revision, archive checksum, and ABI
  version;
- OCaml version;
- Dune version range;
- cross-compiler package and version;
- findlib toolchain name, fixed to `ios`;
- target architecture, fixed to `arm64`;
- Apple platform, fixed to `iphoneos`;
- minimum supported deployment target;
- package universe digest;
- installed target component digest;
- required Apple frameworks and system libraries; and
- build recipe revision.

The CLI computes an SDK fingerprint from this manifest. The fingerprint is part
of the project-local Dune build-directory path, so an SDK replacement cannot
reuse stale Dune output.

The manifest also records an explicit mapping from every supported findlib
library to its owning opam package, exact package version, and provided
components. The CLI never guesses package ownership from a library-name prefix.

### Fixed package universe policy

The switch contains one coherent, immutable, and locked package universe. All
applications using the switch must request versions and components contained in
that universe. A normal build cannot extend, resolve, or partially replace the
universe.

Every application commits `<application>.opam.locked`. Before a build, the CLI
resolves the Dune-reachable findlib library closure for `native_target`, maps
each library through the SDK manifest, and compares only the resulting package
subset with the exact versions in `.opam.locked`:

- an exact compatible subset is accepted;
- a missing component is rejected;
- a conflicting package version is rejected; and
- an unsupported foreign capability is rejected.

The CLI does not install a missing package during `build`. The application must
select compatible dependencies. Replacing the SDK universe requires explicitly
removing and reinstalling the fixed switch.

### Toolchain commands

```sh
bonsai-flutter toolchain install iphoneos
bonsai-flutter toolchain verify iphoneos
bonsai-flutter toolchain remove iphoneos
bonsai-flutter toolchain show iphoneos
```

The default install command is conceptually equivalent to:

```sh
opam switch create bonsai-flutter-ios \
  --repositories=bonsai-flutter-ios=<repository>,default \
  <locked-cross-compiler>
opam install --switch=bonsai-flutter-ios bonsai_flutter_ios_sdk
```

The real command must use a signed or digest-locked repository definition and
package set.

Bonsai Flutter publishes a versioned iOS opam repository. Each released CLI
locks the repository URL and exact Git commit. Every package recipe in that
repository locks all fetched source archives with a cryptographic checksum:
SHA-256 when published upstream, otherwise the upstream SHA-512 checksum. The
repository provides one `bonsai_flutter_ios_sdk` meta-package whose exact-version
dependencies define the complete supported compiler and target package
universe. `toolchain install iphoneos` uses only that locked repository commit
and meta-package version; it never resolves against a moving repository head.

The CLI always uses `--switch=bonsai-flutter-ios`. It never runs `opam switch
set`, never links the switch to an application directory, and never changes the
caller's shell environment.

### Immutable lifecycle

The installed switch is immutable. There is no `toolchain update` command and no
package-level mutation workflow. `toolchain install` fails if
`bonsai-flutter-ios` already exists.

Changing the compiler, SDK manifest, Bonsai Flutter release, package universe,
or build recipes requires the explicit sequence:

```sh
bonsai-flutter toolchain remove iphoneos
bonsai-flutter toolchain install iphoneos
bonsai-flutter toolchain verify iphoneos
```

This replacement is intentionally disruptive. Builds fail while the switch is
absent. The CLI must never attempt to preserve compatibility with the removed
universe or mix files from the old and new installations.

The CLI rejects a manifest whose source revision, source checksum, ABI version,
or build recipe revision differs from the framework executable, even when the
advertised package version is unchanged. The diagnostic requires the same
explicit remove-and-install sequence. Repository maintainers regenerate every
derived package and digest through `make ios-sdk-repository`; direct edits to a
single URL, checksum, manifest, or repository digest are not a release path.

## Application Dune contract

### Native complete object

The application defines one native-object executable:

```lisp
(executable
 (name native_embed)
 (modules native_embed)
 (libraries
  app
  bonsai_flutter.driver
  bonsai_flutter.native_backend)
 (link_flags
  (:standard
   -cclib
   -L%{env:BONSAI_FLUTTER_APPLE_SDK_ROOT=}/usr/lib))
 (modes
  (native object)))
```

The complete object is therefore a normal Dune file target:

```text
app/native_embed.exe.o
```

### Platform aliases

The same Dune directory defines aliases with dependencies only:

```lisp
(alias
 (name bonsai-flutter-macos)
 (enabled_if (= %{context_name} default))
 (deps native_embed.exe.o))

(alias
 (name bonsai-flutter-ios)
 (enabled_if (= %{context_name} default.ios))
 (deps native_embed.exe.o))
```

`bonsai-flutter init` creates these stanzas. Subsequent builds validate them but
do not rewrite Dune files. An explicit `bonsai-flutter sync-project` command may
repair generated project integration after showing the affected files.

The CLI must not maintain an alternate direct-target build path. Missing aliases
are configuration errors.

### Exact context selection

The aliases live in `app/dune`, alongside the native-object executable. The CLI
selects a source-relative alias. Each alias's `enabled_if` condition ensures a
cross build does not also request the host version of the object.

The logical aliases are:

```text
@app/bonsai-flutter-macos
@app/bonsai-flutter-ios
```

## Project-local build layout

All build state is below the project root:

```text
my_app/
└── _build/
    └── bonsai-flutter/
        ├── dune/
        │   ├── macos/
        │   │   └── <host-fingerprint>/
        │   │       └── <profile>/
        │   └── iphoneos/
        │       └── <sdk-fingerprint>/
        │           └── <profile>/
        ├── artifacts/
        │   ├── macos/arm64/<profile>/native_embed.exe.o
        │   └── ios/iphoneos/arm64/<profile>/native_embed.exe.o
        ├── state/
        │   ├── macos/<profile>/build-manifest.sexp
        │   └── iphoneos/<profile>/build-manifest.sexp
        ├── logs/
        └── locks/
```

No corresponding mutable directory exists below the installed package prefix,
the Bonsai Flutter source repository, or the global switch.

### Build-directory identity

The build-directory path includes:

- platform;
- architecture;
- Dune profile;
- host package fingerprint for macOS, or SDK fingerprint for iPhoneOS;
- relevant compiler flags; and
- Bonsai Flutter ABI version.

Application source digests are deliberately excluded. Dune tracks source files
inside a stable build directory and performs the incremental rebuild.

Changing a toolchain or ABI selects a new build directory. Changing one OCaml
source file keeps the same build directory and lets Dune rebuild only the
affected dependency cone.

## macOS build

### Prerequisites

- The application is in a host opam environment containing its dependencies.
- `bonsai_flutter` and `bonsai_flutter_tool` are installed in compatible
  versions.
- Xcode exposes the `macosx` SDK.

### Dune invocation

The CLI constructs one command equivalent to:

```sh
opam exec -- dune build \
  --root="$PROJECT_ROOT" \
  --build-dir="$PROJECT_ROOT/_build/bonsai-flutter/dune/macos/$HOST_FINGERPRINT/$PROFILE" \
  --profile="$PROFILE" \
  @app/bonsai-flutter-macos
```

The command environment includes:

```text
BONSAI_FLUTTER_EMBED_OCAML=enabled
BONSAI_FLUTTER_APPLE_SDK_ROOT=<xcrun macosx SDK path>
MACOSX_DEPLOYMENT_TARGET=<configured minimum>
BUILD_PATH_PREFIX_MAP=<project root>=.
```

The Dune workspace root and physical build directory are both application-owned.

### Output handling

The CLI locates the complete object in the selected Dune build context, verifies
its platform, architecture, deployment target, imports, and ABI symbols, then
stages it at:

```text
_build/bonsai-flutter/artifacts/macos/arm64/<profile>/native_embed.exe.o
```

Staging uses an atomic content comparison:

- identical destination: do nothing;
- changed or absent destination: write a temporary sibling, verify it, then
  rename it atomically.

An unchanged build therefore preserves both the Dune object's timestamp and the
staged artifact's timestamp.

## iPhoneOS build

### Prerequisites

- The global `bonsai-flutter-ios` switch exists.
- The switch SDK manifest is compatible with the CLI and application.
- All reachable target libraries are present in the locked target universe.
- Xcode exposes the `iphoneos` SDK.

### Preflight

Before invoking Dune, the CLI performs read-only checks:

1. `opam switch show --switch=bonsai-flutter-ios` succeeds.
2. The expected compiler, Dune, `ocamlfind`, and SDK manifest exist.
3. `ocamlfind -toolchain ios` resolves the target compiler and libraries.
4. The target standard library is iPhoneOS arm64.
5. The application library closure is a compatible subset of the manifest.
6. The configured deployment target is supported.
7. The Apple SDK and required system libraries are available.

Any failure stops before Dune and reports an explicit `toolchain` recovery
command. A build never repairs the switch implicitly.

### Dune invocation

The CLI constructs one command equivalent to:

```sh
opam exec --switch=bonsai-flutter-ios -- \
  dune build \
  --root="$PROJECT_ROOT" \
  --build-dir="$PROJECT_ROOT/_build/bonsai-flutter/dune/iphoneos/$SDK_FINGERPRINT/$PROFILE" \
  --profile="$PROFILE" \
  -x ios \
  @app/bonsai-flutter-ios
```

The command environment includes:

```text
BONSAI_FLUTTER_EMBED_OCAML=enabled
BONSAI_FLUTTER_APPLE_SDK_ROOT=<xcrun iphoneos SDK path>
SDK=<xcrun iphoneos SDK version>
VER=<configured iOS minimum>
BUILD_PATH_PREFIX_MAP=<project root>=.
```

There is no temporary application symlink, external framework workspace, custom
`OPAMROOT`, project-local switch, or application-specific `OCAMLFIND_CONF`.

Host PPX executables run in Dune's host context. Application modules and linked
libraries are compiled or selected in `default.ios` through the installed `ios`
toolchain.

### Output handling

The CLI verifies the cross-context complete object and stages it at:

```text
_build/bonsai-flutter/artifacts/ios/iphoneos/arm64/<profile>/native_embed.exe.o
```

Verification covers:

- Mach-O platform `IOS`;
- architecture `arm64`;
- configured minimum deployment target;
- exact Bonsai Flutter ABI symbols;
- absence of removed ABI symbols;
- required system-library imports;
- prohibited host libraries and backends; and
- prohibited absolute host paths.

## Full Flutter builds

`bonsai-flutter build macos` and `bonsai-flutter build ios` execute these layers:

1. Validate project and toolchain state.
2. Synchronize the mechanical Flutter host into the application project.
3. Invoke the single platform Dune alias build.
4. Verify and stage the complete object in the application project.
5. Run `flutter pub get` only when dependency inputs require it.
6. Run the platform Flutter build.
7. Let the Native Assets hook link the staged complete object.
8. Verify the produced application bundle.

Flutter, Dart, Native Assets, Xcode, and code-signing output remains below the
application's Flutter and `_build` directories. No layer writes into the
installed Bonsai Flutter package or its source repository.

## Incremental-build contract

### Inputs tracked by Dune

Dune tracks:

- application `.ml` and `.mli` files;
- application Dune files;
- PPX inputs and executables;
- installed library metadata and archives;
- native embedding foreign stubs;
- compiler and linker flags referenced by Dune rules;
- deployment-target environment variables referenced by the rules; and
- the selected build context and profile.

### Expected rebuild behavior

| Change | Expected work |
|---|---|
| No input change | No OCaml compilation or complete-object relink |
| One implementation change | Recompile that module and its dependent modules; relink |
| One interface change | Recompile the affected dependency cone; relink |
| Dune dependency change | Re-evaluate and rebuild the affected graph |
| Deployment target change | Select a different build identity or relink affected objects |
| SDK fingerprint change | Select a fresh iPhoneOS Dune build directory |
| Profile change | Use an independent profile build directory |
| Flutter-only source change | Reuse the staged OCaml artifact |

The CLI must not touch source files or generated Dune integration during a
normal build. Touching a Dune file on every invocation would invalidate Dune's
incremental model.

## Configuration

The relevant project configuration is explicit:

```lisp
(lang 1)

(app
 (name my_app)
 (native_target app/native_embed.exe.o)
 (macos
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (minimum_version 15.0)
  (architectures arm64)))
```

The CLI validates that `native_target` is the dependency of both required
aliases. The iPhoneOS switch is fixed to `bonsai-flutter-ios` and is not a
project configuration field.

## Locking and concurrency

### Normal builds

Dune owns locking for each project-local build directory. The CLI adds only
project-local locks for staging and Flutter orchestration.

Different applications use different physical build directories and may build
concurrently while reading the same global switch.

### Toolchain mutation

Toolchain installation and removal use opam's global switch locking. They must
not run concurrently with a build using that switch. The CLI reports the
conflict rather than copying the switch or mutating a project. There is no
in-place update operation.

## Cleaning

Project cleaning is explicit and cannot affect global state:

```sh
bonsai-flutter clean macos
bonsai-flutter clean iphoneos
bonsai-flutter clean --all-project-builds
```

These commands delete only paths resolved below:

```text
<project>/_build/bonsai-flutter/
```

Global toolchain removal requires:

```sh
bonsai-flutter toolchain remove iphoneos
```

No project clean command invokes `opam switch remove`.

## Failure behavior

Failures identify the ownership layer and recovery action.

Examples:

```text
The global iPhoneOS switch "bonsai-flutter-ios" is missing.
Run: bonsai-flutter toolchain install iphoneos
```

```text
The iPhoneOS switch SDK manifest is incompatible with bonsai-flutter 0.2.0.
Run:
  bonsai-flutter toolchain remove iphoneos
  bonsai-flutter toolchain install iphoneos
```

```text
Package foo.2.0 is not in the fixed iPhoneOS SDK package universe.
Select a dependency version provided by bonsai-flutter-ios.
```

```text
The application must define @app/bonsai-flutter-ios as a dependency-only alias
for app/native_embed.exe.o.
Run: bonsai-flutter sync-project --check
```

The CLI never responds to these errors by searching for a framework checkout,
creating files in an installed package, or silently compiling a new SDK.

## Removed architecture

This design removes the following paths and concepts rather than maintaining
compatibility layers:

- `<framework-root>/_build/ios/`;
- `<framework-root>/external_apps/`;
- application symlinks inside a framework workspace;
- framework-root Dune builds for external applications;
- project-local iPhoneOS opam roots and switches;
- application-specific target library caches outside opam;
- implicit SDK construction during `build-native`;
- profile-less staged native artifacts; and
- direct native-target builds that bypass the platform aliases.

## Testing strategy

### Unit tests

- Fixed switch resolution and rejection of project-level switch overrides.
- Project-local path construction and traversal rejection.
- SDK manifest compatibility and fingerprinting.
- Alias-contract validation.
- Exact Dune command plans for each platform and profile.
- Rejection of any planned write outside the project during normal builds.
- Content-preserving staging.

### Integration tests

- Install the CLI and framework into a temporary read-only opam prefix.
- Create a named global `bonsai-flutter-ios` fixture switch.
- Build an external application with no framework source checkout.
- Confirm every changed path is below the application or the explicitly created
  global switch.
- Run an unchanged macOS build twice and compare Dune object timestamps and
  digests.
- Run an unchanged iPhoneOS build twice and compare Dune object timestamps and
  digests.
- Change one leaf implementation and confirm only its dependency cone rebuilds.
- Change an interface and confirm its dependents rebuild.
- Build two applications concurrently against the same read-only iPhoneOS
  switch.
- Make the installed package prefix read-only and repeat both platform builds.

### Release tests

- Reproduce the global iPhoneOS switch from its locked repository and manifest.
- Verify all target archives are iPhoneOS arm64 and contain no host-path leaks.
- Verify a physical-device application built entirely from installed packages.
- Verify incompatible SDK failure and the explicit remove-then-install
  replacement workflow.

## Acceptance criteria

The design is complete when all of the following are true:

- `bonsai-flutter build-native --target macos` invokes one Dune alias build.
- `bonsai-flutter build-native --target iphoneos` invokes one Dune cross-context
  alias build.
- Every application commits its generated `.opam.locked` file.
- Repeating either command with unchanged inputs does not rebuild or rewrite the
  complete object.
- The framework source repository is not needed by an installed application.
- A read-only installed package prefix supports both builds.
- Every normal-build write is below the application root.
- `opam switch list` shows `bonsai-flutter-ios` after explicit installation.
- The switch name cannot be overridden by project configuration.
- The installed switch cannot be updated in place.
- A normal build never changes the global switch.
- Two projects can build concurrently against the same switch.
- Flutter consumes only project-local artifacts.

## References

- [Dune cross-compilation](https://dune.readthedocs.io/en/stable/cross-compilation.html)
- [Dune aliases](https://dune.readthedocs.io/en/stable/reference/aliases.html)
- [Dune command-line usage and custom build directories](https://dune.readthedocs.io/en/stable/usage.html)
- [opam switch manual](https://opam.ocaml.org/doc/man/opam-switch.html)
- [opam usage guide](https://opam.ocaml.org/doc/Usage.html)
