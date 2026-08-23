import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/application_support_bootstrap.dart';

const _timeout = Duration(seconds: 15);
const _slice = Duration(milliseconds: 10);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate,
  String phase,
) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed >= _timeout) {
      final visibleText = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .toList();
      throw TimeoutException(
        '$phase timed out after ${stopwatch.elapsed}; visible text: '
        '$visibleText',
      );
    }
    await tester.runAsync(() => Future<void>.delayed(_slice));
    await tester.pump();
  }
}

Future<RuntimeClient> _mount(WidgetTester tester, Uint8List config) async {
  final runtime = await tester.runAsync(
    () => RuntimeClient.start(config: config).timeout(_timeout),
  );
  if (runtime == null) throw StateError('SQLite worker runtime did not start');
  await tester.pumpWidget(
    BonsaiFlutterRoot(config: config, runtimeStarter: (_) async => runtime),
  );
  return runtime;
}

Future<void> _unmount(WidgetTester tester, RuntimeClient runtime) async {
  await tester.runAsync(() => runtime.dispose().timeout(_timeout));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  registerSqliteWorkerFfiTests(
    resolveApplicationSupport: () =>
        Directory.systemTemp.createTemp('bonsai_flutter_sqlite_ffi_'),
    deleteApplicationSupportRoot: true,
    enforcePerformanceBudget: false,
  );
}

void registerSqliteWorkerFfiTests({
  ApplicationSupportResolver? resolveApplicationSupport,
  bool deleteApplicationSupportRoot = false,
  bool enforcePerformanceBudget = true,
}) {
  testWidgets(
    'real Worker Domain persists SQLite Todo across runtime recreation',
    (tester) async {
      final bootstrap = await tester.runAsync(
        () => resolveSqliteWorkerBootstrap(
          resolveApplicationSupport:
              resolveApplicationSupport ?? getApplicationSupportDirectory,
        ),
      );
      if (bootstrap == null) {
        throw StateError('SQLite worker bootstrap did not complete');
      }
      final databasePath = bootstrap.databasePath;
      expect(
        bootstrap.applicationSupportDirectory,
        File(databasePath).parent.path,
      );
      final storageDirectory = Directory(bootstrap.applicationSupportDirectory);
      final demoFile = File('${storageDirectory.path}/eio-worker-demo.bin');
      if (deleteApplicationSupportRoot) {
        final supportRoot = File(databasePath).parent.parent;
        addTearDown(() async {
          if (await supportRoot.exists()) {
            await supportRoot.delete(recursive: true);
          }
        });
      }
      for (final candidate in [databasePath, '$databasePath-journal']) {
        final file = File(candidate);
        await tester.runAsync(() async {
          if (await file.exists()) await file.delete();
        });
        addTearDown(() async {
          if (await file.exists()) await file.delete();
        });
      }
      await tester.runAsync(() async {
        if (await demoFile.exists()) await demoFile.delete();
        await for (final entity in storageDirectory.list()) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            await entity.delete();
          }
        }
      });
      addTearDown(() async {
        if (await demoFile.exists()) await demoFile.delete();
      });
      final config = bootstrap.runtimeConfig;
      final first = await _mount(tester, config);
      await _pumpUntil(
        tester,
        () =>
            find.text('Ready').evaluate().isNotEmpty &&
            find.text('0 open · 0 completed').evaluate().isNotEmpty,
        'Ready and initial List',
      );
      await tester.tap(find.text('Write 4 MiB demo file'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('Writing demo file…').evaluate().isNotEmpty,
        'file write pending state',
      );
      await tester.tap(find.text('Cancel file operation'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            find.text('File operation cancelled').evaluate().isNotEmpty ||
            find.text('Wrote 4194304 bytes').evaluate().isNotEmpty,
        'file write Cancel/completion race',
      );
      final temporaryAfterCancel = await tester.runAsync(
        () => storageDirectory
            .list()
            .where((entity) => entity.path.endsWith('.tmp'))
            .toList(),
      );
      expect(temporaryAfterCancel, isEmpty);
      if (find.text('File operation cancelled').evaluate().isNotEmpty) {
        await tester.tap(find.text('Write 4 MiB demo file'));
        await tester.pump();
        await _pumpUntil(
          tester,
          () => find.text('Wrote 4194304 bytes').evaluate().isNotEmpty,
          'file write completion',
        );
      }
      expect(await tester.runAsync(demoFile.length), 4 * 1024 * 1024);
      await tester.tap(find.text('Read demo file'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('Read 4194304 bytes').evaluate().isNotEmpty,
        'file read completion',
      );
      expect(find.text('Checksum: pending'), findsNothing);
      await tester.enterText(
        find.byType(EditableText),
        'Persisted through FFI',
      );
      for (var frame = 0; frame < 6; frame += 1) {
        await tester.runAsync(() => Future<void>.delayed(_slice));
        await tester.pump();
      }
      await tester.tap(find.text('Add'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            find.text('Persisted through FFI').evaluate().isNotEmpty &&
            find.text('1 open · 0 completed').evaluate().isNotEmpty,
        'Add response and coalesced pushes',
      );
      await tester.tap(find.text('Complete'));
      await _pumpUntil(
        tester,
        () => find.text('0 open · 1 completed').evaluate().isNotEmpty,
        'Toggle response and summary push',
      );

      final refreshMicros = <int>[];
      for (var iteration = 0; iteration < 30; iteration += 1) {
        final stopwatch = Stopwatch()..start();
        await tester.tap(find.text('Refresh'));
        await tester.pump();
        await _pumpUntil(
          tester,
          () => find.text('Loading').evaluate().isNotEmpty,
          'Refresh pending state $iteration',
        );
        await _pumpUntil(
          tester,
          () =>
              find.text('Ready').evaluate().isNotEmpty &&
              find.text('0 open · 1 completed').evaluate().isNotEmpty,
          'bounded Refresh load $iteration',
        );
        stopwatch.stop();
        refreshMicros.add(stopwatch.elapsedMicroseconds);
      }
      refreshMicros.sort();
      final p95 = refreshMicros[((refreshMicros.length - 1) * 0.95).round()];
      final p99 = refreshMicros[((refreshMicros.length - 1) * 0.99).round()];
      // Parseable device evidence for the profile lane.
      // ignore: avoid_print
      print('sqlite_worker_refresh_p95_us=$p95 p99_us=$p99');
      if (enforcePerformanceBudget) {
        expect(p95, lessThan(const Duration(milliseconds: 250).inMicroseconds));
        expect(p99, lessThan(const Duration(milliseconds: 500).inMicroseconds));
      }

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final hidden = (await tester.runAsync(first.debugSnapshot))!;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final stillHidden = (await tester.runAsync(first.debugSnapshot))!;
      expect(stillHidden.pumpCount, hidden.pumpCount);
      expect(stillHidden.eligible, isFalse);
      // ignore: avoid_print
      print('sqlite_worker_hidden_verified=true');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Refresh'));
      await _pumpUntil(
        tester,
        () => find.text('0 open · 1 completed').evaluate().isNotEmpty,
        'resume Refresh convergence',
      );
      // ignore: avoid_print
      print('sqlite_worker_resume_verified=true');
      await _unmount(tester, first);
      // ignore: avoid_print
      print('sqlite_worker_first_unmounted=true');

      final second = await _mount(tester, config);
      // ignore: avoid_print
      print('sqlite_worker_second_mounted=true');
      await _pumpUntil(
        tester,
        () =>
            find.text('Persisted through FFI').evaluate().isNotEmpty &&
            find.text('0 open · 1 completed').evaluate().isNotEmpty,
        'persisted recreation read',
      );
      final snapshot = (await tester.runAsync(second.debugSnapshot))!;
      expect(snapshot.state, isNot(RuntimeWorkerState.terminal));
      await _unmount(tester, second);
    },
  );
}
