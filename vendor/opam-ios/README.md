# iOS runtime closure

This directory locks the target-side OCaml package closure used by every
`native_embed` complete object and by the aggregate integration complete
object.

`runtime-closure.lock` was generated from these findlib roots in the pinned
OCaml 5.1.1 host switch:

```text
bonsai
bonsai.driver
incr_dom.ui_incr
incr_dom.ui_time_source
virtual_dom.ui_effect
core
sqlite3
eio_posix
threads
unix
```

The closure contains 56 runtime opam source packages and 90 unique locked
findlib components. The compiler supplies `runtime_events`, `threads`, and
`unix`. The `jst-config` row is the only `target-build` dependency; its
generated `config.h` must describe iPhoneOS rather than the macOS host. Exact
Eio `1.2` and `eio_posix` `1.2` packages are included in the target runtime
closure.

Every source URL and SHA-256 digest is immutable. Package ordering is
topological with respect to the selected runtime components. Host-only PPX
executables, generators, test libraries, and unrelated sublibraries are not
staged in the target sysroot.

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

The target closure is built only for iPhoneOS arm64. iOS Simulator is outside
the repository support boundary.
