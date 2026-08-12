import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'registered native factory decodes typed props and emits events',
    (tester) async {
      final nativeRegistry =
          NativeWidgetRegistry(capabilityBits: NativeCapability.stateful)
            ..register<String>(
              NativeWidgetRegistration(
                kindId: 42,
                minVersion: 2,
                maxVersion: 3,
                capabilityBits: NativeCapability.stateful,
                decodeProps: (payload) => String.fromCharCodes(payload),
                factory: (context) => TextButton(
                  onPressed: () =>
                      context.emit?.call(7, Uint8List.fromList([23])),
                  child: Text(context.props),
                ),
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
                props: NativeWidgetProps(
                  kindId: 42,
                  version: 3,
                  capabilityBits: NativeCapability.stateful,
                  payload: Uint8List.fromList('dial'.codeUnits),
                ),
                eventBindings: const [
                  EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 9),
                ],
              ),
              const SetRoot(1),
            ],
          ),
        );
      final events = <RendererEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(nativeWidgets: nativeRegistry),
            onEvent: events.add,
          ),
        ),
      );
      expect(find.text('dial'), findsOneWidget);
      await tester.tap(find.text('dial'));
      final payload = events.single.payload as NativeEventPayload;
      expect(payload.kindId, 42);
      expect(payload.version, 3);
      expect(payload.eventId, 7);
      expect(payload.payload, [23]);
    },
  );

  testWidgets('unsupported versions and capabilities render a fallback', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(_nativeFrame(capabilityBits: NativeCapability.resource));

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(
            nativeWidgets: NativeWidgetRegistry(capabilityBits: 0),
          ),
        ),
      ),
    );

    expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    expect(find.textContaining('kind 42'), findsOneWidget);
  });

  test('native props survive binary protocol round trip', () {
    final frame = _nativeFrame(
      capabilityBits: NativeCapability.stateful | NativeCapability.resource,
      payload: Uint8List.fromList([0, 1, 2, 255]),
    );
    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final props = (decoded.operations.first as CreateNode).props;
    expect(props, frame.operations.cast<CreateNode>().first.props);
  });

  test('typed native event survives event protocol round trip', () {
    final batch = EventBatch(
      runtimeEpoch: 4,
      events: [
        UiEvent(
          sequence: 1,
          displayedRevision: 3,
          nodeId: 8,
          handlerId: 9,
          eventTag: EventTagId.nativeEvent,
          payload: NativeEventPayload(
            kindId: 42,
            version: 3,
            eventId: 7,
            payload: const [0, 23, 255],
          ),
        ),
      ],
    );
    final decoded = EventBatchCodec.decode(EventBatchCodec.encode(batch));
    expect(decoded.events.single.payload, batch.events.single.payload);
  });

  testWidgets('standard registry includes the built-in swipe action', (
    tester,
  ) async {
    final store = NodeStore()..apply(_swipeNativeFrame(_validSwipePayload()));
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(),
          onEvent: events.add,
        ),
      ),
    );

    expect(find.byType(UnsupportedNativeWidget), findsNothing);
    expect(find.text('Swipe content'), findsOneWidget);
  });

  testWidgets('swipe action rejects unsupported versions and capabilities', (
    tester,
  ) async {
    Future<void> expectRejected(NativeWidgetProps props, String message) async {
      final store = NodeStore()..apply(_swipeNativeFrameFromProps(props));
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
          ),
        ),
      );
      expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
      expect(find.textContaining(message), findsOneWidget);
    }

    await expectRejected(
      NativeWidgetProps(
        kindId: 2,
        version: 1,
        capabilityBits:
            NativeCapability.stateful |
            NativeCapability.resource |
            NativeCapability.semantics,
        payload: _validSwipePayload(),
      ),
      'Unsupported version 1',
    );
    await expectRejected(
      NativeWidgetProps(
        kindId: 2,
        version: 3,
        capabilityBits:
            NativeCapability.stateful |
            NativeCapability.resource |
            NativeCapability.semantics,
        payload: _validSwipePayload(),
      ),
      'Unsupported version 3',
    );
    await expectRejected(
      NativeWidgetProps(
        kindId: 2,
        version: 2,
        capabilityBits: 1 << 20,
        payload: _validSwipePayload(),
      ),
      'Unsupported capabilities',
    );
  });

  testWidgets('swipe action rejects malformed payloads and child counts', (
    tester,
  ) async {
    final malformed = <Uint8List>[
      Uint8List(43),
      _mutate(_validSwipePayload(), 0, 0x80),
      _mutate(_validSwipePayload(), 1, 2),
      _mutate(_validSwipePayload(), 2, 2),
      _mutate(_validSwipePayload(), 3, 1),
      _mutate(_validSwipePayload(), 36, 0xff),
      _payloadWithLabels([0xff], utf8.encode('Mark read')),
      _payloadWithLabels([], utf8.encode('Mark read')),
      _payloadWithLabels(
        utf8.encode('Archive'),
        utf8.encode('Mark read'),
        startBorderRadius: -1,
      ),
      _payloadWithLabels(
        utf8.encode('Archive'),
        utf8.encode('Mark read'),
        endBorderRadius: double.nan,
      ),
      _payloadWithLabels(
        utf8.encode('Archive'),
        utf8.encode('Mark read'),
        clipBorderRadius: double.infinity,
      ),
    ];

    for (final payload in malformed) {
      final store = NodeStore()..apply(_swipeNativeFrame(payload));
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
          ),
        ),
      );
      expect(
        find.byType(UnsupportedNativeWidget),
        findsOneWidget,
        reason: 'payload $payload should be rejected',
      );
    }

    for (final childCount in [0, 1, 2, 4]) {
      final store = NodeStore()
        ..apply(
          _swipeNativeFrame(_validSwipePayload(), childCount: childCount),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
          ),
        ),
      );
      expect(
        find.byType(UnsupportedNativeWidget),
        findsOneWidget,
        reason: '$childCount children should be rejected',
      );
    }
  });

  testWidgets('dropping a swipe host disposes its local animation resource', (
    tester,
  ) async {
    final store = NodeStore()..apply(_swipeNativeFrame(_validSwipePayload()));
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(),
        ),
      ),
    );

    await tester.drag(find.text('Swipe content'), const Offset(240, 0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}

Frame _nativeFrame({int capabilityBits = 0, Uint8List? payload}) => Frame(
  runtimeEpoch: 1,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.nativeWidget,
      props: NativeWidgetProps(
        kindId: 42,
        version: 3,
        capabilityBits: capabilityBits,
        payload: payload ?? Uint8List.fromList([1]),
      ),
      eventBindings: const [
        EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 9),
      ],
    ),
    const SetRoot(1),
  ],
);

Uint8List _validSwipePayload() =>
    _payloadWithLabels(utf8.encode('Archive'), utf8.encode('Mark read'));

Uint8List _payloadWithLabels(
  List<int> start,
  List<int> end, {
  double startBorderRadius = 999,
  double endBorderRadius = 999,
  double clipBorderRadius = 0,
}) {
  final data = ByteData(44 + start.length + end.length)
    ..setUint8(0, 3)
    ..setUint8(1, 0)
    ..setUint8(2, 1)
    ..setUint32(4, 0xff507d58, Endian.little)
    ..setUint32(8, 0xff435f8a, Endian.little)
    ..setFloat64(12, startBorderRadius, Endian.little)
    ..setFloat64(20, endBorderRadius, Endian.little)
    ..setFloat64(28, clipBorderRadius, Endian.little)
    ..setUint32(36, start.length, Endian.little)
    ..setUint32(40, end.length, Endian.little);
  final payload = data.buffer.asUint8List();
  payload.setRange(44, 44 + start.length, start);
  payload.setRange(44 + start.length, payload.length, end);
  return payload;
}

Uint8List _mutate(Uint8List original, int offset, int value) =>
    Uint8List.fromList(original)..[offset] = value;

Frame _swipeNativeFrame(Uint8List payload, {int childCount = 3}) =>
    _swipeNativeFrameFromProps(
      NativeWidgetProps(
        kindId: 2,
        version: 2,
        capabilityBits:
            NativeCapability.stateful |
            NativeCapability.resource |
            NativeCapability.semantics,
        payload: payload,
      ),
      childCount: childCount,
    );

Frame _swipeNativeFrameFromProps(
  NativeWidgetProps props, {
  int childCount = 3,
}) {
  final children = List.generate(
    childCount,
    (index) => CreateNode(
      nodeId: index + 2,
      kind: NodeKind.text,
      props: TextProps(switch (index) {
        0 => 'Swipe content',
        1 => 'Archive icon',
        _ => 'Read icon',
      }),
      eventBindings: const [],
    ),
  );
  return Frame(
    runtimeEpoch: 3,
    baseRevision: 0,
    targetRevision: 1,
    kind: FrameKind.fullSnapshot,
    operations: [
      CreateNode(
        nodeId: 1,
        kind: NodeKind.nativeWidget,
        props: props,
        eventBindings: const [
          EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 12),
        ],
      ),
      ...children,
      SetChildren(
        nodeId: 1,
        children: List.generate(childCount, (index) => index + 2),
      ),
      const SetRoot(1),
    ],
  );
}
