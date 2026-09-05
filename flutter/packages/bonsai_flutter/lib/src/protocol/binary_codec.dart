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
  applicationPayloadTooLarge,
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
      operations.add(_readOperation(opcode, body));
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
      case ApplicationRequestOperation():
        if (operation.requestId <= 0 ||
            operation.requestId > 0x7fffffffffffffff) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Application request ID must be a positive int64',
          );
        }
        if (operation.payload.length >
            ProtocolLimits.maxApplicationPayloadBytes) {
          _fail(
            ProtocolErrorCode.applicationPayloadTooLarge,
            'Application request payload is ${operation.payload.length} bytes',
          );
        }
        payload.envelope(OperationId.applicationRequest, (body) {
          body
            ..uint64(operation.requestId)
            ..uint32(operation.payload.length)
            ..raw(operation.payload);
        });
      case SetApplicationTheme():
        final title = operation.title;
        if (title != null) _validateThemeFontName('Application title', title);
        payload.envelope(OperationId.setApplicationTheme, (body) {
          body.optionalString(title);
          _writeApplicationTheme(body, operation.theme);
        });
      case RuntimeStatsOperation():
        payload.envelope(OperationId.runtimeNotification, (body) {
          _writeRuntimeStats(body, operation);
        });
    }
  }

  static FrameOperation _readOperation(int opcode, _Reader body) {
    if (opcode == OperationId.createNode) {
      final nodeId = body.uint64();
      final kind = _readNodeKind(body);
      final props = _readProps(body, kind);
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
      return UpdateProps(nodeId: body.uint64(), props: _readUpdateProps(body));
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
    if (opcode == OperationId.applicationRequest) {
      final requestId = body.uint64();
      if (requestId <= 0) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Application request ID must be positive',
        );
      }
      final length = body.uint32();
      if (length > ProtocolLimits.maxApplicationPayloadBytes) {
        _fail(
          ProtocolErrorCode.applicationPayloadTooLarge,
          'Application request payload is $length bytes',
        );
      }
      return ApplicationRequestOperation(
        requestId: requestId,
        payload: body.bytes(length),
      );
    }
    if (opcode == OperationId.setApplicationTheme) {
      final title = body.optionalString();
      if (title != null) _validateThemeFontName('Application title', title);
      return SetApplicationTheme(
        title: title,
        theme: _readApplicationTheme(body),
      );
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
      case (NodeKind.constrainedBox, final ConstrainedBoxProps props):
        _validateConstrainedBoxProps(props);
        writer
          ..float64(props.minWidth)
          ..optionalFloat64(props.maxWidth)
          ..float64(props.minHeight)
          ..optionalFloat64(props.maxHeight);
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
      case (
        NodeKind.scrollView,
        ScrollViewProps(
          :final axis,
          :final reverse,
          :final primary,
          :final cacheExtent,
        ),
      ):
        if (axis == ScrollAxis.horizontal && primary) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Horizontal scroll view cannot be primary',
          );
        }
        _validateCacheExtent(cacheExtent);
        writer
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0)
          ..uint8(primary ? 1 : 0)
          ..optionalFloat64(cacheExtent);
      case (NodeKind.sliverBox, EmptyProps()):
        break;
      case (NodeKind.sliverList, EmptyProps()):
        break;
      case (NodeKind.sliverFill, SliverFillProps()):
        break;
      case (
        NodeKind.sliverFixedExtent,
        SliverFixedExtentProps(
          :final totalCount,
          :final firstIndex,
          :final itemExtent,
          :final overscan,
        ),
      ):
        _writeSliverFixedExtent(
          writer,
          totalCount: totalCount,
          firstIndex: firstIndex,
          itemExtent: itemExtent,
          overscan: overscan,
        );
      case (
        NodeKind.sliverVariedExtent,
        SliverVariedExtentProps(
          :final totalCount,
          :final firstIndex,
          :final defaultItemExtent,
          :final overscan,
          :final extentOverrides,
          :final transition,
        ),
      ):
        _writeSliverVariedExtent(
          writer,
          totalCount: totalCount,
          firstIndex: firstIndex,
          defaultItemExtent: defaultItemExtent,
          overscan: overscan,
          extentOverrides: extentOverrides,
          transition: transition,
        );
      case (NodeKind.sliverPadding, SliverPaddingProps(:final insets)):
        writer
          ..float64(insets.left)
          ..float64(insets.top)
          ..float64(insets.right)
          ..float64(insets.bottom);
      case (NodeKind.sliverAppBar, final SliverAppBarProps props):
        _writeSliverAppBar(writer, props);
      case (NodeKind.preferredSize, PreferredSizeProps(:final height)):
        writer.float64(height);
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
      case (NodeKind.theme, ThemeProps(:final data)):
        _writeThemeData(writer, data);
      case (
        NodeKind.materialScaffold,
        MaterialScaffoldProps(
          :final hasAppBar,
          :final hasFloatingActionButton,
          :final floatingActionButtonLocation,
          :final hasBottomNavigationBar,
          :final hasBottomSheet,
        ),
      ):
        writer
          ..uint8(hasAppBar ? 1 : 0)
          ..uint8(hasFloatingActionButton ? 1 : 0)
          ..uint8(floatingActionButtonLocation.index)
          ..uint8(hasBottomNavigationBar ? 1 : 0)
          ..uint8(hasBottomSheet ? 1 : 0);
      case (
        NodeKind.materialElevatedButton ||
            NodeKind.materialTextButton ||
            NodeKind.materialFilledButton ||
            NodeKind.materialFilledTonalButton ||
            NodeKind.materialOutlinedButton,
        MaterialButtonProps(:final enabled, :final autofocus),
      ):
        writer
          ..uint8(enabled ? 1 : 0)
          ..uint8(autofocus ? 1 : 0);
      case (NodeKind.materialIconButton, MaterialButtonProps(:final enabled)):
        writer.uint8(enabled ? 1 : 0);
      case (
        NodeKind.materialFloatingActionButton,
        MaterialFloatingActionButtonProps(
          :final variant,
          :final enabled,
          :final autofocus,
        ),
      ):
        writer
          ..uint8(variant.index)
          ..uint8(enabled ? 1 : 0)
          ..uint8(autofocus ? 1 : 0);
      case (
        NodeKind.materialNavigationBar,
        final MaterialNavigationBarProps props,
      ):
        _validateMaterialNavigation(props);
        writer
          ..uint32(props.selectedIndex)
          ..uint16(props.destinations.length);
        for (final destination in props.destinations) {
          writer
            ..string(destination.label)
            ..uint8(destination.hasSelectedIcon ? 1 : 0)
            ..optionalUint32(destination.badgeCount)
            ..uint8(destination.badgeDot ? 1 : 0)
            ..optionalString(destination.semanticLabel);
        }
        writer
          ..uint8(props.autoLayout ? 1 : 0)
          ..uint8(props.layout)
          ..uint8(props.alignment)
          ..uint8(props.labelBehavior)
          ..uint8(props.iconBehavior)
          ..uint8(props.size)
          ..uint8(props.shape)
          ..uint8(props.density)
          ..uint8(props.safeArea ? 1 : 0)
          ..optionalString(props.semanticLabel);
      case (
        NodeKind.materialRadioGroup,
        MaterialRadioGroupProps(:final selectedId, :final options),
      ):
        _validateMaterialRadio(selectedId, options);
        if (selectedId == null) {
          writer.uint8(0);
        } else {
          writer
            ..uint8(1)
            ..int64(selectedId);
        }
        writer.uint16(options.length);
        for (final option in options) {
          writer
            ..int64(option.id)
            ..uint8(option.enabled ? 1 : 0)
            ..uint8(option.hasLabel ? 1 : 0);
        }
      case (
        NodeKind.materialSegmentedButton,
        final MaterialSegmentedButtonProps props,
      ):
        _writeMaterialSegmentedButton(writer, props);
      case (NodeKind.materialSlider, final MaterialSliderProps props):
        _validateMaterialSlider(props);
        writer
          ..float64(props.value)
          ..float64(props.min)
          ..float64(props.max)
          ..optionalUint32(props.divisions)
          ..optionalString(props.label)
          ..uint8(props.enabled ? 1 : 0)
          ..uint8(props.hasOnChange ? 1 : 0)
          ..uint8(props.kind);
      case (NodeKind.materialRangeSlider, final MaterialRangeSliderProps props):
        _validateMaterialRangeSlider(props);
        writer
          ..float64(props.start)
          ..float64(props.end)
          ..float64(props.min)
          ..float64(props.max)
          ..optionalUint32(props.divisions)
          ..optionalString(props.labelStart)
          ..optionalString(props.labelEnd)
          ..uint8(props.enabled ? 1 : 0)
          ..uint8(props.hasOnChange ? 1 : 0)
          ..uint8(props.kind);
      case (
        NodeKind.materialActionChip ||
            NodeKind.materialFilterChip ||
            NodeKind.materialChoiceChip ||
            NodeKind.materialInputChip,
        MaterialChipProps(
          :final presentation,
          :final enabled,
          :final selected,
          :final hasLeading,
          :final hasOnDelete,
        ),
      ):
        writer
          ..uint8(enabled ? 1 : 0)
          ..uint8(selected ? 1 : 0)
          ..uint8(hasLeading ? 1 : 0)
          ..uint8(hasOnDelete ? 1 : 0)
          ..uint8(presentation.index);
      case (
        NodeKind.materialSearchBar ||
            NodeKind.materialDataTable ||
            NodeKind.materialStepper ||
            NodeKind.materialExpansionPanelList ||
            NodeKind.materialSimpleDialog ||
            NodeKind.materialFullscreenDialog,
        final UiProps props,
      ):
        _writeAdditionalMaterialProps(writer, props);
      case (NodeKind.materialTextField, final MaterialTextFieldProps props):
        _writeMaterialTextField(writer, props);
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
        NodeKind.materialDivider,
        MaterialDividerProps(
          :final orientation,
          :final thickness,
          :final spacing,
          :final indent,
          :final endIndent,
        ),
      ):
        writer
          ..uint8(orientation.index)
          ..float64(thickness)
          ..float64(spacing)
          ..float64(indent)
          ..float64(endIndent);
      case (
        NodeKind.materialCard,
        MaterialCardProps(:final variant, :final elevation),
      ):
        writer
          ..float64(elevation)
          ..uint8(variant.index);
      case (
        NodeKind.materialCircularProgressIndicator,
        MaterialCircularProgressProps(:final value, :final wavy),
      ):
        _validateProgressValue(value);
        writer
          ..optionalFloat64(value)
          ..uint8(wavy ? 1 : 0);
      case (
        NodeKind.materialLinearProgressIndicator,
        MaterialLinearProgressProps(:final value, :final wavy),
      ):
        _validateProgressValue(value);
        writer
          ..optionalFloat64(value)
          ..uint8(wavy ? 1 : 0);
      case (NodeKind.materialExpressive, final MaterialExpressiveProps props):
        _writeMaterialExpressive(writer, props);
      case (NodeKind.cupertinoButton, CupertinoButtonProps(:final enabled)):
        writer.uint8(enabled ? 1 : 0);
      case (
        NodeKind.cupertinoSwitch,
        CupertinoSwitchProps(:final value, :final enabled),
      ):
        writer
          ..uint8(value ? 1 : 0)
          ..uint8(enabled ? 1 : 0);
      case (
        NodeKind.overlay,
        OverlayProps(:final alignment, :final dismissible),
      ):
        writer
          ..uint8(alignment.index)
          ..uint8(dismissible ? 1 : 0);
      case (NodeKind.navigator, NavigatorProps(:final restorationScopeId)):
        writer.optionalString(restorationScopeId);
      case (NodeKind.page, final PageProps props):
        _writePageProps(writer, props);
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
      case final ConstrainedBoxProps props:
        _validateConstrainedBoxProps(props);
        writer
          ..uint16(NodeKindId.constrainedBox)
          ..uint64(_changedFields(props))
          ..float64(props.minWidth)
          ..optionalFloat64(props.maxWidth)
          ..float64(props.minHeight)
          ..optionalFloat64(props.maxHeight);
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
      case ScrollViewProps(
        :final axis,
        :final reverse,
        :final primary,
        :final cacheExtent,
      ):
        if (axis == ScrollAxis.horizontal && primary) {
          _fail(
            ProtocolErrorCode.invalidProps,
            'Horizontal scroll view cannot be primary',
          );
        }
        writer
          ..uint16(NodeKindId.scrollView)
          ..uint64(_changedFields(props))
          ..uint8(axis == ScrollAxis.horizontal ? 0 : 1)
          ..uint8(reverse ? 1 : 0)
          ..uint8(primary ? 1 : 0)
          ..optionalFloat64(cacheExtent);
      case SliverFillProps():
        writer
          ..uint16(NodeKindId.sliverFill)
          ..uint64(0);
      case SliverFixedExtentProps(
        :final totalCount,
        :final firstIndex,
        :final itemExtent,
        :final overscan,
      ):
        writer
          ..uint16(NodeKindId.sliverFixedExtent)
          ..uint64(_changedFields(props));
        _writeSliverFixedExtent(
          writer,
          totalCount: totalCount,
          firstIndex: firstIndex,
          itemExtent: itemExtent,
          overscan: overscan,
        );
      case SliverVariedExtentProps(
        :final totalCount,
        :final firstIndex,
        :final defaultItemExtent,
        :final overscan,
        :final extentOverrides,
        :final transition,
      ):
        writer
          ..uint16(NodeKindId.sliverVariedExtent)
          ..uint64(_changedFields(props));
        _writeSliverVariedExtent(
          writer,
          totalCount: totalCount,
          firstIndex: firstIndex,
          defaultItemExtent: defaultItemExtent,
          overscan: overscan,
          extentOverrides: extentOverrides,
          transition: transition,
        );
      case SliverPaddingProps(:final insets):
        writer
          ..uint16(NodeKindId.sliverPadding)
          ..uint64(_changedFields(props))
          ..float64(insets.left)
          ..float64(insets.top)
          ..float64(insets.right)
          ..float64(insets.bottom);
      case final SliverAppBarProps props:
        writer
          ..uint16(NodeKindId.sliverAppBar)
          ..uint64(_changedFields(props));
        _writeSliverAppBar(writer, props);
      case PreferredSizeProps(:final height):
        writer
          ..uint16(NodeKindId.preferredSize)
          ..uint64(_changedFields(props))
          ..float64(height);
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
      case ThemeProps(:final data):
        writer
          ..uint16(NodeKindId.theme)
          ..uint64(_fieldMask(ThemePropId.data));
        _writeThemeData(writer, data);
      case final MaterialScaffoldProps props:
        writer
          ..uint16(NodeKindId.materialScaffold)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialScaffold, props);
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
            MaterialButtonVariant.filled => NodeKindId.materialFilledButton,
            MaterialButtonVariant.filledTonal =>
              NodeKindId.materialFilledTonalButton,
            MaterialButtonVariant.outlined => NodeKindId.materialOutlinedButton,
          })
          ..uint64(_changedFields(props))
          ..uint8(enabled ? 1 : 0);
        if (variant != MaterialButtonVariant.icon) {
          writer.uint8(autofocus ? 1 : 0);
        }
      case final MaterialFloatingActionButtonProps props:
        writer
          ..uint16(NodeKindId.materialFloatingActionButton)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialFloatingActionButton, props);
      case final MaterialNavigationBarProps props:
        writer
          ..uint16(NodeKindId.materialNavigationBar)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialNavigationBar, props);
      case final MaterialRadioGroupProps props:
        writer
          ..uint16(NodeKindId.materialRadioGroup)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialRadioGroup, props);
      case final MaterialSegmentedButtonProps props:
        writer
          ..uint16(NodeKindId.materialSegmentedButton)
          ..uint64(_changedFields(props));
        _writeMaterialSegmentedButton(writer, props);
      case final MaterialSliderProps props:
        writer
          ..uint16(NodeKindId.materialSlider)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialSlider, props);
      case final MaterialRangeSliderProps props:
        writer
          ..uint16(NodeKindId.materialRangeSlider)
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, NodeKind.materialRangeSlider, props);
      case final MaterialChipProps props:
        _validateMaterialChip(props);
        final kind = switch (props.variant) {
          MaterialChipVariant.action => NodeKind.materialActionChip,
          MaterialChipVariant.filter => NodeKind.materialFilterChip,
          MaterialChipVariant.choice => NodeKind.materialChoiceChip,
          MaterialChipVariant.input => NodeKind.materialInputChip,
        };
        writer
          ..uint16(_nodeKindId(kind))
          ..uint64(_changedFields(props));
        _writeCreateProps(writer, kind, props);
      case final MaterialSearchBarProps props:
        writer
          ..uint16(NodeKindId.materialSearchBar)
          ..uint64(_changedFields(props));
        _writeAdditionalMaterialProps(writer, props);
      case final MaterialTextFieldProps props:
        writer
          ..uint16(NodeKindId.materialTextField)
          ..uint64(_changedFields(props));
        _writeMaterialTextField(writer, props);
      case final MaterialDataTableProps props:
        writer
          ..uint16(NodeKindId.materialDataTable)
          ..uint64(_changedFields(props));
        _writeAdditionalMaterialProps(writer, props);
      case final MaterialStepperProps props:
        writer
          ..uint16(NodeKindId.materialStepper)
          ..uint64(_changedFields(props));
        _writeAdditionalMaterialProps(writer, props);
      case final MaterialExpansionPanelListProps props:
        writer
          ..uint16(NodeKindId.materialExpansionPanelList)
          ..uint64(_changedFields(props));
        _writeAdditionalMaterialProps(writer, props);
      case final MaterialSimpleDialogProps props:
        writer
          ..uint16(NodeKindId.materialSimpleDialog)
          ..uint64(_changedFields(props));
        _writeAdditionalMaterialProps(writer, props);
      case final MaterialFullscreenDialogProps props:
        writer
          ..uint16(NodeKindId.materialFullscreenDialog)
          ..uint64(0);
        _writeAdditionalMaterialProps(writer, props);
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
      case MaterialDividerProps(
        :final orientation,
        :final thickness,
        :final spacing,
        :final indent,
        :final endIndent,
      ):
        _validateMaterialDivider(props);
        writer
          ..uint16(NodeKindId.materialDivider)
          ..uint64(_changedFields(props))
          ..uint8(orientation.index)
          ..float64(thickness)
          ..float64(spacing)
          ..float64(indent)
          ..float64(endIndent);
      case MaterialCardProps(:final variant, :final elevation):
        _validateMaterialCard(props);
        writer
          ..uint16(NodeKindId.materialCard)
          ..uint64(_changedFields(props))
          ..float64(elevation)
          ..uint8(variant.index);
      case MaterialCircularProgressProps(:final value, :final wavy):
        _validateProgressValue(value);
        writer
          ..uint16(NodeKindId.materialCircularProgressIndicator)
          ..uint64(_changedFields(props))
          ..optionalFloat64(value)
          ..uint8(wavy ? 1 : 0);
      case MaterialLinearProgressProps(:final value, :final wavy):
        _validateProgressValue(value);
        writer
          ..uint16(NodeKindId.materialLinearProgressIndicator)
          ..uint64(_changedFields(props))
          ..optionalFloat64(value)
          ..uint8(wavy ? 1 : 0);
      case final MaterialExpressiveProps props:
        writer
          ..uint16(NodeKindId.materialExpressive)
          ..uint64(_changedFields(props));
        _writeMaterialExpressive(writer, props);
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
      case final PageProps props:
        writer
          ..uint16(NodeKindId.page)
          ..uint64(_changedFields(props));
        _writePageProps(writer, props);
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
      case final NativeWidgetProps props:
        writer
          ..uint16(NodeKindId.nativeWidget)
          ..uint64(_changedFields(props));
        _writeNativeWidgetProps(writer, props);
    }
  }

  static UiProps _readUpdateProps(_Reader reader) {
    final kind = _readNodeKind(reader);
    final changedFields = reader.uint64();
    final props = _readProps(reader, kind);
    final expectedChangedFields = _changedFields(props);
    if (changedFields != expectedChangedFields) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Unsupported changed-field bitset $changedFields',
      );
    }
    return props;
  }

  static UiProps _readProps(_Reader reader, NodeKind kind) => switch (kind) {
    NodeKind.empty || NodeKind.stack => const EmptyProps(),
    NodeKind.environmentBoundary => const EnvironmentBoundaryProps(),
    NodeKind.text => _readTextProps(reader),
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
    NodeKind.constrainedBox => _readConstrainedBoxProps(reader),
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
    NodeKind.scrollView => _readScrollViewProps(reader),
    NodeKind.sliverBox => const EmptyProps(),
    NodeKind.sliverList => const EmptyProps(),
    NodeKind.sliverFill => _readSliverFillProps(reader),
    NodeKind.sliverFixedExtent => _readSliverFixedExtentProps(reader),
    NodeKind.sliverVariedExtent => _readSliverVariedExtentProps(reader),
    NodeKind.sliverPadding => _readSliverPaddingProps(reader),
    NodeKind.sliverAppBar => _readSliverAppBarProps(reader),
    NodeKind.preferredSize => _readPreferredSizeProps(reader),
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
    NodeKind.theme => ThemeProps(data: _readThemeData(reader)),
    NodeKind.materialScaffold => MaterialScaffoldProps(
      hasAppBar: reader.boolean(),
      hasFloatingActionButton: reader.boolean(),
      floatingActionButtonLocation: _enumValue(
        MaterialFloatingActionButtonLocation.values,
        reader.uint8(),
        'floating action button location',
      ),
      hasBottomNavigationBar: reader.boolean(),
      hasBottomSheet: reader.boolean(),
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
      autofocus: false,
    ),
    NodeKind.materialFilledButton => MaterialButtonProps(
      variant: MaterialButtonVariant.filled,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialFilledTonalButton => MaterialButtonProps(
      variant: MaterialButtonVariant.filledTonal,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialOutlinedButton => MaterialButtonProps(
      variant: MaterialButtonVariant.outlined,
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialFloatingActionButton => MaterialFloatingActionButtonProps(
      variant: _enumValue(
        MaterialFloatingActionButtonVariant.values,
        reader.uint8(),
        'floating action button variant',
      ),
      enabled: reader.boolean(),
      autofocus: reader.boolean(),
    ),
    NodeKind.materialNavigationBar => _readMaterialNavigationBar(reader),
    NodeKind.materialRadioGroup => _readMaterialRadioGroup(reader),
    NodeKind.materialSegmentedButton => _readMaterialSegmentedButton(reader),
    NodeKind.materialSlider => _readMaterialSlider(reader),
    NodeKind.materialRangeSlider => _readMaterialRangeSlider(reader),
    NodeKind.materialActionChip => _readMaterialChip(
      reader,
      MaterialChipVariant.action,
    ),
    NodeKind.materialFilterChip => _readMaterialChip(
      reader,
      MaterialChipVariant.filter,
    ),
    NodeKind.materialChoiceChip => _readMaterialChip(
      reader,
      MaterialChipVariant.choice,
    ),
    NodeKind.materialInputChip => _readMaterialChip(
      reader,
      MaterialChipVariant.input,
    ),
    NodeKind.materialSearchBar ||
    NodeKind.materialDataTable ||
    NodeKind.materialStepper ||
    NodeKind.materialExpansionPanelList ||
    NodeKind.materialSimpleDialog ||
    NodeKind.materialFullscreenDialog => _readAdditionalMaterialProps(
      reader,
      kind,
    ),
    NodeKind.materialTextField => _readMaterialTextField(reader),
    NodeKind.materialCheckbox => MaterialCheckboxProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
    ),
    NodeKind.materialSwitch => MaterialSwitchProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
    ),
    NodeKind.materialDivider => _readMaterialDivider(reader),
    NodeKind.materialCard => _readMaterialCard(reader),
    NodeKind.materialCircularProgressIndicator => MaterialCircularProgressProps(
      value: _readProgressValue(reader),
      wavy: reader.boolean(),
    ),
    NodeKind.materialLinearProgressIndicator => MaterialLinearProgressProps(
      value: _readProgressValue(reader),
      wavy: reader.boolean(),
    ),
    NodeKind.materialExpressive => _readMaterialExpressive(reader),
    NodeKind.cupertinoButton => CupertinoButtonProps(enabled: reader.boolean()),
    NodeKind.cupertinoSwitch => CupertinoSwitchProps(
      value: reader.boolean(),
      enabled: reader.boolean(),
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
    NodeKind.page => _readPageProps(reader),
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
    NodeKind.sliverBox => NodeKindId.sliverBox,
    NodeKind.sliverList => NodeKindId.sliverList,
    NodeKind.sliverFill => NodeKindId.sliverFill,
    NodeKind.sliverFixedExtent => NodeKindId.sliverFixedExtent,
    NodeKind.sliverVariedExtent => NodeKindId.sliverVariedExtent,
    NodeKind.sliverPadding => NodeKindId.sliverPadding,
    NodeKind.sliverAppBar => NodeKindId.sliverAppBar,
    NodeKind.preferredSize => NodeKindId.preferredSize,
    NodeKind.gesture => NodeKindId.gesture,
    NodeKind.focusScope => NodeKindId.focusScope,
    NodeKind.mouseRegion => NodeKindId.mouseRegion,
    NodeKind.keyboardListener => NodeKindId.keyboardListener,
    NodeKind.pressable => NodeKindId.pressable,
    NodeKind.semantics => NodeKindId.semantics,
    NodeKind.theme => NodeKindId.theme,
    NodeKind.materialScaffold => NodeKindId.materialScaffold,
    NodeKind.materialElevatedButton => NodeKindId.materialElevatedButton,
    NodeKind.materialTextButton => NodeKindId.materialTextButton,
    NodeKind.materialIconButton => NodeKindId.materialIconButton,
    NodeKind.materialFilledButton => NodeKindId.materialFilledButton,
    NodeKind.materialFilledTonalButton => NodeKindId.materialFilledTonalButton,
    NodeKind.materialOutlinedButton => NodeKindId.materialOutlinedButton,
    NodeKind.materialFloatingActionButton =>
      NodeKindId.materialFloatingActionButton,
    NodeKind.materialNavigationBar => NodeKindId.materialNavigationBar,
    NodeKind.materialRadioGroup => NodeKindId.materialRadioGroup,
    NodeKind.materialSegmentedButton => NodeKindId.materialSegmentedButton,
    NodeKind.materialSlider => NodeKindId.materialSlider,
    NodeKind.materialRangeSlider => NodeKindId.materialRangeSlider,
    NodeKind.materialActionChip => NodeKindId.materialActionChip,
    NodeKind.materialFilterChip => NodeKindId.materialFilterChip,
    NodeKind.materialChoiceChip => NodeKindId.materialChoiceChip,
    NodeKind.materialInputChip => NodeKindId.materialInputChip,
    NodeKind.materialSearchBar => NodeKindId.materialSearchBar,
    NodeKind.materialTextField => NodeKindId.materialTextField,
    NodeKind.materialDataTable => NodeKindId.materialDataTable,
    NodeKind.materialStepper => NodeKindId.materialStepper,
    NodeKind.materialExpansionPanelList =>
      NodeKindId.materialExpansionPanelList,
    NodeKind.materialSimpleDialog => NodeKindId.materialSimpleDialog,
    NodeKind.materialFullscreenDialog => NodeKindId.materialFullscreenDialog,
    NodeKind.materialCheckbox => NodeKindId.materialCheckbox,
    NodeKind.materialSwitch => NodeKindId.materialSwitch,
    NodeKind.materialDivider => NodeKindId.materialDivider,
    NodeKind.materialCard => NodeKindId.materialCard,
    NodeKind.materialCircularProgressIndicator =>
      NodeKindId.materialCircularProgressIndicator,
    NodeKind.materialLinearProgressIndicator =>
      NodeKindId.materialLinearProgressIndicator,
    NodeKind.materialExpressive => NodeKindId.materialExpressive,
    NodeKind.cupertinoButton => NodeKindId.cupertinoButton,
    NodeKind.cupertinoSwitch => NodeKindId.cupertinoSwitch,
    NodeKind.overlay => NodeKindId.overlay,
    NodeKind.navigator => NodeKindId.navigator,
    NodeKind.page => NodeKindId.page,
    NodeKind.safeArea => NodeKindId.safeArea,
    NodeKind.environmentBoundary => NodeKindId.environmentBoundary,
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
    if (value == NodeKindId.sliverBox) return NodeKind.sliverBox;
    if (value == NodeKindId.sliverList) return NodeKind.sliverList;
    if (value == NodeKindId.sliverFill) return NodeKind.sliverFill;
    if (value == NodeKindId.sliverFixedExtent) {
      return NodeKind.sliverFixedExtent;
    }
    if (value == NodeKindId.sliverVariedExtent) {
      return NodeKind.sliverVariedExtent;
    }
    if (value == NodeKindId.sliverPadding) return NodeKind.sliverPadding;
    if (value == NodeKindId.sliverAppBar) return NodeKind.sliverAppBar;
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
    if (value == NodeKindId.materialElevatedButton) {
      return NodeKind.materialElevatedButton;
    }
    if (value == NodeKindId.materialTextButton) {
      return NodeKind.materialTextButton;
    }
    if (value == NodeKindId.materialIconButton) {
      return NodeKind.materialIconButton;
    }
    if (value == NodeKindId.materialFilledButton) {
      return NodeKind.materialFilledButton;
    }
    if (value == NodeKindId.materialFilledTonalButton) {
      return NodeKind.materialFilledTonalButton;
    }
    if (value == NodeKindId.materialOutlinedButton) {
      return NodeKind.materialOutlinedButton;
    }
    if (value == NodeKindId.materialFloatingActionButton) {
      return NodeKind.materialFloatingActionButton;
    }
    if (value == NodeKindId.materialNavigationBar) {
      return NodeKind.materialNavigationBar;
    }
    if (value == NodeKindId.materialRadioGroup) {
      return NodeKind.materialRadioGroup;
    }
    if (value == NodeKindId.materialSlider) return NodeKind.materialSlider;
    if (value == NodeKindId.materialRangeSlider) {
      return NodeKind.materialRangeSlider;
    }
    if (value == NodeKindId.materialActionChip) {
      return NodeKind.materialActionChip;
    }
    if (value == NodeKindId.materialFilterChip) {
      return NodeKind.materialFilterChip;
    }
    if (value == NodeKindId.materialChoiceChip) {
      return NodeKind.materialChoiceChip;
    }
    if (value == NodeKindId.materialInputChip) {
      return NodeKind.materialInputChip;
    }
    if (value == NodeKindId.materialSearchBar) {
      return NodeKind.materialSearchBar;
    }
    if (value == NodeKindId.materialTextField) {
      return NodeKind.materialTextField;
    }
    if (value == NodeKindId.materialDataTable) {
      return NodeKind.materialDataTable;
    }
    if (value == NodeKindId.materialStepper) {
      return NodeKind.materialStepper;
    }
    if (value == NodeKindId.materialExpansionPanelList) {
      return NodeKind.materialExpansionPanelList;
    }
    if (value == NodeKindId.materialSimpleDialog) {
      return NodeKind.materialSimpleDialog;
    }
    if (value == NodeKindId.materialFullscreenDialog) {
      return NodeKind.materialFullscreenDialog;
    }
    if (value == NodeKindId.materialCheckbox) {
      return NodeKind.materialCheckbox;
    }
    if (value == NodeKindId.materialSwitch) return NodeKind.materialSwitch;
    if (value == NodeKindId.materialDivider) return NodeKind.materialDivider;
    if (value == NodeKindId.materialCard) return NodeKind.materialCard;
    if (value == NodeKindId.materialCircularProgressIndicator) {
      return NodeKind.materialCircularProgressIndicator;
    }
    if (value == NodeKindId.materialLinearProgressIndicator) {
      return NodeKind.materialLinearProgressIndicator;
    }
    if (value == NodeKindId.materialSegmentedButton) {
      return NodeKind.materialSegmentedButton;
    }
    if (value == NodeKindId.materialExpressive) {
      return NodeKind.materialExpressive;
    }
    if (value == NodeKindId.cupertinoButton) return NodeKind.cupertinoButton;
    if (value == NodeKindId.cupertinoSwitch) return NodeKind.cupertinoSwitch;
    if (value == NodeKindId.overlay) return NodeKind.overlay;
    if (value == NodeKindId.navigator) return NodeKind.navigator;
    if (value == NodeKindId.page) return NodeKind.page;
    if (value == NodeKindId.safeArea) return NodeKind.safeArea;
    if (value == NodeKindId.environmentBoundary) {
      return NodeKind.environmentBoundary;
    }
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
      opcode == OperationId.runtimeNotification ||
      opcode == OperationId.applicationRequest ||
      opcode == OperationId.setApplicationTheme;
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

void _writeThemeTextStyle(_Writer writer, TextStyleValue? style) {
  if (style == null) {
    writer.uint8(0);
    return;
  }
  for (final value in [style.fontSize, style.lineHeight]) {
    if (value != null && (!value.isFinite || value <= 0)) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Theme text values must be positive',
      );
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

void _validateThemeFontName(String label, String value) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    _fail(
      ProtocolErrorCode.invalidProps,
      '$label must be non-empty and contain no NUL',
    );
  }
}

void _validateThemeData(ThemeDataValue data) {
  if (!data.colorScheme.contrastLevel.isFinite ||
      data.colorScheme.contrastLevel < -1 ||
      data.colorScheme.contrastLevel > 1) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Theme contrast must be finite and between -1 and 1',
    );
  }
  for (final radius in [
    data.shape.extraSmall,
    data.shape.small,
    data.shape.medium,
    data.shape.large,
    data.shape.extraLarge,
  ]) {
    if (!radius.isFinite || radius < 0) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Theme shape radii must be finite and non-negative',
      );
    }
  }
  final family = data.typography.fontFamily;
  if (family != null) _validateThemeFontName('Theme font family', family);
  if (data.typography.fontFamilyFallback.length > 16) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Theme supports at most 16 fallback fonts',
    );
  }
  for (final fallback in data.typography.fontFamilyFallback) {
    _validateThemeFontName('Theme fallback font family', fallback);
  }
}

void _writeThemeData(_Writer writer, ThemeDataValue data) {
  _validateThemeData(data);
  writer
    ..uint8(data.brightness.index)
    ..uint32(data.colorScheme.seedArgb)
    ..uint8(data.colorScheme.variant.index)
    ..float64(data.colorScheme.contrastLevel)
    ..optionalString(data.typography.fontFamily)
    ..uint8(data.typography.fontFamilyFallback.length);
  for (final fallback in data.typography.fontFamilyFallback) {
    writer.string(fallback);
  }
  for (final role in data.typography.roles) {
    _writeThemeTextStyle(writer, role);
  }
  writer
    ..float64(data.shape.extraSmall)
    ..float64(data.shape.small)
    ..float64(data.shape.medium)
    ..float64(data.shape.large)
    ..float64(data.shape.extraLarge)
    ..uint8(data.visualDensity.index)
    ..uint8(data.tapTargetSize.index);
}

void _writeApplicationTheme(_Writer writer, ApplicationThemeValue theme) {
  if (theme.light.brightness != ThemeBrightness.light ||
      theme.dark.brightness != ThemeBrightness.dark ||
      theme.highContrastLight?.brightness == ThemeBrightness.dark ||
      theme.highContrastDark?.brightness == ThemeBrightness.light) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Application theme brightness variants are inconsistent',
    );
  }
  writer.uint8(theme.mode.index);
  _writeThemeData(writer, theme.light);
  _writeThemeData(writer, theme.dark);
  for (final optional in [theme.highContrastLight, theme.highContrastDark]) {
    if (optional == null) {
      writer.uint8(0);
    } else {
      writer.uint8(1);
      _writeThemeData(writer, optional);
    }
  }
}

TextProps _readTextProps(_Reader reader) {
  final value = reader.string();
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

TextStyleValue? _readThemeTextStyle(_Reader reader) => switch (reader.uint8()) {
  0 => null,
  1 => TextStyleValue(
    fontSize: _readPositiveOptionalFloat(reader, 'Theme font size'),
    fontWeight: switch (reader.uint8()) {
      0 => null,
      1 => _enumValue(
        TextFontWeight.values,
        reader.uint8(),
        'theme font weight',
      ),
      final tag => _fail(
        ProtocolErrorCode.invalidProps,
        'Invalid optional theme font weight tag $tag',
      ),
    },
    lineHeight: _readPositiveOptionalFloat(reader, 'Theme line height'),
    colorArgb: _readOptionalArgb32(reader),
  ),
  final tag => _fail(
    ProtocolErrorCode.invalidProps,
    'Invalid optional theme text style tag $tag',
  ),
};

ThemeDataValue _readThemeData(_Reader reader) {
  final brightness = _enumValue(
    ThemeBrightness.values,
    reader.uint8(),
    'theme brightness',
  );
  final colorScheme = ThemeColorSchemeValue(
    seedArgb: reader.uint32(),
    variant: _enumValue(
      ThemeDynamicVariant.values,
      reader.uint8(),
      'theme dynamic variant',
    ),
    contrastLevel: reader.finiteFloat64(),
  );
  final fontFamily = reader.optionalString();
  final fallbackCount = reader.uint8();
  if (fallbackCount > 16) {
    _fail(ProtocolErrorCode.invalidProps, 'Theme has too many fallback fonts');
  }
  final fallbacks = List<String>.unmodifiable([
    for (var index = 0; index < fallbackCount; index += 1) reader.string(),
  ]);
  final roles = List<TextStyleValue?>.generate(
    15,
    (_) => _readThemeTextStyle(reader),
    growable: false,
  );
  final typography = ThemeTypographyValue(
    fontFamily: fontFamily,
    fontFamilyFallback: fallbacks,
    displayLarge: roles[0],
    displayMedium: roles[1],
    displaySmall: roles[2],
    headlineLarge: roles[3],
    headlineMedium: roles[4],
    headlineSmall: roles[5],
    titleLarge: roles[6],
    titleMedium: roles[7],
    titleSmall: roles[8],
    bodyLarge: roles[9],
    bodyMedium: roles[10],
    bodySmall: roles[11],
    labelLarge: roles[12],
    labelMedium: roles[13],
    labelSmall: roles[14],
  );
  final data = ThemeDataValue(
    brightness: brightness,
    colorScheme: colorScheme,
    typography: typography,
    shape: ThemeShapeValue(
      extraSmall: reader.finiteFloat64(),
      small: reader.finiteFloat64(),
      medium: reader.finiteFloat64(),
      large: reader.finiteFloat64(),
      extraLarge: reader.finiteFloat64(),
    ),
    visualDensity: _enumValue(
      ThemeVisualDensity.values,
      reader.uint8(),
      'theme visual density',
    ),
    tapTargetSize: _enumValue(
      ThemeTapTargetSize.values,
      reader.uint8(),
      'theme tap target size',
    ),
  );
  _validateThemeData(data);
  return data;
}

ApplicationThemeValue _readApplicationTheme(_Reader reader) {
  final mode = _enumValue(
    ApplicationThemeMode.values,
    reader.uint8(),
    'application theme mode',
  );
  final light = _readThemeData(reader);
  final dark = _readThemeData(reader);
  ThemeDataValue? optional() => switch (reader.uint8()) {
    0 => null,
    1 => _readThemeData(reader),
    final tag => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional theme data tag $tag',
    ),
  };
  final theme = ApplicationThemeValue(
    mode: mode,
    light: light,
    dark: dark,
    highContrastLight: optional(),
    highContrastDark: optional(),
  );
  if (theme.light.brightness != ThemeBrightness.light ||
      theme.dark.brightness != ThemeBrightness.dark ||
      theme.highContrastLight?.brightness == ThemeBrightness.dark ||
      theme.highContrastDark?.brightness == ThemeBrightness.light) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Application theme brightness variants are inconsistent',
    );
  }
  return theme;
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
  // SliverBox and SliverList carry no props (their content is children).
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
    _fieldMask(ScrollViewPropId.axis) |
        _fieldMask(ScrollViewPropId.reverse) |
        _fieldMask(ScrollViewPropId.primary) |
        _fieldMask(ScrollViewPropId.cacheExtent),
  SliverFillProps() => 0,
  SliverFixedExtentProps() =>
    _fieldMask(SliverFixedExtentPropId.totalCount) |
        _fieldMask(SliverFixedExtentPropId.firstIndex) |
        _fieldMask(SliverFixedExtentPropId.itemExtent) |
        _fieldMask(SliverFixedExtentPropId.overscan),
  SliverVariedExtentProps() =>
    _fieldMask(SliverVariedExtentPropId.totalCount) |
        _fieldMask(SliverVariedExtentPropId.firstIndex) |
        _fieldMask(SliverVariedExtentPropId.defaultItemExtent) |
        _fieldMask(SliverVariedExtentPropId.overscan) |
        _fieldMask(SliverVariedExtentPropId.overrideCount) |
        _fieldMask(SliverVariedExtentPropId.overrides) |
        _fieldMask(SliverVariedExtentPropId.transitionEnabled) |
        _fieldMask(SliverVariedExtentPropId.expandDurationMs) |
        _fieldMask(SliverVariedExtentPropId.collapseDurationMs) |
        _fieldMask(SliverVariedExtentPropId.expandCurve) |
        _fieldMask(SliverVariedExtentPropId.collapseCurve),
  SliverPaddingProps() => _fieldMask(SliverPaddingPropId.insets),
  SliverAppBarProps() =>
    _fieldMask(SliverAppBarPropId.pinned) |
        _fieldMask(SliverAppBarPropId.floating) |
        _fieldMask(SliverAppBarPropId.snap) |
        _fieldMask(SliverAppBarPropId.hasLeading) |
        _fieldMask(SliverAppBarPropId.backgroundColor) |
        _fieldMask(SliverAppBarPropId.foregroundColor) |
        _fieldMask(SliverAppBarPropId.actionCount) |
        _fieldMask(SliverAppBarPropId.centerTitleValue) |
        _fieldMask(SliverAppBarPropId.semanticLabel) |
        _fieldMask(SliverAppBarPropId.expandedHeight) |
        _fieldMask(SliverAppBarPropId.collapsedHeight) |
        _fieldMask(SliverAppBarPropId.toolbarHeight) |
        _fieldMask(SliverAppBarPropId.hasFlexibleSpace) |
        _fieldMask(SliverAppBarPropId.hasBottom) |
        _fieldMask(SliverAppBarPropId.bottomHeight) |
        _fieldMask(SliverAppBarPropId.stretch) |
        _fieldMask(SliverAppBarPropId.forceElevated) |
        _fieldMask(SliverAppBarPropId.elevation) |
        _fieldMask(SliverAppBarPropId.automaticallyImplyLeading),
  PreferredSizeProps() => _fieldMask(PreferredSizePropId.height),
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
  ThemeProps() => _fieldMask(ThemePropId.data),
  MaterialScaffoldProps() =>
    _fieldMask(MaterialScaffoldPropId.hasAppBar) |
        _fieldMask(MaterialScaffoldPropId.hasFloatingActionButton) |
        _fieldMask(MaterialScaffoldPropId.floatingActionButtonLocation) |
        _fieldMask(MaterialScaffoldPropId.hasBottomNavigationBar) |
        _fieldMask(MaterialScaffoldPropId.hasBottomSheet),
  MaterialButtonProps(:final variant) => switch (variant) {
    MaterialButtonVariant.elevated =>
      _fieldMask(MaterialElevatedButtonPropId.enabled) |
          _fieldMask(MaterialElevatedButtonPropId.autofocus),
    MaterialButtonVariant.text =>
      _fieldMask(MaterialTextButtonPropId.enabled) |
          _fieldMask(MaterialTextButtonPropId.autofocus),
    MaterialButtonVariant.icon => _fieldMask(MaterialIconButtonPropId.enabled),
    MaterialButtonVariant.filled =>
      _fieldMask(MaterialFilledButtonPropId.enabled) |
          _fieldMask(MaterialFilledButtonPropId.autofocus),
    MaterialButtonVariant.filledTonal =>
      _fieldMask(MaterialFilledTonalButtonPropId.enabled) |
          _fieldMask(MaterialFilledTonalButtonPropId.autofocus),
    MaterialButtonVariant.outlined =>
      _fieldMask(MaterialOutlinedButtonPropId.enabled) |
          _fieldMask(MaterialOutlinedButtonPropId.autofocus),
  },
  MaterialFloatingActionButtonProps() =>
    _fieldMask(MaterialFloatingActionButtonPropId.variant) |
        _fieldMask(MaterialFloatingActionButtonPropId.enabled) |
        _fieldMask(MaterialFloatingActionButtonPropId.autofocus),
  MaterialNavigationBarProps() =>
    _fieldMask(MaterialNavigationBarPropId.selectedIndex) |
        _fieldMask(MaterialNavigationBarPropId.destinations) |
        _fieldMask(MaterialNavigationBarPropId.autoLayout) |
        _fieldMask(MaterialNavigationBarPropId.layout) |
        _fieldMask(MaterialNavigationBarPropId.alignment) |
        _fieldMask(MaterialNavigationBarPropId.labelBehavior) |
        _fieldMask(MaterialNavigationBarPropId.iconBehavior) |
        _fieldMask(MaterialNavigationBarPropId.size) |
        _fieldMask(MaterialNavigationBarPropId.shape) |
        _fieldMask(MaterialNavigationBarPropId.density) |
        _fieldMask(MaterialNavigationBarPropId.safeArea) |
        _fieldMask(MaterialNavigationBarPropId.semanticLabel),
  MaterialRadioGroupProps() =>
    _fieldMask(MaterialRadioGroupPropId.selectedId) |
        _fieldMask(MaterialRadioGroupPropId.options),
  MaterialSegmentedButtonProps() =>
    _fieldMask(MaterialSegmentedButtonPropId.selectedIds) |
        _fieldMask(MaterialSegmentedButtonPropId.enabled) |
        _fieldMask(MaterialSegmentedButtonPropId.multiSelectionEnabled) |
        _fieldMask(MaterialSegmentedButtonPropId.segments),
  MaterialSliderProps() =>
    _fieldMask(MaterialSliderPropId.value) |
        _fieldMask(MaterialSliderPropId.min) |
        _fieldMask(MaterialSliderPropId.max) |
        _fieldMask(MaterialSliderPropId.divisions) |
        _fieldMask(MaterialSliderPropId.label) |
        _fieldMask(MaterialSliderPropId.enabled) |
        _fieldMask(MaterialSliderPropId.hasOnChange) |
        _fieldMask(MaterialSliderPropId.kind),
  MaterialRangeSliderProps() =>
    _fieldMask(MaterialRangeSliderPropId.start) |
        _fieldMask(MaterialRangeSliderPropId.endValue) |
        _fieldMask(MaterialRangeSliderPropId.min) |
        _fieldMask(MaterialRangeSliderPropId.max) |
        _fieldMask(MaterialRangeSliderPropId.divisions) |
        _fieldMask(MaterialRangeSliderPropId.labelStart) |
        _fieldMask(MaterialRangeSliderPropId.labelEnd) |
        _fieldMask(MaterialRangeSliderPropId.enabled) |
        _fieldMask(MaterialRangeSliderPropId.hasOnChange) |
        _fieldMask(MaterialRangeSliderPropId.kind),
  MaterialChipProps() =>
    _fieldMask(MaterialActionChipPropId.enabled) |
        _fieldMask(MaterialActionChipPropId.selected) |
        _fieldMask(MaterialActionChipPropId.hasLeading) |
        _fieldMask(MaterialActionChipPropId.hasOnDelete) |
        _fieldMask(MaterialActionChipPropId.presentation),
  MaterialSearchBarProps() => (1 << 15) - 1,
  MaterialTextFieldProps() => (1 << 19) - 1,
  MaterialDataTableProps() => (1 << 9) - 1,
  MaterialStepperProps() => (1 << 3) - 1,
  MaterialExpansionPanelListProps() => (1 << 3) - 1,
  MaterialSimpleDialogProps() => (1 << 2) - 1,
  MaterialFullscreenDialogProps() => 0,
  MaterialCheckboxProps() =>
    _fieldMask(MaterialCheckboxPropId.value) |
        _fieldMask(MaterialCheckboxPropId.enabled),
  MaterialSwitchProps() =>
    _fieldMask(MaterialSwitchPropId.value) |
        _fieldMask(MaterialSwitchPropId.enabled),
  MaterialDividerProps() => (1 << 5) - 1,
  MaterialCardProps() =>
    _fieldMask(MaterialCardPropId.elevation) |
        _fieldMask(MaterialCardPropId.variant),
  MaterialCircularProgressProps() =>
    _fieldMask(MaterialCircularProgressIndicatorPropId.value) |
        _fieldMask(MaterialCircularProgressIndicatorPropId.wavy),
  MaterialLinearProgressProps() =>
    _fieldMask(MaterialLinearProgressIndicatorPropId.value) |
        _fieldMask(MaterialLinearProgressIndicatorPropId.wavy),
  MaterialExpressiveProps() => (1 << 10) - 1,
  CupertinoButtonProps() => _fieldMask(CupertinoButtonPropId.enabled),
  CupertinoSwitchProps() =>
    _fieldMask(CupertinoSwitchPropId.value) |
        _fieldMask(CupertinoSwitchPropId.enabled),
  OverlayProps() =>
    _fieldMask(OverlayPropId.alignment) | _fieldMask(OverlayPropId.dismissible),
  NavigatorProps() => _fieldMask(NavigatorPropId.restorationScopeId),
  PageProps() =>
    _fieldMask(PagePropId.pageKey) |
        _fieldMask(PagePropId.transition) |
        _fieldMask(PagePropId.canPop) |
        _fieldMask(PagePropId.restorationId) |
        _fieldMask(PagePropId.presentation) |
        _fieldMask(PagePropId.modalBarrierDismissible) |
        _fieldMask(PagePropId.modalBarrierColor) |
        _fieldMask(PagePropId.modalBarrierLabel) |
        _fieldMask(PagePropId.modalUseSafeArea) |
        _fieldMask(PagePropId.modalRequestFocus) |
        _fieldMask(PagePropId.modalTransitionDurationMs) |
        _fieldMask(PagePropId.modalReverseTransitionDurationMs) |
        _fieldMask(PagePropId.modalSizing) |
        _fieldMask(PagePropId.modalDetents) |
        _fieldMask(PagePropId.modalInitialDetent) |
        _fieldMask(PagePropId.modalDismissOnDrag) |
        _fieldMask(PagePropId.modalHandleSemanticsLabel) |
        _fieldMask(PagePropId.modalMediumSemanticsValue) |
        _fieldMask(PagePropId.modalLargeSemanticsValue) |
        _fieldMask(PagePropId.dialogBarrierDismissible) |
        _fieldMask(PagePropId.dialogBarrierColor) |
        _fieldMask(PagePropId.dialogBarrierLabel) |
        _fieldMask(PagePropId.dialogUseSafeArea) |
        _fieldMask(PagePropId.dialogRequestFocus) |
        _fieldMask(PagePropId.dialogTransitionDurationMs) |
        _fieldMask(PagePropId.dialogReverseTransitionDurationMs),
  SafeAreaProps() =>
    _fieldMask(SafeAreaPropId.left) |
        _fieldMask(SafeAreaPropId.top) |
        _fieldMask(SafeAreaPropId.right) |
        _fieldMask(SafeAreaPropId.bottom) |
        _fieldMask(SafeAreaPropId.minimum),
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

void _validateMaterialNavigation(MaterialNavigationBarProps props) {
  final MaterialNavigationBarProps(:selectedIndex, :destinations) = props;
  if (destinations.length < 2) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'NavigationBar needs two destinations',
    );
  }
  if (selectedIndex < 0 || selectedIndex >= destinations.length) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'NavigationBar index is outside destinations',
    );
  }
  if (destinations.any((destination) => destination.label.trim().isEmpty)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Navigation destination label is empty',
    );
  }
  if (destinations.any(
    (destination) =>
        (destination.badgeCount != null && destination.badgeCount! < 0) ||
        (destination.badgeCount != null && destination.badgeDot),
  )) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid navigation badge');
  }
  if (props.layout > 1 ||
      props.alignment > 2 ||
      props.labelBehavior > 2 ||
      props.iconBehavior > 2 ||
      props.size > 1 ||
      props.shape > 1 ||
      props.density > 1) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid navigation bar enum');
  }
}

void _validateMaterialRadio(
  int? selectedId,
  List<MaterialRadioOptionProps> options,
) {
  final ids = <int>{};
  for (final option in options) {
    if (!ids.add(option.id)) {
      _fail(ProtocolErrorCode.invalidProps, 'Radio option IDs must be unique');
    }
  }
  if (selectedId != null && !ids.contains(selectedId)) {
    _fail(ProtocolErrorCode.invalidProps, 'Selected radio ID is absent');
  }
}

void _validateMaterialSegmentedButton(MaterialSegmentedButtonProps props) {
  if (props.segments.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'SegmentedButton needs a segment');
  }
  final segmentIds = <int>{};
  for (final segment in props.segments) {
    if (!segmentIds.add(segment.id)) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'SegmentedButton segment IDs must be unique',
      );
    }
  }
  for (var index = 0; index < props.selectedIds.length; index += 1) {
    final id = props.selectedIds[index];
    if (!segmentIds.contains(id)) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'SegmentedButton selected ID is absent',
      );
    }
    if (index > 0 && props.selectedIds[index - 1] >= id) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'SegmentedButton selected IDs must be sorted and unique',
      );
    }
  }
  if (!props.multiSelectionEnabled && props.selectedIds.length > 1) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'SegmentedButton single-selection mode has multiple IDs',
    );
  }
  if (!props.multiSelectionEnabled && props.selectedIds.isEmpty) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'SegmentedButton single-selection mode requires a selected ID',
    );
  }
}

void _writeMaterialSegmentedButton(
  _Writer writer,
  MaterialSegmentedButtonProps props,
) {
  _validateMaterialSegmentedButton(props);
  if (props.selectedIds.length > 0xffff || props.segments.length > 0xffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'SegmentedButton counts must fit uint16',
    );
  }
  writer.uint16(props.selectedIds.length);
  for (final id in props.selectedIds) {
    writer.int64(id);
  }
  writer
    ..uint8(props.enabled ? 1 : 0)
    ..uint8(props.multiSelectionEnabled ? 1 : 0)
    ..uint16(props.segments.length);
  for (final segment in props.segments) {
    writer
      ..int64(segment.id)
      ..uint8(segment.hasIcon ? 1 : 0);
  }
}

void _validateMaterialSlider(MaterialSliderProps props) {
  if (!props.value.isFinite || !props.min.isFinite || !props.max.isFinite) {
    _fail(ProtocolErrorCode.invalidProps, 'Slider values must be finite');
  }
  if (props.min >= props.max ||
      props.value < props.min ||
      props.value > props.max) {
    _fail(ProtocolErrorCode.invalidProps, 'Slider domain or value is invalid');
  }
  if (props.divisions case final divisions? when divisions <= 0) {
    _fail(ProtocolErrorCode.invalidProps, 'Slider divisions must be positive');
  }
  if (props.kind < 0 || props.kind > 5) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid slider kind');
  }
}

void _validateProgressValue(double? value) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Progress value must be finite and in 0..1',
    );
  }
}

double? _readProgressValue(_Reader reader) {
  final value = reader.optionalFloat64();
  _validateProgressValue(value);
  return value;
}

void _validateMaterialRangeSlider(MaterialRangeSliderProps props) {
  if (props.kind < 0 || props.kind > 1) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid range slider kind');
  }
  _validateMaterialSlider(
    MaterialSliderProps(
      value: props.start,
      min: props.min,
      max: props.max,
      divisions: props.divisions,
      label: props.labelStart,
      enabled: props.enabled,
      hasOnChange: props.hasOnChange,
      kind: 0,
    ),
  );
  _validateMaterialSlider(
    MaterialSliderProps(
      value: props.end,
      min: props.min,
      max: props.max,
      divisions: props.divisions,
      label: props.labelEnd,
      enabled: props.enabled,
      hasOnChange: props.hasOnChange,
      kind: 0,
    ),
  );
  if (props.start > props.end) {
    _fail(ProtocolErrorCode.invalidProps, 'RangeSlider selection is reversed');
  }
}

MaterialNavigationBarProps _readMaterialNavigationBar(_Reader reader) {
  final selectedIndex = reader.uint32();
  final destinations = List.generate(
    reader.uint16(),
    (_) => MaterialNavigationDestinationProps(
      label: reader.string(),
      hasSelectedIcon: reader.boolean(),
      badgeCount: reader.optionalUint32(),
      badgeDot: reader.boolean(),
      semanticLabel: reader.optionalString(),
    ),
  );
  final props = MaterialNavigationBarProps(
    selectedIndex: selectedIndex,
    destinations: destinations,
    autoLayout: reader.boolean(),
    layout: reader.uint8(),
    alignment: reader.uint8(),
    labelBehavior: reader.uint8(),
    iconBehavior: reader.uint8(),
    size: reader.uint8(),
    shape: reader.uint8(),
    density: reader.uint8(),
    safeArea: reader.boolean(),
    semanticLabel: reader.optionalString(),
  );
  _validateMaterialNavigation(props);
  return props;
}

MaterialRadioGroupProps _readMaterialRadioGroup(_Reader reader) {
  final selectedId = switch (reader.uint8()) {
    0 => null,
    1 => reader.int64(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid radio tag $value',
    ),
  };
  final options = List.generate(
    reader.uint16(),
    (_) => MaterialRadioOptionProps(
      id: reader.int64(),
      enabled: reader.boolean(),
      hasLabel: reader.boolean(),
    ),
  );
  _validateMaterialRadio(selectedId, options);
  return MaterialRadioGroupProps(selectedId: selectedId, options: options);
}

MaterialSegmentedButtonProps _readMaterialSegmentedButton(_Reader reader) {
  final selectedIds = List<int>.generate(
    reader.uint16(),
    (_) => reader.int64(),
  );
  final enabled = reader.boolean();
  final multiSelectionEnabled = reader.boolean();
  final segments = List<MaterialSegmentProps>.generate(
    reader.uint16(),
    (_) => MaterialSegmentProps(id: reader.int64(), hasIcon: reader.boolean()),
  );
  final props = MaterialSegmentedButtonProps(
    selectedIds: selectedIds,
    enabled: enabled,
    multiSelectionEnabled: multiSelectionEnabled,
    segments: segments,
  );
  _validateMaterialSegmentedButton(props);
  return props;
}

MaterialSliderProps _readMaterialSlider(_Reader reader) {
  final props = MaterialSliderProps(
    value: reader.finiteFloat64(),
    min: reader.finiteFloat64(),
    max: reader.finiteFloat64(),
    divisions: reader.optionalUint32(),
    label: reader.optionalString(),
    enabled: reader.boolean(),
    hasOnChange: reader.boolean(),
    kind: reader.uint8(),
  );
  _validateMaterialSlider(props);
  return props;
}

MaterialRangeSliderProps _readMaterialRangeSlider(_Reader reader) {
  final props = MaterialRangeSliderProps(
    start: reader.finiteFloat64(),
    end: reader.finiteFloat64(),
    min: reader.finiteFloat64(),
    max: reader.finiteFloat64(),
    divisions: reader.optionalUint32(),
    labelStart: reader.optionalString(),
    labelEnd: reader.optionalString(),
    enabled: reader.boolean(),
    hasOnChange: reader.boolean(),
    kind: reader.uint8(),
  );
  _validateMaterialRangeSlider(props);
  return props;
}

void _writeMaterialExpressive(_Writer writer, MaterialExpressiveProps props) {
  if (props.component < 0 || props.component > 0xff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Material expressive component is outside u8',
    );
  }
  if (props.variant < 0 || props.variant > 0xff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Material expressive variant is outside u8',
    );
  }
  if (props.items.length > 0xffff || props.selectedIds.length > 0xffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Material expressive descriptor count is outside u16',
    );
  }
  writer
    ..uint8(props.component)
    ..uint8(props.variant)
    ..uint64(props.flags)
    ..optionalString(props.primaryText)
    ..optionalString(props.secondaryText)
    ..optionalFloat64(props.value)
    ..optionalFloat64(props.endValue)
    ..uint16(props.selectedIds.length);
  for (final id in props.selectedIds) {
    writer.int64(id);
  }
  writer.uint16(props.items.length);
  for (final item in props.items) {
    if (item.kind < 0 || item.kind > 0xff || item.childCount > 0xffff) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Material expressive item metadata is outside its wire range',
      );
    }
    writer
      ..int64(item.id)
      ..uint8(item.kind)
      ..string(item.label)
      ..uint8(item.enabled ? 1 : 0)
      ..uint8(item.selected ? 1 : 0)
      ..uint16(item.childCount);
  }
  writer.uint8(props.textInput == null ? 0 : 1);
  if (props.textInput case final textInput?) {
    _writeTextInputProps(writer, textInput);
  }
}

MaterialExpressiveProps _readMaterialExpressive(_Reader reader) {
  final component = reader.uint8();
  final variant = reader.uint8();
  final flags = reader.uint64();
  final primaryText = reader.optionalString();
  final secondaryText = reader.optionalString();
  final value = reader.optionalFloat64();
  final endValue = reader.optionalFloat64();
  final selectedIds = List<int>.generate(
    reader.uint16(),
    (_) => reader.int64(),
    growable: false,
  );
  final items = List<MaterialExpressiveItemProps>.generate(
    reader.uint16(),
    (_) => MaterialExpressiveItemProps(
      id: reader.int64(),
      kind: reader.uint8(),
      label: reader.string(),
      enabled: reader.boolean(),
      selected: reader.boolean(),
      childCount: reader.uint16(),
    ),
    growable: false,
  );
  final textInput = switch (reader.uint8()) {
    0 => null,
    1 => _readTextInputProps(reader),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid expressive search text input tag $value',
    ),
  };
  return MaterialExpressiveProps(
    component: component,
    variant: variant,
    flags: flags,
    primaryText: primaryText,
    secondaryText: secondaryText,
    value: value,
    endValue: endValue,
    selectedIds: selectedIds,
    items: items,
    textInput: textInput,
  );
}

MaterialChipProps _readMaterialChip(
  _Reader reader,
  MaterialChipVariant variant,
) {
  final props = MaterialChipProps(
    variant: variant,
    enabled: reader.boolean(),
    selected: reader.boolean(),
    hasLeading: reader.boolean(),
    hasOnDelete: reader.boolean(),
    presentation: _enumValue(
      MaterialChipPresentation.values,
      reader.uint8(),
      'chip presentation',
    ),
  );
  _validateMaterialChip(props);
  return props;
}

void _validateMaterialChip(MaterialChipProps props) {
  if (props.variant == MaterialChipVariant.input &&
      props.presentation == MaterialChipPresentation.elevated) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'InputChip does not support elevated presentation',
    );
  }
}

void _validateMaterialDivider(MaterialDividerProps props) {
  if ([
    props.thickness,
    props.spacing,
    props.indent,
    props.endIndent,
  ].any((value) => !value.isFinite || value < 0)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Divider geometry must be finite and non-negative',
    );
  }
}

MaterialDividerProps _readMaterialDivider(_Reader reader) {
  final props = MaterialDividerProps(
    orientation: _enumValue(
      MaterialDividerOrientation.values,
      reader.uint8(),
      'divider orientation',
    ),
    thickness: reader.finiteFloat64(),
    spacing: reader.finiteFloat64(),
    indent: reader.finiteFloat64(),
    endIndent: reader.finiteFloat64(),
  );
  _validateMaterialDivider(props);
  return props;
}

void _validateMaterialCard(MaterialCardProps props) {
  if (!props.elevation.isFinite || props.elevation < 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Card elevation must be finite and non-negative',
    );
  }
}

MaterialCardProps _readMaterialCard(_Reader reader) {
  final props = MaterialCardProps(
    elevation: reader.finiteFloat64(),
    variant: _enumValue(
      MaterialCardVariant.values,
      reader.uint8(),
      'card variant',
    ),
  );
  _validateMaterialCard(props);
  return props;
}

void _validateMaterialSearchBar(MaterialSearchBarProps props) {
  _checkUint64('search bar session ID', props.sessionId);
  _checkUint64('search bar document revision', props.documentRevision);
  _checkUint64(
    'search bar accepted local revision',
    props.acceptedLocalRevision,
  );
  final maxUtf8Bytes = props.maxUtf8Bytes;
  if (maxUtf8Bytes != null &&
      (maxUtf8Bytes <= 0 || maxUtf8Bytes > ProtocolLimits.maxStringBytes)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'SearchBar max UTF-8 bytes is outside the protocol string limit',
    );
  }
  if (props.trailingCount < 0 || props.trailingCount > 0xffffffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'SearchBar trailing child count must fit uint32',
    );
  }
}

void _validateMaterialTextField(MaterialTextFieldProps props) {
  _checkUint64('text field session ID', props.sessionId);
  _checkUint64('text field document revision', props.documentRevision);
  _checkUint64(
    'text field accepted local revision',
    props.acceptedLocalRevision,
  );
  final maxUtf8Bytes = props.maxUtf8Bytes;
  if (maxUtf8Bytes != null &&
      (maxUtf8Bytes <= 0 || maxUtf8Bytes > ProtocolLimits.maxStringBytes)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'TextField max UTF-8 bytes is outside the protocol string limit',
    );
  }
  if (props.variant < 0 || props.variant > 1) {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid text field variant');
  }
  if (props.maxLines <= 0 || props.maxLines > 0xffffffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'TextField max lines must fit uint32',
    );
  }
}

void _writeMaterialTextField(_Writer writer, MaterialTextFieldProps props) {
  _validateMaterialTextField(props);
  writer
    ..uint64(props.sessionId)
    ..uint64(props.documentRevision)
    ..string(props.value.text);
  _writeTextRange(writer, props.value.text, props.value.selection);
  if (props.value.composing case final composing?) {
    writer.uint8(1);
    _writeTextRange(writer, props.value.text, composing);
  } else {
    writer.uint8(0);
  }
  writer
    ..uint8(props.enabled ? 1 : 0)
    ..uint8(props.readOnly ? 1 : 0)
    ..uint8(props.obscureText ? 1 : 0)
    ..uint8(props.keyboardType.index)
    ..uint8(props.inputAction.index)
    ..uint64(props.acceptedLocalRevision)
    ..uint8(props.updateMode.index)
    ..optionalUint32(props.maxUtf8Bytes)
    ..uint8(props.variant)
    ..optionalString(props.label)
    ..optionalString(props.supportingText)
    ..optionalString(props.errorText)
    ..uint8(props.hasLeading ? 1 : 0)
    ..uint8(props.hasTrailing ? 1 : 0)
    ..uint32(props.maxLines)
    ..uint8(props.autofocus ? 1 : 0);
}

MaterialTextFieldProps _readMaterialTextField(_Reader reader) {
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
  final props = MaterialTextFieldProps(
    sessionId: sessionId,
    documentRevision: documentRevision,
    value: TextEditingStateValue(
      text: text,
      selection: selection,
      composing: composing,
    ),
    enabled: reader.boolean(),
    readOnly: reader.boolean(),
    obscureText: reader.boolean(),
    keyboardType: _enumValue(
      TextKeyboardType.values,
      reader.uint8(),
      'keyboard type',
    ),
    inputAction: _enumValue(
      TextInputActionKind.values,
      reader.uint8(),
      'input action',
    ),
    acceptedLocalRevision: reader.uint64(),
    updateMode: _enumValue(
      TextUpdateMode.values,
      reader.uint8(),
      'update mode',
    ),
    maxUtf8Bytes: reader.optionalUint32(),
    variant: reader.uint8(),
    label: reader.optionalString(),
    supportingText: reader.optionalString(),
    errorText: reader.optionalString(),
    hasLeading: reader.boolean(),
    hasTrailing: reader.boolean(),
    maxLines: reader.uint32(),
    autofocus: reader.boolean(),
  );
  _validateMaterialTextField(props);
  return props;
}

void _validateCanonicalIds(List<int> ids, Set<int> knownIds, String label) {
  for (var index = 0; index < ids.length; index += 1) {
    final id = ids[index];
    if (!knownIds.contains(id)) {
      _fail(ProtocolErrorCode.invalidProps, '$label ID is absent');
    }
    if (index > 0 && ids[index - 1] >= id) {
      _fail(
        ProtocolErrorCode.invalidProps,
        '$label IDs must be sorted and unique',
      );
    }
  }
}

void _validateMaterialDataTable(MaterialDataTableProps props) {
  if (props.columns.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'DataTable needs a column');
  }
  if (props.columns.length > 0xffff ||
      props.rows.length > 0xffff ||
      props.selectedRowIds.length > 0xffff) {
    _fail(ProtocolErrorCode.invalidProps, 'DataTable counts must fit uint16');
  }
  final columnIds = <int>{};
  for (final column in props.columns) {
    if (!columnIds.add(column.id)) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'DataTable column IDs must be unique',
      );
    }
    if (column.tooltip case final tooltip? when tooltip.trim().isEmpty) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'DataTable tooltip must not be empty',
      );
    }
  }
  final rowIds = <int>{};
  for (final row in props.rows) {
    if (!rowIds.add(row.id)) {
      _fail(ProtocolErrorCode.invalidProps, 'DataTable row IDs must be unique');
    }
    if (row.cells.length != props.columns.length) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'DataTable rows must have one cell per column',
      );
    }
  }
  final sortColumnId = props.sortColumnId;
  if (sortColumnId != null && !columnIds.contains(sortColumnId)) {
    _fail(ProtocolErrorCode.invalidProps, 'DataTable sort column ID is absent');
  }
  _validateCanonicalIds(props.selectedRowIds, rowIds, 'DataTable selected row');
}

void _validateMaterialStepper(MaterialStepperProps props) {
  if (props.steps.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'Stepper needs a step');
  }
  if (props.steps.length > 0xffff) {
    _fail(ProtocolErrorCode.invalidProps, 'Stepper count must fit uint16');
  }
  final ids = <int>{};
  for (final step in props.steps) {
    if (!ids.add(step.id)) {
      _fail(ProtocolErrorCode.invalidProps, 'Stepper IDs must be unique');
    }
  }
  if (!ids.contains(props.currentStepId)) {
    _fail(ProtocolErrorCode.invalidProps, 'Stepper current ID is absent');
  }
}

void _validateMaterialExpansionPanels(MaterialExpansionPanelListProps props) {
  if (props.expandedIds.length > 0xffff || props.panels.length > 0xffff) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'ExpansionPanelList counts must fit uint16',
    );
  }
  final ids = <int>{};
  for (final panel in props.panels) {
    if (!ids.add(panel.id)) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'ExpansionPanelList IDs must be unique',
      );
    }
  }
  _validateCanonicalIds(props.expandedIds, ids, 'Expanded panel');
  if (props.policy == MaterialExpansionPanelPolicy.single &&
      props.expandedIds.length > 1) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Single ExpansionPanelList has multiple expanded IDs',
    );
  }
}

void _validateMaterialSimpleDialog(MaterialSimpleDialogProps props) {
  if (props.options.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'SimpleDialog needs an option');
  }
  if (props.options.length > 0xffff) {
    _fail(ProtocolErrorCode.invalidProps, 'SimpleDialog count must fit uint16');
  }
  final ids = <int>{};
  for (final option in props.options) {
    if (!ids.add(option.id)) {
      _fail(ProtocolErrorCode.invalidProps, 'SimpleDialog IDs must be unique');
    }
  }
}

void _writeAdditionalMaterialProps(_Writer writer, UiProps props) {
  switch (props) {
    case MaterialSearchBarProps(
      :final sessionId,
      :final documentRevision,
      :final value,
      :final enabled,
      :final readOnly,
      :final keyboardType,
      :final inputAction,
      :final acceptedLocalRevision,
      :final updateMode,
      :final autofocus,
      :final maxUtf8Bytes,
      :final hasLeading,
      :final trailingCount,
      :final hintText,
      :final hasOnTap,
    ):
      _validateMaterialSearchBar(props);
      writer
        ..uint64(sessionId)
        ..uint64(documentRevision)
        ..string(value.text);
      _writeTextRange(writer, value.text, value.selection);
      if (value.composing case final composing?) {
        writer.uint8(1);
        _writeTextRange(writer, value.text, composing);
      } else {
        writer.uint8(0);
      }
      writer
        ..uint8(enabled ? 1 : 0)
        ..uint8(readOnly ? 1 : 0)
        ..uint8(keyboardType.index)
        ..uint8(inputAction.index)
        ..uint64(acceptedLocalRevision)
        ..uint8(updateMode.index)
        ..uint8(autofocus ? 1 : 0)
        ..optionalUint32(maxUtf8Bytes)
        ..uint8(hasLeading ? 1 : 0)
        ..uint32(trailingCount)
        ..optionalString(hintText)
        ..uint8(hasOnTap ? 1 : 0);
    case MaterialDataTableProps(
      :final columns,
      :final rows,
      :final sortColumnId,
      :final sortAscending,
      :final selectedRowIds,
      :final hasOnSort,
      :final hasOnRowSelected,
      :final hasOnSelectAll,
      :final hasOnCellActivate,
    ):
      _validateMaterialDataTable(props);
      writer.uint16(columns.length);
      for (final column in columns) {
        writer
          ..int64(column.id)
          ..optionalString(column.tooltip)
          ..uint8(column.numeric ? 1 : 0)
          ..uint8(column.sortable ? 1 : 0);
      }
      writer.uint16(rows.length);
      for (final row in rows) {
        writer
          ..int64(row.id)
          ..uint8(row.selected ? 1 : 0)
          ..uint8(row.selectionEnabled ? 1 : 0)
          ..uint16(row.cells.length);
        for (final cell in row.cells) {
          writer
            ..uint8(cell.placeholder ? 1 : 0)
            ..uint8(cell.showEditIcon ? 1 : 0)
            ..uint8(cell.activatable ? 1 : 0);
        }
      }
      if (sortColumnId == null) {
        writer.uint8(0);
      } else {
        writer
          ..uint8(1)
          ..int64(sortColumnId);
      }
      writer
        ..uint8(sortAscending ? 1 : 0)
        ..uint16(selectedRowIds.length);
      for (final id in selectedRowIds) {
        writer.int64(id);
      }
      writer
        ..uint8(hasOnSort ? 1 : 0)
        ..uint8(hasOnRowSelected ? 1 : 0)
        ..uint8(hasOnSelectAll ? 1 : 0)
        ..uint8(hasOnCellActivate ? 1 : 0);
    case MaterialStepperProps(
      :final orientation,
      :final currentStepId,
      :final steps,
    ):
      _validateMaterialStepper(props);
      writer
        ..uint8(orientation == MaterialStepperOrientation.horizontal ? 0 : 1)
        ..int64(currentStepId)
        ..uint16(steps.length);
      for (final step in steps) {
        writer
          ..int64(step.id)
          ..uint8(step.active ? 1 : 0)
          ..uint8(step.state.index)
          ..uint8(step.hasSubtitle ? 1 : 0)
          ..uint8(step.hasLabel ? 1 : 0);
      }
    case MaterialExpansionPanelListProps(
      :final policy,
      :final expandedIds,
      :final panels,
    ):
      _validateMaterialExpansionPanels(props);
      writer
        ..uint8(policy.index)
        ..uint16(expandedIds.length);
      for (final id in expandedIds) {
        writer.int64(id);
      }
      writer.uint16(panels.length);
      for (final panel in panels) {
        writer
          ..int64(panel.id)
          ..uint8(panel.enabled ? 1 : 0)
          ..uint8(panel.canTapOnHeader ? 1 : 0);
      }
    case MaterialSimpleDialogProps(:final hasTitle, :final options):
      _validateMaterialSimpleDialog(props);
      writer
        ..uint8(hasTitle ? 1 : 0)
        ..uint16(options.length);
      for (final option in options) {
        writer
          ..int64(option.id)
          ..uint8(option.enabled ? 1 : 0);
      }
    case MaterialFullscreenDialogProps():
      break;
    default:
      throw ArgumentError.value(props, 'props');
  }
}

UiProps _readAdditionalMaterialProps(_Reader reader, NodeKind kind) {
  if (kind == NodeKind.materialSearchBar) {
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
    final props = MaterialSearchBarProps(
      sessionId: sessionId,
      documentRevision: documentRevision,
      value: TextEditingStateValue(
        text: text,
        selection: selection,
        composing: composing,
      ),
      enabled: reader.boolean(),
      readOnly: reader.boolean(),
      keyboardType: _enumValue(
        TextKeyboardType.values,
        reader.uint8(),
        'keyboard type',
      ),
      inputAction: _enumValue(
        TextInputActionKind.values,
        reader.uint8(),
        'input action',
      ),
      acceptedLocalRevision: reader.uint64(),
      updateMode: _enumValue(
        TextUpdateMode.values,
        reader.uint8(),
        'update mode',
      ),
      autofocus: reader.boolean(),
      maxUtf8Bytes: reader.optionalUint32(),
      hasLeading: reader.boolean(),
      trailingCount: reader.uint32(),
      hintText: reader.optionalString(),
      hasOnTap: reader.boolean(),
    );
    _validateMaterialSearchBar(props);
    return props;
  }
  if (kind == NodeKind.materialDataTable) {
    final columns = List.generate(
      reader.uint16(),
      (_) => MaterialDataTableColumnProps(
        id: reader.int64(),
        tooltip: reader.optionalString(),
        numeric: reader.boolean(),
        sortable: reader.boolean(),
      ),
    );
    final rows = List.generate(reader.uint16(), (_) {
      final id = reader.int64();
      final selected = reader.boolean();
      final selectionEnabled = reader.boolean();
      final cells = List.generate(
        reader.uint16(),
        (_) => MaterialDataTableCellProps(
          placeholder: reader.boolean(),
          showEditIcon: reader.boolean(),
          activatable: reader.boolean(),
        ),
      );
      return MaterialDataTableRowProps(
        id: id,
        selected: selected,
        selectionEnabled: selectionEnabled,
        cells: cells,
      );
    });
    final sortColumnId = switch (reader.uint8()) {
      0 => null,
      1 => reader.int64(),
      final value => _fail(
        ProtocolErrorCode.invalidProps,
        'Invalid optional sort ID tag $value',
      ),
    };
    final sortAscending = reader.boolean();
    final selectedRowIds = List.generate(
      reader.uint16(),
      (_) => reader.int64(),
    );
    final props = MaterialDataTableProps(
      columns: columns,
      rows: rows,
      sortColumnId: sortColumnId,
      sortAscending: sortAscending,
      selectedRowIds: selectedRowIds,
      hasOnSort: reader.boolean(),
      hasOnRowSelected: reader.boolean(),
      hasOnSelectAll: reader.boolean(),
      hasOnCellActivate: reader.boolean(),
    );
    _validateMaterialDataTable(props);
    return props;
  }
  if (kind == NodeKind.materialStepper) {
    final wireOrientation = reader.uint8();
    final orientation = switch (wireOrientation) {
      0 => MaterialStepperOrientation.horizontal,
      1 => MaterialStepperOrientation.vertical,
      _ => _fail(
        ProtocolErrorCode.invalidProps,
        'Invalid stepper orientation $wireOrientation',
      ),
    };
    final currentStepId = reader.int64();
    final steps = List.generate(
      reader.uint16(),
      (_) => MaterialStepProps(
        id: reader.int64(),
        active: reader.boolean(),
        state: _enumValue(
          MaterialStepState.values,
          reader.uint8(),
          'step state',
        ),
        hasSubtitle: reader.boolean(),
        hasLabel: reader.boolean(),
      ),
    );
    final props = MaterialStepperProps(
      orientation: orientation,
      currentStepId: currentStepId,
      steps: steps,
    );
    _validateMaterialStepper(props);
    return props;
  }
  if (kind == NodeKind.materialExpansionPanelList) {
    final policy = _enumValue(
      MaterialExpansionPanelPolicy.values,
      reader.uint8(),
      'panel policy',
    );
    final expandedIds = List.generate(reader.uint16(), (_) => reader.int64());
    final panels = List.generate(
      reader.uint16(),
      (_) => MaterialExpansionPanelProps(
        id: reader.int64(),
        enabled: reader.boolean(),
        canTapOnHeader: reader.boolean(),
      ),
    );
    final props = MaterialExpansionPanelListProps(
      policy: policy,
      expandedIds: expandedIds,
      panels: panels,
    );
    _validateMaterialExpansionPanels(props);
    return props;
  }
  if (kind == NodeKind.materialSimpleDialog) {
    final hasTitle = reader.boolean();
    final options = List.generate(
      reader.uint16(),
      (_) => MaterialSimpleDialogOptionProps(
        id: reader.int64(),
        enabled: reader.boolean(),
      ),
    );
    final props = MaterialSimpleDialogProps(
      hasTitle: hasTitle,
      options: options,
    );
    _validateMaterialSimpleDialog(props);
    return props;
  }
  if (kind == NodeKind.materialFullscreenDialog) {
    return const MaterialFullscreenDialogProps();
  }
  throw ArgumentError.value(kind, 'kind');
}

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
    case ShowSnackBarRequest(
      :final message,
      :final actionLabel,
      :final durationMs,
    ):
      if (message.trim().isEmpty) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Snack bar message must not be empty',
        );
      }
      if (actionLabel != null && actionLabel.trim().isEmpty) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Snack bar action label must not be empty',
        );
      }
      if (durationMs <= 0) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Snack bar duration must be positive',
        );
      }
      writer
        ..uint16(HostRequestId.showSnackBar)
        ..string(message)
        ..optionalString(actionLabel)
        ..uint32(durationMs);
    case PickDateRequest(
      :final initial,
      :final first,
      :final last,
      :final current,
      :final inputMode,
    ):
      writer.uint16(HostRequestId.pickDate);
      _writeOptionalCivilDate(writer, initial);
      _writeCivilDate(writer, first);
      _writeCivilDate(writer, last);
      _writeOptionalCivilDate(writer, current);
      writer.uint8(inputMode ? 1 : 0);
    case PickDateRangeRequest(
      :final initial,
      :final first,
      :final last,
      :final current,
      :final inputMode,
    ):
      writer.uint16(HostRequestId.pickDateRange);
      if (initial == null) {
        writer.uint8(0);
      } else {
        writer.uint8(1);
        _writeCivilDate(writer, initial.start);
        _writeCivilDate(writer, initial.end);
      }
      _writeCivilDate(writer, first);
      _writeCivilDate(writer, last);
      _writeOptionalCivilDate(writer, current);
      writer.uint8(inputMode ? 1 : 0);
    case PickTimeRequest(:final initial, :final inputMode, :final use24Hour):
      writer
        ..uint16(HostRequestId.pickTime)
        ..uint8(initial.hour)
        ..uint8(initial.minute)
        ..uint8(inputMode ? 1 : 0)
        ..uint8(use24Hour ? 1 : 0);
  }
}

void _writeCivilDate(_Writer writer, CivilDateValue date) {
  _validateCivilDate(date);
  writer
    ..uint16(date.year)
    ..uint8(date.month)
    ..uint8(date.day);
}

void _writeOptionalCivilDate(_Writer writer, CivilDateValue? date) {
  writer.uint8(date == null ? 0 : 1);
  if (date != null) _writeCivilDate(writer, date);
}

CivilDateValue _readCivilDate(_Reader reader) {
  final value = CivilDateValue(
    year: reader.uint16(),
    month: reader.uint8(),
    day: reader.uint8(),
  );
  _validateCivilDate(value);
  return value;
}

CivilDateValue? _readOptionalCivilDate(_Reader reader) {
  final tag = reader.uint8();
  if (tag == 0) return null;
  if (tag == 1) return _readCivilDate(reader);
  _fail(ProtocolErrorCode.invalidProps, 'Invalid optional civil date tag $tag');
}

void _validateCivilDate(CivilDateValue date) {
  try {
    final parsed = DateTime.utc(date.year, date.month, date.day);
    if (date.year < 1 ||
        date.year > 9999 ||
        parsed.year != date.year ||
        parsed.month != date.month ||
        parsed.day != date.day) {
      throw const FormatException();
    }
  } on FormatException {
    _fail(ProtocolErrorCode.invalidProps, 'Invalid civil date');
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
  if (requestKind == HostRequestId.showSnackBar) {
    final message = reader.string();
    final actionLabel = reader.optionalString();
    final durationMs = reader.uint32();
    if (message.trim().isEmpty) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Snack bar message must not be empty',
      );
    }
    if (actionLabel != null && actionLabel.trim().isEmpty) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Snack bar action label must not be empty',
      );
    }
    if (durationMs <= 0) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Snack bar duration must be positive',
      );
    }
    return ShowSnackBarRequest(
      message: message,
      actionLabel: actionLabel,
      durationMs: durationMs,
    );
  }
  if (requestKind == HostRequestId.pickDate) {
    return PickDateRequest(
      initial: _readOptionalCivilDate(reader),
      first: _readCivilDate(reader),
      last: _readCivilDate(reader),
      current: _readOptionalCivilDate(reader),
      inputMode: reader.boolean(),
    );
  }
  if (requestKind == HostRequestId.pickDateRange) {
    final hasInitial = reader.boolean();
    return PickDateRangeRequest(
      initial: hasInitial
          ? CivilDateRangeValue(
              start: _readCivilDate(reader),
              end: _readCivilDate(reader),
            )
          : null,
      first: _readCivilDate(reader),
      last: _readCivilDate(reader),
      current: _readOptionalCivilDate(reader),
      inputMode: reader.boolean(),
    );
  }
  if (requestKind == HostRequestId.pickTime) {
    final hour = reader.uint8();
    final minute = reader.uint8();
    if (hour > 23 || minute > 59) {
      _fail(ProtocolErrorCode.invalidProps, 'Invalid civil time');
    }
    return PickTimeRequest(
      initial: CivilTimeValue(hour: hour, minute: minute),
      inputMode: reader.boolean(),
      use24Hour: reader.boolean(),
    );
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
    if (value < 0 || value > 0xffffffff) {
      _fail(ProtocolErrorCode.invalidProps, 'ARGB color is outside u32');
    }
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

void _writePageProps(_Writer writer, PageProps props) {
  if (props.pageKey.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'Page key must not be empty');
  }
  final transition = switch (props.presentation) {
    StandardPagePresentation(:final transition) => transition,
    ModalBottomSheetPresentation() ||
    ModalDialogPresentation() ||
    ModalSideSheetPresentation() => PageTransition.none,
  };
  writer
    ..string(props.pageKey)
    ..uint8(transition.index)
    ..uint8(props.canPop ? 1 : 0)
    ..optionalString(props.restorationId);

  switch (props.presentation) {
    case StandardPagePresentation():
      writer
        ..uint8(0)
        ..uint8(0);
      _writeOptionalArgb32(writer, null);
      writer
        ..optionalString(null)
        ..uint8(0)
        ..uint8(0)
        ..uint8(0)
        ..uint32(0)
        ..uint32(0)
        ..uint8(0)
        ..uint8(0)
        ..uint8(0)
        ..optionalString(null)
        ..optionalString(null)
        ..optionalString(null)
        ..uint8(0);
      _writeOptionalArgb32(writer, null);
      writer
        ..optionalString(null)
        ..uint8(0)
        ..uint8(0)
        ..uint32(0)
        ..uint32(0);
    case ModalBottomSheetPresentation(
      :final barrierDismissible,
      :final barrierColorArgb,
      :final barrierLabel,
      :final sizing,
      :final useSafeArea,
      :final requestFocus,
      :final transitionDurationMilliseconds,
      :final reverseTransitionDurationMilliseconds,
    ):
      _checkPageDuration('Modal transition', transitionDurationMilliseconds);
      _checkPageDuration(
        'Modal reverse transition',
        reverseTransitionDurationMilliseconds,
      );
      final (sizingId, detentsId, initialDetentId, dismissOnDrag, semantics) =
          _modalSizingWireValues(sizing);
      writer
        ..uint8(1)
        ..uint8(barrierDismissible ? 1 : 0);
      _writeOptionalArgb32(writer, barrierColorArgb);
      writer
        ..optionalString(barrierLabel)
        ..uint8(sizingId)
        ..uint8(useSafeArea ? 1 : 0)
        ..uint8(requestFocus ? 1 : 0)
        ..uint32(transitionDurationMilliseconds)
        ..uint32(reverseTransitionDurationMilliseconds)
        ..uint8(detentsId)
        ..uint8(initialDetentId)
        ..uint8(dismissOnDrag ? 1 : 0)
        ..optionalString(semantics?.label)
        ..optionalString(semantics?.mediumValue)
        ..optionalString(semantics?.largeValue)
        ..uint8(0);
      _writeOptionalArgb32(writer, null);
      writer
        ..optionalString(null)
        ..uint8(0)
        ..uint8(0)
        ..uint32(0)
        ..uint32(0);
    case ModalDialogPresentation(
      :final barrierDismissible,
      :final barrierColorArgb,
      :final barrierLabel,
      :final useSafeArea,
      :final requestFocus,
      :final transitionDurationMilliseconds,
      :final reverseTransitionDurationMilliseconds,
    ):
      _writeModalSurfacePresentation(
        writer,
        kind: 2,
        name: 'Dialog',
        barrierDismissible: barrierDismissible,
        barrierColorArgb: barrierColorArgb,
        barrierLabel: barrierLabel,
        useSafeArea: useSafeArea,
        requestFocus: requestFocus,
        transitionDurationMilliseconds: transitionDurationMilliseconds,
        reverseTransitionDurationMilliseconds:
            reverseTransitionDurationMilliseconds,
      );
    case ModalSideSheetPresentation(
      :final barrierDismissible,
      :final barrierColorArgb,
      :final barrierLabel,
      :final useSafeArea,
      :final requestFocus,
      :final transitionDurationMilliseconds,
      :final reverseTransitionDurationMilliseconds,
    ):
      _writeModalSurfacePresentation(
        writer,
        kind: 3,
        name: 'Side sheet',
        barrierDismissible: barrierDismissible,
        barrierColorArgb: barrierColorArgb,
        barrierLabel: barrierLabel,
        useSafeArea: useSafeArea,
        requestFocus: requestFocus,
        transitionDurationMilliseconds: transitionDurationMilliseconds,
        reverseTransitionDurationMilliseconds:
            reverseTransitionDurationMilliseconds,
      );
  }
}

void _writeModalSurfacePresentation(
  _Writer writer, {
  required int kind,
  required String name,
  required bool barrierDismissible,
  required int? barrierColorArgb,
  required String? barrierLabel,
  required bool useSafeArea,
  required bool requestFocus,
  required int transitionDurationMilliseconds,
  required int reverseTransitionDurationMilliseconds,
}) {
  _checkPageDuration('$name transition', transitionDurationMilliseconds);
  _checkPageDuration(
    '$name reverse transition',
    reverseTransitionDurationMilliseconds,
  );
  writer
    ..uint8(kind)
    ..uint8(0);
  _writeOptionalArgb32(writer, null);
  writer
    ..optionalString(null)
    ..uint8(0)
    ..uint8(0)
    ..uint8(0)
    ..uint32(0)
    ..uint32(0)
    ..uint8(0)
    ..uint8(0)
    ..uint8(0)
    ..optionalString(null)
    ..optionalString(null)
    ..optionalString(null)
    ..uint8(barrierDismissible ? 1 : 0);
  _writeOptionalArgb32(writer, barrierColorArgb);
  writer
    ..optionalString(barrierLabel)
    ..uint8(useSafeArea ? 1 : 0)
    ..uint8(requestFocus ? 1 : 0)
    ..uint32(transitionDurationMilliseconds)
    ..uint32(reverseTransitionDurationMilliseconds);
}

(int, int, int, bool, ModalSheetHandleSemantics?) _modalSizingWireValues(
  ModalBottomSheetSizing sizing,
) => switch (sizing) {
  ContentBoundedModalSheetSizing() => (0, 0, 0, false, null),
  ScrollControlledModalSheetSizing() => (1, 0, 0, false, null),
  DetentedModalSheetSizing(
    :final detents,
    :final initialDetent,
    :final dismissOnDrag,
    :final handleSemantics,
  ) =>
    () {
      final includesInitial = switch ((detents, initialDetent)) {
        (ModalSheetDetentSet.medium, ModalSheetDetent.medium) ||
        (ModalSheetDetentSet.large, ModalSheetDetent.large) ||
        (ModalSheetDetentSet.mediumAndLarge, _) => true,
        _ => false,
      };
      if (!includesInitial) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal initial detent must belong to detents',
        );
      }
      if (handleSemantics.label.trim().isEmpty ||
          handleSemantics.mediumValue.trim().isEmpty ||
          handleSemantics.largeValue.trim().isEmpty) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal handle semantics strings must not be empty',
        );
      }
      return (
        2,
        detents.index,
        initialDetent.index,
        dismissOnDrag,
        handleSemantics,
      );
    }(),
};

void _writeSliverFixedExtent(
  _Writer writer, {
  required int totalCount,
  required int firstIndex,
  required double itemExtent,
  required int overscan,
}) {
  _validateVirtualSliverProps(
    SliverFixedExtentProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      itemExtent: itemExtent,
      overscan: overscan,
    ),
  );
  writer
    ..uint64(totalCount)
    ..uint64(firstIndex)
    ..float64(itemExtent)
    ..uint32(overscan);
}

void _writeSliverVariedExtent(
  _Writer writer, {
  required int totalCount,
  required int firstIndex,
  required double defaultItemExtent,
  required int overscan,
  required List<SparseExtentOverride> extentOverrides,
  required SparseExtentTransition? transition,
}) {
  _validateVirtualSliverProps(
    SliverVariedExtentProps(
      totalCount: totalCount,
      firstIndex: firstIndex,
      defaultItemExtent: defaultItemExtent,
      overscan: overscan,
      extentOverrides: extentOverrides,
      transition: transition,
    ),
  );
  writer
    ..uint64(totalCount)
    ..uint64(firstIndex)
    ..float64(defaultItemExtent)
    ..uint32(overscan)
    ..uint32(extentOverrides.length);
  for (final override in extentOverrides) {
    writer
      ..uint64(override.index)
      ..float64(override.extent);
  }
  if (transition == null) {
    writer
      ..optionalBool(null)
      ..optionalDurationMs(null)
      ..optionalDurationMs(null)
      ..optionalSparseExtentCurve(null)
      ..optionalSparseExtentCurve(null);
  } else {
    writer
      ..optionalBool(transition.enabled)
      ..optionalDurationMs(transition.expandDurationMs)
      ..optionalDurationMs(transition.collapseDurationMs)
      ..optionalSparseExtentCurve(transition.expandCurve)
      ..optionalSparseExtentCurve(transition.collapseCurve);
  }
}

void _writeSliverAppBar(_Writer writer, SliverAppBarProps props) {
  _validateSliverAppBarValues(props);
  writer.uint8(props.pinned ? 1 : 0);
  writer.uint8(props.floating ? 1 : 0);
  writer.uint8(props.snap ? 1 : 0);
  writer.uint8(props.hasLeading ? 1 : 0);
  _writeOptionalArgb32(writer, props.backgroundColor);
  _writeOptionalArgb32(writer, props.foregroundColor);
  writer.uint32(props.actionCount);
  writer.uint8(props.centerTitle ? 1 : 0);
  writer.optionalString(props.semanticLabel);
  writer.optionalFloat64(props.expandedHeight);
  writer.optionalFloat64(props.collapsedHeight);
  writer.float64(props.toolbarHeight);
  writer.uint8(props.hasFlexibleSpace ? 1 : 0);
  writer.uint8(props.hasBottom ? 1 : 0);
  writer.optionalFloat64(props.bottomHeight);
  writer.uint8(props.stretch ? 1 : 0);
  writer.uint8(props.forceElevated ? 1 : 0);
  writer.optionalFloat64(props.elevation);
  writer.uint8(props.automaticallyImplyLeading ? 1 : 0);
}

SliverFillProps _readSliverFillProps(_Reader reader) {
  return const SliverFillProps();
}

SliverFixedExtentProps _readSliverFixedExtentProps(_Reader reader) {
  final totalCount = reader.uint64();
  final firstIndex = reader.uint64();
  final itemExtent = reader.finiteFloat64();
  if (itemExtent <= 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Sliver item_extent must be positive',
    );
  }
  final overscan = reader.uint32();
  final props = SliverFixedExtentProps(
    totalCount: totalCount,
    firstIndex: firstIndex,
    itemExtent: itemExtent,
    overscan: overscan,
  );
  _validateVirtualSliverProps(props);
  return props;
}

SliverVariedExtentProps _readSliverVariedExtentProps(_Reader reader) {
  final totalCount = reader.uint64();
  final firstIndex = reader.uint64();
  final defaultItemExtent = reader.finiteFloat64();
  if (defaultItemExtent <= 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Sliver default_item_extent must be positive',
    );
  }
  final overscan = reader.uint32();
  final overrideCount = reader.uint32();
  if (overrideCount > totalCount) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Sliver override count is outside the logical list',
    );
  }
  final overrides = <SparseExtentOverride>[];
  for (var i = 0; i < overrideCount; i++) {
    final index = reader.uint64();
    final extent = reader.finiteFloat64();
    if (extent <= 0) {
      _fail(
        ProtocolErrorCode.invalidProps,
        'Sliver override extent must be positive',
      );
    }
    overrides.add(SparseExtentOverride(index: index, extent: extent));
  }
  final transition = _readSliverTransition(reader);
  final props = SliverVariedExtentProps(
    totalCount: totalCount,
    firstIndex: firstIndex,
    defaultItemExtent: defaultItemExtent,
    overscan: overscan,
    extentOverrides: overrides,
    transition: transition,
  );
  _validateVirtualSliverProps(props);
  return props;
}

void _validateVirtualSliverProps(UiProps props) {
  final error = virtualSliverPropsError(props);
  if (error != null) _fail(ProtocolErrorCode.invalidProps, error);
}

SparseExtentTransition? _readSliverTransition(_Reader reader) {
  final enabled = reader.optionalBool();
  final expandDurationMs = reader.optionalDurationMs();
  final collapseDurationMs = reader.optionalDurationMs();
  final expandCurve = reader.optionalSparseExtentCurve();
  final collapseCurve = reader.optionalSparseExtentCurve();
  if (enabled == null &&
      expandDurationMs == null &&
      collapseDurationMs == null &&
      expandCurve == null &&
      collapseCurve == null) {
    return null;
  }
  if (enabled != null &&
      expandDurationMs != null &&
      collapseDurationMs != null &&
      expandCurve != null &&
      collapseCurve != null) {
    return SparseExtentTransition(
      enabled: enabled,
      expandDurationMs: expandDurationMs,
      collapseDurationMs: collapseDurationMs,
      expandCurve: expandCurve,
      collapseCurve: collapseCurve,
    );
  }
  _fail(
    ProtocolErrorCode.invalidProps,
    'Sliver transition fields must be all-present or all-absent',
  );
}

SliverPaddingProps _readSliverPaddingProps(_Reader reader) {
  return SliverPaddingProps(
    EdgeInsetsValue(
      left: reader.finiteFloat64(),
      top: reader.finiteFloat64(),
      right: reader.finiteFloat64(),
      bottom: reader.finiteFloat64(),
    ),
  );
}

SliverAppBarProps _readSliverAppBarProps(_Reader reader) {
  final props = SliverAppBarProps(
    pinned: reader.boolean(),
    floating: reader.boolean(),
    snap: reader.boolean(),
    hasLeading: reader.boolean(),
    backgroundColor: _readOptionalArgb32(reader),
    foregroundColor: _readOptionalArgb32(reader),
    actionCount: reader.uint32(),
    centerTitle: reader.boolean(),
    semanticLabel: reader.optionalString(),
    expandedHeight: reader.optionalFloat64(),
    collapsedHeight: reader.optionalFloat64(),
    toolbarHeight: reader.finiteFloat64(),
    hasFlexibleSpace: reader.boolean(),
    hasBottom: reader.boolean(),
    bottomHeight: reader.optionalFloat64(),
    stretch: reader.boolean(),
    forceElevated: reader.boolean(),
    elevation: reader.optionalFloat64(),
    automaticallyImplyLeading: reader.boolean(),
  );
  _validateSliverAppBarValues(props);
  return props;
}

ScrollViewProps _readScrollViewProps(_Reader reader) {
  final axis = reader.scrollAxis();
  final reverse = reader.boolean();
  final primary = reader.boolean();
  if (axis == ScrollAxis.horizontal && primary) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Horizontal scroll view cannot be primary',
    );
  }
  final cacheExtent = reader.optionalFloat64();
  _validateCacheExtent(cacheExtent);
  return ScrollViewProps(
    axis: axis,
    reverse: reverse,
    primary: primary,
    cacheExtent: cacheExtent,
  );
}

ConstrainedBoxProps _readConstrainedBoxProps(_Reader reader) {
  final props = ConstrainedBoxProps(
    minWidth: reader.finiteFloat64(),
    maxWidth: reader.optionalFloat64(),
    minHeight: reader.finiteFloat64(),
    maxHeight: reader.optionalFloat64(),
  );
  _validateConstrainedBoxProps(props);
  return props;
}

void _validateConstrainedBoxProps(ConstrainedBoxProps props) {
  if (!props.minWidth.isFinite ||
      props.minWidth < 0 ||
      !props.minHeight.isFinite ||
      props.minHeight < 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Box constraint minima must be finite and non-negative',
    );
  }
  final maxWidth = props.maxWidth;
  if (maxWidth != null &&
      (!maxWidth.isFinite || maxWidth < 0 || props.minWidth > maxWidth)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Box constraint maximum width must be finite, non-negative, and not '
      'below its minimum',
    );
  }
  final maxHeight = props.maxHeight;
  if (maxHeight != null &&
      (!maxHeight.isFinite || maxHeight < 0 || props.minHeight > maxHeight)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'Box constraint maximum height must be finite, non-negative, and not '
      'below its minimum',
    );
  }
}

void _validateCacheExtent(double? cacheExtent) {
  if (cacheExtent != null && (!cacheExtent.isFinite || cacheExtent < 0)) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'cache_extent must be finite and non-negative',
    );
  }
}

void _validateSliverAppBarValues(SliverAppBarProps props) {
  final error = sliverAppBarPropsError(props);
  if (error != null) _fail(ProtocolErrorCode.invalidProps, error);
}

PreferredSizeProps _readPreferredSizeProps(_Reader reader) {
  final height = reader.finiteFloat64();
  if (height <= 0) {
    _fail(
      ProtocolErrorCode.invalidProps,
      'preferred_size height must be positive',
    );
  }
  return PreferredSizeProps(height: height);
}

PageProps _readPageProps(_Reader reader) {
  final pageKey = reader.string();
  if (pageKey.isEmpty) {
    _fail(ProtocolErrorCode.invalidProps, 'Page key must not be empty');
  }
  final transition = _enumValue(
    PageTransition.values,
    reader.uint8(),
    'page transition',
  );
  final canPop = reader.boolean();
  final restorationId = reader.optionalString();
  final presentationKind = reader.uint8();
  final barrierDismissible = reader.boolean();
  final barrierColorArgb = _readOptionalArgb32(reader);
  final barrierLabel = reader.optionalString();
  final sizingKind = reader.uint8();
  final useSafeArea = reader.boolean();
  final requestFocus = reader.boolean();
  final transitionDurationMilliseconds = reader.uint32();
  final reverseTransitionDurationMilliseconds = reader.uint32();
  final detents = _enumValue(
    ModalSheetDetentSet.values,
    reader.uint8(),
    'modal detent set',
  );
  final initialDetent = _enumValue(
    ModalSheetDetent.values,
    reader.uint8(),
    'modal initial detent',
  );
  final dismissOnDrag = reader.boolean();
  final handleSemanticsLabel = reader.optionalString();
  final mediumSemanticsValue = reader.optionalString();
  final largeSemanticsValue = reader.optionalString();
  final dialogBarrierDismissible = reader.boolean();
  final dialogBarrierColorArgb = _readOptionalArgb32(reader);
  final dialogBarrierLabel = reader.optionalString();
  final dialogUseSafeArea = reader.boolean();
  final dialogRequestFocus = reader.boolean();
  final dialogTransitionDurationMilliseconds = reader.uint32();
  final dialogReverseTransitionDurationMilliseconds = reader.uint32();
  final hasDialogProperties =
      dialogBarrierDismissible ||
      dialogBarrierColorArgb != null ||
      dialogBarrierLabel != null ||
      dialogUseSafeArea ||
      dialogRequestFocus ||
      dialogTransitionDurationMilliseconds != 0 ||
      dialogReverseTransitionDurationMilliseconds != 0;

  final PagePresentation presentation;
  switch (presentationKind) {
    case 0:
      if (barrierDismissible ||
          barrierColorArgb != null ||
          barrierLabel != null ||
          sizingKind != 0 ||
          useSafeArea ||
          requestFocus ||
          transitionDurationMilliseconds != 0 ||
          reverseTransitionDurationMilliseconds != 0 ||
          detents != ModalSheetDetentSet.medium ||
          initialDetent != ModalSheetDetent.medium ||
          dismissOnDrag ||
          handleSemanticsLabel != null ||
          mediumSemanticsValue != null ||
          largeSemanticsValue != null ||
          hasDialogProperties) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Standard page has noncanonical modal properties',
        );
      }
      presentation = StandardPagePresentation(transition);
    case 1:
      if (transition != PageTransition.none) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal bottom sheet cannot carry a standard transition',
        );
      }
      if (hasDialogProperties) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal bottom sheet has dialog properties',
        );
      }
      final ModalBottomSheetSizing sizing;
      switch (sizingKind) {
        case 0:
          sizing = const ContentBoundedModalSheetSizing();
        case 1:
          sizing = const ScrollControlledModalSheetSizing();
        case 2:
          final includesInitial = switch ((detents, initialDetent)) {
            (ModalSheetDetentSet.medium, ModalSheetDetent.medium) ||
            (ModalSheetDetentSet.large, ModalSheetDetent.large) ||
            (ModalSheetDetentSet.mediumAndLarge, _) => true,
            _ => false,
          };
          if (!includesInitial) {
            _fail(
              ProtocolErrorCode.invalidProps,
              'Modal initial detent must belong to detents',
            );
          }
          if (handleSemanticsLabel == null ||
              mediumSemanticsValue == null ||
              largeSemanticsValue == null ||
              handleSemanticsLabel.trim().isEmpty ||
              mediumSemanticsValue.trim().isEmpty ||
              largeSemanticsValue.trim().isEmpty) {
            _fail(
              ProtocolErrorCode.invalidProps,
              'Detented modal must include nonempty handle semantics',
            );
          }
          sizing = DetentedModalSheetSizing(
            detents: detents,
            initialDetent: initialDetent,
            dismissOnDrag: dismissOnDrag,
            handleSemantics: ModalSheetHandleSemantics(
              label: handleSemanticsLabel,
              mediumValue: mediumSemanticsValue,
              largeValue: largeSemanticsValue,
            ),
          );
        default:
          _fail(
            ProtocolErrorCode.invalidProps,
            'Invalid modal sizing $sizingKind',
          );
      }
      if (sizing is! DetentedModalSheetSizing &&
          (detents != ModalSheetDetentSet.medium ||
              initialDetent != ModalSheetDetent.medium ||
              dismissOnDrag ||
              handleSemanticsLabel != null ||
              mediumSemanticsValue != null ||
              largeSemanticsValue != null)) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Non-detented modal has noncanonical detent properties',
        );
      }
      presentation = ModalBottomSheetPresentation(
        barrierDismissible: barrierDismissible,
        barrierColorArgb: barrierColorArgb,
        barrierLabel: barrierLabel,
        sizing: sizing,
        useSafeArea: useSafeArea,
        requestFocus: requestFocus,
        transitionDurationMilliseconds: transitionDurationMilliseconds,
        reverseTransitionDurationMilliseconds:
            reverseTransitionDurationMilliseconds,
      );
    case 2:
    case 3:
      if (transition != PageTransition.none) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal surface cannot carry a standard transition',
        );
      }
      if (barrierDismissible ||
          barrierColorArgb != null ||
          barrierLabel != null ||
          sizingKind != 0 ||
          useSafeArea ||
          requestFocus ||
          transitionDurationMilliseconds != 0 ||
          reverseTransitionDurationMilliseconds != 0 ||
          detents != ModalSheetDetentSet.medium ||
          initialDetent != ModalSheetDetent.medium ||
          dismissOnDrag ||
          handleSemanticsLabel != null ||
          mediumSemanticsValue != null ||
          largeSemanticsValue != null) {
        _fail(
          ProtocolErrorCode.invalidProps,
          'Modal surface has bottom-sheet properties',
        );
      }
      presentation = presentationKind == 2
          ? ModalDialogPresentation(
              barrierDismissible: dialogBarrierDismissible,
              barrierColorArgb: dialogBarrierColorArgb,
              barrierLabel: dialogBarrierLabel,
              useSafeArea: dialogUseSafeArea,
              requestFocus: dialogRequestFocus,
              transitionDurationMilliseconds:
                  dialogTransitionDurationMilliseconds,
              reverseTransitionDurationMilliseconds:
                  dialogReverseTransitionDurationMilliseconds,
            )
          : ModalSideSheetPresentation(
              barrierDismissible: dialogBarrierDismissible,
              barrierColorArgb: dialogBarrierColorArgb,
              barrierLabel: dialogBarrierLabel,
              useSafeArea: dialogUseSafeArea,
              requestFocus: dialogRequestFocus,
              transitionDurationMilliseconds:
                  dialogTransitionDurationMilliseconds,
              reverseTransitionDurationMilliseconds:
                  dialogReverseTransitionDurationMilliseconds,
            );
    default:
      _fail(
        ProtocolErrorCode.invalidProps,
        'Invalid page presentation $presentationKind',
      );
  }
  return PageProps(
    pageKey: pageKey,
    presentation: presentation,
    canPop: canPop,
    restorationId: restorationId,
  );
}

void _checkPageDuration(String label, int value) {
  if (value < 0 || value > 0xffffffff) {
    _fail(ProtocolErrorCode.invalidProps, '$label duration is outside u32');
  }
}

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

TextInputProps _readTextInputProps(_Reader reader) {
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
  final maxUtf8Bytes = switch (reader.uint8()) {
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
    if (value < 0 || value > 0xffffffff) {
      _fail(ProtocolErrorCode.invalidProps, 'u32 value is outside u32');
    }
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void uint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void int64(int value) {
    if (value < -0x8000000000000000 || value > 0x7fffffffffffffff) {
      _fail(ProtocolErrorCode.invalidProps, 'i64 value is outside i64');
    }
    final data = ByteData(8)..setInt64(0, value, Endian.little);
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

  void optionalUint32(int? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      uint32(value);
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

  void optionalDurationMs(int? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      uint32(value);
    }
  }

  void optionalSparseExtentCurve(SparseExtentCurve? value) {
    if (value == null) {
      uint8(0);
    } else {
      uint8(1);
      uint8(value.wireId);
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

  int int64() {
    _require(8);
    final result = _data.getInt64(_position, Endian.little);
    _position += 8;
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

  int? optionalUint32() => switch (uint8()) {
    0 => null,
    1 => uint32(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional u32 tag $value',
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

  int? optionalDurationMs() => switch (uint8()) {
    0 => null,
    1 => uint32(),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional duration tag $value',
    ),
  };

  SparseExtentCurve? optionalSparseExtentCurve() => switch (uint8()) {
    0 => null,
    1 => SparseExtentCurve.fromWireId(uint8()),
    final value => _fail(
      ProtocolErrorCode.invalidProps,
      'Invalid optional curve tag $value',
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
