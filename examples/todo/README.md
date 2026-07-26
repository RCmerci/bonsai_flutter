# Todo

The Todo example keeps the keyed item model, selected item, edits, insert,
delete, and reorder behavior in OCaml. Each editor has a stable application
key and session ID so a keyed reorder preserves its Flutter controller and
focus resource.

```sh
make native-object EXAMPLE=todo
cd examples/todo/flutter
flutter run -d macos
```
