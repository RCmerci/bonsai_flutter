# Host effects and environment

Host effects are typed asynchronous requests from OCaml to Flutter. They are
not renderer properties and do not run inside the `NodeStore` transaction.

`Driver.Handler.host_effects` provides the runtime-scoped context used by
`Host_effect`. Performing an effect allocates a monotonic request ID, retains
the Bonsai continuation, and emits one HostRequest operation. Flutter passes
the typed request to `HostEffectImplementation`. Completion produces a
HostResponse event, and the next runtime step resumes the original
continuation.

The API covers clipboard read/write, URL opening, file picking and saving,
focus, scrolling, window title and size, native menus, haptics, platform
information, layout measurement, and snack bars. Implementations that require platform
plugins are injected at `BonsaiFlutterRoot`; deterministic and headless tests
do not load plugins. The built-in implementation handles Flutter-core
clipboard, request-focus, clear-focus, scroll-to, haptic, and
platform-information requests. `Host_effect.show_snack_bar` is also built in:
it waits for an attached `ScaffoldMessenger`, presents typed text with an
optional action and duration, and completes with `Action`, `Dismiss`, `Swipe`,
`Hide`, `Remove`, or `Timeout`. Cancelling the effect closes the matching snack
bar without affecting unrelated requests.

`BonsaiFlutterRoot` owns the `RendererResourceStore` used by both rendering and
the built-in host implementation. `RequestFocus(node_id)` resolves the
node-scoped `FocusNode`; the standard renderer currently creates one for
`TextInput`. `ScrollTo(node_id, alignment, animated)` resolves the
`ScrollController` belonging to a `ScrollView` or `ListView`. Alignment is a
normalized position in the scroll extent: zero is the start and one is the
end. Values outside that range are clamped. Animated requests use a local
Flutter animation, so no per-frame values cross FFI. Both operations wait
until the current Flutter frame has attached their resource before executing.
Missing, dropped, or incompatible node IDs return a typed host-effect error.

Responses are `ok`, `error`, or `cancelled`. `Host_effect.Cancellation` emits a
cancel operation and completes the continuation with `Cancelled`. Flutter
root disposal cancels all in-flight implementation calls. OCaml driver
shutdown releases all pending continuations and clears unsent requests.

`EnvironmentReporter` is a separate change-filtered input path. It reports
viewport size, device-pixel ratio, text scale, brightness, platform, locale,
safe area, keyboard insets, accessibility flags, orientation, and pointer
support. OCaml exposes the latest accepted snapshot through
`Environment.value`; unchanged snapshots do not invalidate Bonsai.
