import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
