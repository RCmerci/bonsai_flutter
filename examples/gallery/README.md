# Gallery

The Gallery covers the complete core Material 3 component matrix and the
native-extension slice. Its application state and declarative tree live in
`ocaml/gallery.ml`.
The Flutter application contains the Material shell, `BonsaiFlutterRoot`, and
the typed factory registration for custom kind `1001`.

The custom native card owns no application counter in Dart. It retains a
node-scoped `FocusNode`, emits a typed activation event, and displays the
counter value returned by OCaml. The integration test verifies the event and
incremental property update over the real FFI boundary.

Build and run this standalone app from the repository root:

```sh
cd examples/gallery
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

The integration workspace also verifies the event flow with
`make integration-test`. macOS deployment targets below 26.0, Intel Mac, and
universal builds are unsupported.

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/gallery
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed physical-device command and prerequisites are documented in
`docs/ios-device-testing.md`. Unsigned packaging does not establish iOS
execution support. iOS Simulator is unsupported.
