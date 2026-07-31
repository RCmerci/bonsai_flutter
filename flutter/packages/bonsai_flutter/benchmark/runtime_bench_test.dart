import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bonsai_flutter Dart renderer benchmark', () {
    final full = _fullFrame(1000);
    final encoded = FrameCodec.encode(full);

    _benchmark('frame decode (1000 nodes)', 200, (_) {
      FrameCodec.decode(encoded);
    });
    _benchmark('NodeStore full transaction', 100, (_) {
      NodeStore().apply(full);
    });

    final oneDirty = NodeStore()..apply(full);
    var oneDirtyRevision = 1;
    _benchmark('one dirty node', 5000, (iteration) {
      oneDirty.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: oneDirtyRevision,
          targetRevision: ++oneDirtyRevision,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: 2,
              props: TextProps('Changed ${iteration & 1}'),
            ),
          ],
        ),
      );
    });

    final hundredDirty = NodeStore()..apply(full);
    var hundredDirtyRevision = 1;
    _benchmark('100 dirty nodes', 500, (iteration) {
      hundredDirty.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: hundredDirtyRevision,
          targetRevision: ++hundredDirtyRevision,
          kind: FrameKind.incremental,
          operations: [
            for (var index = 0; index < 100; index += 1)
              UpdateProps(
                nodeId: index + 2,
                props: TextProps('Value $iteration/$index'),
              ),
          ],
        ),
      );
    });

    final reorder = NodeStore()..apply(full);
    final ascending = [for (var id = 2; id < 1002; id += 1) id];
    final descending = ascending.reversed.toList(growable: false);
    var reorderRevision = 1;
    _benchmark('keyed reorder (1000 child IDs)', 1000, (iteration) {
      reorder.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: reorderRevision,
          targetRevision: ++reorderRevision,
          kind: FrameKind.incremental,
          operations: [
            SetChildren(
              nodeId: 1,
              children: iteration.isEven ? ascending : descending,
            ),
          ],
        ),
      );
    });

    _benchmarkControllerRetention();
    _benchmarkResourceDisposal();
    _benchmarkEventBatching();

    final transferBytes = Uint8List(64 * 1024);
    _benchmark('isolate transfer materialization (64 KiB)', 5000, (_) {
      TransferableTypedData.fromList([transferBytes]).materialize();
    });
  });
}

void _benchmark(
  String name,
  int iterations,
  void Function(int iteration) operation,
) {
  for (var warmup = 0; warmup < 10; warmup += 1) {
    operation(warmup);
  }
  const maximumSamples = 20;
  final sampleCount = iterations < maximumSamples ? iterations : maximumSamples;
  final samples = <double>[];
  var completed = 0;
  for (var sample = 0; sample < sampleCount; sample += 1) {
    final sampleIterations =
        iterations ~/ sampleCount + (sample < iterations % sampleCount ? 1 : 0);
    final stopwatch = Stopwatch()..start();
    for (
      var sampleIteration = 0;
      sampleIteration < sampleIterations;
      sampleIteration += 1
    ) {
      operation(completed++);
    }
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds.toDouble() / sampleIterations);
  }
  samples.sort();
  final middle = sampleCount ~/ 2;
  final median = sampleCount.isOdd
      ? samples[middle]
      : (samples[middle - 1] + samples[middle]) / 2;
  final p95 = samples[(sampleCount * 0.95).ceil() - 1];
  // Benchmark output is intentionally parseable as one metric per line.
  // ignore: avoid_print
  print(
    '${name.padRight(40)} '
    'median ${median.toStringAsFixed(2).padLeft(10)} us/op '
    'p95 ${p95.toStringAsFixed(2).padLeft(10)} us/op '
    '($iterations iterations, $sampleCount samples)',
  );
}

void _benchmarkControllerRetention() {
  final store = NodeStore()..apply(_textInputFrame());
  final resources = RendererResourceStore()..synchronize(store);
  final props = store.node(1).props as TextInputProps;
  final original = resources.acquireTextInput(1, props);
  var revision = 1;
  _benchmark('text controller retention', 5000, (iteration) {
    final next = TextInputProps(
      sessionId: 1,
      documentRevision: iteration + 2,
      value: TextEditingStateValue(
        text: 'Value $iteration',
        selection: const TextRangeValue(startUtf16: 0, endUtf16: 0),
        composing: null,
      ),
      enabled: true,
      readOnly: false,
      obscureText: false,
      keyboardType: TextKeyboardType.text,
      inputAction: TextInputActionKind.done,
      acceptedLocalRevision: 0,
      updateMode: TextUpdateMode.correction,
      autofocus: false,
    );
    store.apply(
      Frame(
        runtimeEpoch: 2,
        baseRevision: revision,
        targetRevision: ++revision,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 1, props: next)],
      ),
    );
    resources.synchronize(store);
    final retained = resources.acquireTextInput(1, next);
    if (!identical(original, retained)) {
      throw StateError('Text input controller identity changed');
    }
  });
  resources.dispose();
}

void _benchmarkResourceDisposal() {
  final store = NodeStore();
  final resources = RendererResourceStore();
  _benchmark('resource create/dispose via resync', 1000, (iteration) {
    store.apply(
      Frame(
        runtimeEpoch: 3,
        baseRevision: 0,
        targetRevision: iteration + 2,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.nativeWidget,
            props: NativeWidgetProps(
              kindId: 42,
              version: 1,
              capabilityBits: NativeCapability.resource,
              payload: Uint8List(0),
            ),
            eventBindings: const [],
          ),
          const SetRoot(1),
        ],
      ),
    );
    resources.synchronize(store);
    resources.acquireNativeResource<Object>(
      nodeId: 1,
      kindId: 42,
      version: 1,
      create: Object.new,
      dispose: (_) {},
    );
  });
  resources.dispose();
}

void _benchmarkEventBatching() {
  _benchmark('event batching (1000 ordered events)', 200, (_) {
    final queue = EventBatchQueue(
      runtimeEpoch: 1,
      displayedRevision: () => 1,
      maxPendingEvents: 1000,
    );
    for (var index = 0; index < 1000; index += 1) {
      queue.enqueue(
        const RendererEvent(
          nodeId: 1,
          eventTag: EventTagId.press,
          handlerId: 1,
          payload: UnitEventPayload(),
        ),
      );
    }
    if (queue.takeBatch()!.events.length != 1000) {
      throw StateError('Ordered events were lost');
    }
  });
}

Frame _fullFrame(int childCount) => Frame(
  runtimeEpoch: 1,
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
    for (var index = 0; index < childCount; index += 1)
      CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Item $index'),
        eventBindings: const [],
      ),
    SetChildren(
      nodeId: 1,
      children: [for (var index = 0; index < childCount; index += 1) index + 2],
    ),
    const SetRoot(1),
  ],
);

Frame _textInputFrame() => const Frame(
  runtimeEpoch: 2,
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
      eventBindings: [],
    ),
    SetRoot(1),
  ],
);
