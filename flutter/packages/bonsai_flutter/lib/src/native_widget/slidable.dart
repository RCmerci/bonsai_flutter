import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart' as fs;

import 'native_widget_registry.dart';

enum SlidablePaneMotion { behind, drawer, scroll, stretch }

enum SlidableSide { start, end }

final class SlidableDismissibleNativeProps {
  const SlidableDismissibleNativeProps({
    required this.dismissThreshold,
    required this.dismissalDuration,
    required this.resizeDuration,
    required this.closeOnCancel,
  });

  final double dismissThreshold;
  final Duration dismissalDuration;
  final Duration resizeDuration;
  final bool closeOnCancel;
}

final class SlidableActionNativeProps {
  const SlidableActionNativeProps({
    required this.id,
    required this.enabled,
    required this.flex,
    required this.foreground,
    required this.background,
    required this.autoClose,
    required this.borderRadius,
    required this.padding,
    required this.alignment,
  });

  final int id;
  final bool enabled;
  final int flex;
  final Color? foreground;
  final Color background;
  final bool autoClose;
  final double borderRadius;
  final EdgeInsets? padding;
  final AlignmentDirectional? alignment;
}

final class SlidablePaneNativeProps {
  const SlidablePaneNativeProps({
    required this.motion,
    required this.extentRatio,
    required this.dismissible,
    required this.dragDismissible,
    required this.openThreshold,
    required this.closeThreshold,
    required this.actions,
  });

  final SlidablePaneMotion motion;
  final double extentRatio;
  final SlidableDismissibleNativeProps? dismissible;
  final bool dragDismissible;
  final double? openThreshold;
  final double? closeThreshold;
  final List<SlidableActionNativeProps> actions;

  SlidablePaneNativeProps withActions(List<SlidableActionNativeProps> value) =>
      SlidablePaneNativeProps(
        motion: motion,
        extentRatio: extentRatio,
        dismissible: dismissible,
        dragDismissible: dragDismissible,
        openThreshold: openThreshold,
        closeThreshold: closeThreshold,
        actions: value,
      );
}

final class SlidableNativeProps {
  const SlidableNativeProps({
    required this.enabled,
    required this.closeOnScroll,
    required this.direction,
    required this.useTextDirection,
    required this.groupTag,
    required this.startPane,
    required this.endPane,
  });

  static const _headerSize = 16;
  static const _paneSize = 48;
  static const _actionSize = 64;

  final bool enabled;
  final bool closeOnScroll;
  final Axis direction;
  final bool useTextDirection;
  final String? groupTag;
  final SlidablePaneNativeProps? startPane;
  final SlidablePaneNativeProps? endPane;

  int get actionCount =>
      (startPane?.actions.length ?? 0) + (endPane?.actions.length ?? 0);

  void validateChildCount(int childCount) {
    final expected = 1 + actionCount;
    if (childCount != expected) {
      throw FormatException(
        'Slidable must have exactly $expected children, got $childCount',
      );
    }
  }

  static SlidableNativeProps decode(Uint8List payload) {
    if (payload.length < _headerSize) {
      throw const FormatException('Slidable props require a 16-byte header');
    }
    final data = ByteData.sublistView(payload);
    final flags = data.getUint8(0);
    _require(flags & ~0x1f == 0, 'Unknown slidable flags');
    final direction = switch (data.getUint8(1)) {
      0 => Axis.horizontal,
      1 => Axis.vertical,
      final value => throw FormatException('Unknown slidable axis $value'),
    };
    _requireZero(payload, 2, 2, 'Slidable header reserved bytes');
    final startCount = data.getUint16(4, Endian.little);
    final endCount = data.getUint16(6, Endian.little);
    final groupLength = data.getUint32(8, Endian.little);
    _requireZero(payload, 12, 4, 'Slidable header reserved bytes');
    final hasStart = flags & 8 != 0;
    final hasEnd = flags & 16 != 0;
    _require(hasStart || hasEnd, 'Slidable requires at least one pane');
    _require(
      hasStart ? startCount > 0 : startCount == 0,
      'Slidable start pane count is inconsistent',
    );
    _require(
      hasEnd ? endCount > 0 : endCount == 0,
      'Slidable end pane count is inconsistent',
    );
    final paneCount = (hasStart ? 1 : 0) + (hasEnd ? 1 : 0);
    final exactLength =
        _headerSize +
        paneCount * _paneSize +
        (startCount + endCount) * _actionSize +
        groupLength;
    _require(
      payload.length == exactLength,
      'Slidable props must be exactly $exactLength bytes',
    );

    var offset = _headerSize;
    SlidablePaneNativeProps? decodePaneIfPresent(bool present) {
      if (!present) return null;
      final pane = _decodePane(payload, data, offset);
      offset += _paneSize;
      return pane;
    }

    var startPane = decodePaneIfPresent(hasStart);
    var endPane = decodePaneIfPresent(hasEnd);

    List<SlidableActionNativeProps> decodeActions(int count) => [
      for (var index = 0; index < count; index++)
        _decodeAction(payload, data, offset + index * _actionSize),
    ];

    final startActions = decodeActions(startCount);
    offset += startCount * _actionSize;
    final endActions = decodeActions(endCount);
    offset += endCount * _actionSize;
    final ids = <int>{};
    for (final action in [...startActions, ...endActions]) {
      _require(ids.add(action.id), 'Duplicate slidable action ID ${action.id}');
    }
    startPane = startPane?.withActions(startActions);
    endPane = endPane?.withActions(endActions);
    final groupTag = groupLength == 0
        ? null
        : utf8.decode(
            payload.sublist(offset, offset + groupLength),
            allowMalformed: false,
          );
    return SlidableNativeProps(
      enabled: flags & 1 != 0,
      closeOnScroll: flags & 2 != 0,
      direction: direction,
      useTextDirection: flags & 4 != 0,
      groupTag: groupTag,
      startPane: startPane,
      endPane: endPane,
    );
  }
}

final class SlidableAutoCloseProps {
  const SlidableAutoCloseProps({
    required this.closeWhenOpened,
    required this.closeWhenTapped,
  });

  final bool closeWhenOpened;
  final bool closeWhenTapped;

  static SlidableAutoCloseProps decode(Uint8List payload) {
    _require(
      payload.length == 4,
      'Slidable auto-close props must contain exactly four bytes',
    );
    final flags = payload[0];
    _require(flags & ~3 == 0, 'Unknown slidable auto-close flags');
    _requireZero(payload, 1, 3, 'Slidable auto-close reserved bytes');
    return SlidableAutoCloseProps(
      closeWhenOpened: flags & 1 != 0,
      closeWhenTapped: flags & 2 != 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlidableAutoCloseProps &&
      closeWhenOpened == other.closeWhenOpened &&
      closeWhenTapped == other.closeWhenTapped;

  @override
  int get hashCode => Object.hash(closeWhenOpened, closeWhenTapped);
}

SlidablePaneNativeProps _decodePane(
  Uint8List payload,
  ByteData data,
  int offset,
) {
  final motion = switch (data.getUint8(offset)) {
    0 => SlidablePaneMotion.behind,
    1 => SlidablePaneMotion.drawer,
    2 => SlidablePaneMotion.scroll,
    3 => SlidablePaneMotion.stretch,
    final value => throw FormatException('Unknown slidable pane motion $value'),
  };
  final flags = data.getUint8(offset + 1);
  _require(flags & ~0x1f == 0, 'Unknown slidable pane flags');
  _require(data.getUint8(offset + 2) == 0, 'Unknown slidable dismiss motion');
  _requireZero(payload, offset + 3, 5, 'Slidable pane reserved bytes');
  final hasDismissible = flags & 2 != 0;
  final hasOpenThreshold = flags & 4 != 0;
  final hasCloseThreshold = flags & 8 != 0;
  final closeOnCancel = flags & 16 != 0;
  _require(
    hasDismissible || !closeOnCancel,
    'closeOnCancel requires a dismissible pane',
  );
  final extentRatio = data.getFloat64(offset + 8, Endian.little);
  final openValue = data.getFloat64(offset + 16, Endian.little);
  final closeValue = data.getFloat64(offset + 24, Endian.little);
  final dismissValue = data.getFloat64(offset + 32, Endian.little);
  final dismissalMs = data.getUint32(offset + 40, Endian.little);
  final resizeMs = data.getUint32(offset + 44, Endian.little);
  _require(
    extentRatio.isFinite && extentRatio > 0 && extentRatio <= 1,
    'Invalid slidable pane extent ratio',
  );
  final openThreshold = _decodeThreshold(hasOpenThreshold, openValue, 'open');
  final closeThreshold = _decodeThreshold(
    hasCloseThreshold,
    closeValue,
    'close',
  );
  final dismissible = hasDismissible
      ? SlidableDismissibleNativeProps(
          dismissThreshold: _validatedThreshold(dismissValue, 'dismiss'),
          dismissalDuration: Duration(milliseconds: dismissalMs),
          resizeDuration: Duration(milliseconds: resizeMs),
          closeOnCancel: closeOnCancel,
        )
      : null;
  if (!hasDismissible) {
    _require(
      dismissValue == 0 && dismissalMs == 0 && resizeMs == 0,
      'Absent slidable dismiss fields must be zero',
    );
  }
  return SlidablePaneNativeProps(
    motion: motion,
    extentRatio: extentRatio,
    dismissible: dismissible,
    dragDismissible: flags & 1 != 0,
    openThreshold: openThreshold,
    closeThreshold: closeThreshold,
    actions: const [],
  );
}

SlidableActionNativeProps _decodeAction(
  Uint8List payload,
  ByteData data,
  int offset,
) {
  final id = data.getUint32(offset, Endian.little);
  _require(id > 0, 'Slidable action ID must be positive');
  final flags = data.getUint8(offset + 12);
  _require(flags & ~0x1f == 0, 'Unknown slidable action flags');
  _requireZero(payload, offset + 14, 2, 'Slidable action reserved bytes');
  final flex = data.getUint32(offset + 16, Endian.little);
  _require(flex > 0, 'Slidable action flex must be positive');
  _requireZero(payload, offset + 20, 4, 'Slidable action reserved bytes');
  final radius = data.getFloat64(offset + 24, Endian.little);
  _require(
    radius.isFinite && radius >= 0,
    'Invalid slidable action border radius',
  );
  final paddingValues = [
    data.getFloat64(offset + 32, Endian.little),
    data.getFloat64(offset + 40, Endian.little),
    data.getFloat64(offset + 48, Endian.little),
    data.getFloat64(offset + 56, Endian.little),
  ];
  final hasPadding = flags & 8 != 0;
  final padding = hasPadding
      ? EdgeInsets.fromLTRB(
          paddingValues[0],
          paddingValues[1],
          paddingValues[2],
          paddingValues[3],
        )
      : null;
  if (hasPadding) {
    _require(
      paddingValues.every((value) => value.isFinite && value >= 0),
      'Invalid slidable action padding',
    );
  } else {
    _require(
      paddingValues.every((value) => value == 0),
      'Absent slidable action padding must be zero',
    );
  }
  final alignmentIndex = data.getUint8(offset + 13);
  final hasAlignment = flags & 16 != 0;
  final alignment = hasAlignment ? _decodeAlignment(alignmentIndex) : null;
  if (!hasAlignment) {
    _require(
      alignmentIndex == 0,
      'Absent slidable action alignment must be zero',
    );
  }
  final foregroundValue = data.getUint32(offset + 8, Endian.little);
  final hasForeground = flags & 4 != 0;
  if (!hasForeground) {
    _require(
      foregroundValue == 0,
      'Absent slidable action foreground must be zero',
    );
  }
  return SlidableActionNativeProps(
    id: id,
    enabled: flags & 1 != 0,
    flex: flex,
    foreground: hasForeground ? Color(foregroundValue) : null,
    background: Color(data.getUint32(offset + 4, Endian.little)),
    autoClose: flags & 2 != 0,
    borderRadius: radius,
    padding: padding,
    alignment: alignment,
  );
}

double? _decodeThreshold(bool present, double value, String label) {
  if (!present) {
    _require(value == 0, 'Absent slidable $label threshold must be zero');
    return null;
  }
  return _validatedThreshold(value, label);
}

double _validatedThreshold(double value, String label) {
  _require(
    value.isFinite && value > 0 && value < 1,
    'Invalid slidable $label threshold',
  );
  return value;
}

AlignmentDirectional _decodeAlignment(int value) => switch (value) {
  0 => AlignmentDirectional.topStart,
  1 => AlignmentDirectional.topCenter,
  2 => AlignmentDirectional.topEnd,
  3 => AlignmentDirectional.centerStart,
  4 => AlignmentDirectional.center,
  5 => AlignmentDirectional.centerEnd,
  6 => AlignmentDirectional.bottomStart,
  7 => AlignmentDirectional.bottomCenter,
  8 => AlignmentDirectional.bottomEnd,
  _ => throw FormatException('Unknown slidable action alignment $value'),
};

void registerSlidable(NativeWidgetRegistry registry) {
  registry.register<SlidableNativeProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.slidable,
      minVersion: 3,
      maxVersion: 3,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics,
      decodeProps: SlidableNativeProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        var childOffset = 1;
        List<Widget> takeChildren(int count) {
          final result = context.children.sublist(
            childOffset,
            childOffset + count,
          );
          childOffset += count;
          return result;
        }

        final startChildren = takeChildren(
          context.props.startPane?.actions.length ?? 0,
        );
        final endChildren = takeChildren(
          context.props.endPane?.actions.length ?? 0,
        );
        return _SlidableHost(
          nodeId: context.node.id,
          props: context.props,
          emit: context.emit,
          content: context.children.first,
          startChildren: startChildren,
          endChildren: endChildren,
        );
      },
    ),
  );
}

void registerSlidableAutoCloseBehavior(NativeWidgetRegistry registry) {
  registry.register<SlidableAutoCloseProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.slidableAutoCloseBehavior,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits: NativeCapability.stateful,
      decodeProps: SlidableAutoCloseProps.decode,
      factory: (context) {
        _require(
          context.children.length == 1,
          'Slidable auto-close behavior must have exactly one child',
        );
        return fs.SlidableAutoCloseBehavior(
          closeWhenOpened: context.props.closeWhenOpened,
          closeWhenTapped: context.props.closeWhenTapped,
          child: context.children.single,
        );
      },
    ),
  );
}

final class _SlidableHost extends StatefulWidget {
  const _SlidableHost({
    required this.nodeId,
    required this.props,
    required this.emit,
    required this.content,
    required this.startChildren,
    required this.endChildren,
  });

  final int nodeId;
  final SlidableNativeProps props;
  final NativeEventEmitter? emit;
  final Widget content;
  final List<Widget> startChildren;
  final List<Widget> endChildren;

  @override
  State<_SlidableHost> createState() => _SlidableHostState();
}

final class _SlidableHostState extends State<_SlidableHost> {
  void _emitAction(int id) {
    if (!mounted) return;
    final payload = Uint8List(4);
    ByteData.sublistView(payload).setUint32(0, id, Endian.little);
    widget.emit?.call(1, payload);
  }

  void _emitDismissed(SlidableSide side) {
    if (!mounted) return;
    widget.emit?.call(
      2,
      Uint8List.fromList([side == SlidableSide.start ? 0 : 1]),
    );
  }

  fs.ActionPane? _buildPane(
    SlidablePaneNativeProps? pane,
    List<Widget> children,
    SlidableSide side,
  ) {
    if (pane == null) return null;
    return fs.ActionPane(
      extentRatio: pane.extentRatio,
      motion: switch (pane.motion) {
        SlidablePaneMotion.behind => const fs.BehindMotion(),
        SlidablePaneMotion.drawer => const fs.DrawerMotion(),
        SlidablePaneMotion.scroll => const fs.ScrollMotion(),
        SlidablePaneMotion.stretch => const fs.StretchMotion(),
      },
      dismissible: pane.dismissible == null
          ? null
          : fs.DismissiblePane(
              dismissThreshold: pane.dismissible!.dismissThreshold,
              dismissalDuration: pane.dismissible!.dismissalDuration,
              resizeDuration: pane.dismissible!.resizeDuration,
              closeOnCancel: pane.dismissible!.closeOnCancel,
              motion: const fs.InversedDrawerMotion(),
              onDismissed: () => _emitDismissed(side),
            ),
      dragDismissible: pane.dragDismissible,
      openThreshold: pane.openThreshold,
      closeThreshold: pane.closeThreshold,
      children: [
        for (var index = 0; index < pane.actions.length; index++)
          fs.CustomSlidableAction(
            flex: pane.actions[index].flex,
            backgroundColor: pane.actions[index].background,
            foregroundColor: pane.actions[index].foreground,
            autoClose: pane.actions[index].autoClose,
            borderRadius: BorderRadius.circular(
              pane.actions[index].borderRadius,
            ),
            padding: pane.actions[index].padding,
            alignment: pane.actions[index].alignment?.resolve(
              Directionality.of(context),
            ),
            onPressed: pane.actions[index].enabled
                ? (_) => _emitAction(pane.actions[index].id)
                : null,
            child: children[index],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => fs.Slidable(
    key: ValueKey<int>(widget.nodeId),
    groupTag: widget.props.groupTag,
    enabled: widget.props.enabled,
    closeOnScroll: widget.props.closeOnScroll,
    direction: widget.props.direction,
    useTextDirection: widget.props.useTextDirection,
    startActionPane: _buildPane(
      widget.props.startPane,
      widget.startChildren,
      SlidableSide.start,
    ),
    endActionPane: _buildPane(
      widget.props.endPane,
      widget.endChildren,
      SlidableSide.end,
    ),
    child: widget.content,
  );
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

void _requireZero(Uint8List payload, int offset, int length, String message) {
  for (var index = offset; index < offset + length; index++) {
    _require(payload[index] == 0, message);
  }
}
