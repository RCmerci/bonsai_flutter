import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _timeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future) => future.timeout(_timeout);

void main() {
  testWidgets('Todo keyed reverse preserves editor node and focus identity', (
    tester,
  ) async {
    final runtime = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(config: Uint8List.fromList(utf8.encode('todo'))),
      ),
    );
    expect(runtime, isNotNull);
    final harness = RuntimeHarness(runtime!);
    addTearDown(() => _bounded(harness.dispose()));

    final initialCycle = await tester.runAsync(() => _bounded(harness.grant()));
    final initialFrame = FrameCodec.decode(initialCycle!.bytes);
    final store = NodeStore()..apply(initialFrame);
    final queue = EventBatchQueue(
      runtimeEpoch: initialFrame.runtimeEpoch,
      displayedRevision: () => store.revision,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );
    final editorNode = store.nodes.values.singleWhere(
      (node) =>
          node.kind == NodeKind.materialTextField &&
          (node.props as MaterialTextFieldProps).sessionId == 2,
    );
    await tester.tap(find.text('Preserve focus'));
    await tester.pump();
    final editorBefore = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey<int>(editorNode.id)),
        matching: find.byType(EditableText),
      ),
    );
    expect(editorBefore.focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Reverse'));
    await tester.pump();
    editorBefore.focusNode.requestFocus();
    await tester.pump();
    final batch = queue.takeBatch();
    expect(batch, isNotNull);
    final response = await tester.runAsync(
      () => _bounded(harness.advance(events: EventBatchCodec.encode(batch!))),
    );
    final frame = FrameCodec.decode(response!.bytes);
    expect(frame.kind, FrameKind.incremental);
    store.apply(frame);
    await tester.pump();

    final editorAfterNode = store.nodes.values.singleWhere(
      (node) =>
          node.kind == NodeKind.materialTextField &&
          (node.props as MaterialTextFieldProps).sessionId == 2,
    );
    expect(editorAfterNode.id, editorNode.id);
    final editorAfter = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey<int>(editorNode.id)),
        matching: find.byType(EditableText),
      ),
    );
    expect(identical(editorAfter.controller, editorBefore.controller), isTrue);
    expect(identical(editorAfter.focusNode, editorBefore.focusNode), isTrue);
    expect(editorAfter.focusNode.hasFocus, isTrue);
    harness.acknowledge();
  });
}
