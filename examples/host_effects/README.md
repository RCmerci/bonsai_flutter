# Host effects example

OCaml owns the request flow and rendered result. Flutter supplies the native
clipboard implementation and returns a typed response through the runtime.

```sh
make native-object EXAMPLE=host_effects
cd examples/host_effects/flutter
flutter run -d macos
```

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/host_effects/flutter
flutter build ios --debug --no-codesign
```

The real iOS clipboard path is part of the signed physical-device suite in
`docs/ios-device-testing.md`; it has not completed with repository-matching
signing credentials. Unsigned packaging is not an iOS support claim.
