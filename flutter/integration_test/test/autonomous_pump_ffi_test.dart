import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _wallClockTimeout = Duration(seconds: 10);
const _realFrameSlice = Duration(milliseconds: 10);

Future<void> _pumpRealForegroundUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required RuntimeClient runtime,
  required String phase,
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed >= _wallClockTimeout) {
      final snapshot = await tester.runAsync(runtime.debugSnapshot);
      throw TimeoutException(
        '$phase timed out after ${stopwatch.elapsed}; '
        'state=${snapshot?.state.name} '
        'generation=${snapshot?.liveGeneration} '
        'eligible=${snapshot?.eligible} '
        'pumpCount=${snapshot?.pumpCount} '
        'coalesced=${snapshot?.hasCoalescedGrant} '
        'presentation=${snapshot?.unresolvedPresentationId} '
        'revision=${snapshot?.unresolvedRevision}',
      );
    }
    await tester.runAsync(() => Future<void>.delayed(_realFrameSlice));
    await tester.pump();
  }
}

Future<RuntimeClient> _mountAutonomousFixture(WidgetTester tester) async {
  final runtime = await tester.runAsync(
    () => RuntimeClient.start(
      config: Uint8List.fromList(utf8.encode('autonomous_pump')),
    ),
  );
  if (runtime == null) throw StateError('runtime startup returned null');
  await tester.pumpWidget(
    BonsaiFlutterRoot(
      config: Uint8List.fromList(utf8.encode('autonomous_pump')),
      runtimeStarter: (_) async => runtime,
    ),
  );
  return runtime;
}

Future<void> _unmountAutonomousFixture(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets(
    'after-display and timer advance through real FFI without external input',
    (tester) async {
      final runtime = await _mountAutonomousFixture(tester);
      final observedPhases = <int>[];

      await _pumpRealForegroundUntil(
        tester,
        () {
          if (find.text('Autonomous phase 0').evaluate().isNotEmpty) {
            if (!observedPhases.contains(0)) observedPhases.add(0);
          }
          if (find.text('Autonomous phase 1').evaluate().isNotEmpty) {
            if (!observedPhases.contains(1)) observedPhases.add(1);
          }
          if (find.text('Autonomous phase 2').evaluate().isNotEmpty) {
            if (!observedPhases.contains(2)) observedPhases.add(2);
          }
          return observedPhases.contains(2);
        },
        runtime: runtime,
        phase: 'autonomous phase 2',
      );

      expect(observedPhases, [0, 1, 2]);
      await _unmountAutonomousFixture(tester);
    },
  );

  testWidgets(
    'background stops pumps and resume acknowledges then catches up',
    (tester) async {
      final runtime = await _mountAutonomousFixture(tester);
      await _pumpRealForegroundUntil(
        tester,
        () => find.text('Autonomous phase 0').evaluate().isNotEmpty,
        runtime: runtime,
        phase: 'initial phase',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final hidden = (await tester.runAsync(runtime.debugSnapshot))!;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final stillHidden = (await tester.runAsync(runtime.debugSnapshot))!;

      expect(stillHidden.pumpCount, hidden.pumpCount);
      expect(stillHidden.eligible, isFalse);
      expect(find.text('Autonomous phase 0'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpRealForegroundUntil(
        tester,
        () => find.text('Autonomous phase 2').evaluate().isNotEmpty,
        runtime: runtime,
        phase: 'resume catch-up phase',
      );

      final resumed = (await tester.runAsync(runtime.debugSnapshot))!;
      expect(resumed.eligible, isTrue);
      expect(resumed.liveGeneration, greaterThan(hidden.liveGeneration));
      expect(resumed.pumpCount, greaterThan(hidden.pumpCount));
      await _unmountAutonomousFixture(tester);
    },
  );
}
