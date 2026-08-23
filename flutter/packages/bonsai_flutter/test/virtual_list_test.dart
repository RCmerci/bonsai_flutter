import 'fixture.dart';
import 'dart:collection';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/renderer/sliver_virtual_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sliver fixed extent props round trip through the frame codec', () {
    const props = SliverFixedExtentProps(
      totalCount: 50000,
      firstIndex: 100,
      itemExtent: 48,
      overscan: 4,
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverFixedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations.whereType<CreateNode>().single;
    expect(create.kind, NodeKind.sliverFixedExtent);
    expect(create.props, props);
  });

  test('sliver varied extent props round trip through the frame codec', () {
    const props = SliverVariedExtentProps(
      totalCount: 50000,
      firstIndex: 40,
      defaultItemExtent: 48,
      overscan: 5,
      extentOverrides: [
        SparseExtentOverride(index: 3, extent: 120),
        SparseExtentOverride(index: 42, extent: 312),
      ],
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations.whereType<CreateNode>().single;
    expect(create.kind, NodeKind.sliverVariedExtent);
    expect(create.props, props);
  });

  test('sliver varied extent props round trip with a transition', () {
    const transition = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 240,
      collapseDurationMs: 190,
      expandCurve: SparseExtentCurve.easeOutCubic,
      collapseCurve: SparseExtentCurve.easeInOutCubic,
    );
    const props = SliverVariedExtentProps(
      totalCount: 20,
      firstIndex: 4,
      defaultItemExtent: 88,
      overscan: 4,
      extentOverrides: [SparseExtentOverride(index: 6, extent: 320)],
      transition: transition,
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations.whereType<CreateNode>().single;
    expect(create.props, props);
    final decodedProps = create.props as SliverVariedExtentProps;
    expect(decodedProps.transition, transition);
  });

  test('sliver varied extent props without transition round trip', () {
    const props = SliverVariedExtentProps(
      totalCount: 20,
      firstIndex: 4,
      defaultItemExtent: 88,
      overscan: 4,
      extentOverrides: [],
    );
    final frame = Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        CreateNode(
          nodeId: 1,
          kind: NodeKind.sliverVariedExtent,
          props: props,
          eventBindings: const [],
        ),
        const SetRoot(1),
      ],
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final create = decoded.operations.whereType<CreateNode>().single;
    expect(create.props, props);
    expect((create.props as SliverVariedExtentProps).transition, isNull);
  });

  test('sparse extent transition equality and curve wire ids', () {
    const a = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.linear,
      collapseCurve: SparseExtentCurve.linear,
    );
    const b = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.linear,
      collapseCurve: SparseExtentCurve.linear,
    );
    const c = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 200,
      collapseDurationMs: 200,
      expandCurve: SparseExtentCurve.easeOut,
      collapseCurve: SparseExtentCurve.linear,
    );
    expect(a, b);
    expect(a, isNot(c));
    expect(SparseExtentCurve.linear.wireId, 0);
    expect(SparseExtentCurve.easeOutCubic.wireId, 4);
    expect(SparseExtentCurve.fromWireId(5), SparseExtentCurve.easeInOutCubic);
  });

  test('sparse extent override equality', () {
    const a = SparseExtentOverride(index: 3, extent: 120);
    const b = SparseExtentOverride(index: 3, extent: 120);
    const c = SparseExtentOverride(index: 4, extent: 120);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.hashCode, b.hashCode);
  });

  testWidgets('sliver fixed extent mounts children in a CustomScrollView', (
    tester,
  ) async {
    final children = List.generate(
      20,
      (index) => CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Item ${100 + index}'),
        eventBindings: const [],
      ),
    );
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const SetApplicationTheme(
              title: 'Test',
              theme: testApplicationTheme,
            ),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.scrollView,
              props: const ScrollViewProps(
                axis: ScrollAxis.vertical,
                reverse: false,
              ),
              eventBindings: const [],
            ),
            CreateNode(
              nodeId: 100,
              kind: NodeKind.sliverFixedExtent,
              props: const SliverFixedExtentProps(
                totalCount: 50000,
                firstIndex: 100,
                itemExtent: 48,
                overscan: 4,
              ),
              eventBindings: const [],
            ),
            ...children,
            SetChildren(
              nodeId: 100,
              children: List.generate(20, (index) => index + 2),
            ),
            SetChildren(nodeId: 1, children: const [100]),
            const SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverFixedExtentList), findsOneWidget);
    expect(find.text('Item 100'), findsOneWidget);
  });

  // Regression: when a virtualized sliver shares a CustomScrollView with a
  // preceding sliver (e.g. a sticky/collapsing header), the reported visible
  // range must be relative to that sliver's own content, not the absolute
  // [ScrollController.offset] of the whole scroll view. Otherwise the
  // first_index/last_exclusive window is shifted by the preceding slivers'
  // total height and the OCaml side materializes the wrong children.
  testWidgets(
    'sliver fixed extent reports a sliver-relative range with a preceding header',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final listChildren = List.generate(
        40,
        (index) => CreateNode(
          nodeId: 200 + index,
          kind: NodeKind.text,
          props: TextProps('Item $index'),
          eventBindings: const [],
        ),
      );
      final store = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 1,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              const SetApplicationTheme(
                title: 'Test',
                theme: testApplicationTheme,
              ),
              CreateNode(
                nodeId: 1,
                kind: NodeKind.scrollView,
                props: const ScrollViewProps(
                  axis: ScrollAxis.vertical,
                  reverse: false,
                ),
                eventBindings: const [],
              ),
              CreateNode(
                nodeId: 2,
                kind: NodeKind.sliverBox,
                props: const EmptyProps(),
                eventBindings: const [],
              ),
              CreateNode(
                nodeId: 3,
                kind: NodeKind.sizedBox,
                props: const SizedBoxProps(width: null, height: 200),
                eventBindings: const [],
              ),
              const CreateNode(
                nodeId: 4,
                kind: NodeKind.text,
                props: TextProps('Header'),
                eventBindings: [],
              ),
              CreateNode(
                nodeId: 100,
                kind: NodeKind.sliverFixedExtent,
                props: const SliverFixedExtentProps(
                  totalCount: 1000,
                  firstIndex: 0,
                  itemExtent: 48,
                  overscan: 0,
                ),
                eventBindings: const [
                  EventBinding(
                    eventTag: EventTagId.visibleRangeChanged,
                    handlerId: 1,
                  ),
                ],
              ),
              ...listChildren,
              SetChildren(nodeId: 2, children: const [3]),
              SetChildren(nodeId: 3, children: const [4]),
              SetChildren(
                nodeId: 100,
                children: List.generate(40, (index) => 200 + index),
              ),
              SetChildren(nodeId: 1, children: const [2, 100]),
              const SetRoot(1),
            ],
          ),
        );

      final events = <RendererEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // At offset 0 the 200px header occludes the top of the viewport, so only
      // 400px of the list is visible: [0, ceil(400/48)) = [0, 9).
      VisibleRangeEventPayload initialRange() =>
          events
                  .where((event) => event.payload is VisibleRangeEventPayload)
                  .last
                  .payload
              as VisibleRangeEventPayload;
      expect(initialRange().firstIndex, 0);
      expect(initialRange().lastExclusive, 9);

      // Scroll to absolute offset 250 (past the 200px header). The list's own
      // leading edge is at relative offset 50 and the full 600px viewport is
      // available: [floor(50/48), ceil(650/48)) = [1, 14).
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(250);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      final scrolledRange =
          events
                  .where((event) => event.payload is VisibleRangeEventPayload)
                  .last
                  .payload
              as VisibleRangeEventPayload;
      expect(scrolledRange.firstIndex, 1);
      expect(scrolledRange.lastExclusive, 14);
    },
  );

  // Same regression as the fixed-extent case above, but exercising the
  // [SliverVariedExtentHost] (sparse-extent geometry path). With a uniform
  // default extent the expected windows match the fixed-extent case, proving
  // the varied host also reports a sliver-relative range.
  testWidgets(
    'sliver varied extent reports a sliver-relative range with a preceding header',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final listChildren = List.generate(
        40,
        (index) => CreateNode(
          nodeId: 200 + index,
          kind: NodeKind.text,
          props: TextProps('Item $index'),
          eventBindings: const [],
        ),
      );
      final store = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 1,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              const SetApplicationTheme(
                title: 'Test',
                theme: testApplicationTheme,
              ),
              CreateNode(
                nodeId: 1,
                kind: NodeKind.scrollView,
                props: const ScrollViewProps(
                  axis: ScrollAxis.vertical,
                  reverse: false,
                ),
                eventBindings: const [],
              ),
              CreateNode(
                nodeId: 2,
                kind: NodeKind.sliverBox,
                props: const EmptyProps(),
                eventBindings: const [],
              ),
              CreateNode(
                nodeId: 3,
                kind: NodeKind.sizedBox,
                props: const SizedBoxProps(width: null, height: 200),
                eventBindings: const [],
              ),
              const CreateNode(
                nodeId: 4,
                kind: NodeKind.text,
                props: TextProps('Header'),
                eventBindings: [],
              ),
              CreateNode(
                nodeId: 101,
                kind: NodeKind.sliverVariedExtent,
                props: const SliverVariedExtentProps(
                  totalCount: 1000,
                  firstIndex: 0,
                  defaultItemExtent: 48,
                  overscan: 0,
                  extentOverrides: [],
                ),
                eventBindings: const [
                  EventBinding(
                    eventTag: EventTagId.visibleRangeChanged,
                    handlerId: 1,
                  ),
                ],
              ),
              ...listChildren,
              SetChildren(nodeId: 2, children: const [3]),
              SetChildren(nodeId: 3, children: const [4]),
              SetChildren(
                nodeId: 101,
                children: List.generate(40, (index) => 200 + index),
              ),
              SetChildren(nodeId: 1, children: const [2, 101]),
              const SetRoot(1),
            ],
          ),
        );

      final events = <RendererEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 600,
            child: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      VisibleRangeEventPayload currentRange() =>
          events
                  .where((event) => event.payload is VisibleRangeEventPayload)
                  .last
                  .payload
              as VisibleRangeEventPayload;
      // Header occludes 200px: [0, 9).
      expect(currentRange().firstIndex, 0);
      expect(currentRange().lastExclusive, 9);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(250);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Past the header: relative offset 50, full viewport: [1, 14).
      expect(currentRange().firstIndex, 1);
      expect(currentRange().lastExclusive, 14);
    },
  );

  for (final kind in _VirtualSliverKind.values) {
    testWidgets(
      '${kind.label} retains the keyed overlap across a materialized window shift',
      (tester) async {
        await _setViewport(tester, const Size(400, 150));
        final initialProps = switch (kind) {
          _VirtualSliverKind.fixed => const SliverFixedExtentProps(
            totalCount: 3,
            firstIndex: 0,
            itemExtent: 50,
            overscan: 0,
          ),
          _VirtualSliverKind.varied => _variedProps(
            totalCount: 3,
            firstIndex: 0,
            itemExtent: 50,
          ),
        };
        final store = NodeStore()
          ..apply(
            Frame(
              runtimeEpoch: 1,
              baseRevision: 0,
              targetRevision: 1,
              kind: FrameKind.fullSnapshot,
              operations: [
                const SetApplicationTheme(
                  title: 'Test',
                  theme: testApplicationTheme,
                ),
                CreateNode(
                  nodeId: 1,
                  kind: NodeKind.scrollView,
                  props: const ScrollViewProps(
                    axis: ScrollAxis.vertical,
                    reverse: false,
                  ),
                  eventBindings: const [],
                ),
                CreateNode(
                  nodeId: _virtualNodeId,
                  kind: kind == _VirtualSliverKind.fixed
                      ? NodeKind.sliverFixedExtent
                      : NodeKind.sliverVariedExtent,
                  props: initialProps,
                  eventBindings: const [],
                ),
                const CreateNode(
                  nodeId: 1000,
                  kind: NodeKind.text,
                  props: TextProps('A'),
                  eventBindings: [],
                ),
                const CreateNode(
                  nodeId: 1001,
                  kind: NodeKind.text,
                  props: TextProps('B'),
                  eventBindings: [],
                ),
                const SetChildren(
                  nodeId: _virtualNodeId,
                  children: [1000, 1001],
                ),
                const SetChildren(nodeId: 1, children: [_virtualNodeId]),
                const SetRoot(1),
              ],
            ),
          );

        await tester.pumpWidget(_virtualSliverView(store));
        await tester.pump();
        expect(tester.takeException(), isNull);

        final aFinder = find.byKey(
          const ValueKey<int>(1000),
          skipOffstage: false,
        );
        final bFinder = find.byKey(
          const ValueKey<int>(1001),
          skipOffstage: false,
        );
        final cFinder = find.byKey(
          const ValueKey<int>(1002),
          skipOffstage: false,
        );
        expect(aFinder, findsOneWidget);
        expect(bFinder, findsOneWidget);
        expect(cFinder, findsNothing);
        final aElementBefore = tester.element(aFinder);
        final bElementBefore = tester.element(bFinder);

        final shiftedProps = switch (kind) {
          _VirtualSliverKind.fixed => const SliverFixedExtentProps(
            totalCount: 3,
            firstIndex: 1,
            itemExtent: 50,
            overscan: 0,
          ),
          _VirtualSliverKind.varied => _variedProps(
            totalCount: 3,
            firstIndex: 1,
            itemExtent: 50,
          ),
        };
        store.apply(
          Frame(
            runtimeEpoch: 1,
            baseRevision: 1,
            targetRevision: 2,
            kind: FrameKind.incremental,
            operations: [
              const CreateNode(
                nodeId: 1002,
                kind: NodeKind.text,
                props: TextProps('C'),
                eventBindings: [],
              ),
              UpdateProps(nodeId: _virtualNodeId, props: shiftedProps),
              const SetChildren(nodeId: _virtualNodeId, children: [1001, 1002]),
              const DropNode(1000),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(aFinder, findsNothing);
        expect(aElementBefore.mounted, isFalse);
        expect(bFinder, findsOneWidget);
        expect(identical(tester.element(bFinder), bElementBefore), isTrue);
        expect(store.node(1001).id, 1001);
        expect(cFinder, findsOneWidget);
        expect(identical(tester.element(cFinder), bElementBefore), isFalse);
      },
    );
  }

  for (final kind in _VirtualSliverKind.values) {
    testWidgets(
      '${kind.label} initial anchor includes preceding sliver extent',
      (tester) async {
        await _setViewport(tester, const Size(400, 200));
        final store = _virtualSliverStore(
          kind: kind,
          totalCount: 50,
          firstIndex: 10,
          itemExtent: 50,
          childCount: 10,
          headerExtent: 200,
        );

        await tester.pumpWidget(_virtualSliverView(store));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(_scrollPosition(tester).pixels, closeTo(700, 0.01));
      },
    );

    testWidgets('${kind.label} clamps a trailing initial window', (
      tester,
    ) async {
      await _setViewport(tester, const Size(400, 200));
      final store = _virtualSliverStore(
        kind: kind,
        totalCount: 20,
        firstIndex: 18,
        itemExtent: 50,
        childCount: 2,
      );

      await tester.pumpWidget(_virtualSliverView(store));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_scrollPosition(tester).pixels, closeTo(800, 0.01));
      expect(
        _scrollPosition(tester).pixels,
        _scrollPosition(tester).maxScrollExtent,
      );
    });
  }

  for (final firstKind in _VirtualSliverKind.values) {
    for (final secondKind in _VirtualSliverKind.values) {
      testWidgets(
        '${firstKind.label} before ${secondKind.label} owns the initial anchor',
        (tester) async {
          await _setViewport(tester, const Size(400, 200));
          final store = _twoVirtualSliverStore(
            firstKind: firstKind,
            secondKind: secondKind,
            firstIndex: 10,
            secondIndex: 15,
          );

          await tester.pumpWidget(_virtualSliverView(store));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(_scrollPosition(tester).pixels, closeTo(500, 0.01));
        },
      );
    }
  }

  testWidgets(
    'an earliest zero-index virtual sliver prevents a later implicit anchor',
    (tester) async {
      await _setViewport(tester, const Size(400, 200));
      final store = _twoVirtualSliverStore(
        firstKind: _VirtualSliverKind.fixed,
        secondKind: _VirtualSliverKind.varied,
        firstIndex: 0,
        secondIndex: 15,
      );

      await tester.pumpWidget(_virtualSliverView(store));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_scrollPosition(tester).pixels, 0);
    },
  );

  testWidgets(
    'an established non-zero scroll offset prevents implicit anchors',
    (tester) async {
      await _setViewport(tester, const Size(400, 200));
      final controller = ScrollController(initialScrollOffset: 125);
      addTearDown(controller.dispose);
      final store = _twoVirtualSliverStore(
        firstKind: _VirtualSliverKind.fixed,
        secondKind: _VirtualSliverKind.varied,
        firstIndex: 10,
        secondIndex: 15,
        primary: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PrimaryScrollController(
            controller: controller,
            child: SizedBox(
              width: 400,
              height: 200,
              child: BonsaiFlutterView(store: store),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.offset, closeTo(125, 0.01));
    },
  );

  for (final kind in _VirtualSliverKind.values) {
    testWidgets(
      '${kind.label} publishes its initial range after zero paint becomes usable',
      (tester) async {
        await _setViewport(tester, const Size(400, 200));
        final store = _virtualSliverStore(
          kind: kind,
          totalCount: 20,
          firstIndex: 0,
          itemExtent: 50,
          childCount: 20,
          headerExtent: 400,
          bindVisibleRange: true,
        );
        final events = <RendererEvent>[];

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 400,
              height: 200,
              child: BonsaiFlutterView(store: store, onEvent: events.add),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(_visibleRangeEvents(events), isEmpty);
        final hostState = tester.state(_hostFinder(kind));

        store.apply(
          const Frame(
            runtimeEpoch: 1,
            baseRevision: 1,
            targetRevision: 2,
            kind: FrameKind.incremental,
            operations: [
              UpdateProps(
                nodeId: 3,
                props: SizedBoxProps(width: null, height: 0),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(identical(tester.state(_hostFinder(kind)), hostState), isTrue);
        final ranges = _visibleRangeEvents(events);
        expect(ranges, hasLength(1));
        expect(ranges.single.firstIndex, 0);
        expect(ranges.single.lastExclusive, 4);

        await tester.pump();
        await tester.pump();
        expect(_visibleRangeEvents(events), hasLength(1));
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('${kind.label} does not create a frame loop at zero paint', (
      tester,
    ) async {
      await _setViewport(tester, const Size(400, 200));
      final events = <RendererEvent>[];
      final store = _virtualSliverStore(
        kind: kind,
        totalCount: 20,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 20,
        headerExtent: 400,
        bindVisibleRange: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_visibleRangeEvents(events), isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets('sliver varied extent anchors a firstIndex update', (
    tester,
  ) async {
    await _setViewport(tester, const Size(400, 200));
    final store = _virtualSliverStore(
      kind: _VirtualSliverKind.varied,
      totalCount: 50,
      firstIndex: 0,
      itemExtent: 50,
      childCount: 10,
    );
    await tester.pumpWidget(_virtualSliverView(store));
    await tester.pump();

    store.apply(
      Frame(
        runtimeEpoch: 1,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(
            nodeId: _virtualNodeId,
            props: _variedProps(totalCount: 50, firstIndex: 10, itemExtent: 50),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_scrollPosition(tester).pixels, closeTo(500, 0.01));
  });

  testWidgets(
    'sliver varied extent preserves the visible item when default extent changes',
    (tester) async {
      await _setViewport(tester, const Size(400, 200));
      final store = _virtualSliverStore(
        kind: _VirtualSliverKind.varied,
        totalCount: 40,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 40,
      );
      await tester.pumpWidget(_virtualSliverView(store));
      await tester.pump();
      _scrollPosition(tester).jumpTo(500);
      await tester.pump();

      store.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: _virtualNodeId,
              props: _variedProps(
                totalCount: 40,
                firstIndex: 0,
                itemExtent: 100,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_scrollPosition(tester).pixels, closeTo(1000, 0.01));
    },
  );

  testWidgets(
    'sliver varied extent completes an animated anchor after preceding content',
    (tester) async {
      await _setViewport(tester, const Size(400, 200));
      const transition = SparseExtentTransition(
        enabled: true,
        expandDurationMs: 100,
        collapseDurationMs: 100,
        expandCurve: SparseExtentCurve.linear,
        collapseCurve: SparseExtentCurve.linear,
      );
      final store = _virtualSliverStore(
        kind: _VirtualSliverKind.varied,
        totalCount: 20,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 20,
        headerExtent: 200,
        extentOverrides: const [SparseExtentOverride(index: 5, extent: 50)],
        transition: transition,
      );
      await tester.pumpWidget(_virtualSliverView(store));
      await tester.pump();
      _scrollPosition(tester).jumpTo(1000);
      await tester.pump();

      store.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: _virtualNodeId,
              props: _variedProps(
                totalCount: 20,
                firstIndex: 0,
                itemExtent: 50,
                extentOverrides: const [
                  SparseExtentOverride(index: 5, extent: 150),
                ],
                transition: transition,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_scrollPosition(tester).pixels, closeTo(1100, 0.01));
    },
  );

  testWidgets(
    'sliver varied extent scans sparse overrides linearly per update',
    (tester) async {
      await _setViewport(tester, const Size(400, 200));
      const overrideCount = 200;
      final oldOverrides = _CountingOverrideList([
        for (var index = 0; index < overrideCount; index += 1)
          SparseExtentOverride(index: index, extent: 50),
      ]);
      final newOverrides = _CountingOverrideList([
        for (var index = 0; index < overrideCount; index += 1)
          SparseExtentOverride(index: index, extent: 51),
      ]);
      const transition = SparseExtentTransition(
        enabled: true,
        expandDurationMs: 100,
        collapseDurationMs: 100,
        expandCurve: SparseExtentCurve.linear,
        collapseCurve: SparseExtentCurve.linear,
      );
      final store = _virtualSliverStore(
        kind: _VirtualSliverKind.varied,
        totalCount: 300,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 10,
        extentOverrides: oldOverrides,
        transition: transition,
      );
      await tester.pumpWidget(_virtualSliverView(store));
      await tester.pump();
      oldOverrides.readCount = 0;

      store.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: _virtualNodeId,
              props: _variedProps(
                totalCount: 300,
                firstIndex: 0,
                itemExtent: 50,
                extentOverrides: newOverrides,
                transition: transition,
              ),
            ),
          ],
        ),
      );
      await tester.pump();

      final reads = oldOverrides.readCount + newOverrides.readCount;
      expect(reads, lessThan(overrideCount * 20));
    },
  );

  for (final kind in _VirtualSliverKind.values) {
    testWidgets('${kind.label} republishes to a replacement binding', (
      tester,
    ) async {
      await _setViewport(tester, const Size(400, 200));
      final events = <RendererEvent>[];
      final store = _virtualSliverStore(
        kind: kind,
        totalCount: 20,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 20,
        bindVisibleRange: true,
      );
      await tester.pumpWidget(_virtualSliverViewWithEvents(store, events.add));
      await tester.pump();
      await tester.pump();
      events.clear();

      store.apply(
        const Frame(
          runtimeEpoch: 1,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateEventBindings(
              nodeId: _virtualNodeId,
              eventBindings: [
                EventBinding(
                  eventTag: EventTagId.visibleRangeChanged,
                  handlerId: 2,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final rangeEvents = events
          .where((event) => event.payload is VisibleRangeEventPayload)
          .toList();
      expect(rangeEvents, hasLength(1));
      expect(rangeEvents.single.handlerId, 2);
      await tester.pump();
      expect(
        events.where((event) => event.payload is VisibleRangeEventPayload),
        hasLength(1),
      );
    });

    testWidgets('${kind.label} republishes after a full runtime snapshot', (
      tester,
    ) async {
      await _setViewport(tester, const Size(400, 200));
      final events = <RendererEvent>[];
      final store = _virtualSliverStore(
        kind: kind,
        totalCount: 20,
        firstIndex: 0,
        itemExtent: 50,
        childCount: 20,
        bindVisibleRange: true,
      );
      await tester.pumpWidget(_virtualSliverViewWithEvents(store, events.add));
      await tester.pump();
      await tester.pump();
      events.clear();

      store.apply(
        _virtualSliverFrame(
          kind: kind,
          totalCount: 20,
          firstIndex: 0,
          itemExtent: 50,
          childCount: 20,
          bindVisibleRange: true,
          runtimeEpoch: 2,
        ),
      );
      await tester.pump();
      await tester.pump();

      final rangeEvents = events
          .where((event) => event.payload is VisibleRangeEventPayload)
          .toList();
      expect(rangeEvents, hasLength(1));
      expect(rangeEvents.single.handlerId, 1);
    });

    testWidgets(
      '${kind.label} publishes when an event sink becomes available',
      (tester) async {
        await _setViewport(tester, const Size(400, 200));
        final events = <RendererEvent>[];
        final store = _virtualSliverStore(
          kind: kind,
          totalCount: 20,
          firstIndex: 0,
          itemExtent: 50,
          childCount: 20,
          bindVisibleRange: true,
        );
        await tester.pumpWidget(_virtualSliverView(store));
        await tester.pump();
        await tester.pump();

        await tester.pumpWidget(
          _virtualSliverViewWithEvents(store, events.add),
        );
        await tester.pump();
        await tester.pump();

        expect(_visibleRangeEvents(events), hasLength(1));
        await tester.pump();
        expect(_visibleRangeEvents(events), hasLength(1));
      },
    );

    testWidgets('${kind.label} uses a precomputed key-index lookup', (
      tester,
    ) async {
      await _setViewport(tester, const Size(400, 200));
      final controller = ScrollController();
      final coordinator = InitialSliverAnchorCoordinator(controller);
      addTearDown(controller.dispose);
      addTearDown(coordinator.dispose);
      final children = _CountingWidgetList([
        for (var index = 0; index < 100; index += 1)
          SizedBox(key: ValueKey<int>(index), height: 50),
      ]);
      final host = switch (kind) {
        _VirtualSliverKind.fixed => SliverFixedExtentHost(
          nodeId: 1,
          deliveryGeneration: 1,
          props: const SliverFixedExtentProps(
            totalCount: 100,
            firstIndex: 0,
            itemExtent: 50,
            overscan: 0,
          ),
          children: children,
          controller: controller,
          anchorCoordinator: coordinator,
          binding: null,
          onEvent: null,
        ),
        _VirtualSliverKind.varied => SliverVariedExtentHost(
          nodeId: 1,
          deliveryGeneration: 1,
          props: const SliverVariedExtentProps(
            totalCount: 100,
            firstIndex: 0,
            defaultItemExtent: 50,
            overscan: 0,
            extentOverrides: [],
          ),
          children: children,
          controller: controller,
          anchorCoordinator: coordinator,
          binding: null,
          onEvent: null,
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: CustomScrollView(controller: controller, slivers: [host]),
          ),
        ),
      );
      await tester.pump();

      final delegate =
          switch (kind) {
                _VirtualSliverKind.fixed =>
                  tester
                      .widget<SliverFixedExtentList>(
                        find.byType(SliverFixedExtentList),
                      )
                      .delegate,
                _VirtualSliverKind.varied =>
                  tester
                      .widget<SliverVariedExtentList>(
                        find.byType(SliverVariedExtentList),
                      )
                      .delegate,
              }
              as SliverChildBuilderDelegate;
      children.readCount = 0;
      for (var index = 0; index < 100; index += 1) {
        expect(delegate.findChildIndexCallback!(ValueKey<int>(index)), index);
      }
      expect(children.readCount, 0);
      expect(
        delegate.findChildIndexCallback!(const ValueKey<int>(1000)),
        isNull,
      );
    });
  }

  testWidgets('virtual slivers reject duplicate non-null child keys', (
    tester,
  ) async {
    await _setViewport(tester, const Size(400, 200));
    final controller = ScrollController();
    final coordinator = InitialSliverAnchorCoordinator(controller);
    addTearDown(controller.dispose);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: CustomScrollView(
            controller: controller,
            slivers: [
              SliverFixedExtentHost(
                nodeId: 1,
                deliveryGeneration: 1,
                props: const SliverFixedExtentProps(
                  totalCount: 2,
                  firstIndex: 0,
                  itemExtent: 50,
                  overscan: 0,
                ),
                controller: controller,
                anchorCoordinator: coordinator,
                binding: null,
                onEvent: null,
                children: const [
                  SizedBox(key: ValueKey<int>(1)),
                  SizedBox(key: ValueKey<int>(1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isA<RendererBuildException>());
  });

  testWidgets('direct virtual sliver rendering rejects malformed props', (
    tester,
  ) async {
    // The semantic validator is shared by the codec, store, and renderer. This
    // direct entry point ensures malformed in-memory props cannot reach Flutter.
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final registry = WidgetRegistry.standard();
    for (final props in const <UiProps>[
      SliverFixedExtentProps(
        totalCount: 1,
        firstIndex: 2,
        itemExtent: 48,
        overscan: 0,
      ),
      SliverVariedExtentProps(
        totalCount: 1,
        firstIndex: 0,
        defaultItemExtent: 48,
        overscan: 0,
        extentOverrides: [SparseExtentOverride(index: 1, extent: 60)],
      ),
    ]) {
      expect(
        () => registry.build(
          context,
          UiNode(
            id: 1,
            kind: props is SliverFixedExtentProps
                ? NodeKind.sliverFixedExtent
                : NodeKind.sliverVariedExtent,
            props: props,
            eventBindings: const [],
            parentData: const NoParentData(),
            children: const [],
            localRevision: 0,
            deliveryGeneration: 1,
          ),
          const [],
          null,
        ),
        throwsA(
          isA<RendererBuildException>().having(
            (error) => error.message,
            'message',
            contains('logical list'),
          ),
        ),
      );
    }
  });

  // The OCaml side derives the viewport cache_extent as the maximum child
  // overscan times item extent. The renderer forwards that value so Flutter's
  // cache and the application-owned materialized windows use one policy.
  testWidgets('scroll view forwards cache_extent to CustomScrollView', (
    tester,
  ) async {
    final children = List.generate(
      20,
      (index) => CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Item ${100 + index}'),
        eventBindings: const [],
      ),
    );
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const SetApplicationTheme(
              title: 'Test',
              theme: testApplicationTheme,
            ),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.scrollView,
              props: const ScrollViewProps(
                axis: ScrollAxis.vertical,
                reverse: false,
                cacheExtent: 192.0,
              ),
              eventBindings: const [],
            ),
            CreateNode(
              nodeId: 100,
              kind: NodeKind.sliverFixedExtent,
              props: const SliverFixedExtentProps(
                totalCount: 50000,
                firstIndex: 100,
                itemExtent: 48,
                overscan: 4,
              ),
              eventBindings: const [],
            ),
            ...children,
            SetChildren(
              nodeId: 100,
              children: List.generate(20, (index) => index + 2),
            ),
            SetChildren(nodeId: 1, children: const [100]),
            const SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.scrollCacheExtent, isNotNull);
    expect(scrollView.scrollCacheExtent!.value, 192.0);
  });

  testWidgets('scroll view leaves cache_extent null when not provided', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const SetApplicationTheme(
              title: 'Test',
              theme: testApplicationTheme,
            ),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.scrollView,
              props: const ScrollViewProps(
                axis: ScrollAxis.vertical,
                reverse: false,
              ),
              eventBindings: const [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.sliverBox,
              props: const EmptyProps(),
              eventBindings: const [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: const TextProps('Hi'),
              eventBindings: const [],
            ),
            SetChildren(nodeId: 2, children: const [3]),
            SetChildren(nodeId: 1, children: const [2]),
            const SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.scrollCacheExtent, isNull);
  });

  testWidgets('scroll view rejects invalid cache extents at render time', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
            CreateNode(
              nodeId: 99,
              kind: NodeKind.text,
              props: TextProps('root'),
              eventBindings: [],
            ),
            SetRoot(99),
          ],
        ),
      );
    final resources = RendererResourceStore()..synchronize(store);
    addTearDown(resources.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      RendererResourceScope(
        resources: resources,
        child: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final registry = WidgetRegistry.standard();

    for (final invalid in const [-1.0, double.nan, double.infinity]) {
      expect(
        () => registry.build(
          context,
          UiNode(
            id: 1,
            kind: NodeKind.scrollView,
            props: ScrollViewProps(
              axis: ScrollAxis.vertical,
              reverse: false,
              cacheExtent: invalid,
            ),
            eventBindings: const [],
            parentData: const NoParentData(),
            children: const [],
            localRevision: 1,
            deliveryGeneration: 1,
          ),
          const [],
          null,
        ),
        throwsA(isA<RendererBuildException>()),
        reason: 'invalid cache extent was accepted: $invalid',
      );
    }
  });
}

const _virtualNodeId = 100;

enum _VirtualSliverKind {
  fixed('sliver fixed extent'),
  varied('sliver varied extent');

  const _VirtualSliverKind(this.label);

  final String label;
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _virtualSliverView(NodeStore store) => MaterialApp(
  home: SizedBox(
    width: 400,
    height: 200,
    child: BonsaiFlutterView(store: store),
  ),
);

Widget _virtualSliverViewWithEvents(
  NodeStore store,
  RendererEventCallback onEvent,
) => MaterialApp(
  home: SizedBox(
    width: 400,
    height: 200,
    child: BonsaiFlutterView(store: store, onEvent: onEvent),
  ),
);

ScrollPosition _scrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

SliverVariedExtentProps _variedProps({
  required int totalCount,
  required int firstIndex,
  required double itemExtent,
  List<SparseExtentOverride> extentOverrides = const [],
  SparseExtentTransition? transition,
}) => SliverVariedExtentProps(
  totalCount: totalCount,
  firstIndex: firstIndex,
  defaultItemExtent: itemExtent,
  overscan: 0,
  extentOverrides: extentOverrides,
  transition: transition,
);

NodeStore _virtualSliverStore({
  required _VirtualSliverKind kind,
  required int totalCount,
  required int firstIndex,
  required double itemExtent,
  required int childCount,
  double headerExtent = 0,
  List<SparseExtentOverride> extentOverrides = const [],
  SparseExtentTransition? transition,
  bool bindVisibleRange = false,
}) => NodeStore()
  ..apply(
    _virtualSliverFrame(
      kind: kind,
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
      childCount: childCount,
      headerExtent: headerExtent,
      extentOverrides: extentOverrides,
      transition: transition,
      bindVisibleRange: bindVisibleRange,
    ),
  );

Frame _virtualSliverFrame({
  required _VirtualSliverKind kind,
  required int totalCount,
  required int firstIndex,
  required double itemExtent,
  required int childCount,
  double headerExtent = 0,
  List<SparseExtentOverride> extentOverrides = const [],
  SparseExtentTransition? transition,
  bool bindVisibleRange = false,
  int runtimeEpoch = 1,
}) {
  final childNodes = [
    for (var index = 0; index < childCount; index += 1)
      CreateNode(
        nodeId: 1000 + index,
        kind: NodeKind.text,
        props: TextProps('Item ${firstIndex + index}'),
        eventBindings: const [],
      ),
  ];
  final virtualProps = switch (kind) {
    _VirtualSliverKind.fixed => SliverFixedExtentProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
      overscan: 0,
    ),
    _VirtualSliverKind.varied => _variedProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
      extentOverrides: extentOverrides,
      transition: transition,
    ),
  };
  final operations = <FrameOperation>[
    CreateNode(
      nodeId: 1,
      kind: NodeKind.scrollView,
      props: const ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
      eventBindings: const [],
    ),
    if (headerExtent > 0) ...[
      CreateNode(
        nodeId: 2,
        kind: NodeKind.sliverBox,
        props: const EmptyProps(),
        eventBindings: const [],
      ),
      CreateNode(
        nodeId: 3,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: null, height: headerExtent),
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 4,
        kind: NodeKind.text,
        props: TextProps('Header'),
        eventBindings: [],
      ),
    ],
    CreateNode(
      nodeId: _virtualNodeId,
      kind: kind == _VirtualSliverKind.fixed
          ? NodeKind.sliverFixedExtent
          : NodeKind.sliverVariedExtent,
      props: virtualProps,
      eventBindings: bindVisibleRange
          ? const [
              EventBinding(
                eventTag: EventTagId.visibleRangeChanged,
                handlerId: 1,
              ),
            ]
          : const [],
    ),
    ...childNodes,
    if (headerExtent > 0) ...[
      const SetChildren(nodeId: 2, children: [3]),
      const SetChildren(nodeId: 3, children: [4]),
    ],
    if (childNodes.isNotEmpty)
      SetChildren(
        nodeId: _virtualNodeId,
        children: [
          for (var index = 0; index < childCount; index += 1) 1000 + index,
        ],
      ),
    SetChildren(nodeId: 1, children: [if (headerExtent > 0) 2, _virtualNodeId]),
    const SetRoot(1),
  ];
  return Frame(
    runtimeEpoch: runtimeEpoch,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: [
      const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
      ...operations,
    ],
  );
}

Finder _hostFinder(_VirtualSliverKind kind) => switch (kind) {
  _VirtualSliverKind.fixed => find.byType(
    SliverFixedExtentHost,
    skipOffstage: false,
  ),
  _VirtualSliverKind.varied => find.byType(
    SliverVariedExtentHost,
    skipOffstage: false,
  ),
};

List<VisibleRangeEventPayload> _visibleRangeEvents(
  List<RendererEvent> events,
) => [
  for (final event in events)
    if (event.payload case final VisibleRangeEventPayload payload) payload,
];

NodeStore _twoVirtualSliverStore({
  required _VirtualSliverKind firstKind,
  required _VirtualSliverKind secondKind,
  required int firstIndex,
  required int secondIndex,
  bool primary = false,
}) {
  const totalCount = 30;
  const itemExtent = 50.0;
  UiProps props(_VirtualSliverKind kind, int firstIndex) => switch (kind) {
    _VirtualSliverKind.fixed => SliverFixedExtentProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
      overscan: 0,
    ),
    _VirtualSliverKind.varied => _variedProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
    ),
  };

  final operations = <FrameOperation>[
    CreateNode(
      nodeId: 1,
      kind: NodeKind.scrollView,
      props: ScrollViewProps(
        axis: ScrollAxis.vertical,
        reverse: false,
        primary: primary,
      ),
      eventBindings: const [],
    ),
    CreateNode(
      nodeId: 100,
      kind: firstKind == _VirtualSliverKind.fixed
          ? NodeKind.sliverFixedExtent
          : NodeKind.sliverVariedExtent,
      props: props(firstKind, firstIndex),
      eventBindings: const [],
    ),
    CreateNode(
      nodeId: 200,
      kind: secondKind == _VirtualSliverKind.fixed
          ? NodeKind.sliverFixedExtent
          : NodeKind.sliverVariedExtent,
      props: props(secondKind, secondIndex),
      eventBindings: const [],
    ),
    for (var index = 0; index < 10; index += 1)
      CreateNode(
        nodeId: 1000 + index,
        kind: NodeKind.text,
        props: TextProps('First ${firstIndex + index}'),
        eventBindings: const [],
      ),
    for (var index = 0; index < 10; index += 1)
      CreateNode(
        nodeId: 2000 + index,
        kind: NodeKind.text,
        props: TextProps('Second ${secondIndex + index}'),
        eventBindings: const [],
      ),
    SetChildren(
      nodeId: 100,
      children: [for (var index = 0; index < 10; index += 1) 1000 + index],
    ),
    SetChildren(
      nodeId: 200,
      children: [for (var index = 0; index < 10; index += 1) 2000 + index],
    ),
    const SetChildren(nodeId: 1, children: [100, 200]),
    const SetRoot(1),
  ];
  return NodeStore()..apply(
    Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
        ...operations,
      ],
    ),
  );
}

final class _CountingOverrideList extends ListBase<SparseExtentOverride> {
  _CountingOverrideList(this._values);

  final List<SparseExtentOverride> _values;
  int readCount = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  SparseExtentOverride operator [](int index) {
    readCount += 1;
    return _values[index];
  }

  @override
  void operator []=(int index, SparseExtentOverride value) =>
      throw UnsupportedError('immutable');
}

final class _CountingWidgetList extends ListBase<Widget> {
  _CountingWidgetList(this._values);

  final List<Widget> _values;
  int readCount = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  Widget operator [](int index) {
    readCount += 1;
    return _values[index];
  }

  @override
  void operator []=(int index, Widget value) =>
      throw UnsupportedError('immutable');
}
