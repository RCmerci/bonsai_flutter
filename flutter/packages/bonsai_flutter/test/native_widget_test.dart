import 'fixture.dart';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
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
              const SetApplicationTheme(
                title: 'Test',
                theme: testApplicationTheme,
              ),
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
    final props = decoded.operations.whereType<CreateNode>().single.props;
    expect(props, frame.operations.whereType<CreateNode>().single.props);
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
}

Frame _nativeFrame({int capabilityBits = 0, Uint8List? payload}) => Frame(
  runtimeEpoch: 1,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
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
