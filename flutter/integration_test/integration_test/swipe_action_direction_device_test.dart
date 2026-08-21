import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _deliverySchedules = [
  (name: 'slow', moveDistance: 1.0, cadence: Duration(milliseconds: 16)),
  (name: 'normal', moveDistance: 4.0, cadence: Duration(milliseconds: 16)),
  (name: 'fast', moveDistance: 8.0, cadence: Duration(milliseconds: 16)),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'swipe-wrapped startup matches a pure list on a physical device',
    (tester) async {
      for (final schedule in _deliverySchedules) {
        for (var trial = 1; trial <= 3; trial += 1) {
          final pureStartup = await _measureStartup(
            tester,
            swipeWrapped: false,
            schedule: schedule,
          );
          final wrappedStartup = await _measureStartup(
            tester,
            swipeWrapped: true,
            schedule: schedule,
          );

          // Printed by flutter drive as physical-device evidence.
          // ignore: avoid_print
          print(
            'mail_row_startup schedule=${schedule.name} trial=$trial '
            'pure_startup_samples=${pureStartup.$1} '
            'pure_startup_distance=${pureStartup.$2} '
            'pure_startup_latency_ms=${pureStartup.$3} '
            'wrapped_startup_samples=${wrappedStartup.$1} '
            'wrapped_startup_distance=${wrappedStartup.$2} '
            'wrapped_startup_latency_ms=${wrappedStartup.$3}',
          );
          expect(wrappedStartup.$1, lessThanOrEqualTo(pureStartup.$1 + 1));
          expect(
            wrappedStartup.$2,
            lessThanOrEqualTo(pureStartup.$2 + schedule.moveDistance),
          );
        }
      }
    },
  );

  testWidgets('one normal touch sample starts scrolling on a physical device', (
    tester,
  ) async {
    final fixture = await _pumpFixture(tester, inScrollableList: true);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(4, -6));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -4));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scrollable.position.pixels, greaterThan(0));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.events, isEmpty);
  });

  testWidgets('horizontal distance swipe still commits on a physical device', (
    tester,
  ) async {
    final fixture = await _pumpFixture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));

    expect(_nativeDirections(fixture.events), [0]);
  });

  testWidgets('near-diagonal touch remains eligible to swipe', (tester) async {
    final fixture = await _pumpFixture(tester, inScrollableList: true);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(4.1, -6));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(scrollable.position.pixels, 0);
    expect(_contentOffset(tester), greaterThan(30));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.events, isEmpty);
  });

  testWidgets('RTL leading swipe still maps to start-to-end', (tester) async {
    final fixture = await _pumpFixture(
      tester,
      textDirection: TextDirection.rtl,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));

    expect(_nativeDirections(fixture.events), [0]);
  });

  for (final kind in [
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  ]) {
    testWidgets('$kind retains ambiguous-drag behavior on a physical device', (
      tester,
    ) async {
      final fixture = await _pumpFixture(tester, inScrollableList: true);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Message')),
        kind: kind,
      );

      await gesture.moveBy(const Offset(4, -6));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(scrollable.position.pixels, 0);
      expect(_contentOffset(tester), greaterThan(30));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(fixture.events, isEmpty);
    });
  }
}

Future<(int, double, double)> _measureStartup(
  WidgetTester tester, {
  required bool swipeWrapped,
  required ({String name, double moveDistance, Duration cadence}) schedule,
}) async {
  final fixture = await _pumpFixture(
    tester,
    inScrollableList: true,
    swipeWrapped: swipeWrapped,
  );
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Message')),
    kind: PointerDeviceKind.touch,
  );
  final stopwatch = Stopwatch()..start();

  var startupSample = -1;
  var startupDistance = 0.0;
  for (var sample = 1; sample <= 48; sample += 1) {
    await gesture.moveBy(Offset(0, -schedule.moveDistance));
    await tester.pump(schedule.cadence);
    startupDistance += schedule.moveDistance;
    if (scrollable.position.pixels > 0) {
      startupSample = sample;
      break;
    }
  }
  stopwatch.stop();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 250));
  expect(startupSample, greaterThan(0));
  expect(fixture.events, isEmpty);
  return (startupSample, startupDistance, stopwatch.elapsedMicroseconds / 1000);
}

final class _Fixture {
  const _Fixture(this.events);

  final List<RendererEvent> events;
}

Future<_Fixture> _pumpFixture(
  WidgetTester tester, {
  bool inScrollableList = false,
  bool swipeWrapped = true,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  final store = NodeStore()
    ..apply(
      _swipeFrame(
        inScrollableList: inScrollableList,
        swipeWrapped: swipeWrapped,
      ),
    );
  final events = <RendererEvent>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: BonsaiFlutterView(
          key: ValueKey<NodeStore>(store),
          store: store,
          registry: WidgetRegistry.standard(),
          onEvent: events.add,
        ),
      ),
    ),
  );
  await tester.pump();
  return _Fixture(events);
}

double _contentOffset(WidgetTester tester) {
  final host = tester.getTopLeft(
    find.byKey(const ValueKey<String>('bonsai-swipe-action-host')),
  );
  final content = tester.getTopLeft(
    find.byKey(const ValueKey<String>('bonsai-swipe-action-content')),
  );
  return content.dx - host.dx;
}

List<int> _nativeDirections(List<RendererEvent> events) => [
  for (final event in events)
    if (event.eventTag == EventTagId.nativeEvent)
      ...(event.payload as NativeEventPayload).payload,
];

Frame _swipeFrame({
  required bool inScrollableList,
  required bool swipeWrapped,
}) {
  final operations = <FrameOperation>[
    if (swipeWrapped)
      CreateNode(
        nodeId: 1,
        kind: NodeKind.nativeWidget,
        props: NativeWidgetProps(
          kindId: 2,
          version: 2,
          capabilityBits:
              NativeCapability.stateful |
              NativeCapability.resource |
              NativeCapability.semantics,
          payload: _swipePayload(),
        ),
        eventBindings: const [
          EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 900),
        ],
      ),
    const CreateNode(
      nodeId: 2,
      kind: NodeKind.pressable,
      props: PressableProps(overlayColorArgb: 0x181c2026, releaseDelayMs: 80),
      eventBindings: [EventBinding(eventTag: EventTagId.press, handlerId: 901)],
    ),
    if (swipeWrapped)
      const CreateNode(
        nodeId: 3,
        kind: NodeKind.text,
        props: TextProps('Archive icon'),
        eventBindings: [],
      ),
    if (swipeWrapped)
      const CreateNode(
        nodeId: 4,
        kind: NodeKind.text,
        props: TextProps('Read icon'),
        eventBindings: [],
      ),
    const CreateNode(
      nodeId: 5,
      kind: NodeKind.text,
      props: TextProps('Message'),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 10,
      kind: NodeKind.sizedBox,
      props: SizedBoxProps(width: 320, height: 88),
      eventBindings: [],
    ),
    if (swipeWrapped) const SetChildren(nodeId: 1, children: [2, 3, 4]),
    const SetChildren(nodeId: 2, children: [10]),
    const SetChildren(nodeId: 10, children: [5]),
  ];
  if (inScrollableList) {
    operations.addAll([
      const CreateNode(
        nodeId: 6,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: 320, height: 1000),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 7,
        kind: NodeKind.empty,
        props: EmptyProps(),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 8,
        kind: NodeKind.scrollView,
        props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 9,
        kind: NodeKind.sliverList,
        props: EmptyProps(),
        eventBindings: [],
      ),
      const SetChildren(nodeId: 6, children: [7]),
      SetChildren(nodeId: 9, children: [if (swipeWrapped) 1 else 2, 6]),
      const SetChildren(nodeId: 8, children: [9]),
      const SetRoot(8),
    ]);
  } else {
    operations.add(SetRoot(swipeWrapped ? 1 : 2));
  }
  return Frame(
    runtimeEpoch: 101,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: operations,
  );
}

Uint8List _swipePayload() {
  final start = utf8.encode('Archive');
  final end = utf8.encode('Mark read');
  final data = ByteData(44 + start.length + end.length)
    ..setUint8(0, 3)
    ..setUint8(1, 0)
    ..setUint8(2, 1)
    ..setUint32(4, 0xff507d58, Endian.little)
    ..setUint32(8, 0xff435f8a, Endian.little)
    ..setFloat64(12, 999, Endian.little)
    ..setFloat64(20, 999, Endian.little)
    ..setFloat64(28, 0, Endian.little)
    ..setUint32(36, start.length, Endian.little)
    ..setUint32(40, end.length, Endian.little);
  final payload = data.buffer.asUint8List();
  payload.setRange(44, 44 + start.length, start);
  payload.setRange(44 + start.length, payload.length, end);
  return payload;
}
