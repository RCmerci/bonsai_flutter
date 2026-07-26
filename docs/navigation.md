# Navigation, overlay, and dialog

The business route stack is an OCaml value. `Widget.navigator` contains typed
`Widget.page` children with stable page keys, transition intent, `can_pop`,
and optional restoration IDs.

Flutter maps the committed list to declarative `Navigator.pages`. Transition
interpolation remains local to Flutter. A platform or system pop emits a typed
RoutePop event containing the page key and optional result. OCaml updates its
route stack, and the next frame creates or drops the corresponding Page
subtree. Dart does not retain a second router state.

`Widget.overlay` and `Widget.material_dialog` follow the same ownership rule:
their content and presence are declared by OCaml, while Flutter owns layout,
paint, hit testing, and transition frames.

