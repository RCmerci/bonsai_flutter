# Todo

The Todo example keeps the keyed item model, selected item, edits, insert,
delete, and reorder behavior in OCaml. Each editor has a stable application
key and session ID so a keyed reorder preserves its Flutter controller and
focus resource.

```sh
cd examples/todo
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/todo
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed physical-device matrix is documented in
`docs/ios-device-testing.md`. Unsigned packaging is verified; physical
interaction uses Development signing. iOS Simulator is unsupported.
