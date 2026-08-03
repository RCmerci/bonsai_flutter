# Bonsai Mail

`Bonsai Mail` is a fictional, local-only mail reader that demonstrates a
compact inbox, message detail, and OCaml-owned declarative navigation. Its
information hierarchy is inspired by current mobile mail applications, while
its identity, palette, fixtures, and content are original.

The example includes:

- twenty initial deterministic fictional messages and endless 20-message
  append pages after a local 750 ms delay;
- a bounded 24-row OCaml sparse-extent virtual window with an inline loading
  footer;
- read, unread, starred, archived, and trashed state;
- a rounded search header with a discoverable Menu action;
- a leading-edge Navigation Drawer for Inbox, Starred, Archived, Trash, and
  an explicit Settings placeholder;
- a fixed, accessible Mail, Chat, Spaces, and Meet bottom bar whose non-Mail
  destinations are explicit local placeholders;
- stable keyed inbox rows with bidirectional swipe actions in collapsed and
  expanded states;
- a single-open inline outliner card with deterministic two-level summaries;
- renderer-local row press feedback and bidirectional row-to-card morphing;
- independent Reply, Open, star, and collapse controls in each expanded card;
- a Cupertino slide transition with interactive leading-edge back;
- archive, delete, mark-unread, and platform-back behavior;
- an optional local attachment tile; and
- deterministic reply-scope notices.

All application data, paging state, derived mailbox state, destinations,
handlers, and route state live in OCaml/Bonsai. Flutter owns the retained
destination bodies, scroll controller, drawer and Back interpolation, row drag
frames, pressed feedback, haptics, spinner animation, and post-release settle
animation. Flutter also owns interpolated sparse extents, accordion anchoring,
and the row/card surface timeline. Reduced motion resolves those transitions
directly to their committed targets. Only settled visible ranges and discrete
actions cross the typed native-widget boundary.

Swipe start-to-end to Archive a message. Swipe end-to-start to Mark read or
Mark unread according to the current row state. Both actions are also exposed
as custom accessibility actions. Scroll near the loaded tail to append another
deterministic page without resetting the current offset.

Tap a collapsed row outside its star control to expand it inline. Expansion is
a preview action: it does not mark the message read or open a route. Only one
message is expanded at a time. Use Reply for the deterministic out-of-scope
notice, Open to mark the message read and push its existing detail route, or
the header and upward chevron to collapse the card. Returning from detail keeps
the same card expanded and retains the list offset.

## Run on macOS arm64

From the repository root:

```sh
make native-object EXAMPLE=mail
cd examples/mail/flutter
flutter pub get
flutter run -d macos
```

The debug run selects the `mail-debug` entrypoint and prints a concise runtime
trace to the terminal. Profile and release builds select the untraced `mail`
entrypoint. The trace shows startup, visibility generations, cycles that emit a
renderer frame or recoverable diagnostic, event-batch ordering, presentation
identities, revisions, frame byte counts, acknowledgments for emitted frames,
and shutdown. Successful idle pumps are intentionally silent. Event payloads
and native error messages are omitted.

The OCaml side prints only the logical widgets changed by each reconciliation,
a summary of every frame sent to Flutter, every event batch received from
Flutter, and acknowledgments for presentations that emitted a frame. The
initial full snapshot contains the complete tree because every widget is new.
Text payload contents are not logged; only their byte lengths are shown.

The OCaml trace uses a workspace-internal virtual `Trace` module. It has no
public Dune name and is not installed as part of the `bonsai_flutter` package.
Its Debug implementation invokes the supplied action, while its Profile/Release
implementation ignores it. The native build stages separate complete objects
and the Flutter build hook selects the matching object before linking.

For example:

```text
[Bonsai Mail][runtime] start entrypoint=mail-debug configBytes=10
[Bonsai Mail][ocaml][widget-diff] targetRevision=1 kind=full_snapshot
Theme
  Center
    Constrained_box
      Navigator
[Bonsai Mail][ocaml][outbound-frame] direction=ocaml->flutter epoch=... kind=full_snapshot baseRevision=0 targetRevision=1 operations=... bytes=...
[Bonsai Mail][runtime] ready
[Bonsai Mail][visibility] generation=1 eligible=true
[Bonsai Mail][cycle] presentation=1 revision=1 frameBytes=14352 recoverable=none
[Bonsai Mail][event-batch] epoch=... events=1 sequences=1..1 displayedRevision=1 tags=tap
[Bonsai Mail][ocaml][inbound-event-batch] direction=flutter->ocaml epoch=... events=1
  sequence=1 displayedRevision=1 node=... handler=... tag=tap payload=tap
[Bonsai Mail][presentation] succeeded generation=1 presentation=2 revision=2 eventBytes=...
[Bonsai Mail][ocaml][presentation-ack] presentationId=2 revision=2 direction=flutter->ocaml
[Bonsai Mail][ocaml][widget-diff] targetRevision=2 kind=incremental_frame
  updateProps node=... Text "Updated subject"
```

The exact byte counts, revisions, epoch, and timings come from the live runtime
and vary between runs.

## Build an unsigned iPhoneOS application

From the repository root:

```sh
make ios-device-native-objects
cd examples/mail/flutter
flutter pub get
flutter build ios --debug --no-codesign
```

macOS arm64 remains the only tested runtime platform. The iPhoneOS build is an
architectural packaging target and does not expand the repository's platform
support claim.

Interactive search, compose, category filtering, dark mode, persistent
multi-button action drawers, Undo, and network-backed accounts are
intentionally outside this focused example.
