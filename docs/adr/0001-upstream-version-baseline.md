# ADR 0001: Upstream version baseline

- Status: Accepted
- Date: 2026-07-25
- Updated: 2026-07-26

## Context

`bonsai_flutter` needs one reproducible compiler and Jane Street package line.
The selected Bonsai revision is
`f31661450eb133fe89564219d97669c2735c6622`, published as
`v0.18~preview.130.106+341`. It requires `ppxlib` from 0.33.0 through 0.35.x.
`ppxlib` 0.35.0 supports OCaml versions below 5.4, making OCaml 5.3.0 the
newest stable compiler that resolves the complete selected dependency set.

Maintaining a second compiler path made the Bonsai-dependent libraries and
tests optional and obscured which runtime was actually supported.

## Decision

- Pin OCaml to 5.3.0 and Dune to 3.17 or newer.
- Pin Bonsai and Core to `v0.18~preview.130.106+341`.
- Build every Bonsai-dependent library, example, and test unconditionally.
- Use the current continuation API and component signature
  `Bonsai.graph -> 'a Bonsai.t`.
- Use public `Bonsai_driver` operations for creation, flushing, result access,
  effect scheduling, lifecycle queries, lifecycle triggering, and observer
  invalidation.
- Confine construction of the private instrumentation configuration type to
  `Bonsai_runtime_adapter`; the type is required by the public driver
  constructor and does not escape the adapter interface.
- Carry only the two-line macOS `basement` portability fix documented under
  `vendor/patches`; do not add compiler-version branches to framework code.
- Target Flutter stable 3.44.8 with bundled Dart 3.12.2 and the
  `package_ffi` build-hook model.

## Consequences

The repository has one OCaml build graph. A missing Bonsai installation is a
dependency error rather than a reason to silently omit the application
runtime or its tests. `dune build @all` and `dune runtest` therefore cover the
real Bonsai driver path.

The exact compiler pin favors reproducibility over accepting an unverified
new compiler. Moving to a newer OCaml version requires selecting a Bonsai/Jane
Street package line that resolves on it and passing the full OCaml, native,
Flutter, and macOS integration suites first.

The current Bonsai effect implementation is delivered transitively through
`virtual_dom.ui_effect`. `bonsai_flutter` uses `Bonsai.Effect` only; it does not
use the Virtual DOM view API. This upstream package layering remains isolated
from the public UI model.
