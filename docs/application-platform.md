# Application platform bridge

The application platform bridge carries bounded opaque bytes between an OCaml
application and application-owned Dart code. It is separate from `Host_effect`:
standard clipboard, focus, scrolling, platform information, native menu, and
renderer-resource behavior continues to use the built-in host-effect path.

## Dart adapter

An application implements its own payload codec and platform bridge:

```dart
abstract interface class BonsaiFlutterApplicationPlatform {
  Future<Uint8List> handleRequest(Uint8List request);

  Stream<Uint8List> get events;
}
```

The managed host creates one `BonsaiFlutterHostAdapter`, awaits
`createApplicationPayload()`, obtains the optional bridge from
`createApplicationPlatform()`, and passes both to `BonsaiFlutterRoot`. The
adapter still receives the generated `MaterialApp` through `buildHost(...)`.
The generator owns the host and runtime envelope but never inspects, casts, or
reconstructs the root from application code.

Requests, responses, and events are limited to 1 MiB each. Buffers are copied
at every ownership boundary. Oversized values are rejected without truncation,
and opaque payload contents are never included in framework traces.

## OCaml API

Applications obtain the runtime-scoped bridge with
`App.Context.application_platform` and use `Application_platform.request`:

```ocaml
let platform = App.Context.application_platform context in
let effect =
  Application_platform.request platform encoded_request
  |> Bonsai.Effect.map ~f:(function
    | Ok response -> decode_response response
    | Error error -> handle_platform_error error)
```

`Application_platform.on_event` installs an ordered event handler for the
runtime. Each handler receives its own copied byte buffer. A cancellation token
may be supplied to `request`; cancellation resolves the continuation with
`Cancelled`, and any later response is rejected as stale.

The public payload limit is
`Application_platform.maximum_payload_bytes`. Typed errors distinguish an
unavailable bridge, oversized payloads, handler failures, cancellation,
shutdown, runtime replacement, and invalid responses.

## Protocol and lifecycle

The framework protocol defines only four generic messages:

- `ApplicationRequest { request_id; payload }`
- `ApplicationResponse { request_id; payload }`
- `ApplicationRequestError { request_id; error }`
- `ApplicationEvent { payload }`

The runtime owns positive monotonic request IDs, correlation, runtime epochs,
pending continuations, cancellation, and disposal. Concurrent responses may
complete in any order and are correlated by request ID. Unsolicited Dart events
retain stream emission order.

Flutter subscribes to `events` only after a runtime epoch is active. Values
emitted before activation or after disposal are not delivered. Root disposal
cancels the stream subscription once and fences late handler completions.
Shutdown resolves all pending OCaml requests with `Shutdown`; native runtime
replacement resolves them with `Runtime_replaced`. Duplicate, unknown,
malformed, stale, and oversized application traffic is rejected as a
recoverable bridge error and does not terminate rendering.

## Application-owned event definitions

Semantic event tags and their codecs belong in the consuming application, for
example:

```dart
enum JournalPlatformEventTag {
  calendarChanged,
}

enum CalendarChangeReason {
  resumed,
  significantTimeChanged,
  timeZoneChanged,
  localeChanged,
}
```

The application also owns signal collection. Depending on its platforms, it
may use `AppLifecycleListener.onResume`,
`WidgetsBindingObserver.didChangeLocales`,
`UIApplication.significantTimeChangeNotification`,
`NSSystemTimeZoneDidChange`, or `NSCalendarDayChanged`. Application code
interprets those signals, encodes them into its versioned opaque protocol, and
emits the bytes through `BonsaiFlutterApplicationPlatform.events`.

`bonsai_flutter` does not provide journal or calendar codecs, localized date
formatting, application storage paths, database support, product-specific
lifecycle interpretation, or native notification listeners.
