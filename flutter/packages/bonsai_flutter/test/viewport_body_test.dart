import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  testWidgets('typed body gives a sparse viewport finite constraints', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in const [Size(800, 600), Size(320, 480)]) {
      tester.view.physicalSize = size;
      final frame = FrameCodec.decode(
        readHexFixture('ocaml_viewport_body.hex'),
      );
      final store = NodeStore()..apply(frame);
      final events = <RendererEvent>[];
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final viewportSize = tester.getSize(find.byType(CustomScrollView));
      expect(viewportSize.height, greaterThan(0));
      expect(viewportSize.height.isFinite, isTrue);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      expect(find.bySemanticsLabel('Capture'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 0'), findsOneWidget);

      // The sliver varied-extent host does not yet emit visible-range
      // events (the state machine is deferred to a follow-up). Dragging
      // should still keep the viewport stable without exceptions.
      await tester.drag(find.byType(Scrollable), const Offset(0, -144));
      await tester.pump();
      expect(tester.takeException(), isNull);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
