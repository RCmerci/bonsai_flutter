import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_sqlite_worker_example/application_support_bootstrap.dart';
import 'package:bonsai_flutter_sqlite_worker_example/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final class _NeverRuntimeStarter {
  int calls = 0;
  Uint8List? config;

  Future<RuntimeSession> call(Uint8List value) {
    calls += 1;
    config = Uint8List.fromList(value);
    return Completer<RuntimeSession>().future;
  }
}

({String entrypoint, int policy, Uint8List payload}) _decodeConfig(
  Uint8List config,
) {
  expect(ascii.decode(config.sublist(0, 4)), 'BFR1');
  final data = ByteData.sublistView(config);
  final entrypointLength = data.getUint32(12, Endian.little);
  final payloadLength = data.getUint32(16, Endian.little);
  final entrypointStart = 20;
  final payloadStart = entrypointStart + entrypointLength;
  return (
    entrypoint: utf8.decode(config.sublist(entrypointStart, payloadStart)),
    policy: config[8],
    payload: Uint8List.fromList(
      config.sublist(payloadStart, payloadStart + payloadLength),
    ),
  );
}

({String databasePath, String applicationSupportDirectory})
_decodeApplicationPayload(Uint8List payload) {
  expect(ascii.decode(payload.sublist(0, 4)), 'SWC1');
  final data = ByteData.sublistView(payload);
  final databaseLength = data.getUint32(4, Endian.little);
  final directoryLength = data.getUint32(8, Endian.little);
  final databaseStart = 12;
  final directoryStart = databaseStart + databaseLength;
  return (
    databasePath: utf8.decode(payload.sublist(databaseStart, directoryStart)),
    applicationSupportDirectory: utf8.decode(
      payload.sublist(directoryStart, directoryStart + directoryLength),
    ),
  );
}

void main() {
  test(
    'resolves, creates, and encodes the Application Support database',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bonsai_flutter_sqlite_bootstrap_',
      );
      addTearDown(() => root.delete(recursive: true));
      String? createdPath;
      final result = await resolveSqliteWorkerBootstrap(
        resolveApplicationSupport: () async => root,
        createDirectory: (directory) async {
          createdPath = directory.path;
          await directory.create(recursive: true);
        },
      );
      final expectedDirectory = '${root.path}/sqlite_worker';
      final expectedDatabase = '$expectedDirectory/todos.sqlite3';
      expect(createdPath, expectedDirectory);
      expect(await Directory(expectedDirectory).exists(), isTrue);
      expect(result.databasePath, expectedDatabase);
      expect(result.applicationSupportDirectory, expectedDirectory);
      final decoded = _decodeConfig(result.runtimeConfig);
      expect(decoded.entrypoint, 'sqlite_worker');
      expect(decoded.policy, RuntimeLaunchPolicy.replaceExisting.index);
      final payload = _decodeApplicationPayload(decoded.payload);
      expect(payload.databasePath, expectedDatabase);
      expect(payload.applicationSupportDirectory, expectedDirectory);
    },
  );

  test(
    'rejects relative Application Support and path resolution failures',
    () async {
      await expectLater(
        resolveSqliteWorkerBootstrap(
          resolveApplicationSupport: () async => Directory('relative'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        resolveSqliteWorkerBootstrap(
          resolveApplicationSupport: () async =>
              throw FileSystemException('unavailable'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        resolveSqliteWorkerBootstrap(
          resolveApplicationSupport: () async => Directory('/absolute/support'),
          createDirectory: (_) async =>
              throw FileSystemException('directory creation failed'),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  testWidgets(
    'shows loading and does not start runtime before path resolution',
    (tester) async {
      final resolver = Completer<Directory>();
      final starter = _NeverRuntimeStarter();
      await tester.pumpWidget(
        MaterialApp(
          home: SqliteWorkerHost(
            resolveApplicationSupport: () => resolver.future,
            createDirectory: (_) async {},
            runtimeStarter: starter.call,
          ),
        ),
      );
      expect(find.text('Preparing Todo database…'), findsOneWidget);
      expect(starter.calls, 0);
      resolver.complete(Directory('/tmp/application-support'));
      for (var index = 0; index < 4 && starter.calls == 0; index += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(starter.calls, 1);
      final payload = _decodeApplicationPayload(
        _decodeConfig(starter.config!).payload,
      );
      expect(
        payload.databasePath,
        '/tmp/application-support/sqlite_worker/todos.sqlite3',
      );
      expect(
        payload.applicationSupportDirectory,
        '/tmp/application-support/sqlite_worker',
      );
    },
  );

  testWidgets('renders bootstrap failure without spawning a runtime', (
    tester,
  ) async {
    var now = Duration.zero;
    final starter = _NeverRuntimeStarter();
    await tester.pumpWidget(
      MaterialApp(
        home: SqliteWorkerHost(
          resolveApplicationSupport: () async {
            now = const Duration(milliseconds: 4);
            throw FileSystemException('permission denied');
          },
          runtimeStarter: starter.call,
          startupNow: () => now,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('Unable to prepare Todo storage'),
      findsOneWidget,
    );
    expect(
      find.text('Storage bootstrap: failed after 4.000 ms'),
      findsOneWidget,
    );
    expect(starter.calls, 0);
  });

  testWidgets('renders timed runtime startup failure', (tester) async {
    var now = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: SqliteWorkerHost(
          resolveApplicationSupport: () async {
            now = const Duration(milliseconds: 5);
            return Directory('/tmp/application-support');
          },
          createDirectory: (_) async {},
          runtimeStarter: (_) async {
            now = const Duration(milliseconds: 9);
            throw StateError('worker startup failed');
          },
          startupNow: () => now,
        ),
      ),
    );
    for (
      var index = 0;
      index < 6 &&
          find.textContaining('Unable to start Todo worker').evaluate().isEmpty;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Storage bootstrap: 5.000 ms'), findsOneWidget);
    expect(
      find.text('Runtime + Worker ready: failed after 4.000 ms'),
      findsOneWidget,
    );
  });
}
