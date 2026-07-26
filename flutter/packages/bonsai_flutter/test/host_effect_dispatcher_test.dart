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
