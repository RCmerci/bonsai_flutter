import 'dart:convert';
import 'dart:typed_data';

import '../application_platform/application_platform.dart';
import 'binary_codec.dart';
import 'generated_protocol.dart';

sealed class EventPayload {
  const EventPayload();
}

final class UnitEventPayload extends EventPayload {
  const UnitEventPayload();

  @override
  bool operator ==(Object other) => other is UnitEventPayload;

  @override
  int get hashCode => 1;
}

final class BoolEventPayload extends EventPayload {
  const BoolEventPayload(this.value);

  final bool value;

  @override
  bool operator ==(Object other) =>
      other is BoolEventPayload && other.value == value;

  @override
  int get hashCode => Object.hash(BoolEventPayload, value);
}

final class TextEventPayload extends EventPayload {
  const TextEventPayload(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is TextEventPayload && other.value == value;

  @override
  int get hashCode => Object.hash(TextEventPayload, value);
}

final class TextEditEventPayload extends EventPayload {
  const TextEditEventPayload({
    required this.sessionId,
    required this.localRevision,
    required this.baseDocumentRevision,
    required this.text,
    required this.selectionStartUtf16,
    required this.selectionEndUtf16,
    required this.composingStartUtf16,
    required this.composingEndUtf16,
  });

  final int sessionId;
  final int localRevision;
  final int baseDocumentRevision;
  final String text;
  final int selectionStartUtf16;
  final int selectionEndUtf16;
  final int? composingStartUtf16;
  final int? composingEndUtf16;

  @override
  bool operator ==(Object other) =>
      other is TextEditEventPayload &&
      other.sessionId == sessionId &&
      other.localRevision == localRevision &&
      other.baseDocumentRevision == baseDocumentRevision &&
      other.text == text &&
      other.selectionStartUtf16 == selectionStartUtf16 &&
      other.selectionEndUtf16 == selectionEndUtf16 &&
      other.composingStartUtf16 == composingStartUtf16 &&
      other.composingEndUtf16 == composingEndUtf16;

  @override
  int get hashCode => Object.hash(
    TextEditEventPayload,
    sessionId,
    localRevision,
    baseDocumentRevision,
    text,
    selectionStartUtf16,
    selectionEndUtf16,
    composingStartUtf16,
    composingEndUtf16,
  );
}

final class Int64EventPayload extends EventPayload {
  const Int64EventPayload(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is Int64EventPayload && other.value == value;

  @override
  int get hashCode => Object.hash(Int64EventPayload, value);
}

final class FloatEventPayload extends EventPayload {
  const FloatEventPayload(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      other is FloatEventPayload && other.value == value;

  @override
  int get hashCode => Object.hash(FloatEventPayload, value);
}

final class FloatRangeEventPayload extends EventPayload {
  const FloatRangeEventPayload({required this.start, required this.end});

  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is FloatRangeEventPayload &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(FloatRangeEventPayload, start, end);
}

enum PointerKindValue {
  mouse,
  touch,
  stylus,
  invertedStylus,
  trackpad,
  unknown,
}

final class TapEventPayload extends EventPayload {
  const TapEventPayload({
    required this.localX,
    required this.localY,
    required this.globalX,
    required this.globalY,
    required this.pointerKind,
  });

  final double localX;
  final double localY;
  final double globalX;
  final double globalY;
  final PointerKindValue pointerKind;

  @override
  bool operator ==(Object other) =>
      other is TapEventPayload &&
      other.localX == localX &&
      other.localY == localY &&
      other.globalX == globalX &&
      other.globalY == globalY &&
      other.pointerKind == pointerKind;

  @override
  int get hashCode => Object.hash(
    TapEventPayload,
    localX,
    localY,
    globalX,
    globalY,
    pointerKind,
  );
}

final class PointerEventPayload extends EventPayload {
  const PointerEventPayload({
    required this.pointerId,
    required this.localX,
    required this.localY,
    required this.globalX,
    required this.globalY,
    required this.pointerKind,
    required this.buttons,
  });

  final int pointerId;
  final double localX;
  final double localY;
  final double globalX;
  final double globalY;
  final PointerKindValue pointerKind;
  final int buttons;

  @override
  bool operator ==(Object other) =>
      other is PointerEventPayload &&
      other.pointerId == pointerId &&
      other.localX == localX &&
      other.localY == localY &&
      other.globalX == globalX &&
      other.globalY == globalY &&
      other.pointerKind == pointerKind &&
      other.buttons == buttons;

  @override
  int get hashCode => Object.hash(
    PointerEventPayload,
    pointerId,
    localX,
    localY,
    globalX,
    globalY,
    pointerKind,
    buttons,
  );
}

enum KeyActionValue { down, up, repeat }

final class KeyEventPayload extends EventPayload {
  const KeyEventPayload({
    required this.logicalKey,
    required this.physicalKey,
    required this.action,
    required this.modifiers,
  });

  final int logicalKey;
  final int physicalKey;
  final KeyActionValue action;
  final int modifiers;

  @override
  bool operator ==(Object other) =>
      other is KeyEventPayload &&
      other.logicalKey == logicalKey &&
      other.physicalKey == physicalKey &&
      other.action == action &&
      other.modifiers == modifiers;

  @override
  int get hashCode =>
      Object.hash(KeyEventPayload, logicalKey, physicalKey, action, modifiers);
}

final class ScrollEventPayload extends EventPayload {
  const ScrollEventPayload({required this.pixels, required this.delta});

  final double pixels;
  final double delta;

  @override
  bool operator ==(Object other) =>
      other is ScrollEventPayload &&
      other.pixels == pixels &&
      other.delta == delta;

  @override
  int get hashCode => Object.hash(ScrollEventPayload, pixels, delta);
}

final class VisibleRangeEventPayload extends EventPayload {
  const VisibleRangeEventPayload({
    required this.firstIndex,
    required this.lastExclusive,
  });

  final int firstIndex;
  final int lastExclusive;

  @override
  bool operator ==(Object other) =>
      other is VisibleRangeEventPayload &&
      other.firstIndex == firstIndex &&
      other.lastExclusive == lastExclusive;

  @override
  int get hashCode =>
      Object.hash(VisibleRangeEventPayload, firstIndex, lastExclusive);
}

final class RoutePopEventPayload extends EventPayload {
  const RoutePopEventPayload({required this.pageKey, required this.result});

  final String pageKey;
  final String? result;

  @override
  bool operator ==(Object other) =>
      other is RoutePopEventPayload &&
      other.pageKey == pageKey &&
      other.result == result;

  @override
  int get hashCode => Object.hash(RoutePopEventPayload, pageKey, result);
}

enum HostResponseStatus { ok, error, cancelled }

final class HostResponseEventPayload extends EventPayload {
  const HostResponseEventPayload({
    required this.requestId,
    required this.status,
    required this.value,
  });

  final int requestId;
  final HostResponseStatus status;
  final List<int> value;

  @override
  bool operator ==(Object other) =>
      other is HostResponseEventPayload &&
      other.requestId == requestId &&
      other.status == status &&
      _eventBytesEqual(other.value, value);

  @override
  int get hashCode => Object.hash(
    HostResponseEventPayload,
    requestId,
    status,
    Object.hashAll(value),
  );
}

final class ApplicationResponseEventPayload extends EventPayload {
  ApplicationResponseEventPayload({
    required this.requestId,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  final int requestId;
  final Uint8List payload;

  @override
  bool operator ==(Object other) =>
      other is ApplicationResponseEventPayload &&
      other.requestId == requestId &&
      _eventBytesEqual(other.payload, payload);

  @override
  int get hashCode => Object.hash(requestId, Object.hashAll(payload));
}

final class ApplicationRequestErrorEventPayload extends EventPayload {
  const ApplicationRequestErrorEventPayload({
    required this.requestId,
    required this.error,
  });

  final int requestId;
  final ApplicationPlatformBridgeError error;

  @override
  bool operator ==(Object other) =>
      other is ApplicationRequestErrorEventPayload &&
      other.requestId == requestId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(requestId, error);
}

final class ApplicationEventPayload extends EventPayload {
  ApplicationEventPayload({required Uint8List payload})
    : payload = Uint8List.fromList(payload);

  final Uint8List payload;

  @override
  bool operator ==(Object other) =>
      other is ApplicationEventPayload &&
      _eventBytesEqual(other.payload, payload);

  @override
  int get hashCode => Object.hashAll(payload);
}

enum EnvironmentBrightness { light, dark }

enum EnvironmentOrientation { portrait, landscape }

final class EnvironmentInsets {
  const EnvironmentInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is EnvironmentInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

final class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.devicePixelRatio,
    required this.textScale,
    required this.brightness,
    required this.platform,
    required this.locale,
    required this.safeArea,
    required this.keyboardInsets,
    required this.accessibleNavigation,
    required this.boldText,
    required this.invertColors,
    required this.disableAnimations,
    required this.reducedMotion,
    required this.highContrast,
    required this.orientation,
    required this.pointerKinds,
  });

  final double viewportWidth;
  final double viewportHeight;
  final double devicePixelRatio;
  final double textScale;
  final EnvironmentBrightness brightness;
  final String platform;
  final String locale;
  final EnvironmentInsets safeArea;
  final EnvironmentInsets keyboardInsets;
  final bool accessibleNavigation;
  final bool boldText;
  final bool invertColors;
  final bool disableAnimations;
  final bool reducedMotion;
  final bool highContrast;
  final EnvironmentOrientation orientation;
  final int pointerKinds;

  @override
  bool operator ==(Object other) =>
      other is EnvironmentSnapshot &&
      other.viewportWidth == viewportWidth &&
      other.viewportHeight == viewportHeight &&
      other.devicePixelRatio == devicePixelRatio &&
      other.textScale == textScale &&
      other.brightness == brightness &&
      other.platform == platform &&
      other.locale == locale &&
      other.safeArea == safeArea &&
      other.keyboardInsets == keyboardInsets &&
      other.accessibleNavigation == accessibleNavigation &&
      other.boldText == boldText &&
      other.invertColors == invertColors &&
      other.disableAnimations == disableAnimations &&
      other.reducedMotion == reducedMotion &&
      other.highContrast == highContrast &&
      other.orientation == orientation &&
      other.pointerKinds == pointerKinds;

  @override
  int get hashCode => Object.hashAll([
    EnvironmentSnapshot,
    viewportWidth,
    viewportHeight,
    devicePixelRatio,
    textScale,
    brightness,
    platform,
    locale,
    safeArea,
    keyboardInsets,
    accessibleNavigation,
    boldText,
    invertColors,
    disableAnimations,
    reducedMotion,
    highContrast,
    orientation,
    pointerKinds,
  ]);
}

final class EnvironmentEventPayload extends EventPayload {
  const EnvironmentEventPayload(this.snapshot);
  final EnvironmentSnapshot snapshot;

  @override
  bool operator ==(Object other) =>
      other is EnvironmentEventPayload && other.snapshot == snapshot;

  @override
  int get hashCode => Object.hash(EnvironmentEventPayload, snapshot);
}

final class NativeEventPayload extends EventPayload {
  NativeEventPayload({
    required this.kindId,
    required this.version,
    required this.eventId,
    required List<int> payload,
  }) : payload = List.unmodifiable(payload);

  final int kindId;
  final int version;
  final int eventId;
  final List<int> payload;

  @override
  bool operator ==(Object other) =>
      other is NativeEventPayload &&
      other.kindId == kindId &&
      other.version == version &&
      other.eventId == eventId &&
      _eventBytesEqual(other.payload, payload);

  @override
  int get hashCode => Object.hash(
    NativeEventPayload,
    kindId,
    version,
    eventId,
    Object.hashAll(payload),
  );
}

final class UiEvent {
  const UiEvent({
    required this.sequence,
    required this.displayedRevision,
    required this.nodeId,
    required this.handlerId,
    required this.eventTag,
    required this.payload,
  });

  final int sequence;
  final int displayedRevision;
  final int nodeId;
  final int handlerId;
  final int eventTag;
  final EventPayload payload;
}

final class EventBatch {
  EventBatch({required this.runtimeEpoch, required List<UiEvent> events})
    : events = List.unmodifiable(events);

  final int runtimeEpoch;
  final List<UiEvent> events;
}

abstract final class EventBatchCodec {
  static Uint8List encode(EventBatch batch) {
    _checkEventUint64('runtime epoch', batch.runtimeEpoch);
    if (batch.events.length > ProtocolLimits.maxOperations) {
      _eventFail(
        ProtocolErrorCode.tooManyOperations,
        'Event batch has ${batch.events.length} events',
      );
    }
    var previousSequence = -1;
    final payload = _EventWriter()..uint32(batch.events.length);
    for (final event in batch.events) {
      if (event.sequence <= previousSequence) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Event sequences must be strictly increasing',
        );
      }
      previousSequence = event.sequence;
      payload.envelope((body) => _writeEvent(body, event));
    }
    final payloadBytes = payload.takeBytes();
    final totalLength = ProtocolLimits.headerBytes + payloadBytes.length;
    if (totalLength > ProtocolLimits.maxFrameBytes) {
      _eventFail(
        ProtocolErrorCode.frameTooLarge,
        'Encoded event batch is $totalLength bytes',
      );
    }
    final baseRevision = batch.events.isEmpty
        ? 0
        : batch.events.first.displayedRevision;
    final targetSequence = batch.events.isEmpty
        ? 0
        : batch.events.last.sequence;
    final output = _EventWriter()
      ..raw(const [0x42, 0x46, 0x46, 0x52])
      ..uint16(ProtocolVersion.protocolMajor)
      ..uint16(ProtocolVersion.protocolMinor)
      ..uint16(ProtocolLimits.headerBytes)
      ..uint8(FrameKindId.eventBatch)
      ..uint8(0)
      ..uint64(batch.runtimeEpoch)
      ..uint64(baseRevision)
      ..uint64(targetSequence)
      ..uint32(payloadBytes.length)
      ..uint32(0)
      ..uint32(0)
      ..raw(payloadBytes);
    return output.takeBytes();
  }

  static EventBatch decode(Uint8List bytes) {
    if (bytes.length > ProtocolLimits.maxFrameBytes) {
      _eventFail(
        ProtocolErrorCode.frameTooLarge,
        'Event batch is ${bytes.length} bytes',
      );
    }
    if (bytes.length < ProtocolLimits.headerBytes) {
      _eventFail(
        ProtocolErrorCode.truncatedInput,
        'Event batch is shorter than the fixed header',
      );
    }
    final reader = _EventReader(bytes);
    if (!_eventBytesEqual(reader.bytes(4), const [0x42, 0x46, 0x46, 0x52])) {
      _eventFail(ProtocolErrorCode.invalidMagic, 'Invalid frame magic');
    }
    final major = reader.uint16();
    final minor = reader.uint16();
    if (major != ProtocolVersion.protocolMajor ||
        minor > ProtocolVersion.protocolMinor) {
      _eventFail(
        ProtocolErrorCode.unsupportedVersion,
        'Unsupported protocol version $major.$minor',
      );
    }
    if (reader.uint16() != ProtocolLimits.headerBytes) {
      _eventFail(ProtocolErrorCode.invalidHeader, 'Invalid header size');
    }
    if (reader.uint8() != FrameKindId.eventBatch) {
      _eventFail(
        ProtocolErrorCode.invalidFrameKind,
        'Expected an event-batch frame',
      );
    }
    if (reader.uint8() != 0) {
      _eventFail(ProtocolErrorCode.invalidFlags, 'Unsupported frame flags');
    }
    final runtimeEpoch = reader.uint64();
    final baseRevision = reader.uint64();
    final targetSequence = reader.uint64();
    final payloadLength = reader.uint32();
    if (reader.uint32() != 0 || reader.uint32() != 0) {
      _eventFail(
        ProtocolErrorCode.invalidHeader,
        'Reserved header fields must be zero',
      );
    }
    if (payloadLength != reader.remaining) {
      _eventFail(
        ProtocolErrorCode.invalidPayloadLength,
        'Payload length does not match the event batch',
      );
    }
    final payload = reader.subReader(payloadLength);
    final count = payload.uint32();
    if (count > ProtocolLimits.maxOperations) {
      _eventFail(
        ProtocolErrorCode.tooManyOperations,
        'Event count $count exceeds the limit',
      );
    }
    final events = <UiEvent>[];
    var previousSequence = -1;
    for (var index = 0; index < count; index += 1) {
      final event = _readEvent(payload.subReader(payload.uint32()));
      if (event.sequence <= previousSequence) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Event sequences must be strictly increasing',
        );
      }
      previousSequence = event.sequence;
      events.add(event);
    }
    payload.requireDone();
    if (events.isEmpty) {
      if (baseRevision != 0 || targetSequence != 0) {
        _eventFail(
          ProtocolErrorCode.invalidHeader,
          'Empty event batches require zero revision and sequence',
        );
      }
    } else if (baseRevision != events.first.displayedRevision ||
        targetSequence != events.last.sequence) {
      _eventFail(
        ProtocolErrorCode.invalidHeader,
        'Header event metadata does not match the payload',
      );
    }
    return EventBatch(runtimeEpoch: runtimeEpoch, events: events);
  }

  static void _writeEvent(_EventWriter writer, UiEvent event) {
    _checkEventUint64('event sequence', event.sequence);
    _checkEventUint64('displayed revision', event.displayedRevision);
    _checkEventUint64('node ID', event.nodeId);
    _checkEventUint64('handler ID', event.handlerId);
    writer
      ..uint64(event.sequence)
      ..uint64(event.displayedRevision)
      ..uint64(event.nodeId)
      ..uint64(event.handlerId)
      ..uint16(event.eventTag);
    _writePayload(writer, event.eventTag, event.payload);
  }

  static UiEvent _readEvent(_EventReader reader) {
    final sequence = reader.uint64();
    final displayedRevision = reader.uint64();
    final nodeId = reader.uint64();
    final handlerId = reader.uint64();
    final eventTag = reader.uint16();
    final payload = _readPayload(reader, eventTag);
    reader.requireDone();
    return UiEvent(
      sequence: sequence,
      displayedRevision: displayedRevision,
      nodeId: nodeId,
      handlerId: handlerId,
      eventTag: eventTag,
      payload: payload,
    );
  }

  static void _writePayload(
    _EventWriter writer,
    int eventTag,
    EventPayload payload,
  ) {
    if ((eventTag == EventTagId.press ||
            eventTag == EventTagId.longPress ||
            eventTag == EventTagId.resyncRequested ||
            eventTag == EventTagId.textLimitReached ||
            eventTag == EventTagId.delete) &&
        payload is UnitEventPayload) {
      return;
    }
    if ((eventTag == EventTagId.tap || eventTag == EventTagId.doubleTap) &&
        payload is TapEventPayload) {
      _writePointerPosition(
        writer,
        localX: payload.localX,
        localY: payload.localY,
        globalX: payload.globalX,
        globalY: payload.globalY,
      );
      writer.uint8(payload.pointerKind.index);
      return;
    }
    if ((eventTag == EventTagId.pointerEnter ||
            eventTag == EventTagId.pointerLeave ||
            eventTag == EventTagId.pointerDown ||
            eventTag == EventTagId.pointerUp) &&
        payload is PointerEventPayload) {
      _checkEventUint64('pointer ID', payload.pointerId);
      _checkEventUint32('pointer buttons', payload.buttons);
      writer.uint64(payload.pointerId);
      _writePointerPosition(
        writer,
        localX: payload.localX,
        localY: payload.localY,
        globalX: payload.globalX,
        globalY: payload.globalY,
      );
      writer
        ..uint8(payload.pointerKind.index)
        ..uint32(payload.buttons);
      return;
    }
    if ((eventTag == EventTagId.focusChanged ||
            eventTag == EventTagId.valueChanged) &&
        payload is BoolEventPayload) {
      writer.uint8(payload.value ? 1 : 0);
      return;
    }
    if (eventTag == EventTagId.textEdit && payload is TextEditEventPayload) {
      _checkEventUint64('text session ID', payload.sessionId);
      _checkEventUint64('local text revision', payload.localRevision);
      _checkEventUint64('base document revision', payload.baseDocumentRevision);
      _validateEventTextRange(
        payload.text,
        payload.selectionStartUtf16,
        payload.selectionEndUtf16,
      );
      writer
        ..uint64(payload.sessionId)
        ..uint64(payload.localRevision)
        ..uint64(payload.baseDocumentRevision)
        ..string(payload.text)
        ..uint32(payload.selectionStartUtf16)
        ..uint32(payload.selectionEndUtf16);
      final composingStart = payload.composingStartUtf16;
      final composingEnd = payload.composingEndUtf16;
      if (composingStart == null && composingEnd == null) {
        writer.uint8(0);
      } else if (composingStart != null && composingEnd != null) {
        _validateEventTextRange(payload.text, composingStart, composingEnd);
        writer
          ..uint8(1)
          ..uint32(composingStart)
          ..uint32(composingEnd);
      } else {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Composing range must provide both offsets',
        );
      }
      return;
    }
    if (eventTag == EventTagId.textSubmit && payload is TextEventPayload) {
      writer.string(payload.value);
      return;
    }
    if (eventTag == EventTagId.key && payload is KeyEventPayload) {
      _checkEventUint64('logical key', payload.logicalKey);
      _checkEventUint64('physical key', payload.physicalKey);
      _checkEventUint32('key modifiers', payload.modifiers);
      writer
        ..uint64(payload.logicalKey)
        ..uint64(payload.physicalKey)
        ..uint8(payload.action.index)
        ..uint32(payload.modifiers);
      return;
    }
    if ((eventTag == EventTagId.animationCompleted ||
            eventTag == EventTagId.semanticsAction) &&
        payload is Int64EventPayload) {
      _checkEventUint64('integer event value', payload.value);
      writer.uint64(payload.value);
      return;
    }
    if ((eventTag == EventTagId.navigationDestinationSelected ||
            eventTag == EventTagId.radioSelected) &&
        payload is Int64EventPayload) {
      writer.int64(payload.value);
      return;
    }
    if ((eventTag == EventTagId.sliderChanged ||
            eventTag == EventTagId.sliderChangeEnd) &&
        payload is FloatEventPayload) {
      if (!payload.value.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Slider value must be finite',
        );
      }
      writer.float64(payload.value);
      return;
    }
    if ((eventTag == EventTagId.rangeSliderChanged ||
            eventTag == EventTagId.rangeSliderChangeEnd) &&
        payload is FloatRangeEventPayload) {
      if (!payload.start.isFinite || !payload.end.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Range slider values must be finite',
        );
      }
      if (payload.start > payload.end) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Range slider is reversed');
      }
      writer
        ..float64(payload.start)
        ..float64(payload.end);
      return;
    }
    if (eventTag == EventTagId.scrollNotification &&
        payload is ScrollEventPayload) {
      if (!payload.pixels.isFinite || !payload.delta.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Scroll values must be finite',
        );
      }
      writer
        ..float64(payload.pixels)
        ..float64(payload.delta);
      return;
    }
    if (eventTag == EventTagId.visibleRangeChanged &&
        payload is VisibleRangeEventPayload) {
      _checkEventUint64('first visible index', payload.firstIndex);
      _checkEventUint64('last visible index', payload.lastExclusive);
      if (payload.lastExclusive < payload.firstIndex) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Visible range is reversed');
      }
      writer
        ..uint64(payload.firstIndex)
        ..uint64(payload.lastExclusive);
      return;
    }
    if (eventTag == EventTagId.routePop && payload is RoutePopEventPayload) {
      if (payload.pageKey.isEmpty) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Route page key is empty');
      }
      writer.string(payload.pageKey);
      final result = payload.result;
      if (result == null) {
        writer.uint8(0);
      } else {
        writer
          ..uint8(1)
          ..string(result);
      }
      return;
    }
    if (eventTag == EventTagId.hostResponse &&
        payload is HostResponseEventPayload) {
      _checkEventUint64('host request ID', payload.requestId);
      writer
        ..uint64(payload.requestId)
        ..uint8(payload.status.index)
        ..uint32(payload.value.length)
        ..raw(payload.value);
      return;
    }
    if (eventTag == EventTagId.applicationResponse &&
        payload is ApplicationResponseEventPayload) {
      _checkApplicationRequestId(payload.requestId);
      writer
        ..uint64(payload.requestId)
        ..applicationPayload(payload.payload);
      return;
    }
    if (eventTag == EventTagId.applicationRequestError &&
        payload is ApplicationRequestErrorEventPayload) {
      _checkApplicationRequestId(payload.requestId);
      writer
        ..uint64(payload.requestId)
        ..uint8(payload.error.code.wireId)
        ..applicationErrorMessage(payload.error.message);
      return;
    }
    if (eventTag == EventTagId.applicationEvent &&
        payload is ApplicationEventPayload) {
      writer.applicationPayload(payload.payload);
      return;
    }
    if (eventTag == EventTagId.environmentChanged &&
        payload is EnvironmentEventPayload) {
      final snapshot = payload.snapshot;
      final dimensions = [
        snapshot.viewportWidth,
        snapshot.viewportHeight,
        snapshot.devicePixelRatio,
        snapshot.textScale,
      ];
      if (dimensions.any((value) => !value.isFinite) ||
          snapshot.viewportWidth < 0 ||
          snapshot.viewportHeight < 0 ||
          snapshot.devicePixelRatio <= 0 ||
          snapshot.textScale <= 0) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Environment dimensions and scales are invalid',
        );
      }
      writer
        ..float64(snapshot.viewportWidth)
        ..float64(snapshot.viewportHeight)
        ..float64(snapshot.devicePixelRatio)
        ..float64(snapshot.textScale)
        ..uint8(snapshot.brightness.index)
        ..string(snapshot.platform)
        ..string(snapshot.locale);
      _writeEnvironmentInsets(writer, snapshot.safeArea);
      _writeEnvironmentInsets(writer, snapshot.keyboardInsets);
      writer
        ..uint8(snapshot.accessibleNavigation ? 1 : 0)
        ..uint8(snapshot.boldText ? 1 : 0)
        ..uint8(snapshot.invertColors ? 1 : 0)
        ..uint8(snapshot.disableAnimations ? 1 : 0)
        ..uint8(snapshot.reducedMotion ? 1 : 0)
        ..uint8(snapshot.highContrast ? 1 : 0)
        ..uint8(snapshot.orientation.index)
        ..uint32(snapshot.pointerKinds);
      return;
    }
    if (eventTag == EventTagId.nativeEvent && payload is NativeEventPayload) {
      if (payload.kindId <= 0 || payload.kindId > 0xffffffff) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Native event kind ID is outside u32',
        );
      }
      if (payload.version <= 0 ||
          payload.version > 0xffff ||
          payload.eventId <= 0 ||
          payload.eventId > 0xffff) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Native event version and event ID must be in 1..65535',
        );
      }
      writer
        ..uint32(payload.kindId)
        ..uint16(payload.version)
        ..uint16(payload.eventId)
        ..uint32(payload.payload.length)
        ..raw(payload.payload);
      return;
    }
    _eventFail(
      ProtocolErrorCode.invalidEventTag,
      'Event tag $eventTag is unsupported or has the wrong payload',
    );
  }

  static EventPayload _readPayload(_EventReader reader, int eventTag) {
    if (eventTag == EventTagId.press ||
        eventTag == EventTagId.longPress ||
        eventTag == EventTagId.resyncRequested ||
        eventTag == EventTagId.textLimitReached ||
        eventTag == EventTagId.delete) {
      return const UnitEventPayload();
    }
    if (eventTag == EventTagId.tap || eventTag == EventTagId.doubleTap) {
      final position = _readPointerPosition(reader);
      return TapEventPayload(
        localX: position.$1,
        localY: position.$2,
        globalX: position.$3,
        globalY: position.$4,
        pointerKind: _readPointerKind(reader),
      );
    }
    if (eventTag == EventTagId.pointerEnter ||
        eventTag == EventTagId.pointerLeave ||
        eventTag == EventTagId.pointerDown ||
        eventTag == EventTagId.pointerUp) {
      final pointerId = reader.uint64();
      final position = _readPointerPosition(reader);
      return PointerEventPayload(
        pointerId: pointerId,
        localX: position.$1,
        localY: position.$2,
        globalX: position.$3,
        globalY: position.$4,
        pointerKind: _readPointerKind(reader),
        buttons: reader.uint32(),
      );
    }
    if (eventTag == EventTagId.focusChanged ||
        eventTag == EventTagId.valueChanged) {
      return BoolEventPayload(reader.boolean());
    }
    if (eventTag == EventTagId.textEdit) {
      final sessionId = reader.uint64();
      final localRevision = reader.uint64();
      final baseDocumentRevision = reader.uint64();
      final text = reader.string();
      final selectionStartUtf16 = reader.uint32();
      final selectionEndUtf16 = reader.uint32();
      _validateEventTextRange(text, selectionStartUtf16, selectionEndUtf16);
      final (composingStartUtf16, composingEndUtf16) = switch (reader.uint8()) {
        0 => (null, null),
        1 => (reader.uint32(), reader.uint32()),
        final value => _eventFail(
          ProtocolErrorCode.invalidProps,
          'Invalid composing tag $value',
        ),
      };
      if (composingStartUtf16 != null && composingEndUtf16 != null) {
        _validateEventTextRange(text, composingStartUtf16, composingEndUtf16);
      }
      return TextEditEventPayload(
        sessionId: sessionId,
        localRevision: localRevision,
        baseDocumentRevision: baseDocumentRevision,
        text: text,
        selectionStartUtf16: selectionStartUtf16,
        selectionEndUtf16: selectionEndUtf16,
        composingStartUtf16: composingStartUtf16,
        composingEndUtf16: composingEndUtf16,
      );
    }
    if (eventTag == EventTagId.textSubmit) {
      return TextEventPayload(reader.string());
    }
    if (eventTag == EventTagId.key) {
      return KeyEventPayload(
        logicalKey: reader.uint64(),
        physicalKey: reader.uint64(),
        action: _eventEnumValue(
          KeyActionValue.values,
          reader.uint8(),
          'key action',
        ),
        modifiers: reader.uint32(),
      );
    }
    if (eventTag == EventTagId.animationCompleted ||
        eventTag == EventTagId.semanticsAction) {
      return Int64EventPayload(reader.uint64());
    }
    if (eventTag == EventTagId.navigationDestinationSelected ||
        eventTag == EventTagId.radioSelected) {
      return Int64EventPayload(reader.int64());
    }
    if (eventTag == EventTagId.sliderChanged ||
        eventTag == EventTagId.sliderChangeEnd) {
      final value = reader.float64();
      if (!value.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Slider value must be finite',
        );
      }
      return FloatEventPayload(value);
    }
    if (eventTag == EventTagId.rangeSliderChanged ||
        eventTag == EventTagId.rangeSliderChangeEnd) {
      final start = reader.float64();
      final end = reader.float64();
      if (!start.isFinite || !end.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Range slider values must be finite',
        );
      }
      if (start > end) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Range slider is reversed');
      }
      return FloatRangeEventPayload(start: start, end: end);
    }
    if (eventTag == EventTagId.scrollNotification) {
      final pixels = reader.float64();
      final delta = reader.float64();
      if (!pixels.isFinite || !delta.isFinite) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Scroll values must be finite',
        );
      }
      return ScrollEventPayload(pixels: pixels, delta: delta);
    }
    if (eventTag == EventTagId.visibleRangeChanged) {
      final firstIndex = reader.uint64();
      final lastExclusive = reader.uint64();
      if (lastExclusive < firstIndex) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Visible range is reversed');
      }
      return VisibleRangeEventPayload(
        firstIndex: firstIndex,
        lastExclusive: lastExclusive,
      );
    }
    if (eventTag == EventTagId.routePop) {
      final pageKey = reader.string();
      if (pageKey.isEmpty) {
        _eventFail(ProtocolErrorCode.invalidProps, 'Route page key is empty');
      }
      final result = switch (reader.uint8()) {
        0 => null,
        1 => reader.string(),
        final value => _eventFail(
          ProtocolErrorCode.invalidProps,
          'Invalid optional route result tag $value',
        ),
      };
      return RoutePopEventPayload(pageKey: pageKey, result: result);
    }
    if (eventTag == EventTagId.hostResponse) {
      final requestId = reader.uint64();
      final statusIndex = reader.uint8();
      if (statusIndex >= HostResponseStatus.values.length) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Invalid host response status $statusIndex',
        );
      }
      final value = reader.bytes(reader.uint32());
      return HostResponseEventPayload(
        requestId: requestId,
        status: HostResponseStatus.values[statusIndex],
        value: List.unmodifiable(value),
      );
    }
    if (eventTag == EventTagId.applicationResponse) {
      final requestId = reader.uint64();
      _checkApplicationRequestId(requestId);
      return ApplicationResponseEventPayload(
        requestId: requestId,
        payload: reader.applicationPayload(),
      );
    }
    if (eventTag == EventTagId.applicationRequestError) {
      final requestId = reader.uint64();
      _checkApplicationRequestId(requestId);
      final codeValue = reader.uint8();
      final ApplicationPlatformErrorCode code;
      try {
        code = ApplicationPlatformErrorCode.fromWireId(codeValue);
      } on StateError {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Unknown application platform error code $codeValue',
        );
      }
      return ApplicationRequestErrorEventPayload(
        requestId: requestId,
        error: ApplicationPlatformBridgeError(
          code: code,
          message: reader.applicationErrorMessage(),
        ),
      );
    }
    if (eventTag == EventTagId.applicationEvent) {
      return ApplicationEventPayload(payload: reader.applicationPayload());
    }
    if (eventTag == EventTagId.environmentChanged) {
      final viewportWidth = reader.float64();
      final viewportHeight = reader.float64();
      final devicePixelRatio = reader.float64();
      final textScale = reader.float64();
      if (!viewportWidth.isFinite ||
          !viewportHeight.isFinite ||
          !devicePixelRatio.isFinite ||
          !textScale.isFinite ||
          viewportWidth < 0 ||
          viewportHeight < 0 ||
          devicePixelRatio <= 0 ||
          textScale <= 0) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Environment dimensions and scales are invalid',
        );
      }
      final brightnessIndex = reader.uint8();
      if (brightnessIndex >= EnvironmentBrightness.values.length) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Invalid environment brightness $brightnessIndex',
        );
      }
      final platform = reader.string();
      final locale = reader.string();
      final safeArea = _readEnvironmentInsets(reader);
      final keyboardInsets = _readEnvironmentInsets(reader);
      final accessibleNavigation = reader.boolean();
      final boldText = reader.boolean();
      final invertColors = reader.boolean();
      final disableAnimations = reader.boolean();
      final reducedMotion = reader.boolean();
      final highContrast = reader.boolean();
      final orientationIndex = reader.uint8();
      if (orientationIndex >= EnvironmentOrientation.values.length) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Invalid environment orientation $orientationIndex',
        );
      }
      return EnvironmentEventPayload(
        EnvironmentSnapshot(
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
          devicePixelRatio: devicePixelRatio,
          textScale: textScale,
          brightness: EnvironmentBrightness.values[brightnessIndex],
          platform: platform,
          locale: locale,
          safeArea: safeArea,
          keyboardInsets: keyboardInsets,
          accessibleNavigation: accessibleNavigation,
          boldText: boldText,
          invertColors: invertColors,
          disableAnimations: disableAnimations,
          reducedMotion: reducedMotion,
          highContrast: highContrast,
          orientation: EnvironmentOrientation.values[orientationIndex],
          pointerKinds: reader.uint32(),
        ),
      );
    }
    if (eventTag == EventTagId.nativeEvent) {
      final kindId = reader.uint32();
      final version = reader.uint16();
      final eventId = reader.uint16();
      if (kindId == 0 || version == 0 || eventId == 0) {
        _eventFail(
          ProtocolErrorCode.invalidProps,
          'Native event identifiers must be positive',
        );
      }
      return NativeEventPayload(
        kindId: kindId,
        version: version,
        eventId: eventId,
        payload: reader.bytes(reader.uint32()),
      );
    }
    _eventFail(
      ProtocolErrorCode.invalidEventTag,
      'Unsupported event tag $eventTag',
    );
  }
}

final class _EventWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void uint8(int value) => _builder.add([value & 0xff]);

  void uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void uint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void int64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    raw(data.buffer.asUint8List());
  }

  void float64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void raw(List<int> bytes) => _builder.add(bytes);

  void string(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > ProtocolLimits.maxStringBytes) {
      _eventFail(
        ProtocolErrorCode.stringTooLarge,
        'String is ${bytes.length} bytes',
      );
    }
    uint32(bytes.length);
    raw(bytes);
  }

  void applicationPayload(List<int> value) {
    if (value.length > ProtocolLimits.maxApplicationPayloadBytes) {
      _eventFail(
        ProtocolErrorCode.applicationPayloadTooLarge,
        'Application payload is ${value.length} bytes',
      );
    }
    uint32(value.length);
    raw(value);
  }

  void applicationErrorMessage(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > maximumApplicationPlatformErrorBytes) {
      _eventFail(
        ProtocolErrorCode.stringTooLarge,
        'Application error is ${bytes.length} bytes',
      );
    }
    uint32(bytes.length);
    raw(bytes);
  }

  void envelope(void Function(_EventWriter) writeBody) {
    final body = _EventWriter();
    writeBody(body);
    final bytes = body.takeBytes();
    uint32(bytes.length);
    raw(bytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

void _writeEnvironmentInsets(_EventWriter writer, EnvironmentInsets insets) {
  final values = [insets.left, insets.top, insets.right, insets.bottom];
  if (values.any((value) => !value.isFinite)) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      'Environment insets must be finite',
    );
  }
  for (final value in values) {
    writer.float64(value);
  }
}

EnvironmentInsets _readEnvironmentInsets(_EventReader reader) =>
    EnvironmentInsets(
      left: reader.float64(),
      top: reader.float64(),
      right: reader.float64(),
      bottom: reader.float64(),
    );

final class _EventReader {
  _EventReader(this._bytes, [this._position = 0, int? limit])
    : _limit = limit ?? _bytes.length;

  final Uint8List _bytes;
  int _position;
  final int _limit;

  int get remaining => _limit - _position;

  int uint8() {
    _require(1);
    return _bytes[_position++];
  }

  int uint16() {
    _require(2);
    final value = ByteData.sublistView(
      _bytes,
      _position,
      _position + 2,
    ).getUint16(0, Endian.little);
    _position += 2;
    return value;
  }

  int uint32() {
    _require(4);
    final value = ByteData.sublistView(
      _bytes,
      _position,
      _position + 4,
    ).getUint32(0, Endian.little);
    _position += 4;
    return value;
  }

  int uint64() {
    _require(8);
    final value = ByteData.sublistView(
      _bytes,
      _position,
      _position + 8,
    ).getUint64(0, Endian.little);
    _position += 8;
    if (value > 0x7fffffffffffffff) {
      _eventFail(
        ProtocolErrorCode.invalidProps,
        'u64 exceeds the supported positive int64 range',
      );
    }
    return value;
  }

  int int64() {
    _require(8);
    final result = ByteData.sublistView(
      _bytes,
      _position,
      _position + 8,
    ).getInt64(0, Endian.little);
    _position += 8;
    return result;
  }

  double float64() {
    _require(8);
    final value = ByteData.sublistView(
      _bytes,
      _position,
      _position + 8,
    ).getFloat64(0, Endian.little);
    _position += 8;
    return value;
  }

  bool boolean() {
    final value = uint8();
    if (value == 0) return false;
    if (value == 1) return true;
    _eventFail(ProtocolErrorCode.invalidProps, 'Invalid bool $value');
  }

  Uint8List bytes(int length) {
    _require(length);
    final value = Uint8List.sublistView(_bytes, _position, _position + length);
    _position += length;
    return value;
  }

  String string() {
    final length = uint32();
    if (length > ProtocolLimits.maxStringBytes) {
      _eventFail(ProtocolErrorCode.stringTooLarge, 'String is $length bytes');
    }
    try {
      return utf8.decode(bytes(length), allowMalformed: false);
    } on FormatException {
      _eventFail(ProtocolErrorCode.invalidUtf8, 'String is not valid UTF-8');
    }
  }

  Uint8List applicationPayload() {
    final length = uint32();
    if (length > ProtocolLimits.maxApplicationPayloadBytes) {
      _eventFail(
        ProtocolErrorCode.applicationPayloadTooLarge,
        'Application payload is $length bytes',
      );
    }
    return Uint8List.fromList(bytes(length));
  }

  String applicationErrorMessage() {
    final length = uint32();
    if (length > maximumApplicationPlatformErrorBytes) {
      _eventFail(
        ProtocolErrorCode.stringTooLarge,
        'Application error is $length bytes',
      );
    }
    try {
      return utf8.decode(bytes(length), allowMalformed: false);
    } on FormatException {
      _eventFail(
        ProtocolErrorCode.invalidUtf8,
        'Application error is not UTF-8',
      );
    }
  }

  _EventReader subReader(int length) {
    _require(length);
    final reader = _EventReader(_bytes, _position, _position + length);
    _position += length;
    return reader;
  }

  void requireDone() {
    if (remaining != 0) {
      _eventFail(
        ProtocolErrorCode.trailingBytes,
        'Event payload has $remaining trailing bytes',
      );
    }
  }

  void _require(int length) {
    if (length < 0 || length > remaining) {
      _eventFail(
        ProtocolErrorCode.truncatedInput,
        'Need $length bytes, only $remaining remain',
      );
    }
  }
}

Never _eventFail(ProtocolErrorCode code, String message) =>
    throw ProtocolException(code, message);

void _checkEventUint32(String label, int value) {
  if (value < 0 || value > 0xffffffff) {
    _eventFail(ProtocolErrorCode.invalidProps, '$label is outside uint32');
  }
}

void _checkEventUint64(String label, int value) {
  if (value < 0 || value > 0x7fffffffffffffff) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      '$label is outside the supported positive int64 range',
    );
  }
}

void _checkApplicationRequestId(int value) {
  if (value <= 0 || value > 0x7fffffffffffffff) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      'Application request ID must be a positive int64',
    );
  }
}

void _writePointerPosition(
  _EventWriter writer, {
  required double localX,
  required double localY,
  required double globalX,
  required double globalY,
}) {
  final values = [localX, localY, globalX, globalY];
  if (values.any((value) => !value.isFinite)) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      'Pointer coordinates must be finite',
    );
  }
  for (final value in values) {
    writer.float64(value);
  }
}

(double, double, double, double) _readPointerPosition(_EventReader reader) {
  final values = (
    reader.float64(),
    reader.float64(),
    reader.float64(),
    reader.float64(),
  );
  if (![
    values.$1,
    values.$2,
    values.$3,
    values.$4,
  ].every((value) => value.isFinite)) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      'Pointer coordinates must be finite',
    );
  }
  return values;
}

PointerKindValue _readPointerKind(_EventReader reader) =>
    _eventEnumValue(PointerKindValue.values, reader.uint8(), 'pointer kind');

T _eventEnumValue<T>(List<T> values, int index, String label) {
  if (index >= values.length) {
    _eventFail(ProtocolErrorCode.invalidProps, 'Invalid $label $index');
  }
  return values[index];
}

void _validateEventTextRange(String text, int start, int end) {
  if (start > end ||
      !_eventIsUtf16Boundary(text, start) ||
      !_eventIsUtf16Boundary(text, end)) {
    _eventFail(
      ProtocolErrorCode.invalidProps,
      'Text range is not on ordered UTF-16 boundaries',
    );
  }
}

bool _eventIsUtf16Boundary(String text, int offset) {
  if (offset < 0 || offset > text.length) return false;
  if (offset == 0 || offset == text.length) return true;
  final previous = text.codeUnitAt(offset - 1);
  final next = text.codeUnitAt(offset);
  return !(previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff);
}

bool _eventBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
