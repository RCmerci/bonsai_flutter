# Protocol schema

`schema.sexp` is the single source of truth for stable numeric protocol IDs.
The schema is declarative input to the OCaml generator. Generated OCaml and
Dart constants and debug names plus the readable ID table are committed. CI
runs the generator in `--check` mode.

IDs are never reused. Removing a field reserves its old ID. Additive optional
fields increment the protocol minor version; incompatible encoding or semantic
changes increment the major version.

The S-expression is not a runtime serialization format.

Generate or verify the committed artifacts from the repository root:

```sh
dune exec protocol/generator/generate.exe --
dune exec protocol/generator/generate.exe -- --check
make protocol-fixtures-generate
make protocol-fixtures-check
```

The two fixture producers have explicit ownership. OCaml generates
`ocaml_*.hex` output frames for the Dart decoder; Dart generates
`dart_*.hex` input event batches for the OCaml decoder. The opposite language
validates typed contents and byte-for-byte re-encoding. `counter_full.hex` and
`counter_press.hex` are generated compatibility aliases. CI runs both
producers in `--check` mode and fails on missing or stale fixtures.
