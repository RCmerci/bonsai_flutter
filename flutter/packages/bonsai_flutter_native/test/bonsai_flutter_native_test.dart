import 'dart:typed_data';

import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:test/test.dart';

void main() {
  test('reports the stable native protocol version', () {
    expect(nativeProtocolVersion, const NativeProtocolVersion(1, 12));
  });

  test('owns and frees native error buffers after every call', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    final output = runtime.step(Uint8List.fromList([1, 2, 3]));

    expect(output.status, NativeStatus.fatalError);
    expect(output.errorCode, NativeRuntimeErrorCode.nativeLibraryLoadingError);
    expect(output.bytes, isEmpty);
    expect(output.revision, 0);
    expect(output.nextWakeupNanoseconds, -1);
    expect(output.errorMessage, 'bonsai_flutter runtime error 12');
    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('frame-presented uses the same serialized error boundary', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    final output = runtime.framePresented(42);

    expect(output.status, NativeStatus.fatalError);
    expect(output.errorMessage, 'bonsai_flutter runtime error 12');
    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('1000 failed calls do not retain native output buffers', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    for (var iteration = 0; iteration < 1000; iteration += 1) {
      expect(runtime.step(Uint8List(0)).status, NativeStatus.fatalError);
    }

    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('dispose is idempotent and rejects use after release', () {
    final runtime = NativeRuntime.create();

    runtime.dispose();
    runtime.dispose();

    expect(runtime.isDisposed, isTrue);
    expect(() => runtime.step(Uint8List(0)), throwsA(isA<StateError>()));
  });
}
