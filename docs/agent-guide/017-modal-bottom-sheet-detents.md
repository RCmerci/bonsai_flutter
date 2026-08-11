# Detented Modal Bottom Sheet Design

Status: Implemented

## Summary

Extend the existing declarative modal-bottom-sheet page presentation with an
iOS-like detented interaction model:

- A sheet can rest at the system-style `Medium` and `Large` detents.
- An upward drag expands the sheet before scrolling its content.
- A downward drag scrolls content to its leading edge, collapses the sheet,
  and can dismiss it past the smallest visible detent.
- Every dismissal attempt reads the latest same-key `Page.canPop` value before
  the route is removed.
- A route-owned drag handle supports touch, mouse, keyboard, and accessibility
  adjustment actions.

This remains a page presentation. It does not add a bottom-sheet `NodeKind`.
The page child continues to be an ordinary widget tree. The only generic
widget-surface change is an explicit `primary` controller option on vertical
scroll views so a scrollable child can participate in route-owned detent
gestures.

The implementation should use Flutter's public `DraggableScrollableSheet` and
`PrimaryScrollController` APIs inside the existing
`ModalBottomSheetRoute`. It must not enable the route's built-in drag-to-close
path because that path starts the closing animation and calls `Navigator.pop`
without consulting `Route.popDisposition` first.

## Current baseline

The repository currently supports:

- `Navigation.Standard` pages with `None`, `Fade`, and `Slide` transitions.
- `Navigation.Modal_bottom_sheet` pages backed by a real, non-opaque
  `ModalBottomSheetRoute`.
- Declarative page identity, restoration IDs, live `can_pop`, native barriers,
  focus isolation, safe-area policy, keyboard-inset ownership, and reduced
  motion.
- Barrier, Back, and Escape dismissal through preflighted pop paths.

Drag is deliberately disabled today:

```dart
enableDrag: false,
showDragHandle: false,
```

That decision is correct for Flutter's built-in modal drag implementation.
`BottomSheet` begins reversing the route animation before its `onClosing`
callback. The modal route's callback then invokes `Navigator.pop`, while
`Page.canPop` is consulted by `Navigator.maybePop`, not by `Navigator.pop`.
Vetoing after the animation reaches zero would leave the route present but
visually closed unless the framework also owns the recovery animation.

The current `is_scroll_controlled` boolean only changes the route height
constraint. It does not create detents, snapping, or scroll-to-resize
coordination by itself.

## Research findings

### Apple interaction model

Apple describes resizable sheets in terms of detents: heights where a sheet
naturally rests. UIKit provides `medium` and `large` system detents, plus custom
detents. The system medium detent is approximately half height; large is the
fully expanded height. Detents must be supplied from smallest to largest.

Apple's guidance establishes the target interaction:

- Scrolling upward expands a resizable sheet before scrolling its content.
- A grabber communicates that the sheet is resizable.
- The grabber can be tapped to move between detents and must be accessible to
  VoiceOver users.
- A vertical swipe is an expected dismissal gesture.
- UIKit asks its adaptive presentation delegate whether an interactive
  dismissal is allowed before completing it.

This proposal provides behavioral parity through Flutter widgets. It does not
embed or invoke `UISheetPresentationController`, so Android and desktop hosts
receive the same declarative behavior.

### Flutter primitives

`ModalBottomSheetRoute` owns the correct modal barrier, route focus,
semantics boundary, safe-area behavior, and entrance/exit transition. Its
`enableDrag` option supports vertical dragging and downward dismissal, but it
does not expose a pre-dismiss callback suitable for the live declarative
`can_pop` contract.

`DraggableScrollableSheet` provides the missing resizing and scrolling
coordination:

- `initialChildSize`, `minChildSize`, and `maxChildSize` are fractions of the
  available parent height.
- `snap` and `snapSizes` create resting sizes.
- The provided `ScrollController` makes an upward gesture resize the sheet,
  then scroll content after the maximum extent is reached.
- `minChildSize` may be zero.
- `DraggableScrollableNotification` reports extent changes without forcing a
  parent dismissal.
- `DraggableScrollableController` can return a vetoed dismissal to the first
  visible detent.

The child scrollable must use the controller supplied by
`DraggableScrollableSheet`; otherwise the sheet remains at its initial size.
`PrimaryScrollController` is Flutter's standard mechanism for associating a
controller with a subtree, but the existing renderer always supplies its own
controller to every `ScrollView` and `ListView`. The renderer therefore needs
an explicit primary-controller path.

## Goals

1. Match the core iOS medium/large sheet interaction on touch devices.
2. Preserve OCaml ownership of page presence and `can_pop`.
3. Keep the current real modal route, barrier, focus, semantics, restoration,
   keyboard, and safe-area behavior.
4. Coordinate one vertical content scrollable with route-owned resizing.
5. Preserve scroll position, text editing state, and the selected detent across
   same-key page updates.
6. Provide deterministic, testable dismissal and veto recovery.
7. Support drag-handle operation with pointer and accessibility actions.

## Non-goals

- Custom pixel or content-height detents.
- A nonmodal or undimmed detent.
- Exposing the selected detent as OCaml application state.
- Persisting the selected detent through process restoration.
- Consumer-specific surface colors, shapes, padding, or business state.
- An imperative `showModalBottomSheet` API.
- A bottom-sheet widget node or a native UIKit bridge.
- Multiple coordinated vertical scrollables inside one sheet.
- A veto-attempt event for confirmation UI. A future design may add a typed
  pop-attempt event analogous to UIKit's dismissal-attempt delegate callback.

## Proposed public API

Replace the modal `is_scroll_controlled` boolean with a typed sizing contract.
There is no compatibility alias or fallback decoder.

```ocaml
module Modal_bottom_sheet : sig
  module Detent : sig
    type t =
      | Medium
      | Large
  end

  module Handle_semantics : sig
    type t

    val create
      :  label:string
      -> medium_value:string
      -> large_value:string
      -> t
  end

  module Detents : sig
    type t

    val create
      :  ?initial:Detent.t
      -> ?dismiss_on_drag:bool
      -> semantics:Handle_semantics.t
      -> Detent.t list
      -> t
  end

  module Sizing : sig
    type t =
      | Content_bounded
      | Scroll_controlled
      | Detented of Detents.t
  end

  type t

  val create
    :  ?barrier_dismissible:bool
    -> ?barrier_color:Style.Color.t
    -> ?barrier_label:string
    -> ?sizing:Sizing.t
    -> ?use_safe_area:bool
    -> ?request_focus:bool
    -> ?transition_duration_ms:int
    -> ?reverse_transition_duration_ms:int
    -> unit
    -> t
end
```

The scrollable content opts into the controller supplied by the detented route:

```ocaml
Ui.Widget.List_view.vertical
  ~primary:true
  ~on_scroll
  rows
  ()
```

Add `?primary:bool` to `Scroll_view.vertical` and `List_view.vertical`. The
default is `false`. A primary vertical scrollable requires an enclosing primary
controller. A detented modal route requires exactly one primary vertical
scrollable in its child subtree.

Example:

```ocaml
let handle_semantics =
  Ui.Navigation.Modal_bottom_sheet.Handle_semantics.create
    ~label:"Adjust sheet height"
    ~medium_value:"Half height"
    ~large_value:"Full height"
in
let detents =
  Ui.Navigation.Modal_bottom_sheet.Detents.create
    ~initial:Medium
    ~semantics:handle_semantics
    [ Medium; Large ]
in
let sheet =
  Ui.Navigation.Modal_bottom_sheet.create
    ~barrier_label:"Close filters"
    ~sizing:(Detented detents)
    ~use_safe_area:true
    ()
in
Ui.Widget.page
  ~page_key
  ~presentation:(Ui.Navigation.Modal_bottom_sheet sheet)
  ~can_pop
  primary_scrollable_content
```

The concrete constructor paths may be fully qualified in shipped examples to
avoid ambiguity; the shortened constructors above illustrate the type shape.

### API rules and defaults

| Setting | Rule |
| --- | --- |
| `sizing` | Defaults to `Content_bounded`, matching the current bounded behavior. |
| detents | Must contain one or both of `Medium` and `Large`; duplicates are rejected and storage is canonical smallest-to-largest. |
| `initial` | Defaults to the smallest configured detent and must be present in the configured set. |
| `dismiss_on_drag` | Defaults to `true`; `can_pop` remains the final authority. |
| drag handle | Always visible in detented mode; there is no misleading resizable mode without an accessible affordance. |
| handle semantics | Required and nonempty because Flutter has no localized medium/large sheet strings. |
| primary scrollable | Exactly one vertical `Scroll_view` or `List_view` with `primary = true`. Horizontal scrollables remain independent. |

`Content_bounded` retains Material's bounded-height behavior.
`Scroll_controlled` retains the current unbounded route-height behavior without
detents or drag. `Detented` sets the route to scroll-controlled internally and
owns the sheet extent.

Only the two Apple system-style detents are included initially. This avoids a
premature list-of-floats protocol, identifier lifecycle, pixel-height
resolution, and compact-height policy for arbitrary custom detents.

## Runtime architecture

```text
OCaml Navigator.pages
└── Page(presentation = Modal_bottom_sheet Detented, can_pop = live value)
    └── ModalBottomSheetRoute
        ├── native modal barrier, focus scope, safe area, keyboard inset
        └── BottomSheet(enableDrag = false, showDragHandle = false)
            └── DetentedSheetHost
                └── DraggableScrollableSheet
                    ├── route-owned accessible drag handle
                    └── PrimaryScrollController
                        └── ordinary Bonsai widget subtree
                            └── one vertical scrollable(primary = true)
```

The outer `ModalBottomSheetRoute` continues to own modality. Its built-in drag
and handle stay disabled. The `DetentedSheetHost` is a private renderer widget,
not a protocol node.

For a medium/large sheet:

```dart
DraggableScrollableSheet(
  minChildSize: dismissalEnabled ? 0.0 : 0.5,
  initialChildSize: 0.5,
  maxChildSize: 1.0,
  snap: true,
  snapSizes: dismissalEnabled ? const [0.5] : null,
  shouldCloseOnMinExtent: false,
  controller: detentController,
  builder: (context, scrollController) => ...,
)
```

The exact `snapSizes` list is derived from the configured visible detents.
`minChildSize = 0` is an internal dismissal target, not a public detent. The
smallest public detent remains `Medium` or `Large`.

### Drag state machine

| Starting state | Gesture | Result |
| --- | --- | --- |
| `Medium`, content at offset 0 | Drag up | Resize toward `Large`; snap on release. |
| `Large`, content not at max scroll | Drag up | Scroll content. |
| `Large`, content offset greater than 0 | Drag down | Scroll content toward offset 0. |
| `Large`, content at offset 0 | Drag down | Resize toward `Medium`; snap on release. |
| smallest visible detent, `can_pop = true` | Drag down beyond threshold | Snap toward internal extent 0, preflight, then dismiss. |
| smallest visible detent, `can_pop = false` | Drag down | Do not expose extent 0; remain at or return to the smallest visible detent. |

Flutter chooses the next snap target in the gesture direction when release has
velocity and the nearest target otherwise. This matches the desired native
feel without implementing a second velocity model.

### Live `can_pop` and safe dismissal

The detented host must derive its minimum extent from the latest route page:

- `dismiss_on_drag && page.canPop`: minimum extent is `0.0`.
- Otherwise: minimum extent is the smallest visible detent.

Changing `can_pop` on a stable page key rebuilds the route child without
recreating the route or content state. If `can_pop` becomes false during an
active drag below the smallest visible detent, the controller animates back to
that detent.

When extent zero is reached, a guarded dismissal task:

1. Records the notification and schedules work after the current layout frame;
   it does not mutate layout from the notification callback.
2. Ignores duplicate zero-extent notifications while a dismissal is active.
3. Reads the current route settings again.
4. If dismissal is no longer allowed, returns to the smallest visible detent.
5. Otherwise calls `Navigator.maybePop`, never `Navigator.pop`.
6. Lets the existing page-based removal emit exactly one typed `RoutePop`.

This preserves the distinction between an interactive request and direct
declarative removal. When OCaml removes the page from `Navigator.pages`, the
route exits even if `can_pop` is false because OCaml already made the decision.

### Primary scroll-controller binding

The renderer currently stores an owned `ScrollController` per scroll node.
Detented scrolling requires a borrowed controller supplied by
`DraggableScrollableSheet`.

Refactor the resource entry to distinguish ownership:

```text
ScrollControllerBinding
├── owned: renderer creates and disposes the controller
└── borrowed: route creates and disposes the controller
```

A private stateful scroll host binds the borrowed controller to the scroll
node ID while mounted and unbinds it before disposal. This is necessary so the
existing `scroll_to` host request still targets the actual controller. The
resource store must never dispose a borrowed controller.

Rules:

- `primary = false` acquires the existing owned resource.
- `primary = true` reads the nearest explicit primary controller and registers
  a borrowed binding.
- Missing or multiple primary attachments produce a typed renderer error with
  the offending node IDs.
- A node that changes between primary and owned modes releases the old binding
  before acquiring the new one.
- Dropping the page unregisters the borrowed binding before the detent host
  disposes its controller.

## Drag handle and accessibility

Do not use `ModalBottomSheetRoute.showDragHandle`. Flutter's default Material
handle is not detent aware; in the pinned framework source its semantic tap is
wired to `onClosing`.

The private detent handle should:

- Reserve a minimum 48 logical-pixel hit target.
- Draw a theme-derived handle while leaving surface color and shape consumer
  owned.
- Resize continuously during a pointer drag and snap on release.
- Accept mouse dragging even though desktop scroll behavior does not normally
  use mouse drag for scrolling.
- Tap to cycle to the next configured detent.
- Expose adjustable semantics with `onIncrease` and `onDecrease`.
- Announce the caller-provided label and current medium/large value.
- Treat decrease at the smallest detent as dismiss only when current `can_pop`
  and `dismiss_on_drag` allow it.
- Use immediate extent changes when reduced motion is active.

The route remains responsible for excluding the lower page from accessibility
interaction. The existing barrier label remains independent from the handle
label.

## Layout, keyboard, and safe areas

Detent fractions are resolved against the route's usable height after the
existing bottom keyboard inset has been applied. A medium sheet therefore
occupies half of the viewport above the keyboard, not half of the obscured full
screen.

The existing single keyboard-inset owner remains unchanged:

1. The route applies `MediaQuery.viewInsets.bottom` outside its child.
2. The child receives a `MediaQuery` with that bottom view inset removed.
3. The detented host sizes itself inside the remaining usable viewport.

`use_safe_area` continues to govern top, left, and right intrusions. The sheet
remains attached to the bottom edge. The large detent is `1.0` of the usable
route height; medium is `0.5`.

For compact height, both values are clamped by the available constraints and
must not overflow. The first release does not attempt to reproduce UIKit's
private compact-height rule that deactivates its system medium detent.

## Declarative updates and local state

The selected detent is transient renderer interaction state, like animation
progress and scroll offset. It is not sent to OCaml.

- A stable page key and unchanged detent set preserve the current extent.
- If a same-key update removes the current detent, move to the nearest remaining
  detent; ties choose the larger detent to avoid hiding focused content.
- A new page key starts at the configured initial detent.
- Changing only barrier, focus, duration, or `can_pop` does not reset extent or
  the primary scroll position.
- Process restoration restores route identity and child state as it does now,
  then starts at the configured initial detent. Extent restoration is deferred.

## Protocol design

Retire page property ID 9 (`modal_is_scroll_controlled`) and do not reuse its
numeric ID. Old payloads are not decoded through a compatibility path.

Add typed schema enums:

```text
modal_sheet_sizing:
  content_bounded = 1
  scroll_controlled = 2
  detented = 3

modal_sheet_detents:
  medium = 1
  large = 2
  medium_and_large = 3

modal_sheet_detent:
  medium = 1
  large = 2
```

Add page properties with new IDs above the current maximum:

```text
modal_sizing
modal_detents
modal_initial_detent
modal_dismiss_on_drag
modal_handle_semantics_label
modal_medium_semantics_value
modal_large_semantics_value
```

Add `primary` as the next property ID for `scroll_view` and `list_view`.

Codec validation must reject:

- Unknown enum values.
- An initial detent that is not configured.
- Empty detent sets or duplicate public detents at the OCaml API boundary.
- Missing or empty handle semantics strings in detented mode.
- Noncanonical detent fields in non-detented sizing modes.
- A primary horizontal scrollable inside a detented host.

Increment the protocol minor version and regenerate owned protocol outputs and
fixtures. Do not hand-edit generated artifacts.

## Failure behavior

Configuration failures should be explicit:

- Invalid OCaml detent construction raises `Invalid_argument` before a frame
  is emitted, following existing constructor validation conventions.
- Invalid wire values produce the existing typed `invalid_props` protocol
  error.
- A detented page without exactly one primary vertical scrollable renders a
  `RendererBuildException` boundary instead of silently disabling drag.
- A detached borrowed controller causes `scroll_to` to return a host-effect
  error rather than creating a second controller.

There is no fallback to fixed-height behavior, no implicit search for the first
scrollable, and no use of a controller from a different route.

## Test plan

### OCaml surface and protocol

- Construct each sizing mode through the public API.
- Validate medium-only, large-only, and medium-plus-large configurations.
- Reject invalid initial detents, duplicates, empty strings, and empty sets.
- Round-trip every field and reject every unknown enum value.
- Verify same-key incremental updates for detents, initial detent,
  `dismiss_on_drag`, and `can_pop`.
- Verify `primary` scroll props in OCaml/Dart cross-language fixtures.

### Flutter behavior

- Start at medium and drag upward to large.
- At large, prove that upward gestures scroll content rather than exceed the
  maximum extent.
- With content scrolled, prove that a downward gesture returns content to zero
  before collapsing the sheet.
- Collapse large to medium and dismiss medium past the internal zero extent.
- Prove distance and fling dismissals emit one `RoutePop` with the actual page
  key.
- With `canPop = false`, prove no dismissal target is exposed and no event is
  emitted.
- Change `canPop` on the same key, retain child/controller state, then dismiss.
- Change `canPop` from true to false during a drag and prove recovery to the
  smallest visible detent.
- Remove the page declaratively with `canPop = false` and prove it still exits.
- Exercise handle tap, pointer drag, mouse drag, semantics increase/decrease,
  and the announced current value.
- Reject missing and multiple primary scrollables.
- Verify `scroll_to` uses the borrowed controller.
- Verify focus, barrier isolation, safe areas, keyboard insets, compact height,
  large text, RTL, dark theme, and reduced motion at both detents.
- Verify stable keys preserve extent and changed keys use the configured
  initial detent.

## Implementation sequence

1. Add failing OCaml API and codec tests for typed sizing and system detents.
2. Replace `is_scroll_controlled` with the typed sizing API and regenerate the
   protocol.
3. Add failing renderer tests for primary-controller borrowing and `scroll_to`.
4. Implement owned/borrowed scroll resources and explicit primary scroll props.
5. Add failing detent, scroll coordination, and live-`can_pop` gesture tests.
6. Implement the private detented host inside the existing modal route builder.
7. Add the accessible handle and its pointer/semantics tests.
8. Add geometry, reduced-motion, reconciliation, and restoration tests.
9. Update navigation, protocol, testing, changelog, and generic examples.

Every implementation slice must follow the repository TDD process. No OCaml
file under `spec/` and no Dune file should change unless separately authorized.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Gesture competition between resizing and content scroll | Require the content to use the exact `DraggableScrollableSheet` controller; test both directions at every boundary. |
| A veto arrives while dismissal is animating | Recompute minimum extent from live `can_pop`, guard zero-extent handling, and animate back before any route removal. |
| Borrowed controller is disposed by the renderer | Track owned versus borrowed bindings and make disposal ownership explicit. |
| Multiple scrollables attach to the detent controller | Require exactly one explicit primary vertical scrollable and fail loudly. |
| Keyboard changes available height during a drag | Size inside the route's existing keyboard-adjusted viewport and clamp controller updates. |
| Default Flutter handle dismisses instead of resizing | Keep the native route handle disabled and provide a route-owned detent-aware handle. |
| API exposes Flutter implementation details | Keep public values limited to portable sizing, detents, dismissal policy, and accessibility strings. |

## Sources

- [Apple Human Interface Guidelines: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Apple `UISheetPresentationController`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller)
- [Apple `UISheetPresentationController.Detent`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/detent)
- [Apple `prefersScrollingExpandsWhenScrolledToEdge`](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/prefersscrollingexpandswhenscrolledtoedge)
- [Apple `presentationControllerShouldDismiss`](https://developer.apple.com/documentation/uikit/uiadaptivepresentationcontrollerdelegate/presentationcontrollershoulddismiss%28_%3A%29)
- [Flutter `ModalBottomSheetRoute`](https://api.flutter.dev/flutter/material/ModalBottomSheetRoute-class.html)
- [Flutter `DraggableScrollableSheet`](https://api.flutter.dev/flutter/widgets/DraggableScrollableSheet-class.html)
- [Flutter `DraggableScrollableController`](https://api.flutter.dev/flutter/widgets/DraggableScrollableController-class.html)
- [Flutter `PrimaryScrollController`](https://api.flutter.dev/flutter/widgets/PrimaryScrollController-class.html)
- [Pinned Flutter 3.44.8 Material bottom-sheet source](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/packages/flutter/lib/src/material/bottom_sheet.dart)
- [Pinned Flutter 3.44.8 draggable-sheet source](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/packages/flutter/lib/src/widgets/draggable_scrollable_sheet.dart)
