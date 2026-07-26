import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(BonsaiFlutterDebug.reset);

  test('node store dump is deterministic and readable', () {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 7,
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
            SetChildren(nodeId: 1, children: [2]),
            SetRoot(1),
          ],
        ),
      );

    if (kReleaseMode) {
      expect(BonsaiFlutterDebug.dumpNodeStore(store), '<debug dump disabled>');
    } else {
      expect(
        BonsaiFlutterDebug.dumpNodeStore(store),
        'Column id=1\n  Text id=2 "Count: 0"',
      );
    }
  });

  test('frame stats combine decode, apply, patch, and dirty-node metrics', () {
    const frame = Frame(
      runtimeEpoch: 9,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.text,
          props: TextProps('hello'),
          eventBindings: [],
        ),
        SetRoot(1),
        RuntimeStatsOperation(
          eventBatchSize: 3,
          bonsaiFlushNanoseconds: 11,
          resultReadNanoseconds: 12,
          reconcileNanoseconds: 13,
          encodeNanoseconds: 14,
          patchCount: 2,
          patchBytes: 80,
          lifecycleNanoseconds: 15,
          fullSnapshotCount: 1,
          resyncCount: 0,
        ),
      ],
    );
    final encoded = FrameCodec.encode(frame);
    final decoded = FrameCodec.decode(encoded);
    final result = NodeStore().apply(decoded);
    expect(result.dirtyNodeIds, {1});

    final stats = BonsaiFlutterDebug.frameStats().single;
    expect(stats.runtimeEpoch, 9);
    expect(stats.revision, 1);
    expect(stats.frameKind, FrameKind.fullSnapshot);
    expect(stats.patchCount, 2);
    expect(stats.patchBytes, encoded.length);
    expect(stats.dirtyNodeCount, 1);
    expect(stats.fullSnapshotCount, 1);
    expect(stats.decodeDuration, isNotNull);
    expect(stats.nodeStoreApplyDuration, isNotNull);
    expect(stats.eventBatchSize, 3);
    expect(stats.bonsaiFlushNanoseconds, 11);
    expect(stats.resultReadNanoseconds, 12);
    expect(stats.reconcileNanoseconds, 13);
    expect(stats.encodeNanoseconds, 14);
    expect(stats.lifecycleNanoseconds, 15);
  });

  test('event queue publishes batch, coalesced, and dropped counts', () {
    final queue = EventBatchQueue(
      runtimeEpoch: 5,
      displayedRevision: () => 2,
      maxPendingEvents: 1,
    );
    const scroll = RendererEvent(
      nodeId: 1,
      eventTag: EventTagId.scrollNotification,
      handlerId: 8,
      payload: ScrollEventPayload(pixels: 1, delta: 1),
    );
    queue
      ..enqueue(scroll)
      ..enqueue(
        const RendererEvent(
          nodeId: 1,
          eventTag: EventTagId.scrollNotification,
          handlerId: 8,
          payload: ScrollEventPayload(pixels: 2, delta: 1),
        ),
      );
    expect(queue.takeBatch(), isNotNull);

    const frame = Frame(
      runtimeEpoch: 5,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.empty,
          props: EmptyProps(),
          eventBindings: [],
        ),
        SetRoot(1),
      ],
    );
    NodeStore().apply(FrameCodec.decode(FrameCodec.encode(frame)));
    final stats = BonsaiFlutterDebug.frameStats().single;
    expect(stats.eventBatchSize, 1);
    expect(stats.coalescedEventCount, 1);
    expect(stats.droppedEventCount, 0);
  });
}
