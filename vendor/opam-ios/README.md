# iOS runtime closure

This directory contains the checked-in reference application closure. The SDK
generates the same lock format per application; applications do not share a
fixed package union.

`runtime-closure.lock` is generated from
`tool/ios/fixtures/application-closure`. Its pinned opam metadata and Dune
libraries are the roots. The fixture deliberately includes `astring`, a pure
OCaml package that is not named by framework source, as well as these
DataScript-facing libraries:

```text
datascript-ocaml-native
datascript-ocaml-native.sqlite
uutf
uunf
uucp
astring
```

The lock metadata records the row counts and digest derived from its package
rows. The current reference has 121 packages: 69 target packages, 51 host-only
packages, one target-build package, and 106 target findlib components. These
numbers are verification evidence, not constants in the resolver or verifier.
`tool/ios/verify_runtime_closure.sh --check-lock-only` recomputes every count
and the digest before accepting the lock.

Every source URL, source commit, version, and SHA-256 digest is immutable.
`tool/ios/resolve_application_closure.sh` resolves Dune library names through
the pinned host switch, maps them to owning opam packages, and records the
complete target dependency closure in deterministic order. Host-only PPX
executables, generators, and build dependencies are locked separately. Only
their descriptions are projected into the target findlib path; their host
archives, plugins, objects, and executables are not staged.

Packages detected as pure OCaml and built by the supported Dune or Topkg
mechanisms do not need a package allowlist entry. Packages with C or Rust
stubs, networking, entropy, filesystem behavior, system libraries, or another
platform capability must have an explicit entry in
`tool/ios/closure_capabilities.lock`. Resolution fails before compilation with
the package, unsupported capability, and required cross-build recipe when no
safe recipe exists.

The `sqlite` feature gates both `sqlite3` and
`datascript-ocaml-native.sqlite`. The reference lock pins the unchanged
DataScript source at commit
`b1029d6a7210baae15aa2189293bd126b746bad4`, plus the exact persistent sorted
set, Melange EDN, and Melange Transit commits recorded in the lock and
`tool/ios/toolchain.lock`.

The host and target use OCaml 5.1.1 and the same Jane Street v0.17.x release
line. Host executables are never copied into the iOS sysroot or executed as
target programs. Target C and OCaml compilation always runs through the
`ios` findlib toolchain.

Dune resolves installed PPX packages in both its host and cross contexts.
`tool/ios/stage_host_metadata.sh` copies only `META`, `dune-package`, and
`opam` descriptions into the iOS sysroot so that resolution succeeds. It does
not copy host archives, objects, plugins, or executables.

`ocaml-ios64.5.1.1` is the repository-owned opam overlay for the cross
compiler recipe. `tool/ios/prepare_cross_overlay.sh` verifies the template
checksums and derives the full package from the locked opam-cross-ios source.
The installed `ios-cc` wrapper preserves iPhoneOS architecture, sysroot, and
minimum-version metadata for foreign C stubs.

The target closure is built only for iPhoneOS arm64. The SDK cache identity is
the digest of canonical selected features, the per-application closure lock,
and `tool/ios/toolchain.lock`, so different applications and feature profiles
cannot accidentally reuse a target sysroot. iOS Simulator is outside the
repository support boundary.
