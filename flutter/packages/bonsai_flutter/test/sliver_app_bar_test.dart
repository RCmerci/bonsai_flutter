import 'fixture.dart';
import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sliver app bar renders a preferred-size bottom', (tester) async {
    final store = _sliverAppBarStore(
      props: const SliverAppBarProps(pinned: true, hasBottom: true),
      slotChildren: const [2, 3],
      extraOperations: const [
        CreateNode(
          nodeId: 3,
          kind: NodeKind.preferredSize,
          props: PreferredSizeProps(height: 36),
          eventBindings: [],
        ),
        CreateNode(
          nodeId: 4,
          kind: NodeKind.text,
          props: TextProps('Bottom'),
          eventBindings: [],
        ),
        SetChildren(nodeId: 3, children: [4]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Bottom'), findsOneWidget);
    expect(
      tester.widget<SliverAppBar>(find.byType(SliverAppBar)).bottom,
      isNotNull,
    );
  });

  testWidgets('sliver app bar maps every action child', (tester) async {
    final store = _sliverAppBarStore(
      props: const SliverAppBarProps(pinned: true, hasActions: true),
      slotChildren: const [2, 5, 6],
      extraOperations: const [
        CreateNode(
          nodeId: 5,
          kind: NodeKind.text,
          props: TextProps('Search'),
          eventBindings: [],
        ),
        CreateNode(
          nodeId: 6,
          kind: NodeKind.text,
          props: TextProps('Settings'),
          eventBindings: [],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.actions, hasLength(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('sliver app bar rejects invalid render parameters', (
    tester,
  ) async {
    final invalidProps = <SliverAppBarProps>[
      const SliverAppBarProps(pinned: false, snap: true),
      const SliverAppBarProps(pinned: false, toolbarHeight: 0),
      const SliverAppBarProps(pinned: false, toolbarHeight: -1),
      const SliverAppBarProps(pinned: false, toolbarHeight: double.nan),
      const SliverAppBarProps(pinned: false, toolbarHeight: double.infinity),
      const SliverAppBarProps(pinned: false, expandedHeight: -1),
      const SliverAppBarProps(
        pinned: false,
        expandedHeight: 100,
        collapsedHeight: 120,
      ),
      const SliverAppBarProps(pinned: false, collapsedHeight: 40),
      const SliverAppBarProps(pinned: false, elevation: -1),
      const SliverAppBarProps(pinned: false, elevation: double.nan),
      const SliverAppBarProps(pinned: false, elevation: double.infinity),
    ];
    final registry = WidgetRegistry.standard();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    for (final props in invalidProps) {
      expect(
        () => registry.build(
          context,
          UiNode(
            id: 1,
            kind: NodeKind.sliverAppBar,
            props: props,
            eventBindings: const [],
            parentData: const NoParentData(),
            children: const [2],
            localRevision: 1,
            deliveryGeneration: 1,
          ),
          const [Text('Title')],
          null,
        ),
        throwsA(isA<RendererBuildException>()),
        reason: 'invalid props were accepted: $props',
      );
    }
  });

  testWidgets('sliver renderer errors preserve the viewport child shape', (
    tester,
  ) async {
    final store = _sliverAppBarStore(
      props: const SliverAppBarProps(pinned: false, snap: true),
      slotChildren: const [2],
      extraOperations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isA<RendererBoundaryError>());
    expect(tester.takeException(), isNull);
    expect(find.byType(SliverToBoxAdapter), findsOneWidget);
    expect(
      tester.renderObject(find.byType(SliverToBoxAdapter)),
      isA<RenderSliver>(),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);

    store.apply(
      const Frame(
        runtimeEpoch: 1,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 10, props: SliverAppBarProps(pinned: true)),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SliverToBoxAdapter), findsNothing);
    expect(find.byType(SliverAppBar), findsOneWidget);
  });
}

NodeStore _sliverAppBarStore({
  required SliverAppBarProps props,
  required List<int> slotChildren,
  required List<FrameOperation> extraOperations,
}) => NodeStore()
  ..apply(
    Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        const CreateNode(
          nodeId: 1,
          kind: NodeKind.scrollView,
          props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
          eventBindings: [],
        ),
        CreateNode(
          nodeId: 10,
          kind: NodeKind.sliverAppBar,
          props: props,
          eventBindings: const [],
        ),
        const CreateNode(
          nodeId: 2,
          kind: NodeKind.text,
          props: TextProps('Title'),
          eventBindings: [],
        ),
        ...extraOperations,
        SetChildren(nodeId: 10, children: slotChildren),
        const SetChildren(nodeId: 1, children: [10]),
        const SetRoot(1),
      ],
    ),
  );
