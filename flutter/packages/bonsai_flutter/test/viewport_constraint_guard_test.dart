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
          viewportType: SingleChildScrollView,
          guidance: 'Body.Vertical.fill',
        ),
        (
          name: 'horizontal ListView',
          frame: _coreViewportFrame(
            viewportKind: NodeKind.listView,
            axis: ScrollAxis.horizontal,
          ),
          viewportType: ListView,
          guidance: 'Body.Horizontal.fill',
        ),
        (
          name: 'vertical VirtualList',
          frame: _nativeViewportFrame(
            VirtualListProps(
              totalCount: 20,
              firstIndex: 0,
              itemExtent: 48,
              overscan: 2,
              axis: ScrollAxis.vertical,
            ).toNativeWidgetProps(),
            axis: ScrollAxis.vertical,
          ),
          viewportType: ListView,
          guidance: 'Body.Vertical.fill',
        ),
        (
          name: 'horizontal SparseExtentList',
          frame: _nativeViewportFrame(
            const SparseExtentListProps(
              totalCount: 20,
              firstIndex: 0,
              defaultItemExtent: 48,
              extentOverrides: [],
              overscan: 2,
              axis: ScrollAxis.horizontal,
            ).toNativeWidgetProps(),
            axis: ScrollAxis.horizontal,
          ),
          viewportType: ListView,
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
              kind: NodeKind.listView,
              props: ListViewProps(axis: ScrollAxis.vertical, reverse: false),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.text,
              props: TextProps('Row'),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2, 3]),
            SetChildren(nodeId: 3, children: [4]),
            SetChildren(nodeId: 4, children: [5]),
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
    expect(find.byType(ListView), findsNothing);

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
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.getSize(find.byType(ListView)).height, 240);
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
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(RendererLayoutError), findsOneWidget);
  });
}

Frame _coreViewportFrame({
  required NodeKind viewportKind,
  required ScrollAxis axis,
}) {
  final vertical = axis == ScrollAxis.vertical;
  final viewportProps = switch (viewportKind) {
    NodeKind.scrollView => ScrollViewProps(axis: axis, reverse: false),
    NodeKind.listView => ListViewProps(axis: axis, reverse: false),
    _ => throw ArgumentError.value(viewportKind, 'viewportKind'),
  };
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
        kind: NodeKind.text,
        props: TextProps('Scrollable'),
        eventBindings: [],
      ),
      const SetChildren(nodeId: 1, children: [2, 3]),
      const SetChildren(nodeId: 3, children: [4]),
      const SetRoot(1),
    ],
  );
}

Frame _nativeViewportFrame(
  NativeWidgetProps props, {
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
        kind: NodeKind.nativeWidget,
        props: props,
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 4,
        kind: NodeKind.text,
        props: TextProps('Scrollable'),
        eventBindings: [],
      ),
      const SetChildren(nodeId: 1, children: [2, 3]),
      const SetChildren(nodeId: 3, children: [4]),
      const SetRoot(1),
    ],
  );
}
