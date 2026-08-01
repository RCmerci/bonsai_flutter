import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_mail_example/mail_runtime_trace.dart';
import 'package:bonsai_flutter_mail_example/main.dart' as mail_app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logs startup and token-bearing runtime updates', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession();
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail-debug'.codeUnits),
      trace: messages.add,
      runtimeStarter: (config) async {
        expect(String.fromCharCodes(config), 'mail-debug');
        return runtime;
      },
    );
    final update = traced.updates.first;
    runtime.emitCycle(presentationId: 7, revision: 3, frameBytes: 144);
    await update;

    expect(messages, [
      '[Bonsai Mail][runtime] start entrypoint=mail-debug configBytes=10',
      '[Bonsai Mail][runtime] ready',
      '[Bonsai Mail][cycle] presentation=7 revision=3 frameBytes=144 '
          'recoverable=none',
    ]);
  });

  test('does not attach tracing to the non-debug entrypoint', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession();

    final session = await startTracedMailRuntime(
      Uint8List.fromList('mail'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => runtime,
    );

    expect(session, same(runtime));
    expect(messages, isEmpty);
    await session.dispose();
  });

  test('suppresses successful idle pump traces', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession();
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail-debug'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => runtime,
    );
    messages.clear();

    final update = traced.updates.first;
    runtime.emitCycle(presentationId: 8, revision: 3, frameBytes: 0);
    await update;
    traced.grantVsync(generation: 2);
    traced.presentationSucceeded(
      generation: 2,
      presentationId: 8,
      revision: 3,
      eventBatch: Uint8List(0),
    );

    expect(messages, isEmpty);
  });

  test('logs a recoverable diagnostic without a renderer frame', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession();
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail-debug'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => runtime,
    );
    messages.clear();

    final update = traced.updates.first;
    runtime.emitCycle(
      presentationId: 9,
      revision: 3,
      frameBytes: 0,
      recoverableDiagnostic: const RuntimeDiagnostic(
        code: RuntimeErrorCode.staleEvent,
        message: 'sensitive diagnostic detail',
      ),
    );
    await update;

    expect(messages, [
      '[Bonsai Mail][cycle] presentation=9 revision=3 frameBytes=0 '
          'recoverable=staleEvent',
    ]);
    expect(messages.join('\n'), isNot(contains('sensitive diagnostic detail')));
  });

  test('logs ordered event metadata without payload contents', () async {
    final messages = <String>[];
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail-debug'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => _FakeRuntimeSession(),
    );
    final batch = EventBatch(
      runtimeEpoch: 41,
      events: const [
        UiEvent(
          sequence: 12,
          displayedRevision: 9,
          nodeId: 100,
          handlerId: 200,
          eventTag: EventTagId.tap,
          payload: TapEventPayload(
            localX: 1,
            localY: 2,
            globalX: 3,
            globalY: 4,
            pointerKind: PointerKindValue.touch,
          ),
        ),
        UiEvent(
          sequence: 13,
          displayedRevision: 9,
          nodeId: 101,
          handlerId: 201,
          eventTag: EventTagId.textSubmit,
          payload: TextEventPayload('private message text must not be logged'),
        ),
      ],
    );

    traced.presentationSucceeded(
      generation: 2,
      presentationId: 8,
      revision: 9,
      eventBatch: EventBatchCodec.encode(batch),
    );

    expect(
      messages,
      containsAllInOrder([
        '[Bonsai Mail][event-batch] epoch=41 events=2 sequences=12..13 '
            'displayedRevision=9 tags=tap,text_submit',
        '[Bonsai Mail][presentation] succeeded generation=2 presentation=8 '
            'revision=9 eventBytes=${EventBatchCodec.encode(batch).length}',
      ]),
    );
    expect(messages.join('\n'), isNot(contains('private message text')));
  });

  test('logs visibility, rejection, command failure, and disposal', () async {
    final messages = <String>[];
    final runtime = _FakeRuntimeSession()..throwOnGrant = true;
    final traced = await startTracedMailRuntime(
      Uint8List.fromList('mail-debug'.codeUnits),
      trace: messages.add,
      runtimeStarter: (_) async => runtime,
    );

    traced.setFrameEligibility(generation: 3, eligible: true);
    expect(() => traced.grantVsync(generation: 3), throwsStateError);
    traced.presentationRejected(
      generation: 3,
      presentationId: 9,
      revision: 4,
      reason: PresentationRejectionReason.decodeFailed,
    );
    await traced.dispose();

    expect(
      messages,
      containsAllInOrder([
        '[Bonsai Mail][visibility] generation=3 eligible=true',
        '[Bonsai Mail][error] command=grantVsync type=StateError',
        '[Bonsai Mail][presentation] rejected generation=3 presentation=9 '
            'revision=4 reason=decodeFailed',
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
        Uint8List.fromList('mail-debug'.codeUnits),
        trace: messages.add,
        runtimeStarter: (_) async => throw StateError('private startup detail'),
      ),
      throwsStateError,
    );

    expect(messages, [
      '[Bonsai Mail][runtime] start entrypoint=mail-debug configBytes=10',
      '[Bonsai Mail][error] command=start type=StateError',
    ]);
    expect(messages.join('\n'), isNot(contains('private startup detail')));
  });

  testWidgets('debug build selects the traced native entrypoint', (
    tester,
  ) async {
    late Widget built;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          built = const mail_app.MailExampleApp().build(context);
          return const SizedBox.shrink();
        },
      ),
    );

    final materialApp = built as MaterialApp;
    final root = materialApp.home! as BonsaiFlutterRoot;
    expect(String.fromCharCodes(root.config), 'mail-debug');
  });
}

final class _FakeRuntimeSession implements RuntimeSession {
  final StreamController<RuntimeUpdate> _updates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  bool throwOnGrant = false;
  bool disposed = false;

  @override
  Stream<RuntimeUpdate> get updates => _updates.stream;

  void emitCycle({
    required int presentationId,
    required int revision,
    required int frameBytes,
    RuntimeDiagnostic? recoverableDiagnostic,
  }) {
    _updates.add(
      CycleReady(
        presentationId: presentationId,
        revision: revision,
        bytes: TransferableTypedData.fromList([Uint8List(frameBytes)]),
        recoverableDiagnostic: recoverableDiagnostic,
      ),
    );
  }

  @override
  void grantVsync({required int generation}) {
    if (throwOnGrant) throw StateError('sensitive runtime failure');
  }

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {}

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {}

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {}

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async =>
      const RuntimeDebugSnapshot(
        state: RuntimeWorkerState.ready,
        liveGeneration: 1,
        eligible: true,
        hasCoalescedGrant: false,
        unresolvedPresentationId: null,
        unresolvedRevision: null,
        pumpCount: 0,
      );

  @override
  Future<void> dispose() async {
    disposed = true;
    await _updates.close();
  }
}
