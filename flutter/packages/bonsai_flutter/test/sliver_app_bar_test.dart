import 'fixture.dart';
import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sliver app bar renders native app bar and every action', (
    tester,
  ) async {
    final store = _sliverAppBarStore(
      props: _props(actionCount: 2),
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
      findsNothing,
    );
    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.actions, hasLength(2));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  for (final pinned in [false, true]) {
    for (final wrapped in [false, true]) {
      testWidgets('retained bottom updates pinned=$pinned wrapped=$wrapped', (
        tester,
      ) async {
        final events = <RendererEvent>[];
        SliverAppBarProps props({bool bottom = true, double height = 48}) =>
            _props(
              pinned: pinned,
              actionCount: 2,
              hasLeading: true,
              expandedHeight: 200,
              collapsedHeight: 80,
              toolbarHeight: 64,
              hasFlexibleSpace: true,
              hasBottom: bottom,
              bottomHeight: bottom ? height : null,
              stretch: true,
              forceElevated: true,
              elevation: 4,
              automaticallyImplyLeading: false,
            );
        final store = _sliverAppBarStore(
          props: props(),
          slotChildren: [3, 2, 5, 6, 7, 8],
          extraOperations: [
            for (final entry in {
              3: 'Leading',
              5: 'Search',
              6: 'Settings',
              7: 'Flexible',
              9: 'Bottom',
            }.entries)
              CreateNode(
                nodeId: entry.key,
                kind: NodeKind.text,
                props: TextProps(entry.value),
                eventBindings: const [],
              ),
            const CreateNode(
              nodeId: 8,
              kind: NodeKind.gesture,
              props: GestureProps(),
              eventBindings: [
                EventBinding(eventTag: EventTagId.tap, handlerId: 100),
              ],
            ),
            const SetChildren(nodeId: 8, children: [9]),
          ],
        );
        var revision = 1;
        void update(List<FrameOperation> operations) {
          store.apply(
            Frame(
              runtimeEpoch: 1,
              baseRevision: revision,
              targetRevision: ++revision,
              kind: FrameKind.incremental,
              operations: operations,
            ),
          );
        }

        update([
          const CreateNode(
            nodeId: 20,
            kind: NodeKind.sliverBox,
            props: EmptyProps(),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 21,
            kind: NodeKind.sizedBox,
            props: SizedBoxProps(width: null, height: 3000),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 23,
            kind: NodeKind.empty,
            props: EmptyProps(),
            eventBindings: [],
          ),
          const SetChildren(nodeId: 21, children: [23]),
          const SetChildren(nodeId: 20, children: [21]),
          if (wrapped) ...[
            const CreateNode(
              nodeId: 22,
              kind: NodeKind.sliverPadding,
              props: SliverPaddingProps(
                EdgeInsetsValue(left: 12, top: 16, right: 12, bottom: 16),
              ),
              eventBindings: [],
            ),
            const SetChildren(nodeId: 22, children: [10]),
          ],
          SetChildren(nodeId: 1, children: [wrapped ? 22 : 10, 20]),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
              child: BonsaiFlutterView(store: store, onEvent: events.add),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
        expect(appBar.actions, hasLength(2));
        expect(appBar.leading, isNotNull);
        expect(appBar.flexibleSpace, isNotNull);
        expect(appBar.bottom, isNull);
        expect(appBar.expandedHeight, 200);
        expect(appBar.collapsedHeight, 80);
        expect(appBar.toolbarHeight, 64);
        expect(appBar.stretch, isTrue);
        expect(appBar.forceElevated, isTrue);
        expect(appBar.elevation, 4);
        expect(appBar.automaticallyImplyLeading, isFalse);
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(1200);
        await tester.pumpAndSettle();
        expect(find.text('Bottom'), findsOneWidget);
        final header = find.byType(SliverPersistentHeader).last;
        expect(
          tester.getTopLeft(find.text('Bottom')).dy,
          closeTo(24 + (pinned ? 80 : 0), .01),
        );
        await tester.tap(find.text('Bottom'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.handlerId == 100), hasLength(1));
        update([
          UpdateProps(nodeId: 10, props: props(height: 72)),
          const CreateNode(
            nodeId: 12,
            kind: NodeKind.text,
            props: TextProps('Replacement'),
            eventBindings: [],
          ),
          const SetChildren(nodeId: 8, children: [12]),
          const DropNode(9),
        ]);
        await tester.pump();
        expect(find.text('Bottom'), findsNothing);
        expect(find.text('Replacement'), findsOneWidget);
        expect(
          tester.widget<SliverPersistentHeader>(header).delegate.maxExtent,
          72,
        );
        await tester.tap(find.text('Replacement'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.handlerId == 100), hasLength(2));
        update([
          UpdateProps(nodeId: 10, props: props(bottom: false)),
          const SetChildren(nodeId: 10, children: [3, 2, 5, 6, 7]),
          const DropNode(8),
          const DropNode(12),
        ]);
        await tester.pump();
        expect(find.text('Replacement'), findsNothing);
        update([
          UpdateProps(nodeId: 10, props: props()),
          const CreateNode(
            nodeId: 8,
            kind: NodeKind.gesture,
            props: GestureProps(),
            eventBindings: [
              EventBinding(eventTag: EventTagId.tap, handlerId: 100),
            ],
          ),
          const CreateNode(
            nodeId: 12,
            kind: NodeKind.text,
            props: TextProps('Replacement'),
            eventBindings: [],
          ),
          const SetChildren(nodeId: 8, children: [12]),
          const SetChildren(nodeId: 10, children: [3, 2, 5, 6, 7, 8]),
        ]);
        await tester.pump();
        expect(find.text('Replacement'), findsOneWidget);
        expect(
          tester.state<ScrollableState>(find.byType(Scrollable).first),
          same(scrollable),
        );
        expect(scrollable.position.pixels, 1200);
        await tester.tap(find.text('Replacement'));
        await tester.pumpAndSettle();
        expect(events.where((e) => e.handlerId == 100), hasLength(3));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('rejects missing and surplus slot children', (tester) async {
    final registry = WidgetRegistry.standard();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            for (final count in [0, 1, 3, 5]) {
              expect(
                () => registry.build(
                  context,
                  UiNode(
                    id: 10,
                    kind: NodeKind.sliverAppBar,
                    props: _props(
                      hasFlexibleSpace: true,
                      hasBottom: true,
                      bottomHeight: 48,
                      actionCount: 1,
                    ),
                    eventBindings: const [],
                    parentData: const NoParentData(),
                    children: List.generate(count, (i) => i + 20),
                    localRevision: 1,
                    deliveryGeneration: 1,
                  ),
                  List.generate(count, (i) => Text('$i')),
                  null,
                ),
                throwsA(isA<RendererBuildException>()),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('sliver app bar rejects invalid render parameters', (
    tester,
  ) async {
    final invalidProps = <SliverAppBarProps>[
      _props(snap: true),
      _props(actionCount: -1),
      _props(toolbarHeight: 0),
      _props(toolbarHeight: double.nan),
      _props(expandedHeight: -1),
      _props(expandedHeight: 40),
      _props(collapsedHeight: 20),
      _props(expandedHeight: 60, collapsedHeight: 80),
      _props(elevation: -1),
      _props(elevation: double.infinity),
      _props(hasBottom: true),
      _props(bottomHeight: 48),
      _props(hasBottom: true, bottomHeight: 0),
      _props(hasBottom: true, bottomHeight: double.nan),
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
  bool hasLeading = false,
  bool pinned = true,
  bool floating = false,
  bool snap = false,
  int actionCount = 0,
  double? expandedHeight,
  double? collapsedHeight,
  double toolbarHeight = 56,
  bool hasFlexibleSpace = false,
  bool hasBottom = false,
  double? bottomHeight,
  bool stretch = false,
  bool forceElevated = false,
  double? elevation,
  bool automaticallyImplyLeading = true,
}) => SliverAppBarProps(
  pinned: pinned,
  floating: floating,
  snap: snap,
  hasLeading: hasLeading,
  backgroundColor: null,
  foregroundColor: null,
  actionCount: actionCount,
  centerTitle: false,
  expandedHeight: expandedHeight,
  collapsedHeight: collapsedHeight,
  toolbarHeight: toolbarHeight,
  hasFlexibleSpace: hasFlexibleSpace,
  hasBottom: hasBottom,
  bottomHeight: bottomHeight,
  stretch: stretch,
  forceElevated: forceElevated,
  elevation: elevation,
  automaticallyImplyLeading: automaticallyImplyLeading,
  semanticLabel: 'Native app bar',
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
