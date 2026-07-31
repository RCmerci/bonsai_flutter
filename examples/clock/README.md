# Clock

Clock demonstrates the application-facing `Bonsai.Cont.Clock` APIs and
presentation-aware frame waits using the runtime-owned logical clock.
The OCaml application owns all time reads, timer state, recurring counters,
event history, and UI construction. Flutter is only the native host.

Build the linked OCaml object from the repository root, then run the Flutter
application:

```sh
make native-object EXAMPLE=clock
cd examples/clock/flutter
flutter run -d macos
```

Build the target-qualified unsigned iPhoneOS application:

```sh
make ios-device-native-objects
cd examples/clock/flutter
flutter build ios --debug --no-codesign
```

Visible time advances on eligible foreground Flutter frames. Timers do not run
while frame pumping is disabled, and overdue work is observed when foreground
pumping resumes.
