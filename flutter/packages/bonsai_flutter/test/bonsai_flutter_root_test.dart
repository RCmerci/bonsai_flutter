import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/runtime/foreground_frame_loop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_bonsai.dart';

void main() {
  testWidgets('root owns runtime startup, event flushing, and presentation', (
    tester,
  ) async {
    final runtime = _FakeRuntimeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterRoot(
            config: Uint8List.fromList([1, 2, 3]),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      ),
    );
    await pumpBonsaiFrames(tester, count: 6);

    expect(find.text('Count: 0'), findsOneWidget);
    expect(runtime.presentedRevisions, isNotEmpty);
    expect(runtime.presentedRevisions, everyElement(1));
    expect(runtime.environmentBatchCount, 1);

    await tester.tap(find.byType(ElevatedButton));
    await pumpBonsaiFrames(tester, count: 6);

    expect(find.text('Count: 1'), findsOneWidget);
    expect(runtime.eventBatchCount, 1);
    expect(runtime.presentedRevisions.last, 2);
    expect(runtime.presentedRevisions, containsAllInOrder([1, 2]));

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpBonsaiFrames(tester, count: 2);
    expect(runtime.disposed, isTrue);
  });

  testWidgets('root dispatches host requests and returns typed responses', (
    tester,
  ) async {
    final runtime = _HostRequestRuntimeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterRoot(
          config: Uint8List(0),
          runtimeStarter: (_) async => runtime,
          hostEffects: const _ClipboardHostEffects(),
        ),
      ),
    );
    await pumpBonsaiFrames(tester, count: 6);

    expect(find.text('Clipboard from Flutter'), findsOneWidget);
    expect(runtime.hostResponseCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpBonsaiFrames(tester, count: 2);
    expect(runtime.disposed, isTrue);
  });

  testWidgets('root gives built-in host effects access to renderer resources', (
    tester,
  ) async {
    final runtime = _FocusHostRequestRuntimeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      ),
    );
    await pumpBonsaiFrames(
      tester,
      count: 6,
      step: const Duration(milliseconds: 10),
    );

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(runtime.hostResponseCount, 1);
  });

  testWidgets('revision mismatch rejection automatically applies a snapshot', (
    tester,
  ) async {
    final runtime = _ResyncRuntimeSession();

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterRoot(
          config: Uint8List(0),
          runtimeStarter: (_) async => runtime,
        ),
      ),
    );
    await pumpBonsaiFrames(tester, count: 6);
    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await pumpBonsaiFrames(tester, count: 6);

    expect(find.text('Count: 1'), findsOneWidget);
    expect(find.textContaining('Bonsai runtime error'), findsNothing);
    expect(runtime.resyncRequestCount, 1);
    expect(runtime.presentedRevisions.last, 2);
    expect(runtime.presentedRevisions, containsAllInOrder([1, 2]));
  });

  testWidgets(
    'recoverable stale input is dropped without replacing the application',
    (tester) async {
      final runtime = _RecoverableStaleRuntimeSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BonsaiFlutterRoot(
              config: Uint8List(0),
              runtimeStarter: (_) async => runtime,
            ),
          ),
        ),
      );
      await pumpBonsaiFrames(tester, count: 6);

      await tester.tap(find.byType(ElevatedButton));
      await pumpBonsaiFrames(tester, count: 6);

      expect(find.text('Count: 0'), findsOneWidget);
      expect(find.textContaining('Bonsai runtime error'), findsNothing);

      await tester.tap(find.byType(ElevatedButton));
      await pumpBonsaiFrames(tester, count: 6);

      expect(find.text('Count: 1'), findsOneWidget);
      expect(find.textContaining('Bonsai runtime error'), findsNothing);
      expect(runtime.pressBatchCount, 2);
      expect(runtime.presentedRevisions.last, 2);
      expect(runtime.presentedRevisions, containsAllInOrder([1, 2]));
    },
  );

  group('presentation-token root pipeline', () {
    testWidgets('applies an initial snapshot before later post-frame success', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession();

      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();
      runtime.emitCycle(
        presentationId: 10,
        revision: 1,
        bytes: FrameCodec.encode(counterWidgetSnapshot()),
      );

      expect(runtime.successes, isEmpty);
      await tester.pump();

      expect(find.text('Count: 0'), findsOneWidget);
      expect(runtime.successes, hasLength(1));
      expect(runtime.successes.single.presentationId, 10);
      expect(runtime.successes.single.revision, 1);
    });

    testWidgets('no-byte cycle still waits for and receives a real frame', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();
      runtime.emitCycle(
        presentationId: 1,
        revision: 1,
        bytes: FrameCodec.encode(counterWidgetSnapshot()),
      );
      await tester.pump();
      runtime.emitCycle(presentationId: 2, revision: 1, bytes: Uint8List(0));

      expect(runtime.successes.map((value) => value.presentationId), [1]);
      await tester.pump();
      expect(runtime.successes.map((value) => value.presentationId), [1, 2]);
    });

    testWidgets('update delivered after begin frame waits for a later frame', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();
      tester.binding.addPostFrameCallback((_) {
        runtime.emitCycle(
          presentationId: 21,
          revision: 1,
          bytes: FrameCodec.encode(counterWidgetSnapshot()),
        );
      });

      await tester.pump();
      expect(runtime.successes, isEmpty);

      await tester.pump();
      expect(runtime.successes.single.presentationId, 21);
    });

    testWidgets('decode failure rejects the exact token before live commit', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();

      runtime.emitCycle(
        presentationId: 31,
        revision: 1,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      await tester.pump();

      expect(runtime.rejections, hasLength(1));
      expect(runtime.rejections.single.presentationId, 31);
      expect(
        runtime.rejections.single.reason,
        PresentationRejectionReason.decodeFailed,
      );
      expect(runtime.successes, isEmpty);
    });

    testWidgets(
      'ineligible update is held raw and applied before first resumed callback',
      (tester) async {
        final runtime = _OrderedRuntimeSession();
        final eligibility = _TestFrameEligibilitySource(true);
        await tester.pumpWidget(
          MaterialApp(
            home: BonsaiFlutterRoot(
              config: Uint8List(0),
              runtimeStarter: (_) async => runtime,
              frameEligibilitySource: eligibility,
            ),
          ),
        );
        await tester.pump();
        eligibility.emit(false);
        runtime.emitCycle(
          presentationId: 41,
          revision: 1,
          bytes: FrameCodec.encode(counterWidgetSnapshot()),
        );

        await tester.pump();
        expect(find.text('Count: 0'), findsNothing);
        expect(runtime.successes, isEmpty);
        expect(runtime.rejections, isEmpty);

        eligibility.emit(true);
        expect(find.text('Count: 0'), findsNothing);
        await tester.pump();

        expect(find.text('Count: 0'), findsOneWidget);
        expect(runtime.successes.single.presentationId, 41);
        expect(runtime.visibilityChanges.last.eligible, isTrue);
      },
    );

    testWidgets('post-frame session handoff failure is terminal', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession()..throwOnSuccess = true;
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();
      runtime.emitCycle(
        presentationId: 51,
        revision: 1,
        bytes: FrameCodec.encode(counterWidgetSnapshot()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Bonsai runtime error'), findsOneWidget);
      expect(runtime.rejections, isEmpty);
    });

    testWidgets('stale callback after root disposal sends no session command', (
      tester,
    ) async {
      final runtime = _OrderedRuntimeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterRoot(
            config: Uint8List(0),
            runtimeStarter: (_) async => runtime,
          ),
        ),
      );
      await tester.pump();
      runtime.emitCycle(
        presentationId: 59,
        revision: 1,
        bytes: FrameCodec.encode(counterWidgetSnapshot()),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(runtime.successes, isEmpty);
      expect(runtime.rejections, isEmpty);
      expect(runtime.disposed, isTrue);
    });

    testWidgets(
      'later host-dispatch Future failure is terminal, not rejected',
      (tester) async {
        final runtime = _OrderedRuntimeSession();
        await tester.pumpWidget(
          MaterialApp(
            home: BonsaiFlutterRoot(
              config: Uint8List(0),
              runtimeStarter: (_) async => runtime,
              hostEffects: const _FailingHostEffects(),
            ),
          ),
        );
        await tester.pump();
        runtime.emitCycle(
          presentationId: 61,
          revision: 1,
          bytes: FrameCodec.encode(
            const Frame(
              runtimeEpoch: 21,
              baseRevision: 0,
              targetRevision: 1,
              kind: FrameKind.fullSnapshot,
              operations: [
                CreateNode(
                  nodeId: 1,
                  kind: NodeKind.text,
                  props: TextProps('committed'),
                  eventBindings: [],
                ),
                SetRoot(1),
                HostRequestOperation(
                  requestId: 8,
                  request: ClipboardReadRequest(),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Bonsai runtime error'), findsOneWidget);
        expect(runtime.rejections, isEmpty);
      },
    );
  });
}

final class _ClipboardHostEffects implements HostEffectImplementation {
  const _ClipboardHostEffects();

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) async {
    expect(requestId, 5);
    expect(request, isA<ClipboardReadRequest>());
    return const HostStringValue('Clipboard from Flutter');
  }

  @override
  Future<void> cancel(int requestId) async {}
}

final class _FailingHostEffects implements HostEffectImplementation {
  const _FailingHostEffects();

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) =>
      Future<HostEffectValue>.error(StateError('host dispatch failed'));

  @override
  Future<void> cancel(int requestId) async {}
}

final class _LegacyResponse {
  const _LegacyResponse({
    required this.requestSequence,
    required this.status,
    required this.bytes,
    required this.revision,
    required this.errorMessage,
    this.errorCode = RuntimeErrorCode.none,
  });

  final int requestSequence;
  final RuntimeStatus status;
  final Uint8List bytes;
  final int revision;
  final String? errorMessage;
  final RuntimeErrorCode errorCode;
}

abstract class _LegacyRuntimeSessionAdapter implements RuntimeSession {
  final StreamController<RuntimeUpdate> _legacyUpdates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  var _legacyGeneration = 0;
  var _legacyEligible = false;
  var _legacyAwaitingPresentation = false;
  var _legacyNextPresentationId = 1;
  var _legacyPumpCount = 0;
  var _legacyStarted = false;
  var _legacyLastRevision = 0;

  Future<_LegacyResponse> legacyPump(Uint8List input);
  Future<_LegacyResponse> legacyEvents(EventBatch batch);
  Future<_LegacyResponse> legacyPresent(int revision);

  @override
  Stream<RuntimeUpdate> get updates => _legacyUpdates.stream;

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    _legacyGeneration = generation;
    _legacyEligible = eligible;
  }

  @override
  void grantVsync({required int generation}) {
    if (!_legacyEligible ||
        generation != _legacyGeneration ||
        _legacyAwaitingPresentation) {
      return;
    }
    _legacyAwaitingPresentation = true;
    _legacyPumpCount += 1;
    if (_legacyStarted) {
      _legacyUpdates.add(
        CycleReady(
          presentationId: _legacyNextPresentationId++,
          revision: _legacyLastRevision,
          bytes: TransferableTypedData.fromList([Uint8List(0)]),
          recoverableDiagnostic: null,
        ),
      );
    } else {
      _legacyStarted = true;
      unawaited(
        _emitLegacyResponse(
          (this as dynamic).legacyPump(Uint8List(0)) as Future<_LegacyResponse>,
        ),
      );
    }
  }

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    if (generation != _legacyGeneration || !_legacyAwaitingPresentation) {
      throw StateError('Legacy presentation token mismatch');
    }
    unawaited(
      (() async {
        final presented =
            await (this as dynamic).legacyPresent(revision) as _LegacyResponse;
        if (presented.status == RuntimeStatus.fatalError) {
          _emitLegacyFatal(presented);
          return;
        }
        _legacyAwaitingPresentation = false;
        if (eventBatch.isNotEmpty) {
          _legacyAwaitingPresentation = true;
          final batch = EventBatchCodec.decode(eventBatch);
          await _emitLegacyResponse(
            (this as dynamic).legacyEvents(batch) as Future<_LegacyResponse>,
          );
        }
      })(),
    );
  }

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {
    _legacyAwaitingPresentation = false;
    final recovery = onLegacyPresentationRejected(reason);
    if (recovery != null) {
      _legacyAwaitingPresentation = true;
      unawaited(_emitLegacyResponse(recovery));
    }
  }

  Future<_LegacyResponse>? onLegacyPresentationRejected(
    PresentationRejectionReason reason,
  ) => null;

  Future<void> _emitLegacyResponse(Future<_LegacyResponse> future) async {
    try {
      final response = await future;
      if (response.status == RuntimeStatus.fatalError) {
        _emitLegacyFatal(response);
        return;
      }
      _legacyLastRevision = response.revision;
      _legacyUpdates.add(
        CycleReady(
          presentationId: _legacyNextPresentationId++,
          revision: response.revision,
          bytes: TransferableTypedData.fromList([response.bytes]),
          recoverableDiagnostic:
              response.status == RuntimeStatus.recoverableError
              ? RuntimeDiagnostic(
                  code: response.errorCode,
                  message: response.errorMessage ?? 'recoverable legacy error',
                )
              : null,
        ),
      );
    } catch (error) {
      _legacyUpdates.add(
        RuntimeFatalDiagnostic(
          RuntimeDiagnostic(
            code: RuntimeErrorCode.invalidSchedulerState,
            message: error.toString(),
          ),
        ),
      );
    }
  }

  void _emitLegacyFatal(_LegacyResponse response) {
    _legacyUpdates.add(
      RuntimeFatalDiagnostic(
        RuntimeDiagnostic(
          code: response.errorCode,
          message: response.errorMessage ?? 'fatal legacy error',
        ),
      ),
    );
  }

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async => RuntimeDebugSnapshot(
    state: _legacyAwaitingPresentation
        ? RuntimeWorkerState.awaitingPresentation
        : RuntimeWorkerState.ready,
    liveGeneration: _legacyGeneration,
    eligible: _legacyEligible,
    pumpCount: _legacyPumpCount,
    hasCoalescedGrant: false,
    unresolvedPresentationId: null,
    unresolvedRevision: null,
  );
}

final class _HostRequestRuntimeSession extends _LegacyRuntimeSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  var hostResponseCount = 0;
  var disposed = false;
  var revision = 1;

  @override
  Future<_LegacyResponse> legacyPump(Uint8List input) async => _LegacyResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: FrameCodec.encode(
      const Frame(
        runtimeEpoch: 61,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.text,
            props: TextProps('Waiting'),
            eventBindings: [],
          ),
          SetRoot(1),
          HostRequestOperation(requestId: 5, request: ClipboardReadRequest()),
        ],
      ),
    ),
    revision: 1,
    errorMessage: null,
  );

  @override
  Future<_LegacyResponse> legacyEvents(EventBatch batch) async {
    final hostResponses = batch.events
        .where((event) => event.eventTag == EventTagId.hostResponse)
        .toList(growable: false);
    if (hostResponses.isEmpty) {
      return _response(Uint8List(0));
    }
    hostResponseCount += hostResponses.length;
    final payload = hostResponses.single.payload as HostResponseEventPayload;
    expect(payload.requestId, 5);
    expect(payload.status, HostResponseStatus.ok);
    expect(utf8.decode(payload.value), 'Clipboard from Flutter');
    final baseRevision = revision;
    revision += 1;
    return _response(
      FrameCodec.encode(
        Frame(
          runtimeEpoch: 61,
          baseRevision: baseRevision,
          targetRevision: revision,
          kind: FrameKind.incremental,
          operations: const [
            UpdateProps(nodeId: 1, props: TextProps('Clipboard from Flutter')),
          ],
        ),
      ),
    );
  }

  _LegacyResponse _response(Uint8List bytes) => _LegacyResponse(
    requestSequence: 2,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: revision,
    errorMessage: null,
  );

  @override
  Future<_LegacyResponse> legacyPresent(int revision) async =>
      _response(Uint8List(0));

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FocusHostRequestRuntimeSession
    extends _LegacyRuntimeSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  var hostResponseCount = 0;

  @override
  Future<_LegacyResponse> legacyPump(Uint8List input) async => _response(
    FrameCodec.encode(
      const Frame(
        runtimeEpoch: 62,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 7,
            kind: NodeKind.textInput,
            props: TextInputProps(
              sessionId: 1,
              documentRevision: 1,
              value: TextEditingStateValue(
                text: '',
                selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
                composing: null,
              ),
              enabled: true,
              readOnly: false,
              obscureText: false,
              keyboardType: TextKeyboardType.text,
              inputAction: TextInputActionKind.done,
              acceptedLocalRevision: 0,
              updateMode: TextUpdateMode.forceReplace,
              autofocus: false,
            ),
            eventBindings: [],
          ),
          SetRoot(7),
          HostRequestOperation(requestId: 8, request: RequestFocusRequest(7)),
        ],
      ),
    ),
  );

  @override
  Future<_LegacyResponse> legacyEvents(EventBatch batch) async {
    hostResponseCount += batch.events
        .where((event) => event.eventTag == EventTagId.hostResponse)
        .length;
    return _response(Uint8List(0));
  }

  _LegacyResponse _response(Uint8List bytes) => _LegacyResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: 1,
    errorMessage: null,
  );

  @override
  Future<_LegacyResponse> legacyPresent(int revision) async =>
      _response(Uint8List(0));

  @override
  Future<void> dispose() async {}
}

final class _FakeRuntimeSession extends _LegacyRuntimeSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final presentedRevisions = <int>[];
  var eventBatchCount = 0;
  var environmentBatchCount = 0;
  var disposed = false;

  @override
  Future<_LegacyResponse> legacyPump(Uint8List input) async => _LegacyResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: FrameCodec.encode(counterWidgetSnapshot()),
    revision: 1,
    errorMessage: null,
  );

  @override
  Future<_LegacyResponse> legacyEvents(EventBatch batch) async {
    expect(batch.events, hasLength(1));
    if (batch.events.single.eventTag == EventTagId.environmentChanged) {
      environmentBatchCount += 1;
      return _LegacyResponse(
        requestSequence: 2,
        status: RuntimeStatus.ok,
        bytes: Uint8List(0),
        revision: 1,
        errorMessage: null,
      );
    }
    eventBatchCount += 1;
    expect(batch.events.single.eventTag, EventTagId.press);
    return _LegacyResponse(
      requestSequence: 2,
      status: RuntimeStatus.ok,
      bytes: FrameCodec.encode(
        const Frame(
          runtimeEpoch: 21,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 2, props: TextProps('Count: 1'))],
        ),
      ),
      revision: 2,
      errorMessage: null,
    );
  }

  @override
  Future<_LegacyResponse> legacyPresent(int revision) async {
    presentedRevisions.add(revision);
    return _LegacyResponse(
      requestSequence: 3,
      status: RuntimeStatus.ok,
      bytes: Uint8List(0),
      revision: revision,
      errorMessage: null,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _RecoverableStaleRuntimeSession
    extends _LegacyRuntimeSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final presentedRevisions = <int>[];
  var pressBatchCount = 0;

  @override
  Future<_LegacyResponse> legacyPump(Uint8List input) async =>
      _response(bytes: FrameCodec.encode(counterWidgetSnapshot()), revision: 1);

  @override
  Future<_LegacyResponse> legacyEvents(EventBatch batch) async {
    expect(batch.events, hasLength(1));
    final event = batch.events.single;
    if (event.eventTag == EventTagId.environmentChanged) {
      return _response(bytes: Uint8List(0), revision: 1);
    }
    expect(event.eventTag, EventTagId.press);
    pressBatchCount += 1;
    if (pressBatchCount == 1) {
      return _LegacyResponse(
        requestSequence: 2,
        status: RuntimeStatus.recoverableError,
        bytes: Uint8List(0),
        revision: 1,
        errorMessage: 'stale event for revision 1',
        errorCode: RuntimeErrorCode.staleEvent,
      );
    }
    return _response(
      bytes: FrameCodec.encode(
        const Frame(
          runtimeEpoch: 21,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 2, props: TextProps('Count: 1'))],
        ),
      ),
      revision: 2,
    );
  }

  @override
  Future<_LegacyResponse> legacyPresent(int revision) async {
    presentedRevisions.add(revision);
    return _response(bytes: Uint8List(0), revision: revision);
  }

  _LegacyResponse _response({
    required Uint8List bytes,
    required int revision,
  }) => _LegacyResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: revision,
    errorMessage: null,
  );

  @override
  Future<void> dispose() async {}
}

final class _ResyncRuntimeSession extends _LegacyRuntimeSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  var resyncRequestCount = 0;
  final presentedRevisions = <int>[];

  @override
  Future<_LegacyResponse> legacyPump(Uint8List input) async => _LegacyResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: FrameCodec.encode(counterWidgetSnapshot()),
    revision: 1,
    errorMessage: null,
  );

  @override
  Future<_LegacyResponse> legacyEvents(EventBatch batch) async {
    final event = batch.events.single;
    if (event.eventTag == EventTagId.environmentChanged) {
      return _response(Uint8List(0), revision: 1);
    }
    expect(event.eventTag, EventTagId.press);
    return _response(
      FrameCodec.encode(
        const Frame(
          runtimeEpoch: 21,
          baseRevision: 99,
          targetRevision: 100,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(nodeId: 2, props: TextProps('Must not commit')),
          ],
        ),
      ),
      revision: 100,
    );
  }

  @override
  Future<_LegacyResponse>? onLegacyPresentationRejected(
    PresentationRejectionReason reason,
  ) {
    expect(reason, PresentationRejectionReason.rendererRevisionMismatch);
    resyncRequestCount += 1;
    return Future.value(
      _response(
        FrameCodec.encode(
          const Frame(
            runtimeEpoch: 21,
            baseRevision: 0,
            targetRevision: 2,
            kind: FrameKind.fullSnapshot,
            operations: [
              CreateNode(
                nodeId: 11,
                kind: NodeKind.column,
                props: LinearProps(),
                eventBindings: [],
              ),
              CreateNode(
                nodeId: 12,
                kind: NodeKind.text,
                props: TextProps('Count: 1'),
                eventBindings: [],
              ),
              CreateNode(
                nodeId: 13,
                kind: NodeKind.button,
                props: ButtonProps(enabled: true),
                eventBindings: [
                  EventBinding(eventTag: EventTagId.press, handlerId: 9101),
                ],
              ),
              CreateNode(
                nodeId: 14,
                kind: NodeKind.text,
                props: TextProps('Increment'),
                eventBindings: [],
              ),
              SetChildren(nodeId: 11, children: [12, 13]),
              SetChildren(nodeId: 13, children: [14]),
              SetRoot(11),
            ],
          ),
        ),
        revision: 2,
      ),
    );
  }

  _LegacyResponse _response(Uint8List bytes, {required int revision}) =>
      _LegacyResponse(
        requestSequence: 2,
        status: RuntimeStatus.ok,
        bytes: bytes,
        revision: revision,
        errorMessage: null,
      );

  @override
  Future<_LegacyResponse> legacyPresent(int revision) async {
    presentedRevisions.add(revision);
    return _response(Uint8List(0), revision: revision);
  }

  @override
  Future<void> dispose() async {}
}

Frame counterWidgetSnapshot() => const Frame(
  runtimeEpoch: 21,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.text,
      props: TextProps('Count: 0'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.button,
      props: ButtonProps(enabled: true),
      eventBindings: [
        EventBinding(eventTag: EventTagId.press, handlerId: 9001),
      ],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Increment'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2, 3]),
    SetChildren(nodeId: 3, children: [4]),
    SetRoot(1),
  ],
);

final class _PresentationSuccessRecord {
  const _PresentationSuccessRecord({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.eventBatch,
  });

  final int generation;
  final int presentationId;
  final int revision;
  final Uint8List eventBatch;
}

final class _PresentationRejectionRecord {
  const _PresentationRejectionRecord({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.reason,
  });

  final int generation;
  final int presentationId;
  final int revision;
  final PresentationRejectionReason reason;
}

final class _VisibilityRecord {
  const _VisibilityRecord({required this.generation, required this.eligible});

  final int generation;
  final bool eligible;

  @override
  bool operator ==(Object other) =>
      other is _VisibilityRecord &&
      other.generation == generation &&
      other.eligible == eligible;

  @override
  int get hashCode => Object.hash(generation, eligible);
}

final class _OrderedRuntimeSession implements RuntimeSession {
  final StreamController<RuntimeUpdate> _updates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  final List<int> grants = [];
  final List<_VisibilityRecord> visibilityChanges = [];
  final List<_PresentationSuccessRecord> successes = [];
  final List<_PresentationRejectionRecord> rejections = [];
  var disposed = false;
  var throwOnSuccess = false;

  @override
  Stream<RuntimeUpdate> get updates => _updates.stream;

  void emitCycle({
    required int presentationId,
    required int revision,
    required Uint8List bytes,
  }) {
    _updates.add(
      CycleReady(
        presentationId: presentationId,
        revision: revision,
        bytes: TransferableTypedData.fromList([bytes]),
        recoverableDiagnostic: null,
      ),
    );
  }

  @override
  void grantVsync({required int generation}) {
    grants.add(generation);
  }

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    visibilityChanges.add(
      _VisibilityRecord(generation: generation, eligible: eligible),
    );
  }

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    if (throwOnSuccess) {
      throw StateError('presentation handoff failed');
    }
    successes.add(
      _PresentationSuccessRecord(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        eventBatch: Uint8List.fromList(eventBatch),
      ),
    );
  }

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {
    rejections.add(
      _PresentationRejectionRecord(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        reason: reason,
      ),
    );
  }

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async => RuntimeDebugSnapshot(
    state: RuntimeWorkerState.ready,
    liveGeneration: visibilityChanges.isEmpty
        ? 0
        : visibilityChanges.last.generation,
    eligible: visibilityChanges.isNotEmpty && visibilityChanges.last.eligible,
    pumpCount: 0,
    hasCoalescedGrant: false,
    unresolvedPresentationId: null,
    unresolvedRevision: null,
  );

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _updates.close();
  }
}

final class _TestFrameEligibilitySource implements FrameEligibilitySource {
  _TestFrameEligibilitySource(this._eligible);

  bool _eligible;
  void Function(bool)? _listener;

  @override
  bool get isEligible => _eligible;

  @override
  void start(void Function(bool isEligible) onChanged) {
    _listener = onChanged;
  }

  void emit(bool value) {
    _eligible = value;
    _listener?.call(value);
  }

  @override
  void dispose() {
    _listener = null;
  }
}
