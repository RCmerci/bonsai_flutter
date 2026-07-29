import 'dart:typed_data';

import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:bonsai_flutter/src/runtime/runtime_worker.dart';

sealed class NativeCall {
  const NativeCall();
}

final class PumpCall extends NativeCall {
  const PumpCall(this.monotonicNowNanoseconds, this.input);

  final int monotonicNowNanoseconds;
  final Uint8List input;
}

final class PresentationSucceededCall extends NativeCall {
  const PresentationSucceededCall({
    required this.presentationId,
    required this.revision,
    required this.monotonicNowNanoseconds,
  });

  final int presentationId;
  final int revision;
  final int monotonicNowNanoseconds;
}

final class PresentationRejectedCall extends NativeCall {
  const PresentationRejectedCall({
    required this.presentationId,
    required this.revision,
    required this.reason,
  });

  final int presentationId;
  final int revision;
  final NativePresentationRejectionReason reason;
}

final class FakeRuntimeNative implements RuntimeNativeRuntime {
  final List<NativeCall> calls = [];
  final List<NativeOutput> pumpOutputs = [];
  NativeOutput presentationOutput = successOutput();
  var disposeCount = 0;

  static NativeOutput successOutput({
    int presentationId = 0,
    int revision = 0,
    List<int> bytes = const [],
    NativeStatus status = NativeStatus.ok,
    NativeRuntimeErrorCode errorCode = NativeRuntimeErrorCode.none,
    String? errorMessage,
  }) => NativeOutput(
    status: status,
    bytes: Uint8List.fromList(bytes),
    presentationId: presentationId,
    revision: revision,
    errorMessage: errorMessage,
    errorCode: errorCode,
  );

  @override
  NativeOutput pump({
    required int monotonicNowNanoseconds,
    required Uint8List input,
  }) {
    calls.add(PumpCall(monotonicNowNanoseconds, Uint8List.fromList(input)));
    if (pumpOutputs.isEmpty) {
      throw StateError('FakeRuntimeNative has no queued pump output');
    }
    return pumpOutputs.removeAt(0);
  }

  @override
  NativeOutput presentationSucceeded({
    required int presentationId,
    required int revision,
    required int monotonicNowNanoseconds,
  }) {
    calls.add(
      PresentationSucceededCall(
        presentationId: presentationId,
        revision: revision,
        monotonicNowNanoseconds: monotonicNowNanoseconds,
      ),
    );
    return presentationOutput;
  }

  @override
  NativeOutput presentationRejected({
    required int presentationId,
    required int revision,
    required NativePresentationRejectionReason reason,
  }) {
    calls.add(
      PresentationRejectedCall(
        presentationId: presentationId,
        revision: revision,
        reason: reason,
      ),
    );
    return presentationOutput;
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}

final class FakeRuntimeMonotonicClock implements RuntimeMonotonicClock {
  FakeRuntimeMonotonicClock(Iterable<int> readings)
    : _readings = List<int>.of(readings);

  final List<int> _readings;
  var readCount = 0;

  @override
  int readNanoseconds() {
    readCount += 1;
    if (_readings.isEmpty) {
      throw StateError('FakeRuntimeMonotonicClock has no queued reading');
    }
    return _readings.removeAt(0);
  }
}
