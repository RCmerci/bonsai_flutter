# GADT Widget Refactoring Plan

- Status: Planning
- Date: 2026-07-28

## Goal

Merge the current `Kind.t` (52 constructors) and `props` (45 constructors) — two independent ADTs with no compile-time relationship — into a single GADT `'k node` where each constructor simultaneously carries its kind identity and its props data. This makes kind/props mismatch impossible to express.

## Current State

```ocaml
(* widget.ml — current: kind and props are independent *)
type t = { view : view }
and view =
  { key : Key.t option
  ; test_id : Test_id.t option
  ; kind : Kind.t              (* enum tag, 52 constructors *)
  ; props : props              (* separate union, 45 constructors *)
  ; event_bindings : event_binding array
  ; children : child array
  ; fingerprint : int64
  }
```

Problem: `(Kind.Text, Icon_props { code_point = ... })` compiles but is semantically wrong. Safety relies entirely on the private `create` function hard-coding correct pairings.

## Target State

```ocaml
(* widget.ml — target: single GADT *)
type t = T : 'k view -> t              (* existential wrapper *)
and child = { widget : t; parent_data : child_parent_data }
and 'k view =
  { key : Key.t option
  ; test_id : Test_id.t option
  ; node : 'k node                     (* kind + props fused *)
  ; event_bindings : event_binding array
  ; children : child array
  ; fingerprint : int64
  }
and 'k node =
  | Empty : [ `Empty ] node
  | Text : { value : string; style : ...; text_align : ...; max_lines : ...; overflow : ... }
      -> [ `Text ] node
  | Icon : { code_point : int; font_family : ...; size : ...; color : ... }
      -> [ `Icon ] node
  | ... (* all 52 constructors, each carrying its own props inline *)
```

## Key Design Decisions

### D1: Existential wrapper `T : 'k view -> t`

`Widget.t` must remain abstract (public API unchanged). The type index `'k` is hidden via existential wrapping. Every consumer unpacks with `let T { node; _ } = w in ...`.

### D2: `kind_tag` projection for kind-only consumers

Several modules need only the kind (not props): `runtime_error.ml` error reports, `reconciler.ml` key-conflict detection, `mounted_tree.ml` compatibility check. A projection function bridges this:

```ocaml
type kind_tag = K_empty | K_text | K_icon | ...   (* 52 variants, mirrors old Kind.t *)

let node_kind_tag (type k) (n : k node) : kind_tag =
  match n with
  | Empty -> K_empty
  | Text _ -> K_text
  | Icon _ -> K_icon
  | ...
```

`kind_tag` replaces `Kind.t` in all kind-only contexts. It is structurally identical to the old `Kind.t` — the same 52-variant enum with `compare`/`equal`/`to_string`.

### D3: Reconciler two-phase diff preserved

Current logic: `Kind.equal` first (remount if different), then `props_equal` (update if different). With GADT:

```ocaml
let old_kind = node_kind_tag old_node in
let new_kind = node_kind_tag new_node in
if not (kind_tag_equal old_kind new_kind) then Remount
else if not (node_equal old_node new_node) then Update_node
else No_change
```

Verified by compilation — the two-phase strategy works unchanged via projection.

### D4: Frame patch data carrier

`Update_props of { node_id; props : props }` becomes `Update_node of { node_id; widget : t }` since there is no standalone `props` type. The receiver unpacks the widget to extract node data. This is a data-packing change, not a semantic change.

### D5: Serialization boundary unchanged

`wire_frame.ml` keeps its separate `node_kind` and `props` ADTs. `driver.ml` converts GADT (`'k node`) to wire types in a single match per constructor (simpler than current two-function approach). The GADT type index is erased at the protocol boundary.

---

## Phased Plan

### Phase 1: Core type definition (`widget.ml` + `widget.mli`)

**Scope:** Define the GADT `'k node`, `kind_tag`, existential wrapper `t`, and projection functions. Rewrite all 46 constructor functions.

**Files:**
- `ocaml/ui/widget.ml` — rewrite: `Kind` module → `node` GADT + `kind_tag`; `props` type eliminated; `view` → `'k view` + existential `T`; `create` → `create_typed` with GADT constructor; all 46 constructors updated; `props_equal` → `node_equal`; `fingerprint` updated
- `ocaml/ui/widget.mli` — update `Private` module: `Kind.t` → `kind_tag`; `props` → `'k node` (existential); `view` → `'k view` + `T`; add `node_kind_tag`, `kind_tag_equal`, `kind_tag_to_string`, `node_equal`

**Validation:** `dune build ocaml` compiles. Existing widget tests pass (they use public API, which is unchanged).

**Estimated effort:** Largest single phase. ~46 constructor rewrites + type definitions + equality/fingerprint.

### Phase 2: Runtime core (`reconciler` + `mounted_tree` + `frame_patch` + `runtime_error`)

**Scope:** Update the runtime modules that store and compare nodes.

**Files (13 references):**
- `ocaml/runtime/reconciler.ml` (13 refs) — `view.kind` → `node_kind_tag view.node`; `Kind.equal` → `kind_tag_equal`; `props_equal` → `node_equal`; `view.props` → unpack from `view.node`
- `ocaml/runtime/mounted_tree.ml` (6 refs) — `Snapshot.node` fields `kind` + `props` → `node_tag : kind_tag` + `node : 'k node` (existential); `node_equal` uses `kind_tag_equal` + `node_equal`; `find_by_text` matches on GADT
- `ocaml/runtime/frame_patch.ml` (3 refs) — `Operation.create_node` fields `kind` + `props` → `node_tag` + `widget : t`; `Update_props` → `Update_node`
- `ocaml/runtime/runtime_error.ml` (4 refs) — `path_segment.kind` → `kind_tag`; `duplicate_occurrence.kind` → `kind_tag`; `Kind.to_string` → `kind_tag_to_string`

**Validation:** `dune build ocaml` compiles. Reconciler tests pass.

### Phase 3: Driver / serialization (`driver.ml`)

**Scope:** Merge `wire_node_kind` + `wire_props` into a single `wire_node` function that matches the GADT once per constructor.

**Files (1 ref but ~100 match arms):**
- `ocaml/runtime/driver.ml` — `wire_node_kind` (52 arms) + `wire_props` (45 arms) → single `wire_node` (~52 arms, each extracting kind + props together). Simpler than current.

**Validation:** `dune build ocaml` compiles. Protocol tests pass.

### Phase 4: Debug + test support

**Scope:** Update debug output and test helper modules.

**Files (5 refs):**
- `ocaml/ui/debug.ml` (2 refs) — `Kind.to_string` → `kind_tag_to_string`; props match → GADT match
- `ocaml/test_support/query.ml` (2 refs) — `Kind.to_string` → `kind_tag_to_string`; `Text_props` match → GADT match
- `ocaml/test_support/handle.ml` (1 ref) — `Kind.to_string` → `kind_tag_to_string`; props match → GADT match

**Validation:** `dune build ocaml` compiles. Test support compiles.

### Phase 5: Tests

**Scope:** Update test assertions that reference `Kind.t` constructors or `props` variants directly.

**Files (29 refs):**
- `ocaml/test/core_tests.ml` (19 refs) — `Kind.Text` → `K_text`; `Kind.Empty` → `K_empty`; `Text_props { value; _ }` → GADT match; `Pressable_props {...}` → GADT match; `Text_input_props {...}` → GADT match; `Page_props {...}` → GADT match
- `ocaml/test/native_widget_tests.ml` (10 refs) — `Kind.equal view.kind Native_widget` → `kind_tag_equal (node_kind_tag view.node) K_native_widget`; `Native_widget_props {...}` → GADT match

**Validation:** `dune test ocaml` — all existing tests pass.

---

## What Does NOT Change

| Module | Reason |
|--------|--------|
| `protocol/wire_frame.ml` | Protocol layer stays as separate ADTs |
| `protocol/binary_codec.ml` | Operates on wire_frame types, not widget types |
| `protocol/generated_protocol.ml` | Generated from spec, unaffected |
| `ocaml/ui/material.ml` | Only calls `Widget.Private.*` functions |
| `ocaml/ui/cupertino.ml` | Only calls `Widget.Private.*` functions |
| `ocaml/ui/native_widget.ml` | Only calls `Widget.Private.*` functions |
| All examples / integration tests | Only use public API (`Widget.t` is abstract) |
| All Flutter Dart code | Protocol unchanged |

## Public API Impact

**Zero change.** `Widget.t` remains abstract. All public constructor functions (`text`, `icon`, `row`, `column`, `Flex.row`, `Stack.create`, `Body.Vertical.create`, etc.) keep the same signatures. The existential wrapper is internal.

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| GADT exhaustiveness warnings unreliable in OCaml 5.1 | Add explicit `| _ -> ...` or `[@warning "-8"]` where needed; verify with tests |
| Existential unpacking boilerplate in 65+ sites | Mechanical pattern; can be automated with a one-line `let T { node; key; children; event_bindings; test_id; fingerprint } = w in ...` |
| `kind_tag` duplicates old `Kind.t` | Intentional — `kind_tag` is the projection target for kind-only consumers. It is smaller (no props) and serves a different purpose |
| `mounted_tree` snapshot stores existential | Snapshot node carries `node_tag : kind_tag` for quick comparison + `node : 'k node` wrapped in existential for full data |
| Performance: existential allocation | `T` constructor is a single allocation, same order as current `{ view = {...} }` |

## Constructor Mapping Reference

Full mapping from current `Kind.t` + `props` pairs to GADT `'k node` constructors:

| Kind.t | props | GADT constructor |
|--------|-------|------------------|
| Empty | Empty_props | `Empty : [ `Empty ] node` |
| Text | Text_props { value; style; text_align; max_lines; overflow } | `Text : {...} -> [ `Text ] node` |
| Rich_text | Rich_text_props { spans } | `Rich_text : { spans } -> [ `Rich_text ] node` |
| Icon | Icon_props { code_point; font_family; size; color } | `Icon : {...} -> [ `Icon ] node` |
| Image | Image_props { uri; fit; width; height } | `Image : {...} -> [ `Image ] node` |
| Row / Column | Linear_props | `Row : [ `Row ] node` / `Column : [ `Column ] node` |
| Flex_row / Flex_column | Linear_props | `Flex_row : [ `Flex_row ] node` / `Flex_column : [ `Flex_column ] node` |
| Stack | Stack_props | `Stack : [ `Stack ] node` |
| Button | Button_props { enabled } | `Button : {...} -> [ `Button ] node` |
| Padding | Padding_props { left; top; right; bottom } | `Padding : {...} -> [ `Padding ] node` |
| Align | Align_props { alignment } | `Align : {...} -> [ `Align ] node` |
| Center | Center_props { width_factor; height_factor } | `Center : {...} -> [ `Center ] node` |
| Sized_box | Sized_box_props { width; height } | `Sized_box : {...} -> [ `Sized_box ] node` |
| Constrained_box | Constrained_box_props { min_width; max_width; min_height; max_height } | `Constrained_box : {...} -> [ `Constrained_box ] node` |
| Decorated_box | Decorated_box_props { background; border_radius } | `Decorated_box : {...} -> [ `Decorated_box ] node` |
| Clip | Clip_props { behavior } | `Clip : {...} -> [ `Clip ] node` |
| Opacity | Opacity_props { opacity } | `Opacity : {...} -> [ `Opacity ] node` |
| Animated_opacity | Animated_opacity_props { opacity; animation } | `Animated_opacity : {...} -> [ `Animated_opacity ] node` |
| Transform | Transform_props { matrix4 } | `Transform : {...} -> [ `Transform ] node` |
| Scroll_view | Scroll_view_props { axis; reverse; primary } | `Scroll_view : {...} -> [ `Scroll_view ] node` |
| List_view | List_view_props { axis; reverse; primary } | `List_view : {...} -> [ `List_view ] node` |
| Gesture | Gesture_props | `Gesture : [ `Gesture ] node` |
| Focus_scope | Focus_scope_props { autofocus } | `Focus_scope : {...} -> [ `Focus_scope ] node` |
| Mouse_region | Mouse_region_props { opaque } | `Mouse_region : {...} -> [ `Mouse_region ] node` |
| Keyboard_listener | Keyboard_listener_props { autofocus; key_policy } | `Keyboard_listener : {...} -> [ `Keyboard_listener ] node` |
| Pressable | Pressable_props { overlay_color; release_delay_ms } | `Pressable : {...} -> [ `Pressable ] node` |
| Semantics | Semantics_props { label; hint; value; role; ...; actions } | `Semantics : {...} -> [ `Semantics ] node` |
| Theme | Theme_props { brightness; color_seed } | `Theme : {...} -> [ `Theme ] node` |
| Material_scaffold | Material_scaffold_props { has_app_bar } | `Material_scaffold : {...} -> [ `Material_scaffold ] node` |
| Material_app_bar | Material_app_bar_props { center_title } | `Material_app_bar : {...} -> [ `Material_app_bar ] node` |
| Material_elevated_button | Material_button_props { variant; enabled; autofocus } | `Material_elevated_button : {...} -> [ `Material_elevated_button ] node` |
| Material_text_button | Material_button_props { variant; enabled; autofocus } | `Material_text_button : {...} -> [ `Material_text_button ] node` |
| Material_icon_button | Material_button_props { variant; enabled; autofocus } | `Material_icon_button : {...} -> [ `Material_icon_button ] node` |
| Material_checkbox | Material_checkbox_props { value; enabled } | `Material_checkbox : {...} -> [ `Material_checkbox ] node` |
| Material_switch | Material_switch_props { value; enabled } | `Material_switch : {...} -> [ `Material_switch ] node` |
| Material_list_tile | Material_list_tile_props { enabled; selected; has_subtitle; has_leading; has_trailing } | `Material_list_tile : {...} -> [ `Material_list_tile ] node` |
| Material_divider | Material_divider_props { thickness } | `Material_divider : {...} -> [ `Material_divider ] node` |
| Material_card | Material_card_props { elevation } | `Material_card : {...} -> [ `Material_card ] node` |
| Material_circular_progress_indicator | Material_progress_props { value } | `Material_circular_progress_indicator : {...} -> [ `Material_circular_progress_indicator ] node` |
| Cupertino_button | Cupertino_button_props { enabled } | `Cupertino_button : {...} -> [ `Cupertino_button ] node` |
| Cupertino_switch | Cupertino_switch_props { value; enabled } | `Cupertino_switch : {...} -> [ `Cupertino_switch ] node` |
| Text_input | Text_input_props { session_id; document_revision; ...; max_utf8_bytes } | `Text_input : {...} -> [ `Text_input ] node` |
| Overlay | Overlay_props { alignment; dismissible } | `Overlay : {...} -> [ `Overlay ] node` |
| Navigator | Navigator_props { restoration_scope_id } | `Navigator : {...} -> [ `Navigator ] node` |
| Page | Page_props { page_key; presentation; can_pop; restoration_id } | `Page : {...} -> [ `Page ] node` |
| Safe_area | Safe_area_props { left; top; right; bottom; minimum_left; ...; minimum_bottom } | `Safe_area : {...} -> [ `Safe_area ] node` |
| Environment_boundary | Environment_boundary_props | `Environment_boundary : [ `Environment_boundary ] node` |
| Material_dialog | Material_dialog_props { barrier_dismissible } | `Material_dialog : {...} -> [ `Material_dialog ] node` |
| Native_widget | Native_widget_props { kind_id; version; capabilities; payload } | `Native_widget : {...} -> [ `Native_widget ] node` |

Note: `Material_elevated_button`, `Material_text_button`, `Material_icon_button` currently share `Material_button_props`. In the GADT, each gets its own constructor (carrying the same record type), preserving the distinct kind tags while sharing the props structure.

## Validation Checkpoints

| Checkpoint | Command | Expected |
|------------|---------|----------|
| Phase 1 complete | `dune build ocaml` | Compiles |
| Phase 2 complete | `dune build ocaml` | Compiles |
| Phase 3 complete | `dune build ocaml` | Compiles |
| Phase 4 complete | `dune build ocaml` | Compiles |
| Phase 5 complete | `dune test ocaml` | All tests pass |
| Full integration | `dune runtest` | All tests pass |
| All examples build | `make ci-ocaml` (runs `dune build --root=. @all && dune runtest --root=.` per example) | All 11 examples compile and pass tests |
| Protocol round-trip | `dune test ocaml/test/protocol_tests.ml` | Wire frame encoding unchanged |
