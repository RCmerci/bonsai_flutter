import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sliver fixed extent props round trip through the frame codec', () {
    const props = SliverFixedExtentProps(
      totalCount: 50000,
      firstIndex: 100,
      itemExtent: 48,
      overscan: 4,
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverFixedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations[0] as CreateNode;
    expect(create.kind, NodeKind.sliverFixedExtent);
    expect(create.props, props);
  });

  test('sliver varied extent props round trip through the frame codec', () {
    const props = SliverVariedExtentProps(
      totalCount: 50000,
      firstIndex: 40,
      defaultItemExtent: 48,
      overscan: 5,
      extentOverrides: [
        SparseExtentOverride(index: 3, extent: 120),
        SparseExtentOverride(index: 42, extent: 312),
      ],
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations[0] as CreateNode;
    expect(create.kind, NodeKind.sliverVariedExtent);
    expect(create.props, props);
  });

  test('sliver varied extent props round trip with a transition', () {
    const transition = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 240,
      collapseDurationMs: 190,
      expandCurve: SparseExtentCurve.easeOutCubic,
      collapseCurve: SparseExtentCurve.easeInOutCubic,
    );
    const props = SliverVariedExtentProps(
      totalCount: 20,
      firstIndex: 4,
      defaultItemExtent: 88,
      overscan: 4,
      extentOverrides: [SparseExtentOverride(index: 6, extent: 320)],
      transition: transition,
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations[0] as CreateNode;
    expect(create.props, props);
    final decodedProps = create.props as SliverVariedExtentProps;
    expect(decodedProps.transition, transition);
  });

  test('sliver varied extent props without transition round trip', () {
    const props = SliverVariedExtentProps(
      totalCount: 20,
      firstIndex: 4,
      defaultItemExtent: 88,
      overscan: 4,
      extentOverrides: [],
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations[0] as CreateNode;
    expect(create.props, props);
    expect((create.props as SliverVariedExtentProps).transition, isNull);
  });

  test('sparse extent transition equality and curve wire ids', () {
    const a = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.linear,
      collapseCurve: SparseExtentCurve.linear,
    );
    const b = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.linear,
      collapseCurve: SparseExtentCurve.linear,
    );
    const c = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.easeOut,
      collapseCurve: SparseExtentCurve.linear,
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(SparseExtentCurve.linear.wireId, 0);
    expect(SparseExtentCurve.easeOutCubic.wireId, 4);
    expect(SparseExtentCurve.fromWireId(5), SparseExtentCurve.easeInOutCubic);
  });

  test('sparse extent override equality', () {
    const a = SparseExtentOverride(index: 3, extent: 120);
    const b = SparseExtentOverride(index: 3, extent: 120);
    const c = SparseExtentOverride(index: 4, extent: 120);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.hashCode, b.hashCode);
  });

  testWidgets('sliver fixed extent mounts children in a CustomScrollView', (
    tester,
  ) async {
    final children = List.generate(
      20,
      (index) => CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Item ${100 + index}'),
        eventBindings: const [],
      ),
    );
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.scrollView,
              props: const ScrollViewProps(
                axis: ScrollAxis.vertical,
                reverse: false,
              ),
              eventBindings: const [],
            ),
            CreateNode(
              nodeId: 100,
              kind: NodeKind.sliverFixedExtent,
              props: const SliverFixedExtentProps(
                totalCount: 50000,
                firstIndex: 100,
                itemExtent: 48,
                overscan: 4,
              ),
              eventBindings: const [],
            ),
            ...children,
            SetChildren(
              nodeId: 100,
              children: List.generate(20, (index) => index + 2),
            ),
            SetChildren(nodeId: 1, children: const [100]),
            const SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverFixedExtentList), findsOneWidget);
    expect(find.text('Item 100'), findsOneWidget);
  });
}
