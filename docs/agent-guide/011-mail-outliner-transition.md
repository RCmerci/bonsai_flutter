# Mail Outliner Row-to-Card Transition

## Document status

| Field | Value |
| --- | --- |
| Date | 2026-08-03 |
| Status | Implemented |
| Target | Reusable Flutter-native transition infrastructure and `examples/mail` |
| Current baseline | Inline mail cards use Flutter-local extent and surface transitions |
| Related documents | `003-mail-interactions.md`, `009-mail-inbox-expansion_report.md`, `010-mail-outliner-card_report.md` |

## Executive summary

The collapsed mail row should transform into the expanded outliner card at the
same logical list index. The transition is inline and bidirectional: the item
grows downward while later rows move, and the expanded card can reverse into
the compact row without a route change or overlay handoff.

Two named Flutter components own the transition:

1. `SparseExtentListHost` owns the single animation timeline, interpolated
   item extents, list geometry, scroll anchoring, interruption, and settled
   visible-range reporting.
2. `MorphingSurfaceHost` consumes that same progress and transforms the
   visible surface and content in both directions: row to card for expansion
   and card to row for collapse.

OCaml continues to own committed application state and publishes only the
target state, final content, and final known extent. It must not publish
per-frame animation values across FFI.

The infrastructure is intentionally reusable. `SparseExtentListHost` is a
general solution for animated sparse known-extent changes, while
`MorphingSurfaceHost` is a general solution for a compact surface morphing
into an expanded surface or panel. Mail-specific content such as sender text,
outline nodes, `Reply`, and `Open` remains in the Mail composition.

## Current behavior

The current working-tree implementation already provides the correct settled
state model:

- a collapsed mail row has an extent of `88` logical pixels;
- an expanded card has a deterministic extent calculated from its header,
  outline, optional notice, dividers, and footer;
- `expanded_id` is independent of `selected_id`;
- the same keyed `Swipe_action` remains the direct list child in both states;
- `Sparse_extent_list` receives a sparse override for the expanded item; and
- scroll anchoring preserves the activated row or the first visible logical
  item when an extent changes.

After the existing Pressable feedback, however, the application currently
publishes the final expanded widget tree and final extent in one frame.
`SparseExtentListHost` applies the target extent immediately and corrects the
scroll position after layout. This prevents a persistent scroll jump, but it
does not animate the height or the row-to-card appearance.

## Goals

- Preserve object continuity: the selected row visibly becomes the card.
- Keep the activated header at a stable screen position while the item grows
  downward and later rows move out of the way.
- Support the exact reverse card-to-row transition.
- Support interruption and retargeting without snapping to an endpoint.
- Keep all per-frame work in Flutter.
- Preserve bounded virtualization, keyed row identity, scrolling, swipe
  behavior, and deterministic OCaml state.
- Respect reduced-motion settings without removing any functionality.
- Provide reusable transition primitives with no Mail-specific fields or
  behavior in their Flutter contracts.

## Non-goals

- A route transition, `Hero` flight, sheet, or permanent overlay.
- Moving `expanded_id`, message state, or route state into Flutter.
- Self-measuring arbitrary-height virtualization.
- Publishing an extent for every animation frame through FFI.
- Pixel-identical reproduction of a third-party mail client.
- Spring overshoot or a decorative bounce that moves the entire list past its
  settled geometry.

## Architecture

```text
OCaml Mail state and composition
  publishes target expanded state, content, and final extent
                         |
                         v
SparseExtentListHost
  owns the single timeline, interpolated geometry, and scroll anchor
                         |
                         +---- item extent and later-row movement
                         |
                         v
MorphingSurfaceHost
  consumes the same progress and morphs surface plus content
```

### OCaml application ownership

`examples/mail/ocaml/mail.ml` remains responsible for:

- `expanded_id` and all committed interaction state;
- the final collapsed and expanded content;
- the exact final expanded extent;
- stable message and swipe-host identity;
- expand, collapse, `Reply`, `Open`, star, and swipe handlers; and
- stale-expansion cleanup when a message leaves the active projection.

The application publishes one target-state update. It does not wait for the
animation before committing expansion or collapse, and it does not send
intermediate progress or extent values.

The compact and expanded header compositions should share the same principal
geometry wherever possible. Avatar, sender, subject, timestamp, and star
placement should not jump merely because the surface changes state.

### `SparseExtentListHost`

`SparseExtentListHost` is the transition coordinator and the only owner of the
master animation controller. It is responsible for:

- detecting added, removed, and changed extent overrides;
- capturing the current effective extents before a new target is applied;
- interpolating every affected logical index from its current extent to its
  new target extent;
- constructing layout and visible-range geometry from the interpolated
  extents;
- keeping the preferred visible item anchored during layout-driven movement;
- driving old-card collapse and new-row expansion together during an
  accordion switch;
- retargeting from the current interpolated values after rapid input;
- suppressing transient visible-range events during the transition;
- emitting the settled visible range after the target is reached;
- disposing ticker and transition resources with the retained list host; and
- resolving immediately to the target when reduced motion is enabled.

The host must support more than one temporarily animated index even though
Mail commits at most one expanded override. During an accordion switch, the
removed override is still shrinking while the added override is growing.

`SparseExtentListHost` must not know about cards, avatars, outline nodes, or
Mail actions. Its domain is logical indexes, extents, viewport geometry, and
animation progress.

### `MorphingSurfaceHost`

`MorphingSurfaceHost` is a bidirectional surface transition. It consumes the
progress owned by `SparseExtentListHost` rather than creating a second,
independent animation controller.

The normalized state is:

```text
0.0 = compact row
1.0 = expanded card or panel
```

It is responsible for:

- interpolating horizontal inset, vertical gap, corner radius, elevation, and
  other supported surface decoration;
- clipping content to the current animated item extent;
- keeping stable header content visually continuous;
- fading or translating compact-only content out;
- revealing expanded-only content and actions in defined phases;
- retaining outgoing visual content long enough to avoid an empty tail during
  collapse;
- preventing outgoing or clipped controls from receiving input;
- exposing only the appropriate semantics during a transition; and
- disposing outgoing content after the transition settles.

The host handles both directions:

```text
row -> card: progress moves toward 1.0
card -> row: progress moves toward 0.0
```

It must also tolerate a direction reversal at any intermediate progress. A
card that is collapsing and immediately expanded again resumes from its
current appearance instead of jumping to either endpoint.

`MorphingSurfaceHost` must not define Mail-specific slots or actions. It may
expose generic compact content, expanded content, stable/shared content,
collapsed decoration, expanded decoration, and transition timing. The Mail
composition decides that preview text is compact-only and that the outline and
footer are expanded-only.

### Shared progress

There must be one source of truth for transition progress. Running independent
controllers in `SparseExtentListHost` and `MorphingSurfaceHost` risks visible
drift: the list slot could finish moving before the card surface finishes
morphing.

The Flutter implementation should make the list-owned progress available to
the affected item through an internal transition scope or an equivalent
explicit binding. `MorphingSurfaceHost` reads that progress and applies its
own interval mappings without owning the clock.

When `MorphingSurfaceHost` is used outside a sparse list, another parent may
provide the same normalized progress contract. This keeps the surface
primitive reusable without moving list geometry into it.

## Motion specification

All numeric values are initial tuning hypotheses and must be checked on a
compact physical device in Profile mode.

| Motion | Initial value |
| --- | --- |
| Existing Pressable feedback | `80 ms` |
| Row-to-card duration | `240 ms` |
| Card-to-row duration | `190 ms` |
| Row-to-card geometry curve | `easeOutCubic` |
| Card-to-row geometry curve | `easeInOutCubic` |
| Expanded horizontal inset | Current Mail target, initially approximately `8` logical pixels |
| Expanded elevation | Current Mail target, initially `3` |
| Expanded-content entrance offset | `8` logical pixels toward the collapsed edge |
| Overshoot | None |

### Row-to-card sequence

1. Pressable feedback completes and OCaml commits the expanded target.
2. `SparseExtentListHost` captures the current extent and viewport anchor.
3. The activated item grows from `88` to its target extent while later rows
   move downward.
4. `MorphingSurfaceHost` changes the full-width row surface into the inset,
   elevated card surface using the same progress.
5. Compact-only preview content fades out early.
6. The outline begins a short fade and upward translation after the surface
   has visibly started expanding.
7. Footer actions appear in the latter half of the transition.
8. Settled geometry becomes authoritative and one final visible range may be
   emitted.

The header leading edge remains stable. The transition does not automatically
scroll the footer into view.

### Card-to-row sequence

1. OCaml commits the collapsed target.
2. Expanded-only footer and outline content stop receiving input and begin
   fading out.
3. The outgoing expanded visual remains available while the item shrinks, so
   the region below the header never becomes an unexplained blank area.
4. Elevation, radius, and inset return toward the compact row values.
5. `SparseExtentListHost` reduces the extent to `88` while later rows move
   upward.
6. Compact preview content becomes visible as sufficient space returns.
7. Outgoing expanded content is released after the transition settles.

The exit content intervals may be front-loaded rather than being a literal
time reversal of the entrance intervals. Geometry and surface progress still
share one master timeline.

### Accordion switch

When another compact row is tapped while a card is expanded:

- the old logical index animates from its current expanded extent to `88`;
- the new logical index animates from `88` to its target card extent;
- both changes run concurrently;
- the newly activated row is the preferred anchor when it is visible; and
- both corresponding `MorphingSurfaceHost` instances consume their own
  direction derived from the same transition timeline.

Sequentially completing the old collapse before starting the new expansion is
not the default because it makes a frequent accordion action unnecessarily
slow.

### Interruption and scrolling

A new target received during an active animation starts from the current
interpolated extents and surface progress. It must not restart from the last
settled endpoint.

Scroll interaction remains available. Anchor correction must not fight an
active user drag. The implementation must explicitly release or settle its
preferred animation anchor when direct scrolling takes control while
continuing to use valid interpolated geometry.

## Genericity

The two components are reusable at different levels:

| Component | Reusable capability | Example consumers |
| --- | --- | --- |
| `SparseExtentListHost` | Animate deterministic per-index extent changes while preserving virtual-list geometry | Accordions, agenda lists, search results, settings lists |
| `MorphingSurfaceHost` | Morph a compact surface into an expanded surface or panel in either direction | Mail cards, notification previews, inline inspectors, expandable settings rows |

Mail provides only one composition of those capabilities:

- avatar, sender, subject, timestamp, and star are stable header content;
- preview is compact-only content;
- outline and footer are expanded-only content; and
- `Reply` and `Open` remain independent nested controls.

Neither reusable component contains the terms `mail`, `outline`, `Reply`, or
`Open` in its API or implementation.

The pair is not intended to replace route transitions, overlay transforms,
`Hero` flights, or arbitrary self-measuring layout animation.

## Contract strategy

The current sparse-list version-1 payload has no animation configuration.
Changing its established immediate behavior implicitly would make duration
and reduced-motion semantics unavailable to typed consumers.

The reusable contract should therefore expose an explicit optional transition
specification before animation becomes general behavior. If the wire payload
must change, introduce a backward-compatible native-widget version rather
than silently reinterpreting version 1. Version 1 remains a valid immediate
transition, and the new version may carry duration, curve, and enablement
fields.

The internal progress connection between `SparseExtentListHost` and
`MorphingSurfaceHost` remains Flutter-local. It is not an FFI event stream and
does not require a core protocol frame for every tick.

No change under `spec/` and no dune-file change is expected for this design.

## Accessibility and input behavior

- Reduced motion resolves both hosts directly to the target while preserving
  expand, collapse, `Reply`, `Open`, star, swipe, and scroll behavior.
- Only the target interactive tree participates in hit testing during a
  transition; outgoing visuals are `IgnorePointer` equivalents.
- Outgoing visual content is excluded from semantics to prevent duplicate
  announcements.
- The collapsed/expanded semantic value reflects committed application state,
  not an intermediate visual percentage.
- Connector decoration remains non-semantic.
- Horizontal swipe and vertical scroll gesture arbitration remains owned by
  the existing native hosts.
- A canceled or interrupted transition emits no application action by itself.

## Verification requirements

### `SparseExtentListHost`

- Observable intermediate extents exist between the collapsed and expanded
  targets.
- The activated visible item remains anchored while later rows move.
- Multiple changed indexes interpolate correctly during an accordion switch.
- Rapid target changes retarget from the current effective geometry.
- Visible-range math uses interpolated extents and emits the correct settled
  range.
- Mount count remains bounded by the supplied child window.
- Reduced motion applies the final extent immediately.
- Controllers and listeners are disposed with the retained resource.

### `MorphingSurfaceHost`

- Row-to-card and card-to-row transitions both use the parent-owned progress.
- Surface inset, radius, elevation, and content phases reach exact endpoints.
- The stable header does not visibly jump between widget trees.
- Collapse retains outgoing content until it can be safely clipped away.
- Outgoing content cannot receive taps or semantic focus.
- Mid-flight reversal is continuous and does not flash either endpoint.
- Reduced motion shows only the final target state.

### Mail integration

- Expansion still does not mark a message read or open the detail route.
- Collapse still changes only inline expansion state.
- `Open` remains the only card action that selects the existing detail page.
- Star, swipe, `Reply`, `Open`, collapse, and scrolling do not cross-activate.
- Back from detail restores the same expanded card and retained scroll offset.
- Accordion switching animates old and new items without an empty region or
  viewport jump.
- Reply-notice extent changes remain valid while the card is expanded.

## Recommended delivery sequence

1. Add transition and reduced-motion tests for interpolated sparse extents,
   anchoring, accordion switching, interruption, and settled range reporting.
2. Implement the `SparseExtentListHost` master timeline and interpolated
   geometry independently of Mail visuals.
3. Add bidirectional `MorphingSurfaceHost` tests for surface endpoints,
   outgoing-content retention, semantics, hit testing, and reversal.
4. Implement `MorphingSurfaceHost` as a generic consumer of parent-owned
   progress.
5. Refactor the Mail compact and expanded compositions so their stable header
   geometry can participate in the morph without Mail state entering Flutter.
6. Add real-FFI and compact-device Profile coverage, then tune duration and
   content intervals without changing the ownership model.

## Decision summary

- Use the names `SparseExtentListHost` and `MorphingSurfaceHost`.
- Keep one master progress owned by `SparseExtentListHost`.
- Make the transition inline, bidirectional, interruptible, and reduced-motion
  aware.
- Let `SparseExtentListHost` own extent, list movement, anchoring, and range
  reporting.
- Let `MorphingSurfaceHost` own row/card surface appearance, content reveal,
  outgoing-content retention, input gating, and semantics gating.
- Keep committed state and final targets in OCaml.
- Keep both Flutter components generic and compose Mail-specific behavior
  above them.
- Do not use a route, `Hero`, overlay, or per-frame FFI updates.
