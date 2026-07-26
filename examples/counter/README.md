# Counter

The Counter keeps its state, view, and increment handler in
`ocaml/counter.ml`. The Flutter application is only the native host and
`BonsaiFlutterRoot`.

Build the linked OCaml object from the repository root, then run the Flutter
application:

```sh
make native-object EXAMPLE=counter
cd examples/counter/flutter
flutter run -d macos
```
