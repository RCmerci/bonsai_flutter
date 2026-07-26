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
that range to advance or prefetch a window in OCaml. Range notifications are
bounded to the supplied window; a window update can retain overlapping node
IDs and keys.

The widget test uses 50,000 logical items with a 20-item OCaml window. It
proves that no more than the window's `NodeHost` widgets are mounted, scrolling
emits visible ranges, and an overlapping keyed row retains its Flutter
`Element` when the window advances.

The prototype currently requires a fixed `item_extent`. Variable-height rows,
two-dimensional virtualization, graph canvases, and virtualized tree editors
belong in separate native extensions.
