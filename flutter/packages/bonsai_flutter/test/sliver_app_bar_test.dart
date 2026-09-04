import 'fixture.dart';
import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sliver app bar renders M3E variants and every action', (
    tester,
  ) async {
    final store = _sliverAppBarStore(
      props: _props(actionCount: 2, variant: 2, shape: 1, density: 1),
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
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'M3EAppBar',
      ),
      findsOneWidget,
    );
    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.actions, hasLength(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('sliver app bar rejects invalid render parameters', (
    tester,
  ) async {
    final invalidProps = <SliverAppBarProps>[
      _props(snap: true),
      _props(actionCount: -1),
      _props(variant: 3),
      _props(shape: 2),
      _props(density: 2),
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
      props: _props(snap: true),
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
      Frame(
        runtimeEpoch: 1,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 10, props: _props())],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SliverToBoxAdapter), findsNothing);
    expect(find.byType(SliverAppBar), findsOneWidget);
  });
}

SliverAppBarProps _props({
  bool pinned = true,
  bool floating = false,
  bool snap = false,
  int actionCount = 0,
  int variant = 1,
  int shape = 0,
  int density = 0,
}) => SliverAppBarProps(
  pinned: pinned,
  floating: floating,
  snap: snap,
  hasLeading: false,
  backgroundColor: null,
  foregroundColor: null,
  actionCount: actionCount,
  centerTitle: false,
  variant: variant,
  shape: shape,
  density: density,
  semanticLabel: 'Expressive app bar',
);

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
