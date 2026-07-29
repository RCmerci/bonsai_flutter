# Bonsai Mail

`Bonsai Mail` is a fictional, local-only mail reader that demonstrates a
compact inbox, message detail, and OCaml-owned declarative navigation. Its
information hierarchy is inspired by current mobile mail applications, while
its identity, palette, fixtures, and content are original.

The example includes:

- twelve in-memory fictional messages;
- read, unread, starred, archived, and trashed state;
- a static rounded search header;
- stable keyed inbox rows with Gmail-style bidirectional swipe actions;
- a Cupertino slide transition with interactive leading-edge back;
- archive, delete, mark-unread, and platform-back behavior;
- an optional local attachment tile; and
- deterministic reply-scope notices.

All application data, derived inbox state, handlers, and route state live in
OCaml/Bonsai. Flutter owns route interpolation, edge-back tracking, row drag
frames, haptics, and post-release settle animation. A completed swipe emits one
typed logical-direction event to OCaml.

Swipe start-to-end to Archive a message. Swipe end-to-start to Mark read or
Mark unread according to the current row state. Both actions are also exposed
as custom accessibility actions.

## Run on macOS arm64

From the repository root:

```sh
make native-object EXAMPLE=mail
cd examples/mail/flutter
flutter pub get
flutter run -d macos
```

The debug run prints a concise runtime trace to the terminal. It shows the
entrypoint startup, foreground grants, visibility generations, ordered cycles,
event-batch ordering, presentation identities, revisions, frame byte counts,
recoverable diagnostics, acknowledgments, and shutdown. Event payloads and
native error messages are intentionally omitted.

The OCaml side prints only the logical widgets changed by each reconciliation,
a summary of every frame sent to Flutter, every event batch received from
Flutter, and every presentation acknowledgment. The initial full snapshot
contains the complete tree because every widget is new. Text payload contents
are not logged; only their byte lengths are shown.

For example:

```text
[Bonsai Mail][runtime] start entrypoint=mail configBytes=4
[Bonsai Mail][ocaml][widget-diff] targetRevision=1 kind=full_snapshot
Theme
  Center
    Constrained_box
      Navigator
[Bonsai Mail][ocaml][outbound-frame] direction=ocaml->flutter epoch=... kind=full_snapshot baseRevision=0 targetRevision=1 operations=... bytes=...
[Bonsai Mail][runtime] ready
[Bonsai Mail][visibility] generation=1 eligible=true
[Bonsai Mail][command] grantVsync generation=1
[Bonsai Mail][cycle] presentation=1 revision=1 frameBytes=14352 recoverable=none
[Bonsai Mail][event-batch] epoch=... events=1 sequences=1..1 displayedRevision=1 tags=tap
[Bonsai Mail][ocaml][inbound-event-batch] direction=flutter->ocaml epoch=... events=1
  sequence=1 displayedRevision=1 node=... handler=... tag=tap payload=tap
[Bonsai Mail][presentation] succeeded generation=1 presentation=2 revision=2 eventBytes=...
[Bonsai Mail][ocaml][presentation-ack] presentation=2 revision=2 direction=flutter->ocaml
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
