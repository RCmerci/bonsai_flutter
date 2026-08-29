# Material components

The core Material surface is renderer-independent and controlled by OCaml.
Flutter maps each logical node to its Material 3 constructor and sends typed
events back to the bound OCaml handler.

`Material.scaffold` owns the native Scaffold slots. Its canonical child order
is app bar, floating action button, bottom navigation bar, persistent bottom
sheet, and body, omitting absent optional slots. Flutter assigns these children
directly to the corresponding Scaffold properties; application code should not
manually place an app bar above the body.

The button family includes filled, filled tonal, outlined, elevated, text, and
icon buttons. `Material.Floating_action_button` provides small, standard,
large, and extended variants. All use the shared `Press` event contract.

Navigation bars and radio groups are controlled components. A navigation bar
owns at least two abstract destinations and emits a signed destination index.
A radio group owns abstract options with unique stable `int64` IDs and emits
the selected ID. The selected value remains authoritative in OCaml and must be
updated in the next logical tree.

`Material.Segmented_button` is also controlled by OCaml. Each segment has a
stable signed `int64` ID and at least one of `icon` or `label`; optional
tooltips and per-segment enabled state map directly to Flutter's native
`ButtonSegment<int>`. Pass the complete selected ID set as `selected_ids`.
The constructor rejects duplicates and unknown IDs, then sorts valid IDs in
signed ascending order so equality, reconciliation, and wire output do not
depend on caller ordering. The selection handler receives the complete new set
as `Event.Payload.Int64_list`, in the same canonical order.

```ocaml
let segments =
  [ Ui.Material.Segmented_button.segment
      ~id:1L
      ~icon:list_icon
      ~label:(Ui.Widget.text "List")
      ~tooltip:"List view"
      ()
  ; Ui.Material.Segmented_button.segment
      ~id:2L
      ~label:(Ui.Widget.text "Grid")
      ()
  ]
in
Ui.Material.Segmented_button.create
  ~multi_selection_enabled:true
  ~empty_selection_allowed:true
  ~selected_ids:model.selected_view_ids
  ~on_selection_changed
  segments
  ()
```

Single-selection mode accepts at most one selected ID. Empty selection is
valid only with `empty_selection_allowed:true`. The whole control can be
disabled independently of individual segments. Direction, expanded insets,
default selected-icon visibility, and an optional custom selected icon are
part of the semantic API. Visual styling remains owned by
`SegmentedButtonThemeData` in the active Material theme; this node does not
serialize `ButtonStyle` or `WidgetStateProperty` values.

Sliders validate finite domains, positive optional divisions, and controlled
values before encoding. Flutter coalesces continuous change events to at most
one per rendered frame, while change-end events are always delivered. Range
sliders additionally reject reversed selections.

Circular and linear progress indicators inherit their Material 3 appearance
from the application theme. Omit `value` to display indeterminate progress, or
provide a finite value from `0.0` through `1.0`, inclusive, for determinate
progress. A linear indicator receives its horizontal extent from its parent;
place it in a bounded layout such as `Widget.sized_box ~width` when necessary.

```ocaml
Ui.Widget.sized_box
  ~width:240.
  (Ui.Material.linear_progress_indicator ~value:0.68 ())
```

Action, filter, choice, and input chips have separate public constructors.
Action chips represent both assist chips (an action with an avatar/icon) and
suggestion chips (a label without an avatar). Action, filter, and choice chips
accept `Flat` or `Elevated` presentation; input chips are always flat because
Flutter does not provide `InputChip.elevated`. Filter, choice, and input chips
use controlled selected state.

Cards retain one logical node and accept `Elevated`, `Filled`, or `Outlined`.
Dividers similarly retain one node and accept horizontal or vertical
orientation plus renderer-neutral thickness, cross-axis spacing, indent, and
end-indent geometry.

`Material.search_bar` uses the same session, revision, UTF-16 selection,
composing-range, focus, submit, stale-edit, and UTF-8 limit contract as
`Material.text_field`. Its optional leading and ordered trailing children map
to Flutter `SearchBar`; suggestions and `SearchAnchor` are intentionally not
part of this API. `Material.tooltip` wraps exactly one child and supports
automatic long-press or tap triggers, finite non-negative lifecycle durations,
semantics inclusion, placement, feedback, and an optional triggered event.

`Material.Data_table` uses abstract columns, rows, and cells with stable signed
`int64` IDs. OCaml validates unique IDs, exact row widths, known controlled sort
and selected-row IDs, and canonicalizes selected IDs. Sort, row-selection, and
cell-activation events carry stable IDs rather than Flutter indices.

`Material.Stepper` owns a stable ordered step list and controlled current-step
ID. Flutter replaces its inner state when ordered IDs change. Step selection
emits the stable step ID. `Material.Expansion_panel_list` supports controlled
single and multiple policies; every toggle emits the complete, sorted expanded
ID set. It does not use `ExpansionPanelList.radio`, whose selection is
Flutter-owned.

The dialog visual family is `Material.Dialog`: `alert`, `simple`, and
`fullscreen`. A simple option emits its stable ID. These constructors describe
visual content only. Modal route policy belongs to `Navigation.Modal_dialog`,
while modal bottom sheets continue to use `Navigation.Modal_bottom_sheet`.
Persistent bottom sheets are available only through the Scaffold slot.

`SearchAnchor`, `MaterialBanner`, `CarouselView`, `PaginatedDataTable`, and
`AboutDialog` are intentionally excluded; there are no fallback or experimental
paths for them.

Snack bars are typed host effects rather than logical children. Use
`Host_effect.show_snack_bar` with a message, optional action label, duration,
and optional cancellation token; its result identifies the exact close reason.
