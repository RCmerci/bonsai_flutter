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

const _applicationTheme = ApplicationThemeValue(
  mode: ApplicationThemeMode.system,
  light: ThemeDataValue(
    brightness: ThemeBrightness.light,
    colorScheme: ThemeColorSchemeValue(
      seedArgb: 0xff6750a4,
      variant: ThemeDynamicVariant.tonalSpot,
      contrastLevel: 0,
    ),
    typography: ThemeTypographyValue(),
    shape: ThemeShapeValue(
      extraSmall: 4,
      small: 8,
      medium: 12,
      large: 16,
      extraLarge: 28,
    ),
    visualDensity: ThemeVisualDensity.adaptive,
    tapTargetSize: ThemeTapTargetSize.padded,
  ),
  dark: ThemeDataValue(
    brightness: ThemeBrightness.dark,
    colorScheme: ThemeColorSchemeValue(
      seedArgb: 0xff6750a4,
      variant: ThemeDynamicVariant.tonalSpot,
      contrastLevel: 0,
    ),
    typography: ThemeTypographyValue(),
    shape: ThemeShapeValue(
      extraSmall: 4,
      small: 8,
      medium: 12,
      large: 16,
      extraLarge: 28,
    ),
    visualDensity: ThemeVisualDensity.adaptive,
    tapTargetSize: ThemeTapTargetSize.padded,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'records stock Slidable startup beside a pure list on a physical device',
    (tester) async {
      for (final schedule in _deliverySchedules) {
        for (var trial = 1; trial <= 3; trial += 1) {
          final pureStartup = await _measureStartup(
            tester,
            slidableWrapped: false,
            schedule: schedule,
          );
          final wrappedStartup = await _measureStartup(
            tester,
            slidableWrapped: true,
            schedule: schedule,
          );

          // Printed by flutter drive as physical-device evidence.
          // ignore: avoid_print
          print(
            'representative_row_startup schedule=${schedule.name} trial=$trial '
            'pure_startup_samples=${pureStartup.$1} '
            'pure_startup_distance=${pureStartup.$2} '
            'pure_startup_latency_ms=${pureStartup.$3} '
            'wrapped_startup_samples=${wrappedStartup.$1} '
            'wrapped_startup_distance=${wrappedStartup.$2} '
            'wrapped_startup_latency_ms=${wrappedStartup.$3}',
          );
        }
      }
    },
  );

  testWidgets('stock Slidable eventually yields vertical scrolling', (
    tester,
  ) async {
    final fixture = await _pumpFixture(tester, inScrollableList: true);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    for (
      var sample = 0;
      sample < 8 && scrollable.position.pixels == 0;
      sample++
    ) {
      await gesture.moveBy(const Offset(1, -8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollable.position.pixels, greaterThan(0));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.events, isEmpty);
  });

  testWidgets('horizontal distance swipe still opens on a physical device', (
    tester,
  ) async {
    final fixture = await _pumpFixture(tester);
    final initialContentX = tester.getTopLeft(find.text('Message')).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.getTopLeft(find.text('Message')).dx - initialContentX,
      greaterThan(0),
    );
    expect(fixture.events, isEmpty);
  });

  testWidgets('near-diagonal touch remains eligible to swipe', (tester) async {
    final fixture = await _pumpFixture(tester, inScrollableList: true);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final initialContentX = tester.getTopLeft(find.text('Message')).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(4.1, -6));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(scrollable.position.pixels, 0);
    expect(
      tester.getTopLeft(find.text('Message')).dx - initialContentX,
      greaterThan(30),
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.events, isEmpty);
  });

  testWidgets('RTL leading swipe still maps to start-to-end', (tester) async {
    final fixture = await _pumpFixture(
      tester,
      textDirection: TextDirection.rtl,
    );
    final initialContentX = tester.getTopLeft(find.text('Message')).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Message')),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.getTopLeft(find.text('Message')).dx - initialContentX,
      lessThan(0),
    );
    expect(fixture.events, isEmpty);
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
      final initialContentX = tester.getTopLeft(find.text('Message')).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Message')),
        kind: kind,
      );

      await gesture.moveBy(const Offset(4, -6));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(scrollable.position.pixels, 0);
      expect(
        tester.getTopLeft(find.text('Message')).dx - initialContentX,
        greaterThan(30),
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(fixture.events, isEmpty);
    });
  }
}

Future<(int, double, double)> _measureStartup(
  WidgetTester tester, {
  required bool slidableWrapped,
  required ({String name, double moveDistance, Duration cadence}) schedule,
}) async {
  final fixture = await _pumpFixture(
    tester,
    inScrollableList: true,
    slidableWrapped: slidableWrapped,
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
  bool slidableWrapped = true,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  final store = NodeStore()
    ..apply(
      _slidableFrame(
        inScrollableList: inScrollableList,
        slidableWrapped: slidableWrapped,
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

Frame _slidableFrame({
  required bool inScrollableList,
  required bool slidableWrapped,
}) {
  final operations = <FrameOperation>[
    const SetApplicationTheme(title: 'Test', theme: _applicationTheme),
    if (slidableWrapped)
      CreateNode(
        nodeId: 1,
        kind: NodeKind.nativeWidget,
        props: NativeWidgetProps(
          kindId: 2,
          version: 3,
          capabilityBits:
              NativeCapability.stateful |
              NativeCapability.resource |
              NativeCapability.semantics,
          payload: _slidablePayload(),
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
    if (slidableWrapped)
      const CreateNode(
        nodeId: 3,
        kind: NodeKind.text,
        props: TextProps('Archive icon'),
        eventBindings: [],
      ),
    if (slidableWrapped)
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
    if (slidableWrapped) const SetChildren(nodeId: 1, children: [2, 3, 4]),
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
      SetChildren(nodeId: 9, children: [if (slidableWrapped) 1 else 2, 6]),
      const SetChildren(nodeId: 8, children: [9]),
      const SetRoot(8),
    ]);
  } else {
    operations.add(SetRoot(slidableWrapped ? 1 : 2));
  }
  return Frame(
    runtimeEpoch: 101,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: operations,
  );
}

Uint8List _slidablePayload() {
  final data = ByteData(240)
    ..setUint8(0, 31)
    ..setUint8(1, 0)
    ..setUint16(4, 1, Endian.little)
    ..setUint16(6, 1, Endian.little)
    // Start pane: BehindMotion, drag-dismissible, 0.5 extent.
    ..setUint8(16, 0)
    ..setUint8(17, 1)
    ..setFloat64(24, 0.5, Endian.little)
    // End pane: BehindMotion, drag-dismissible, 0.5 extent.
    ..setUint8(64, 0)
    ..setUint8(65, 1)
    ..setFloat64(72, 0.5, Endian.little)
    // Start action.
    ..setUint32(112, 1, Endian.little)
    ..setUint32(116, 0xff507d58, Endian.little)
    ..setUint8(124, 3)
    ..setUint32(128, 1, Endian.little)
    // End action.
    ..setUint32(176, 2, Endian.little)
    ..setUint32(180, 0xff435f8a, Endian.little)
    ..setUint8(188, 3)
    ..setUint32(192, 1, Endian.little);
  return data.buffer.asUint8List();
}
