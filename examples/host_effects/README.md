# Host effects example

OCaml owns the request flow and rendered result. Flutter supplies the native
clipboard implementation and returns a typed response through the runtime.

```sh
cd examples/host_effects
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/host_effects
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The real iOS clipboard path is part of the signed physical-device suite in
`docs/ios-device-testing.md`; it has not completed with repository-matching
signing credentials. Unsigned packaging is not an iOS support claim.
