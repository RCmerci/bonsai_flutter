# Text Input

The canonical document and revision acceptance logic live in
`ocaml/text_input_example.ml`. The Flutter application is a Material shell
containing only `BonsaiFlutterRoot`.

The native integration test sends two local composing edits in one event
batch. OCaml/Bonsai accepts them during one flush and returns one TextInput
property update with the latest accepted local revision. Flutter treats it as
an acknowledgment and preserves the controller, selection, and composing
range.

Build and run this standalone app from the repository root:

```sh
cd examples/text_input
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

The integration test, run with `make integration-test`, simulates editing
values through Flutter's test text input channel.
A distributable macOS runner and physical IME automation remain unclaimed.

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/text_input
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed device suite covers composing text, emoji, and selection when the
external inputs in `docs/ios-device-testing.md` are available. iOS Simulator
is unsupported.
