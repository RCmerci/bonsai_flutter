# bonsai_flutter_native

This package owns the native-assets and C ABI boundary for `bonsai_flutter`.
It provides the opaque `bf_runtime`, fixed-width status values, owned output
buffers, generated private FFI declarations, and the public `NativeRuntime`
Dart wrapper.

The build hook, buffer ownership tests, and Dart wrapper have been verified on
macOS arm64 with Dart 3.12.2. By default the hook builds the C ABI fallback,
whose runtime calls return an explicit fatal status instead of fabricating a
frame.

A consuming workspace can set the `ocaml_complete_object` hook user define to
a Dune complete object containing the OCaml runtime, application entrypoints,
and the C bridge. The repository integration workspace uses this route to run
a real Bonsai Counter through Flutter on the project OCaml 5.3.0 baseline.
The tested platform scope is documented in the repository README.

Regenerate the private bindings after changing the header:

```sh
dart run ffigen --config ffigen.yaml
```
