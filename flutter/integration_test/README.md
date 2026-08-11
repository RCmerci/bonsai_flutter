# bonsai_flutter Integration Application

This deployable Flutter host exercises the aggregate OCaml application object,
the generated C ABI, the dedicated Dart runtime isolate, reconciliation, and
real Flutter widgets.

The `ocaml/` directory owns integration-only snapshots of the example
components exercised by this aggregate host. They are local Dune modules, not
dependencies on sibling example packages, so both macOS and iPhoneOS builds
remain self-contained consumer builds. Update a snapshot deliberately when an
integration assertion adopts changed example behavior.

Run the verified macOS suite from the repository root:

```sh
make integration-test
```

Build the unsigned iPhoneOS application:

```sh
cd flutter/integration_test
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed physical-device matrix is:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

It requires the external signing inputs described in
`docs/ios-device-testing.md`. iOS Simulator is unsupported; run the signed
suite on an explicitly selected physical iPhone.

Run the warmed Mail interaction performance gate on the same device:

```sh
../../_build/default/bonsai_flutter_tool/bin/main.exe exec --profile=profile -- \
  flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/mail_profile_test.dart \
  --driver test_driver/mail_profile_test.dart \
  --timeout 600
```

The driver performs two warm-up repetitions and measures twenty repetitions
for each route and swipe interaction group. It writes the verified frame
summary to `build/mail_profile_summary.json`.
