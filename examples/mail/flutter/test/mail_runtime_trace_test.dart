import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_mail_example/mail_runtime_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logs startup and the actual runtime response metrics', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession(
      stepResponse: _response(
        requestSequence: 7,
        revision: 3,
        frameBytes: 144,
        ffiMicroseconds: 23,
        transferMicroseconds: 5,
      ),
    );

    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail'.codeUnits),
      trace: messages.add,
      runtimeStarter: (config) async {
        expect(String.fromCharCodes(config), 'mail');
        return runtime;
      },
    );
    await traced.step(Uint8List(0));

    expect(messages, [
      '[Bonsai Mail][runtime] start entrypoint=mail configBytes=4',
      '[Bonsai Mail][runtime] ready',
      '[Bonsai Mail][command] step inputBytes=0',
      '[Bonsai Mail][response] command=step request=7 status=ok '
          'error=none revision=3 frameBytes=144 nextWakeup=none '
          'ffiUs=23 transferUs=5',
    ]);
  });

  test(
    'logs ordered event metadata without logging payload contents',
    () async {
      final messages = <String>[];
      final runtime = _FakeRuntimeSession(
        eventResponse: _response(
          requestSequence: 8,
          status: RuntimeStatus.recoverableError,
          errorCode: RuntimeErrorCode.staleEvent,
          errorMessage: 'private message text must not be logged',
          revision: 9,
        ),
      );
      final traced = await startTracedMailRuntime(
        Uint8List.fromList('mail'.codeUnits),
        trace: messages.add,
        runtimeStarter: (_) async => runtime,
      );

      await traced.sendEventBatch(
        EventBatch(
          runtimeEpoch: 41,
          events: const [
            UiEvent(
              sequence: 12,
              displayedRevision: 9,
              nodeId: 100,
              handlerId: 200,
              eventTag: EventTagId.tap,
              payload: UnitEventPayload(),
            ),
            UiEvent(
              sequence: 13,
              displayedRevision: 9,
              nodeId: 101,
              handlerId: 201,
              eventTag: 999,
              payload: UnitEventPayload(),
            ),
          ],
        ),
      );
      await traced.sendEventBatch(
        EventBatch(runtimeEpoch: 41, events: const []),
      );

      expect(
        messages,
        containsAllInOrder([
          '[Bonsai Mail][event-batch] epoch=41 events=2 sequences=12..13 '
              'displayedRevision=9 tags=tap,unknown(999)',
          '[Bonsai Mail][response] command=eventBatch request=8 '
              'status=recoverableError error=staleEvent revision=9 '
              'frameBytes=0 nextWakeup=none ffiUs=0 transferUs=0',
          '[Bonsai Mail][event-batch] epoch=41 events=0 sequences=none '
              'displayedRevision=none tags=none',
        ]),
      );
      expect(messages.join('\n'), isNot(contains('private message text')));
    },
  );

  test('logs presentation, shutdown, and thrown command failures', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession(
      presentedResponse: _response(requestSequence: 9, revision: 4),
      stepError: StateError('sensitive runtime failure'),
    );
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => runtime,
    );

    await expectLater(traced.step(Uint8List.fromList([1])), throwsStateError);
    await traced.framePresented(4);
    await traced.dispose();

    expect(
      messages,
      containsAllInOrder([
        '[Bonsai Mail][command] step inputBytes=1',
        '[Bonsai Mail][error] command=step type=StateError',
        '[Bonsai Mail][presentation] acknowledge revision=4',
        '[Bonsai Mail][response] command=framePresented request=9 status=ok '
            'error=none revision=4 frameBytes=0 nextWakeup=none '
            'ffiUs=0 transferUs=0',
        '[Bonsai Mail][runtime] dispose',
        '[Bonsai Mail][runtime] disposed',
      ]),
    );
    expect(messages.join('\n'), isNot(contains('sensitive runtime failure')));
    expect(runtime.disposed, isTrue);
  });

  test('logs startup failure without exposing its message', () async {
    final messages = <String>[];

    await expectLater(
      startTracedMailRuntime(
        Uint8List.fromList('mail'.codeUnits),
        trace: messages.add,
        runtimeStarter: (_) async => throw StateError('private startup detail'),
      ),
      throwsStateError,
    );

    expect(messages, [
      '[Bonsai Mail][runtime] start entrypoint=mail configBytes=4',
      '[Bonsai Mail][error] command=start type=StateError',
    ]);
    expect(messages.join('\n'), isNot(contains('private startup detail')));
  });
}

RuntimeResponse _response({
  required int requestSequence,
  RuntimeStatus status = RuntimeStatus.ok,
  RuntimeErrorCode errorCode = RuntimeErrorCode.none,
  String? errorMessage,
  int revision = 0,
  int frameBytes = 0,
  int ffiMicroseconds = 0,
  int transferMicroseconds = 0,
}) => RuntimeResponse(
  requestSequence: requestSequence,
  status: status,
  bytes: Uint8List(frameBytes),
  revision: revision,
  nextWakeupNanoseconds: -1,
  errorMessage: errorMessage,
  errorCode: errorCode,
  ffiDuration: Duration(microseconds: ffiMicroseconds),
  isolateTransferDuration: Duration(microseconds: transferMicroseconds),
);

final class _FakeRuntimeSession implements RuntimeSession {
  _FakeRuntimeSession({
    RuntimeResponse? stepResponse,
    RuntimeResponse? eventResponse,
    RuntimeResponse? presentedResponse,
    this.stepError,
  }) : stepResponse = stepResponse ?? _response(requestSequence: 1),
       eventResponse = eventResponse ?? _response(requestSequence: 2),
       presentedResponse = presentedResponse ?? _response(requestSequence: 3);

  final RuntimeResponse stepResponse;
  final RuntimeResponse eventResponse;
  final RuntimeResponse presentedResponse;
  final Object? stepError;
  bool disposed = false;

  @override
  Future<RuntimeResponse> step(Uint8List input) async {
    final error = stepError;
    if (error != null) throw error;
    return stepResponse;
  }

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async =>
      eventResponse;

  @override
  Future<RuntimeResponse> framePresented(int revision) async =>
      presentedResponse;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
