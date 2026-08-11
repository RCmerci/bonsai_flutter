# Packaging

The release transport is a batched C ABI loaded through Dart FFI. The Flutter
native package follows Flutter 3.44.8's `package_ffi` build-hook template and
uses `DynamicLoadingBundled` code assets.

## Target-qualified OCaml artifacts

Every application produces a complete object containing its OCaml component
and entrypoint, the OCaml runtime, the shared C bridge, and the exported
`bf_*` ABI. Complete objects are never shared across Apple platforms or SDK
kinds.

The build hook resolves one of these paths below the consumer-local artifact
root managed by `bonsai-flutter`:

| Target | Relative complete-object path | Measured minimum |
| --- | --- | --- |
| macOS arm64 | `macos/arm64/<profile>/native_embed.exe.o` | macOS 26.0 |
| iPhoneOS arm64 | `ios/iphoneos/arm64/<profile>/native_embed.exe.o` | iOS 15.0 |

A consuming workspace owns the surrounding pubspec while the tool synchronizes
the marked package and native-hook regions:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      # bonsai-flutter:begin native-hook
      native_artifact_root: ../_build/bonsai-flutter/artifacts/
      macos_deployment_target: '26.0'
      ios_deployment_target: '15.0'
      require_ocaml_backend: true
      # bonsai-flutter:end native-hook

dependencies:
  # bonsai-flutter:begin packages
  bonsai_flutter:
    path: ../.bonsai-flutter/flutter-packages/bonsai_flutter
  # bonsai-flutter:end packages
```

`exec` temporarily adds `native_artifact_profile` inside the native-hook region
and restores the original pubspec bytes after the child command exits.

The generated macOS host passes the quoted `macos_deployment_target` to the
hook and includes `BonsaiFlutter.xcconfig` from the Debug, Release/Profile, and
Runner configurations. That xcconfig sets `MACOSX_DEPLOYMENT_TARGET = 26.0`
and `ARCHS = arm64`.

Flutter 3.44.8 reports its SDK-level iOS native-assets default to build hooks
instead of the Runner target's `IPHONEOS_DEPLOYMENT_TARGET`. Every repository
workspace therefore passes the quoted `ios_deployment_target` explicitly. The
hook uses it both for C/linker deployment flags and complete-object metadata
validation. It must match `tool/ios/toolchain.lock` and every Runner target.

The resolver inspects the real Mach-O load commands with Apple tools before
linking. It rejects a missing object, wrong architecture, wrong platform,
wrong SDK kind, inconsistent minimum version, Bitcode, and an optional
C-only fallback when `require_ocaml_backend` is true.

Applications that declare `(features sqlite)` in `bonsai-flutter.sexp` opt into
the Apple system SQLite library. The tool writes `link_system_sqlite3: true`
inside the owned native-hook region.

`link_system_sqlite3` is a strict boolean and is accepted only for Apple
targets. The build hook adds `-lsqlite3` only when opted in; every other
application remains free of a SQLite dependency.

## macOS

Build one consumer from its own root:

```sh
cd examples/counter
../../_build/default/bonsai_flutter_tool/bin/main.exe build macos --profile release
```

Run a Flutter command with the matching native profile selected temporarily:

```sh
../../_build/default/bonsai_flutter_tool/bin/main.exe exec --profile=debug -- \
  flutter test --no-pub
```

The macOS contract is minimum 26.0 and Apple Silicon arm64 only. The native
build, staged object verifier, Native Assets hook, and Xcode host all consume
that contract. Intel Mac (`x86_64`) and universal binaries are unsupported;
the hook rejects an x86_64 request before artifact resolution.

## iPhoneOS

The immutable cross SDK uses the fixed global `bonsai-flutter-ios` opam switch
and never changes the developer's active switch:

```sh
dune build bonsai_flutter_tool/bin/main.exe
_build/default/bonsai_flutter_tool/bin/main.exe toolchain install iphoneos
cd examples/counter
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile release --no-codesign
```

`tool/ios/toolchain.lock` pins OCaml 5.1.1, opam-cross-ios, target triples,
deployment settings, and the Jane Street v0.17 release line.
The application SDK resolves each application's pinned opam metadata and Dune
libraries into a deterministic closure lock. The lock pins every version,
source commit or archive, SHA-256 digest, target component, host-only package,
capability, and target dependency. `vendor/opam-ios/runtime-closure.lock` is
the checked-in DataScript SQLite fixture result and verification baseline, not
a fixed union imposed on every application.
`vendor/opam-ios/supported-closure.lock` is the independently generated union
installed in the immutable SDK for the repository's supported core, network,
and SQLite feature families. Each consumer still resolves its own reachable
application closure from pinned metadata and may use only packages present in
that supported SDK closure. Host PPX executables and
generators remain native macOS processes. Their locked descriptions are
available to Dune's cross context, but only resolved target components enter
the iOS artifact set.

Supported pure OCaml packages using Dune or Topkg are cross-compiled without a
framework package allowlist entry. Platform-sensitive packages require an
artifact-derived supported recipe or an explicit recipe in
`tool/ios/closure_capabilities.lock`, plus a matching feature. An unsupported
capability is rejected during closure resolution, before compilation. The SDK
cache key includes canonical features, the application closure digest, and the
toolchain lock digest.

The reference application's metadata pins the SQLite OCaml binding exactly to
`sqlite3` 5.4.0 and pins its DataScript stack independently of the framework.
The resolver recognizes `-lsqlite3` in any selected native archive as the
`System_sqlite` capability and requires the `sqlite` feature without checking
the package name. The target closure stages the arm64 iPhoneOS
`libsqlite3_stubs.a` and application-selected stub archives and metadata
containing `-lsqlite3`; it does not stage a `libsqlite3.a` engine.
SDK-aware pkg-config metadata selects Apple headers and the system library and
is audited against Homebrew, `/usr/local`, macOS SDK, loadable-extension, and
bundled-engine leakage.

The iPhoneOS output is a real arm64 `IOS` complete object with minimum 15.0.
iOS Simulator is intentionally unsupported; use a registered physical iPhone
for iOS execution.

## Flutter iOS framework pipeline

For a compatible iPhoneOS object, the package build hook:

1. selects and verifies the target-qualified complete object;
2. links the object with the iOS-only unavailable-process stubs;
3. strips unreachable code;
4. retains only the nine public `bf_*` bridge symbols;
5. returns a bundled dynamic code asset to Flutter;
6. lets Flutter create, embed, rewrite, and sign
   `bonsai_flutter_native.framework`.

No Podfile, manual framework reference, framework copy phase, static
XCFramework, `DynamicLibrary.process()`, or `-undefined dynamic_lookup` is
used.

The final bundle audit verifies architecture, platform, minimum version,
Bitcode absence, install name, linked-library paths, exact exports, Native
Assets manifest mapping, prohibited process imports, and Profile/Release
dSYM UUIDs. Signed lanes add code-signature, provisioning-profile, Team ID,
App ID, and entitlement checks.

The linked OCaml closure imports file-metadata APIs and a monotonic clock API.
Each iOS Runner therefore includes a minimal privacy manifest with
`NSPrivacyAccessedAPICategoryFileTimestamp` reason `C617.1` and
`NSPrivacyAccessedAPICategorySystemBootTime` reason `35F9.1`. The bundle
verifier requires the corresponding linked symbols, including either
`mach_absolute_time` or `clock_gettime_nsec_np`, and rejects unrelated blanket
reasons.

SQLite applications invoke the verifier's explicit `require-sqlite` mode. It
requires the final framework to import `/usr/lib/libsqlite3.dylib` and real
`_sqlite3_*` symbols while retaining the exact existing `bf_*` export set.
The default mode rejects an unexpected SQLite dependency, which protects
non-SQLite examples from accidental global linkage.

## Current evidence boundary

The repository contains eleven standalone consumer examples. CI analyzes and
tests all eleven through the public tool. The hosted iOS matrix builds Counter,
SQLite Worker, and Network as unsigned iPhoneOS arm64 applications; Counter
Debug, Profile, and Release frameworks pass the repository bundle audit.

Development-signed installation and launch have been verified on a physical
iPhone. Release archive export and distribution signing remain outside the
current support boundary. Unsigned results are packaging evidence, not device
execution evidence.

## Future platforms

Linux will use an ELF shared library, Windows will use a DLL with an explicit
export definition, and Android will package ABI-specific shared objects.
These remain architectural targets rather than support claims.

## Development transport

An optional socket transport may run the same binary protocol against a
standalone OCaml process for reload and diagnostics. It is not a release
transport and cannot alter the UI API, revision rules, or transaction model.
