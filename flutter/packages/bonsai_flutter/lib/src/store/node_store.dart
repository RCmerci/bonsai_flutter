// ignore_for_file: prefer_initializing_formals

import 'dart:collection';

import '../debug/frame_stats.dart';
import '../protocol/frame.dart';

enum FrameErrorCode {
  revisionMismatch,
  epochMismatch,
  invalidRevision,
  duplicateNode,
  missingNode,
  invalidProps,
  invalidApplicationTheme,
  missingRoot,
  cycle,
  multipleParents,
  unreachableNode,
}

final class FrameApplyException implements Exception {
  const FrameApplyException(this.code, this.message);

  final FrameErrorCode code;
  final String message;

  @override
  String toString() => 'FrameApplyException($code, $message)';
}

final class UiNode {
  const UiNode({
    required this.id,
    required this.kind,
    required this.props,
    required this.eventBindings,
    required this.parentData,
    required this.children,
    required this.localRevision,
    required this.deliveryGeneration,
  });

  final int id;
  final NodeKind kind;
  final UiProps props;
  final List<EventBinding> eventBindings;
  final ParentDataValue parentData;
  final List<int> children;
  final int localRevision;
  final int deliveryGeneration;

  UiNode copyWith({
    UiProps? props,
    List<EventBinding>? eventBindings,
    List<int>? children,
  }) => UiNode(
    id: id,
    kind: kind,
    props: props ?? this.props,
    eventBindings: eventBindings ?? this.eventBindings,
    parentData: parentData,
    children: children ?? this.children,
    localRevision: localRevision + 1,
    deliveryGeneration: deliveryGeneration,
  );
}

final class ApplyResult {
  const ApplyResult({required this.dirtyNodeIds, required this.droppedNodeIds});

  final Set<int> dirtyNodeIds;
  final Set<int> droppedNodeIds;
}

final class PreparedNodeStoreFrame {
  PreparedNodeStoreFrame._({
    required NodeStore owner,
    required Map<int, UiNode> baseNodes,
    required int? baseRootId,
    required int? baseRuntimeEpoch,
    required int baseRevision,
    required ApplicationThemeValue? baseApplicationTheme,
    required String? baseApplicationTitle,
    required this.frame,
    required Map<int, UiNode> nodes,
    required this.rootId,
    required this.resourceGeneration,
    required this.applicationTheme,
    required this.applicationTitle,
    required this.result,
    required this.prepareDuration,
  }) : _owner = owner,
       _baseNodes = baseNodes,
       _baseRootId = baseRootId,
       _baseRuntimeEpoch = baseRuntimeEpoch,
       _baseRevision = baseRevision,
       _baseApplicationTheme = baseApplicationTheme,
       _baseApplicationTitle = baseApplicationTitle,
       _nodes = nodes;

  final NodeStore _owner;
  final Map<int, UiNode> _baseNodes;
  final int? _baseRootId;
  final int? _baseRuntimeEpoch;
  final int _baseRevision;
  final ApplicationThemeValue? _baseApplicationTheme;
  final String? _baseApplicationTitle;
  final Frame frame;
  final Map<int, UiNode> _nodes;
  final int? rootId;
  final int resourceGeneration;
  final ApplicationThemeValue applicationTheme;
  final String? applicationTitle;
  final ApplyResult result;
  final Duration prepareDuration;
  bool _committed = false;
}

typedef NodeListener = void Function();

final class NodeStore {
  Map<int, UiNode> _nodes = const {};
  int? _rootId;
  int? _runtimeEpoch;
  int _revision = 0;
  int _resourceGeneration = 0;
  ApplicationThemeValue? _applicationTheme;
  String? _applicationTitle;
  final Map<int, Set<NodeListener>> _listeners = {};
  final Set<NodeListener> _storeListeners = {};

  Map<int, UiNode> get nodes => _nodes;
  int? get rootId => _rootId;
  int? get runtimeEpoch => _runtimeEpoch;
  int get revision => _revision;
  int get resourceGeneration => _resourceGeneration;
  ApplicationThemeValue? get applicationTheme => _applicationTheme;
  String? get applicationTitle => _applicationTitle;

  UiNode node(int nodeId) {
    final result = _nodes[nodeId];
    if (result == null) {
      throw FrameApplyException(
        FrameErrorCode.missingNode,
        'Node $nodeId does not exist',
      );
    }
    return result;
  }

  void Function() subscribe(int nodeId, NodeListener listener) {
    (_listeners[nodeId] ??= {}).add(listener);
    return () {
      final listeners = _listeners[nodeId];
      listeners?.remove(listener);
      if (listeners != null && listeners.isEmpty) {
        _listeners.remove(nodeId);
      }
    };
  }

  void Function() subscribeStore(NodeListener listener) {
    _storeListeners.add(listener);
    return () => _storeListeners.remove(listener);
  }

  ApplyResult apply(Frame frame) => commit(prepare(frame));

  PreparedNodeStoreFrame prepare(Frame frame) {
    final stopwatch = Stopwatch()..start();
    final baseNodes = _nodes;
    final baseRootId = _rootId;
    final baseRuntimeEpoch = _runtimeEpoch;
    final baseRevision = _revision;
    final baseApplicationTheme = _applicationTheme;
    final baseApplicationTitle = _applicationTitle;
    _validateRevision(frame);

    final isFullSnapshot = frame.kind == FrameKind.fullSnapshot;
    final shadow = isFullSnapshot
        ? <int, UiNode>{}
        : Map<int, UiNode>.of(_nodes);
    var shadowRoot = isFullSnapshot ? null : _rootId;
    ApplicationThemeValue? shadowTheme = isFullSnapshot
        ? null
        : _applicationTheme;
    String? shadowTitle = isFullSnapshot ? null : _applicationTitle;
    var themeOperationCount = 0;
    final dirty = <int>{};
    final dropped = isFullSnapshot ? _nodes.keys.toSet() : <int>{};

    for (final operation in frame.operations) {
      switch (operation) {
        case CreateNode():
          if (shadow.containsKey(operation.nodeId)) {
            _fail(
              FrameErrorCode.duplicateNode,
              'Node ${operation.nodeId} already exists',
            );
          }
          _validateProps(operation.kind, operation.props);
          shadow[operation.nodeId] = UiNode(
            id: operation.nodeId,
            kind: operation.kind,
            props: operation.props,
            eventBindings: List.unmodifiable(operation.eventBindings),
            parentData: operation.parentData,
            children: const [],
            localRevision: 0,
            deliveryGeneration: isFullSnapshot
                ? _resourceGeneration + 1
                : _resourceGeneration,
          );
          dirty.add(operation.nodeId);
        case UpdateProps():
          final current = _requiredNode(shadow, operation.nodeId);
          _validateProps(current.kind, operation.props);
          shadow[operation.nodeId] = current.copyWith(props: operation.props);
          dirty.add(operation.nodeId);
        case UpdateEventBindings():
          final current = _requiredNode(shadow, operation.nodeId);
          shadow[operation.nodeId] = current.copyWith(
            eventBindings: List.unmodifiable(operation.eventBindings),
          );
          dirty.add(operation.nodeId);
        case SetChildren():
          final current = _requiredNode(shadow, operation.nodeId);
          shadow[operation.nodeId] = current.copyWith(
            children: List.unmodifiable(operation.children),
          );
          dirty.add(operation.nodeId);
        case SetRoot():
          shadowRoot = operation.nodeId;
        case SetApplicationTheme():
          themeOperationCount += 1;
          if (themeOperationCount > 1) {
            _fail(
              FrameErrorCode.invalidApplicationTheme,
              'A frame may contain at most one application theme',
            );
          }
          _validateApplicationTheme(operation.theme, operation.title);
          shadowTheme = operation.theme;
          shadowTitle = operation.title;
        case DropNode():
          if (shadow.remove(operation.nodeId) == null) {
            _fail(
              FrameErrorCode.missingNode,
              'Cannot drop missing node ${operation.nodeId}',
            );
          }
          dropped.add(operation.nodeId);
          dirty.remove(operation.nodeId);
        case HostRequestOperation() ||
            CancelHostRequestOperation() ||
            ApplicationRequestOperation():
        // Platform requests are consumed by their dispatchers, outside the
        // renderer's atomic node transaction.
        case RuntimeStatsOperation():
        // Debug instrumentation is consumed after frame decode and never
        // participates in the atomic node transaction.
      }
    }

    _validateTree(shadow, shadowRoot);
    if (shadowTheme == null || (isFullSnapshot && themeOperationCount != 1)) {
      _fail(
        FrameErrorCode.invalidApplicationTheme,
        'A full snapshot requires exactly one application theme',
      );
    }

    final result = ApplyResult(
      dirtyNodeIds: Set.unmodifiable(dirty),
      droppedNodeIds: Set.unmodifiable(dropped),
    );
    stopwatch.stop();
    return PreparedNodeStoreFrame._(
      owner: this,
      baseNodes: baseNodes,
      baseRootId: baseRootId,
      baseRuntimeEpoch: baseRuntimeEpoch,
      baseRevision: baseRevision,
      baseApplicationTheme: baseApplicationTheme,
      baseApplicationTitle: baseApplicationTitle,
      frame: frame,
      nodes: !isFullSnapshot && dirty.isEmpty && dropped.isEmpty
          ? baseNodes
          : UnmodifiableMapView(shadow),
      rootId: shadowRoot,
      resourceGeneration: isFullSnapshot
          ? _resourceGeneration + 1
          : _resourceGeneration,
      applicationTheme: shadowTheme,
      applicationTitle: shadowTitle,
      result: result,
      prepareDuration: stopwatch.elapsed,
    );
  }

  ApplyResult commit(PreparedNodeStoreFrame prepared) {
    if (!identical(prepared._owner, this)) {
      throw StateError('Prepared frame belongs to another NodeStore');
    }
    if (prepared._committed) {
      throw StateError('Prepared frame was already committed');
    }
    if (!identical(_nodes, prepared._baseNodes) ||
        _rootId != prepared._baseRootId ||
        _runtimeEpoch != prepared._baseRuntimeEpoch ||
        _applicationTheme != prepared._baseApplicationTheme ||
        _applicationTitle != prepared._baseApplicationTitle ||
        _revision != prepared._baseRevision) {
      throw StateError('Prepared frame base is stale');
    }
    prepared._committed = true;
    _nodes = prepared._nodes;
    _rootId = prepared.rootId;
    _runtimeEpoch = prepared.frame.runtimeEpoch;
    _revision = prepared.frame.targetRevision;
    _resourceGeneration = prepared.resourceGeneration;
    _applicationTheme = prepared.applicationTheme;
    _applicationTitle = prepared.applicationTitle;

    for (final nodeId in prepared.result.dirtyNodeIds) {
      final listeners = _listeners[nodeId]?.toList(growable: false) ?? const [];
      for (final listener in listeners) {
        listener();
      }
    }
    for (final listener in _storeListeners.toList(growable: false)) {
      listener();
    }

    DebugFrameRecorder.recordApplied(
      prepared.frame,
      dirtyNodeCount: prepared.result.dirtyNodeIds.length,
      duration: prepared.prepareDuration,
    );
    return prepared.result;
  }

  void _validateApplicationTheme(ApplicationThemeValue theme, String? title) {
    if (title != null && (title.trim().isEmpty || title.contains('\u0000'))) {
      _fail(
        FrameErrorCode.invalidApplicationTheme,
        'Application title must be non-empty and contain no NUL',
      );
    }
    if (theme.light.brightness != ThemeBrightness.light ||
        theme.dark.brightness != ThemeBrightness.dark ||
        theme.highContrastLight?.brightness == ThemeBrightness.dark ||
        theme.highContrastDark?.brightness == ThemeBrightness.light) {
      _fail(
        FrameErrorCode.invalidApplicationTheme,
        'Application theme brightness variants are inconsistent',
      );
    }
    for (final data in [
      theme.light,
      theme.dark,
      theme.highContrastLight,
      theme.highContrastDark,
    ].whereType<ThemeDataValue>()) {
      final contrast = data.colorScheme.contrastLevel;
      if (!contrast.isFinite || contrast < -1 || contrast > 1) {
        _fail(
          FrameErrorCode.invalidApplicationTheme,
          'Theme contrast must be finite and between -1 and 1',
        );
      }
      for (final radius in [
        data.shape.extraSmall,
        data.shape.small,
        data.shape.medium,
        data.shape.large,
        data.shape.extraLarge,
      ]) {
        if (!radius.isFinite || radius < 0) {
          _fail(
            FrameErrorCode.invalidApplicationTheme,
            'Theme shape radii must be finite and non-negative',
          );
        }
      }
      final fontNames = [
        ?data.typography.fontFamily,
        ...data.typography.fontFamilyFallback,
      ];
      if (data.typography.fontFamilyFallback.length > 16 ||
          fontNames.any(
            (name) => name.trim().isEmpty || name.contains('\u0000'),
          )) {
        _fail(
          FrameErrorCode.invalidApplicationTheme,
          'Theme font names are invalid',
        );
      }
      for (final role in data.typography.roles.whereType<TextStyleValue>()) {
        for (final value in [role.fontSize, role.lineHeight]) {
          if (value != null && (!value.isFinite || value <= 0)) {
            _fail(
              FrameErrorCode.invalidApplicationTheme,
              'Theme text sizes must be finite and positive',
            );
          }
        }
      }
    }
  }

  void _validateRevision(Frame frame) {
    if (frame.targetRevision <= frame.baseRevision) {
      _fail(
        FrameErrorCode.invalidRevision,
        'Target revision must be greater than base revision',
      );
    }
    switch (frame.kind) {
      case FrameKind.fullSnapshot:
        if (frame.baseRevision != 0) {
          _fail(
            FrameErrorCode.revisionMismatch,
            'Full snapshots must use base revision zero',
          );
        }
      case FrameKind.incremental:
        if (_runtimeEpoch != frame.runtimeEpoch) {
          _fail(
            FrameErrorCode.epochMismatch,
            'Expected epoch $_runtimeEpoch, got ${frame.runtimeEpoch}',
          );
        }
        if (_revision != frame.baseRevision) {
          _fail(
            FrameErrorCode.revisionMismatch,
            'Expected revision $_revision, got ${frame.baseRevision}',
          );
        }
    }
  }

  void _validateTree(Map<int, UiNode> nodes, int? rootId) {
    if (rootId == null || !nodes.containsKey(rootId)) {
      _fail(FrameErrorCode.missingRoot, 'The frame has no valid root');
    }
    if (nodes[rootId]!.parentData is! NoParentData) {
      _fail(
        FrameErrorCode.invalidProps,
        'The root node cannot have parent data',
      );
    }

    final parentCounts = {for (final id in nodes.keys) id: 0};
    for (final node in nodes.values) {
      final availableChildren = switch (node.props) {
        SliverFixedExtentProps(:final totalCount, :final firstIndex) ||
        SliverVariedExtentProps(
          :final totalCount,
          :final firstIndex,
        ) => totalCount - firstIndex,
        _ => null,
      };
      if (availableChildren != null &&
          node.children.length > availableChildren) {
        _fail(
          FrameErrorCode.invalidProps,
          'Virtual sliver node ${node.id} has more children than its logical window',
        );
      }
      for (final childId in node.children) {
        if (!nodes.containsKey(childId)) {
          _fail(
            FrameErrorCode.missingNode,
            'Node ${node.id} references missing child $childId',
          );
        }
        parentCounts[childId] = parentCounts[childId]! + 1;
        final child = nodes[childId]!;
        switch (child.parentData) {
          case NoParentData():
            break;
          case FlexParentData():
            if (node.kind != NodeKind.row && node.kind != NodeKind.column) {
              _fail(
                FrameErrorCode.invalidProps,
                'Flex parent data requires a Row or Column parent',
              );
            }
          case StackPositionData():
            if (node.kind != NodeKind.stack) {
              _fail(
                FrameErrorCode.invalidProps,
                'Positioned parent data requires a Stack parent',
              );
            }
        }
      }
    }

    final visiting = <int>{};
    final visited = <int>{};
    void visit(int nodeId) {
      if (visiting.contains(nodeId)) {
        _fail(FrameErrorCode.cycle, 'A cycle includes node $nodeId');
      }
      if (!visited.add(nodeId)) {
        return;
      }
      visiting.add(nodeId);
      for (final childId in nodes[nodeId]!.children) {
        visit(childId);
      }
      visiting.remove(nodeId);
    }

    visit(rootId);

    for (final entry in parentCounts.entries) {
      final expected = entry.key == rootId ? 0 : 1;
      if (entry.value != expected) {
        _fail(
          FrameErrorCode.multipleParents,
          'Node ${entry.key} has ${entry.value} parents',
        );
      }
    }
    if (visited.length != nodes.length) {
      _fail(FrameErrorCode.unreachableNode, 'The frame contains orphan nodes');
    }
  }

  UiNode _requiredNode(Map<int, UiNode> nodes, int nodeId) {
    final result = nodes[nodeId];
    if (result == null) {
      _fail(FrameErrorCode.missingNode, 'Node $nodeId does not exist');
    }
    return result;
  }

  void _validateProps(NodeKind kind, UiProps props) {
    final valid = switch (kind) {
      NodeKind.empty || NodeKind.stack => props is EmptyProps,
      NodeKind.environmentBoundary => props is EnvironmentBoundaryProps,
      NodeKind.text => props is TextProps,
      NodeKind.richText => props is RichTextProps,
      NodeKind.icon => props is IconProps,
      NodeKind.image => props is ImageProps,
      NodeKind.row || NodeKind.column => props is LinearProps,
      NodeKind.button => props is ButtonProps,
      NodeKind.padding => props is PaddingProps,
      NodeKind.align => props is AlignProps,
      NodeKind.center => props is CenterProps,
      NodeKind.sizedBox => props is SizedBoxProps,
      NodeKind.constrainedBox => props is ConstrainedBoxProps,
      NodeKind.decoratedBox => props is DecoratedBoxProps,
      NodeKind.clip => props is ClipProps,
      NodeKind.opacity => props is OpacityProps,
      NodeKind.animatedOpacity => props is AnimatedOpacityProps,
      NodeKind.transform => props is TransformProps,
      NodeKind.scrollView => props is ScrollViewProps,
      NodeKind.sliverBox => props is EmptyProps,
      NodeKind.sliverList => props is EmptyProps,
      NodeKind.sliverFill => props is SliverFillProps,
      NodeKind.sliverFixedExtent => props is SliverFixedExtentProps,
      NodeKind.sliverVariedExtent => props is SliverVariedExtentProps,
      NodeKind.sliverPadding => props is SliverPaddingProps,
      NodeKind.sliverAppBar => props is SliverAppBarProps,
      NodeKind.preferredSize => props is PreferredSizeProps,
      NodeKind.gesture => props is GestureProps,
      NodeKind.focusScope => props is FocusScopeProps,
      NodeKind.mouseRegion => props is MouseRegionProps,
      NodeKind.keyboardListener => props is KeyboardListenerProps,
      NodeKind.pressable => props is PressableProps,
      NodeKind.semantics => props is SemanticsProps,
      NodeKind.theme => props is ThemeProps,
      NodeKind.materialScaffold => props is MaterialScaffoldProps,
      NodeKind.materialAppBar => props is MaterialAppBarProps,
      NodeKind.materialElevatedButton ||
      NodeKind.materialTextButton ||
      NodeKind.materialIconButton => props is MaterialButtonProps,
      NodeKind.materialFilledButton ||
      NodeKind.materialFilledTonalButton ||
      NodeKind.materialOutlinedButton => props is MaterialButtonProps,
      NodeKind.materialFloatingActionButton =>
        props is MaterialFloatingActionButtonProps,
      NodeKind.materialNavigationBar => props is MaterialNavigationBarProps,
      NodeKind.materialRadioGroup => props is MaterialRadioGroupProps,
      NodeKind.materialSlider => props is MaterialSliderProps,
      NodeKind.materialRangeSlider => props is MaterialRangeSliderProps,
      NodeKind.materialActionChip ||
      NodeKind.materialFilterChip ||
      NodeKind.materialChoiceChip ||
      NodeKind.materialInputChip => props is MaterialChipProps,
      NodeKind.materialAlertDialog => props is MaterialAlertDialogProps,
      NodeKind.materialCheckbox => props is MaterialCheckboxProps,
      NodeKind.materialSwitch => props is MaterialSwitchProps,
      NodeKind.materialListTile => props is MaterialListTileProps,
      NodeKind.materialDivider => props is MaterialDividerProps,
      NodeKind.materialCard => props is MaterialCardProps,
      NodeKind.materialCircularProgressIndicator =>
        props is MaterialProgressProps,
      NodeKind.cupertinoButton => props is CupertinoButtonProps,
      NodeKind.cupertinoSwitch => props is CupertinoSwitchProps,
      NodeKind.textInput => props is TextInputProps,
      NodeKind.overlay => props is OverlayProps,
      NodeKind.navigator => props is NavigatorProps,
      NodeKind.page => props is PageProps,
      NodeKind.safeArea => props is SafeAreaProps,
      NodeKind.nativeWidget => props is NativeWidgetProps,
    };
    if (!valid) {
      _fail(
        FrameErrorCode.invalidProps,
        'Props ${props.runtimeType} are invalid for $kind',
      );
    }
    final propsError = virtualSliverPropsError(props);
    if (propsError != null) {
      _fail(FrameErrorCode.invalidProps, propsError);
    }
  }

  Never _fail(FrameErrorCode code, String message) {
    throw FrameApplyException(code, message);
  }
}
