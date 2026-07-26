# Upstream patches

The project does not carry an OCaml 5.4 compatibility layer.

The selected Bonsai preview supports OCaml 5.3 through `ppxlib` 0.35.0. On
macOS, its matching `basement` revision needs the small portability patch in
[`basement-macos.patch`](basement-macos.patch):

- use the public `Caml_state` runtime macro;
- prevent OCaml's internal `fallthrough` macro from expanding inside Apple's
  dispatch headers.

The patch is limited to the upstream dependency and does not change
`bonsai_flutter` APIs or runtime behavior. It was applied to
`janestreet/basement` commit
`5c640c230a3989f8e505cda7aa6aca9925a23a5b` and the full OCaml build and test
suite passed on the recorded macOS arm64 host.

Remove this patch when the selected upstream `basement` revision contains the
equivalent fixes.
