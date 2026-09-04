import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/runtime_harness.dart';

void main() {
  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('Gallery stays within ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final client = await tester.runAsync(
        () => RuntimeClient.start(
          config: Uint8List.fromList(utf8.encode('gallery')),
        ),
      );
      final harness = RuntimeHarness(client!);
      addTearDown(harness.dispose);
      final initialCycle = await tester.runAsync(harness.grant);
      final frame = FrameCodec.decode(initialCycle!.bytes);
      final store = NodeStore()..apply(frame);
      final nativeWidgets =
          NativeWidgetRegistry(
            capabilityBits:
                NativeCapability.stateful |
                NativeCapability.resource |
                NativeCapability.semantics,
          )..register<String>(
            NativeWidgetRegistration(
              kindId: 1001,
              minVersion: 1,
              maxVersion: 1,
              capabilityBits:
                  NativeCapability.stateful |
                  NativeCapability.resource |
                  NativeCapability.semantics,
              decodeProps: utf8.decode,
              factory: (context) =>
                  ElevatedButton(onPressed: () {}, child: Text(context.props)),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BonsaiFlutterView(
              store: store,
              registry: WidgetRegistry.standard(nativeWidgets: nativeWidgets),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  }
}
