# Binary protocol

The production protocol is versioned, little-endian, length-delimited, and
generated from `protocol/schema.sexp`. JSON and S-expressions are permitted
only for debug output and readable test fixtures.

## Frame header

Every frame starts with this fixed 48-byte header:

| Offset | Width | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic `BFFR` (`0x52464642` as little-endian `u32`) |
| 4 | 2 | Protocol major (`u16`) |
| 6 | 2 | Protocol minor (`u16`) |
| 8 | 2 | Header size, currently 48 (`u16`) |
| 10 | 1 | Frame kind (`u8`) |
| 11 | 1 | Flags (`u8`) |
| 12 | 8 | Runtime epoch (`u64`) |
| 20 | 8 | Base revision (`u64`) |
| 28 | 8 | Target revision (`u64`) |
| 36 | 4 | Payload length (`u32`) |
| 40 | 4 | CRC32C or zero when the checksum flag is clear (`u32`) |
| 44 | 4 | Reserved, must be zero (`u32`) |

The current decoder rejects a wrong magic, unsupported major or newer minor
version, short or noncanonical header, nonzero flags, nonzero checksum or
reserved fields, an inconsistent payload length, truncated input, trailing
operation bytes, and frames above the configured maximum. CRC32C negotiation
is reserved for a later compatible protocol minor version; version 1.18
requires the flags and checksum fields to be zero.

## Frame kinds

- `Handshake` exchanges protocol ranges and renderer capabilities.
- `Full_snapshot` replaces the complete store and may use base revision zero.
- `Incremental_frame` requires an exact base-revision match.
- `Event_batch` carries typed UI events, environment updates, acknowledgments,
  resync requests, and host responses toward OCaml.
- `Runtime_error` carries a structured safe error.

Payload operations have a one-byte opcode, a four-byte byte length, and a
kind-specific generated body. A decoder validates the body length before
allocating.

Version 1.18 uses these primitive encodings:

- integers are unsigned little-endian values of their declared width;
- runtime IDs and revisions are restricted to the positive `int64` range;
- strings are `u32 byte_length` followed by strict UTF-8 bytes;
- floating-point values are finite little-endian IEEE-754 `f64` values;
- lists carry a bounded count before their elements;
- booleans are exactly byte zero or one.

Optional strings and floats use a one-byte presence tag (`0` absent, `1`
present) before the value. Optional booleans use `0` for absent, `1` for
false, and `2` for true.

## Output operations

- `Begin_frame`
- `Create_node`
- `Update_props`
- `Update_event_bindings`
- `Set_children`
- `Set_root`
- `Drop_node`
- `Host_request`
- `Runtime_notification`
- `End_frame`

`Update_props` begins with the node kind and a generated changed-field bitset.
Fields appear in schema order and use fixed numeric IDs. There is no
`Map<String, Object?>` representation in the hot path.

Protocol 1.12 adds the `AnimatedOpacity` node without changing the existing
`Opacity` payload. Its fixed property body is `opacity:f64`,
`animation_id:u64`, `duration_ms:u32`, and `curve:u8`. Using a new node kind
preserves decoding of frames written by earlier 1.x minor versions. Completion
is an inbound `AnimationCompleted` event carrying the same animation ID;
intermediate values are renderer-local and never appear on the wire.

The implemented widget slice uses these bodies:

| Operation | Body |
| --- | --- |
| `Begin_frame`, `End_frame` | Empty |
| `Create_node` | `node_id:u64`, `node_kind:u16`, full kind-specific props, bindings |
| `Update_props` | `node_id:u64`, prop-layout kind `u16`, changed fields `u64`, changed values |
| `Update_event_bindings` | `node_id:u64`, bindings |
| `Set_children` | `node_id:u64`, count `u32`, child IDs |
| `Set_root`, `Drop_node` | `node_id:u64` |
| `Host_request` | `request_id:u64`, request kind `u16`, typed request body |
| `Set_application_theme` | optional application title plus one structured application-theme value |

Request kind zero inside `Host_request` is `CancelHostRequest` and carries no
body after the request ID. Other request kinds use generated constants.
Clipboard, URL, file, focus, scroll, window, menu, haptic,
platform-information, and layout-measurement bodies are statically typed.

A bindings value is `count:u16`, followed by `(event_tag:u16,
handler_id:u64)` entries. Empty and linear props have no value bytes. The
implemented kind-specific property layouts are:

| Kind | Property body, in generated field-ID order |
| --- | --- |
| Text | `value:string`, optional text style, `text_align:u8`, `max_lines:optional u32`, `overflow:u8` |
| Button | `enabled:bool` |
| Padding | `left:f64`, `top:f64`, `right:f64`, `bottom:f64` |
| Center | `width_factor:optional f64`, `height_factor:optional f64` |
| ScrollView | `axis:u8`, `reverse:bool` |
| Semantics | `label:optional string`, `button:bool`, `enabled:optional bool`, `checked:optional bool` |
| Theme | one structured `theme_data` value used only as a subtree override |
| MaterialCheckbox | `value:bool`, `enabled:bool` |
| TextInput | `session_id:u64`, `document_revision:u64`, editing value, three bool flags, keyboard type, input action, `accepted_local_revision:u64`, update mode, `autofocus:bool` |
| Overlay | `alignment:u8`, `dismissible:bool` |
| Navigator | `restoration_scope_id:optional string` |
| Page | `page_key:string`, standard transition `u8`, `can_pop:bool`, `restoration_id:optional string`, presentation `u8`, typed modal flags and values |
| Material controls | Typed Scaffold slots, button/FAB variants, navigation, radio and segmented-button metadata, slider values, chip roles, and AlertDialog child-presence fields |
| Pressable | `overlay_color:u32 ARGB`, `release_delay_ms:u16` |

`Update_props` carries the exact generated field mask expected for its full
typed property value. Empty and linear values use mask zero; multi-property
values set each implemented field bit. Future fields extend the
kind-specific generated layout rather than inserting a dynamic property map.
Protocol 1.22 adds node kind 124 for Material linear progress with one optional
finite `f64` value. An absent value selects indeterminate progress; a present
value must be in the inclusive range `0.0` through `1.0`. OCaml and Dart both
reject non-finite and out-of-range values at their wire boundaries.
Protocol 1.23 adds node kind 125 for Material segmented buttons and event tag
35 for complete selection changes. Selected IDs use a `u16` count followed by
signed `i64` values in strictly ascending order. Segment metadata uses a `u16`
count followed by stable ID, enabled flag, optional tooltip, and icon/label
presence flags. Optional expanded insets contain four finite non-negative
`f64` values. The canonical child order is the optional custom selected icon,
then each segment's optional icon and optional label in segment order. Both
decoders reject empty segment collections, duplicate segment IDs, segments
without icon or label, non-canonical or unknown selected IDs, invalid single-
or empty-selection policies, hidden custom selected icons, and invalid child
shapes.
Protocol 1.21 adds `Set_application_theme`. Every current-protocol full
snapshot contains exactly one such operation; an incremental frame contains
one only when the logical application theme or title changes. Its bounded
payload contains theme mode, required light and dark `theme_data`, and optional
high-contrast light and dark values. Each `theme_data` contains brightness, a
seed ARGB color, dynamic-scheme variant, contrast level, all fifteen optional
Material typography roles, an optional font family and at most sixteen
fallback names, five shape radii, visual density, and tap-target policy.
Decoders reject unknown enums, non-finite or out-of-range contrast, non-finite
or negative radii, invalid font names, oversized fallback collections, and
inconsistent light/dark brightness before commit. The local Theme node reuses
the identical `theme_data` codec.
Protocol 1.18 includes the Page presentation discriminator, optional modal
barrier ARGB and label, barrier/focus/safe-area flags, two `u32` motion
durations, typed modal sizing and detent fields, required detent-handle
semantics, and the vertical scrollable `primary` flag.
Standard pages encode canonical zero modal fields; modal pages must encode
`No_transition` in the standard transition slot because presentation, not
transition, selects the route class. Both decoders reject invalid
discriminators, booleans, optional values, noncanonical standard fields, and
out-of-range encoded values.
Protocol 1.13 extends Text with optional font size, font weight, line height,
and ARGB color, followed by alignment, an optional positive line limit, and
overflow behavior. A missing style preserves Flutter defaults.
The TextInput editing value is a UTF-8 string, an ordered pair of `u32`
selection offsets, and an optional ordered pair of `u32` composing offsets.
Every offset is a UTF-16 code-unit boundary. Keyboard type, input action, and
update mode are bounded `u8` enums.

Version 1.18 decoders continue to accept earlier 1.x frames whose operations
use layouts defined by that earlier minor version. In particular, the protocol
test suite decodes the value-only Text layout from 1.12 and the unchanged
`Opacity` layout from 1.11.

## Event batches

An `Event_batch` reuses the fixed frame header. `runtime_epoch` identifies the
runtime, `base_revision` is the first event's displayed revision, and
`target_revision` carries the last accepted event sequence. An empty batch
uses zero for both metadata fields.

The payload starts with `event_count:u32`. Each event is length-delimited by a
`body_length:u32` and then contains:

| Field | Encoding |
| --- | --- |
| Event sequence | `u64` |
| Displayed frame revision | `u64` |
| Node ID | `u64` |
| Handler ID | `u64` |
| Event tag | `u16` |
| Payload | Tag-specific fixed layout |

The displayed-frame revision is the latest committed `NodeStore` revision when
the widget callback's handler ID still matches that node. If the binding was
replaced before Flutter rebuilt the stateful host, the event instead uses the
revision that created the old callback. This keeps the revision and handler ID
from a compatible frame without making unchanged callbacks stale. OCaml
retains the immediately preceding handler frame as a bounded grace period;
superseded events older than that remain stale and are rejected.

Sequences must be strictly increasing. The implemented Phase 3 slice supports
unit payloads for Press/LongPress, one-byte bool for FocusChanged and
ValueChanged, UTF-8 string
for TextSubmit, `u64` for AnimationCompleted, two finite `f64` values
(`pixels`, `delta`) for ScrollNotification, and two ordered `u64` indices for
VisibleRangeChanged. Other schema tags are rejected until their typed layouts
are implemented; they are never decoded as a dynamic map.

TextEdit carries `session_id:u64`, `local_revision:u64`,
`base_document_revision:u64`, a UTF-8 string, UTF-16 selection offsets, and
optional UTF-16 composing offsets. Both decoders reject reversed, out-of-range,
or split-surrogate ranges.

RoutePop carries a nonempty UTF-8 page key and an optional UTF-8 result.
HostResponse carries `request_id:u64`, status `u8` (`ok`, `error`, or
`cancelled`), and a `u32`-length-delimited typed result. Host responses use
node and handler ID zero and are resolved by the driver before normal handler
dispatch.

EnvironmentChanged also uses node and handler ID zero. Its fixed body contains
viewport width and height, device-pixel ratio, text scale, brightness,
platform, locale, safe-area and keyboard insets, accessibility flags,
orientation, and a pointer-kind bitset. Flutter emits it only when the
semantic snapshot changes.

`protocol/generated/fixtures/dart_counter_press.hex` is the canonical Button
event. Dart produces it with `EventBatchCodec`, and OCaml decodes and validates
the same bytes.

The OCaml `Driver` validates every handler reference and event sequence in a
batch before committing its sequence cursor. Driver-created handlers enqueue
Bonsai effects rather than applying them immediately. If any event is invalid,
the queue is cleared and no effect from that batch reaches
`Bonsai_driver.flush`.

## Transaction semantics

Dart decodes and applies a frame to a transaction shadow state. Before commit
it verifies:

- protocol, epoch, and revision;
- node uniqueness and kind-specific properties;
- every child reference and the root reference;
- absence of cycles and multiple parents where prohibited;
- event bindings compatible with the node kind;
- drops that leave no live reference.

Only a fully valid transaction replaces the `NodeStore`. Subscribers are
notified once with the dirty node set. Failure exposes none of the shadow
state and requests a full snapshot or enters a structured fatal state.

## Resynchronization

If `frame.base_revision` differs from `NodeStore.revision`, Dart does not apply
the frame. It sends `Resync` with its epoch and revision. OCaml returns a full
snapshot at a new target revision and increments the resync instrumentation
counter.

## Limits

Limits are runtime configuration with conservative defaults:

- 16 MiB maximum frame;
- 1 MiB maximum string;
- 1,000,000 maximum operations;
- 1,000,000 maximum nodes;
- 1,000,000 maximum child references for one operation;
- checked arithmetic for every offset and allocation.

Malformed input cannot request an unbounded allocation or cause an unchecked
out-of-range read.

## Generation and golden data

`protocol/schema.sexp` is parsed and validated by the OCaml generator. It emits
the committed OCaml and Dart numeric constants, debug-name lookups, and
`protocol/generated/protocol-ids.md`. Duplicate names and IDs are rejected.

Run:

```sh
dune exec protocol/generator/generate.exe --
dune exec protocol/generator/generate.exe -- --check
make protocol-fixtures-generate
make protocol-fixtures-check
```

Generated IDs and generated binary fixtures are separate clean-tree checks.
The fixture target has two explicit owners:

| Producer | Consumer | Canonical fixtures |
| --- | --- | --- |
| OCaml `Binary_codec` | Dart `FrameCodec` and `NodeStore` | empty incremental frame, Counter full snapshot, Unicode update, child reorder, host request, animated opacity |
| Dart `EventBatchCodec` | OCaml `Event_batch_codec` and dispatcher | Counter press, host response, Unicode text edit, environment change |

Every opposite-language test decodes the committed bytes, validates their
typed contents, and re-encodes the equivalent value byte for byte.
The shared incremental fixture is also applied against wrong epoch and
revision state to prove rejection before mutation. Malformed length, unknown
kind or tag, wrong version, truncation, and oversized-input coverage remains
in the bounded decoder suites.
