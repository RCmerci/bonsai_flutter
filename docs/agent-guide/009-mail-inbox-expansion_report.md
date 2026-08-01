# Mail Inbox Growth and Navigation Research

## Document status

| Field | Value |
| --- | --- |
| Date | 2026-08-01 |
| Status | Research only; no implementation is included in this change |
| Target | `examples/mail` |
| Primary platform | Compact iPhone-style layout |
| Product reference | Current Gmail for iOS, without Gmail branding or content |
| Framework baseline | Flutter 3.44.8, revision `058e0af2c2` |
| Related documents | `002-mail-client-example_report.md`, `003-mail-interactions.md` |

## Confirmed request interpretation

This report uses the following concrete meanings for the requested behavior.

- **Infinite mail list** means a user-perceived unbounded feed that loads
  deterministic local pages for as long as the session continues. It does not
  mean allocating an infinite collection or mounting every generated row.
- **Load while scrolling down** means advancing toward older messages at the
  lower end of the inbox. Pull-to-refresh at the top is a separate Gmail
  behavior and is not part of this request.
- **Left-edge swipe** means a drag that starts at the leading screen edge and
  moves inward. In an LTR compact layout, the physical motion is from the left
  edge toward the right. RTL mirrors both the edge and direction.
- On a **detail page**, that leading-edge gesture continues to perform the
  existing interactive Back action.
- On the root **mail list page**, the same leading-edge gesture opens a
  Gmail-style **Navigation Drawer**. This is the confirmed product behavior,
  not an unresolved interpretation.
- The gesture does not navigate directly to Settings. Settings is one regular
  destination inside the Navigation Drawer, alongside the mailboxes.
- **Bottom Navigation Bar** means app-level destinations. Mailboxes, labels,
  and Settings remain in the drawer so the two navigation surfaces do not
  duplicate the same hierarchy.
- Its concrete destinations follow the current four-item Gmail iOS reference:
  Mail, Chat, Spaces, and Meet. The latter three are explicit local scope
  placeholders in this mail-only example.

These interpretations follow the named Gmail iOS reference. A literal
leftward drag starting at the physical left edge cannot reveal a left-side
drawer; leftward motion closes an already-open drawer in LTR.

## Decision summary

1. Replace the fixed all-children inbox with the existing fixed-extent
   `Native_widget.Virtual_list` and a bounded keyed OCaml item window.
2. Model endless scrolling as deterministic local pagination: load 20 messages
   per page, prefetch near the end, show an inline indeterminate spinner, and
   use a testable Bonsai clock delay with one request in flight.
3. Keep the route-scoped gesture split explicit: detail leading edge means
   Back; root inbox leading edge means open the Navigation Drawer; horizontal
   drags that start outside the edge zone remain mail-row swipe actions.
4. Prefer a reusable typed native Navigation Shell over changing the main
   frame protocol for this example. Flutter should own drawer tracking,
   settling, scrim, and retained destination bodies; OCaml should own settled
   drawer state and selected destinations.
5. Add a reusable Flutter-local Pressable host around the existing custom mail
   row. It should expose an immediate pressed state, cancel cleanly when scroll
   or swipe wins, and emit one activation only after the feedback has been
   visible.
6. Use the four destinations visible in the current official Gmail iOS
   screenshots as the reference baseline: Mail, Chat, Spaces, and Meet. Mail is
   functional; the other destinations must render explicit local-only scope
   placeholders unless their product scope is expanded later. They must not be
   dead controls.
7. Keep data, paging state, mailbox state, selected destinations, and route
   state in OCaml/Bonsai. Keep pointer deltas, scroll controllers, drawer
   progress, pressed progress, and animation frames in Flutter.

## Evidence and limitations

### Evidence classification

| Finding | Classification | Planning consequence |
| --- | --- | --- |
| The current official Gmail iOS listing shows a left overlay drawer with a scrim and selected mailbox state. | Official visual evidence | Use an overlay Navigation Drawer rather than a permanently visible side rail on compact layouts. |
| Gmail Help places inboxes, categories, labels, and Settings behind the top-left Menu entry. | Official behavior | Keep mailbox-level navigation and Settings in the drawer. |
| The current official Gmail iOS listing shows Mail, Chat, Spaces, and Meet in a bottom bar. | Official visual evidence | Use those four labels as the reference app-level hierarchy. |
| Gmail Help says Chat and Meet availability can depend on settings, account type, or administrator policy. | Official behavior | Treat the four-item demo configuration as a chosen reference state, not a universal Gmail layout. |
| The Gmail API uses `pageToken` and `nextPageToken` for message pagination. | Official API behavior | Model simulated loading with a cursor/page state rather than one prebuilt giant list. |
| Gmail Help documents a short refresh indicator for top pull-to-refresh. | Official behavior | Do not conflate top refresh with bottom append-loading. |
| Gmail does not publish its iOS inbox prefetch threshold, append delay, spinner geometry, pressed opacity, or press-to-route delay. | Research limitation | Treat all numeric loading and press values below as implementation hypotheses. |
| Public Gmail documentation confirms the drawer and Menu button but does not specify its iOS edge-drag recognizer. | Research limitation | Use the maintained Flutter `Scaffold.drawer` gesture as the implementation baseline, not as a claim about Gmail internals. |
| Flutter `ListView.builder` is intended for large or infinite lists, and `Scaffold.drawer` provides a maintained mobile edge gesture. | Official Flutter behavior | Reuse maintained lazy-list and drawer behavior instead of sending continuous motion over FFI. |
| Material `InkWell` and `ListTile` provide pressed ink feedback, but ink can be hidden by an opaque decoration between the Material and the response. | Official Flutter behavior | The existing custom opaque mail-row surface needs a deliberate visible state layer or a renderer primitive that paints above it. |

### Reference boundaries

The official App Store screenshots are suitable for confirming composition and
navigation hierarchy. They do not prove gesture recognition, loading, or press
timing. This report therefore reuses these visually supported ideas only:

- a modal left drawer for mailboxes, labels, and Settings;
- a distinct bottom surface for app-level destinations; and
- Mail, Chat, Spaces, and Meet as one current four-item reference state.

Continuous access to older mail and visible row feedback come from the user
request. Their loading threshold, simulated delay, pressed state, and
press-to-route timing below are implementation hypotheses informed by Flutter,
Material, and Apple platform guidance, not observed Gmail behavior.

The report does not claim pixel parity, exact Gmail motion curves, exact
thresholds, or Gmail source-level behavior.

## Repository findings

### Existing application boundary

The current example already follows the intended ownership boundary:

- `examples/mail/ocaml/mail.ml` owns the message model, read/star/mailbox
  state, selected message, handlers, page list, and route-pop validation.
- `examples/mail/flutter/lib/main.dart` is a mechanical runtime shell.
- Flutter already owns the Cupertino page interpolation and the continuous
  row-swipe interaction.

The new behavior should preserve this split. Dart must not gain a second mail
model, paging cursor, selected mailbox, or route reducer.

### Current inbox limitations

The mail example currently has twelve fixed messages in
`examples/mail/ocaml/mail.ml:69`. The inbox uses an inert scroll handler and
passes every visible message row to `Widget.list_view` at
`examples/mail/ocaml/mail.ml:575`.

Flutter realizes that node with `ListView(children: children)` in
`flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart:506`.
That constructor is appropriate for a small collection, but every logical
child remains represented as the list grows.

State updates also scan the complete message list:

- `update_message` uses `List.map` at `examples/mail/ocaml/mail.ml:238`;
- `find_message` uses `List.find_opt` at line 247; and
- the visible inbox uses `List.filter` at line 931.

Appending forever to the current representation would grow OCaml computation,
frame size, reconciliation work, and Flutter child storage. It is not an
acceptable infinite-list design.

### Existing virtual-list fit

The repository already has `Native_widget.Virtual_list`:

- its public OCaml API is in `ocaml/ui/native_widget.mli:55`;
- its Flutter host uses `ListView.builder` in
  `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart:237`;
- it emits typed visible-range events instead of per-pixel scroll events; and
- its widget test proves a 50,000-item logical list with a 20-item supplied
  window in
  `flutter/packages/bonsai_flutter/test/virtual_list_test.dart:6`.

The prototype requires one fixed item extent. Current mail rows are already
fixed at 88 logical pixels in `examples/mail/ocaml/mail.ml:441`, so the example
is a strong fit.

One API gap must be addressed before the example can schedule a Bonsai load
effect safely. `Virtual_list.create` accepts a direct
`visible_range -> unit` callback. Follow the existing `Swipe_action` pattern:
add both a raw-handler `create_with_handler` constructor and a public
`visible_range_of_payload` decoder. The example can then use
`Driver.Handler.create` to validate the native payload and schedule state
changes plus a clock sleep through the runtime. Merely adding the constructor
would be insufficient, because the private typed extension cannot currently be
passed to `Driver.Handler.create_native`.

### Navigation and pressed-state gaps

The current `Material.scaffold` protocol accepts only an optional app bar and a
body:

- `ocaml/ui/material.mli:3` exposes no drawer or bottom-navigation slot; and
- the Flutter renderer accepts only one or two children at
  `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart:804`.

The generic `Widget.gesture` supports taps but no horizontal drag updates. Its
Flutter renderer uses a plain `GestureDetector`, so the custom mail row has no
local state layer, ink, or button-like feedback before its tap event opens the
detail route.

The existing detail route already uses `Navigation.Slide` and a
`CupertinoPage`, so interactive leading-edge Back does not need to be
reimplemented.

## Product behavior specification

### Endless inbox and append-loading

#### User-visible behavior

1. The inbox initially exposes 20 deterministic fictional messages.
2. Scrolling toward older messages remains smooth and interactive.
3. When the visible range is within approximately one compact viewport of the
   loaded tail, the application begins loading the next page if no load is
   already in flight.
4. Loading adds one 88-logical-pixel footer row containing a small centered
   indeterminate circular progress indicator and the semantic label
   `Loading more messages`.
5. Existing mail remains visible, scrollable, and actionable during the
   simulated delay. No full-screen loading overlay is shown.
6. After a baseline 750 millisecond logical delay, 20 new deterministic
   messages replace the footer and extend the scroll extent.
7. The current scroll offset and every overlapping keyed row remain stable.
   The list does not jump to the top or visibly flash an empty window.
8. The session always reports another page. Reaching the loaded tail repeatedly
   continues the same state machine without an end-of-list message.

The 20-item page size, one-viewport prefetch distance, and 750 millisecond delay
are initial hypotheses. Device tuning may choose values in the following
ranges without presenting them as Gmail specifications:

| Parameter | Baseline | Tuning range |
| --- | --- | --- |
| Initial page size | 20 messages | 16 to 24 |
| Append page size | 20 messages | 16 to 24 |
| Prefetch distance | One compact viewport | 6 to 10 rows |
| Simulated delay | 750 ms | 600 to 900 ms |
| Supplied OCaml window | 24 rows | 20 to 32 rows |
| Virtual-list overscan | 4 rows per direction | 3 to 6 rows |

#### State machine

```text
Idle(cursor, loaded_count)
  | visible range reaches the prefetch boundary
  v
Loading_more(generation, cursor, loaded_count)
  | Bonsai logical sleep completes for the active generation
  v
Idle(next_cursor, loaded_count + page_size)
```

Repeated visible-range notifications while `Loading_more` must be ignored.
Every completion must carry or close over a generation token so a stale timer
cannot append the same page twice.

#### Data and identity

Generated messages must remain fictional and deterministic. A logical page and
offset must always produce the same stable message ID and content. IDs cannot
reuse the original template ID because the same ID is used for:

- Bonsai child keys;
- native swipe and press host identity;
- deterministic test IDs;
- avatar color selection; and
- detail page keys.

The simplest acceptable demo model may retain loaded message records for the
current session, while the rendered tree remains bounded to the supplied
virtual window. If later profiling shows model scans becoming material, replace
the message list with an ordered ID collection plus an ID-indexed override map;
do not move the source of truth into Flutter.

Top pull-to-refresh is explicitly separate. If added later, it must use its own
`refreshing` state and must not reset or impersonate the append cursor.

### Route-scoped leading-edge gesture

The same physical leading-edge motion has different behavior because the
active route provides different context.

| Active surface | LTR start zone and motion | Result |
| --- | --- | --- |
| Mail detail page | Left edge, drag right | Existing interactive Back; reveal and return to the inbox |
| Root Mail inbox | Left edge, drag right | Track and reveal the Navigation Drawer |
| Root Mail inbox row, outside edge zone | Horizontal drag in either direction | Existing Archive or Mark read/unread row action |
| Open drawer | Drag left, tap scrim, or use Back | Close the drawer without changing the current mailbox |

RTL mirrors the physical edge and motion while preserving leading-edge
semantics.

The root drawer edge zone should follow Flutter's maintained Scaffold behavior:
20 logical pixels plus the leading safe-area padding. The detail route keeps
the existing Cupertino Back recognizer, whose leading zone is the greater of
20 logical pixels and the leading safe-area padding. These formulas are not
interchangeable. The drawer must be placed inside the root list page, below the
detail page in the existing Navigator. This hierarchy makes the top detail
route own hit testing while it is visible, so the drawer cannot steal the Back
gesture.

On the compact target, `screen edge` means the physical app viewport edge. The
current example centers a surface up to 720 logical pixels wide. Wide-screen
drawer behavior is deferred; if retained on macOS or tablet, the leading edge
of the constrained app surface is the practical gesture boundary rather than
the edge of an external monitor.

### Navigation Drawer

#### Open and close behavior

- The drawer tracks the finger one-to-one while a valid edge gesture is
  active, with the scrim opacity following open progress.
- Release uses the maintained Flutter distance and velocity decision to open
  or settle closed.
- A visible Menu button remains available in the search header. Edge gestures
  must not be the only discoverable or accessible entry point.
- Tapping the scrim, invoking system Back, or swiping toward the leading edge
  closes the drawer.
- While open, the scrim blocks inbox taps, mail-row swipes, and star actions.
- Per-frame drawer deltas never cross FFI. Flutter emits only a settled
  open/closed event and OCaml synchronizes the committed state.

#### Drawer content

Use original Bonsai Mail identity and local data. A minimal useful drawer is:

1. Bonsai Mail header and fictional account marker.
2. Inbox, selected initially.
3. Starred.
4. Archived.
5. Trash.
6. Settings, anchored after the mailbox destinations.

Inbox, Starred, Archived, and Trash can derive from the existing message
model. Settings may show an explicit local scope placeholder until actual
settings are requested. Selecting an item updates the OCaml mailbox view,
closes the drawer, and then exposes the selected content. It must not silently
perform a no-op.

### Mail-row pressed feedback

The pressed response must be observable before the detail route takes over.

1. Pointer down on the non-star row area immediately shows a low-emphasis
   neutral state layer across the clipped row.
2. The state layer may include a subtle touch-origin response, but a clear
   pressed overlay is the required behavior.
3. A valid pointer up keeps the response visible for at least one rendered
   frame, then emits exactly one activation to OCaml and opens the detail.
4. If a full runtime round trip still makes the response imperceptible, use an
   initial 80 millisecond release delay. Do not exceed 100 milliseconds without
   device evidence because navigation should remain immediate.
5. A vertical scroll, horizontal row swipe, pointer cancel, or winning nested
   star action cancels the row press and emits no activation.
6. Rapid repeated taps while activation is pending cannot push duplicate detail
   pages.
7. Reduced-motion mode may remove the release fade, but pointer-down feedback
   and one activation remain available.

The exact color opacity and duration are design hypotheses. Use an original
neutral color derived from the Bonsai Mail theme, not Gmail brand red.

### Bottom Navigation Bar

The current official Gmail iOS screenshots show four app-level destinations.
Use that hierarchy as the reference configuration:

| Destination | Initial example behavior |
| --- | --- |
| Mail | Functional; shows the retained Mail inbox and its drawer |
| Chat | Local placeholder explaining that Chat is outside this mail demo |
| Spaces | Local placeholder explaining that Spaces is outside this mail demo |
| Meet | Local placeholder explaining that Meet is outside this mail demo |

The placeholder approach keeps the requested bar deterministic without
expanding the example into real chat or meeting products. It is the adopted
scope for this report rather than an optional omission path.

Additional behavior:

- Mail is selected initially.
- The bar is fixed above the bottom safe area and never scrolls with the inbox.
- The selected destination uses an original tonal indicator, distinct icon,
  label, and selected semantics.
- Re-selecting the active destination does not push another route. A later
  enhancement may use a second Mail tap to scroll the inbox to the top.
- Switching to a placeholder retains loaded messages, mail state, and inbox
  scroll position for the return to Mail.
- The drawer is available only for the Mail destination.
- The bar remains on app-level surfaces. A pushed message detail page covers or
  hides it, matching the principle that bottom navigation is not used inside a
  single-email reading flow.
- Every destination exposes an accessibility label and a minimum 48 by 48
  logical-pixel touch target.

## Gesture arbitration

Gesture ownership must be decided entirely from the pointer start location,
active route, and gesture arena. It must not wait for an OCaml frame.

Priority on a compact LTR device:

1. If a detail route is topmost and a drag starts in the existing Cupertino
   leading zone, `max(20 logical pixels, leading safe-area padding)`, the Back
   recognizer owns the interaction.
2. Otherwise, if the root Mail inbox is topmost and a drag starts in the
   Scaffold drawer zone, `20 logical pixels + leading safe-area padding`, the
   drawer recognizer owns the interaction.
3. Otherwise, a horizontal drag on a mail row belongs to `Swipe_action`.
4. A predominantly vertical drag belongs to the virtual list.
5. A nested star press wins over the row Pressable tap recognizer.
6. A row activation is emitted only if no drag or nested control has won.

Drawer-open state blocks all background gesture candidates until the drawer is
closed.

## Recommended architecture

### Logical tree

```text
Navigator
  Page("mail-list", can_pop = false)
    Native_widget.Navigation_shell
      Indexed destination bodies retained by Flutter
        Mail body
          search header and Menu button
          Native_widget.Virtual_list
            keyed Swipe_action rows
              Native_widget.Pressable row content
            optional loading footer
        Chat placeholder
        Spaces placeholder
        Meet placeholder
      drawer content
      bottom navigation content
  Page("mail-detail-<id>", transition = Slide)
    existing detail scaffold
```

Putting the Navigation Shell inside the list page is the key route boundary.
When a detail page is present, the existing Cupertino route covers the shell
and owns the leading edge. When detail is absent, the shell exposes the drawer
edge recognizer.

### Ownership table

| Concern | Owner |
| --- | --- |
| Loaded messages, cursor, load generation, loading status | OCaml/Bonsai |
| Supplied virtual window and stable message IDs | OCaml/Bonsai |
| Read, starred, mailbox, archived, and trashed state | OCaml/Bonsai |
| Selected app destination and drawer mailbox destination | OCaml/Bonsai |
| Settled drawer open/closed state | OCaml/Bonsai, synchronized from one typed event |
| Selected detail message and page list | OCaml/Bonsai |
| Virtual-list `ScrollController` and visible-range observation | Flutter |
| Indeterminate spinner frames | Flutter |
| Drawer drag, scrim progress, velocity decision, and settle | Flutter |
| Pressed state, cancel arbitration, and short release feedback | Flutter |
| Cupertino Back progress | Flutter |
| Row swipe progress, haptics, and settle | Flutter |

### Typed event boundary

Only discrete events cross Flutter to OCaml:

- virtual-list visible range changed;
- Navigation Drawer settled open or closed;
- mail row activated;
- bottom destination pressed;
- drawer destination pressed;
- row swipe committed; and
- detail route popped.

Pointer deltas, animation ticks, spinner ticks, and drawer progress remain
renderer-local.

### Proposed OCaml model additions

```ocaml
type load_state =
  | Idle
  | Loading_more of
      { generation : int
      ; cursor : int
      }

type app_destination =
  | Mail
  | Chat
  | Spaces
  | Meet

type mail_destination =
  | Inbox_view
  | Starred_view
  | Archived_view
  | Trash_view
  | Settings_view

type state =
  { messages : message list
  ; next_cursor : int
  ; load_state : load_state
  ; window_first : int
  ; selected_app_destination : app_destination
  ; selected_mail_destination : mail_destination
  ; drawer_open : bool
  ; selected_id : int option
  ; notice : string option
  }
```

The exact representation may change after profiling. The invariants matter:
one active cursor, one in-flight generation, unique IDs, a bounded rendered
window, and no duplicate application state in Dart.

## Proposed reusable capability additions

### Effect-friendly Virtual List handler

Add `Virtual_list.create_with_handler` and
`Virtual_list.visible_range_of_payload` APIs parallel to the raw-handler path
used by `Swipe_action`. They should reuse the existing props, internal event
decoder, kind ID, version, and Flutter host. The example uses
`Driver.Handler.create`, then validates each payload through
`visible_range_of_payload` before scheduling the effect. This is an OCaml API
completion, not a new wire format.

An alternative is to expose the typed Virtual List extension and use
`Driver.Handler.create_native`, but that would widen the public extension API.
Do not combine `create_with_handler` with `create_native` unless that typed
extension is intentionally exposed.

### Typed Navigation Shell

Add a generic built-in native extension that:

- receives retained destination bodies, one drawer child, and one bottom-bar
  child;
- selects a body with Flutter `IndexedStack` or equivalent retained layout;
- uses a real Flutter `Scaffold` and `Drawer` for maintained edge, scrim, Back,
  safe-area, and lifecycle behavior;
- accepts the selected body and requested drawer-open state as typed props;
- enables the drawer only for configured destinations;
- emits one typed settled drawer event; and
- disposes controllers and ignores late completion after node drop.

This avoids expanding the main `Material_scaffold` protocol solely for the
example. A future project-wide Material API may later promote drawer and
bottom-navigation slots into the core protocol after broader design review.

### Typed Pressable

Add a generic one-child Pressable native extension that:

- owns tap-down, tap-up, tap-cancel, pressed state, and optional short release
  delay locally;
- paints a clipped state layer above opaque child decoration;
- emits exactly one typed activation;
- cooperates with an ancestor row swipe, a descendant star control, and a
  surrounding vertical scrollable;
- exposes one accessible tap action without duplicating child semantics; and
- retains state only while its keyed node is alive.

Reusing a generic Pressable is preferred to putting mail-specific animation
state in Dart. Replacing the current row with `Material.list_tile` is a viable
prototype, but its present protocol lacks the padding, height, tile color, and
shape controls needed to preserve the existing 88-pixel three-line layout.

## Alternatives considered

| Option | Decision | Reason |
| --- | --- | --- |
| Append forever to the current `Widget.list_view` | Reject | It retains every logical child and scales reconciliation and state scans with the session length. |
| Preallocate a huge or `max_int` mail collection | Reject | It is not meaningful infinity and creates avoidable model and identity problems. |
| Reuse `Native_widget.Virtual_list` | Accept | It already provides a fixed-extent, bounded keyed window and typed visible ranges. |
| Detect the tail from the current scroll event | Reject as primary design | The event has pixels and delta but no max extent, and the normal list still retains all rows. |
| Extend the main `Material_scaffold` wire schema now | Defer | It is reusable but changes the cross-language core protocol, codecs, fixtures, and all scaffold tests. |
| Add a typed native Navigation Shell | Accept | It contains continuous native navigation behavior and retained bodies without a main protocol revision. |
| Replace the custom row directly with `ListTile` | Defer | It gives ink feedback but risks layout, unread-surface, nested-star, and fixed-extent regressions. |
| Send pointer down/up through OCaml to animate the row | Reject | Visible touch feedback and cancellation must not wait for an FFI frame. |
| Add one selected Mail item to a bottom bar | Reject | A one-destination bar has no navigation purpose. |
| Duplicate Inbox, Starred, and Trash in both drawer and bottom bar | Reject | It collapses app-level and mailbox-level hierarchy into redundant controls. |

## Future testing strategy

Implementation must follow test-driven development. Record the green baseline,
add each behavior assertion, observe the intended failure, and then implement
the smallest behavior that passes.

### Automated coverage matrix

| Layer | Primary file | Required new coverage |
| --- | --- | --- |
| OCaml mail behavior | `ocaml/test/mail_example_tests.ml` | Load threshold, one in-flight generation, logical-time delay, three sequential pages, unique IDs, loading semantics, stable overlap identity, drawer selection, destination selection, preserved mail state, and unchanged detail actions |
| OCaml native contracts | `ocaml/test/native_widget_tests.ml` | Virtual-list handler path, Navigation Shell props/events, Pressable props/activation, malformed payload rejection, version filtering, and child-count validation |
| Flutter Virtual List | `flutter/packages/bonsai_flutter/test/virtual_list_test.dart` | Rapid range changes, prefetch window movement, no blank visible slot, retained offset, bounded mounted hosts, and repeated-props stability |
| Flutter Navigation Shell | New focused widget test | Edge tracking, cancel, commit, Menu open, scrim close, Back close, detail/root guard, row-swipe arbitration, RTL, reduced motion, retained bodies, semantics, rebuild, and disposal |
| Flutter Pressable | New focused widget test | Down-state visibility before event, one activation, minimum visible feedback, cancel on vertical/horizontal drag, nested-star isolation, rapid taps, RTL independence, reduced motion, rebuild, semantics, and disposal |
| Flutter bottom bar composition | New or existing renderer test | Fixed placement, safe-area inset, selected state, touch targets, semantic labels, one event per press, no duplicate push, and deterministic placeholders |
| Real OCaml/Flutter FFI | `flutter/integration_test/test/mail_ffi_test.dart` | Scroll to prefetch, see loading, advance logical time, retain offset, open detail after press feedback, edge-pop detail, edge-open drawer on root, close drawer, and switch/restore a bottom destination |
| Physical Profile | `flutter/integration_test/integration_test/mail_profile_test.dart` | Sustained virtual scroll/load, drawer cancel/commit, press-to-detail, bottom switch, and no repeatable post-warmup jank |

### Critical assertions

#### Endless list

- Three consecutive append cycles complete without an end sentinel.
- Each cursor starts at most one load and appends exactly one page.
- The loading indicator appears in the next presentable frame and remains
  semantically announced without blocking the inbox.
- Existing offset and overlapping Flutter `Element` identity remain stable.
- Retained virtual-list item roots identified by their keyed mail-row test IDs
  stay within the supplied window and overscan bound rather than the loaded
  message count. Do not count every descendant `NodeHost` inside each row.
- A fast user does not expose a blank row while the OCaml window advances.

#### Route and drawer gestures

- A detail edge drag never opens the drawer.
- A root inbox edge drag never emits a route-pop event.
- A root row drag outside the edge zone still performs its configured mail
  action.
- A vertical drag scrolls without opening the drawer or activating a row.
- Drawer cancel/commit tracks the finger and sends no per-frame FFI events.
- Menu, scrim, system Back, and accessibility actions provide complete
  non-gesture operation.

#### Press feedback

- Pressed state is visible before the activation event is delivered.
- A completed tap opens exactly one matching detail page.
- Vertical scrolling, horizontal row swipe, pointer cancellation, and star tap
  restore the row and do not navigate.
- The state layer is clipped to the row and remains visible over the unread
  decoration.

#### Bottom navigation

- The bar stays above the safe area and does not cover the last mail or loader.
- Mail, Chat, Spaces, and Meet expose selected and accessible semantics.
- Placeholders are explicit, local, and reversible.
- Returning to Mail preserves loaded data, read/star/archive state, virtual
  window, and scroll position.
- A pushed detail covers the bottom bar and returning reveals the same selected
  Mail state.

### Manual visual and performance review

Continue the repository's behavior-first policy instead of introducing a new
mail-only golden framework.

After automated checks pass:

1. Capture 390 by 844 screenshots of the idle inbox, append loader, open
   drawer, and selected bottom destinations.
2. Record short compact-device videos for row press to detail, detail edge
   Back, root edge drawer open/close, and repeated append-loading.
3. Run twenty warmed Profile repetitions for the new interactions.
4. Treat a warmed p90 build or raster time above 16 milliseconds, or any
   repeatable visible blank/jump, as a release blocker.

Numeric thresholds must be tuned from observable device behavior and updated
with their tests. Widget tests must not use wall-clock performance assertions.

## Future file change matrix

| File | Expected responsibility |
| --- | --- |
| `examples/mail/ocaml/mail.ml` | Paging model, generated fixtures, window selection, load effect, drawer destinations, bottom destinations, Pressable composition, and retained route behavior |
| `examples/mail/README.md` | Replace the twelve-message statement and document infinite loading, drawer, press feedback, bottom navigation, and placeholder scope |
| `ocaml/ui/native_widget.ml` | Effect-friendly Virtual List constructor plus typed Navigation Shell and Pressable contracts |
| `ocaml/ui/native_widget.mli` | Publish the reusable typed APIs |
| `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart` | Preserve or strengthen visible-range/window behavior required by prefetch tests |
| New Flutter native-widget host files | Own Navigation Shell and Pressable local interaction state |
| `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart` | Register built-in hosts if registration is not centralized elsewhere |
| `flutter/packages/bonsai_flutter/lib/bonsai_flutter.dart` | Export public Dart contracts used by tests and custom registries |
| `ocaml/test/mail_example_tests.ml` | Lock loading, identity, navigation, placeholder, and existing mail business behavior |
| `ocaml/test/native_widget_tests.ml` | Lock typed native props and event decoding |
| `flutter/packages/bonsai_flutter/test/virtual_list_test.dart` | Lock prefetch window and retained offset behavior |
| New Flutter host tests | Lock drawer, Pressable, bottom composition, gesture arena, semantics, and lifecycle |
| `flutter/integration_test/test/mail_ffi_test.dart` | Lock the real cross-language end-to-end flow |
| `flutter/integration_test/integration_test/mail_profile_test.dart` | Exercise warmed interactions on a compact physical iPhone |
| `flutter/integration_test/test_driver/mail_profile_test.dart` | Summarize and enforce the existing Profile frame-budget policy |
| `docs/custom-widgets.md` | Document the reusable handler, Navigation Shell, and Pressable ownership contracts |
| `docs/virtual-lists.md` | Document effect-friendly visible-range handling and append-window guidance |

The implementation may split native APIs into more focused files, but it must
not add mail-specific state or a mail-specific FFI channel to Dart.

## Verification commands for a later implementation

Focused OCaml tests:

```sh
dune exec ./ocaml/test/mail_example_tests.exe
dune exec ./ocaml/test/native_widget_tests.exe
dune exec ./ocaml/test/core_surface_tests.exe
```

Focused Flutter tests:

```sh
cd flutter/packages/bonsai_flutter
flutter test test/virtual_list_test.dart
flutter test test/navigation_host_test.dart
flutter test test/swipe_action_test.dart
flutter test test/native_widget_test.dart
flutter test test/navigation_shell_test.dart
flutter test test/pressable_test.dart
```

Real FFI test:

```sh
make integration-native-object
cd flutter/integration_test
flutter test test/mail_ffi_test.dart
```

Compact physical-iPhone Profile gate:

```sh
cd flutter/integration_test
flutter drive --profile --no-dds \
  -d <physical-device-id> \
  --target integration_test/mail_profile_test.dart \
  --driver test_driver/mail_profile_test.dart \
  --timeout 600
```

Full repository checks:

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

## Acceptance criteria for the later implementation

- The inbox can complete at least three consecutive simulated page loads and
  still offers another page.
- The rendered mail tree stays bounded to a keyed virtual window even as the
  loaded OCaml session data grows.
- Every page has unique stable IDs, one cursor load, one visible loader, and no
  offset jump or blank flash.
- The detail leading-edge gesture still performs interactive Back.
- The root Mail leading-edge gesture opens the Navigation Drawer, while
  non-edge row swipes and vertical scrolls retain their existing behavior.
- The drawer also opens from a visible Menu button and closes through scrim,
  Back, selection, and the reverse gesture.
- A mail row shows visible pressed feedback before exactly one detail
  activation; scroll, swipe, cancel, and star interactions never open detail.
- Mail, Chat, Spaces, and Meet form a fixed accessible bottom bar; non-Mail
  destinations expose explicit local placeholders and returning to Mail
  restores its state.
- The bottom bar and drawer are covered by detail rather than competing with
  its reading and Back interaction.
- OCaml owns all committed application, paging, destination, mailbox, and route
  state. Flutter owns only transient motion, controller, and pressed state.
- All new renderer capabilities are generic, typed, versioned, lifecycle-safe,
  semantics-tested, and documented.
- Focused and full automated gates pass, and compact physical-device review
  shows no repeatable jank, blank window, gesture conflict, or state jump.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| The virtual item window advances too late and exposes empty placeholders. | Prefetch by visible index with overscan and test fast drags plus overlapping window updates. |
| Repeated range events start duplicate timers or pages. | Keep one load generation/cursor in OCaml and ignore stale or duplicate completion. |
| Appending changes max extent and moves the user's viewport. | Retain the Flutter controller and assert exact offset before and after append. |
| The root drawer steals detail Back or a row swipe. | Put the shell inside the root page and enforce edge-only gesture priority in widget and FFI tests. |
| A custom row decoration hides Material ink. | Paint a tested state layer above the opaque row content in a generic Pressable host. |
| Press feedback adds noticeable navigation latency. | Require one visible frame, start at 80 ms only if needed, and cap at 100 ms without device evidence. |
| Bottom destinations look functional but do nothing. | Navigate to explicit local scope placeholders or omit the bar until meaningful destinations exist. |
| Switching destinations disposes the inbox controller. | Retain destination bodies in a Flutter `IndexedStack` owned by the Navigation Shell. |
| Four Gmail-style labels are mistaken for copied product scope. | Keep original Bonsai visuals and content, document the destinations as reference placeholders, and do not implement Google services. |
| Gmail observations are treated as internal specifications. | Keep evidence classification and label numeric values as hypotheses. |

## Sources

### External primary sources

- [Gmail - Email by Google on the Apple App Store](https://apps.apple.com/us/app/gmail-email-by-google/id422689480)
- [Official App Store drawer screenshot](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/8d/0d/75/8d0d7520-9911-08ad-dbfd-4e3cf6cbf728/APP_IPHONE_55-5.png/392x696bb.png)
- [Official App Store bottom-navigation screenshot](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/24/78/b7/2478b7cb-c912-851f-f29c-6b7b9eb876a0/APP_IPHONE_55-9.png/392x696bb.png)
- [Change your Gmail inbox layout - iPhone and iPad](https://support.google.com/mail/answer/18522?co=GENIE.Platform%3DiOS&hl=en)
- [Fix sync errors with the Gmail app - iPhone and iPad](https://support.google.com/mail/answer/6383854?co=GENIE.Platform%3DiOS&hl=en)
- [Use Google Chat in Gmail - iPhone and iPad](https://support.google.com/chat/answer/9341104?co=GENIE.Platform%3DiOS&hl=en)
- [Join meetings from Gmail - iPhone and iPad](https://support.google.com/mail/answer/9822902?co=GENIE.Platform%3DiOS&hl=en)
- [Enable the new integrated experience in G Suite](https://workspaceupdates.googleblog.com/2020/08/enable-new-integrated-experience-in-gsuite.html)
- [Gmail API: users.messages.list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list)
- [Flutter ListView.builder](https://api.flutter.dev/flutter/widgets/ListView/ListView.builder.html)
- [Flutter Scaffold](https://api.flutter.dev/flutter/material/Scaffold-class.html)
- [Flutter Scaffold.drawerEdgeDragWidth](https://api.flutter.dev/flutter/material/Scaffold/drawerEdgeDragWidth.html)
- [Flutter Drawer](https://api.flutter.dev/flutter/material/Drawer-class.html)
- [Flutter Cupertino route source at the researched framework revision](https://github.com/flutter/flutter/blob/058e0af2c2/packages/flutter/lib/src/cupertino/route.dart#L793-L806)
- [Flutter InkWell](https://api.flutter.dev/flutter/material/InkWell-class.html)
- [Flutter ListTile](https://api.flutter.dev/flutter/material/ListTile-class.html)
- [Flutter NavigationBar](https://api.flutter.dev/flutter/material/NavigationBar-class.html)
- [Flutter CircularProgressIndicator](https://api.flutter.dev/flutter/material/CircularProgressIndicator-class.html)
- [Material Ripple for iOS](https://m2.material.io/develop/ios/supporting/ripple)
- [Material bottom navigation](https://m2.material.io/components/bottom-navigation/)
- [Material progress indicators](https://m2.material.io/components/progress-indicators)
- [Apple Human Interface Guidelines: Loading](https://developer.apple.com/design/human-interface-guidelines/loading)
- [Apple Human Interface Guidelines: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

### Repository sources

- `docs/agent-guide/002-mail-client-example_report.md`
- `docs/agent-guide/003-mail-interactions.md`
- `docs/architecture.md`
- `docs/custom-widgets.md`
- `docs/navigation.md`
- `docs/testing.md`
- `docs/virtual-lists.md`
- `examples/mail/README.md`
- `examples/mail/ocaml/mail.ml`
- `ocaml/ui/material.mli`
- `ocaml/ui/native_widget.ml`
- `ocaml/ui/native_widget.mli`
- `ocaml/ui/widget.ml`
- `ocaml/ui/widget.mli`
- `ocaml/runtime/driver.mli`
- `ocaml/test/mail_example_tests.ml`
- `ocaml/test/native_widget_tests.ml`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/swipe_action.dart`
- `flutter/packages/bonsai_flutter/lib/src/native_widget/virtual_list.dart`
- `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`
- `flutter/packages/bonsai_flutter/test/navigation_host_test.dart`
- `flutter/packages/bonsai_flutter/test/swipe_action_test.dart`
- `flutter/packages/bonsai_flutter/test/virtual_list_test.dart`
- `flutter/integration_test/test/mail_ffi_test.dart`
- `flutter/integration_test/integration_test/mail_profile_test.dart`
