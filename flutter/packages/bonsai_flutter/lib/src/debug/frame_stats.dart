import '../protocol/frame.dart';

final class BonsaiFlutterFrameStats {
  BonsaiFlutterFrameStats({
    required this.runtimeEpoch,
    required this.revision,
    required this.frameKind,
    required this.patchCount,
    required this.patchBytes,
    required this.fullSnapshotCount,
  });

  final int runtimeEpoch;
  final int revision;
  final FrameKind frameKind;
  final int patchCount;
  final int patchBytes;
  final int fullSnapshotCount;
  int eventBatchSize = 0;
  int coalescedEventCount = 0;
  int droppedEventCount = 0;
  int dirtyNodeCount = 0;
  Duration? decodeDuration;
  Duration? nodeStoreApplyDuration;
  Duration? flutterBuildDuration;
  Duration? layoutDuration;
  Duration? paintDuration;
  int? bonsaiFlushNanoseconds;
  int? resultReadNanoseconds;
  int? reconcileNanoseconds;
  int? encodeNanoseconds;
  int? lifecycleNanoseconds;
  int resyncCount = 0;
}

final class DebugFrameRecorder {
  DebugFrameRecorder._();

  static const int _maximumFrames = 256;
  static final List<BonsaiFlutterFrameStats> _frames = [];
  static final Map<String, BonsaiFlutterFrameStats> _byFrame = {};
  static final Map<int, _PendingEventStats> _pendingEvents = {};
  static var _fullSnapshotCount = 0;

  static void recordDecoded(
    Frame frame, {
    required int patchBytes,
    required Duration duration,
  }) {
    if (frame.kind == FrameKind.fullSnapshot) {
      _fullSnapshotCount += 1;
    }
    final runtimeStats = frame.operations.whereType<RuntimeStatsOperation>();
    final runtime = runtimeStats.isEmpty ? null : runtimeStats.single;
    final stats = BonsaiFlutterFrameStats(
      runtimeEpoch: frame.runtimeEpoch,
      revision: frame.targetRevision,
      frameKind: frame.kind,
      patchCount: runtime?.patchCount ?? frame.operations.length,
      patchBytes: patchBytes,
      fullSnapshotCount: _fullSnapshotCount,
    )..decodeDuration = duration;
    if (runtime != null) {
      stats
        ..eventBatchSize = runtime.eventBatchSize
        ..bonsaiFlushNanoseconds = runtime.bonsaiFlushNanoseconds
        ..resultReadNanoseconds = runtime.resultReadNanoseconds
        ..reconcileNanoseconds = runtime.reconcileNanoseconds
        ..encodeNanoseconds = runtime.encodeNanoseconds
        ..lifecycleNanoseconds = runtime.lifecycleNanoseconds
        ..resyncCount = runtime.resyncCount;
    }
    final pending = _pendingEvents.remove(frame.runtimeEpoch);
    if (pending != null) {
      stats
        ..eventBatchSize = pending.batchSize
        ..coalescedEventCount = pending.coalesced
        ..droppedEventCount = pending.dropped;
    }
    _frames.add(stats);
    _byFrame[_key(frame.runtimeEpoch, frame.targetRevision)] = stats;
    if (_frames.length > _maximumFrames) {
      final removed = _frames.removeAt(0);
      _byFrame.remove(_key(removed.runtimeEpoch, removed.revision));
    }
  }

  static void recordApplied(
    Frame frame, {
    required int dirtyNodeCount,
    required Duration duration,
  }) {
    final stats =
        _byFrame[_key(frame.runtimeEpoch, frame.targetRevision)] ??
        _recordFrameWithoutDecode(frame);
    stats
      ..dirtyNodeCount = dirtyNodeCount
      ..nodeStoreApplyDuration = duration;
  }

  static void recordEventBatch({
    required int runtimeEpoch,
    required int batchSize,
    required int coalesced,
    required int dropped,
  }) {
    final current = _pendingEvents[runtimeEpoch];
    _pendingEvents[runtimeEpoch] = _PendingEventStats(
      batchSize: (current?.batchSize ?? 0) + batchSize,
      coalesced: (current?.coalesced ?? 0) + coalesced,
      dropped: (current?.dropped ?? 0) + dropped,
    );
  }

  static void recordFlutterTiming(
    int runtimeEpoch,
    int revision, {
    required Duration buildDuration,
    required Duration layoutDuration,
    required Duration paintDuration,
  }) {
    final stats = _byFrame[_key(runtimeEpoch, revision)];
    if (stats == null) return;
    stats
      ..flutterBuildDuration = buildDuration
      ..layoutDuration = layoutDuration
      ..paintDuration = paintDuration;
  }

  static List<BonsaiFlutterFrameStats> snapshot() => List.unmodifiable(_frames);

  static void reset() {
    _frames.clear();
    _byFrame.clear();
    _pendingEvents.clear();
    _fullSnapshotCount = 0;
  }

  static BonsaiFlutterFrameStats _recordFrameWithoutDecode(Frame frame) {
    if (frame.kind == FrameKind.fullSnapshot) {
      _fullSnapshotCount += 1;
    }
    final stats = BonsaiFlutterFrameStats(
      runtimeEpoch: frame.runtimeEpoch,
      revision: frame.targetRevision,
      frameKind: frame.kind,
      patchCount: frame.operations.length,
      patchBytes: 0,
      fullSnapshotCount: _fullSnapshotCount,
    );
    _frames.add(stats);
    _byFrame[_key(frame.runtimeEpoch, frame.targetRevision)] = stats;
    return stats;
  }

  static String _key(int epoch, int revision) => '$epoch:$revision';
}

final class _PendingEventStats {
  const _PendingEventStats({
    required this.batchSize,
    required this.coalesced,
    required this.dropped,
  });

  final int batchSize;
  final int coalesced;
  final int dropped;
}
