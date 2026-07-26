# Packaging

The release transport is a batched C ABI loaded through Dart FFI. The Flutter
native package follows Flutter 3.44's `package_ffi` build-hook template.

## macOS

Each application produces its own arm64 complete object containing its OCaml
component and entrypoint, the OCaml runtime, the shared C bridge, and the
exported `bf_*` ABI:

```sh
make native-object EXAMPLE=counter
```

The consuming Flutter workspace selects that object with a package build-hook
user define:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      ocaml_complete_object: path/to/examples/counter/ocaml/native_embed.exe.o
```

`hook/build.dart` passes the complete object to the compiler driver, registers
the resulting dylib as a code asset, and lets Flutter copy and ad-hoc sign the
test artifact. No manual dylib copy is involved. Every standalone example
selects the object under its own directory. The checked-in
`flutter/integration_test` workspace uses a separate test-only aggregate
object so one test process can exercise several entrypoints.

Without `ocaml_complete_object`, the hook builds only the stable C ABI
fallback. That artifact reports that the OCaml backend is not linked; it does
not fabricate frames.

The Counter application has built, launched, and passed code-signing checks in
Debug, Profile, and Release on the recorded macOS 26 arm64 host with the
project OCaml 5.3.0 baseline. The package build hook links and bundles the
native asset without a manual dylib copy.

The measured OCaml and Jane Street objects inherit the macOS 26 build host.
Setting a lower link target on only the final object does not prove backward
compatibility, so no lower deployment version is claimed until the complete
dependency set is rebuilt and run there.

## Future platforms

- Linux will use an ELF shared library built for x64 or arm64.
- Windows will use a DLL with an explicit export definition for x64 or arm64.
- Android will package ABI-specific shared objects for arm64 and x64.
- iOS will use a statically linkable native archive or framework compatible
  with device arm64 and simulator targets.

These are architectural targets, not support claims.

## Development transport

An optional socket transport may run the same binary protocol against a
standalone OCaml process for reload and diagnostics. It is not a release
transport and cannot alter the UI API, revision rules, or transaction model.
