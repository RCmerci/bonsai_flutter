import 'dart:typed_data';

import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:bonsai_flutter_native/src/native_version_facade.dart';
import 'package:test/test.dart';

final class _FakeNativeVersionFacade implements NativeVersionFacade {
  const _FakeNativeVersionFacade({
    required this.abi,
    this.protocol = const NativeProtocolVersion(3, 0),
  });

  @override
  final NativeAbiVersion abi;

  @override
  final NativeProtocolVersion protocol;
}

void main() {
  test('requires exact ABI 2.0 independently from protocol 3.0', () {
    expect(nativeAbiVersion, const NativeAbiVersion(2, 0));
    expect(nativeProtocolVersion, const NativeProtocolVersion(3, 0));
  });

  test('rejects ABI major and minor mismatch before runtime creation', () {
    expect(
      () => validateNativeVersions(
        const _FakeNativeVersionFacade(abi: NativeAbiVersion(1, 0)),
      ),
      throwsA(isA<NativeLibraryLoadingException>()),
    );
    expect(
      () => validateNativeVersions(
        const _FakeNativeVersionFacade(abi: NativeAbiVersion(2, 1)),
      ),
      throwsA(isA<NativeLibraryLoadingException>()),
    );
  });

  test('rejects protocol mismatch before runtime creation', () {
    expect(
      () => validateNativeVersions(
        const _FakeNativeVersionFacade(
          abi: NativeAbiVersion(2, 0),
          protocol: NativeProtocolVersion(1, 27),
        ),
      ),
      throwsA(isA<NativeLibraryLoadingException>()),
    );
    expect(
      () => validateNativeVersions(
        const _FakeNativeVersionFacade(
          abi: NativeAbiVersion(2, 0),
          protocol: NativeProtocolVersion(2, 26),
        ),
      ),
      throwsA(isA<NativeLibraryLoadingException>()),
    );
  });

  test('reports the stable native protocol version', () {
    expect(nativeProtocolVersion, const NativeProtocolVersion(3, 0));
  });

  test('owns and frees native error buffers after every call', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    final output = runtime.pump(
      monotonicNowNanoseconds: 1,
      input: Uint8List.fromList([1, 2, 3]),
    );

    expect(output.status, NativeStatus.fatalError);
    expect(output.errorCode, NativeRuntimeErrorCode.nativeLibraryLoadingError);
    expect(output.bytes, isEmpty);
    expect(output.presentationId, 0);
    expect(output.revision, 0);
    expect(output.errorMessage, 'bonsai_flutter runtime error 12');
    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('presentation success uses the same serialized error boundary', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    final output = runtime.presentationSucceeded(
      presentationId: 42,
      revision: 7,
      monotonicNowNanoseconds: 99,
    );

    expect(output.status, NativeStatus.fatalError);
    expect(output.errorMessage, 'bonsai_flutter runtime error 12');
    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('presentation rejection validates and forwards an exact reason', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    final output = runtime.presentationRejected(
      presentationId: 42,
      revision: 7,
      reason: NativePresentationRejectionReason.rendererRevisionMismatch,
    );

    expect(output.status, NativeStatus.fatalError);
    expect(output.errorMessage, 'bonsai_flutter runtime error 12');
    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('1000 failed calls do not retain native output buffers', () {
    final runtime = NativeRuntime.create();
    addTearDown(runtime.dispose);

    for (var iteration = 0; iteration < 1000; iteration += 1) {
      expect(
        runtime
            .pump(monotonicNowNanoseconds: iteration, input: Uint8List(0))
            .status,
        NativeStatus.fatalError,
      );
    }

    expect(runtime.debugOutstandingBufferCount, 0);
  });

  test('dispose is idempotent and rejects use after release', () {
    final runtime = NativeRuntime.create();

    runtime.dispose();
    runtime.dispose();

    expect(runtime.isDisposed, isTrue);
    expect(
      () => runtime.pump(monotonicNowNanoseconds: 0, input: Uint8List(0)),
      throwsA(isA<StateError>()),
    );
  });
}
