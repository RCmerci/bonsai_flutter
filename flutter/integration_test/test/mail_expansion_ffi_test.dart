import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets('mail expansion flows round trip through real OCaml FFI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(config: Uint8List.fromList(utf8.encode('mail'))),
        'RuntimeClient.start',
      ),
    );
    expect(client, isNotNull);
    final harness = RuntimeHarness(client!);
    addTearDown(() => _bounded(harness.dispose(), 'RuntimeHarness.dispose'));
    final initialCycle = await tester.runAsync(
      () => _bounded(harness.grant(), 'initial mail grant'),
    );
    final initial = FrameCodec.decode(initialCycle!.bytes);
    final store = NodeStore()..apply(initial);
    final queue = EventBatchQueue(
      runtimeEpoch: initial.runtimeEpoch,
      displayedRevision: () => store.revision,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      queue.pendingCount,
      greaterThan(0),
      reason: 'virtual inbox did not emit its initial visible range',
    );
    await _advance(tester, harness, store, queue, 'initial visible range');

    final semantics = tester.ensureSemantics();
    for (final label in ['Mail', 'Chat', 'Spaces', 'Meet']) {
      final destination = find.bySemanticsLabel(label);
      expect(destination, findsOneWidget);
      final size = tester.getSize(destination);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Mail'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    final drawerGesture = await tester.startGesture(const Offset(5, 180));
    await drawerGesture.moveBy(const Offset(180, 0));
    await tester.pump();
    expect(queue.pendingCount, 0, reason: 'drawer tracking crossed FFI');
    await drawerGesture.moveBy(const Offset(160, 0));
    await drawerGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Bonsai Mail'), findsWidgets);
    await _advance(tester, harness, store, queue, 'drawer settled open');

    await tester.tapAt(const Offset(380, 180));
    await tester.pumpAndSettle();
    await _advance(tester, harness, store, queue, 'drawer scrim close');

    await tester.tap(find.bySemanticsLabel('Chat'));
    await tester.pump();
    await _advance(tester, harness, store, queue, 'select Chat');
    expect(
      find.text('Chat is outside the scope of this local mail demo.'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Mail'));
    await tester.pump();
    await _advance(tester, harness, store, queue, 'restore Mail');
    expect(find.text('Juniper Works'), findsOneWidget);

    final press = await tester.startGesture(
      tester.getCenter(find.text('Juniper Works')),
    );
    await tester.pump();
    expect(queue.pendingCount, 0, reason: 'pointer down crossed FFI');
    await press.up();
    await tester.pump(const Duration(milliseconds: 79));
    expect(
      queue.pendingCount,
      0,
      reason: 'activation skipped visible feedback',
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(queue.pendingCount, 1);
    await _advance(tester, harness, store, queue, 'expand inline card');
    await tester.pumpAndSettle();
    final detailBody = find.textContaining(
      'The guide for Saturday',
      findRichText: true,
    );
    expect(detailBody, findsNothing);
    expect(
      find.text('Everything for the miniature landscape session is attached.'),
      findsAtLeastNWidgets(1),
    );
    final open = find.bySemanticsLabel('Open message from Juniper Works');
    expect(open, findsOneWidget);
    final openSize = tester.getSize(open);
    expect(openSize.width, greaterThanOrEqualTo(48));
    expect(openSize.height, greaterThanOrEqualTo(48));
    await tester.tap(open);
    await tester.pump(const Duration(milliseconds: 80));
    await _advance(tester, harness, store, queue, 'Open card to detail');
    expect(detailBody, findsOneWidget);
    expect(find.bySemanticsLabel('Mail'), findsOneWidget);
    await tester.pumpAndSettle();

    final popGesture = await tester.startGesture(const Offset(5, 180));
    await popGesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await popGesture.moveBy(const Offset(276, 0));
    await popGesture.up();
    await tester.pumpAndSettle();
    await _advance(tester, harness, store, queue, 'detail edge pop');
    expect(detailBody, findsNothing);
    expect(find.bySemanticsLabel('Mail'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open message from Juniper Works'),
      findsOneWidget,
      reason: 'Back did not restore the same expanded card',
    );
    expect(_sparseProps(store).extentOverrides, hasLength(1));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final offsetBefore = scrollable.position.pixels;
    await _advance(tester, harness, store, queue, 'tail visible range');
    expect(_hasLoadingMoreSemantics(store), isTrue);
    expect(
      _sparseProps(store).extentOverrides,
      hasLength(1),
      reason: 'pagination dropped the expanded extent override',
    );
    expect(scrollable.position.pixels, offsetBefore);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await _advance(tester, harness, store, queue, 'append timer');
    expect(_hasLoadingMoreSemantics(store), isFalse);
    expect(scrollable.position.pixels, offsetBefore);
    expect(_hasTextContaining(store, 'Field Dispatch 21'), isTrue);
    semantics.dispose();
    harness.acknowledge();
  });
}

bool _hasLoadingMoreSemantics(NodeStore store) => store.nodes.values.any(
  (node) =>
      node.props is SemanticsProps &&
      (node.props as SemanticsProps).label == 'Loading more messages',
);

SparseExtentListProps _sparseProps(NodeStore store) {
  final node = store.nodes.values.singleWhere(
    (node) =>
        node.props is NativeWidgetProps &&
        (node.props as NativeWidgetProps).kindId ==
            NativeWidgetKind.sparseExtentList,
  );
  expect((node.props as NativeWidgetProps).version, 2);
  return SparseExtentListProps.decode(
    (node.props as NativeWidgetProps).payload,
  );
}

bool _hasTextContaining(NodeStore store, String value) =>
    store.nodes.values.any(
      (node) =>
          node.props is TextProps &&
          (node.props as TextProps).value.contains(value),
    );

Future<void> _advance(
  WidgetTester tester,
  RuntimeHarness harness,
  NodeStore store,
  EventBatchQueue queue,
  String operation,
) async {
  final batch = queue.takeBatch();
  final cycle = await tester.runAsync(
    () => _bounded(
      harness.advance(
        events: batch == null ? null : EventBatchCodec.encode(batch),
      ),
      operation,
    ),
  );
  if (cycle!.bytes.isNotEmpty) {
    store.apply(FrameCodec.decode(cycle.bytes));
  }
  await tester.pump();
}
