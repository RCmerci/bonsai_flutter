import 'dart:convert';

import 'package:flutter/material.dart';

import '../navigation/modal_sheet_keyboard_coordinator.dart';
import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/renderer_resource_store.dart';
import '../renderer/widget_registry.dart';
import '../store/node_store.dart';

typedef TextInputWidgetBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      FocusNode focusNode,
      ValueChanged<String> onSubmitted,
    );

final class TextInputHost extends StatefulWidget {
  const TextInputHost({
    required this.node,
    required this.props,
    required this.resources,
    this.onEvent,
    this.builder,
    super.key,
  });

  final UiNode node;
  final TextInputProps props;
  final RendererResourceStore resources;
  final RendererEventCallback? onEvent;
  final TextInputWidgetBuilder? builder;

  @override
  State<TextInputHost> createState() => _TextInputHostState();
}

final class _TextInputHostState extends State<TextInputHost> {
  late TextInputResourceHandle _resource;
  late TextEditingValue _lastValidValue;
  bool _applyingRemote = false;
  bool? _automaticFocusReady;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  @override
  void didUpdateWidget(TextInputHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.resources, widget.resources) ||
        oldWidget.node.id != widget.node.id) {
      _detach();
      _acquire();
    } else if (oldWidget.props != widget.props) {
      _applyingRemote = true;
      try {
        _resource.applyRemote(widget.props);
        _lastValidValue = _resource.controller.value;
      } finally {
        _applyingRemote = false;
      }
    }
    if (!oldWidget.props.autofocus &&
        widget.props.autofocus &&
        _automaticFocusReady == true) {
      _scheduleAutomaticFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final automaticFocusReady = ModalSheetAutomaticFocusScope.isReady(context);
    if (_automaticFocusReady == false &&
        automaticFocusReady &&
        widget.props.autofocus) {
      _scheduleAutomaticFocus();
    }
    _automaticFocusReady = automaticFocusReady;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _acquire() {
    _resource = widget.resources.acquireTextInput(widget.node.id, widget.props);
    _lastValidValue = _resource.controller.value;
    _resource.controller.addListener(_onControllerChanged);
    _resource.focusNode.addListener(_onFocusChanged);
  }

  void _detach() {
    if (_resource.disposed) return;
    _resource.controller.removeListener(_onControllerChanged);
    _resource.focusNode.removeListener(_onFocusChanged);
  }

  void _onControllerChanged() {
    if (_applyingRemote || _resource.disposed) return;
    final value = _resource.controller.value;
    final maxUtf8Bytes = widget.props.maxUtf8Bytes;
    if (maxUtf8Bytes != null && utf8.encode(value.text).length > maxUtf8Bytes) {
      _applyingRemote = true;
      try {
        _resource.controller.value = _lastValidValue;
      } finally {
        _applyingRemote = false;
      }
      _emit(EventTagId.textLimitReached, const UnitEventPayload());
      return;
    }
    _lastValidValue = value;
    _resource.localRevision += 1;
    final selection = _normalizeSelection(value.text, value.selection);
    final composing = _normalizeComposing(value.text, value.composing);
    _emit(
      EventTagId.textEdit,
      TextEditEventPayload(
        sessionId: _resource.sessionId,
        localRevision: _resource.localRevision,
        baseDocumentRevision: _resource.documentRevision,
        text: value.text,
        selectionStartUtf16: selection.$1,
        selectionEndUtf16: selection.$2,
        composingStartUtf16: composing?.$1,
        composingEndUtf16: composing?.$2,
      ),
    );
  }

  void _onFocusChanged() {
    if (_resource.disposed) return;
    _emit(
      EventTagId.focusChanged,
      BoolEventPayload(_resource.focusNode.hasFocus),
    );
  }

  void _scheduleAutomaticFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.props.autofocus ||
          _automaticFocusReady != true ||
          _resource.disposed ||
          _resource.focusNode.hasFocus) {
        return;
      }
      FocusScope.of(context).autofocus(_resource.focusNode);
    }, debugLabel: 'TextInputHost.automaticFocus');
  }

  void _emit(int eventTag, EventPayload payload) {
    final onEvent = widget.onEvent;
    if (onEvent == null) return;
    final binding = _binding(widget.node, eventTag);
    if (binding == null) return;
    onEvent(
      RendererEvent(
        nodeId: widget.node.id,
        eventTag: eventTag,
        handlerId: binding.handlerId,
        payload: payload,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder != null) {
      return builder(
        context,
        _resource.controller,
        _resource.focusNode,
        (value) => _emit(EventTagId.textSubmit, TextEventPayload(value)),
      );
    }
    return TextField(
      controller: _resource.controller,
      focusNode: _resource.focusNode,
      enabled: widget.props.enabled,
      readOnly: widget.props.readOnly,
      obscureText: widget.props.obscureText,
      keyboardType: _keyboardType(widget.props.keyboardType),
      textInputAction: _inputAction(widget.props.inputAction),
      autofocus:
          widget.props.autofocus &&
          ModalSheetAutomaticFocusScope.isReady(context),
      maxLines: widget.props.keyboardType == TextKeyboardType.multiline
          ? null
          : 1,
      onSubmitted: (value) =>
          _emit(EventTagId.textSubmit, TextEventPayload(value)),
    );
  }
}

(int, int) _normalizeSelection(String text, TextSelection selection) {
  if (!selection.isValid) return (text.length, text.length);
  final base = _normalizeUtf16Boundary(text, selection.baseOffset);
  final extent = _normalizeUtf16Boundary(text, selection.extentOffset);
  return base <= extent ? (base, extent) : (extent, base);
}

(int, int)? _normalizeComposing(String text, TextRange composing) {
  if (!composing.isValid || composing.isCollapsed) return null;
  final start = _normalizeUtf16Boundary(text, composing.start);
  final end = _normalizeUtf16Boundary(text, composing.end);
  if (start == end) return null;
  return start <= end ? (start, end) : (end, start);
}

int _normalizeUtf16Boundary(String text, int offset) {
  if (offset < 0 || offset > text.length) return text.length;
  if (offset == 0 || offset == text.length) return offset;
  final previous = text.codeUnitAt(offset - 1);
  final next = text.codeUnitAt(offset);
  final splitsSurrogatePair =
      previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff;
  return splitsSurrogatePair ? offset + 1 : offset;
}

EventBinding? _binding(UiNode node, int eventTag) {
  for (final binding in node.eventBindings) {
    if (binding.eventTag == eventTag) return binding;
  }
  return null;
}

TextInputType _keyboardType(TextKeyboardType type) => switch (type) {
  TextKeyboardType.text => TextInputType.text,
  TextKeyboardType.multiline => TextInputType.multiline,
  TextKeyboardType.number => TextInputType.number,
  TextKeyboardType.email => TextInputType.emailAddress,
  TextKeyboardType.phone => TextInputType.phone,
  TextKeyboardType.url => TextInputType.url,
};

TextInputAction _inputAction(TextInputActionKind action) => switch (action) {
  TextInputActionKind.done => TextInputAction.done,
  TextInputActionKind.newline => TextInputAction.newline,
  TextInputActionKind.next => TextInputAction.next,
  TextInputActionKind.previous => TextInputAction.previous,
  TextInputActionKind.search => TextInputAction.search,
  TextInputActionKind.send => TextInputAction.send,
  TextInputActionKind.go => TextInputAction.go,
};
