import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final testCase
      in <({String name, Frame frame, Type viewportType, String guidance})>[
        (
          name: 'vertical ScrollView',
          frame: _coreViewportFrame(
            viewportKind: NodeKind.scrollView,
            axis: ScrollAxis.vertical,
          ),
          viewportType: CustomScrollView,
          guidance: 'Body.Vertical.fill',
        ),
        (
          name: 'horizontal ScrollView',
          frame: _coreViewportFrame(
            viewportKind: NodeKind.scrollView,
            axis: ScrollAxis.horizontal,
          ),
          viewportType: CustomScrollView,
          guidance: 'Body.Horizontal.fill',
        ),
        (
          name: 'vertical SliverFixedExtent',
          frame: _sliverViewportFrame(
            sliverKind: NodeKind.sliverFixedExtent,
            sliverProps: const SliverFixedExtentProps(
              totalCount: 20,
              firstIndex: 0,
              itemExtent: 48,
              overscan: 2,
            ),
            axis: ScrollAxis.vertical,
          ),
          viewportType: CustomScrollView,
          guidance: 'Body.Vertical.fill',
        ),
        (
          name: 'horizontal SliverVariedExtent',
          frame: _sliverViewportFrame(
            sliverKind: NodeKind.sliverVariedExtent,
            sliverProps: const SliverVariedExtentProps(
              totalCount: 20,
              firstIndex: 0,
              defaultItemExtent: 48,
              overscan: 2,
              extentOverrides: [],
            ),
            axis: ScrollAxis.horizontal,
          ),
          viewportType: CustomScrollView,
          guidance: 'Body.Horizontal.fill',
        ),
      ]) {
    testWidgets('${testCase.name} reports one stable constraint violation', (
      tester,
    ) async {
      final store = NodeStore()..apply(testCase.frame);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 480,
            child: BonsaiFlutterView(store: store),
          ),
        ),
      );

      final diagnostic = tester.takeException();
      expect(diagnostic, isNotNull);
      expect(diagnostic.toString(), contains('node 3'));
      expect(diagnostic.toString(), contains('requires bounded'));
      expect(diagnostic.toString(), contains(testCase.guidance));
      expect(find.byType(testCase.viewportType), findsNothing);
      expect(find.byType(RendererLayoutError), findsOneWidget);

      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('valid constraints preserve revision-scoped deduplication', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 72,
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
              props: TextProps('Fixed'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.sizedBox,
              props: SizedBoxProps(width: null, height: null),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.scrollView,
              props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.sliverList,
              props: EmptyProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 6,
              kind: NodeKind.text,
              props: TextProps('Row'),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2, 3]),
            SetChildren(nodeId: 3, children: [4]),
            SetChildren(nodeId: 4, children: [5]),
            SetChildren(nodeId: 5, children: [6]),
            SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 480, child: BonsaiFlutterView(store: store)),
      ),
    );
    expect(tester.takeException(), isNotNull);
    expect(find.byType(CustomScrollView), findsNothing);

    store.apply(
      const Frame(
        runtimeEpoch: 72,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(
            nodeId: 3,
            props: SizedBoxProps(width: null, height: 240),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(CustomScrollView)).height, 240);
    expect(find.byType(RendererLayoutError), findsNothing);

    store.apply(
      const Frame(
        runtimeEpoch: 72,
        baseRevision: 2,
        targetRevision: 3,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(
            nodeId: 3,
            props: SizedBoxProps(width: null, height: null),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsNothing);
    expect(find.byType(RendererLayoutError), findsOneWidget);
  });
}

Frame _coreViewportFrame({
  required NodeKind viewportKind,
  required ScrollAxis axis,
}) {
  final vertical = axis == ScrollAxis.vertical;
  final viewportProps = ScrollViewProps(axis: axis, reverse: false);
  return Frame(
    runtimeEpoch: 70,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: [
      CreateNode(
        nodeId: 1,
        kind: vertical ? NodeKind.column : NodeKind.row,
        props: const LinearProps(),
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 2,
        kind: NodeKind.text,
        props: TextProps('Fixed'),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 3,
        kind: viewportKind,
        props: viewportProps,
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 4,
        kind: NodeKind.sliverList,
        props: EmptyProps(),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 5,
        kind: NodeKind.text,
        props: TextProps('Scrollable'),
        eventBindings: [],
      ),
      const SetChildren(nodeId: 1, children: [2, 3]),
      const SetChildren(nodeId: 3, children: [4]),
      const SetChildren(nodeId: 4, children: [5]),
      const SetRoot(1),
    ],
  );
}

Frame _sliverViewportFrame({
  required NodeKind sliverKind,
  required UiProps sliverProps,
  required ScrollAxis axis,
}) {
  final vertical = axis == ScrollAxis.vertical;
  return Frame(
    runtimeEpoch: 71,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: [
      CreateNode(
        nodeId: 1,
        kind: vertical ? NodeKind.column : NodeKind.row,
        props: const LinearProps(),
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 2,
        kind: NodeKind.text,
        props: TextProps('Fixed'),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 3,
        kind: NodeKind.scrollView,
        props: ScrollViewProps(axis: axis, reverse: false),
        eventBindings: const [],
      ),
      CreateNode(
        nodeId: 4,
        kind: sliverKind,
        props: sliverProps,
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 5,
        kind: NodeKind.text,
        props: TextProps('Scrollable'),
        eventBindings: [],
      ),
      const SetChildren(nodeId: 1, children: [2, 3]),
      const SetChildren(nodeId: 3, children: [4]),
      const SetChildren(nodeId: 4, children: [5]),
      const SetRoot(1),
    ],
  );
}
