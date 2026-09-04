import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() => registerHostNavigationFfiTests();

void registerHostNavigationFfiTests({
  HostEffectImplementation implementation = const _FakeHostEffects(),
  Future<void> Function()? beforeClipboardRead,
  String expectedClipboardText = 'Clipboard from Flutter',
}) {
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
    final harness = RuntimeHarness(client!);
    addTearDown(() => _bounded(harness.dispose(), 'RuntimeHarness.dispose'));

    final initialCycle = await tester.runAsync(
      () => _bounded(harness.grant(), 'initial navigation grant'),
    );
    expect(initialCycle, isNotNull);
    final initial = FrameCodec.decode(initialCycle!.bytes);
    final store = NodeStore()..apply(initial);
    final queue = EventBatchQueue(
      runtimeEpoch: initial.runtimeEpoch,
      displayedRevision: () => store.revision,
    );
    final dispatcher = HostEffectDispatcher(
      implementation: implementation,
      onEvent: queue.enqueue,
    );
    addTearDown(dispatcher.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );
    expect(find.text('Host effects and navigation'), findsOneWidget);
    expect(find.text('Clipboard not read'), findsOneWidget);

    await beforeClipboardRead?.call();
    await tester.tap(find.text('Read clipboard'));
    await tester.pump();
    final requestResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(queue.takeBatch()!)),
        'clipboard request pump',
      ),
    );
    final requestFrame = FrameCodec.decode(requestResponse!.bytes);
    expect(
      requestFrame.operations.whereType<HostRequestOperation>().single.request,
      isA<ClipboardReadRequest>(),
    );
    store.apply(requestFrame);
    await dispatcher.dispatch(requestFrame);

    final response = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(queue.takeBatch()!)),
        'clipboard host-response pump',
      ),
    );
    final clipboardFrame = FrameCodec.decode(response!.bytes);
    store.apply(clipboardFrame);
    await tester.pump();
    expect(find.text(expectedClipboardText), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pump();
    final navigationResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(queue.takeBatch()!)),
        'open settings pump',
      ),
    );
    final navigationFrame = FrameCodec.decode(navigationResponse!.bytes);
    store.apply(navigationFrame);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Overlay owned by OCaml'), findsOneWidget);
    expect(find.text('Dialog owned by OCaml'), findsOneWidget);
    expect(find.byType(M3EDialog), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await tester.pumpAndSettle();
    final popResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(queue.takeBatch()!)),
        'system route-pop pump',
      ),
    );
    final popFrame = FrameCodec.decode(popResponse!.bytes);
    store.apply(popFrame);
    await tester.pumpAndSettle();

    expect(find.text('Host effects and navigation'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    harness.acknowledge();
  });
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
