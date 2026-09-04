import 'fixture.dart';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scroll host effects drive the node-scoped controller', (
    tester,
  ) async {
    final store = NodeStore()..apply(_scrollFrame(revision: 1));
    final resources = RendererResourceStore()..synchronize(store);
    final controller = resources.acquireScrollController(7);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 100,
          child: ListView(
            controller: controller,
            children: const [SizedBox(height: 1000)],
          ),
        ),
      ),
    );
    final scrollRequest = resources.scrollTo(
      7,
      alignment: 0.75,
      animated: false,
    );
    await tester.pump();
    await scrollRequest;

    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent * 0.75, 0.001),
    );
  });

  test('scroll controller is retained and disposed with the logical node', () {
    final store = NodeStore()..apply(_scrollFrame(revision: 1));
    final resources = RendererResourceStore()..synchronize(store);

    final first = resources.acquireScrollController(7);
    final retained = resources.acquireScrollController(7);
    expect(identical(first, retained), isTrue);
    expect(resources.liveResourceCount, 1);

    store.apply(_scrollFrame(revision: 2));
    resources.synchronize(store);
    expect(identical(resources.acquireScrollController(7), first), isFalse);
    expect(resources.createdResourceCount, 2);
    expect(resources.disposedResourceCount, 1);

    resources.dispose();
    expect(resources.liveResourceCount, 0);
    expect(resources.disposedResourceCount, 2);
  });

  testWidgets(
    'borrowed scroll controller serves host effects without transferring ownership',
    (tester) async {
      final store = NodeStore()..apply(_scrollFrame(revision: 1));
      final resources = RendererResourceStore()..synchronize(store);
      final borrowed = ScrollController();
      resources.bindBorrowedScrollController(7, borrowed);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 100,
            child: ListView(
              controller: borrowed,
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      );
      final request = resources.scrollTo(7, alignment: 0.5, animated: false);
      await tester.pump();
      await request;

      expect(
        borrowed.offset,
        closeTo(borrowed.position.maxScrollExtent * 0.5, 0.001),
      );
      expect(resources.liveResourceCount, 1);
      expect(resources.createdResourceCount, 0);

      resources.unbindBorrowedScrollController(7, borrowed);
      resources.dispose();
      expect(resources.disposedResourceCount, 0);
      expect(() => borrowed.addListener(() {}), returnsNormally);
      borrowed.dispose();
    },
  );

  test('rejects competing borrowed controllers for one scroll node', () {
    final store = NodeStore()..apply(_scrollFrame(revision: 1));
    final resources = RendererResourceStore()..synchronize(store);
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(resources.dispose);

    resources.bindBorrowedScrollController(7, first);

    expect(
      () => resources.bindBorrowedScrollController(7, second),
      throwsStateError,
    );
    expect(() => resources.acquireScrollController(7), throwsStateError);
  });

  test('reconciles one scroll node between owned and borrowed modes', () {
    final store = NodeStore()..apply(_scrollFrame(revision: 1));
    final resources = RendererResourceStore()..synchronize(store);
    addTearDown(resources.dispose);
    final firstOwned = resources.acquireScrollController(7);
    final borrowed = ScrollController();
    addTearDown(borrowed.dispose);

    store.apply(_scrollPrimaryUpdate(baseRevision: 1, primary: true));
    resources.synchronize(store);
    resources.bindBorrowedScrollController(7, borrowed);
    expect(resources.disposedResourceCount, 1);

    store.apply(_scrollPrimaryUpdate(baseRevision: 2, primary: false));
    resources.synchronize(store);
    final secondOwned = resources.acquireScrollController(7);

    expect(secondOwned, isNot(same(firstOwned)));
    expect(secondOwned, isNot(same(borrowed)));
    expect(resources.createdResourceCount, 2);
    expect(() => borrowed.addListener(() {}), returnsNormally);
  });

  testWidgets('detached borrowed scroll controller fails host scrolling', (
    tester,
  ) async {
    final store = NodeStore()..apply(_scrollFrame(revision: 1));
    final resources = RendererResourceStore()..synchronize(store);
    final borrowed = ScrollController();
    addTearDown(resources.dispose);
    addTearDown(borrowed.dispose);
    resources.bindBorrowedScrollController(7, borrowed);
    resources.unbindBorrowedScrollController(7, borrowed);

    final request = resources.scrollTo(7, alignment: 0.5, animated: false);
    final expectation = expectLater(request, throwsStateError);
    await tester.pump();
    await expectation;
  });

  test(
    'native resource is retained, replaced, and disposed with node lifecycle',
    () {
      final store = NodeStore()..apply(_fullFrame(version: 1, revision: 1));
      final resources = RendererResourceStore()..synchronize(store);
      var disposed = 0;
      final first = resources.acquireNativeResource<Object>(
        nodeId: 1,
        kindId: 42,
        version: 1,
        create: Object.new,
        dispose: (_) => disposed += 1,
      );
      final retained = resources.acquireNativeResource<Object>(
        nodeId: 1,
        kindId: 42,
        version: 1,
        create: Object.new,
        dispose: (_) => disposed += 1,
      );
      expect(identical(first, retained), isTrue);

      store.apply(
        _replaceFrame(baseRevision: 1, targetRevision: 2, version: 2),
      );
      resources.synchronize(store);
      expect(disposed, 1);
      final replacement = resources.acquireNativeResource<Object>(
        nodeId: 1,
        kindId: 42,
        version: 2,
        create: Object.new,
        dispose: (_) => disposed += 1,
      );
      expect(identical(first, replacement), isFalse);

      store.apply(_dropFrame());
      resources.synchronize(store);
      expect(disposed, 2);
      expect(resources.liveResourceCount, 0);
    },
  );

  test(
    'resource lifecycle remains balanced across 1000 full resync cycles',
    () {
      final store = NodeStore();
      final resources = RendererResourceStore();
      var disposed = 0;

      for (var cycle = 0; cycle < 1000; cycle += 1) {
        store.apply(_fullFrame(version: 1, revision: cycle + 1));
        resources.synchronize(store);
        resources.acquireNativeResource<Object>(
          nodeId: 1,
          kindId: 42,
          version: 1,
          create: Object.new,
          dispose: (_) => disposed += 1,
        );
      }

      resources.dispose();
      expect(resources.liveResourceCount, 0);
      expect(resources.createdResourceCount, 1000);
      expect(resources.disposedResourceCount, 1000);
      expect(disposed, 1000);
    },
  );
}

Frame _scrollFrame({required int revision}) => Frame(
  runtimeEpoch: 2,
  baseRevision: 0,
  targetRevision: revision,
  kind: FrameKind.fullSnapshot,
  operations: const [
    SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: 7,
      kind: NodeKind.scrollView,
      props: ScrollViewProps(
        axis: ScrollAxis.vertical,
        reverse: false,
        primary: false,
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 8,
      kind: NodeKind.empty,
      props: EmptyProps(),
      eventBindings: [],
    ),
    SetChildren(nodeId: 7, children: [8]),
    SetRoot(7),
  ],
);

Frame _scrollPrimaryUpdate({
  required int baseRevision,
  required bool primary,
}) => Frame(
  runtimeEpoch: 2,
  baseRevision: baseRevision,
  targetRevision: baseRevision + 1,
  kind: FrameKind.incremental,
  operations: [
    UpdateProps(
      nodeId: 7,
      props: ScrollViewProps(
        axis: ScrollAxis.vertical,
        reverse: false,
        primary: primary,
      ),
    ),
  ],
);

Frame _fullFrame({required int version, required int revision}) => Frame(
  runtimeEpoch: 1,
  baseRevision: 0,
  targetRevision: revision,
  kind: FrameKind.fullSnapshot,
  operations: [
    const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: 1,
      kind: NodeKind.nativeWidget,
      props: _props(version),
      eventBindings: const [],
    ),
    const SetRoot(1),
  ],
);

Frame _replaceFrame({
  required int baseRevision,
  required int targetRevision,
  required int version,
}) => Frame(
  runtimeEpoch: 1,
  baseRevision: baseRevision,
  targetRevision: targetRevision,
  kind: FrameKind.incremental,
  operations: [UpdateProps(nodeId: 1, props: _props(version))],
);

Frame _dropFrame() => Frame(
  runtimeEpoch: 1,
  baseRevision: 2,
  targetRevision: 3,
  kind: FrameKind.incremental,
  operations: const [
    CreateNode(
      nodeId: 2,
      kind: NodeKind.empty,
      props: EmptyProps(),
      eventBindings: [],
    ),
    SetRoot(2),
    DropNode(1),
  ],
);

NativeWidgetProps _props(int version) => NativeWidgetProps(
  kindId: 42,
  version: version,
  capabilityBits: NativeCapability.resource,
  payload: Uint8List(0),
);
