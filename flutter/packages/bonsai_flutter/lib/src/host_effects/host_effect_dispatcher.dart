import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/renderer_resource_store.dart';
import '../renderer/widget_registry.dart';

sealed class HostEffectValue {
  const HostEffectValue();
}

final class HostUnitValue extends HostEffectValue {
  const HostUnitValue();
}

final class HostStringValue extends HostEffectValue {
  const HostStringValue(this.value);
  final String value;
}

final class HostBytesValue extends HostEffectValue {
  const HostBytesValue(this.value);
  final List<int> value;
}

final class HostOptionalFileValue extends HostEffectValue {
  const HostOptionalFileValue({this.path, this.data});
  final String? path;
  final List<int>? data;
}

final class HostMenuValue extends HostEffectValue {
  const HostMenuValue(this.itemId);
  final String? itemId;
}

final class HostPlatformInformationValue extends HostEffectValue {
  const HostPlatformInformationValue({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.localeName,
  });

  final String operatingSystem;
  final String operatingSystemVersion;
  final String localeName;
}

final class HostLayoutValue extends HostEffectValue {
  const HostLayoutValue({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

final class HostCancelledValue extends HostEffectValue {
  const HostCancelledValue();
}

final class HostEffectException implements Exception {
  const HostEffectException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class HostEffectImplementation {
  Future<HostEffectValue> execute(int requestId, HostRequest request);
  Future<void> cancel(int requestId);
}

final class FlutterHostEffectImplementation
    implements HostEffectImplementation {
  const FlutterHostEffectImplementation({this.resources});

  final RendererHostResources? resources;

  @override
  Future<HostEffectValue> execute(int requestId, HostRequest request) async {
    switch (request) {
      case ClipboardReadRequest():
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return HostStringValue(data?.text ?? '');
      case ClipboardWriteRequest(:final text):
        await Clipboard.setData(ClipboardData(text: text));
        return const HostUnitValue();
      case ClearFocusRequest():
        FocusManager.instance.primaryFocus?.unfocus();
        return const HostUnitValue();
      case RequestFocusRequest(:final nodeId):
        await _requireResources(request).requestFocus(nodeId);
        return const HostUnitValue();
      case ScrollToRequest(:final nodeId, :final alignment, :final animated):
        await _requireResources(
          request,
        ).scrollTo(nodeId, alignment: alignment, animated: animated);
        return const HostUnitValue();
      case HapticFeedbackRequest(:final kind):
        await switch (kind) {
          HapticKind.light => HapticFeedback.lightImpact(),
          HapticKind.medium => HapticFeedback.mediumImpact(),
          HapticKind.heavy => HapticFeedback.heavyImpact(),
          HapticKind.selection => HapticFeedback.selectionClick(),
        };
        return const HostUnitValue();
      case PlatformInformationRequest():
        return HostPlatformInformationValue(
          operatingSystem: Platform.operatingSystem,
          operatingSystemVersion: Platform.operatingSystemVersion,
          localeName: Platform.localeName,
        );
      default:
        throw HostEffectException(
          '${request.runtimeType} requires an injected platform implementation',
        );
    }
  }

  @override
  Future<void> cancel(int requestId) async {}

  RendererHostResources _requireResources(HostRequest request) {
    final resources = this.resources;
    if (resources == null) {
      throw HostEffectException(
        '${request.runtimeType} requires renderer resources',
      );
    }
    return resources;
  }
}

final class HostEffectDispatcher {
  HostEffectDispatcher({required this.implementation, required this.onEvent});

  final HostEffectImplementation implementation;
  final RendererEventCallback onEvent;
  final Map<int, _PendingHostRequest> _pending = {};
  final Set<int> _seen = {};
  bool _disposed = false;

  int get pendingRequestCount => _pending.length;

  Future<void> dispatch(Frame frame) async {
    if (_disposed) {
      throw StateError('HostEffectDispatcher has been disposed');
    }
    final completions = <Future<void>>[];
    for (final operation in frame.operations) {
      switch (operation) {
        case HostRequestOperation():
          completions.add(_start(operation));
        case CancelHostRequestOperation():
          completions.add(_cancel(operation.requestId));
        default:
          break;
      }
    }
    await Future.wait(completions);
  }

  Future<void> _start(HostRequestOperation operation) async {
    if (!_seen.add(operation.requestId)) {
      throw StateError('Duplicate host request ID ${operation.requestId}');
    }
    final pending = _PendingHostRequest();
    _pending[operation.requestId] = pending;
    HostResponseStatus status;
    List<int> value;
    try {
      final result = await implementation.execute(
        operation.requestId,
        operation.request,
      );
      if (pending.cancelled || result is HostCancelledValue) {
        status = HostResponseStatus.cancelled;
        value = const [];
      } else {
        status = HostResponseStatus.ok;
        value = _encodeValue(result);
      }
    } catch (error) {
      if (pending.cancelled) {
        status = HostResponseStatus.cancelled;
        value = const [];
      } else {
        status = HostResponseStatus.error;
        value = utf8.encode(
          error is HostEffectException ? error.message : error.toString(),
        );
      }
    } finally {
      _pending.remove(operation.requestId);
    }
    if (_disposed) return;
    onEvent(
      RendererEvent(
        nodeId: 0,
        eventTag: EventTagId.hostResponse,
        handlerId: 0,
        payload: HostResponseEventPayload(
          requestId: operation.requestId,
          status: status,
          value: List.unmodifiable(value),
        ),
      ),
    );
  }

  Future<void> _cancel(int requestId) async {
    final pending = _pending[requestId];
    if (pending == null) return;
    pending.cancelled = true;
    await implementation.cancel(requestId);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final requestIds = _pending.keys.toList(growable: false);
    for (final requestId in requestIds) {
      _pending[requestId]!.cancelled = true;
    }
    await Future.wait([
      for (final requestId in requestIds) implementation.cancel(requestId),
    ]);
  }
}

final class _PendingHostRequest {
  bool cancelled = false;
}

List<int> _encodeValue(HostEffectValue value) => switch (value) {
  HostUnitValue() => const [],
  HostStringValue(:final value) => utf8.encode(value),
  HostBytesValue(:final value) => List<int>.of(value),
  HostOptionalFileValue(:final path, :final data) => () {
    final writer = _HostValueWriter();
    if (path == null && data == null) {
      writer.uint8(0);
    } else {
      writer
        ..uint8(1)
        ..optionalString(path)
        ..optionalBytes(data);
    }
    return writer.takeBytes();
  }(),
  HostMenuValue(:final itemId) => () {
    final writer = _HostValueWriter()..optionalString(itemId);
    return writer.takeBytes();
  }(),
  HostPlatformInformationValue(
    :final operatingSystem,
    :final operatingSystemVersion,
    :final localeName,
  ) =>
    () {
      final writer = _HostValueWriter()
        ..string(operatingSystem)
        ..string(operatingSystemVersion)
        ..string(localeName);
      return writer.takeBytes();
    }(),
  HostLayoutValue(:final left, :final top, :final width, :final height) => () {
    final data = ByteData(32)
      ..setFloat64(0, left, Endian.little)
      ..setFloat64(8, top, Endian.little)
      ..setFloat64(16, width, Endian.little)
      ..setFloat64(24, height, Endian.little);
    return data.buffer.asUint8List();
  }(),
  HostCancelledValue() => const [],
};

final class _HostValueWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void uint8(int value) => _builder.add([value & 0xff]);

  void uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void raw(List<int> value) => _builder.add(value);

  void string(String value) {
    final encoded = utf8.encode(value);
    uint32(encoded.length);
    raw(encoded);
  }

  void optionalString(String? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      string(value);
    }
  }

  void optionalBytes(List<int>? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      uint32(value.length);
      raw(value);
    }
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
