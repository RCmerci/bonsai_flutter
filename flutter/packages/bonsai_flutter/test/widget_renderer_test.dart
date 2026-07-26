import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  testWidgets('renders a typed Counter snapshot with stable node keys', (
    tester,
  ) async {
    final store = NodeStore()..apply(counterWidgetSnapshot());

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    expect(find.text('Count: 0'), findsOneWidget);
    expect(find.text('Increment'), findsOneWidget);
    expect(find.byType(Column), findsOneWidget);
    for (final nodeId in [1, 2, 3, 4]) {
      expect(find.byKey(ValueKey<int>(nodeId)), findsOneWidget);
    }
  });

  testWidgets('one text patch preserves unaffected ancestor elements', (
    tester,
  ) async {
    final store = NodeStore()..apply(counterWidgetSnapshot());
    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));
    final rootBefore = tester.element(find.byKey(const ValueKey<int>(1)));
    final buttonBefore = tester.element(find.byKey(const ValueKey<int>(3)));

    store.apply(
      const Frame(
        runtimeEpoch: 21,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: TextProps('Count: 1'))],
      ),
    );
    await tester.pump();

    expect(find.text('Count: 0'), findsNothing);
    expect(find.text('Count: 1'), findsOneWidget);
    expect(
      identical(tester.element(find.byKey(const ValueKey<int>(1))), rootBefore),
      isTrue,
    );
    expect(
      identical(
        tester.element(find.byKey(const ValueKey<int>(3))),
        buttonBefore,
      ),
      isTrue,
    );
  });

  testWidgets('button press dispatches only the bound typed event', (
    tester,
  ) async {
    final store = NodeStore()..apply(counterWidgetSnapshot());
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(events, hasLength(1));
    expect(events.single.nodeId, 3);
    expect(events.single.eventTag, EventTagId.press);
    expect(events.single.handlerId, 9001);
    expect(events.single.payload, const UnitEventPayload());
  });

  testWidgets('interaction primitives emit typed pointer and key events', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 25,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.gesture,
              props: GestureProps(),
              eventBindings: [
                EventBinding(eventTag: EventTagId.tap, handlerId: 101),
                EventBinding(eventTag: EventTagId.pointerDown, handlerId: 102),
                EventBinding(eventTag: EventTagId.pointerUp, handlerId: 103),
              ],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.focusScope,
              props: FocusScopeProps(autofocus: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.focusChanged, handlerId: 104),
              ],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.mouseRegion,
              props: MouseRegionProps(opaque: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.pointerEnter, handlerId: 105),
                EventBinding(eventTag: EventTagId.pointerLeave, handlerId: 106),
              ],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.keyboardListener,
              props: KeyboardListenerProps(
                autofocus: true,
                keyPolicy: KeyEventPolicy.handled,
              ),
              eventBindings: [
                EventBinding(eventTag: EventTagId.key, handlerId: 107),
              ],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.text,
              props: TextProps('Interact'),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2]),
            SetChildren(nodeId: 2, children: [3]),
            SetChildren(nodeId: 3, children: [4]),
            SetChildren(nodeId: 4, children: [5]),
            SetRoot(1),
          ],
        ),
      );
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GestureDetector), findsOneWidget);
    expect(find.byType(FocusScope), findsWidgets);
    expect(find.byType(MouseRegion), findsWidgets);
    expect(find.byType(Focus), findsWidgets);

    await tester.tap(find.text('Interact'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    expect(
      events.any(
        (event) =>
            event.eventTag == EventTagId.tap &&
            event.handlerId == 101 &&
            event.payload is TapEventPayload,
      ),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event.eventTag == EventTagId.pointerDown &&
            event.handlerId == 102 &&
            event.payload is PointerEventPayload,
      ),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event.eventTag == EventTagId.key &&
            event.handlerId == 107 &&
            event.payload is KeyEventPayload,
      ),
      isTrue,
    );
  });

  testWidgets('button press flows into the canonical encoded event batch', (
    tester,
  ) async {
    final store = NodeStore()..apply(counterWidgetSnapshot());
    final queue = EventBatchQueue(
      runtimeEpoch: store.runtimeEpoch!,
      displayedRevision: () => store.revision,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(
      EventBatchCodec.encode(queue.takeBatch()!),
      orderedEquals(readHexFixture('counter_press.hex')),
    );
  });

  testWidgets('root replacement rebuilds from the new committed root', (
    tester,
  ) async {
    final store = NodeStore()..apply(counterWidgetSnapshot());
    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    store.apply(
      const Frame(
        runtimeEpoch: 22,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 8,
            kind: NodeKind.text,
            props: TextProps('Replacement'),
            eventBindings: [],
          ),
          SetRoot(8),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Count: 0'), findsNothing);
    expect(find.text('Replacement'), findsOneWidget);
    expect(find.byKey(const ValueKey<int>(8)), findsOneWidget);
  });

  testWidgets('renders typed Phase 4 layout, semantics, theme, and checkbox', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 31,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.theme,
              props: ThemeProps(
                brightness: ThemeBrightness.dark,
                colorSeedArgb: 0xff2060a0,
              ),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.semantics,
              props: SemanticsProps(
                label: 'Accept terms',
                hint: 'Double tap to toggle',
                value: 'Not accepted',
                role: SemanticsRoleValue.checkbox,
                enabled: true,
                selected: false,
                checked: false,
                focusable: true,
                obscured: false,
                liveRegion: true,
                headingLevel: 2,
                sortKey: 3.5,
                actions: {SemanticsActionValue.tap},
              ),
              eventBindings: [
                EventBinding(
                  eventTag: EventTagId.semanticsAction,
                  handlerId: 79,
                ),
              ],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.padding,
              props: PaddingProps(
                EdgeInsetsValue(left: 12, top: 8, right: 12, bottom: 8),
              ),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.center,
              props: CenterProps(widthFactor: null, heightFactor: 1.5),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.scrollView,
              props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
              eventBindings: [
                EventBinding(
                  eventTag: EventTagId.scrollNotification,
                  handlerId: 80,
                ),
              ],
            ),
            CreateNode(
              nodeId: 6,
              kind: NodeKind.materialCheckbox,
              props: MaterialCheckboxProps(value: false, enabled: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.valueChanged, handlerId: 81),
              ],
            ),
            SetChildren(nodeId: 1, children: [2]),
            SetChildren(nodeId: 2, children: [3]),
            SetChildren(nodeId: 3, children: [4]),
            SetChildren(nodeId: 4, children: [5]),
            SetChildren(nodeId: 5, children: [6]),
            SetRoot(1),
          ],
        ),
      );
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );

    expect(
      tester.widget<Padding>(find.byType(Padding)).padding,
      const EdgeInsets.fromLTRB(12, 8, 12, 8),
    );
    final center = tester.widget<Center>(find.byType(Center));
    expect(center.widthFactor, isNull);
    expect(center.heightFactor, 1.5);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .scrollDirection,
      Axis.vertical,
    );
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((widget) => widget.properties.label == 'Accept terms'),
      isTrue,
    );
    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .firstWhere((widget) => widget.properties.label == 'Accept terms');
    expect(semantics.properties.hint, 'Double tap to toggle');
    expect(semantics.properties.value, 'Not accepted');
    expect(semantics.properties.checked, false);
    expect(semantics.properties.focused, false);
    expect(semantics.properties.liveRegion, true);
    expect(semantics.properties.headingLevel, 2);
    expect((semantics.properties.sortKey! as OrdinalSortKey).order, 3.5);
    semantics.properties.onTap!();
    expect(events.single.eventTag, EventTagId.semanticsAction);
    expect(events.single.handlerId, 79);
    expect(
      events.single.payload,
      const Int64EventPayload(SemanticsActionValue.tapWireId),
    );
    events.clear();
    expect(
      tester
          .widgetList<Theme>(find.byType(Theme))
          .any((widget) => widget.data.brightness == Brightness.dark),
      isTrue,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(events, hasLength(1));
    expect(events.single.eventTag, EventTagId.valueChanged);
    expect(events.single.handlerId, 81);
    expect(events.single.payload, const BoolEventPayload(true));
  });

  testWidgets('renderer error boundary identifies the failed logical node', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 91,
          baseRevision: 0,
          targetRevision: 7,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.text,
              props: TextProps('Invalid parent'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.empty,
              props: EmptyProps(),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2]),
            SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    final reported = tester.takeException();
    expect(reported, isA<RendererBoundaryError>());
    final error = reported! as RendererBoundaryError;
    expect(error.nodeId, 1);
    expect(error.kind, NodeKind.text);
    expect(error.revision, 7);
    expect(find.byType(BonsaiRendererErrorWidget), findsOneWidget);
    expect(find.textContaining('node 1'), findsOneWidget);
  });

  testWidgets('typed flex and stack parent data reach Flutter', (tester) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 23,
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
              kind: NodeKind.row,
              props: LinearProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: TextProps('Expanded'),
              eventBindings: [],
              parentData: FlexParentData(flex: 2, fit: FlexParentFit.tight),
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.stack,
              props: EmptyProps(),
              eventBindings: [],
              parentData: FlexParentData(flex: 1, fit: FlexParentFit.tight),
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.text,
              props: TextProps('Positioned'),
              eventBindings: [],
              parentData: StackPositionData(left: 8, top: 12),
            ),
            SetChildren(nodeId: 1, children: [2, 4]),
            SetChildren(nodeId: 2, children: [3]),
            SetChildren(nodeId: 4, children: [5]),
            SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    expect(find.byType(Expanded), findsNWidgets(2));
    expect(find.byType(Positioned), findsOneWidget);
    final positioned = tester.widget<Positioned>(find.byType(Positioned));
    expect(positioned.left, 8);
    expect(positioned.top, 12);
  });

  testWidgets('renders the stable Material semantic surface', (tester) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 24,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.materialScaffold,
              props: MaterialScaffoldProps(hasAppBar: true),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.materialAppBar,
              props: MaterialAppBarProps(centerTitle: true),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: TextProps('Title'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.column,
              props: LinearProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.materialTextButton,
              props: MaterialButtonProps(
                variant: MaterialButtonVariant.text,
                enabled: true,
                autofocus: false,
              ),
              eventBindings: [
                EventBinding(eventTag: EventTagId.press, handlerId: 50),
              ],
            ),
            CreateNode(
              nodeId: 6,
              kind: NodeKind.text,
              props: TextProps('Action'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 7,
              kind: NodeKind.materialSwitch,
              props: MaterialSwitchProps(value: true, enabled: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.valueChanged, handlerId: 51),
              ],
            ),
            CreateNode(
              nodeId: 8,
              kind: NodeKind.materialCard,
              props: MaterialCardProps(elevation: 4),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 9,
              kind: NodeKind.materialListTile,
              props: MaterialListTileProps(
                enabled: true,
                selected: true,
                hasSubtitle: false,
                hasLeading: false,
                hasTrailing: false,
              ),
              eventBindings: [
                EventBinding(eventTag: EventTagId.press, handlerId: 52),
              ],
            ),
            CreateNode(
              nodeId: 10,
              kind: NodeKind.text,
              props: TextProps('Tile'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 11,
              kind: NodeKind.materialDivider,
              props: MaterialDividerProps(thickness: 2),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 12,
              kind: NodeKind.materialCircularProgressIndicator,
              props: MaterialProgressProps(value: 0.5),
              eventBindings: [],
            ),
            SetChildren(nodeId: 1, children: [2, 4]),
            SetChildren(nodeId: 2, children: [3]),
            SetChildren(nodeId: 4, children: [5, 7, 8, 11, 12]),
            SetChildren(nodeId: 5, children: [6]),
            SetChildren(nodeId: 8, children: [9]),
            SetChildren(nodeId: 9, children: [10]),
            SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders native Cupertino semantic widgets', (tester) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 25,
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
              kind: NodeKind.cupertinoButton,
              props: CupertinoButtonProps(enabled: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.press, handlerId: 61),
              ],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: TextProps('Cupertino action'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.cupertinoSwitch,
              props: CupertinoSwitchProps(value: true, enabled: true),
              eventBindings: [
                EventBinding(eventTag: EventTagId.valueChanged, handlerId: 62),
              ],
            ),
            SetChildren(nodeId: 1, children: [2, 4]),
            SetChildren(nodeId: 2, children: [3]),
            SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    expect(find.byType(cupertino.CupertinoButton), findsOneWidget);
    expect(find.byType(cupertino.CupertinoSwitch), findsOneWidget);
  });

  testWidgets('renders typed core visual and layout primitives', (
    tester,
  ) async {
    final operations = <FrameOperation>[
      const CreateNode(
        nodeId: 1,
        kind: NodeKind.listView,
        props: ListViewProps(axis: ScrollAxis.vertical, reverse: false),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 2,
        kind: NodeKind.richText,
        props: RichTextProps(['Rich', ' text']),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 3,
        kind: NodeKind.icon,
        props: IconProps(
          codePoint: 0x2605,
          fontFamily: null,
          size: 20,
          colorArgb: 0xff102030,
        ),
        eventBindings: [],
      ),
    ];
    final rootChildren = <int>[2, 3];
    var nextId = 4;
    void addUnary(NodeKind kind, UiProps props) {
      final wrapperId = nextId++;
      final textId = nextId++;
      operations
        ..add(
          CreateNode(
            nodeId: wrapperId,
            kind: kind,
            props: props,
            eventBindings: const [],
          ),
        )
        ..add(
          CreateNode(
            nodeId: textId,
            kind: NodeKind.text,
            props: TextProps(kind.name),
            eventBindings: const [],
          ),
        )
        ..add(SetChildren(nodeId: wrapperId, children: [textId]));
      rootChildren.add(wrapperId);
    }

    addUnary(NodeKind.align, const AlignProps(AlignmentValue.bottomEnd));
    addUnary(NodeKind.sizedBox, const SizedBoxProps(width: 100, height: 40));
    addUnary(
      NodeKind.constrainedBox,
      const ConstrainedBoxProps(
        minWidth: 10,
        maxWidth: 100,
        minHeight: 20,
        maxHeight: 200,
      ),
    );
    addUnary(
      NodeKind.decoratedBox,
      const DecoratedBoxProps(backgroundArgb: 0xff28323c, borderRadius: 8),
    );
    addUnary(NodeKind.clip, const ClipProps(ClipBehaviorValue.antiAlias));
    addUnary(NodeKind.opacity, const OpacityProps(0.5));
    addUnary(
      NodeKind.transform,
      const TransformProps([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4, 5, 0, 1]),
    );
    addUnary(
      NodeKind.safeArea,
      const SafeAreaProps(
        left: true,
        top: true,
        right: true,
        bottom: true,
        minimum: EdgeInsetsValue(left: 0, top: 0, right: 0, bottom: 0),
      ),
    );
    addUnary(NodeKind.environmentBoundary, const EnvironmentBoundaryProps());
    operations
      ..add(SetChildren(nodeId: 1, children: rootChildren))
      ..add(const SetRoot(1));
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 26,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: operations,
        ),
      );

    await tester.pumpWidget(MaterialApp(home: BonsaiFlutterView(store: store)));

    expect(find.text('Rich text', findRichText: true), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Align), findsOneWidget);
    expect(find.byType(ConstrainedBox), findsWidgets);
    expect(find.byType(DecoratedBox), findsOneWidget);
    expect(find.byType(ClipRect), findsWidgets);
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsWidgets);
    expect(find.byType(SafeArea), findsOneWidget);
    expect(find.byType(MediaQuery), findsWidgets);
  });
}

Frame counterWidgetSnapshot() => const Frame(
  runtimeEpoch: 21,
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
    CreateNode(
      nodeId: 3,
      kind: NodeKind.button,
      props: ButtonProps(enabled: true),
      eventBindings: [
        EventBinding(eventTag: EventTagId.press, handlerId: 9001),
      ],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Increment'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2, 3]),
    SetChildren(nodeId: 3, children: [4]),
    SetRoot(1),
  ],
);
