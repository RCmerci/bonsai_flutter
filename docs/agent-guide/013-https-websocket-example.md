# HTTPS and WebSocket Example Implementation Plan

Goal: Add a production-shaped example that performs HTTPS requests and maintains a secure WebSocket connection from the OCaml Worker Domain, with TLS implemented by `tls-eio`.

Architecture: Keep Bonsai state and protocol handling on OCaml domain 0, run all network and TLS work inside the existing Eio Worker session, and keep Flutter as a mechanical renderer and host.

Tech Stack: OCaml 5.1.1, Bonsai v0.17, Eio 1.2, `tls-eio` 2.1.2, `tls` 2.1.2, `ca-certs-nss` 3.126, `httpun-eio` 0.2.0, `httpun-ws` 0.2.0, `gluten-eio` 0.5.2, Flutter, Alcotest, and physical iPhoneOS arm64 validation.

Related: `docs/agent-guide/012-eio-worker-service.md`, `docs/adr/0007-ocaml-worker-domain.md`, `docs/architecture.md`, and `ocaml/runtime/worker.mli`.

## Problem statement

The repository has examples for state, navigation, host effects, SQLite, and Eio Worker services, but it does not demonstrate secure network I/O owned by OCaml.


The new example must cover both a bounded HTTPS GET and a persistent WSS echo session without moving application networking into Dart.


The TLS implementation must be the pure OCaml `tls-eio` stack rather than OpenSSL, Secure Transport bindings, Dart `HttpClient`, or a certificate-verification bypass.


This document is research and implementation planning only.


No production code, test code, Dune file, opam manifest, or build script is changed as part of this planning task.

## Decision summary

Use `tls-eio` for every HTTPS and WSS connection.


Use `ca-certs-nss` for a compiled Mozilla NSS trust store instead of discovering host certificates through operating-system commands.


Initialize `Mirage_crypto_rng_unix` exactly once in the Worker Domain process before the first TLS handshake.


Use HTTP/1.1 only for the first version.


Use `httpun-eio` for HTTPS and `httpun-ws` for WebSocket framing, with `gluten-eio` driving both protocols.


Add an application-private adapter that presents the generic `Tls_eio.t` two-way flow to the stream-socket-shaped `gluten-eio` client API.


Do not add a framework-level `ocaml/worker_http` abstraction in this phase.


Treat macOS and signed physical iPhoneOS arm64 proof as hard gates before committing the full example dependency and build-system changes.

## Testing Strategy

Testing starts with deterministic pure and loopback tests, not public Internet services.


Each implementation task begins with a failing test, records the expected failure, adds the minimum behavior required to pass, and reruns the focused test before broader verification.


The test layers are:

| Layer | Purpose | Network dependency |
| --- | --- | --- |
| Pure unit tests | URI policy, limits, state transitions, generations, and error classification | None |
| Provider contract tests | Worker request, response, push, cancellation, and shutdown behavior | Injected fake |
| TLS loopback tests | Trust, hostname, handshake, timeout, and cancellation | Local process only |
| HTTPS loopback tests | Request formatting, response parsing, bounds, and close behavior | Local process only |
| WSS loopback tests | Upgrade, framing, echo, ping/pong, fragmentation, limits, and close behavior | Local process only |
| Headless Bonsai tests | Commands, status rendering, transcript bounds, and stale event fencing | Injected worker events |
| Platform smoke tests | DNS, entropy, certificates, linking, HTTPS, and WSS on supported Apple targets | Explicit manual endpoint |


Public echo services are manual smoke-test aids only and must never be CI dependencies.


NOTE: I will write *all* tests before I add any implementation behavior.

## Research findings

### Existing Worker runtime fit

`Worker.Session_context.environment`, `clock`, `net`, `switch`, `fork_daemon`, and `emit` already expose the capabilities needed for network services.


An HTTPS request fits a request-owned switch because completion produces one correlated response and cancellation should close its connection.


A WebSocket fits a session-owned daemon because the connection outlives individual Connect, Send, and Disconnect requests and can emit unsolicited pushes.


The existing `Serial` service policy is sufficient for the first version because a suspended request fiber does not block the session daemon or control processing.


The `examples/sqlite_worker` example is the closest structural reference for protocol modules, a Worker service, Bonsai state, headless tests, Flutter packaging, and native object staging.

### TLS stack

`Tls_eio.client_of_flow` accepts an Eio two-way flow and returns a TLS-protected Eio two-way flow.


The call requires an initialized Mirage Crypto RNG and accepts a DNS host for Server Name Indication and hostname verification.


`Tls.Config.client` accepts an X.509 authenticator and ALPN preferences, so the example can require certificate-chain validation and advertise only `http/1.1`.


`ca-certs-nss` supplies Mozilla NSS trust anchors as OCaml data and does not require an iOS application to run a host certificate-discovery command.


The physical iPhoneOS build still needs to prove that the entropy syscall stub and the complete Mirage Crypto dependency closure cross-compile and link correctly.

### HTTP client choice

The initial candidate was `cohttp-eio` 6.2.1 because its HTTPS callback can wrap a generic Eio two-way flow.


An opam dry run against the repository's `bonsai-flutter-v017-exact` switch showed that installing `cohttp-eio` 6.2.1 upgrades `cohttp` from 5.x to 6.2.1 and removes `cohttp_async_websocket`, `async_rpc_websocket`, and Bonsai v0.17.


That dependency transition is unacceptable for an example and makes `cohttp-eio` a rejected option for the current baseline.


The same switch already resolves `httpun-eio` 0.2.0, `httpun-ws` 0.2.0, and `gluten-eio` 0.5.2 without package removal or upgrade.


The plan therefore uses the smaller `httpun` stack directly and keeps the HTTPS response policy application-private.

### Generic TLS flow adapter

`Tls_eio.t` provides Eio flow and close capabilities but is not statically typed as an `Eio.Net.stream_socket`.


The installed `httpun-eio` and `gluten-eio` client functions currently require an Eio stream socket even though their protocol runtimes fundamentally consume reads, writes, shutdown, and close.


The implementation must prove a small capability adapter built with Eio's resource provider interface that delegates only supported flow, shutdown, and close operations to `Tls_eio.t`.


The adapter must not claim `Eio_unix` platform-specific socket operations and must not use unsafe casts.


If Eio 1.2 cannot express this adapter without lying about capabilities, the implementation stops at Phase 0 and reports the upstream API limitation.

### Repository integration constraints

The iOS runtime closure is explicit and locked in `vendor/opam-ios/runtime-closure.lock`.


The current CI contract intentionally rejects `tls-eio`, `ca-certs-nss`, `httpun-eio`, and a legacy `ocaml/worker_http` directory because network transport was out of scope for the preceding Worker phase.


Implementation must update those guards deliberately after the platform spike rather than weakening or deleting the contract wholesale.


The revised contract should require the approved exact packages and continue rejecting OpenSSL, `ssl`, `eio-ssl`, Piaf, insecure modes, and framework-level `ocaml/worker_http` code.

## Goals

- Demonstrate a bounded HTTPS GET whose DNS, TCP, TLS, HTTP, timeout, and cancellation work all run in the OCaml Worker Domain.

- Demonstrate a session-scoped WSS connection with Connect, Send, Receive, Disconnect, and error events.

- Verify certificate chains and DNS hostnames against `ca-certs-nss` trust anchors.

- Preserve the existing Worker request correlation, pump visibility boundary, and structural cancellation model.

- Keep all user-visible state, command decisions, and bounded history in the OCaml Bonsai application.

- Keep Flutter limited to startup configuration, rendering, text input deltas, and platform packaging.

- Make every buffer, body, message, history, timeout, redirect, and command queue explicitly bounded.

- Provide deterministic tests that run without Internet access.

- Prove macOS arm64 and signed physical iPhoneOS arm64 behavior before accepting the dependency closure.

## Non-goals

- HTTP/2, HTTP/3, QUIC, or WebTransport.

- Plaintext `http://` or `ws://` connections.

- Authentication, cookies, credential storage, proxy configuration, or arbitrary custom headers.

- File uploads, streaming downloads, compression, multipart bodies, or binary WebSocket application messages.

- Automatic background reconnection while iOS suspends the application.

- A reusable public HTTP client API in `bonsai_flutter.runtime`.

- A Dart networking fallback.

- Trust-on-first-use, pinning, custom user certificates, or an `allow_insecure` switch.

- Changing public `.mli` files under `spec/`.

## Proposed architecture

```text
Flutter host
  mechanical events and rendering only
          |
          v
OCaml domain 0
  Bonsai state, commands, result rendering, bounded transcript
          |
          | Worker.send / Worker.on_event
          v
OCaml Worker Domain
  one Eio session switch
    HTTPS request fiber
      Eio.Net TCP -> tls-eio -> TLS stream adapter -> httpun-eio
    WebSocket session daemon
      bounded command stream
      Eio.Net TCP -> tls-eio -> TLS stream adapter -> httpun-ws
      reader fiber -> latest/bounded Worker pushes
```


The transport stack is application-private so the example can validate the design without committing the framework to a premature networking API.


The HTTPS path opens one connection per Run action in the first version and closes it after the bounded response is complete.


The WSS daemon owns at most one live connection and one reader fiber at a time.

## Dependency baseline

The first implementation should pin the following versions because they were checked against the current OCaml 5.1.1 and Eio 1.2 switch:

| Package | Version | Role |
| --- | --- | --- |
| `tls-eio` | `2.1.2` | TLS over Eio flows |
| `tls` | `2.1.2` | Pure OCaml TLS protocol and configuration |
| `ca-certs-nss` | `3.126` | Compiled Mozilla NSS trust anchors |
| `mirage-crypto` family | `2.2.0` baseline | Cryptography and RNG support |
| `httpun` | `0.2.0` | HTTP/1.1 protocol engine |
| `httpun-eio` | `0.2.0` | Eio runtime for `httpun` |
| `httpun-ws` | `0.2.0` | RFC 6455 upgrade and framing |
| `gluten-eio` | `0.5.2` | Eio protocol driver |


Exact transitive package pins must come from the successful macOS and iPhoneOS Phase 0 closure rather than from the developer switch alone.


A dedicated example opam package such as `bonsai_flutter_network_example.opam` is preferred over adding networking dependencies to the core `bonsai_flutter.opam` package.


Phase 0 must verify that this packaging choice works with `opam install . --deps-only`, `dune build @all`, CI caching, and iOS closure generation before it is adopted.

## Protocol and state model

The OCaml application protocol should use closed variants rather than stringly typed commands.

```ocaml
type request =
  | Https_get of { request_id : int; uri : string }
  | Websocket_connect of { generation : int; uri : string }
  | Websocket_send of { generation : int; message : string }
  | Websocket_disconnect of { generation : int }

type response =
  | Https_result of https_result
  | Websocket_command_result of websocket_command_result

type push =
  | Websocket_state_changed of websocket_state_event
  | Websocket_message_received of websocket_message_event
```


The exact public shapes belong in the example's own `.mli` files and must be kept immutable across domains.


Every WebSocket command and push includes a monotonically increasing connection generation so domain 0 can reject events from a cancelled or replaced reader fiber.


The UI state should distinguish Idle, Connecting, Connected, Disconnecting, Closed, and Failed rather than deriving connection state from button availability.

## WebSocket daemon lifecycle

The service `init` function starts one session daemon with `Worker.Session_context.fork_daemon`.


The daemon owns a bounded `Eio.Stream` of Connect, Send, and Disconnect commands.


Each request handler submits a command carrying a worker-local promise resolver and awaits its result before returning the correlated Worker response.


No Eio promise, switch, flow, socket, TLS state, or mutable buffer crosses an OCaml Domain boundary.


Connect closes any failed partial transport before publishing Failed.


Disconnect attempts a normal RFC 6455 close handshake within a short deadline and then structurally closes the transport.


Session shutdown fails the session switch, cancels the reader, closes the TLS flow, resolves queued commands with a terminal error, and emits no events after shutdown completes.

## User experience

The example should be named `network` and present a compact "Secure Network Lab" screen.


The HTTPS panel contains a read-only endpoint, a Run HTTPS GET button, a Cancel button while pending, status code, content type, body byte count, a truncated preview, and a sanitized error.


The WebSocket panel contains a read-only endpoint, Connect or Disconnect controls, a revisioned text input, a Send button enabled only while connected, connection status, and a bounded event transcript.


The initial endpoints may use `https://echo.websocket.org/` and `wss://echo.websocket.org`, but must be OCaml configuration constants that can be replaced for tests and manual validation.


The public endpoint is an operational convenience, not an availability guarantee.

## Security and resource policy

| Concern | Initial policy |
| --- | --- |
| Schemes | Accept only `https://` and `wss://` |
| Certificate trust | Require `ca-certs-nss` authentication |
| Hostname | Normalize DNS host and pass it to TLS for SNI and verification |
| ALPN | Advertise `http/1.1` only |
| Connect timeout | 10 seconds |
| Complete HTTPS timeout | 10 seconds |
| Redirects | At most 3, with no secure-to-insecure downgrade |
| Response body | At most 64 KiB |
| WebSocket message | At most 64 KiB after reassembly |
| Transcript | Keep the most recent 50 entries |
| Preview | Truncate by UTF-8-safe character or byte policy defined in tests |
| Command queue | Fixed capacity with explicit Busy result |
| Error text | Classified and sanitized, with no certificate or payload secrets |


The implementation must close or drain resources on every normal, error, timeout, cancellation, redirect, and shutdown path.

## Edge cases to specify in tests

- URI parsing rejects user information, missing hosts, unsupported schemes, fragments where inappropriate, and invalid ports.

- DNS resolution handles no addresses and tries eligible IPv6 and IPv4 candidates within one overall deadline.

- TLS reports unknown issuer, expired certificate, wrong hostname, peer alert, premature EOF, and protocol failure as stable application error classes.

- HTTPS rejects oversized headers and bodies without accumulating unbounded buffers.

- HTTPS handles informational responses, empty bodies, early EOF, malformed framing, and redirect loops.

- WSS validates status `101`, `Upgrade`, `Connection`, and `Sec-WebSocket-Accept` before entering Connected.

- WSS reassembles fragmented text, responds to ping, observes pong, handles clean close, and classifies abnormal EOF.

- Invalid UTF-8 text and binary application messages produce a defined unsupported-message event rather than corrupting state.

- Send while disconnected, duplicate Connect, Disconnect while Connecting, and a full command queue return deterministic errors.

- Cancellation racing with handshake, response completion, receive, or close produces one terminal command result.

- Events from an obsolete connection generation never mutate the current transcript or connection state.

- Application suspend and resume do not assume background execution and reconcile a closed connection without automatic reconnect in the first version.

## Phase 0 feasibility gate

Phase 0 is an isolated spike and must complete before product example modules or permanent manifests are added.


The spike performs these checks:

1. Resolve the exact dependency set with OCaml 5.1.1, Bonsai v0.17, and Eio 1.2 without removing or upgrading the pinned Bonsai dependency family.

2. Initialize `Mirage_crypto_rng_unix` once and complete a verified loopback TLS handshake on macOS arm64.

3. Implement the minimal safe `Tls_eio.t` to `Eio.Net.stream_socket` capability adapter without unsafe casts or unsupported platform operations.

4. Complete one loopback and one explicit manual public HTTPS GET through `httpun-eio`.

5. Complete one loopback and one explicit manual public WSS echo through `httpun-ws`.

6. Cross-build the exact runtime closure and complete native object for iPhoneOS arm64.

7. Link and run the spike in a signed application on a physical iPhone.

8. Verify DNS, entropy, trust anchors, hostname rejection, cancellation, disconnect, and suspend or resume behavior on the device.

9. Record package count, runtime-closure components, native object size, final application size delta, and linked symbols.

10. Confirm there are no OpenSSL, `libssl`, `libcrypto`, Secure Transport wrapper, or Dart networking symbols introduced by the example stack.


If any gate fails, stop and report the precise blocker and the smallest upstream or spec change required.


Do not fall back to OpenSSL, Dart networking, unsafe casts, or disabled certificate verification.

## Implementation tasks

### Task 1: Capture the dependency and platform spike

Files:

- Create `tool/network_spike/README.md`.

- Create `tool/network_spike/dune` only after explicit implementation authorization that includes Dune changes.

- Create `tool/network_spike/network_spike.ml`.

- Modify the opam and iOS closure files selected by the successful dependency experiment.

Steps:

1. Run the exact opam dry run and record the selected package versions in the spike README.

2. Write a failing loopback TLS test proving that an unknown test CA is rejected.

3. Add explicit test trust anchors and prove valid-host success plus wrong-host failure.

4. Write a failing test that exercises the generic TLS flow adapter through `httpun-eio`.

5. Implement only the resource capabilities needed to make that test pass.

6. Repeat for `httpun-ws` upgrade and echo.

7. Run the iPhoneOS closure build, native link verification, and signed physical-device smoke procedure.

8. Stop for review if any Phase 0 criterion fails.

Verification:

```sh
opam install --dry-run --switch=bonsai-flutter-v017-exact \
  tls-eio.2.1.2 tls.2.1.2 ca-certs-nss.3.126 \
  httpun.0.2.0 httpun-eio.0.2.0 httpun-ws.0.2.0 gluten-eio.0.5.2
dune runtest tool/network_spike
./tool/ios/verify_runtime_closure.sh
```

Expected result:

The solver preserves Bonsai v0.17, all loopback checks pass, and the signed physical device completes verified HTTPS and WSS operations without OpenSSL-linked symbols.

### Task 2: Define the example protocol and pure policies

Files:

- Create `examples/network/ocaml/network_protocol.mli`.

- Create `examples/network/ocaml/network_protocol.ml`.

- Create `examples/network/ocaml/network_policy.mli`.

- Create `examples/network/ocaml/network_policy.ml`.

- Create `ocaml/test/network_policy_tests.ml`.

Steps:

1. Write failing tests for accepted and rejected URI forms, size limits, redirects, error classes, and connection generations.

2. Define immutable request, response, push, error, and display-summary values.

3. Implement URI normalization and policy validation without performing I/O.

4. Add bounded transcript insertion and stale-generation filtering.

5. Run the focused tests and then the complete OCaml test suite.

Verification:

```sh
dune runtest ocaml/test
```

Expected result:

Every policy edge case is deterministic and no test opens a network socket.

### Task 3: Implement TLS configuration and the safe flow adapter

Files:

- Create `examples/network/ocaml/network_tls.mli`.

- Create `examples/network/ocaml/network_tls.ml`.

- Create `ocaml/test/network_tls_tests.ml`.

Steps:

1. Write failing tests for RNG initialization ownership, trust-anchor failure, hostname mismatch, timeout, cancellation, shutdown, and adapter capabilities.

2. Build `Tls.Config.client` with `ca-certs-nss`, peer DNS name, and `http/1.1` ALPN.

3. Connect TCP candidates through `Worker.Request_context.net` within one overall timeout.

4. Wrap the successful TCP flow with `Tls_eio.client_of_flow`.

5. Adapt only flow, shutdown, and close capabilities for the protocol runtime.

6. Verify that cancellation closes the underlying TCP and TLS resources.

Verification:

```sh
dune exec ocaml/test/network_tls_tests.exe
```

Expected result:

Valid loopback certificates succeed, invalid trust or hostnames fail, and resource shutdown is leak-free under cancellation.

### Task 4: Implement the bounded HTTPS provider

Files:

- Create `examples/network/ocaml/network_http.mli`.

- Create `examples/network/ocaml/network_http.ml`.

- Create `ocaml/test/network_http_tests.ml`.

Steps:

1. Write failing loopback tests for GET success, empty body, body limit, malformed response, redirects, timeout, and cancellation.

2. Construct an HTTP/1.1 origin-form request with a normalized Host header and fixed safe headers.

3. Drive the request with `httpun-eio` over the TLS adapter.

4. Accumulate at most 64 KiB and cancel the protocol runtime immediately when the limit is exceeded.

5. Return a small immutable response summary rather than the transport objects or mutable body buffers.

6. Implement the bounded redirect policy without scheme downgrade.

Verification:

```sh
dune exec ocaml/test/network_http_tests.exe
```

Expected result:

All HTTPS behaviors pass against the local TLS server and no public network is used.

### Task 5: Implement the session-owned WSS provider

Files:

- Create `examples/network/ocaml/network_websocket.mli`.

- Create `examples/network/ocaml/network_websocket.ml`.

- Create `ocaml/test/network_websocket_tests.ml`.

Steps:

1. Write failing loopback tests for upgrade validation, echo, fragmented text, ping or pong, clean close, abnormal EOF, oversized messages, and cancellation races.

2. Create a bounded command stream and one daemon-owned connection state machine.

3. Perform the HTTP/1.1 WebSocket upgrade through `httpun-ws` over the TLS adapter.

4. Run the reader as a child fiber of the current connection generation.

5. Reassemble text only up to the message limit and classify binary messages as unsupported.

6. Resolve every queued command exactly once during disconnect, replacement, error, or shutdown.

Verification:

```sh
dune exec ocaml/test/network_websocket_tests.exe
```

Expected result:

The loopback WSS server proves framing, lifecycle, backpressure, stale-event fencing, and structural cancellation.

### Task 6: Integrate the Worker service

Files:

- Create `examples/network/ocaml/network_service.mli`.

- Create `examples/network/ocaml/network_service.ml`.

- Create `ocaml/test/network_service_tests.ml`.

Steps:

1. Write failing tests against injected HTTPS and WebSocket provider interfaces.

2. Create a `Worker.Service.Serial` service and start the WSS daemon from session initialization.

3. Route HTTPS requests through request-scoped resources.

4. Route WSS commands through worker-local promises and translate reader activity into bounded pushes.

5. Verify exactly one response per accepted request and no push after session shutdown.

6. Verify that the existing domain-0 pump remains the only visibility boundary.

Verification:

```sh
dune exec ocaml/test/network_service_tests.exe
dune exec ocaml/test/worker_eio_environment_tests.exe
```

Expected result:

Service behavior is deterministic under fake providers, real loopback providers, cancellation, queue pressure, and teardown.

### Task 7: Build the Bonsai application

Files:

- Create `examples/network/ocaml/network_example.mli`.

- Create `examples/network/ocaml/network_example.ml`.

- Create `examples/network/ocaml/native_embed.ml`.

- Create `examples/network/ocaml/dune` only after explicit implementation authorization that includes Dune changes.

- Create `ocaml/test/network_example_tests.ml`.

Steps:

1. Write failing headless tests for initial state, HTTPS actions, Cancel, Connect, Send, Disconnect, status text, bounded history, and stale generations.

2. Implement the HTTPS and WebSocket panels with stable semantics labels and test IDs.

3. Keep endpoint selection and all action decisions in OCaml.

4. Keep response previews and transcript entries bounded before they enter the UI model.

5. Verify that text-input revisions remain coherent while pushes arrive.

Verification:

```sh
dune exec ocaml/test/network_example_tests.exe
dune runtest ocaml/test
```

Expected result:

The headless Driver exposes the complete interaction without requiring Flutter or a network connection.

### Task 8: Add the mechanical Flutter shell

Files:

- Create `examples/network/README.md`.

- Create `examples/network/flutter/pubspec.yaml`.

- Create `examples/network/flutter/lib/main.dart`.

- Create the platform files that match the repository's current example scaffold.

- Create Flutter tests for startup, rendering, and host error presentation.

Steps:

1. Copy the minimal shell shape from `examples/sqlite_worker/flutter` and change only example-specific identifiers and labels.

2. Start `BonsaiFlutterRoot` with the embedded OCaml application.

3. Add no Dart HTTP, WebSocket, TLS, retry, parsing, or application state logic.

4. Run analyzer and tests on macOS.

Verification:

```sh
cd examples/network/flutter
flutter pub get
flutter analyze
flutter test
```

Expected result:

Flutter only renders the OCaml tree and forwards user or lifecycle events.

### Task 9: Integrate build, CI, packaging, and documentation

Files:

- Modify `Makefile`.

- Modify `tool/macos/stage_native_objects.sh`.

- Modify `tool/ios/build_native_objects.sh`.

- Modify `tool/test_ci_contract.sh`.

- Modify `vendor/opam-ios/runtime-closure.lock` and related package recipes only as proven by Phase 0.

- Modify `README.md`.

- Modify opam manifests according to the dependency-package decision from Phase 0.

- Modify `ocaml/test/dune` and example Dune files only with explicit authorization.

Steps:

1. Write failing CI contract assertions for the new example, exact pure OCaml TLS packages, and continued OpenSSL rejection.

2. Add the example to macOS and iPhoneOS native object build and staging lists.

3. Lock the proven iOS runtime closure and verify every archived component.

4. Add the example to Flutter CI loops and repository documentation.

5. Run all repository contract, OCaml, Flutter, macOS, and iOS link checks.

6. Run the documented manual public HTTPS and WSS smoke test only after deterministic suites pass.

Verification:

```sh
./tool/test_ci_contract.sh
dune runtest
make ci-flutter
make example-network-native-object
./tool/macos/stage_native_objects.sh
./tool/ios/verify_runtime_closure.sh
```

Expected result:

The example is included in normal build and CI coverage, the closure is reproducible, and contract tests reject all unapproved TLS backends.

## Expected file impact

The likely new product files are under `examples/network/ocaml`, `examples/network/flutter`, and `ocaml/test`.


The likely modified integration files are `Makefile`, platform staging scripts, CI contract tests, the iOS runtime closure, opam manifests, Dune files, and `README.md`.


No file under `spec/` is expected to change.


All listed paths are proposed implementation scope and are not authorized changes in this planning task.

## Acceptance criteria

- HTTPS and WSS use `tls-eio` and verified `ca-certs-nss` trust anchors end to end.

- No Dart networking API or OpenSSL-backed package participates in either transport.

- The dependency closure preserves Bonsai v0.17 and the pinned OCaml and Eio baseline.

- HTTPS success, TLS rejection, response limits, timeouts, and cancellation pass deterministic loopback tests.

- WSS upgrade, echo, ping or pong, fragmentation, limits, close, and cancellation pass deterministic loopback tests.

- The Worker session owns all network resources and closes them structurally on runtime stop.

- The UI remains responsive and ignores pushes from obsolete connection generations.

- The example works on macOS arm64 and a signed physical iPhoneOS arm64 application.

- CI has no dependency on a public HTTPS or WebSocket service.

- The complete runtime closure is reproducible and contains no OpenSSL-linked symbols.

## Risks and rejected alternatives

| Option | Decision | Reason |
| --- | --- | --- |
| `tls-eio` plus `httpun` | Adopt | Pure OCaml TLS and compatible with the current switch in the initial solver check |
| `cohttp-eio` 6.2.1 | Reject for current baseline | Its `cohttp` 6.x requirement removes Bonsai v0.17 dependencies in the current switch |
| Piaf or `eio-ssl` | Reject | Introduces an OpenSSL path and violates the TLS constraint |
| Dart `HttpClient` or `WebSocket` | Reject | Moves network ownership and application behavior out of OCaml |
| Manual TLS or RFC 6455 implementation | Reject | Duplicates security-critical protocol machinery unnecessarily |
| Restore `ocaml/worker_http` | Reject for this example | Prematurely commits the framework to a public transport abstraction |
| Disable certificate checks | Reject | Converts the example into an unsafe pattern |
| Unsafe cast from TLS flow to Unix socket | Reject | Advertises capabilities the value does not possess |

## Open questions and decision points

1. Can Eio 1.2 express the generic TLS flow adapter cleanly with its public resource provider API?

2. Should the dependency manifest be a dedicated `bonsai_flutter_network_example.opam` package or a broader examples package?

3. Does `mirage-crypto-rng-unix` cross-link and obtain entropy correctly in the signed physical iPhoneOS application?

4. What exact app-size and native-object-size budget is acceptable for the added TLS, X.509, trust-store, HTTP, and WebSocket closure?

5. Should the public manual smoke endpoint remain WebSocket.org or be replaced by a project-controlled service before release?


Questions 1 through 4 are Phase 0 gates rather than implementation details that can be assumed away.

## References

- [Eio Worker Service plan](./012-eio-worker-service.md)

- [Worker Domain ADR](../adr/0007-ocaml-worker-domain.md)

- [Worker public interface](../../ocaml/runtime/worker.mli)

- [`tls-eio` package](https://opam.ocaml.org/packages/tls-eio/)

- [`ocaml-tls` source](https://github.com/mirleft/ocaml-tls)

- [`ca-certs-nss` package](https://opam.ocaml.org/packages/ca-certs-nss/)

- [`ca-certs-nss` source](https://github.com/mirage/ca-certs-nss)

- [`httpun-eio` package](https://opam.ocaml.org/packages/httpun-eio/)

- [`httpun-ws-eio` package](https://opam.ocaml.org/packages/httpun-ws-eio/httpun-ws-eio.0.2.0/)

- [`httpun-ws` source](https://github.com/anmonteiro/httpun-ws)

- [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455)

- [WebSocket.org public echo server](https://websocket.org/tools/websocket-echo-server/)

## Testing Details

- Run pure policy and state tests without Eio or sockets.

- Use generated test certificates and an ephemeral loopback TLS server for transport tests.

- Make hostname, issuer, timeout, cancellation, size, and close failures observable before implementing success paths.

- Inject transport providers into Worker service tests.

- Fence all WebSocket events with connection generations.

- Keep public endpoints out of CI.

- Finish with macOS and signed physical iPhoneOS smoke tests.

## Implementation Details

- Initialize Mirage Crypto RNG once in the Worker Domain.

- Build TLS configs from `ca-certs-nss` and normalized DNS peer names.

- Advertise only HTTP/1.1.

- Adapt only capabilities actually provided by `Tls_eio.t`.

- Use request ownership for HTTPS and session-daemon ownership for WSS.

- Bound bodies, messages, queues, transcripts, redirects, and timeouts.

- Keep the provider private to `examples/network`.

- Keep Flutter free of transport logic.

- Stop after Phase 0 if platform or capability assumptions fail.

## Question

Phase 0 must resolve the safe TLS-flow adapter, manifest boundary, iPhone entropy support, and size budget before the full implementation begins.

---
