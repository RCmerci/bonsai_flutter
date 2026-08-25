import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../protocol/frame.dart';
import '../renderer/renderer_resource_store.dart';
import 'message_composer.dart';
import 'message_composer_surface_scope.dart';
import 'native_widget_registry.dart';

@immutable
final class ExpandableMessageComposerProps {
  const ExpandableMessageComposerProps({
    required this.enabled,
    required this.fabLabel,
    required this.fabTooltip,
    required this.animationDurationMilliseconds,
    required this.animationCurve,
    required this.maxLines,
    required this.hintText,
    required this.buttons,
  });

  static const _headerLength = 24;
  static const _buttonHeaderLength = 12;

  final bool enabled;
  final String fabLabel;
  final String fabTooltip;
  final int animationDurationMilliseconds;
  final AnimationCurveValue animationCurve;
  final int maxLines;
  final String hintText;
  final List<MessageComposerButtonProps> buttons;

  Uint8List encode() {
    _validate();
    final label = _encodeUtf8(fabLabel, 'fabLabel');
    final fabTooltipBytes = _encodeUtf8(fabTooltip, 'fabTooltip');
    final hint = _encodeUtf8(hintText, 'hintText');
    final buttonTooltips = [
      for (final button in buttons)
        _encodeUtf8(button.tooltip, 'button.tooltip'),
    ];
    final length =
        _headerLength +
        label.length +
        fabTooltipBytes.length +
        hint.length +
        buttons.length * _buttonHeaderLength +
        buttonTooltips.fold<int>(0, (sum, bytes) => sum + bytes.length);
    final payload = Uint8List(length);
    final data = ByteData.sublistView(payload);
    data
      ..setUint8(0, enabled ? 1 : 0)
      ..setUint8(1, animationCurve.index)
      ..setUint16(2, animationDurationMilliseconds, Endian.little)
      ..setUint16(4, maxLines, Endian.little)
      ..setUint16(6, buttons.length, Endian.little)
      ..setUint32(8, label.length, Endian.little)
      ..setUint32(12, fabTooltipBytes.length, Endian.little)
      ..setUint32(16, hint.length, Endian.little);
    var offset = _headerLength;
    payload.setRange(offset, offset + label.length, label);
    offset += label.length;
    payload.setRange(offset, offset + fabTooltipBytes.length, fabTooltipBytes);
    offset += fabTooltipBytes.length;
    payload.setRange(offset, offset + hint.length, hint);
    offset += hint.length;
    for (var index = 0; index < buttons.length; index += 1) {
      final button = buttons[index];
      final tooltip = buttonTooltips[index];
      data
        ..setUint32(offset, button.id, Endian.little)
        ..setUint8(offset + 4, button.position.index)
        ..setUint8(offset + 5, button.visibility.index)
        ..setUint8(offset + 6, button.style.index)
        ..setUint8(offset + 7, button.enabled ? 1 : 0)
        ..setUint32(offset + 8, tooltip.length, Endian.little);
      offset += _buttonHeaderLength;
      payload.setRange(offset, offset + tooltip.length, tooltip);
      offset += tooltip.length;
    }
    return payload;
  }

  NativeWidgetProps toNativeWidgetProps() => NativeWidgetProps(
    kindId: NativeWidgetKind.expandableMessageComposer,
    version: 1,
    capabilityBits: NativeCapability.stateful | NativeCapability.semantics,
    payload: encode(),
  );

  static ExpandableMessageComposerProps decode(Uint8List payload) {
    if (payload.length < _headerLength) {
      throw const FormatException(
        'Expandable message composer props require a 24-byte header',
      );
    }
    final data = ByteData.sublistView(payload);
    final flags = data.getUint8(0);
    if (flags & ~1 != 0) {
      throw FormatException(
        'Unknown expandable message composer flags 0x${flags.toRadixString(16)}',
      );
    }
    final curve = _enumValue(
      AnimationCurveValue.values,
      data.getUint8(1),
      'animation curve',
    );
    final duration = data.getUint16(2, Endian.little);
    final maxLines = data.getUint16(4, Endian.little);
    if (maxLines == 0) {
      throw const FormatException(
        'Expandable message composer max lines must be positive',
      );
    }
    final buttonCount = data.getUint16(6, Endian.little);
    if (buttonCount > 0xfffe) {
      throw const FormatException(
        'Expandable message composer button count exceeds child bound',
      );
    }
    if (data.getUint32(20, Endian.little) != 0) {
      throw const FormatException(
        'Expandable message composer reserved bytes must be zero',
      );
    }
    var offset = _headerLength;
    final labelResult = _decodeString(
      payload,
      offset,
      data.getUint32(8, Endian.little),
      'FAB label',
    );
    final fabLabel = labelResult.$1;
    offset = labelResult.$2;
    if (fabLabel.isEmpty) {
      throw const FormatException('Expandable FAB label must not be empty');
    }
    final tooltipResult = _decodeString(
      payload,
      offset,
      data.getUint32(12, Endian.little),
      'FAB tooltip',
    );
    final fabTooltip = tooltipResult.$1;
    offset = tooltipResult.$2;
    if (fabTooltip.isEmpty) {
      throw const FormatException('Expandable FAB tooltip must not be empty');
    }
    final hintResult = _decodeString(
      payload,
      offset,
      data.getUint32(16, Endian.little),
      'hint',
    );
    final hintText = hintResult.$1;
    offset = hintResult.$2;
    final buttons = <MessageComposerButtonProps>[];
    final ids = <int>{};
    for (var index = 0; index < buttonCount; index += 1) {
      if (offset + _buttonHeaderLength > payload.length) {
        throw const FormatException(
          'Expandable message composer button header exceeds payload',
        );
      }
      final id = data.getUint32(offset, Endian.little);
      if (id == 0 || !ids.add(id)) {
        throw const FormatException(
          'Expandable message composer button IDs must be positive and unique',
        );
      }
      final position = _enumValue(
        MessageComposerButtonPosition.values,
        data.getUint8(offset + 4),
        'button position',
      );
      final visibility = _enumValue(
        MessageComposerButtonVisibility.values,
        data.getUint8(offset + 5),
        'button visibility',
      );
      final style = _enumValue(
        MessageComposerButtonStyle.values,
        data.getUint8(offset + 6),
        'button style',
      );
      final buttonFlags = data.getUint8(offset + 7);
      if (buttonFlags & ~1 != 0) {
        throw FormatException(
          'Unknown expandable message composer button flags 0x${buttonFlags.toRadixString(16)}',
        );
      }
      final tooltipLength = data.getUint32(offset + 8, Endian.little);
      offset += _buttonHeaderLength;
      final tooltip = _decodeString(
        payload,
        offset,
        tooltipLength,
        'button tooltip',
      );
      if (tooltip.$1.isEmpty) {
        throw const FormatException(
          'Expandable message composer button tooltip must not be empty',
        );
      }
      buttons.add(
        MessageComposerButtonProps(
          id: id,
          tooltip: tooltip.$1,
          position: position,
          visibility: visibility,
          style: style,
          enabled: buttonFlags & 1 != 0,
        ),
      );
      offset = tooltip.$2;
    }
    if (offset != payload.length) {
      throw const FormatException(
        'Expandable message composer props contain extra bytes',
      );
    }
    return ExpandableMessageComposerProps(
      enabled: flags & 1 != 0,
      fabLabel: fabLabel,
      fabTooltip: fabTooltip,
      animationDurationMilliseconds: duration,
      animationCurve: curve,
      maxLines: maxLines,
      hintText: hintText,
      buttons: List.unmodifiable(buttons),
    );
  }

  void _validate() {
    if (fabLabel.isEmpty) {
      throw ArgumentError.value(fabLabel, 'fabLabel', 'must not be empty');
    }
    if (fabTooltip.isEmpty) {
      throw ArgumentError.value(fabTooltip, 'fabTooltip', 'must not be empty');
    }
    if (animationDurationMilliseconds < 0 ||
        animationDurationMilliseconds > 0xffff) {
      throw ArgumentError.value(
        animationDurationMilliseconds,
        'animationDurationMilliseconds',
        'must be in 0..65535',
      );
    }
    if (maxLines <= 0 || maxLines > 0xffff) {
      throw ArgumentError.value(maxLines, 'maxLines', 'must be in 1..65535');
    }
    if (buttons.length > 0xfffe) {
      throw ArgumentError.value(
        buttons.length,
        'buttons',
        'must contain at most 65534 entries',
      );
    }
    if (buttons.length > 0xfffe) {
      throw ArgumentError.value(
        buttons.length,
        'buttons',
        'must contain at most 65534 entries',
      );
    }
    _encodeUtf8(fabLabel, 'fabLabel');
    _encodeUtf8(fabTooltip, 'fabTooltip');
    _encodeUtf8(hintText, 'hintText');
    final ids = <int>{};
    for (final button in buttons) {
      if (button.id <= 0 || button.id > 0xffffffff || !ids.add(button.id)) {
        throw ArgumentError.value(
          button.id,
          'button.id',
          'must be positive and unique',
        );
      }
      if (button.tooltip.isEmpty) {
        throw ArgumentError.value(
          button.tooltip,
          'button.tooltip',
          'must not be empty',
        );
      }
      _encodeUtf8(button.tooltip, 'button.tooltip');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ExpandableMessageComposerProps &&
      other.enabled == enabled &&
      other.fabLabel == fabLabel &&
      other.fabTooltip == fabTooltip &&
      other.animationDurationMilliseconds == animationDurationMilliseconds &&
      other.animationCurve == animationCurve &&
      other.maxLines == maxLines &&
      other.hintText == hintText &&
      listEquals(other.buttons, buttons);

  @override
  int get hashCode => Object.hash(
    enabled,
    fabLabel,
    fabTooltip,
    animationDurationMilliseconds,
    animationCurve,
    maxLines,
    hintText,
    Object.hashAll(buttons),
  );
}

abstract final class ExpandableMessageComposerEvent {
  static const int textChanged = 1;
  static const int buttonPressed = 2;

  static Uint8List encodeTextChanged(String text) =>
      Uint8List.fromList(_encodeUtf8(text, 'text'));

  static Uint8List encodeButtonPressed(int buttonId, String text) {
    if (buttonId <= 0 || buttonId > 0xffffffff) {
      throw ArgumentError.value(buttonId, 'buttonId', 'must be positive');
    }
    final encoded = _encodeUtf8(text, 'text');
    final payload = Uint8List(4 + encoded.length);
    ByteData.sublistView(payload).setUint32(0, buttonId, Endian.little);
    payload.setRange(4, payload.length, encoded);
    return payload;
  }
}

void registerExpandableMessageComposer(NativeWidgetRegistry registry) {
  registry.register<ExpandableMessageComposerProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.expandableMessageComposer,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits: NativeCapability.stateful | NativeCapability.semantics,
      decodeProps: ExpandableMessageComposerProps.decode,
      factory: (context) {
        final expectedChildren = context.props.buttons.length + 1;
        if (context.children.length != expectedChildren) {
          throw FormatException(
            'Expandable message composer requires exactly '
            '$expectedChildren children: FAB icon followed by button children',
          );
        }
        return ExpandableMessageComposer(
          enabled: context.props.enabled,
          fabLabel: context.props.fabLabel,
          fabTooltip: context.props.fabTooltip,
          fabIcon: context.children.first,
          animationDuration: Duration(
            milliseconds: context.props.animationDurationMilliseconds,
          ),
          animationCurve: _curve(context.props.animationCurve),
          maxLines: context.props.maxLines,
          hintText: context.props.hintText,
          buttons: List.generate(context.props.buttons.length, (index) {
            final props = context.props.buttons[index];
            return MessageComposerButton(
              id: props.id,
              tooltip: props.tooltip,
              position: props.position,
              visibility: props.visibility,
              style: props.style,
              enabled: props.enabled,
              child: context.children[index + 1],
            );
          }),
          onChanged: context.emit == null
              ? null
              : (text) => context.emit!(
                  ExpandableMessageComposerEvent.textChanged,
                  ExpandableMessageComposerEvent.encodeTextChanged(text),
                ),
          onButtonPressed: context.emit == null
              ? null
              : (buttonId, text) => context.emit!(
                  ExpandableMessageComposerEvent.buttonPressed,
                  ExpandableMessageComposerEvent.encodeButtonPressed(
                    buttonId,
                    text,
                  ),
                ),
        );
      },
    ),
  );
}

/// An extended FAB for [Scaffold.floatingActionButton] that presents a modal
/// message composer.
final class ExpandableMessageComposer extends StatefulWidget {
  ExpandableMessageComposer({
    required this.fabLabel,
    required this.fabTooltip,
    required this.fabIcon,
    required this.buttons,
    this.enabled = true,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeOut,
    this.maxLines = 5,
    this.hintText = 'Ask anything',
    this.onChanged,
    this.onButtonPressed,
    super.key,
  }) {
    if (fabLabel.isEmpty) {
      throw ArgumentError.value(fabLabel, 'fabLabel', 'must not be empty');
    }
    if (fabTooltip.isEmpty) {
      throw ArgumentError.value(fabTooltip, 'fabTooltip', 'must not be empty');
    }
    if (animationDuration.isNegative ||
        animationDuration > const Duration(milliseconds: 65535)) {
      throw ArgumentError.value(
        animationDuration,
        'animationDuration',
        'must be in 0..65535 milliseconds',
      );
    }
    if (maxLines <= 0 || maxLines > 0xffff) {
      throw ArgumentError.value(maxLines, 'maxLines', 'must be in 1..65535');
    }
    _encodeUtf8(fabLabel, 'fabLabel');
    _encodeUtf8(fabTooltip, 'fabTooltip');
    _encodeUtf8(hintText, 'hintText');
    final buttonIds = <int>{};
    for (final button in buttons) {
      if (button.id <= 0 ||
          button.id > 0xffffffff ||
          !buttonIds.add(button.id)) {
        throw ArgumentError.value(
          button.id,
          'button.id',
          'must be positive and unique',
        );
      }
      if (button.tooltip.isEmpty) {
        throw ArgumentError.value(
          button.tooltip,
          'button.tooltip',
          'must not be empty',
        );
      }
      _encodeUtf8(button.tooltip, 'button.tooltip');
    }
  }

  final bool enabled;
  final String fabLabel;
  final String fabTooltip;
  final Widget fabIcon;
  final Duration animationDuration;
  final Curve animationCurve;
  final int maxLines;
  final String hintText;
  final List<MessageComposerButton> buttons;
  final ValueChanged<String>? onChanged;
  final MessageComposerButtonCallback? onButtonPressed;

  @override
  State<ExpandableMessageComposer> createState() =>
      _ExpandableMessageComposerState();
}

final class _ExpandableMessageComposerState
    extends State<ExpandableMessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final ValueNotifier<ExpandableMessageComposer> _sheetConfiguration;
  ModalBottomSheetRoute<void>? _sheetRoute;
  int _routeGeneration = 0;
  int _configurationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _sheetConfiguration = ValueNotifier(widget);
  }

  @override
  void didUpdateWidget(ExpandableMessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final configuration = widget;
    final generation = ++_configurationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _configurationGeneration) {
        _sheetConfiguration.value = configuration;
      }
    });
  }

  @override
  void dispose() {
    _routeGeneration += 1;
    _configurationGeneration += 1;
    final route = _sheetRoute;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    _controller.dispose();
    _focusNode.dispose();
    _sheetConfiguration.dispose();
    super.dispose();
  }

  void _beginExpansion() {
    if (!widget.enabled || _sheetRoute != null) return;
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    final rendererResources = RendererResourceScope.maybeOf(context);
    final generation = ++_routeGeneration;
    final route = ModalBottomSheetRoute<void>(
      builder: (sheetContext) {
        final sheet = ValueListenableBuilder<ExpandableMessageComposer>(
          valueListenable: _sheetConfiguration,
          builder: (context, configuration, child) => _ExpandableComposerSheet(
            controller: _controller,
            focusNode: _focusNode,
            enabled: configuration.enabled,
            maxLines: configuration.maxLines,
            hintText: configuration.hintText,
            buttons: configuration.buttons,
            onChanged: configuration.onChanged,
            onButtonPressed: configuration.onButtonPressed,
            onCollapseRequested: _dismissSheet,
          ),
        );
        return rendererResources == null
            ? sheet
            : RendererResourceScope(resources: rendererResources, child: sheet);
      },
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 640),
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: false,
      sheetAnimationStyle: widget.animationDuration == Duration.zero
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: widget.animationDuration,
              reverseDuration: widget.animationDuration,
            ),
    );
    setState(() => _sheetRoute = route);
    unawaited(
      navigator.push(route).whenComplete(() {
        if (!mounted || generation != _routeGeneration) return;
        _focusNode.unfocus();
        setState(() => _sheetRoute = null);
      }),
    );
  }

  void _dismissSheet() {
    final route = _sheetRoute;
    if (route == null || !route.isActive) return;
    _focusNode.unfocus();
    final navigator = route.navigator;
    if (route.isCurrent) {
      navigator?.pop();
    } else {
      navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _sheetRoute == null ? _buildFab() : const SizedBox.shrink();

  Widget _buildFab() => Tooltip(
    message: widget.fabTooltip,
    child: Semantics(
      label: widget.fabTooltip,
      button: true,
      enabled: widget.enabled,
      onTap: widget.enabled ? _beginExpansion : null,
      child: ExcludeSemantics(
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: widget.enabled ? _beginExpansion : null,
          icon: widget.fabIcon,
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.fabLabel, maxLines: 1),
          ),
        ),
      ),
    ),
  );
}

final class _ExpandableComposerSheet extends StatefulWidget {
  const _ExpandableComposerSheet({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.maxLines,
    required this.hintText,
    required this.buttons,
    required this.onChanged,
    required this.onButtonPressed,
    required this.onCollapseRequested,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final int maxLines;
  final String hintText;
  final List<MessageComposerButton> buttons;
  final ValueChanged<String>? onChanged;
  final MessageComposerButtonCallback? onButtonPressed;
  final VoidCallback onCollapseRequested;

  @override
  State<_ExpandableComposerSheet> createState() =>
      _ExpandableComposerSheetState();
}

final class _ExpandableComposerSheetState
    extends State<_ExpandableComposerSheet> {
  Animation<double>? _routeAnimation;

  void _requestFocusAfterMount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.enabled &&
          _routeAnimation?.status != AnimationStatus.reverse) {
        widget.focusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    _routeAnimation = animation;
    animation?.addStatusListener(_handleAnimationStatus);
    if (animation != null) _handleAnimationStatus(animation.status);
    if (widget.enabled) _requestFocusAfterMount();
  }

  @override
  void didUpdateWidget(_ExpandableComposerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      widget.focusNode.unfocus();
    } else if (!oldWidget.enabled && widget.enabled) {
      _requestFocusAfterMount();
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleAnimationStatus);
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      widget.focusNode.unfocus();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: MessageComposerSurfaceScope.embedded(
        child: MessageComposer(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          autofocus: false,
          maxLines: widget.maxLines,
          hintText: widget.hintText,
          buttons: widget.buttons,
          onChanged: widget.onChanged,
          onButtonPressed: widget.onButtonPressed,
          onCollapseRequested: widget.onCollapseRequested,
        ),
      ),
    );
  }
}

T _enumValue<T>(List<T> values, int index, String label) {
  if (index >= values.length) {
    throw FormatException('Invalid expandable message composer $label $index');
  }
  return values[index];
}

(String, int) _decodeString(
  Uint8List payload,
  int offset,
  int length,
  String label,
) {
  final end = offset + length;
  if (end > payload.length) {
    throw FormatException('Expandable message composer $label exceeds payload');
  }
  try {
    return (
      utf8.decode(payload.sublist(offset, end), allowMalformed: false),
      end,
    );
  } on FormatException {
    throw FormatException(
      'Expandable message composer $label must be valid UTF-8',
    );
  }
}

List<int> _encodeUtf8(String value, String label) {
  final encoded = utf8.encode(value);
  if (utf8.decode(encoded, allowMalformed: false) != value) {
    throw ArgumentError.value(value, label, 'must be valid Unicode');
  }
  return encoded;
}

Curve _curve(AnimationCurveValue curve) => switch (curve) {
  AnimationCurveValue.linear => Curves.linear,
  AnimationCurveValue.easeIn => Curves.easeIn,
  AnimationCurveValue.easeOut => Curves.easeOut,
  AnimationCurveValue.easeInOut => Curves.easeInOut,
};
