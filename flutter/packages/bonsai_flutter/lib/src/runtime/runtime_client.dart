import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'runtime_protocol.dart';
import 'runtime_coordinator_slot.dart';
import 'runtime_worker.dart';

export 'runtime_protocol.dart';

enum RuntimeStatus { ok, recoverableError, fatalError }

final class BonsaiRuntimeException implements Exception {
  const BonsaiRuntimeException({
    required this.status,
    required this.code,
    required this.message,
  });

  final RuntimeStatus status;
  final RuntimeErrorCode code;
  final String message;

  @override
  String toString() =>
      'BonsaiRuntimeException(${status.name}, ${code.name}, $message)';
}

abstract interface class RuntimeSession {
  Stream<RuntimeUpdate> get updates;

  void grantVsync({required int generation});

  void setFrameEligibility({required int generation, required bool eligible});

  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  });

  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  });

  Future<RuntimeDebugSnapshot> debugSnapshot();
  Future<void> dispose();
}

typedef RuntimeIsolateEntrypoint = void Function(List<Object?> startup);
typedef RuntimeIsolateSpawner =
    Future<Isolate> Function(RuntimeIsolateSpawnRequest request);

final class RuntimeIsolateSpawnRequest {
  const RuntimeIsolateSpawnRequest({
    required this.startup,
    required this.errors,
    required this.exit,
  });

  final List<Object?> startup;
  final SendPort errors;
  final SendPort exit;

  Future<Isolate> spawn({RuntimeIsolateEntrypoint? entrypoint}) =>
      Isolate.spawn(
        entrypoint ?? runtimeWorkerMain,
        startup,
        debugName: 'bonsai_flutter_runtime',
        onError: errors,
        onExit: exit,
        errorsAreFatal: true,
      );
}

sealed class _RuntimeStartupEvent {
  const _RuntimeStartupEvent();
}

final class _RuntimeStartupReady extends _RuntimeStartupEvent {
  const _RuntimeStartupReady(this.message);

  final Object? message;
}

final class _RuntimeStartupFailed extends _RuntimeStartupEvent {
  const _RuntimeStartupFailed(this.error);

  final Object error;
}

final class _RuntimeStartupExited extends _RuntimeStartupEvent {
  const _RuntimeStartupExited();
}

final class RuntimeClient implements RuntimeSession {
  RuntimeClient._(
    this._commands,
    this._updatesPort,
    this._errorsPort,
    this._exitPort,
    this._worker,
    this._coordinatorLease,
    Future<Object?> exitFuture,
  ) {
    _updatesSubscription = _updatesPort.listen(_handleUpdate);
    _errorsSubscription = _errorsPort.listen(_handleIsolateError);
    unawaited(exitFuture.then(_handleIsolateExit));
  }

  static Future<RuntimeClient> start({Uint8List? config}) async {
    return _start(config: config, isolateSpawner: (request) => request.spawn());
  }

  static Future<RuntimeClient> startForTesting({
    Uint8List? config,
    required RuntimeIsolateSpawner isolateSpawner,
  }) => _start(config: config, isolateSpawner: isolateSpawner);

  static Future<RuntimeClient> _start({
    required Uint8List? config,
    required RuntimeIsolateSpawner isolateSpawner,
  }) async {
    final coordinatorLease = runtimeCoordinatorSlot.acquire();
    final ready = ReceivePort();
    final updates = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    Isolate worker;
    try {
      worker = await isolateSpawner(
        RuntimeIsolateSpawnRequest(
          startup: <Object?>[
            ready.sendPort,
            updates.sendPort,
            TransferableTypedData.fromList([config ?? Uint8List(0)]),
          ],
          errors: errors.sendPort,
          exit: exit.sendPort,
        ),
      );
    } catch (_) {
      ready.close();
      updates.close();
      errors.close();
      exit.close();
      runtimeCoordinatorSlot.release(coordinatorLease);
      rethrow;
    }
    final exitFuture = exit.first;
    final startupEvent = await Future.any<_RuntimeStartupEvent>([
      ready.first.then<_RuntimeStartupEvent>(
        _RuntimeStartupReady.new,
        onError: (Object error, StackTrace _) => _RuntimeStartupFailed(error),
      ),
      exitFuture.then<_RuntimeStartupEvent>(
        (_) => const _RuntimeStartupExited(),
      ),
    ]);
    if (startupEvent is _RuntimeStartupExited) {
      ready.close();
      updates.close();
      errors.close();
      exit.close();
      runtimeCoordinatorSlot.release(coordinatorLease);
      throw StateError('Runtime isolate exited before startup completed');
    }
    if (startupEvent case _RuntimeStartupFailed(:final error)) {
      worker.kill(priority: Isolate.immediate);
      await exitFuture;
      ready.close();
      updates.close();
      errors.close();
      exit.close();
      runtimeCoordinatorSlot.release(coordinatorLease);
      throw StateError('Runtime isolate failed to start: $error');
    }
    final readyMessage = (startupEvent as _RuntimeStartupReady).message;
    ready.close();
    if (readyMessage case SendPort commands) {
      runtimeCoordinatorSlot.activate(coordinatorLease);
      return RuntimeClient._(
        commands,
        updates,
        errors,
        exit,
        worker,
        coordinatorLease,
        exitFuture,
      );
    }
    updates.close();
    errors.close();
    worker.kill(priority: Isolate.immediate);
    await exitFuture;
    exit.close();
    runtimeCoordinatorSlot.release(coordinatorLease);
    throw StateError('Runtime isolate failed to start: $readyMessage');
  }

  final SendPort _commands;
  final ReceivePort _updatesPort;
  final ReceivePort _errorsPort;
  final ReceivePort _exitPort;
  final Isolate _worker;
  final RuntimeCoordinatorLease _coordinatorLease;
  final StreamController<RuntimeUpdate> _updates =
      StreamController<RuntimeUpdate>.broadcast(sync: true);
  final Map<int, Completer<RuntimeDebugSnapshot>> _debugRequests = {};
  final Completer<void> _exitCompleter = Completer<void>();
  late final StreamSubscription<Object?> _updatesSubscription;
  late final StreamSubscription<Object?> _errorsSubscription;
  Completer<void>? _disposeCompleter;
  var _nextDebugRequestId = 1;
  bool _disposed = false;
  bool _closed = false;

  @override
  Stream<RuntimeUpdate> get updates => _updates.stream;

  @override
  void grantVsync({required int generation}) {
    _send(VsyncGranted(generation));
  }

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    _send(VisibilityChanged(generation: generation, eligible: eligible));
  }

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    _send(
      PresentationSucceeded(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        events: TransferableTypedData.fromList([eventBatch]),
      ),
    );
  }

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) {
    _send(
      PresentationRejected(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        reason: reason,
      ),
    );
  }

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() {
    _checkLive();
    final requestId = _nextDebugRequestId++;
    final completer = Completer<RuntimeDebugSnapshot>();
    _debugRequests[requestId] = completer;
    _commands.send(DebugRuntime(requestId));
    return completer.future;
  }

  @override
  Future<void> dispose() {
    final existing = _disposeCompleter;
    if (existing != null) return existing.future;
    _disposed = true;
    runtimeCoordinatorSlot.beginDisposal(_coordinatorLease);
    final completer = Completer<void>();
    _disposeCompleter = completer;
    _commands.send(const DisposeRuntime());
    return completer.future;
  }

  void _send(RuntimeCommand command) {
    _checkLive();
    _commands.send(command);
  }

  void _checkLive() {
    if (_disposed || _closed) {
      throw StateError('RuntimeClient has been disposed');
    }
  }

  void _handleUpdate(Object? message) {
    if (message is! RuntimeUpdate) {
      _fail(StateError('Malformed runtime-isolate update'));
      return;
    }
    if (message case RuntimeDebugSnapshot(:final requestId?)) {
      final completer = _debugRequests.remove(requestId);
      if (completer == null) {
        _fail(StateError('Unknown runtime debug response $requestId'));
      } else {
        completer.complete(message);
      }
      return;
    }
    if (message is RuntimeDisposed) {
      unawaited(_finishDispose());
      return;
    }
    _updates.add(message);
  }

  Future<void> _finishDispose() async {
    await _exitCompleter.future;
    await _close();
    final completer = _disposeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _handleIsolateError(Object? message) {
    final error = switch (message) {
      [final Object error, final Object stack] => '$error\n$stack',
      _ => '$message',
    };
    _fail(StateError('Runtime isolate failed: $error'));
  }

  void _handleIsolateExit(Object? _) {
    if (!_exitCompleter.isCompleted) _exitCompleter.complete();
    runtimeCoordinatorSlot.release(_coordinatorLease);
    if (!_disposed) {
      _fail(StateError('Runtime isolate exited unexpectedly'));
    } else {
      unawaited(_finishDispose());
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    for (final completer in _debugRequests.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _debugRequests.clear();
    final disposeCompleter = _disposeCompleter;
    if (disposeCompleter != null && !disposeCompleter.isCompleted) {
      disposeCompleter.completeError(error);
    }
    _updates.add(
      RuntimeFatalDiagnostic(
        RuntimeDiagnostic(
          code: RuntimeErrorCode.invalidSchedulerState,
          message: error.toString(),
        ),
      ),
    );
    _worker.kill(priority: Isolate.immediate);
    unawaited(_closeAfterExit());
  }

  Future<void> _closeAfterExit() async {
    await _exitCompleter.future;
    await _close();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _updatesPort.close();
    _errorsPort.close();
    _exitPort.close();
    await _updatesSubscription.cancel();
    await _errorsSubscription.cancel();
    await _updates.close();
  }
}
