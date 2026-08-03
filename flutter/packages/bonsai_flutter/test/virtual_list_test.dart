import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('50000 item virtual list mounts only its supplied window', (
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
            CreateNode(
              nodeId: 1,
              kind: NodeKind.nativeWidget,
              props: VirtualListProps(
                totalCount: 50000,
                firstIndex: 100,
                itemExtent: 48,
                overscan: 4,
                axis: ScrollAxis.vertical,
              ).toNativeWidgetProps(),
              eventBindings: const [
                EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 11),
              ],
            ),
            ...children,
            SetChildren(
              nodeId: 1,
              children: List.generate(20, (index) => index + 2),
            ),
            const SetRoot(1),
          ],
        ),
      );
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 240,
          child: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NodeHost).evaluate().length, lessThanOrEqualTo(21));
    expect(find.text('Item 100'), findsOneWidget);
    expect(find.text('Item 49999'), findsNothing);
    expect(events, isNotEmpty);
    final range = events.last.payload as NativeEventPayload;
    expect(range.kindId, NativeWidgetKind.virtualList);
    expect(range.eventId, VirtualListEvent.visibleRangeChanged);
    final decoded = VirtualListEvent.decodeVisibleRange(range.payload);
    expect(decoded.firstIndex, greaterThanOrEqualTo(100));
    expect(decoded.lastExclusive, lessThanOrEqualTo(120));

    await tester.drag(find.byType(Scrollable), const Offset(0, -192));
    await tester.pump();
    final afterScroll = VirtualListEvent.decodeVisibleRange(
      (events.last.payload as NativeEventPayload).payload,
    );
    expect(afterScroll.firstIndex, greaterThan(100));

    final retainedElement = tester.element(find.text('Item 104'));
    store.apply(
      Frame(
        runtimeEpoch: 1,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(
            nodeId: 1,
            props: VirtualListProps(
              totalCount: 50000,
              firstIndex: 104,
              itemExtent: 48,
              overscan: 4,
              axis: ScrollAxis.vertical,
            ).toNativeWidgetProps(),
          ),
          for (var index = 120; index < 124; index += 1)
            CreateNode(
              nodeId: index - 98,
              kind: NodeKind.text,
              props: TextProps('Item $index'),
              eventBindings: const [],
            ),
          SetChildren(
            nodeId: 1,
            children: List.generate(20, (index) => index + 6),
          ),
          for (var nodeId = 2; nodeId < 6; nodeId += 1) DropNode(nodeId),
        ],
      ),
    );
    await tester.pump();

    expect(
      identical(tester.element(find.text('Item 104')), retainedElement),
      isTrue,
    );
  });

  test('virtual list props validate the logical window', () {
    expect(
      () => VirtualListProps(
        totalCount: 10,
        firstIndex: 9,
        itemExtent: 48,
        overscan: 2,
        axis: ScrollAxis.vertical,
      ).validateChildCount(2),
      throwsArgumentError,
    );
  });

  testWidgets(
    'fast scroll reports the logical range beyond the supplied window',
    (tester) async {
      final children = List.generate(
        24,
        (index) => CreateNode(
          nodeId: index + 2,
          kind: NodeKind.text,
          props: TextProps('Item $index'),
          eventBindings: const [],
        ),
      );
      final store = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 2,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              CreateNode(
                nodeId: 1,
                kind: NodeKind.nativeWidget,
                props: VirtualListProps(
                  totalCount: 100,
                  firstIndex: 0,
                  itemExtent: 48,
                  overscan: 4,
                  axis: ScrollAxis.vertical,
                ).toNativeWidgetProps(),
                eventBindings: const [
                  EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 12),
                ],
              ),
              ...children,
              SetChildren(
                nodeId: 1,
                children: List.generate(24, (index) => index + 2),
              ),
              const SetRoot(1),
            ],
          ),
        );
      final events = <RendererEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 240,
            child: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      await tester.pump();

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(48 * 36);
      await tester.pump();
      final range = VirtualListEvent.decodeVisibleRange(
        (events.last.payload as NativeEventPayload).payload,
      );

      expect(range.firstIndex, greaterThanOrEqualTo(36));
      expect(range.lastExclusive, greaterThan(range.firstIndex));
    },
  );

  testWidgets(
    'window catch-up fills fast-scroll viewport without offset jump',
    (tester) async {
      List<CreateNode> children(int first, int nodeBase) => List.generate(
        24,
        (index) => CreateNode(
          nodeId: nodeBase + index,
          kind: NodeKind.text,
          props: TextProps('Item ${first + index}'),
          eventBindings: const [],
        ),
      );
      final initialChildren = children(0, 2);
      final store = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 3,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              CreateNode(
                nodeId: 1,
                kind: NodeKind.nativeWidget,
                props: VirtualListProps(
                  totalCount: 100,
                  firstIndex: 0,
                  itemExtent: 48,
                  overscan: 4,
                  axis: ScrollAxis.vertical,
                ).toNativeWidgetProps(),
                eventBindings: const [],
              ),
              ...initialChildren,
              SetChildren(
                nodeId: 1,
                children: List.generate(24, (index) => index + 2),
              ),
              const SetRoot(1),
            ],
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(height: 240, child: BonsaiFlutterView(store: store)),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(48 * 36);
      await tester.pump();
      final offsetBefore = position.pixels;

      final nextChildren = children(32, 26);
      store.apply(
        Frame(
          runtimeEpoch: 3,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: 1,
              props: VirtualListProps(
                totalCount: 100,
                firstIndex: 32,
                itemExtent: 48,
                overscan: 4,
                axis: ScrollAxis.vertical,
              ).toNativeWidgetProps(),
            ),
            ...nextChildren,
            SetChildren(
              nodeId: 1,
              children: List.generate(24, (index) => index + 26),
            ),
            for (var nodeId = 2; nodeId < 26; nodeId += 1) DropNode(nodeId),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Item 36'), findsOneWidget);
      expect(position.pixels, offsetBefore);

      store.apply(
        Frame(
          runtimeEpoch: 3,
          baseRevision: 2,
          targetRevision: 3,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: 1,
              props: VirtualListProps(
                totalCount: 100,
                firstIndex: 32,
                itemExtent: 48,
                overscan: 4,
                axis: ScrollAxis.vertical,
              ).toNativeWidgetProps(),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(position.pixels, offsetBefore);
      expect(find.text('Item 36'), findsOneWidget);
    },
  );

  test('sparse extent props round trip and reject malformed payloads', () {
    const props = SparseExtentListProps(
      totalCount: 50000,
      firstIndex: 40,
      defaultItemExtent: 48,
      extentOverrides: [
        ExtentOverride(index: 3, extent: 120),
        ExtentOverride(index: 42, extent: 312),
      ],
      overscan: 5,
      axis: ScrollAxis.vertical,
    );
    final native = props.toNativeWidgetProps();
    expect(native.kindId, NativeWidgetKind.sparseExtentList);
    expect(native.version, 1);
    expect(native.payload, hasLength(68));
    expect(SparseExtentListProps.decode(native.payload), props);

    expect(
      () => SparseExtentListProps.decode(
        Uint8List.sublistView(native.payload, 0, native.payload.length - 1),
      ),
      throwsFormatException,
    );
    expect(
      () => SparseExtentListProps.decode(
        Uint8List.fromList([...native.payload, 0]),
      ),
      throwsFormatException,
    );
    final badReserved = Uint8List.fromList(native.payload)..[29] = 1;
    expect(
      () => SparseExtentListProps.decode(badReserved),
      throwsFormatException,
    );
    final badAxis = Uint8List.fromList(native.payload)..[28] = 2;
    expect(() => SparseExtentListProps.decode(badAxis), throwsFormatException);
    final badCount = Uint8List.fromList(native.payload);
    ByteData.sublistView(badCount).setUint32(32, 3, Endian.little);
    expect(() => SparseExtentListProps.decode(badCount), throwsFormatException);
  });

  test(
    'sparse extent transition uses an explicit backward-compatible v2 payload',
    () {
      const transition = SparseExtentTransitionSpec(
        expandDuration: Duration(milliseconds: 240),
        collapseDuration: Duration(milliseconds: 190),
        expandCurve: SparseExtentTransitionCurve.easeOutCubic,
        collapseCurve: SparseExtentTransitionCurve.easeInOutCubic,
      );
      const props = SparseExtentListProps(
        totalCount: 20,
        firstIndex: 4,
        defaultItemExtent: 88,
        extentOverrides: [ExtentOverride(index: 6, extent: 320)],
        overscan: 4,
        axis: ScrollAxis.vertical,
        transition: transition,
      );

      final native = props.toNativeWidgetProps();
      expect(native.version, 2);
      expect(native.payload, hasLength(64));
      expect(SparseExtentListProps.decode(native.payload), props);

      final badEnabled = Uint8List.fromList(native.payload)..[46] = 2;
      expect(
        () => SparseExtentListProps.decode(badEnabled),
        throwsFormatException,
      );
      final badCurve = Uint8List.fromList(native.payload)..[44] = 99;
      expect(
        () => SparseExtentListProps.decode(badCurve),
        throwsFormatException,
      );
      final badReserved = Uint8List.fromList(native.payload)..[47] = 1;
      expect(
        () => SparseExtentListProps.decode(badReserved),
        throwsFormatException,
      );
    },
  );

  test('sparse extent transition validates duration bounds', () {
    expect(
      () => SparseExtentTransitionSpec(
        expandDuration: const Duration(milliseconds: -1),
        collapseDuration: Duration.zero,
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => SparseExtentTransitionSpec(
        expandDuration: const Duration(milliseconds: 0x100000000),
        collapseDuration: Duration.zero,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('sparse extent props validate indexes, ordering, and extents', () {
    SparseExtentListProps props({
      int totalCount = 10,
      int firstIndex = 0,
      double defaultItemExtent = 48,
      List<ExtentOverride> overrides = const [],
      int overscan = 2,
    }) => SparseExtentListProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      defaultItemExtent: defaultItemExtent,
      extentOverrides: overrides,
      overscan: overscan,
      axis: ScrollAxis.vertical,
    );

    for (final invalid in <SparseExtentListProps>[
      props(totalCount: -1),
      props(firstIndex: 11),
      props(defaultItemExtent: double.nan),
      props(defaultItemExtent: 0),
      props(overscan: -1),
      props(overrides: const [ExtentOverride(index: -1, extent: 80)]),
      props(overrides: const [ExtentOverride(index: 10, extent: 80)]),
      props(
        overrides: const [
          ExtentOverride(index: 4, extent: 80),
          ExtentOverride(index: 3, extent: 90),
        ],
      ),
      props(
        overrides: const [
          ExtentOverride(index: 3, extent: 80),
          ExtentOverride(index: 3, extent: 90),
        ],
      ),
      props(
        overrides: const [ExtentOverride(index: 3, extent: double.infinity)],
      ),
      props(overrides: const [ExtentOverride(index: 3, extent: 0)]),
    ]) {
      expect(() => invalid.validateChildCount(0), throwsArgumentError);
    }
    expect(
      () => props(totalCount: 2, firstIndex: 1).validateChildCount(2),
      throwsArgumentError,
    );
  });

  test('sparse extent geometry is correct around multiple tall items', () {
    final geometry = SparseExtentGeometry(
      totalCount: 10,
      defaultItemExtent: 50,
      extentOverrides: [
        ExtentOverride(index: 2, extent: 150),
        ExtentOverride(index: 6, extent: 100),
      ],
    );

    expect(geometry.leadingOffset(0), 0);
    expect(geometry.leadingOffset(2), 100);
    expect(geometry.leadingOffset(3), 250);
    expect(geometry.leadingOffset(6), 400);
    expect(geometry.leadingOffset(7), 500);
    expect(geometry.totalExtent, 650);
    expect(geometry.itemExtent(2), 150);
    expect(geometry.itemExtent(5), 50);

    expect(geometry.visibleRange(offset: 0, viewportExtent: 100), (
      firstIndex: 0,
      lastExclusive: 2,
    ));
    expect(geometry.visibleRange(offset: 125, viewportExtent: 50), (
      firstIndex: 2,
      lastExclusive: 3,
    ));
    expect(geometry.visibleRange(offset: 250, viewportExtent: 150), (
      firstIndex: 3,
      lastExclusive: 6,
    ));
    expect(geometry.visibleRange(offset: 425, viewportExtent: 50), (
      firstIndex: 6,
      lastExclusive: 7,
    ));
    expect(geometry.visibleRange(offset: 650, viewportExtent: 50), (
      firstIndex: 10,
      lastExclusive: 10,
    ));
  });

  testWidgets(
    'sparse list keeps mounts bounded and anchors an extent change above viewport',
    (tester) async {
      List<CreateNode> children(int first, int count) => List.generate(
        count,
        (index) => CreateNode(
          nodeId: first + index + 2,
          kind: NodeKind.text,
          props: TextProps('Sparse ${first + index}'),
          eventBindings: const [],
        ),
      );

      const oldProps = SparseExtentListProps(
        totalCount: 100,
        firstIndex: 0,
        defaultItemExtent: 48,
        extentOverrides: [ExtentOverride(index: 2, extent: 144)],
        overscan: 4,
        axis: ScrollAxis.vertical,
      );
      final initialChildren = children(0, 24);
      final store = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 4,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: [
              CreateNode(
                nodeId: 1,
                kind: NodeKind.nativeWidget,
                props: oldProps.toNativeWidgetProps(),
                eventBindings: const [
                  EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 13),
                ],
              ),
              ...initialChildren,
              SetChildren(
                nodeId: 1,
                children: List.generate(24, (index) => index + 2),
              ),
              const SetRoot(1),
            ],
          ),
        );
      final events = <RendererEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 240,
            child: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NodeHost).evaluate().length, lessThanOrEqualTo(25));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final oldGeometry = SparseExtentGeometry(
        totalCount: 100,
        defaultItemExtent: 48,
        extentOverrides: [ExtentOverride(index: 2, extent: 144)],
      );
      position.jumpTo(oldGeometry.leadingOffset(10) + 7);
      await tester.pump();
      expect(events, isNotEmpty);
      final beforeUpdate = events.last.payload as NativeEventPayload;
      expect(beforeUpdate.kindId, NativeWidgetKind.sparseExtentList);
      final beforeRange = VirtualListEvent.decodeVisibleRange(
        beforeUpdate.payload,
      );
      expect(beforeRange.firstIndex, 10);
      expect(beforeRange.lastExclusive, greaterThan(10));
      events.clear();

      const newProps = SparseExtentListProps(
        totalCount: 100,
        firstIndex: 4,
        defaultItemExtent: 48,
        extentOverrides: [ExtentOverride(index: 2, extent: 240)],
        overscan: 4,
        axis: ScrollAxis.vertical,
      );
      final nextChildren = children(24, 4);
      final retainedElement = tester.element(find.text('Sparse 10'));
      store.apply(
        Frame(
          runtimeEpoch: 4,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(nodeId: 1, props: newProps.toNativeWidgetProps()),
            ...nextChildren,
            SetChildren(
              nodeId: 1,
              children: List.generate(24, (index) => index + 6),
            ),
            for (var nodeId = 2; nodeId < 6; nodeId += 1) DropNode(nodeId),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final newGeometry = SparseExtentGeometry(
        totalCount: 100,
        defaultItemExtent: 48,
        extentOverrides: [ExtentOverride(index: 2, extent: 240)],
      );
      expect(position.pixels, newGeometry.leadingOffset(10) + 7);
      expect(
        identical(tester.element(find.text('Sparse 10')), retainedElement),
        isTrue,
      );
      expect(
        events,
        isEmpty,
        reason: 'anchor correction emitted a transient or duplicate range',
      );
    },
  );

  testWidgets('sparse list starts at the exact logical leading offset', (
    tester,
  ) async {
    const props = SparseExtentListProps(
      totalCount: 20,
      firstIndex: 5,
      defaultItemExtent: 40,
      extentOverrides: [ExtentOverride(index: 2, extent: 100)],
      overscan: 2,
      axis: ScrollAxis.vertical,
    );
    final children = List.generate(
      5,
      (index) => CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps('Initial ${index + 5}'),
        eventBindings: const [],
      ),
    );
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 5,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.nativeWidget,
              props: props.toNativeWidgetProps(),
              eventBindings: const [],
            ),
            ...children,
            SetChildren(
              nodeId: 1,
              children: List.generate(5, (index) => index + 2),
            ),
            const SetRoot(1),
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 160, child: BonsaiFlutterView(store: store)),
      ),
    );

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, 260);
    expect(find.text('Initial 5'), findsOneWidget);
  });
}
