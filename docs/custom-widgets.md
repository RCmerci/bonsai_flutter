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
effect. This preserves the extension type while placing the effect in the
driver's normal event queue:

```ocaml
let handler =
  Driver.Handler.create_native handlers card (fun Activate ->
    set_count (fun count -> count + 1))
in
Native_widget.widget_with_handler
  card
  ~key:(Key.string "card")
  ~props:"Native card"
  ~on_event:handler
  ()
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
The built-in virtual list uses the same extension boundary.
