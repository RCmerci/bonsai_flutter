# Changelog

## Unreleased

- Aligned the native protocol query and Dart version contract with generated
  renderer protocol 2.27, whose constrained-box maxima use explicit optional
  values for unbounded layout.

## 0.0.1

- Replaced runtime-driving ABI v1 with exact ABI 2.0 while retaining renderer
  protocol 1.12. Added monotonic pump calls, presentation identity, explicit
  success and rejection, and stable scheduler and clock errors.
- Regenerated Dart bindings and extended owned-buffer coverage across success,
  recoverable, fatal, and diagnostic outputs. The complete-object audit
  rejects removed ABI v1 symbols.
- Bootstrapped the Dart native-assets build hook on macOS arm64.
- Replaced the package template API with the stable `bf_runtime_*` C ABI,
  generated bindings, and an owned-buffer Dart wrapper.
- Added the opt-in OCaml complete-object build-hook route, named-callback
  bridge, runtime handle registry, and real Flutter-to-Bonsai Counter
  integration coverage.
