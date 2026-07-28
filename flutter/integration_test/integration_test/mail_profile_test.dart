import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _iterations = 20;
const _interactionY = 180.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('mail interactions stay within the warmed Profile frame budget', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterRoot(
          config: Uint8List.fromList(utf8.encode('mail')),
        ),
      ),
    );
    await _waitForPresent(tester, find.text('Juniper Works'));
    await tester.pumpAndSettle();

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
  });
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
  }
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('Juniper Works'));
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
  await _waitForPresent(tester, find.text('Juniper Works'));
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
