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
  Future<RuntimeResponse> step(Uint8List input) {
    _trace('[Bonsai Mail][command] step inputBytes=${input.length}');
    return _run('step', () => _runtime.step(input));
  }

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) {
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
    return _run('eventBatch', () => _runtime.sendEventBatch(batch));
  }

  @override
  Future<RuntimeResponse> framePresented(int revision) {
    _trace('[Bonsai Mail][presentation] acknowledge revision=$revision');
    return _run('framePresented', () => _runtime.framePresented(revision));
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

  Future<RuntimeResponse> _run(
    String command,
    Future<RuntimeResponse> Function() invoke,
  ) async {
    try {
      final response = await invoke();
      _trace(
        '[Bonsai Mail][response] '
        'command=$command '
        'request=${response.requestSequence} '
        'status=${response.status.name} '
        'error=${response.errorCode.name} '
        'revision=${response.revision} '
        'frameBytes=${response.bytes.length} '
        'nextWakeup=${_wakeup(response.nextWakeupNanoseconds)} '
        'ffiUs=${response.ffiDuration.inMicroseconds} '
        'transferUs=${response.isolateTransferDuration.inMicroseconds}',
      );
      return response;
    } catch (error) {
      _trace('[Bonsai Mail][error] command=$command type=${error.runtimeType}');
      rethrow;
    }
  }
}

String _wakeup(int nanoseconds) =>
    nanoseconds < 0 ? 'none' : '${nanoseconds}ns';
