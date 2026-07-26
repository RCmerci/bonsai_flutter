import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets('host effects and route stack round trip through OCaml', (
    tester,
  ) async {
    final client = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(
          config: Uint8List.fromList(utf8.encode('host_navigation')),
        ),
        'RuntimeClient.start',
      ),
    );
    expect(client, isNotNull);
    final runtime = client!;
    addTearDown(() => _bounded(runtime.dispose(), 'RuntimeClient.dispose'));

    final initialResponse = await tester.runAsync(
      () => _bounded(runtime.step(Uint8List(0)), 'initial navigation step'),
    );
    expect(initialResponse, isNotNull);
    expect(initialResponse!.status, RuntimeStatus.ok);
    final initial = FrameCodec.decode(initialResponse.bytes);
    final store = NodeStore()..apply(initial);
    final queue = EventBatchQueue(
      runtimeEpoch: initial.runtimeEpoch,
      displayedRevision: () => store.revision,
    );
    final dispatcher = HostEffectDispatcher(
      implementation: const _FakeHostEffects(),
      onEvent: queue.enqueue,
    );
    addTearDown(dispatcher.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );
    await _present(
      tester,
      runtime,
      initial.targetRevision,
      'initial presentation',
    );

    expect(find.text('Host effects and navigation'), findsOneWidget);
    expect(find.text('Clipboard not read'), findsOneWidget);

    await tester.tap(find.text('Read clipboard'));
    await tester.pump();
    final requestResponse = await tester.runAsync(
      () => _bounded(
        runtime.sendEventBatch(queue.takeBatch()!),
        'clipboard request event',
      ),
    );
    final requestFrame = FrameCodec.decode(requestResponse!.bytes);
    expect(
      requestFrame.operations.whereType<HostRequestOperation>().single.request,
      isA<ClipboardReadRequest>(),
    );
    store.apply(requestFrame);
    await _present(
      tester,
      runtime,
      requestFrame.targetRevision,
      'request presentation',
    );
    await dispatcher.dispatch(requestFrame);

    final response = await tester.runAsync(
      () => _bounded(
        runtime.sendEventBatch(queue.takeBatch()!),
        'clipboard host response',
      ),
    );
    final clipboardFrame = FrameCodec.decode(response!.bytes);
    store.apply(clipboardFrame);
    await tester.pump();
    await _present(
      tester,
      runtime,
      clipboardFrame.targetRevision,
      'clipboard presentation',
    );
    expect(find.text('Clipboard from Flutter'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pump();
    final navigationResponse = await tester.runAsync(
      () => _bounded(
        runtime.sendEventBatch(queue.takeBatch()!),
        'open settings event',
      ),
    );
    final navigationFrame = FrameCodec.decode(navigationResponse!.bytes);
    store.apply(navigationFrame);
    await tester.pumpAndSettle();
    await _present(
      tester,
      runtime,
      navigationFrame.targetRevision,
      'settings presentation',
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Overlay owned by OCaml'), findsOneWidget);
    expect(find.text('Dialog owned by OCaml'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await tester.pumpAndSettle();
    final popResponse = await tester.runAsync(
      () => _bounded(
        runtime.sendEventBatch(queue.takeBatch()!),
        'system route pop',
      ),
    );
    final popFrame = FrameCodec.decode(popResponse!.bytes);
    store.apply(popFrame);
    await tester.pumpAndSettle();

    expect(find.text('Host effects and navigation'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });
}

Future<void> _present(
  WidgetTester tester,
  RuntimeSession runtime,
  int revision,
  String operation,
) async {
  final response = await tester.runAsync(
    () => _bounded(runtime.framePresented(revision), operation),
  );
  expect(response, isNotNull);
  expect(response!.status, RuntimeStatus.ok);
}

final class _FakeHostEffects implements HostEffectImplementation {
  const _FakeHostEffects();

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) async {
    expect(request, isA<ClipboardReadRequest>());
    return const HostStringValue('Clipboard from Flutter');
  }

  @override
  Future<void> cancel(int requestId) async {}
}
