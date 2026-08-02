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

## Run on macOS

From the repository root, build and stage the application-specific complete
object:

```sh
make native-object EXAMPLE=sqlite_worker
cd examples/sqlite_worker/flutter
flutter pub get
flutter run -d macos
```

Run the focused OCaml and Flutter tests with:

```sh
dune runtest ocaml/test/sqlite_worker_store_tests.exe \
  ocaml/test/sqlite_worker_example_tests.exe
cd examples/sqlite_worker/flutter
flutter test
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
minimum deployment target of iOS 13.0. iOS Simulator is not supported.

```sh
make ios-device-native-objects
cd examples/sqlite_worker/flutter
flutter pub get
flutter build ios --debug --no-codesign
```

The unsigned build proves packaging only. Installation and execution require
repository-external Apple signing material and an available physical iPhone:

```sh
make ci-ios-device IOS_DEVICE_ID=<physical-device-id>
```

## Storage and persistence

The Flutter UI isolate resolves the platform Application Support directory,
creates a `sqlite_worker` child directory, and passes the absolute database
path through the startup envelope. The resulting paths are:

- macOS: `<Application Support>/sqlite_worker/todos.sqlite3`
- iOS: `<Application Support>/sqlite_worker/todos.sqlite3`

The exact platform prefix is chosen by `path_provider` and may vary by bundle
identifier, sandbox container, user, device, and OS version. The application
never relies on a hard-coded home or container path.

Schema migrations and mutations are transactional. Successful mutations use
idempotency keys and advance a durable database revision. Destroying or
replacing the logical runtime stops the worker session, finalizes statements,
and closes SQLite before another runtime can open the same file. Sequential
runtime recreation and normal application relaunch therefore recover committed
Todos and their database revision.

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
