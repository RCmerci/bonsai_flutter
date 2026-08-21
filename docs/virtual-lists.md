# Virtual lists

`Widget.Sliver.fixed_extent` and `Widget.Sliver.varied_extent` represent large
logical collections without mounting every row in the OCaml tree. Their
contract separates three ranges:

- The logical collection is `[0, total_count)`.
- The painted range is the half-open range reported by
  `visible_range_changed` after Flutter lays out the sliver.
- The materialized range is `[first_index, first_index + List.length items)`;
  OCaml owns it and supplies keyed widgets for it.

Flutter never requests an individual row synchronously across FFI. A logical
index outside the materialized range renders as an empty placeholder until the
application catches up. The `overscan` property affects viewport cache pixels,
but it does not fetch, retain, or create OCaml widgets.

## Window policy

`Widget.Sliver.Window.create` expands a valid painted range by a logical
overscan count and clamps the result to the collection. It is pure and uses no
renderer or protocol types:

```ocaml
let materialized =
  Widget.Sliver.Window.create
    ~total_count
    ~overscan:4
    ~visible_first_index:painted.first_index
    ~visible_last_exclusive:painted.last_exclusive
in
let items =
  all_rows
  |> drop materialized.first_index
  |> take (materialized.last_exclusive - materialized.first_index)
  |> List.map (fun row ->
    Widget.Keyed.create ~key:(Key.string row.id) (render_row row))
in
Widget.Sliver.fixed_extent
  ~total_count
  ~first_index:materialized.first_index
  ~item_extent:48.
  ~overscan:4
  ~items
  ~on_visible_range
  ()
```

Applications must provide a useful initial materialized window before the
first event. A common policy stores an initial painted range such as `[0, 20)`,
derives the first materialized window from it, and replaces the stored painted
range whenever `visible_range_changed` arrives. Later events are catch-up
requests, not synchronous row callbacks.

The callback payload is decoded through
`Widget.Sliver.visible_range_of_payload`. It remains a pure painted range: it
does not include overscan. Both ends are bounded by `total_count`, independent
of the currently supplied item window.

The renderer keeps initial publication pending while a mounted sliver has no
usable paint geometry. A later layout transition to a positive painted extent
publishes exactly one current range without requiring controller movement.
Unchanged ranges are deduplicated, and a permanently zero-paint sliver does not
schedule a frame loop.

## Fixed and varied extents

The fixed form uses `SliverFixedExtentList` and one positive finite
`item_extent`. The varied form uses `SliverVariedExtentList`, one positive
finite `default_item_extent`, and sorted sparse overrides:

```ocaml
let materialized =
  Widget.Sliver.Window.create
    ~total_count
    ~overscan:4
    ~visible_first_index:painted.first_index
    ~visible_last_exclusive:painted.last_exclusive
in
Widget.Sliver.varied_extent
  ~total_count
  ~first_index:materialized.first_index
  ~default_item_extent:48.
  ~extent_overrides:
    [ { Widget.Sparse_extent_override.index = 104; extent = 312. } ]
  ~transition:
    (Widget.Sparse_extent_transition.create
       ~expand_duration_ms:240
       ~collapse_duration_ms:190
       ())
  ~overscan:4
  ~items:keyed_materialized_rows
  ~on_visible_range
  ()
```

Sparse extents are known geometry, not arbitrary self-measurement. Leading
offsets and painted ranges come from the default extent plus sparse prefix
deltas, so an override remains meaningful outside the current materialized
window.

The optional transition interpolates changed extents on one Flutter-owned
timeline. It preserves a logical anchor and its intra-item offset, suppresses
painted-range publication during correction, and emits the settled range once.
Reduced motion applies final geometry immediately. No per-frame animation
values cross FFI.

## Cache and initial anchors

`Scroll_view` derives its viewport cache extent from the maximum
`overscan * item_extent` among nested virtual slivers unless an explicit
`cache_extent` is supplied. Explicit and derived values must be finite and
non-negative. Logical overscan is exact for the OCaml materialized range; its
conversion to cache pixels is approximate for varied extents.

One coordinator owned by the enclosing `Scroll_view` arbitrates implicit
initial anchors. The earliest virtual sliver in layout order owns the decision:

- `first_index = 0` keeps the normal leading scroll offset;
- a positive `first_index` targets that sliver's global leading offset plus its
  local logical offset, clamped to the controller extent;
- later virtual slivers cannot move the shared controller;
- a user or external non-zero offset disables implicit anchoring.

This preserves preceding box or app-bar geometry while preventing callback
order from deciding global scroll position.

## Pagination and identity

A continuation row is part of `total_count` while loading. Recompute the
materialized range whenever either the painted range or `total_count` changes,
then include the continuation widget only when its logical index lies inside
that range. After an append, the same stored painted range expands against the
new count, so newly loaded rows can enter the window without a gesture.

Rows must use stable keys. Overlap between the old and new materialized ranges
then preserves element and OCaml node identity while pagination advances. The
mail example implements this policy and ignores repeated tail notifications
for an in-flight load generation.

## Limits

Consumers still own state, effects, pagination, asymmetric or velocity-aware
prefetching, and timely window updates. Self-measuring rows, two-dimensional
virtualization, graph canvases, and virtualized tree editors require separate
extensions.

Both virtual-list slivers live inside a `Scroll_view`, which returns
`Viewport.Vertical.t` or `Viewport.Horizontal.t`, not `Widget.t`. See
[Viewport layout](viewport-layout.md) for embedding rules.
