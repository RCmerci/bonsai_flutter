import '../debug/frame_stats.dart';
import '../protocol/event_batch.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/widget_registry.dart';

final class EventQueueBackpressureException implements Exception {
  const EventQueueBackpressureException(this.message);

  final String message;

  @override
  String toString() => 'EventQueueBackpressureException($message)';
}

final class EventBatchQueue {
  EventBatchQueue({
    required this.runtimeEpoch,
    required this.displayedRevision,
    this.maxPendingEvents = 1024,
  }) {
    if (runtimeEpoch < 0) {
      throw RangeError.value(runtimeEpoch, 'runtimeEpoch');
    }
    if (maxPendingEvents <= 0) {
      throw RangeError.value(maxPendingEvents, 'maxPendingEvents');
    }
  }

  final int runtimeEpoch;
  final int Function() displayedRevision;
  final int maxPendingEvents;
  final List<UiEvent> _pending = [];
  var _nextSequence = 1;
  var _coalescedCount = 0;
  var _droppedCount = 0;
  var _reportedCoalescedCount = 0;
  var _reportedDroppedCount = 0;

  int get pendingCount => _pending.length;
  int get coalescedCount => _coalescedCount;
  int get droppedCount => _droppedCount;

  void enqueue(RendererEvent event) {
    final coalescible = _isCoalescible(event.eventTag);
    if (coalescible) {
      final existing = _pending.indexWhere(
        (candidate) =>
            candidate.nodeId == event.nodeId &&
            candidate.handlerId == event.handlerId &&
            candidate.eventTag == event.eventTag,
      );
      if (existing >= 0) {
        _pending.removeAt(existing);
        _coalescedCount += 1;
      } else if (_pending.length >= maxPendingEvents) {
        final evictable = _pending.indexWhere(
          (candidate) => _isCoalescible(candidate.eventTag),
        );
        if (evictable < 0) {
          _droppedCount += 1;
          return;
        }
        _pending.removeAt(evictable);
        _droppedCount += 1;
      }
    } else if (_pending.length >= maxPendingEvents) {
      throw const EventQueueBackpressureException(
        'Ordered event queue is full; flush before accepting more input',
      );
    }

    _pending.add(
      UiEvent(
        sequence: _nextSequence++,
        displayedRevision: event.sourceRevision ?? displayedRevision(),
        nodeId: event.nodeId,
        handlerId: event.handlerId,
        eventTag: event.eventTag,
        payload: event.payload,
      ),
    );
  }

  void requestResync() {
    _droppedCount += _pending.length;
    _pending.clear();
    enqueue(
      const RendererEvent(
        nodeId: 0,
        eventTag: EventTagId.resyncRequested,
        handlerId: 0,
        payload: UnitEventPayload(),
      ),
    );
  }

  EventBatch? takeBatch() {
    if (_pending.isEmpty) return null;
    final batch = EventBatch(
      runtimeEpoch: runtimeEpoch,
      events: List.of(_pending),
    );
    DebugFrameRecorder.recordEventBatch(
      runtimeEpoch: runtimeEpoch,
      batchSize: batch.events.length,
      coalesced: _coalescedCount - _reportedCoalescedCount,
      dropped: _droppedCount - _reportedDroppedCount,
    );
    _reportedCoalescedCount = _coalescedCount;
    _reportedDroppedCount = _droppedCount;
    _pending.clear();
    return batch;
  }
}

bool _isCoalescible(int eventTag) =>
    eventTag == EventTagId.scrollNotification ||
    eventTag == EventTagId.visibleRangeChanged;
