import 'dart:convert';
import 'dart:typed_data';

import '../debug/frame_stats.dart';
import 'frame.dart';
import 'generated_protocol.dart';

export 'generated_protocol.dart' show ProtocolLimits;

enum ProtocolErrorCode {
  invalidMagic,
  unsupportedVersion,
  invalidHeader,
  invalidFrameKind,
  invalidFlags,
  invalidPayloadLength,
  frameTooLarge,
  tooManyOperations,
  stringTooLarge,
  unknownOperation,
  unknownNodeKind,
  invalidEventTag,
  invalidProps,
  invalidUtf8,
  invalidOperationOrder,
  truncatedInput,
  trailingBytes,
}

final class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message);

  final ProtocolErrorCode code;
  final String message;

  @override
  String toString() => 'ProtocolException($code, $message)';
}

abstract final class FrameCodec {
  static Uint8List encode(Frame frame) {
    final operationCount = frame.operations.length + 2;
    if (operationCount > ProtocolLimits.maxOperations) {
      _fail(
        ProtocolErrorCode.tooManyOperations,
        'Frame has $operationCount wire operations',
      );
    }
    _checkUint64('runtime epoch', frame.runtimeEpoch);
    _checkUint64('base revision', frame.baseRevision);
    _checkUint64('target revision', frame.targetRevision);

    final payload = _Writer()..envelope(OperationId.beginFrame, (_) {});
    for (final operation in frame.operations) {
      _writeOperation(payload, operation);
    }
    payload.envelope(OperationId.endFrame, (_) {});
    final payloadBytes = payload.takeBytes();
    final totalLength = ProtocolLimits.headerBytes + payloadBytes.length;
    if (totalLength > ProtocolLimits.maxFrameBytes) {
      _fail(
        ProtocolErrorCode.frameTooLarge,
        'Encoded frame is $totalLength bytes',
      );
    }

    final output = _Writer()
      ..raw(const [0x42, 0x46, 0x46, 0x52])
      ..uint16(ProtocolVersion.protocolMajor)
      ..uint16(ProtocolVersion.protocolMinor)
      ..uint16(ProtocolLimits.headerBytes)
      ..uint8(_frameKindId(frame.kind))
      ..uint8(0)
      ..uint64(frame.runtimeEpoch)
      ..uint64(frame.baseRevision)
      ..uint64(frame.targetRevision)
      ..uint32(payloadBytes.length)
      ..uint32(0)
      ..uint32(0)
      ..raw(payloadBytes);
    return output.takeBytes();
  }

  static Frame decode(Uint8List bytes) {
    final stopwatch = Stopwatch()..start();
    if (bytes.length > ProtocolLimits.maxFrameBytes) {
      _fail(ProtocolErrorCode.frameTooLarge, 'Frame is ${bytes.length} bytes');
    }
    if (bytes.length < ProtocolLimits.headerBytes) {
      _fail(
        ProtocolErrorCode.truncatedInput,
        'Frame is shorter than the fixed header',
      );
    }

    final reader = _Reader.root(bytes);
    final magic = reader.bytes(4);
    if (!_bytesEqual(magic, const [0x42, 0x46, 0x46, 0x52])) {
      _fail(ProtocolErrorCode.invalidMagic, 'Invalid frame magic');
    }
    final major = reader.uint16();
    final minor = reader.uint16();
    if (major != ProtocolVersion.protocolMajor ||
        minor > ProtocolVersion.protocolMinor) {
      _fail(
        ProtocolErrorCode.unsupportedVersion,
        'Unsupported protocol version $major.$minor',
      );
    }
    final headerBytes = reader.uint16();
    if (headerBytes != ProtocolLimits.headerBytes) {
      _fail(
        ProtocolErrorCode.invalidHeader,
        'Invalid header size $headerBytes',
      );
    }
    final kind = _decodeFrameKind(reader.uint8());
    final flags = reader.uint8();
    if (flags != 0) {
      _fail(
        ProtocolErrorCode.invalidFlags,
        'Unsupported flags 0x${flags.toRadixString(16)}',
      );
    }
    final runtimeEpoch = reader.uint64();
    final baseRevision = reader.uint64();
    final targetRevision = reader.uint64();
    final payloadLength = reader.uint32();
    final checksum = reader.uint32();
    final reserved = reader.uint32();
    if (checksum != 0 || reserved != 0) {
      _fail(
        ProtocolErrorCode.invalidHeader,
        'Reserved header fields must be zero',
      );
    }
    if (payloadLength != reader.remaining) {
      _fail(
        ProtocolErrorCode.invalidPayloadLength,
        'Header declares $payloadLength payload bytes, '
        '${reader.remaining} remain',
      );
    }

    final payload = reader.subReader(payloadLength);
    final operations = <FrameOperation>[];
    var operationCount = 0;
    var sawBegin = false;
    var sawEnd = false;
    while (!payload.isDone) {
      operationCount += 1;
      if (operationCount > ProtocolLimits.maxOperations) {
        _fail(ProtocolErrorCode.tooManyOperations, 'Operation limit exceeded');
      }
      final opcode = payload.uint8();
      final bodyLength = payload.uint32();
      final body = payload.subReader(bodyLength);

      if (opcode == OperationId.beginFrame) {
        if (operationCount != 1 || sawBegin) {
          _fail(
            ProtocolErrorCode.invalidOperationOrder,
            'BeginFrame must be first',
          );
        }
        body.requireDone();
        sawBegin = true;
        continue;
      }
      if (opcode == OperationId.endFrame) {
        if (!sawBegin || sawEnd) {
          _fail(ProtocolErrorCode.invalidOperationOrder, 'Invalid EndFrame');
        }
        body.requireDone();
        sawEnd = true;
        if (!payload.isDone) {
          _fail(
            ProtocolErrorCode.invalidOperationOrder,
            'EndFrame must be last',
          );
        }
        continue;
      }
      if (!_isKnownSemanticOperation(opcode)) {
        _fail(ProtocolErrorCode.unknownOperation, 'Unknown operation $opcode');
      }
      if (!sawBegin || sawEnd) {
        _fail(
          ProtocolErrorCode.invalidOperationOrder,
          'Operation is outside BeginFrame/EndFrame',
        );
      }
      operations.add(_readOperation(opcode, body, protocolMinor: minor));
      body.requireDone();
    }
    if (!sawBegin || !sawEnd) {
      _fail(
        ProtocolErrorCode.invalidOperationOrder,
        'Frame is missing BeginFrame or EndFrame',
      );
    }

    final frame = Frame(
      runtimeEpoch: runtimeEpoch,
      baseRevision: baseRevision,
      targetRevision: targetRevision,
      kind: kind,
      operations: List.unmodifiable(operations),
    );
    stopwatch.stop();
    DebugFrameRecorder.recordDecoded(
      frame,
      patchBytes: bytes.length,
      duration: stopwatch.elapsed,
    );
    return frame;
  }

  static void _writeOperation(_Writer payload, FrameOperation operation) {
    switch (operation) {
      case CreateNode():
        payload.envelope(OperationId.createNode, (body) {
          _checkUint64('node ID', operation.nodeId);
          body
            ..uint64(operation.nodeId)
            ..uint16(_nodeKindId(operation.kind));
          _writeCreateProps(body, operation.kind, operation.props);
          _writeBindings(body, operation.eventBindings);
          _writeParentData(body, operation.parentData);
        });
      case UpdateProps():
        payload.envelope(OperationId.updateProps, (body) {
          _checkUint64('node ID', operation.nodeId);
          body.uint64(operation.nodeId);
          _writeUpdateProps(body, operation.props);
        });
      case UpdateEventBindings():
        payload.envelope(OperationId.updateEventBindings, (body) {
          _checkUint64('node ID', operation.nodeId);
          body.uint64(operation.nodeId);
          _writeBindings(body, operation.eventBindings);
        });
      case SetChildren():
        if (operation.children.length > ProtocolLimits.maxNodes) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Child count exceeds the node limit',
          );
        }
        payload.envelope(OperationId.setChildren, (body) {
          _checkUint64('node ID', operation.nodeId);
          body
            ..uint64(operation.nodeId)
            ..uint32(operation.children.length);
          for (final child in operation.children) {
            _checkUint64('child node ID', child);
            body.uint64(child);
          }
        });
      case SetRoot():
        payload.envelope(OperationId.setRoot, (body) {
          _checkUint64('root node ID', operation.nodeId);
          body.uint64(operation.nodeId);
        });
      case DropNode():
        payload.envelope(OperationId.dropNode, (body) {
          _checkUint64('node ID', operation.nodeId);
          body.uint64(operation.nodeId);
        });
      case HostRequestOperation():
        payload.envelope(OperationId.hostRequest, (body) {
          _writeHostRequest(body, operation.requestId, operation.request);
        });
      case CancelHostRequestOperation():
        payload.envelope(OperationId.hostRequest, (body) {
          _checkUint64('host request ID', operation.requestId);
          body
            ..uint64(operation.requestId)
            ..uint16(0);
        });
      case RuntimeStatsOperation():
        payload.envelope(OperationId.runtimeNotification, (body) {
          _writeRuntimeStats(body, operation);
        });
    }
  }

  static FrameOperation _readOperation(
    int opcode,
    _Reader body, {
    required int protocolMinor,
  }) {
    if (opcode == OperationId.createNode) {
      final nodeId = body.uint64();
      final kind = _readNodeKind(body);
      final props = _readProps(body, kind, protocolMinor: protocolMinor);
      final bindings = _readBindings(body);
      final parentData = _readParentData(body);
      return CreateNode(
        nodeId: nodeId,
        kind: kind,
        props: props,
        eventBindings: bindings,
        parentData: parentData,
      );
    }
    if (opcode == OperationId.updateProps) {
      return UpdateProps(
        nodeId: body.uint64(),
        props: _readUpdateProps(body, protocolMinor: protocolMinor),
      );
    }
    if (opcode == OperationId.updateEventBindings) {
      return UpdateEventBindings(
        nodeId: body.uint64(),
        eventBindings: _readBindings(body),
      );
    }
    if (opcode == OperationId.setChildren) {
      final nodeId = body.uint64();
      final count = body.uint32();
      if (count > ProtocolLimits.maxNodes) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Child count exceeds the node limit',
        );
      }
      return SetChildren(
        nodeId: nodeId,
        children: List.unmodifiable([
          for (var index = 0; index < count; index += 1) body.uint64(),
        ]),
      );
    }
    if (opcode == OperationId.setRoot) {
      return SetRoot(body.uint64());
    }
    if (opcode == OperationId.dropNode) {
      return DropNode(body.uint64());
    }
    if (opcode == OperationId.hostRequest) {
      final requestId = body.uint64();
      final requestKind = body.uint16();
      if (requestKind == 0) {
        return CancelHostRequestOperation(requestId: requestId);
      }
      return HostRequestOperation(
        requestId: requestId,
        request: _readHostRequest(body, requestKind),
      );
    }
    if (opcode == OperationId.runtimeNotification) {
      return _readRuntimeStats(body);
    }
    _fail(ProtocolErrorCode.unknownOperation, 'Unknown operation $opcode');
  }

  static void _writeCreateProps(_Writer writer, NodeKind kind, UiProps props) {
    switch ((kind, props)) {
      case (NodeKind.empty, EmptyProps()):
      case (NodeKind.stack, EmptyProps()):
      case (NodeKind.environmentBoundary, EnvironmentBoundaryProps()):
      case (NodeKind.gesture, GestureProps()):
      case (NodeKind.row, LinearProps()):
      case (NodeKind.column, LinearProps()):
        return;
      case (NodeKind.text, final TextProps props):
        _writeTextProps(writer, props);
      case (NodeKind.richText, RichTextProps(:final spans)):
        _writeStringList(writer, spans, 'rich text span');
      case (
        NodeKind.icon,
        IconProps(
          :final codePoint,
          :final fontFamily,
          :final size,
          :final colorArgb,
        ),
      ):
        writer
          ..uint32(codePoint)
          ..optionalString(fontFamily)
          ..optionalFloat64(size);
        _writeOptionalArgb32(writer, colorArgb);
      case (
        NodeKind.image,
        ImageProps(:final uri, :final fit, :final width, :final height),
      ):
        writer
          ..string(uri)
          ..uint8(fit.index)
          ..optionalFloat64(width)
          ..optionalFloat64(height);
      case (NodeKind.button, ButtonProps(:final enabled)):
        writer.uint8(enabled ? 1 : 0);
      case (NodeKind.pressable, final PressableProps props):
        _writePressableProps(writer, props);
      case (NodeKind.padding, PaddingProps(:final insets)):
        _writeInsets(writer, insets);
      case (NodeKind.align, AlignProps(:final alignment)):
        writer.uint8(alignment.index);
      case (
        NodeKind.center,
        CenterProps(:final widthFactor, :final heightFactor),
      ):
        writer
          ..optionalFloat64(widthFactor)
          ..optionalFloat64(heightFactor);
      case (NodeKind.sizedBox, SizedBoxProps(:final width, :final height)):
        writer
          ..optionalFloat64(width)
          ..optionalFloat64(height);
      case (
        NodeKind.constrainedBox,
        ConstrainedBoxProps(
          :final minWidth,
          :final maxWidth,
          :final minHeight,
          :final maxHeight,
        ),
      ):
        writer
          ..float64(minWidth)
          ..float64(maxWidth)
          ..float64(minHeight)
          ..float64(maxHeight);
      case (
        NodeKind.decoratedBox,
        DecoratedBoxProps(:final backgroundArgb, :final borderRadius),
      ):
        _writeOptionalArgb32(writer, backgroundArgb);
        writer.float64(borderRadius);
      case (NodeKind.clip, ClipProps(:final behavior)):
        writer.uint8(behavior.index);
      case (NodeKind.opacity, OpacityProps(:final opacity)):
        writer.float64(opacity);
      case (
        NodeKind.animatedOpacity,
        AnimatedOpacityProps(:final opacity, :final animation),
      ):
        writer.float64(opacity);
        _writeAnimation(writer, animation);
      case (NodeKind.transform, TransformProps(:final matrix4)):
        if (matrix4.length != 16) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Transform matrix must contain 16 values',
          );
        }
        for (final value in matrix4) {
          writer.float64(value);
        }
      case (NodeKind.scrollView, ScrollViewProps(:final axis, :final reverse)):
        writer
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0);
      case (NodeKind.listView, ListViewProps(:final axis, :final reverse)):
        writer
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0);
      case (NodeKind.focusScope, FocusScopeProps(:final autofocus)):
        writer.uint8(autofocus ? 1 : 0);
      case (NodeKind.mouseRegion, MouseRegionProps(:final opaque)):
        writer.uint8(opaque ? 1 : 0);
      case (
        NodeKind.keyboardListener,
        KeyboardListenerProps(:final autofocus, :final keyPolicy),
      ):
        writer
          ..uint8(autofocus ? 1 : 0)
          ..uint8(keyPolicy.index);
      case (NodeKind.semantics, final SemanticsProps props):
        _writeSemanticsProps(writer, props);
      case (
        NodeKind.theme,
        ThemeProps(:final brightness, :final colorSeedArgb),
      ):
        writer
          ..uint8(brightness == ThemeBrightness.light ? 0 : 1)
          ..uint32(colorSeedArgb);
      case (NodeKind.materialScaffold, MaterialScaffoldProps(:final hasAppBar)):
        writer.uint8(hasAppBar ? 1 : 0);
      case (NodeKind.materialAppBar, MaterialAppBarProps(:final centerTitle)):
        writer.uint8(centerTitle ? 1 : 0);
      case (
        NodeKind.materialElevatedButton ||
            NodeKind.materialTextButton ||
            NodeKind.materialIconButton,
        MaterialButtonProps(:final enabled, :final autofocus),
      ):
        writer
          ..uint8(enabled ? 1 : 0)
          ..uint8(autofocus ? 1 : 0);
      case (
        NodeKind.materialCheckbox,
        MaterialCheckboxProps(:final value, :final enabled),
      ):
        writer
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case (
        NodeKind.materialSwitch,
        MaterialSwitchProps(:final value, :final enabled),
      ):
        writer
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case (
        NodeKind.materialListTile,
        MaterialListTileProps(
          :final enabled,
          :final selected,
          :final hasSubtitle,
          :final hasLeading,
          :final hasTrailing,
        ),
      ):
        writer
          ..uint8(enabled ? 1 : 0)
          ..uint8(selected ? 1 : 0)
          ..uint8(hasSubtitle ? 1 : 0)
          ..uint8(hasLeading ? 1 : 0)
          ..uint8(hasTrailing ? 1 : 0);
      case (NodeKind.materialDivider, MaterialDividerProps(:final thickness)):
        writer.float64(thickness);
      case (NodeKind.materialCard, MaterialCardProps(:final elevation)):
        writer.float64(elevation);
      case (
        NodeKind.materialCircularProgressIndicator,
        MaterialProgressProps(:final value),
      ):
        writer.optionalFloat64(value);
      case (NodeKind.cupertinoButton, CupertinoButtonProps(:final enabled)):
        writer.uint8(enabled ? 1 : 0);
      case (
        NodeKind.cupertinoSwitch,
        CupertinoSwitchProps(:final value, :final enabled),
      ):
        writer
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case (NodeKind.textInput, final TextInputProps props):
        _writeTextInputProps(writer, props);
      case (
        NodeKind.overlay,
        OverlayProps(:final alignment, :final dismissible),
      ):
        writer
          ..uint8(alignment.index)
          ..uint8(dismissible ? 1 : 0);
      case (NodeKind.navigator, NavigatorProps(:final restorationScopeId)):
        writer.optionalString(restorationScopeId);
      case (
        NodeKind.page,
        PageProps(
          :final pageKey,
          :final transition,
          :final canPop,
          :final restorationId,
        ),
      ):
        if (pageKey.isEmpty) {
          _fail(ProtocolErrorCode.invalidProps, 'Page key must not be empty');
        }
        writer
          ..string(pageKey)
          ..uint8(transition.index)
          ..uint8(canPop ? 1 : 0)
          ..optionalString(restorationId);
      case (
        NodeKind.safeArea,
        SafeAreaProps(
          :final left,
          :final top,
          :final right,
          :final bottom,
          :final minimum,
        ),
      ):
        writer
          ..uint8(left ? 1 : 0)
          ..uint8(top ? 1 : 0)
          ..uint8(right ? 1 : 0)
          ..uint8(bottom ? 1 : 0);
        _writeInsets(writer, minimum);
      case (
        NodeKind.materialDialog,
        MaterialDialogProps(:final barrierDismissible),
      ):
        writer.uint8(barrierDismissible ? 1 : 0);
      case (NodeKind.nativeWidget, final NativeWidgetProps props):
        _writeNativeWidgetProps(writer, props);
      default:
        _fail(
          ProtocolErrorCode.invalidProps,
          'Props do not match node kind $kind',
        );
    }
  }

  static void _writeUpdateProps(_Writer writer, UiProps props) {
    switch (props) {
      case EmptyProps():
        writer
          ..uint16(NodeKindId.empty)
          ..uint64(0);
      case EnvironmentBoundaryProps():
        writer
          ..uint16(NodeKindId.environmentBoundary)
          ..uint64(0);
      case final TextProps props:
        writer
          ..uint16(NodeKindId.text)
          ..uint64(_changedFields(props));
        _writeTextProps(writer, props);
      case RichTextProps(:final spans):
        writer
          ..uint16(NodeKindId.richText)
          ..uint64(_changedFields(props));
        _writeStringList(writer, spans, 'rich text span');
      case IconProps(
        :final codePoint,
        :final fontFamily,
        :final size,
        :final colorArgb,
      ):
        writer
          ..uint16(NodeKindId.icon)
          ..uint64(_changedFields(props))
          ..uint32(codePoint)
          ..optionalString(fontFamily)
          ..optionalFloat64(size);
        _writeOptionalArgb32(writer, colorArgb);
      case ImageProps(:final uri, :final fit, :final width, :final height):
        writer
          ..uint16(NodeKindId.image)
          ..uint64(_changedFields(props))
          ..string(uri)
          ..uint8(fit.index)
          ..optionalFloat64(width)
          ..optionalFloat64(height);
      case LinearProps():
        writer
          ..uint16(NodeKindId.row)
          ..uint64(0);
      case ButtonProps(:final enabled):
        writer
          ..uint16(NodeKindId.button)
          ..uint64(1)
          ..uint8(enabled ? 1 : 0);
      case final PressableProps props:
        writer
          ..uint16(NodeKindId.pressable)
          ..uint64(_changedFields(props));
        _writePressableProps(writer, props);
      case PaddingProps(:final insets):
        writer
          ..uint16(NodeKindId.padding)
          ..uint64(_fieldMask(PaddingPropId.insets));
        _writeInsets(writer, insets);
      case AlignProps(:final alignment):
        writer
          ..uint16(NodeKindId.align)
          ..uint64(_changedFields(props))
          ..uint8(alignment.index);
      case CenterProps(:final widthFactor, :final heightFactor):
        writer
          ..uint16(NodeKindId.center)
          ..uint64(
            _fieldMask(CenterPropId.widthFactor) |
                _fieldMask(CenterPropId.heightFactor),
          )
          ..optionalFloat64(widthFactor)
          ..optionalFloat64(heightFactor);
      case SizedBoxProps(:final width, :final height):
        writer
          ..uint16(NodeKindId.sizedBox)
          ..uint64(_changedFields(props))
          ..optionalFloat64(width)
          ..optionalFloat64(height);
      case ConstrainedBoxProps(
        :final minWidth,
        :final maxWidth,
        :final minHeight,
        :final maxHeight,
      ):
        writer
          ..uint16(NodeKindId.constrainedBox)
          ..uint64(_changedFields(props))
          ..float64(minWidth)
          ..float64(maxWidth)
          ..float64(minHeight)
          ..float64(maxHeight);
      case DecoratedBoxProps(:final backgroundArgb, :final borderRadius):
        writer
          ..uint16(NodeKindId.decoratedBox)
          ..uint64(_changedFields(props));
        _writeOptionalArgb32(writer, backgroundArgb);
        writer.float64(borderRadius);
      case ClipProps(:final behavior):
        writer
          ..uint16(NodeKindId.clip)
          ..uint64(_changedFields(props))
          ..uint8(behavior.index);
      case OpacityProps(:final opacity):
        writer
          ..uint16(NodeKindId.opacity)
          ..uint64(_changedFields(props))
          ..float64(opacity);
      case AnimatedOpacityProps(:final opacity, :final animation):
        writer
          ..uint16(NodeKindId.animatedOpacity)
          ..uint64(_changedFields(props))
          ..float64(opacity);
        _writeAnimation(writer, animation);
      case TransformProps(:final matrix4):
        writer
          ..uint16(NodeKindId.transform)
          ..uint64(_changedFields(props));
        if (matrix4.length != 16) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Transform matrix must contain 16 values',
          );
        }
        for (final value in matrix4) {
          writer.float64(value);
        }
      case ScrollViewProps(:final axis, :final reverse):
        writer
          ..uint16(NodeKindId.scrollView)
          ..uint64(
            _fieldMask(ScrollViewPropId.axis) |
                _fieldMask(ScrollViewPropId.reverse),
          )
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0);
      case ListViewProps(:final axis, :final reverse):
        writer
          ..uint16(NodeKindId.listView)
          ..uint64(_changedFields(props))
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0);
      case GestureProps():
        writer
          ..uint16(NodeKindId.gesture)
          ..uint64(0);
      case FocusScopeProps(:final autofocus):
        writer
          ..uint16(NodeKindId.focusScope)
          ..uint64(_changedFields(props))
          ..uint8(autofocus ? 1 : 0);
      case MouseRegionProps(:final opaque):
        writer
          ..uint16(NodeKindId.mouseRegion)
          ..uint64(_changedFields(props))
          ..uint8(opaque ? 1 : 0);
      case KeyboardListenerProps(:final autofocus, :final keyPolicy):
        writer
          ..uint16(NodeKindId.keyboardListener)
          ..uint64(_changedFields(props))
          ..uint8(autofocus ? 1 : 0)
          ..uint8(keyPolicy.index);
      case final SemanticsProps props:
        writer
          ..uint16(NodeKindId.semantics)
          ..uint64(
            _fieldMask(SemanticsPropId.label) |
                _fieldMask(SemanticsPropId.hint) |
                _fieldMask(SemanticsPropId.value) |
                _fieldMask(SemanticsPropId.role) |
                _fieldMask(SemanticsPropId.enabled) |
                _fieldMask(SemanticsPropId.selected) |
                _fieldMask(SemanticsPropId.checked) |
                _fieldMask(SemanticsPropId.focusable) |
                _fieldMask(SemanticsPropId.obscured) |
                _fieldMask(SemanticsPropId.liveRegion) |
                _fieldMask(SemanticsPropId.headingLevel) |
                _fieldMask(SemanticsPropId.sortKey) |
                _fieldMask(SemanticsPropId.actions),
          );
        _writeSemanticsProps(writer, props);
      case ThemeProps(:final brightness, :final colorSeedArgb):
        writer
          ..uint16(NodeKindId.theme)
          ..uint64(
            _fieldMask(ThemePropId.brightness) |
                _fieldMask(ThemePropId.colorSeed),
          )
          ..uint8(brightness == ThemeBrightness.light ? 0 : 1)
          ..uint32(colorSeedArgb);
      case MaterialScaffoldProps(:final hasAppBar):
        writer
          ..uint16(NodeKindId.materialScaffold)
          ..uint64(_changedFields(props))
          ..uint8(hasAppBar ? 1 : 0);
      case MaterialAppBarProps(:final centerTitle):
        writer
          ..uint16(NodeKindId.materialAppBar)
          ..uint64(_changedFields(props))
          ..uint8(centerTitle ? 1 : 0);
      case MaterialButtonProps(
        :final variant,
        :final enabled,
        :final autofocus,
      ):
        writer
          ..uint16(switch (variant) {
            MaterialButtonVariant.elevated => NodeKindId.materialElevatedButton,
            MaterialButtonVariant.text => NodeKindId.materialTextButton,
            MaterialButtonVariant.icon => NodeKindId.materialIconButton,
          })
          ..uint64(_changedFields(props))
          ..uint8(enabled ? 1 : 0)
          ..uint8(autofocus ? 1 : 0);
      case MaterialCheckboxProps(:final value, :final enabled):
        writer
          ..uint16(NodeKindId.materialCheckbox)
          ..uint64(
            _fieldMask(MaterialCheckboxPropId.value) |
                _fieldMask(MaterialCheckboxPropId.enabled),
          )
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case MaterialSwitchProps(:final value, :final enabled):
        writer
          ..uint16(NodeKindId.materialSwitch)
          ..uint64(_changedFields(props))
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case MaterialListTileProps(
        :final enabled,
        :final selected,
        :final hasSubtitle,
        :final hasLeading,
        :final hasTrailing,
      ):
        writer
          ..uint16(NodeKindId.materialListTile)
          ..uint64(_changedFields(props))
          ..uint8(enabled ? 1 : 0)
          ..uint8(selected ? 1 : 0)
          ..uint8(hasSubtitle ? 1 : 0)
          ..uint8(hasLeading ? 1 : 0)
          ..uint8(hasTrailing ? 1 : 0);
      case MaterialDividerProps(:final thickness):
        writer
          ..uint16(NodeKindId.materialDivider)
          ..uint64(_changedFields(props))
          ..float64(thickness);
      case MaterialCardProps(:final elevation):
        writer
          ..uint16(NodeKindId.materialCard)
          ..uint64(_changedFields(props))
          ..float64(elevation);
      case MaterialProgressProps(:final value):
        writer
          ..uint16(NodeKindId.materialCircularProgressIndicator)
          ..uint64(_changedFields(props))
          ..optionalFloat64(value);
      case CupertinoButtonProps(:final enabled):
        writer
          ..uint16(NodeKindId.cupertinoButton)
          ..uint64(_changedFields(props))
          ..uint8(enabled ? 1 : 0);
      case CupertinoSwitchProps(:final value, :final enabled):
        writer
          ..uint16(NodeKindId.cupertinoSwitch)
          ..uint64(_changedFields(props))
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case final TextInputProps props:
        writer
          ..uint16(NodeKindId.textInput)
          ..uint64(_changedFields(props));
        _writeTextInputProps(writer, props);
      case OverlayProps(:final alignment, :final dismissible):
        writer
          ..uint16(NodeKindId.overlay)
          ..uint64(
            _fieldMask(OverlayPropId.alignment) |
                _fieldMask(OverlayPropId.dismissible),
          )
          ..uint8(alignment.index)
          ..uint8(dismissible ? 1 : 0);
      case NavigatorProps(:final restorationScopeId):
        writer
          ..uint16(NodeKindId.navigator)
          ..uint64(_fieldMask(NavigatorPropId.restorationScopeId))
          ..optionalString(restorationScopeId);
      case PageProps(
        :final pageKey,
        :final transition,
        :final canPop,
        :final restorationId,
      ):
        if (pageKey.isEmpty) {
          _fail(ProtocolErrorCode.invalidProps, 'Page key must not be empty');
        }
        writer
          ..uint16(NodeKindId.page)
          ..uint64(
            _fieldMask(PagePropId.pageKey) |
                _fieldMask(PagePropId.transition) |
                _fieldMask(PagePropId.canPop) |
                _fieldMask(PagePropId.restorationId),
          )
          ..string(pageKey)
          ..uint8(transition.index)
          ..uint8(canPop ? 1 : 0)
          ..optionalString(restorationId);
      case SafeAreaProps(
        :final left,
        :final top,
        :final right,
        :final bottom,
        :final minimum,
      ):
        writer
          ..uint16(NodeKindId.safeArea)
          ..uint64(_changedFields(props))
          ..uint8(left ? 1 : 0)
          ..uint8(top ? 1 : 0)
          ..uint8(right ? 1 : 0)
          ..uint8(bottom ? 1 : 0);
        _writeInsets(writer, minimum);
      case MaterialDialogProps(:final barrierDismissible):
        writer
          ..uint16(NodeKindId.materialDialog)
          ..uint64(_fieldMask(MaterialDialogPropId.barrierDismissible))
          ..uint8(barrierDismissible ? 1 : 0);
      case final NativeWidgetProps props:
        writer
          ..uint16(NodeKindId.nativeWidget)
          ..uint64(_changedFields(props));
        _writeNativeWidgetProps(writer, props);
    }
  }

  static UiProps _readUpdateProps(
    _Reader reader, {
    required int protocolMinor,
  }) {
    final kind = _readNodeKind(reader);
    final changedFields = reader.uint64();
    final props = _readProps(reader, kind, protocolMinor: protocolMinor);
    final expectedChangedFields = switch (kind) {
      NodeKind.text when protocolMinor < _styledTextProtocolMinor => _fieldMask(
        TextPropId.value,
      ),
      NodeKind.textInput
          when protocolMinor < _textInputUtf8LimitProtocolMinor =>
        _changedFields(props) & ~_fieldMask(TextInputPropId.maxUtf8Bytes),
      _ => _changedFields(props),
    };
    if (changedFields != expectedChangedFields) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Unsupported changed-field bitset $changedFields',
      );
    }
    return props;
  }

  static UiProps _readProps(
    _Reader reader,
    NodeKind kind, {
    required int protocolMinor,
  }) => switch (kind) {
    NodeKind.empty || NodeKind.stack => const EmptyProps(),
    NodeKind.environmentBoundary => const EnvironmentBoundaryProps(),
    NodeKind.text => _readTextProps(reader, protocolMinor: protocolMinor),
    NodeKind.richText => RichTextProps(_readStringList(reader)),
    NodeKind.icon => IconProps(
      codePoint: reader.uint32(),
      fontFamily: reader.optionalString(),
      size: reader.optionalFloat64(),
      colorArgb: _readOptionalArgb32(reader),
    ),
    NodeKind.image => ImageProps(
      uri: reader.string(),
      fit: _enumValue(ImageFitValue.values, reader.uint8(), 'image fit'),
      width: reader.optionalFloat64(),
      height: reader.optionalFloat64(),
    ),
    NodeKind.row || NodeKind.column => const LinearProps(),
    NodeKind.button => ButtonProps(enabled: reader.boolean()),
    NodeKind.pressable => () {
      final overlayColorArgb = reader.uint32();
      final releaseDelayMs = reader.uint16();
      if (releaseDelayMs > 100) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Pressable release delay must be in 0..100ms',
        );
      }
      return PressableProps(
        overlayColorArgb: overlayColorArgb,
        releaseDelayMs: releaseDelayMs,
      );
    }(),
    NodeKind.padding => PaddingProps(
      EdgeInsetsValue(
        left: reader.finiteFloat64(),
        top: reader.finiteFloat64(),
        right: reader.finiteFloat64(),
        bottom: reader.finiteFloat64(),
      ),
    ),
    NodeKind.align => AlignProps(
      _enumValue(AlignmentValue.values, reader.uint8(), 'alignment'),
    ),
    NodeKind.center => CenterProps(
      widthFactor: reader.optionalFloat64(),
      heightFactor: reader.optionalFloat64(),
    ),
    NodeKind.sizedBox => SizedBoxProps(
      width: reader.optionalFloat64(),
      height: reader.optionalFloat64(),
    ),
    NodeKind.constrainedBox => ConstrainedBoxProps(
      minWidth: reader.finiteFloat64(),
      maxWidth: reader.finiteFloat64(),
      minHeight: reader.finiteFloat64(),
      maxHeight: reader.finiteFloat64(),
    ),
    NodeKind.decoratedBox => DecoratedBoxProps(
      backgroundArgb: _readOptionalArgb32(reader),
      borderRadius: reader.finiteFloat64(),
    ),
    NodeKind.clip => ClipProps(
      _enumValue(ClipBehaviorValue.values, reader.uint8(), 'clip behavior'),
    ),
    NodeKind.opacity => OpacityProps(reader.finiteFloat64()),
    NodeKind.animatedOpacity => AnimatedOpacityProps(
      opacity: reader.finiteFloat64(),
      animation: _readAnimation(reader),
    ),
    NodeKind.transform => TransformProps(
      List<double>.generate(16, (_) => reader.finiteFloat64()),
    ),
    NodeKind.scrollView => ScrollViewProps(
      axis: reader.scrollAxis(),
      reverse: reader.boolean(),
    ),
    NodeKind.listView => ListViewProps(
      axis: reader.scrollAxis(),
      reverse: reader.boolean(),
    ),
    NodeKind.gesture => const GestureProps(),
    NodeKind.focusScope => FocusScopeProps(autofocus: reader.boolean()),
    NodeKind.mouseRegion => MouseRegionProps(opaque: reader.boolean()),
    NodeKind.keyboardListener => KeyboardListenerProps(
      autofocus: reader.boolean(),
      keyPolicy: _enumValue(
        KeyEventPolicy.values,
        reader.uint8(),
        'key event policy',
      ),
    ),
    NodeKind.semantics => _readSemanticsProps(reader),
    NodeKind.theme => ThemeProps(
      brightness: reader.themeBrightness(),
      colorSeedArgb: reader.uint32(),
    ),
    NodeKind.materialScaffold => MaterialScaffoldProps(
      hasAppBar: reader.boolean(),
    ),
    NodeKind.materialAppBar => MaterialAppBarProps(
      centerTitle: reader.boolean(),
    ),
    NodeKind.materialElevatedButton => MaterialButtonProps(
      variant: MaterialButtonVariant.elevated,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialTextButton => MaterialButtonProps(
      variant: MaterialButtonVariant.text,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialIconButton => MaterialButtonProps(
      variant: MaterialButtonVariant.icon,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialCheckbox => MaterialCheckboxProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
    ),
    NodeKind.materialSwitch => MaterialSwitchProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
    ),
    NodeKind.materialListTile => MaterialListTileProps(
      enabled: reader.boolean(),
      selected: reader.boolean(),
      hasSubtitle: reader.boolean(),
      hasLeading: reader.boolean(),
      hasTrailing: reader.boolean(),
    ),
    NodeKind.materialDivider => MaterialDividerProps(
      thickness: reader.finiteFloat64(),
    ),
    NodeKind.materialCard => MaterialCardProps(
      elevation: reader.finiteFloat64(),
    ),
    NodeKind.materialCircularProgressIndicator => MaterialProgressProps(
      value: reader.optionalFloat64(),
    ),
    NodeKind.cupertinoButton => CupertinoButtonProps(enabled: reader.boolean()),
    NodeKind.cupertinoSwitch => CupertinoSwitchProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
    ),
    NodeKind.textInput => _readTextInputProps(
      reader,
      protocolMinor: protocolMinor,
    ),
    NodeKind.overlay => OverlayProps(
      alignment: _enumValue(
        OverlayAlignment.values,
        reader.uint8(),
        'overlay alignment',
      ),
      dismissible: reader.boolean(),
    ),
    NodeKind.navigator => NavigatorProps(
      restorationScopeId: reader.optionalString(),
    ),
    NodeKind.page => () {
      final pageKey = reader.string();
      if (pageKey.isEmpty) {
        _fail(ProtocolErrorCode.invalidProps, 'Page key must not be empty');
      }
      return PageProps(
        pageKey: pageKey,
        transition: _enumValue(
          PageTransition.values,
          reader.uint8(),
          'page transition',
        ),
        canPop: reader.boolean(),
        restorationId: reader.optionalString(),
      );
    }(),
    NodeKind.safeArea => SafeAreaProps(
      left: reader.boolean(),
      top: reader.boolean(),
      right: reader.boolean(),
      bottom: reader.boolean(),
      minimum: EdgeInsetsValue(
        left: reader.finiteFloat64(),
        top: reader.finiteFloat64(),
        right: reader.finiteFloat64(),
        bottom: reader.finiteFloat64(),
      ),
    ),
    NodeKind.materialDialog => MaterialDialogProps(
      barrierDismissible: reader.boolean(),
    ),
    NodeKind.nativeWidget => _readNativeWidgetProps(reader),
  };

  static void _writeBindings(_Writer writer, List<EventBinding> bindings) {
    if (bindings.length > 0xffff) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Event binding count is outside u16',
      );
    }
    writer.uint16(bindings.length);
    for (final binding in bindings) {
      if (binding.eventTag < 0 || binding.eventTag > 0xffff) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Event tag ${binding.eventTag} is outside u16',
        );
      }
      _checkUint64('handler ID', binding.handlerId);
      writer
        ..uint16(binding.eventTag)
        ..uint64(binding.handlerId);
    }
  }

  static List<EventBinding> _readBindings(_Reader reader) {
    final count = reader.uint16();
    return List.unmodifiable([
      for (var index = 0; index < count; index += 1)
        EventBinding(eventTag: reader.uint16(), handlerId: reader.uint64()),
    ]);
  }

  static int _frameKindId(FrameKind kind) => switch (kind) {
    FrameKind.fullSnapshot => FrameKindId.fullSnapshot,
    FrameKind.incremental => FrameKindId.incrementalFrame,
  };

  static FrameKind _decodeFrameKind(int value) {
    if (value == FrameKindId.fullSnapshot) {
      return FrameKind.fullSnapshot;
    }
    if (value == FrameKindId.incrementalFrame) {
      return FrameKind.incremental;
    }
    _fail(ProtocolErrorCode.invalidFrameKind, 'Invalid frame kind $value');
  }

  static int _nodeKindId(NodeKind kind) => switch (kind) {
    NodeKind.empty => NodeKindId.empty,
    NodeKind.text => NodeKindId.text,
    NodeKind.richText => NodeKindId.richText,
    NodeKind.icon => NodeKindId.icon,
    NodeKind.image => NodeKindId.image,
    NodeKind.row => NodeKindId.row,
    NodeKind.column => NodeKindId.column,
    NodeKind.stack => NodeKindId.stack,
    NodeKind.button => NodeKindId.button,
    NodeKind.padding => NodeKindId.padding,
    NodeKind.align => NodeKindId.align,
    NodeKind.center => NodeKindId.center,
    NodeKind.sizedBox => NodeKindId.sizedBox,
    NodeKind.constrainedBox => NodeKindId.constrainedBox,
    NodeKind.decoratedBox => NodeKindId.decoratedBox,
    NodeKind.clip => NodeKindId.clip,
    NodeKind.opacity => NodeKindId.opacity,
    NodeKind.animatedOpacity => NodeKindId.animatedOpacity,
    NodeKind.transform => NodeKindId.transform,
    NodeKind.scrollView => NodeKindId.scrollView,
    NodeKind.listView => NodeKindId.listView,
    NodeKind.gesture => NodeKindId.gesture,
    NodeKind.focusScope => NodeKindId.focusScope,
    NodeKind.mouseRegion => NodeKindId.mouseRegion,
    NodeKind.keyboardListener => NodeKindId.keyboardListener,
    NodeKind.pressable => NodeKindId.pressable,
    NodeKind.semantics => NodeKindId.semantics,
    NodeKind.theme => NodeKindId.theme,
    NodeKind.materialScaffold => NodeKindId.materialScaffold,
    NodeKind.materialAppBar => NodeKindId.materialAppBar,
    NodeKind.materialElevatedButton => NodeKindId.materialElevatedButton,
    NodeKind.materialTextButton => NodeKindId.materialTextButton,
    NodeKind.materialIconButton => NodeKindId.materialIconButton,
    NodeKind.materialCheckbox => NodeKindId.materialCheckbox,
    NodeKind.materialSwitch => NodeKindId.materialSwitch,
    NodeKind.materialListTile => NodeKindId.materialListTile,
    NodeKind.materialDivider => NodeKindId.materialDivider,
    NodeKind.materialCard => NodeKindId.materialCard,
    NodeKind.materialCircularProgressIndicator =>
      NodeKindId.materialCircularProgressIndicator,
    NodeKind.cupertinoButton => NodeKindId.cupertinoButton,
    NodeKind.cupertinoSwitch => NodeKindId.cupertinoSwitch,
    NodeKind.textInput => NodeKindId.textInput,
    NodeKind.overlay => NodeKindId.overlay,
    NodeKind.navigator => NodeKindId.navigator,
    NodeKind.page => NodeKindId.page,
    NodeKind.safeArea => NodeKindId.safeArea,
    NodeKind.environmentBoundary => NodeKindId.environmentBoundary,
    NodeKind.materialDialog => NodeKindId.materialDialog,
    NodeKind.nativeWidget => NodeKindId.nativeWidget,
  };

  static NodeKind _readNodeKind(_Reader reader) {
    final value = reader.uint16();
    if (value == NodeKindId.empty) return NodeKind.empty;
    if (value == NodeKindId.text) return NodeKind.text;
    if (value == NodeKindId.richText) return NodeKind.richText;
    if (value == NodeKindId.icon) return NodeKind.icon;
    if (value == NodeKindId.image) return NodeKind.image;
    if (value == NodeKindId.row) return NodeKind.row;
    if (value == NodeKindId.column) return NodeKind.column;
    if (value == NodeKindId.stack) return NodeKind.stack;
    if (value == NodeKindId.button) return NodeKind.button;
    if (value == NodeKindId.padding) return NodeKind.padding;
    if (value == NodeKindId.align) return NodeKind.align;
    if (value == NodeKindId.center) return NodeKind.center;
    if (value == NodeKindId.sizedBox) return NodeKind.sizedBox;
    if (value == NodeKindId.constrainedBox) return NodeKind.constrainedBox;
    if (value == NodeKindId.decoratedBox) return NodeKind.decoratedBox;
    if (value == NodeKindId.clip) return NodeKind.clip;
    if (value == NodeKindId.opacity) return NodeKind.opacity;
    if (value == NodeKindId.animatedOpacity) {
      return NodeKind.animatedOpacity;
    }
    if (value == NodeKindId.transform) return NodeKind.transform;
    if (value == NodeKindId.scrollView) return NodeKind.scrollView;
    if (value == NodeKindId.listView) return NodeKind.listView;
    if (value == NodeKindId.gesture) return NodeKind.gesture;
    if (value == NodeKindId.focusScope) return NodeKind.focusScope;
    if (value == NodeKindId.mouseRegion) return NodeKind.mouseRegion;
    if (value == NodeKindId.keyboardListener) {
      return NodeKind.keyboardListener;
    }
    if (value == NodeKindId.pressable) return NodeKind.pressable;
    if (value == NodeKindId.semantics) return NodeKind.semantics;
    if (value == NodeKindId.theme) return NodeKind.theme;
    if (value == NodeKindId.materialScaffold) {
      return NodeKind.materialScaffold;
    }
    if (value == NodeKindId.materialAppBar) return NodeKind.materialAppBar;
    if (value == NodeKindId.materialElevatedButton) {
      return NodeKind.materialElevatedButton;
    }
    if (value == NodeKindId.materialTextButton) {
      return NodeKind.materialTextButton;
    }
    if (value == NodeKindId.materialIconButton) {
      return NodeKind.materialIconButton;
    }
    if (value == NodeKindId.materialCheckbox) {
      return NodeKind.materialCheckbox;
    }
    if (value == NodeKindId.materialSwitch) return NodeKind.materialSwitch;
    if (value == NodeKindId.materialListTile) return NodeKind.materialListTile;
    if (value == NodeKindId.materialDivider) return NodeKind.materialDivider;
    if (value == NodeKindId.materialCard) return NodeKind.materialCard;
    if (value == NodeKindId.materialCircularProgressIndicator) {
      return NodeKind.materialCircularProgressIndicator;
    }
    if (value == NodeKindId.cupertinoButton) return NodeKind.cupertinoButton;
    if (value == NodeKindId.cupertinoSwitch) return NodeKind.cupertinoSwitch;
    if (value == NodeKindId.textInput) return NodeKind.textInput;
    if (value == NodeKindId.overlay) return NodeKind.overlay;
    if (value == NodeKindId.navigator) return NodeKind.navigator;
    if (value == NodeKindId.page) return NodeKind.page;
    if (value == NodeKindId.safeArea) return NodeKind.safeArea;
    if (value == NodeKindId.environmentBoundary) {
      return NodeKind.environmentBoundary;
    }
    if (value == NodeKindId.materialDialog) return NodeKind.materialDialog;
    if (value == NodeKindId.nativeWidget) return NodeKind.nativeWidget;
    _fail(ProtocolErrorCode.unknownNodeKind, 'Unknown node kind $value');
  }

  static bool _isKnownSemanticOperation(int opcode) =>
      opcode == OperationId.createNode ||
      opcode == OperationId.updateProps ||
      opcode == OperationId.updateEventBindings ||
      opcode == OperationId.setChildren ||
      opcode == OperationId.setRoot ||
      opcode == OperationId.dropNode ||
      opcode == OperationId.hostRequest ||
      opcode == OperationId.runtimeNotification;
}

void _writeTextProps(_Writer writer, TextProps props) {
  writer.string(props.value);
  final style = props.style;
  if (style == null) {
    writer.uint8(0);
  } else {
    for (final entry in [
      (style.fontSize, 'Text font size'),
      (style.lineHeight, 'Text line height'),
    ]) {
      final value = entry.$1;
      if (value != null && (!value.isFinite || value <= 0)) {
        _fail(ProtocolErrorCode.invalidProps, '${entry.$2} must be positive');
      }
    }
    writer
      ..uint8(1)
      ..optionalFloat64(style.fontSize);
    if (style.fontWeight == null) {
      writer.uint8(0);
    } else {
      writer
        ..uint8(1)
        ..uint8(style.fontWeight!.index);
    }
    writer.optionalFloat64(style.lineHeight);
    _writeOptionalArgb32(writer, style.colorArgb);
  }
  writer.uint8(props.textAlign.index);
  if (props.maxLines == null) {
    writer.uint8(0);
  } else {
    if (props.maxLines! <= 0) {
      _fail(ProtocolErrorCode.invalidProps, 'Text max lines must be positive');
    }
    writer
      ..uint8(1)
      ..uint32(props.maxLines!);
  }
  writer.uint8(props.overflow.index);
}

const _styledTextProtocolMinor = 13;

TextProps _readTextProps(_Reader reader, {required int protocolMinor}) {
  final value = reader.string();
  if (protocolMinor < _styledTextProtocolMinor) {
    return TextProps(value);
  }
  final style = switch (reader.uint8()) {
    0 => null,
    1 => TextStyleValue(
      fontSize: _readPositiveOptionalFloat(reader, 'Text font size'),
      fontWeight: switch (reader.uint8()) {
        0 => null,
        1 => _enumValue(
          TextFontWeight.values,
          reader.uint8(),
          'text font weight',
        ),
        final tag => _fail(
          ProtocolErrorCode.invalidProps,
          'Invalid optional text font weight tag $tag',
        ),
      },
      lineHeight: _readPositiveOptionalFloat(reader, 'Text line height'),
      colorArgb: _readOptionalArgb32(reader),
    ),
    final tag => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional text style tag $tag',
    ),
  };
  final textAlign = _enumValue(
    TextAlignValue.values,
    reader.uint8(),
    'text alignment',
  );
  final maxLines = switch (reader.uint8()) {
    0 => null,
    1 => reader.uint32(),
    final tag => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional text max lines tag $tag',
    ),
  };
  if (maxLines == 0) {
    _fail(ProtocolErrorCode.invalidProps, 'Text max lines must be positive');
  }
  final overflow = _enumValue(
    TextOverflowValue.values,
    reader.uint8(),
    'text overflow',
  );
  return TextProps(
    value,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

double? _readPositiveOptionalFloat(_Reader reader, String label) {
  final value = reader.optionalFloat64();
  if (value != null && value <= 0) {
    _fail(ProtocolErrorCode.invalidProps, '$label must be positive');
  }
  return value;
}

int _fieldMask(int propertyId) => 1 << (propertyId - 1);

int _changedFields(UiProps props) => switch (props) {
  EmptyProps() ||
  LinearProps() ||
  GestureProps() ||
  EnvironmentBoundaryProps() => 0,
  TextProps() =>
    _fieldMask(TextPropId.value) |
        _fieldMask(TextPropId.textStyle) |
        _fieldMask(TextPropId.textAlign) |
        _fieldMask(TextPropId.maxLines) |
        _fieldMask(TextPropId.overflow),
  RichTextProps() => _fieldMask(RichTextPropId.spans),
  IconProps() =>
    _fieldMask(IconPropId.codePoint) |
        _fieldMask(IconPropId.fontFamily) |
        _fieldMask(IconPropId.size) |
        _fieldMask(IconPropId.color),
  ImageProps() =>
    _fieldMask(ImagePropId.uri) |
        _fieldMask(ImagePropId.fit) |
        _fieldMask(ImagePropId.width) |
        _fieldMask(ImagePropId.height),
  ButtonProps() => _fieldMask(ButtonPropId.enabled),
  PressableProps() =>
    _fieldMask(PressablePropId.overlayColor) |
        _fieldMask(PressablePropId.releaseDelayMs),
  PaddingProps() => _fieldMask(PaddingPropId.insets),
  AlignProps() => _fieldMask(AlignPropId.alignment),
  CenterProps() =>
    _fieldMask(CenterPropId.widthFactor) |
        _fieldMask(CenterPropId.heightFactor),
  SizedBoxProps() =>
    _fieldMask(SizedBoxPropId.width) | _fieldMask(SizedBoxPropId.height),
  ConstrainedBoxProps() =>
    _fieldMask(ConstrainedBoxPropId.minWidth) |
        _fieldMask(ConstrainedBoxPropId.maxWidth) |
        _fieldMask(ConstrainedBoxPropId.minHeight) |
        _fieldMask(ConstrainedBoxPropId.maxHeight),
  DecoratedBoxProps() =>
    _fieldMask(DecoratedBoxPropId.background) |
        _fieldMask(DecoratedBoxPropId.borderRadius),
  ClipProps() => _fieldMask(ClipPropId.behavior),
  OpacityProps() => _fieldMask(OpacityPropId.opacity),
  AnimatedOpacityProps() =>
    _fieldMask(AnimatedOpacityPropId.opacity) |
        _fieldMask(AnimatedOpacityPropId.animationId) |
        _fieldMask(AnimatedOpacityPropId.durationMs) |
        _fieldMask(AnimatedOpacityPropId.curve),
  TransformProps() => _fieldMask(TransformPropId.matrix4),
  ScrollViewProps() =>
    _fieldMask(ScrollViewPropId.axis) | _fieldMask(ScrollViewPropId.reverse),
  ListViewProps() =>
    _fieldMask(ListViewPropId.axis) | _fieldMask(ListViewPropId.reverse),
  FocusScopeProps() => _fieldMask(FocusScopePropId.autofocus),
  MouseRegionProps() => _fieldMask(MouseRegionPropId.opaque),
  KeyboardListenerProps() =>
    _fieldMask(KeyboardListenerPropId.autofocus) |
        _fieldMask(KeyboardListenerPropId.keyPolicy),
  SemanticsProps() =>
    _fieldMask(SemanticsPropId.label) |
        _fieldMask(SemanticsPropId.hint) |
        _fieldMask(SemanticsPropId.value) |
        _fieldMask(SemanticsPropId.role) |
        _fieldMask(SemanticsPropId.enabled) |
        _fieldMask(SemanticsPropId.selected) |
        _fieldMask(SemanticsPropId.checked) |
        _fieldMask(SemanticsPropId.focusable) |
        _fieldMask(SemanticsPropId.obscured) |
        _fieldMask(SemanticsPropId.liveRegion) |
        _fieldMask(SemanticsPropId.headingLevel) |
        _fieldMask(SemanticsPropId.sortKey) |
        _fieldMask(SemanticsPropId.actions),
  ThemeProps() =>
    _fieldMask(ThemePropId.brightness) | _fieldMask(ThemePropId.colorSeed),
  MaterialScaffoldProps() => _fieldMask(MaterialScaffoldPropId.hasAppBar),
  MaterialAppBarProps() => _fieldMask(MaterialAppBarPropId.centerTitle),
  MaterialButtonProps(:final variant) => switch (variant) {
    MaterialButtonVariant.elevated =>
      _fieldMask(MaterialElevatedButtonPropId.enabled) |
          _fieldMask(MaterialElevatedButtonPropId.autofocus),
    MaterialButtonVariant.text =>
      _fieldMask(MaterialTextButtonPropId.enabled) |
          _fieldMask(MaterialTextButtonPropId.autofocus),
    MaterialButtonVariant.icon =>
      _fieldMask(MaterialIconButtonPropId.enabled) |
          _fieldMask(MaterialIconButtonPropId.autofocus),
  },
  MaterialCheckboxProps() =>
    _fieldMask(MaterialCheckboxPropId.value) |
        _fieldMask(MaterialCheckboxPropId.enabled),
  MaterialSwitchProps() =>
    _fieldMask(MaterialSwitchPropId.value) |
        _fieldMask(MaterialSwitchPropId.enabled),
  MaterialListTileProps() =>
    _fieldMask(MaterialListTilePropId.enabled) |
        _fieldMask(MaterialListTilePropId.selected) |
        _fieldMask(MaterialListTilePropId.hasSubtitle) |
        _fieldMask(MaterialListTilePropId.hasLeading) |
        _fieldMask(MaterialListTilePropId.hasTrailing),
  MaterialDividerProps() => _fieldMask(MaterialDividerPropId.thickness),
  MaterialCardProps() => _fieldMask(MaterialCardPropId.elevation),
  MaterialProgressProps() => _fieldMask(
    MaterialCircularProgressIndicatorPropId.value,
  ),
  CupertinoButtonProps() => _fieldMask(CupertinoButtonPropId.enabled),
  CupertinoSwitchProps() =>
    _fieldMask(CupertinoSwitchPropId.value) |
        _fieldMask(CupertinoSwitchPropId.enabled),
  TextInputProps() =>
    _fieldMask(TextInputPropId.sessionId) |
        _fieldMask(TextInputPropId.documentRevision) |
        _fieldMask(TextInputPropId.value) |
        _fieldMask(TextInputPropId.enabled) |
        _fieldMask(TextInputPropId.readOnly) |
        _fieldMask(TextInputPropId.obscureText) |
        _fieldMask(TextInputPropId.keyboardType) |
        _fieldMask(TextInputPropId.inputAction) |
        _fieldMask(TextInputPropId.acceptedLocalRevision) |
        _fieldMask(TextInputPropId.updateMode) |
        _fieldMask(TextInputPropId.autofocus) |
        _fieldMask(TextInputPropId.maxUtf8Bytes),
  OverlayProps() =>
    _fieldMask(OverlayPropId.alignment) | _fieldMask(OverlayPropId.dismissible),
  NavigatorProps() => _fieldMask(NavigatorPropId.restorationScopeId),
  PageProps() =>
    _fieldMask(PagePropId.pageKey) |
        _fieldMask(PagePropId.transition) |
        _fieldMask(PagePropId.canPop) |
        _fieldMask(PagePropId.restorationId),
  SafeAreaProps() =>
    _fieldMask(SafeAreaPropId.left) |
        _fieldMask(SafeAreaPropId.top) |
        _fieldMask(SafeAreaPropId.right) |
        _fieldMask(SafeAreaPropId.bottom) |
        _fieldMask(SafeAreaPropId.minimum),
  MaterialDialogProps() => _fieldMask(MaterialDialogPropId.barrierDismissible),
  NativeWidgetProps() =>
    _fieldMask(NativeWidgetPropId.kindId) |
        _fieldMask(NativeWidgetPropId.version) |
        _fieldMask(NativeWidgetPropId.capabilities) |
        _fieldMask(NativeWidgetPropId.payload),
};

void _writeNativeWidgetProps(_Writer writer, NativeWidgetProps props) {
  if (props.kindId <= 0 || props.kindId > 0xffffffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Native widget kind ID must be in 1..4294967295',
    );
  }
  if (props.version <= 0 || props.version > 0xffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Native widget version must be in 1..65535',
    );
  }
  _checkUint64('native widget capabilities', props.capabilityBits);
  writer
    ..uint32(props.kindId)
    ..uint16(props.version)
    ..uint64(props.capabilityBits)
    ..uint32(props.payload.length)
    ..raw(props.payload);
}

NativeWidgetProps _readNativeWidgetProps(_Reader reader) {
  final kindId = reader.uint32();
  final version = reader.uint16();
  if (kindId == 0 || version == 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Native widget kind ID and version must be positive',
    );
  }
  final capabilityBits = reader.uint64();
  return NativeWidgetProps(
    kindId: kindId,
    version: version,
    capabilityBits: capabilityBits,
    payload: reader.bytes(reader.uint32()),
  );
}

void _writePressableProps(_Writer writer, PressableProps props) {
  if (props.releaseDelayMs < 0 || props.releaseDelayMs > 100) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Pressable release delay must be in 0..100ms',
    );
  }
  writer
    ..uint32(props.overlayColorArgb)
    ..uint16(props.releaseDelayMs);
}

void _writeRuntimeStats(_Writer writer, RuntimeStatsOperation stats) {
  final uint32Values = [
    stats.eventBatchSize,
    stats.patchCount,
    stats.patchBytes,
    stats.fullSnapshotCount,
    stats.resyncCount,
  ];
  if (uint32Values.any((value) => value < 0 || value > 0xffffffff)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Runtime stats u32 field is outside range',
    );
  }
  final durations = [
    stats.bonsaiFlushNanoseconds,
    stats.resultReadNanoseconds,
    stats.reconcileNanoseconds,
    stats.encodeNanoseconds,
    stats.lifecycleNanoseconds,
  ];
  for (final duration in durations) {
    _checkUint64('runtime stats duration', duration);
  }
  writer
    ..uint32(stats.eventBatchSize)
    ..uint64(stats.bonsaiFlushNanoseconds)
    ..uint64(stats.resultReadNanoseconds)
    ..uint64(stats.reconcileNanoseconds)
    ..uint64(stats.encodeNanoseconds)
    ..uint32(stats.patchCount)
    ..uint32(stats.patchBytes)
    ..uint64(stats.lifecycleNanoseconds)
    ..uint32(stats.fullSnapshotCount)
    ..uint32(stats.resyncCount);
}

RuntimeStatsOperation _readRuntimeStats(_Reader reader) =>
    RuntimeStatsOperation(
      eventBatchSize: reader.uint32(),
      bonsaiFlushNanoseconds: reader.uint64(),
      resultReadNanoseconds: reader.uint64(),
      reconcileNanoseconds: reader.uint64(),
      encodeNanoseconds: reader.uint64(),
      patchCount: reader.uint32(),
      patchBytes: reader.uint32(),
      lifecycleNanoseconds: reader.uint64(),
      fullSnapshotCount: reader.uint32(),
      resyncCount: reader.uint32(),
    );

void _writeHostRequest(_Writer writer, int requestId, HostRequest request) {
  _checkUint64('host request ID', requestId);
  writer.uint64(requestId);
  switch (request) {
    case ClipboardReadRequest():
      writer.uint16(HostRequestId.clipboardRead);
    case ClipboardWriteRequest(:final text):
      writer
        ..uint16(HostRequestId.clipboardWrite)
        ..string(text);
    case OpenUrlRequest(:final uri):
      writer
        ..uint16(HostRequestId.openUrl)
        ..string(uri);
    case PickFileRequest(:final allowedExtensions, :final allowMultiple):
      if (allowedExtensions.length > 0xffff) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'File extension count is outside u16',
        );
      }
      writer
        ..uint16(HostRequestId.pickFile)
        ..uint16(allowedExtensions.length);
      for (final extension in allowedExtensions) {
        writer.string(extension);
      }
      writer.uint8(allowMultiple ? 1 : 0);
    case SaveFileRequest(:final suggestedName, :final data):
      writer
        ..uint16(HostRequestId.saveFile)
        ..optionalString(suggestedName)
        ..uint32(data.length)
        ..raw(data);
    case RequestFocusRequest(:final nodeId):
      _checkUint64('focus node ID', nodeId);
      writer
        ..uint16(HostRequestId.requestFocus)
        ..uint64(nodeId);
    case ClearFocusRequest():
      writer.uint16(HostRequestId.clearFocus);
    case ScrollToRequest(:final nodeId, :final alignment, :final animated):
      _checkUint64('scroll node ID', nodeId);
      writer
        ..uint16(HostRequestId.scrollTo)
        ..uint64(nodeId)
        ..float64(alignment)
        ..uint8(animated ? 1 : 0);
    case SetWindowTitleRequest(:final title):
      writer
        ..uint16(HostRequestId.setWindowTitle)
        ..string(title);
    case SetWindowSizeRequest(:final width, :final height):
      if (width <= 0 || height <= 0) {
        _fail(ProtocolErrorCode.invalidProps, 'Window size must be positive');
      }
      writer
        ..uint16(HostRequestId.setWindowSize)
        ..float64(width)
        ..float64(height);
    case ShowNativeMenuRequest(:final items):
      if (items.length > 0xffff) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Native menu item count is outside u16',
        );
      }
      writer
        ..uint16(HostRequestId.showNativeMenu)
        ..uint16(items.length);
      for (final item in items) {
        writer
          ..string(item.itemId)
          ..string(item.label)
          ..uint8(item.enabled ? 1 : 0);
      }
    case HapticFeedbackRequest(:final kind):
      writer
        ..uint16(HostRequestId.hapticFeedback)
        ..uint8(kind.index);
    case PlatformInformationRequest():
      writer.uint16(HostRequestId.platformInformation);
    case MeasureLayoutRequest(:final nodeId):
      _checkUint64('layout node ID', nodeId);
      writer
        ..uint16(HostRequestId.measureLayout)
        ..uint64(nodeId);
  }
}

HostRequest _readHostRequest(_Reader reader, int requestKind) {
  if (requestKind == HostRequestId.clipboardRead) {
    return const ClipboardReadRequest();
  }
  if (requestKind == HostRequestId.clipboardWrite) {
    return ClipboardWriteRequest(reader.string());
  }
  if (requestKind == HostRequestId.openUrl) {
    return OpenUrlRequest(reader.string());
  }
  if (requestKind == HostRequestId.pickFile) {
    final count = reader.uint16();
    final extensions = [
      for (var index = 0; index < count; index += 1) reader.string(),
    ];
    return PickFileRequest(
      allowedExtensions: List.unmodifiable(extensions),
      allowMultiple: reader.boolean(),
    );
  }
  if (requestKind == HostRequestId.saveFile) {
    final suggestedName = reader.optionalString();
    final data = reader.bytes(reader.uint32());
    return SaveFileRequest(
      suggestedName: suggestedName,
      data: List.unmodifiable(data),
    );
  }
  if (requestKind == HostRequestId.requestFocus) {
    return RequestFocusRequest(reader.uint64());
  }
  if (requestKind == HostRequestId.clearFocus) {
    return const ClearFocusRequest();
  }
  if (requestKind == HostRequestId.scrollTo) {
    return ScrollToRequest(
      nodeId: reader.uint64(),
      alignment: reader.finiteFloat64(),
      animated: reader.boolean(),
    );
  }
  if (requestKind == HostRequestId.setWindowTitle) {
    return SetWindowTitleRequest(reader.string());
  }
  if (requestKind == HostRequestId.setWindowSize) {
    final width = reader.finiteFloat64();
    final height = reader.finiteFloat64();
    if (width <= 0 || height <= 0) {
      _fail(ProtocolErrorCode.invalidProps, 'Window size must be positive');
    }
    return SetWindowSizeRequest(width: width, height: height);
  }
  if (requestKind == HostRequestId.showNativeMenu) {
    final count = reader.uint16();
    return ShowNativeMenuRequest(
      List.unmodifiable([
        for (var index = 0; index < count; index += 1)
          NativeMenuItemValue(
            itemId: reader.string(),
            label: reader.string(),
            enabled: reader.boolean(),
          ),
      ]),
    );
  }
  if (requestKind == HostRequestId.hapticFeedback) {
    return HapticFeedbackRequest(
      _enumValue(HapticKind.values, reader.uint8(), 'haptic kind'),
    );
  }
  if (requestKind == HostRequestId.platformInformation) {
    return const PlatformInformationRequest();
  }
  if (requestKind == HostRequestId.measureLayout) {
    return MeasureLayoutRequest(reader.uint64());
  }
  _fail(
    ProtocolErrorCode.invalidProps,
    'Unknown host request kind $requestKind',
  );
}

int _semanticsActionBits(Set<SemanticsActionValue> actions) {
  var bits = 0;
  for (final action in actions) {
    bits |= 1 << (action.wireId - 1);
  }
  return bits;
}

void _writeSemanticsProps(_Writer writer, SemanticsProps props) {
  final headingLevel = props.headingLevel;
  if (headingLevel != null && (headingLevel < 1 || headingLevel > 6)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Semantics heading level must be between 1 and 6',
    );
  }
  final sortKey = props.sortKey;
  if (sortKey != null && !sortKey.isFinite) {
    _fail(ProtocolErrorCode.invalidProps, 'Semantics sort key must be finite');
  }
  writer
    ..optionalString(props.label)
    ..optionalString(props.hint)
    ..optionalString(props.value)
    ..uint8(props.role.wireId)
    ..optionalBool(props.enabled)
    ..optionalBool(props.selected)
    ..optionalBool(props.checked)
    ..optionalBool(props.focusable)
    ..uint8(props.obscured ? 1 : 0)
    ..uint8(props.liveRegion ? 1 : 0)
    ..optionalUint8(headingLevel)
    ..optionalFloat64(sortKey)
    ..uint32(_semanticsActionBits(props.actions));
}

SemanticsProps _readSemanticsProps(_Reader reader) {
  final label = reader.optionalString();
  final hint = reader.optionalString();
  final value = reader.optionalString();
  final role = _enumValue(
    SemanticsRoleValue.values,
    reader.uint8(),
    'semantics role',
  );
  final enabled = reader.optionalBool();
  final selected = reader.optionalBool();
  final checked = reader.optionalBool();
  final focusable = reader.optionalBool();
  final obscured = reader.boolean();
  final liveRegion = reader.boolean();
  final headingLevel = reader.optionalUint8();
  if (headingLevel != null && (headingLevel < 1 || headingLevel > 6)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Semantics heading level must be between 1 and 6',
    );
  }
  final sortKey = reader.optionalFloat64();
  final actionBits = reader.uint32();
  final knownMask = (1 << SemanticsActionValue.values.length) - 1;
  if ((actionBits & ~knownMask) != 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Semantics actions contain unknown bits',
    );
  }
  final actions = {
    for (final action in SemanticsActionValue.values)
      if (actionBits & (1 << (action.wireId - 1)) != 0) action,
  };
  return SemanticsProps(
    label: label,
    hint: hint,
    value: value,
    role: role,
    enabled: enabled,
    selected: selected,
    checked: checked,
    focusable: focusable,
    obscured: obscured,
    liveRegion: liveRegion,
    headingLevel: headingLevel,
    sortKey: sortKey,
    actions: Set.unmodifiable(actions),
  );
}

void _writeInsets(_Writer writer, EdgeInsetsValue insets) {
  final values = [insets.left, insets.top, insets.right, insets.bottom];
  if (values.any((value) => !value.isFinite || value < 0)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Padding insets must be finite and non-negative',
    );
  }
  for (final value in values) {
    writer.float64(value);
  }
}

void _writeOptionalArgb32(_Writer writer, int? value) {
  if (value == null) {
    writer.uint8(0);
  } else {
    writer
      ..uint8(1)
      ..uint32(value);
  }
}

int? _readOptionalArgb32(_Reader reader) => switch (reader.uint8()) {
  0 => null,
  1 => reader.uint32(),
  final value => _fail(
    ProtocolErrorCode.invalidProps,
    'Invalid optional ARGB tag $value',
  ),
};

void _writeAnimation(_Writer writer, AnimationIntent animation) {
  _checkUint64('animation ID', animation.id);
  if (animation.durationMilliseconds < 0 ||
      animation.durationMilliseconds > 0xffffffff) {
    _fail(ProtocolErrorCode.invalidProps, 'Animation duration is outside u32');
  }
  writer
    ..uint64(animation.id)
    ..uint32(animation.durationMilliseconds)
    ..uint8(animation.curve.index);
}

AnimationIntent _readAnimation(_Reader reader) => AnimationIntent(
  id: reader.uint64(),
  durationMilliseconds: reader.uint32(),
  curve: _enumValue(
    AnimationCurveValue.values,
    reader.uint8(),
    'animation curve',
  ),
);

void _writeStringList(_Writer writer, List<String> values, String label) {
  if (values.length > 0xffff) {
    _fail(ProtocolErrorCode.invalidProps, '$label count is outside u16');
  }
  writer.uint16(values.length);
  for (final value in values) {
    writer.string(value);
  }
}

List<String> _readStringList(_Reader reader) {
  final count = reader.uint16();
  return List.unmodifiable([
    for (var index = 0; index < count; index += 1) reader.string(),
  ]);
}

void _writeTextInputProps(_Writer writer, TextInputProps props) {
  _checkUint64('text session ID', props.sessionId);
  _checkUint64('document revision', props.documentRevision);
  _checkUint64('accepted local revision', props.acceptedLocalRevision);
  writer
    ..uint64(props.sessionId)
    ..uint64(props.documentRevision)
    ..string(props.value.text);
  _writeTextRange(writer, props.value.text, props.value.selection);
  final composing = props.value.composing;
  if (composing == null) {
    writer.uint8(0);
  } else {
    writer.uint8(1);
    _writeTextRange(writer, props.value.text, composing);
  }
  writer
    ..uint8(props.enabled ? 1 : 0)
    ..uint8(props.readOnly ? 1 : 0)
    ..uint8(props.obscureText ? 1 : 0)
    ..uint8(props.keyboardType.index)
    ..uint8(props.inputAction.index)
    ..uint64(props.acceptedLocalRevision)
    ..uint8(props.updateMode.index)
    ..uint8(props.autofocus ? 1 : 0);
  final maxUtf8Bytes = props.maxUtf8Bytes;
  if (maxUtf8Bytes == null) {
    writer.uint8(0);
  } else {
    if (maxUtf8Bytes <= 0 || maxUtf8Bytes > ProtocolLimits.maxStringBytes) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Text input max UTF-8 bytes must be within '
        '1..${ProtocolLimits.maxStringBytes}',
      );
    }
    writer
      ..uint8(1)
      ..uint32(maxUtf8Bytes);
  }
}

const _textInputUtf8LimitProtocolMinor = 15;

TextInputProps _readTextInputProps(
  _Reader reader, {
  required int protocolMinor,
}) {
  final sessionId = reader.uint64();
  final documentRevision = reader.uint64();
  final text = reader.string();
  final selection = _readTextRange(reader, text);
  final composing = switch (reader.uint8()) {
    0 => null,
    1 => _readTextRange(reader, text),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid composing tag $value',
    ),
  };
  final enabled = reader.boolean();
  final readOnly = reader.boolean();
  final obscureText = reader.boolean();
  final keyboardType = _enumValue(
    TextKeyboardType.values,
    reader.uint8(),
    'text keyboard type',
  );
  final inputAction = _enumValue(
    TextInputActionKind.values,
    reader.uint8(),
    'text input action',
  );
  final acceptedLocalRevision = reader.uint64();
  final updateMode = _enumValue(
    TextUpdateMode.values,
    reader.uint8(),
    'text update mode',
  );
  final autofocus = reader.boolean();
  final maxUtf8Bytes = protocolMinor < _textInputUtf8LimitProtocolMinor
      ? null
      : switch (reader.uint8()) {
          0 => null,
          1 => reader.uint32(),
          final tag => _fail(
            ProtocolErrorCode.invalidProps,
            'Invalid optional text input max UTF-8 bytes tag $tag',
          ),
        };
  if (maxUtf8Bytes != null &&
      (maxUtf8Bytes == 0 || maxUtf8Bytes > ProtocolLimits.maxStringBytes)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Text input max UTF-8 bytes is outside the protocol string limit',
    );
  }
  return TextInputProps(
    sessionId: sessionId,
    documentRevision: documentRevision,
    value: TextEditingStateValue(
      text: text,
      selection: selection,
      composing: composing,
    ),
    enabled: enabled,
    readOnly: readOnly,
    obscureText: obscureText,
    keyboardType: keyboardType,
    inputAction: inputAction,
    acceptedLocalRevision: acceptedLocalRevision,
    updateMode: updateMode,
    autofocus: autofocus,
    maxUtf8Bytes: maxUtf8Bytes,
  );
}

T _enumValue<T>(List<T> values, int index, String label) {
  if (index >= values.length) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid $label $index');
  }
  return values[index];
}

void _writeTextRange(_Writer writer, String text, TextRangeValue range) {
  if (range.startUtf16 > range.endUtf16 ||
      !_isUtf16Boundary(text, range.startUtf16) ||
      !_isUtf16Boundary(text, range.endUtf16)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Text range is not on ordered UTF-16 boundaries',
    );
  }
  writer
    ..uint32(range.startUtf16)
    ..uint32(range.endUtf16);
}

TextRangeValue _readTextRange(_Reader reader, String text) {
  final range = TextRangeValue(
    startUtf16: reader.uint32(),
    endUtf16: reader.uint32(),
  );
  if (range.startUtf16 > range.endUtf16 ||
      !_isUtf16Boundary(text, range.startUtf16) ||
      !_isUtf16Boundary(text, range.endUtf16)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Text range is not on ordered UTF-16 boundaries',
    );
  }
  return range;
}

bool _isUtf16Boundary(String text, int offset) {
  if (offset < 0 || offset > text.length) return false;
  if (offset == 0 || offset == text.length) return true;
  final previous = text.codeUnitAt(offset - 1);
  final next = text.codeUnitAt(offset);
  return !(previous >= 0xd800 &&
      previous <= 0xdbff &&
      next >= 0xdc00 &&
      next <= 0xdfff);
}

final class _Writer {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void uint8(int value) => _builder.add([value & 0xff]);

  void uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void uint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void float64(double value) {
    if (!value.isFinite) {
      _fail(ProtocolErrorCode.invalidProps, 'Float property must be finite');
    }
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void raw(List<int> bytes) => _builder.add(bytes);

  void string(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > ProtocolLimits.maxStringBytes) {
      _fail(
        ProtocolErrorCode.stringTooLarge,
        'String is ${bytes.length} bytes',
      );
    }
    uint32(bytes.length);
    raw(bytes);
  }

  void optionalString(String? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      string(value);
    }
  }

  void optionalBool(bool? value) {
    uint8(switch (value) {
      null => 0,
      false => 1,
      true => 2,
    });
  }

  void optionalUint8(int? value) {
    if (value == null) {
      uint8(0);
    } else {
      if (value < 0 || value > 0xff) {
        _fail(ProtocolErrorCode.invalidProps, 'Optional u8 is outside u8');
      }
      uint8(1);
      uint8(value);
    }
  }

  void optionalFloat64(double? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      float64(value);
    }
  }

  void envelope(int opcode, void Function(_Writer) writeBody) {
    final body = _Writer();
    writeBody(body);
    final bodyBytes = body.takeBytes();
    uint8(opcode);
    uint32(bodyBytes.length);
    raw(bodyBytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

final class _Reader {
  _Reader.root(Uint8List bytes)
    : _bytes = bytes,
      _data = ByteData.sublistView(bytes),
      _position = 0,
      _limit = bytes.length;

  _Reader._slice(this._bytes, this._data, this._position, this._limit);

  final Uint8List _bytes;
  final ByteData _data;
  int _position;
  final int _limit;

  int get remaining => _limit - _position;
  bool get isDone => _position == _limit;

  int uint8() {
    _require(1);
    return _bytes[_position++];
  }

  int uint16() {
    _require(2);
    final result = _data.getUint16(_position, Endian.little);
    _position += 2;
    return result;
  }

  int uint32() {
    _require(4);
    final result = _data.getUint32(_position, Endian.little);
    _position += 4;
    return result;
  }

  int uint64() {
    _require(8);
    final result = _data.getUint64(_position, Endian.little);
    _position += 8;
    if (result > 0x7fffffffffffffff) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'u64 value exceeds the supported positive int64 range',
      );
    }
    return result;
  }

  double finiteFloat64() {
    _require(8);
    final result = _data.getFloat64(_position, Endian.little);
    _position += 8;
    if (!result.isFinite) {
      _fail(ProtocolErrorCode.invalidProps, 'Float property must be finite');
    }
    return result;
  }

  bool boolean() {
    final value = uint8();
    if (value == 0) return false;
    if (value == 1) return true;
    _fail(ProtocolErrorCode.invalidProps, 'Invalid bool $value');
  }

  String? optionalString() => switch (uint8()) {
    0 => null,
    1 => string(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional string tag $value',
    ),
  };

  bool? optionalBool() => switch (uint8()) {
    0 => null,
    1 => false,
    2 => true,
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional bool tag $value',
    ),
  };

  int? optionalUint8() => switch (uint8()) {
    0 => null,
    1 => uint8(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional u8 tag $value',
    ),
  };

  double? optionalFloat64() => switch (uint8()) {
    0 => null,
    1 => finiteFloat64(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional float tag $value',
    ),
  };

  ScrollAxis scrollAxis() => switch (uint8()) {
    0 => ScrollAxis.horizontal,
    1 => ScrollAxis.vertical,
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid scroll axis $value',
    ),
  };

  ThemeBrightness themeBrightness() => switch (uint8()) {
    0 => ThemeBrightness.light,
    1 => ThemeBrightness.dark,
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid theme brightness $value',
    ),
  };

  Uint8List bytes(int length) {
    _require(length);
    final result = Uint8List.sublistView(_bytes, _position, _position + length);
    _position += length;
    return result;
  }

  String string() {
    final length = uint32();
    if (length > ProtocolLimits.maxStringBytes) {
      _fail(ProtocolErrorCode.stringTooLarge, 'String is $length bytes');
    }
    _require(length);
    final start = _position;
    final end = start + length;
    _position = end;
    try {
      return const Utf8Decoder(
        allowMalformed: false,
      ).convert(_bytes, start, end);
    } on FormatException {
      _fail(ProtocolErrorCode.invalidUtf8, 'String is not valid UTF-8');
    }
  }

  _Reader subReader(int length) {
    _require(length);
    final result = _Reader._slice(_bytes, _data, _position, _position + length);
    _position += length;
    return result;
  }

  void requireDone() {
    if (!isDone) {
      _fail(
        ProtocolErrorCode.trailingBytes,
        'Operation body has $remaining trailing bytes',
      );
    }
  }

  void _require(int length) {
    if (length < 0 || length > remaining) {
      _fail(
        ProtocolErrorCode.truncatedInput,
        'Need $length bytes, only $remaining remain',
      );
    }
  }
}

Never _fail(ProtocolErrorCode code, String message) =>
    throw ProtocolException(code, message);

void _checkUint64(String label, int value) {
  if (value < 0 || value > 0x7fffffffffffffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      '$label is outside the supported positive int64 range',
    );
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _writeParentData(_Writer writer, ParentDataValue parentData) {
  switch (parentData) {
    case NoParentData():
      writer.uint8(0);
    case FlexParentData(:final flex, :final fit):
      if (flex <= 0 || flex > 0xffffffff) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Flex factor must be in 1..4294967295',
        );
      }
      writer
        ..uint8(fit == FlexParentFit.loose ? 1 : 2)
        ..uint32(flex);
    case StackPositionData(
      :final left,
      :final top,
      :final right,
      :final bottom,
    ):
      writer
        ..uint8(3)
        ..optionalFloat64(left)
        ..optionalFloat64(top)
        ..optionalFloat64(right)
        ..optionalFloat64(bottom);
  }
}

ParentDataValue _readParentData(_Reader reader) {
  final tag = reader.uint8();
  return switch (tag) {
    0 => const NoParentData(),
    1 || 2 => () {
      final flex = reader.uint32();
      if (flex == 0) {
        _fail(ProtocolErrorCode.invalidProps, 'Flex factor must be positive');
      }
      return FlexParentData(
        flex: flex,
        fit: tag == 1 ? FlexParentFit.loose : FlexParentFit.tight,
      );
    }(),
    3 => StackPositionData(
      left: reader.optionalFloat64(),
      top: reader.optionalFloat64(),
      right: reader.optionalFloat64(),
      bottom: reader.optionalFloat64(),
    ),
    _ => _fail(ProtocolErrorCode.invalidProps, 'Invalid parent-data tag $tag'),
  };
}
