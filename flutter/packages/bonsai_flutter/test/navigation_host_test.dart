import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('declarative pages emit typed system-pop requests', (
    tester,
  ) async {
    final store = NodeStore()..apply(_navigationSnapshot());
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(),
          onEvent: events.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Overlay content'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await tester.pumpAndSettle();

    expect(events, hasLength(1));
    expect(events.single.eventTag, EventTagId.routePop);
    expect(
      events.single.payload,
      const RoutePopEventPayload(pageKey: 'settings', result: null),
    );
  });

  group('Slide navigation', () {
    testWidgets(
      'enters with front-loaded monotonic motion and inbox parallax',
      (tester) async {
        final fixture = await _pumpSlideFixture(tester);

        fixture.pushDetail();
        await tester.pump();
        final start = _pageLeadingEdge(tester, 'Detail');
        final inboxStart = _pageLeadingEdge(tester, 'Inbox');

        await tester.pump(const Duration(milliseconds: 125));
        final quarter = _pageLeadingEdge(tester, 'Detail');
        final inboxQuarter = _pageLeadingEdge(tester, 'Inbox');
        await tester.pump(const Duration(milliseconds: 125));
        final halfway = _pageLeadingEdge(tester, 'Detail');
        await tester.pump(const Duration(milliseconds: 125));
        final threeQuarters = _pageLeadingEdge(tester, 'Detail');
        await tester.pump(const Duration(milliseconds: 125));
        final end = _pageLeadingEdge(tester, 'Detail');

        final width =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        final progressAtQuarter = (width - quarter) / width;
        final progressAtHalfway = (width - halfway) / width;
        final firstQuarterDistance = start - quarter;
        final lastQuarterDistance = threeQuarters - end;

        expect(start, closeTo(width, 1 / tester.view.devicePixelRatio));
        expect(end, closeTo(0, 1 / tester.view.devicePixelRatio));
        expect(
          [start, quarter, halfway, threeQuarters, end],
          orderedEquals(
            [start, quarter, halfway, threeQuarters, end]
              ..sort((a, b) => b.compareTo(a)),
          ),
        );
        expect(progressAtQuarter, greaterThan(0.25));
        expect(progressAtHalfway, greaterThan(0.5));
        expect(firstQuarterDistance, greaterThan(lastQuarterDistance));
        expect(inboxStart, closeTo(0, 1));
        expect(inboxQuarter, lessThan(0));
        expect(inboxQuarter.abs(), lessThan(quarter.abs()));
        expect(find.text('Inbox', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets('leading-edge drag tracks the finger and can cancel', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(96, 0));
      await tester.pump();

      expect(navigator.userGestureInProgress, isTrue);
      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(96, 2));

      await gesture.up();
      expect(navigator.userGestureInProgress, isTrue);
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('distance edge-pop commit emits one typed detail key', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(260, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(fixture.events.single.eventTag, EventTagId.routePop);
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detail', result: null),
      );
    });

    testWidgets('qualifying leading-edge fling commits exactly once', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      await tester.flingFrom(const Offset(5, 120), const Offset(80, 0), 1200);
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detail', result: null),
      );
    });

    testWidgets('edge-pop guards reject invalid starts and route states', (
      tester,
    ) async {
      final rootOnly = await _pumpSlideFixture(tester, pushable: false);
      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(rootOnly.events, isEmpty);

      final fixture = await _pumpSlideFixture(tester, canPop: false);
      fixture.pushDetail();
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.dragFrom(const Offset(180, 120), const Offset(180, 0));
      await tester.dragFrom(const Offset(5, 120), const Offset(-180, 0));
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('edge-pop cannot begin while the push is transitioning', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('RTL mirrors the physical leading edge and direction', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(
        tester,
        textDirection: TextDirection.rtl,
      );
      fixture.pushDetail();
      await tester.pumpAndSettle();
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      final gesture = await tester.startGesture(Offset(width - 5, 120));
      await gesture.moveBy(const Offset(-96, 0));
      await tester.pump();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(-96, 2));
      await gesture.moveBy(const Offset(-180, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.events, hasLength(1));
    });

    testWidgets('reduced motion preserves direct interactive tracking', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester, disableAnimations: true);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(72, 0));
      await tester.pump();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(72, 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.events, isEmpty);
    });
  });
}

double _pageLeadingEdge(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label, skipOffstage: false)).dx;

final class _SlideFixture {
  _SlideFixture({
    required this.store,
    required this.events,
    required this.canPop,
    required this.pushable,
  });

  final NodeStore store;
  final List<RendererEvent> events;
  final bool canPop;
  final bool pushable;

  void pushDetail() {
    if (!pushable) return;
    store.apply(_detailPageFrame(canPop: canPop));
  }
}

Future<_SlideFixture> _pumpSlideFixture(
  WidgetTester tester, {
  bool canPop = true,
  bool pushable = true,
  bool disableAnimations = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(400, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = NodeStore()..apply(_rootPageFrame());
  final events = <RendererEvent>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 300),
            disableAnimations: disableAnimations,
            accessibleNavigation: disableAnimations,
          ),
          child: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
            onEvent: events.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _SlideFixture(
    store: store,
    events: events,
    canPop: canPop,
    pushable: pushable,
  );
}

Frame _rootPageFrame() => const Frame(
  runtimeEpoch: 72,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'slide-test'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 701),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'inbox',
        transition: PageTransition.none,
        canPop: false,
        restorationId: 'inbox-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Inbox'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2]),
    SetChildren(nodeId: 2, children: [3]),
    SetChildren(nodeId: 3, children: [4]),
    SetRoot(1),
  ],
);

Frame _detailPageFrame({required bool canPop}) => Frame(
  runtimeEpoch: 72,
  baseRevision: 1,
  targetRevision: 2,
  kind: FrameKind.incremental,
  operations: [
    CreateNode(
      nodeId: 5,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'detail',
        transition: PageTransition.slide,
        canPop: canPop,
        restorationId: 'detail-page',
      ),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 6,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 7,
      kind: NodeKind.text,
      props: TextProps('Detail'),
      eventBindings: [],
    ),
    const SetChildren(nodeId: 5, children: [6]),
    const SetChildren(nodeId: 6, children: [7]),
    const SetChildren(nodeId: 1, children: [2, 5]),
  ],
);

Frame _navigationSnapshot() => const Frame(
  runtimeEpoch: 51,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'app'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 700),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'home',
        transition: PageTransition.none,
        canPop: false,
        restorationId: 'home-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.text,
      props: TextProps('Home'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'settings',
        transition: PageTransition.fade,
        canPop: true,
        restorationId: 'settings-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 5,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 6,
      kind: NodeKind.text,
      props: TextProps('Settings'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 7,
      kind: NodeKind.overlay,
      props: OverlayProps(
        alignment: OverlayAlignment.center,
        dismissible: false,
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 8,
      kind: NodeKind.text,
      props: TextProps('Overlay content'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 9,
      kind: NodeKind.materialDialog,
      props: MaterialDialogProps(barrierDismissible: false),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 10,
      kind: NodeKind.text,
      props: TextProps('Confirm'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2, 4]),
    SetChildren(nodeId: 2, children: [3]),
    SetChildren(nodeId: 4, children: [5]),
    SetChildren(nodeId: 5, children: [6, 7, 9]),
    SetChildren(nodeId: 7, children: [8]),
    SetChildren(nodeId: 9, children: [10]),
    SetRoot(1),
  ],
);
