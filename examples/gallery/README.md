# Gallery

The Gallery covers the Phase 4 widget slice and the Phase 7 native-extension
slice. Its application state and declarative tree live in `ocaml/gallery.ml`.
The Flutter application contains the Material shell, `BonsaiFlutterRoot`, and
the typed factory registration for custom kind `1001`.

The custom native card owns no application counter in Dart. It retains a
node-scoped `FocusNode`, emits a typed activation event, and displays the
counter value returned by OCaml. The integration test verifies the event and
incremental property update over the real FFI boundary.

Build and run this standalone app from the repository root:

```sh
make native-object EXAMPLE=gallery
cd examples/gallery/flutter
flutter run -d macos
```

The integration workspace also verifies the event flow with
`make integration-test`. Lower macOS deployment targets remain unclaimed.

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/gallery/flutter
flutter build ios --debug --no-codesign
```

The signed physical-device command and prerequisites are documented in
`docs/ios-device-testing.md`. Unsigned packaging does not establish iOS
execution support. iOS Simulator is unsupported.
