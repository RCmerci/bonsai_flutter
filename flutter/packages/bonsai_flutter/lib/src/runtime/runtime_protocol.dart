import 'dart:isolate';

sealed class RuntimeCommand {
  const RuntimeCommand();
}

final class VsyncGranted extends RuntimeCommand {
  const VsyncGranted(this.generation);

  final int generation;
}

final class VisibilityChanged extends RuntimeCommand {
  const VisibilityChanged({required this.generation, required this.eligible});

  final int generation;
  final bool eligible;
}

final class PresentationSucceeded extends RuntimeCommand {
  const PresentationSucceeded({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.events,
  });

  final int generation;
  final int presentationId;
  final int revision;
  final TransferableTypedData events;
}

enum PresentationRejectionReason {
  decodeFailed,
  frameValidationFailed,
  rendererEpochMismatch,
  rendererRevisionMismatch,
}

final class PresentationRejected extends RuntimeCommand {
  const PresentationRejected({
    required this.generation,
    required this.presentationId,
    required this.revision,
    required this.reason,
  });

  final int generation;
  final int presentationId;
  final int revision;
  final PresentationRejectionReason reason;
}

final class DebugRuntime extends RuntimeCommand {
  const DebugRuntime(this.requestId);

  final int requestId;
}

final class DisposeRuntime extends RuntimeCommand {
  const DisposeRuntime();
}

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
  nativeLibraryLoadingError(12),
  invalidPresentation(13),
  invalidMonotonicTime(14),
  invalidSchedulerState(15);

  const RuntimeErrorCode(this.wireId);

  final int wireId;

  static RuntimeErrorCode fromWireId(int value) {
    for (final code in values) {
      if (code.wireId == value) return code;
    }
    throw StateError('Unknown runtime error code $value');
  }
}

final class RuntimeDiagnostic {
  const RuntimeDiagnostic({required this.code, required this.message});

  final RuntimeErrorCode code;
  final String message;
}

sealed class RuntimeUpdate {
  const RuntimeUpdate();
}

enum RuntimeWorkerState { ready, awaitingPresentation, terminal }

final class CycleReady extends RuntimeUpdate {
  const CycleReady({
    required this.presentationId,
    required this.revision,
    required this.bytes,
    required this.recoverableDiagnostic,
  });

  final int presentationId;
  final int revision;
  final TransferableTypedData bytes;
  final RuntimeDiagnostic? recoverableDiagnostic;
}

final class RuntimeFatalDiagnostic extends RuntimeUpdate {
  const RuntimeFatalDiagnostic(this.diagnostic);

  final RuntimeDiagnostic diagnostic;
}

final class RuntimeDebugSnapshot extends RuntimeUpdate {
  const RuntimeDebugSnapshot({
    this.requestId,
    required this.state,
    required this.liveGeneration,
    required this.eligible,
    required this.hasCoalescedGrant,
    required this.unresolvedPresentationId,
    required this.unresolvedRevision,
    required this.pumpCount,
  });

  final int? requestId;
  final RuntimeWorkerState state;
  final int liveGeneration;
  final bool eligible;
  final bool hasCoalescedGrant;
  final int? unresolvedPresentationId;
  final int? unresolvedRevision;
  final int pumpCount;
}

final class RuntimeDisposed extends RuntimeUpdate {
  const RuntimeDisposed();
}
