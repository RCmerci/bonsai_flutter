import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostKey = ValueKey<String>('bonsai-swipe-action-host');
const _contentKey = ValueKey<String>('bonsai-swipe-action-content');
const _pillKey = ValueKey<String>('bonsai-swipe-action-pill');

void main() {
  testWidgets('content tracks both horizontal directions and reversals', (
    tester,
  ) async {
    await _pumpSwipeFixture(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(64, 0));
    await tester.pump();
    expect(_contentOffset(tester), closeTo(64, 1));

    await gesture.moveBy(const Offset(-112, 0));
    await tester.pump();
    expect(_contentOffset(tester), closeTo(-48, 1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_contentOffset(tester), closeTo(0, 1));
  });

  testWidgets('feedback grows from the active edge and stays clipped', (
    tester,
  ) async {
    await _pumpSwipeFixture(tester);
    final host = tester.getRect(find.byKey(_hostKey));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final small = tester.getRect(find.byKey(_pillKey));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final large = tester.getRect(find.byKey(_pillKey));

    expect(small.left, closeTo(host.left, 1));
    expect(large.left, closeTo(host.left, 1));
    expect(large.width, greaterThan(small.width));
    expect(large.width, lessThanOrEqualTo(144));
    expect(large.top, greaterThanOrEqualTo(host.top + 4));
    expect(large.bottom, lessThanOrEqualTo(host.bottom - 4));

    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    final reversed = tester.getRect(find.byKey(_pillKey));
    expect(reversed.right, closeTo(host.right, 1));
    expect(reversed.left, greaterThanOrEqualTo(host.left));
    await gesture.up();
  });

  testWidgets('action and host border radii are independently configurable', (
    tester,
  ) async {
    await _pumpSwipeFixture(
      tester,
      startBorderRadius: 12,
      endBorderRadius: 24,
      clipBorderRadius: 18,
    );
    final hostClip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byKey(_hostKey),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(hostClip.borderRadius, BorderRadius.circular(18));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(_feedbackBorderRadius(tester), BorderRadius.circular(12));

    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    expect(_feedbackBorderRadius(tester), BorderRadius.circular(24));
    await gesture.up();
  });

  testWidgets('sub-threshold release closes without a native event', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(tester);

    await tester.drag(find.text('Message'), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(_contentOffset(tester), closeTo(0, 1));
    expect(fixture.events, isEmpty);
  });

  testWidgets('distance commits dismiss and rebound after local settle', (
    tester,
  ) async {
    final dismiss = await _pumpSwipeFixture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 219));
    expect(dismiss.events, isEmpty);
    await tester.pumpAndSettle();
    expect(_nativeDirections(dismiss.events), [0]);

    final rebound = await _pumpSwipeFixture(tester);
    final endGesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await endGesture.moveBy(const Offset(-120, 0));
    await endGesture.up();
    await tester.pump(const Duration(milliseconds: 189));
    expect(rebound.events, isEmpty);
    await tester.pumpAndSettle();
    expect(_nativeDirections(rebound.events), [1]);
    expect(_contentOffset(tester), closeTo(0, 1));
  });

  testWidgets('intentional short fling commits in either direction', (
    tester,
  ) async {
    final start = await _pumpSwipeFixture(tester);
    await tester.fling(find.text('Message'), const Offset(56, 0), 1000);
    await tester.pumpAndSettle();
    expect(_nativeDirections(start.events), [0]);

    final end = await _pumpSwipeFixture(tester);
    await tester.fling(find.text('Message'), const Offset(-56, 0), 1000);
    await tester.pumpAndSettle();
    expect(_nativeDirections(end.events), [1]);
  });

  testWidgets('threshold haptic fires at most once per gesture', (
    tester,
  ) async {
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics += 1;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpSwipeFixture(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(haptics, 1);
    await gesture.up();
  });

  testWidgets('vertical scrolling wins over ambiguous row drag', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(tester, inScrollableList: true);

    await tester.drag(find.text('Message'), const Offset(5, -40));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(_contentOffset(tester), closeTo(0, 1));
    expect(fixture.events, isEmpty);
  });

  testWidgets('horizontal win cancels row and nested star taps', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Star')),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_nativeDirections(fixture.events), [0]);
    expect(
      fixture.events.where((event) => event.eventTag == EventTagId.tap),
      isEmpty,
    );

    final tapFixture = await _pumpSwipeFixture(tester);
    await tester.tap(find.text('Star'));
    expect(
      tapFixture.events.where((event) => event.eventTag == EventTagId.tap),
      hasLength(1),
    );
  });

  testWidgets('disabled direction stays closed and exposes no action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = await _pumpSwipeFixture(tester, endEnabled: false);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    expect(_contentOffset(tester), closeTo(0, 1));
    expect(find.byKey(_pillKey), findsNothing);
    await gesture.up();
    expect(fixture.events, isEmpty);
    expect(_customActionLabels(tester), contains('Archive'));
    expect(_customActionLabels(tester), isNot(contains('Mark read')));
    semantics.dispose();
  });

  testWidgets('custom semantics actions use the same commit state machine', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = await _pumpSwipeFixture(tester);
    final node = tester.getSemantics(find.byKey(_hostKey));
    final actions = {
      for (final id
          in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label!: id,
    };

    expect(actions.keys, containsAll(<String>['Archive', 'Mark read']));
    expect(_semanticsLabels(node), isNot(contains('Archive icon')));
    expect(_semanticsLabels(node), isNot(contains('Read icon')));

    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      actions['Mark read'],
    );
    await tester.pumpAndSettle();
    expect(_nativeDirections(fixture.events), [1]);
    semantics.dispose();
  });

  testWidgets('rebuild during settle retains state and emits once', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(tester);
    final hostElement = tester.element(find.byKey(_hostKey));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    fixture.updateLabels(endLabel: 'Mark unread');
    await tester.pump();
    expect(
      identical(tester.element(find.byKey(_hostKey)), hostElement),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(_nativeDirections(fixture.events), [0]);
  });

  testWidgets('dropping during settle prevents a late commit', (tester) async {
    final fixture = await _pumpSwipeFixture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(fixture.events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL maps physical leading swipe to start-to-end', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(
      tester,
      textDirection: TextDirection.rtl,
    );

    await tester.drag(find.text('Message'), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(_nativeDirections(fixture.events), [0]);
  });

  testWidgets('reduced motion keeps tracking direct and settles immediately', (
    tester,
  ) async {
    final fixture = await _pumpSwipeFixture(tester, disableAnimations: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(_contentOffset(tester), closeTo(-120, 1));

    await gesture.up();
    await tester.pump();
    expect(_nativeDirections(fixture.events), [1]);
    expect(_contentOffset(tester), closeTo(0, 1));
  });
}

double _contentOffset(WidgetTester tester) {
  final host = tester.getTopLeft(find.byKey(_hostKey));
  final content = tester.getTopLeft(find.byKey(_contentKey));
  return content.dx - host.dx;
}

List<int> _nativeDirections(List<RendererEvent> events) => [
  for (final event in events)
    if (event.eventTag == EventTagId.nativeEvent)
      ...(event.payload as NativeEventPayload).payload,
];

Set<String> _customActionLabels(WidgetTester tester) {
  final node = tester.getSemantics(find.byKey(_hostKey));
  return {
    for (final id
        in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
      if (CustomSemanticsAction.getAction(id)?.label case final String label)
        label,
  };
}

BorderRadiusGeometry? _feedbackBorderRadius(WidgetTester tester) {
  final decoration =
      tester
              .widget<DecoratedBox>(
                find.descendant(
                  of: find.byKey(_pillKey),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .decoration
          as BoxDecoration;
  return decoration.borderRadius;
}

Set<String> _semanticsLabels(SemanticsNode root) {
  final labels = <String>{};
  bool visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren(visit);
    return true;
  }

  visit(root);
  return labels;
}

final class _SwipeFixture {
  _SwipeFixture({required this.store, required this.events});

  final NodeStore store;
  final List<RendererEvent> events;

  void updateLabels({required String endLabel}) {
    store.apply(
      Frame(
        runtimeEpoch: 91,
        baseRevision: store.revision,
        targetRevision: store.revision + 1,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 1, props: _nativeProps(endLabel: endLabel)),
        ],
      ),
    );
  }
}

Future<_SwipeFixture> _pumpSwipeFixture(
  WidgetTester tester, {
  bool startEnabled = true,
  bool endEnabled = true,
  bool inScrollableList = false,
  bool disableAnimations = false,
  TextDirection textDirection = TextDirection.ltr,
  double startBorderRadius = 999,
  double endBorderRadius = 999,
  double clipBorderRadius = 0,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = NodeStore()
    ..apply(
      _swipeFrame(
        startEnabled: startEnabled,
        endEnabled: endEnabled,
        inScrollableList: inScrollableList,
        startBorderRadius: startBorderRadius,
        endBorderRadius: endBorderRadius,
        clipBorderRadius: clipBorderRadius,
      ),
    );
  final events = <RendererEvent>[];
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
            onEvent: events.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _SwipeFixture(store: store, events: events);
}

NativeWidgetProps _nativeProps({
  bool startEnabled = true,
  bool endEnabled = true,
  String startLabel = 'Archive',
  String endLabel = 'Mark read',
  double startBorderRadius = 999,
  double endBorderRadius = 999,
  double clipBorderRadius = 0,
}) {
  final start = utf8.encode(startLabel);
  final end = utf8.encode(endLabel);
  final data = ByteData(44 + start.length + end.length)
    ..setUint8(0, (startEnabled ? 1 : 0) | (endEnabled ? 2 : 0))
    ..setUint8(1, 0)
    ..setUint8(2, 1)
    ..setUint32(4, 0xff507d58, Endian.little)
    ..setUint32(8, 0xff435f8a, Endian.little)
    ..setFloat64(12, startBorderRadius, Endian.little)
    ..setFloat64(20, endBorderRadius, Endian.little)
    ..setFloat64(28, clipBorderRadius, Endian.little)
    ..setUint32(36, start.length, Endian.little)
    ..setUint32(40, end.length, Endian.little);
  final payload = data.buffer.asUint8List();
  payload.setRange(44, 44 + start.length, start);
  payload.setRange(44 + start.length, payload.length, end);
  return NativeWidgetProps(
    kindId: 2,
    version: 2,
    capabilityBits:
        NativeCapability.stateful |
        NativeCapability.resource |
        NativeCapability.semantics,
    payload: payload,
  );
}

Frame _swipeFrame({
  required bool startEnabled,
  required bool endEnabled,
  required bool inScrollableList,
  double startBorderRadius = 999,
  double endBorderRadius = 999,
  double clipBorderRadius = 0,
}) {
  final operations = <FrameOperation>[
    CreateNode(
      nodeId: 1,
      kind: NodeKind.nativeWidget,
      props: _nativeProps(
        startEnabled: startEnabled,
        endEnabled: endEnabled,
        endLabel: endEnabled ? 'Mark read' : '',
        startBorderRadius: startBorderRadius,
        endBorderRadius: endBorderRadius,
        clipBorderRadius: clipBorderRadius,
      ),
      eventBindings: const [
        EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 900),
      ],
    ),
    const CreateNode(
      nodeId: 2,
      kind: NodeKind.gesture,
      props: GestureProps(),
      eventBindings: [EventBinding(eventTag: EventTagId.tap, handlerId: 901)],
    ),
    const CreateNode(
      nodeId: 3,
      kind: NodeKind.text,
      props: TextProps('Archive icon'),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Read icon'),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 5,
      kind: NodeKind.sizedBox,
      props: SizedBoxProps(width: 320, height: 88),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 6,
      kind: NodeKind.row,
      props: LinearProps(),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 7,
      kind: NodeKind.sizedBox,
      props: SizedBoxProps(width: 200, height: 88),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 8,
      kind: NodeKind.text,
      props: TextProps('Message'),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 9,
      kind: NodeKind.sizedBox,
      props: SizedBoxProps(width: 120, height: 88),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 10,
      kind: NodeKind.gesture,
      props: GestureProps(),
      eventBindings: [EventBinding(eventTag: EventTagId.tap, handlerId: 902)],
    ),
    const CreateNode(
      nodeId: 11,
      kind: NodeKind.text,
      props: TextProps('Star'),
      eventBindings: [],
    ),
    const SetChildren(nodeId: 1, children: [2, 3, 4]),
    const SetChildren(nodeId: 2, children: [5]),
    const SetChildren(nodeId: 5, children: [6]),
    const SetChildren(nodeId: 6, children: [7, 9]),
    const SetChildren(nodeId: 7, children: [8]),
    const SetChildren(nodeId: 9, children: [10]),
    const SetChildren(nodeId: 10, children: [11]),
  ];
  if (inScrollableList) {
    operations.addAll(const [
      CreateNode(
        nodeId: 12,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: 320, height: 1000),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 13,
        kind: NodeKind.empty,
        props: EmptyProps(),
        eventBindings: [],
      ),
      CreateNode(
        nodeId: 20,
        kind: NodeKind.listView,
        props: ListViewProps(axis: ScrollAxis.vertical, reverse: false),
        eventBindings: [],
      ),
      SetChildren(nodeId: 12, children: [13]),
      SetChildren(nodeId: 20, children: [1, 12]),
      SetRoot(20),
    ]);
  } else {
    operations.add(const SetRoot(1));
  }
  return Frame(
    runtimeEpoch: 91,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: operations,
  );
}
