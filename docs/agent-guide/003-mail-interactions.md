# Mail Interaction Polish Implementation Plan

Goal: Add a polished leading-edge back gesture, front-loaded detail navigation motion, and Gmail-inspired bidirectional message actions to the Bonsai Mail example.

Architecture: Keep mailbox state, route state, and committed actions in OCaml while Flutter owns route interpolation, gesture-arena participation, per-frame drag state, haptics, and settle animations.
Reuse the existing Slide intent and typed native-widget envelope so neither continuous pointer traffic nor a new core protocol node crosses the FFI boundary.

Tech Stack: OCaml, Jane Street Bonsai, the existing bonsai_flutter binary protocol, Flutter 3.44.8, Navigator 2.0 pages, Cupertino route transitions, and typed native widgets.

Related: Builds on `docs/agent-guide/002-mail-client-example_report.md` and the current `examples/mail` implementation.

## Problem statement

The current `PageTransition.slide` renderer uses a default `PageRouteBuilder` with a raw offset tween.

Its position is linear, only the incoming page moves, and it does not install an interactive leading-edge pop recognizer.

The mail list also changes the outer wrapper of an unread row when opening it marks the message as read.

That wrapper change can remount the row behind the entering detail page and contributes avoidable work at the most visible part of the transition.

`Widget.gesture` has no horizontal drag API, and sending every pointer delta through the OCaml FFI boundary would make Flutter wait on application frames for an interaction that must track the finger locally.

The requested work therefore needs one route-rendering improvement, one keyed-row correction, and one reusable native gesture primitive.

## Document status

| Field | Value |
| --- | --- |
| Date | 2026-07-27 |
| Status | Implemented and verified |
| Implementation | Completed with automated OCaml, Flutter, FFI, signed physical-iOS, and compact-device Profile coverage |
| Primary example | `examples/mail` |
| Primary platform | Compact iPhone-style layout |
| Protocol strategy | Reuse `NativeWidgetProps` without changing the core frame schema |

## Decision summary

1. Realize the existing `Slide` transition as a page-based Cupertino transition instead of a linear `PageRouteBuilder`.
2. Preserve the existing OCaml `Navigation.Slide` API and avoid a main protocol version bump.
3. Make every direct inbox list child one stable keyed swipe host whose shape does not change with read state.
4. Add a reusable built-in `Native_widget.Swipe_action` extension with kind ID `2`.
5. Keep continuous drag, gesture arbitration, pill geometry, haptics, and settle animation entirely in Flutter.
6. Emit one typed start-to-end or end-to-start commit event to OCaml after the local animation reaches its commit point.
7. Use start-to-end for Archive and end-to-start for Mark read or Mark unread in the first implementation.
8. Treat a persistent multi-button action drawer as a separate optional mode because current Gmail uses one configured action per direction.

## Research findings

### Evidence classification

| Finding | Classification | Planning consequence |
| --- | --- | --- |
| Gmail lets the user choose one action for each swipe direction from Archive, Trash, Mark read or unread, Move, Snooze, and None. | Official behavior | Model one commit action per direction for Gmail parity. |
| Current Gmail feedback grows from an edge strip into a rounded pill with a centered action icon. | Observed production behavior | Recreate the spatial idea with original Bonsai Mail colors and icons. |
| The row approximately follows the finger while the pill grows behind it. | Observed production behavior | Keep per-frame translation local to Flutter and approximately one-to-one. |
| Gmail does not publish its detail-route curve, duration, swipe threshold, or fling velocity. | Research limitation | Label all numeric motion values as implementation hypotheses and validate them on a device. |
| Flutter's Cupertino page transition supplies non-linear entrance motion, underlying-page parallax, edge shadow, directionality, and an interactive leading-edge pop. | Official Flutter behavior | Prefer the maintained framework route instead of copying Flutter's private gesture controller. |
| Flutter's Cupertino route uses a 20 logical-pixel leading-edge detector and linear tracking during an active pop gesture. | Official Flutter behavior | Use the framework defaults and lock observable behavior with tests. |

### Gmail parity versus a multi-action drawer

The phrase "more actionable options" can describe two different interaction models.

| Model | Release behavior | Visible controls | Reference |
| --- | --- | --- | --- |
| Gmail parity | Crossing the threshold commits the configured action. | One pill and icon for the active direction. | Current Gmail |
| Multi-action drawer | Releasing at a detent leaves the row open for a later button tap. | Two or more persistent buttons. | Apple Mail and platform swipe-actions APIs |

The recommended first implementation is Gmail parity because it is simpler, faster to operate, and matches the named reference.

The two directions still expose two useful contextual actions without placing destructive Delete on a full-swipe gesture.

A multi-action drawer should be planned as a second mode only if the product requirement is specifically to leave multiple tappable buttons open.

## Testing Plan

### Test-first rule

Implementation execution must use @test-driven-development for every behavior change in this plan.

Record the current green baseline before adding new assertions.

Add every new behavior test and observe the intended RED result before adding implementation behavior.

Use raw `NativeWidgetProps` fixtures or zero-behavior API declarations where necessary so a RED test fails on behavior rather than an unrelated missing import.

Implement only enough behavior to make one group of tests green at a time.

Refactor shared codecs, fixtures, and animation helpers only after the complete new test set is green.

### Automated coverage matrix

| Layer | Test file | Required coverage |
| --- | --- | --- |
| OCaml mail behavior | `ocaml/test/mail_example_tests.ml` | Stable row identity, action mapping, mailbox mutation, read-state mutation, nested-action isolation, and route-pop validation |
| OCaml native contract | `ocaml/test/native_widget_tests.ml` | Props encoding, validation, direction-event decoding, handler filtering, and child-count assumptions |
| Flutter navigation | `flutter/packages/bonsai_flutter/test/navigation_host_test.dart` | Front-loaded entrance, exact landing, parallax, interactive edge tracking, cancel, commit, guards, RTL, and reduced motion |
| Flutter native registry | `flutter/packages/bonsai_flutter/test/native_widget_test.dart` | Built-in registration, version and capability rejection, malformed props, and host disposal |
| Flutter swipe behavior | `flutter/packages/bonsai_flutter/test/swipe_action_test.dart` | Both directions, threshold, fling, pill geometry, gesture arena, single emission, semantics, lifecycle, RTL, and reduced motion |
| Real OCaml to Flutter round trip | `flutter/integration_test/test/mail_ffi_test.dart` | Swipe commit through FFI, incremental row removal, detail push, edge pop, and preserved read state |
| Existing regressions | Existing OCaml, Flutter, protocol, and integration suites | No change to None, Fade, text input, virtual list, renderer lifecycle, or host navigation behavior |

### Navigation motion assertions

Define visible progress as `p(t) = (viewportWidth - detailLeadingEdge(t)) / viewportWidth`.

The entrance test must observe `p(0) = 0` and `p(T) = 1` within one physical pixel.

The first quarter of the animation must cover more distance than the last quarter.

The halfway sample must be beyond linear halfway progress.

Every sampled detail position must be monotonic and must not overshoot the leading edge.

The underlying inbox must move by a smaller parallax distance and remain mounted throughout the transition.

Tests must assert observable motion instead of asserting a specific route class or curve object.

### Interactive back assertions

A drag beginning inside the leading 20 logical pixels must move the detail page approximately one physical pixel for each physical pixel of finger movement.

`NavigatorState.userGestureInProgress` must remain true during the drag and its settle.

A short low-velocity drag must return to the detail page without emitting `RoutePop`.

A drag beyond the framework commit point or a qualifying fling must expose the inbox and emit exactly one typed `RoutePop` for the detail page.

The real page removal from the OCaml model must wait for the event batch and the next OCaml frame.

The gesture must not start on the root page, on a page with `canPop = false`, during an existing route transition, from the middle of the screen, or in the reverse direction.

RTL must mirror the physical edge and movement while preserving leading-edge semantics.

### Swipe-action assertions

Horizontal content translation must track the finger until release.

The active feedback must grow from the correct directional edge and never paint outside the row bounds.

A drag below both distance and velocity thresholds must close without emitting an event.

A threshold crossing must produce one light haptic at most once for that gesture.

A committed action must emit exactly one direction event even if a second pointer update or widget rebuild occurs during settle.

A predominantly vertical gesture must remain owned by the inbox `ListView` and leave the row offset at zero.

Winning a horizontal drag must cancel the row tap and any star-button tap candidate.

Closed feedback children must not be hit-testable or independently focusable.

The host must expose Archive and Mark read or unread as custom semantic actions even when no swipe is performed.

Reduced-motion mode must preserve direct finger tracking and may make only the post-release settle immediate.

NOTE: I will write *all* tests before I add any implementation behavior.

## Product behavior specification

### Opening a message

Tapping the non-star area of a mail row marks the message as read and selects the detail route in one OCaml state update.

The direct list child retains the same key and node identity while its read decoration and typography update.

The detail page enters from the trailing edge with a front-loaded non-linear trajectory.

The inbox remains visible underneath and shifts with low-amplitude parallax.

The incoming page carries the framework edge shadow so the spatial boundary remains legible.

The baseline duration is Flutter 3.44.8's 500 millisecond Cupertino transition duration.

That duration is an implementation baseline rather than a claim about Gmail's internal timing.

If device comparison shows that the tail feels too long, change the measured target and its tests together instead of layering a second animation over the route.

### Returning from detail

The visible Back button continues to work.

In LTR, dragging right from the left edge interactively reveals the inbox.

In RTL, dragging left from the right edge provides the mirrored interaction.

The page follows the finger linearly while the gesture is active.

Releasing before the commit decision eases the page back to its settled position.

Committing the gesture completes the visual pop and emits one route-pop event containing the actual detail page key.

The mail route handler ignores a route-pop event whose page key does not match the currently selected detail page.

### Swiping a message row

The first version has no persistent open row state.

Dragging reveals one directional pill and releasing either cancels or commits that direction.

| Logical direction | LTR physical gesture | Action | Visual role | Commit disposition |
| --- | --- | --- | --- | --- |
| Start-to-end | Swipe right | Archive | Muted success green with archive icon | Animate content out, then emit |
| End-to-start | Swipe left | Mark read or Mark unread | Muted primary blue with envelope icon | Return content to rest, then emit |

The end action label and icon are derived from the current message state.

Archive changes `mailbox` from `Inbox` to `Archived` and removes the row only after the Flutter commit animation completes.

Mark read or unread updates the row in place and preserves its keyed native host.

Neither action opens the detail page.

Delete remains in the detail toolbar because a destructive full swipe should not ship before an Undo path exists.

### Initial motion hypotheses for device tuning

| Parameter | Initial value | Rationale |
| --- | --- | --- |
| Horizontal intent slop | 10 logical pixels | Avoid accidental activation during taps. |
| Direction dominance | `abs(dx) > 1.35 * abs(dy)` | Let vertical inbox scrolling win ambiguous gestures. |
| Pill vertical inset | 4 logical pixels per edge | Preserve row separation. |
| Pill minimum width | 8 logical pixels | Begin as a visible edge strip. |
| Pill circle width | 52 logical pixels | Create a stable icon stage. |
| Pill maximum width | 144 logical pixels | Keep feedback local instead of filling the row. |
| Icon size | 24 logical pixels | Match the existing compact toolbar scale. |
| Commit distance | `clamp(rowWidth * 0.28, 72, 112)` | Start below Flutter Dismissible's heavier default. |
| Commit fling velocity | 800 logical pixels per second | Permit an intentional short fling. |
| Cancel settle | 200 milliseconds | Return quickly without snapping. |
| Dismiss settle | 220 milliseconds | Complete before OCaml removes the row. |
| Rebound settle | 190 milliseconds | Return before the read-state frame becomes visible. |

These values must be measured on a compact device in Profile mode.

They must not be documented later as Gmail specifications.

## Accessibility and input behavior

The row retains its existing sender, subject, category, and read-state semantics.

The native host adds custom semantic actions named `Archive` and either `Mark read` or `Mark unread`.

Invoking a custom semantic action follows the same commit state machine and emits the same typed event as a swipe.

The star remains a separately labeled button with its existing selected state.

The Back button remains available for switch control, keyboard navigation, pointer input, and users who do not discover edge gestures.

The feedback pill is decorative and is excluded from independent semantics and hit testing.

All logical directions use start and end rather than hard-coded left and right.

Mouse and trackpad input may use the same horizontal drag recognizer, but this work does not add desktop-only hover controls.

The framework route and local animation controllers must honor the platform reduced-motion setting.

## Scope boundaries

### In scope

- The existing `Slide` transition's Flutter realization.
- Interactive leading-edge return for a poppable Slide page.
- Stable keyed inbox row structure.
- One Gmail-style commit action in each logical swipe direction.
- Reusable typed native-widget support for the swipe interaction.
- OCaml, Flutter widget, FFI integration, accessibility, and manual profile tests.
- Documentation updates that describe the new behavior and architecture.

### Out of scope

- A Gmail settings screen for remapping swipe directions.
- A persistent multi-button action drawer in the first implementation.
- Full mailbox navigation for Archived or Trash.
- Undo, Snackbar, compose, networking, persistence, or real mail accounts.
- Exact Gmail brand colors, icons, source code, curve values, or thresholds.
- Android predictive-back surface scaling and rounded-corner treatment.
- A new Android support claim.
- A core protocol node kind or main protocol version bump.

## Architecture

### Ownership flow

```text
OCaml mailbox state and route state
              |
              | declarative frame
              v
Flutter NodeStore and Navigator.pages
              |
              +--> Cupertino page transition
              |      owns push frames and edge-pop progress
              |
              +--> SwipeActionHost
                     owns drag frames, gesture arena, pill paint,
                     haptic, and post-release settle
                              |
                              | one NativeEvent on commit
                              v
OCaml handler updates mailbox or read state
              |
              | incremental frame
              v
Flutter removes or updates the keyed row
```

### Route boundary

`Ui.Navigation.Slide` remains the OCaml and wire-level transition intent.

`WidgetRegistry` maps None and Fade to their existing route behavior.

`WidgetRegistry` maps Slide to `CupertinoPage<void>` with the existing page key, restoration ID, `canPop`, and child.

Using the page-based Flutter type ensures an updated declarative page supplies its latest child.

Using Flutter's maintained route also avoids copying the private back-gesture controller and its edge, velocity, settle, parallax, directionality, and lifecycle rules.

`Navigator.onDidRemovePage` remains the only renderer path that emits `RoutePop`.

Cancellation never removes the route and therefore never emits an event.

### Mail row boundary

Every direct `ListView` child becomes a keyed `Native_widget.Swipe_action` node.

The content child always contains the same decoration, semantics, tap gesture, and row layout shape.

Read state changes decoration and text properties without conditionally adding or removing an outer wrapper.

The inner tap gesture does not carry the collection key because identity belongs to the direct list child.

The native host receives three children in this fixed order:

1. Row content.
2. Start-direction icon.
3. End-direction icon.

The host paints the pill itself from typed color props and positions the icon child inside it.

The mail example uses `mail-swipe-<id>` for the host and keeps the existing `mail-row-<id>` and `mail-star-<id>` identifiers on the content controls.

The two decorative icon children use `mail-swipe-archive-<id>` and the state-dependent `mail-swipe-mark-read-<id>` or `mail-swipe-mark-unread-<id>` identifiers.

### Native widget contract

The built-in extension uses kind ID `2`, schema version `1`, and the `Stateful`, `Resource`, and `Semantics` capability bits.

The core `NativeWidgetProps` envelope already carries kind, version, capabilities, payload, children, and a typed native-event binding.

No core frame codec or generated protocol change is required.

The proposed OCaml surface is:

```ocaml
module Swipe_action : sig
  type direction =
    | Start_to_end
    | End_to_start

  type disposition =
    | Dismiss
    | Rebound

  type action

  val action
    :  label:string
    -> background:Style.Color.t
    -> disposition:disposition
    -> icon:Widget.t
    -> action

  val create
    :  ?key:Key.t
    -> ?start_action:action
    -> ?end_action:action
    -> content:Widget.t
    -> on_commit:(direction -> unit)
    -> unit
    -> Widget.t
end
```

`create` requires at least one action and substitutes `Widget.empty` for an omitted directional icon so the native child count remains fixed.

Default motion values remain inside the reusable primitive for version `1`.

A future schema version can expose tuning values only after more than one consumer needs them.

The proposed Dart model is:

```dart
enum SwipeActionDirection { startToEnd, endToStart }

enum SwipeActionDisposition { dismiss, rebound }

final class SwipeActionProps {
  const SwipeActionProps({
    required this.startEnabled,
    required this.endEnabled,
    required this.startLabel,
    required this.endLabel,
    required this.startBackground,
    required this.endBackground,
    required this.startDisposition,
    required this.endDisposition,
  });

  final bool startEnabled;
  final bool endEnabled;
  final String startLabel;
  final String endLabel;
  final Color startBackground;
  final Color endBackground;
  final SwipeActionDisposition startDisposition;
  final SwipeActionDisposition endDisposition;
}
```

### Version 1 payload

| Offset | Field | Encoding |
| --- | --- | --- |
| 0 | Flags | `u8`, bit 0 start enabled, bit 1 end enabled |
| 1 | Start disposition | `u8`, `0 = dismiss`, `1 = rebound` |
| 2 | End disposition | `u8`, `0 = dismiss`, `1 = rebound` |
| 3 | Reserved | `u8`, must be zero |
| 4 | Start background | ARGB `u32`, little-endian |
| 8 | End background | ARGB `u32`, little-endian |
| 12 | Start label byte length | `u32`, little-endian |
| 16 | End label byte length | `u32`, little-endian |
| 20 | Labels | Consecutive UTF-8 start and end labels |

The decoder rejects an incorrect exact length, unknown flags, unknown disposition, nonzero reserved data, invalid UTF-8, an empty enabled label, or any child count other than three.

The only version `1` event uses event ID `1` and a one-byte payload.

Event byte `0` means start-to-end and event byte `1` means end-to-start.

The OCaml decoder ignores a native event with a different kind, version, event ID, payload length, or direction byte.

### Swipe state machine

```text
Idle
  |
  | horizontal recognizer wins
  v
Dragging
  | \
  |  \ release below distance and velocity thresholds
  |   v
  |  Cancelling ---- settle to zero ----> Idle
  |
  \ release above distance or velocity threshold
      |
      +--> Dismiss commit ---- animate offscreen ---- emit once ---- node drops
      |
      \--> Rebound commit ---- settle to zero ---- emit once ---- updated Idle
```

The host stores drag offset, active direction, threshold-haptic state, commit state, and its animation controller by node identity.

`didUpdateWidget` updates labels, colors, and child content without resetting an active gesture.

`dispose` cancels the controller and prevents a late animation completion from emitting an event.

## Edge cases and failure behavior

| Case | Required behavior |
| --- | --- |
| Mostly vertical row drag | Inbox scroll wins and no pill appears. |
| Slight pointer movement followed by release | Tap is allowed only if the horizontal recognizer never wins. |
| Drag begins on the star | A horizontal win cancels star activation, while a normal tap still toggles the star. |
| Direction reverses before release | Offset and active pill follow the current sign, and only the final committed direction emits. |
| Direction is omitted | Drag in that direction remains at zero and no semantic action is exposed. |
| Row is dropped during settle | Controller is disposed and no late event is emitted. |
| OCaml frame updates a rebound row | Host identity survives and the settled offset remains zero. |
| Archive removes a preceding row | Every following keyed host retains its node and Flutter state. |
| Edge back starts during push | Framework guard rejects it until the route transition completes. |
| Edge back is cancelled | Detail remains selected and no route event enters the OCaml queue. |
| A stale route-pop key arrives | Mail state remains unchanged. |
| Reduced motion is active | Gesture tracking remains direct and settle duration is minimized by framework policy. |
| Wide layout reaches the current 720 pixel cap | The route edge is the constrained application surface edge, with compact-device validation remaining the acceptance target. |

## Implementation plan

### Task 1: Freeze the baseline

Files:

- `flutter/packages/bonsai_flutter/test/navigation_host_test.dart`
- `ocaml/test/mail_example_tests.ml`
- `ocaml/test/native_widget_tests.ml`

Steps:

1. Run the current focused navigation test and record that it is green before adding new assertions.
2. Run the current mail and native-widget executables in an opam switch containing the repository's Bonsai dependencies.
3. Record the current environment failure separately if `bonsai` is unavailable instead of treating it as a product regression.
4. Capture a short Profile-mode recording of the current linear detail entrance for later comparison.

Expected baseline:

- The existing Flutter navigation test is green.
- The current Slide entrance is visibly linear.
- An edge drag does not move or pop the detail route.
- The current mail row has no swipe action host or action test IDs.

### Task 2: Write all navigation RED tests

File:

- `flutter/packages/bonsai_flutter/test/navigation_host_test.dart`

Steps:

1. Add a reusable two-page Slide fixture with stable keys and an event collector.
2. Add time-sampled entrance assertions for front-loaded motion, monotonicity, exact landing, and underlying-page parallax.
3. Add a gesture that begins at `Offset(5, y)` and verifies one-to-one detail tracking.
4. Add separate cancel, distance commit, and velocity commit tests.
5. Assert exactly one `RoutePopEventPayload` with the detail page key after commit.
6. Add root, `canPop = false`, transition-in-progress, middle-start, and reverse-direction guards.
7. Add RTL and reduced-motion cases.
8. Run this file and confirm failures identify the current linear transition and missing edge gesture.

### Task 3: Write all native swipe RED tests

Files:

- `ocaml/test/native_widget_tests.ml`
- `flutter/packages/bonsai_flutter/test/native_widget_test.dart`
- `flutter/packages/bonsai_flutter/test/swipe_action_test.dart`

Steps:

1. Add OCaml examples for both directions, both dispositions, Unicode labels, and invalid values.
2. Assert the exact version `1` byte layout and round-trip event decoding.
3. Assert that wrong kind, version, event ID, length, or direction is ignored.
4. Build raw Flutter frames using native kind ID `2` so the current registry produces an unsupported-widget RED result.
5. Add Dart decoder tests for every malformed payload condition.
6. Add widget tests for horizontal tracking, pill growth, threshold cancellation, distance commit, fling commit, and single emission.
7. Add gesture-arena tests with a vertical `ListView`, a row tap, and a nested star button.
8. Add semantics tests for custom actions and hidden decorative children.
9. Add keyed update, drop, reset, shutdown, RTL, and reduced-motion tests.
10. Run all three focused targets and confirm each new assertion fails for the expected missing behavior.

### Task 4: Write all mail behavior RED tests

Files:

- `ocaml/test/mail_example_tests.ml`
- `ocaml/test_support/handle.ml`
- `ocaml/test_support/handle.mli`

The proposed helper surface is:

```ocaml
val native_event
  :  t
  -> Query.t
  -> kind_id:int
  -> version:int
  -> event_id:int
  -> payload:bytes
  -> unit
```

Steps:

1. Add a generic `Test.Handle.native_event` helper that dispatches a typed native payload through the real headless event path.
2. Assert that every visible row has a stable keyed swipe host and deterministic test ID.
3. Capture the first unread row node ID, open it, pop detail, and assert the same row node ID remains after read state changes.
4. Capture the row after an archive target, invoke the archive direction handler, and assert the following row keeps its node ID.
5. Assert that Archive removes only the target inbox row.
6. Assert that Mark read or Mark unread updates semantics while retaining the row.
7. Assert that either swipe action leaves `mail-detail-page` absent.
8. Send a route-pop event with a nonmatching page key and assert the selected detail remains.
9. Preserve the existing star, attachment, reply notice, toolbar action, and platform-pop coverage.
10. Run the mail executable and confirm the new test IDs and action outcomes are RED.

### Task 5: Write the FFI integration RED test

Files:

- `flutter/integration_test/ocaml/native_integration_embed.ml`
- `flutter/integration_test/ocaml/dune`
- `flutter/integration_test/test/mail_ffi_test.dart`

Steps:

1. Add the mail library and `Native_backend.embed ~name:"mail" Mail.app` to the aggregate native integration object.
2. Start a real runtime session with the `mail` configuration.
3. Swipe an inbox row through the archive threshold and wait for the local dismiss settle.
4. Send the queued native event batch to OCaml and apply the incremental frame.
5. Assert that the archived row disappears and its following keyed row survives.
6. Open another unread message and assert that the detail transition starts away from its final edge.
7. Drag from the leading edge, verify interactive movement, and commit the pop.
8. Send the typed route-pop batch to OCaml and apply the returned frame.
9. Assert that the detail disappears and the opened message remains read.
10. Run the test and confirm the unsupported native kind and missing edge interaction produce the expected RED result.

### Task 6: Make Slide motion and edge back GREEN

File:

- `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`

Steps:

1. Keep `_BonsaiPage` for None and Fade behavior.
2. Create a `cupertino.CupertinoPage<void>` for each Slide page with the same key, name, restoration ID, `canPop`, and child.
3. Keep `Navigator.onDidRemovePage` and its typed route-pop payload unchanged.
4. Do not add a second gesture detector or copied route controller.
5. Run the navigation tests and adjust only observable acceptance tolerances that differ by physical-pixel rounding.
6. Run the existing navigation example and host-navigation tests to verify None and Fade regressions did not occur.

### Task 7: Make the native contract GREEN

Files:

- `ocaml/ui/native_widget.ml`
- `ocaml/ui/native_widget.mli`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/native_widget_registry.dart`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/swipe_action.dart`
- `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`
- `flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart`

Steps:

1. Add `Native_widget.Swipe_action` with the proposed typed actions, encoder, event decoder, validation, and testing helpers.
2. Add the Dart props decoder and direction-event encoder for kind ID `2`.
3. Register the extension beside `Virtual_list` in `WidgetRegistry.standard()`.
4. Validate version, capabilities, exact payload length, reserved bits, UTF-8 labels, and exactly three children before building the host.
5. Implement `_SwipeActionHost` as a `StatefulWidget` whose `State` uses `SingleTickerProviderStateMixin` and disposes its own `AnimationController`.
6. Render a clipped Stack containing the active pill, decorative icon child, and translated content.
7. Use Flutter's horizontal gesture recognizer so the standard gesture arena arbitrates against the vertical list, row tap, and star tap.
8. Implement distance, velocity, direction reversal, one-shot haptic, dismiss, rebound, reduced-motion, and one-shot emission behavior.
9. Add parent custom semantics actions that invoke the same commit methods.
10. Run the native contract, registry, swipe behavior, lifecycle, and animation regression tests.

### Task 8: Make stable mail rows and actions GREEN

Files:

- `examples/mail/ocaml/mail.ml`
- `examples/mail/ocaml/mail.mli`
- `ocaml/test/mail_example_tests.ml`

Steps:

1. Move the stable integer key to the outer `Swipe_action` node that is the direct `ListView` child.
2. Always render the same decorated content wrapper and vary only its background value for read state.
3. Remove the duplicated key from the inner tap gesture.
4. Add Archive and Mark read or unread handlers that update the existing `message` model.
5. Compose the existing row as the content child and use small generic icon children for both directions.
6. Add the documented `mail-swipe-*` test IDs without changing the existing row and star IDs.
7. Validate the exact current detail page key before clearing `selected_id` in the route-pop handler.
8. Keep Delete, toolbar Archive, toolbar Mark unread, and Back behavior unchanged.
9. Run the mail test executable until every new identity and action assertion is green.

### Task 9: Make the FFI path GREEN

Files:

- `flutter/integration_test/ocaml/native_integration_embed.ml`
- `flutter/integration_test/ocaml/dune`
- `flutter/integration_test/test/mail_ffi_test.dart`

Steps:

1. Rebuild the aggregate native object with the mail entrypoint.
2. Run the new mail FFI test without mocking renderer events.
3. Verify that only the final swipe commit crosses FFI and no drag delta appears in an event batch.
4. Verify that archive removal arrives as an incremental frame.
5. Verify that edge pop uses the existing `RoutePop` event and preserves OCaml route ownership.
6. Run the existing FFI tests to catch aggregate embedding or resource-lifecycle regressions.

### Task 10: Profile, tune, and document

Files:

- `examples/mail/README.md`
- `docs/navigation.md`
- `docs/custom-widgets.md`
- `docs/testing.md`
- `docs/agent-guide/002-mail-client-example_report.md`

Steps:

1. Update the mail README so swipe actions are no longer listed as out of scope.
2. Document that Slide uses a non-linear page transition with interactive leading-edge pop.
3. Document the built-in swipe native widget, payload ownership, event timing, and semantics behavior.
4. Add a historical addendum to the earlier mail report instead of rewriting its original research conclusions.
5. Build the mail example in Profile mode on macOS as a preflight, then run
   it on a compact physical iPhone; iPhone Simulator cannot load the
   repository's device-only native object.
6. Record twenty warmed detail entrances, edge-pop cancels, edge-pop commits, row-swipe cancels, and row-swipe commits.
7. Compare the recordings side by side with the public Gmail references at normal speed and slow motion.
8. Inspect Flutter frame timings and remove any repeated over-budget build or raster frame before accepting the motion.
9. Tune only the documented implementation-hypothesis values and update tests when a threshold changes.
10. Preserve the current platform-support wording and do not infer Android support from renderer behavior.

## File change matrix

| File | Planned responsibility |
| --- | --- |
| `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart` | Map Slide pages to the maintained Cupertino page transition and register the built-in swipe host. |
| `flutter/packages/bonsai_flutter/lib/src/native_widget/swipe_action.dart` | Decode props and own drag, animation, pill, haptic, semantics, and event emission. |
| `flutter/packages/bonsai_flutter/lib/src/native_widget/native_widget_registry.dart` | Expose or centralize the built-in kind ID if needed without changing registry semantics. |
| `flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart` | Export the reusable Dart contract used by tests and custom registries. |
| `ocaml/ui/native_widget.ml` | Encode typed swipe props and decode typed direction commits. |
| `ocaml/ui/native_widget.mli` | Publish the reusable OCaml API. |
| `examples/mail/ocaml/mail.ml` | Compose keyed swipe rows and apply Archive or read-state mutations. |
| `examples/mail/ocaml/mail.mli` | Expose only any additional testing surface required by headless tests. |
| `ocaml/test/mail_example_tests.ml` | Lock business state, row identity, action isolation, and route-pop validation. |
| `ocaml/test/native_widget_tests.ml` | Lock the OCaml side of the versioned binary extension contract. |
| `ocaml/test_support/handle.ml` | Dispatch typed native events through the headless runtime for behavior tests. |
| `ocaml/test_support/handle.mli` | Publish the native-event test helper. |
| `flutter/packages/bonsai_flutter/test/navigation_host_test.dart` | Lock observable route motion and interactive edge behavior. |
| `flutter/packages/bonsai_flutter/test/native_widget_test.dart` | Lock registration, rejection, and lifecycle behavior. |
| `flutter/packages/bonsai_flutter/test/swipe_action_test.dart` | Lock the complete Flutter-local swipe state machine. |
| `flutter/integration_test/test/mail_ffi_test.dart` | Lock the real cross-language interaction path. |
| `flutter/integration_test/integration_test/ios_ffi_test.dart` | Include the Mail round trip in the signed physical-iOS aggregate suite. |
| `flutter/integration_test/integration_test/mail_profile_test.dart` | Run warmed production-host interactions and collect physical-device timelines. |
| `flutter/integration_test/test_driver/mail_profile_test.dart` | Summarize timelines, enforce the p90 frame budget, and write the Profile report. |
| `flutter/integration_test/ocaml/native_integration_embed.ml` | Add the mail entrypoint to the test native object. |
| `flutter/integration_test/ocaml/dune` | Link the mail example library for integration tests. |
| `examples/mail/README.md` | Describe the shipped interaction and manual run steps. |
| `docs/navigation.md` | Describe Slide motion and route-pop ownership. |
| `docs/custom-widgets.md` | Describe the new built-in typed native widget. |
| `docs/testing.md` | Describe motion, gesture-arena, semantics, and Profile-mode verification. |

## Verification commands

Run focused OCaml tests:

```sh
dune exec ./ocaml/test/mail_example_tests.exe
dune exec ./ocaml/test/native_widget_tests.exe
dune exec ./ocaml/test/core_surface_tests.exe
```

Run focused Flutter tests:

```sh
cd flutter/packages/bonsai_flutter
flutter test test/navigation_host_test.dart
flutter test test/native_widget_test.dart
flutter test test/swipe_action_test.dart
flutter test test/animation_host_test.dart
```

Run the real FFI test:

```sh
make integration-native-object
cd flutter/integration_test
flutter test test/mail_ffi_test.dart
```

Run the compact physical-iPhone Profile gate:

```sh
cd flutter/integration_test
flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/mail_profile_test.dart \
  --driver test_driver/mail_profile_test.dart \
  --timeout 600
```

The driver writes `build/mail_profile_summary.json`.

Run the full repository checks:

```sh
make test
make fmt
make protocol-check
make protocol-fixtures-check
make ci-contract
make ci-ocaml
make ci-flutter
make integration-test
```

Use the repository's configured Flutter executable or `/Users/rcmerci/development/flutter/bin/flutter` when the shell does not resolve the expected SDK.

The current active opam environment must provide the `bonsai` library before the OCaml commands can establish a valid baseline.

## Acceptance criteria

- Detail entrance motion is measurably front-loaded, monotonic, and exact at rest.
- The inbox remains mounted and participates in subtle parallax during detail entrance.
- A leading-edge drag follows the finger and can either cancel or commit.
- A committed edge gesture emits exactly one matching route-pop event.
- Opening an unread message does not replace the keyed row behind the route.
- Start-to-end Archive removes only the intended row after local dismiss motion.
- End-to-start Mark read or unread updates the intended row in place.
- Horizontal swipe never also opens the row or toggles the star.
- Vertical inbox scrolling remains reliable when a gesture starts on a row.
- Swipe commits generate one FFI event and no per-frame drag traffic.
- Screen-reader users can invoke both row actions without performing a swipe.
- RTL, reduced motion, node drop, stale event, and malformed payload cases are covered.
- Existing None, Fade, virtual-list, renderer-lifecycle, mail-detail, and FFI tests remain green.
- Profile-mode runs show no repeatable jank after warm-up on the compact acceptance device.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Changing Slide affects the navigation example as well as mail. | Add renderer-level regression coverage and keep None and Fade untouched. |
| A 500 millisecond transition may feel longer than the Gmail reference. | Judge front-loaded progress and device recordings first, then tune one route implementation and its tests together. |
| Native swipe state could outlive its OCaml row. | Bind state to node identity, dispose on drop, and guard late completion callbacks. |
| Row removal could interrupt the dismiss animation. | Emit Archive only after Flutter reaches the offscreen commit point. |
| Ambiguous diagonal drags could make the inbox feel sticky. | Let the Flutter gesture arena and a horizontal-intent threshold protect vertical scrolling. |
| A nested star tap could fire with a swipe. | Rely on recognizer cancellation and add explicit widget tests. |
| Native payload duplication could drift between OCaml and Dart. | Freeze exact bytes and invalid cases on both sides with kind-version tests. |
| Gmail research could be mistaken for internal specification. | Keep source classifications and label all numeric values as hypotheses. |
| Users may actually expect multiple persistent buttons. | Ship the recommended Gmail-parity model only after confirming the final product choice below. |

## Sources

- [Gmail swipe settings for Android](https://support.google.com/mail/answer/6562?co=GENIE.Platform%3DAndroid&hl=en)
- [Gmail swipe settings for iOS](https://support.google.com/mail/answer/6562?co=GENIE.Platform%3DiOS&hl=en)
- [Gmail Material 3 Expressive rollout](https://9to5google.com/2025/08/26/gmail-material-3-expressive-redesign/)
- [Gmail Material 3 Expressive swipe animation](https://9to5google.com/2025/06/02/gmail-android-material-3-expressive-update-start/)
- [Flutter MaterialPageRoute](https://api.flutter.dev/flutter/material/MaterialPageRoute-class.html)
- [Flutter CupertinoPageTransitionsBuilder](https://api.flutter.dev/flutter/cupertino/CupertinoPageTransitionsBuilder-class.html)
- [Flutter Cupertino transition duration](https://api.flutter.dev/flutter/cupertino/CupertinoRouteTransitionMixin/kTransitionDuration-constant.html)
- [Flutter PageRoute popGestureEnabled](https://api.flutter.dev/flutter/widgets/PageRoute/popGestureEnabled.html)
- [Flutter fastEaseInToSlowEaseOut](https://api.flutter.dev/flutter/animation/Curves/fastEaseInToSlowEaseOut-constant.html)
- [Flutter linearToEaseOut](https://api.flutter.dev/flutter/animation/Curves/linearToEaseOut-constant.html)
- [Apple interactivePopGestureRecognizer](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivepopgesturerecognizer)
- [Apple SwiftUI swipeActions](https://developer.apple.com/documentation/SwiftUI/View/swipeActions%28edge%3AallowsFullSwipe%3Acontent%3A%29)

## Testing Details

The automated suite separates observable route motion, Flutter-local gesture behavior, OCaml business state, native payload compatibility, and the real FFI round trip.

Widget tests intentionally avoid wall-clock performance gates because shared CI timing is noisy.

Profile-mode device runs remain the acceptance gate for perceived smoothness and repeated frame-budget misses.

The local Flutter navigation baseline passed before implementation.

The required RED failures were observed for the linear Slide transition, missing
edge-pop interaction, unsupported native kind `2`, unimplemented OCaml swipe
contract, missing mail swipe hosts, and absent FFI commit path.

The GREEN verification passes the focused navigation, native-widget, swipe,
mail, and FFI tests; the complete Flutter package and integration suites; OCaml
`@all`, `runtest`, `@fmt`, protocol checks, release benchmark build, and opam
lint; and the complete `ci-flutter` target.

The exact Bonsai preview dependency is installed in the verification switch.
The first `ci-ocaml` dependency-resolution command cannot currently rediscover
that preview package from its configured repositories, but every subsequent
command in the target passes directly in the same switch.

The signed Debug aggregate suite passes on a physical iPhone 13 running
iOS 26.6, including Counter, Gallery, Text Input, Todo, Mail, and Host
Navigation.

The Profile driver also passes on that device after two warm-up repetitions.
It records twenty repetitions each for detail entrance, edge-pop cancel,
edge-pop commit, row-swipe cancel, and row-swipe commit. The unrecorded
acceptance run reported zero missed build and raster budgets. Across an
additional run captured concurrently in QuickTime, the worst p90 build time
was 3.641 ms and the worst p90 raster time was 0.012 ms. That capture recorded
four isolated build-budget misses across 722 build frames and no raster misses,
which were not repeatable in the unrecorded run.

QuickTime reached the physical-device screen, but an iOS accessory-confirmation
sheet obscured the application during that capture. Observable route motion,
gesture tracking, and exact landing therefore remain locked by widget and FFI
tests, while the generated timeline report is the reproducible device
performance evidence. The repository's device-only native object does not
support iPhone Simulator.

## Implementation Details

- Preserve `Navigation.Slide` and its wire value.
- Use a page-based Cupertino route for Slide instead of copying private Flutter gesture code.
- Keep the direct inbox child shape stable and keyed by message ID.
- Allocate native kind ID `2` and schema version `1` for `Swipe_action`.
- Keep drag updates and settle frames inside Flutter.
- Emit one typed logical-direction event only at commit.
- Map start-to-end to Archive and end-to-start to Mark read or unread.
- Keep Delete out of full-swipe behavior until Undo exists.
- Reuse the native-widget envelope so the core frame protocol does not change.
- Validate motion with behavior tests and warmed Profile-mode recordings.

## Implemented product decision

The first release uses the recommended Gmail-parity behavior: Archive on
start-to-end and Mark read or Mark unread on end-to-start. It does not keep a
persistent multi-button drawer open.

---
