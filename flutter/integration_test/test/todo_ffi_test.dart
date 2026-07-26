import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    addTearDown(() => _bounded(runtime!.dispose()));

    final initialResponse = await tester.runAsync(
      () => _bounded(runtime!.step(Uint8List(0))),
    );
    final initialFrame = FrameCodec.decode(initialResponse!.bytes);
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
          node.kind == NodeKind.textInput &&
          (node.props as TextInputProps).sessionId == 2,
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

    final presented = await tester.runAsync(
      () => _bounded(runtime!.framePresented(initialFrame.targetRevision)),
    );
    expect(presented!.status, RuntimeStatus.ok);

    await tester.tap(find.text('Reverse'));
    await tester.pump();
    final batch = queue.takeBatch();
    expect(batch, isNotNull);
    final response = await tester.runAsync(
      () => _bounded(runtime!.sendEventBatch(batch!)),
    );
    final frame = FrameCodec.decode(response!.bytes);
    expect(frame.kind, FrameKind.incremental);
    store.apply(frame);
    await tester.pump();

    final editorAfterNode = store.nodes.values.singleWhere(
      (node) =>
          node.kind == NodeKind.textInput &&
          (node.props as TextInputProps).sessionId == 2,
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
  });
}
