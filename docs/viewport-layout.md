# Viewport layout

A viewport is content that requires a finite extent on its scroll axis.
Vertical and horizontal requirements are represented by distinct opaque OCaml
types:

- `Viewport.Vertical.t` requires finite height;
- `Viewport.Horizontal.t` requires finite width.

Core `Scroll_view` and `List_view` constructors, `Virtual_list`, and
`Sparse_extent_list` expose separate `vertical` and `horizontal` entry points.
They do not return `Widget.t`, and their scroll axis is not a runtime optional
argument. As a result, a vertical viewport cannot be passed to `Widget.column`
or `Widget.Flex.fixed`, and a horizontal viewport cannot be passed to
`Widget.row`.

## Bounded bodies

`Body.Vertical.fill` and `Body.Horizontal.fill` are the normal embedding
paths. They encode tight flex parent data, while `fixed` children remain
ordinary non-flex widgets:

```ocaml
let feed =
  Ui.Native_widget.Sparse_extent_list.vertical
    ~total_count
    ~first_index
    ~default_item_extent
    ~extent_overrides
    ~items
    ~on_visible_range
    ()
in
let body =
  Ui.Body.Vertical.create
    [ Ui.Body.Vertical.fixed search_action
    ; Ui.Body.Vertical.fill feed
    ]
in
Ui.Material.scaffold ~app_bar ~body ()
```

Framework slots that guarantee finite constraints consume `Body.t`.
`Material.scaffold` accepts one body, and `Navigation_shell` accepts a list of
bodies. Non-scrollable content remains valid through `Body.static`.

`Body.overlay` positions its base against all four edges before adding stack
overlays. This preserves the bounded body contract and prevents an overlay from
causing the base viewport to be measured with an unbounded scroll axis.

## Explicit finite extents

A viewport becomes `Widget.t` only through an axis-specific finite extent:

```ocaml
let preview =
  feed
  |> Ui.Viewport.Vertical.with_height ~height:240.
in
Ui.Widget.column [ heading; preview ]
```

`Viewport.Vertical.with_height` and `Viewport.Horizontal.with_width` reject
NaN, infinity, zero, and negative values. Transparent viewport decorators such
as test IDs, padding, decoration, semantics, safe areas, and themes preserve
the axis-specific viewport type.

`shrinkWrap` is not a substitute for a bounded virtualized viewport. It changes
layout and virtualization behavior rather than proving that the viewport has a
finite scroll-axis extent.

## Runtime guard

The OCaml types are the public guarantee. Flutter also checks incoming
constraints before constructing a real viewport so malformed frames, direct
Dart use, and internal renderer defects fail safely in debug, profile, and
release builds.

An invalid node reports one structured diagnostic for its node ID, local
revision, widget kind, axis, and actual constraints. The renderer then shows a
finite `RendererLayoutError` surface without constructing `ListView`,
`SingleChildScrollView`, or another viewport. Repeated frames do not re-report
the same violation or enter a layout/semantics exception loop. A newer valid
constraint boundary clears the recorded violation.
