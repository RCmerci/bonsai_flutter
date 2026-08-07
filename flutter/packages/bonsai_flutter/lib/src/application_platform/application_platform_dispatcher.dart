import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/renderer_event.dart';
import 'application_platform.dart';

typedef ApplicationPlatformErrorCallback =
    void Function(ApplicationPlatformBridgeError error);

final class ApplicationPlatformDispatcher {
  ApplicationPlatformDispatcher({
    required this.platform,
    required this.onEvent,
    required this.onError,
  });

  final BonsaiFlutterApplicationPlatform? platform;
  final RendererEventCallback onEvent;
  final ApplicationPlatformErrorCallback onError;
  final Map<int, _PendingApplicationRequest> _pending = {};
  StreamSubscription<Uint8List>? _subscription;
  int? _runtimeEpoch;
  int _lastRequestId = 0;
  bool _disposed = false;

  int get pendingRequestCount => _pending.length;
  int? get runtimeEpoch => _runtimeEpoch;

  void activate({required int runtimeEpoch}) {
    if (_disposed) {
      throw StateError('ApplicationPlatformDispatcher has been disposed');
    }
    if (_runtimeEpoch != null) {
      throw StateError('ApplicationPlatformDispatcher is already active');
    }
    if (runtimeEpoch <= 0) {
      throw ArgumentError.value(
        runtimeEpoch,
        'runtimeEpoch',
        'must be positive',
      );
    }
    _runtimeEpoch = runtimeEpoch;
    final platform = this.platform;
    if (platform == null) return;
    try {
      _subscription = platform.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          if (_disposed) return;
          onError(
            ApplicationPlatformBridgeError(
              code: ApplicationPlatformErrorCode.handlerFailed,
              message: _boundedErrorMessage(error),
            ),
          );
        },
        cancelOnError: false,
      );
    } catch (error) {
      onError(
        ApplicationPlatformBridgeError(
          code: ApplicationPlatformErrorCode.handlerFailed,
          message: _boundedErrorMessage(error),
        ),
      );
    }
  }

  Future<void> dispatch(Frame frame) async {
    if (_disposed) return;
    final runtimeEpoch = _runtimeEpoch;
    if (runtimeEpoch == null) {
      throw StateError('ApplicationPlatformDispatcher is not active');
    }
    if (frame.runtimeEpoch != runtimeEpoch) {
      onError(
        const ApplicationPlatformBridgeError(
          code: ApplicationPlatformErrorCode.runtimeReplaced,
          message: 'Application request belongs to a stale runtime epoch',
        ),
      );
      return;
    }
    await Future.wait([
      for (final operation in frame.operations)
        if (operation is ApplicationRequestOperation) _start(operation),
    ]);
  }

  Future<void> _start(ApplicationRequestOperation operation) async {
    if (operation.requestId <= _lastRequestId ||
        _pending.containsKey(operation.requestId)) {
      onError(
        const ApplicationPlatformBridgeError(
          code: ApplicationPlatformErrorCode.invalidResponse,
          message: 'Duplicate application request ID',
        ),
      );
      return;
    }
    _lastRequestId = operation.requestId;
    final pending = _PendingApplicationRequest();
    _pending[operation.requestId] = pending;
    final platform = this.platform;
    if (platform == null) {
      _pending.remove(operation.requestId);
      _emitError(operation.requestId, ApplicationPlatformErrorCode.unavailable);
      return;
    }
    try {
      final request = Uint8List.fromList(operation.payload);
      if (request.length > ProtocolLimits.maxApplicationPayloadBytes) {
        _emitError(
          operation.requestId,
          ApplicationPlatformErrorCode.payloadTooLarge,
        );
        return;
      }
      final response = await platform.handleRequest(request);
      if (_disposed || !identical(_pending[operation.requestId], pending)) {
        return;
      }
      if (response.length > ProtocolLimits.maxApplicationPayloadBytes) {
        _emitError(
          operation.requestId,
          ApplicationPlatformErrorCode.payloadTooLarge,
        );
      } else {
        onEvent(
          RendererEvent(
            nodeId: 0,
            eventTag: EventTagId.applicationResponse,
            handlerId: 0,
            payload: ApplicationResponseEventPayload(
              requestId: operation.requestId,
              payload: Uint8List.fromList(response),
            ),
          ),
        );
      }
    } catch (error) {
      if (_disposed || !identical(_pending[operation.requestId], pending)) {
        return;
      }
      _emitError(
        operation.requestId,
        ApplicationPlatformErrorCode.handlerFailed,
        _boundedErrorMessage(error),
      );
    } finally {
      if (identical(_pending[operation.requestId], pending)) {
        _pending.remove(operation.requestId);
      }
    }
  }

  void _handleEvent(Uint8List event) {
    if (_disposed || _runtimeEpoch == null) return;
    if (event.length > ProtocolLimits.maxApplicationPayloadBytes) {
      onError(
        const ApplicationPlatformBridgeError(
          code: ApplicationPlatformErrorCode.payloadTooLarge,
          message: 'Application event exceeds the payload limit',
        ),
      );
      return;
    }
    onEvent(
      RendererEvent(
        nodeId: 0,
        eventTag: EventTagId.applicationEvent,
        handlerId: 0,
        payload: ApplicationEventPayload(payload: Uint8List.fromList(event)),
      ),
    );
  }

  void _emitError(
    int requestId,
    ApplicationPlatformErrorCode code, [
    String message = '',
  ]) {
    if (_disposed) return;
    onEvent(
      RendererEvent(
        nodeId: 0,
        eventTag: EventTagId.applicationRequestError,
        handlerId: 0,
        payload: ApplicationRequestErrorEventPayload(
          requestId: requestId,
          error: ApplicationPlatformBridgeError(code: code, message: message),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _runtimeEpoch = null;
    _pending.clear();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) await subscription.cancel();
  }
}

final class _PendingApplicationRequest {}

String _boundedErrorMessage(Object error) {
  final value = error.toString();
  final encoded = utf8.encode(value);
  if (encoded.length <= maximumApplicationPlatformErrorBytes) return value;
  final output = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (used + length > maximumApplicationPlatformErrorBytes) break;
    output.write(character);
    used += length;
  }
  return output.toString();
}
