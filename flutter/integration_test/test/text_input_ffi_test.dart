import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets('rapid composing edits round trip through OCaml without echo', (
    tester,
  ) async {
    final client = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(
          config: Uint8List.fromList(utf8.encode('text_input')),
        ),
        'RuntimeClient.start',
      ),
    );
    expect(client, isNotNull);
    final harness = RuntimeHarness(client!);
    addTearDown(() => _bounded(harness.dispose(), 'RuntimeHarness.dispose'));

    final initialCycle = await tester.runAsync(
      () => _bounded(harness.grant(), 'initial text input grant'),
    );
    expect(initialCycle, isNotNull);
    final initialFrame = FrameCodec.decode(initialCycle!.bytes);
    final store = NodeStore()..apply(initialFrame);
    final queue = EventBatchQueue(
      runtimeEpoch: initialFrame.runtimeEpoch,
      displayedRevision: () => store.revision,
    );
    final resources = RendererResourceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(
            store: store,
            resourceStore: resources,
            onEvent: queue.enqueue,
          ),
        ),
      ),
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final controller = editable.controller;
    expect(controller.text, 'Type here');

    controller.value = const TextEditingValue(
      text: '拼😀',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    controller.value = const TextEditingValue(
      text: '拼😀音',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    expect(queue.pendingCount, 2);

    final response = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(queue.takeBatch()!)),
        'rapid composing event pump',
      ),
    );
    expect(response, isNotNull);
    final incremental = FrameCodec.decode(response!.bytes);
    expect(incremental.kind, FrameKind.incremental);
    final update = incremental.operations.whereType<UpdateProps>().single;
    expect(
      update.props,
      isA<TextInputProps>()
          .having(
            (props) => props.acceptedLocalRevision,
            'accepted local revision',
            2,
          )
          .having((props) => props.updateMode, 'mode', TextUpdateMode.ack)
          .having((props) => props.value.text, 'text', '拼😀音'),
    );

    store.apply(incremental);
    await tester.pump();
    expect(controller.text, '拼😀音');
    expect(controller.value.composing, const TextRange(start: 0, end: 4));
    expect(
      identical(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        controller,
      ),
      isTrue,
    );
    expect(resources.liveResourceCount, 1);
    harness.acknowledge();
  });
}
