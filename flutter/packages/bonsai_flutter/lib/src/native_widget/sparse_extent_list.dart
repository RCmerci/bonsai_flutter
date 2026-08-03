import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

import '../protocol/frame.dart';
import 'native_widget_registry.dart';
import 'sparse_extent_transition_scope.dart';
import 'virtual_list.dart';

const int _maxSafeInteger = 0x1fffffffffffff;

@immutable
final class ExtentOverride {
  const ExtentOverride({required this.index, required this.extent});

  final int index;
  final double extent;

  @override
  bool operator ==(Object other) =>
      other is ExtentOverride && other.index == index && other.extent == extent;

  @override
  int get hashCode => Object.hash(index, extent);
}

enum SparseExtentTransitionCurve {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  easeOutCubic,
  easeInOutCubic,
}

@immutable
final class SparseExtentTransitionSpec {
  const SparseExtentTransitionSpec({
    required this.expandDuration,
    required this.collapseDuration,
    this.expandCurve = SparseExtentTransitionCurve.easeOutCubic,
    this.collapseCurve = SparseExtentTransitionCurve.easeInOutCubic,
    this.enabled = true,
  });

  final Duration expandDuration;
  final Duration collapseDuration;
  final SparseExtentTransitionCurve expandCurve;
  final SparseExtentTransitionCurve collapseCurve;
  final bool enabled;

  void validate() {
    for (final duration in [expandDuration, collapseDuration]) {
      if (duration.isNegative || duration.inMilliseconds > 0xffffffff) {
        throw ArgumentError.value(
          duration,
          'duration',
          'must fit an unsigned 32-bit millisecond value',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SparseExtentTransitionSpec &&
      other.expandDuration == expandDuration &&
      other.collapseDuration == collapseDuration &&
      other.expandCurve == expandCurve &&
      other.collapseCurve == collapseCurve &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    expandDuration,
    collapseDuration,
    expandCurve,
    collapseCurve,
    enabled,
  );
}

@immutable
final class SparseExtentListProps {
  const SparseExtentListProps({
    required this.totalCount,
    required this.firstIndex,
    required this.defaultItemExtent,
    required this.extentOverrides,
    required this.overscan,
    required this.axis,
    this.transition,
  });

  final int totalCount;
  final int firstIndex;
  final double defaultItemExtent;
  final List<ExtentOverride> extentOverrides;
  final int overscan;
  final ScrollAxis axis;
  final SparseExtentTransitionSpec? transition;

  void validateChildCount(int childCount) {
    if (totalCount < 0 ||
        totalCount > _maxSafeInteger ||
        firstIndex < 0 ||
        firstIndex > totalCount ||
        childCount < 0 ||
        childCount > totalCount - firstIndex) {
      throw ArgumentError(
        'Sparse extent list window is outside the logical list',
      );
    }
    if (!defaultItemExtent.isFinite || defaultItemExtent <= 0) {
      throw ArgumentError.value(
        defaultItemExtent,
        'defaultItemExtent',
        'must be finite and positive',
      );
    }
    if (overscan < 0 || overscan > 0xffffffff) {
      throw ArgumentError.value(overscan, 'overscan', 'must be a valid u32');
    }
    transition?.validate();
    var previous = -1;
    for (final override in extentOverrides) {
      if (override.index < 0 ||
          override.index >= totalCount ||
          override.index > _maxSafeInteger) {
        throw ArgumentError.value(
          override.index,
          'extentOverrides',
          'index is outside the logical list',
        );
      }
      if (override.index <= previous) {
        throw ArgumentError(
          'Sparse extent override indexes must be sorted and unique',
        );
      }
      if (!override.extent.isFinite || override.extent <= 0) {
        throw ArgumentError.value(
          override.extent,
          'extentOverrides',
          'extent must be finite and positive',
        );
      }
      previous = override.index;
    }
  }

  NativeWidgetProps toNativeWidgetProps() {
    validateChildCount(0);
    final transition = this.transition;
    final headerLength = transition == null ? 36 : 48;
    final data = ByteData(headerLength + extentOverrides.length * 16)
      ..setUint64(0, totalCount, Endian.little)
      ..setUint64(8, firstIndex, Endian.little)
      ..setFloat64(16, defaultItemExtent, Endian.little)
      ..setUint32(24, overscan, Endian.little)
      ..setUint8(28, axis == ScrollAxis.horizontal ? 0 : 1)
      ..setUint32(32, extentOverrides.length, Endian.little);
    if (transition != null) {
      data
        ..setUint8(29, 1)
        ..setUint32(36, transition.expandDuration.inMilliseconds, Endian.little)
        ..setUint32(
          40,
          transition.collapseDuration.inMilliseconds,
          Endian.little,
        )
        ..setUint8(44, transition.expandCurve.index)
        ..setUint8(45, transition.collapseCurve.index)
        ..setUint8(46, transition.enabled ? 1 : 0);
    }
    for (var offset = 0; offset < extentOverrides.length; offset += 1) {
      final override = extentOverrides[offset];
      final payloadOffset = headerLength + offset * 16;
      data
        ..setUint64(payloadOffset, override.index, Endian.little)
        ..setFloat64(payloadOffset + 8, override.extent, Endian.little);
    }
    return NativeWidgetProps(
      kindId: NativeWidgetKind.sparseExtentList,
      version: transition == null ? 1 : 2,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics |
          NativeCapability.virtualized,
      payload: data.buffer.asUint8List(),
    );
  }

  static SparseExtentListProps decode(Uint8List payload) {
    if (payload.length < 36) {
      throw const FormatException(
        'Sparse extent list props must contain a 36-byte header',
      );
    }
    final data = ByteData.sublistView(payload);
    final schema = data.getUint8(29);
    if ((schema != 0 && schema != 1) ||
        data.getUint8(30) != 0 ||
        data.getUint8(31) != 0) {
      throw const FormatException(
        'Sparse extent list reserved bytes must be zero',
      );
    }
    final headerLength = schema == 0 ? 36 : 48;
    if (payload.length < headerLength ||
        (schema == 1 && data.getUint8(47) != 0)) {
      throw const FormatException(
        'Sparse extent list transition header is malformed',
      );
    }
    final overrideCount = data.getUint32(32, Endian.little);
    if (payload.length != headerLength + overrideCount * 16) {
      throw const FormatException(
        'Sparse extent list props length does not match override count',
      );
    }
    SparseExtentTransitionSpec? transition;
    if (schema == 1) {
      final enabled = switch (data.getUint8(46)) {
        0 => false,
        1 => true,
        _ => throw const FormatException(
          'Invalid sparse extent transition enablement',
        ),
      };
      SparseExtentTransitionCurve decodeCurve(int offset) {
        final value = data.getUint8(offset);
        if (value >= SparseExtentTransitionCurve.values.length) {
          throw FormatException(
            'Invalid sparse extent transition curve $value',
          );
        }
        return SparseExtentTransitionCurve.values[value];
      }

      transition = SparseExtentTransitionSpec(
        expandDuration: Duration(
          milliseconds: data.getUint32(36, Endian.little),
        ),
        collapseDuration: Duration(
          milliseconds: data.getUint32(40, Endian.little),
        ),
        expandCurve: decodeCurve(44),
        collapseCurve: decodeCurve(45),
        enabled: enabled,
      );
    }
    final axis = switch (data.getUint8(28)) {
      0 => ScrollAxis.horizontal,
      1 => ScrollAxis.vertical,
      final value => throw FormatException(
        'Invalid sparse extent list axis $value',
      ),
    };
    final totalCount = data.getUint64(0, Endian.little);
    final firstIndex = data.getUint64(8, Endian.little);
    if (totalCount > _maxSafeInteger || firstIndex > _maxSafeInteger) {
      throw const FormatException(
        'Sparse extent list index exceeds the safe integer range',
      );
    }
    final overrides = List<ExtentOverride>.generate(overrideCount, (offset) {
      final payloadOffset = headerLength + offset * 16;
      final index = data.getUint64(payloadOffset, Endian.little);
      if (index > _maxSafeInteger) {
        throw const FormatException(
          'Sparse extent override index exceeds the safe integer range',
        );
      }
      return ExtentOverride(
        index: index,
        extent: data.getFloat64(payloadOffset + 8, Endian.little),
      );
    }, growable: false);
    final props = SparseExtentListProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      defaultItemExtent: data.getFloat64(16, Endian.little),
      extentOverrides: overrides,
      overscan: data.getUint32(24, Endian.little),
      axis: axis,
      transition: transition,
    );
    try {
      props.validateChildCount(0);
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
    return props;
  }

  @override
  bool operator ==(Object other) =>
      other is SparseExtentListProps &&
      other.totalCount == totalCount &&
      other.firstIndex == firstIndex &&
      other.defaultItemExtent == defaultItemExtent &&
      listEquals(other.extentOverrides, extentOverrides) &&
      other.overscan == overscan &&
      other.axis == axis &&
      other.transition == transition;

  @override
  int get hashCode => Object.hash(
    totalCount,
    firstIndex,
    defaultItemExtent,
    Object.hashAll(extentOverrides),
    overscan,
    axis,
    transition,
  );
}

@immutable
final class SparseExtentGeometry {
  SparseExtentGeometry({
    required this.totalCount,
    required this.defaultItemExtent,
    required this.extentOverrides,
  }) : _prefixDeltas = _buildPrefixDeltas(defaultItemExtent, extentOverrides);

  final int totalCount;
  final double defaultItemExtent;
  final List<ExtentOverride> extentOverrides;
  final List<double> _prefixDeltas;

  static List<double> _buildPrefixDeltas(
    double defaultItemExtent,
    List<ExtentOverride> overrides,
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

void registerSparseExtentList(NativeWidgetRegistry registry) {
  registry.register<SparseExtentListProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.sparseExtentList,
      minVersion: 1,
      maxVersion: 2,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics |
          NativeCapability.virtualized,
      decodeProps: SparseExtentListProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        final geometry = SparseExtentGeometry(
          totalCount: context.props.totalCount,
          defaultItemExtent: context.props.defaultItemExtent,
          extentOverrides: context.props.extentOverrides,
        );
        final controller = context.resource<ScrollController>(
          create: () => ScrollController(
            initialScrollOffset: geometry.leadingOffset(
              context.props.firstIndex,
            ),
          ),
          dispose: (controller) => controller.dispose(),
        );
        return SparseExtentListHost(
          props: context.props,
          controller: controller,
          emit: context.emit,
          children: context.children,
        );
      },
    ),
  );
}

final class SparseExtentListHost extends StatefulWidget {
  const SparseExtentListHost({
    required this.props,
    required this.children,
    required this.controller,
    required this.emit,
    super.key,
  });

  final SparseExtentListProps props;
  final List<Widget> children;
  final ScrollController controller;
  final NativeEventEmitter? emit;

  static ValueKey<String> itemKey(int logicalIndex) =>
      ValueKey<String>('bonsai-sparse-extent-item-$logicalIndex');

  @override
  State<SparseExtentListHost> createState() => _SparseExtentListHostState();
}

final class _SparseExtentListHostState extends State<SparseExtentListHost>
    with SingleTickerProviderStateMixin {
  ({int firstIndex, int lastExclusive})? _lastRange;
  double _viewportExtent = 0;
  bool _suppressRange = false;
  bool _anchorCorrectionScheduled = false;
  late final AnimationController _animation;
  Map<int, double> _extentStarts = const {};
  Map<int, double> _extentTargets = const {};
  Map<int, double> _surfaceStarts = const {};
  Map<int, double> _surfaceTargets = const {};
  ({int index, double viewportOffset})? _anchor;
  bool _animating = false;

  SparseExtentGeometry get _geometry => _geometryFor(widget.props);

  @override
  void initState() {
    super.initState();
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
          _surfaceStarts = const {};
          _surfaceTargets = const {};
          _anchor = null;
          _suppressRange = false;
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reportVisibleRange(),
        );
      });
    widget.controller.addListener(_reportVisibleRange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animating && _reduceMotion) {
      _settleImmediately();
    }
  }

  @override
  void didUpdateWidget(SparseExtentListHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_reportVisibleRange);
      widget.controller.addListener(_reportVisibleRange);
    }
    final currentGeometry = _geometryFor(oldWidget.props);
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
              final current = _effectiveExtent(index, oldWidget.props);
              return current != _targetExtent(index, widget.props);
            })
            .toList(growable: false)
          ..sort();

    if (changedIndexes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportVisibleRange(),
      );
      return;
    }

    _captureAnchor(currentGeometry, oldWidget.props, changedIndexes);
    final starts = <int, double>{};
    final targets = <int, double>{};
    final surfaceStarts = <int, double>{};
    final surfaceTargets = <int, double>{};
    for (final index in changedIndexes) {
      starts[index] = _effectiveExtent(index, oldWidget.props);
      targets[index] = _targetExtent(index, widget.props);
      surfaceStarts[index] = _effectiveSurfaceProgress(index, oldWidget.props);
      surfaceTargets[index] = _overrideByIndex(widget.props).containsKey(index)
          ? 1
          : 0;
    }
    _animation.stop();
    _extentStarts = starts;
    _extentTargets = targets;
    _surfaceStarts = surfaceStarts;
    _surfaceTargets = surfaceTargets;

    final transition = widget.props.transition;
    if (transition == null ||
        !transition.enabled ||
        _reduceMotion ||
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

  Map<int, double> _overrideByIndex(SparseExtentListProps props) => {
    for (final override in props.extentOverrides)
      override.index: override.extent,
  };

  double _targetExtent(int index, SparseExtentListProps props) =>
      _overrideByIndex(props)[index] ?? props.defaultItemExtent;

  double _effectiveExtent(int index, SparseExtentListProps props) {
    if (!_animating || !_extentStarts.containsKey(index)) {
      return _targetExtent(index, props);
    }
    final start = _extentStarts[index]!;
    final target = _extentTargets[index]!;
    final progress = _curveFor(
      index,
      target >= start,
    ).transform(_animation.value);
    return start + (target - start) * progress;
  }

  double _effectiveSurfaceProgress(int index, SparseExtentListProps props) {
    if (!_animating || !_surfaceStarts.containsKey(index)) {
      return _overrideByIndex(props).containsKey(index) ? 1 : 0;
    }
    final start = _surfaceStarts[index]!;
    final target = _surfaceTargets[index]!;
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

  SparseExtentGeometry _geometryFor(SparseExtentListProps props) {
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
    return SparseExtentGeometry(
      totalCount: props.totalCount,
      defaultItemExtent: props.defaultItemExtent,
      extentOverrides: [
        for (final index in indexes)
          if (_effectiveExtent(index, props) != props.defaultItemExtent)
            ExtentOverride(
              index: index,
              extent: _effectiveExtent(index, props),
            ),
      ],
    );
  }

  Duration _transitionDuration(
    List<int> indexes,
    SparseExtentTransitionSpec transition,
  ) {
    var duration = Duration.zero;
    for (final index in indexes) {
      final candidate = _extentTargets[index]! >= _extentStarts[index]!
          ? transition.expandDuration
          : transition.collapseDuration;
      if (candidate > duration) duration = candidate;
    }
    return duration;
  }

  void _captureAnchor(
    SparseExtentGeometry geometry,
    SparseExtentListProps oldProps,
    List<int> changedIndexes,
  ) {
    if (!widget.controller.hasClients || _viewportExtent <= 0) {
      _anchor = null;
      return;
    }
    final pixels = widget.controller.offset;
    final visibleRange = geometry.visibleRange(
      offset: pixels,
      viewportExtent: _viewportExtent,
    );
    final newOverrides = _overrideByIndex(widget.props);
    final preferred = changedIndexes.cast<int?>().firstWhere(
      (index) =>
          index != null &&
          newOverrides.containsKey(index) &&
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
      _surfaceStarts = const {};
      _surfaceTargets = const {};
      _suppressRange = true;
    });
    _scheduleAnchorCorrection(settled: true);
  }

  void _scheduleAnchorCorrection({bool settled = false}) {
    if (_anchor == null || _anchorCorrectionScheduled) {
      if (settled) {
        _suppressRange = false;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reportVisibleRange(),
        );
      }
      return;
    }
    _anchorCorrectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCorrectionScheduled = false;
      if (!mounted || !widget.controller.hasClients) return;
      final anchor = _anchor;
      if (anchor == null) return;
      final target =
          _geometry.leadingOffset(anchor.index) - anchor.viewportOffset;
      final logicalMax = math.max(0.0, _geometry.totalExtent - _viewportExtent);
      final corrected = target.clamp(0.0, logicalMax);
      final correction = corrected - widget.controller.position.pixels;
      if (correction.abs() > precisionErrorTolerance) {
        widget.controller.position.correctBy(correction);
        WidgetsBinding.instance.scheduleFrame();
      }
      if (settled) {
        _anchor = null;
        _suppressRange = false;
        _reportVisibleRange();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reportVisibleRange);
    _animation.dispose();
    super.dispose();
  }

  void _reportVisibleRange() {
    final emit = widget.emit;
    if (_suppressRange ||
        emit == null ||
        _viewportExtent <= 0 ||
        !widget.controller.hasClients) {
      return;
    }
    final range = _geometry.visibleRange(
      offset: widget.controller.offset,
      viewportExtent: _viewportExtent,
    );
    if (range == _lastRange) return;
    _lastRange = range;
    emit(
      VirtualListEvent.visibleRangeChanged,
      VirtualListEvent.encodeVisibleRange(
        firstIndex: range.firstIndex,
        lastExclusive: range.lastExclusive,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      if (notification is ScrollStartNotification &&
          notification.dragDetails != null) {
        _anchor = null;
      }
      return false;
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        _viewportExtent = widget.props.axis == ScrollAxis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reportVisibleRange(),
        );
        final geometry = _geometry;
        return ListView.builder(
          controller: widget.controller,
          scrollDirection: widget.props.axis == ScrollAxis.horizontal
              ? Axis.horizontal
              : Axis.vertical,
          itemCount: widget.props.totalCount,
          itemExtentBuilder: (index, dimensions) => geometry.itemExtent(index),
          scrollCacheExtent: ScrollCacheExtent.pixels(
            widget.props.overscan * widget.props.defaultItemExtent,
          ),
          findChildIndexCallback: (key) {
            for (var index = 0; index < widget.children.length; index += 1) {
              if (widget.children[index].key == key) {
                return widget.props.firstIndex + index;
              }
            }
            return null;
          },
          itemBuilder: (context, index) {
            final windowIndex = index - widget.props.firstIndex;
            if (windowIndex >= 0 && windowIndex < widget.children.length) {
              final child = widget.children[windowIndex];
              if (widget.props.transition == null) return child;
              final progress = _effectiveSurfaceProgress(index, widget.props);
              final expanded = _overrideByIndex(
                widget.props,
              ).containsKey(index);
              final expandedExtent = math.max(
                widget.props.defaultItemExtent,
                math.max(
                  _extentStarts[index] ?? geometry.itemExtent(index),
                  _extentTargets[index] ?? geometry.itemExtent(index),
                ),
              );
              return SparseExtentTransitionScope(
                key: child.key,
                progress: progress,
                expanded: expanded,
                compactExtent: widget.props.defaultItemExtent,
                expandedExtent: expandedExtent,
                child: SizedBox(
                  key: SparseExtentListHost.itemKey(index),
                  child: child,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    ),
  );
}

Curve _flutterCurve(SparseExtentTransitionCurve curve) => switch (curve) {
  SparseExtentTransitionCurve.linear => Curves.linear,
  SparseExtentTransitionCurve.easeIn => Curves.easeIn,
  SparseExtentTransitionCurve.easeOut => Curves.easeOut,
  SparseExtentTransitionCurve.easeInOut => Curves.easeInOut,
  SparseExtentTransitionCurve.easeOutCubic => Curves.easeOutCubic,
  SparseExtentTransitionCurve.easeInOutCubic => Curves.easeInOutCubic,
};
