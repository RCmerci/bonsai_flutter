import 'dart:async';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';

final class RuntimeCycle {
  const RuntimeCycle({
    required this.presentationId,
    required this.revision,
    required this.bytes,
    required this.recoverableDiagnostic,
  });

  final int presentationId;
  final int revision;
  final Uint8List bytes;
  final RuntimeDiagnostic? recoverableDiagnostic;
}

final class RuntimeHarness {
  RuntimeHarness(this.runtime) {
    _subscription = runtime.updates.listen(_handleUpdate, onError: _fail);
    runtime.setFrameEligibility(generation: _generation, eligible: true);
  }

  final RuntimeClient runtime;
  final int _generation = 1;
  final List<RuntimeCycle> _queuedCycles = [];
  final List<Completer<RuntimeCycle>> _cycleWaiters = [];
  late final StreamSubscription<RuntimeUpdate> _subscription;
  RuntimeCycle? _current;
  Object? _terminalError;
  bool _disposed = false;

  RuntimeCycle? get current => _current;

  Future<RuntimeCycle> grant() {
    _checkLive();
    if (_current != null) {
      throw StateError('A presentation must be acknowledged before a grant');
    }
    final future = _nextCycle();
    runtime.grantVsync(generation: _generation);
    return future;
  }

  Future<RuntimeCycle> advance({Uint8List? events}) {
    acknowledge(events: events);
    return grant();
  }

  void acknowledge({Uint8List? events}) {
    _checkLive();
    final cycle = _current;
    if (cycle == null) {
      throw StateError('No presentation is awaiting acknowledgment');
    }
    runtime.presentationSucceeded(
      generation: _generation,
      presentationId: cycle.presentationId,
      revision: cycle.revision,
      eventBatch: events ?? Uint8List(0),
    );
    _current = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await runtime.dispose();
    await _subscription.cancel();
  }

  Future<RuntimeCycle> _nextCycle() {
    final error = _terminalError;
    if (error != null) return Future<RuntimeCycle>.error(error);
    if (_queuedCycles.isNotEmpty) {
      final cycle = _queuedCycles.removeAt(0);
      _current = cycle;
      return Future.value(cycle);
    }
    final completer = Completer<RuntimeCycle>();
    _cycleWaiters.add(completer);
    return completer.future.then((cycle) {
      _current = cycle;
      return cycle;
    });
  }

  void _handleUpdate(RuntimeUpdate update) {
    switch (update) {
      case CycleReady():
        final cycle = RuntimeCycle(
          presentationId: update.presentationId,
          revision: update.revision,
          bytes: update.bytes.materialize().asUint8List(),
          recoverableDiagnostic: update.recoverableDiagnostic,
        );
        if (_cycleWaiters.isEmpty) {
          _queuedCycles.add(cycle);
        } else {
          _cycleWaiters.removeAt(0).complete(cycle);
        }
      case RuntimeFatalDiagnostic():
        _fail(
          StateError(
            '${update.diagnostic.code.name}: ${update.diagnostic.message}',
          ),
        );
      case RuntimeDebugSnapshot() || RuntimeDisposed():
        break;
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_terminalError != null) return;
    _terminalError = error;
    for (final waiter in _cycleWaiters) {
      waiter.completeError(error, stackTrace);
    }
    _cycleWaiters.clear();
  }

  void _checkLive() {
    if (_disposed) throw StateError('RuntimeHarness has been disposed');
    final error = _terminalError;
    if (error != null) throw StateError('RuntimeHarness is terminal: $error');
  }
}
