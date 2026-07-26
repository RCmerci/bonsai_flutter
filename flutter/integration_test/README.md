# bonsai_flutter Integration Application

This deployable Flutter host exercises the aggregate OCaml application object,
the generated C ABI, the dedicated Dart runtime isolate, reconciliation, and
real Flutter widgets.

Run the verified macOS suite from the repository root:

```sh
make integration-test
```

Build the unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd flutter/integration_test
flutter build ios --debug --no-codesign
```

The signed physical-device matrix is:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

It requires the external signing inputs described in
`docs/ios-device-testing.md`. iOS Simulator is unsupported; run the signed
suite on an explicitly selected physical iPhone.
