import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/runtime_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real OCaml runtime supports 100 create, pump, present, and destroy cycles',
    (tester) async {
      for (var cycle = 0; cycle < 100; cycle += 1) {
        final runtime = await tester.runAsync(
          () => RuntimeClient.start(
            config: Uint8List.fromList(utf8.encode('counter')),
          ),
        );
        expect(runtime, isNotNull, reason: 'runtime creation failed at $cycle');
        final liveRuntime = runtime!;
        final harness = RuntimeHarness(liveRuntime);

        final initial = await tester.runAsync(harness.grant);
        expect(initial, isNotNull);
        final frame = FrameCodec.decode(initial!.bytes);
        expect(frame.kind, FrameKind.fullSnapshot);

        harness.acknowledge();
        final presented = await tester.runAsync(liveRuntime.debugSnapshot);
        expect(presented, isNotNull);
        expect(presented!.state, RuntimeWorkerState.ready);
        await tester.runAsync(harness.dispose);
      }
    },
  );
}
