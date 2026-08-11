# SQLite Worker Todo

This example keeps the UI and persistence model in OCaml while confining every
SQLite operation to the process-wide OCaml Worker Domain. Flutter is a thin
host: it resolves the Application Support directory, constructs a versioned
startup envelope, renders `BonsaiFlutterRoot`, and executes platform services.

The active path has four serialized stages:

```text
Flutter UI isolate
  -> Dart runtime coordinator isolate
  -> OCaml UI domain 0 (singleton Driver and Bonsai state)
  <-> OCaml Worker Domain (singleton worker session and SQLite connection)
```

Immutable, typed requests, responses, and latest-wins pushes cross the OCaml
Domain boundary. SQLite connections, prepared statements, migrations,
transactions, and cleanup never leave the Worker Domain. Worker output becomes
visible to Bonsai only at an accepted domain-0 pump boundary.

The same direct-style Worker Service also contains a bounded file demonstration.
It writes or reads `eio-worker-demo.bin` through a confined Eio directory
capability, reports latest-wins progress, and uses ordinary Worker request
cancellation. There is no legacy callback, `step`, or compatibility service
path.

## Run on macOS

From the repository root, run the independent consumer workspace:

```sh
cd examples/sqlite_worker
../../_build/default/bonsai_flutter_tool/bin/main.exe run macos --profile debug
```

Run the focused OCaml and Flutter tests with:

```sh
cd examples/sqlite_worker
dune runtest --root=.
cd flutter
../../../_build/default/bonsai_flutter_tool/bin/main.exe exec \
  --profile=debug -- flutter test --no-pub
```

The aggregate real-FFI persistence test is part of:

```sh
make integration-test
```

## Startup diagnostics

The running app displays diagnostic startup timings from both sides of the
runtime boundary. The Flutter host reports storage bootstrap, runtime and
Worker readiness, first OCaml frame, first Flutter presentation, and their
total. The OCaml UI reports SQLite open plus migration, the initial Todo query,
and total Worker service startup time.

These values are observability data only. They do not change the runtime's time
authority, Worker ordering, renderer protocol, or FFI boundary.

## Build for iPhoneOS

The supported Apple mobile artifact is physical-device arm64 iPhoneOS with a
minimum deployment target of iOS 15.0. iOS Simulator is not supported.

```sh
cd examples/sqlite_worker
../../_build/default/bonsai_flutter_tool/bin/main.exe build ios \
  --profile debug --no-codesign
```

The unsigned build proves packaging only. Installation and execution require
repository-external Apple signing material and an available physical iPhone:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

The DataScript-specific physical-device slice resolves the fixture
application's pinned opam metadata and Dune libraries into its own closure
lock, builds the feature-qualified SDK, signs the application, and launches it
twice:

```sh
IOS_DEVICE_ID=<physical-device-id> \
IOS_DEVELOPMENT_TEAM=<team-id> \
IOS_DEVELOPMENT_PROFILE_SPECIFIER=<development-profile> \
IOS_BUNDLE_IDENTIFIER=<unique-bundle-id> \
tool/ios/test_datascript_worker_device.sh
```

The first launch opens an app-private database through `Datascript_sqlite`,
persists one typed fact, closes the Worker runtime, and emits the
`BONSAI_DATASCRIPT_WORKER_PERSISTED` and
`BONSAI_DATASCRIPT_WORKER_SHUTDOWN` markers. The second launch must emit
`BONSAI_DATASCRIPT_WORKER_RESTORED` for the same fact before shutdown. The
test also requires the host runtime start/dispose markers, an arm64 iPhoneOS
complete object, system `sqlite3` imports, a valid app signature, and the
repository bundle audit.

## Storage and persistence

The Flutter UI isolate resolves the platform Application Support directory,
creates a `sqlite_worker` child directory, and passes both that absolute
directory and the absolute database path through the versioned `SWC1` startup
envelope. The OCaml decoder validates the envelope and both paths before
starting the Worker Service. The resulting paths are:

- macOS: `<Application Support>/sqlite_worker/todos.sqlite3`
- iOS: `<Application Support>/sqlite_worker/todos.sqlite3`
- file demo: `<Application Support>/sqlite_worker/eio-worker-demo.bin`

The exact platform prefix is chosen by `path_provider` and may vary by bundle
identifier, sandbox container, user, device, and OS version. The application
never relies on a hard-coded home or container path.

Schema migrations and mutations are transactional. Successful mutations use
idempotency keys and advance a durable database revision. Destroying or
replacing the logical runtime stops the worker session, finalizes statements,
and closes SQLite before another runtime can open the same file. Sequential
runtime recreation and normal application relaunch therefore recover committed
Todos and their database revision.

## File demonstration

The panel can generate a deterministic 4 MiB file, read it back, display its
rolling checksum, or cancel the current file request. File operations use 64
KiB chunks and reject generated or existing files larger than 16 MiB. Each
chunk yields to the Eio scheduler so cancellation and Worker control remain
runnable even when the operating system page cache makes file calls complete
immediately.

A write first creates `eio-worker-demo.<request-id>.tmp` in the same confined
directory. Only a completely successful write renames that file to
`eio-worker-demo.bin`. Cancellation and normal failures remove the temporary
file and preserve any older completed demo file. Reads stream through a bounded
buffer and never load an unbounded file into one string. File operations do not
change the Todo database revision.

## Support boundary

- One embedded OCaml runtime, one active logical `bf_runtime`, one Driver, one
  Dart runtime coordinator lease, one OCaml Worker Domain, and at most one
  worker session are supported per process.
- The Apple application links the system `libsqlite3`; it does not bundle a
  second SQLite implementation.
- SQLite runs only on the OCaml Worker Domain. It does not run on Dart,
  Flutter, OCaml domain 0, or a per-request thread.
- Hidden, paused, and detached applications do not pump Bonsai. The Worker
  Domain may finish bounded work and coalesce notifications, but the example
  makes no iOS background-execution guarantee. Results become visible after
  foreground pumping resumes.
- macOS arm64 and unsigned iPhoneOS arm64 packaging are validated. Signed
  physical-device behavior depends on external signing and device
  availability.
