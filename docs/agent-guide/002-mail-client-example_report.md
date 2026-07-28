# Gmail-Inspired Mail Example Research and Implementation Prompt

## Document status

- Date: 2026-07-26
- Status: Research and prompt only; implementation is intentionally deferred.
- Proposed example: `examples/mail`
- Product name: `Bonsai Mail`
- Primary reference: the current Google Gmail mobile email list and email
  detail experience.
- Focus: email list, email detail, and the list-to-detail navigation flow.

## Decision summary

Create a fictional, local-only mail reader named `Bonsai Mail`. It should use
the current Gmail mobile application as a visual and interaction reference,
without copying Gmail branding, logos, account data, or proprietary content.

The example should demonstrate two polished screens:

1. An email list with a static rounded search/header surface, high-density
   message rows, and unread and starred states.
2. An email detail view with a compact action toolbar, subject hierarchy,
   sender metadata, readable body content, an optional attachment, and reply
   actions.

The first implementation should prioritize the two-screen reading experience.
Authentication, networking, synchronization, multi-account management, AI
features, and a complete compose flow are explicitly outside the scope.

All application state, derived data, handlers, and route state must remain in
OCaml/Bonsai. Dart must remain a mechanical host and renderer, except for
small, reusable renderer primitives that are genuinely missing from
`bonsai_flutter`.

## Research baseline

### Current Gmail mobile direction

The current official Google Play listing, updated on 2026-07-24, presents a
Material 3 Expressive-style mobile inbox. Its first phone screenshot shows:

- a very light blue-gray application background;
- a prominent white pill-shaped search surface;
- a small navigation affordance and account avatar around the search surface;
- an `Inbox` section label;
- a large white rounded content surface;
- category summary rows followed by dense email rows;
- circular sender avatars, sender name, subject, preview, timestamp, and star;
- an extended compose affordance near the lower-right edge; and
- a low-emphasis navigation surface at the bottom.

The official detail screenshot shows a compact top toolbar, a strong subject
heading, sender information, message actions, a readable message surface, and
content cards that can surface structured information. Gmail Help also
documents that mobile detail views expose archive and read/unread actions near
the top, while Reply, Reply all, and Forward are available at the bottom of a
message.

The visual measurements in this document are implementation guidance inferred
from the official screenshots and Material conventions. They are not claimed
to be Google's internal design specifications.

### Stable design characteristics to reuse

- Mail content is primary; chrome is quiet and tonal.
- Rounded surfaces group search, categories, and message content.
- Unread state is communicated through typography and semantics, not only
  color.
- Every row has a predictable scan path: avatar, sender, subject/preview,
  timestamp, and star.
- The detail screen keeps destructive and organizational actions in a compact
  toolbar, separate from reply actions.
- Touch targets remain generous even when text density is high.
- Motion should clarify navigation and state changes, not decorate them.

### Characteristics not to copy

- Do not use the Gmail name, Gmail logo, Google account imagery, Google product
  icons, or Google-owned sample messages.
- Do not reproduce exact Gmail colors as a brand palette. Use an original
  muted-blue seed and a documented light palette that agrees with it.
- Do not implement Gemini, AI Overview, Smart Reply, Chat, Meet, subscriptions,
  account switching, or Gmail backend behavior.
- Do not claim pixel parity with Gmail. The goal is a recognizable,
  Gmail-inspired information hierarchy built with `bonsai_flutter`.

## Focused product scope

### P0: required first version

- Fictional in-memory email data.
- A compact mobile-first email list.
- A static, pill-shaped `Search in mail` header that establishes the Gmail-like
  composition without pretending the current default `TextField` can match
  Gmail's SearchBar.
- Read/unread presentation.
- Star/unstar from the list and detail screens.
- Open an email by tapping its row.
- Mark an opened email as read.
- Declarative list-to-detail navigation with a slide transition.
- Platform/system back navigation to the email list.
- Archive, delete, and mark-unread actions from the detail toolbar.
- Subject, sender metadata, message body, one optional attachment tile, and
  Reply/Reply all/Forward affordances in the detail view.
- A light theme derived from one original seed color.
- Accessibility semantics and deterministic test IDs.
- An inline live-region notice when a reply affordance is tapped, explaining
  that composing is outside this focused example.

### P1: explicitly deferred follow-up

- Interactive search by sender, subject, and preview text.
- Category summaries and category filtering for `Promotions` and `Updates`.
- A Compose floating action button and complete compose flow.
- Dark theme and semantic Material color-role tokens for custom surfaces.
- Large-screen split list/detail layout.

### Out of scope

- Real mail accounts, OAuth, network calls, persistence, or background sync.
- Complete drawer, settings, labels management, or account switching.
- A compose editor or message sending.
- AI and Google Workspace integrations.
- Multi-select mode and bulk actions.
- Swipe-to-archive or swipe-to-delete in the first version.
- Rich HTML email rendering, remote images, tracking pixels, or web content.
- Variable-height virtualized mail rows.
- Android packaging or a new platform support claim.

## Repository findings

### Architectural boundary

`bonsai_flutter` is OCaml-first. OCaml/Bonsai owns application state,
declarative UI, routing, identity, handlers, and incremental frame generation.
Dart mechanically realizes accepted frames as Flutter widgets.

The mail example must preserve that boundary:

- The message collection, selected message, mailbox state, read state, starred
  state, inline notice, and route stack live in OCaml.
- Flutter must not keep a second mail model, selected message, reducer, or
  router.
- The Flutter shell should contain only `MaterialApp`,
  `BonsaiFlutterRoot`, native initialization, and registrations for any
  genuinely reusable typed renderer extension.

### Useful existing examples

| Concern | Existing reference | Reuse |
| --- | --- | --- |
| Stable keyed collection | `examples/todo` | Stable message IDs, item handlers, deterministic list updates |
| List-to-detail routing | `examples/navigation` | OCaml-owned page list, stable page keys, typed route-pop event |
| Layout and Material primitives | `examples/gallery` | Flex, Stack, decoration, icons, cards, list tiles, theme, semantics |
| Optional P1 search input | `examples/text_input` | Canonical revisioned text state and optimistic Flutter-local editing |

### Existing primitives that fit the design

- `Widget.list_view` for the small, fixed demo inbox.
- `Widget.row`, `Widget.column`, `Widget.Flex`, `Widget.Stack`, padding,
  alignment, constraints, and safe area.
- `Widget.decorated_box` for tonal rounded surfaces and avatars.
- `Widget.icon`, `Material.icon_button`, `Material.list_tile`, dividers, and
  cards.
- `Widget.navigator` and `Widget.page` for list/detail navigation.
- `Widget.theme` with a Material seed for the light theme.
- `Widget.semantics` and `Widget.with_test_id` for accessibility and tests.
- `Environment.value` for compact versus larger-window layout decisions.

### Important capability gaps

The current primitives can express the two-screen structure, but not the full
visual hierarchy:

- `Widget.text` has no public size, weight, line-height, color, maximum-line,
  or overflow controls.
- `Material.app_bar` only accepts a title and `center_title`; it cannot express
  Gmail's leading/back and trailing action groups.
- `Material.scaffold` has no drawer, floating action button, or bottom
  navigation slots.
- There is no dedicated SearchBar, FloatingActionButton, CircleAvatar, Chip,
  or Dismissible primitive.
- `Material.text_field` maps to a default Flutter `TextField` and has no public
  hint, fill, border, or content-padding controls. It cannot produce a faithful
  pill SearchBar without another generic API.
- `Style.Decoration` currently exposes only background color and border radius.
- `Widget.gesture` does not expose a horizontal drag or dismiss gesture.
- Custom OCaml decorations and text receive concrete colors, not semantic
  Material color roles derived from the active seed.

For P0, compose the static search surface, avatar, and toolbar from existing
layout, decoration, icon, semantics, and gesture primitives. Do not add
app-specific native widgets for those elements. P1 interactive search requires
a separate, generic text-input decoration and hint API; styled text alone does
not solve SearchBar styling.

The one justified reusable P0 core addition is styled text. Add the smallest
generic, typed text-style surface required for sender/subject hierarchy:

- font size;
- font weight;
- line height;
- color;
- maximum lines; and
- ellipsis overflow.

If extending the core text protocol would make this example disproportionately
large, use one small typed native **text leaf** as a temporary fallback. Do not
implement an entire email row, list screen, or detail screen as one Dart
widget. The example is intended to demonstrate OCaml-owned composition and
incremental updates.

## Proposed application model

Use a compact, immutable OCaml model with these concepts:

- Message:
  - stable integer ID;
  - sender display name and fictional email address;
  - subject;
  - preview;
  - plain-text body;
  - compact timestamp label;
  - read/unread flag;
  - starred flag;
  - mailbox state: Inbox, Archived, or Trash;
  - optional category metadata for a later P1 filter;
  - optional attachment metadata.
- Application:
  - ordered message collection;
  - selected message ID, if detail is open;
  - optional inline notice text for out-of-scope reply actions.

Derive the visible inbox by selecting messages whose mailbox state is Inbox.
Opening a message sets its read state and selects its ID in one Bonsai update.
Archiving changes the mailbox state to Archived; deleting changes it to Trash.
Both actions then pop detail, so their visible result is similar while their
model semantics remain distinct. Marking a detail message unread updates the
model and returns to the inbox so that the state change is immediately
visible.

Use stable application keys based on message ID for every mail row and detail
subtree that represents a message. Do not use list position as identity.

## Screen specification

### Email list

Design for a reference compact viewport of 390 by 844 logical pixels, while
remaining usable at larger sizes.

#### Email list composition

1. Apply a Material theme derived from an original muted-blue seed.
2. Use `SafeArea`.
3. Paint a low-contrast blue-gray tonal background.
4. Place a 56 logical-pixel rounded search surface near the top:
   - original mail glyph on the left, used as presentational content;
   - static `Search in mail` text in the center;
   - fictional circular account avatar on the right, also presentational;
   - no button semantics on the non-interactive glyph or avatar.
5. Add an `Inbox` label with modest emphasis below the search surface.
6. Place the scrollable content in a white or surface-colored container with
   large top corner radii.
7. Render 10 to 14 fictional mail rows.

#### Email row anatomy

- Row height: approximately 76 to 88 logical pixels.
- Horizontal padding: approximately 12 to 16 logical pixels.
- Leading avatar: 40 logical pixels, circular, with deterministic color and
  sender initial.
- Main column:
  - sender, single line;
  - subject, single line;
  - preview, single line with ellipsis.
- Trailing column:
  - timestamp at the top;
  - star button at the bottom.
- Unread rows:
  - use stronger sender and subject weight;
  - expose `Unread` in semantics;
  - may use a subtle tonal row background.
- Read rows:
  - use normal sender weight and lower-emphasis preview text.
- Star state:
  - use filled amber for starred;
  - use a neutral outline for unstarred;
  - expose a clear toggle label and selected state to semantics.
- The whole row is one primary tap target for opening detail, but the star
  remains an independent action.

#### Deferred search behavior

P0 deliberately keeps the search header static because the current text-input
API cannot style the default Flutter `TextField` as the required pill
SearchBar. A later P1 should add a generic hint/decoration API, then implement
case-insensitive filtering by sender, address, subject, and preview while
preserving keyed row identity.

### Email detail

Push a declarative `Widget.page` using
`~page_key:"mail-detail-<message-id>"` and a slide transition. This page key is
the route identity; it is distinct from the widget's optional application
`~key`.

#### Email detail composition

1. Use the same tonal background and safe-area treatment as the list.
2. Build a compact custom toolbar:
   - Back;
   - Archive;
   - Delete;
   - Mark unread.
3. Keep all toolbar targets at least 48 by 48 logical pixels and provide
   explicit semantics labels.
4. Render the subject as the strongest text on the page.
5. Place a star toggle beside the subject without shrinking the subject below
   two useful lines.
6. Render a sender header:
   - 40 logical-pixel avatar;
   - sender name;
   - fictional sender address;
   - compact timestamp;
   - recipient disclosure text such as `to me`.
7. Render the plain-text body on a quiet surface with comfortable line length
   and vertical spacing.
8. For one fixture message, render one attachment tile with file name, type,
   and size. The tile is visual and local-only.
9. End the content with three evenly spaced actions:
   - Reply;
   - Reply all;
   - Forward.

Reply actions do not open a compose screen in this focused example. They should
set an inline live-region notice whose content clearly says that composing is
outside the scope of this demo. This keeps behavior deterministic without
depending on the current incomplete modal-barrier behavior of Overlay and
MaterialDialog.

#### Detail interaction behavior

- Opening a row marks it read.
- Back and the platform route-pop event return to the same list state.
- Star changes are reflected in both detail and list.
- Archive sets mailbox state to Archived and returns to the list.
- Delete sets mailbox state to Trash and returns to the list.
- Mark unread sets the message unread and returns to the list.
- Reply actions set the inline scope notice; the attachment tile is
  presentational content and does not expose button semantics.

## Visual language

Use an original, small light-theme palette that visually agrees with the
Material seed. The current OCaml API cannot read semantic color roles such as
`surfaceContainer` back from Flutter, so custom decorations and styled text
must use documented concrete colors in P0. They must not use Gmail brand
colors.

Suggested light-theme direction:

- app background: very light blue-gray;
- content surface: near-white;
- primary accent: muted medium blue;
- primary container: pale blue;
- text: near-black with neutral gray secondary text;
- star: warm amber;
- archive and delete actions: neutral toolbar icons, with their destructive or
  organizational meaning conveyed by semantics rather than color alone.

Suggested shape direction:

- search surface: full pill;
- main list surface: 24 to 28 logical-pixel top corners;
- avatar: circular;
- attachment tile and inline notice: 16 to 20 logical-pixel radius.

Suggested typography hierarchy:

- subject heading: 22 to 24 logical pixels, medium weight;
- sender in an unread row: 14 to 16 logical pixels, semibold;
- sender in a read row: 14 to 16 logical pixels, regular;
- subject and preview: 13 to 14 logical pixels;
- timestamp and metadata: 11 to 12 logical pixels;
- body: 15 to 16 logical pixels with comfortable line height.

Dark mode is deferred until `bonsai_flutter` exposes reusable semantic
color-role tokens for custom surfaces and text.

## Responsive behavior

- Below 600 logical pixels: use the compact single-column list and pushed
  detail page.
- At and above 600 logical pixels: center the mail experience with a sensible
  maximum width and preserve comfortable margins.
- A split list/detail layout is not required for the first version.
- Respect safe area, text scale, bold text, high contrast, and reduced-motion
  values exposed by `Environment`.
- Do not present the UI as proof of Android support. The design is
  mobile-inspired; platform support claims remain those of the repository.

## Accessibility requirements

- Add deterministic test IDs to the page roots, static search header, every
  message row, every star control, detail toolbar actions, sender header, body,
  attachment, inline notice, and reply actions.
- Give every icon-only control a semantic label.
- Expose button role, enabled state, selected/starred state, and unread state.
- Give `Inbox` and the detail subject heading semantics.
- Ensure logical reading order follows visual order.
- Use a minimum 48 by 48 logical-pixel interactive target.
- Do not communicate unread, starred, destructive, or selected state with
  color alone.
- Preserve usability at larger text scales; truncate list previews, but allow
  the detail subject and body to expand.
- Honor reduced motion for page and transient-state animation.

## Fixture content

Use entirely fictional, English-language content so code and artifact text
follow repository conventions. Include enough variation to exercise the UI:

- unread and read messages;
- starred and unstarred messages;
- short and long sender names;
- short and long subjects; long subjects truncate in the list and may wrap to
  two lines in detail;
- Promotions and Updates metadata reserved for P1;
- one attachment;
- one long body with paragraphs and a bulleted list;
- timestamps using both time and abbreviated date formats.

Do not use real personal addresses, real companies, Gmail screenshot content,
or remote images. Avatars should use initials and deterministic local colors.

## Testing strategy for the later implementation

Follow test-driven development. Add a failing behavioral test before each
implementation slice, verify that it fails for the intended reason, and then
write the smallest change that passes.

### Required OCaml/headless coverage

- Initial inbox renders the expected visible message IDs.
- Read and unread rows expose distinct semantics.
- Star toggles without replacing the keyed row.
- Tapping a row selects the correct message and marks it read.
- The detail page key is stable and contains the correct subject and sender.
- Route-pop returns to the list without resetting read or star state.
- Archive removes the selected message from the visible inbox and pops detail.
- Delete moves the selected message to Trash and pops detail.
- Mark unread updates the message and pops detail.
- Reply affordances update the inline focused-scope notice.

### Required renderer coverage

If a generic styled-text primitive is added, cover:

- protocol encode/decode round trips;
- Flutter mapping for size, weight, line height, color, maximum lines, and
  ellipsis;
- incremental property updates;
- invalid value rejection;
- semantics preservation; and
- light-theme rendering behavior.

### Required integration coverage

Add one real FFI flow only if the example is included in the aggregate
integration application:

1. Start the `mail` entrypoint.
2. Verify the inbox and one unread keyed row.
3. Tap that row.
4. Verify the detail subject.
5. Trigger route pop.
6. Verify that the same row is now read and its stable identity was preserved.

Do not introduce a fragile screenshot-golden framework solely for this
example. Instead, capture a manual 390 by 844 reference screenshot under
`artifacts/example-screenshots/` after behavioral tests pass.

## Repository integration checklist for the later implementation

Create the standard first-class example shape:

- `examples/mail/README.md`
- `examples/mail/ocaml/mail.ml`
- `examples/mail/ocaml/mail.mli`
- `examples/mail/ocaml/dune`
- `examples/mail/ocaml/native_embed.ml`
- `examples/mail/flutter/lib/main.dart`
- `examples/mail/flutter/pubspec.yaml`
- the standard Flutter host files for macOS and iOS

Keep the name `mail` consistent across:

- `Native_backend.embed ~name:"mail"`;
- the Dart runtime configuration string;
- the Dune library and executable dependencies;
- the Flutter package name;
- the native artifact root; and
- test entrypoint configuration.

Update all first-class example enumerations:

- `Makefile` native-object targets and Flutter analysis loop;
- `tool/macos/stage_native_objects.sh`;
- `tool/ios/build_native_objects.sh`;
- `tool/test_ci_contract.sh`;
- the root README example catalog;
- documentation that states the exact standalone example count; and
- integration aggregate files only if the integration flow is added.

The later implementation must not weaken CI assertions, bypass the binary
protocol, add application state to Dart, or add an app-specific FFI channel.

## Acceptance criteria

The later implementation is complete when:

- `examples/mail` is a first-class standalone example and follows existing
  naming and packaging conventions.
- The compact email list is recognizably inspired by current Gmail mobile
  information hierarchy without using Gmail branding.
- The detail page matches the list visually and has a clear subject/sender/body
  hierarchy.
- Tapping any visible mail row opens the correct detail page.
- Platform back returns to the same list state.
- Read and star state remain consistent across both screens.
- Archive, delete, and mark-unread actions produce the specified local model
  changes.
- All visible controls have deterministic behavior and semantics.
- OCaml/Bonsai owns all application and route state.
- Any renderer additions are generic, typed, protocol-tested, and documented.
- Required OCaml, Dart, Flutter, formatting, and CI-contract checks pass;
  integration checks pass if the optional FFI flow is added.
- A compact reference screenshot has been visually reviewed at 390 by 844.

## Copy-paste implementation prompt

```text
You are working in the bonsai_flutter repository.

Goal
----
Add a new first-class example at examples/mail named "Bonsai Mail". The visual
reference is the current Google Gmail mobile app, but the implementation must
be an original, fictional mail reader and must not copy Gmail branding, logos,
real account data, or Google-owned sample content.

Focus only on two polished screens:

1. Email List
2. Email Detail, opened by tapping an email row

Read and follow:

- AGENTS.md
- README.md
- docs/architecture.md
- docs/navigation.md
- docs/testing.md
- docs/agent-guide/002-mail-client-example_report.md
- examples/todo
- examples/navigation
- examples/gallery

Use test-driven development. Write a focused behavioral test first, run it, and
confirm that it fails for the expected reason before writing implementation
code. Work in small verified slices.

Architecture constraints
------------------------
- OCaml/Bonsai owns messages, mailbox state, read state, starred state,
  selected message, inline notice, handlers, derived lists, and route stack.
- Dart contains no mail reducer, selected-message state, message model, or
  application router.
- Flutter remains a mechanical host/renderer.
- Use stable application keys derived from message IDs.
- Use the existing binary protocol and typed event model.
- Do not implement an entire row or screen as one opaque Dart widget.

Product scope
-------------
Implement:

- local fictional message fixtures;
- static rounded "Search in mail" header surface;
- Inbox label;
- 10-14 dense mail rows with avatar, sender, subject, preview, timestamp, read
  state, and star state;
- declarative list-to-detail navigation with platform back;
- detail toolbar with Back, Archive, Delete, and Mark unread;
- detail subject, star, sender metadata, plain-text body, one optional local
  attachment tile, and Reply/Reply all/Forward affordances;
- an inline live-region notice for reply actions, because a compose screen is
  outside this focused example;
- original muted-blue light Material theme;
- accessibility semantics and deterministic test IDs.

Do not implement:

- authentication, networking, persistence, or synchronization;
- real email accounts;
- a complete drawer or account switcher;
- interactive search;
- a compose editor;
- category filtering;
- dark mode;
- Gemini, AI Overview, Smart Reply, Chat, or Meet;
- rich HTML or remote email content;
- multi-select or bulk actions;
- swipe-to-archive/delete in the first version;
- Android packaging or new platform support claims.

Email List UI
-------------
- Optimize first for a 390x844 compact viewport.
- Use SafeArea and a very light blue-gray tonal background.
- Build a 56dp static pill search surface with an original mail glyph,
  "Search in mail" text, and fictional initials avatar. The glyph and avatar
  are presentational and must not expose button semantics.
- Place the scrollable inbox in a near-white rounded content surface.
- Use approximately 76-88dp rows, 40dp avatars, 12-16dp horizontal padding,
  and 48dp minimum action targets.
- Unread rows use stronger sender/subject typography and explicit unread
  semantics.
- Read rows use normal sender weight and lower-emphasis preview text.
- Keep sender and subject scannable; truncate list previews with ellipsis.
- Make the whole row open detail while preserving an independent star action.

Email Detail UI
---------------
- Push Widget.page with ~page_key:"mail-detail-<id>" and a slide transition.
  Do not confuse page_key with the widget's optional application key.
- Use the same tonal background and a compact custom toolbar.
- Keep toolbar actions at least 48x48dp and label them for semantics.
- Make subject the strongest text and place a star toggle beside it.
- Show a 40dp avatar, sender name/address, timestamp, and "to me" disclosure.
- Render a comfortable plain-text body and one optional attachment tile.
- End with Reply, Reply all, and Forward actions.
- Opening detail marks the message read.
- Star changes must remain consistent between detail and list.
- Archive and Delete update the OCaml model and return to the list.
- Archive sets mailbox state to Archived; Delete sets it to Trash.
- Mark unread updates the OCaml model and returns to the list.
- Platform route pop returns to the same list state.
- Reply actions update an inline live-region notice explaining that compose is
  outside this focused example. Do not use Overlay or MaterialDialog for it.
- Every visible control must have deterministic behavior; do not leave no-op
  icons.

Renderer strategy
-----------------
Compose the static search surface, avatar, toolbar, attachment tile, and inline
notice from existing generic primitives.

The current text API cannot express the necessary hierarchy. Prefer adding the
smallest generic typed styled-text capability needed for font size, weight,
line height, color, maximum lines, and ellipsis. Cover the OCaml API, binary
protocol, Flutter renderer mapping, invalid input, incremental updates, and
semantics. If that expansion is disproportionate, use one small typed native
text leaf as a temporary fallback. Never move a complete row or screen into
Dart.

Do not make the search field interactive in P0. The current text-input API has
no hint, fill, border, or content-padding controls. Interactive Gmail-like
search belongs in a separate P1 with a generic text-input decoration API.

Use a documented concrete light palette for custom decorations and text.
Dark mode belongs in P1 after generic semantic Material color-role tokens are
available.

Deferred P1
-----------
Do not include these in the first implementation:

- interactive search backed by a generic text-input decoration/hint API;
- Promotions and Updates summary rows with filtering;
- Compose floating action button and compose screen;
- dark mode backed by semantic Material color-role tokens;
- split list/detail large-screen layout;
- swipe actions, drawer, and account switching.

Testing and verification
------------------------
At minimum, cover:

- initial inbox and stable mail test IDs;
- read/unread semantics;
- star toggling without row replacement;
- row tap -> correct detail -> platform pop;
- opened message becomes read;
- archive, delete, and mark unread;
- inline reply scope notice;
- any new typed renderer primitive at protocol and Flutter levels.

Register the example everywhere first-class examples are enumerated:

- Makefile
- tool/macos/stage_native_objects.sh
- tool/ios/build_native_objects.sh
- tool/test_ci_contract.sh
- root README and exact-count documentation
- integration aggregate files only if an FFI integration test is added

Run the smallest relevant tests after each slice, then the repository-required
format, analysis, build, protocol, and CI-contract checks. Do not weaken or
skip existing gates.

Finish by capturing and visually reviewing a 390x844 reference screenshot
under artifacts/example-screenshots/. Report all changed files, commands run,
test results, known limitations, and any generic bonsai_flutter API additions.
```

## Historical addendum: interaction polish

The original P0 intentionally deferred swipe actions. The follow-up
`003-mail-interactions.md` work has now added them without changing the
original ownership conclusion:

- each direct inbox child is a stable keyed native swipe host;
- Flutter owns continuous drag, pill feedback, haptics, and settle animation;
- one typed logical-direction event crosses FFI only after commit;
- start-to-end archives and end-to-start toggles read state;
- `Navigation.Slide` now uses the maintained page-based Cupertino transition
  with interactive leading-edge pop; and
- stale route-pop keys are ignored by the OCaml mail state handler.

Delete remains a detail-toolbar action because the example still has no Undo
path. Persistent multi-button drawers remain out of scope.

## Sources

### External primary sources

- [Gmail on Google Play](https://play.google.com/store/apps/details?id=com.google.android.gm&hl=en_US)
- [Gmail on the Apple App Store](https://apps.apple.com/us/app/gmail-email-by-google/id422689480)
- [Google Workspace Updates Weekly Recap - April 25, 2025](https://workspaceupdates.googleblog.com/2025/04/release-notes-04-25-2025.html)
- [Android and Wear OS are getting a big refresh](https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch/)
- [Material Design 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- [Change your Gmail inbox layout](https://support.google.com/mail/answer/18522?co=GENIE.Platform%3DAndroid&hl=en)
- [Change your Gmail settings](https://support.google.com/mail/answer/6562?co=GENIE.Platform%3DAndroid&hl=en)
- [Archive Gmail messages](https://support.google.com/mail/answer/6576?co=GENIE.Platform%3DAndroid&hl=en)
- [Mark messages as read or unread](https://support.google.com/mail/answer/12516?co=GENIE.Platform%3DAndroid&hl=en)
- [Reply to messages in Gmail](https://support.google.com/mail/answer/6585?co=GENIE.Platform%3DAndroid&hl=en)
- [Forward an email](https://support.google.com/mail/answer/15162918?co=GENIE.Platform%3DAndroid&hl=en)

### Repository sources

- `README.md`
- `docs/architecture.md`
- `docs/navigation.md`
- `docs/testing.md`
- `docs/text-input.md`
- `docs/virtual-lists.md`
- `ocaml/ui/widget.mli`
- `ocaml/ui/material.mli`
- `ocaml/ui/style.mli`
- `ocaml/ui/theme.mli`
- `ocaml/ui/native_widget.mli`
- `ocaml/ui/semantics.mli`
- `ocaml/runtime/environment.mli`
- `examples/todo`
- `examples/navigation`
- `examples/gallery`
- `examples/text_input`
- `examples/host_navigation`
- `Makefile`
- `tool/macos/stage_native_objects.sh`
- `tool/ios/build_native_objects.sh`
- `tool/test_ci_contract.sh`
