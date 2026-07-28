import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets('mail swipe and edge pop round trip through real OCaml FFI', (
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
    final runtime = client!;
    addTearDown(() => _bounded(runtime.dispose(), 'RuntimeClient.dispose'));

    final initialResponse = await tester.runAsync(
      () => _bounded(runtime.step(Uint8List(0)), 'initial mail step'),
    );
    expect(initialResponse, isNotNull);
    expect(initialResponse!.status, RuntimeStatus.ok);
    final initial = FrameCodec.decode(initialResponse.bytes);
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
    await _present(
      tester,
      runtime,
      initial.targetRevision,
      'initial mail frame',
    );

    final followingElement = tester.element(find.text('River Tan'));
    final archiveGesture = await tester.startGesture(
      tester.getCenter(find.text('Mara Vale')),
    );
    await archiveGesture.moveBy(const Offset(140, 0));
    await tester.pump();
    final duringDrag = queue.takeBatch();
    expect(
      duringDrag?.events.where(
        (event) => event.eventTag == EventTagId.nativeEvent,
      ),
      anyOf(isNull, isEmpty),
      reason: 'drag deltas must not use native events',
    );
    await archiveGesture.up();
    final beforeSettle = queue.takeBatch();
    expect(
      beforeSettle?.events.where(
        (event) => event.eventTag == EventTagId.nativeEvent,
      ),
      anyOf(isNull, isEmpty),
      reason: 'commit waits for local dismiss settle',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(queue.pendingCount, 1);

    final swipeBatch = queue.takeBatch()!;
    expect(swipeBatch.events, hasLength(1));
    expect(swipeBatch.events.single.eventTag, EventTagId.nativeEvent);
    final nativePayload =
        swipeBatch.events.single.payload as NativeEventPayload;
    expect(nativePayload.kindId, 2);
    expect(nativePayload.version, 1);
    expect(nativePayload.eventId, 1);
    expect(nativePayload.payload, [0]);

    final archiveResponse = await tester.runAsync(
      () => _bounded(runtime.sendEventBatch(swipeBatch), 'archive swipe event'),
    );
    final archiveFrame = FrameCodec.decode(archiveResponse!.bytes);
    expect(archiveFrame.kind, FrameKind.incremental);
    store.apply(archiveFrame);
    await tester.pump();
    await _present(
      tester,
      runtime,
      archiveFrame.targetRevision,
      'archive mail frame',
    );

    expect(find.text('Mara Vale'), findsNothing);
    expect(
      identical(tester.element(find.text('River Tan')), followingElement),
      isTrue,
    );
    expect(find.text('The field notes are ready'), findsNothing);

    await tester.tap(find.text('Juniper Works'));
    await tester.pump();
    final openBatch = queue.takeBatch()!;
    final openResponse = await tester.runAsync(
      () => _bounded(runtime.sendEventBatch(openBatch), 'open mail detail'),
    );
    final openFrame = FrameCodec.decode(openResponse!.bytes);
    store.apply(openFrame);
    await tester.pump();
    final detailBody = find.textContaining(
      'The guide for Saturday',
      findRichText: true,
    );
    expect(detailBody, findsOneWidget);
    expect(tester.getTopLeft(detailBody).dx, greaterThan(0));
    await tester.pumpAndSettle();
    final detailRoute =
        ModalRoute.of(tester.element(detailBody))! as PageRoute<void>;
    expect(detailRoute.popGestureEnabled, isTrue);
    expect(detailRoute.animation!.value, closeTo(1, 0.001));
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    await _present(
      tester,
      runtime,
      openFrame.targetRevision,
      'detail mail frame',
    );

    final popGesture = await tester.startGesture(const Offset(5, 180));
    await popGesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(navigator.userGestureInProgress, isTrue);
    final trackingStart = detailRoute.animation!.value;
    await popGesture.moveBy(const Offset(96, 0));
    await tester.pump();
    expect(
      detailRoute.animation!.value,
      closeTo(trackingStart - (96 / logicalWidth), 0.01),
    );
    expect(queue.pendingCount, 0);
    await popGesture.moveBy(const Offset(180, 0));
    await popGesture.up();
    await tester.pumpAndSettle();
    expect(queue.pendingCount, 1);

    final popBatch = queue.takeBatch()!;
    expect(popBatch.events, hasLength(1));
    expect(popBatch.events.single.eventTag, EventTagId.routePop);
    expect(
      popBatch.events.single.payload,
      const RoutePopEventPayload(pageKey: 'mail-detail-4', result: null),
    );
    final popResponse = await tester.runAsync(
      () => _bounded(runtime.sendEventBatch(popBatch), 'mail edge pop event'),
    );
    final popFrame = FrameCodec.decode(popResponse!.bytes);
    store.apply(popFrame);
    await tester.pumpAndSettle();

    expect(detailBody, findsNothing);
    expect(
      find.bySemanticsLabel('Read message from Juniper Works'),
      findsOneWidget,
    );
  });
}

Future<void> _present(
  WidgetTester tester,
  RuntimeSession runtime,
  int revision,
  String operation,
) async {
  final response = await tester.runAsync(
    () => _bounded(runtime.framePresented(revision), operation),
  );
  expect(response, isNotNull);
  expect(response!.status, RuntimeStatus.ok);
}
