import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _iterations = 20;
const _interactionY = 180.0;
const _startupTrials = 3;
const _startupSchedules = [
  (name: 'slow', moveDistance: 1.0, cadence: Duration(milliseconds: 16)),
  (name: 'normal', moveDistance: 4.0, cadence: Duration(milliseconds: 16)),
  (name: 'fast', moveDistance: 8.0, cadence: Duration(milliseconds: 16)),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('mail interactions stay within the warmed Profile frame budget', (
    tester,
  ) async {
    await tester.pumpWidget(
      BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('mail'))),
    );
    await _waitForPresent(tester, find.text('Juniper Works'));
    await tester.pumpAndSettle();

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['mail_real_row_startup'] =
        await _recordRealMailRowStartup(tester);

    await _warmInteractions(tester);

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _openDetail(tester);
        await _closeWithBack(tester);
      }
    }, reportKey: 'mail_detail_entrance');

    await _openDetail(tester);
    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _cancelEdgePop(tester);
      }
    }, reportKey: 'mail_edge_pop_cancel');
    await _closeWithBack(tester);

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _openDetail(tester);
        await _commitEdgePop(tester);
      }
    }, reportKey: 'mail_edge_pop_commit');

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _cancelRowSwipe(tester);
      }
    }, reportKey: 'mail_row_swipe_cancel');

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _commitRowSwipe(tester);
      }
    }, reportKey: 'mail_row_swipe_commit');

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _cancelDrawer(tester);
      }
    }, reportKey: 'mail_drawer_cancel');

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _openAndCloseDrawer(tester);
      }
    }, reportKey: 'mail_drawer_commit');

    await binding.traceAction(() async {
      for (var index = 0; index < _iterations; index += 1) {
        await _switchBottomDestination(tester);
      }
    }, reportKey: 'mail_bottom_switch');

    await binding.traceAction(() async {
      for (var index = 0; index < 3; index += 1) {
        await _loadNextPage(tester);
      }
    }, reportKey: 'mail_virtual_append');
  });
}

Future<List<Map<String, Object>>> _recordRealMailRowStartup(
  WidgetTester tester,
) async {
  final samples = <Map<String, Object>>[];
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

  for (final schedule in _startupSchedules) {
    for (var trial = 1; trial <= _startupTrials; trial += 1) {
      scrollable.position.jumpTo(0);
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Juniper Works')),
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
      await tester.pumpAndSettle();
      expect(startupSample, greaterThan(0));
      samples.add({
        'schedule': schedule.name,
        'trial': trial,
        'startup_samples': startupSample,
        'startup_distance': startupDistance,
        'startup_latency_ms': stopwatch.elapsedMicroseconds / 1000,
      });
    }
  }

  scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
  return samples;
}

Future<void> _warmInteractions(WidgetTester tester) async {
  for (var index = 0; index < 2; index += 1) {
    await _openDetail(tester);
    await _closeWithBack(tester);
  }

  await _openDetail(tester);
  for (var index = 0; index < 2; index += 1) {
    await _cancelEdgePop(tester);
  }
  await _closeWithBack(tester);

  for (var index = 0; index < 2; index += 1) {
    await _openDetail(tester);
    await _commitEdgePop(tester);
  }

  for (var index = 0; index < 2; index += 1) {
    await _cancelRowSwipe(tester);
    await _commitRowSwipe(tester);
    await _cancelDrawer(tester);
    await _openAndCloseDrawer(tester);
    await _switchBottomDestination(tester);
  }
}

Future<void> _openDetail(WidgetTester tester) async {
  final open = find.bySemanticsLabel('Open message from Juniper Works');
  if (open.evaluate().isEmpty) {
    await tester.tap(find.text('Juniper Works'));
    await _waitForPresent(tester, open);
  }
  await tester.tap(open);
  await _waitForPresent(tester, _detailBody);
  await tester.pumpAndSettle();
}

Future<void> _closeWithBack(WidgetTester tester) async {
  final back = find.bySemanticsLabel('Back');
  expect(back, findsOneWidget);
  await tester.tap(back);
  await _waitForAbsent(tester, _detailBody);
  await tester.pumpAndSettle();
}

Future<void> _cancelEdgePop(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(5, _interactionY));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(72, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  expect(_detailBody, findsOneWidget);
}

Future<void> _commitEdgePop(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(5, _interactionY));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(260, 0));
  await tester.pump();
  await gesture.up();
  await _waitForAbsent(tester, _detailBody);
  await tester.pumpAndSettle();
}

Future<void> _cancelRowSwipe(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Juniper Works')),
  );
  await gesture.moveBy(const Offset(-24, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-24, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.text('Juniper Works'), findsOneWidget);
}

Future<void> _commitRowSwipe(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Juniper Works')),
  );
  await gesture.moveBy(const Offset(-24, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-120, 0));
  await tester.pump();
  await gesture.up();
  final action = find.textContaining('Mark ');
  await _waitForPresent(tester, action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.text('Juniper Works'), findsOneWidget);
}

Future<void> _cancelDrawer(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(5, _interactionY));
  await gesture.moveBy(const Offset(80, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(-60, 0));
  await gesture.up();
  await tester.pumpAndSettle();
  expect(find.byType(ModalBarrier), findsNothing);
}

Future<void> _openAndCloseDrawer(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(5, _interactionY));
  await gesture.moveBy(const Offset(300, 0));
  await gesture.up();
  await _waitForPresent(tester, find.byType(ModalBarrier));
  await tester.tapAt(const Offset(385, _interactionY));
  await _waitForAbsent(tester, find.byType(ModalBarrier));
  await tester.pumpAndSettle();
}

Future<void> _switchBottomDestination(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Chat'));
  await _waitForPresent(
    tester,
    find.text('Chat is outside the scope of this local mail demo.'),
  );
  await tester.tap(find.bySemanticsLabel('Mail'));
  await _waitForPresent(tester, find.text('Juniper Works'));
  await tester.pumpAndSettle();
}

Future<void> _loadNextPage(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  final previousMaxExtent = scrollable.position.maxScrollExtent;
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    if (scrollable.position.maxScrollExtent > previousMaxExtent) break;
  }
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  final loadingMore = find.bySemanticsLabel(RegExp(r'^Loading more messages'));
  await _waitForPresent(tester, loadingMore);
  await _waitForAbsent(tester, loadingMore);
  await tester.pumpAndSettle();
}

Finder get _detailBody =>
    find.textContaining('The guide for Saturday', findRichText: true);

Future<void> _waitForPresent(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitForAbsent(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for the Mail UI to reach the expected state');
}
