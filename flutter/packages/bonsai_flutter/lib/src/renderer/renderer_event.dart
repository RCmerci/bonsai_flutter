import '../protocol/event_batch.dart';

typedef RendererEventCallback = void Function(RendererEvent event);

final class RendererEvent {
  const RendererEvent({
    required this.nodeId,
    required this.eventTag,
    required this.handlerId,
    required this.payload,
    this.sourceRevision,
  });

  final int nodeId;
  final int eventTag;
  final int handlerId;
  final EventPayload payload;
  final int? sourceRevision;

  RendererEvent fromRevision(int revision) => RendererEvent(
    nodeId: nodeId,
    eventTag: eventTag,
    handlerId: handlerId,
    payload: payload,
    sourceRevision: revision,
  );
}
