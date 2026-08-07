import 'dart:async';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/application_platform/application_platform_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApplicationPlatformDispatcher', () {
    test(
      'delivers copied request bytes and correlates concurrent responses',
      () async {
        final first = Completer<Uint8List>();
        final second = Completer<Uint8List>();
        final platform = _TestApplicationPlatform((request) {
          if (request.first == 1) return first.future;
          return second.future;
        });
        final events = <RendererEvent>[];
        final dispatcher = ApplicationPlatformDispatcher(
          platform: platform,
          onEvent: events.add,
          onError: (_) {},
        )..activate(runtimeEpoch: 41);
        final firstRequest = Uint8List.fromList([1, 2, 255]);
        final secondRequest = Uint8List.fromList([2, 3, 0]);
        final dispatch = dispatcher.dispatch(
          Frame(
            runtimeEpoch: 41,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              ApplicationRequestOperation(requestId: 11, payload: firstRequest),
              ApplicationRequestOperation(
                requestId: 12,
                payload: secondRequest,
              ),
            ],
          ),
        );

        firstRequest[0] = 99;
        secondRequest[0] = 99;
        expect(platform.requests, [
          [1, 2, 255],
          [2, 3, 0],
        ]);

        final secondResponse = Uint8List.fromList([8, 7, 6]);
        second.complete(secondResponse);
        await Future<void>.delayed(Duration.zero);
        secondResponse[0] = 0;
        first.complete(Uint8List.fromList([9, 0, 4]));
        await dispatch;

        expect(events, hasLength(2));
        final secondPayload =
            events[0].payload as ApplicationResponseEventPayload;
        final firstPayload =
            events[1].payload as ApplicationResponseEventPayload;
        expect(secondPayload.requestId, 12);
        expect(secondPayload.payload, [8, 7, 6]);
        expect(firstPayload.requestId, 11);
        expect(firstPayload.payload, [9, 0, 4]);
        expect(dispatcher.pendingRequestCount, 0);
        await dispatcher.dispose();
      },
    );

    test(
      'reports unavailable and bounded handler failures without throwing',
      () async {
        final events = <RendererEvent>[];
        final unavailable = ApplicationPlatformDispatcher(
          platform: null,
          onEvent: events.add,
          onError: (_) {},
        )..activate(runtimeEpoch: 42);
        await unavailable.dispatch(_requestFrame(epoch: 42, requestId: 1));
        final unavailablePayload =
            events.single.payload as ApplicationRequestErrorEventPayload;
        expect(unavailablePayload.requestId, 1);
        expect(
          unavailablePayload.error.code,
          ApplicationPlatformErrorCode.unavailable,
        );

        events.clear();
        final failed = ApplicationPlatformDispatcher(
          platform: _TestApplicationPlatform(
            (_) => throw StateError(
              List<String>.filled(
                maximumApplicationPlatformErrorBytes * 2,
                'x',
              ).join(),
            ),
          ),
          onEvent: events.add,
          onError: (_) {},
        )..activate(runtimeEpoch: 42);
        await failed.dispatch(_requestFrame(epoch: 42, requestId: 2));
        final failedPayload =
            events.single.payload as ApplicationRequestErrorEventPayload;
        expect(failedPayload.requestId, 2);
        expect(
          failedPayload.error.code,
          ApplicationPlatformErrorCode.handlerFailed,
        );
        expect(
          failedPayload.error.message.codeUnits.length,
          lessThanOrEqualTo(maximumApplicationPlatformErrorBytes),
        );
        await unavailable.dispose();
        await failed.dispose();
      },
    );

    test(
      'enforces the public payload bound for responses and stream events',
      () async {
        final errors = <ApplicationPlatformBridgeError>[];
        final events = <RendererEvent>[];
        final platform = _TestApplicationPlatform(
          (_) async => Uint8List(maximumApplicationPlatformPayloadBytes + 1),
        );
        final dispatcher = ApplicationPlatformDispatcher(
          platform: platform,
          onEvent: events.add,
          onError: errors.add,
        )..activate(runtimeEpoch: 43);

        await dispatcher.dispatch(_requestFrame(epoch: 43, requestId: 3));
        final responseError =
            events.single.payload as ApplicationRequestErrorEventPayload;
        expect(
          responseError.error.code,
          ApplicationPlatformErrorCode.payloadTooLarge,
        );

        platform.addEvent(Uint8List(maximumApplicationPlatformPayloadBytes));
        platform.addEvent(
          Uint8List(maximumApplicationPlatformPayloadBytes + 1),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.payload is ApplicationEventPayload),
          hasLength(1),
        );
        expect(
          errors.single.code,
          ApplicationPlatformErrorCode.payloadTooLarge,
        );
        await dispatcher.dispose();
      },
    );

    test(
      'preserves ordered copied events only while the epoch is active',
      () async {
        final platform = _TestApplicationPlatform((request) async => request);
        final events = <RendererEvent>[];
        final dispatcher = ApplicationPlatformDispatcher(
          platform: platform,
          onEvent: events.add,
          onError: (_) {},
        );

        final before = Uint8List.fromList([0]);
        platform.addEvent(before);
        dispatcher.activate(runtimeEpoch: 44);
        final first = Uint8List.fromList([1, 2]);
        final second = Uint8List.fromList([3, 4]);
        platform.addEvent(first);
        platform.addEvent(second);
        first[0] = 9;
        second[0] = 9;
        await Future<void>.delayed(Duration.zero);
        expect(
          events.map(
            (event) => (event.payload as ApplicationEventPayload).payload,
          ),
          [
            [1, 2],
            [3, 4],
          ],
        );

        await dispatcher.dispose();
        await dispatcher.dispose();
        platform.addEvent(Uint8List.fromList([5]));
        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(2));
        expect(platform.listenCount, 1);
        expect(platform.cancelCount, 1);
      },
    );

    test(
      'turns stream errors into bounded typed errors and keeps the renderer live',
      () async {
        final platform = _TestApplicationPlatform((request) async => request);
        final errors = <ApplicationPlatformBridgeError>[];
        final events = <RendererEvent>[];
        final dispatcher = ApplicationPlatformDispatcher(
          platform: platform,
          onEvent: events.add,
          onError: errors.add,
        )..activate(runtimeEpoch: 45);

        platform.addError(StateError('stream failed'));
        platform.addEvent(Uint8List.fromList([7]));
        await Future<void>.delayed(Duration.zero);

        expect(errors.single.code, ApplicationPlatformErrorCode.handlerFailed);
        expect(errors.single.message, contains('stream failed'));
        expect(events.single.payload, isA<ApplicationEventPayload>());
        await dispatcher.dispose();
      },
    );

    test(
      'rejects duplicate and stale requests and drops late completions',
      () async {
        final completion = Completer<Uint8List>();
        final platform = _TestApplicationPlatform((_) => completion.future);
        final errors = <ApplicationPlatformBridgeError>[];
        final events = <RendererEvent>[];
        final dispatcher = ApplicationPlatformDispatcher(
          platform: platform,
          onEvent: events.add,
          onError: errors.add,
        )..activate(runtimeEpoch: 46);

        final active = dispatcher.dispatch(
          _requestFrame(epoch: 46, requestId: 8),
        );
        await dispatcher.dispatch(_requestFrame(epoch: 46, requestId: 8));
        await dispatcher.dispatch(_requestFrame(epoch: 99, requestId: 9));
        expect(errors.map((error) => error.code), [
          ApplicationPlatformErrorCode.invalidResponse,
          ApplicationPlatformErrorCode.runtimeReplaced,
        ]);

        await dispatcher.dispose();
        completion.complete(Uint8List.fromList([1]));
        await active;
        expect(events, isEmpty);
        expect(dispatcher.pendingRequestCount, 0);
      },
    );

    test(
      'repeated activation and disposal cycles do not leak subscriptions',
      () async {
        final platform = _TestApplicationPlatform((request) async => request);
        for (var epoch = 1; epoch <= 4; epoch += 1) {
          final dispatcher = ApplicationPlatformDispatcher(
            platform: platform,
            onEvent: (_) {},
            onError: (_) {},
          )..activate(runtimeEpoch: epoch);
          await dispatcher.dispose();
        }
        expect(platform.listenCount, 4);
        expect(platform.cancelCount, 4);
      },
    );
  });
}

Frame _requestFrame({required int epoch, required int requestId}) => Frame(
  runtimeEpoch: epoch,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    ApplicationRequestOperation(
      requestId: requestId,
      payload: Uint8List.fromList([1, 2, 3]),
    ),
  ],
);

final class _TestApplicationPlatform
    implements BonsaiFlutterApplicationPlatform {
  _TestApplicationPlatform(this._handler) {
    _controller = StreamController<Uint8List>.broadcast(
      sync: true,
      onListen: () => listenCount += 1,
      onCancel: () => cancelCount += 1,
    );
  }

  final Future<Uint8List> Function(Uint8List request) _handler;
  late final StreamController<Uint8List> _controller;
  final requests = <List<int>>[];
  var listenCount = 0;
  var cancelCount = 0;

  @override
  Stream<Uint8List> get events => _controller.stream;

  @override
  Future<Uint8List> handleRequest(Uint8List request) {
    requests.add(List<int>.of(request));
    return _handler(request);
  }

  void addEvent(Uint8List event) => _controller.add(event);
  void addError(Object error) => _controller.addError(error);
}
