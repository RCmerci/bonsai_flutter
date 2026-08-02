import 'dart:convert';
import 'dart:typed_data';

enum RuntimeLaunchPolicy { fresh, replaceExisting }

final class RuntimeBootstrapConfig {
  RuntimeBootstrapConfig({
    required String entrypoint,
    required this.launchPolicy,
    Uint8List? applicationPayload,
  }) : entrypoint = _validateEntrypoint(entrypoint),
       _applicationPayload = Uint8List.fromList(
         applicationPayload ?? Uint8List(0),
       ) {
    if (_applicationPayload.length > _maximumPayloadLength) {
      throw ArgumentError.value(
        _applicationPayload.length,
        'applicationPayload',
        'must be at most 1 MiB',
      );
    }
  }

  static const _headerLength = 20;
  static const _maximumEntrypointLength = 255;
  static const _maximumPayloadLength = 1024 * 1024;

  final String entrypoint;
  final RuntimeLaunchPolicy launchPolicy;
  final Uint8List _applicationPayload;

  Uint8List encode() {
    final entrypointBytes = utf8.encode(entrypoint);
    final encoded = Uint8List(
      _headerLength + entrypointBytes.length + _applicationPayload.length,
    );
    encoded.setRange(0, 4, ascii.encode('BFR1'));
    final data = ByteData.sublistView(encoded);
    data.setUint16(4, 1, Endian.little);
    data.setUint16(6, 0, Endian.little);
    encoded[8] = switch (launchPolicy) {
      RuntimeLaunchPolicy.fresh => 0,
      RuntimeLaunchPolicy.replaceExisting => 1,
    };
    data.setUint32(12, entrypointBytes.length, Endian.little);
    data.setUint32(16, _applicationPayload.length, Endian.little);
    encoded.setRange(
      _headerLength,
      _headerLength + entrypointBytes.length,
      entrypointBytes,
    );
    encoded.setRange(
      _headerLength + entrypointBytes.length,
      encoded.length,
      _applicationPayload,
    );
    return encoded;
  }

  static String _validateEntrypoint(String entrypoint) {
    final encoded = utf8.encode(entrypoint);
    if (encoded.isEmpty) {
      throw ArgumentError.value(entrypoint, 'entrypoint', 'must not be empty');
    }
    if (entrypoint.contains('\u0000')) {
      throw ArgumentError.value(
        entrypoint,
        'entrypoint',
        'must not contain NUL',
      );
    }
    if (encoded.length > _maximumEntrypointLength) {
      throw ArgumentError.value(
        entrypoint,
        'entrypoint',
        'must be at most 255 UTF-8 bytes',
      );
    }
    return entrypoint;
  }
}
