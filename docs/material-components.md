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
Filter, choice, and input chips use controlled selected state; input chips can
also bind press and delete actions. `Material.alert_dialog` describes dialog
content and action slots. Modal route policy belongs to
`Navigation.Modal_dialog`, while modal bottom sheets continue to use
`Navigation.Modal_bottom_sheet`. Persistent bottom sheets are available only
through the Scaffold slot.

Snack bars are typed host effects rather than logical children. Use
`Host_effect.show_snack_bar` with a message, optional action label, duration,
and optional cancellation token; its result identifies the exact close reason.
