import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';

import '../protocol/event_batch.dart';

enum RuntimeStatus { ok, recoverableError, fatalError }

enum RuntimeErrorCode {
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

  const RuntimeErrorCode(this.wireId);

  final int wireId;

  static RuntimeErrorCode fromWireId(int value) {
    for (final code in values) {
      if (code.wireId == value) return code;
    }
    throw StateError('Unknown runtime error code $value');
  }
}

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

final class RuntimeResponse {
  const RuntimeResponse({
    required this.requestSequence,
    required this.status,
    required this.bytes,
    required this.revision,
    required this.nextWakeupNanoseconds,
    required this.errorMessage,
    this.errorCode = RuntimeErrorCode.none,
    this.ffiDuration = Duration.zero,
    this.isolateTransferDuration = Duration.zero,
  });

  final int requestSequence;
  final RuntimeStatus status;
  final Uint8List bytes;
  final int revision;
  final int nextWakeupNanoseconds;
  final String? errorMessage;
  final RuntimeErrorCode errorCode;
  final Duration ffiDuration;
  final Duration isolateTransferDuration;
}

abstract interface class RuntimeSession {
  Future<RuntimeResponse> step(Uint8List input);
  Future<RuntimeResponse> sendEventBatch(EventBatch batch);
  Future<RuntimeResponse> framePresented(int revision);
  Future<void> dispose();
}

final class RuntimeClient implements RuntimeSession {
  RuntimeClient._(this._commands, this._responses, this._worker) {
    _responses.listen(_handleResponse);
  }

  static Future<RuntimeClient> start({Uint8List? config}) async {
    final ready = ReceivePort();
    final responses = ReceivePort();
    final worker = await Isolate.spawn(_runtimeWorkerMain, <Object?>[
      ready.sendPort,
      responses.sendPort,
      TransferableTypedData.fromList([config ?? Uint8List(0)]),
    ], debugName: 'bonsai_flutter_runtime');
    final readyMessage = await ready.first;
    ready.close();
    if (readyMessage case SendPort commands) {
      return RuntimeClient._(commands, responses, worker);
    }
    responses.close();
    worker.kill(priority: Isolate.immediate);
    throw StateError('Runtime isolate failed to start: $readyMessage');
  }

  final SendPort _commands;
  final ReceivePort _responses;
  final Isolate _worker;
  final Map<int, Completer<RuntimeResponse>> _pending = {};
  final Map<int, Stopwatch> _roundTrips = {};
  var _nextSequence = 1;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Future<RuntimeResponse> step(Uint8List input) =>
      _send(_Command.step, TransferableTypedData.fromList([input]));

  @override
  Future<RuntimeResponse> sendEventBatch(EventBatch batch) =>
      step(EventBatchCodec.encode(batch));

  @override
  Future<RuntimeResponse> framePresented(int revision) =>
      _send(_Command.framePresented, revision);

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    final sequence = _nextSequence++;
    final response = Completer<RuntimeResponse>();
    _pending[sequence] = response;
    _roundTrips[sequence] = Stopwatch()..start();
    _commands.send(<Object?>[sequence, _Command.dispose.index, null]);
    response.future.then((_) {
      _responses.close();
      completer.complete();
    }, onError: completer.completeError);
    return completer.future;
  }

  Future<RuntimeResponse> _send(_Command command, Object? payload) {
    if (_disposed) {
      throw StateError('RuntimeClient has been disposed');
    }
    final sequence = _nextSequence++;
    final completer = Completer<RuntimeResponse>();
    _pending[sequence] = completer;
    _roundTrips[sequence] = Stopwatch()..start();
    _commands.send(<Object?>[sequence, command.index, payload]);
    return completer.future;
  }

  void _handleResponse(Object? message) {
    if (message is! List<Object?> || message.length != 8) {
      _failPending(StateError('Malformed runtime-isolate response'));
      return;
    }
    final sequence = message[0]! as int;
    final completer = _pending.remove(sequence);
    final roundTrip = _roundTrips.remove(sequence)?..stop();
    if (completer == null) {
      _failPending(StateError('Unknown runtime response $sequence'));
      return;
    }
    final transferable = message[2]! as TransferableTypedData;
    final ffiDuration = Duration(microseconds: message[7]! as int);
    final totalDuration = roundTrip?.elapsed ?? ffiDuration;
    final transferMicroseconds =
        totalDuration.inMicroseconds - ffiDuration.inMicroseconds;
    completer.complete(
      RuntimeResponse(
        requestSequence: sequence,
        status: RuntimeStatus.values[message[1]! as int],
        bytes: transferable.materialize().asUint8List(),
        revision: message[3]! as int,
        nextWakeupNanoseconds: message[4]! as int,
        errorMessage: message[5] as String?,
        errorCode: RuntimeErrorCode.fromWireId(message[6]! as int),
        ffiDuration: ffiDuration,
        isolateTransferDuration: Duration(
          microseconds: transferMicroseconds < 0 ? 0 : transferMicroseconds,
        ),
      ),
    );
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    _roundTrips.clear();
    _worker.kill(priority: Isolate.immediate);
  }
}

enum _Command { step, framePresented, dispose }

Future<void> _runtimeWorkerMain(List<Object?> startup) async {
  final ready = startup[0]! as SendPort;
  final responses = startup[1]! as SendPort;
  final config = (startup[2]! as TransferableTypedData)
      .materialize()
      .asUint8List();
  NativeRuntime runtime;
  try {
    runtime = NativeRuntime.create(config);
  } catch (error) {
    ready.send(error.toString());
    return;
  }

  final commands = ReceivePort();
  ready.send(commands.sendPort);
  await for (final message in commands) {
    final values = message! as List<Object?>;
    final sequence = values[0]! as int;
    final command = _Command.values[values[1]! as int];
    if (command == _Command.dispose) {
      runtime.dispose();
      responses.send(_responseMessage(sequence, _emptySuccess(), 0));
      commands.close();
      break;
    }
    try {
      final stopwatch = Stopwatch()..start();
      final output = switch (command) {
        _Command.step => runtime.step(
          (values[2]! as TransferableTypedData).materialize().asUint8List(),
        ),
        _Command.framePresented => runtime.framePresented(values[2]! as int),
        _Command.dispose => _emptySuccess(),
      };
      stopwatch.stop();
      responses.send(
        _responseMessage(sequence, output, stopwatch.elapsedMicroseconds),
      );
    } catch (error) {
      responses.send(<Object?>[
        sequence,
        RuntimeStatus.fatalError.index,
        TransferableTypedData.fromList([Uint8List(0)]),
        0,
        -1,
        error.toString(),
        RuntimeErrorCode.nativeLibraryLoadingError.wireId,
        0,
      ]);
    }
  }
}

List<Object?> _responseMessage(
  int sequence,
  NativeOutput output,
  int ffiMicroseconds,
) => <Object?>[
  sequence,
  _runtimeStatus(output.status).index,
  TransferableTypedData.fromList([output.bytes]),
  output.revision,
  output.nextWakeupNanoseconds,
  output.errorMessage,
  output.errorCode.wireId,
  ffiMicroseconds,
];

NativeOutput _emptySuccess() => NativeOutput(
  status: NativeStatus.ok,
  bytes: Uint8List(0),
  revision: 0,
  nextWakeupNanoseconds: -1,
  errorMessage: null,
);

RuntimeStatus _runtimeStatus(NativeStatus status) => switch (status) {
  NativeStatus.ok => RuntimeStatus.ok,
  NativeStatus.recoverableError => RuntimeStatus.recoverableError,
  NativeStatus.fatalError => RuntimeStatus.fatalError,
};
