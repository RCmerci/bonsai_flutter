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
cd examples/mail
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

All profiles use the same public `ocaml/native_embed.exe.o` target and the
registered `mail` entrypoint. The profile-specific complete object is produced
and selected by `bonsai-flutter`; the example has no private debug/release
native targets.

## Build an unsigned iPhoneOS application

From the repository root:

```sh
cd examples/mail
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

macOS arm64 remains the only tested runtime platform. The iPhoneOS build is an
architectural packaging target and does not expand the repository's platform
support claim.

Interactive search, compose, category filtering, dark mode, persistent
multi-button action drawers, Undo, and network-backed accounts are
intentionally outside this focused example.
