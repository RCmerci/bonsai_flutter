import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../gesture/bonsai_gesture_detector.dart';
import '../protocol/frame.dart';
import 'message_composer_surface_scope.dart';
import 'native_widget_registry.dart';

enum MessageComposerButtonPosition { leading, trailing }

enum MessageComposerButtonVisibility { always, whenEmpty, whenNonEmpty }

enum MessageComposerButtonStyle { plain, filled }

@immutable
final class MessageComposerButtonProps {
  const MessageComposerButtonProps({
    required this.id,
    required this.tooltip,
    required this.position,
    required this.visibility,
    required this.style,
    required this.enabled,
  });

  final int id;
  final String tooltip;
  final MessageComposerButtonPosition position;
  final MessageComposerButtonVisibility visibility;
  final MessageComposerButtonStyle style;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is MessageComposerButtonProps &&
      other.id == id &&
      other.tooltip == tooltip &&
      other.position == position &&
      other.visibility == visibility &&
      other.style == style &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, tooltip, position, visibility, style, enabled);
}

@immutable
final class MessageComposerProps {
  const MessageComposerProps({
    required this.enabled,
    required this.autofocus,
    required this.maxLines,
    required this.hintText,
    required this.buttons,
  });

  static const _headerLength = 12;
  static const _buttonHeaderLength = 12;

  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final String hintText;
  final List<MessageComposerButtonProps> buttons;

  Uint8List encode() {
    _validate();
    final hint = utf8.encode(hintText);
    final tooltips = [
      for (final button in buttons) utf8.encode(button.tooltip),
    ];
    final length =
        _headerLength +
        hint.length +
        buttons.length * _buttonHeaderLength +
        tooltips.fold<int>(0, (total, bytes) => total + bytes.length);
    final payload = Uint8List(length);
    final data = ByteData.sublistView(payload);
    data
      ..setUint8(0, (enabled ? 1 : 0) | (autofocus ? 2 : 0))
      ..setUint16(2, maxLines, Endian.little)
      ..setUint16(4, buttons.length, Endian.little)
      ..setUint32(8, hint.length, Endian.little);
    payload.setRange(_headerLength, _headerLength + hint.length, hint);

    var offset = _headerLength + hint.length;
    for (var index = 0; index < buttons.length; index += 1) {
      final button = buttons[index];
      final tooltip = tooltips[index];
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
    kindId: NativeWidgetKind.messageComposer,
    version: 1,
    capabilityBits: NativeCapability.stateful | NativeCapability.semantics,
    payload: encode(),
  );

  static MessageComposerProps decode(Uint8List payload) {
    if (payload.length < _headerLength) {
      throw const FormatException(
        'Message composer props must contain a 12-byte header',
      );
    }
    final data = ByteData.sublistView(payload);
    final flags = data.getUint8(0);
    if (flags & ~0x03 != 0) {
      throw FormatException(
        'Unknown message composer flags 0x${flags.toRadixString(16)}',
      );
    }
    final maxLines = data.getUint16(2, Endian.little);
    if (maxLines == 0) {
      throw const FormatException(
        'Message composer max lines must be positive',
      );
    }
    final buttonCount = data.getUint16(4, Endian.little);
    if (data.getUint8(1) != 0 || data.getUint16(6, Endian.little) != 0) {
      throw const FormatException(
        'Message composer reserved bytes must be zero',
      );
    }
    final hintLength = data.getUint32(8, Endian.little);
    var offset = _headerLength;
    final hintEnd = offset + hintLength;
    if (hintEnd > payload.length) {
      throw const FormatException('Message composer hint exceeds payload');
    }
    final hintText = _decodeUtf8(payload, offset, hintEnd, 'hint');
    offset = hintEnd;
    final buttons = <MessageComposerButtonProps>[];
    final ids = <int>{};
    for (var index = 0; index < buttonCount; index += 1) {
      if (offset + _buttonHeaderLength > payload.length) {
        throw const FormatException(
          'Message composer button header exceeds payload',
        );
      }
      final id = data.getUint32(offset, Endian.little);
      if (id == 0 || !ids.add(id)) {
        throw const FormatException(
          'Message composer button IDs must be positive and unique',
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
          'Unknown message composer button flags 0x'
          '${buttonFlags.toRadixString(16)}',
        );
      }
      final tooltipLength = data.getUint32(offset + 8, Endian.little);
      offset += _buttonHeaderLength;
      final tooltipEnd = offset + tooltipLength;
      if (tooltipEnd > payload.length) {
        throw const FormatException(
          'Message composer button tooltip exceeds payload',
        );
      }
      final tooltip = _decodeUtf8(payload, offset, tooltipEnd, 'tooltip');
      if (tooltip.isEmpty) {
        throw const FormatException(
          'Message composer button tooltip must not be empty',
        );
      }
      buttons.add(
        MessageComposerButtonProps(
          id: id,
          tooltip: tooltip,
          position: position,
          visibility: visibility,
          style: style,
          enabled: buttonFlags & 1 != 0,
        ),
      );
      offset = tooltipEnd;
    }
    if (offset != payload.length) {
      throw const FormatException('Message composer props contain extra bytes');
    }
    return MessageComposerProps(
      enabled: flags & 1 != 0,
      autofocus: flags & 2 != 0,
      maxLines: maxLines,
      hintText: hintText,
      buttons: List.unmodifiable(buttons),
    );
  }

  void _validate() {
    if (maxLines <= 0 || maxLines > 0xffff) {
      throw ArgumentError.value(maxLines, 'maxLines', 'must be in 1..65535');
    }
    if (buttons.length > 0xffff) {
      throw ArgumentError.value(
        buttons.length,
        'buttons',
        'must contain at most 65535 entries',
      );
    }
    final ids = <int>{};
    for (final button in buttons) {
      if (button.id <= 0 || button.id > 0xffffffff) {
        throw ArgumentError.value(
          button.id,
          'button.id',
          'must be in 1..4294967295',
        );
      }
      if (!ids.add(button.id)) {
        throw ArgumentError.value(button.id, 'button.id', 'must be unique');
      }
      if (button.tooltip.isEmpty) {
        throw ArgumentError.value(
          button.tooltip,
          'button.tooltip',
          'must not be empty',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MessageComposerProps &&
      other.enabled == enabled &&
      other.autofocus == autofocus &&
      other.maxLines == maxLines &&
      other.hintText == hintText &&
      listEquals(other.buttons, buttons);

  @override
  int get hashCode => Object.hash(
    enabled,
    autofocus,
    maxLines,
    hintText,
    Object.hashAll(buttons),
  );
}

T _enumValue<T>(List<T> values, int index, String label) {
  if (index >= values.length) {
    throw FormatException('Invalid message composer $label $index');
  }
  return values[index];
}

String _decodeUtf8(Uint8List payload, int start, int end, String label) {
  try {
    return utf8.decode(payload.sublist(start, end), allowMalformed: false);
  } on FormatException {
    throw FormatException('Message composer $label must be valid UTF-8');
  }
}

abstract final class MessageComposerEvent {
  static const int textChanged = 1;
  static const int buttonPressed = 2;

  static Uint8List encodeTextChanged(String text) =>
      Uint8List.fromList(utf8.encode(text));

  static Uint8List encodeButtonPressed(int buttonId, String text) {
    final encodedText = utf8.encode(text);
    final payload = Uint8List(4 + encodedText.length);
    ByteData.sublistView(payload).setUint32(0, buttonId, Endian.little);
    payload.setRange(4, payload.length, encodedText);
    return payload;
  }
}

void registerMessageComposer(NativeWidgetRegistry registry) {
  registry.register<MessageComposerProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.messageComposer,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits: NativeCapability.stateful | NativeCapability.semantics,
      decodeProps: MessageComposerProps.decode,
      factory: (context) {
        if (context.children.length != context.props.buttons.length) {
          throw FormatException(
            'Message composer requires exactly '
            '${context.props.buttons.length} button children',
          );
        }
        return MessageComposer(
          enabled: context.props.enabled,
          autofocus: context.props.autofocus,
          maxLines: context.props.maxLines,
          hintText: context.props.hintText,
          buttons: List.generate(context.props.buttons.length, (index) {
            final button = context.props.buttons[index];
            return MessageComposerButton(
              id: button.id,
              tooltip: button.tooltip,
              position: button.position,
              visibility: button.visibility,
              style: button.style,
              enabled: button.enabled,
              child: context.children[index],
            );
          }),
          onChanged: context.emit == null
              ? null
              : (text) => context.emit!(
                  MessageComposerEvent.textChanged,
                  MessageComposerEvent.encodeTextChanged(text),
                ),
          onButtonPressed: context.emit == null
              ? null
              : (buttonId, text) => context.emit!(
                  MessageComposerEvent.buttonPressed,
                  MessageComposerEvent.encodeButtonPressed(buttonId, text),
                ),
        );
      },
    ),
  );
}

@immutable
final class MessageComposerButton {
  const MessageComposerButton({
    required this.id,
    required this.tooltip,
    required this.child,
    this.position = MessageComposerButtonPosition.trailing,
    this.visibility = MessageComposerButtonVisibility.always,
    this.style = MessageComposerButtonStyle.plain,
    this.enabled = true,
  });

  final int id;
  final String tooltip;
  final Widget child;
  final MessageComposerButtonPosition position;
  final MessageComposerButtonVisibility visibility;
  final MessageComposerButtonStyle style;
  final bool enabled;
}

typedef MessageComposerButtonCallback =
    void Function(int buttonId, String currentText);

/// A theme-aware message input whose actions are supplied by its owner.
final class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.buttons,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 5,
    this.hintText = 'Ask anything',
    this.onChanged,
    this.onButtonPressed,
    this.onCollapseRequested,
    super.key,
  }) : assert(maxLines > 0);

  final List<MessageComposerButton> buttons;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final MessageComposerButtonCallback? onButtonPressed;
  final VoidCallback? onCollapseRequested;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

final class _MessageComposerState extends State<MessageComposer> {
  static const _collapseDragThreshold = 24.0;

  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _forceCollapsed = false;
  double _verticalDragDistance = 0;

  bool get _hasText => _controller.text.trim().isNotEmpty;

  bool get _isExpanded => !_forceCollapsed && (_focusNode.hasFocus || _hasText);

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _attachListeners();
  }

  @override
  void didUpdateWidget(MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _controller.removeListener(_handleValueChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_handleValueChanged);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _focusNode.removeListener(_handleValueChanged);
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleValueChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleValueChanged);
    _focusNode.removeListener(_handleValueChanged);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _attachListeners() {
    _controller.addListener(_handleValueChanged);
    _focusNode.addListener(_handleValueChanged);
  }

  void _handleValueChanged() {
    if (!mounted) return;
    setState(() {
      if (_focusNode.hasFocus) _forceCollapsed = false;
    });
  }

  void _handleVerticalDragStart(DragStartDetails _) {
    _verticalDragDistance = 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragDistance += details.delta.dy;
  }

  void _handleVerticalDragEnd(DragEndDetails _) {
    if (_verticalDragDistance < _collapseDragThreshold) return;
    if (widget.onCollapseRequested != null) {
      widget.onCollapseRequested!();
      return;
    }
    if (!_isExpanded) return;
    setState(() => _forceCollapsed = true);
    _focusNode.unfocus();
  }

  void _handleVerticalDragCancel() {
    _verticalDragDistance = 0;
  }

  bool _isVisible(MessageComposerButton button) => switch (button.visibility) {
    MessageComposerButtonVisibility.always => true,
    MessageComposerButtonVisibility.whenEmpty => !_hasText,
    MessageComposerButtonVisibility.whenNonEmpty => _hasText,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expanded = _isExpanded;
    final embedded = MessageComposerSurfaceScope.isEmbedded(context);
    final editor = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 1,
      maxLines: expanded ? widget.maxLines : 1,
      onChanged: widget.onChanged,
      cursorColor: colors.primary,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      style: TextStyle(color: colors.onSurface, fontSize: 15, height: 1.3),
    );
    final actions = _actions();

    return BonsaiGestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _handleVerticalDragStart,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      onVerticalDragEnd: _handleVerticalDragEnd,
      onVerticalDragCancel: _handleVerticalDragCancel,
      child: AnimatedSize(
        alignment: Alignment.bottomCenter,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          type: embedded ? MaterialType.transparency : MaterialType.canvas,
          color: embedded ? null : colors.surfaceContainerHighest,
          shape: embedded
              ? null
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(expanded ? 20 : 24),
                  side: BorderSide(color: colors.outlineVariant),
                ),
          clipBehavior: embedded ? Clip.none : Clip.antiAlias,
          child: _AdaptiveComposer(
            expanded: expanded,
            editor: editor,
            actions: actions,
          ),
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final visible = widget.buttons.where(_isVisible);
    final leading = visible
        .where(
          (button) => button.position == MessageComposerButtonPosition.leading,
        )
        .map(_buildButton);
    final trailing = visible
        .where(
          (button) => button.position == MessageComposerButtonPosition.trailing,
        )
        .map(_buildButton);
    return [...leading, const Spacer(), ...trailing];
  }

  Widget _buildButton(MessageComposerButton button) => _ComposerAction(
    tooltip: button.tooltip,
    filled: button.style == MessageComposerButtonStyle.filled,
    onPressed:
        widget.enabled && button.enabled && widget.onButtonPressed != null
        ? () => widget.onButtonPressed!(button.id, _controller.text)
        : null,
    child: button.child,
  );
}

final class _AdaptiveComposer extends StatelessWidget {
  const _AdaptiveComposer({
    required this.expanded,
    required this.editor,
    required this.actions,
  });

  final bool expanded;
  final Widget editor;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: expanded
            ? const EdgeInsets.fromLTRB(16, 12, 16, 52)
            : const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Expanded(child: editor),
            if (!expanded) ...[
              const SizedBox(width: 4),
              ...actions.where((action) => action is! Spacer),
            ],
          ],
        ),
      ),
      if (expanded)
        Positioned(left: 8, right: 8, bottom: 6, child: Row(children: actions)),
    ],
  );
}

final class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.tooltip,
    required this.child,
    required this.onPressed,
    required this.filled,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: child,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        iconSize: filled ? 20 : 22,
        foregroundColor: filled ? colors.onPrimary : colors.onSurface,
        disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
        backgroundColor: filled ? colors.primary : Colors.transparent,
        disabledBackgroundColor: filled
            ? colors.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: const CircleBorder(),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
