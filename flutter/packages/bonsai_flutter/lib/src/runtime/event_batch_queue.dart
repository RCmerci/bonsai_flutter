// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import '../debug/frame_stats.dart';
import '../protocol/event_batch.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/widget_registry.dart';

final class PreparedEventBatch {
  PreparedEventBatch._({
    required EventBatchQueue owner,
    required this.prefixLength,
    required this.encodedBytes,
    required int generation,
    required List<int> sequences,
  }) : _owner = owner,
       _generation = generation,
       _sequences = sequences;

  final EventBatchQueue _owner;
  final int _generation;
  final List<int> _sequences;
  final int prefixLength;
  final Uint8List encodedBytes;
  bool _committed = false;
}

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
  var _commitGeneration = 0;

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
    final prepared = prepareBatch();
    final batch = EventBatchCodec.decode(prepared.encodedBytes);
    commit(prepared);
    return batch;
  }

  PreparedEventBatch prepareBatch({int? runtimeControlRevision}) {
    final events = [
      for (final event in _pending)
        if (runtimeControlRevision != null && _isRuntimeControl(event.eventTag))
          UiEvent(
            sequence: event.sequence,
            displayedRevision: runtimeControlRevision,
            nodeId: event.nodeId,
            handlerId: event.handlerId,
            eventTag: event.eventTag,
            payload: event.payload,
          )
        else
          event,
    ];
    final batch = EventBatch(runtimeEpoch: runtimeEpoch, events: events);
    return PreparedEventBatch._(
      owner: this,
      prefixLength: events.length,
      encodedBytes: events.isEmpty
          ? Uint8List(0)
          : EventBatchCodec.encode(batch),
      generation: _commitGeneration,
      sequences: List.unmodifiable(events.map((event) => event.sequence)),
    );
  }

  void commit(PreparedEventBatch prepared) {
    if (!identical(prepared._owner, this)) {
      throw StateError('Prepared event batch belongs to another queue');
    }
    if (prepared._committed || prepared._generation != _commitGeneration) {
      throw StateError('Prepared event batch is stale or already committed');
    }
    if (prepared.prefixLength > _pending.length) {
      throw StateError('Prepared event prefix is no longer available');
    }
    for (var index = 0; index < prepared.prefixLength; index += 1) {
      if (_pending[index].sequence != prepared._sequences[index]) {
        throw StateError('Prepared event prefix no longer matches the queue');
      }
    }
    DebugFrameRecorder.recordEventBatch(
      runtimeEpoch: runtimeEpoch,
      batchSize: prepared.prefixLength,
      coalesced: _coalescedCount - _reportedCoalescedCount,
      dropped: _droppedCount - _reportedDroppedCount,
    );
    _reportedCoalescedCount = _coalescedCount;
    _reportedDroppedCount = _droppedCount;
    _pending.removeRange(0, prepared.prefixLength);
    prepared._committed = true;
    _commitGeneration += 1;
  }
}

bool _isCoalescible(int eventTag) =>
    eventTag == EventTagId.scrollNotification ||
    eventTag == EventTagId.visibleRangeChanged ||
    eventTag == EventTagId.textLimitReached;

bool _isRuntimeControl(int eventTag) =>
    eventTag == EventTagId.hostResponse ||
    eventTag == EventTagId.environmentChanged ||
    eventTag == EventTagId.resyncRequested;
