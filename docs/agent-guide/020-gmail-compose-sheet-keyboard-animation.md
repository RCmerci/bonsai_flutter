# Gmail-Style Compose Sheet Keyboard Animation Implementation Plan

Goal: Make an autofocus modal bottom sheet enter smoothly on iOS by staging automatic keyboard activation after the sheet entrance, following the observable Gmail compose choreography without claiming knowledge of Gmail's private implementation.

Architecture: Keep Flutter's `ModalBottomSheetRoute` and iOS engine as the single route-animation and keyboard-inset authorities, add a Flutter-only automatic-focus activation boundary tied to route progress, and localize keyboard-inset rebuilds around the sheet layout.

Tech Stack: Dart 3.12.2, Flutter 3.44.8, Material `ModalBottomSheetRoute`, Flutter focus and text-input APIs, `MediaQuery.viewInsets`, the Flutter iOS engine viewport-metrics pipeline, Flutter widget tests, Flutter integration tests, and a physical iPhone profile lane.

Related: Builds on `/Users/rcmerci/gh-repos/bonsai_flutter/docs/agent-guide/019-bottom-sheet-refactor.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/docs/navigation.md`, and `/Users/rcmerci/gh-repos/bonsai_flutter/docs/ios-device-testing.md`.

## Problem statement

The current modal route starts three visually significant operations in the same interval.
It starts the sheet entrance and lower-route depth transition, immediately lets the route and an autofocus text input acquire focus, and responds to every iOS keyboard frame by changing the bottom inset and available detent viewport.


These operations have separate animation sources and separate geometry effects.
The route controller moves the sheet and the route below it, while the iOS system keyboard moves on its native timeline and the Flutter engine continuously publishes the corresponding `viewInsets.bottom` values.


The result can be visually uneven even when each source is individually smooth.
During the overlap, the route translation, the keyboard inset, the sheet height, and the detent constraints all change at once, so the sheet can appear to hesitate, accelerate, or change height while entering.


This is primarily a choreography and layout-ownership problem, not evidence that Flutter lacks the native iOS keyboard curve.
The pinned Flutter 3.44.8 engine already follows the native keyboard animation on VSync and emits interpolated viewport metrics.


The target is therefore to prevent automatic keyboard presentation from competing with the route entrance, preserve immediate response to an explicit user tap, and reduce the amount of widget work caused by each inset update.

## Testing Plan

I will first add behavior tests that sample the route before, during, and after its entrance instead of relying only on settled `pumpAndSettle` assertions.


I will verify that a bottom sheet with `requestFocus: true` and an autofocus text input does not focus the input during a nonzero route entrance, focuses it when the entrance completes, and still exposes the route's modal focus and semantics boundary during the delay.


I will verify that tapping the text input during the entrance bypasses the automatic delay and opens the keyboard immediately because explicit user intent takes precedence over presentation choreography.


I will verify that dismissing or declaratively removing the sheet before entrance completion cancels pending automatic activation and never flashes the keyboard after the route is gone.


I will verify that `requestFocus: false` never triggers delayed autofocus, while changing the same-key route to `requestFocus: true` after it is settled activates autofocus without replacing route or child state.


I will verify that reduced motion activates automatic focus without an artificial 250 millisecond wait because the effective route duration is zero.


I will verify that a keyboard already visible at presentation does not pass through a temporary zero-inset layout and does not visibly hide and reappear merely to honor the staged default.


I will sample changing test insets during content-bounded, scroll-controlled, medium-detent, and large-detent presentations and assert monotonic sheet geometry, one inset owner, stable child identity, and no content-side inset duplication.


I will add a physical-iPhone Profile test that records the bottom-sheet entrance and automatic keyboard presentation as a separate interaction group, compares build and raster frame timings before and after the change, and saves a high-frame-rate screen recording for visual review.


I will use the repository's existing 16 millisecond p90 build and raster thresholds as a compatibility gate, while treating screen-recorded geometry and before-or-after deltas as the primary evidence for perceived smoothness.


NOTE: I will write *all* tests before I add any implementation behavior.

## Executive recommendation

Adopt a two-phase default for automatic focus.
Let the modal route complete its entrance first, then activate the autofocus text input on the next frame so the system keyboard begins from a stable sheet surface.


Do not delay an explicit tap or explicit host focus request.
Those actions represent current user or application intent and should be allowed to open the keyboard during the entrance.


Do not add `AnimatedPadding`, a fixed keyboard duration, or a second keyboard curve.
Those mechanisms would animate an inset that the Flutter iOS engine already interpolates from the native keyboard animation and could introduce lag or double easing.


Do not add an iOS platform channel in the first implementation.
Only reconsider native timing metadata if physical-device traces prove that the pinned engine's published inset does not follow the visible keyboard on the supported iOS versions.


Keep every change on the Flutter side.
The OCaml presentation API, binary protocol, schema, generated files, native assets, and dune files do not need to change.

## Research boundary

Gmail for iOS is proprietary, and Google does not publish the source or presentation architecture for its compose screen.
No public evidence establishes whether the current app uses `UISheetPresentationController`, a custom `UIPresentationController`, SwiftUI, an internal cross-platform framework, or another implementation.


The research can establish observable choreography and platform capabilities, but it must not present an inferred Gmail implementation as fact.


The official Google help animation is a stylized product demonstration rather than an instrumented recording of a named Gmail build.
It is useful for identifying phase ordering, but its duration and easing must not be copied as production constants.


The current App Store build should be captured on the same physical iPhone used for the Bonsai comparison before implementation begins.
That capture must record the Gmail version, iOS version, device refresh rate, Reduce Motion setting, and whether a hardware keyboard is attached.

## Sources reviewed

| Source | Version or status | Finding |
| --- | --- | --- |
| [Apple App Store: Gmail - Email by Google](https://apps.apple.com/us/app/gmail-email-by-google/id422689480) | Version `6.0.260727`, listed on 2026-08-11 | Establishes the current public iOS build to use for the same-device comparison, but does not document compose animation internals. |
| [Google Gmail Help: Send or unsend Gmail messages on iPhone and iPad](https://support.google.com/mail/answer/2819488?co=GENIE.Platform%3DiOS&hl=en) | Public Google help content reviewed on 2026-08-11 | Provides Google's official iOS compose-and-send animation and confirms the Compose entry point. |
| [Google Gmail Help: Format your messages on iPhone and iPad](https://support.google.com/mail/answer/8260?co=GENIE.Platform%3DiOS&hl=en) | Public Google help content reviewed on 2026-08-11 | Confirms that Compose is initiated from the bottom-right action on iPhone and iPad. |
| [Apple: Adjusting your layout with keyboard layout guide](https://developer.apple.com/documentation/uikit/adjusting-your-layout-with-keyboard-layout-guide) | Current Apple documentation reviewed on 2026-08-11 | Shows that native layouts should track keyboard movement and distinguishes docked, split, undocked, floating, and hardware-keyboard cases. |
| [Apple: `keyboardWillChangeFrameNotification`](https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillchangeframenotification) | Current Apple documentation reviewed on 2026-08-11 | Establishes the native frame-change event and its frame, duration, and animation-curve metadata. |
| [Flutter: `ModalBottomSheetRoute`](https://api.flutter.dev/flutter/material/ModalBottomSheetRoute-class.html) | Flutter 3.44 API reviewed on 2026-08-11 | Confirms that the route owns entrance and exit animation configuration and exposes `requestFocus`. |
| [Flutter: `MediaQueryData.viewInsets`](https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html) | Flutter 3.44 API reviewed on 2026-08-11 | Defines the keyboard-obscured bottom region consumed by the current route. |
| [`widgets/routes.dart`](https://github.com/flutter/flutter/blob/058e0af2c2b57e369d905a03ac9748b0ebf543c6/packages/flutter/lib/src/widgets/routes.dart) | Pinned Flutter framework revision `058e0af2c2` | Shows that a current route with `requestFocus` acquires its route focus scope without waiting for the forward transition to complete. |
| [`FlutterViewController.mm`](https://github.com/flutter/flutter/blob/0cd610717b/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm) | Pinned Flutter engine revision `0cd610717b` | Shows native keyboard notifications, VSync tracking, presentation-layer or spring interpolation, and continuous viewport-inset updates. |

## Observable Gmail choreography

The official Google iOS animation was downloaded from the Gmail Help page and inspected at its native 15 frames per second.
The compose portion visibly separates into two phases.


First, the inbox transitions to a complete compose surface while no keyboard is visible.
Second, the compose surface remains visually stable while the keyboard rises and the editable content adopts the reduced viewport.


The useful reference is the phase boundary, not the exact transition style.
The official asset depicts a full-screen compose presentation and does not prove that Gmail's current production app uses a modal bottom-sheet primitive.


The animation also does not reveal whether Gmail requests first-responder status after a completion callback, gates automatic focus until a presentation controller settles, or uses another coordination mechanism.
The defensible inference is only that separating surface entrance from keyboard entrance avoids two large vertical motions fighting for attention.

## Apple and Flutter platform findings

Apple exposes native keyboard frame, duration, and curve information and recommends layouts that dynamically follow the keyboard rather than assuming one fixed keyboard height.
`UIKeyboardLayoutGuide` is the preferred native UIKit layout primitive when the content itself is hosted in a UIKit view hierarchy.


The Bonsai sheet is a Flutter widget inside `FlutterViewController`, so constraining it directly to `UIKeyboardLayoutGuide` would require replacing or bridging the Flutter layout owner.
That would be disproportionate and would duplicate functionality already present in the Flutter engine.


The pinned Flutter iOS engine observes keyboard show, hide, and frame-change notifications.
It calculates the docked keyboard intersection, starts a native-duration animation, tracks the native presentation layer or a captured spring curve on VSync, and publishes the interpolated result as the viewport bottom inset.


Consequently, `MediaQuery.viewInsets.bottom` is already the correct geometry source for the supported Flutter version.
The application should follow that value directly and must not apply another duration or curve over it.


Flutter's route focus behavior is independent of route transition completion.
When the modal becomes current, its focus scope can be selected immediately, and a descendant `TextField` with `autofocus: true` can request the software keyboard while the route is still moving forward.

## Current Bonsai behavior

The current implementation has one correct inset owner but no automatic-focus phase boundary.

| Concern | Current owner | Current behavior during entrance |
| --- | --- | --- |
| Sheet translation and barrier | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_bottom_sheet_route.dart` | Runs on the route controller for the configured 250 millisecond default. |
| Lower-route scale, offset, and clipping | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_background_transition.dart` | Runs from the incoming route's delegated animation. |
| Route focus | `ModalRoute` plus `BonsaiModalBottomSheetRoute.requestFocus` | Becomes eligible as soon as the route is current. |
| Text input autofocus | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/text_input/text_input_host.dart` | Passes the OCaml `autofocus` value directly to Flutter's `TextField`. |
| Keyboard geometry | Flutter iOS engine and `MediaQuery.viewInsets.bottom` | Changes continuously while the native keyboard moves. |
| Inset application | `BonsaiModalBottomSheetRoute.builder` | Rebuilds the route composition with bottom padding and removes the bottom inset from the child. |
| Detent geometry | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/detented_modal_sheet_host.dart` | Recalculates medium and large extents against the keyboard-adjusted constraints. |


The current route reads `MediaQuery.viewInsetsOf(context)` in its top-level builder.
Every keyboard metric change therefore invalidates the route-built composition, even though the page child and most presentation policy are unchanged.


For a detented sheet, the changing bottom padding also changes the constraints used by `DraggableScrollableSheet`.
The keyboard animation can therefore alter both the sheet's bottom position and its visible height while the route translation is still in progress.


The lower-route depth treatment remains tied only to route progress.
It does not know that the keyboard and sheet constraints are changing on another timeline, which can make the foreground sheet and background depth cue appear temporarily desynchronized.

## Root-cause hypothesis

The primary hypothesis is that immediate autofocus starts native keyboard presentation before the modal route reaches its settled position.
The user sees the composition of two large vertical animations plus detent relayout rather than one coherent motion.


The secondary hypothesis is that the broad `MediaQuery` dependency and constraint changes make more of the sheet subtree rebuild or relayout on every interpolated keyboard frame than necessary.
This may turn a choreography problem into measurable build-time or layout-time pressure on a physical device.


The hypothesis does not assume that the native keyboard inset jumps.
The pinned engine source indicates the opposite, so any implementation based on smoothing a supposedly discrete inset would need device evidence before adoption.


The implementation must collect a before trace before changing behavior.
If the trace shows that frames are within budget but the motion still looks uneven, the phase overlap is the main problem; if frames also miss budget, rebuild localization becomes part of the required fix rather than an optional cleanup.

## Target interaction contract

| Situation | Required behavior |
| --- | --- |
| Automatic autofocus with a nonzero entrance duration | The sheet completes its forward route transition before the text input activates and the keyboard begins to appear. |
| Explicit tap on a text input during entrance | The tap focuses immediately and may overlap the remaining entrance because user intent takes priority. |
| Explicit host `requestFocus` effect during entrance | The request executes immediately and is not silently converted into an automatic delayed request. |
| `requestFocus: false` | The route does not initiate delayed text-input autofocus. |
| Reduced motion or zero entrance duration | Automatic focus activates on the next safe frame with no artificial delay. |
| Sheet removed before completion | Pending automatic activation is discarded and cannot show a keyboard after disposal. |
| Same-key policy or child update | Route identity, text controller, selection, scroll state, and detent state remain stable. |
| Keyboard already visible | The route consumes the current inset immediately and avoids a hide-then-show cycle where iOS permits focus transfer. |
| Hardware keyboard | Focus still transfers correctly even when `viewInsets.bottom` remains zero. |
| Floating or undocked iPad keyboard | The route follows Flutter's reported inset semantics and does not invent a full-width keyboard height. |
| Interactive keyboard dismissal | The sheet follows engine-provided inset values without an additional implicit animation. |
| Stacked modal sheets | Only the top sheet owns its pending automatic activation, and a covered sheet cannot activate late. |

## Proposed Flutter architecture

### Automatic-focus activation scope

Add one internal Flutter activation scope that communicates whether automatic text-input autofocus is ready for the current subtree.
The scope is a presentation concern and is not serialized through the OCaml protocol.


The modal route publishes automatic-focus readiness as false for as long as `requestFocus` is false.
When `requestFocus` is true, the route initially publishes readiness as false only if the forward transition has nonzero remaining time, the keyboard is not already visible, and reduced motion is not active.
All other focus-requesting cases may publish readiness immediately.


The scope changes to ready from the route animation's completed status rather than from a wall-clock timer.
This keeps custom durations, reduced motion, interrupted transitions, and future route-curve changes aligned with actual route state.


`TextInputHost` derives its effective Flutter `autofocus` value from the protocol property and the nearest activation scope.
The protocol property remains the source of product intent, while the scope controls only when automatic intent is allowed to execute.


Changing effective autofocus from false to true after settlement uses Flutter's normal focus and keyboard path.
The implementation must not call private route focus APIs or synthesize a keyboard show command.


The gate must not disable the input's ability to receive a pointer focus request.
The text field remains enabled and focusable throughout the entrance, so an explicit tap is immediate.

### Local keyboard-inset host

Move the `MediaQuery.viewInsetsOf(context)` dependency out of the route's policy builder and into a small internal widget immediately around the already-built sheet surface.
That widget remains the single bottom-inset owner, applies the current bottom padding once, and removes the bottom inset from the child's `MediaQuery` exactly as the current route does.


The localized host must follow each engine-provided inset value directly.
It must not use `AnimatedPadding`, a hard-coded duration, curve matching, debounce, or frame skipping.


The sheet surface child should remain identity-stable across inset updates where Flutter's element rules allow it.
Only geometry that truly depends on the keyboard-adjusted constraints should relayout.


Detented sheets must continue to compute medium and large extents from the keyboard-adjusted viewport.
The refactor must not freeze detent height during keyboard presentation because that could place content behind the keyboard.

### Route lifecycle ownership

`BonsaiModalBottomSheetRoute` owns the activation lifecycle because it owns the entrance animation and knows whether it is current, reversing, completed, or disposed.
The route must cancel listeners and pending frame callbacks on pop, replacement, declarative removal, and disposal.


The current delegated lower-route transition remains unchanged.
Once automatic keyboard presentation begins after settlement, the lower route is already at its final depth state and no second synchronization mechanism is needed.

## Alternatives considered

| Alternative | Decision | Rationale |
| --- | --- | --- |
| Shorten the sheet duration until the overlap is less visible | Reject | This masks the race, changes presentation feel globally, and still permits competing geometry. |
| Start autofocus after a fixed 250 millisecond timer | Reject | Custom durations, reduced motion, interrupted routes, and same-key updates make a timer incorrect. |
| Start autofocus at an arbitrary route-progress threshold | Defer | Partial overlap may feel faster, but it reintroduces two simultaneous vertical motions and requires device-specific tuning. |
| Wrap the inset padding in `AnimatedPadding` | Reject | The engine already animates the inset, so a second implicit animation can lag and double-ease. |
| Bridge `UIKeyboardWillChangeFrameNotification` over a new platform channel | Reject for the first tranche | The pinned engine already consumes the same native event and tracks its animation on VSync. |
| Rebuild the sheet as a native `UISheetPresentationController` | Reject | This would split ownership across UIKit and Flutter and disrupt the existing declarative route, renderer, detent, and event contracts. |
| Disable autofocus in OCaml examples | Reject | The issue is framework presentation behavior and must not be pushed onto every consumer. |
| Stage only automatic focus and preserve explicit focus | Accept | This removes the default race without making the UI ignore direct intent. |

## Files in scope

| File | Planned responsibility |
| --- | --- |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_bottom_sheet_route.dart` | Own route-animation observation, automatic-focus readiness, cancellation, and composition of the localized inset host. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_keyboard_coordinator.dart` | Own the internal readiness scope and the narrow keyboard-inset host without exporting public API. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/text_input/text_input_host.dart` | Derive effective `TextField.autofocus` from protocol intent and route readiness while preserving direct tap focus. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/navigation_host_test.dart` | Add route-timeline, cancellation, reduced-motion, existing-keyboard, same-key, stacked-sheet, and geometry tests. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/text_input_host_test.dart` | Add isolated readiness-scope tests for effective autofocus and direct interaction. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/integration_test/bottom_sheet_keyboard_profile_test.dart` | Exercise the real iOS software keyboard and record the staged entrance in Profile mode on a physical iPhone. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/test_driver/bottom_sheet_keyboard_profile_test.dart` | Summarize timeline data and enforce the existing frame-budget policy for the new interaction group. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/README.md` | Document the physical-device command and output artifact for the keyboard profile test. |
| `/Users/rcmerci/gh-repos/bonsai_flutter/docs/navigation.md` | Document that route focus remains modal immediately but automatic text-input autofocus is staged until entrance completion. |


No file under `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml`, `/Users/rcmerci/gh-repos/bonsai_flutter/spec`, or a dune path is in scope.
No protocol schema or generated protocol file is in scope.

## Implementation sequence

Use `@Test-Driven Development (TDD)` for every behavior-changing task.
Write the complete failing behavior suite first, confirm that failures describe the current entrance and keyboard overlap, add the minimum production behavior, and then refactor the inset dependency.

### Task 1: Capture the pre-change baseline

1. Read `/Users/rcmerci/gh-repos/bonsai_flutter/AGENTS.md` and preserve unrelated worktree changes.
2. Run the existing focused modal widget suite and retain its full result as the semantic baseline.
3. Build a Profile physical-iPhone fixture containing a modal bottom sheet and an autofocus `TextInputHost` without changing any OCaml source.
4. Record the current sheet top edge, keyboard top edge, bottom inset, route progress, build duration, raster duration, and missed-frame counts.
5. Capture a high-frame-rate screen recording and label the frames where the sheet starts, keyboard starts, sheet settles, and keyboard settles.
6. Capture the same interaction in the current Gmail App Store build on the same device and record the app and operating-system versions.
7. Do not tune any constant before the baseline artifacts exist.

### Task 2: Add all failing automatic-focus tests

1. Extend `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/navigation_host_test.dart` with a fixture that can sample route progress without settling the entire animation.
2. Add a test that proves the autofocus input is currently focused before the entrance completes.
3. Add the required future assertion that automatic input focus remains false during the entrance and becomes true only after completion.
4. Add tests for route removal during entrance, stacked modals, a same-key `requestFocus` update, reduced motion, zero duration, and a pre-existing keyboard inset.
5. Add a mid-entrance pointer-tap test that requires immediate focus despite the closed automatic gate.
6. Add tests in `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/text_input_host_test.dart` for protocol autofocus combined with absent, closed, and ready activation scopes.
7. Run the focused tests and confirm the new assertions fail for the intended missing staging behavior.
8. Fix fixture errors until no failure is caused by compilation, timing ambiguity, or an unrelated existing contract.

### Task 3: Implement the minimal automatic-focus boundary

1. Create `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_keyboard_coordinator.dart` as an internal-only module.
2. Add a readiness scope that defaults to ready outside a staged modal route so ordinary text inputs retain their existing behavior.
3. Make `BonsaiModalBottomSheetRoute` publish not-ready only for automatic focus during a live nonzero entrance with no existing keyboard.
4. Observe the route animation status and publish ready when the forward transition completes.
5. Make `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/text_input/text_input_host.dart` combine protocol autofocus with readiness.
6. Preserve pointer focus, explicit host focus, route focus isolation, semantics isolation, and text-controller identity.
7. Cancel every route listener and pending callback when the route reverses or is disposed.
8. Run the RED tests and confirm they become green without changing route duration or keyboard-inset math.

### Task 4: Localize keyboard-inset rebuilding

1. Add a narrow inset-owning widget to `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/navigation/modal_sheet_keyboard_coordinator.dart`.
2. Move the `MediaQuery.viewInsetsOf` dependency from the route policy builder into that widget.
3. Preserve one bottom padding application and continue removing the bottom view inset from the content subtree.
4. Keep the rounded clipped surface and detented host inside the same route and preserve their identity.
5. Do not add an implicit animation over the inset.
6. Add sampled-inset tests that verify monotonic bottom position and correct medium and large detent geometry.
7. Run the full modal and text-input widget suites.

### Task 5: Verify on a physical iPhone

1. Add `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/integration_test/bottom_sheet_keyboard_profile_test.dart` and its timeline driver without editing OCaml fixtures.
2. Run the test in Profile mode on the explicitly selected physical device described by `/Users/rcmerci/gh-repos/bonsai_flutter/docs/ios-device-testing.md`.
3. Verify that the sheet reaches its settled route geometry before automatic keyboard motion begins.
4. Verify that the keyboard and route-owned bottom inset remain visually locked during keyboard presentation and dismissal.
5. Compare build and raster p90, missed-frame counts, and screen recordings with the Task 1 baseline.
6. Repeat with reduced motion, hardware keyboard, interactive keyboard dismissal, medium detent, large detent, and a mid-entrance user tap.
7. Save the machine-readable summary under the integration application's ignored `build` directory and record only non-sensitive aggregate results in documentation.

### Task 6: Update documentation and finish verification

1. Update `/Users/rcmerci/gh-repos/bonsai_flutter/docs/navigation.md` with the staged automatic-focus contract and the explicit-focus exception.
2. Update `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/integration_test/README.md` with the physical-device profile command.
3. Run `dart format` on changed Dart files.
4. Run `flutter analyze` in `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter`.
5. Run the focused modal and text-input tests, then the complete package test suite.
6. Run the physical-iPhone Profile gate one final time.
7. Confirm that no OCaml, spec, schema, generated protocol, native-asset, or dune file changed.

## Acceptance criteria

The automatic autofocus path has a visible phase boundary: the sheet completes its route entrance before the iOS keyboard starts moving.


The sheet top edge and keyboard top edge move monotonically within their own phases, with no one-frame reversal, jump, or temporary double inset in the screen recording.


The physical-device Profile report keeps p90 build and raster durations at or below 16 milliseconds and does not regress missed-frame counts relative to the recorded baseline.


An explicit tap or explicit host focus request during entrance remains immediate.


Reduced motion, zero-duration transitions, existing keyboards, hardware keyboards, floating keyboards, interactive dismissal, stacked sheets, and interrupted routes behave according to the target contract.


All existing modal semantics, barrier behavior, Back and Escape handling, route-pop events, detents, safe areas, rounded clipping, restoration, same-key state preservation, and one-inset ownership tests continue to pass.


No public OCaml or Dart API changes, protocol changes, compatibility path, timing flag, or consumer workaround are introduced.

## Rollback and escalation

The automatic-focus coordinator is internal and can be removed without changing serialized data if physical testing disproves the hypothesis.
Rollback must restore the prior direct autofocus behavior and remove the coordinator rather than retain a disabled compatibility branch.


If staging fixes the visual overlap but frame timings still regress, keep the behavior and profile the localized inset host and detented layout before changing timing.


If the keyboard visibly diverges from `MediaQuery.viewInsets.bottom` on the pinned engine, capture the device, iOS version, keyboard type, engine revision, notification timeline, and screen recording before proposing an iOS bridge or upstream Flutter issue.


An iOS platform channel is an escalation path only after that evidence exists.
It must provide missing timing evidence rather than become a second geometry owner.

## Testing Details

- Existing focused baseline: 55 modal bottom-sheet widget tests passed on 2026-08-11.
- New widget coverage: route progress, staged autofocus, direct tap, cancellation, same-key updates, stacked routes, reduced motion, existing insets, and detent geometry.
- New text-input coverage: protocol autofocus combined with absent, closed, and ready internal activation scopes.
- New device coverage: physical iPhone only because this repository does not support its OCaml backend on iOS Simulator.
- Performance evidence: Profile timeline summary plus before-and-after high-frame-rate recordings.
- Required commands: focused modal tests, focused text-input tests, full package tests, package analysis, and the signed physical-device Profile lane.

## Implementation Details

- Stage only automatic text-input focus and preserve direct user and explicit host focus.
- Use route animation completion rather than a timer or copied Gmail duration.
- Keep Flutter's iOS engine as the sole keyboard animation and inset source.
- Keep the route as the sole consumer and remover of the bottom view inset.
- Localize inset dependencies without adding `AnimatedPadding` or curve matching.
- Preserve route, child, text-controller, selection, scroll, and detent identity.
- Add no OCaml, protocol, native bridge, or public API surface.
- Delete any superseded direct autofocus wiring rather than keep parallel behavior paths.

## Question

Should product review require a completely sequential default, where automatic keyboard motion starts only after the sheet settles, or permit a later follow-up experiment that starts keyboard motion near the end of route progress?
This plan recommends the completely sequential default for the first implementation because it matches the observable Gmail phase ordering and is deterministic across devices.

---
