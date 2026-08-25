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
Navigation shell, Slidable, and morphing surface use the extension boundary.
Pressable and the virtual sliver family are core protocol nodes.

## Built-in varied-extent sliver

`Widget.Sliver.varied_extent` is core sliver kind `36`. It supports a
default item extent with sorted logical-index overrides and an optional
transition with expand/collapse durations and curves. Its core payload carries
a default item extent and sorted `(logical index, extent)` overrides. Painted
range changes use core event tag `14` and the standard 16-byte range payload.

Flutter realizes the contract with `SliverVariedExtentList` and the controller
owned by its enclosing `Scroll_view`. Sparse leading-offset math supports exact
initial anchors, painted ranges before and inside tall items, bounded OCaml
materialized windows, and logical anchor preservation when overrides change.
This is a known-extent contract, not arbitrary child measurement. Flutter owns
interpolation, anchor correction, interruption, settled-range reporting, and
reduced-motion resolution. `MorphingSurfaceHost` consumes the same per-item
progress for generic surface and content transitions without emitting frame
events over FFI. See [Virtual lists](virtual-lists.md) for window ownership.

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

## Built-in expandable message composer

`Native_widget.Expandable_message_composer` is built-in extension kind `7`,
schema version `2`, with Stateful and Semantics capabilities. The required
`fab_presentation` selects `Extended`, a real Material extended FAB, or
`Compact`, the standard icon-only FAB (not the small FAB). Both presentations
open `MessageComposer` in a Material 3 modal bottom sheet without an OCaml event
or frame. `fab_label` remains required, non-empty, and encoded for both
presentations; `fab_tooltip` is their accessible label. The native Flutter
`State` owns the modal route, text controller, focus node, staged draft,
dismissal lifecycle, renderer-resource propagation, and background pointer and
semantics gating.

Pass the widget to `Material.scaffold ~floating_action_button`; do not use
`bottom_navigation_bar`. The scaffold owns the button's margins, safe-area
avoidance, directionality, and relationship with a real bottom navigation bar.
The default location is `End_float`, and callers may use the existing
`floating_action_button_location` parameter for another standard floating or
docked location. The composer occupies the scaffold's single FAB slot. If a
page has another FAB, product code must explicitly choose which action owns the
slot; multi-action composition is a separate component concern.

The first logical child is always the FAB icon. Each remaining child
corresponds in order to one encoded composer button. Both protocol boundaries
require exactly `1 + button_count` children. Native event `1` carries the exact
UTF-8 editor text. Event `2` carries a positive little-endian `uint32` button ID
followed by the exact UTF-8 editor text; the framework never trims whitespace.

The version-2 payload begins with a 24-byte header: enabled flags, animation
curve, `uint16` duration in milliseconds, positive `uint16` maximum lines,
`uint16` button count, three `uint32` byte lengths for FAB label, FAB tooltip,
and hint text, one FAB-presentation byte (`0` extended, `1` compact), and three
reserved zero bytes. Those three UTF-8 strings follow, then each button uses a
12-byte ID/position/visibility/style/enabled/tooltip-length header followed by
its UTF-8 tooltip. Version `1` is not registered or decoded. Both version-2
decoders reject unknown flags or enums, nonzero reserved data, invalid or empty
required strings, invalid or duplicate button IDs, truncation, child-count
mismatch, and trailing bytes.

Standard motion defaults to 200 milliseconds with an ease-out curve and
requests focus only after the bottom-sheet entrance completes. Duration zero
mounts and focuses the sheet editor in the next frame. The modal sheet uses a
scrim, drag handle, 28dp top corners, compact full width, a 640dp large-window
maximum width, and keyboard/safe-area padding. Downward swipe, scrim tap, and
Escape dismiss and unfocus without clearing the controller draft. Disablement
dismisses to the disabled FAB, while a changed logical key removes the old
route and creates fresh native-local state.

Changing only `fab_presentation` with a stable logical key updates the collapsed
FAB without replacing the outer composer State. The existing State owns one
interruptible morph that continuously changes width, label opacity and occupied
space, and resolved shape while retaining one literal Flutter FAB, tooltip, and
button semantics node. Reversals and duration or curve changes continue from
the painted progress. Duration zero or `MediaQuery.disableAnimations` settles
the target immediately. An active route, exact draft, controller, and focus
node remain mounted; hidden presentation changes settle without replaying after
dismissal.

The modal sheet is the sole visible compose surface. Its embedded
`MessageComposer` paints no additional background, outline, or rounded card;
the editor and actions use the sheet directly with one 16dp horizontal content
inset. A standalone `MessageComposer` continues to own its outlined Material
card when no surrounding framework surface is responsible for that chrome.

## Core pressable

`Widget.pressable` is a core protocol node. It receives exactly one child and
stores an ARGB overlay color plus a release delay from 0 to 100 ms in typed
`Pressable_props`. The default neutral overlay uses an 80 ms release delay.

Flutter owns pointer-down feedback, drag and nested-control cancellation,
rapid-tap suppression, clipping, reduced-motion behavior, and disposal guards.
It emits the standard `Press` event with `Event.Payload.Unit` only after a
completed activation. The host contributes one tap action while retaining
descriptive child semantics and independent nested-button semantics.

## Built-in Slidable

`Native_widget.Slidable` is built-in extension kind `2`, schema version `3`.
It uses the Stateful, Resource, and Semantics capabilities and is rendered with
the stock `flutter_slidable` `4.0.3` package through its public API. Version `2`
is unsupported; the previous custom swipe renderer has no compatibility path.

A Slidable requires a stable application key and at least one action pane.
Each pane has one of `Behind`, `Drawer`, `Scroll`, or `Stretch` motion, one or
more actions, an extent ratio, optional open and close thresholds, and optional
dismissal behavior. Actions have positive IDs unique across both panes and map
to `CustomSlidableAction`. `action ~child` accepts arbitrary OCaml widget
content. `icon_label_action ~icon ~label` builds the common vertical icon and
label arrangement without introducing a separate wire type.

Children always use this order:

1. row content;
2. start-pane action children in metadata order; and
3. end-pane action children in metadata order.

The 16-byte header stores global flags, axis, two action counts, and the UTF-8
group-tag length. Each present pane contributes a 48-byte record containing
motion, dismissal and threshold flags, extent ratio, optional thresholds,
dismiss threshold, and dismissal and resize durations. Each action contributes
a 64-byte record containing its ID, background and optional foreground colors,
enabled and auto-close flags, optional alignment and padding, flex, and border
radius. Pane and action records precede the optional group tag. Both decoders
reject unknown flags and enums, nonzero reserved data, invalid numbers,
duplicate or zero action IDs, malformed UTF-8, inconsistent pane counts,
incorrect child counts, truncation, and trailing bytes.

Native event `1` carries a positive little-endian `uint32` action ID. Native
event `2` carries one logical dismissal-side byte (`0` start, `1` end).
`event_of_payload` validates kind, version, event ID, and exact event length
before exposing `Action_pressed` or `Dismissed`. Dropping a host suppresses a
late dismissal callback.

Flutter owns package controllers, gesture arbitration, motion, auto-close,
dismissal, and settle frames locally; drag progress does not cross FFI. The
first release intentionally omits imperative controllers, ratio notifications,
and asynchronous `confirmDismiss`. It uses the stock package gesture behavior,
including its accepted iPhone vertical-scroll startup regression.

`Native_widget.Slidable_auto_close_behavior` is built-in extension kind `8`,
schema version `1`, with the Stateful capability. It receives exactly one child
and maps its two policy flags to `SlidableAutoCloseBehavior.closeWhenOpened`
and `closeWhenTapped`. Descendant Slidables coordinate through their optional
group tags. This wrapper emits no events.
