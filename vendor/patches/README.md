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

## iOS target patches

`ios/jst-config-host-discover.patch` applies to `janestreet/jst-config` commit
`058a69f3e11c96196a3eb4a449e74d2936ec186d`. The upstream rule aliases
`discover.exe` through a named dependency and then executes `%{first_dep}`.
Dune 3.24 cannot recognize that indirection as a host tool while building an
`ios` context, so it attempts to link and run an iOS executable during the
build.

The patch expresses the same dependency directly in the `run` action. Dune's
cross-compilation rule then selects the native host executable, while
`dune-configurator` receives the target context and probes with the iOS
compiler. The generated `config.h` behavior is unchanged except that it now
describes the intended Apple target.

Remove this patch when upstream invokes the discovery executable directly or
when Dune recognizes executable aliases in cross-context actions.
