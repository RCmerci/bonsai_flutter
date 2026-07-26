import 'dart:typed_data';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

import '../protocol/frame.dart';
import 'native_widget_registry.dart';

abstract final class NativeWidgetKind {
  static const int virtualList = 1;
}

abstract final class VirtualListEvent {
  static const int visibleRangeChanged = 1;

  static Uint8List encodeVisibleRange({
    required int firstIndex,
    required int lastExclusive,
  }) {
    if (firstIndex < 0 || lastExclusive < firstIndex) {
      throw ArgumentError('Visible range must be non-negative and ordered');
    }
    final data = ByteData(16)
      ..setUint64(0, firstIndex, Endian.little)
      ..setUint64(8, lastExclusive, Endian.little);
    return data.buffer.asUint8List();
  }

  static ({int firstIndex, int lastExclusive}) decodeVisibleRange(
    List<int> payload,
  ) {
    if (payload.length != 16) {
      throw const FormatException(
        'Visible range payload must be exactly 16 bytes',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(payload));
    final firstIndex = data.getUint64(0, Endian.little);
    final lastExclusive = data.getUint64(8, Endian.little);
    if (lastExclusive < firstIndex) {
      throw const FormatException('Visible range is reversed');
    }
    return (firstIndex: firstIndex, lastExclusive: lastExclusive);
  }
}

final class VirtualListProps {
  const VirtualListProps({
    required this.totalCount,
    required this.firstIndex,
    required this.itemExtent,
    required this.overscan,
    required this.axis,
  });

  final int totalCount;
  final int firstIndex;
  final double itemExtent;
  final int overscan;
  final ScrollAxis axis;

  void validateChildCount(int childCount) {
    if (totalCount < 0 ||
        firstIndex < 0 ||
        firstIndex > totalCount ||
        childCount < 0 ||
        childCount > totalCount - firstIndex) {
      throw ArgumentError('Virtual list window is outside the logical list');
    }
    if (!itemExtent.isFinite || itemExtent <= 0) {
      throw ArgumentError.value(
        itemExtent,
        'itemExtent',
        'must be finite and positive',
      );
    }
    if (overscan < 0 || overscan > 0xffffffff) {
      throw ArgumentError.value(overscan, 'overscan', 'must be a valid u32');
    }
  }

  NativeWidgetProps toNativeWidgetProps() {
    validateChildCount(0);
    final data = ByteData(29)
      ..setUint64(0, totalCount, Endian.little)
      ..setUint64(8, firstIndex, Endian.little)
      ..setFloat64(16, itemExtent, Endian.little)
      ..setUint32(24, overscan, Endian.little)
      ..setUint8(28, axis == ScrollAxis.horizontal ? 0 : 1);
    return NativeWidgetProps(
      kindId: NativeWidgetKind.virtualList,
      version: 1,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics |
          NativeCapability.virtualized,
      payload: data.buffer.asUint8List(),
    );
  }

  static VirtualListProps decode(Uint8List payload) {
    if (payload.length != 29) {
      throw const FormatException(
        'Virtual list props must be exactly 29 bytes',
      );
    }
    final data = ByteData.sublistView(payload);
    final axis = switch (data.getUint8(28)) {
      0 => ScrollAxis.horizontal,
      1 => ScrollAxis.vertical,
      final value => throw FormatException('Invalid virtual list axis $value'),
    };
    final props = VirtualListProps(
      totalCount: data.getUint64(0, Endian.little),
      firstIndex: data.getUint64(8, Endian.little),
      itemExtent: data.getFloat64(16, Endian.little),
      overscan: data.getUint32(24, Endian.little),
      axis: axis,
    );
    props.validateChildCount(0);
    return props;
  }
}

void registerVirtualList(NativeWidgetRegistry registry) {
  registry.register<VirtualListProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.virtualList,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics |
          NativeCapability.virtualized,
      decodeProps: VirtualListProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        final controller = context.resource<ScrollController>(
          create: () => ScrollController(
            initialScrollOffset:
                context.props.firstIndex * context.props.itemExtent,
          ),
          dispose: (controller) => controller.dispose(),
        );
        return _VirtualListHost(
          props: context.props,
          controller: controller,
          emit: context.emit,
          children: context.children,
        );
      },
    ),
  );
}

final class _VirtualListHost extends StatefulWidget {
  const _VirtualListHost({
    required this.props,
    required this.children,
    required this.controller,
    required this.emit,
  });

  final VirtualListProps props;
  final List<Widget> children;
  final ScrollController controller;
  final NativeEventEmitter? emit;

  @override
  State<_VirtualListHost> createState() => _VirtualListHostState();
}

final class _VirtualListHostState extends State<_VirtualListHost> {
  ({int firstIndex, int lastExclusive})? _lastRange;
  double _viewportExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_reportVisibleRange);
  }

  @override
  void didUpdateWidget(_VirtualListHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_reportVisibleRange);
      widget.controller.addListener(_reportVisibleRange);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportVisibleRange());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reportVisibleRange);
    super.dispose();
  }

  void _reportVisibleRange() {
    final emit = widget.emit;
    if (emit == null || _viewportExtent <= 0 || !widget.controller.hasClients) {
      return;
    }
    final offset = widget.controller.offset;
    final logicalFirst = (offset / widget.props.itemExtent).floor();
    final logicalLast = ((offset + _viewportExtent) / widget.props.itemExtent)
        .ceil();
    final windowFirst = widget.props.firstIndex;
    final windowLast = windowFirst + widget.children.length;
    final range = (
      firstIndex: logicalFirst.clamp(windowFirst, windowLast),
      lastExclusive: logicalLast.clamp(windowFirst, windowLast),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewportExtent = widget.props.axis == ScrollAxis.horizontal
          ? constraints.maxWidth
          : constraints.maxHeight;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportVisibleRange(),
      );
      return ListView.builder(
        controller: widget.controller,
        scrollDirection: widget.props.axis == ScrollAxis.horizontal
            ? Axis.horizontal
            : Axis.vertical,
        itemCount: widget.props.totalCount,
        itemExtent: widget.props.itemExtent,
        scrollCacheExtent: ScrollCacheExtent.pixels(
          widget.props.overscan * widget.props.itemExtent,
        ),
        itemBuilder: (context, index) {
          final windowIndex = index - widget.props.firstIndex;
          if (windowIndex >= 0 && windowIndex < widget.children.length) {
            return widget.children[windowIndex];
          }
          return const SizedBox.shrink();
        },
      );
    },
  );
}
