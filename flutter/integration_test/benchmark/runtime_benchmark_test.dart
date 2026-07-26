import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future) => future.timeout(_timeout);

void _metric(String name, Duration elapsed) {
  // Benchmark output is intentionally parseable as one metric per line.
  // ignore: avoid_print
  print('${name.padRight(36)} ${elapsed.inMicroseconds} us');
}

void main() {
  testWidgets('macOS arm64 integration benchmark', (tester) async {
    final runtime = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(config: Uint8List.fromList(utf8.encode('counter'))),
      ),
    );
    expect(runtime, isNotNull);
    addTearDown(() => _bounded(runtime!.dispose()));

    final initialResponse = await tester.runAsync(
      () => _bounded(runtime!.step(Uint8List(0))),
    );
    final initial = FrameCodec.decode(initialResponse!.bytes);
    final store = NodeStore()..apply(initial);
    final queue = EventBatchQueue(
      runtimeEpoch: initial.runtimeEpoch,
      displayedRevision: () => store.revision,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );
    await tester.runAsync(
      () => _bounded(runtime!.framePresented(initial.targetRevision)),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final click = Stopwatch()..start();
    final clickResponse = await tester.runAsync(
      () => _bounded(runtime!.sendEventBatch(queue.takeBatch()!)),
    );
    final incremental = FrameCodec.decode(clickResponse!.bytes);
    store.apply(incremental);
    await tester.pump();
    await tester.runAsync(
      () => _bounded(runtime!.framePresented(incremental.targetRevision)),
    );
    click.stop();
    _metric('click-to-frame-presented', click.elapsed);

    queue.requestResync();
    final resync = Stopwatch()..start();
    final resyncResponse = await tester.runAsync(
      () => _bounded(runtime!.sendEventBatch(queue.takeBatch()!)),
    );
    final fullResync = FrameCodec.decode(resyncResponse!.bytes);
    expect(fullResync.kind, FrameKind.fullSnapshot);
    store.apply(fullResync);
    await tester.pump();
    await tester.runAsync(
      () => _bounded(runtime!.framePresented(fullResync.targetRevision)),
    );
    resync.stop();
    _metric('full resync presented', resync.elapsed);

    final visibleStore = NodeStore()..apply(_visibleFrame(1000));
    final visible = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: BonsaiFlutterView(store: visibleStore),
        ),
      ),
    );
    await tester.pump();
    visible.stop();
    _metric('1000 visible widgets pump', visible.elapsed);

    final virtualStore = NodeStore()..apply(_virtualFrame());
    final virtualized = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: BonsaiFlutterView(store: virtualStore),
        ),
      ),
    );
    await tester.pump();
    virtualized.stop();
    _metric('10000 logical keyed nodes pump', virtualized.elapsed);

    final resize = Stopwatch()..start();
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    resize.stop();
    _metric('window resize pump', resize.elapsed);

    final textStore = NodeStore()..apply(_textInputFrame());
    final textQueue = EventBatchQueue(
      runtimeEpoch: 3,
      displayedRevision: () => textStore.revision,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: textStore, onEvent: textQueue.enqueue),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    final typing = Stopwatch()..start();
    for (var index = 0; index < 100; index += 1) {
      controller.value = TextEditingValue(
        text: '快速输入 $index 😀',
        selection: TextSelection.collapsed(offset: '快速输入 $index 😀'.length),
      );
    }
    final typingBatch = textQueue.takeBatch();
    typing.stop();
    expect(typingBatch, isNotNull);
    expect(typingBatch!.events, hasLength(100));
    _metric('rapid typing batch (100 edits)', typing.elapsed);
  });
}

Frame _visibleFrame(int count) => Frame(
  runtimeEpoch: 2,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    for (var index = 0; index < count; index += 1)
      CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Visible $index'),
        eventBindings: const [],
      ),
    SetChildren(
      nodeId: 1,
      children: [for (var index = 0; index < count; index += 1) index + 2],
    ),
    const SetRoot(1),
  ],
);

Frame _virtualFrame() {
  final props = const VirtualListProps(
    totalCount: 10000,
    firstIndex: 0,
    itemExtent: 24,
    overscan: 4,
    axis: ScrollAxis.vertical,
  ).toNativeWidgetProps();
  return Frame(
    runtimeEpoch: 2,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: [
      CreateNode(
        nodeId: 1,
        kind: NodeKind.nativeWidget,
        props: props,
        eventBindings: const [],
      ),
      for (var index = 0; index < 20; index += 1)
        CreateNode(
          nodeId: index + 2,
          kind: NodeKind.text,
          props: TextProps('Logical item $index'),
          eventBindings: const [],
        ),
      SetChildren(
        nodeId: 1,
        children: [for (var index = 0; index < 20; index += 1) index + 2],
      ),
      const SetRoot(1),
    ],
  );
}

Frame _textInputFrame() => const Frame(
  runtimeEpoch: 3,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
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
        updateMode: TextUpdateMode.ack,
        autofocus: false,
      ),
      eventBindings: [
        EventBinding(eventTag: EventTagId.textEdit, handlerId: 1),
        EventBinding(eventTag: EventTagId.textSubmit, handlerId: 2),
        EventBinding(eventTag: EventTagId.focusChanged, handlerId: 3),
      ],
    ),
    SetRoot(1),
  ],
);
