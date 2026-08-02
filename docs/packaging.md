# Packaging

The release transport is a batched C ABI loaded through Dart FFI. The Flutter
native package follows Flutter 3.44.8's `package_ffi` build-hook template and
uses `DynamicLoadingBundled` code assets.

## Target-qualified OCaml artifacts

Every application produces a complete object containing its OCaml component
and entrypoint, the OCaml runtime, the shared C bridge, and the exported
`bf_*` ABI. Complete objects are never shared across Apple platforms or SDK
kinds.

The build hook resolves one of these paths below an application-specific
`native_artifact_root`:

| Target | Relative complete-object path | Measured minimum |
| --- | --- | --- |
| macOS arm64 | `macos/arm64/native_embed.exe.o` | macOS 26.0 |
| iPhoneOS arm64 | `ios/iphoneos/arm64/native_embed.exe.o` | iOS 13.0 |

A consuming workspace configures the root and makes the real backend
mandatory:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      native_artifact_root: ../../../_build/native-artifacts/counter/
      require_ocaml_backend: true
```

The resolver inspects the real Mach-O load commands with Apple tools before
linking. It rejects a missing object, wrong architecture, wrong platform,
wrong SDK kind, inconsistent minimum version, Bitcode, and an optional
C-only fallback when `require_ocaml_backend` is true.

Applications that use the SQLite binding opt into the Apple system library:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      native_artifact_root: ../../../_build/native-artifacts/sqlite_worker/
      require_ocaml_backend: true
      link_system_sqlite3: true
```

`link_system_sqlite3` is a strict boolean and is accepted only for Apple
targets. The build hook adds `-lsqlite3` only when opted in; every other
application remains free of a SQLite dependency.

## macOS

Build and stage all standalone macOS objects:

```sh
make native-objects
```

The aggregate integration object is separate:

```sh
make integration-native-object
```

The existing OCaml dependency closure is measured at macOS 26.0 and arm64
only. Flutter 3.44.8 links native assets with a lower fixed macOS target, so
the Apple linker reports that the object was built for a newer version. The
repository does not relabel the input object and does not claim compatibility
below the measured macOS 26 host.

## iPhoneOS

The cross environments are isolated below ignored `_build/ios` paths and do
not mutate a developer's default opam switch:

```sh
make ios-toolchains
make ios-device-native-objects
```

`tool/ios/toolchain.lock` pins OCaml 5.1.1, opam-cross-ios, target triples,
deployment settings, and the Jane Street v0.17 release line.
`vendor/opam-ios/runtime-closure.lock` pins the exact runtime
closure by source URL and SHA-256 digest. Host PPX executables and generators
remain native macOS processes; only target metadata and selected target
runtime components enter the iOS sysroot.

The SQLite OCaml binding is pinned exactly to `sqlite3` 5.4.0. The target
closure stages the arm64 iPhoneOS `libsqlite3_stubs.a` binding archive and
metadata containing `-lsqlite3`; it does not stage a `libsqlite3.a` engine.
SDK-aware pkg-config metadata selects Apple headers and the system library and
is audited against Homebrew, `/usr/local`, macOS SDK, loadable-extension, and
bundled-engine leakage.

The iPhoneOS output is a real arm64 `IOS` complete object with minimum 13.0.
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

The repository contains ten standalone examples. All ten examples and the
aggregate integration application build as unsigned iPhoneOS arm64
applications. Counter Debug, Profile, and Release frameworks pass the
repository bundle audit.

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
