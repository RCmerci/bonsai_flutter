# Navigation, overlay, and dialog

The business route stack is an OCaml value. `Widget.navigator` contains typed
`Widget.page` children with stable page keys, transition intent, `can_pop`,
and optional restoration IDs.

Flutter maps the committed list to declarative `Navigator.pages`. Transition
interpolation remains local to Flutter. A platform or system pop emits a typed
RoutePop event containing the page key and optional result. OCaml updates its
route stack, and the next frame creates or drops the corresponding Page
subtree. Dart does not retain a second router state.

`Navigation.Slide` is realized as a page-based `CupertinoPage`. Its maintained
framework transition provides front-loaded entrance motion, underlying-page
parallax, edge shadow, directionality, and an interactive leading-edge pop.
The route follows the finger linearly while an edge gesture is active. A
cancelled gesture emits nothing; a committed gesture removes the Flutter route
and emits exactly one RoutePop containing the actual page key. Application
code must validate that key before changing its OCaml route state.

`Navigation.None` and `Navigation.Fade` retain their existing page-route
behavior.

`Widget.overlay` and `Widget.material_dialog` follow the same ownership rule:
their content and presence are declared by OCaml, while Flutter owns layout,
paint, hit testing, and transition frames.
