import 'package:flutter/widgets.dart';

import '../protocol/frame.dart';
import '../store/node_store.dart';

abstract interface class RendererHostResources {
  Future<void> requestFocus(int nodeId);

  Future<void> scrollTo(
    int nodeId, {
    required double alignment,
    required bool animated,
  });
}

final class TextInputResourceHandle {
  TextInputResourceHandle(TextInputProps props)
    : controller = TextEditingController.fromValue(_editingValue(props.value)),
      focusNode = FocusNode(),
      sessionId = props.sessionId,
      localRevision = props.acceptedLocalRevision,
      documentRevision = props.documentRevision;

  final TextEditingController controller;
  final FocusNode focusNode;
  int sessionId;
  int localRevision;
  int documentRevision;
  bool disposed = false;

  void applyRemote(TextInputProps props) {
    if (disposed) return;
    final force =
        props.updateMode == TextUpdateMode.forceReplace ||
        props.sessionId != sessionId;
    if (force) {
      sessionId = props.sessionId;
      localRevision = props.acceptedLocalRevision;
      documentRevision = props.documentRevision;
      _replaceValue(props.value);
      return;
    }
    if (props.documentRevision < documentRevision) return;
    documentRevision = props.documentRevision;
    if (props.updateMode == TextUpdateMode.ack) {
      return;
    }
    if (props.updateMode == TextUpdateMode.correction &&
        props.acceptedLocalRevision == localRevision) {
      _replaceValue(props.value);
    }
  }

  void _replaceValue(TextEditingStateValue value) {
    final replacement = _editingValue(value);
    if (controller.value != replacement) {
      controller.value = replacement;
    }
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
    focusNode.dispose();
  }
}

final class _NativeResourceEntry {
  _NativeResourceEntry({
    required this.kindId,
    required this.version,
    required this.resource,
    required this.disposeResource,
  });

  final int kindId;
  final int version;
  final Object resource;
  final void Function() disposeResource;
}

final class AnimationResourceHandle {
  AnimationResourceHandle({
    required TickerProvider vsync,
    required double initialValue,
  }) : _vsync = vsync,
       controller = AnimationController(
         value: initialValue,
         lowerBound: 0,
         upperBound: 1,
         vsync: vsync,
       );

  final AnimationController controller;
  TickerProvider _vsync;

  void resync(TickerProvider vsync) {
    if (identical(_vsync, vsync)) return;
    controller.resync(vsync);
    _vsync = vsync;
  }

  void dispose() {
    controller.dispose();
  }
}

final class RendererResourceStore implements RendererHostResources {
  final Map<int, TextInputResourceHandle> _textInputs = {};
  final Map<int, ScrollController> _scrollControllers = {};
  final Map<int, AnimationResourceHandle> _animations = {};
  final Map<int, _NativeResourceEntry> _nativeResources = {};
  int? _runtimeEpoch;
  int? _resourceGeneration;
  int _createdResourceCount = 0;
  int _disposedResourceCount = 0;
  bool _disposed = false;

  int get liveResourceCount =>
      _textInputs.length +
      _scrollControllers.length +
      _animations.length +
      _nativeResources.length;
  int get createdResourceCount => _createdResourceCount;
  int get disposedResourceCount => _disposedResourceCount;
  bool get isDisposed => _disposed;

  TextInputResourceHandle acquireTextInput(int nodeId, TextInputProps props) {
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    if (_runtimeEpoch == null) {
      throw StateError('RendererResourceStore is not synchronized');
    }
    return _textInputs.putIfAbsent(nodeId, () {
      _createdResourceCount += 1;
      return TextInputResourceHandle(props);
    });
  }

  ScrollController acquireScrollController(int nodeId) {
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    if (_runtimeEpoch == null) {
      throw StateError('RendererResourceStore is not synchronized');
    }
    return _scrollControllers.putIfAbsent(nodeId, () {
      _createdResourceCount += 1;
      return ScrollController();
    });
  }

  AnimationResourceHandle acquireAnimation({
    required int nodeId,
    required TickerProvider vsync,
    required double initialValue,
  }) {
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    if (_runtimeEpoch == null) {
      throw StateError('RendererResourceStore is not synchronized');
    }
    final existing = _animations[nodeId];
    if (existing != null) {
      existing.resync(vsync);
      return existing;
    }
    final resource = AnimationResourceHandle(
      vsync: vsync,
      initialValue: initialValue,
    );
    _animations[nodeId] = resource;
    _createdResourceCount += 1;
    return resource;
  }

  @override
  Future<void> requestFocus(int nodeId) async {
    await _waitForResourceAttachment();
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    final resource = _textInputs[nodeId];
    if (resource == null) {
      throw StateError('Node $nodeId has no focus resource');
    }
    resource.focusNode.requestFocus();
  }

  @override
  Future<void> scrollTo(
    int nodeId, {
    required double alignment,
    required bool animated,
  }) async {
    await _waitForResourceAttachment();
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    final controller = _scrollControllers[nodeId];
    if (controller == null) {
      throw StateError('Node $nodeId has no scroll resource');
    }
    if (!controller.hasClients) {
      throw StateError('Scroll node $nodeId is not attached');
    }
    final target =
        controller.position.maxScrollExtent * alignment.clamp(0.0, 1.0);
    if (animated) {
      await controller.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  Resource acquireNativeResource<Resource extends Object>({
    required int nodeId,
    required int kindId,
    required int version,
    required Resource Function() create,
    required void Function(Resource resource) dispose,
  }) {
    if (_disposed) {
      throw StateError('RendererResourceStore has been disposed');
    }
    if (_runtimeEpoch == null) {
      throw StateError('RendererResourceStore is not synchronized');
    }
    final current = _nativeResources[nodeId];
    if (current != null &&
        current.kindId == kindId &&
        current.version == version) {
      return current.resource as Resource;
    }
    if (current != null) {
      _disposeNative(nodeId);
    }
    final resource = create();
    _nativeResources[nodeId] = _NativeResourceEntry(
      kindId: kindId,
      version: version,
      resource: resource,
      disposeResource: () => dispose(resource),
    );
    _createdResourceCount += 1;
    return resource;
  }

  void synchronize(NodeStore store) {
    if (_disposed) return;
    final epoch = store.runtimeEpoch;
    final generation = store.resourceGeneration;
    if ((_runtimeEpoch != null && _runtimeEpoch != epoch) ||
        (_resourceGeneration != null && _resourceGeneration != generation)) {
      _disposeEntries();
    }
    _runtimeEpoch = epoch;
    _resourceGeneration = generation;
    final retained = store.nodes.entries
        .where((entry) => entry.value.kind == NodeKind.textInput)
        .map((entry) => entry.key)
        .toSet();
    for (final nodeId in _textInputs.keys.toList(growable: false)) {
      if (!retained.contains(nodeId)) {
        _disposeTextInput(nodeId);
      }
    }
    final retainedScrollControllers = store.nodes.entries
        .where(
          (entry) =>
              entry.value.kind == NodeKind.scrollView ||
              entry.value.kind == NodeKind.listView,
        )
        .map((entry) => entry.key)
        .toSet();
    for (final nodeId in _scrollControllers.keys.toList(growable: false)) {
      if (!retainedScrollControllers.contains(nodeId)) {
        _disposeScrollController(nodeId);
      }
    }
    final retainedAnimations = store.nodes.entries
        .where((entry) => entry.value.kind == NodeKind.animatedOpacity)
        .map((entry) => entry.key)
        .toSet();
    for (final nodeId in _animations.keys.toList(growable: false)) {
      if (!retainedAnimations.contains(nodeId)) {
        _disposeAnimation(nodeId);
      }
    }
    final retainedNative = <int, NativeWidgetProps>{
      for (final entry in store.nodes.entries)
        if (entry.value.props case final NativeWidgetProps props)
          entry.key: props,
    };
    for (final entry in _nativeResources.entries.toList(growable: false)) {
      final props = retainedNative[entry.key];
      if (props == null ||
          props.kindId != entry.value.kindId ||
          props.version != entry.value.version) {
        _disposeNative(entry.key);
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeEntries();
  }

  void _disposeTextInput(int nodeId) {
    final resource = _textInputs.remove(nodeId);
    if (resource == null) return;
    resource.dispose();
    _disposedResourceCount += 1;
  }

  void _disposeNative(int nodeId) {
    final resource = _nativeResources.remove(nodeId);
    if (resource == null) return;
    resource.disposeResource();
    _disposedResourceCount += 1;
  }

  void _disposeScrollController(int nodeId) {
    final controller = _scrollControllers.remove(nodeId);
    if (controller == null) return;
    controller.dispose();
    _disposedResourceCount += 1;
  }

  void _disposeAnimation(int nodeId) {
    final resource = _animations.remove(nodeId);
    if (resource == null) return;
    resource.dispose();
    _disposedResourceCount += 1;
  }

  void _disposeEntries() {
    for (final nodeId in _textInputs.keys.toList(growable: false)) {
      _disposeTextInput(nodeId);
    }
    for (final nodeId in _nativeResources.keys.toList(growable: false)) {
      _disposeNative(nodeId);
    }
    for (final nodeId in _scrollControllers.keys.toList(growable: false)) {
      _disposeScrollController(nodeId);
    }
    for (final nodeId in _animations.keys.toList(growable: false)) {
      _disposeAnimation(nodeId);
    }
  }

  Future<void> _waitForResourceAttachment() {
    WidgetsBinding.instance.scheduleFrame();
    return WidgetsBinding.instance.endOfFrame;
  }
}

final class RendererResourceScope extends InheritedWidget {
  const RendererResourceScope({
    required this.resources,
    required super.child,
    super.key,
  });

  final RendererResourceStore resources;

  static RendererResourceStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RendererResourceScope>();
    if (scope == null) {
      throw StateError('No RendererResourceScope is available');
    }
    return scope.resources;
  }

  @override
  bool updateShouldNotify(RendererResourceScope oldWidget) =>
      !identical(resources, oldWidget.resources);
}

TextEditingValue _editingValue(TextEditingStateValue value) {
  final composing = value.composing;
  return TextEditingValue(
    text: value.text,
    selection: TextSelection(
      baseOffset: value.selection.startUtf16,
      extentOffset: value.selection.endUtf16,
    ),
    composing: composing == null
        ? TextRange.empty
        : TextRange(start: composing.startUtf16, end: composing.endUtf16),
  );
}
