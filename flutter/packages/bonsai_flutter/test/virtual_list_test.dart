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
}
