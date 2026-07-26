# bonsai_flutter_native

This package owns the native-assets and C ABI boundary for `bonsai_flutter`.
It provides the opaque `bf_runtime`, fixed-width status values, owned output
buffers, generated private FFI declarations, and the public `NativeRuntime`
Dart wrapper.

The build hook, buffer ownership tests, and Dart wrapper have been verified on
macOS arm64 and as unsigned iPhoneOS arm64 artifacts with Dart 3.12.2. By
default the hook builds the C ABI fallback, whose runtime calls return an
explicit fatal status instead of fabricating a frame.

A consuming workspace sets a target-qualified `native_artifact_root` and makes
the backend mandatory:

```yaml
hooks:
  user_defines:
    bonsai_flutter_native:
      native_artifact_root: ../../../_build/native-artifacts/counter/
      require_ocaml_backend: true
```

The root contains separate `macos/arm64/native_embed.exe.o` and
`ios/iphoneos/arm64/native_embed.exe.o` artifacts. The hook inspects the real
Mach-O metadata and rejects the wrong platform, SDK kind, architecture,
minimum version, Bitcode, missing backend, or backend that does not expose the
exact bridge contract.

The repository integration workspace uses this route to run a real Bonsai
Counter through Flutter on the project OCaml 5.3.0 baseline. iPhoneOS unsigned
packaging and development-signed device launch are verified as documented in
`docs/ios-device-testing.md`. iOS Simulator is unsupported. The public
platform scope remains defined by the repository README.

Regenerate the private bindings after changing the header:

```sh
dart run ffigen --config ffigen.yaml
```
