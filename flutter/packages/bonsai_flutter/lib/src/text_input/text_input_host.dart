import 'package:flutter/material.dart';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/renderer_resource_store.dart';
import '../renderer/widget_registry.dart';
import '../store/node_store.dart';

final class TextInputHost extends StatefulWidget {
  const TextInputHost({
    required this.node,
    required this.props,
    required this.resources,
    this.onEvent,
    super.key,
  });

  final UiNode node;
  final TextInputProps props;
  final RendererResourceStore resources;
  final RendererEventCallback? onEvent;

  @override
  State<TextInputHost> createState() => _TextInputHostState();
}

final class _TextInputHostState extends State<TextInputHost> {
  late TextInputResourceHandle _resource;
  bool _applyingRemote = false;

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
      } finally {
        _applyingRemote = false;
      }
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _acquire() {
    _resource = widget.resources.acquireTextInput(widget.node.id, widget.props);
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
    _resource.localRevision += 1;
    final value = _resource.controller.value;
    final composing = value.composing.isValid && !value.composing.isCollapsed
        ? value.composing
        : null;
    _emit(
      EventTagId.textEdit,
      TextEditEventPayload(
        sessionId: _resource.sessionId,
        localRevision: _resource.localRevision,
        baseDocumentRevision: _resource.documentRevision,
        text: value.text,
        selectionStartUtf16: value.selection.baseOffset,
        selectionEndUtf16: value.selection.extentOffset,
        composingStartUtf16: composing?.start,
        composingEndUtf16: composing?.end,
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
  Widget build(BuildContext context) => TextField(
    controller: _resource.controller,
    focusNode: _resource.focusNode,
    enabled: widget.props.enabled,
    readOnly: widget.props.readOnly,
    obscureText: widget.props.obscureText,
    keyboardType: _keyboardType(widget.props.keyboardType),
    textInputAction: _inputAction(widget.props.inputAction),
    autofocus: widget.props.autofocus,
    maxLines: widget.props.keyboardType == TextKeyboardType.multiline
        ? null
        : 1,
    onSubmitted: (value) =>
        _emit(EventTagId.textSubmit, TextEventPayload(value)),
  );
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
