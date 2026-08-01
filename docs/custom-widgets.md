# Custom native widgets

`Native_widget` extends the renderer without exposing string widget names or
`Map<String, dynamic>` properties. The core protocol carries a versioned
extension envelope; application code owns the typed schema on both sides.

## OCaml registration

An extension declares a stable positive numeric kind ID, a positive schema
version, capability bits, a typed property encoder, and a typed event decoder:

```ocaml
type card_event = Activate

let card =
  Native_widget.Extension.create
    ~kind_id:1001
    ~version:1
    ~capabilities:
      [ Native_widget.Capability.Stateful
      ; Resource
      ; Semantics
      ]
    ~encode_props:Bytes.of_string
    ~decode_event:(fun ~event_id payload ->
      if event_id = 1 && Bytes.length payload = 0
      then Ok Activate
      else Error "unknown card event")
    ()
```

Use `Driver.Handler.create_native` when a typed event schedules a Bonsai
effect. The handler retains its identity while its declared dependencies are
equal, preserves the extension type, and places the effect in the driver's
normal event queue:

```ocaml
let handler =
  Driver.Handler.create_native
    handlers
    card
    ~equal:( == )
    set_count
    ~f:(fun set_count Activate ->
      set_count (fun count -> count + 1))
in
Bonsai.map handler ~f:(fun handler ->
  Native_widget.widget_with_handler
    card
    ~key:(Key.string "card")
    ~props:"Native card"
    ~on_event:handler
    ())
```

## Dart registration

The Flutter shell registers a typed decoder and factory before creating
`BonsaiFlutterRoot`:

```dart
final nativeWidgets =
    NativeWidgetRegistry(
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics,
    )
      ..register<String>(
        NativeWidgetRegistration(
          kindId: 1001,
          minVersion: 1,
          maxVersion: 1,
          capabilityBits:
              NativeCapability.stateful |
              NativeCapability.resource |
              NativeCapability.semantics,
          decodeProps: utf8.decode,
          factory: (context) {
            final focusNode = context.resource<FocusNode>(
              create: FocusNode.new,
              dispose: (focusNode) => focusNode.dispose(),
            );
            return ElevatedButton(
              focusNode: focusNode,
              onPressed: () => context.emit?.call(1, Uint8List(0)),
              child: Text(context.props),
            );
          },
        ),
      );

final registry = WidgetRegistry.standard(nativeWidgets: nativeWidgets);
```

The core renderer imports no application module. Missing factories, unsupported
schema versions, missing capabilities, and decoder failures render
`UnsupportedNativeWidget` with a diagnostic semantics label.

## Resource lifecycle

`context.resource` binds one typed resource to the runtime epoch, node ID,
extension kind ID, and schema version. Compatible property updates retain it.
Version changes, `DropNode`, full snapshots, epoch changes, and renderer
shutdown dispose it exactly once. `RendererResourceStore` exposes creation,
disposal, and live counts for tests and debug instrumentation.

Native widget events use the common event tag with extension kind, version,
event ID, and bounded byte payload. OCaml validates all identifiers before the
typed extension decoder runs. Revision-scoped handler rules still reject stale
or replaced handlers.

The Gallery contains the complete custom card example and its real FFI test.
The built-in virtual list, navigation shell, and swipe action use the same
extension boundary. Pressable is a core protocol node described below.

## Built-in navigation shell

`Native_widget.Navigation_shell` is built-in extension kind `3`, schema
version `1`. Its children are retained destination bodies followed by one
drawer child and one bottom-navigation child. The fixed 12-byte payload carries
the selected destination, destination count, requested drawer state, and
whether the drawer is enabled. Both sides reject reserved flags, invalid
indexes, and mismatched child counts.

Flutter uses a real `Scaffold`, `Drawer`, and retained `IndexedStack`. Drawer
drag progress, scrim animation, edge arbitration, Back handling, and settle
stay local. Native event `1` carries one settled state byte (`0` closed, `1`
open), and the host suppresses that event until the active pointer interaction
has finished. OCaml uses `drawer_state_of_payload` before committing state.
Dropping an open shell cancels pending post-frame work.

## Core pressable

`Widget.pressable` is a core protocol node. It receives exactly one child and
stores an ARGB overlay color plus a release delay from 0 to 100 ms in typed
`Pressable_props`. The default neutral overlay uses an 80 ms release delay.

Flutter owns pointer-down feedback, drag and nested-control cancellation,
rapid-tap suppression, clipping, reduced-motion behavior, and disposal guards.
It emits the standard `Press` event with `Event.Payload.Unit` only after a
completed activation. The host contributes one tap action while retaining
descriptive child semantics and independent nested-button semantics.

## Built-in swipe action

`Native_widget.Swipe_action` is built-in extension kind `2`, schema version
`1`. It uses the Stateful, Resource, and Semantics capabilities and always
receives three children in this order:

1. row content;
2. start-direction icon;
3. end-direction icon.

At least one direction must be enabled. Each enabled action supplies an
accessibility label, ARGB background, `Dismiss` or `Rebound` disposition, and
an icon child. The fixed payload header stores enabled flags, both
dispositions, a reserved byte, two colors, and two UTF-8 byte lengths; the
labels follow the 20-byte header. Both decoders reject unknown flags or
dispositions, nonzero reserved data, invalid UTF-8, empty enabled labels,
incorrect exact lengths, and incorrect child counts.

Flutter owns all pointer deltas, gesture-arena arbitration, clipping, pill
geometry, threshold haptics, and settle frames. No drag delta crosses FFI.
After a dismiss or rebound reaches its commit point, Flutter emits native event
`1` with a one-byte logical direction (`0` start-to-end, `1` end-to-start).
Dropping the node disposes its controller and suppresses late emission.

The host exposes the same actions through custom Semantics actions. Decorative
feedback icons are excluded from independent semantics and hit testing.
`create_with_handler` attaches a driver-managed raw handler for Bonsai effects;
`direction_of_payload` performs the same kind, version, event, length, and
direction validation before application state is updated.
