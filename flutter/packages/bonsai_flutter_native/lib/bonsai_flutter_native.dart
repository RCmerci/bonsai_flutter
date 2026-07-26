import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bonsai_flutter_native_bindings_generated.dart' as bindings;

const int _maxNativeOutputBytes = 16 * 1024 * 1024;

final class NativeProtocolVersion {
  const NativeProtocolVersion(this.major, this.minor);

  final int major;
  final int minor;

  @override
  bool operator ==(Object other) =>
      other is NativeProtocolVersion &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

final NativeProtocolVersion nativeProtocolVersion = NativeProtocolVersion(
  bindings.bf_protocol_version_major(),
  bindings.bf_protocol_version_minor(),
);

enum NativeStatus { ok, recoverableError, fatalError }

enum NativeRuntimeErrorCode {
  none(0),
  protocolError(1),
  revisionMismatch(2),
  duplicateKey(3),
  unsupportedNodeKind(4),
  invalidProp(5),
  handlerMissing(6),
  staleEvent(7),
  hostEffectFailure(8),
  ocamlException(9),
  dartRendererException(10),
  lifecycleException(11),
  nativeLibraryLoadingError(12);

  const NativeRuntimeErrorCode(this.wireId);

  final int wireId;
}

final class NativeOutput {
  const NativeOutput({
    required this.status,
    required this.bytes,
    required this.revision,
    required this.nextWakeupNanoseconds,
    required this.errorMessage,
    this.errorCode = NativeRuntimeErrorCode.none,
  });

  final NativeStatus status;
  final Uint8List bytes;
  final int revision;
  final int nextWakeupNanoseconds;
  final String? errorMessage;
  final NativeRuntimeErrorCode errorCode;
}

final class NativeRuntime {
  NativeRuntime._(this._pointer);

  factory NativeRuntime.create([Uint8List? config]) {
    final bytes = config ?? Uint8List(0);
    final pointer = _withNativeBytes(
      bytes,
      (data) => bindings.bf_runtime_create(data, bytes.length),
    );
    if (pointer == nullptr) {
      throw StateError('bf_runtime_create failed');
    }
    return NativeRuntime._(pointer);
  }

  Pointer<bindings.bf_runtime> _pointer;

  bool get isDisposed => _pointer == nullptr;

  int get debugOutstandingBufferCount {
    _checkLive();
    return bindings.bf_runtime_outstanding_buffers(_pointer);
  }

  NativeOutput step(Uint8List input) {
    _checkLive();
    return _withNativeBytes(
      input,
      (data) => _invoke(
        (output) =>
            bindings.bf_runtime_step(_pointer, data, input.length, output),
      ),
    );
  }

  NativeOutput framePresented(int revision) {
    _checkLive();
    if (revision < 0 || revision > 0x7fffffffffffffff) {
      throw RangeError.range(revision, 0, 0x7fffffffffffffff, 'revision');
    }
    return _invoke(
      (output) =>
          bindings.bf_runtime_frame_presented(_pointer, revision, output),
    );
  }

  void dispose() {
    if (isDisposed) return;
    bindings.bf_runtime_destroy(_pointer);
    _pointer = nullptr;
  }

  NativeOutput _invoke(int Function(Pointer<bindings.bf_output_buffer>) call) {
    final output = calloc<bindings.bf_output_buffer>();
    try {
      final returnedStatus = call(output);
      if (output.ref.status != returnedStatus) {
        if (output.ref.data != nullptr) {
          bindings.bf_buffer_free(_pointer, output.ref.data);
        }
        throw StateError(
          'Native return status $returnedStatus does not match '
          'output status ${output.ref.status}',
        );
      }
      final copied = _copyAndFree(output);
      final status = _status(returnedStatus);
      final errorCode = _errorCode(output.ref.error_code);
      final errorMessage = status == NativeStatus.ok ? null : _lastError();
      return NativeOutput(
        status: status,
        bytes: copied.bytes,
        revision: copied.revision,
        nextWakeupNanoseconds: copied.nextWakeupNanoseconds,
        errorMessage: errorMessage,
        errorCode: errorCode,
      );
    } finally {
      calloc.free(output);
    }
  }

  String _lastError() {
    final output = calloc<bindings.bf_output_buffer>();
    try {
      final status = bindings.bf_runtime_get_last_error(_pointer, output);
      if (status != bindings.BF_STATUS_OK) {
        return 'Unable to retrieve the native runtime error';
      }
      final copied = _copyAndFree(output);
      return String.fromCharCodes(copied.bytes);
    } finally {
      calloc.free(output);
    }
  }

  _CopiedOutput _copyAndFree(Pointer<bindings.bf_output_buffer> output) {
    final value = output.ref;
    if (value.length != 0 && value.data == nullptr) {
      throw StateError('Native output has a null pointer with nonzero length');
    }
    if (value.length > _maxNativeOutputBytes) {
      if (value.data != nullptr) {
        bindings.bf_buffer_free(_pointer, value.data);
      }
      throw StateError(
        'Native output length ${value.length} exceeds '
        '$_maxNativeOutputBytes bytes',
      );
    }
    final bytes = value.length == 0
        ? Uint8List(0)
        : Uint8List.fromList(value.data.asTypedList(value.length));
    if (value.data != nullptr) {
      bindings.bf_buffer_free(_pointer, value.data);
    }
    return _CopiedOutput(
      bytes: bytes,
      revision: value.revision,
      nextWakeupNanoseconds: value.next_wakeup_ns,
    );
  }

  void _checkLive() {
    if (isDisposed) {
      throw StateError('NativeRuntime has been disposed');
    }
  }
}

final class _CopiedOutput {
  const _CopiedOutput({
    required this.bytes,
    required this.revision,
    required this.nextWakeupNanoseconds,
  });

  final Uint8List bytes;
  final int revision;
  final int nextWakeupNanoseconds;
}

NativeStatus _status(int value) => switch (value) {
  bindings.BF_STATUS_OK => NativeStatus.ok,
  bindings.BF_STATUS_RECOVERABLE_ERROR => NativeStatus.recoverableError,
  bindings.BF_STATUS_FATAL_ERROR => NativeStatus.fatalError,
  _ => throw StateError('Unknown bf_status value $value'),
};

NativeRuntimeErrorCode _errorCode(int value) {
  for (final code in NativeRuntimeErrorCode.values) {
    if (code.wireId == value) return code;
  }
  throw StateError('Unknown bf_error_code value $value');
}

T _withNativeBytes<T>(Uint8List bytes, T Function(Pointer<Uint8>) body) {
  if (bytes.isEmpty) return body(nullptr);
  final pointer = calloc<Uint8>(bytes.length);
  try {
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return body(pointer);
  } finally {
    calloc.free(pointer);
  }
}
