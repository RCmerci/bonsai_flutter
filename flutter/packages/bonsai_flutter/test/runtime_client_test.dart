import 'dart:async';
import 'dart:isolate';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _exitAfterReady(List<Object?> startup) async {
  final ready = startup[0]! as SendPort;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.close();
}

void _exitBeforeReady(List<Object?> startup) {}

void main() {
  test('dedicated isolate emits terminal native diagnostics', () async {
    final client = await RuntimeClient.start();
    addTearDown(client.dispose);
    final update = client.updates.first;

    client.setFrameEligibility(generation: 1, eligible: true);
    client.grantVsync(generation: 1);

    final fatal = await update as RuntimeFatalDiagnostic;
    expect(fatal.diagnostic.code, RuntimeErrorCode.nativeLibraryLoadingError);
    expect(
      fatal.diagnostic.message,
      anyOf(
        'bonsai_flutter runtime error 12',
        contains('OCaml runtime backend is not linked'),
      ),
    );
  });

  test('same-port debug request observes prior visibility command', () async {
    final client = await RuntimeClient.start();
    addTearDown(client.dispose);

    client.setFrameEligibility(generation: 7, eligible: false);
    final snapshot = await client.debugSnapshot();

    expect(snapshot.liveGeneration, 7);
    expect(snapshot.eligible, isFalse);
    expect(snapshot.pumpCount, 0);
  });

  test('shutdown is exact once and rejects later commands', () async {
    final client = await RuntimeClient.start();

    await client.dispose();
    await client.dispose();

    expect(() => client.grantVsync(generation: 1), throwsA(isA<StateError>()));
  });

  test('acquires the coordinator lease before spawning an isolate', () async {
    final spawnEntered = Completer<void>();
    final allowSpawn = Completer<void>();
    final starting = RuntimeClient.startForTesting(
      isolateSpawner: (request) async {
        spawnEntered.complete();
        await allowSpawn.future;
        return request.spawn();
      },
    );
    await spawnEntered.future;

    await expectLater(RuntimeClient.start(), throwsStateError);

    allowSpawn.complete();
    final client = await starting;
    await client.dispose();
  });

  test('failed isolate spawn rolls back its own coordinator lease', () async {
    await expectLater(
      RuntimeClient.startForTesting(
        isolateSpawner: (_) async => throw StateError('spawn failed'),
      ),
      throwsStateError,
    );

    final client = await RuntimeClient.start();
    await client.dispose();
  });

  test('isolate exit before ready rolls back its coordinator lease', () async {
    await expectLater(
      RuntimeClient.startForTesting(
        isolateSpawner: (request) =>
            request.spawn(entrypoint: _exitBeforeReady),
      ).timeout(const Duration(seconds: 1)),
      throwsStateError,
    );

    final client = await RuntimeClient.start();
    await client.dispose();
  });

  test('abnormal isolate exit releases its coordinator lease', () async {
    final exited = await RuntimeClient.startForTesting(
      isolateSpawner: (request) => request.spawn(entrypoint: _exitAfterReady),
    );
    await exited.updates.firstWhere(
      (update) => update is RuntimeFatalDiagnostic,
    );

    final replacement = await RuntimeClient.start();
    await replacement.dispose();
  });

  test('completed disposal releases the coordinator lease', () async {
    final first = await RuntimeClient.start();
    await first.dispose();

    final second = await RuntimeClient.start();
    await second.dispose();
  });
}
