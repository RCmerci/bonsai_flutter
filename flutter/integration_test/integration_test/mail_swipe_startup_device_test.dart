import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
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

  testWidgets('measure real Mail row vertical-scroll startup', (tester) async {
    await tester.pumpWidget(
      BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('mail'))),
    );
    await _waitForPresent(tester, find.text('Juniper Works'));
    await tester.pump(const Duration(milliseconds: 100));

    for (final schedule in _deliverySchedules) {
      for (var trial = 1; trial <= 3; trial += 1) {
        final result = await _measureStartup(tester, schedule);
        // Printed by flutter drive as physical-device evidence.
        // ignore: avoid_print
        print(
          'mail_startup schedule=${schedule.name} trial=$trial '
          'startup_samples=${result.$1} startup_distance=${result.$2} '
          'startup_latency_ms=${result.$3}',
        );
      }
    }
  });
}

Future<(int, double, double)> _measureStartup(
  WidgetTester tester,
  ({String name, double moveDistance, Duration cadence}) schedule,
) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  scrollable.position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 32));
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Juniper Works')),
  );
  final stopwatch = Stopwatch()..start();

  var startupSamples = -1;
  var startupDistance = 0.0;
  for (var sample = 1; sample <= 48; sample += 1) {
    await gesture.moveBy(Offset(0, -schedule.moveDistance));
    startupDistance += schedule.moveDistance;
    await tester.pump(schedule.cadence);
    if (scrollable.position.pixels >= 1) {
      startupSamples = sample;
      break;
    }
  }
  stopwatch.stop();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 100));
  expect(startupSamples, greaterThan(0));
  return (
    startupSamples,
    startupDistance,
    stopwatch.elapsedMicroseconds / 1000,
  );
}

Future<void> _waitForPresent(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for the Mail UI');
}
