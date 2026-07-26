# Navigation example

The route stack and page identity live in OCaml. Flutter mechanically maps the
page list to a native `Navigator` and returns typed pop events.

```sh
make native-object EXAMPLE=navigation
cd examples/navigation/flutter
flutter run -d macos
```

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/navigation/flutter
flutter build ios --debug --no-codesign
```

See `docs/ios-device-testing.md` for the signed physical-device matrix.
Unsigned packaging is verified. iOS Simulator is unsupported.
