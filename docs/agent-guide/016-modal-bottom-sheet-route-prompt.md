# Generic Modal Bottom Sheet Route Implementation Plan

Goal: Add a reusable declarative modal-bottom-sheet page presentation to `bonsai_flutter` without introducing any application-specific state, naming, layout, or behavior.

Architecture: Extend the existing typed `Widget.page` navigation pipeline from the public OCaml API through the binary protocol to the Flutter renderer.
The Flutter host must create a real non-opaque Material modal route so the lower page remains mounted and visible while the route owns its barrier, focus scope, semantics isolation, keyboard interaction, and platform dismissal mechanics.
OCaml remains the source of truth for the page stack and the dynamic `can_pop` policy.

Tech Stack: OCaml, Bonsai, the generated binary protocol, Dart, Flutter Material navigation, Dune, Alcotest, and Flutter widget tests.

Related: Relates to the external consumer design in `/Users/rcmerci/gh-repos/logseq_journal/docs/agent-guide/009-contextual-capture-bottom-sheet.md`, but this framework change must not contain Journal or Capture concepts.

## Problem statement

You are working in `/Users/rcmerci/gh-repos/bonsai_flutter`.

Read `/Users/rcmerci/gh-repos/bonsai_flutter/AGENTS.md` before changing anything.

The current declarative navigation surface supports standard pages with `None`, `Fade`, and `Slide` transitions.
The Flutter renderer creates opaque `PageRouteBuilder` routes for `None` and `Fade`, and a Cupertino route for `Slide`.
The current `Ui.Widget.overlay` is a stack-like layout primitive rather than a modal route.
It cannot provide a Navigator-owned modal barrier, lower-route semantics isolation, native platform Back behavior, route-local focus, or correct route restoration identity.

Implement a first-class modal-bottom-sheet page presentation in the framework.
The result must be a generic capability that can be used by editors, filters, inspectors, pickers, forms, and other applications.
Do not implement a Journal widget, a Capture widget, draft state, save state, task state, storage behavior, or any consumer-specific visual tokens.

Do not use an imperative `showModalBottomSheet` call detached from the declarative page list.
Do not emulate modality with `Stack`, `Overlay`, duplicated background content, or an application-owned scrim.
Do not add a Dart-side source of truth for whether the page exists.

## Testing Plan

I will add OCaml behavior tests that construct a standard page and a modal-bottom-sheet page through the public API and verify their distinct typed presentation contracts in the emitted UI tree.

I will add protocol tests that round-trip every supported modal configuration value and verify incremental property updates without relying only on record equality.

I will add Flutter codec tests that decode valid modal-page properties and reject invalid enum values, flags, durations, and numeric values with the existing typed protocol error behavior.

I will add Flutter navigation widget tests that prove the lower route remains mounted and visible, the barrier blocks pointer interaction, the modal route owns focus, and the lower route is excluded from accessible interaction while the modal is active.

I will add dismissal tests for platform Back, barrier tap, and drag where supported.
Each dismissal path must honor the current declarative `canPop` value before removal and emit exactly one typed route-pop event only after an allowed removal.

I will add update tests that change `canPop` while the route is mounted and prove the active route uses the new policy without losing its child state or route identity.

I will add keyboard tests with a focused text input and nonzero `MediaQuery.viewInsets.bottom` to prove that framework and consumer padding do not double-apply the keyboard inset.

I will add safe-area, compact-height, large-text, LTR, RTL, light-theme, dark-theme, and reduced-motion tests for behavior that belongs to the route.

I will add restoration and reconciliation tests that prove a stable page key updates the existing route while a different key creates a distinct route.

I will run the focused OCaml, protocol, and Flutter tests after each layer, then run the repository-wide suites and protocol generation checks.

NOTE: I will write *all* tests before I add any implementation behavior.

## Required execution process

Use `@Test-Driven Development (TDD)` for every implementation tranche.

For each behavior, write the smallest test first, run it, and record that it fails for the expected missing behavior.
Then add the minimum implementation needed to pass it and rerun the focused test.

Do not write all implementation first and add tests afterward.
Do not accept snapshot-only or type-shape-only tests as evidence for navigation, dismissal, focus, semantics, or keyboard behavior.

Inspect the current navigation, reconciliation, protocol-generation, and testing conventions before choosing the final API shape.
Keep the implementation aligned with the existing typed UI IR rather than creating a parallel custom-widget path.

## Repository authority and constraints

| Area | Authority and constraint |
| --- | --- |
| Repository | Modify only `/Users/rcmerci/gh-repos/bonsai_flutter`. |
| External consumer | Do not modify `/Users/rcmerci/gh-repos/logseq_journal`. |
| Public spec | You are explicitly authorized to modify only relevant `.mli` files under `ocaml/spec/` if the generic API genuinely requires it. |
| Spec implementation | Do not modify other OCaml files under `ocaml/spec/`. |
| Dune | Do not modify any Dune file. |
| Generated protocol | Modify the schema source and use the repository generator rather than hand-maintaining generated artifacts. |
| Compatibility | Keep existing standard page behavior correct, but do not add deprecated aliases, fallback decoding, or duplicate APIs. |
| Blocker | If an `ocaml/spec/*.mli` contract is unclear or unreasonable, stop and report the exact issue, proposed signature change, and rationale. |

## Generic framework boundary

The public API may describe presentation mechanics only.

| Framework-owned concern | Consumer-owned concern |
| --- | --- |
| Route kind and non-opaque composition. | Sheet content and product layout. |
| Modal barrier color, label, dismissibility, and semantics. | Product copy and business semantics inside the child. |
| Route focus scope and optional initial focus request. | Which child is autofocusable. |
| Safe-area and keyboard geometry policy. | Content padding within the sheet. |
| Entrance and exit motion policy. | Product-state transitions. |
| Drag capability and drag handle visibility when safe. | Dirty-draft or saving policy expressed through `can_pop`. |
| Stable page and restoration identity. | Application route IDs and reducer state. |
| Typed route-pop event after allowed removal. | Deciding whether to remove the declarative page. |

No public identifier, source filename, test fixture, comment, or documentation example for the new framework API may contain `journal`, `capture`, `block`, `draft`, or `logseq` unless it is clearly labeled as external motivation outside shipped source.

## Recommended public API direction

Prefer a presentation type that is separate from transition intent.
A modal bottom sheet is not merely another animation because it changes opacity, barrier ownership, focus, semantics, safe-area behavior, and dismissal mechanics.

The likely shape is a typed page-presentation value with a standard-page case and a `Modal_bottom_sheet` case carrying generic configuration.
`Widget.page` should accept the presentation value while retaining the existing stable page key, `can_pop`, and restoration ID.

Treat this as a design direction rather than permission to copy an unreviewed record shape.
Inspect naming conventions, default-argument conventions, protocol evolution rules, and how the renderer reconciles `Page` objects before finalizing the signature.

The modal configuration should cover only route-level behavior that cannot be expressed by the child.
Evaluate the following fields and document every included default.

| Option | Required behavior |
| --- | --- |
| `barrier_dismissible` | Controls whether a barrier tap may request dismissal, while still honoring `can_pop`. |
| `barrier_color` | Uses the framework color type or a documented theme-derived default. |
| `barrier_label` | Provides an accessible localized barrier label when the consumer supplies one. |
| `is_scroll_controlled` | Allows content to use the viewport above the keyboard rather than the default half-height policy. |
| `use_safe_area` | Defines whether route-level safe-area avoidance is applied and which edges it affects. |
| `request_focus` | Controls route focus acquisition without selecting a product-specific child. |
| `enable_drag` | Is exposed only if every drag dismissal can safely honor dynamic `can_pop`. |
| `show_drag_handle` | Must never advertise drag dismissal when drag is disabled or unsafe. |
| `transition_duration` | Uses a finite nonnegative typed duration and resolves to zero for reduced motion. |
| `reverse_transition_duration` | Uses a finite nonnegative typed duration and resolves to zero for reduced motion. |

Do not expose Flutter objects, callbacks, `BuildContext`, `Route`, `ShapeBorder`, or Material implementation classes through the OCaml API.
Do not add arbitrary untyped JSON or string maps.
Do not expose every constructor parameter of Flutter's `ModalBottomSheetRoute` preemptively.
YAGNI applies to elevation, constraints, clipping, snapshotting, captured themes, and animation controllers unless a behavior test demonstrates that the declarative framework must own them.

The child should remain responsible for drawing any custom sheet surface when the generic route can safely use a transparent or theme-derived host surface.
If the renderer must supply a Material surface for correct route behavior, expose only portable typed primitives and document the ownership boundary.

## Required route behavior

### Declarative identity and reconciliation

The modal bottom sheet must be represented by an item in the existing Navigator page list.
Adding the item presents one route.
Removing the item dismisses that route.
Updating properties with the same page key must update the active route contract without recreating its content state.
A new page key must represent a distinct route.
The existing restoration ID must remain attached to the route settings.

The renderer must not imperatively mutate the OCaml-owned page list.
An allowed native dismissal must produce the existing typed route-pop event exactly once so OCaml can update that list.

### Non-opaque composition

The lower route must remain mounted, laid out, and visible behind the modal barrier.
The lower route must not be rebuilt as a copy inside the modal route.
The modal route must use Navigator route composition rather than application content composition.

### Barrier and modality

The route must install a real modal barrier above the lower route and below the sheet child.
The barrier must prevent pointer events from reaching lower content even when barrier dismissal is disabled.
When barrier dismissal is enabled, a tap may dismiss only when the current declarative `can_pop` value permits it.
When barrier dismissal is disabled, a tap must neither dismiss nor leak through.

The lower route must not remain actionable through keyboard traversal or accessibility semantics while the modal route is active.
Use Flutter's route and semantics mechanisms rather than manually hiding a few known child types.

### Dismissal policy

The current `can_pop` value is authoritative for platform Back, Escape where applicable, barrier tap, drag dismissal, and any Navigator pop attempt initiated by the host.
When `can_pop` is false, the route remains present and no route-pop event is emitted.
When `can_pop` changes to true without changing the page key, a later allowed dismissal succeeds and emits exactly one event.
Programmatic removal from the declarative page list must still work even when `can_pop` is false because OCaml already made the removal decision.

Do not approximate this with a check that occurs only after the route has been removed.
Do not rely on a stale constructor value when Page updates can change `can_pop`.

If Flutter's modal drag machinery cannot be made to consult the live declarative pop policy before removal, ship the first generic API with drag disabled and without a drag handle.
In that case, omit or reject `enable_drag = true` rather than exposing an unsafe affordance, and document the specific Flutter limitation for future work.

### Focus and accessibility

The modal route must own an independent focus scope.
When `request_focus` is true, focus enters the modal route without the framework choosing a specific child.
An autofocus child may then receive focus through normal Flutter behavior.
When the route closes, focus returns through normal Navigator behavior.

The route must expose modal semantics and exclude the lower route from accessible interaction while active.
The barrier label must be applied through the native modal barrier contract.
The implementation must behave correctly with screen-reader semantics enabled and with keyboard focus traversal.

### Keyboard and safe area

The API must define whether the route or the child consumes `MediaQuery.viewInsets.bottom`.
There must be one authoritative keyboard-inset owner so a consumer can avoid double padding.
With `is_scroll_controlled` enabled, focused text input must remain usable as the keyboard appears and changes height.

The implementation must handle zero and nonzero top, left, right, and bottom safe-area values.
It must handle compact landscape height without placing the sheet outside the visible viewport.
It must not hard-code phone dimensions or consumer-specific maximum widths.

### Motion

The modal barrier fades and the sheet enters from the bottom using the native modal route behavior or an equivalent route-owned transition.
Configured durations must be finite and nonnegative.
When `MediaQuery.disableAnimations` or `accessibleNavigation` requests reduced motion, entrance and exit durations resolve to zero while route, barrier, focus, and semantics behavior remains unchanged.

## Protocol and implementation layers

Review and update the following existing layers as required.

| Layer | Primary files |
| --- | --- |
| Public navigation type | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ui/navigation.mli` and `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ui/navigation.ml`. |
| Public page constructor and private view | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ui/widget.mli` and `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/ui/widget.ml`. |
| Wire schema | `/Users/rcmerci/gh-repos/bonsai_flutter/protocol/schema.sexp`. |
| OCaml wire model and codec | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/protocol/wire_frame.mli`, `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/protocol/wire_frame.ml`, `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/protocol/binary_codec.mli`, and `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/protocol/binary_codec.ml`. |
| Generated protocol outputs | Existing generator-owned OCaml, Dart, and Markdown outputs under `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/protocol/`, `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/protocol/`, and `/Users/rcmerci/gh-repos/bonsai_flutter/protocol/generated/`. |
| Dart frame and codec | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/protocol/frame.dart` and `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/protocol/binary_codec.dart`. |
| Flutter page renderer | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`. |
| OCaml behavior tests | `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/core_surface_tests.ml`, `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/public_api_tests.ml`, and `/Users/rcmerci/gh-repos/bonsai_flutter/ocaml/test/protocol_tests.ml`. |
| Flutter behavior tests | `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/navigation_host_test.dart`, `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/binary_codec_test.dart`, and `/Users/rcmerci/gh-repos/bonsai_flutter/flutter/packages/bonsai_flutter/test/cross_language_fixture_test.dart`. |
| Documentation | `/Users/rcmerci/gh-repos/bonsai_flutter/docs/navigation.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/docs/protocol.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/docs/testing.md`, `/Users/rcmerci/gh-repos/bonsai_flutter/README.md`, and `/Users/rcmerci/gh-repos/bonsai_flutter/CHANGES.md` where appropriate. |

Do not assume every listed file must change.
Change only the layers required by the final typed design.
Do not create a native custom widget for this feature because it belongs to core page navigation.

## Bite-sized implementation sequence

### Task 1: Confirm the route contract

1. Read the public page API, page IR, protocol schema, generated protocol rules, renderer reconciliation, and existing navigation tests.
2. Write a short design note in the implementation commit or planning document explaining why presentation is distinct from transition.
3. Decide the minimal generic modal configuration and its defaults.
4. Identify how an active route will read live `can_pop` after a same-key Page update.
5. Identify one keyboard-inset owner and document it before coding.

### Task 2: Add failing OCaml public-surface tests

1. Add a test that constructs a modal page through the intended public API.
2. Assert the emitted page view contains a modal presentation and its generic options.
3. Add a test that standard pages keep their current presentation and transition behavior.
4. Run the focused OCaml test and verify that it fails because the new API or presentation is absent.

### Task 3: Add failing protocol tests

1. Add OCaml codec round-trip tests for the presentation kind and each supported option.
2. Add a test for incremental changes to `can_pop`, barrier policy, focus policy, and duration values on a stable node.
3. Add invalid-value tests where the existing protocol validates enums, flags, durations, colors, or finite numbers.
4. Add or update cross-language fixtures through the repository fixture generator.
5. Run the focused tests and verify the expected failures.

### Task 4: Implement the typed OCaml and protocol surface

1. Add the minimal navigation presentation type and modal configuration.
2. Extend `Widget.page` and its private view representation.
3. Update `protocol/schema.sexp` with stable additive field IDs according to repository conventions.
4. Update handwritten wire and codec code where the generator does not own it.
5. Run `make protocol-generate` and `make protocol-fixtures-generate` rather than editing generated files by hand.
6. Run the focused OCaml and protocol tests until they pass.

### Task 5: Add failing Flutter route tests

1. Add a fixture with one standard lower page and one modal-bottom-sheet upper page.
2. Prove that both child subtrees remain mounted and that the lower page is visible behind the route.
3. Prove the barrier blocks a lower-page tap when it is nondismissible.
4. Prove an enabled barrier tap honors `canPop = false` and later honors a same-key update to `canPop = true`.
5. Prove system Back and Escape follow the same live policy and emit exactly one typed event after an allowed dismissal.
6. Add drag tests only if the selected implementation safely supports live veto before route removal.
7. Prove the modal owns focus and lower semantics are unavailable while it is active.
8. Prove nonzero keyboard insets do not create double padding.
9. Prove reduced motion produces zero-duration entrance and exit without changing modal behavior.
10. Run the focused Flutter tests and verify they fail for the missing route behavior.

### Task 6: Implement the Flutter modal route

1. Decode the typed presentation into the Dart frame model.
2. Create a dedicated declarative `Page<void>` representation for the modal presentation or cleanly extend the existing private page class.
3. Create a real Material modal route with `settings` bound to the Page and with the declarative child as its builder content.
4. Preserve stable Page identity and route state across same-key updates.
5. Wire the live `canPop` policy into every host-initiated dismissal path before removal.
6. Apply barrier, focus, safe-area, keyboard, and reduced-motion configuration through native route mechanisms.
7. Keep programmatic declarative removal independent from user-pop veto.
8. Run the focused navigation, codec, reconciliation, semantics, and text-input tests until they pass.

### Task 7: Document and verify the public capability

1. Add a generic OCaml usage example that presents arbitrary editor or filter content.
2. Document defaults, keyboard ownership, safe-area behavior, dismissal semantics, dynamic `can_pop`, restoration identity, and reduced motion.
3. State whether drag is supported in the first version and why.
4. Update the change log with the public capability and any deliberate limitation.
5. Run formatting and all focused tests again.
6. Run the complete repository verification commands.

## Edge cases

| Edge case | Required outcome |
| --- | --- |
| Modal page is the only Navigator page | Reject through the existing Navigator invariant or document and test the supported behavior. |
| Two modal pages are stacked | Preserve stable ordering, independent keys, and one pop event for the top route only. |
| `can_pop` changes during an entrance animation | The first dismissal attempt after the update uses the new value. |
| Declarative removal occurs during an entrance animation | Route disposal completes without a duplicate pop event or leaked animation controller. |
| Barrier is transparent | It still blocks lower pointer and semantic interaction. |
| Barrier dismissal is false while `can_pop` is true | Barrier tap remains blocked, while another allowed path may pop. |
| Barrier dismissal is true while `can_pop` is false | Barrier tap cannot remove the route or emit a pop event. |
| Drag is disabled | No drag handle or drag semantics imply that dismissal is available. |
| Drag is interrupted or canceled | The route returns to its resting position and emits no event. |
| Keyboard height changes while open | Content follows the documented single-inset policy without a jump caused by double padding. |
| Text scale is large | Route-owned controls and barrier semantics remain valid while consumer content may scroll or size itself. |
| LTR and RTL | Direction-sensitive animation and barrier semantics follow the ambient direction. |
| Reduced motion changes while mounted | Subsequent route motion uses the resolved accessibility policy without recreating content. |
| Page key stays stable while configuration changes | Route state and child state are preserved when Flutter permits a Page update. |
| Restoration ID changes unexpectedly | Follow and test the existing framework invariant rather than silently reusing incorrect restoration state. |
| Host receives repeated pop attempts | At most one allowed route-pop event is emitted for one removal. |

## Verification commands

Run focused commands during development and show the expected failing and passing results in the final report.

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
dune runtest ocaml/test
make protocol-check
make protocol-fixtures-check
cd flutter/packages/bonsai_flutter
flutter test test/navigation_host_test.dart test/binary_codec_test.dart test/cross_language_fixture_test.dart
```

Run the complete verification before declaring success.

```sh
cd /Users/rcmerci/gh-repos/bonsai_flutter
make fmt
make test
make protocol-check
make protocol-fixtures-check
make dart-analyze
make flutter-test
git diff --check
git status --short
```

Do not modify test expectations merely to accept incorrect behavior.
If a repository-wide test fails for an unrelated pre-existing reason, prove that with the focused passing tests and include the exact failure in the final report.

## Acceptance criteria

1. A consumer can declaratively add a modal-bottom-sheet page through the public typed OCaml API.
2. The same API contains no consumer-specific state, copy, colors, dimensions, persistence, or product concepts.
3. The Flutter renderer creates a real non-opaque modal route rather than an opaque page or stack overlay.
4. The lower page remains mounted and visible but cannot receive pointer, keyboard, or accessible activation.
5. System Back, Escape, barrier tap, and drag where supported all honor the live declarative `can_pop` policy before removal.
6. An allowed dismissal emits exactly one existing typed route-pop event.
7. Declarative removal works even when native user dismissal is vetoed.
8. Focus, keyboard insets, safe areas, restoration identity, LTR, RTL, and reduced motion have behavior tests.
9. Existing `None`, `Fade`, and `Slide` pages retain their tested behavior without a fallback or parallel compatibility API.
10. Protocol generation and cross-language fixtures are current and all focused and complete verification commands pass.
11. Public navigation documentation explains the generic API, defaults, limitations, and inset ownership.
12. No Dune file, external consumer file, or unauthorized `ocaml/spec/` implementation file changes.

## Testing Details

The OCaml tests verify observable public UI construction and serialized behavior rather than testing only type declarations.
The Flutter tests exercise real Navigator, route, barrier, focus, semantics, keyboard, and pop behavior using rendered widgets and emitted typed events.
The cross-language fixture tests prove that OCaml and Dart agree on the same wire values.
The regression tests keep every existing page presentation working while the new modal presentation follows a distinct route contract.

## Implementation Details

- Model modal bottom sheet as page presentation rather than as animation alone.
- Keep the page list and pop policy declarative and OCaml-owned.
- Use a real Material modal route with non-opaque composition.
- Keep configuration typed, portable, minimal, and generic.
- Apply one documented keyboard-inset owner.
- Preserve stable Page and restoration identity.
- Honor live `can_pop` before every user-initiated removal.
- Omit unsafe drag support rather than exposing a lossy affordance.
- Generate protocol artifacts from the schema source.
- Remove any superseded experimental path instead of adding a compatibility layer.

## Question

The implementation must answer whether Flutter's modal drag route can consult an updated declarative `can_pop` value before committing dismissal.
If it cannot, keep drag and the drag handle unavailable in the first release and document the limitation.

The implementation must also decide whether route-owned safe-area handling consumes only top, left, and right padding while the child owns bottom keyboard geometry, or whether the route owns all insets.
Choose one policy, encode it in the public documentation, and prove it with tests.

Do not pause for stylistic choices that can be resolved from existing repository conventions.
Stop only for the spec blocker described above or for a route-safety limitation that makes the core non-draggable modal contract impossible.

When complete, report the final public API, changed files by layer, observed red-to-green TDD evidence, verification commands and results, deliberate limitations, and any follow-up work.

---
