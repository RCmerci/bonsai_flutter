# iOS runtime closure

This directory locks the target-side OCaml package closure used by every
`native_embed` complete object and by the aggregate integration complete
object.

`runtime-closure.lock` was derived from these findlib roots in the pinned
OCaml 5.3.0 host switch:

```text
bonsai
bonsai.driver
bonsai_concrete.ui_incr
core
threads
unix
```

The closure contains 55 runtime opam source packages and 102 target findlib
components. The lock lists 100 package components; the compiler supplies
`threads` and `unix`, so they do not have separate source-package rows. The
additional `jst-config` row is a `target-build` dependency whose generated
`config.h` must describe the Apple target rather than the macOS host. A
`dual` package provides both a native host PPX or generator and one or more
target runtime components. Only the components listed in the final column
may be staged in the iOS sysroot.

The source URL and SHA-256 digest in every row are immutable. The Basement
row records the unmodified upstream archive. The build applies
`vendor/patches/basement-macos.patch` after verifying that archive and before
compiling it for either Apple target.

Package ordering is topological with respect to the selected findlib runtime
components. It is not the larger opam package-level dependency closure:
package-level metadata includes host-only PPX executables, generators, test
libraries, JavaScript libraries, and unrelated sublibraries that are not
linked into a native embed object.

The host context uses the same package versions and pinned Jane Street opam
repositories as `tool/ios/toolchain.lock`. Host executables are never copied
to the iOS sysroot or executed as target programs. Target C and OCaml
compilation must always run through the `ios` findlib toolchain with an
explicit `VER`; the pinned cross wrapper otherwise defaults to iOS 15.0.

Dune resolves an installed PPX in both its host and cross contexts before it
selects the native host executable. `tool/ios/stage_host_metadata.sh` copies
only `META`, `dune-package`, and `opam` descriptions into the iOS sysroot so
that resolution succeeds. It does not copy any host archive, object, plugin,
or executable. The PPX driver itself therefore remains a macOS host process,
while generated OCaml is compiled only by the target compiler.

The target closure is built only for iPhoneOS. iOS Simulator is intentionally
outside the repository support boundary.
