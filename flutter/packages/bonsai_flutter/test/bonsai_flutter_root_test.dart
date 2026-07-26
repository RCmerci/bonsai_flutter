import 'dart:typed_data';
import 'dart:convert';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    await tester.pumpAndSettle();

    expect(find.text('Count: 0'), findsOneWidget);
    expect(runtime.presentedRevisions, [1]);
    expect(runtime.environmentBatchCount, 1);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Count: 1'), findsOneWidget);
    expect(runtime.eventBatchCount, 1);
    expect(runtime.presentedRevisions, [1, 2]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(find.text('Clipboard from Flutter'), findsOneWidget);
    expect(runtime.hostResponseCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(runtime.hostResponseCount, 1);
  });

  testWidgets('revision mismatch automatically requests and applies resync', (
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
    await tester.pumpAndSettle();
    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Count: 1'), findsOneWidget);
    expect(find.textContaining('Bonsai runtime error'), findsNothing);
    expect(runtime.resyncRequestCount, 1);
    expect(runtime.presentedRevisions, [1, 2]);
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
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Count: 0'), findsOneWidget);
      expect(find.textContaining('Bonsai runtime error'), findsNothing);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Count: 1'), findsOneWidget);
      expect(find.textContaining('Bonsai runtime error'), findsNothing);
      expect(runtime.pressBatchCount, 2);
      expect(runtime.presentedRevisions, [1, 2]);
    },
  );
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

final class _HostRequestRuntimeSession implements RuntimeSession {
  var hostResponseCount = 0;
  var disposed = false;
  var revision = 1;

  @override
  Future<RuntimeResponse> step(Uint8List input) async => RuntimeResponse(
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
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async {
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

  RuntimeResponse _response(Uint8List bytes) => RuntimeResponse(
    requestSequence: 2,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: revision,
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<RuntimeResponse> framePresented(int revision) async =>
      _response(Uint8List(0));

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FocusHostRequestRuntimeSession implements RuntimeSession {
  var hostResponseCount = 0;

  @override
  Future<RuntimeResponse> step(Uint8List input) async => _response(
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
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async {
    hostResponseCount += batch.events
        .where((event) => event.eventTag == EventTagId.hostResponse)
        .length;
    return _response(Uint8List(0));
  }

  RuntimeResponse _response(Uint8List bytes) => RuntimeResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: 1,
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<RuntimeResponse> framePresented(int revision) async =>
      _response(Uint8List(0));

  @override
  Future<void> dispose() async {}
}

final class _FakeRuntimeSession implements RuntimeSession {
  final presentedRevisions = <int>[];
  var eventBatchCount = 0;
  var environmentBatchCount = 0;
  var disposed = false;

  @override
  Future<RuntimeResponse> step(Uint8List input) async => RuntimeResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: FrameCodec.encode(counterWidgetSnapshot()),
    revision: 1,
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async {
    expect(batch.events, hasLength(1));
    if (batch.events.single.eventTag == EventTagId.environmentChanged) {
      environmentBatchCount += 1;
      return RuntimeResponse(
        requestSequence: 2,
        status: RuntimeStatus.ok,
        bytes: Uint8List(0),
        revision: 1,
        nextWakeupNanoseconds: -1,
        errorMessage: null,
      );
    }
    eventBatchCount += 1;
    expect(batch.events.single.eventTag, EventTagId.press);
    return RuntimeResponse(
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
      nextWakeupNanoseconds: -1,
      errorMessage: null,
    );
  }

  @override
  Future<RuntimeResponse> framePresented(int revision) async {
    presentedRevisions.add(revision);
    return RuntimeResponse(
      requestSequence: 3,
      status: RuntimeStatus.ok,
      bytes: Uint8List(0),
      revision: revision,
      nextWakeupNanoseconds: -1,
      errorMessage: null,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _RecoverableStaleRuntimeSession implements RuntimeSession {
  final presentedRevisions = <int>[];
  var pressBatchCount = 0;

  @override
  Future<RuntimeResponse> step(Uint8List input) async =>
      _response(bytes: FrameCodec.encode(counterWidgetSnapshot()), revision: 1);

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async {
    expect(batch.events, hasLength(1));
    final event = batch.events.single;
    if (event.eventTag == EventTagId.environmentChanged) {
      return _response(bytes: Uint8List(0), revision: 1);
    }
    expect(event.eventTag, EventTagId.press);
    pressBatchCount += 1;
    if (pressBatchCount == 1) {
      return RuntimeResponse(
        requestSequence: 2,
        status: RuntimeStatus.recoverableError,
        bytes: Uint8List(0),
        revision: 1,
        nextWakeupNanoseconds: -1,
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
  Future<RuntimeResponse> framePresented(int revision) async {
    presentedRevisions.add(revision);
    return _response(bytes: Uint8List(0), revision: revision);
  }

  RuntimeResponse _response({
    required Uint8List bytes,
    required int revision,
  }) => RuntimeResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: bytes,
    revision: revision,
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<void> dispose() async {}
}

final class _ResyncRuntimeSession implements RuntimeSession {
  var resyncRequestCount = 0;
  final presentedRevisions = <int>[];

  @override
  Future<RuntimeResponse> step(Uint8List input) async => RuntimeResponse(
    requestSequence: 1,
    status: RuntimeStatus.ok,
    bytes: FrameCodec.encode(counterWidgetSnapshot()),
    revision: 1,
    nextWakeupNanoseconds: -1,
    errorMessage: null,
  );

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) async {
    final event = batch.events.single;
    if (event.eventTag == EventTagId.environmentChanged) {
      return _response(Uint8List(0), revision: 1);
    }
    if (event.eventTag == EventTagId.resyncRequested) {
      resyncRequestCount += 1;
      return _response(
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
      );
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

  RuntimeResponse _response(Uint8List bytes, {required int revision}) =>
      RuntimeResponse(
        requestSequence: 2,
        status: RuntimeStatus.ok,
        bytes: bytes,
        revision: revision,
        nextWakeupNanoseconds: -1,
        errorMessage: null,
      );

  @override
  Future<RuntimeResponse> framePresented(int revision) async {
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
