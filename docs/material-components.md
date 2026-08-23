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

Sliders validate finite domains, positive optional divisions, and controlled
values before encoding. Flutter coalesces continuous change events to at most
one per rendered frame, while change-end events are always delivered. Range
sliders additionally reject reversed selections.

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
