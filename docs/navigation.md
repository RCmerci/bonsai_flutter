# Navigation, modal presentation, overlay, and dialog

The business route stack is an OCaml value. `Widget.navigator` contains typed
`Widget.page` children with stable page keys, presentation contracts, `can_pop`,
and optional restoration IDs. Presentation is distinct from transition: a
standard page carries `None`, `Fade`, or `Slide` transition intent, while a
modal bottom sheet changes route opacity, barrier ownership, focus, semantics,
safe-area behavior, and keyboard geometry.

Standard pages use `Navigation.Standard transition`. The default is
`Navigation.Standard Navigation.None`.

Flutter maps the committed list to declarative `Navigator.pages`. Transition
interpolation remains local to Flutter. A platform or system pop emits a typed
RoutePop event containing the page key and optional result. OCaml updates its
route stack, and the next frame creates or drops the corresponding Page
subtree. Dart does not retain a second router state.

## Modal bottom sheet pages

A modal bottom sheet remains an item in the OCaml-owned page list. Adding the
item presents one route, removing it dismisses that route, and a stable page key
updates the existing route without replacing its child state. A different key
creates a distinct route. A modal bottom sheet cannot be the first page because
it requires a lower route to compose behind its barrier.

```ocaml
let handle_semantics =
  Ui.Navigation.Modal_bottom_sheet.Handle_semantics.create
    ~label:"Adjust filter sheet height"
    ~medium_value:"Half height"
    ~large_value:"Full height"
in
let detents =
  Ui.Navigation.Modal_bottom_sheet.Detents.create
    ~semantics:handle_semantics
    [ Ui.Navigation.Modal_bottom_sheet.Detent.Medium
    ; Ui.Navigation.Modal_bottom_sheet.Detent.Large
    ]
in
let filter_sheet =
  Ui.Navigation.Modal_bottom_sheet.create
    ~barrier_label:"Close filters"
    ~sizing:(Ui.Navigation.Modal_bottom_sheet.Sizing.Detented detents)
    ~use_safe_area:true
    ()
in
let filter_editor =
  Ui.Widget.List_view.vertical ~primary:true ~on_scroll filter_rows ()
in
Ui.Widget.navigator
  ~on_pop
  [ Ui.Widget.page
      ~page_key:(ID.Navigation.Page_key.of_string "results")
      results
  ; Ui.Widget.page
      ~page_key:(ID.Navigation.Page_key.of_string "filters")
      ~presentation:(Ui.Navigation.Modal_bottom_sheet filter_sheet)
      ~can_pop:filters_may_close
      ~restoration_id:(ID.Navigation.Restoration_id.of_string "filters-sheet")
      filter_editor
  ]
```

The configuration defaults are:

| Option | Default | Route behavior |
| --- | --- | --- |
| `barrier_dismissible` | `true` | A barrier tap may request a pop, subject to live `can_pop`. |
| `barrier_color` | `None` | Uses Material `Colors.black54`; a transparent color still blocks input. |
| `barrier_label` | `None` | Uses the localized Material scrim label. |
| `sizing` | `Sizing.Content_bounded` | Selects content-bounded, scroll-controlled, or detented route sizing. |
| `use_safe_area` | `false` | When enabled, avoids top, left, and right system padding; the route still extends to the bottom edge. |
| `request_focus` | `true` | The route acquires its own focus scope; an autofocus child may then receive focus normally. |
| `transition_duration_ms` | `250` | Nonnegative `u32` entrance duration. |
| `reverse_transition_duration_ms` | `200` | Nonnegative `u32` exit duration. |

The route is the single keyboard-inset owner. It applies
`MediaQuery.viewInsets.bottom` once outside the child and removes that bottom
view inset from the child's `MediaQuery`. Consumers must not apply the keyboard
inset again. Product padding, scrolling, surface shape, and content layout
remain consumer owned. The route supplies a transparent Material host surface.

`MediaQuery.disableAnimations` or `accessibleNavigation` resolves both route
durations to zero. A change while the route is mounted updates the active route
and its animation controller without replacing child state.

`Sizing.Detented` supports `Medium`, `Large`, or both. `Medium` is half of the
keyboard-adjusted route viewport and `Large` fills it. The initial detent must
belong to the configured set. Drag dismissal defaults to enabled and can be
disabled with `~dismiss_on_drag:false`.

A detented page must contain exactly one vertical `Scroll_view` or `List_view`
created with `~primary:true`. It borrows the route controller: an upward drag
expands before scrolling content, while a downward drag scrolls to the leading
edge, collapses, and may dismiss past the smallest visible detent. Horizontal,
zero, or multiple primary scrollables are rejected.

The route-owned handle supports touch and mouse drag, tap-to-cycle, and
accessibility increase/decrease actions. Its label and current detent values
are required through `Handle_semantics`.

Flutter's native modal drag remains disabled because it calls `Navigator.pop`
without the required declarative preflight. The detented host rechecks the
latest same-key `can_pop` after layout and calls `Navigator.maybePop`; a veto
returns the sheet to its smallest visible detent. Barrier tap, platform Back,
and Escape also use preflighted pop paths.

An allowed native dismissal emits exactly one typed `RoutePop` event. OCaml
removes the page in its next declarative frame. Direct declarative removal does
not consult `can_pop`, because OCaml has already made the removal decision.

## Standard pages and non-route overlays

`Navigation.Standard Navigation.Slide` is realized as a page-based
`CupertinoPage`. Its maintained framework transition provides front-loaded
entrance motion, underlying-page parallax, edge shadow, directionality, and an
interactive leading-edge pop. The route follows the finger linearly while an
edge gesture is active. A cancelled gesture emits nothing; a committed gesture
removes the Flutter route and emits exactly one RoutePop containing the actual
page key. Application code must validate that key before changing its OCaml
route state.

`Navigation.Standard Navigation.None` and
`Navigation.Standard Navigation.Fade` retain their existing page-route
behavior.

`Widget.overlay` and `Widget.material_dialog` follow the same ownership rule:
their content and presence are declared by OCaml, while Flutter owns layout,
paint, hit testing, and transition frames.
