import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes the byte-exact Fresh startup envelope', () {
    final encoded = RuntimeBootstrapConfig(
      entrypoint: 'counter',
      launchPolicy: RuntimeLaunchPolicy.fresh,
      applicationPayload: Uint8List.fromList([0, 1, 255]),
    ).encode();

    expect(encoded, <int>[
      0x42,
      0x46,
      0x52,
      0x31,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      7,
      0,
      0,
      0,
      3,
      0,
      0,
      0,
      ...utf8.encode('counter'),
      0,
      1,
      255,
    ]);
  });

  test('encodes Replace_existing and UTF-8 entrypoint bytes', () {
    final encoded = RuntimeBootstrapConfig(
      entrypoint: 'todos-例',
      launchPolicy: RuntimeLaunchPolicy.replaceExisting,
    ).encode();
    final entrypoint = utf8.encode('todos-例');

    expect(encoded.sublist(0, 4), ascii.encode('BFR1'));
    expect(encoded[8], 1);
    expect(encoded.sublist(9, 12), [0, 0, 0]);
    expect(
      ByteData.sublistView(encoded).getUint32(12, Endian.little),
      entrypoint.length,
    );
    expect(ByteData.sublistView(encoded).getUint32(16, Endian.little), 0);
    expect(encoded.sublist(20), entrypoint);
  });

  test('copies payload input and returns independent encoded bytes', () {
    final payload = Uint8List.fromList([1, 2, 3]);
    final config = RuntimeBootstrapConfig(
      entrypoint: 'counter',
      launchPolicy: RuntimeLaunchPolicy.fresh,
      applicationPayload: payload,
    );
    payload[0] = 9;

    final first = config.encode();
    first[20] = 0;
    final second = config.encode();

    expect(second.sublist(second.length - 3), [1, 2, 3]);
    expect(second[20], ascii.encode('c').single);
  });

  test('accepts and preserves an opaque payload at the exact 1 MiB limit', () {
    final payload = Uint8List(1024 * 1024);
    payload[0] = 0xff;
    payload[payload.length - 1] = 0x7f;

    final encoded = RuntimeBootstrapConfig(
      entrypoint: 'managed',
      launchPolicy: RuntimeLaunchPolicy.replaceExisting,
      applicationPayload: payload,
    ).encode();
    final data = ByteData.sublistView(encoded);
    final entrypointLength = utf8.encode('managed').length;

    expect(encoded.sublist(0, 4), ascii.encode('BFR1'));
    expect(data.getUint32(16, Endian.little), 1024 * 1024);
    expect(encoded.length, 20 + entrypointLength + (1024 * 1024));
    expect(encoded[20 + entrypointLength], 0xff);
    expect(encoded.last, 0x7f);
  });

  test('rejects invalid entrypoints and oversized payloads', () {
    expect(
      () => RuntimeBootstrapConfig(
        entrypoint: '',
        launchPolicy: RuntimeLaunchPolicy.fresh,
      ),
      throwsArgumentError,
    );
    expect(
      () => RuntimeBootstrapConfig(
        entrypoint: 'bad\u0000name',
        launchPolicy: RuntimeLaunchPolicy.fresh,
      ),
      throwsArgumentError,
    );
    expect(
      () => RuntimeBootstrapConfig(
        entrypoint: 'é' * 128,
        launchPolicy: RuntimeLaunchPolicy.fresh,
      ),
      throwsArgumentError,
    );
    expect(
      () => RuntimeBootstrapConfig(
        entrypoint: 'counter',
        launchPolicy: RuntimeLaunchPolicy.fresh,
        applicationPayload: Uint8List((1024 * 1024) + 1),
      ),
      throwsArgumentError,
    );
  });
}
