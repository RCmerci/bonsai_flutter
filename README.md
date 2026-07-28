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

- OCaml 5.3.0;
- Dune 3.17 or newer;
- Bonsai and Core `v0.18~preview.130.106+341`;
- `ppxlib` 0.35.0.

OCaml 5.3.0 is the newest stable compiler accepted by the complete selected
dependency graph. The compiler is pinned consistently in `.ocaml-version`,
`dune-project`, and the opam manifests. There is no separate compiler or
reduced-feature build path.

The measured Flutter stack is Flutter 3.44.8 with Dart 3.12.2 and the current
`package_ffi` build-hook model.

### Prepare an OCaml switch

From the repository root:

```sh
opam switch create . ocaml-base-compiler.5.3.0 --no-install
opam repository add --switch=. janestreet-bleeding \
  git+https://github.com/janestreet/opam-repository.git#6789b91abef324f0f9dc2a07332afc4843c7dbe5 \
  --rank=2
opam repository add --switch=. janestreet-bleeding-external \
  git+https://github.com/janestreet/opam-repository.git#a577fc24cba311814e5088a0f6851c65b5cf8dc1 \
  --rank=1

repository_root="$PWD"
basement_source="$(opam var --switch=. prefix)/.bonsai-flutter/basement"
mkdir -p "$(dirname "$basement_source")"
git clone https://github.com/janestreet/basement.git "$basement_source"
git -C "$basement_source" checkout 5c640c230a3989f8e505cda7aa6aca9925a23a5b
git -C "$basement_source" apply \
  "$repository_root/vendor/patches/basement-macos.patch"
opam pin add --switch=. basement "file://$basement_source" \
  --with-version=v0.18~preview.130.106+341 --yes

OCAMLPARAM='_,keywords=4.14' \
  opam install --switch=. . --deps-only --with-test --yes
eval "$(opam env --switch=. --set-switch)"
```

The `OCAMLPARAM` setting is needed only while compiling an upstream source
that uses `effect` as an identifier. Normal project builds do not require it.
The small macOS `basement` patch is documented in
[`vendor/patches`](vendor/patches/README.md).

## Minimal Counter

The Counter model, handler, and view all live in OCaml:

```ocaml
let component handlers graph =
  let count, set_count = Bonsai.state' ~equal:Int.equal 0 graph in
  let increment =
    Bonsai.map set_count ~f:(fun set_count ->
      Driver.Handler.create handlers ~name:"increment" (function
        | Event.Payload.Unit -> set_count (fun count -> count + 1)
        | _ -> Bonsai.Effect.Ignore))
  in
  Bonsai.map2 count increment ~f:(fun count increment ->
    Material.scaffold
      ~app_bar:(Material.app_bar ~title:(Widget.text "Counter") ())
      ~body:
        (Widget.center
           (Widget.column
              [ Widget.text (Printf.sprintf "Count: %d" count)
              ; Material.elevated_button
                  ~on_press:increment
                  ~child:(Widget.text "Increment")
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

## Testing

Run the complete OCaml 5.3.0 gate:

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

macOS arm64 is the only tested platform. On the recorded macOS 26.5.2 arm64
host, the Counter built and launched in Debug, Profile, and Release, the
native symbols and signatures were verified, and real FFI integration tests
passed. A lower macOS deployment target is not claimed because the measured
upstream objects were compiled on macOS 26.

Linux, Windows, Android, and iOS are architectural targets only. They are not
marked supported until their native builds and integration suites pass.
Flutter Web is out of scope.

## Examples

The repository contains OCaml-owned Counter, Todo, Text Input, Host Effects,
Navigation, Host Navigation, Gallery, and Bonsai Mail applications under
[`examples`](examples). Their Flutter directories contain only host setup,
renderer registration, and native-library initialization.

## Current limitations and roadmap

- Only the recorded macOS arm64 host is tested.
- The selected upstream `basement` revision needs the documented macOS patch.
- The generic virtual-list prototype is intended for cached visible windows,
  not synchronous per-row FFI calls.
- Platform packaging and integration coverage will expand to Linux, Windows,
  Android, and iOS without changing the UI or binary protocol boundary.

Architecture, lifecycle, protocol, packaging, reconciliation, host effects,
and ADR details are under [`docs`](docs).

## License

MIT
