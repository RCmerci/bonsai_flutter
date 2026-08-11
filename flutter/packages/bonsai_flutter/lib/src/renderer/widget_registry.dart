import 'dart:collection';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../native_widget/native_widget_registry.dart';
import '../native_widget/morphing_surface.dart';
import '../native_widget/navigation_shell.dart';
import '../native_widget/sparse_extent_list.dart';
import '../native_widget/swipe_action.dart';
import '../native_widget/virtual_list.dart';
import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../store/node_store.dart';
import '../text_input/text_input_host.dart';
import 'animated_opacity_host.dart';
import 'node_host.dart';
import 'pressable_host.dart';
import 'renderer_event.dart';
import 'renderer_resource_store.dart';
import 'viewport_constraint_guard.dart';

export 'renderer_event.dart';

final class RendererBuildException implements Exception {
  const RendererBuildException(this.message);

  final String message;

  @override
  String toString() => 'RendererBuildException($message)';
}

typedef NodeWidgetFactory =
    Widget Function(
      BuildContext context,
      UiNode node,
      List<Widget> children,
      RendererEventCallback? onEvent,
    );

final class WidgetRegistry {
  WidgetRegistry(
    Map<NodeKind, NodeWidgetFactory> factories,
    this._nativeWidgets,
  ) : _factories = UnmodifiableMapView(Map.of(factories));

  factory WidgetRegistry.standard({NativeWidgetRegistry? nativeWidgets}) {
    final extensions =
        nativeWidgets ??
        NativeWidgetRegistry(capabilityBits: NativeCapability.core);
    if (nativeWidgets == null) {
      registerVirtualList(extensions);
      registerSparseExtentList(extensions);
      registerMorphingSurface(extensions);
      registerSwipeAction(extensions);
      registerNavigationShell(extensions);
    }
    return WidgetRegistry({
      NodeKind.empty: _buildEmpty,
      NodeKind.text: _buildText,
      NodeKind.richText: _buildRichText,
      NodeKind.icon: _buildIcon,
      NodeKind.image: _buildImage,
      NodeKind.row: _buildRow,
      NodeKind.column: _buildColumn,
      NodeKind.stack: _buildStack,
      NodeKind.button: _buildButton,
      NodeKind.pressable: _buildPressable,
      NodeKind.padding: _buildPadding,
      NodeKind.align: _buildAlign,
      NodeKind.center: _buildCenter,
      NodeKind.sizedBox: _buildSizedBox,
      NodeKind.constrainedBox: _buildConstrainedBox,
      NodeKind.decoratedBox: _buildDecoratedBox,
      NodeKind.clip: _buildClip,
      NodeKind.opacity: _buildOpacity,
      NodeKind.animatedOpacity: _buildAnimatedOpacity,
      NodeKind.transform: _buildTransform,
      NodeKind.scrollView: _buildScrollView,
      NodeKind.listView: _buildListView,
      NodeKind.gesture: _buildGesture,
      NodeKind.focusScope: _buildFocusScope,
      NodeKind.mouseRegion: _buildMouseRegion,
      NodeKind.keyboardListener: _buildKeyboardListener,
      NodeKind.semantics: _buildSemantics,
      NodeKind.theme: _buildTheme,
      NodeKind.materialScaffold: _buildMaterialScaffold,
      NodeKind.materialAppBar: _buildMaterialAppBar,
      NodeKind.materialElevatedButton: _buildMaterialButton,
      NodeKind.materialTextButton: _buildMaterialButton,
      NodeKind.materialIconButton: _buildMaterialButton,
      NodeKind.materialCheckbox: _buildMaterialCheckbox,
      NodeKind.materialSwitch: _buildMaterialSwitch,
      NodeKind.materialListTile: _buildMaterialListTile,
      NodeKind.materialDivider: _buildMaterialDivider,
      NodeKind.materialCard: _buildMaterialCard,
      NodeKind.materialCircularProgressIndicator: _buildMaterialProgress,
      NodeKind.cupertinoButton: _buildCupertinoButton,
      NodeKind.cupertinoSwitch: _buildCupertinoSwitch,
      NodeKind.textInput: _buildTextInput,
      NodeKind.overlay: _buildOverlay,
      NodeKind.navigator: _buildNavigator,
      NodeKind.page: _buildPage,
      NodeKind.safeArea: _buildSafeArea,
      NodeKind.environmentBoundary: _buildEnvironmentBoundary,
      NodeKind.materialDialog: _buildMaterialDialog,
    }, extensions);
  }

  final Map<NodeKind, NodeWidgetFactory> _factories;
  final NativeWidgetRegistry _nativeWidgets;

  Widget build(
    BuildContext context,
    UiNode node,
    List<Widget> children,
    RendererEventCallback? onEvent,
  ) {
    if (node.kind == NodeKind.nativeWidget) {
      final props = _expectProps<NativeWidgetProps>(node);
      final binding = _binding(node, EventTagId.nativeEvent);
      return _nativeWidgets.build(
        context: context,
        node: node,
        props: props,
        children: children,
        resources: RendererResourceScope.of(context),
        emit: binding == null || onEvent == null
            ? null
            : (eventId, payload) => onEvent(
                RendererEvent(
                  nodeId: node.id,
                  eventTag: binding.eventTag,
                  handlerId: binding.handlerId,
                  payload: NativeEventPayload(
                    kindId: props.kindId,
                    version: props.version,
                    eventId: eventId,
                    payload: payload,
                  ),
                ),
              ),
      );
    }
    final factory = _factories[node.kind];
    if (factory == null) {
      throw RendererBuildException(
        'No widget factory is registered for ${node.kind}',
      );
    }
    return factory(context, node, children, onEvent);
  }
}

Widget _buildEmpty(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  _expectProps<EmptyProps>(node);
  return const SizedBox.shrink();
}

Widget _buildPressable(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<PressableProps>(node);
  if (props.releaseDelayMs < 0 || props.releaseDelayMs > 100) {
    throw const RendererBuildException(
      'Pressable release delay must be in 0..100ms',
    );
  }
  final binding = _binding(node, EventTagId.press);
  return PressableHost(
    props: props,
    onPress: binding == null || onEvent == null
        ? null
        : () => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: const UnitEventPayload(),
            ),
          ),
    child: children.single,
  );
}

Widget _buildText(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<TextProps>(node);
  final style = props.style;
  return Text(
    props.value,
    style: style == null
        ? null
        : TextStyle(
            fontSize: style.fontSize,
            fontWeight: switch (style.fontWeight) {
              null || TextFontWeight.normal => FontWeight.w400,
              TextFontWeight.medium => FontWeight.w500,
              TextFontWeight.semiBold => FontWeight.w600,
              TextFontWeight.bold => FontWeight.w700,
            },
            height: style.lineHeight,
            color: style.colorArgb == null ? null : Color(style.colorArgb!),
          ),
    textAlign: switch (props.textAlign) {
      TextAlignValue.start => TextAlign.start,
      TextAlignValue.center => TextAlign.center,
      TextAlignValue.end => TextAlign.end,
    },
    maxLines: props.maxLines,
    overflow: switch (props.overflow) {
      TextOverflowValue.clip => TextOverflow.clip,
      TextOverflowValue.fade => TextOverflow.fade,
      TextOverflowValue.ellipsis => TextOverflow.ellipsis,
      TextOverflowValue.visible => TextOverflow.visible,
    },
  );
}

Widget _buildRichText(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<RichTextProps>(node);
  return RichText(
    text: TextSpan(
      style: DefaultTextStyle.of(context).style,
      children: [for (final span in props.spans) TextSpan(text: span)],
    ),
  );
}

Widget _buildIcon(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<IconProps>(node);
  return Semantics(
    image: true,
    child: Text(
      String.fromCharCode(props.codePoint),
      style: TextStyle(
        fontFamily: props.fontFamily,
        fontSize: props.size,
        color: props.colorArgb == null ? null : Color(props.colorArgb!),
      ),
    ),
  );
}

Widget _buildImage(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<ImageProps>(node);
  return Image.network(
    props.uri,
    fit: _imageFit(props.fit),
    width: props.width,
    height: props.height,
  );
}

Widget _buildRow(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectProps<LinearProps>(node);
  return Row(children: children);
}

Widget _buildColumn(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectProps<LinearProps>(node);
  return Column(children: children);
}

Widget _buildStack(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectProps<EmptyProps>(node);
  return Stack(children: children);
}

Widget _buildButton(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<ButtonProps>(node);
  final binding = _binding(node, EventTagId.press);
  return ElevatedButton(
    onPressed: !props.enabled || binding == null || onEvent == null
        ? null
        : () => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: const UnitEventPayload(),
            ),
          ),
    child: children.single,
  );
}

Widget _buildPadding(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<PaddingProps>(node);
  final insets = props.insets;
  return Padding(
    padding: EdgeInsets.fromLTRB(
      insets.left,
      insets.top,
      insets.right,
      insets.bottom,
    ),
    child: children.single,
  );
}

Widget _buildAlign(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<AlignProps>(node);
  return Align(alignment: _alignment(props.alignment), child: children.single);
}

Widget _buildCenter(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<CenterProps>(node);
  return Center(
    widthFactor: props.widthFactor,
    heightFactor: props.heightFactor,
    child: children.single,
  );
}

Widget _buildSizedBox(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SizedBoxProps>(node);
  return SizedBox(
    width: props.width,
    height: props.height,
    child: children.single,
  );
}

Widget _buildConstrainedBox(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<ConstrainedBoxProps>(node);
  return ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: props.minWidth,
      maxWidth: props.maxWidth,
      minHeight: props.minHeight,
      maxHeight: props.maxHeight,
    ),
    child: children.single,
  );
}

Widget _buildDecoratedBox(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<DecoratedBoxProps>(node);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: props.backgroundArgb == null ? null : Color(props.backgroundArgb!),
      borderRadius: BorderRadius.circular(props.borderRadius),
    ),
    child: children.single,
  );
}

Widget _buildClip(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<ClipProps>(node);
  return ClipRect(
    clipBehavior: _clipBehavior(props.behavior),
    child: children.single,
  );
}

Widget _buildOpacity(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<OpacityProps>(node);
  return Opacity(opacity: props.opacity, child: children.single);
}

Widget _buildAnimatedOpacity(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<AnimatedOpacityProps>(node);
  return AnimatedOpacityHost(
    nodeId: node.id,
    opacity: props.opacity,
    animation: props.animation,
    completionBinding: _binding(node, EventTagId.animationCompleted),
    onEvent: onEvent,
    child: children.single,
  );
}

Widget _buildTransform(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<TransformProps>(node);
  return Transform(
    transform: Matrix4.fromList(props.matrix4),
    child: children.single,
  );
}

Widget _buildScrollView(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<ScrollViewProps>(node);
  final binding = _binding(node, EventTagId.scrollNotification);
  final resources = RendererResourceScope.of(context);
  final controller = props.primary
      ? PrimaryScrollController.maybeOf(context)
      : resources.acquireScrollController(node.id);
  if (controller == null) {
    throw RendererBuildException(
      'Primary ScrollView node ${node.id} has no route scroll controller',
    );
  }
  final viewport = _guardedScrollable(
    node: node,
    widgetKind: 'ScrollView',
    axis: props.axis,
    binding: binding,
    onEvent: onEvent,
    viewportBuilder: () => SingleChildScrollView(
      controller: controller,
      scrollDirection: props.axis == ScrollAxis.horizontal
          ? Axis.horizontal
          : Axis.vertical,
      reverse: props.reverse,
      child: children.single,
    ),
  );
  return props.primary
      ? _BorrowedScrollControllerHost(
          nodeId: node.id,
          resources: resources,
          controller: controller,
          child: viewport,
        )
      : viewport;
}

Widget _buildListView(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<ListViewProps>(node);
  final binding = _binding(node, EventTagId.scrollNotification);
  final resources = RendererResourceScope.of(context);
  final controller = props.primary
      ? PrimaryScrollController.maybeOf(context)
      : resources.acquireScrollController(node.id);
  if (controller == null) {
    throw RendererBuildException(
      'Primary ListView node ${node.id} has no route scroll controller',
    );
  }
  final viewport = _guardedScrollable(
    node: node,
    widgetKind: 'ListView',
    axis: props.axis,
    binding: binding,
    onEvent: onEvent,
    viewportBuilder: () => ListView(
      controller: controller,
      scrollDirection: props.axis == ScrollAxis.horizontal
          ? Axis.horizontal
          : Axis.vertical,
      reverse: props.reverse,
      children: children,
    ),
  );
  return props.primary
      ? _BorrowedScrollControllerHost(
          nodeId: node.id,
          resources: resources,
          controller: controller,
          child: viewport,
        )
      : viewport;
}

final class _BorrowedScrollControllerHost extends StatefulWidget {
  const _BorrowedScrollControllerHost({
    required this.nodeId,
    required this.resources,
    required this.controller,
    required this.child,
  });

  final int nodeId;
  final RendererResourceStore resources;
  final ScrollController controller;
  final Widget child;

  @override
  State<_BorrowedScrollControllerHost> createState() =>
      _BorrowedScrollControllerHostState();
}

final class _BorrowedScrollControllerHostState
    extends State<_BorrowedScrollControllerHost> {
  @override
  void initState() {
    super.initState();
    widget.resources.replaceBorrowedScrollController(
      widget.nodeId,
      widget.controller,
    );
  }

  @override
  void didUpdateWidget(_BorrowedScrollControllerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId == widget.nodeId &&
        identical(oldWidget.resources, widget.resources) &&
        identical(oldWidget.controller, widget.controller)) {
      widget.resources.replaceBorrowedScrollController(
        widget.nodeId,
        widget.controller,
      );
      return;
    }
    oldWidget.resources.unbindBorrowedScrollController(
      oldWidget.nodeId,
      oldWidget.controller,
    );
    widget.resources.replaceBorrowedScrollController(
      widget.nodeId,
      widget.controller,
    );
  }

  @override
  void dispose() {
    widget.resources.unbindBorrowedScrollController(
      widget.nodeId,
      widget.controller,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _guardedScrollable({
  required UiNode node,
  required String widgetKind,
  required ScrollAxis axis,
  required EventBinding? binding,
  required RendererEventCallback? onEvent,
  required Widget Function() viewportBuilder,
}) => ViewportConstraintGuard(
  nodeId: node.id,
  localRevision: node.localRevision,
  widgetKind: widgetKind,
  axis: axis == ScrollAxis.horizontal
      ? RendererViewportAxis.horizontal
      : RendererViewportAxis.vertical,
  builder: (context, constraints) {
    final viewport = viewportBuilder();
    if (binding == null || onEvent == null) return viewport;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final delta = notification is ScrollUpdateNotification
            ? (notification.scrollDelta ?? 0)
            : 0.0;
        onEvent(
          RendererEvent(
            nodeId: node.id,
            eventTag: binding.eventTag,
            handlerId: binding.handlerId,
            payload: ScrollEventPayload(
              pixels: notification.metrics.pixels,
              delta: delta,
            ),
          ),
        );
        return false;
      },
      child: viewport,
    );
  },
);

Widget _buildGesture(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<GestureProps>(node);
  final tap = _binding(node, EventTagId.tap);
  final doubleTap = _binding(node, EventTagId.doubleTap);
  final longPress = _binding(node, EventTagId.longPress);
  final pointerDown = _binding(node, EventTagId.pointerDown);
  final pointerUp = _binding(node, EventTagId.pointerUp);
  TapDownDetails? doubleTapDetails;

  void emit(EventBinding? binding, EventPayload payload) {
    if (binding == null || onEvent == null) return;
    onEvent(
      RendererEvent(
        nodeId: node.id,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: payload,
      ),
    );
  }

  return Listener(
    onPointerDown: pointerDown == null
        ? null
        : (event) => emit(pointerDown, _pointerPayload(event)),
    onPointerUp: pointerUp == null
        ? null
        : (event) => emit(pointerUp, _pointerPayload(event)),
    child: GestureDetector(
      onTapUp: tap == null
          ? null
          : (details) => emit(tap, _tapPayload(details)),
      onDoubleTapDown: doubleTap == null
          ? null
          : (details) => doubleTapDetails = details,
      onDoubleTap: doubleTap == null
          ? null
          : () {
              final details = doubleTapDetails;
              if (details != null) emit(doubleTap, _tapPayload(details));
            },
      onLongPress: longPress == null
          ? null
          : () => emit(longPress, const UnitEventPayload()),
      child: children.single,
    ),
  );
}

Widget _buildFocusScope(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<FocusScopeProps>(node);
  final binding = _binding(node, EventTagId.focusChanged);
  return FocusScope(
    autofocus: props.autofocus,
    onFocusChange: binding == null || onEvent == null
        ? null
        : (focused) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: BoolEventPayload(focused),
            ),
          ),
    child: children.single,
  );
}

Widget _buildMouseRegion(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<MouseRegionProps>(node);
  final enter = _binding(node, EventTagId.pointerEnter);
  final leave = _binding(node, EventTagId.pointerLeave);
  return MouseRegion(
    opaque: props.opaque,
    onEnter: enter == null || onEvent == null
        ? null
        : (event) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: enter.eventTag,
              handlerId: enter.handlerId,
              payload: _pointerPayload(event),
            ),
          ),
    onExit: leave == null || onEvent == null
        ? null
        : (event) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: leave.eventTag,
              handlerId: leave.handlerId,
              payload: _pointerPayload(event),
            ),
          ),
    child: children.single,
  );
}

Widget _buildKeyboardListener(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<KeyboardListenerProps>(node);
  final binding = _binding(node, EventTagId.key);
  return Focus(
    autofocus: props.autofocus,
    onKeyEvent: binding == null || onEvent == null
        ? null
        : (focusNode, event) {
            onEvent(
              RendererEvent(
                nodeId: node.id,
                eventTag: binding.eventTag,
                handlerId: binding.handlerId,
                payload: KeyEventPayload(
                  logicalKey: event.logicalKey.keyId,
                  physicalKey: event.physicalKey.usbHidUsage,
                  action: switch (event) {
                    KeyRepeatEvent() => KeyActionValue.repeat,
                    KeyUpEvent() => KeyActionValue.up,
                    _ => KeyActionValue.down,
                  },
                  modifiers: _keyboardModifiers(),
                ),
              ),
            );
            return props.keyPolicy == KeyEventPolicy.handled
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
    child: children.single,
  );
}

Widget _buildSemantics(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SemanticsProps>(node);
  final binding = _binding(node, EventTagId.semanticsAction);
  VoidCallback? action(SemanticsActionValue action) {
    if (!props.actions.contains(action) || binding == null || onEvent == null) {
      return null;
    }
    return () => onEvent(
      RendererEvent(
        nodeId: node.id,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: Int64EventPayload(action.wireId),
      ),
    );
  }

  final isSwitch = props.role == SemanticsRoleValue.switchControl;
  return Semantics(
    label: props.label,
    hint: props.hint,
    value: props.value,
    button: props.role == SemanticsRoleValue.button,
    link: props.role == SemanticsRoleValue.link,
    image: props.role == SemanticsRoleValue.image,
    header: props.role == SemanticsRoleValue.header,
    textField: props.role == SemanticsRoleValue.textField || props.obscured,
    slider: props.role == SemanticsRoleValue.slider,
    enabled: props.enabled,
    selected: props.selected,
    checked: isSwitch ? null : props.checked,
    toggled: isSwitch ? props.checked : null,
    focused: props.focusable == null ? null : false,
    obscured: props.obscured,
    liveRegion: props.liveRegion,
    headingLevel: props.headingLevel,
    sortKey: props.sortKey == null ? null : OrdinalSortKey(props.sortKey!),
    onTap: action(SemanticsActionValue.tap),
    onLongPress: action(SemanticsActionValue.longPress),
    onFocus: action(SemanticsActionValue.focus),
    onIncrease: action(SemanticsActionValue.increase),
    onDecrease: action(SemanticsActionValue.decrease),
    onCopy: action(SemanticsActionValue.copy),
    onCut: action(SemanticsActionValue.cut),
    onPaste: action(SemanticsActionValue.paste),
    onDismiss: action(SemanticsActionValue.dismiss),
    child: children.single,
  );
}

Widget _buildTheme(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<ThemeProps>(node);
  return Theme(
    data: ThemeData(
      brightness: props.brightness == ThemeBrightness.light
          ? Brightness.light
          : Brightness.dark,
      colorSchemeSeed: Color(props.colorSeedArgb),
    ),
    child: children.single,
  );
}

Widget _buildMaterialCheckbox(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialCheckboxProps>(node);
  final binding = _binding(node, EventTagId.valueChanged);
  return Checkbox(
    value: props.value,
    onChanged: !props.enabled || binding == null || onEvent == null
        ? null
        : (value) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: BoolEventPayload(value ?? false),
            ),
          ),
  );
}

Widget _buildMaterialScaffold(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialScaffoldProps>(node);
  final expected = props.hasAppBar ? 2 : 1;
  _expectChildCount(node, children, expected);
  if (!props.hasAppBar) return Scaffold(body: children.single);
  return Scaffold(
    body: Column(
      children: [
        SizedBox(height: kToolbarHeight, child: children.first),
        Expanded(child: children.last),
      ],
    ),
  );
}

Widget _buildMaterialAppBar(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<MaterialAppBarProps>(node);
  return AppBar(title: children.single, centerTitle: props.centerTitle);
}

Widget _buildMaterialButton(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<MaterialButtonProps>(node);
  final binding = _binding(node, EventTagId.press);
  void emit() {
    if (!props.enabled || binding == null || onEvent == null) return;
    onEvent(
      RendererEvent(
        nodeId: node.id,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: const UnitEventPayload(),
      ),
    );
  }

  final callback = props.enabled && binding != null && onEvent != null
      ? emit
      : null;
  return switch (props.variant) {
    MaterialButtonVariant.elevated => ElevatedButton(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.text => TextButton(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.icon => IconButton(
      autofocus: props.autofocus,
      onPressed: callback,
      icon: children.single,
    ),
  };
}

Widget _buildMaterialSwitch(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialSwitchProps>(node);
  final binding = _binding(node, EventTagId.valueChanged);
  return Switch(
    value: props.value,
    onChanged: !props.enabled || binding == null || onEvent == null
        ? null
        : (value) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: BoolEventPayload(value),
            ),
          ),
  );
}

Widget _buildMaterialListTile(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialListTileProps>(node);
  final expected =
      1 +
      (props.hasSubtitle ? 1 : 0) +
      (props.hasLeading ? 1 : 0) +
      (props.hasTrailing ? 1 : 0);
  _expectChildCount(node, children, expected);
  var index = 0;
  final leading = props.hasLeading ? children[index++] : null;
  final title = children[index++];
  final subtitle = props.hasSubtitle ? children[index++] : null;
  final trailing = props.hasTrailing ? children[index++] : null;
  final binding = _binding(node, EventTagId.press);
  return ListTile(
    enabled: props.enabled,
    selected: props.selected,
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: !props.enabled || binding == null || onEvent == null
        ? null
        : () => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: const UnitEventPayload(),
            ),
          ),
  );
}

Widget _buildMaterialDivider(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialDividerProps>(node);
  return Divider(thickness: props.thickness);
}

Widget _buildMaterialCard(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<MaterialCardProps>(node);
  return Card(elevation: props.elevation, child: children.single);
}

Widget _buildMaterialProgress(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialProgressProps>(node);
  return CircularProgressIndicator(value: props.value);
}

Widget _buildCupertinoButton(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<CupertinoButtonProps>(node);
  final binding = _binding(node, EventTagId.press);
  return cupertino.CupertinoButton(
    onPressed: !props.enabled || binding == null || onEvent == null
        ? null
        : () => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: const UnitEventPayload(),
            ),
          ),
    child: children.single,
  );
}

Widget _buildCupertinoSwitch(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<CupertinoSwitchProps>(node);
  final binding = _binding(node, EventTagId.valueChanged);
  return cupertino.CupertinoSwitch(
    value: props.value,
    onChanged: !props.enabled || binding == null || onEvent == null
        ? null
        : (value) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: BoolEventPayload(value),
            ),
          ),
  );
}

Widget _buildTextInput(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<TextInputProps>(node);
  return TextInputHost(
    node: node,
    props: props,
    resources: RendererResourceScope.of(context),
    onEvent: onEvent,
  );
}

Widget _buildPage(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<PageProps>(node);
  return children.single;
}

Widget _buildNavigator(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<NavigatorProps>(node);
  final binding = _binding(node, EventTagId.routePop);
  final pages = <({PageProps props, Widget child})>[];
  for (final child in children) {
    if (child is! NodeHost) {
      throw RendererBuildException(
        'Navigator node ${node.id} children must all be Page nodes',
      );
    }
    final pageNode = child.store.node(child.nodeId);
    if (pageNode.kind != NodeKind.page || pageNode.props is! PageProps) {
      throw RendererBuildException(
        'Navigator node ${node.id} children must all be Page nodes',
      );
    }
    final pageProps = pageNode.props as PageProps;
    if (pageProps.presentation case ModalBottomSheetPresentation(
      sizing: DetentedModalSheetSizing(),
    )) {
      final primaryNodeIds = <int>[];
      void visit(int nodeId) {
        final descendant = child.store.node(nodeId);
        switch (descendant.props) {
          case ScrollViewProps(:final axis, primary: true):
            if (axis != ScrollAxis.vertical) {
              throw RendererBuildException(
                'Detented Page ${pageProps.pageKey} has horizontal primary '
                'ScrollView node $nodeId',
              );
            }
            primaryNodeIds.add(nodeId);
          case ListViewProps(:final axis, primary: true):
            if (axis != ScrollAxis.vertical) {
              throw RendererBuildException(
                'Detented Page ${pageProps.pageKey} has horizontal primary '
                'ListView node $nodeId',
              );
            }
            primaryNodeIds.add(nodeId);
          case _:
        }
        for (final descendantId in descendant.children) {
          visit(descendantId);
        }
      }

      for (final descendantId in pageNode.children) {
        visit(descendantId);
      }
      if (primaryNodeIds.length != 1) {
        throw RendererBuildException(
          'Detented Page ${pageProps.pageKey} requires exactly one primary '
          'vertical scrollable; found ${primaryNodeIds.length}: '
          '$primaryNodeIds',
        );
      }
    }
    pages.add((props: pageProps, child: child));
  }
  if (pages.isEmpty) {
    throw RendererBuildException(
      'Navigator node ${node.id} must contain at least one Page',
    );
  }
  if (pages.first.props.presentation is ModalBottomSheetPresentation) {
    throw RendererBuildException(
      'Navigator node ${node.id} cannot use a modal bottom sheet as its first Page',
    );
  }
  return _BonsaiNavigator(
    restorationScopeId: props.restorationScopeId,
    pages: pages,
    nodeId: node.id,
    binding: binding,
    onEvent: onEvent,
  );
}

Widget _buildOverlay(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<OverlayProps>(node);
  return Stack(
    alignment: _overlayAlignment(props.alignment),
    children: children,
  );
}

Widget _buildSafeArea(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SafeAreaProps>(node);
  return SafeArea(
    left: props.left,
    top: props.top,
    right: props.right,
    bottom: props.bottom,
    minimum: EdgeInsets.fromLTRB(
      props.minimum.left,
      props.minimum.top,
      props.minimum.right,
      props.minimum.bottom,
    ),
    child: children.single,
  );
}

Widget _buildEnvironmentBoundary(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<EnvironmentBoundaryProps>(node);
  return MediaQuery(data: MediaQuery.of(context), child: children.single);
}

Widget _buildMaterialDialog(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<MaterialDialogProps>(node);
  return Dialog(child: children.single);
}

Alignment _overlayAlignment(OverlayAlignment alignment) => switch (alignment) {
  OverlayAlignment.topStart => Alignment.topLeft,
  OverlayAlignment.topCenter => Alignment.topCenter,
  OverlayAlignment.topEnd => Alignment.topRight,
  OverlayAlignment.centerStart => Alignment.centerLeft,
  OverlayAlignment.center => Alignment.center,
  OverlayAlignment.centerEnd => Alignment.centerRight,
  OverlayAlignment.bottomStart => Alignment.bottomLeft,
  OverlayAlignment.bottomCenter => Alignment.bottomCenter,
  OverlayAlignment.bottomEnd => Alignment.bottomRight,
};

Alignment _alignment(AlignmentValue alignment) => switch (alignment) {
  AlignmentValue.topStart => Alignment.topLeft,
  AlignmentValue.topCenter => Alignment.topCenter,
  AlignmentValue.topEnd => Alignment.topRight,
  AlignmentValue.centerStart => Alignment.centerLeft,
  AlignmentValue.center => Alignment.center,
  AlignmentValue.centerEnd => Alignment.centerRight,
  AlignmentValue.bottomStart => Alignment.bottomLeft,
  AlignmentValue.bottomCenter => Alignment.bottomCenter,
  AlignmentValue.bottomEnd => Alignment.bottomRight,
};

BoxFit _imageFit(ImageFitValue fit) => switch (fit) {
  ImageFitValue.fill => BoxFit.fill,
  ImageFitValue.contain => BoxFit.contain,
  ImageFitValue.cover => BoxFit.cover,
  ImageFitValue.fitWidth => BoxFit.fitWidth,
  ImageFitValue.fitHeight => BoxFit.fitHeight,
  ImageFitValue.none => BoxFit.none,
  ImageFitValue.scaleDown => BoxFit.scaleDown,
};

Clip _clipBehavior(ClipBehaviorValue behavior) => switch (behavior) {
  ClipBehaviorValue.hardEdge => Clip.hardEdge,
  ClipBehaviorValue.antiAlias => Clip.antiAlias,
  ClipBehaviorValue.antiAliasWithSaveLayer => Clip.antiAliasWithSaveLayer,
};

TapEventPayload _tapPayload(Object details) {
  final (local, global, kind) = switch (details) {
    TapDownDetails(:final localPosition, :final globalPosition, :final kind) =>
      (localPosition, globalPosition, kind),
    TapUpDetails(:final localPosition, :final globalPosition, :final kind) => (
      localPosition,
      globalPosition,
      kind,
    ),
    _ => throw ArgumentError.value(
      details,
      'details',
      'Unsupported tap details',
    ),
  };
  return TapEventPayload(
    localX: local.dx,
    localY: local.dy,
    globalX: global.dx,
    globalY: global.dy,
    pointerKind: _pointerKind(kind),
  );
}

PointerEventPayload _pointerPayload(PointerEvent event) => PointerEventPayload(
  pointerId: event.pointer,
  localX: event.localPosition.dx,
  localY: event.localPosition.dy,
  globalX: event.position.dx,
  globalY: event.position.dy,
  pointerKind: _pointerKind(event.kind),
  buttons: event.buttons,
);

PointerKindValue _pointerKind(PointerDeviceKind? kind) => switch (kind) {
  PointerDeviceKind.mouse => PointerKindValue.mouse,
  PointerDeviceKind.touch => PointerKindValue.touch,
  PointerDeviceKind.stylus => PointerKindValue.stylus,
  PointerDeviceKind.invertedStylus => PointerKindValue.invertedStylus,
  PointerDeviceKind.trackpad => PointerKindValue.trackpad,
  PointerDeviceKind.unknown || null => PointerKindValue.unknown,
};

int _keyboardModifiers() {
  final keyboard = HardwareKeyboard.instance;
  return (keyboard.isShiftPressed ? 1 : 0) |
      (keyboard.isControlPressed ? 1 << 1 : 0) |
      (keyboard.isAltPressed ? 1 << 2 : 0) |
      (keyboard.isMetaPressed ? 1 << 3 : 0);
}

final class _BonsaiPage extends Page<void> {
  const _BonsaiPage({
    required this.child,
    required this.transition,
    super.key,
    super.name,
    super.restorationId,
    super.canPop,
  });

  final Widget child;
  final PageTransition transition;

  @override
  Route<void> createRoute(BuildContext context) => switch (transition) {
    PageTransition.none => PageRouteBuilder<void>(
      settings: this,
      pageBuilder: (_, _, _) => child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
    PageTransition.fade => PageRouteBuilder<void>(
      settings: this,
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, routeChild) =>
          FadeTransition(opacity: animation, child: routeChild),
    ),
    PageTransition.slide => throw StateError(
      'Slide pages must use CupertinoPage',
    ),
  };
}

final class _BonsaiNavigator extends StatefulWidget {
  const _BonsaiNavigator({
    required this.restorationScopeId,
    required this.pages,
    required this.nodeId,
    required this.binding,
    required this.onEvent,
  });

  final String? restorationScopeId;
  final List<({PageProps props, Widget child})> pages;
  final int nodeId;
  final EventBinding? binding;
  final RendererEventCallback? onEvent;

  @override
  State<_BonsaiNavigator> createState() => _BonsaiNavigatorState();
}

final class _BonsaiNavigatorState extends State<_BonsaiNavigator> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
    child: Navigator(
      key: _navigatorKey,
      restorationScopeId: widget.restorationScopeId,
      pages: [
        for (final page in widget.pages)
          switch (page.props.presentation) {
            StandardPagePresentation(transition: PageTransition.slide) =>
              cupertino.CupertinoPage<void>(
                key: ValueKey<String>(page.props.pageKey),
                name: page.props.pageKey,
                restorationId: page.props.restorationId,
                canPop: page.props.canPop,
                child: page.child,
              ),
            StandardPagePresentation(:final transition) => _BonsaiPage(
              key: ValueKey<String>(page.props.pageKey),
              name: page.props.pageKey,
              restorationId: page.props.restorationId,
              canPop: page.props.canPop,
              transition: transition,
              child: page.child,
            ),
            final ModalBottomSheetPresentation presentation =>
              _BonsaiModalBottomSheetPage(
                key: ValueKey<String>(page.props.pageKey),
                name: page.props.pageKey,
                restorationId: page.props.restorationId,
                canPop: page.props.canPop,
                presentation: presentation,
                child: page.child,
              ),
          },
      ],
      onDidRemovePage: (page) {
        final binding = widget.binding;
        final onEvent = widget.onEvent;
        if (binding == null || onEvent == null) return;
        onEvent(
          RendererEvent(
            nodeId: widget.nodeId,
            eventTag: binding.eventTag,
            handlerId: binding.handlerId,
            payload: RoutePopEventPayload(pageKey: page.name!, result: null),
          ),
        );
      },
    ),
  );
}

final class _BonsaiModalBottomSheetPage extends Page<void> {
  const _BonsaiModalBottomSheetPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.restorationId,
    super.canPop,
  });

  final Widget child;
  final ModalBottomSheetPresentation presentation;

  @override
  Route<void> createRoute(BuildContext context) => _BonsaiModalBottomSheetRoute(
    page: this,
    defaultBarrierLabel: MaterialLocalizations.of(context).scrimLabel,
  );
}

final class _BonsaiModalBottomSheetRoute extends ModalBottomSheetRoute<void> {
  _BonsaiModalBottomSheetRoute({
    required _BonsaiModalBottomSheetPage page,
    required String defaultBarrierLabel,
  }) : _defaultBarrierLabel = defaultBarrierLabel,
       super(
         settings: page,
         builder: (_) => page.child,
         barrierLabel: page.presentation.barrierLabel ?? defaultBarrierLabel,
         modalBarrierColor: page.presentation.barrierColorArgb == null
             ? null
             : Color(page.presentation.barrierColorArgb!),
         isDismissible: page.presentation.barrierDismissible,
         isScrollControlled:
             page.presentation.sizing is! ContentBoundedModalSheetSizing,
         useSafeArea: page.presentation.useSafeArea,
         requestFocus: page.presentation.requestFocus,
         enableDrag: false,
         showDragHandle: false,
         backgroundColor: Colors.transparent,
         elevation: 0,
         sheetAnimationStyle: AnimationStyle(
           duration: Duration(
             milliseconds: page.presentation.transitionDurationMilliseconds,
           ),
           reverseDuration: Duration(
             milliseconds:
                 page.presentation.reverseTransitionDurationMilliseconds,
           ),
         ),
       );

  final String _defaultBarrierLabel;

  _BonsaiModalBottomSheetPage get _page =>
      settings as _BonsaiModalBottomSheetPage;
  ModalBottomSheetPresentation get _presentation => _page.presentation;

  bool get _reducedMotion {
    final context = navigator?.context;
    if (context == null) return false;
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  @override
  WidgetBuilder get builder => (context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final sizing = _presentation.sizing;
    Widget child = _page.child;
    if (sizing is DetentedModalSheetSizing) {
      bool canDismiss() => sizing.dismissOnDrag && _page.canPop;
      final pageChild = child;
      child = BottomSheet(
        onClosing: () {},
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (_) => _DetentedModalSheetHost(
          sizing: sizing,
          canDismiss: canDismiss,
          requestDismiss: () async {
            if (!canDismiss()) return false;
            return navigator?.maybePop() ?? false;
          },
          reducedMotion: _reducedMotion,
          child: pageChild,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  };

  @override
  bool get barrierDismissible => _presentation.barrierDismissible;

  @override
  Color get barrierColor => _presentation.barrierColorArgb == null
      ? Colors.black54
      : Color(_presentation.barrierColorArgb!);

  @override
  String get barrierLabel => _presentation.barrierLabel ?? _defaultBarrierLabel;

  @override
  bool get isScrollControlled =>
      _presentation.sizing is! ContentBoundedModalSheetSizing;

  @override
  bool get useSafeArea => _presentation.useSafeArea;

  @override
  bool get requestFocus => _presentation.requestFocus;

  @override
  bool get enableDrag => false;

  @override
  bool get showDragHandle => false;

  @override
  AnimationStyle get sheetAnimationStyle => _reducedMotion
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: Duration(
            milliseconds: _presentation.transitionDurationMilliseconds,
          ),
          reverseDuration: Duration(
            milliseconds: _presentation.reverseTransitionDurationMilliseconds,
          ),
        );

  @override
  Duration get transitionDuration => _reducedMotion
      ? Duration.zero
      : Duration(milliseconds: _presentation.transitionDurationMilliseconds);

  @override
  Duration get reverseTransitionDuration => _reducedMotion
      ? Duration.zero
      : Duration(
          milliseconds: _presentation.reverseTransitionDurationMilliseconds,
        );

  @override
  void changedInternalState() {
    super.changedInternalState();
    _synchronizeAnimationDurations();
  }

  @override
  void changedExternalState() {
    super.changedExternalState();
    _synchronizeAnimationDurations();
  }

  void _synchronizeAnimationDurations() {
    controller
      ?..duration = transitionDuration
      ..reverseDuration = reverseTransitionDuration;
  }
}

final class _DetentedModalSheetHost extends StatefulWidget {
  const _DetentedModalSheetHost({
    required this.sizing,
    required this.canDismiss,
    required this.requestDismiss,
    required this.reducedMotion,
    required this.child,
  });

  final DetentedModalSheetSizing sizing;
  final bool Function() canDismiss;
  final Future<bool> Function() requestDismiss;
  final bool reducedMotion;
  final Widget child;

  @override
  State<_DetentedModalSheetHost> createState() =>
      _DetentedModalSheetHostState();
}

final class _DetentedModalSheetHostState
    extends State<_DetentedModalSheetHost> {
  static const _mediumExtent = 0.5;
  static const _largeExtent = 1.0;
  static const _dismissExtent = 0.0;
  static const _epsilon = 0.001;
  static const _animationDuration = Duration(milliseconds: 200);
  // Flutter treats null as its default ballistic snap and rejects zero.
  static const _reducedMotionSnapDuration = Duration(milliseconds: 1);

  final DraggableScrollableController _controller =
      DraggableScrollableController();
  late double _reportedExtent = _detentExtent(widget.sizing.initialDetent);
  bool _extentUpdateScheduled = false;
  bool _dismissScheduled = false;
  double _handleDragDelta = 0;

  List<double> get _visibleExtents => switch (widget.sizing.detents) {
    ModalSheetDetentSet.medium => const [_mediumExtent],
    ModalSheetDetentSet.large => const [_largeExtent],
    ModalSheetDetentSet.mediumAndLarge => const [_mediumExtent, _largeExtent],
  };

  bool get _dismissEnabled => widget.canDismiss();

  double get _minimumVisibleExtent => _visibleExtents.first;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleExtentUpdate);
  }

  @override
  void didUpdateWidget(_DetentedModalSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isAttached) return;
      final allowed = _visibleExtents;
      final current = _controller.size;
      if (current < _minimumVisibleExtent && !_dismissEnabled) {
        _moveTo(_minimumVisibleExtent);
        return;
      }
      if (!allowed.any((extent) => (extent - current).abs() <= _epsilon) &&
          current >= _minimumVisibleExtent) {
        _moveTo(_nearestExtent(current, allowed));
      }
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_scheduleExtentUpdate)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleExtents;
    final dismissEnabled = _dismissEnabled;
    final minExtent = dismissEnabled ? _dismissExtent : visible.first;
    final maxExtent = visible.last;
    final initialExtent = _detentExtent(
      widget.sizing.initialDetent,
    ).clamp(minExtent, maxExtent);
    final snapSizes = visible
        .where((extent) => extent > minExtent && extent < maxExtent)
        .toList(growable: false);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _handleDragNotification,
      child: DraggableScrollableSheet(
        controller: _controller,
        expand: false,
        initialChildSize: initialExtent,
        minChildSize: minExtent,
        maxChildSize: maxExtent,
        snap: true,
        snapSizes: snapSizes,
        snapAnimationDuration: widget.reducedMotion
            ? _reducedMotionSnapDuration
            : _animationDuration,
        shouldCloseOnMinExtent: false,
        builder: (context, scrollController) => PrimaryScrollController(
          controller: scrollController,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: widget.child,
              ),
              Align(
                alignment: Alignment.topCenter,
                child: _buildHandle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    final visible = _visibleExtents;
    final currentIndex = _nearestExtentIndex(_reportedExtent, visible);
    final currentExtent = visible[currentIndex];
    final semantics = widget.sizing.handleSemantics;
    final currentValue = currentExtent == _mediumExtent
        ? semantics.mediumValue
        : semantics.largeValue;
    final canIncrease = currentIndex < visible.length - 1;
    final canDecrease = currentIndex > 0 || _dismissEnabled;

    KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp && canIncrease) {
        _moveTo(visible[currentIndex + 1]);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown && canDecrease) {
        _decreaseFrom(currentIndex, visible);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Focus(
      onKeyEvent: handleKeyEvent,
      child: Semantics(
        label: semantics.label,
        value: currentValue,
        increasedValue: canIncrease
            ? _semanticsValue(visible[currentIndex + 1])
            : null,
        decreasedValue: canDecrease
            ? currentIndex > 0
                  ? _semanticsValue(visible[currentIndex - 1])
                  : currentValue
            : null,
        onIncrease: canIncrease
            ? () => _moveTo(visible[currentIndex + 1])
            : null,
        onDecrease: canDecrease
            ? () => _decreaseFrom(currentIndex, visible)
            : null,
        child: Listener(
          onPointerDown: (event) {
            if (event.kind == PointerDeviceKind.mouse) _handleDragDelta = 0;
          },
          onPointerMove: (event) {
            if (event.kind == PointerDeviceKind.mouse) {
              _dragHandleBy(event.delta.dy);
            }
          },
          onPointerUp: (event) {
            if (event.kind == PointerDeviceKind.mouse) _endHandleDragWith(0);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
            onTap: _cycleDetent,
            onVerticalDragStart: (_) => _handleDragDelta = 0,
            onVerticalDragUpdate: _dragHandle,
            onVerticalDragEnd: _endHandleDrag,
            child: SizedBox(
              width: 72,
              height: 48,
              child: Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _decreaseFrom(int currentIndex, List<double> visible) {
    _moveTo(currentIndex > 0 ? visible[currentIndex - 1] : _dismissExtent);
  }

  String _semanticsValue(double extent) => extent == _mediumExtent
      ? widget.sizing.handleSemantics.mediumValue
      : widget.sizing.handleSemantics.largeValue;

  void _cycleDetent() {
    final visible = _visibleExtents;
    final current = _controller.isAttached ? _controller.size : _reportedExtent;
    final index = _nearestExtentIndex(current, visible);
    _moveTo(visible[(index + 1) % visible.length]);
  }

  void _dragHandle(DragUpdateDetails details) {
    _dragHandleBy(details.delta.dy);
  }

  void _dragHandleBy(double deltaPixels) {
    if (!_controller.isAttached) return;
    _handleDragDelta += deltaPixels;
    final delta = _controller.pixelsToSize(deltaPixels);
    final minimum = _dismissEnabled ? _dismissExtent : _minimumVisibleExtent;
    _controller.jumpTo(
      (_controller.size - delta).clamp(minimum, _visibleExtents.last),
    );
  }

  void _endHandleDrag(DragEndDetails details) {
    _endHandleDragWith(details.primaryVelocity ?? 0);
  }

  void _endHandleDragWith(double velocity) {
    if (!_controller.isAttached) return;
    final targets = <double>[
      if (_dismissEnabled) _dismissExtent,
      ..._visibleExtents,
    ];
    final current = _controller.size;
    double target;
    if (_handleDragDelta < -20 || velocity < -300) {
      target = targets.firstWhere(
        (extent) => extent > current + _epsilon,
        orElse: () => targets.last,
      );
    } else if (_handleDragDelta > 20 || velocity > 300) {
      target = targets.lastWhere(
        (extent) => extent < current - _epsilon,
        orElse: () => targets.first,
      );
    } else {
      target = _nearestExtent(current, targets);
    }
    _moveTo(target);
  }

  bool _handleDragNotification(DraggableScrollableNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.extent <= _epsilon) {
      _scheduleDismissal();
    }
    return false;
  }

  void _scheduleExtentUpdate() {
    if (_extentUpdateScheduled) return;
    _extentUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extentUpdateScheduled = false;
      if (!mounted || !_controller.isAttached) return;
      final next = _controller.size;
      if ((next - _reportedExtent).abs() <= _epsilon) return;
      setState(() => _reportedExtent = next);
      if (next <= _epsilon) _scheduleDismissal();
    });
  }

  void _scheduleDismissal() {
    if (_dismissScheduled) return;
    _dismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _dismissScheduled = false;
      if (!mounted || !_controller.isAttached) return;
      if (_controller.size > _epsilon) return;
      if (!widget.canDismiss()) {
        _moveTo(_minimumVisibleExtent);
        return;
      }
      final dismissed = await widget.requestDismiss();
      if (mounted && _controller.isAttached && !dismissed) {
        _moveTo(_minimumVisibleExtent);
      }
    });
  }

  void _moveTo(double extent) {
    if (!_controller.isAttached) return;
    if (widget.reducedMotion) {
      _controller.jumpTo(extent);
      if ((extent - _reportedExtent).abs() > _epsilon) {
        setState(() => _reportedExtent = extent);
      }
      if (extent <= _epsilon) _scheduleDismissal();
      return;
    }
    _controller
        .animateTo(extent, duration: _animationDuration, curve: Curves.easeOut)
        .then((_) {
          if (extent <= _epsilon) _scheduleDismissal();
        });
  }

  static double _detentExtent(ModalSheetDetent detent) => switch (detent) {
    ModalSheetDetent.medium => _mediumExtent,
    ModalSheetDetent.large => _largeExtent,
  };

  static int _nearestExtentIndex(double value, List<double> extents) {
    var bestIndex = 0;
    var bestDistance = (value - extents.first).abs();
    for (var index = 1; index < extents.length; index += 1) {
      final distance = (value - extents[index]).abs();
      if (distance <= bestDistance) {
        bestIndex = index;
        bestDistance = distance;
      }
    }
    return bestIndex;
  }

  static double _nearestExtent(double value, List<double> extents) =>
      extents[_nearestExtentIndex(value, extents)];
}

T _expectProps<T extends UiProps>(UiNode node) {
  final props = node.props;
  if (props is! T) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} has ${props.runtimeType} props',
    );
  }
  return props;
}

void _expectChildCount(UiNode node, List<Widget> children, int expected) {
  if (children.length != expected) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires $expected children, '
      'got ${children.length}',
    );
  }
}

EventBinding? _binding(UiNode node, int eventTag) {
  for (final binding in node.eventBindings) {
    if (binding.eventTag == eventTag) return binding;
  }
  return null;
}
