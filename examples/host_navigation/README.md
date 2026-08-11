# Host Effects and Navigation

The OCaml component owns the clipboard-result state, page stack, overlay
visibility, and dialog visibility. Flutter executes clipboard access and
declarative route transitions, then returns typed responses and pop events.

The Flutter application is only a Material shell containing
`BonsaiFlutterRoot`. Platform integrations that need plugins, including URL
launching and file dialogs, are supplied through `HostEffectImplementation`;
headless tests inject a fake implementation.

Build and run this standalone app from the repository root:

```sh
cd examples/host_navigation
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Run the multi-app integration suite with `make integration-test`.

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/host_navigation
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The signed device suite exercises the real clipboard and route-pop paths when
the external signing inputs in `docs/ios-device-testing.md` are available.
iOS Simulator is unsupported.
