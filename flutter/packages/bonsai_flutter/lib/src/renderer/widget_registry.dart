import 'dart:collection';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../gesture/bonsai_gesture_detector.dart';
import '../native_widget/native_widget_registry.dart';
import '../native_widget/expandable_message_composer.dart';
import 'sliver_virtual_host.dart';
import '../native_widget/morphing_surface.dart';
import '../native_widget/message_composer.dart';
import '../native_widget/navigation_shell.dart';
import '../native_widget/slidable.dart';
import '../navigation/navigation_host.dart';
import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../protocol/generated_protocol.dart';
import '../store/node_store.dart';
import '../text_input/text_input_host.dart';
import 'animated_opacity_host.dart';
import 'application_theme.dart';
import 'node_host.dart';
import 'pressable_host.dart';
import 'renderer_event.dart';
import 'renderer_error.dart';
import 'renderer_resource_store.dart';
import 'viewport_constraint_guard.dart';

export 'renderer_event.dart';
export 'renderer_error.dart';

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
      registerMorphingSurface(extensions);
      registerSlidable(extensions);
      registerSlidableAutoCloseBehavior(extensions);
      registerNavigationShell(extensions);
      registerMessageComposer(extensions);
      registerExpandableMessageComposer(extensions);
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
      NodeKind.sliverBox: _buildSliverBox,
      NodeKind.sliverList: _buildSliverList,
      NodeKind.sliverFill: _buildSliverFill,
      NodeKind.sliverFixedExtent: _buildSliverFixedExtent,
      NodeKind.sliverVariedExtent: _buildSliverVariedExtent,
      NodeKind.sliverPadding: _buildSliverPadding,
      NodeKind.sliverAppBar: _buildSliverAppBar,
      NodeKind.preferredSize: _buildPreferredSize,
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
      NodeKind.materialFilledButton: _buildMaterialButton,
      NodeKind.materialFilledTonalButton: _buildMaterialButton,
      NodeKind.materialOutlinedButton: _buildMaterialButton,
      NodeKind.materialFloatingActionButton: _buildMaterialFloatingActionButton,
      NodeKind.materialNavigationBar: _buildMaterialNavigationBar,
      NodeKind.materialRadioGroup: _buildMaterialRadioGroup,
      NodeKind.materialSlider: _buildMaterialSlider,
      NodeKind.materialRangeSlider: _buildMaterialRangeSlider,
      NodeKind.materialActionChip: _buildMaterialChip,
      NodeKind.materialFilterChip: _buildMaterialChip,
      NodeKind.materialChoiceChip: _buildMaterialChip,
      NodeKind.materialInputChip: _buildMaterialChip,
      NodeKind.materialAlertDialog: _buildMaterialAlertDialog,
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

/// Provides the shared [ScrollController] and scroll [Axis] to sliver
/// children built inside a [CustomScrollView].
class ScrollViewScope extends InheritedWidget {
  const ScrollViewScope({
    required this.controller,
    required this.axis,
    required this.anchorCoordinator,
    required super.child,
    super.key,
  });

  final ScrollController controller;
  final Axis axis;
  final InitialSliverAnchorCoordinator anchorCoordinator;

  static ScrollViewScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScrollViewScope>();

  @override
  bool updateShouldNotify(ScrollViewScope old) =>
      controller != old.controller ||
      axis != old.axis ||
      anchorCoordinator != old.anchorCoordinator;
}

final class _ScrollViewScopeHost extends StatefulWidget {
  const _ScrollViewScopeHost({
    required this.controller,
    required this.axis,
    required this.child,
  });

  final ScrollController controller;
  final Axis axis;
  final Widget child;

  @override
  State<_ScrollViewScopeHost> createState() => _ScrollViewScopeHostState();
}

final class _ScrollViewScopeHostState extends State<_ScrollViewScopeHost> {
  late InitialSliverAnchorCoordinator _anchorCoordinator;

  @override
  void initState() {
    super.initState();
    _anchorCoordinator = InitialSliverAnchorCoordinator(widget.controller);
  }

  @override
  void didUpdateWidget(_ScrollViewScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _anchorCoordinator.dispose();
      _anchorCoordinator = InitialSliverAnchorCoordinator(widget.controller);
    }
  }

  @override
  void dispose() {
    _anchorCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollViewScope(
    controller: widget.controller,
    axis: widget.axis,
    anchorCoordinator: _anchorCoordinator,
    child: widget.child,
  );
}

Widget _buildScrollView(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<ScrollViewProps>(node);
  final cacheExtent = props.cacheExtent;
  if (cacheExtent != null && (!cacheExtent.isFinite || cacheExtent < 0)) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires cacheExtent to be finite '
      'and non-negative',
    );
  }
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
  final scrollAxis = props.axis == ScrollAxis.horizontal
      ? Axis.horizontal
      : Axis.vertical;
  final viewport = _guardedScrollable(
    node: node,
    widgetKind: 'ScrollView',
    axis: props.axis,
    binding: binding,
    onEvent: onEvent,
    viewportBuilder: () => CustomScrollView(
      controller: controller,
      scrollDirection: scrollAxis,
      reverse: props.reverse,
      scrollCacheExtent: cacheExtent != null
          ? ScrollCacheExtent.pixels(cacheExtent)
          : null,
      slivers: children,
    ),
  );
  final scoped = _ScrollViewScopeHost(
    controller: controller,
    axis: scrollAxis,
    child: viewport,
  );
  return props.primary
      ? _BorrowedScrollControllerHost(
          nodeId: node.id,
          resources: resources,
          controller: controller,
          child: scoped,
        )
      : scoped;
}

Widget _buildSliverBox(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<EmptyProps>(node);
  return SliverToBoxAdapter(child: children.single);
}

Widget _buildSliverList(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectProps<EmptyProps>(node);
  return SliverList(delegate: SliverChildListDelegate(children));
}

Widget _buildSliverFill(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<SliverFillProps>(node);
  return SliverFillRemaining(child: children.single);
}

Widget _buildSliverFixedExtent(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<SliverFixedExtentProps>(node);
  _validateVirtualSliverRendererProps(props);
  final scope = ScrollViewScope.of(context);
  if (scope == null) {
    throw RendererBuildException(
      'Sliver_fixed_extent node ${node.id} must be inside a Scroll_view',
    );
  }
  return SliverFixedExtentHost(
    nodeId: node.id,
    deliveryGeneration: node.deliveryGeneration,
    props: props,
    controller: scope.controller,
    anchorCoordinator: scope.anchorCoordinator,
    binding: _binding(node, EventTagId.visibleRangeChanged),
    onEvent: onEvent,
    children: children,
  );
}

Widget _buildSliverVariedExtent(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<SliverVariedExtentProps>(node);
  _validateVirtualSliverRendererProps(props);
  final scope = ScrollViewScope.of(context);
  if (scope == null) {
    throw RendererBuildException(
      'Sliver_varied_extent node ${node.id} must be inside a Scroll_view',
    );
  }
  return SliverVariedExtentHost(
    nodeId: node.id,
    deliveryGeneration: node.deliveryGeneration,
    props: props,
    controller: scope.controller,
    anchorCoordinator: scope.anchorCoordinator,
    binding: _binding(node, EventTagId.visibleRangeChanged),
    onEvent: onEvent,
    children: children,
  );
}

void _validateVirtualSliverRendererProps(UiProps props) {
  final error = virtualSliverPropsError(props);
  if (error != null) throw RendererBuildException(error);
}

Widget _buildSliverPadding(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<SliverPaddingProps>(node);
  return SliverPadding(
    padding: EdgeInsets.fromLTRB(
      props.insets.left,
      props.insets.top,
      props.insets.right,
      props.insets.bottom,
    ),
    sliver: children.single,
  );
}

Widget _buildSliverAppBar(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<SliverAppBarProps>(node);
  _validateSliverAppBarProps(node, props);
  final slotCount =
      1 +
      (props.hasLeading ? 1 : 0) +
      (props.hasFlexibleSpace ? 1 : 0) +
      (props.hasBottom ? 1 : 0);
  if (props.hasActions) {
    if (children.length <= slotCount) {
      throw RendererBuildException(
        'Node ${node.id} of kind ${node.kind} requires at least one action',
      );
    }
  } else {
    _expectChildCount(node, children, slotCount);
  }
  var index = 0;
  final leading = props.hasLeading ? children[index++] : null;
  final title = children[index++];
  final flexibleSpace = props.hasFlexibleSpace ? children[index++] : null;
  final bottom = props.hasBottom ? children[index++] : null;
  if (bottom != null && bottom is! PreferredSizeWidget) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires a PreferredSize bottom',
    );
  }
  final actions = props.hasActions ? children.sublist(index) : null;
  return SliverAppBar(
    pinned: props.pinned,
    expandedHeight: props.expandedHeight,
    collapsedHeight: props.collapsedHeight,
    floating: props.floating,
    snap: props.snap,
    stretch: props.stretch,
    toolbarHeight: props.toolbarHeight,
    forceElevated: props.forceElevated,
    automaticallyImplyLeading: props.automaticallyImplyLeading,
    centerTitle: props.centerTitle,
    backgroundColor: props.backgroundColor != null
        ? Color(props.backgroundColor!)
        : null,
    foregroundColor: props.foregroundColor != null
        ? Color(props.foregroundColor!)
        : null,
    elevation: props.elevation,
    leading: leading,
    title: title,
    flexibleSpace: flexibleSpace,
    bottom: bottom as PreferredSizeWidget?,
    actions: actions,
  );
}

void _validateSliverAppBarProps(UiNode node, SliverAppBarProps props) {
  void finiteNonNegative(String name, double? value) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw RendererBuildException(
        'Node ${node.id} of kind ${node.kind} requires $name to be finite '
        'and non-negative',
      );
    }
  }

  if (!props.toolbarHeight.isFinite || props.toolbarHeight <= 0) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires toolbarHeight to be '
      'finite and strictly positive',
    );
  }
  finiteNonNegative('expandedHeight', props.expandedHeight);
  finiteNonNegative('collapsedHeight', props.collapsedHeight);
  finiteNonNegative('elevation', props.elevation);
  if (props.snap && !props.floating) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires floating when snap is true',
    );
  }
  final collapsedHeight = props.collapsedHeight;
  if (collapsedHeight != null && collapsedHeight < props.toolbarHeight) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires collapsedHeight to be '
      'at least toolbarHeight',
    );
  }
  final expandedHeight = props.expandedHeight;
  if (collapsedHeight != null &&
      expandedHeight != null &&
      collapsedHeight > expandedHeight) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires collapsedHeight not to '
      'exceed expandedHeight',
    );
  }
}

Widget _buildPreferredSize(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<PreferredSizeProps>(node);
  return PreferredSize(
    preferredSize: Size.fromHeight(props.height),
    child: children.single,
  );
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
    child: BonsaiGestureDetector(
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
  return Theme(data: decodeThemeData(props.data), child: children.single);
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
  RendererResourceScope.maybeOf(
    context,
  )?.bindScaffoldMessenger(ScaffoldMessenger.maybeOf(context));
  final expected =
      (props.hasAppBar ? 1 : 0) +
      (props.hasFloatingActionButton ? 1 : 0) +
      (props.hasBottomNavigationBar ? 1 : 0) +
      (props.hasBottomSheet ? 1 : 0) +
      1;
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final Widget? appBarChild = props.hasAppBar ? children[childIndex++] : null;
  final PreferredSizeWidget? appBar = switch (appBarChild) {
    null => null,
    final PreferredSizeWidget widget => widget,
    final widget => PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: widget,
    ),
  };
  final floatingActionButton = props.hasFloatingActionButton
      ? children[childIndex++]
      : null;
  final bottomNavigationBar = props.hasBottomNavigationBar
      ? children[childIndex++]
      : null;
  final bottomSheet = props.hasBottomSheet ? children[childIndex++] : null;
  final body = children[childIndex];
  return Scaffold(
    appBar: appBar,
    floatingActionButton: floatingActionButton,
    floatingActionButtonLocation: switch (props.floatingActionButtonLocation) {
      MaterialFloatingActionButtonLocation.startFloat =>
        FloatingActionButtonLocation.startFloat,
      MaterialFloatingActionButtonLocation.centerFloat =>
        FloatingActionButtonLocation.centerFloat,
      MaterialFloatingActionButtonLocation.endFloat =>
        FloatingActionButtonLocation.endFloat,
      MaterialFloatingActionButtonLocation.startDocked =>
        FloatingActionButtonLocation.startDocked,
      MaterialFloatingActionButtonLocation.centerDocked =>
        FloatingActionButtonLocation.centerDocked,
      MaterialFloatingActionButtonLocation.endDocked =>
        FloatingActionButtonLocation.endDocked,
    },
    bottomNavigationBar: bottomNavigationBar,
    bottomSheet: bottomSheet,
    body: body,
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
    MaterialButtonVariant.filled => FilledButton(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.filledTonal => FilledButton.tonal(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.outlined => OutlinedButton(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
  };
}

Widget _buildMaterialFloatingActionButton(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialFloatingActionButtonProps>(node);
  final expected = props.variant == MaterialFloatingActionButtonVariant.extended
      ? (props.hasIcon ? 2 : 1)
      : 1;
  _expectChildCount(node, children, expected);
  final binding = _binding(node, EventTagId.press);
  final callback = props.enabled && binding != null && onEvent != null
      ? () => onEvent(
          RendererEvent(
            nodeId: node.id,
            eventTag: binding.eventTag,
            handlerId: binding.handlerId,
            payload: const UnitEventPayload(),
          ),
        )
      : null;
  return switch (props.variant) {
    MaterialFloatingActionButtonVariant.small => FloatingActionButton.small(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialFloatingActionButtonVariant.standard => FloatingActionButton(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialFloatingActionButtonVariant.large => FloatingActionButton.large(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialFloatingActionButtonVariant.extended =>
      FloatingActionButton.extended(
        autofocus: props.autofocus,
        onPressed: callback,
        icon: props.hasIcon ? children.first : null,
        label: children.last,
      ),
  };
}

Widget _buildMaterialNavigationBar(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialNavigationBarProps>(node);
  final expected = props.destinations.fold<int>(
    0,
    (count, destination) => count + (destination.hasSelectedIcon ? 2 : 1),
  );
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final destinations = <NavigationDestination>[];
  for (final destination in props.destinations) {
    final icon = children[childIndex++];
    final selectedIcon = destination.hasSelectedIcon
        ? children[childIndex++]
        : null;
    destinations.add(
      NavigationDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: destination.label,
        enabled: destination.enabled,
      ),
    );
  }
  final binding = _binding(node, EventTagId.navigationDestinationSelected);
  return NavigationBar(
    selectedIndex: props.selectedIndex,
    destinations: destinations,
    onDestinationSelected: binding == null || onEvent == null
        ? null
        : (index) => onEvent(
            RendererEvent(
              nodeId: node.id,
              eventTag: binding.eventTag,
              handlerId: binding.handlerId,
              payload: Int64EventPayload(index),
            ),
          ),
  );
}

Widget _buildMaterialRadioGroup(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialRadioGroupProps>(node);
  final expected = props.options.where((option) => option.hasLabel).length;
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final radios = <Widget>[];
  for (final option in props.options) {
    final radio = Radio<int>(value: option.id, enabled: option.enabled);
    radios.add(
      option.hasLabel
          ? Row(
              children: [
                radio,
                Expanded(child: children[childIndex++]),
              ],
            )
          : radio,
    );
  }
  final binding = _binding(node, EventTagId.radioSelected);
  return RadioGroup<int>(
    groupValue: props.selectedId,
    onChanged: binding == null || onEvent == null
        ? (_) {}
        : (value) {
            if (value == null) return;
            onEvent(
              RendererEvent(
                nodeId: node.id,
                eventTag: binding.eventTag,
                handlerId: binding.handlerId,
                payload: Int64EventPayload(value),
              ),
            );
          },
    child: Column(mainAxisSize: MainAxisSize.min, children: radios),
  );
}

Widget _buildMaterialSlider(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  return _MaterialSliderHost(node: node, onEvent: onEvent);
}

Widget _buildMaterialRangeSlider(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  return _MaterialRangeSliderHost(node: node, onEvent: onEvent);
}

Widget _buildMaterialChip(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialChipProps>(node);
  final expected =
      1 + (props.hasAvatar ? 1 : 0) + (props.hasDeleteIcon ? 1 : 0);
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final avatar = props.hasAvatar ? children[childIndex++] : null;
  final label = children[childIndex++];
  final deleteIcon = props.hasDeleteIcon ? children[childIndex] : null;
  final pressBinding = _binding(node, EventTagId.press);
  final selectedBinding = _binding(node, EventTagId.valueChanged);
  final deleteBinding = _binding(node, EventTagId.delete);
  VoidCallback? unitCallback(EventBinding? binding, bool enabled) =>
      enabled && binding != null && onEvent != null
      ? () => onEvent(
          RendererEvent(
            nodeId: node.id,
            eventTag: binding.eventTag,
            handlerId: binding.handlerId,
            payload: const UnitEventPayload(),
          ),
        )
      : null;
  final onSelected =
      props.enabled &&
          props.hasOnSelected &&
          selectedBinding != null &&
          onEvent != null
      ? (bool value) => onEvent(
          RendererEvent(
            nodeId: node.id,
            eventTag: selectedBinding.eventTag,
            handlerId: selectedBinding.handlerId,
            payload: BoolEventPayload(value),
          ),
        )
      : null;
  return switch (props.variant) {
    MaterialChipVariant.action => ActionChip(
      avatar: avatar,
      label: label,
      onPressed: unitCallback(pressBinding, props.enabled && props.hasOnPress),
    ),
    MaterialChipVariant.filter => FilterChip(
      avatar: avatar,
      label: label,
      selected: props.selected,
      onSelected: onSelected,
    ),
    MaterialChipVariant.choice => ChoiceChip(
      avatar: avatar,
      label: label,
      selected: props.selected,
      onSelected: onSelected,
    ),
    MaterialChipVariant.input => () {
      final onPressed = unitCallback(
        pressBinding,
        props.enabled && props.hasOnPress,
      );
      final chip = InputChip(
        avatar: avatar,
        label: label,
        selected: props.selected,
        deleteIcon: deleteIcon,
        onSelected: onSelected,
        onDeleted: unitCallback(
          deleteBinding,
          props.enabled && props.hasOnDelete,
        ),
      );
      return onPressed == null
          ? chip
          : GestureDetector(onTap: onPressed, child: chip);
    }(),
  };
}

Widget _buildMaterialAlertDialog(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialAlertDialogProps>(node);
  final expected =
      (props.hasIcon ? 1 : 0) +
      (props.hasTitle ? 1 : 0) +
      (props.hasContent ? 1 : 0) +
      props.actionCount;
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final icon = props.hasIcon ? children[childIndex++] : null;
  final title = props.hasTitle ? children[childIndex++] : null;
  final content = props.hasContent ? children[childIndex++] : null;
  return AlertDialog(
    icon: icon,
    title: title,
    content: content,
    actions: children.sublist(childIndex),
  );
}

final class _MaterialSliderHost extends StatefulWidget {
  const _MaterialSliderHost({required this.node, required this.onEvent});
  final UiNode node;
  final RendererEventCallback? onEvent;

  @override
  State<_MaterialSliderHost> createState() => _MaterialSliderHostState();
}

final class _MaterialSliderHostState extends State<_MaterialSliderHost> {
  double? _pending;
  bool _scheduled = false;

  void _emit(EventBinding binding, double value) => widget.onEvent!(
    RendererEvent(
      nodeId: widget.node.id,
      eventTag: binding.eventTag,
      handlerId: binding.handlerId,
      payload: FloatEventPayload(value),
    ),
  );

  void _coalesce(EventBinding binding, double value) {
    _pending = value;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final pending = _pending;
      _pending = null;
      if (mounted && pending != null) _emit(binding, pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.node.props as MaterialSliderProps;
    final changed = _binding(widget.node, EventTagId.sliderChanged);
    final ended = _binding(widget.node, EventTagId.sliderChangeEnd);
    return Slider(
      value: props.value,
      min: props.min,
      max: props.max,
      divisions: props.divisions,
      label: props.label,
      onChanged:
          props.enabled &&
              props.hasOnChange &&
              changed != null &&
              widget.onEvent != null
          ? (value) => _coalesce(changed, value)
          : null,
      onChangeEnd: props.enabled && ended != null && widget.onEvent != null
          ? (value) => _emit(ended, value)
          : null,
    );
  }
}

final class _MaterialRangeSliderHost extends StatefulWidget {
  const _MaterialRangeSliderHost({required this.node, required this.onEvent});
  final UiNode node;
  final RendererEventCallback? onEvent;

  @override
  State<_MaterialRangeSliderHost> createState() =>
      _MaterialRangeSliderHostState();
}

final class _MaterialRangeSliderHostState
    extends State<_MaterialRangeSliderHost> {
  RangeValues? _pending;
  bool _scheduled = false;

  void _emit(EventBinding binding, RangeValues value) => widget.onEvent!(
    RendererEvent(
      nodeId: widget.node.id,
      eventTag: binding.eventTag,
      handlerId: binding.handlerId,
      payload: FloatRangeEventPayload(start: value.start, end: value.end),
    ),
  );

  void _coalesce(EventBinding binding, RangeValues value) {
    _pending = value;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final pending = _pending;
      _pending = null;
      if (mounted && pending != null) _emit(binding, pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.node.props as MaterialRangeSliderProps;
    final changed = _binding(widget.node, EventTagId.rangeSliderChanged);
    final ended = _binding(widget.node, EventTagId.rangeSliderChangeEnd);
    return RangeSlider(
      values: RangeValues(props.start, props.end),
      min: props.min,
      max: props.max,
      divisions: props.divisions,
      labels: props.labelStart == null && props.labelEnd == null
          ? null
          : RangeLabels(props.labelStart ?? '', props.labelEnd ?? ''),
      onChanged:
          props.enabled &&
              props.hasOnChange &&
              changed != null &&
              widget.onEvent != null
          ? (value) => _coalesce(changed, value)
          : null,
      onChangeEnd: props.enabled && ended != null && widget.onEvent != null
          ? (value) => _emit(ended, value)
          : null,
    );
  }
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
  final pages = <NavigationEntry>[];
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
    pages.add(NavigationEntry(props: pageProps, child: child));
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
  return NavigationHost(
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
