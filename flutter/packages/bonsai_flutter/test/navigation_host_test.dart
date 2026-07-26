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
}

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
