# Virtual lists

`Widget.Sliver.fixed_extent` represents a large logical collection without
mounting every row in the OCaml tree or creating a `NodeHost` per logical
item. OCaml supplies only a keyed, prefetched item window:

```ocaml
let viewport =
  Widget.Scroll_view.vertical
    ~on_scroll:scroll_handler
    [ Widget.Sliver.fixed_extent
        ~total_count:50_000
        ~first_index:100
        ~item_extent:48.
        ~overscan:4
        ~items:twenty_keyed_rows
        ~on_visible_range
        ()
    ]
    ()
in
Body.Vertical.create [ Body.Vertical.fill viewport ]
```

The sliver props contain the logical count, window origin, fixed item
extent, and overscan count. Flutter uses `SliverFixedExtentList` and
maps logical indexes into the supplied child window. It never requests an
individual row synchronously across FFI.

Visible-range changes are emitted as a core event (tag 14,
`visible_range_changed`). Applications use that range to advance or
prefetch a window in OCaml. The reported logical range is bounded by
`total_count`, not by the currently supplied child window. This lets a
fast scroll request a catch-up window instead of becoming pinned to stale
supplied indexes.

Applications attach a driver-managed `Event.Handler.t` and validate raw
input through `Widget.Sliver.visible_range_of_payload`. A typical append
feed keeps one cursor and one load generation in OCaml, ignores repeated
range events while loading, supplies an overlapping keyed window, and
schedules completion through Bonsai logical time. Flutter retains the
controller and exact offset while props and children advance.

`Sliver.fixed_extent` remains a fixed-`item_extent` contract. Arbitrary
self-measuring rows, two-dimensional virtualization, graph canvases, and
virtualized tree editors belong in separate extensions.

## Sparse known extents

`Widget.Sliver.varied_extent` is a core sliver kind
(`sliver_varied_extent`, kind 36). It supports a default item extent with
sorted logical-index overrides and an optional transition:

```ocaml
let viewport =
  Widget.Scroll_view.vertical
    ~on_scroll:scroll_handler
    [ Widget.Sliver.varied_extent
        ~total_count:50_000
        ~first_index:100
        ~default_item_extent:48.
        ~extent_overrides:[ { Widget.Sparse_extent_override.index = 104; extent = 312. } ]
        ~transition:
          (Widget.Sparse_extent_transition.create
             ~expand_duration_ms:240
             ~collapse_duration_ms:190
             ())
        ~overscan:4
        ~items:twenty_keyed_rows
        ~on_visible_range
        ()
    ]
    ()
in
Body.Vertical.create [ Body.Vertical.fill viewport ]
```

The props validate exact length, safe indexes, sorted uniqueness, and finite
positive extents on both sides. Flutter uses `SliverVariedExtentList`; it
does not measure arbitrary child heights. Leading offsets and visible ranges
come from the default extent plus sparse prefix deltas, so an override may
remain correct even when its logical item is outside the supplied OCaml
window.

The optional transition captures current effective extents, interpolates all
changed indexes on one Flutter-owned timeline, and retargets from the current
geometry when interrupted. Accordion removal and addition animate
concurrently. Extent updates preserve a logical anchor and its intra-item
offset; a newly expanded visible override is preferred, otherwise the old
first visible item is retained. Direct scrolling releases the animation
anchor. Visible-range emission is suppressed until the target settles, and
reduced motion applies the final geometry immediately. No per-frame values
cross FFI.

The same per-index progress drives `MorphingSurfaceHost`, which clips and
interpolates generic compact/expanded surface geometry while retaining
outgoing visuals. Only committed target content participates in hit testing
and semantics. The controller, bounded mounts, keyed child identity, and fast
catch-up behavior remain retained across window updates.

OCaml composes the two endpoint trees with
`Native_widget.Morphing_surface.create`. The wrapper is placed inside the
single keyed row or swipe host, so list identity and gesture arbitration
remain unchanged while both endpoint visuals are available to Flutter.

Both virtual-list slivers are children of a `Scroll_view` which returns
`Viewport.Vertical.t` or `Viewport.Horizontal.t`, not `Widget.t`. See
[Viewport layout](viewport-layout.md) for bounded body and explicit extent
embedding.
