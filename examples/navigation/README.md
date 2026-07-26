# Navigation example

The route stack and page identity live in OCaml. Flutter mechanically maps the
page list to a native `Navigator` and returns typed pop events.

```sh
make native-object EXAMPLE=navigation
cd examples/navigation/flutter
flutter run -d macos
```
