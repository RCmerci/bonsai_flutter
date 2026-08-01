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

The prototype currently requires a fixed `item_extent`. Variable-height rows,
two-dimensional virtualization, graph canvases, and virtualized tree editors
belong in separate native extensions.
