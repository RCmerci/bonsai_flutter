import 'dart:async';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'built-in focus and scroll requests use node-scoped renderer resources',
    () async {
      final resources = _FakeRendererHostResources();
      final implementation = FlutterHostEffectImplementation(
        resources: resources,
      );

      expect(
        await implementation.execute(1, const RequestFocusRequest(41)),
        isA<HostUnitValue>(),
      );
      expect(
        await implementation.execute(
          2,
          const ScrollToRequest(nodeId: 42, alignment: 0.75, animated: false),
        ),
        isA<HostUnitValue>(),
      );

      expect(resources.focusRequests, [41]);
      expect(resources.scrollRequests, [(42, 0.75, false)]);
    },
  );

  test(
    'snack bars use renderer identity, typed close reasons, and cancellation',
    () async {
      final resources = _FakeRendererHostResources();
      final implementation = FlutterHostEffectImplementation(
        resources: resources,
      );

      final result = await implementation.execute(
        77,
        const ShowSnackBarRequest(
          message: 'Saved',
          actionLabel: 'Undo',
          durationMs: 1500,
        ),
      );
      expect(
        result,
        const HostSnackBarCloseReasonValue(SnackBarCloseReason.action),
      );
      expect(resources.snackBars, [(77, 'Saved', 'Undo', 1500)]);

      await implementation.cancel(77);
      expect(resources.cancelledSnackBars, [77]);
    },
  );

  test('date and time pickers preserve typed civil values', () async {
    final resources = _FakeRendererHostResources();
    final implementation = FlutterHostEffectImplementation(
      resources: resources,
    );
    const first = CivilDateValue(year: 2024, month: 1, day: 1);
    const last = CivilDateValue(year: 2026, month: 12, day: 31);
    const date = CivilDateValue(year: 2025, month: 9, day: 3);
    const range = CivilDateRangeValue(start: first, end: date);
    const time = CivilTimeValue(hour: 18, minute: 45);

    expect(
      await implementation.execute(
        80,
        const PickDateRequest(
          initial: date,
          first: first,
          last: last,
          current: date,
          inputMode: false,
        ),
      ),
      isA<HostCivilDateValue>().having((value) => value.value, 'value', date),
    );
    expect(
      await implementation.execute(
        81,
        const PickDateRangeRequest(
          initial: range,
          first: first,
          last: last,
          current: date,
          inputMode: true,
        ),
      ),
      isA<HostCivilDateRangeValue>().having(
        (value) => value.value,
        'value',
        range,
      ),
    );
    expect(
      await implementation.execute(
        82,
        const PickTimeRequest(initial: time, use24Hour: true, inputMode: false),
      ),
      isA<HostCivilTimeValue>().having((value) => value.value, 'value', time),
    );
  });

  test(
    'typed host requests return success, error, and cancellation events',
    () async {
      final implementation = _FakeHostEffects();
      final events = <RendererEvent>[];
      final dispatcher = HostEffectDispatcher(
        implementation: implementation,
        onEvent: events.add,
      );
      final frame = Frame(
        runtimeEpoch: 41,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: const [
          HostRequestOperation(
            requestId: 1,
            request: ClipboardWriteRequest('剪贴板😀'),
          ),
          HostRequestOperation(
            requestId: 2,
            request: OpenUrlRequest('https://example.com/路径'),
          ),
          HostRequestOperation(
            requestId: 3,
            request: PickFileRequest(
              allowedExtensions: ['txt', 'md'],
              allowMultiple: true,
            ),
          ),
          CancelHostRequestOperation(requestId: 3),
        ],
      );

      await dispatcher.dispatch(frame);

      expect(implementation.clipboardWrites, ['剪贴板😀']);
      expect(events, hasLength(3));
      expect(
        events.map((event) => event.eventTag),
        everyElement(EventTagId.hostResponse),
      );
      expect(
        events.map((event) => event.payload),
        containsAll([
          const HostResponseEventPayload(
            requestId: 1,
            status: HostResponseStatus.ok,
            value: [],
          ),
          const HostResponseEventPayload(
            requestId: 2,
            status: HostResponseStatus.error,
            value: [100, 101, 110, 105, 101, 100],
          ),
          const HostResponseEventPayload(
            requestId: 3,
            status: HostResponseStatus.cancelled,
            value: [],
          ),
        ]),
      );
    },
  );

  test('dispose cancels every pending request exactly once', () async {
    final implementation = _BlockingHostEffects();
    final dispatcher = HostEffectDispatcher(
      implementation: implementation,
      onEvent: (_) {},
    );
    final pending = dispatcher.dispatch(
      const Frame(
        runtimeEpoch: 41,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          HostRequestOperation(requestId: 9, request: ClipboardReadRequest()),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await dispatcher.dispose();
    implementation.complete();
    await pending;

    expect(implementation.cancelled, [9]);
  });

  test(
    'explicit cancellation returns cancelled and duplicate IDs fail',
    () async {
      final implementation = _BlockingHostEffects();
      final events = <RendererEvent>[];
      final dispatcher = HostEffectDispatcher(
        implementation: implementation,
        onEvent: events.add,
      );
      final dispatch = dispatcher.dispatch(
        const Frame(
          runtimeEpoch: 41,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            HostRequestOperation(
              requestId: 12,
              request: ClipboardReadRequest(),
            ),
            CancelHostRequestOperation(requestId: 12),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      implementation.complete();
      await dispatch;

      expect(implementation.cancelled, [12]);
      expect(
        events.single.payload,
        const HostResponseEventPayload(
          requestId: 12,
          status: HostResponseStatus.cancelled,
          value: [],
        ),
      );

      await expectLater(
        dispatcher.dispatch(
          const Frame(
            runtimeEpoch: 41,
            baseRevision: 2,
            targetRevision: 3,
            kind: FrameKind.incremental,
            operations: [
              HostRequestOperation(
                requestId: 12,
                request: ClipboardReadRequest(),
              ),
            ],
          ),
        ),
        throwsStateError,
      );
    },
  );
}

final class _FakeRendererHostResources implements RendererHostResources {
  final focusRequests = <int>[];
  final scrollRequests = <(int, double, bool)>[];
  final snackBars = <(int, String, String?, int)>[];
  final cancelledSnackBars = <int>[];

  @override
  Future<void> requestFocus(int nodeId) async {
    focusRequests.add(nodeId);
  }

  @override
  Future<void> scrollTo(
    int nodeId, {
    required double alignment,
    required bool animated,
  }) async {
    scrollRequests.add((nodeId, alignment, animated));
  }

  @override
  Future<SnackBarCloseReason> showSnackBar(
    int requestId, {
    required String message,
    required String? actionLabel,
    required int durationMs,
  }) async {
    snackBars.add((requestId, message, actionLabel, durationMs));
    return SnackBarCloseReason.action;
  }

  @override
  Future<void> cancelSnackBar(int requestId) async {
    cancelledSnackBars.add(requestId);
  }

  @override
  Future<CivilDateValue?> pickDate(PickDateRequest request) async =>
      request.initial;

  @override
  Future<CivilDateRangeValue?> pickDateRange(
    PickDateRangeRequest request,
  ) async => request.initial;

  @override
  Future<CivilTimeValue?> pickTime(PickTimeRequest request) async =>
      request.initial;
}

final class _FakeHostEffects implements HostEffectImplementation {
  final clipboardWrites = <String>[];

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) async {
    return switch (request) {
      ClipboardWriteRequest(:final text) => () {
        clipboardWrites.add(text);
        return const HostUnitValue();
      }(),
      OpenUrlRequest() => throw const HostEffectException('denied'),
      PickFileRequest() => const HostCancelledValue(),
      _ => throw StateError('Unexpected request $request'),
    };
  }

  @override
  Future<void> cancel(int requestId) async {}
}

final class _BlockingHostEffects implements HostEffectImplementation {
  final completer = Completer<HostEffectValue>();
  final cancelled = <int>[];

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) =>
      completer.future;

  @override
  Future<void> cancel(int requestId) async {
    cancelled.add(requestId);
  }

  void complete() => completer.complete(const HostCancelledValue());
}
