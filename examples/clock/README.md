# Clock

Clock demonstrates the application-facing `Bonsai.Cont.Clock` APIs and
presentation-aware frame waits using the runtime-owned logical clock.
The OCaml application owns all time reads, timer state, recurring counters,
event history, and UI construction. Flutter is only the native host.

Run the Flutter application through the consumer build workflow:

```sh
cd examples/clock
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Build the target-qualified unsigned iPhoneOS application:

```sh
cd examples/clock
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

Visible time advances on eligible foreground Flutter frames. Timers do not run
while frame pumping is disabled, and overdue work is observed when foreground
pumping resumes.
