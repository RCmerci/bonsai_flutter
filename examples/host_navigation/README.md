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
make native-object EXAMPLE=host_navigation
cd examples/host_navigation/flutter
flutter run -d macos
```

Run the multi-app integration suite with `make integration-test`.

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/host_navigation/flutter
flutter build ios --debug --no-codesign
```

The signed device suite exercises the real clipboard and route-pop paths when
the external signing inputs in `docs/ios-device-testing.md` are available.
iOS Simulator is unsupported.
