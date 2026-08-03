# Virtual lists

`Native_widget.Virtual_list` represents a large logical collection without
mounting every row in the OCaml tree or creating a `NodeHost` per logical
item. OCaml supplies only a keyed, prefetched item window:

```ocaml
Native_widget.Virtual_list.create
  ~total_count:50_000
  ~first_index:100
  ~item_extent:48.
  ~overscan:4
  ~items:twenty_keyed_rows
  ~on_visible_range
  ()
```

The binary properties contain the logical count, window origin, fixed item
extent, overscan count, and scroll axis. Flutter uses `ListView.builder` and
maps logical indexes into the supplied child window. It never requests an
individual row synchronously across FFI.

Visible-range changes are emitted as a typed native event. Applications use
that range to advance or prefetch a window in OCaml. The reported logical range
is bounded by `total_count`, not by the currently supplied child window. This
lets a fast scroll request a catch-up window instead of becoming pinned to
stale supplied indexes.

Effectful applications can attach a driver-managed handler directly with
`create_with_handler` and validate raw input through
`visible_range_of_payload`. A typical append feed keeps one cursor and one load
generation in OCaml, ignores repeated range events while loading, supplies an
overlapping keyed window, and schedules completion through Bonsai logical
time. Flutter retains the controller and exact offset while props and children
advance.

The widget test uses 50,000 logical items with a 20-item OCaml window. It
proves that no more than the window's `NodeHost` widgets are mounted, fast
scrolling emits logical catch-up ranges, and an overlapping keyed row retains
its Flutter `Element` when the window advances or logical indexes shift.

`Virtual_list` remains a fixed-`item_extent` contract. Arbitrary self-measuring
rows, two-dimensional virtualization, graph canvases, and virtualized tree
editors belong in separate native extensions.

## Sparse known extents

`Native_widget.Sparse_extent_list` is built-in extension kind `4`. Schema
version `1` retains immediate extent updates. Schema version `2` adds an
explicit optional transition while retaining the same bounded OCaml child
window, default extent, and sorted logical-index overrides:

```ocaml
Native_widget.Sparse_extent_list.create
  ~total_count:50_000
  ~first_index:100
  ~default_item_extent:48.
  ~extent_overrides:[ { index = 104; extent = 312. } ]
  ~transition:
    (Native_widget.Sparse_extent_list.Transition.create
       ~expand_duration_ms:240
       ~collapse_duration_ms:190
       ())
  ~overscan:4
  ~items:twenty_keyed_rows
  ~on_visible_range
  ()
```

The payload validates exact length, safe indexes, sorted uniqueness, reserved
bytes, axis, and finite positive extents on both sides. Flutter uses
`ListView.builder.itemExtentBuilder`; it does not measure arbitrary child
heights. Leading offsets and visible ranges come from the default extent plus
sparse prefix deltas, so an override may remain correct even when its logical
item is outside the supplied OCaml window.

Version `2` captures current effective extents, interpolates all changed
indexes on one Flutter-owned timeline, and retargets from the current geometry
when interrupted. Accordion removal and addition animate concurrently. Extent
updates preserve a logical anchor and its intra-item offset; a newly expanded
visible override is preferred, otherwise the old first visible item is
retained. Direct scrolling releases the animation anchor. Visible-range
emission is suppressed until the target settles, and reduced motion applies
the final geometry immediately. No per-frame values cross FFI.

The same per-index progress drives `MorphingSurfaceHost`, which clips and
interpolates generic compact/expanded surface geometry while retaining outgoing
visuals. Only committed target content participates in hit testing and
semantics. The controller, bounded mounts, keyed child identity, and fast
catch-up behavior remain retained across window updates.

OCaml composes the two endpoint trees with
`Native_widget.Morphing_surface.create`. The wrapper is placed inside the
single keyed row or swipe host, so list identity and gesture arbitration remain
unchanged while both endpoint visuals are available to Flutter.
