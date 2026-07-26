import 'package:bonsai_flutter/src/protocol/frame.dart';
import 'package:bonsai_flutter/src/store/node_store.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  test('full snapshot commits a validated tree atomically', () {
    final store = NodeStore();
    final result = store.apply(counterSnapshot(text: 'Count: 0'));

    expect(store.runtimeEpoch, 7);
    expect(store.revision, 1);
    expect(store.rootId, 1);
    expect(store.nodes, hasLength(2));
    expect(store.node(2).props, const TextProps('Count: 0'));
    expect(result.dirtyNodeIds, {1, 2});
  });

  test('one text update replaces only the affected node', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));
    final rootBefore = store.node(1);
    final textBefore = store.node(2);
    final notifications = <int>[];
    store.subscribe(1, () => notifications.add(1));
    store.subscribe(2, () => notifications.add(2));

    final result = store.apply(
      const Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: TextProps('Count: 1'))],
      ),
    );

    expect(identical(store.node(1), rootBefore), isTrue);
    expect(identical(store.node(2), textBefore), isFalse);
    expect(store.node(2).props, const TextProps('Count: 1'));
    expect(result.dirtyNodeIds, {2});
    expect(notifications, [2]);
  });

  test('revision mismatch leaves the previous store untouched', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));
    final nodesBefore = store.nodes;

    expect(
      () => store.apply(
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 0,
          targetRevision: 3,
          kind: FrameKind.incremental,
          operations: [],
        ),
      ),
      throwsA(
        isA<FrameApplyException>().having(
          (error) => error.code,
          'code',
          FrameErrorCode.revisionMismatch,
        ),
      ),
    );

    expect(identical(store.nodes, nodesBefore), isTrue);
    expect(store.revision, 1);
  });

  test('invalid child reference rolls back every operation', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));
    final nodesBefore = store.nodes;

    expect(
      () => store.apply(
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(nodeId: 2, props: TextProps('must roll back')),
            SetChildren(nodeId: 1, children: [999]),
          ],
        ),
      ),
      throwsA(
        isA<FrameApplyException>().having(
          (error) => error.code,
          'code',
          FrameErrorCode.missingNode,
        ),
      ),
    );

    expect(identical(store.nodes, nodesBefore), isTrue);
    expect(store.node(2).props, const TextProps('Count: 0'));
    expect(store.revision, 1);
  });

  test('cycles are rejected without notifying subscribers', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));
    var notifications = 0;
    store.subscribe(1, () => notifications += 1);

    expect(
      () => store.apply(
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            SetChildren(nodeId: 2, children: [1]),
          ],
        ),
      ),
      throwsA(
        isA<FrameApplyException>().having(
          (error) => error.code,
          'code',
          FrameErrorCode.cycle,
        ),
      ),
    );

    expect(notifications, 0);
    expect(store.revision, 1);
  });

  test('drop succeeds only after references are removed', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));

    final result = store.apply(
      const Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          SetChildren(nodeId: 1, children: []),
          DropNode(2),
        ],
      ),
    );

    expect(store.nodes.keys, {1});
    expect(result.droppedNodeIds, {2});
    expect(result.dirtyNodeIds, {1});
  });

  test('full snapshot replaces epoch and reports every old node dropped', () {
    final store = NodeStore()..apply(counterSnapshot(text: 'Count: 0'));

    final result = store.apply(
      const Frame(
        runtimeEpoch: 8,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.text,
            props: TextProps('new runtime'),
            eventBindings: [],
          ),
          SetRoot(1),
        ],
      ),
    );

    expect(store.runtimeEpoch, 8);
    expect(store.nodes, hasLength(1));
    expect(result.droppedNodeIds, {1, 2});
    expect(result.dirtyNodeIds, {1});
  });

  test('a node cannot have multiple parents', () {
    final store = NodeStore();

    expect(
      () => store.apply(
        const Frame(
          runtimeEpoch: 9,
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
              kind: NodeKind.column,
              props: LinearProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: TextProps('shared'),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2, 3]),
            SetChildren(nodeId: 2, children: [3]),
            SetRoot(1),
          ],
        ),
      ),
      throwsA(
        isA<FrameApplyException>().having(
          (error) => error.code,
          'code',
          FrameErrorCode.multipleParents,
        ),
      ),
    );

    expect(store.nodes, isEmpty);
  });

  test('store listeners fire once only after a successful commit', () {
    final store = NodeStore();
    var notifications = 0;
    final unsubscribe = store.subscribeStore(() => notifications += 1);

    store.apply(counterSnapshot(text: 'Count: 0'));
    expect(notifications, 1);

    expect(
      () => store.apply(
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            SetChildren(nodeId: 1, children: [999]),
          ],
        ),
      ),
      throwsA(isA<FrameApplyException>()),
    );
    expect(notifications, 1);

    unsubscribe();
    store.apply(
      const Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: TextProps('Count: 1'))],
      ),
    );
    expect(notifications, 1);
  });
}
