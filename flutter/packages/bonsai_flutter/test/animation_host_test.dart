import 'fixture.dart';
import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'semantic opacity interpolates locally and emits one completion event',
    (tester) async {
      final store = NodeStore()..apply(_snapshot());
      final resources = RendererResourceStore();
      final events = <RendererEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            resourceStore: resources,
            onEvent: events.add,
          ),
        ),
      );
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

      store.apply(_animate());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(0.5, 0.05),
      );
      expect(events, isEmpty);

      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(events, hasLength(1));
      expect(events.single.nodeId, 1);
      expect(events.single.eventTag, EventTagId.animationCompleted);
      expect(events.single.handlerId, 71);
      expect(events.single.payload, const Int64EventPayload(7001));

      store.apply(_drop());
      await tester.pump();
      expect(resources.liveResourceCount, 0);
      expect(resources.createdResourceCount, 1);
      expect(resources.disposedResourceCount, 1);
    },
  );

  test('animated opacity protocol props round trip', () {
    final encoded = FrameCodec.encode(_animate());
    final decoded = FrameCodec.decode(encoded);
    final update = decoded.operations.single as UpdateProps;

    expect(
      update.props,
      const AnimatedOpacityProps(
        opacity: 1,
        animation: AnimationIntent(
          id: 7001,
          durationMilliseconds: 100,
          curve: AnimationCurveValue.linear,
        ),
      ),
    );
  });

  testWidgets('reduced motion completes without local interpolation', (
    tester,
  ) async {
    final store = NodeStore()..apply(_snapshot());
    final resources = RendererResourceStore();
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BonsaiFlutterView(
            store: store,
            resourceStore: resources,
            onEvent: events.add,
          ),
        ),
      ),
    );
    store.apply(_animate());
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(events, hasLength(1));
    expect(events.single.payload, const Int64EventPayload(7001));

    await tester.pumpWidget(const SizedBox.shrink());
    resources.dispose();
  });

  testWidgets('a replacement intent cancels the superseded completion', (
    tester,
  ) async {
    final store = NodeStore()..apply(_snapshot());
    final resources = RendererResourceStore();
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          resourceStore: resources,
          onEvent: events.add,
        ),
      ),
    );
    store.apply(
      _animationUpdate(
        baseRevision: 1,
        targetRevision: 2,
        opacity: 1,
        animationId: 7001,
        durationMilliseconds: 200,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    store.apply(
      _animationUpdate(
        baseRevision: 2,
        targetRevision: 3,
        opacity: 0,
        animationId: 7002,
        durationMilliseconds: 50,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    expect(events, hasLength(1));
    expect(events.single.payload, const Int64EventPayload(7002));

    await tester.pumpWidget(const SizedBox.shrink());
    resources.dispose();
  });
}

Frame _snapshot() => const Frame(
  runtimeEpoch: 17,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: 1,
      kind: NodeKind.animatedOpacity,
      props: AnimatedOpacityProps(
        opacity: 0,
        animation: AnimationIntent(
          id: 7000,
          durationMilliseconds: 100,
          curve: AnimationCurveValue.linear,
        ),
      ),
      eventBindings: [
        EventBinding(eventTag: EventTagId.animationCompleted, handlerId: 71),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.text,
      props: TextProps('Animated'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2]),
    SetRoot(1),
  ],
);

Frame _animate() => const Frame(
  runtimeEpoch: 17,
  baseRevision: 1,
  targetRevision: 2,
  kind: FrameKind.incremental,
  operations: [
    UpdateProps(
      nodeId: 1,
      props: AnimatedOpacityProps(
        opacity: 1,
        animation: AnimationIntent(
          id: 7001,
          durationMilliseconds: 100,
          curve: AnimationCurveValue.linear,
        ),
      ),
    ),
  ],
);

Frame _animationUpdate({
  required int baseRevision,
  required int targetRevision,
  required double opacity,
  required int animationId,
  required int durationMilliseconds,
}) => Frame(
  runtimeEpoch: 17,
  baseRevision: baseRevision,
  targetRevision: targetRevision,
  kind: FrameKind.incremental,
  operations: [
    UpdateProps(
      nodeId: 1,
      props: AnimatedOpacityProps(
        opacity: opacity,
        animation: AnimationIntent(
          id: animationId,
          durationMilliseconds: durationMilliseconds,
          curve: AnimationCurveValue.linear,
        ),
      ),
    ),
  ],
);

Frame _drop() => const Frame(
  runtimeEpoch: 17,
  baseRevision: 0,
  targetRevision: 3,
  kind: FrameKind.fullSnapshot,
  operations: [
    SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.empty,
      props: EmptyProps(),
      eventBindings: [],
    ),
    SetRoot(3),
  ],
);
