import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  group('event batch codec', () {
    test('round trips host responses and route pops', () {
      final batch = EventBatch(
        runtimeEpoch: 21,
        events: const [
          UiEvent(
            sequence: 1,
            displayedRevision: 4,
            nodeId: 0,
            handlerId: 0,
            eventTag: EventTagId.hostResponse,
            payload: HostResponseEventPayload(
              requestId: 90,
              status: HostResponseStatus.error,
              value: [100, 101, 110, 105, 101, 100],
            ),
          ),
          UiEvent(
            sequence: 2,
            displayedRevision: 4,
            nodeId: 8,
            handlerId: 99,
            eventTag: EventTagId.routePop,
            payload: RoutePopEventPayload(pageKey: 'settings', result: 'saved'),
          ),
          UiEvent(
            sequence: 3,
            displayedRevision: 4,
            nodeId: 0,
            handlerId: 0,
            eventTag: EventTagId.environmentChanged,
            payload: EnvironmentEventPayload(
              EnvironmentSnapshot(
                viewportWidth: 1440,
                viewportHeight: 900,
                devicePixelRatio: 2,
                textScale: 1.25,
                brightness: EnvironmentBrightness.dark,
                platform: 'macos',
                locale: 'zh-CN',
                safeArea: EnvironmentInsets(
                  left: 0,
                  top: 24,
                  right: 0,
                  bottom: 0,
                ),
                keyboardInsets: EnvironmentInsets(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 280,
                ),
                accessibleNavigation: false,
                boldText: false,
                invertColors: false,
                disableAnimations: false,
                reducedMotion: false,
                highContrast: true,
                orientation: EnvironmentOrientation.landscape,
                pointerKinds: 10,
              ),
            ),
          ),
        ],
      );

      final decoded = EventBatchCodec.decode(EventBatchCodec.encode(batch));

      expect(decoded.events[0].payload, batch.events[0].payload);
      expect(decoded.events[1].payload, batch.events[1].payload);
      expect(decoded.events[2].payload, batch.events[2].payload);
    });

    test('matches the shared Counter press fixture byte for byte', () {
      final batch = EventBatch(
        runtimeEpoch: 21,
        events: [
          UiEvent(
            sequence: 1,
            displayedRevision: 1,
            nodeId: 3,
            handlerId: 9001,
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        ],
      );

      final encoded = EventBatchCodec.encode(batch);

      expect(encoded, orderedEquals(readHexFixture('counter_press.hex')));
      expect(encoded, hasLength(90));
    });

    test('matches the bounded text limit fixture byte for byte', () {
      final batch = EventBatch(
        runtimeEpoch: 22,
        events: const [
          UiEvent(
            sequence: 4,
            displayedRevision: 2,
            nodeId: 4,
            handlerId: 45,
            eventTag: EventTagId.textLimitReached,
            payload: UnitEventPayload(),
          ),
        ],
      );

      final encoded = EventBatchCodec.encode(batch);

      expect(
        encoded,
        orderedEquals(readHexFixture('dart_text_limit_reached.hex')),
      );
      expect(encoded.length, lessThan(128));
    });

    test('round trips all implemented typed payload layouts', () {
      final batch = EventBatch(
        runtimeEpoch: 21,
        events: [
          UiEvent(
            sequence: 4,
            displayedRevision: 3,
            nodeId: 10,
            handlerId: 20,
            eventTag: EventTagId.focusChanged,
            payload: const BoolEventPayload(true),
          ),
          UiEvent(
            sequence: 5,
            displayedRevision: 3,
            nodeId: 11,
            handlerId: 21,
            eventTag: EventTagId.valueChanged,
            payload: const BoolEventPayload(false),
          ),
          UiEvent(
            sequence: 6,
            displayedRevision: 3,
            nodeId: 12,
            handlerId: 22,
            eventTag: EventTagId.textEdit,
            payload: const TextEditEventPayload(
              sessionId: 7,
              localRevision: 11,
              baseDocumentRevision: 9,
              text: '拼😀音',
              selectionStartUtf16: 4,
              selectionEndUtf16: 4,
              composingStartUtf16: 0,
              composingEndUtf16: 4,
            ),
          ),
          UiEvent(
            sequence: 7,
            displayedRevision: 3,
            nodeId: 13,
            handlerId: 23,
            eventTag: EventTagId.textSubmit,
            payload: const TextEventPayload('提交'),
          ),
          UiEvent(
            sequence: 8,
            displayedRevision: 3,
            nodeId: 14,
            handlerId: 24,
            eventTag: EventTagId.animationCompleted,
            payload: const Int64EventPayload(99),
          ),
          UiEvent(
            sequence: 9,
            displayedRevision: 3,
            nodeId: 15,
            handlerId: 25,
            eventTag: EventTagId.scrollNotification,
            payload: const ScrollEventPayload(pixels: 120.5, delta: -4.25),
          ),
          UiEvent(
            sequence: 10,
            displayedRevision: 3,
            nodeId: 16,
            handlerId: 26,
            eventTag: EventTagId.visibleRangeChanged,
            payload: const VisibleRangeEventPayload(
              firstIndex: 10,
              lastExclusive: 30,
            ),
          ),
          UiEvent(
            sequence: 11,
            displayedRevision: 3,
            nodeId: 17,
            handlerId: 27,
            eventTag: EventTagId.tap,
            payload: const TapEventPayload(
              localX: 10.5,
              localY: 20.5,
              globalX: 30.5,
              globalY: 40.5,
              pointerKind: PointerKindValue.touch,
            ),
          ),
          UiEvent(
            sequence: 12,
            displayedRevision: 3,
            nodeId: 18,
            handlerId: 28,
            eventTag: EventTagId.pointerDown,
            payload: const PointerEventPayload(
              pointerId: 9,
              localX: 1,
              localY: 2,
              globalX: 3,
              globalY: 4,
              pointerKind: PointerKindValue.mouse,
              buttons: 1,
            ),
          ),
          UiEvent(
            sequence: 13,
            displayedRevision: 3,
            nodeId: 19,
            handlerId: 29,
            eventTag: EventTagId.key,
            payload: const KeyEventPayload(
              logicalKey: 0x61,
              physicalKey: 0x70004,
              action: KeyActionValue.down,
              modifiers: 3,
            ),
          ),
          const UiEvent(
            sequence: 14,
            displayedRevision: 3,
            nodeId: 20,
            handlerId: 30,
            eventTag: EventTagId.textLimitReached,
            payload: UnitEventPayload(),
          ),
        ],
      );

      final decoded = EventBatchCodec.decode(EventBatchCodec.encode(batch));

      expect(decoded.runtimeEpoch, 21);
      expect(decoded.events, hasLength(11));
      expect(decoded.events[0].payload, const BoolEventPayload(true));
      expect(decoded.events[1].payload, const BoolEventPayload(false));
      expect(
        decoded.events[2].payload,
        const TextEditEventPayload(
          sessionId: 7,
          localRevision: 11,
          baseDocumentRevision: 9,
          text: '拼😀音',
          selectionStartUtf16: 4,
          selectionEndUtf16: 4,
          composingStartUtf16: 0,
          composingEndUtf16: 4,
        ),
      );
      expect(decoded.events[3].payload, const TextEventPayload('提交'));
      expect(decoded.events[4].payload, const Int64EventPayload(99));
      expect(
        decoded.events[5].payload,
        const ScrollEventPayload(pixels: 120.5, delta: -4.25),
      );
      expect(
        decoded.events[6].payload,
        const VisibleRangeEventPayload(firstIndex: 10, lastExclusive: 30),
      );
      expect(decoded.events[7].payload, batch.events[7].payload);
      expect(decoded.events[8].payload, batch.events[8].payload);
      expect(decoded.events[9].payload, batch.events[9].payload);
      expect(decoded.events[10].payload, const UnitEventPayload());
    });

    test('rejects malformed event batches before allocation', () {
      final valid = readHexFixture('counter_press.hex');

      expectEventDecodeError(
        Uint8List.sublistView(valid, 0, valid.length - 1),
        ProtocolErrorCode.invalidPayloadLength,
      );
      expectEventDecodeError(
        mutateEvent(valid, 10, FrameKindId.fullSnapshot),
        ProtocolErrorCode.invalidFrameKind,
      );
      expectEventDecodeError(
        mutateEvent(valid, 88, 0xff),
        ProtocolErrorCode.invalidEventTag,
      );

      final oversizedCount = Uint8List.fromList(valid);
      ByteData.sublistView(
        oversizedCount,
      ).setUint32(48, ProtocolLimits.maxOperations + 1, Endian.little);
      expectEventDecodeError(
        oversizedCount,
        ProtocolErrorCode.tooManyOperations,
      );
    });

    test(
      'round trips generic application responses, errors, and ordered events',
      () {
        final boundary = Uint8List(maximumApplicationPlatformPayloadBytes)
          ..[0] = 1
          ..[maximumApplicationPlatformPayloadBytes - 1] = 255;
        final batch = EventBatch(
          runtimeEpoch: 72,
          events: [
            UiEvent(
              sequence: 1,
              displayedRevision: 7,
              nodeId: 0,
              handlerId: 0,
              eventTag: EventTagId.applicationResponse,
              payload: ApplicationResponseEventPayload(
                requestId: 101,
                payload: Uint8List.fromList([0, 127, 128, 255]),
              ),
            ),
            const UiEvent(
              sequence: 2,
              displayedRevision: 7,
              nodeId: 0,
              handlerId: 0,
              eventTag: EventTagId.applicationRequestError,
              payload: ApplicationRequestErrorEventPayload(
                requestId: 102,
                error: ApplicationPlatformBridgeError(
                  code: ApplicationPlatformErrorCode.handlerFailed,
                  message: 'handler failed safely',
                ),
              ),
            ),
            UiEvent(
              sequence: 3,
              displayedRevision: 7,
              nodeId: 0,
              handlerId: 0,
              eventTag: EventTagId.applicationEvent,
              payload: ApplicationEventPayload(payload: boundary),
            ),
          ],
        );

        final decoded = EventBatchCodec.decode(EventBatchCodec.encode(batch));

        expect(decoded.events[0].payload, batch.events[0].payload);
        expect(decoded.events[1].payload, batch.events[1].payload);
        expect(decoded.events[2].payload, batch.events[2].payload);
      },
    );

    test('rejects oversized application event lengths before slicing', () {
      final valid = EventBatchCodec.encode(
        EventBatch(
          runtimeEpoch: 72,
          events: [
            UiEvent(
              sequence: 1,
              displayedRevision: 7,
              nodeId: 0,
              handlerId: 0,
              eventTag: EventTagId.applicationEvent,
              payload: ApplicationEventPayload(
                payload: Uint8List.fromList([1]),
              ),
            ),
          ],
        ),
      );
      final malformed = Uint8List.fromList(valid);
      ByteData.sublistView(malformed).setUint32(
        90,
        maximumApplicationPlatformPayloadBytes + 1,
        Endian.little,
      );

      expectEventDecodeError(
        malformed,
        ProtocolErrorCode.applicationPayloadTooLarge,
      );
      expect(
        () => EventBatchCodec.encode(
          EventBatch(
            runtimeEpoch: 72,
            events: [
              UiEvent(
                sequence: 1,
                displayedRevision: 7,
                nodeId: 0,
                handlerId: 0,
                eventTag: EventTagId.applicationEvent,
                payload: ApplicationEventPayload(
                  payload: Uint8List(
                    maximumApplicationPlatformPayloadBytes + 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.applicationPayloadTooLarge,
          ),
        ),
      );
    });

    test('preserves UTF-16 ranges across supported writing systems', () {
      final cases = ['ascii', '拼音', 'かな', '한글', '😀', 'é'];
      for (var index = 0; index < cases.length; index += 1) {
        final text = cases[index];
        final payload = TextEditEventPayload(
          sessionId: 1,
          localRevision: index + 1,
          baseDocumentRevision: 1,
          text: text,
          selectionStartUtf16: text.length,
          selectionEndUtf16: text.length,
          composingStartUtf16: 0,
          composingEndUtf16: text.length,
        );
        final batch = EventBatch(
          runtimeEpoch: 21,
          events: [
            UiEvent(
              sequence: index + 1,
              displayedRevision: 1,
              nodeId: 1,
              handlerId: 2,
              eventTag: EventTagId.textEdit,
              payload: payload,
            ),
          ],
        );

        final decoded = EventBatchCodec.decode(EventBatchCodec.encode(batch));

        expect(decoded.events.single.payload, payload);
      }

      expect(
        () => EventBatchCodec.encode(
          EventBatch(
            runtimeEpoch: 21,
            events: [
              const UiEvent(
                sequence: 1,
                displayedRevision: 1,
                nodeId: 1,
                handlerId: 2,
                eventTag: EventTagId.textEdit,
                payload: TextEditEventPayload(
                  sessionId: 1,
                  localRevision: 1,
                  baseDocumentRevision: 1,
                  text: '😀',
                  selectionStartUtf16: 1,
                  selectionEndUtf16: 1,
                  composingStartUtf16: null,
                  composingEndUtf16: null,
                ),
              ),
            ],
          ),
        ),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.invalidProps,
          ),
        ),
      );
    });
  });

  group('event batch queue', () {
    test(
      'rebases application controls to the carrying presentation revision',
      () {
        final queue = EventBatchQueue(
          runtimeEpoch: 21,
          displayedRevision: () => 3,
        );
        queue.enqueue(
          RendererEvent(
            nodeId: 0,
            eventTag: EventTagId.applicationResponse,
            handlerId: 0,
            payload: ApplicationResponseEventPayload(
              requestId: 41,
              payload: Uint8List.fromList([1]),
            ),
          ),
        );
        queue.enqueue(
          const RendererEvent(
            nodeId: 0,
            eventTag: EventTagId.applicationRequestError,
            handlerId: 0,
            payload: ApplicationRequestErrorEventPayload(
              requestId: 42,
              error: ApplicationPlatformBridgeError(
                code: ApplicationPlatformErrorCode.handlerFailed,
              ),
            ),
          ),
        );
        queue.enqueue(
          RendererEvent(
            nodeId: 0,
            eventTag: EventTagId.applicationEvent,
            handlerId: 0,
            payload: ApplicationEventPayload(payload: Uint8List.fromList([2])),
          ),
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        );

        final events = EventBatchCodec.decode(
          queue.prepareBatch(runtimeControlRevision: 4).encodedBytes,
        ).events;

        expect(events.map((event) => event.displayedRevision), [4, 4, 4, 3]);
      },
    );

    test(
      'coalesces bounded text limit notifications without text payloads',
      () {
        final queue = EventBatchQueue(
          runtimeEpoch: 21,
          displayedRevision: () => 7,
          maxPendingEvents: 1,
        );
        final notification = rendererEvent(
          eventTag: EventTagId.textLimitReached,
          payload: const UnitEventPayload(),
        );

        queue.enqueue(notification);
        queue.enqueue(notification);

        final prepared = queue.prepareBatch();
        final events = EventBatchCodec.decode(prepared.encodedBytes).events;
        expect(events, hasLength(1));
        expect(events.single.eventTag, EventTagId.textLimitReached);
        expect(events.single.payload, const UnitEventPayload());
        expect(prepared.encodedBytes.length, lessThan(128));
        expect(queue.coalescedCount, 1);
      },
    );

    test('never coalesces ordered press events and applies backpressure', () {
      final queue = EventBatchQueue(
        runtimeEpoch: 21,
        displayedRevision: () => 7,
        maxPendingEvents: 2,
      );
      final press = rendererEvent(
        eventTag: EventTagId.press,
        payload: const UnitEventPayload(),
      );

      queue.enqueue(press);
      queue.enqueue(press);
      expect(
        () => queue.enqueue(press),
        throwsA(isA<EventQueueBackpressureException>()),
      );

      final batch = queue.takeBatch()!;
      expect(batch.events.map((event) => event.sequence), [1, 2]);
      expect(batch.events.map((event) => event.displayedRevision), [7, 7]);
      expect(queue.pendingCount, 0);
    });

    test(
      'coalesces high-frequency state events without reordering presses',
      () {
        final queue = EventBatchQueue(
          runtimeEpoch: 21,
          displayedRevision: () => 8,
          maxPendingEvents: 3,
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.scrollNotification,
            payload: const ScrollEventPayload(pixels: 10, delta: 1),
          ),
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.scrollNotification,
            payload: const ScrollEventPayload(pixels: 20, delta: 2),
          ),
        );

        final events = queue.takeBatch()!.events;
        expect(events.map((event) => event.eventTag), [
          EventTagId.press,
          EventTagId.scrollNotification,
        ]);
        expect(
          events[1].payload,
          const ScrollEventPayload(pixels: 20, delta: 2),
        );
        expect(events.map((event) => event.sequence), [2, 3]);
        expect(queue.coalescedCount, 1);
      },
    );

    test('drops only coalescible input when ordered events fill the bound', () {
      final queue = EventBatchQueue(
        runtimeEpoch: 21,
        displayedRevision: () => 9,
        maxPendingEvents: 1,
      );
      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.press,
          payload: const UnitEventPayload(),
        ),
      );
      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.visibleRangeChanged,
          payload: const VisibleRangeEventPayload(
            firstIndex: 50,
            lastExclusive: 60,
          ),
        ),
      );

      expect(queue.pendingCount, 1);
      expect(queue.droppedCount, 1);
      expect(queue.takeBatch()!.events.single.eventTag, EventTagId.press);
    });

    test('prepare preserves events until exact prefix commit', () {
      final queue = EventBatchQueue(
        runtimeEpoch: 21,
        displayedRevision: () => 10,
      );
      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.press,
          payload: const UnitEventPayload(),
        ),
      );
      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.key,
          payload: const KeyEventPayload(
            logicalKey: 13,
            physicalKey: 40,
            action: KeyActionValue.down,
            modifiers: 0,
          ),
        ),
      );

      final prepared = queue.prepareBatch();

      expect(prepared.prefixLength, 2);
      expect(
        EventBatchCodec.decode(prepared.encodedBytes).events,
        hasLength(2),
      );
      expect(queue.pendingCount, 2);

      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.press,
          payload: const UnitEventPayload(),
        ),
      );
      queue.commit(prepared);

      expect(queue.pendingCount, 1);
      expect(queue.prepareBatch().prefixLength, 1);
    });

    test('failed handoff preserves the prepared prefix for retry', () {
      final queue = EventBatchQueue(
        runtimeEpoch: 21,
        displayedRevision: () => 11,
      );
      queue.enqueue(
        rendererEvent(
          eventTag: EventTagId.press,
          payload: const UnitEventPayload(),
        ),
      );
      final first = queue.prepareBatch();

      expect(queue.pendingCount, 1);

      final retry = queue.prepareBatch();
      expect(retry.encodedBytes, orderedEquals(first.encodedBytes));
      queue.commit(retry);
      expect(queue.pendingCount, 0);
    });

    test(
      'prepared prefixes are exact-once and reject stale queue identity',
      () {
        final queue = EventBatchQueue(
          runtimeEpoch: 21,
          displayedRevision: () => 12,
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        );
        final stale = queue.prepareBatch();
        final committed = queue.prepareBatch();
        queue.commit(committed);

        expect(() => queue.commit(committed), throwsStateError);
        expect(() => queue.commit(stale), throwsStateError);
      },
    );

    test(
      'events capture presented revision instead of later applied revision',
      () {
        var presentedRevision = 1;
        final queue = EventBatchQueue(
          runtimeEpoch: 21,
          displayedRevision: () => presentedRevision,
        );
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        );
        presentedRevision = 2;
        queue.enqueue(
          rendererEvent(
            eventTag: EventTagId.press,
            payload: const UnitEventPayload(),
          ),
        );

        final events = EventBatchCodec.decode(
          queue.prepareBatch().encodedBytes,
        ).events;
        expect(events.map((event) => event.displayedRevision), [1, 2]);
      },
    );
  });
}

RendererEvent rendererEvent({
  required int eventTag,
  required EventPayload payload,
}) => RendererEvent(
  nodeId: 3,
  eventTag: eventTag,
  handlerId: 9001,
  payload: payload,
);

void expectEventDecodeError(Uint8List bytes, ProtocolErrorCode code) {
  expect(
    () => EventBatchCodec.decode(bytes),
    throwsA(
      isA<ProtocolException>().having((error) => error.code, 'code', code),
    ),
  );
}

Uint8List mutateEvent(Uint8List source, int offset, int value) {
  final result = Uint8List.fromList(source);
  result[offset] = value;
  return result;
}
