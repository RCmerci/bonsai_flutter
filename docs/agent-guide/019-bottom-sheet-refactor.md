# Bottom Sheet Refactor Implementation Plan

Goal: Refactor the Flutter modal bottom sheet implementation into focused navigation modules and add a route-coordinated receding background transition inspired by the referenced `flutterfx_widgets` example without weakening the existing declarative navigation contract.

Architecture: Keep the OCaml-owned `Navigator.pages` model and the existing `ModalBottomSheetRoute`, then use Flutter's public `ModalRoute.delegatedTransition` mechanism so the incoming sheet route animates the route immediately below it.
Move the modal route, background transition, and detented host out of the monolithic renderer while deleting the obsolete in-file implementations rather than retaining wrappers or aliases.

Tech Stack: Dart 3.12, Flutter 3.44.8, Material navigation, `ModalBottomSheetRoute`, `ModalRoute.delegatedTransition`, `DraggableScrollableSheet`, `PrimaryScrollController`, and Flutter widget tests.

Related: Builds on `/Users/rcmerci/gh-repos/bonsai_flutter/docs/agent-guide/016-modal-bottom-sheet-route-prompt.md` and `/Users/rcmerci/gh-repos/bonsai_flutter/docs/agent-guide/017-modal-bottom-sheet-detents.md`.

## Problem statement

The current bottom sheet implementation has the correct product-level semantics but is concentrated inside `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`.
That file is 2,075 lines long and currently contains navigator page mapping, modal route configuration, keyboard ownership, reduced-motion synchronization, detent reconciliation, drag dismissal, handle gestures, keyboard actions, and accessibility semantics.

The referenced `flutterfx_widgets` example demonstrates one useful visual idea.
One animation source drives the sheet entrance, barrier fade, and a receding transformation of the main content.
The main content scales down, moves vertically, and gains rounded corners while the drawer enters.

The reference is not a suitable architecture to copy into Bonsai Flutter.
It composes `mainContent`, a hand-built barrier, and `drawerContent` in one `Stack`, exposes an imperative controller, and treats animation completion as drawer presence.
It does not provide a Navigator route, declarative page identity, restoration, live `can_pop`, modal focus isolation, lower-route semantics isolation, keyboard-inset ownership, detents, coordinated scrolling, or typed route-pop events.

The refactor must therefore adopt the coordinated-transition concept while preserving the current route model.
It must not replace the modal route with a `Stack`, duplicate the lower page, expose a Dart-side presence controller, or create a second source of truth.

## Testing Plan

I will retain the existing 43 modal bottom sheet widget tests as characterization coverage for route identity, modality, dynamic dismissal policy, keyboard ownership, safe areas, reduced motion, detents, scrolling, restoration, pointer input, keyboard input, and accessibility actions.

I will add an integration test that starts with only a lower page, pushes a modal bottom sheet through the declarative page list, and verifies that the same mounted lower-page surface recedes while the sheet enters.

I will add an integration test that samples an in-progress entrance and verifies that the lower route and sheet both advance during the same route transition rather than using independent controllers.

I will add an integration test that dismisses the modal and verifies that the lower-page geometry returns exactly to its original settled bounds and that one typed `RoutePop` event is emitted.

I will add an integration test that enables reduced motion and verifies that no intermediate animated geometry is observable while the final modal composition, barrier, focus, and semantics remain correct.

I will add an integration test that pushes an ordinary standard page and verifies that the bottom-sheet-specific background transformation is not applied.

I will add an integration test for two stacked modal sheets and verify that only the route immediately below the new sheet receives the delegated transition while the root page remains mounted once.

I will add compact-height, RTL, light-theme, and dark-theme assertions to the new visual-transition fixture so the receding route remains inside the viewport and does not become direction-dependent.

I will run the focused modal test group before and after each refactor step, then run package analysis and the complete Flutter package test suite.

NOTE: I will write *all* tests before I add any implementation behavior.

## Research scope

The external source was reviewed at an immutable revision so later upstream edits cannot silently change this plan.

| Source | Revision or version | Relevance |
| --- | --- | --- |
| [`flutterfx_widgets/lib/bottom-sheet`](https://github.com/flutterfx/flutterfx_widgets/tree/9089ad77e2b0a76a51a79e17355802c510dde208/lib/bottom-sheet) | `9089ad77e2b0a76a51a79e17355802c510dde208` | User-provided visual and interaction reference. |
| [`bottom_sheet.dart`](https://github.com/flutterfx/flutterfx_widgets/blob/9089ad77e2b0a76a51a79e17355802c510dde208/lib/bottom-sheet/bottom_sheet.dart) | Same revision | Controller, coordinated animations, layout, barrier, and drag behavior. |
| [`bottom_sheet_demo.dart`](https://github.com/flutterfx/flutterfx_widgets/blob/9089ad77e2b0a76a51a79e17355802c510dde208/lib/bottom-sheet/bottom_sheet_demo.dart) | Same revision | Consumer ownership and content composition. |
| [`ModalRoute.delegatedTransition`](https://api.flutter.dev/flutter/widgets/ModalRoute/delegatedTransition.html) | Flutter 3.44.8 | Public mechanism for an incoming route to animate the route below it. |
| [`widgets/routes.dart`](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/packages/flutter/lib/src/widgets/routes.dart) | Flutter `058e0af2c2` | Exact pinned implementation of delegated and received transitions. |
| [`cupertino/sheet.dart`](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/packages/flutter/lib/src/cupertino/sheet.dart) | Flutter `058e0af2c2` | Maintained example of a sheet route providing a scale, offset, clipping, and contrast transition to the previous route. |

The researched `flutterfx_widgets` revision has no repository license reported by GitHub and no root license file.
No source code, constants, comments, or names should be copied from that repository.
The implementation should independently use Flutter's documented public APIs and treat the reference only as a behavioral and visual input.

## Reference implementation findings

### Useful ideas

| Reference behavior | Design value for Bonsai Flutter |
| --- | --- |
| One animation controller drives drawer translation and lower-content depth effects. | The lower route and sheet should be synchronized from one route animation. |
| Drag distance is normalized against the actual constrained drawer height. | Gesture math should continue to use `DraggableScrollableController.pixelsToSize` and the keyboard-adjusted viewport instead of global screen dimensions. |
| The lower content gains scale, translation, and rounded corners as the drawer opens. | A delegated transition can provide the same depth cue without moving lower content into the modal route. |
| The barrier animation follows the same opening progress. | The native `ModalBottomSheetRoute` barrier already follows the route animation and should remain the sole barrier owner. |
| Sheet content is passed as an ordinary widget. | The existing Bonsai page child should remain an ordinary rendered widget subtree. |

### Behaviors that must not be adopted

| Reference behavior | Reason for rejection |
| --- | --- |
| Imperative `open`, `close`, and `toggle` methods determine visibility. | OCaml owns page presence and native dismissal must emit one typed event. |
| `Stack` composes the lower page, barrier, and sheet. | This loses route focus, restoration, Back handling, and modal semantics isolation. |
| The controller is attached once and disposed by the child widget. | External controller ownership and widget lifecycle ownership are mixed. |
| Any downward velocity closes and any upward velocity opens. | The current detent state machine has tested snap targets, dismissal preflight, and veto recovery. |
| Barrier taps directly reverse an animation. | Barrier dismissal must consult the latest same-key `Page.canPop` value before route removal. |
| Fixed visual colors and a fixed `0.85` scale are embedded in the widget. | Framework behavior must remain theme-compatible and usable on compact layouts. |
| `minHeight` is exposed but not used by layout or drag handling. | Public configuration must have a complete, tested contract or be omitted. |
| The demo's independent `ListView` scrolls inside a sheet-wide drag detector. | Detented Bonsai sheets require explicit resize-then-scroll coordination through the primary controller. |

## Current Bonsai Flutter baseline

The current route stack is declarative and must remain so.

```text
OCaml Navigator.pages
        |
        v
binary PageProps with a typed PagePresentation
        |
        v
WidgetRegistry validates Page children and detented primary scrolling
        |
        v
Flutter Navigator.pages
        |
        +-- standard PageRoute or CupertinoPageRoute
        |
        `-- ModalBottomSheetRoute
              |
              +-- native barrier, focus, semantics, safe area, and route motion
              |
              `-- optional DetentedModalSheetHost
                    |
                    `-- DraggableScrollableSheet + PrimaryScrollController
```

The focused command below passed all 43 modal tests during this research on 2026-08-11.

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter
flutter test test/navigation_host_test.dart --plain-name 'Modal bottom sheet navigation'
```

The existing behavior includes the following contracts.

| Contract | Current owner |
| --- | --- |
| Page presence, page key, restoration ID, and `can_pop`. | OCaml page list and Flutter `Page`. |
| Native barrier, focus route, modal semantics, and Back or Escape integration. | `_BonsaiModalBottomSheetRoute`. |
| One keyboard bottom inset and child inset removal. | `_BonsaiModalBottomSheetRoute.builder`. |
| Reduced entrance and exit duration updates. | `_BonsaiModalBottomSheetRoute`. |
| Medium and large extents, snap reconciliation, and drag dismissal. | `_DetentedModalSheetHostState`. |
| Touch, stylus, mouse, keyboard, tap, and accessibility handle actions. | `_DetentedModalSheetHostState`. |
| Exactly one primary vertical scrollable for detented content. | `_buildNavigator` in `widget_registry.dart`. |
| Exactly one typed event after an allowed native removal. | `_BonsaiNavigatorState.onDidRemovePage`. |

## Current design debt

| Debt | Consequence |
| --- | --- |
| Bottom sheet code occupies roughly one third of `widget_registry.dart`. | Navigation changes require editing a renderer file that also owns unrelated widget construction. |
| Route configuration and detent interaction live in one private block. | The modal route lifecycle and the resize or gesture lifecycle are difficult to review independently. |
| Visual transition policy is limited to the incoming sheet and native barrier. | The lower route does not receive the depth effect demonstrated by the reference. |
| Private classes cannot be imported from focused tests or focused modules. | Every bottom sheet behavior currently shares the 2,054-line `navigation_host_test.dart` harness. |
| Same-key live route getters are interleaved with constructor-time `super` values. | The distinction is correct but easy to regress when adding route behavior. |

## Design decisions

### Preserve the public contract

This refactor will not change `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ui/navigation.mli`, any other OCaml file, `/Users/rcmerci/gh-repos/bonsai_flutter/protocol/schema.sexp`, generated protocol files, or any dune file.

The existing `Content_bounded`, `Scroll_controlled`, and `Detented` sizing cases remain the complete public API.
No visual-controller handle, Flutter callback, animation object, scale value, offset value, or corner radius will cross the OCaml-to-Flutter protocol.

The background treatment is route presentation behavior, like the native barrier and entrance motion.
It should therefore be an internal default for every `Modal_bottom_sheet` presentation in this tranche.
If a future consumer demonstrates a real need for multiple presentation styles, that should be designed as a typed replacement rather than adding fallback flags to this implementation.

### Keep the real modal route

`_BonsaiModalBottomSheetRoute` remains a `ModalBottomSheetRoute<void>`.
Flutter continues to own the non-opaque overlay entries, barrier, route focus scope, semantics isolation, restoration attachment, and sheet entrance or exit transition.

The route's built-in `enableDrag` and `showDragHandle` remain disabled.
The existing detented host continues to preflight dismissal with live `canPop` and `Navigator.maybePop`.

### Use a delegated lower-route transition

The custom modal route will override `delegatedTransition` and return one internal builder.
Flutter assigns that builder to the route immediately below the sheet as its `receivedTransition`.
The lower route remains in its original Navigator overlay entry and remains mounted exactly once.

```text
incoming modal route animation
        |
        +-- native sheet slide
        |
        +-- native modal barrier fade
        |
        `-- delegated transition on the route below
              |
              +-- scale from 1.00 to 0.92
              +-- vertical fractional offset from 0.00 to -0.03
              `-- top corner radius from 0 to 16 logical pixels
```

The `0.92` settled scale is intentionally less aggressive than the reference's `0.85` value and is close to Flutter's maintained Cupertino sheet depth treatment.
The vertical offset is fractional rather than a fixed phone-sized pixel constant so compact and large viewports remain proportional.
The radius is a private renderer constant and must not become protocol surface area.

The delegated transition must use the provided `secondaryAnimation` and must not allocate a second `AnimationController`.
The implementation must use `transformHitTests: false` for the lower visual transform because the modal barrier owns interaction blocking.
The implementation must not paint another dimming overlay because `barrier_color` already defines the sole scrim.

The settled depth treatment remains visible when reduced motion is enabled, but the route duration resolves to zero so no intermediate movement is presented.
This matches the existing distinction between disabling animation and changing the final modal composition.

### Separate renderer responsibilities

The implementation should create the following internal Dart modules.

| File | Responsibility |
| --- | --- |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/navigation_host.dart` | Map typed page entries to Flutter `Page` objects, own the nested `Navigator`, and emit typed route-pop events. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_bottom_sheet_route.dart` | Own the modal `Page`, live route getters, keyboard inset policy, reduced-motion duration synchronization, and detented host composition. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_background_transition.dart` | Own only the route-below scale, offset, clipping, curve, and private visual constants. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/detented_modal_sheet_host.dart` | Own detent extents, controller lifecycle, reconciliation, dismissal scheduling, gestures, keyboard input, and semantics. |

These files are under `lib/src` and are not exported from `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart`.
Their non-private class names are package implementation details, not consumer API.

`/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart` will retain UiNode validation and the check for exactly one primary vertical scrollable.
It will construct a typed internal navigation entry list and delegate Navigator widget creation to `navigation_host.dart`.

The old `_BonsaiPage`, `_BonsaiNavigator`, `_BonsaiNavigatorState`, `_BonsaiModalBottomSheetPage`, `_BonsaiModalBottomSheetRoute`, `_DetentedModalSheetHost`, and `_DetentedModalSheetHostState` definitions must be removed from `widget_registry.dart` in the same change that introduces their replacements.
No forwarding classes, deprecated aliases, duplicate implementations, or compatibility imports should remain.

## Runtime flow after refactor

```text
WidgetRegistry
  validates Navigator and Page UiNodes
        |
        v
NavigationHost
  maps PageProps to Flutter Page objects
        |
        v
BonsaiModalBottomSheetPage.createRoute
        |
        v
BonsaiModalBottomSheetRoute
  owns modality and supplies delegatedTransition
        |
        +------------------------------+
        |                              |
        v                              v
native BottomSheet transition     route below receives transition
        |                              |
        v                              v
DetentedModalSheetHost            scale + offset + rounded clip
        |
        v
primary scroll controller and content
```

Same-key page updates continue to replace `Route.settings` with the latest page object.
Every dynamic getter must read the current page from `settings` rather than retaining the constructor page.
This rule applies to barrier policy, barrier color, barrier label, sizing, safe-area policy, focus policy, durations, detent policy, and `canPop`.

## Edge cases and invariants

| Case | Required result |
| --- | --- |
| The modal is the first page. | Existing renderer validation rejects the frame. |
| The lower route is `None`, `Fade`, or `Slide`. | The incoming modal's delegated transition wraps the lower route without replacing its primary transition implementation. |
| A second modal is pushed over a first modal. | Only the immediately lower modal receives the new delegated transition and both page identities remain stable. |
| A standard page is pushed. | No bottom-sheet background transition is installed. |
| A same-key modal policy update occurs while open. | Route identity, selected detent, child state, lower-route transform, and primary scroll offset remain unchanged. |
| `canPop` changes during a drag. | Existing veto recovery returns to the smallest visible detent and no event is emitted. |
| The keyboard changes the available height. | Detent extents and the fractional background offset use the keyboard-adjusted layout without double-consuming the inset. |
| Reduced motion is enabled before presentation. | The route reaches its final composition without observable intermediate frames. |
| Reduced motion changes while the modal is mounted. | The existing route controller duration synchronization remains correct and does not remount either route. |
| Compact height is used. | The proportional offset remains bounded and the transformed route stays visible. |
| RTL is used. | The vertical transform and centered scale remain direction-independent. |
| A transparent nondismissible barrier is used. | The transformed lower route remains non-interactive and does not receive leaked taps. |
| The barrier has a custom color. | No second overlay changes the configured color or alpha. |
| The modal exits declaratively while `canPop` is false. | Removal still succeeds because OCaml already made the decision and no native pop event is emitted. |
| The route is restored after process restart. | The configured initial detent and existing restoration contract remain unchanged. |
| The lower page contains active state or an editable. | The same elements and controllers remain mounted through entrance and exit. |

## Implementation sequence

Use `@Test-Driven Development (TDD)` for every behavior-changing task.
Write all tests for the delegated transition before adding production transition behavior, run them to confirm the expected failures, add the minimum behavior, rerun them, and only then perform structural extraction.

### Task 1: Record the clean baseline

1. Read `/Users/rcmerci/gh-repos/bonsai_flutter/AGENTS.md` and confirm the worktree does not contain unrelated overlapping edits.
2. Run `git status --short` from `/Users/rcmerci/gh-repos/bonsai_flutter` and preserve any user-owned changes.
3. Run the focused 43-test modal group from `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter`.
4. Confirm the command ends with `All tests passed` before editing.
5. Do not modify an OCaml file, `protocol/schema.sexp`, a generated protocol file, or a dune file.

### Task 2: Add all failing delegated-transition tests

1. Extend the modal fixture in `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/navigation_host_test.dart` so it can render the lower page first and add a modal later through a new frame.
2. Give the lower test surface a stable test key so its geometry and element identity can be measured without inspecting production widget classes.
3. Add a test named `modal entrance recedes the same mounted lower page`.
4. Assert that the lower element identity is unchanged, its settled width is approximately 92 percent of the original width, its top moves upward proportionally, and the modal remains a real `ModalBottomSheetRoute<void>`.
5. Add a test named `modal and lower route share entrance progress`.
6. Pump part of the configured route duration and assert that both the sheet entrance and lower-page geometry are strictly between their start and settled states.
7. Add a test named `modal exit restores lower geometry and emits one pop`.
8. Add a test named `reduced motion skips intermediate lower-route movement`.
9. Add a test named `standard page does not recede the lower route`.
10. Add a test named `stacked modals transform only the immediate lower route`.
11. Add compact-height, RTL, light-theme, and dark-theme variants to the settled geometry test.
12. Run the focused modal group and confirm every new test fails because the lower route currently has no delegated sheet transition.
13. Fix fixture mistakes until failures are behavioral assertion failures rather than compile errors or unrelated exceptions.
14. Do not add production code during this RED phase.

### Task 3: Implement the minimal background transition

1. Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_background_transition.dart`.
2. Add one internal delegated-transition builder driven only by the supplied `secondaryAnimation`.
3. Interpolate scale from `1.00` to `0.92` with top-center alignment.
4. Interpolate a vertical fractional offset from `0.00` to `-0.03`.
5. Interpolate only the top corner radius from `0` to `16` logical pixels.
6. Use the reference's general ease-in-out intent but select a Flutter framework curve explicitly and test the observable progress rather than the curve class name.
7. Return the original child unchanged when there is no child or the secondary animation is dismissed.
8. Do not add a scrim, controller, gesture detector, route state, or public options to this file.
9. Temporarily wire the builder directly from the existing `_BonsaiModalBottomSheetRoute.delegatedTransition` getter in `widget_registry.dart`.
10. Run the focused modal group and confirm all new and existing tests pass.
11. If a test fails, change the production behavior rather than weakening the asserted route contract.

### Task 4: Extract the modal route

1. Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_bottom_sheet_route.dart`.
2. Move the modal `Page` and `ModalBottomSheetRoute` behavior from `widget_registry.dart` without changing its behavior.
3. Rename the moved implementation classes to non-underscored internal names because Dart privacy is file-scoped.
4. Keep the new files under `lib/src` and do not export them from the package barrel.
5. Keep constructor-time `super` values for route creation and retain live getters that read the latest page from `settings` after same-key reconciliation.
6. Keep keyboard inset application outside the page child and continue removing the bottom view inset from the child's `MediaQuery`.
7. Keep animation-controller duration synchronization in `changedInternalState` and `changedExternalState`.
8. Keep native drag and the native drag handle disabled.
9. Import and expose the background delegated-transition builder from this route.
10. Delete the old modal page and route classes from `widget_registry.dart` immediately after the imports compile.
11. Run the focused modal group and confirm all tests remain green.

### Task 5: Extract the detented host

1. Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/detented_modal_sheet_host.dart`.
2. Move the detented widget, state, extent constants, controller lifecycle, snap reconciliation, handle UI, pointer gestures, keyboard handling, semantics, and dismissal scheduling into this file.
3. Preserve `DraggableScrollableController.pixelsToSize` as the only pixel-to-extent conversion.
4. Preserve the larger-detent tie break in nearest-extent reconciliation.
5. Preserve exactly-once dismissal scheduling and post-frame checks.
6. Preserve the latest `canDismiss` callback instead of capturing an initial boolean.
7. Preserve the one-millisecond reduced-motion snap duration required by Flutter's nonzero duration assertion.
8. Delete the old detented host classes from `widget_registry.dart` in the same edit.
9. Run the focused modal group and confirm all tests remain green.

### Task 6: Extract the navigation host

1. Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/navigation_host.dart`.
2. Define one internal typed entry that carries `PageProps` and its rendered child.
3. Move standard page creation, slide page creation, modal page creation, the nested Navigator, the navigator key, `NavigatorPopHandler`, and `onDidRemovePage` event emission into this file.
4. Keep UiNode graph traversal and the exactly-one-primary-scrollable validation in `widget_registry.dart`.
5. Make `_buildNavigator` construct the internal entry list and return the new navigation host.
6. Delete the obsolete in-file standard page and navigator classes rather than retaining wrappers.
7. Run the focused modal group.
8. Run the complete `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/navigation_host_test.dart` file to cover standard pages and Cupertino slide behavior.

### Task 7: Refactor while green

1. Review the extracted files for duplicated route getters, duplicated extent calculations, and names that still imply file privacy.
2. Extract only repeated pure helpers that are already exercised through widget behavior.
3. Do not introduce an imperative controller façade, a transition configuration object, or a new public abstraction without a failing behavior test.
4. Run the focused modal group after each cleanup.
5. Confirm `widget_registry.dart` contains only renderer registration, UiNode validation, and calls into focused navigation modules for this feature.

### Task 8: Update user-facing documentation

1. Update `/Users/rcmerci/gh-repos/bonsai_flutter/docs/navigation.md` to explain that a modal page delegates its route animation to the route below for a receding depth treatment.
2. State that the lower page remains mounted in its own route and that the native barrier remains the sole interaction and scrim owner.
3. State that reduced motion removes interpolation while preserving the final modal composition.
4. Update the existing bottom sheet entry in `/Users/rcmerci/gh-repos/bonsai_flutter/CHANGES.md` with the route-coordinated background transition and internal renderer separation.
5. Do not change protocol documentation because the wire contract does not change.

### Task 9: Verify the complete change

1. Format only the touched Dart files with `dart format` from `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter`.
2. Run `dart format --output=none --set-exit-if-changed lib test` from the same directory and expect exit code zero.
3. Run `flutter analyze` from the same directory and expect `No issues found`.
4. Run `flutter test test/navigation_host_test.dart --plain-name 'Modal bottom sheet navigation'` and expect all modal tests to pass.
5. Run `flutter test test/navigation_host_test.dart` and expect all navigation tests to pass.
6. Run `make flutter-test` from `/Users/rcmerci/gh-repos/bonsai_flutter` and expect the complete Flutter package suite to pass.
7. Run `git diff --check` from `/Users/rcmerci/gh-repos/bonsai_flutter` and expect no output.
8. Inspect `git diff --stat` and confirm no OCaml, protocol schema, generated protocol, or dune file changed.

## Acceptance criteria

1. Modal presentation still uses a real non-opaque `ModalBottomSheetRoute<void>`.
2. The lower page remains mounted exactly once and stays in its own route.
3. Modal entrance, native barrier fade, and lower-route depth treatment share the route animation timeline.
4. The lower route settles at the documented scale, proportional offset, and rounded top corners.
5. Modal exit restores the lower route to its exact original geometry.
6. Reduced motion produces no intermediate animation frames.
7. Standard page navigation does not receive the modal background treatment.
8. Stacked sheets transform only their immediate predecessor.
9. Live `can_pop`, drag veto recovery, restoration, keyboard ownership, focus, semantics, detents, and route-pop event behavior remain green.
10. Bottom sheet and navigator implementation classes no longer live in `widget_registry.dart`.
11. No imperative visibility controller or Dart-side page-presence state is introduced.
12. No OCaml, protocol, generated protocol, or dune file changes are present.
13. No external unlicensed source code is copied.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| `receivedTransition` suppresses a lower route's normal secondary transition. | Test `None`, `Fade`, `Slide`, and stacked modal predecessors through actual Navigator pushes. |
| A custom visual wrapper changes hit testing. | Use `transformHitTests: false` and retain barrier pointer-blocking tests. |
| A second dim layer changes custom barrier colors. | Do not paint any lower-route overlay and test a custom translucent barrier. |
| Same-key updates restart the background animation. | Test a policy update while fully open and assert stable lower geometry and route identity. |
| Extracted classes accidentally capture constructor-time page values. | Preserve live getters from `settings` and retain existing dynamic-update tests. |
| Compact layouts expose hard-coded phone assumptions. | Use a fractional vertical offset and run compact-height geometry variants. |
| Snapshotting obscures live lower-page state during transitions. | Keep state-identity assertions and add an editable or ticking lower child to the in-progress test if snapshot behavior becomes observable. |
| The upstream reference's absent license creates provenance risk. | Reimplement from Flutter public APIs and document the immutable source only as research input. |

## Testing Details

The new tests observe route type, mounted element identity, geometry over time, event count, and interaction behavior through a real nested Navigator.
They do not assert private class names, internal controller fields, or data structure shapes.

The existing 43 modal tests remain the regression boundary for modality, focus, accessibility, keyboard geometry, detents, scroll coordination, pointer devices, restoration, reconciliation, and exact dismissal events.
The new tests add the missing visual coordination boundary and distinguish a modal route push from an ordinary page push.

## Implementation Details

- Keep OCaml as the only owner of page presence.
- Keep `ModalBottomSheetRoute` as the modality primitive.
- Use `ModalRoute.delegatedTransition` instead of wrapping lower content inside the sheet.
- Drive all coordinated visuals from the existing route animation.
- Keep the native modal barrier as the only scrim and pointer blocker.
- Keep native bottom-sheet drag disabled and preserve the custom detent preflight.
- Keep visual constants private to the Flutter renderer.
- Delete moved implementations from `widget_registry.dart` without compatibility layers.
- Keep internal modules under `lib/src` and out of the public package barrel.
- Verify behavior through Navigator-level widget tests before and after extraction.

## Question

There is no blocking design question for implementation.
This plan assumes the receding background treatment is the new default for every modal bottom sheet on every Flutter platform and intentionally does not expose a public opt-out or tuning surface.
If product review rejects that cross-platform default, the design should stop before implementation and replace the assumption with one typed presentation-style decision rather than adding ad hoc booleans.

---
