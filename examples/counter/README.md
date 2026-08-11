# Counter

The Counter keeps its state, view, and increment handler in
`ocaml/counter.ml`. The Flutter application is only the native host and
`BonsaiFlutterRoot`.

Run the Flutter application through the consumer build workflow:

```sh
cd examples/counter
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/counter
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

Use `make ci-ios-device IOS_DEVICE_ID=<physical-device-id>` for the signed
device matrix after providing the external signing inputs documented in
`docs/ios-device-testing.md`. iOS Simulator is unsupported.
