// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';

import 'runtime_protocol.dart';

abstract interface class RuntimeNativeRuntime {
  NativeOutput pump({
    required int monotonicNowNanoseconds,
    required Uint8List input,
  });

  NativeOutput presentationSucceeded({
    required int presentationId,
    required int revision,
    required int monotonicNowNanoseconds,
  });

  NativeOutput presentationRejected({
    required int presentationId,
    required int revision,
    required NativePresentationRejectionReason reason,
  });

  void dispose();
}

abstract interface class RuntimeMonotonicClock {
  int readNanoseconds();
}

final class StopwatchRuntimeMonotonicClock implements RuntimeMonotonicClock {
  StopwatchRuntimeMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  int readNanoseconds() =>
      checkedNanosecondsFromElapsedMicroseconds(_stopwatch.elapsedMicroseconds);
}

int checkedNanosecondsFromElapsedMicroseconds(int microseconds) {
  const maxInt64 = 0x7fffffffffffffff;
  const nanosecondsPerMicrosecond = 1000;
  if (microseconds < 0 ||
      microseconds > maxInt64 ~/ nanosecondsPerMicrosecond) {
    throw StateError('Elapsed runtime time does not fit in signed int64');
  }
  return microseconds * nanosecondsPerMicrosecond;
}

final class RuntimeWorker {
  RuntimeWorker.forTesting({
    required RuntimeNativeRuntime nativeRuntime,
    required RuntimeMonotonicClock monotonicClock,
    required void Function(RuntimeUpdate) emitUpdate,
  }) : _native = nativeRuntime,
       _clock = monotonicClock,
       _emitUpdate = emitUpdate;

  final RuntimeNativeRuntime _native;
  final RuntimeMonotonicClock _clock;
  final void Function(RuntimeUpdate) _emitUpdate;

  RuntimeWorkerState state = RuntimeWorkerState.ready;
  Future<void> _tail = Future<void>.value();
  int _liveGeneration = 0;
  bool _eligible = false;
  bool _hasCoalescedGrant = false;
  int? _unresolvedPresentationId;
  int? _unresolvedRevision;
  Uint8List _pendingEvents = Uint8List(0);
  int _pumpCount = 0;
  bool _explicitlyDisposed = false;
  bool _nativeDisposed = false;
  bool _terminalUpdateEmitted = false;

  Future<void> handle(RuntimeCommand command) {
    if (_explicitlyDisposed && command is! DisposeRuntime) {
      throw StateError('RuntimeWorker has been disposed');
    }
    final operation = _tail.then((_) => _handleNow(command));
    _tail = operation.catchError((Object error, StackTrace stackTrace) {
      _enterTerminal(
        RuntimeDiagnostic(
          code: RuntimeErrorCode.invalidSchedulerState,
          message: '$error\n$stackTrace',
        ),
      );
    });
    return operation;
  }

  Future<RuntimeDebugSnapshot> debugSnapshot() async {
    await _tail;
    return _snapshot();
  }

  void _handleNow(RuntimeCommand command) {
    if (command is DisposeRuntime) {
      _dispose();
      return;
    }
    if (state == RuntimeWorkerState.terminal) {
      return;
    }
    switch (command) {
      case VisibilityChanged():
        _handleVisibility(command);
      case VsyncGranted():
        _handleGrant(command);
      case PresentationSucceeded():
        _handlePresentationSucceeded(command);
      case PresentationRejected():
        _handlePresentationRejected(command);
      case DebugRuntime():
        _emitUpdate(_snapshot(requestId: command.requestId));
      case DisposeRuntime():
        break;
    }
  }

  void _handleVisibility(VisibilityChanged command) {
    if (command.generation < _liveGeneration) return;
    _liveGeneration = command.generation;
    _eligible = command.eligible;
    if (!_eligible) _hasCoalescedGrant = false;
  }

  void _handleGrant(VsyncGranted command) {
    if (!_eligible || command.generation != _liveGeneration) return;
    if (state == RuntimeWorkerState.awaitingPresentation) {
      _hasCoalescedGrant = true;
      return;
    }
    _pump();
  }

  void _pump() {
    final input = _pendingEvents;
    _pendingEvents = Uint8List(0);
    final output = _native.pump(
      monotonicNowNanoseconds: _clock.readNanoseconds(),
      input: input,
    );
    _pumpCount += 1;
    if (output.status == NativeStatus.fatalError) {
      _enterTerminal(_diagnostic(output));
      return;
    }
    if (output.presentationId <= 0) {
      _enterTerminal(
        const RuntimeDiagnostic(
          code: RuntimeErrorCode.invalidPresentation,
          message: 'Native pump returned no presentation token',
        ),
      );
      return;
    }
    _unresolvedPresentationId = output.presentationId;
    _unresolvedRevision = output.revision;
    state = RuntimeWorkerState.awaitingPresentation;
    _emitUpdate(
      CycleReady(
        presentationId: output.presentationId,
        revision: output.revision,
        bytes: TransferableTypedData.fromList([output.bytes]),
        recoverableDiagnostic: output.status == NativeStatus.recoverableError
            ? _diagnostic(output)
            : null,
      ),
    );
  }

  void _handlePresentationSucceeded(PresentationSucceeded command) {
    if (!_validatePresentation(
      command.generation,
      command.presentationId,
      command.revision,
    )) {
      return;
    }
    final events = command.events.materialize().asUint8List();
    final output = _native.presentationSucceeded(
      presentationId: command.presentationId,
      revision: command.revision,
      monotonicNowNanoseconds: _clock.readNanoseconds(),
    );
    if (output.status != NativeStatus.ok) {
      _enterTerminal(_diagnostic(output));
      return;
    }
    _clearBarrier();
    _pendingEvents = events;
    _consumeCoalescedGrant();
  }

  void _handlePresentationRejected(PresentationRejected command) {
    if (!_validatePresentation(
      command.generation,
      command.presentationId,
      command.revision,
    )) {
      return;
    }
    final output = _native.presentationRejected(
      presentationId: command.presentationId,
      revision: command.revision,
      reason: _nativeRejectionReason(command.reason),
    );
    if (output.status != NativeStatus.ok) {
      _enterTerminal(_diagnostic(output));
      return;
    }
    _clearBarrier();
    _consumeCoalescedGrant();
  }

  bool _validatePresentation(int generation, int presentationId, int revision) {
    final valid =
        _eligible &&
        generation == _liveGeneration &&
        state == RuntimeWorkerState.awaitingPresentation &&
        presentationId == _unresolvedPresentationId &&
        revision == _unresolvedRevision;
    if (!valid) {
      _enterTerminal(
        const RuntimeDiagnostic(
          code: RuntimeErrorCode.invalidPresentation,
          message: 'Presentation result does not match the live token',
        ),
      );
    }
    return valid;
  }

  void _clearBarrier() {
    _unresolvedPresentationId = null;
    _unresolvedRevision = null;
    state = RuntimeWorkerState.ready;
  }

  void _consumeCoalescedGrant() {
    if (_hasCoalescedGrant && _eligible) {
      _hasCoalescedGrant = false;
      _pump();
    }
  }

  RuntimeDebugSnapshot _snapshot({int? requestId}) => RuntimeDebugSnapshot(
    requestId: requestId,
    state: state,
    liveGeneration: _liveGeneration,
    eligible: _eligible,
    hasCoalescedGrant: _hasCoalescedGrant,
    unresolvedPresentationId: _unresolvedPresentationId,
    unresolvedRevision: _unresolvedRevision,
    pumpCount: _pumpCount,
  );

  RuntimeDiagnostic _diagnostic(NativeOutput output) => RuntimeDiagnostic(
    code: RuntimeErrorCode.fromWireId(output.errorCode.wireId),
    message: output.errorMessage ?? 'Native runtime failed',
  );

  void _enterTerminal(RuntimeDiagnostic diagnostic) {
    if (state == RuntimeWorkerState.terminal) return;
    state = RuntimeWorkerState.terminal;
    if (!_terminalUpdateEmitted) {
      _terminalUpdateEmitted = true;
      _emitUpdate(RuntimeFatalDiagnostic(diagnostic));
    }
    _disposeNative();
  }

  void _dispose() {
    if (_explicitlyDisposed) return;
    _explicitlyDisposed = true;
    state = RuntimeWorkerState.terminal;
    _disposeNative();
    _emitUpdate(const RuntimeDisposed());
  }

  void _disposeNative() {
    if (_nativeDisposed) return;
    _nativeDisposed = true;
    _native.dispose();
  }
}

NativePresentationRejectionReason _nativeRejectionReason(
  PresentationRejectionReason reason,
) => switch (reason) {
  PresentationRejectionReason.decodeFailed =>
    NativePresentationRejectionReason.decodeFailed,
  PresentationRejectionReason.frameValidationFailed =>
    NativePresentationRejectionReason.frameValidationFailed,
  PresentationRejectionReason.rendererEpochMismatch =>
    NativePresentationRejectionReason.rendererEpochMismatch,
  PresentationRejectionReason.rendererRevisionMismatch =>
    NativePresentationRejectionReason.rendererRevisionMismatch,
};

final class _NativeRuntimeAdapter implements RuntimeNativeRuntime {
  _NativeRuntimeAdapter(this._runtime);

  final NativeRuntime _runtime;

  @override
  NativeOutput pump({
    required int monotonicNowNanoseconds,
    required Uint8List input,
  }) => _runtime.pump(
    monotonicNowNanoseconds: monotonicNowNanoseconds,
    input: input,
  );

  @override
  NativeOutput presentationSucceeded({
    required int presentationId,
    required int revision,
    required int monotonicNowNanoseconds,
  }) => _runtime.presentationSucceeded(
    presentationId: presentationId,
    revision: revision,
    monotonicNowNanoseconds: monotonicNowNanoseconds,
  );

  @override
  NativeOutput presentationRejected({
    required int presentationId,
    required int revision,
    required NativePresentationRejectionReason reason,
  }) => _runtime.presentationRejected(
    presentationId: presentationId,
    revision: revision,
    reason: reason,
  );

  @override
  void dispose() => _runtime.dispose();
}

Future<void> runtimeWorkerMain(List<Object?> startup) async {
  final ready = startup[0]! as SendPort;
  final updates = startup[1]! as SendPort;
  final config = (startup[2]! as TransferableTypedData)
      .materialize()
      .asUint8List();
  NativeRuntime native;
  try {
    native = NativeRuntime.create(config);
  } catch (error, stackTrace) {
    ready.send('$error\n$stackTrace');
    return;
  }
  final worker = RuntimeWorker.forTesting(
    nativeRuntime: _NativeRuntimeAdapter(native),
    monotonicClock: StopwatchRuntimeMonotonicClock(),
    emitUpdate: updates.send,
  );
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  await for (final message in commands) {
    if (message is! RuntimeCommand) {
      updates.send(
        const RuntimeFatalDiagnostic(
          RuntimeDiagnostic(
            code: RuntimeErrorCode.invalidSchedulerState,
            message: 'Runtime isolate received a malformed command',
          ),
        ),
      );
      continue;
    }
    await worker.handle(message);
    if (message is DisposeRuntime) {
      commands.close();
      break;
    }
  }
}
