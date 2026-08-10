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
        (Ui.Widget.Body.static
           (Ui.Widget.center
              (Ui.Widget.column
                 [ Ui.Widget.text (Printf.sprintf "Count: %d" count)
                 ; Ui.Material.elevated_button
                     ~on_press:increment
                     ~child:(Ui.Widget.text "Increment")
                     ()
                 ])))
      ())
```

Scrollable widgets use axis-specific viewport types and must enter a bounded
body slot or receive an explicit finite extent. See
[`docs/viewport-layout.md`](docs/viewport-layout.md).

The Flutter shell initializes the native runtime and hosts
`BonsaiFlutterRoot`; it has no count variable or increment reducer.

Build and run the macOS 26.0+ Apple Silicon arm64 example:

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

## OCaml-first application tooling

The `bonsai_flutter_tool` opam package installs the `bonsai-flutter`
executable. A development checkout can pin the framework and tool together:

```sh
opam pin add --no-action bonsai_flutter .
opam pin add --no-action bonsai_flutter_tool .
opam install bonsai_flutter bonsai_flutter_tool
```

Initialize an external OCaml workspace and its managed macOS/iOS Flutter host:

```sh
mkdir my_app && cd my_app
bonsai-flutter init --name my_app --ios-deployment-target 15.0
dune runtest
bonsai-flutter doctor --target macos
bonsai-flutter build macos --profile release
```

Run Flutter or Xcode tests through the same native-artifact profile gate. The
wrapped command runs unchanged from the caller's current directory, so invoke
Flutter commands from the generated Flutter directory and Xcode commands from
its `macos` directory:

```sh
cd flutter
bonsai-flutter exec --profile=debug -- flutter test --no-pub test
bonsai-flutter exec --profile=debug -- \
  flutter test --no-pub -d macos integration_test/runtime_flow_test.dart

cd macos
bonsai-flutter exec --profile=debug -- \
  xcodebuild test -workspace Runner.xcworkspace -scheme Runner
```

`exec` holds the project Flutter build lock, builds the selected macOS native
artifact, temporarily selects that profile in the generated `pubspec.yaml`,
and preserves the wrapped command's exit status. It restores the exact original
manifest after success, failure, or an interrupt, keeping `sync-host --check`
clean.

Profile and Release `build` and `run` commands for both macOS and iOS always
pass `--no-tree-shake-icons`. Bonsai Flutter icon code points arrive through
runtime protocol frames, so Flutter's static Dart `IconData` scan cannot know
which Material icons the application will use. Retaining the complete
`MaterialIcons-Regular.otf` is therefore part of the framework contract and
costs approximately 1.6 MB uncompressed. Forwarded duplicates are removed,
and a forwarded `--tree-shake-icons` cannot override this requirement. Debug
keeps Flutter's default behavior, which already retains the complete font. The
policy lives only in command construction and does not modify generated host
files.

Install and verify the immutable global iPhoneOS SDK before building an iOS
application:

```sh
bonsai-flutter toolchain install iphoneos
bonsai-flutter toolchain verify iphoneos
bonsai-flutter build ios --profile release --no-codesign
```

The versioned SDK repository pins its commits, exact package versions, source
checksums, target components, and `bonsai_flutter_ios_sdk` meta-package.
Applications commit their generated `.opam.locked` file. Native builds validate
only the Dune-reachable package subset, then select `@app/bonsai-flutter-macos`
or `@app/bonsai-flutter-ios`. They never mutate or rebuild the installed SDK,
and unchanged inputs leave both the Dune object and staged artifact untouched.

`bonsai-flutter sync-host --check` verifies generated Dart, Native Assets
configuration, the Apple privacy manifest, and its Xcode resource reference
without modifying the application. The generated host depends only on the
public renderer package; the renderer brings in `bonsai_flutter_native`
transitively. Application behavior remains in OCaml.

Applications configure their asynchronous, application-owned bootstrap
payload through the required managed adapter host:

```lisp
(host
 (mode managed_adapter)
 (adapter lib/application_host_adapter.dart)
 (entrypoint my_app)
 (launch_policy replace_existing))
```

The adapter file exports `createBonsaiFlutterHostAdapter()`, implements
`BonsaiFlutterHostAdapter`, and remains application-owned. Synchronization
continues to replace the generated `lib/main.dart`, but it never modifies the
adapter. Fresh initialization creates a starter only when the configured file
does not exist. The generated host awaits the payload, wraps it in the
versioned `RuntimeBootstrapConfig` (`BFR1`) envelope, and passes the encoded
bytes to `BonsaiFlutterRoot`. A configuration without `host` is rejected with
a migration error. See the renderer package README for a complete adapter
example. The adapter may also provide a bounded opaque-byte application bridge
for asynchronous requests and ordered unsolicited events. See
[`docs/application-platform.md`](docs/application-platform.md).

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

On macOS 26.0+ arm64, run the OCaml gate, Counter Debug/Profile/Release builds, and
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

macOS 26.0 or newer on Apple Silicon arm64 is supported and tested end to end.
On the recorded macOS 26.5.2 arm64 host, the Counter builds in Debug, Profile,
and Release, native symbols and signatures are verified, and the
cross-language integration suite passes. Intel Mac (`x86_64`) and universal
macOS builds are unsupported.

iPhoneOS arm64 is supported with a minimum iOS 15.0.
The locked OCaml 5.1.1 cross compiler builds every standalone example and the
aggregate integration entrypoint, and the resulting complete objects are
audited as platform `IOS`. Development signing, installation, OCaml callback
execution, and the Eio Worker Phase 0 probe have passed on a physical iPhone.
Reproduction still requires repository-external Apple signing material. iOS
Simulator is unsupported.

Linux, Windows, and Android remain architectural targets. Flutter Web is out
of scope.

## Examples

The repository contains OCaml-owned Counter, Clock, Todo, Text Input, Host
Effects, Navigation, Host Navigation, Gallery, Bonsai Mail, SQLite Worker Todo,
and Secure Network Lab applications under [`examples`](examples). Their Flutter directories
contain only host setup, renderer registration, native-library initialization,
and platform bootstrap such as Application Support path discovery.

The [SQLite Worker Todo example](examples/sqlite_worker/README.md) exercises
the singleton OCaml Worker Domain with bounded typed requests, correlated
responses, coalesced pushes, and a Worker-Domain-owned SQLite connection. Its
Apple artifacts link the system `libsqlite3` without bundling another SQLite
implementation. macOS arm64 and unsigned physical-device iPhoneOS arm64
packaging are validated; signed device execution requires external signing
material and a reachable iPhone.

The [Secure Network Lab](examples/network/README.md) keeps verified HTTPS and
WSS connections in the OCaml Worker Domain using `tls-eio`, `ca-certs-nss`,
`httpun-eio`, and `httpun-ws`. Its deterministic tests use loopback TLS servers;
public endpoints are used only for explicit manual smoke tests. The macOS
complete object statically absorbs GMP and introduces no OpenSSL dependency.

## Current limitations and roadmap

- macOS 26.0+ Apple Silicon arm64 and physical-device iPhoneOS 15.0+ arm64 are
  the validated targets. Intel Mac and universal macOS builds are unsupported.
- The generic virtual-list prototype is intended for cached visible windows,
  not synchronous per-row FFI calls.
- Platform packaging and integration coverage will expand to Linux, Windows,
  Android, and iOS without changing the UI or binary protocol boundary.

Architecture, lifecycle, protocol, packaging, reconciliation, host effects,
and ADR details are under [`docs`](docs).

## License

MIT
