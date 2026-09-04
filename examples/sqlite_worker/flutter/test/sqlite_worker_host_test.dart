import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_sqlite_worker_example/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ScriptedRuntime implements RuntimeSession {
  final StreamController<RuntimeUpdate> _updates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  final String status;
  final bool includeTodo;
  final List<EventBatch> eventBatches = [];
  bool _eligible = false;
  int _generation = 0;
  int _nextPresentation = 1;
  bool _initialSent = false;
  bool _awaitingPresentation = false;
  final void Function()? beforeFirstCycle;
  final void Function()? beforeFirstPresentation;

  _ScriptedRuntime({
    required this.status,
    this.includeTodo = false,
    this.beforeFirstCycle,
    this.beforeFirstPresentation,
  });

  @override
  Stream<RuntimeUpdate> get updates => _updates.stream;

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    _generation = generation;
    _eligible = eligible;
  }

  @override
  void grantVsync({required int generation}) {
    if (!_eligible || generation != _generation || _awaitingPresentation) {
      return;
    }
    final bytes = _initialSent
        ? Uint8List(0)
        : FrameCodec.encode(
            _snapshot(status: status, includeTodo: includeTodo),
          );
    if (!_initialSent) beforeFirstCycle?.call();
    _initialSent = true;
    _awaitingPresentation = true;
    _updates.add(
      CycleReady(
        presentationId: _nextPresentation++,
        revision: 1,
        bytes: TransferableTypedData.fromList([bytes]),
        recoverableDiagnostic: null,
      ),
    );
  }

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    if (_nextPresentation == 2) beforeFirstPresentation?.call();
    _awaitingPresentation = false;
    if (eventBatch.isNotEmpty) {
      eventBatches.add(EventBatchCodec.decode(eventBatch));
    }
  }

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {
    _awaitingPresentation = false;
  }

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async => RuntimeDebugSnapshot(
    state: RuntimeWorkerState.ready,
    liveGeneration: _generation,
    eligible: _eligible,
    pumpCount: _nextPresentation - 1,
    hasCoalescedGrant: false,
    unresolvedPresentationId: null,
    unresolvedRevision: null,
  );

  @override
  Future<void> dispose() async => _updates.close();
}

Frame _snapshot({required String status, required bool includeTodo}) {
  final operations = <FrameOperation>[
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.text,
      props: TextProps(status),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 3,
      kind: NodeKind.materialTextField,
      props: MaterialTextFieldProps(
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
        maxUtf8Bytes: null,
        variant: 0,
        label: null,
        supportingText: null,
        errorText: null,
        hasLeading: false,
        hasTrailing: false,
        maxLines: 1,
      ),
      eventBindings: [
        EventBinding(eventTag: EventTagId.textEdit, handlerId: 30),
      ],
    ),
    const CreateNode(
      nodeId: 4,
      kind: NodeKind.materialFilledButton,
      props: MaterialButtonProps(
        variant: MaterialButtonVariant.filled,
        enabled: true,
        autofocus: false,
      ),
      eventBindings: [EventBinding(eventTag: EventTagId.press, handlerId: 40)],
    ),
    const CreateNode(
      nodeId: 5,
      kind: NodeKind.text,
      props: TextProps('Add'),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 6,
      kind: NodeKind.materialFilledButton,
      props: MaterialButtonProps(
        variant: MaterialButtonVariant.filled,
        enabled: true,
        autofocus: false,
      ),
      eventBindings: [EventBinding(eventTag: EventTagId.press, handlerId: 60)],
    ),
    const CreateNode(
      nodeId: 7,
      kind: NodeKind.text,
      props: TextProps('Refresh'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 8,
      kind: NodeKind.text,
      props: TextProps(
        includeTodo ? '1 open · 0 completed' : '0 open · 0 completed',
      ),
      eventBindings: const [],
    ),
    if (includeTodo) ...[
      const CreateNode(
        nodeId: 9,
        kind: NodeKind.text,
        props: TextProps('Persistent Todo'),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 10,
        kind: NodeKind.materialCheckbox,
        props: MaterialCheckboxProps(value: false, enabled: true),
        eventBindings: [
          EventBinding(eventTag: EventTagId.valueChanged, handlerId: 100),
        ],
      ),
    ],
    SetChildren(
      nodeId: 1,
      children: [2, 3, 4, 6, 8, if (includeTodo) 9, if (includeTodo) 10],
    ),
    const SetChildren(nodeId: 4, children: [5]),
    const SetChildren(nodeId: 6, children: [7]),
    const SetRoot(1),
  ];
  return Frame(
    runtimeEpoch: 91,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: operations,
  );
}

Future<_ScriptedRuntime> _pumpHost(
  WidgetTester tester, {
  required String status,
  bool includeTodo = false,
}) async {
  final runtime = _ScriptedRuntime(status: status, includeTodo: includeTodo);
  await tester.pumpWidget(
    MaterialApp(
      home: SqliteWorkerHost(
        resolveApplicationSupport: () async => Directory('/tmp/support'),
        createDirectory: (_) async {},
        runtimeStarter: (_) async => runtime,
      ),
    ),
  );
  for (
    var index = 0;
    index < 12 && find.text(status).evaluate().isEmpty;
    index += 1
  ) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return runtime;
}

void main() {
  testWidgets('shows each host startup stage and total elapsed time', (
    tester,
  ) async {
    var now = Duration.zero;
    final runtime = _ScriptedRuntime(
      status: 'Ready',
      beforeFirstCycle: () => now = const Duration(milliseconds: 15),
      beforeFirstPresentation: () => now = const Duration(milliseconds: 17),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SqliteWorkerHost(
          resolveApplicationSupport: () async {
            now = const Duration(milliseconds: 5);
            return Directory('/tmp/support');
          },
          createDirectory: (_) async {},
          runtimeStarter: (_) async {
            now = const Duration(milliseconds: 12);
            return runtime;
          },
          startupNow: () => now,
        ),
      ),
    );
    expect(find.text('Storage bootstrap: pending'), findsOneWidget);
    expect(find.text('Runtime + Worker ready: pending'), findsOneWidget);
    expect(find.text('First OCaml frame: pending'), findsOneWidget);
    expect(find.text('First Flutter presentation: pending'), findsOneWidget);
    for (
      var index = 0;
      index < 12 && find.text('Total startup: 17.000 ms').evaluate().isEmpty;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Storage bootstrap: 5.000 ms'), findsOneWidget);
    expect(find.text('Runtime + Worker ready: 7.000 ms'), findsOneWidget);
    expect(find.text('First OCaml frame: 3.000 ms'), findsOneWidget);
    expect(find.text('First Flutter presentation: 2.000 ms'), findsOneWidget);
    expect(find.text('Total startup: 17.000 ms'), findsOneWidget);
  });

  testWidgets('never displays a negative startup duration', (tester) async {
    var now = Duration.zero;
    final runtime = _ScriptedRuntime(
      status: 'Ready',
      beforeFirstCycle: () => now = const Duration(milliseconds: 2),
      beforeFirstPresentation: () => now = const Duration(milliseconds: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SqliteWorkerHost(
          resolveApplicationSupport: () async {
            now = const Duration(milliseconds: 5);
            return Directory('/tmp/support');
          },
          createDirectory: (_) async {},
          runtimeStarter: (_) async {
            now = const Duration(milliseconds: 3);
            return runtime;
          },
          startupNow: () => now,
        ),
      ),
    );
    for (
      var index = 0;
      index < 12 && find.text('Total startup: 5.000 ms').evaluate().isEmpty;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Storage bootstrap: 5.000 ms'), findsOneWidget);
    expect(find.text('Runtime + Worker ready: 0.000 ms'), findsOneWidget);
    expect(find.text('First OCaml frame: 0.000 ms'), findsOneWidget);
    expect(find.text('First Flutter presentation: 0.000 ms'), findsOneWidget);
    expect(find.text('Total startup: 5.000 ms'), findsOneWidget);
  });

  for (final status in [
    'Booting',
    'Loading',
    'Ready',
    'Busy',
    'Database error',
    'Terminal',
  ]) {
    testWidgets('renders $status without discarding the last snapshot', (
      tester,
    ) async {
      await _pumpHost(
        tester,
        status: status,
        includeTodo: status != 'Booting' && status != 'Loading',
      );
      expect(find.text(status), findsOneWidget);
      if (status != 'Booting' && status != 'Loading') {
        expect(find.text('Persistent Todo'), findsOneWidget);
      }
    });
  }

  testWidgets('Add, Toggle, Refresh, and retry cross the injected session', (
    tester,
  ) async {
    final runtime = await _pumpHost(tester, status: 'Ready', includeTodo: true);
    await tester.enterText(find.byType(EditableText), 'New Todo');
    await tester.tap(find.text('Add'));
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Refresh'));
    for (var index = 0; index < 4; index += 1) {
      await tester.pump();
    }
    final tags = runtime.eventBatches
        .expand((batch) => batch.events)
        .map((event) => event.eventTag)
        .toList();
    expect(tags, contains(EventTagId.textEdit));
    expect(tags.where((tag) => tag == EventTagId.press), hasLength(2));
    expect(tags, contains(EventTagId.valueChanged));
  });
}
