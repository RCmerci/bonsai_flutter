import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_network_example/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects the network entrypoint and renders startup state', (
    tester,
  ) async {
    final starter = _RecordingStarter();
    await tester.pumpWidget(
      MaterialApp(home: NetworkHost(runtimeStarter: starter.call)),
    );
    await tester.pump();

    expect(find.text('Starting Secure Network Lab…'), findsOneWidget);
    expect(starter.calls, 1);
    expect(String.fromCharCodes(starter.config!), 'network');
  });

  testWidgets('renders the first OCaml-owned frame', (tester) async {
    final runtime = _ScriptedRuntime();
    await tester.pumpWidget(
      MaterialApp(home: NetworkHost(runtimeStarter: (_) async => runtime)),
    );
    for (
      var attempt = 0;
      attempt < 12 && find.text('Secure Network Lab').evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Secure Network Lab'), findsOneWidget);
  });

  testWidgets('renders native runtime startup failures', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkHost(
          runtimeStarter: (_) async =>
              throw StateError('native startup failed'),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 8 &&
          find
              .textContaining('Unable to start Secure Network Lab')
              .evaluate()
              .isEmpty;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.textContaining('Unable to start Secure Network Lab'),
      findsOneWidget,
    );
    expect(find.textContaining('native startup failed'), findsOneWidget);
  });

  testWidgets('application shell has no Flutter-owned network state', (
    tester,
  ) async {
    late Widget built;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          built = const NetworkApplication().build(context);
          return const SizedBox.shrink();
        },
      ),
    );

    final application = built as MaterialApp;
    expect(application.title, 'bonsai_flutter Secure Network Lab');
    expect(application.home, isA<NetworkHost>());
  });
}

final class _RecordingStarter {
  int calls = 0;
  Uint8List? config;
  final Completer<RuntimeSession> _session = Completer<RuntimeSession>();

  Future<RuntimeSession> call(Uint8List value) {
    calls += 1;
    config = Uint8List.fromList(value);
    return _session.future;
  }
}

final class _ScriptedRuntime implements RuntimeSession {
  final StreamController<RuntimeUpdate> _updates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  bool _eligible = false;
  bool _sent = false;
  int _generation = 0;

  @override
  Stream<RuntimeUpdate> get updates => _updates.stream;

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    _generation = generation;
    _eligible = eligible;
  }

  @override
  void grantVsync({required int generation}) {
    if (!_eligible || generation != _generation || _sent) return;
    _sent = true;
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: const [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.text,
          props: TextProps('Secure Network Lab'),
          eventBindings: [],
        ),
        SetRoot(1),
      ],
    );
    _updates.add(
      CycleReady(
        presentationId: 1,
        revision: 1,
        bytes: TransferableTypedData.fromList([FrameCodec.encode(frame)]),
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
  }) {}

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {}

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async => RuntimeDebugSnapshot(
    state: RuntimeWorkerState.ready,
    liveGeneration: _generation,
    eligible: _eligible,
    pumpCount: _sent ? 1 : 0,
    hasCoalescedGrant: false,
    unresolvedPresentationId: null,
    unresolvedRevision: null,
  );

  @override
  Future<void> dispose() => _updates.close();
}
