# Update DataScript and Melange Transit 0.1.2

## Problem

The checked-in iPhoneOS application and supported dependency closures pin
`datascript-ocaml` before its Transit 0.1.2 dependency update and pin
`melange-transit-core` and `melange-transit-native` at 0.1.1. Current
DataScript native metadata requires Melange Transit 0.1.2, whose native codec
preserves evaluation order while decoding and encoding cached compound values.
Leaving the SDK closure stale prevents DataScript consumers from selecting the
updated package set and retaining that correctness fix.

## Proposal

Update the application fixture to DataScript commit
`40345cc2f59214daa88b33b8aec711337d20afa7` and Melange Transit 0.1.2 commit
`35f8afe7d6506863c7253e67a20befb3dde5c18f`. Regenerate the reference,
supported, and SDK repository closures with immutable archive checksums.
Remove the obsolete Melange Transit 0.1.1 package paths and increment both the
runtime SDK package version and framework SDK package version. Keep the
protocol ABI and SDK build recipe revisions unchanged.

## Alternatives considered

### Keep the current closure

Allow non-iOS consumers to resolve the updated DataScript stack independently.
This was not selected because the immutable iPhoneOS runtime would disagree
with DataScript's exact Transit dependency and would retain the Transit 0.1.1
codec behavior.

### Retain both Transit versions

Add 0.1.2 metadata beside 0.1.1. This was not selected because the generated
SDK repository is a deterministic snapshot, not a compatibility repository;
obsolete package paths must be removed.

## Acceptance criteria

- The application fixture pins the exact DataScript and Melange Transit commits.
- Reference and supported closure locks select Transit 0.1.2 with verified
  immutable source checksums.
- Generated iOS repository metadata contains only the selected Transit 0.1.2
  package paths.
- Runtime and framework SDK package versions advance without changing the ABI
  or build recipe revisions.
- Closure contract checks, SDK regeneration checks, and relevant builds pass.

## Risks

- The runtime SDK identity changes, so installed iPhoneOS toolchains require a
  complete replacement rather than a framework-only update.
- Incomplete closure regeneration or incorrect source checksums would make the
  immutable SDK unbuildable.

## Questions

- None. The user selected the dependency versions and requested both framework
  and iOS SDK updates.
