# bonsai_flutter_native

This package owns the native-assets and C ABI boundary for `bonsai_flutter`.
It provides the opaque `bf_runtime`, fixed-width status values, owned output
buffers, generated private FFI declarations, and the public `NativeRuntime`
Dart wrapper.

The current version contract is native ABI 2.0 and renderer protocol 2.26.
The package queries and validates them independently before runtime creation.

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
      macos_deployment_target: '26.0'
      ios_deployment_target: '15.0'
      require_ocaml_backend: true
```

The root contains separate `macos/arm64/native_embed.exe.o` and
`ios/iphoneos/arm64/native_embed.exe.o` artifacts. The hook inspects the real
Mach-O metadata and rejects the wrong platform, SDK kind, architecture,
minimum version, Bitcode, missing backend, or backend that does not expose the
exact bridge contract.

The macOS contract is minimum 26.0 and Apple Silicon arm64 only. The hook
rejects Intel (`x86_64`) before resolving an artifact, and universal macOS
builds are unsupported. iPhoneOS remains minimum 15.0 on physical-device
arm64.

The repository integration workspace uses this route to run a real Bonsai
Counter through Flutter on the project OCaml 5.1.1 baseline. iPhoneOS unsigned
packaging and development-signed device launch are verified as documented in
`docs/ios-device-testing.md`. iOS Simulator is unsupported. The public
platform scope remains defined by the repository README.

Regenerate the private bindings after changing the header:

```sh
dart run ffigen --config ffigen.yaml
```
