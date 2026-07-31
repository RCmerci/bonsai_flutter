# bonsai_flutter

`bonsai_flutter` is an OCaml-first native Flutter UI backend for Jane Street
Bonsai. It occupies the same architectural role as `bonsai_web` and
`bonsai_term`, but targets Flutter widgets, elements, render objects, and
platform integrations rather than a DOM or terminal.

The project is under active construction and is not production ready.

## Responsibility boundary

OCaml and Bonsai own application state, computations, the declarative UI
tree, identity, routing, handlers, host-effect orchestration, reconciliation,
and incremental binary frame generation. Dart owns renderer-local resources
and mechanically realizes accepted frames with Flutter.

This is not a `bonsai_web` compatibility layer. It does not use HTML, CSS,
DOM nodes, JavaScript, WebView, Remote Flutter Widgets, JSON in the production
protocol, or application-specific state in Dart.

## Toolchain

The locked OCaml stack is:

- OCaml 5.1.1;
- Dune 3.17 or newer;
- Jane Street packages from the `v0.17.x` release line;
- `ppxlib` 0.35.0.

OCaml 5.1.1 is pinned consistently in `.ocaml-version`, `dune-project`, and
the opam manifests. Host and iPhoneOS builds use the same compiler version and
the same Jane Street release line.

The measured Flutter stack is Flutter 3.44.8 with Dart 3.12.2 and the current
`package_ffi` build-hook model.

### Prepare an OCaml switch

From the repository root:

```sh
opam switch create . ocaml-base-compiler.5.1.1 --no-install
opam install --switch=. . --deps-only --with-test --yes
eval "$(opam env --switch=. --set-switch)"
```

The opam constraints keep Bonsai, Core, and their Jane Street dependency
closure below `v0.18`.

## Minimal Counter

The Counter model, handler, and view all live in OCaml:

```ocaml
module Ui = Bonsai_flutter_ui

let component handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      set_count
      ~f:(fun set_count -> function
        | Event.Payload.Unit -> set_count (fun count -> count + 1)
        | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    Ui.Material.scaffold
      ~app_bar:(Ui.Material.app_bar ~title:(Ui.Widget.text "Counter") ())
      ~body:
        (Ui.Widget.center
           (Ui.Widget.column
              [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
              ; Ui.Material.elevated_button
                  ~on_press:increment
                  ~child:(Ui.Widget.text "Increment")
                  ()
              ]))
      ())
```

The Flutter shell initializes the native runtime and hosts
`BonsaiFlutterRoot`; it has no count variable or increment reducer.

Build and run the macOS arm64 example:

```sh
make native-object EXAMPLE=counter
cd examples/counter/flutter
flutter pub get
flutter run -d macos
```

Each directory under `examples/` owns its OCaml component, native entrypoint,
complete-object target, Flutter shell, and build-hook configuration.
`make native-object EXAMPLE=counter` builds the complete object and stages it
under `_build/native-artifacts/counter/`, where the package build hook links it
into the application. No dylib is copied manually. Run `make native-objects` to
build and stage every standalone example object.

The [`Clock`](examples/clock/README.md) example demonstrates exact,
approximate, and manually sampled logical time, one-shot timers, all four
`Bonsai.Clock.every` policies, and presentation-aware frame waits. Its Dart
shell remains mechanical; OCaml owns the schedules, statuses, history, and UI.

## Testing

Run the complete OCaml 5.1.1 gate:

```sh
make ci-ocaml
```

Run the Flutter renderer, native package, generated binding, example, and
sanitizer gates:

```sh
make ci-flutter
make ci-sanitizers
```

Regenerate or verify the committed cross-language protocol fixtures:

```sh
make protocol-fixtures-generate
make protocol-fixtures-check
```

OCaml owns the output-frame fixtures and Dart owns the renderer-to-runtime
event-batch fixtures. Both CI gates run their respective generator in
`--check` mode so stale bytes fail instead of being rewritten.

On macOS arm64, run the OCaml gate, Counter Debug/Profile/Release builds, and
the real OCaml/Dart/Flutter integration suite:

```sh
make ci-macos
```

Headless application tests use `bonsai_flutter_test` handles and query by
typed test ID, application key, role, visible text, semantics label, or node
kind. They do not use DOM or CSS selectors. See
[`docs/testing.md`](docs/testing.md).

## Native widgets, animation, and text input

Custom native leaves use a registered numeric kind, versioned typed OCaml
properties and events, a generated binary schema, and a typed Dart factory.
Factories retain renderer-local resources by `(runtime_epoch, node_id)`.
See [`docs/custom-widgets.md`](docs/custom-widgets.md).

`Animation.create` and `Widget.animated_opacity` publish a target, duration,
curve, animation ID, and OCaml completion handler. Flutter interpolates with a
node-scoped `AnimationController`; only the final `AnimationCompleted` event
crosses FFI. Reduced-motion updates complete without interpolation. See
[`docs/architecture.md`](docs/architecture.md#semantic-animation).

Text input uses optimistic Flutter-local echo while OCaml remains the
canonical document owner. Edit events carry session, local, base-document,
and document revisions; selection and composing offsets are UTF-16 code-unit
offsets. Stale corrections are rejected and accepted edits are acknowledged
without rewriting the controller. See
[`docs/text-input.md`](docs/text-input.md).

## Platform status

macOS arm64 is tested end to end. On the recorded macOS 26.5.2 arm64 host,
the Counter builds in Debug, Profile, and Release, native symbols and
signatures are verified, and the cross-language integration suite passes.

iPhoneOS arm64 is supported for unsigned packaging with a minimum iOS 13.0.
The locked OCaml 5.1.1 cross compiler builds every standalone example and the
aggregate integration entrypoint, and the resulting complete objects are
audited as platform `IOS`. Signed physical-device execution still requires
repository-external Apple signing material. iOS Simulator is unsupported.

Linux, Windows, and Android remain architectural targets. Flutter Web is out
of scope.

## Examples

The repository contains OCaml-owned Counter, Todo, Text Input, Host Effects,
Navigation, Host Navigation, Gallery, and Bonsai Mail applications under
[`examples`](examples). Their Flutter directories contain only host setup,
renderer registration, and native-library initialization.

## Current limitations and roadmap

- macOS arm64 and unsigned iPhoneOS arm64 packaging are the validated targets.
- The generic virtual-list prototype is intended for cached visible windows,
  not synchronous per-row FFI calls.
- Platform packaging and integration coverage will expand to Linux, Windows,
  Android, and iOS without changing the UI or binary protocol boundary.

Architecture, lifecycle, protocol, packaging, reconciliation, host effects,
and ADR details are under [`docs`](docs).

## License

MIT
