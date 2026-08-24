import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  testWidgets('mail Slidable round trips through real OCaml FFI', (
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
    expect(initialCycle, isNotNull);
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
    expect(tester.takeException(), isNull);
    expect(find.byType(RendererLayoutError), findsNothing);
    final unsupported = tester
        .widgetList<UnsupportedNativeWidget>(
          find.byType(UnsupportedNativeWidget),
        )
        .map((widget) => widget.message)
        .toList();
    expect(unsupported, isEmpty, reason: unsupported.join('\n'));
    final listViewport = tester.getSize(find.byType(CustomScrollView).first);
    expect(listViewport.height, greaterThan(0));
    expect(listViewport.height.isFinite, isTrue);
    final initialRangeBatch = queue.takeBatch();
    expect(initialRangeBatch, isNotNull);
    final initialRangeResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(initialRangeBatch!)),
        'initial visible-range pump',
      ),
    );
    if (initialRangeResponse!.bytes.isNotEmpty) {
      store.apply(FrameCodec.decode(initialRangeResponse.bytes));
    }
    await tester.pump();
    final followingElement = tester.element(find.text('River Tan'));
    final archiveGesture = await tester.startGesture(
      tester.getCenter(find.text('Mara Vale')),
    );
    await archiveGesture.moveBy(const Offset(140, 0));
    await tester.pump();
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    final duringDrag = queue.takeBatch();
    expect(
      duringDrag?.events.where(
        (event) => event.eventTag == EventTagId.nativeEvent,
      ),
      anyOf(isNull, isEmpty),
      reason: 'drag deltas must not use native events',
    );
    await archiveGesture.up();
    await tester.pumpAndSettle();
    final afterReveal = queue.takeBatch();
    expect(
      afterReveal?.events.where(
        (event) => event.eventTag == EventTagId.nativeEvent,
      ),
      anyOf(isNull, isEmpty),
      reason: 'revealing an action pane must not emit a native event',
    );
    await tester.tap(find.text('Archive'));
    await tester.pump();
    expect(queue.pendingCount, 1);

    final slidableBatch = queue.takeBatch()!;
    expect(slidableBatch.events, hasLength(1));
    expect(slidableBatch.events.single.eventTag, EventTagId.nativeEvent);
    final nativePayload =
        slidableBatch.events.single.payload as NativeEventPayload;
    expect(nativePayload.kindId, 2);
    expect(nativePayload.version, 3);
    expect(nativePayload.eventId, 1);
    expect(nativePayload.payload, [1, 0, 0, 0]);

    final archiveResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(slidableBatch)),
        'archive Slidable pump',
      ),
    );
    final archiveFrame = FrameCodec.decode(archiveResponse!.bytes);
    expect(archiveFrame.kind, FrameKind.incremental);
    store.apply(archiveFrame);
    await tester.pump();

    expect(find.text('Mara Vale'), findsNothing);
    expect(
      identical(tester.element(find.text('River Tan')), followingElement),
      isTrue,
    );
    expect(find.text('The field notes are ready'), findsNothing);

    harness.acknowledge();
  });
}
