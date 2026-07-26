import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:test/test.dart';

void expectBackendNotLinked(RuntimeResponse response) {
  expect(response.errorCode, RuntimeErrorCode.nativeLibraryLoadingError);
  expect(
    response.errorMessage,
    anyOf(
      'bonsai_flutter runtime error 12',
      contains('OCaml runtime backend is not linked'),
    ),
  );
}

void main() {
  test(
    'dedicated runtime isolate owns native calls and transfers responses',
    () async {
      final client = await RuntimeClient.start();
      addTearDown(client.dispose);

      final response = await client.step(Uint8List.fromList([1, 2, 3]));

      expect(response.status, RuntimeStatus.fatalError);
      expect(response.bytes, isEmpty);
      expectBackendNotLinked(response);
    },
  );

  test('queues concurrent commands through one serialized worker', () async {
    final client = await RuntimeClient.start();
    addTearDown(client.dispose);

    final responses = await Future.wait([
      client.step(Uint8List.fromList([1])),
      client.framePresented(1),
      client.step(Uint8List.fromList([2])),
    ]);

    expect(
      responses.map((response) => response.requestSequence),
      orderedEquals([1, 2, 3]),
    );
    expect(
      responses.map((response) => response.status),
      everyElement(RuntimeStatus.fatalError),
    );
  });

  test(
    'encodes a typed event batch before crossing the isolate boundary',
    () async {
      final client = await RuntimeClient.start();
      addTearDown(client.dispose);
      final batch = EventBatch(
        runtimeEpoch: 21,
        events: [
          UiEvent(
            sequence: 1,
            displayedRevision: 1,
            nodeId: 3,
            handlerId: 9001,
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        ],
      );

      final response = await client.sendEventBatch(batch);

      expect(response.status, RuntimeStatus.fatalError);
      expectBackendNotLinked(response);
    },
  );

  test('shutdown is acknowledged and rejects later commands', () async {
    final client = await RuntimeClient.start();

    expect(await client.debugOutstandingBufferCount(), 0);
    await client.dispose();
    await client.dispose();

    expect(() => client.step(Uint8List(0)), throwsA(isA<StateError>()));
  });
}
