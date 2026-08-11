# Secure Network Lab

This example keeps HTTPS and secure WebSocket behavior in the OCaml Worker
Domain. Flutter starts the `network` entrypoint and mechanically renders the
logical UI tree; it contains no HTTP, WebSocket, TLS, retry, or application
state logic.

## macOS

Build, analyze, test, and run through the consumer workflow:

```sh
cd examples/network
../../_build/default/bonsai_flutter_tool/bin/main.exe build macos --profile debug
cd flutter
../../../_build/default/bonsai_flutter_tool/bin/main.exe exec \
  --profile=debug -- flutter analyze
../../../_build/default/bonsai_flutter_tool/bin/main.exe exec \
  --profile=debug -- flutter test --no-pub
cd ..
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

The deterministic OCaml and Flutter test suites use no public network service.
The application endpoints are manual smoke-test conveniences configured in
`network_example.ml`.

After deterministic tests pass, exercise the production HTTPS and WebSocket
providers against the configured public endpoints with:

```sh
cd examples/network
dune exec --root=. ocaml/network_smoke_cli.exe
```

This command is manual-only and is intentionally excluded from CI.

## Verified macOS arm64 gate

The current macOS arm64 build produces a 25,902,260-byte staged complete
object. The release application is 36,728 KiB, compared with 32,840 KiB for
the counter baseline, for a 3,888 KiB application-size delta.

Debug, profile, and release application bundles pass strict code-signing
verification. Their native framework links only itself through `@rpath` and
`libSystem`; it has no unresolved GMP, OpenSSL, `libssl`, `libcrypto`, or
Secure Transport wrapper symbols. The actual debug application completed an
HTTPS 200 response, a WSS connect and text echo, and a normal disconnect on
macOS arm64.

## Verified iPhoneOS arm64 gate

The locked iPhoneOS closure contains 88 runtime packages, two target-build
packages, and 128 unique findlib components. The staged network complete object
is a 25,888,424-byte arm64 Mach-O object with an iOS 15.0 minimum deployment
target.

Debug, profile, and release iPhoneOS application bundles pass native framework,
install-name, dependency, export, privacy-manifest, and dSYM verification. The
release application is 31,944 KiB, compared with 27,968 KiB for the counter
baseline, for a 3,976 KiB application-size delta. Its native framework is
15,982,064 bytes and links `Security.framework` plus `libSystem`; it has no
unresolved OpenSSL, `libssl`, `libcrypto`, or Secure Transport wrapper symbols.

The signed physical-iPhone probe completed verified loopback TLS, HTTPS,
cancel, WSS echo, disconnect, NSS trust rejection, wrong-host rejection, public
HTTPS, and public WSS. The signed product application then installed and
launched on the same device, remained alive while backgrounded, and resumed
with the same process after returning to the foreground.
