import 'dart:async';
import 'dart:typed_data';

import '../protocol/generated_protocol.dart';

/// Maximum size of one opaque application request, response, or event.
const int maximumApplicationPlatformPayloadBytes =
    ProtocolLimits.maxApplicationPayloadBytes;

/// Maximum UTF-8 size of a sanitized application bridge error message.
const int maximumApplicationPlatformErrorBytes = 4096;

/// Application-owned request handler and ordered event source.
abstract interface class BonsaiFlutterApplicationPlatform {
  Future<Uint8List> handleRequest(Uint8List request);

  Stream<Uint8List> get events;
}

enum ApplicationPlatformErrorCode {
  unavailable(1),
  payloadTooLarge(2),
  handlerFailed(3),
  cancelled(4),
  shutdown(5),
  runtimeReplaced(6),
  invalidResponse(7);

  const ApplicationPlatformErrorCode(this.wireId);

  final int wireId;

  static ApplicationPlatformErrorCode fromWireId(int value) {
    for (final code in values) {
      if (code.wireId == value) return code;
    }
    throw StateError('Unknown application platform error code $value');
  }
}

final class ApplicationPlatformBridgeError {
  const ApplicationPlatformBridgeError({required this.code, this.message = ''});

  final ApplicationPlatformErrorCode code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ApplicationPlatformBridgeError &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}
