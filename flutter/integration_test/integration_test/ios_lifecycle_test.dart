import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real OCaml runtime supports 100 create, step, present, and destroy cycles',
    (tester) async {
      for (var cycle = 0; cycle < 100; cycle += 1) {
        final runtime = await tester.runAsync(
          () => RuntimeClient.start(
            config: Uint8List.fromList(utf8.encode('counter')),
          ),
        );
        expect(runtime, isNotNull, reason: 'runtime creation failed at $cycle');
        final liveRuntime = runtime!;

        final initial = await tester.runAsync(
          () => liveRuntime.step(Uint8List(0)),
        );
        expect(initial, isNotNull);
        expect(initial!.status, RuntimeStatus.ok);
        final frame = FrameCodec.decode(initial.bytes);
        expect(frame.kind, FrameKind.fullSnapshot);

        final presented = await tester.runAsync(
          () => liveRuntime.framePresented(frame.targetRevision),
        );
        expect(presented, isNotNull);
        expect(presented!.status, RuntimeStatus.ok);

        final outstandingBuffers = await tester.runAsync(
          liveRuntime.debugOutstandingBufferCount,
        );
        expect(
          outstandingBuffers,
          0,
          reason: 'native buffers leaked at cycle $cycle',
        );
        await tester.runAsync(liveRuntime.dispose);
      }
    },
  );
}
