import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_slidable/flutter_slidable.dart' as fs;
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

const _runtimeEpoch = 141;
const _nativeNodeId = 1;
const _contentNodeId = 2;
const _contentTextNodeId = 3;

void main() {
  test('decodes the complete version-3 props contract', () {
    final padding = const EdgeInsets.fromLTRB(1, 2, 3, 4);
    final props = SlidableNativeProps.decode(
      _encodeSlidableProps(
        enabled: true,
        closeOnScroll: false,
        direction: Axis.vertical,
        useTextDirection: false,
        groupTag: 'inbox-收件箱',
        start: _Pane(
          motion: SlidablePaneMotion.drawer,
          extentRatio: 0.4,
          openThreshold: 0.2,
          closeThreshold: 0.1,
          dismissible: const _Dismissible(
            dismissThreshold: 0.8,
            dismissalDurationMs: 240,
            resizeDurationMs: 180,
            closeOnCancel: true,
            motion: _DismissMotion.inversedDrawer,
          ),
          dragDismissible: false,
          actions: [
            const _Action(id: 1, background: Color(0xff507d58)),
            _Action(
              id: 2,
              enabled: false,
              flex: 3,
              foreground: const Color(0xfffafafa),
              background: const Color(0xff435f8a),
              autoClose: false,
              borderRadius: 12,
              padding: padding,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ],
        ),
        end: const _Pane(
          motion: SlidablePaneMotion.stretch,
          extentRatio: 0.6,
          actions: [_Action(id: 3, background: Color(0xff112233))],
        ),
      ),
    );

    expect(props.enabled, isTrue);
    expect(props.closeOnScroll, isFalse);
    expect(props.direction, Axis.vertical);
    expect(props.useTextDirection, isFalse);
    expect(props.groupTag, 'inbox-收件箱');
    expect(props.startPane!.motion, SlidablePaneMotion.drawer);
    expect(props.startPane!.extentRatio, 0.4);
    expect(props.startPane!.openThreshold, 0.2);
    expect(props.startPane!.closeThreshold, 0.1);
    expect(props.startPane!.dismissible!.dismissThreshold, 0.8);
    expect(props.startPane!.dismissible!.dismissalDuration, 240.ms);
    expect(props.startPane!.dismissible!.resizeDuration, 180.ms);
    expect(props.startPane!.dismissible!.closeOnCancel, isTrue);
    expect(props.startPane!.dragDismissible, isFalse);
    expect(props.startPane!.actions, hasLength(2));
    expect(props.startPane!.actions[1].id, 2);
    expect(props.startPane!.actions[1].enabled, isFalse);
    expect(props.startPane!.actions[1].flex, 3);
    expect(props.startPane!.actions[1].foreground, const Color(0xfffafafa));
    expect(props.startPane!.actions[1].autoClose, isFalse);
    expect(props.startPane!.actions[1].borderRadius, 12);
    expect(props.startPane!.actions[1].padding, padding);
    expect(
      props.startPane!.actions[1].alignment,
      AlignmentDirectional.centerEnd,
    );
    expect(props.endPane!.motion, SlidablePaneMotion.stretch);
    expect(props.endPane!.actions.single.id, 3);
    props.validateChildCount(4);
  });

  test('rejects malformed global, pane, action, and string data', () {
    final valid = _encodeSlidableProps(
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [_Action(id: 1, background: Color(0xff123456))],
      ),
    );

    expect(
      () => SlidableNativeProps.decode(Uint8List(15)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 0, valid[0] | 0x80)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 1, 2)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 2, 1)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 16, 9)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 17, 0x80)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_floatChanged(valid, 24, 0)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 64, 0)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_changed(valid, 76, 0x80)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_uint32Changed(valid, 64, 0)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_uint32Changed(valid, 80, 0)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_floatChanged(valid, 88, -1)),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(Uint8List.fromList([...valid, 0])),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(valid)..validateChildCount(2),
      returnsNormally,
    );
    expect(
      () => SlidableNativeProps.decode(valid)..validateChildCount(1),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(valid)..validateChildCount(3),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_encodeSlidableProps()),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(
        _encodeSlidableProps(
          start: const _Pane(motion: SlidablePaneMotion.behind, actions: []),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => SlidableNativeProps.decode(_floatChanged(valid, 24, double.nan)),
      throwsFormatException,
    );

    final duplicate = _encodeSlidableProps(
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [_Action(id: 7, background: Color(0xff123456))],
      ),
      end: const _Pane(
        motion: SlidablePaneMotion.scroll,
        actions: [_Action(id: 7, background: Color(0xff654321))],
      ),
    );
    expect(() => SlidableNativeProps.decode(duplicate), throwsFormatException);

    final malformedGroup = _encodeSlidableProps(
      groupTag: 'x',
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [_Action(id: 1, background: Color(0xff123456))],
      ),
    )..last = 0xff;
    expect(
      () => SlidableNativeProps.decode(malformedGroup),
      throwsFormatException,
    );
  });

  test('decodes and validates auto-close behavior props', () {
    expect(
      SlidableAutoCloseProps.decode(Uint8List.fromList([3, 0, 0, 0])),
      const SlidableAutoCloseProps(
        closeWhenOpened: true,
        closeWhenTapped: true,
      ),
    );
    expect(
      SlidableAutoCloseProps.decode(Uint8List.fromList([2, 0, 0, 0])),
      const SlidableAutoCloseProps(
        closeWhenOpened: false,
        closeWhenTapped: true,
      ),
    );
    expect(
      () => SlidableAutoCloseProps.decode(Uint8List(3)),
      throwsFormatException,
    );
    expect(
      () => SlidableAutoCloseProps.decode(Uint8List.fromList([4, 0, 0, 0])),
      throwsFormatException,
    );
    expect(
      () => SlidableAutoCloseProps.decode(Uint8List.fromList([3, 1, 0, 0])),
      throwsFormatException,
    );
  });

  for (final motion in SlidablePaneMotion.values) {
    testWidgets('renders ${motion.name} with multiple actions', (tester) async {
      final fixture = await _pumpSingle(
        tester,
        start: _Pane(
          motion: motion,
          extentRatio: 0.65,
          actions: const [
            _Action(id: 11, background: Color(0xff507d58)),
            _Action(
              id: 12,
              flex: 2,
              foreground: Color(0xfffafafa),
              background: Color(0xff435f8a),
              borderRadius: 12,
              padding: EdgeInsets.all(3),
              alignment: AlignmentDirectional.centerEnd,
            ),
          ],
        ),
        actionLabels: const ['Archive', 'Share'],
      );

      await tester.drag(find.text('Message'), const Offset(220, 0));
      await tester.pumpAndSettle();

      expect(find.byType(_motionType(motion)), findsOneWidget);
      final actions = tester.widgetList<fs.CustomSlidableAction>(
        find.byType(fs.CustomSlidableAction),
      );
      expect(actions, hasLength(2));
      expect(actions.last.flex, 2);
      expect(actions.last.foregroundColor, const Color(0xfffafafa));
      expect(actions.last.borderRadius, BorderRadius.circular(12));
      expect(actions.last.padding, const EdgeInsets.all(3));
      expect(actions.last.alignment, Alignment.centerRight);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(_actionIds(fixture.events), [12]);
      expect(_controller(tester, 'Message').ratio, 0);
    });
  }

  testWidgets('disabled hosts and actions do not activate', (tester) async {
    final disabledHost = await _pumpSingle(
      tester,
      enabled: false,
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [_Action(id: 1, background: Color(0xff507d58))],
      ),
      actionLabels: const ['Archive'],
    );
    await tester.drag(find.text('Message'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(_controller(tester, 'Message').ratio, 0);
    expect(disabledHost.events, isEmpty);

    final disabledAction = await _pumpSingle(
      tester,
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [
          _Action(id: 2, enabled: false, background: Color(0xff507d58)),
        ],
      ),
      actionLabels: const ['Archive'],
    );
    await tester.drag(find.text('Message'), const Offset(220, 0));
    await tester.pumpAndSettle();
    final action = tester.widget<fs.CustomSlidableAction>(
      find.byType(fs.CustomSlidableAction),
    );
    expect(action.onPressed, isNull);
    await tester.tap(find.text('Archive'));
    expect(disabledAction.events, isEmpty);
  });

  testWidgets('autoClose controls pane closure after an action event', (
    tester,
  ) async {
    final staysOpen = await _pumpSingle(
      tester,
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [
          _Action(id: 4, autoClose: false, background: Color(0xff507d58)),
        ],
      ),
      actionLabels: const ['Keep open'],
    );
    await tester.drag(find.text('Message'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep open'));
    await tester.pumpAndSettle();
    expect(_actionIds(staysOpen.events), [4]);
    expect(_controller(tester, 'Message').ratio, greaterThan(0));

    final closes = await _pumpSingle(
      tester,
      start: const _Pane(
        motion: SlidablePaneMotion.behind,
        actions: [_Action(id: 5, background: Color(0xff507d58))],
      ),
      actionLabels: const ['Close'],
    );
    await tester.drag(find.text('Message'), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(_actionIds(closes.events), [5]);
    expect(_controller(tester, 'Message').ratio, 0);
  });

  testWidgets(
    'dismiss emits its logical side once and permits immediate removal',
    (tester) async {
      final fixture = await _pumpSingle(
        tester,
        start: const _Pane(
          motion: SlidablePaneMotion.drawer,
          extentRatio: 0.3,
          dismissible: _Dismissible(
            dismissThreshold: 0.45,
            dismissalDurationMs: 10,
            resizeDurationMs: 10,
          ),
          actions: [_Action(id: 1, background: Color(0xff507d58))],
        ),
        actionLabels: const ['Archive'],
        removeOnDismiss: true,
      );

      unawaited(_controller(tester, 'Message').openStartActionPane());
      await tester.pumpAndSettle();
      final dismissible =
          tester.widget<fs.ActionPane>(find.byType(fs.ActionPane)).dismissible!
              as fs.DismissiblePane;
      dismissible.onDismissed();
      await tester.pump();

      expect(_dismissedSides(fixture.events), [SlidableSide.start]);
      expect(find.text('Message'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dropping during dismissal suppresses a late callback', (
    tester,
  ) async {
    final fixture = await _pumpSingle(
      tester,
      start: const _Pane(
        motion: SlidablePaneMotion.drawer,
        extentRatio: 0.3,
        dismissible: _Dismissible(
          dismissThreshold: 0.45,
          dismissalDurationMs: 300,
          resizeDurationMs: 300,
        ),
        actions: [_Action(id: 1, background: Color(0xff507d58))],
      ),
      actionLabels: const ['Archive'],
    );
    unawaited(_controller(tester, 'Message').openStartActionPane());
    await tester.pumpAndSettle();
    final onDismissed =
        (tester.widget<fs.ActionPane>(find.byType(fs.ActionPane)).dismissible!
                as fs.DismissiblePane)
            .onDismissed;
    fixture.replaceWithEmpty();
    await tester.pump();
    onDismissed();
    await tester.pump();

    expect(_dismissedSides(fixture.events), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logical sides follow LTR, RTL, and vertical direction', (
    tester,
  ) async {
    await _pumpSingle(
      tester,
      start: _startPane,
      end: _endPane,
      actionLabels: const ['Start', 'End'],
    );
    expect(tester.takeException(), isNull);
    final ltrController = _controller(tester, 'Message');
    unawaited(ltrController.openStartActionPane());
    await tester.pumpAndSettle();
    expect(find.byType(fs.CustomSlidableAction), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsNothing);
    unawaited(ltrController.openEndActionPane());
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsNothing);
    expect(find.text('End'), findsOneWidget);
    unawaited(ltrController.close());
    await tester.pumpAndSettle();
    await tester.drag(find.text('Message'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(
      _controller(tester, 'Message').actionPaneType.value,
      fs.ActionPaneType.start,
    );

    await _pumpSingle(
      tester,
      textDirection: TextDirection.rtl,
      start: _startPane,
      end: _endPane,
      actionLabels: const ['Start', 'End'],
    );
    await tester.drag(find.text('Message'), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(
      _controller(tester, 'Message').actionPaneType.value,
      fs.ActionPaneType.start,
    );

    await _pumpSingle(
      tester,
      direction: Axis.vertical,
      start: _startPane,
      end: _endPane,
      actionLabels: const ['Start', 'End'],
    );
    await tester.drag(find.text('Message'), const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(
      _controller(tester, 'Message').actionPaneType.value,
      fs.ActionPaneType.start,
    );
  });

  testWidgets('closeOnScroll closes an open pane after stock arbitration', (
    tester,
  ) async {
    await _pumpSingle(
      tester,
      inScrollableList: true,
      closeOnScroll: true,
      start: _startPane,
      actionLabels: const ['Archive'],
    );
    final controller = _controller(tester, 'Message');
    unawaited(controller.openStartActionPane());
    await tester.pumpAndSettle();
    expect(controller.ratio, greaterThan(0));

    await tester.drag(find.text('Spacer'), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(controller.ratio, 0);
  });

  testWidgets('ordinary prop patches preserve package-owned open state', (
    tester,
  ) async {
    final fixture = await _pumpSingle(
      tester,
      groupTag: 'inbox',
      start: _startPane,
      actionLabels: const ['Archive'],
    );
    final slidableElement = tester.element(find.byType(fs.Slidable));
    unawaited(_controller(tester, 'Message').openStartActionPane());
    await tester.pumpAndSettle();
    final ratio = _controller(tester, 'Message').ratio;

    fixture.updateProps(
      _encodeSlidableProps(groupTag: 'updated', start: _startPane),
    );
    await tester.pump();

    expect(
      identical(tester.element(find.byType(fs.Slidable)), slidableElement),
      isTrue,
    );
    expect(_controller(tester, 'Message').ratio, ratio);
  });

  testWidgets('auto-close behavior closes the previously open group member', (
    tester,
  ) async {
    await _pumpAutoCloseGroup(tester);
    unawaited(_controller(tester, 'First').openStartActionPane());
    await tester.pumpAndSettle();
    expect(_controller(tester, 'First').ratio, greaterThan(0));

    unawaited(_controller(tester, 'Second').openStartActionPane());
    await tester.pumpAndSettle();
    expect(_controller(tester, 'First').ratio, 0);
    expect(_controller(tester, 'Second').ratio, greaterThan(0));
  });

  testWidgets('actions expose semantics and reduced motion settles locally', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpSingle(
      tester,
      disableAnimations: true,
      start: _startPane,
      actionLabels: const ['Archive'],
    );
    unawaited(_controller(tester, 'Message').openStartActionPane());
    await tester.pump();
    expect(_controller(tester, 'Message').ratio, greaterThan(0));
    final actionSemantics = tester.getSemantics(find.text('Archive'));
    expect(
      actionSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('version 2 is rejected with no compatibility decoder', (
    tester,
  ) async {
    await _pumpSingle(
      tester,
      version: 2,
      start: _startPane,
      actionLabels: const ['Archive'],
    );
    expect(
      find.text('Unsupported version 2 for native widget kind 2'),
      findsOneWidget,
    );
  });
}

const _startPane = _Pane(
  motion: SlidablePaneMotion.behind,
  actions: [_Action(id: 1, background: Color(0xff507d58))],
);

const _endPane = _Pane(
  motion: SlidablePaneMotion.behind,
  actions: [_Action(id: 2, background: Color(0xff507d58))],
);

Type _motionType(SlidablePaneMotion motion) => switch (motion) {
  SlidablePaneMotion.behind => fs.BehindMotion,
  SlidablePaneMotion.drawer => fs.DrawerMotion,
  SlidablePaneMotion.scroll => fs.ScrollMotion,
  SlidablePaneMotion.stretch => fs.StretchMotion,
};

fs.SlidableController _controller(WidgetTester tester, String label) =>
    fs.Slidable.of(tester.element(find.text(label)))!;

List<int> _actionIds(List<RendererEvent> events) => [
  for (final event in events)
    if (event.payload case final NativeEventPayload payload
        when payload.kindId == 2 &&
            payload.version == 3 &&
            payload.eventId == 1)
      ByteData.sublistView(
        Uint8List.fromList(payload.payload),
      ).getUint32(0, Endian.little),
];

List<SlidableSide> _dismissedSides(List<RendererEvent> events) => [
  for (final event in events)
    if (event.payload case final NativeEventPayload payload
        when payload.kindId == 2 &&
            payload.version == 3 &&
            payload.eventId == 2)
      switch (payload.payload.single) {
        0 => SlidableSide.start,
        1 => SlidableSide.end,
        _ => throw StateError('invalid side'),
      },
];

final class _Fixture {
  _Fixture({required this.store, required this.events, required this.props});

  final NodeStore store;
  final List<RendererEvent> events;
  NativeWidgetProps props;

  void updateProps(Uint8List payload) {
    props = NativeWidgetProps(
      kindId: 2,
      version: 3,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics,
      payload: payload,
    );
    store.apply(
      Frame(
        runtimeEpoch: _runtimeEpoch,
        baseRevision: store.revision,
        targetRevision: store.revision + 1,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: _nativeNodeId, props: props)],
      ),
    );
  }

  void replaceWithEmpty() {
    store.apply(
      Frame(
        runtimeEpoch: _runtimeEpoch,
        baseRevision: 0,
        targetRevision: store.revision + 1,
        kind: FrameKind.fullSnapshot,
        operations: const [
          SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
          CreateNode(
            nodeId: 100,
            kind: NodeKind.empty,
            props: EmptyProps(),
            eventBindings: [],
          ),
          SetRoot(100),
        ],
      ),
    );
  }
}

Future<_Fixture> _pumpSingle(
  WidgetTester tester, {
  int version = 3,
  bool enabled = true,
  bool closeOnScroll = true,
  Axis direction = Axis.horizontal,
  bool useTextDirection = true,
  String? groupTag,
  _Pane? start,
  _Pane? end,
  required List<String> actionLabels,
  bool inScrollableList = false,
  bool disableAnimations = false,
  bool removeOnDismiss = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final payload = _encodeSlidableProps(
    enabled: enabled,
    closeOnScroll: closeOnScroll,
    direction: direction,
    useTextDirection: useTextDirection,
    groupTag: groupTag,
    start: start,
    end: end,
  );
  final nativeProps = NativeWidgetProps(
    kindId: 2,
    version: version,
    capabilityBits:
        NativeCapability.stateful |
        NativeCapability.resource |
        NativeCapability.semantics,
    payload: payload,
  );
  final store = NodeStore()
    ..apply(_singleFrame(nativeProps, actionLabels, inScrollableList));
  final events = <RendererEvent>[];
  late final _Fixture fixture;
  fixture = _Fixture(store: store, events: events, props: nativeProps);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 640),
            disableAnimations: disableAnimations,
            accessibleNavigation: disableAnimations,
          ),
          child: BonsaiFlutterView(
            key: ValueKey<NodeStore>(store),
            store: store,
            registry: WidgetRegistry.standard(),
            onEvent: (event) {
              events.add(event);
              final eventPayload = event.payload;
              if (removeOnDismiss &&
                  eventPayload is NativeEventPayload &&
                  eventPayload.kindId == 2 &&
                  eventPayload.eventId == 2) {
                fixture.replaceWithEmpty();
              }
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return fixture;
}

Frame _singleFrame(
  NativeWidgetProps props,
  List<String> actionLabels,
  bool inScrollableList,
) {
  final actionNodeIds = [for (var i = 0; i < actionLabels.length; i++) 10 + i];
  final operations = <FrameOperation>[
    const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: _nativeNodeId,
      kind: NodeKind.nativeWidget,
      props: props,
      eventBindings: const [
        EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 900),
      ],
    ),
    const CreateNode(
      nodeId: _contentNodeId,
      kind: NodeKind.sizedBox,
      props: SizedBoxProps(width: 320, height: 88),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: _contentTextNodeId,
      kind: NodeKind.text,
      props: TextProps('Message'),
      eventBindings: [],
    ),
    for (var i = 0; i < actionLabels.length; i++)
      CreateNode(
        nodeId: actionNodeIds[i],
        kind: NodeKind.text,
        props: TextProps(actionLabels[i]),
        eventBindings: const [],
      ),
    const SetChildren(nodeId: _contentNodeId, children: [_contentTextNodeId]),
    SetChildren(
      nodeId: _nativeNodeId,
      children: [_contentNodeId, ...actionNodeIds],
    ),
  ];
  if (inScrollableList) {
    operations.addAll(const [
      CreateNode(
        nodeId: 50,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: 320, height: 1000),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 51,
        kind: NodeKind.text,
        props: TextProps('Spacer'),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 60,
        kind: NodeKind.scrollView,
        props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 61,
        kind: NodeKind.sliverList,
        props: EmptyProps(),
        eventBindings: [],
      ),
      SetChildren(nodeId: 50, children: [51]),
      SetChildren(nodeId: 61, children: [_nativeNodeId, 50]),
      SetChildren(nodeId: 60, children: [61]),
      SetRoot(60),
    ]);
  } else {
    operations.add(const SetRoot(_nativeNodeId));
  }
  return Frame(
    runtimeEpoch: _runtimeEpoch,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: operations,
  );
}

Future<void> _pumpAutoCloseGroup(WidgetTester tester) async {
  final pane = _startPane;
  final props = NativeWidgetProps(
    kindId: 2,
    version: 3,
    capabilityBits:
        NativeCapability.stateful |
        NativeCapability.resource |
        NativeCapability.semantics,
    payload: _encodeSlidableProps(groupTag: 'mail', start: pane),
  );
  final autoCloseProps = NativeWidgetProps(
    kindId: 8,
    version: 1,
    capabilityBits: NativeCapability.stateful,
    payload: Uint8List.fromList([3, 0, 0, 0]),
  );
  final store = NodeStore()
    ..apply(
      Frame(
        runtimeEpoch: _runtimeEpoch,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
          CreateNode(
            nodeId: 1,
            kind: NodeKind.nativeWidget,
            props: autoCloseProps,
            eventBindings: const [],
          ),
          const CreateNode(
            nodeId: 2,
            kind: NodeKind.column,
            props: LinearProps(),
            eventBindings: [],
          ),
          for (final id in [3, 6])
            CreateNode(
              nodeId: id,
              kind: NodeKind.nativeWidget,
              props: props,
              eventBindings: const [
                EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 900),
              ],
            ),
          const CreateNode(
            nodeId: 4,
            kind: NodeKind.sizedBox,
            props: SizedBoxProps(width: 320, height: 88),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 5,
            kind: NodeKind.text,
            props: TextProps('First'),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 7,
            kind: NodeKind.sizedBox,
            props: SizedBoxProps(width: 320, height: 88),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 8,
            kind: NodeKind.text,
            props: TextProps('Second'),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 9,
            kind: NodeKind.text,
            props: TextProps('Archive first'),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 10,
            kind: NodeKind.text,
            props: TextProps('Archive second'),
            eventBindings: [],
          ),
          const SetChildren(nodeId: 4, children: [5]),
          const SetChildren(nodeId: 7, children: [8]),
          const SetChildren(nodeId: 3, children: [4, 9]),
          const SetChildren(nodeId: 6, children: [7, 10]),
          const SetChildren(nodeId: 2, children: [3, 6]),
          const SetChildren(nodeId: 1, children: [2]),
          const SetRoot(1),
        ],
      ),
    );
  await tester.pumpWidget(
    MaterialApp(
      home: BonsaiFlutterView(
        store: store,
        registry: WidgetRegistry.standard(),
      ),
    ),
  );
  await tester.pump();
}

enum _DismissMotion { inversedDrawer }

final class _Dismissible {
  const _Dismissible({
    this.dismissThreshold = 0.75,
    this.dismissalDurationMs = 300,
    this.resizeDurationMs = 300,
    this.closeOnCancel = false,
    this.motion = _DismissMotion.inversedDrawer,
  });

  final double dismissThreshold;
  final int dismissalDurationMs;
  final int resizeDurationMs;
  final bool closeOnCancel;
  final _DismissMotion motion;
}

final class _Pane {
  const _Pane({
    required this.motion,
    this.extentRatio = 0.5,
    this.openThreshold,
    this.closeThreshold,
    this.dismissible,
    this.dragDismissible = true,
    required this.actions,
  });

  final SlidablePaneMotion motion;
  final double extentRatio;
  final double? openThreshold;
  final double? closeThreshold;
  final _Dismissible? dismissible;
  final bool dragDismissible;
  final List<_Action> actions;
}

final class _Action {
  const _Action({
    required this.id,
    this.enabled = true,
    this.flex = 1,
    this.foreground,
    required this.background,
    this.autoClose = true,
    this.borderRadius = 0,
    this.padding,
    this.alignment,
  });

  final int id;
  final bool enabled;
  final int flex;
  final Color? foreground;
  final Color background;
  final bool autoClose;
  final double borderRadius;
  final EdgeInsets? padding;
  final AlignmentDirectional? alignment;
}

Uint8List _encodeSlidableProps({
  bool enabled = true,
  bool closeOnScroll = true,
  Axis direction = Axis.horizontal,
  bool useTextDirection = true,
  String? groupTag,
  _Pane? start,
  _Pane? end,
}) {
  final groupBytes = groupTag == null ? const <int>[] : utf8.encode(groupTag);
  final actionCount = (start?.actions.length ?? 0) + (end?.actions.length ?? 0);
  final paneCount = (start == null ? 0 : 1) + (end == null ? 0 : 1);
  final payload = Uint8List(
    16 + paneCount * 48 + actionCount * 64 + groupBytes.length,
  );
  final data = ByteData.sublistView(payload);
  data
    ..setUint8(
      0,
      (enabled ? 1 : 0) |
          (closeOnScroll ? 2 : 0) |
          (useTextDirection ? 4 : 0) |
          (start == null ? 0 : 8) |
          (end == null ? 0 : 16),
    )
    ..setUint8(1, direction == Axis.horizontal ? 0 : 1)
    ..setUint16(4, start?.actions.length ?? 0, Endian.little)
    ..setUint16(6, end?.actions.length ?? 0, Endian.little)
    ..setUint32(8, groupBytes.length, Endian.little);
  var offset = 16;
  for (final pane in [start, end]) {
    if (pane == null) continue;
    _writePane(data, offset, pane);
    offset += 48;
  }
  for (final pane in [start, end]) {
    if (pane == null) continue;
    for (final action in pane.actions) {
      _writeAction(data, offset, action);
      offset += 64;
    }
  }
  payload.setRange(offset, payload.length, groupBytes);
  return payload;
}

void _writePane(ByteData data, int offset, _Pane pane) {
  final dismissible = pane.dismissible;
  data
    ..setUint8(offset, pane.motion.index)
    ..setUint8(
      offset + 1,
      (pane.dragDismissible ? 1 : 0) |
          (dismissible == null ? 0 : 2) |
          (pane.openThreshold == null ? 0 : 4) |
          (pane.closeThreshold == null ? 0 : 8) |
          (dismissible?.closeOnCancel ?? false ? 16 : 0),
    )
    ..setUint8(offset + 2, dismissible?.motion.index ?? 0)
    ..setFloat64(offset + 8, pane.extentRatio, Endian.little)
    ..setFloat64(offset + 16, pane.openThreshold ?? 0, Endian.little)
    ..setFloat64(offset + 24, pane.closeThreshold ?? 0, Endian.little)
    ..setFloat64(offset + 32, dismissible?.dismissThreshold ?? 0, Endian.little)
    ..setUint32(
      offset + 40,
      dismissible?.dismissalDurationMs ?? 0,
      Endian.little,
    )
    ..setUint32(offset + 44, dismissible?.resizeDurationMs ?? 0, Endian.little);
}

void _writeAction(ByteData data, int offset, _Action action) {
  data
    ..setUint32(offset, action.id, Endian.little)
    ..setUint32(offset + 4, action.background.toARGB32(), Endian.little)
    ..setUint32(offset + 8, action.foreground?.toARGB32() ?? 0, Endian.little)
    ..setUint8(
      offset + 12,
      (action.enabled ? 1 : 0) |
          (action.autoClose ? 2 : 0) |
          (action.foreground == null ? 0 : 4) |
          (action.padding == null ? 0 : 8) |
          (action.alignment == null ? 0 : 16),
    )
    ..setUint8(offset + 13, _alignmentIndex(action.alignment))
    ..setUint32(offset + 16, action.flex, Endian.little)
    ..setFloat64(offset + 24, action.borderRadius, Endian.little)
    ..setFloat64(offset + 32, action.padding?.left ?? 0, Endian.little)
    ..setFloat64(offset + 40, action.padding?.top ?? 0, Endian.little)
    ..setFloat64(offset + 48, action.padding?.right ?? 0, Endian.little)
    ..setFloat64(offset + 56, action.padding?.bottom ?? 0, Endian.little);
}

int _alignmentIndex(AlignmentDirectional? alignment) => switch (alignment) {
  null => 0,
  AlignmentDirectional.topStart => 0,
  AlignmentDirectional.topCenter => 1,
  AlignmentDirectional.topEnd => 2,
  AlignmentDirectional.centerStart => 3,
  AlignmentDirectional.center => 4,
  AlignmentDirectional.centerEnd => 5,
  AlignmentDirectional.bottomStart => 6,
  AlignmentDirectional.bottomCenter => 7,
  AlignmentDirectional.bottomEnd => 8,
  _ => throw ArgumentError.value(alignment, 'alignment'),
};

Uint8List _changed(Uint8List source, int offset, int value) =>
    Uint8List.fromList(source)..[offset] = value;

Uint8List _uint32Changed(Uint8List source, int offset, int value) {
  final result = Uint8List.fromList(source);
  ByteData.sublistView(result).setUint32(offset, value, Endian.little);
  return result;
}

Uint8List _floatChanged(Uint8List source, int offset, double value) {
  final result = Uint8List.fromList(source);
  ByteData.sublistView(result).setFloat64(offset, value, Endian.little);
  return result;
}

extension on int {
  Duration get ms => Duration(milliseconds: this);
}
