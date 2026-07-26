# bonsai_flutter

This package is the typed Flutter-side renderer for the `bonsai_flutter`
project. OCaml and Bonsai own application state, declarative UI,
reconciliation, and event handlers. Dart validates binary frames, commits them
atomically to a `NodeStore`, and will host the corresponding native Flutter
widgets.

The current development release contains:

- typed core, text-input, navigation, host-effect, and native-extension frame
  models;
- bounded little-endian frame encoding and decoding;
- strict protocol, UTF-8, epoch, revision, and graph validation;
- copy-on-write frame application with per-node dirty notifications;
- OCaml-produced frame fixtures decoded by Dart and Dart-produced event
  fixtures decoded by OCaml, with byte-for-byte clean checks;
- keyed per-node widget hosts and a typed application extension registry;
- subtree-local rebuilds and typed Button event dispatch;
- bounded event batching, ordered-event backpressure, and state coalescing;
- a dedicated runtime isolate and native owned-buffer transport boundary;
- node-scoped text-input, focus, scroll, animation, and native resource
  disposal;
- Flutter-local semantic opacity interpolation with typed completion events
  and reduced-motion handling;
- a 50,000-item windowed VirtualList prototype.

The default native package build reports an unavailable-backend fatal status
unless an application supplies the opt-in linked OCaml complete object. The
macOS arm64 integration workspace exercises that real backend. This package is
not production ready.

Run the package checks with:

```sh
dart analyze
NO_PROXY=127.0.0.1,localhost flutter test
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/generate_input_fixtures.dart --check
```
