import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _overlayColor = Color(0x181c2026);

void main() {
  testWidgets('shows feedback before one delayed activation', (tester) async {
    final fixture = await _pumpPressable(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pressable item')),
    );
    await tester.pump();

    expect(_pressedOverlay, findsOneWidget);
    expect(fixture.events, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(_pressedOverlay, findsOneWidget);
    expect(fixture.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 79));
    expect(fixture.events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));

    expect(_activationEvents(fixture.events), hasLength(1));
    expect(_pressedOverlay, findsNothing);
  });

  testWidgets('vertical and horizontal drags cancel feedback and activation', (
    tester,
  ) async {
    for (final delta in [const Offset(0, 80), const Offset(100, 0)]) {
      final fixture = await _pumpPressable(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Pressable item')),
      );
      await tester.pump();
      expect(_pressedOverlay, findsOneWidget);
      await gesture.moveBy(delta);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_pressedOverlay, findsNothing);
      expect(_activationEvents(fixture.events), isEmpty);
    }
  });

  testWidgets('nested action wins without activating the host', (tester) async {
    final fixture = await _pumpPressable(tester);
    await tester.tap(find.text('Nested action'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(_activationEvents(fixture.events), isEmpty);
    expect(
      fixture.events.where((event) => event.eventTag == EventTagId.press),
      hasLength(1),
    );
    expect(_pressedOverlay, findsNothing);
  });

  testWidgets('rapid taps emit only one activation while feedback is pending', (
    tester,
  ) async {
    final fixture = await _pumpPressable(tester);
    await tester.tap(find.text('Pressable item'), warnIfMissed: false);
    await tester.tap(find.text('Pressable item'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));

    expect(_activationEvents(fixture.events), hasLength(1));
  });

  testWidgets('merges child label into one accessible tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = await _pumpPressable(tester);
    final matches = find.bySemanticsLabel(RegExp('^Pressable item'));

    expect(matches, findsOneWidget);
    final node = tester.getSemantics(matches);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_activationEvents(fixture.events), hasLength(1));
    semantics.dispose();
  });

  testWidgets('reduced motion keeps down feedback and activates once', (
    tester,
  ) async {
    final fixture = await _pumpPressable(tester, disableAnimations: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Pressable item')),
    );
    await tester.pump();
    expect(_pressedOverlay, findsOneWidget);
    await gesture.up();
    await tester.pump();

    expect(_activationEvents(fixture.events), hasLength(1));
    expect(_pressedOverlay, findsNothing);
  });

  testWidgets('rejects invalid delay and child counts', (tester) async {
    final invalidDelay = _PressableFixture(
      props: const PressableProps(
        overlayColorArgb: 0x181c2026,
        releaseDelayMs: 101,
      ),
      childCount: 1,
    );
    await tester.pumpWidget(invalidDelay.widget());
    expect(tester.takeException(), isA<RendererBoundaryError>());
    expect(find.byType(BonsaiRendererErrorWidget), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    for (final childCount in [0, 2]) {
      final fixture = _PressableFixture(
        props: _pressableProps(),
        childCount: childCount,
      );
      await tester.pumpWidget(fixture.widget());
      expect(tester.takeException(), isA<RendererBoundaryError>());
      expect(find.byType(BonsaiRendererErrorWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('renders without a native widget registration', (tester) async {
    final fixture = _PressableFixture(props: _pressableProps(), childCount: 1);
    await tester.pumpWidget(
      fixture.widget(
        registry: WidgetRegistry.standard(
          nativeWidgets: NativeWidgetRegistry(capabilityBits: 0),
        ),
      ),
    );

    expect(find.text('Pressable item'), findsOneWidget);
    expect(find.byType(UnsupportedNativeWidget), findsNothing);
  });

  testWidgets('drop while release is pending emits nothing late', (
    tester,
  ) async {
    final fixture = await _pumpPressable(tester);
    await tester.tap(find.text('Pressable item'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(_activationEvents(fixture.events), isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Finder get _pressedOverlay => find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == _overlayColor,
);

List<RendererEvent> _activationEvents(List<RendererEvent> events) => [
  for (final event in events)
    if (event.eventTag == EventTagId.press &&
        event.handlerId == 100 &&
        event.payload is UnitEventPayload)
      event,
];

Future<_PressableFixture> _pumpPressable(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  final fixture = _PressableFixture(props: _pressableProps(), childCount: 1);
  await tester.pumpWidget(fixture.widget(disableAnimations: disableAnimations));
  await tester.pump();
  return fixture;
}

PressableProps _pressableProps({int releaseDelayMs = 80}) => PressableProps(
  overlayColorArgb: _overlayColor.toARGB32(),
  releaseDelayMs: releaseDelayMs,
);

final class _PressableFixture {
  _PressableFixture({required this.props, required this.childCount}) {
    final operations = <FrameOperation>[
      CreateNode(
        nodeId: 1,
        kind: NodeKind.pressable,
        props: props,
        eventBindings: const [
          EventBinding(eventTag: EventTagId.press, handlerId: 100),
        ],
      ),
      if (childCount > 0) ...[
        const CreateNode(
          nodeId: 2,
          kind: NodeKind.semantics,
          props: SemanticsProps(
            label: 'Pressable item',
            role: SemanticsRoleValue.generic,
            enabled: true,
          ),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 3,
          kind: NodeKind.sizedBox,
          props: SizedBoxProps(width: 320, height: 88),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 4,
          kind: NodeKind.row,
          props: LinearProps(),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 5,
          kind: NodeKind.sizedBox,
          props: SizedBoxProps(width: 240, height: 88),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 6,
          kind: NodeKind.text,
          props: TextProps('Pressable item'),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 7,
          kind: NodeKind.sizedBox,
          props: SizedBoxProps(width: 80, height: 88),
          eventBindings: [],
        ),
        const CreateNode(
          nodeId: 8,
          kind: NodeKind.materialIconButton,
          props: MaterialButtonProps(
            variant: MaterialButtonVariant.icon,
            enabled: true,
            autofocus: false,
          ),
          eventBindings: [
            EventBinding(eventTag: EventTagId.press, handlerId: 101),
          ],
        ),
        const CreateNode(
          nodeId: 9,
          kind: NodeKind.text,
          props: TextProps('Nested action'),
          eventBindings: [],
        ),
        const SetChildren(nodeId: 1, children: [2]),
        const SetChildren(nodeId: 2, children: [3]),
        const SetChildren(nodeId: 3, children: [4]),
        const SetChildren(nodeId: 4, children: [5, 7]),
        const SetChildren(nodeId: 5, children: [6]),
        const SetChildren(nodeId: 7, children: [8]),
        const SetChildren(nodeId: 8, children: [9]),
      ] else
        const SetChildren(nodeId: 1, children: []),
      for (var index = 1; index < childCount; index += 1)
        CreateNode(
          nodeId: 9 + index,
          kind: NodeKind.text,
          props: const TextProps('Extra'),
          eventBindings: const [],
        ),
      if (childCount > 1)
        SetChildren(
          nodeId: 1,
          children: [
            2,
            for (var index = 1; index < childCount; index += 1) 9 + index,
          ],
        ),
      const SetRoot(1),
    ];
    store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: operations,
        ),
      );
  }

  final PressableProps props;
  final int childCount;
  final events = <RendererEvent>[];
  late final NodeStore store;

  Widget widget({bool disableAnimations = false, WidgetRegistry? registry}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(
            child: BonsaiFlutterView(
              store: store,
              registry: registry,
              onEvent: events.add,
            ),
          ),
        ),
      );
}
