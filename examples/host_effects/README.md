# Host effects example

OCaml owns the request flow and rendered result. Flutter supplies the native
clipboard implementation and returns a typed response through the runtime.

```sh
make native-object EXAMPLE=host_effects
cd examples/host_effects/flutter
flutter run -d macos
```
