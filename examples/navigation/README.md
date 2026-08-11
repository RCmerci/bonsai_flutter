# Navigation example

The route stack and page identity live in OCaml. Flutter mechanically maps the
page list to a native `Navigator` and returns typed pop events.

```sh
cd examples/navigation
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/navigation
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

See `docs/ios-device-testing.md` for the signed physical-device matrix.
Unsigned packaging is verified. iOS Simulator is unsupported.
