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
The built-in fixed virtual list, sparse-extent list, navigation shell, and swipe
action use the same extension boundary. Pressable is a core protocol node
described below.

## Built-in sparse-extent list

`Native_widget.Sparse_extent_list` is built-in extension kind `4`. Schema
version `1` preserves immediate updates; schema version `2` adds explicit
enablement, expand/collapse durations, and curves. Its Stateful, Resource,
Semantics, and Virtualized capabilities match the fixed virtual list, while
its payload carries a default item extent and sorted
`(logical index, extent)` overrides. Both versions reuse native event `1` and
the 16-byte visible-range payload.

Flutter realizes the contract with `ListView.builder.itemExtentBuilder` and a
retained `ScrollController`. Sparse leading-offset math supports exact initial
offsets, visible ranges before and inside tall items, bounded OCaml child
windows, and logical anchor preservation when overrides change. This is a
known-extent contract, not arbitrary child measurement. Version `2` owns
interpolation, anchor correction, interruption, settled-range reporting, and
reduced-motion resolution in Flutter. `MorphingSurfaceHost` consumes the same
per-item progress for generic surface and content transitions without emitting
frame events over FFI.

## Built-in morphing surface

`Native_widget.Morphing_surface` is built-in extension kind `5`, schema version
`1`. Its two children are generic compact and expanded content. The four-byte
payload carries only committed target state; animation progress is inherited
locally from the enclosing sparse-extent item and never crosses FFI.

Flutter lays out each child at its endpoint extent, clips both to current list
geometry, interpolates inset, radius, and elevation, and phases content opacity
and translation. The outgoing child is excluded from hit testing and semantics,
while the committed target remains interactive. Outside a sparse list,
`MorphingSurfaceHost` accepts explicit normalized progress from another parent.

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
`2`. It uses the Stateful, Resource, and Semantics capabilities and always
receives three children in this order:

1. row content;
2. start-direction icon;
3. end-direction icon.

At least one direction must be enabled. Each enabled action supplies an
accessibility label, ARGB background, non-negative finite border radius,
`Dismiss` or `Rebound` disposition, and an icon child. The action border radius
defaults to `999` for capsule actions; use `0` when the action surface must
cover square row corners without gaps. The host also accepts a non-negative
finite `clip_border_radius`, which defaults to `0` and clips the content, action
surface, and translation animation together.

The fixed payload header stores enabled flags, both dispositions, a reserved
byte, two colors, both action border radii, the host clip border radius, and two
UTF-8 byte lengths; the labels follow the 44-byte header. Both decoders reject
unknown flags or dispositions, nonzero reserved data, invalid radii, invalid
UTF-8, empty enabled labels, incorrect exact lengths, and incorrect child
counts.

Flutter owns all pointer deltas, gesture-arena arbitration, clipping, action
geometry, threshold haptics, and settle frames. No drag delta crosses FFI. The
active action surface fills the host and remains fixed beneath the translated
foreground, without an inset between the two layers. Its icon stays centered
in a fixed 96-pixel edge zone. The translated foreground rounds only the
physical edge exposed by the active action. Action content paints at 72 percent
scale below the commit threshold and at full scale after crossing it, in sync
with the one-shot threshold haptic.
After a dismiss or rebound reaches its commit point, Flutter emits native event
`1` with a one-byte logical direction (`0` start-to-end, `1` end-to-start).
Dropping the node disposes its controller and suppresses late emission.

The host exposes the same actions through custom Semantics actions. Decorative
action icons are excluded from independent semantics and hit testing.
`create_with_handler` attaches a driver-managed raw handler for Bonsai effects;
`direction_of_payload` performs the same kind, version, event, length, and
direction validation before application state is updated.
