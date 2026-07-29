import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';

typedef MailRuntimeTraceSink = void Function(String message);

Future<RuntimeSession> startTracedMailRuntime(
  Uint8List config, {
  required MailRuntimeTraceSink trace,
  RuntimeStarter? runtimeStarter,
}) async {
  final configCopy = Uint8List.fromList(config);
  final start =
      runtimeStarter ??
      (config) => RuntimeClient.start(config: Uint8List.fromList(config));
  trace(
    '[Bonsai Mail][runtime] start '
    'entrypoint=${String.fromCharCodes(configCopy)} '
    'configBytes=${configCopy.length}',
  );
  try {
    final runtime = await start(configCopy);
    trace('[Bonsai Mail][runtime] ready');
    return _TracedRuntimeSession(runtime, trace);
  } catch (error) {
    trace('[Bonsai Mail][error] command=start type=${error.runtimeType}');
    rethrow;
  }
}

final class _TracedRuntimeSession implements RuntimeSession {
  const _TracedRuntimeSession(this._runtime, this._trace);

  final RuntimeSession _runtime;
  final MailRuntimeTraceSink _trace;

  @override
  Stream<RuntimeUpdate> get updates => _runtime.updates.map((update) {
    RuntimeUpdate forwarded = update;
    switch (update) {
      case CycleReady():
        final bytes = update.bytes.materialize().asUint8List();
        _trace(
          '[Bonsai Mail][cycle] '
          'presentation=${update.presentationId} '
          'revision=${update.revision} '
          'frameBytes=${bytes.length} '
          'recoverable=${update.recoverableDiagnostic?.code.name ?? 'none'}',
        );
        forwarded = CycleReady(
          presentationId: update.presentationId,
          revision: update.revision,
          bytes: TransferableTypedData.fromList([bytes]),
          recoverableDiagnostic: update.recoverableDiagnostic,
        );
      case RuntimeFatalDiagnostic():
        _trace('[Bonsai Mail][fatal] code=${update.diagnostic.code.name}');
      case RuntimeDebugSnapshot() || RuntimeDisposed():
        break;
    }
    return forwarded;
  });

  @override
  void grantVsync({required int generation}) {
    _trace('[Bonsai Mail][command] grantVsync generation=$generation');
    _runSync('grantVsync', () => _runtime.grantVsync(generation: generation));
  }

  @override
  void setFrameEligibility({required int generation, required bool eligible}) {
    _trace(
      '[Bonsai Mail][visibility] '
      'generation=$generation eligible=$eligible',
    );
    _runSync(
      'visibility',
      () => _runtime.setFrameEligibility(
        generation: generation,
        eligible: eligible,
      ),
    );
  }

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    _traceEventBatch(eventBatch);
    _trace(
      '[Bonsai Mail][presentation] succeeded '
      'generation=$generation presentation=$presentationId '
      'revision=$revision eventBytes=${eventBatch.length}',
    );
    _runSync(
      'presentationSucceeded',
      () => _runtime.presentationSucceeded(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        eventBatch: eventBatch,
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
    _trace(
      '[Bonsai Mail][presentation] rejected '
      'generation=$generation presentation=$presentationId '
      'revision=$revision reason=${reason.name}',
    );
    _runSync(
      'presentationRejected',
      () => _runtime.presentationRejected(
        generation: generation,
        presentationId: presentationId,
        revision: revision,
        reason: reason,
      ),
    );
  }

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() async {
    try {
      final snapshot = await _runtime.debugSnapshot();
      _trace(
        '[Bonsai Mail][debug] '
        'state=${snapshot.state.name} generation=${snapshot.liveGeneration} '
        'eligible=${snapshot.eligible} pumps=${snapshot.pumpCount} '
        'presentation=${snapshot.unresolvedPresentationId ?? 'none'}',
      );
      return snapshot;
    } catch (error) {
      _trace(
        '[Bonsai Mail][error] command=debugSnapshot type=${error.runtimeType}',
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    _trace('[Bonsai Mail][runtime] dispose');
    try {
      await _runtime.dispose();
      _trace('[Bonsai Mail][runtime] disposed');
    } catch (error) {
      _trace('[Bonsai Mail][error] command=dispose type=${error.runtimeType}');
      rethrow;
    }
  }

  void _traceEventBatch(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final batch = EventBatchCodec.decode(bytes);
    final events = batch.events;
    final sequences = events.isEmpty
        ? 'none'
        : '${events.first.sequence}..${events.last.sequence}';
    final displayedRevision = events.isEmpty
        ? 'none'
        : events.first.displayedRevision.toString();
    final tags = events.isEmpty
        ? 'none'
        : events
              .map(
                (event) =>
                    EventTagId.debugName(event.eventTag) ??
                    'unknown(${event.eventTag})',
              )
              .join(',');
    _trace(
      '[Bonsai Mail][event-batch] '
      'epoch=${batch.runtimeEpoch} '
      'events=${events.length} '
      'sequences=$sequences '
      'displayedRevision=$displayedRevision '
      'tags=$tags',
    );
  }

  void _runSync(String command, void Function() invoke) {
    try {
      invoke();
    } catch (error) {
      _trace('[Bonsai Mail][error] command=$command type=${error.runtimeType}');
      rethrow;
    }
  }
}
