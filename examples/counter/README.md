# Counter

The Counter keeps its state, view, and increment handler in
`ocaml/counter.ml`. The Flutter application is only the native host and
`BonsaiFlutterRoot`.

Build the linked OCaml object from the repository root, then run the Flutter
application:

```sh
make native-object EXAMPLE=counter
cd examples/counter/flutter
flutter run -d macos
```

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/counter/flutter
flutter build ios --debug --no-codesign
```

Use `make ci-ios-device IOS_DEVICE_ID=<physical-device-id>` for the signed
device matrix after providing the external signing inputs documented in
`docs/ios-device-testing.md`. iOS Simulator is unsupported.
