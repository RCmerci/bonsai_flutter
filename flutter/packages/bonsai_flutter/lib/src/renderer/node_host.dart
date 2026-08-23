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
  final Map<int, void Function()> _navigationPageUnsubscribes = {};
  RendererBoundaryError? _buildError;
  int? _failedLocalRevision;
  RendererResourceStore? _leasedResources;
  int? _leasedNodeId;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateResourceLease(RendererResourceScope.of(context), widget.nodeId);
  }

  @override
  void didUpdateWidget(NodeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.nodeId != widget.nodeId) {
      _unsubscribe?.call();
      _clearNavigationPageSubscriptions();
      _subscribe();
    }
    if (oldWidget.nodeId != widget.nodeId && _leasedResources != null) {
      _updateResourceLease(_leasedResources!, widget.nodeId);
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _clearNavigationPageSubscriptions();
    final resources = _leasedResources;
    final nodeId = _leasedNodeId;
    if (resources != null && nodeId != null) {
      resources.unmountNode(nodeId);
    }
    super.dispose();
  }

  void _updateResourceLease(RendererResourceStore resources, int nodeId) {
    if (identical(_leasedResources, resources) && _leasedNodeId == nodeId) {
      return;
    }
    final previousResources = _leasedResources;
    final previousNodeId = _leasedNodeId;
    if (previousResources != null && previousNodeId != null) {
      previousResources.unmountNode(previousNodeId);
    }
    resources.mountNode(nodeId);
    _leasedResources = resources;
    _leasedNodeId = nodeId;
  }

  void _subscribe() {
    _unsubscribe = widget.store.subscribe(widget.nodeId, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.store.node(widget.nodeId);
    _synchronizeNavigationPageSubscriptions(node);
    final sourceRevision = widget.store.revision;
    if (_failedLocalRevision == node.localRevision && _buildError != null) {
      return _errorFallback(node.kind, _buildError!);
    }
    _buildError = null;
    _failedLocalRevision = null;
    final children = [
      for (final childId in node.children) _buildChildHost(childId),
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
      return _errorFallback(node.kind, error);
    }
  }

  Widget _buildChildHost(int childId) {
    final host = NodeHost(
      key: ValueKey<int>(childId),
      store: widget.store,
      nodeId: childId,
      registry: widget.registry,
      onEvent: widget.onEvent,
    );
    final child = widget.store.node(childId);
    return switch (child.props) {
      PreferredSizeProps(:final height) => _PreferredSizeNodeHost(
        height: height,
        child: host,
      ),
      _ => host,
    };
  }

  void _synchronizeNavigationPageSubscriptions(UiNode node) {
    final desired = node.kind == NodeKind.navigator
        ? node.children.toSet()
        : const <int>{};
    for (final nodeId
        in _navigationPageUnsubscribes.keys
            .where((nodeId) => !desired.contains(nodeId))
            .toList(growable: false)) {
      _navigationPageUnsubscribes.remove(nodeId)?.call();
    }
    for (final nodeId in desired) {
      _navigationPageUnsubscribes.putIfAbsent(
        nodeId,
        () => widget.store.subscribe(nodeId, () {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  void _clearNavigationPageSubscriptions() {
    for (final unsubscribe in _navigationPageUnsubscribes.values) {
      unsubscribe();
    }
    _navigationPageUnsubscribes.clear();
  }
}

Widget _errorFallback(NodeKind kind, RendererBoundaryError error) {
  final surface = BonsaiRendererErrorWidget(error: error);
  return _isCoreSliverKind(kind) ? SliverToBoxAdapter(child: surface) : surface;
}

bool _isCoreSliverKind(NodeKind kind) => switch (kind) {
  NodeKind.sliverBox ||
  NodeKind.sliverList ||
  NodeKind.sliverFill ||
  NodeKind.sliverFixedExtent ||
  NodeKind.sliverVariedExtent ||
  NodeKind.sliverPadding ||
  NodeKind.sliverAppBar => true,
  NodeKind.empty ||
  NodeKind.environmentBoundary ||
  NodeKind.text ||
  NodeKind.richText ||
  NodeKind.icon ||
  NodeKind.image ||
  NodeKind.row ||
  NodeKind.column ||
  NodeKind.stack ||
  NodeKind.button ||
  NodeKind.padding ||
  NodeKind.align ||
  NodeKind.center ||
  NodeKind.sizedBox ||
  NodeKind.constrainedBox ||
  NodeKind.decoratedBox ||
  NodeKind.clip ||
  NodeKind.opacity ||
  NodeKind.animatedOpacity ||
  NodeKind.transform ||
  NodeKind.scrollView ||
  NodeKind.preferredSize ||
  NodeKind.gesture ||
  NodeKind.focusScope ||
  NodeKind.mouseRegion ||
  NodeKind.keyboardListener ||
  NodeKind.pressable ||
  NodeKind.semantics ||
  NodeKind.theme ||
  NodeKind.materialScaffold ||
  NodeKind.materialAppBar ||
  NodeKind.materialElevatedButton ||
  NodeKind.materialTextButton ||
  NodeKind.materialIconButton ||
  NodeKind.materialFilledButton ||
  NodeKind.materialFilledTonalButton ||
  NodeKind.materialOutlinedButton ||
  NodeKind.materialFloatingActionButton ||
  NodeKind.materialNavigationBar ||
  NodeKind.materialRadioGroup ||
  NodeKind.materialSlider ||
  NodeKind.materialRangeSlider ||
  NodeKind.materialActionChip ||
  NodeKind.materialFilterChip ||
  NodeKind.materialChoiceChip ||
  NodeKind.materialInputChip ||
  NodeKind.materialAlertDialog ||
  NodeKind.materialCheckbox ||
  NodeKind.materialSwitch ||
  NodeKind.materialListTile ||
  NodeKind.materialDivider ||
  NodeKind.materialCard ||
  NodeKind.materialCircularProgressIndicator ||
  NodeKind.cupertinoButton ||
  NodeKind.cupertinoSwitch ||
  NodeKind.textInput ||
  NodeKind.overlay ||
  NodeKind.navigator ||
  NodeKind.page ||
  NodeKind.safeArea ||
  NodeKind.nativeWidget => false,
};

final class _PreferredSizeNodeHost extends StatelessWidget
    implements PreferredSizeWidget {
  const _PreferredSizeNodeHost({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => child;
}
