# Mail Inline Outliner Card Research

## Document status

| Field | Value |
| --- | --- |
| Date | 2026-08-02 |
| Status | Research and implementation guidance only; no implementation is included |
| Target | `examples/mail` |
| Reference | User-provided compact mail screenshot |
| Repository baseline | `main` at `c1f0064` |
| Framework baseline | Flutter 3.44.8, revision `058e0af2c2` |
| Related documents | `002-mail-client-example_report.md`, `003-mail-interactions.md`, `009-mail-inbox-expansion_report.md` |

## Executive summary

The requested interaction is feasible, but it is not an application-only
change. The current inbox is an endless, bounded-window virtual list whose
items are all forced to `88` logical pixels. An inline card with an outline is
substantially taller, so rendering one inside the current
`Native_widget.Virtual_list` would clip it to `88` pixels and corrupt the
visible-range calculations.

The recommended design is:

1. Treat a row tap as **expand**, not **open**.
2. Keep at most one message expanded with OCaml-owned
   `expanded_id : int option` state.
3. Keep expansion separate from the existing `selected_id` detail-route state.
4. Add explicit, deterministic outline data to every message instead of
   parsing the plain-text body.
5. Add a separate built-in `Sparse_extent_list` native extension, kind `4`,
   version `1`. It retains the current bounded child window while allowing a
   small sorted set of known item-extent overrides.
6. Keep the current keyed `Swipe_action` as the direct list child in both
   collapsed and expanded states.
7. Reuse the existing `mail-detail-<id>` page, route-pop validation, and
   read-state update from a card-local `Open` action.
8. Preserve the expanded card and scroll position when returning from detail.
9. Keep P0 expansion immediate. Size animation can be added later in the
   Flutter-native host without changing committed OCaml state.

The card and outliner visuals themselves do not require a new drawing
primitive. Existing `Material.card`, `Material.divider`, `Stack`, `Sized_box`,
`Decorated_box`, padding, text, and icon nodes can produce the hierarchy shown
in the reference. The main engineering work is safe sparse-extent
virtualization, state semantics, and interaction isolation.

## Request interpretation

This report uses the following terms precisely:

- A **collapsed row** is the current compact `88`-pixel mail item.
- An **expanded card** replaces that row at the same logical list index. It is
  not an overlay and does not duplicate the message.
- **Expand** changes only inline list presentation. It does not select a detail
  route and does not mark the message read.
- **Open** is the explicit card action that marks the message read and pushes
  the existing detail page.
- An **outliner** is a read-only visual tree with top-level bullets, one nested
  child level, and decorative connector lines. Individual outline nodes are not
  independently expandable.
- **Every mail item** means every message rendered through the shared mail-row
  path, including Inbox, Starred, Archived, and Trash views.

The intended primary flow is:

```text
Collapsed row
  -- tap non-star content --> Expanded card
  -- tap another row ------> Other expanded card

Expanded card
  -- tap header/chevron ---> Collapsed row
  -- tap Open -------------> Existing detail page

Existing detail page
  -- Back -----------------> Same expanded card and list position
```

The screenshot also contains `Reply`. The recommended visual match includes
both `Reply` and `Open` in the footer. `Open` is required by the request.
`Reply` should reuse the example's existing deterministic
"Composing is outside the scope of this demo" behavior and must not be a dead
control. If Reply is intentionally deferred, omit it rather than rendering a
button that does nothing.

## Scope

### In scope

- Inline collapsed and expanded presentation for each mail message.
- A single-open accordion model.
- Structured, fictional outline fixtures for curated and generated messages.
- Card header, outline body, divider, collapse affordance, star, Reply, and
  Open actions.
- Reuse of the existing detail page and Back behavior.
- Preservation of endless paging, the bounded OCaml window, drawer, bottom
  destinations, row swipe actions, and stable keyed identity.
- A reusable sparse-known-extent virtual-list extension.
- Headless OCaml, Flutter widget, real-FFI, accessibility, and profile coverage.

### Out of scope

- Editable outline nodes, per-node disclosure, drag reordering, or a general
  tree editor.
- Parsing arbitrary email bodies into a tree.
- Multiple simultaneously expanded cards.
- Real compose, reply sending, accounts, persistence, or network access.
- Changes to the existing detail-page information architecture.
- Arbitrary self-measuring variable-height virtualization.
- Pixel parity with the reference image or copied branding/content.
- Expansion of Search, Chat, Spaces, Meet, or Settings product scope.
- Changes under `spec/` or changes to any dune file.

## Evidence and limitations

### Reference-image observations

The following are visual observations from the user-provided image, not claims
about Gmail internals or exact product specifications.

| Observed element | Adopted interpretation |
| --- | --- |
| One message occupies a tall white rounded surface while later messages remain compact | The selected row expands inline and pushes later rows down |
| Avatar, sender, subject, timestamp, and star remain in the tall item | Expanded card reuses compact-row identity and header information |
| An upward chevron appears in the header | Header content and chevron collapse the card |
| A divider separates the header from a bullet tree | The body is a read-only structured outline |
| Nested bullets use a vertical stem and short horizontal branches | Connectors are decorative layout, not independent semantic nodes |
| A muted final bullet is visible | Outline nodes may carry default or muted tone |
| Reply and Open are equal footer actions | Footer actions are independent controls; Open is the route entry |
| Only one item is expanded in the image | Use an accordion rather than an expanded-ID set |

The image does not establish animation timing, swipe behavior, read-state
timing, accessibility semantics, or behavior after Back. Those are product
decisions in this report.

### Repository and framework evidence

- The current row is fixed at `88` logical pixels in
  `examples/mail/ocaml/mail.ml:521-530`.
- The inbox passes `item_extent:88.` to the built-in virtual list at
  `examples/mail/ocaml/mail.ml:724-733`.
- `docs/virtual-lists.md:42-44` explicitly excludes variable-height rows from
  the fixed-extent prototype and directs them to a separate native extension.
- The Flutter host derives logical indexes with `offset / itemExtent` at
  `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart:203-215`
  and passes one `itemExtent` to `ListView.builder` at lines `236-245`.
- Flutter's maintained `ListView.builder.itemExtentBuilder` supports known
  per-index extents without measuring every child. It is a direct fit for a
  small sparse override set.

The historical `009-mail-inbox-expansion_report.md` still labels itself
"research only", but its virtual list, pagination, Navigation Drawer, bottom
destinations, and Pressable recommendations are present in the current code and
tests. Executable code is the baseline for this report.

## Current repository findings

### Application ownership

The existing boundary is appropriate and must remain intact:

- `examples/mail/ocaml/mail.ml` owns messages, mailbox/read/star state,
  destinations, paging, selected detail, handlers, and route state.
- `examples/mail/flutter/lib/main.dart` is a mechanical runtime shell.
- Flutter owns retained scroll controllers, row drag frames, Pressable feedback,
  drawer motion, and interactive Back interpolation.

Committed expansion state and outline data therefore belong in OCaml. Flutter
may own local scroll anchoring and future interpolation frames, but it must not
gain a second message model or selected-message reducer.

### Current data and state

`message` is defined at `examples/mail/ocaml/mail.ml:20-33`. It has a flat
`preview` and plain-text `body`, but no structured summary. Mara Vale's body at
lines `97-116` already contains bullet characters, yet those characters do not
encode a reliable parent/child tree.

The global state at `examples/mail/ocaml/mail.ml:55-66` contains:

- `selected_id` for the detail route;
- a reply scope `notice`;
- app and mailbox destinations;
- drawer state;
- pagination generation/cursor state; and
- the first logical index in the bounded virtual window.

There is no inline expansion state.

### Current collapsed row and activation

`render_mail_row` at `examples/mail/ocaml/mail.ml:479-586` builds:

- a three-line sender/subject/preview column;
- timestamp and independent star control;
- an `88`-pixel opaque read/unread surface;
- a keyed core `Pressable`; and
- a keyed `Native_widget.Swipe_action` as the outer row host.

`mail_row` at lines `589-649` currently maps the row Pressable directly to
`mail-open-message`. One OCaml update marks the message read and sets
`selected_id`. This handler must be split because row activation and detail
opening now have different meanings.

The current star and swipe behaviors already update in place without route
activation. Existing tests verify nested-control isolation and keyed host
identity.

### Existing detail route

The detail implementation already satisfies the new Open destination:

- `render_detail_page` uses stable `mail-detail-<id>` keys and a Slide
  transition at `examples/mail/ocaml/mail.ml:1092-1103`.
- `selected_id` is projected into a keyed detail-page list at lines
  `1506-1521`.
- route-pop handling validates the exact selected page key at lines
  `1523-1539`.
- Back, archive, delete, mark unread, star, attachment, and reply-scope behavior
  already exist.

No new page, route type, or Flutter-side navigation state is required.

### Available card and outliner primitives

The following current APIs are sufficient for a similar, not pixel-identical,
card:

- `Ui.Material.card ~elevation` and `Ui.Material.divider` in
  `ocaml/ui/material.mli:80-81`;
- `Ui.Widget.Stack` in `ocaml/ui/widget.mli:207-220`;
- `sized_box`, `decorated_box`, `padding`, `row`, and `column` in
  `ocaml/ui/widget.mli:40-48`; and
- the existing text, icon, Pressable, button, and semantics nodes.

A bullet is a small rounded `Decorated_box`. Connector stems and branches are
one-logical-pixel decorated boxes positioned in a fixed-width lane. Nested
columns provide depth. No canvas or mail-specific Dart widget is needed.

Current visual limitations should be accepted for P0:

- `Ui.Material.card` exposes elevation only. Radius, margin, surface tint, and
  shape are supplied by the Material theme.
- `Style.Decoration` exposes background and one uniform radius, but no border or
  shadow.
- core `Widget.clip` maps to `ClipRect`, not a rounded clip.
- there is no core `AnimatedSize` node.
- padding and positioned Stack offsets use physical left/right values rather
  than direction-aware start/end values.

These limitations permit a clearly similar card with light elevation but not
an exact reproduction of the reference radius or shadow.

## Recommended product behavior

### State model

Add one independent field:

```ocaml
type state =
  { (* existing fields *)
  ; selected_id : int option
  ; expanded_id : int option
  }
```

`selected_id` continues to mean "a detail page is selected".
`expanded_id` means "this message is rendered as an inline card". They may
temporarily contain the same ID while detail is open so that Back restores the
card.

### Interaction table

| Action | Committed result |
| --- | --- |
| Tap collapsed row content | Set `expanded_id = Some id`; clear a stale card notice; do not change `selected_id` or `read` |
| Tap another collapsed row | Replace `expanded_id` atomically; only the new card remains expanded |
| Tap expanded header or chevron | Set `expanded_id = None`; clear card notice |
| Tap star in either state | Toggle only `starred`; do not expand, collapse, or navigate |
| Swipe start-to-end in either state | Archive the message; clear `expanded_id` if it is the target |
| Swipe end-to-start in either state | Toggle read state; keep the card expanded |
| Tap Reply | Show the existing fixed-scope notice in the card; do not navigate |
| Tap Open | In one update mark the message read, set `selected_id = Some id`, and clear the card notice |
| Detail Back or matching platform pop | Clear only `selected_id`; retain `expanded_id` and list offset |
| Detail Archive/Delete | Apply the mailbox mutation, clear `selected_id`, and clear `expanded_id` when it targets that message; whether the message remains in the current projection is determined by the active destination/filter |
| Change mailbox destination | Collapse and clear the card notice before resetting the virtual window |
| Open/close drawer | Preserve expansion |
| Switch to Chat/Spaces/Meet and return to Mail | Preserve the retained Mail body, scroll position, and expansion |

If starring or un-starring removes an expanded message from the active Starred
projection, the derived view must clear stale expansion. The same invariant
applies to archive, trash, or any future filter change.

### Read-state timing

Expansion is a preview action and must not mark a message read. `Open` is the
point that preserves the current "open marks read" behavior. This distinction
also matches the reference image, where an expanded sender and subject can
remain visually emphasized, although the image alone is not authoritative for
read semantics.

### Swipe policy

P0 should retain the existing keyed `Swipe_action` around both collapsed and
expanded content. This preserves archive and mark-read behavior, avoids a
direct-list-child identity change, and lets the existing gesture arena separate
horizontal drag from nested taps.

The current swipe feedback pill uses almost the full host height. On a tall
card that can look oversized even though the interaction remains correct.
Compact-device visual QA must explicitly cover this state. If it is
unacceptable, cap the feedback pill height or add an enabled flag while
retaining the same outer kind and key.

If product review later decides that a tall card must not swipe, add an explicit
enabled flag to `Swipe_action` while retaining the same kind and key. Replacing
the outer native host only in the expanded state is not recommended.

## Outline data model

Use explicit fixture data:

```ocaml
type outline_tone =
  | Default
  | Muted

type outline_node =
  { text : string
  ; tone : outline_tone
  ; children : outline_node list
  }

type message =
  { (* existing fields *)
  ; outline : outline_node list
  }
```

Fixture constraints for P0:

- one or more top-level nodes per message;
- maximum depth of two levels;
- no more than six rendered nodes per message;
- one display line per node with ellipsis overflow;
- stable source order; and
- fictional English text only.

Generated messages should receive a deterministic outline from
`generated_message`; they must not fall back to body parsing. The detail page
continues to render the existing full plain-text `body`. The outline is an
authored summary, not the canonical message body.

For Mara Vale, the intended structure can follow the current fictional body:

```text
Field notes from the north plot
Highlights
  Five young maples are ready for wiring
  Cedar bench needs fresh shade cloth
  Move watering to the summer schedule
Printed notes at the next workshop — Mara
```

The final node may use `Muted`; connector colors and bullet colors derive from
the Bonsai Mail palette.

## Expanded card composition

Render the card as one vertical surface inside the existing swipe host:

1. Outer horizontal inset and small vertical gap.
2. Light-elevation Material card.
3. Header with avatar, sender, subject, timestamp, star, and upward chevron.
4. Divider.
5. Read-only outline body.
6. Optional fixed-height reply scope notice.
7. Divider.
8. Equal Reply and Open footer actions separated by a vertical rule.

Only the non-control part of the header and the chevron collapse the card. The
outline body is inert. Star, Reply, and Open are independent nested controls.
This avoids turning the entire tall card into an ambiguous collapse target.

### Initial metric hypotheses

These values are implementation starting points, not reference-image
specifications:

| Element | Starting range |
| --- | --- |
| Horizontal item inset | 12-16 logical pixels |
| Vertical item gap | 4-8 logical pixels per side |
| Card elevation | 2-4 |
| Header extent | 88-96 logical pixels |
| Outline line extent | 28-32 logical pixels |
| Nested indent | 28-32 logical pixels |
| Connector thickness | 1 logical pixel |
| Footer extent | 56 logical pixels |
| Interactive target | At least 48 by 48 logical pixels |

The exact card extent must be deterministic and computed from the same
constants used by the renderer composition:

```text
expanded_extent =
  outer_vertical_gaps
  + header_extent
  + header_divider
  + outline_vertical_padding
  + flattened_outline_node_count * outline_line_extent
  + optional_notice_extent
  + footer_divider
  + footer_extent
```

Single-line capped outline labels make the computed extent exact. P0 must not
allow unconstrained wrapping inside an extent-constrained virtual item. The
calculation must also include the Material Card's current default margin because
the OCaml Card API does not expose a margin override.

## Sparse-extent virtualization

### Why the existing Virtual_list must remain unchanged

`Native_widget.Virtual_list` is a fixed-extent contract with a stable kind,
version, 29-byte payload, visible-range algorithm, resource identity, and test
surface. Changing kind `1` to a broader version would force unrelated clients
onto new offset behavior and contradict the repository's documented direction
that variable-height lists belong in a separate extension.

Do not replace the endless inbox with core `Widget.list_view`. That would either
mount every loaded row or require fragile manual spacers, losing the current
bounded-window and catch-up guarantees.

### Recommended extension

Add a reusable built-in extension:

```text
Name: Sparse_extent_list
Kind ID: 4
Version: 1
Capabilities: Stateful | Resource | Semantics | Virtualized
Event 1: visible_range_changed
```

The OCaml API should mirror `Virtual_list` and add sparse extent overrides:

```ocaml
type extent_override =
  { index : int
  ; extent : float
  }

val create_with_handler
  :  ?key:Key.t
  -> total_count:int
  -> first_index:int
  -> default_item_extent:float
  -> extent_overrides:extent_override list
  -> ?overscan:int
  -> ?axis:Layout.Axis.t
  -> items:Widget.t list
  -> on_visible_range:Event.Handler.t
  -> unit
  -> Widget.t
```

The mail example supplies either zero overrides or exactly one override for the
logical index of `expanded_id`. An expanded item outside the current OCaml
window still remains in the override set so Flutter can calculate all logical
offsets correctly.

### Typed payload

A compact version-1 payload can use:

```text
u64 total_count
u64 first_index
f64 default_item_extent
u32 overscan
u8  axis
u8[3] reserved_zero
u32 override_count
repeat override_count times:
  u64 logical_index
  f64 extent
```

Both payload decoders must reject:

- a payload whose exact length does not match `override_count`;
- indexes outside `[0, total_count)`;
- unsorted or duplicate override indexes;
- non-finite or non-positive extents;
- an invalid axis or nonzero reserved byte;
- integers that cannot be represented safely on the receiving side.

The payload does not contain the actual child count. The OCaml constructor and
the Flutter registration/factory must therefore validate the supplied child
window against `first_index` and `total_count` when the children are available.

The existing 16-byte visible-range event shape can be reused under kind `4`,
version `1`. The generic core protocol envelope already carries native kind,
version, capabilities, and payload, so this design does not require a change to
`protocol/schema.sexp`.

### Flutter realization

Use `ListView.builder(itemExtentBuilder: ...)` with:

- the override extent for an overridden logical index;
- `default_item_extent` for every other index;
- the current bounded child-window mapping;
- the current keyed `findChildIndexCallback`; and
- a retained `ScrollController` acquired through the native resource store.

This is sparse known-extent virtualization, not self-measuring arbitrary row
height. Flutter receives enough metadata to compute the complete scroll
geometry even though OCaml supplies only a 24-child window.

### Offset and visible-range math

For default extent `d` and sorted overrides `(index, extent)`, define the
leading offset of logical item `k` as:

```text
L(k) = k * d + sum(extent - d for each override whose index < k)
```

Then:

- initial scroll offset is `L(first_index)`;
- first visible index is the greatest `k` where `L(k) <= pixels`;
- last exclusive index is the smallest `k` where
  `L(k) >= pixels + viewport_extent`; and
- all results are clamped to `[0, total_count]`.

Use binary search over logical indexes, with prefix sums over the sorted sparse
overrides. The mail case has at most one override, but the generic contract
should remain correct for more than one.

### Scroll anchoring

Changing an extent above the viewport must not jump unrelated content. For an
ordinary props/window update, use the old first-visible item as the anchor. For
a user-initiated accordion change, prefer the changed override index when its
header is currently visible: use the newly expanded index, or the removed index
for a collapse. This keeps the activated row header at the same viewport
position even when an earlier card collapses in the same update.

Capture:

```text
anchor_index = visible changed override, otherwise old first visible index
intra_item_offset = pixels - L_old(anchor_index)
```

After the new extents are installed, restore:

```text
new_pixels = L_new(anchor_index) + intra_item_offset
```

Clamp the result to the new scroll bounds and apply it after layout. A visible
tapped row therefore keeps its leading edge and grows downward; an offscreen
override change preserves the first-visible viewport anchor. The user can
continue scrolling to reach the footer; automatic scroll-to-top is not required
for P0.

Suppress transient visible-range emission between the extent update and anchor
correction. Otherwise OCaml could briefly advance the 24-row window from a
range that the user never actually saw.

### Expansion animation

Do not emulate size animation in OCaml by publishing per-frame extents. That
would send continuous motion over FFI and repeatedly mutate committed state.

P0 should switch the known extent immediately after existing Pressable
feedback. A later enhancement may interpolate the override locally in the
Flutter `Sparse_extent_list` host, recompute visible ranges from the
interpolated extent, respect reduced-motion settings, and emit only settled
logical range changes.

## Accessibility and semantics

P0 requirements:

- Collapsed row semantics use Button role, the current read/sender label, the
  subject hint, and value `Collapsed`.
- Expanded header semantics use Button role and value `Expanded`.
- Chevron label is `Collapse message from <sender>`.
- Open label is `Open message from <sender>`.
- Reply and star keep independent Button semantics.
- All interactive targets are at least `48 x 48` logical pixels.
- Connector stems, branches, and dots do not create semantic nodes.
- Outline text is traversed in visual source order, with depth included in the
  label or hint when needed.
- Reduced motion leaves all functionality available and removes only optional
  interpolation.

Flutter has a native `expanded` semantics property, but the current OCaml
`Semantics.create` surface at `ocaml/ui/semantics.mli:38-53` does not expose it.
For P0, the explicit `Collapsed`/`Expanded` value exposes deterministic state
text in the semantics tree without widening the core semantics protocol. This
is not equivalent to a native expanded-state flag and must be verified with
VoiceOver. Adding a typed `expanded : bool option` field and expand/collapse
actions is a valuable follow-up, but it is not required to render or operate
this example.

Fixed known extents and one-line outline labels preserve the current list's
layout model. Large accessibility text scales remain a risk because the OCaml
side does not currently calculate text metrics from Flutter's text scale. P0
must test the supported compact-device scaling envelope and avoid silent
overflow; fully self-measuring accessible cards require a broader layout
contract.

## Identity and reconciliation invariants

- Message ID remains the Bonsai assoc key.
- The direct virtual-list child remains the same keyed `Swipe_action` native
  node in collapsed and expanded states.
- Expansion changes the swipe host's content and one sparse extent override; it
  does not change the outer message key.
- Star/read updates do not replace the swipe host.
- Window movement retains overlapping keyed Flutter Elements.
- `Open` creates at most one keyed detail page.
- Matching route pop clears only the selected detail; stale page keys remain
  ignored.
- If an expanded ID is not present in the active message projection, the
  effective expansion is `None` and the override list is empty.

## Test strategy

### Baseline verified during research

The following current tests passed before any implementation work:

```sh
dune exec ./ocaml/test/mail_example_tests.exe
```

From `flutter/packages/bonsai_flutter`:

```sh
flutter test \
  test/virtual_list_test.dart \
  test/pressable_test.dart \
  test/swipe_action_test.dart
```

The Flutter command completed 27 tests successfully. These checks introduced no
source changes.

### Required future coverage

| Layer | Coverage |
| --- | --- |
| OCaml native-widget contract | Sparse payload round trip, exact-length validation, sorted/unique indexes, bounds, finite extents, event filtering, and handler constructor |
| Flutter native-widget host | Empty and single override, multiple sparse overrides, range math before/inside/after a tall item, fast catch-up, initial offset, anchor preservation, bounded mounts, retained overlapping Element, and disposal |
| OCaml mail behavior | Initial collapsed rows, row-tap expansion without route/read change, accordion replacement, collapse, explicit outline order/depth, star isolation, swipe behavior, Reply notice, Open-to-detail, read timing, Back restoration, stale expansion cleanup, pagination, and rapid-tap deduplication |
| Pressable/swipe widget tests | Nested star/Reply/Open wins taps; horizontal drag cancels header press; pointer cancel emits no action; reduced motion remains functional |
| Real OCaml/Flutter FFI | Expand a visible row, verify no detail, Open it, edge-Back to the same card, expand a lower paged row, retain offset, swipe a card, switch app destinations, and restore Mail |
| Physical Profile | Repeated expand/collapse/Open/Back while paging, bounded mounted nodes, stable offset, and no repeatable post-warmup jank |
| Visual QA | Compact iPhone-size capture compared for hierarchy, spacing, clipping, footer reachability, and original Bonsai styling |

Existing direct-press-to-detail assertions must be rewritten, not duplicated:

- `ocaml/test/mail_example_tests.ml:238-290` currently expects one row press to
  mark read and open detail.
- `ocaml/test/mail_example_tests.ml:748-760` currently treats rapid Pressable
  activation as detail activation.
- `flutter/integration_test/test/mail_expansion_ffi_test.dart:103-122`
  currently taps `Juniper Works` once and expects detail.
- `flutter/integration_test/test/mail_ffi_test.dart:121-143` has the same
  one-tap route expectation in the lower-level FFI flow.
- `flutter/integration_test/integration_test/mail_profile_test.dart` has a
  one-tap detail helper that must become expand-then-Open.

## Expected implementation impact

### Application and documentation

| File | Expected work |
| --- | --- |
| `examples/mail/ocaml/mail.ml` | Outline types/fixtures, `expanded_id`, derived expanded logical index/extent, compact/card render paths, expansion/Open/Reply handlers, and stale-state cleanup |
| `examples/mail/README.md` | Document row expansion, outliner card, Open semantics, read timing, and retained Back behavior |
| `docs/virtual-lists.md` | Document the new sparse-known-extent extension and retain the fixed-list limitation |
| `docs/custom-widgets.md` | Add kind `4` to the built-in native-widget summary if that summary remains exhaustive |

`examples/mail/ocaml/mail.mli`, Flutter `main.dart`, and native embed entrypoints
do not need a public or runtime change unless additional testing helpers are
intentionally exposed.

### Native list implementation

| File | Expected work |
| --- | --- |
| `ocaml/ui/native_widget.ml` | Typed kind-4 contract, validation, encoding, event decoding, direct callback and raw-handler constructors, and testing decoder |
| `ocaml/ui/native_widget.mli` | Public `Sparse_extent_list` API and `For_testing` props |
| `flutter/packages/bonsai_flutter/lib/src/native_widget/sparse_extent_list.dart` | Kind-4 props codec, extent math, host, retained controller, and registration function |
| `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart` | Add the shared kind-4 constant, or move native kind constants to a neutral shared file without changing kind-1 behavior |
| `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart` | Import and register kind `4` in the standard built-in registry |
| `flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart` | Export the sparse-list contract for tests and consumers |

The native extension envelope is already sufficient. No change is expected in
`protocol/schema.sexp`, generated core protocol fixtures, `spec/`, or dune
files.

### Tests

| File | Expected work |
| --- | --- |
| `ocaml/test/native_widget_tests.ml` | Kind-4 contract and handler tests |
| `flutter/packages/bonsai_flutter/test/virtual_list_test.dart` | Sparse extent and anchoring tests, or equivalent adjacent test file |
| `ocaml/test/mail_example_tests.ml` | New expansion state machine and updated Open assertions |
| `flutter/integration_test/test/mail_expansion_ffi_test.dart` | Full inline-card FFI flow |
| `flutter/integration_test/test/mail_ffi_test.dart` | Keep core mail detail/actions compatible with the new two-step entry |
| `flutter/integration_test/integration_test/mail_profile_test.dart` | Expand/Open interactions in physical profile coverage |

## Rejected alternatives

| Alternative | Reason rejected |
| --- | --- |
| Render the card inside the existing fixed `Virtual_list` | Flutter constrains it to `88` pixels and range math remains wrong |
| Upgrade kind `1` in place | Broadens a deliberately fixed contract and risks unrelated clients/resources |
| Replace the inbox with core `Widget.list_view` | Loses bounded mounting, logical catch-up, and endless-feed guarantees |
| Render the card as an overlay | Covers later rows instead of pushing them, breaks logical order and accessibility |
| Move expansion to Flutter-local state | Duplicates application state and makes reconciliation/route tests nondeterministic |
| Parse `body` bullet characters | Cannot reliably recover hierarchy, tone, or fixture constraints |
| Use a Flutter `ExpansionTile` native widget | Moves selection state and mail-specific rendering across the ownership boundary |
| Allow multiple expanded cards | Requires multiple overrides, increases scroll instability, and is not supported by the reference |
| Add per-frame OCaml size animation | Sends continuous motion over FFI and mutates committed state for presentation detail |

## Acceptance criteria

- The initial mail view retains the current search header, drawer, bottom bar,
  endless paging, and compact rows.
- Tapping the non-star content of any visible collapsed row expands that exact
  message inline and does not create a detail page.
- Expansion alone does not change read, starred, or mailbox state.
- At most one card is expanded; tapping a different row atomically switches the
  expanded message.
- Tapping the expanded header or chevron collapses the card.
- The card remains at the message's logical list index and pushes later rows
  down; it is not an overlay.
- The card header preserves avatar, sender, subject, timestamp, read emphasis,
  star state, and a collapse affordance.
- Every curated and generated message has deterministic outline data.
- Outline nodes render in stable depth-first source order with at most one
  nested child level.
- Connector lines and bullets communicate hierarchy visually without becoming
  meaningless accessibility nodes.
- Reply either shows the existing scope notice or is omitted; it is never a
  silent no-op.
- Open is an independent button and is the only card action that selects the
  detail route.
- Open marks the correct message read and creates exactly one existing
  `mail-detail-<id>` page.
- Back returns to the same expanded card and retained list offset.
- Star, Reply, Open, collapse, vertical scroll, horizontal swipe, pointer
  cancel, drawer gestures, and interactive Back do not cross-activate.
- Swipe archive clears expansion for the target; swipe read/unread keeps the
  card expanded.
- Mailbox changes and filter removal cannot leave a stale extent override.
- Switching to a retained non-Mail app destination and back preserves Mail
  expansion and scroll position.
- The direct keyed swipe host and overlapping virtual-window Elements retain
  identity across expansion, state updates, and paging.
- Sparse visible-range reporting is correct before, inside, and after the tall
  card.
- The mounted Flutter/OCaml row count remains bounded by the supplied window,
  not total loaded messages.
- All interactive targets are at least `48 x 48` logical pixels and expose
  unambiguous labels and collapsed/expanded values.
- Compact-device rendering has no overflow, clipped footer, nested scroll trap,
  or card shadow cut off by insufficient item extent.
- No mail reducer, message model, route state, or expansion state is added to
  Dart.
- No files under `spec/` and no dune files are modified.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Wrong extent clips the footer or leaves excess space | Derive extent from shared layout constants and capped flattened node count; test every fixture |
| Extent change jumps content | Anchor a visible activated override; otherwise preserve the logical first-visible item and intra-item offset |
| Range reporting loads too early or late | Use `L(k)` binary-search math and test boundaries around the override |
| Expanded rendering replaces the outer row host | Keep the keyed `Swipe_action` as the direct sparse-list child |
| Nested controls also trigger collapse | Restrict collapse Pressable to non-control header content and test gesture-arena outcomes |
| Reply grows the card unexpectedly | Use a fixed notice extent included in the override formula, or omit Reply from P0 |
| Large text scale overflows fixed known extents | Cap lines, test the supported scale envelope, and document the self-measuring-layout limitation |
| A stale expanded ID survives a filter mutation | Derive effective expansion from the active projection and clear it on destructive/destination actions |
| New native list grows into a second general list framework | Keep its contract narrow: fixed default extent plus validated sparse known overrides |
| Visual work expands into exact screenshot cloning | Use original Bonsai palette/content and treat all metrics as tuning hypotheses |

## Recommended implementation order

1. Add failing OCaml and Flutter tests for the sparse extent contract and
   visible-range math.
2. Implement `Sparse_extent_list` kind `4` and prove bounded identity plus
   scroll anchoring independently of Mail.
3. Add failing mail tests for row-tap expansion, no read change, accordion
   replacement, and Open-to-detail.
4. Add explicit outline fixtures, `expanded_id`, card rendering, and handlers
   in `mail.ml` while retaining the outer swipe host.
5. Update real-FFI and profile flows to expand before Open.
6. Perform compact-device visual/accessibility QA and tune deterministic
   metrics without changing the state model.
7. Update example and virtual-list documentation.

No implementation should begin by editing `spec/` or dune files. The proposed
contract fits the existing typed native-widget extension mechanism.

## Recommended defaults pending product review

- One expanded card at a time.
- Expansion does not mark read; Open does.
- Back preserves the card and scroll position.
- Expanded cards retain swipe actions.
- All messages receive explicit outline fixtures.
- Outline nodes are display-only and not individually collapsible.
- Reply displays the existing out-of-scope notice; no compose UI is added.
- Attachments remain on the detail page; an outline node may mention an
  attachment, but the card does not render the attachment tile.
- P0 expansion is immediate after Pressable feedback; animation is deferred.
- Current Material Card shape is acceptable for "similar" visual scope.

## Sources

### Local sources

- User-provided reference image in this request.
- `examples/mail/ocaml/mail.ml`
- `examples/mail/README.md`
- `ocaml/ui/native_widget.ml`
- `ocaml/ui/native_widget.mli`
- `ocaml/ui/widget.mli`
- `ocaml/ui/material.mli`
- `ocaml/ui/semantics.mli`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/swipe_action.dart`
- `flutter/packages/bonsai_flutter/lib/src/renderer/pressable_host.dart`
- `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`
- `ocaml/test/mail_example_tests.ml`
- `flutter/packages/bonsai_flutter/test/virtual_list_test.dart`
- `flutter/integration_test/test/mail_expansion_ffi_test.dart`
- `docs/virtual-lists.md`
- `docs/custom-widgets.md`
- `docs/agent-guide/002-mail-client-example_report.md`
- `docs/agent-guide/003-mail-interactions.md`
- `docs/agent-guide/009-mail-inbox-expansion_report.md`

### Official Flutter sources

- [ListView.itemExtentBuilder](https://api.flutter.dev/flutter/widgets/ListView/itemExtentBuilder.html)
- [ListView.builder](https://api.flutter.dev/flutter/widgets/ListView/ListView.builder.html)
- [SliverVariedExtentList](https://api.flutter.dev/flutter/widgets/SliverVariedExtentList-class.html)
- [SemanticsProperties.expanded](https://api.flutter.dev/flutter/semantics/SemanticsProperties/expanded.html)
- [AnimatedSize](https://api.flutter.dev/flutter/widgets/AnimatedSize-class.html)
