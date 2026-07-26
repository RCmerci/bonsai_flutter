# Lifecycle

Flutter presentation is the commit point for Bonsai after-display lifecycle
effects. Decoding a frame or committing a `NodeStore` transaction is not
equivalent to presentation.

## Initial frame

```text
Dart runtime isolate       OCaml runtime            Flutter UI isolate
        |                       |                           |
        | create + step         |                           |
        |---------------------->|                           |
        |                       | driver.flush              |
        |                       | driver.result             |
        |                       | reconcile full snapshot   |
        |<----------------------|                           |
        | transfer frame bytes                              |
        |-------------------------------------------------->|
        |                                                   | validate + commit
        |                                                   | build/layout/paint
        |                  frame_presented(revision)         |
        |<--------------------------------------------------|
        |---------------------->|                           |
        |                       | trigger_lifecycles        |
        |                       | retire older handlers     |
```

`Bonsai_driver.flush` processes pending actions, clock alarms, and
before-display work before `result` is read. `trigger_lifecycles` runs only in
response to `frame_presented`.

## Subsequent pump

One pump performs this order:

1. Decode and validate the complete input batch.
2. Apply an environment update.
3. Complete host-effect responses.
4. Resolve UI events against the handler frame for their displayed revision.
5. Schedule the resulting Bonsai effects.
6. Advance the Bonsai time source when a timer wakeup is present.
7. Call `Bonsai_driver.flush`.
8. Read `Bonsai_driver.result`.
9. Reconcile the immutable view against the mounted tree.
10. Freeze the handler registry for the target revision.
11. Encode one incremental frame or no frame.
12. Return the next required wakeup time.

Before-display effects are included in `flush`; if they schedule actions, the
driver applies and stabilizes them before the view is read.

After Flutter presents a revision:

1. Mark the revision displayed.
2. Call `Bonsai_driver.trigger_lifecycles`.
3. Retain the displayed handler frame and its immediate predecessor, retiring
   all older frames.
4. If after-display work scheduled an action, request another pump.

`Driver.frame_presented` implements the first three operations in that exact
order. Handler-registry marking and retirement are separate tested operations,
so an older frame is not retired before lifecycle work begins. The one-frame
grace covers events created by an old Flutter widget callback after `NodeStore`
commits the next frame but before that widget rebuilds. If the handler ID was
replaced, the event keeps the callback's source revision and can only resolve
against that revision's handler frame. If the binding is unchanged, the event
uses the latest committed revision so a long-lived callback does not become
artificially stale.

## Shutdown

Shutdown is serialized with normal calls. It rejects new events, cancels host
requests, flushes deactivation work where the driver API permits it,
invalidates driver observers, clears handler frames, releases mounted state,
and lets Dart dispose every renderer resource before freeing the native
runtime.

The current public `Bonsai_driver` has no dedicated destroy operation.
`Bonsai_driver.Expert.invalidate_observers` is isolated in
`Bonsai_runtime_adapter` as the selected release mechanism.

The implemented adapter makes shutdown idempotent and invalidates those
observers. It cannot yet synthesize component deactivation through the public
driver API. End-to-end deactivation cleanup therefore remains an explicit
release blocker rather than a claimed property.

The implemented Dart `RuntimeClient` already serializes `step`,
`frame_presented`, and destroy on one runtime isolate and waits for a shutdown
acknowledgment. The native boundary implements the corresponding ownership and
status surface. `Bonsai_runtime_adapter` is part of the mandatory OCaml 5.3.0
build graph; its test proves that `flush` does not run activation or
after-display effects and that `frame_presented` does. The `Driver` test
extends that proof through
event dispatch, state update, reconciliation, encoding, and handler retirement.
The opt-in native complete object extends the same proof through the C ABI,
Dart runtime isolate, Flutter presentation acknowledgment, and native destroy.
The same adapter and driver are linked into the native complete object used by
the Flutter integration suite.

## Timers

The runtime returns an absolute `next_wakeup_ns`. Dart arms one timer on the
runtime isolate and calls `step` when it expires. The design does not poll at
60 Hz. A newly returned earlier deadline replaces the existing timer.
