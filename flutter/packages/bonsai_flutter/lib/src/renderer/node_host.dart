import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../protocol/frame.dart';
import '../store/node_store.dart';
import 'renderer_resource_store.dart';
import 'widget_registry.dart';

final class RendererBoundaryError implements Exception {
  const RendererBoundaryError({
    required this.nodeId,
    required this.kind,
    required this.revision,
    required this.cause,
    required this.stackTrace,
  });

  final int nodeId;
  final NodeKind kind;
  final int revision;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'RendererBoundaryError(node: $nodeId, kind: ${kind.name}, '
      'revision: $revision, cause: $cause)';
}

final class BonsaiRendererErrorWidget extends StatelessWidget {
  const BonsaiRendererErrorWidget({required this.error, super.key});

  final RendererBoundaryError error;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffffe9e9),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        kDebugMode
            ? 'bonsai_flutter renderer error at node ${error.nodeId} '
                  '(${error.kind.name}), revision ${error.revision}'
            : 'Unable to render this view.',
        textDirection: TextDirection.ltr,
      ),
    ),
  );
}

final class BonsaiFlutterView extends StatefulWidget {
  BonsaiFlutterView({
    required this.store,
    this.onEvent,
    this.resourceStore,
    WidgetRegistry? registry,
    super.key,
  }) : registry = registry ?? WidgetRegistry.standard();

  final NodeStore store;
  final WidgetRegistry registry;
  final RendererEventCallback? onEvent;
  final RendererResourceStore? resourceStore;

  @override
  State<BonsaiFlutterView> createState() => _BonsaiFlutterViewState();
}

final class _BonsaiFlutterViewState extends State<BonsaiFlutterView> {
  void Function()? _unsubscribe;
  int? _rootId;
  late RendererResourceStore _resources;
  late bool _ownsResources;

  @override
  void initState() {
    super.initState();
    _configureResources();
    _subscribe();
  }

  @override
  void didUpdateWidget(BonsaiFlutterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.resourceStore, widget.resourceStore)) {
      if (_ownsResources) {
        _resources.dispose();
      }
      _configureResources();
      _resources.synchronize(widget.store);
    }
    if (!identical(oldWidget.store, widget.store)) {
      _unsubscribe?.call();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    if (_ownsResources) {
      _resources.dispose();
    }
    super.dispose();
  }

  void _configureResources() {
    _ownsResources = widget.resourceStore == null;
    _resources = widget.resourceStore ?? RendererResourceStore();
  }

  void _subscribe() {
    _rootId = widget.store.rootId;
    _resources.synchronize(widget.store);
    _unsubscribe = widget.store.subscribeStore(() {
      _resources.synchronize(widget.store);
      final nextRootId = widget.store.rootId;
      if (nextRootId != _rootId && mounted) {
        setState(() => _rootId = nextRootId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rootId = _rootId;
    if (rootId == null) return const SizedBox.shrink();
    return RendererResourceScope(
      resources: _resources,
      child: NodeHost(
        key: ValueKey<int>(rootId),
        store: widget.store,
        nodeId: rootId,
        registry: widget.registry,
        onEvent: widget.onEvent,
      ),
    );
  }
}

final class NodeHost extends StatefulWidget {
  const NodeHost({
    required this.store,
    required this.nodeId,
    required this.registry,
    this.onEvent,
    super.key,
  });

  final NodeStore store;
  final int nodeId;
  final WidgetRegistry registry;
  final RendererEventCallback? onEvent;

  @override
  State<NodeHost> createState() => _NodeHostState();
}

final class _NodeHostState extends State<NodeHost> {
  void Function()? _unsubscribe;
  RendererBoundaryError? _buildError;
  int? _failedLocalRevision;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NodeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.nodeId != widget.nodeId) {
      _unsubscribe?.call();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _subscribe() {
    _unsubscribe = widget.store.subscribe(widget.nodeId, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.store.node(widget.nodeId);
    final sourceRevision = widget.store.revision;
    if (_failedLocalRevision == node.localRevision && _buildError != null) {
      return BonsaiRendererErrorWidget(error: _buildError!);
    }
    _buildError = null;
    _failedLocalRevision = null;
    final children = [
      for (final childId in node.children)
        NodeHost(
          key: ValueKey<int>(childId),
          store: widget.store,
          nodeId: childId,
          registry: widget.registry,
          onEvent: widget.onEvent,
        ),
    ];
    try {
      final onEvent = widget.onEvent;
      final store = widget.store;
      final built = widget.registry.build(
        context,
        node,
        children,
        onEvent == null
            ? null
            : (event) {
                final currentNode = store.nodes[event.nodeId];
                final bindingIsCurrent =
                    currentNode != null &&
                    currentNode.eventBindings.any(
                      (binding) =>
                          binding.eventTag == event.eventTag &&
                          binding.handlerId == event.handlerId,
                    );
                onEvent(
                  event.fromRevision(
                    bindingIsCurrent ? store.revision : sourceRevision,
                  ),
                );
              },
      );
      return switch (node.parentData) {
        NoParentData() => built,
        FlexParentData(:final flex, fit: FlexParentFit.loose) => Flexible(
          flex: flex,
          child: built,
        ),
        FlexParentData(:final flex, fit: FlexParentFit.tight) => Expanded(
          flex: flex,
          child: built,
        ),
        StackPositionData(
          :final left,
          :final top,
          :final right,
          :final bottom,
        ) =>
          Positioned(
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            child: built,
          ),
      };
    } catch (cause, stackTrace) {
      final error = RendererBoundaryError(
        nodeId: node.id,
        kind: node.kind,
        revision: widget.store.revision,
        cause: cause,
        stackTrace: stackTrace,
      );
      _buildError = error;
      _failedLocalRevision = node.localRevision;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'bonsai_flutter',
          context: ErrorDescription(
            'while building node ${node.id} (${node.kind.name}) at '
            'revision ${widget.store.revision}',
          ),
        ),
      );
      return BonsaiRendererErrorWidget(error: error);
    }
  }
}
