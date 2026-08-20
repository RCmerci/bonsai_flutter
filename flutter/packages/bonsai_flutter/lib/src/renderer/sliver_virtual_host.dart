import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderSliver;
import 'package:flutter/widgets.dart';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import 'renderer_event.dart';

/// The visible window of a virtualized sliver expressed in the sliver's own
/// content coordinates.
///
/// A [CustomScrollView] reports a single absolute [ScrollController.offset]
/// for the whole viewport. When a virtualized sliver is preceded by other
/// slivers (e.g. a sticky/collapsing header), that absolute offset must not be
/// divided directly by the item extent: the sliver's leading edge sits
/// [SliverConstraints.scrollOffset] pixels into its own content, and only
/// [SliverGeometry.paintExtent] pixels of it are actually on screen. Reading
/// both from the sliver's [RenderSliver] (after layout) yields the
/// sliver-relative window the OCaml side expects.
({double scrollOffset, double paintExtent})? _sliverViewportMetrics(
  BuildContext context,
) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderSliver) return null;
  final geometry = renderObject.geometry;
  if (geometry == null) return null;
  final paintExtent = geometry.paintExtent;
  if (!paintExtent.isFinite || paintExtent <= 0) return null;
  return (
    scrollOffset: renderObject.constraints.scrollOffset,
    paintExtent: paintExtent,
  );
}

double? _sliverLeadingScrollOffset(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderSliver || renderObject.geometry == null) {
    return null;
  }
  final offset = RenderAbstractViewport.of(
    renderObject,
  ).getOffsetToReveal(renderObject, 0).offset;
  return offset.isFinite ? offset : null;
}

final class _InitialAnchorCandidate {
  const _InitialAnchorCandidate({
    required this.leadingOffset,
    required this.target,
    required this.shouldJump,
  });

  final double leadingOffset;
  final double target;
  final bool shouldJump;
}

/// Arbitrates the one implicit initial anchor owned by a scroll view.
final class InitialSliverAnchorCoordinator {
  InitialSliverAnchorCoordinator(this.controller) {
    controller.addListener(_handleControllerChange);
  }

  final ScrollController controller;
  final Map<Object, _InitialAnchorCandidate> _candidates = {};
  bool _commitScheduled = false;
  bool _committed = false;
  bool _disposed = false;
  bool _externalOffsetEstablished = false;
  Object? _owner;

  void _handleControllerChange() {
    if (!_committed && controller.hasClients && controller.offset != 0) {
      _externalOffsetEstablished = true;
    }
  }

  void register({
    required Object owner,
    required BuildContext context,
    required double localOffset,
    required bool shouldJump,
  }) {
    if (_disposed || _committed || !controller.hasClients) return;
    if (_owner != null && !identical(_owner, owner)) return;
    final leadingOffset = _sliverLeadingScrollOffset(context);
    if (leadingOffset == null) return;
    final position = controller.position;
    _candidates[owner] = _InitialAnchorCandidate(
      leadingOffset: leadingOffset,
      target: (leadingOffset + localOffset).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      shouldJump: shouldJump,
    );
    _scheduleCommit();
  }

  void unregister(Object owner) {
    _candidates.remove(owner);
    if (identical(_owner, owner)) {
      _committed = true;
      _owner = null;
    }
  }

  void _scheduleCommit() {
    if (_commitScheduled) return;
    _commitScheduled = true;
    scheduleMicrotask(() {
      _commitScheduled = false;
      _commit();
    });
  }

  void _commit() {
    if (_disposed || _committed || _candidates.isEmpty) return;
    if (!controller.hasClients ||
        _externalOffsetEstablished ||
        controller.offset != 0) {
      _committed = true;
      _candidates.clear();
      return;
    }
    final earliest = _candidates.values.reduce(
      (left, right) => left.leadingOffset <= right.leadingOffset ? left : right,
    );
    _owner ??= _candidates.entries
        .firstWhere((entry) => identical(entry.value, earliest))
        .key;
    _candidates.clear();
    if (earliest.shouldJump && earliest.target != 0) {
      _committed = true;
      controller.jumpTo(earliest.target);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_handleControllerChange);
    _candidates.clear();
  }
}

/// Binary-search geometry for sparse-extent lists.
///
/// Extracted from the old native_widget/sparse_extent_list.dart and adapted
/// to use the protocol's [SparseExtentOverride] type.
final class SparseExtentGeometry {
  SparseExtentGeometry({
    required this.totalCount,
    required this.defaultItemExtent,
    required this.extentOverrides,
  }) : _prefixDeltas = _buildPrefixDeltas(defaultItemExtent, extentOverrides);

  final int totalCount;
  final double defaultItemExtent;
  final List<SparseExtentOverride> extentOverrides;
  final List<double> _prefixDeltas;

  static List<double> _buildPrefixDeltas(
    double defaultItemExtent,
    List<SparseExtentOverride> overrides,
  ) {
    var sum = 0.0;
    return List<double>.unmodifiable([
      0.0,
      for (final override in overrides)
        sum += override.extent - defaultItemExtent,
    ]);
  }

  double itemExtent(int index) {
    var low = 0;
    var high = extentOverrides.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final candidate = extentOverrides[middle];
      if (candidate.index < index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < extentOverrides.length && extentOverrides[low].index == index
        ? extentOverrides[low].extent
        : defaultItemExtent;
  }

  double leadingOffset(int index) {
    final boundedIndex = index.clamp(0, totalCount);
    var low = 0;
    var high = extentOverrides.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (extentOverrides[middle].index < boundedIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return boundedIndex * defaultItemExtent + _prefixDeltas[low];
  }

  double get totalExtent => leadingOffset(totalCount);

  ({int firstIndex, int lastExclusive}) visibleRange({
    required double offset,
    required double viewportExtent,
  }) {
    final boundedOffset = offset.clamp(0.0, totalExtent);
    final endOffset = (boundedOffset + math.max(0, viewportExtent)).clamp(
      0.0,
      totalExtent,
    );
    return (
      firstIndex: _lastLeadingAtOrBefore(boundedOffset),
      lastExclusive: _firstLeadingAtOrAfter(endOffset),
    );
  }

  int _lastLeadingAtOrBefore(double offset) {
    var low = 0;
    var high = totalCount;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (leadingOffset(middle) <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  int _firstLeadingAtOrAfter(double offset) {
    var low = 0;
    var high = totalCount;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (leadingOffset(middle) < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// Host for [SliverFixedExtentList] virtualization.
///
/// Consumes the shared [ScrollController] from [ScrollViewScope] and emits
/// [visible_range_changed] events (tag 14) as the user scrolls.
final class SliverFixedExtentHost extends StatefulWidget {
  const SliverFixedExtentHost({
    required this.nodeId,
    required this.localRevision,
    required this.props,
    required this.children,
    required this.controller,
    required this.anchorCoordinator,
    required this.binding,
    required this.onEvent,
    super.key,
  });

  final int nodeId;
  final int localRevision;
  final SliverFixedExtentProps props;
  final List<Widget> children;
  final ScrollController controller;
  final InitialSliverAnchorCoordinator anchorCoordinator;
  final EventBinding? binding;
  final RendererEventCallback? onEvent;

  @override
  State<SliverFixedExtentHost> createState() => _SliverFixedExtentHostState();
}

final class _SliverFixedExtentHostState extends State<SliverFixedExtentHost> {
  ({int firstIndex, int lastExclusive})? _lastRange;
  bool _rangeReportScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRangeReport);
    _scheduleInitialAnchor();
  }

  @override
  void didUpdateWidget(SliverFixedExtentHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged) {
      oldWidget.controller.removeListener(_scheduleRangeReport);
      widget.controller.addListener(_scheduleRangeReport);
    }
    final coordinatorChanged = !identical(
      oldWidget.anchorCoordinator,
      widget.anchorCoordinator,
    );
    if (coordinatorChanged) {
      oldWidget.anchorCoordinator.unregister(this);
    }
    if (controllerChanged ||
        coordinatorChanged ||
        oldWidget.props.firstIndex != widget.props.firstIndex) {
      _scheduleInitialAnchor();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisibleRange());
  }

  void _scheduleInitialAnchor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      widget.anchorCoordinator.register(
        owner: this,
        context: context,
        localOffset: widget.props.firstIndex * widget.props.itemExtent,
        shouldJump: widget.props.firstIndex > 0,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRangeReport);
    widget.anchorCoordinator.unregister(this);
    super.dispose();
  }

  /// Coalesces scroll-driven reports into one read of the sliver's geometry
  /// after layout. The scroll controller fires its listeners synchronously,
  /// before the viewport re-lays-out, so reading the [RenderSliver] then would
  /// return stale constraints; deferring to the next post-frame callback reads
  /// the freshly laid-out sliver-relative window.
  void _scheduleRangeReport() {
    if (_rangeReportScheduled || !mounted) return;
    _rangeReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rangeReportScheduled = false;
      if (!mounted) return;
      _reportVisibleRange();
    });
  }

  void _reportVisibleRange() {
    final binding = widget.binding;
    final onEvent = widget.onEvent;
    if (binding == null || onEvent == null) return;
    final viewport = _sliverViewportMetrics(context);
    if (viewport == null) return;
    final itemExtent = widget.props.itemExtent;
    final totalCount = widget.props.totalCount;
    final logicalFirst = (viewport.scrollOffset / itemExtent).floor();
    final logicalLast =
        ((viewport.scrollOffset + viewport.paintExtent) / itemExtent).ceil();
    final range = (
      firstIndex: logicalFirst.clamp(0, totalCount),
      lastExclusive: logicalLast.clamp(0, totalCount),
    );
    if (range == _lastRange) return;
    _lastRange = range;
    onEvent(
      RendererEvent(
        nodeId: widget.nodeId,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: VisibleRangeEventPayload(
          firstIndex: range.firstIndex,
          lastExclusive: range.lastExclusive,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        _scheduleRangeReport();
        return SliverFixedExtentList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final windowIndex = index - widget.props.firstIndex;
              if (windowIndex >= 0 && windowIndex < widget.children.length) {
                return widget.children[windowIndex];
              }
              return const SizedBox.shrink();
            },
            childCount: widget.props.totalCount,
            findChildIndexCallback: (key) {
              for (var i = 0; i < widget.children.length; i += 1) {
                if (widget.children[i].key == key) {
                  return widget.props.firstIndex + i;
                }
              }
              return null;
            },
          ),
          itemExtent: widget.props.itemExtent,
        );
      },
    );
  }
}

/// Host for [SliverVariedExtentList] virtualization with sparse overrides
/// and optional transition animation.
final class SliverVariedExtentHost extends StatefulWidget {
  const SliverVariedExtentHost({
    required this.nodeId,
    required this.localRevision,
    required this.props,
    required this.children,
    required this.controller,
    required this.anchorCoordinator,
    required this.binding,
    required this.onEvent,
    super.key,
  });

  final int nodeId;
  final int localRevision;
  final SliverVariedExtentProps props;
  final List<Widget> children;
  final ScrollController controller;
  final InitialSliverAnchorCoordinator anchorCoordinator;
  final EventBinding? binding;
  final RendererEventCallback? onEvent;

  @override
  State<SliverVariedExtentHost> createState() => _SliverVariedExtentHostState();
}

final class _SliverVariedExtentHostState extends State<SliverVariedExtentHost>
    with SingleTickerProviderStateMixin {
  ({int firstIndex, int lastExclusive})? _lastRange;
  bool _suppressRange = false;
  bool _rangeReportScheduled = false;
  bool _initialAnchorScheduled = false;
  bool _anchorCorrectionScheduled = false;
  late final AnimationController _animation;
  Map<int, double> _extentStarts = const {};
  Map<int, double> _extentTargets = const {};
  late Map<int, double> _overrideExtents;
  ({int index, double viewportOffset})? _anchor;
  bool _animating = false;
  bool _settleAfterAnchorCorrection = false;

  SparseExtentGeometry get _geometry =>
      _geometryFor(widget.props, _overrideExtents);

  @override
  void initState() {
    super.initState();
    _overrideExtents = _overrideByIndex(widget.props);
    _animation = AnimationController(vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
        _scheduleAnchorCorrection();
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !_animating) return;
        setState(() {
          _animating = false;
          _extentStarts = const {};
          _extentTargets = const {};
        });
        _scheduleAnchorCorrection(settled: true);
      });
    widget.controller.addListener(_scheduleRangeReport);
    _scheduleInitialAnchor();
  }

  @override
  void didUpdateWidget(SliverVariedExtentHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged) {
      oldWidget.controller.removeListener(_scheduleRangeReport);
      widget.controller.addListener(_scheduleRangeReport);
    }
    final coordinatorChanged = !identical(
      oldWidget.anchorCoordinator,
      widget.anchorCoordinator,
    );
    if (coordinatorChanged) {
      oldWidget.anchorCoordinator.unregister(this);
    }
    if (controllerChanged ||
        coordinatorChanged ||
        oldWidget.props.firstIndex != widget.props.firstIndex) {
      _scheduleInitialAnchor();
    }
    final oldOverrideExtents = _overrideExtents;
    final newOverrideExtents = _overrideByIndex(widget.props);
    final currentGeometry = _geometryFor(oldWidget.props, oldOverrideExtents);
    final changedIndexes =
        <int>{
              ..._extentStarts.keys,
              ..._extentTargets.keys,
              for (final override in oldWidget.props.extentOverrides)
                override.index,
              for (final override in widget.props.extentOverrides)
                override.index,
            }
            .where((index) {
              final current = _effectiveExtent(
                index,
                oldWidget.props,
                oldOverrideExtents,
              );
              return current !=
                  _targetExtent(index, widget.props, newOverrideExtents);
            })
            .toList(growable: false)
          ..sort();

    if (oldWidget.props.defaultItemExtent != widget.props.defaultItemExtent) {
      _captureAnchor(currentGeometry, changedIndexes, newOverrideExtents);
      _overrideExtents = newOverrideExtents;
      _settleImmediately();
      return;
    }

    if (changedIndexes.isEmpty) {
      _overrideExtents = newOverrideExtents;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportVisibleRange(),
      );
      return;
    }

    _captureAnchor(currentGeometry, changedIndexes, newOverrideExtents);
    final starts = <int, double>{};
    final targets = <int, double>{};
    for (final index in changedIndexes) {
      starts[index] = _effectiveExtent(
        index,
        oldWidget.props,
        oldOverrideExtents,
      );
      targets[index] = _targetExtent(index, widget.props, newOverrideExtents);
    }
    _animation.stop();
    _extentStarts = starts;
    _extentTargets = targets;
    _overrideExtents = newOverrideExtents;

    final transition = widget.props.transition;
    if (transition == null ||
        !transition.enabled ||
        _transitionDuration(changedIndexes, transition) == Duration.zero) {
      _settleImmediately();
      return;
    }

    _animating = true;
    _suppressRange = true;
    _animation
      ..duration = _transitionDuration(changedIndexes, transition)
      ..value = 0
      ..forward();
  }

  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.maybeOf(context)?.accessibleNavigation == true;

  Map<int, double> _overrideByIndex(SliverVariedExtentProps props) => {
    for (final override in props.extentOverrides)
      override.index: override.extent,
  };

  double _targetExtent(
    int index,
    SliverVariedExtentProps props,
    Map<int, double> overrides,
  ) => overrides[index] ?? props.defaultItemExtent;

  double _effectiveExtent(
    int index,
    SliverVariedExtentProps props,
    Map<int, double> overrides,
  ) {
    if (!_animating || !_extentStarts.containsKey(index)) {
      return _targetExtent(index, props, overrides);
    }
    final start = _extentStarts[index]!;
    final target = _extentTargets[index]!;
    final progress = _curveFor(
      index,
      target >= start,
    ).transform(_animation.value);
    return start + (target - start) * progress;
  }

  Curve _curveFor(int index, bool expanding) {
    final transition = widget.props.transition;
    if (transition == null) return Curves.linear;
    return _flutterCurve(
      expanding ? transition.expandCurve : transition.collapseCurve,
    );
  }

  SparseExtentGeometry _geometryFor(
    SliverVariedExtentProps props,
    Map<int, double> overrides,
  ) {
    if (!_animating) {
      return SparseExtentGeometry(
        totalCount: props.totalCount,
        defaultItemExtent: props.defaultItemExtent,
        extentOverrides: props.extentOverrides,
      );
    }
    final indexes = <int>{
      ..._extentStarts.keys,
      ..._extentTargets.keys,
      for (final override in props.extentOverrides) override.index,
    }.toList(growable: false)..sort();
    final animatedOverrides = <SparseExtentOverride>[];
    for (final index in indexes) {
      final extent = _effectiveExtent(index, props, overrides);
      if (extent != props.defaultItemExtent) {
        animatedOverrides.add(
          SparseExtentOverride(index: index, extent: extent),
        );
      }
    }
    return SparseExtentGeometry(
      totalCount: props.totalCount,
      defaultItemExtent: props.defaultItemExtent,
      extentOverrides: animatedOverrides,
    );
  }

  Duration _transitionDuration(
    List<int> indexes,
    SparseExtentTransition transition,
  ) {
    var duration = Duration.zero;
    for (final index in indexes) {
      final candidate = _extentTargets[index]! >= _extentStarts[index]!
          ? Duration(milliseconds: transition.expandDurationMs)
          : Duration(milliseconds: transition.collapseDurationMs);
      if (candidate > duration) duration = candidate;
    }
    return duration;
  }

  void _captureAnchor(
    SparseExtentGeometry geometry,
    List<int> changedIndexes,
    Map<int, double> newOverrideExtents,
  ) {
    if (!widget.controller.hasClients) {
      _anchor = null;
      return;
    }
    final pixels = widget.controller.offset;
    final viewport = _sliverViewportMetrics(context);
    if (viewport == null) {
      _anchor = null;
      return;
    }
    // Pick the anchor from the sliver-relative visible window so a preceding
    // sliver does not shift the chosen index off-screen. The viewport offset
    // stays absolute (controller.offset) so the correction delta in
    // [_scheduleAnchorCorrection] is independent of the sliver's position.
    final visibleRange = geometry.visibleRange(
      offset: viewport.scrollOffset,
      viewportExtent: viewport.paintExtent,
    );
    final preferred = changedIndexes.cast<int?>().firstWhere(
      (index) =>
          index != null &&
          newOverrideExtents.containsKey(index) &&
          index >= visibleRange.firstIndex &&
          index < visibleRange.lastExclusive,
      orElse: () => null,
    );
    final anchor = preferred ?? visibleRange.firstIndex;
    _anchor = (
      index: anchor,
      viewportOffset: geometry.leadingOffset(anchor) - pixels,
    );
  }

  void _settleImmediately() {
    _animation.stop();
    setState(() {
      _animating = false;
      _extentStarts = const {};
      _extentTargets = const {};
      _suppressRange = true;
    });
    _scheduleAnchorCorrection(settled: true);
  }

  void _scheduleInitialAnchor() {
    if (!_initialAnchorScheduled) {
      _initialAnchorScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initialAnchorScheduled = false;
        if (!mounted || !widget.controller.hasClients) return;
        widget.anchorCoordinator.register(
          owner: this,
          context: context,
          localOffset: _geometry.leadingOffset(widget.props.firstIndex),
          shouldJump: widget.props.firstIndex > 0,
        );
      });
    }
  }

  void _scheduleAnchorCorrection({bool settled = false}) {
    _settleAfterAnchorCorrection |= settled;
    if (_anchor == null) {
      if (settled) {
        _finishAnchorCorrection();
      }
      return;
    }
    if (_anchorCorrectionScheduled) return;
    _anchorCorrectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCorrectionScheduled = false;
      if (!mounted || !widget.controller.hasClients) return;
      final anchor = _anchor;
      if (anchor == null) return;
      final target =
          _geometry.leadingOffset(anchor.index) - anchor.viewportOffset;
      final position = widget.controller.position;
      final corrected = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final correction = corrected - widget.controller.position.pixels;
      if (correction.abs() > precisionErrorTolerance) {
        widget.controller.position.correctBy(correction);
        WidgetsBinding.instance.scheduleFrame();
      }
      if (_settleAfterAnchorCorrection) _finishAnchorCorrection();
    });
  }

  void _finishAnchorCorrection() {
    _settleAfterAnchorCorrection = false;
    _anchor = null;
    _suppressRange = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportVisibleRange();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRangeReport);
    widget.anchorCoordinator.unregister(this);
    _animation.dispose();
    super.dispose();
  }

  /// Coalesces scroll-driven reports into one read of the sliver's geometry
  /// after layout. See [_SliverFixedExtentHostState._scheduleRangeReport].
  void _scheduleRangeReport() {
    if (_rangeReportScheduled || !mounted) return;
    _rangeReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rangeReportScheduled = false;
      if (!mounted) return;
      _reportVisibleRange();
    });
  }

  void _reportVisibleRange() {
    final binding = widget.binding;
    final onEvent = widget.onEvent;
    if (_suppressRange || binding == null || onEvent == null) return;
    final viewport = _sliverViewportMetrics(context);
    if (viewport == null) return;
    final range = _geometry.visibleRange(
      offset: viewport.scrollOffset,
      viewportExtent: viewport.paintExtent,
    );
    if (range == _lastRange) return;
    _lastRange = range;
    onEvent(
      RendererEvent(
        nodeId: widget.nodeId,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: VisibleRangeEventPayload(
          firstIndex: range.firstIndex,
          lastExclusive: range.lastExclusive,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_animating && _reduceMotion) {
      _settleImmediately();
    }
    final geometry = _geometry;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        _scheduleRangeReport();
        return SliverVariedExtentList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final windowIndex = index - widget.props.firstIndex;
              if (windowIndex >= 0 && windowIndex < widget.children.length) {
                return widget.children[windowIndex];
              }
              return const SizedBox.shrink();
            },
            childCount: widget.props.totalCount,
            findChildIndexCallback: (key) {
              for (var i = 0; i < widget.children.length; i += 1) {
                if (widget.children[i].key == key) {
                  return widget.props.firstIndex + i;
                }
              }
              return null;
            },
          ),
          itemExtentBuilder: (index, _) => geometry.itemExtent(index),
        );
      },
    );
  }
}

Curve _flutterCurve(SparseExtentCurve curve) => switch (curve) {
  SparseExtentCurve.linear => Curves.linear,
  SparseExtentCurve.easeIn => Curves.easeIn,
  SparseExtentCurve.easeOut => Curves.easeOut,
  SparseExtentCurve.easeInOut => Curves.easeInOut,
  SparseExtentCurve.easeOutCubic => Curves.easeOutCubic,
  SparseExtentCurve.easeInOutCubic => Curves.easeInOutCubic,
};
