# Sliver Scroll Refactoring Plan

- Status: Planning
- Date: 2026-08-16
- Approach: Plan B — Sliver family + unified `Scroll_view` (breaking)
- Compatibility: None. Old `scroll_view`/`list_view` core nodes and
  `Virtual_list`/`Sparse_extent_list` native widget extensions are deleted
  outright. No migration shim, no protocol backward compatibility.

## Goal

Replace the four current scrolling/viewport components with a single
`Scroll_view` that builds a Flutter `CustomScrollView` and a family of
`Sliver` child nodes that produce `RenderSliver` children inside it. This
unlocks real sliver composition — collapsing `SliverAppBar`, sticky headers,
mixed fixed + virtualized + footer sections sharing one scroll axis and one
`ScrollController` — which the current box-based scrollables cannot express.

### What is deleted

| Deleted | Was | Flutter primitive |
| --- | --- | --- |
| `Widget.Scroll_view` (core kind 30) | `SingleChildScrollView` | box |
| `Widget.List_view` (core kind 31) | `ListView` | box |
| `Native_widget.Virtual_list` (native kind 1) | `ListView.builder` fixed extent | box |
| `Native_widget.Sparse_extent_list` (native kind 4) | `ListView.builder` itemExtentBuilder | box |

The `virtual_list.dart` and `sparse_extent_list.dart` state machines
(visible-range reporting, anchor correction, transition animation) are
re-homed into core sliver host widgets, not deleted.

## Current architecture (reference)

### OCaml type safety layers

`Viewport.Vertical.t` / `Viewport.Horizontal.t` are opaque types that
require a finite main-axis extent. They are created only by scroll producers
and embedded only via:

- `Body.Vertical.fill` → `Flex.expanded` (tight, `widget.ml:1546`)
- `Viewport.Vertical.with_height` → `Widget.sized_box` (`widget.ml:1439`)

`Body.t` is consumed by `Material.scaffold` and `Navigation_shell`.

### Scroll controller ownership

- `primary: true` → borrows `PrimaryScrollController.maybeOf(context)`
  via `_BorrowedScrollControllerHost` (`widget_registry.dart:588`)
- `primary: false` → owned `ScrollController` via
  `RendererResourceStore.acquireScrollController(nodeId)`
  (`renderer_resource_store.dart:172`)
- `DetentedModalSheetHost` injects a `PrimaryScrollController` from
  `DraggableScrollableSheet`'s builder
  (`detented_modal_sheet_host.dart:113`)
- Navigator validates detented pages have exactly one primary vertical
  scrollable (`widget_registry.dart:1216-1253`)

### Events

- `scroll_notification` (tag 13): `ScrollEventPayload(pixels, delta)` from
  `NotificationListener<ScrollNotification>` in `_guardedScrollable`
  (`widget_registry.dart:652`)
- `visible_range_changed` (tag 14): native event 1, 16-byte payload
  (`firstIndex` u64 + `lastExclusive` u64) from virtual/sparse list hosts
- `NavigationShellHost` listens to depth-0 vertical scroll notifications to
  hide/show bottom navigation (`navigation_shell.dart:171`)

### Protocol generation pipeline

`protocol/schema.sexp` is the single source of truth. `make
protocol-generate` runs `protocol/generator/generate.exe`, which emits:

- OCaml: `generated_protocol.ml` / `.mli` (kind IDs, prop IDs, debug names)
- Dart: `generated_protocol.dart`, and the props classes in `frame.dart`

`make protocol-fixtures-generate` regenerates all `.hex` test fixtures.

Current protocol version: 1.18 (`schema.sexp:3-4`).

## Target architecture

### New OCaml type system

```ocaml
(* widget.mli — new *)

(** A sliver is scroll-axis content that lives only inside a Scroll_view.
    It is not a Widget.t and cannot be placed in a column, row, or body. *)
module Sliver : sig
  type t

  val with_test_id : Test_id.t -> t -> t

  (** Wraps a single box widget. → SliverToBoxAdapter *)
  val box : ?key:Key.t -> Widget.t -> t

  (** A non-virtualized list of box widgets. → SliverList *)
  val list : ?key:Key.t -> Widget.t list -> t

  (** Fills the remaining viewport extent. → SliverFillRemaining *)
  val fill : ?key:Key.t -> ?flex:int -> Widget.t -> t

  (** Fixed-extent virtual list. → SliverFixedExtentList
      Replaces Native_widget.Virtual_list. *)
  val fixed_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** Varied-extent virtual list with sparse overrides. → SliverVariedExtentList
      Replaces Native_widget.Sparse_extent_list. *)
  val varied_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:Sparse_extent_override.t list
    -> ?overscan:int
    -> ?transition:Sparse_extent_transition.t
    -> items:Widget.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  (** SliverPadding wrapper. *)
  val padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t

  (** Collapsible app bar. → SliverAppBar *)
  val app_bar
    :  ?key:Key.t
    -> ?pinned:bool
    -> ?expanded_height:float
    -> ?collapsed_height:float
    -> Widget.t
    -> t
end

(** Scroll_view builds a CustomScrollView. Its children are Sliver.t, not
    Widget.t. It still returns Viewport.Vertical.t / Horizontal.t so the
    existing Body.fill / Viewport.with_height embedding paths are unchanged. *)
module Scroll_view : sig
  val vertical
    :  ?key:Key.t
    -> ?reverse:bool
    -> ?primary:bool
    -> on_scroll:Event.Handler.t
    -> Sliver.t list
    -> unit
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?reverse:bool
    -> on_scroll:Event.Handler.t
    -> Sliver.t list
    -> unit
    -> Viewport.Horizontal.t
end
```

### Type safety preserved

- `Sliver.t` is opaque and distinct from `Widget.t`. The OCaml compiler
  rejects passing a sliver to `Widget.column`, `Body.Vertical.fixed`, or
  any box-only slot.
- `Scroll_view` accepts `Sliver.t list` only — not `Widget.t list`.
- `Scroll_view` still returns `Viewport.Vertical.t` / `Horizontal.t`, so
  `Body.Vertical.fill` and `Viewport.Vertical.with_height` are unchanged.
- A `Sliver.t` cannot be a body, a navigator child, or a stack child.

### Protocol node kinds

Delete kinds 30 (`scroll_view`) and 31 (`list_view`). Re-add `scroll_view`
with a new kind and add the sliver family. Use the gap at 32–39:

| Kind | Name | Props |
| ---: | --- | --- |
| 30 | `scroll_view` (reused) | `axis`, `reverse`, `primary` |
| 32 | `sliver_box` | *(none — child is a box widget)* |
| 33 | `sliver_list` | *(none — children are box widgets)* |
| 34 | `sliver_fill` | `flex` (u32, default 1) |
| 35 | `sliver_fixed_extent` | `total_count` (u64), `first_index` (u64), `item_extent` (f64), `overscan` (u32) |
| 36 | `sliver_varied_extent` | `total_count`, `first_index`, `default_item_extent`, `overscan`, `override_count` (u32), `overrides` (repeated index+extent), transition header (optional) |
| 37 | `sliver_padding` | `insets` (edge_insets) |
| 38 | `sliver_app_bar` | `pinned` (bool), `expanded_height` (optional f64), `collapsed_height` (optional f64) |

`list_view` (31) is deleted. Kind 30 is reused for `scroll_view` but its
props encoding changes (child model is slivers, not a single box). Since
backward compatibility is explicitly not a concern, reusing 30 is fine — the
props wire format is the same (`axis` + `reverse` + `primary`), only the
child semantics change.

### Native widget extensions

Delete native kinds 1 (`Virtual_list`) and 4 (`Sparse_extent_list`) from
`NativeWidgetKind` (`virtual_list.dart:10-17`). Their registration calls
(`registerVirtualList`, `registerSparseExtentList`) are removed from
`WidgetRegistry.standard` (`widget_registry.dart:58-59`).

Remaining native extensions: `swipe_action` (2), `navigation_shell` (3),
`morphing_surface` (5), `message_composer` (6).

### Dart renderer: scroll controller sharing

`Scroll_view`'s factory builds a `CustomScrollView` and owns (or borrows)
the `ScrollController`. It publishes the controller and viewport extent via
a new `InheritedWidget`:

```dart
/// Provided by _ScrollViewHost. Sliver children consume it to compute
/// visible ranges and participate in anchor correction.
final class ScrollViewScope extends InheritedWidget {
  const ScrollViewScope({
    required this.controller,
    required this.axis,
    required super.child,
    super.key,
  });

  final ScrollController controller;
  final Axis axis;

  static ScrollViewScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScrollViewScope>();
}
```

`sliver_fixed_extent` and `sliver_varied_extent` hosts consume
`ScrollViewScope.of(context)` to access the shared controller for
visible-range computation, instead of owning their own controller.

### Dart renderer: sliver factories

Each sliver kind gets a `_buildSliver*` factory in `widget_registry.dart`.
These return sliver widgets (`SliverToBoxAdapter`, `SliverList`, etc.),
which are still `Widget` subclasses. `NodeHost` builds them as normal and
`Scroll_view`'s factory passes the children list directly to
`CustomScrollView(slivers: children)`.

`NodeHost` already wraps children with `Flexible`/`Expanded`/`Positioned`
based on `parentData` (`node_host.dart:270-293`). Sliver children use
`NoParentData`, so they pass through unwrapped. No `NodeHost` change needed.

### ViewportConstraintGuard

Unchanged. `Scroll_view`'s factory wraps the `CustomScrollView` in
`ViewportConstraintGuard` exactly as today, checking finite main-axis
constraints before constructing the real viewport.

### scroll_to host effect

`RendererResourceStore.scrollTo(nodeId)` now addresses the `Scroll_view`
node (which owns the `ScrollController`), not individual list nodes. The
resource store's scroll-controller map is keyed by the `scroll_view` node ID.
`_BorrowedScrollControllerHost` logic moves into the `Scroll_view` host.

### Detented modal sheet & navigator validation

`DetentedModalSheetHost` already injects a `PrimaryScrollController`
(`detented_modal_sheet_host.dart:113`). The `Scroll_view` host with
`primary: true` borrows it via `PrimaryScrollController.maybeOf(context)`.
Unchanged behavior.

Navigator's detented-page validation (`widget_registry.dart:1216-1253`)
now scans for primary `Scroll_view` nodes (kind 30) instead of
`ScrollView`/`ListView` props. The check remains: exactly one primary
vertical scrollable per detented page.

## Protocol schema changes (`protocol/schema.sexp`)

### Bump minor version

```
(minor 18) → (minor 19)
```

### Node kinds

Delete `list_view` (31). Add sliver kinds 32–38:

```sexp
   (scroll_view 30)
   (sliver_box 32)
   (sliver_list 33)
   (sliver_fill 34)
   (sliver_fixed_extent 35)
   (sliver_varied_extent 36)
   (sliver_padding 37)
   (sliver_app_bar 38)
```

### Kind props

Delete `list_view` props. `scroll_view` props unchanged. Add:

```sexp
    (sliver_fill
     ((flex 1 u32)))
    (sliver_fixed_extent
     ((total_count 1 u64)
      (first_index 2 u64)
      (item_extent 3 f64)
      (overscan 4 u32)))
    (sliver_varied_extent
     ((total_count 1 u64)
      (first_index 2 u64)
      (default_item_extent 3 f64)
      (overscan 4 u32)
      (override_count 5 u32)
      (overrides 6 varied_extent_overrides)
      (transition_enabled 7 optional_bool)
      (expand_duration_ms 8 optional_u32)
      (collapse_duration_ms 9 optional_u32)
      (expand_curve 10 optional_animation_curve)
      (collapse_curve 11 optional_animation_curve)))
    (sliver_padding
     ((insets 1 edge_insets)))
    (sliver_app_bar
     ((pinned 1 bool)
      (expanded_height 2 optional_f64)
      (collapsed_height 3 optional_f64)))
```

`sliver_box` and `sliver_list` have no props (their content is their
children).

### Event tags

Unchanged. `scroll_notification` (13) stays on `Scroll_view`.
`visible_range_changed` (14) moves from native event to a core event on
`sliver_fixed_extent` / `sliver_varied_extent` nodes.

### New encoding types

`varied_extent_overrides`: a bounded list of `(u64 index, f64 extent)`
pairs. `optional_animation_curve`: one-byte presence tag + `u8` curve enum
(matching the current `SparseExtentTransitionCurve` indices).

The generator (`protocol/generator/schema.ml`) may need a new encoding
entry if `varied_extent_overrides` is not expressible as a simple
`list` of a struct. If so, encode it as a counted list of f64 pairs
(index as f64 to reuse existing list-of-f64 machinery, validated to be a
non-negative safe integer on decode).

## OCaml changes

### `ocaml/ui/widget.ml` + `.mli`

**Delete:**
- `K_list_view` kind tag
- `List_view` GADT constructor
- `list_view_widget` function
- `module List_view`

**Add to `Private_types.node`:**
```ocaml
  | Sliver_box : [ `Sliver_box ] node
  | Sliver_list : [ `Sliver_list ] node
  | Sliver_fill : { flex : int } -> [ `Sliver_fill ] node
  | Sliver_fixed_extent :
      { total_count : int
      ; first_index : int
      ; item_extent : float
      ; overscan : int
      }
      -> [ `Sliver_fixed_extent ] node
  | Sliver_varied_extent :
      { total_count : int
      ; first_index : int
      ; default_item_extent : float
      ; extent_overrides : Sparse_extent_override.t list
      ; overscan : int
      ; transition : Sparse_extent_transition.t option
      }
      -> [ `Sliver_varied_extent ] node
  | Sliver_padding :
      { left : float; top : float; right : float; bottom : float }
      -> [ `Sliver_padding ] node
  | Sliver_app_bar :
      { pinned : bool
      ; expanded_height : float option
      ; collapsed_height : float option
      }
      -> [ `Sliver_app_bar ] node
```

**Add kind tags:** `K_sliver_box` … `K_sliver_app_bar` to the `kind_tag`
enum, `node_kind_tag`, `kind_tag_to_string`, `node_equal`.

**New `Sliver` module** (opaque `t`, wraps a `Widget.t` with a sliver
node + optional parent-data). Internal representation:

```ocaml
type sliver = Sliver of Widget.t  (* the widget carries a sliver_* node *)
type t = sliver
```

`Sliver.box child` creates a `Widget.t` with node `Sliver_box` and one
child, then wraps it in `Sliver`. `Sliver.list children` creates a
`Widget.t` with node `Sliver_list` and the children. `Sliver.padding`
creates a `Sliver_padding` widget wrapping the inner sliver's widget.

`Sliver.fixed_extent` / `varied_extent` create widgets with the
corresponding nodes and carry the `visible_range_changed` event binding.

**`Scroll_view` module** creates a `Widget.t` with node `Scroll_view`
whose children are the sliver widgets (unwrapped from `Sliver.t`). Returns
`Viewport.Vertical.t` / `Horizontal.t`.

### `ocaml/ui/native_widget.ml` + `.mli`

**Delete:** `module Virtual_list` and `module Sparse_extent_list` entirely.

**Move to `widget.ml`** (or a new `ocaml/ui/sparse_extent.ml`):
- `Sparse_extent_override.t` (`{ index; extent }`)
- `Sparse_extent_transition.t` + `Transition.create`
- `visible_range_of_payload` decoder (now decodes core event tag 14, not
  native event)

These types are referenced by `Sliver.varied_extent` and by application
event handlers.

### `ocaml/protocol/wire_frame.ml` + `.mli`

**Delete:** `List_view` kind, `List_view_props`.

**Add:** `Sliver_box`, `Sliver_list`, `Sliver_fill`, `Sliver_fixed_extent`,
`Sliver_varied_extent`, `Sliver_padding`, `Sliver_app_bar` kinds and
their props variants.

### `ocaml/protocol/binary_codec.ml` + `.mli`

**Delete:** `List_view` kind mapping, `List_view_props` encode/decode,
field masks.

**Add:** sliver kind mappings, sliver props encode/decode. The
`sliver_varied_extent` encoder reuses the existing
`Sparse_extent_list` payload layout (header + override pairs + optional
transition header) but as a core props encoding, not an opaque native payload.

### `ocaml/runtime/driver.ml`

**Delete:** `K_list_view` → `List_view` mapping, `List_view` →
`List_view_props` conversion.

**Add:** `K_sliver_*` → `Sliver_*` mappings and props conversions. The
`Scroll_view` node now carries sliver children (which are themselves nodes
with sliver kinds); the driver's reconciler handles them as normal children
— no special child handling needed beyond kind/props matching.

### `ocaml/runtime/mounted_tree.ml` + `frame_patch.ml`

No structural change. Sliver nodes are regular nodes with a kind tag. The
reconciler's two-phase diff (kind tag first, then props) works unchanged.
`kind_tag` gains the new `K_sliver_*` variants.

## Dart renderer changes

### `flutter/.../protocol/frame.dart`

**Delete:** `NodeKind.listView`, `ListViewProps`.

**Add to `NodeKind`:** `sliverBox`, `sliverList`, `sliverFill`,
`sliverFixedExtent`, `sliverVariedExtent`, `sliverPadding`,
`sliverAppBar`.

**Add props classes:**
- `SliverFillProps({ flex })`
- `SliverFixedExtentProps({ totalCount, firstIndex, itemExtent, overscan })`
- `SliverVariedExtentProps({ totalCount, firstIndex, defaultItemExtent, overscan, extentOverrides, transition })`
- `SliverPaddingProps({ insets })`
- `SliverAppBarProps({ pinned, expandedHeight, collapsedHeight })`

`SliverBoxProps` and `SliverListProps` use `EmptyProps` (no props).

### `flutter/.../protocol/generated_protocol.dart`

Regenerated by `make protocol-generate`. Adds `Sliver*PropId` classes.

### `flutter/.../protocol/binary_codec.dart`

**Delete:** `NodeKind.listView` / `ListViewProps` encode/decode.

**Add:** sliver kind + props encode/decode. The `sliver_varied_extent`
decoder reuses the existing `SparseExtentListProps.decode` logic (header +
overrides + optional transition) but as a core props decoder.

### `flutter/.../renderer/widget_registry.dart`

**Delete:** `_buildListView`, `NodeKind.listView` registration.

**Rewrite `_buildScrollView`** to build `CustomScrollView`:

```dart
Widget _buildScrollView(context, node, children, onEvent) {
  _expectProps<ScrollViewProps>(node);
  final props = _expectProps<ScrollViewProps>(node);
  final binding = _binding(node, EventTagId.scrollNotification);
  final resources = RendererResourceScope.of(context);
  final controller = props.primary
      ? PrimaryScrollController.maybeOf(context)
      : resources.acquireScrollController(node.id);
  if (controller == null) {
    throw RendererBuildException(
      'Primary Scroll_view node ${node.id} has no route scroll controller',
    );
  }
  final viewport = ViewportConstraintGuard(
    nodeId: node.id,
    localRevision: node.localRevision,
    widgetKind: 'Scroll_view',
    axis: props.axis == ScrollAxis.horizontal
        ? RendererViewportAxis.horizontal
        : RendererViewportAxis.vertical,
    builder: (context, constraints) => ScrollViewScope(
      controller: controller,
      axis: props.axis == ScrollAxis.horizontal
          ? Axis.horizontal
          : Axis.vertical,
      child: _guardedScrollNotification(
        node: node,
        binding: binding,
        onEvent: onEvent,
        child: CustomScrollView(
          controller: controller,
          scrollDirection: props.axis == ScrollAxis.horizontal
              ? Axis.horizontal
              : Axis.vertical,
          reverse: props.reverse,
          slivers: children,
        ),
      ),
    ),
  );
  return props.primary
      ? _BorrowedScrollControllerHost(
          nodeId: node.id,
          resources: resources,
          controller: controller,
          child: viewport,
        )
      : viewport;
}
```

**Add sliver factories:**

```dart
Widget _buildSliverBox(context, node, children, onEvent) {
  _expectChildCount(node, children, 1);
  _expectProps<EmptyProps>(node);
  return SliverToBoxAdapter(child: children.single);
}

Widget _buildSliverList(context, node, children, onEvent) {
  _expectProps<EmptyProps>(node);
  return SliverList(delegate: SliverChildListDelegate(children));
}

Widget _buildSliverFill(context, node, children, onEvent) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SliverFillProps>(node);
  return SliverFillRemaining(
    fillOverscroll: false,
    child: children.single,
  );
}

Widget _buildSliverFixedExtent(context, node, children, onEvent) {
  final props = _expectProps<SliverFixedExtentProps>(node);
  final binding = _binding(node, EventTagId.visibleRangeChanged);
  return _SliverFixedExtentHost(
    nodeId: node.id,
    props: props,
    emit: /* wire binding */,
    children: children,
  );
}

Widget _buildSliverVariedExtent(context, node, children, onEvent) {
  final props = _expectProps<SliverVariedExtentProps>(node);
  final binding = _binding(node, EventTagId.visibleRangeChanged);
  return _SliverVariedExtentHost(
    nodeId: node.id,
    props: props,
    emit: /* wire binding */,
    children: children,
  );
}

Widget _buildSliverPadding(context, node, children, onEvent) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SliverPaddingProps>(node);
  return SliverPadding(
    padding: EdgeInsets.fromLTRB(
      props.insets.left, props.insets.top,
      props.insets.right, props.insets.bottom,
    ),
    sliver: children.single,
  );
}

Widget _buildSliverAppBar(context, node, children, onEvent) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SliverAppBarProps>(node);
  return SliverAppBar(
    pinned: props.pinned,
    expandedHeight: props.expandedHeight,
    collapsedHeight: props.collapsedHeight,
    title: children.single,
  );
}
```

**Register in `WidgetRegistry.standard`:**

```dart
  NodeKind.scrollView: _buildScrollView,
  NodeKind.sliverBox: _buildSliverBox,
  NodeKind.sliverList: _buildSliverList,
  NodeKind.sliverFill: _buildSliverFill,
  NodeKind.sliverFixedExtent: _buildSliverFixedExtent,
  NodeKind.sliverVariedExtent: _buildSliverVariedExtent,
  NodeKind.sliverPadding: _buildSliverPadding,
  NodeKind.sliverAppBar: _buildSliverAppBar,
```

**Delete native widget registrations:**
```dart
  // registerVirtualList(extensions);    // deleted
  // registerSparseExtentList(extensions); // deleted
```

### New file: `flutter/.../renderer/sliver_virtual_host.dart`

Houses `_SliverFixedExtentHost` and `_SliverVariedExtentHost` (extracted
from `virtual_list.dart` and `sparse_extent_list.dart`). Key changes from
the old hosts:

- Do **not** own a `ScrollController`. Consume
  `ScrollViewScope.of(context)` to access the shared controller.
- Build `SliverFixedExtentList` / `SliverVariedExtentList` instead of
  `ListView.builder`.
- Visible-range computation, anchor correction, and transition animation
  logic move over unchanged (they operate on the controller + viewport
  extent, which are now inherited rather than owned).
- Emit `visible_range_changed` as a core event (tag 14) via the standard
  `onEvent` callback, not a native event emitter.

### `flutter/.../renderer/renderer_resource_store.dart`

`scrollTo(nodeId)` unchanged — it still looks up `_scrollControllers[nodeId]`.
Now the nodeId is always a `scroll_view` node. The retained-scroll-controller
sweep (`renderer_resource_store.dart:368-385`) checks for `ScrollViewProps`
instead of `ScrollViewProps`/`ListViewProps`.

### `flutter/.../native_widget/virtual_list.dart`

**Delete** the file. `NativeWidgetKind.virtualList` and `NativeWidgetKind.sparseExtentList`
constants are removed. Remaining `NativeWidgetKind` values renumber
conceptually but keep their wire kind IDs (2, 3, 5, 6).

### `flutter/.../native_widget/sparse_extent_list.dart`

**Delete** the file. `SparseExtentGeometry` (the offset/visible-range math)
moves to `sliver_virtual_host.dart` or a shared `sparse_extent_geometry.dart`.

### `flutter/.../native_widget/sparse_extent_transition_scope.dart`

Keep. `Morphing_surface` still consumes per-item transition progress.
The scope is now published by `_SliverVariedExtentHost` instead of
`SparseExtentListHost`.

## Call-site migration

### Examples

| File | Current | New |
| --- | --- | --- |
| `examples/clock/clock.ml:872` | `Scroll_view.vertical ~on_scroll body` | `Scroll_view.vertical ~on_scroll [Sliver.box body]` |
| `examples/todo/todo.ml:261` | `Scroll_view.vertical ~on_scroll (column rows)` | `Scroll_view.vertical ~on_scroll [Sliver.box (column rows)]` (or `[Sliver.list rows]`) |
| `examples/gallery/gallery.ml:361` | `Scroll_view.vertical ~on_scroll content` | `Scroll_view.vertical ~on_scroll [Sliver.box content]` |
| `examples/mail/mail.ml:1582` | `Scroll_view.vertical ~on_scroll (column blocks)` | `Scroll_view.vertical ~on_scroll [Sliver.box (column blocks)]` |
| `examples/mail/mail.ml:1216` | `Sparse_extent_list.vertical ...` in `Body.Vertical.fill` | `Scroll_view.vertical ~on_scroll [Sliver.varied_extent ...]` in `Body.Vertical.fill` (or keep fixed headers as separate `Sliver.box` entries in the same scroll view) |

The mail inbox becomes the showcase for sliver composition:

```ocaml
let inbox_viewport =
  Scroll_view.vertical
    ~on_scroll:scroll
    [ Sliver.box (padding ~horizontal:16. ~vertical:10. search_header)
    ; Sliver.box (padding ~horizontal:20. ~vertical:8. (styled_text ... title))
    ; Sliver.varied_extent
        ~total_count
        ~first_index:state.window_first
        ~default_item_extent:compact_mail_extent
        ~extent_overrides:(expanded_extent_override state)
        ~overscan:4
        ~transition:mail_list_transition
        ~items:rows
        ~on_visible_range
        ()
    ]
    ()
in
(* This viewport goes straight into Body.Vertical.fill — the fixed
   header slivers and the virtual list share one scroll controller. *)
```

### OCaml tests

| File | Change |
| --- | --- |
| `ocaml/test/core_surface_tests.ml:48` | `List_view.vertical` → `Scroll_view.vertical [Sliver.list [child]]` |
| `ocaml/test/core_tests.ml:1514` | `Scroll_view.vertical` → add `[Sliver.box ...]` |
| `ocaml/test/public_api_tests.ml:74,85` | `List_view.vertical` → `Scroll_view.vertical [Sliver.list ...]` |
| `ocaml/test/protocol_tests.ml:417` | Update fixture: kind + props |
| `ocaml/test/viewport_compile/*` | Rewrite all: `List_view` → `Scroll_view + Sliver.list`, `Scroll_view` → add sliver children |
| `ocaml/test/native_widget_tests.ml` | Delete `Virtual_list`/`Sparse_extent_list` tests; move logic tests to new `sliver_tests.ml` |

### Dart tests

| File | Change |
| --- | --- |
| `test/widget_renderer_test.dart:409,454,774,871` | `NodeKind.scrollView` children become slivers; `find.byType(SingleChildScrollView)` → `find.byType(CustomScrollView)`; `NodeKind.listView` → `NodeKind.sliverList`; `find.byType(ListView)` → `find.byType(SliverList)` |
| `test/viewport_body_test.dart` | Fixture regenerated; `find.byType(ListView)` → `find.byType(SliverFixedExtentList)` (inside `CustomScrollView`) |
| `test/virtual_list_test.dart` | Rewrite: `VirtualListProps` → `SliverFixedExtentProps`; wrap in `Scroll_view` node; visible-range event now core tag 14 |
| `test/mail_outliner_transition_test.dart` | `SparseExtentListHost` → `_SliverVariedExtentHost`; pump inside a `CustomScrollView` |
| `test/viewport_constraint_guard_test.dart` | Unchanged (guard API same) |
| `test/navigation_host_test.dart` | Primary scrollable now `Scroll_view` with `primary: true` |
| `test/navigation_shell_test.dart` | Scroll notification listener unchanged (depth-0 `CustomScrollView` still emits `ScrollNotification`) |

### Fixtures

Run `make protocol-fixtures-generate` to regenerate all `.hex` fixtures after
schema + codec changes. This updates:
- `test/ocaml_viewport_body.hex`
- All protocol test fixtures in `ocaml/test/` and `flutter/.../test/`

## Implementation phases

### Phase 1: Protocol schema + codegen (review checkpoint)

1. Edit `protocol/schema.sexp`: bump minor to 19, delete `list_view`, add
   sliver kinds + props, add `varied_extent_overrides` encoding type.
2. Extend `protocol/generator/schema.ml` + `render.ml` if the new
   encoding type requires generator support.
3. Run `make protocol-generate` → inspect generated `generated_protocol.ml` /
   `.mli` / `.dart`.
4. Run `make protocol-check` → must pass.

**Checkpoint:** Review generated IDs and debug names. No hand-written code
beyond the schema yet.

### Phase 2: OCaml wire layer (review checkpoint)

1. Update `wire_frame.ml` + `.mli`: delete `List_view` + props, add sliver
   kinds + props.
2. Update `binary_codec.ml` + `.mli`: delete list_view encode/decode,
   add sliver encode/decode. Reuse the sparse-extent payload layout for
   `sliver_varied_extent`.
3. Update `driver.ml`: delete list_view mappings, add sliver mappings.
4. Run `make protocol-fixtures-generate` → regenerate fixtures.
5. Run `make native-test` → protocol + codec tests pass (may require
   updating test expectations in same commit).

**Checkpoint:** OCaml protocol round-trips. Reconciler not yet updated.

### Phase 3: OCaml UI layer (review checkpoint)

1. Update `widget.ml` + `.mli`: delete `List_view` module + GADT
   constructor + kind tag; add sliver GADT constructors, kind tags,
   `node_equal`, `node_kind_tag`; add `Sliver` module; rewrite
   `Scroll_view` module to accept `Sliver.t list`.
2. Extract `Sparse_extent_override` + `Sparse_extent_transition` from
   `native_widget.ml` into `widget.ml` (or new `sparse_extent.ml`).
3. Delete `Virtual_list` + `Sparse_extent_list` modules from
   `native_widget.ml` + `.mli`.
4. Update `mounted_tree.ml` / `frame_patch.ml`: new kind tags flow
   through unchanged.
5. Update all OCaml tests + viewport_compile tests.
6. Run `make native-test` → all OCaml tests pass.

**Checkpoint:** Full OCaml stack compiles and tests green.

### Phase 4: Dart protocol layer (review checkpoint)

1. Regenerate `generated_protocol.dart` + `frame.dart` props via
   `make protocol-generate`.
2. Update `binary_codec.dart`: delete list_view, add sliver encode/decode.
3. Run `make dart-test` → binary_codec tests pass (update expectations).

**Checkpoint:** Dart protocol decodes new frames.

### Phase 5: Dart renderer (review checkpoint)

1. Add `ScrollViewScope` inherited widget.
2. Create `sliver_virtual_host.dart` with `_SliverFixedExtentHost` +
   `_SliverVariedExtentHost` (extracted + adapted from old hosts).
3. Move `SparseExtentGeometry` to shared file.
4. Rewrite `_buildScrollView` in `widget_registry.dart` to build
   `CustomScrollView` + `ScrollViewScope`.
5. Add `_buildSliverBox` / `_buildSliverList` / `_buildSliverFill` /
   `_buildSliverFixedExtent` / `_buildSliverVariedExtent` /
   `_buildSliverPadding` / `_buildSliverAppBar` factories.
6. Delete `virtual_list.dart` + `sparse_extent_list.dart`; remove their
   registrations from `WidgetRegistry.standard`.
7. Update `renderer_resource_store.dart`: retained-controller sweep checks
   `ScrollViewProps` only.
8. Update Navigator detented-page validation: scan for `Scroll_view`
   primary vertical.
9. Run `make dart-test` + `make flutter-test` → all pass (update test
   expectations).

**Checkpoint:** Full Dart renderer builds slivers.

### Phase 6: Examples + integration (final checkpoint)

1. Migrate all examples (clock, todo, gallery, mail).
2. Run `make integration-test` → FFI integration tests pass.
3. Run `make flutter-test` → widget + integration tests pass.
4. Update docs: `virtual-lists.md`, `viewport-layout.md`,
   `custom-widgets.md`, `architecture.md`.
5. Run `make protocol-check` + `make protocol-fixtures-check` → clean.
6. Run `make ci-contract` → full CI gate passes.

**Checkpoint:** Done.

## Risks and open questions

### R1: `sliver_varied_extent` props encoding complexity

The current sparse-extent payload is a hand-rolled binary blob (header +
override pairs + optional transition header) encoded by
`Sparse_extent_list.toNativeWidgetProps` in OCaml and decoded by
`SparseExtentListProps.decode` in Dart. Moving this to a core props
encoding means the schema generator must support the repeated-struct
encoding. If the generator cannot express `varied_extent_overrides` as
a typed list-of-structs, encode it as a counted list of f64 pairs (index
as f64, validated to safe int) and validate on decode. This is the highest-
risk schema change.

### R2: Sliver children and `NodeHost` parent-data wrapping

`NodeHost` wraps children with `Flexible`/`Expanded`/`Positioned`
based on `parentData` (`node_host.dart:270-293`). Sliver children must
use `NoParentData`. The OCaml `Sliver` module must ensure sliver widgets
never carry flex/stack parent data. Since `Sliver.t` is opaque and
constructed only by `Sliver.*` functions, this is enforced by construction.
But `Sliver.padding` wraps an inner `Sliver.t` — the inner sliver's
widget is a child of the `Sliver_padding` widget, and must not get flex
parent data. Verify the OCaml `plain_children` helper is used (it sets
`NoParentData`).

### R3: `SliverAppBar` child semantics

`SliverAppBar` takes a `title` widget and manages its own flexible space.
The current `material_app_bar` core node builds a plain `AppBar`. Should
`material_app_bar` be deprecated in favor of `Sliver.app_bar`, or kept
for non-scroll scaffolds? Recommendation: keep `material_app_bar` for
`Scaffold.appBar` (fixed app bar); `Sliver.app_bar` is for collapsing
app bars inside a `Scroll_view`. They coexist.

### R4: `Morphing_surface` and `Swipe_action` interaction

`Morphing_surface` (native kind 5) consumes per-item transition progress
from `SparseExtentTransitionScope`, which was published by
`SparseExtentListHost`. Now `_SliverVariedExtentHost` publishes it.
`Morphing_surface` itself is unchanged (it's still a native widget that
wraps two box children inside a sliver list item). `Swipe_action` is
unchanged (it wraps a row content inside a sliver list item). Both continue
to work as box children of `sliver_fixed_extent` / `sliver_varied_extent`.

### R5: `visible_range_changed` event routing

Currently a native event (tag 21 `native_event` with kind_id/version/event_id).
In the new design it becomes a core event (tag 14 `visible_range_changed`).
The OCaml `Sliver.fixed_extent` / `varied_extent` constructors bind
`Event.Tag.Visible_range_changed` instead of a native event handler. The
`visible_range_of_payload` decoder moves from `Native_widget` to `Widget`
or `Event` and decodes tag 14 directly. This is a clean simplification but
touches the event dispatch path.

### R6: Protocol minor bump coordination

Bumping 1.18 → 1.19 requires the handshake to advertise the new minor. Both
OCaml and Dart must agree. The existing handshake rejects newer minors, so
a mixed-version pair fails fast with a protocol error — acceptable for a
breaking change.
