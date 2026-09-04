import 'dart:async';
import 'dart:collection';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/lists/components/m3e_card_list_item.dart'
    show M3ECardListItem;
import 'package:material_ui/material_ui.dart';
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
      NodeKind.materialElevatedButton: _buildMaterialButton,
      NodeKind.materialTextButton: _buildMaterialButton,
      NodeKind.materialIconButton: _buildMaterialButton,
      NodeKind.materialFilledButton: _buildMaterialButton,
      NodeKind.materialFilledTonalButton: _buildMaterialButton,
      NodeKind.materialOutlinedButton: _buildMaterialButton,
      NodeKind.materialFloatingActionButton: _buildMaterialFloatingActionButton,
      NodeKind.materialNavigationBar: _buildMaterialNavigationBar,
      NodeKind.materialRadioGroup: _buildMaterialRadioGroup,
      NodeKind.materialSegmentedButton: _buildMaterialSegmentedButton,
      NodeKind.materialSlider: _buildMaterialSlider,
      NodeKind.materialRangeSlider: _buildMaterialRangeSlider,
      NodeKind.materialActionChip: _buildMaterialChip,
      NodeKind.materialFilterChip: _buildMaterialChip,
      NodeKind.materialChoiceChip: _buildMaterialChip,
      NodeKind.materialInputChip: _buildMaterialChip,
      NodeKind.materialSearchBar: _buildMaterialSearchBar,
      NodeKind.materialTextField: _buildMaterialTextField,
      NodeKind.materialDataTable: _buildMaterialDataTable,
      NodeKind.materialStepper: _buildMaterialStepper,
      NodeKind.materialExpansionPanelList: _buildMaterialExpansionPanelList,
      NodeKind.materialSimpleDialog: _buildMaterialSimpleDialog,
      NodeKind.materialFullscreenDialog: _buildMaterialFullscreenDialog,
      NodeKind.materialCheckbox: _buildMaterialCheckbox,
      NodeKind.materialSwitch: _buildMaterialSwitch,
      NodeKind.materialDivider: _buildMaterialDivider,
      NodeKind.materialCard: _buildMaterialCard,
      NodeKind.materialCircularProgressIndicator:
          _buildMaterialCircularProgress,
      NodeKind.materialLinearProgressIndicator: _buildMaterialLinearProgress,
      NodeKind.materialExpressive: _buildMaterialExpressive,
      NodeKind.cupertinoButton: _buildCupertinoButton,
      NodeKind.cupertinoSwitch: _buildCupertinoSwitch,
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
  final child = children.single;
  if (child is _ExpressiveSliverPayload) {
    return child.sliverBuilder();
  }
  return SliverToBoxAdapter(child: child);
}

final class _ExpressiveSliverPayload extends StatelessWidget {
  const _ExpressiveSliverPayload({required this.sliverBuilder});

  final Widget Function() sliverBuilder;

  @override
  Widget build(BuildContext context) {
    throw const RendererBuildException(
      'An expressive sliver payload must be wrapped by Sliver.box',
    );
  }
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
  _expectChildCount(
    node,
    children,
    1 + (props.hasLeading ? 1 : 0) + props.actionCount,
  );
  var index = 0;
  final leading = props.hasLeading ? children[index++] : null;
  final title = children[index++];
  final actions = children.sublist(index);
  return M3EAppBar.sliver(
    pinned: props.pinned,
    floating: props.floating,
    snap: props.snap,
    centerTitle: props.centerTitle,
    backgroundColor: props.backgroundColor != null
        ? Color(props.backgroundColor!)
        : null,
    foregroundColor: props.foregroundColor != null
        ? Color(props.foregroundColor!)
        : null,
    leading: leading,
    title: props.semanticLabel == null
        ? title
        : Semantics(
            container: true,
            label: props.semanticLabel,
            textDirection: Directionality.of(context),
            child: title,
          ),
    actions: actions,
    variant: switch (props.variant) {
      0 => M3EAppBarVariant.small,
      1 => M3EAppBarVariant.medium,
      _ => M3EAppBarVariant.large,
    },
    shapeFamily: props.shape == 0
        ? M3EAppBarShapeFamily.round
        : M3EAppBarShapeFamily.square,
    density: props.density == 0
        ? M3EAppBarDensity.regular
        : M3EAppBarDensity.compact,
  );
}

void _validateSliverAppBarProps(UiNode node, SliverAppBarProps props) {
  if (props.actionCount < 0 || props.actionCount > 0xffffffff) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} has an invalid action count',
    );
  }
  if (props.snap && !props.floating) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} requires floating when snap is true',
    );
  }
  if (props.variant < 0 || props.variant > 2) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} has an invalid app bar variant',
    );
  }
  if (props.shape < 0 ||
      props.shape > 1 ||
      props.density < 0 ||
      props.density > 1) {
    throw RendererBuildException(
      'Node ${node.id} of kind ${node.kind} has invalid shape or density',
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
  return M3ECheckbox(
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
    MaterialButtonVariant.elevated => M3EButton.elevated(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.text => M3EButton.text(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.icon => M3EIconButton(
      onPressed: callback,
      icon: children.single,
    ),
    MaterialButtonVariant.filled => M3EButton.filled(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.filledTonal => M3EButton.tonal(
      autofocus: props.autofocus,
      onPressed: callback,
      child: children.single,
    ),
    MaterialButtonVariant.outlined => M3EButton.outlined(
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
      ? 2
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
    MaterialFloatingActionButtonVariant.small => M3EFab(
      autofocus: props.autofocus,
      onPressed: callback,
      size: M3EFabSize.small,
      icon: children.single,
    ),
    MaterialFloatingActionButtonVariant.standard => M3EFab(
      autofocus: props.autofocus,
      onPressed: callback,
      size: M3EFabSize.medium,
      icon: children.single,
    ),
    MaterialFloatingActionButtonVariant.large => M3EFab(
      autofocus: props.autofocus,
      onPressed: callback,
      size: M3EFabSize.large,
      icon: children.single,
    ),
    MaterialFloatingActionButtonVariant.extended => M3EExtendedFab(
      autofocus: props.autofocus,
      onPressed: callback,
      icon: children.first,
      label: _textLabel(children.last, 'extended FAB'),
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
  final destinations = <M3ENavigationBarDestination>[];
  for (final destination in props.destinations) {
    final icon = children[childIndex++];
    final selectedIcon = destination.hasSelectedIcon
        ? children[childIndex++]
        : null;
    destinations.add(
      M3ENavigationBarDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: destination.label,
        badgeCount: destination.badgeCount,
        badgeDot: destination.badgeDot,
        semanticLabel: destination.semanticLabel,
      ),
    );
  }
  final binding = _binding(node, EventTagId.navigationDestinationSelected);
  return M3ENavigationBar(
    selectedIndex: props.selectedIndex,
    destinations: destinations,
    autoLayout: props.autoLayout,
    layout: M3ENavBarLayout.values[props.layout],
    alignment: M3ENavBarAlignment.values[props.alignment],
    labelBehavior: M3ENavBarLabelBehavior.values[props.labelBehavior],
    iconBehavior: M3ENavBarIconBehavior.values[props.iconBehavior],
    size: M3ENavBarSize.values[props.size],
    shapeFamily: M3ENavBarShapeFamily.values[props.shape],
    density: M3ENavBarDensity.values[props.density],
    safeArea: props.safeArea,
    semanticLabel: props.semanticLabel,
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
  final binding = _binding(node, EventTagId.radioSelected);
  final radios = <Widget>[];
  for (final option in props.options) {
    final label = option.hasLabel ? children[childIndex++] : null;
    radios.add(
      M3ERadio<int>(
        value: option.id,
        groupValue: props.selectedId,
        onChanged: !option.enabled || binding == null || onEvent == null
            ? null
            : (value) => onEvent(
                RendererEvent(
                  nodeId: node.id,
                  eventTag: binding.eventTag,
                  handlerId: binding.handlerId,
                  payload: Int64EventPayload(value),
                ),
              ),
        label: label,
      ),
    );
  }
  return Column(mainAxisSize: MainAxisSize.min, children: radios);
}

Widget _buildMaterialSegmentedButton(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialSegmentedButtonProps>(node);
  final expected = props.segments.fold<int>(
    0,
    (count, segment) => count + (segment.hasIcon ? 2 : 1),
  );
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final segments = <M3ESegment<int>>[];
  for (final segment in props.segments) {
    final icon = segment.hasIcon ? children[childIndex++] : null;
    final label = _textLabel(children[childIndex++], 'segmented button');
    segments.add(M3ESegment<int>(value: segment.id, icon: icon, label: label));
  }
  final binding = _binding(node, EventTagId.segmentedSelectionChanged);
  return M3ESegmentedButton<int>(
    segments: segments,
    selected: props.selectedIds.toSet(),
    onSelectionChanged: !props.enabled || binding == null || onEvent == null
        ? (_) {}
        : (selection) {
            final selectedIds = selection.toList()..sort();
            onEvent(
              RendererEvent(
                nodeId: node.id,
                eventTag: binding.eventTag,
                handlerId: binding.handlerId,
                payload: Int64ListEventPayload(selectedIds),
              ),
            );
          },
    multiSelect: props.multiSelectionEnabled,
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
  final expected = 1 + (props.hasLeading ? 1 : 0);
  _expectChildCount(node, children, expected);
  var childIndex = 0;
  final leading = props.hasLeading ? children[childIndex++] : null;
  final label = _textLabel(children[childIndex++], 'chip');
  final pressBinding = _binding(node, EventTagId.press);
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
  return M3EChip(
    label: label,
    type: switch (props.variant) {
      MaterialChipVariant.action => M3EChipType.assist,
      MaterialChipVariant.choice => M3EChipType.suggestion,
      MaterialChipVariant.filter => M3EChipType.filter,
      MaterialChipVariant.input => M3EChipType.input,
    },
    leading: leading,
    selected: props.selected,
    elevated: props.presentation == MaterialChipPresentation.elevated,
    onPressed: unitCallback(pressBinding, props.enabled),
    onDeleted: unitCallback(deleteBinding, props.enabled && props.hasOnDelete),
  );
}

String _textLabel(Widget widget, String component) {
  if (widget is Text && widget.data != null) return widget.data!;
  if (widget is NodeHost) {
    final props = widget.store.node(widget.nodeId).props;
    if (props is TextProps) return props.value;
  }
  throw RendererBuildException('$component requires a plain Text label');
}

void _emitMaterialEvent(
  UiNode node,
  int tag,
  EventPayload payload,
  RendererEventCallback? onEvent,
) {
  final binding = _binding(node, tag);
  if (binding == null || onEvent == null) return;
  onEvent(
    RendererEvent(
      nodeId: node.id,
      eventTag: tag,
      handlerId: binding.handlerId,
      payload: payload,
    ),
  );
}

TextInputType _materialKeyboardType(TextKeyboardType type) => switch (type) {
  TextKeyboardType.text => TextInputType.text,
  TextKeyboardType.multiline => TextInputType.multiline,
  TextKeyboardType.number => TextInputType.number,
  TextKeyboardType.email => TextInputType.emailAddress,
  TextKeyboardType.phone => TextInputType.phone,
  TextKeyboardType.url => TextInputType.url,
};

TextInputAction _materialInputAction(TextInputActionKind action) =>
    switch (action) {
      TextInputActionKind.done => TextInputAction.done,
      TextInputActionKind.newline => TextInputAction.newline,
      TextInputActionKind.next => TextInputAction.next,
      TextInputActionKind.previous => TextInputAction.previous,
      TextInputActionKind.search => TextInputAction.search,
      TextInputActionKind.send => TextInputAction.send,
      TextInputActionKind.go => TextInputAction.go,
    };

Widget _buildMaterialSearchBar(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialSearchBarProps>(node);
  _expectChildCount(
    node,
    children,
    (props.hasLeading ? 1 : 0) + props.trailingCount,
  );
  var index = 0;
  final leading = props.hasLeading ? children[index++] : null;
  final trailing = children.sublist(index);
  final textProps = TextInputProps(
    sessionId: props.sessionId,
    documentRevision: props.documentRevision,
    value: props.value,
    enabled: props.enabled,
    readOnly: props.readOnly,
    obscureText: false,
    keyboardType: props.keyboardType,
    inputAction: props.inputAction,
    acceptedLocalRevision: props.acceptedLocalRevision,
    updateMode: props.updateMode,
    autofocus: props.autofocus,
    maxUtf8Bytes: props.maxUtf8Bytes,
  );
  return TextInputHost(
    node: node,
    props: textProps,
    resources: RendererResourceScope.of(context),
    onEvent: onEvent,
    builder: (context, controller, focusNode, onSubmitted) => M3ESearchBar(
      controller: controller,
      focusNode: focusNode,
      leading: leading,
      trailing: trailing,
      hintText: props.hintText,
      enabled: props.enabled,
      readOnly: props.readOnly,
      autoFocus: props.autofocus,
      keyboardType: _materialKeyboardType(props.keyboardType),
      textInputAction: _materialInputAction(props.inputAction),
      onSubmitted: onSubmitted,
      onTap: !props.hasOnTap
          ? null
          : () => _emitMaterialEvent(
              node,
              EventTagId.press,
              const UnitEventPayload(),
              onEvent,
            ),
    ),
  );
}

Widget _buildMaterialTextField(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialTextFieldProps>(node);
  _expectChildCount(
    node,
    children,
    (props.hasLeading ? 1 : 0) + (props.hasTrailing ? 1 : 0),
  );
  var index = 0;
  final leading = props.hasLeading ? children[index++] : null;
  final trailing = props.hasTrailing ? children[index] : null;
  return TextInputHost(
    node: node,
    props: props.textInputProps,
    resources: RendererResourceScope.of(context),
    onEvent: onEvent,
    builder: (context, controller, focusNode, onSubmitted) => M3ETextField(
      controller: controller,
      focusNode: focusNode,
      label: props.label,
      supportingText: props.supportingText,
      errorText: props.errorText,
      leading: leading,
      trailing: trailing,
      variant: props.variant == 0
          ? M3ETextFieldVariant.filled
          : M3ETextFieldVariant.outlined,
      obscureText: props.obscureText,
      enabled: props.enabled && !props.readOnly,
      keyboardType: _materialKeyboardType(props.keyboardType),
      textInputAction: _materialInputAction(props.inputAction),
      onSubmitted: onSubmitted,
      maxLines: props.maxLines,
    ),
  );
}

Widget _buildMaterialDataTable(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialDataTableProps>(node);
  final expected =
      props.columns.length +
      props.rows.fold<int>(0, (sum, row) => sum + row.cells.length);
  _expectChildCount(node, children, expected);
  var child = 0;
  final sortIndex = props.sortColumnId == null
      ? null
      : props.columns.indexWhere((column) => column.id == props.sortColumnId);
  final columns = <DataColumn>[];
  for (final column in props.columns) {
    final id = column.id;
    columns.add(
      DataColumn(
        label: children[child++],
        tooltip: column.tooltip,
        numeric: column.numeric,
        onSort: !column.sortable || !props.hasOnSort
            ? null
            : (_, ascending) => _emitMaterialEvent(
                node,
                EventTagId.tableSortRequested,
                Int64BoolEventPayload(id: id, value: ascending),
                onEvent,
              ),
      ),
    );
  }
  final selected = props.selectedRowIds.toSet();
  final rows = <DataRow>[];
  for (final row in props.rows) {
    final cells = <DataCell>[];
    for (var columnIndex = 0; columnIndex < row.cells.length; columnIndex++) {
      final cell = row.cells[columnIndex];
      final columnId = props.columns[columnIndex].id;
      cells.add(
        DataCell(
          children[child++],
          placeholder: cell.placeholder,
          showEditIcon: cell.showEditIcon,
          onTap: !cell.activatable || !props.hasOnCellActivate
              ? null
              : () => _emitMaterialEvent(
                  node,
                  EventTagId.tableCellActivated,
                  Int64PairEventPayload(first: row.id, second: columnId),
                  onEvent,
                ),
        ),
      );
    }
    rows.add(
      DataRow(
        selected: selected.contains(row.id),
        cells: cells,
        onSelectChanged: !row.selectionEnabled || !props.hasOnRowSelected
            ? null
            : (value) {
                if (value != null) {
                  _emitMaterialEvent(
                    node,
                    EventTagId.tableRowSelected,
                    Int64BoolEventPayload(id: row.id, value: value),
                    onEvent,
                  );
                }
              },
      ),
    );
  }
  return DataTable(
    columns: columns,
    rows: rows,
    sortColumnIndex: sortIndex == -1 ? null : sortIndex,
    sortAscending: props.sortAscending,
    onSelectAll: !props.hasOnSelectAll
        ? null
        : (value) {
            if (value != null) {
              _emitMaterialEvent(
                node,
                EventTagId.tableSelectAll,
                BoolEventPayload(value),
                onEvent,
              );
            }
          },
  );
}

Widget _buildMaterialStepper(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialStepperProps>(node);
  final expected = props.steps.fold<int>(
    0,
    (sum, step) =>
        sum + 2 + (step.hasSubtitle ? 1 : 0) + (step.hasLabel ? 1 : 0),
  );
  _expectChildCount(node, children, expected);
  var child = 0;
  final steps = <Step>[];
  for (final step in props.steps) {
    final title = children[child++];
    final content = children[child++];
    final subtitle = step.hasSubtitle ? children[child++] : null;
    final label = step.hasLabel ? children[child++] : null;
    steps.add(
      Step(
        title: title,
        content: content,
        subtitle: subtitle,
        label: label,
        isActive: step.active,
        state: StepState.values[step.state.index],
      ),
    );
  }
  final current = props.steps.indexWhere(
    (step) => step.id == props.currentStepId,
  );
  return KeyedSubtree(
    key: ValueKey(
      _MaterialStepperIdentity(props.steps.map((step) => step.id).toList()),
    ),
    child: Stepper(
      type: props.orientation == MaterialStepperOrientation.horizontal
          ? StepperType.horizontal
          : StepperType.vertical,
      currentStep: current,
      steps: steps,
      onStepTapped: _binding(node, EventTagId.stepSelected) == null
          ? null
          : (index) => _emitMaterialEvent(
              node,
              EventTagId.stepSelected,
              Int64EventPayload(props.steps[index].id),
              onEvent,
            ),
      onStepContinue: _binding(node, EventTagId.stepContinue) == null
          ? null
          : () => _emitMaterialEvent(
              node,
              EventTagId.stepContinue,
              const UnitEventPayload(),
              onEvent,
            ),
      onStepCancel: _binding(node, EventTagId.stepCancel) == null
          ? null
          : () => _emitMaterialEvent(
              node,
              EventTagId.stepCancel,
              const UnitEventPayload(),
              onEvent,
            ),
    ),
  );
}

final class _MaterialStepperIdentity {
  _MaterialStepperIdentity(List<int> stepIds)
    : stepIds = List.unmodifiable(stepIds);

  final List<int> stepIds;

  @override
  bool operator ==(Object other) {
    if (other is! _MaterialStepperIdentity ||
        other.stepIds.length != stepIds.length) {
      return false;
    }
    for (var index = 0; index < stepIds.length; index += 1) {
      if (other.stepIds[index] != stepIds[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(stepIds);
}

Widget _buildMaterialExpansionPanelList(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialExpansionPanelListProps>(node);
  _expectChildCount(node, children, props.panels.length * 2);
  final expanded = props.expandedIds.toSet();
  var child = 0;
  final panels = props.panels.map((panel) {
    final header = children[child++];
    final body = children[child++];
    return ExpansionPanel(
      headerBuilder: (_, _) => header,
      body: body,
      isExpanded: expanded.contains(panel.id),
      canTapOnHeader: panel.enabled && panel.canTapOnHeader,
    );
  }).toList();
  return SingleChildScrollView(
    child: ExpansionPanelList(
      children: panels,
      expansionCallback: (index, isExpanded) {
        final panel = props.panels[index];
        if (!panel.enabled) return;
        final next = expanded.toSet();
        if (isExpanded) {
          next.remove(panel.id);
        } else {
          if (props.policy == MaterialExpansionPanelPolicy.single) next.clear();
          next.add(panel.id);
        }
        final canonical = next.toList()..sort();
        _emitMaterialEvent(
          node,
          EventTagId.expansionChanged,
          Int64ListEventPayload(canonical),
          onEvent,
        );
      },
    ),
  );
}

Widget _buildMaterialSimpleDialog(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialSimpleDialogProps>(node);
  _expectChildCount(
    node,
    children,
    props.options.length + (props.hasTitle ? 1 : 0),
  );
  var child = 0;
  final title = props.hasTitle ? children[child++] : null;
  final options = <Widget>[];
  for (final option in props.options) {
    final label = children[child++];
    options.add(
      SimpleDialogOption(
        onPressed: !option.enabled
            ? null
            : () => _emitMaterialEvent(
                node,
                EventTagId.dialogOptionSelected,
                Int64EventPayload(option.id),
                onEvent,
              ),
        child: label,
      ),
    );
  }
  return SimpleDialog(title: title, children: options);
}

Widget _buildMaterialFullscreenDialog(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  _expectProps<MaterialFullscreenDialogProps>(node);
  return Dialog.fullscreen(child: children.single);
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
    final ValueChanged<double>? onChanged =
        props.enabled &&
            props.hasOnChange &&
            changed != null &&
            widget.onEvent != null
        ? (value) => _coalesce(changed, value)
        : null;
    final ValueChanged<double>? onChangeEnd =
        props.enabled && ended != null && widget.onEvent != null
        ? (value) => _emit(ended, value)
        : null;
    return switch (props.kind) {
      0 => M3ESlider(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      1 => M3ESlider.centered(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      2 => M3ESlider.wavy(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      3 => M3ESlider.wavyCentered(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      4 => M3ESlider.vertical(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      _ => M3ESlider.verticalCentered(
        value: props.value,
        min: props.min,
        max: props.max,
        divisions: props.divisions,
        label: props.label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    };
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
  M3ESliderRange? _pending;
  bool _scheduled = false;

  void _emit(EventBinding binding, M3ESliderRange value) => widget.onEvent!(
    RendererEvent(
      nodeId: widget.node.id,
      eventTag: binding.eventTag,
      handlerId: binding.handlerId,
      payload: FloatRangeEventPayload(start: value.start, end: value.end),
    ),
  );

  void _coalesce(EventBinding binding, M3ESliderRange value) {
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
    final args = (
      values: M3ESliderRange(props.start, props.end),
      min: props.min,
      max: props.max,
      divisions: props.divisions,
      labels: props.labelStart == null && props.labelEnd == null
          ? null
          : M3ESliderRangeLabels(props.labelStart ?? '', props.labelEnd ?? ''),
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
    return props.kind == 0
        ? M3ERangeSlider(
            values: args.values,
            min: args.min,
            max: args.max,
            divisions: args.divisions,
            labels: args.labels,
            onChanged: args.onChanged,
            onChangeEnd: args.onChangeEnd,
          )
        : M3ERangeSlider.wavy(
            values: args.values,
            min: args.min,
            max: args.max,
            divisions: args.divisions,
            labels: args.labels,
            onChanged: args.onChanged,
            onChangeEnd: args.onChangeEnd,
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
  return M3ESwitch(
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

Widget _buildMaterialDivider(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialDividerProps>(node);
  final divider = M3EDivider(
    axis: props.orientation == MaterialDividerOrientation.horizontal
        ? M3EDividerAxis.horizontal
        : M3EDividerAxis.vertical,
    thickness: props.thickness,
    indent: props.indent,
    endIndent: props.endIndent,
  );
  return props.orientation == MaterialDividerOrientation.horizontal
      ? SizedBox(
          height: props.spacing,
          child: Center(child: divider),
        )
      : SizedBox(
          width: props.spacing,
          child: Center(child: divider),
        );
}

Widget _buildMaterialCard(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<MaterialCardProps>(node);
  return switch (props.variant) {
    MaterialCardVariant.elevated => M3ECard(
      elevation: props.elevation,
      padding: EdgeInsets.zero,
      child: children.single,
    ),
    MaterialCardVariant.filled => M3ECard(
      variant: M3ECardVariant.filled,
      elevation: props.elevation,
      padding: EdgeInsets.zero,
      child: children.single,
    ),
    MaterialCardVariant.outlined => M3ECard(
      variant: M3ECardVariant.outlined,
      elevation: props.elevation,
      padding: EdgeInsets.zero,
      child: children.single,
    ),
  };
}

Widget _buildMaterialCircularProgress(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialCircularProgressProps>(node);
  return props.wavy
      ? M3EProgressIndicator.circularWavy(value: props.value)
      : M3EProgressIndicator.circular(value: props.value);
}

Widget _buildMaterialLinearProgress(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  _expectChildCount(node, children, 0);
  final props = _expectProps<MaterialLinearProgressProps>(node);
  return props.wavy
      ? M3EProgressIndicator.linearWavy(value: props.value)
      : M3EProgressIndicator.linear(value: props.value);
}

Widget _buildMaterialExpressive(
  BuildContext context,
  UiNode node,
  List<Widget> children,
  RendererEventCallback? onEvent,
) {
  final props = _expectProps<MaterialExpressiveProps>(node);

  void emit(int tag, EventPayload payload) {
    final binding = _binding(node, tag);
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

  void emitId(int id) =>
      emit(EventTagId.navigationDestinationSelected, Int64EventPayload(id));
  void emitActiveId(int id) =>
      emit(EventTagId.radioSelected, Int64EventPayload(id));
  void emitIds(Iterable<int> ids) => emit(
    EventTagId.segmentedSelectionChanged,
    Int64ListEventPayload((ids.toList()..sort())),
  );
  void emitOrderedIds(Iterable<int> ids) => emit(
    EventTagId.segmentedSelectionChanged,
    Int64ListEventPayload(ids.toList(growable: false)),
  );
  final selected = props.selectedIds.toSet();

  switch (props.component) {
    case 0:
      if (children.length < 2) {
        throw const RendererBuildException(
          'FAB menu requires expand and collapse icons',
        );
      }
      final itemChildren = _expressiveItemChildren(
        node,
        props.items,
        children,
        prefix: 2,
      );
      return M3EFabMenu(
        position: props.variant == 0
            ? M3EFabMenuPosition.left
            : M3EFabMenuPosition.right,
        expandIcon: children[0],
        collapseIcon: children[1],
        items: [
          for (var index = 0; index < props.items.length; index++)
            M3EFabMenuItem(
              icon: itemChildren[index].single,
              label: props.items[index].label,
              onPressed: props.items[index].enabled
                  ? () => emitId(props.items[index].id)
                  : null,
            ),
        ],
      );
    case 1:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      final multiple = props.flags & (1 << 7) != 0;
      final selectedIndices = <int>{
        for (var index = 0; index < props.items.length; index++)
          if (selected.contains(props.items[index].id)) index,
      };
      return M3EButtonGroup(
        type: props.variant ~/ 5 == 0
            ? M3EButtonGroupType.standard
            : M3EButtonGroupType.connected,
        style: _m3eButtonStyle(props.variant % 5),
        size: _m3eButtonSize(props.flags & 7),
        shape: props.flags & 8 == 0
            ? M3EButtonShape.round
            : M3EButtonShape.square,
        direction: props.flags & 16 == 0 ? Axis.horizontal : Axis.vertical,
        overflow: switch ((props.flags >> 5) & 3) {
          0 => M3EButtonGroupOverflow.none,
          1 => M3EButtonGroupOverflow.scroll,
          _ => M3EButtonGroupOverflow.menu,
        },
        selectedIndex: multiple || selectedIndices.isEmpty
            ? null
            : selectedIndices.single,
        selectedIndices: multiple ? selectedIndices : null,
        onSelectedIndexChanged: multiple
            ? null
            : (index) => emitIds(
                index == null ? const <int>[] : [props.items[index].id],
              ),
        onSelectedIndicesChanged: multiple
            ? (indices) =>
                  emitIds(indices.map((index) => props.items[index].id))
            : null,
        actions: [
          for (var index = 0; index < props.items.length; index++)
            M3EButtonGroupAction(
              icon: itemChildren[index].firstOrNull,
              label: props.items[index].label.isEmpty
                  ? null
                  : Text(props.items[index].label),
              enabled: props.items[index].enabled,
            ),
        ],
      );
    case 2:
      var childIndex = 0;
      Widget? take(int bit) =>
          props.flags & bit == 0 ? null : children[childIndex++];
      final result = M3EToggleButton(
        style: _m3eButtonStyle(props.variant),
        enabled: props.flags & 1 != 0,
        checked: props.flags & 2 != 0,
        icon: take(4),
        checkedIcon: take(8),
        label: take(16),
        onCheckedChange: (value) =>
            emit(EventTagId.valueChanged, BoolEventPayload(value)),
      );
      if (childIndex != children.length) {
        throw RendererBuildException(
          'Node ${node.id} has unexpected toggle-button children',
        );
      }
      return result;
    case 3:
      _expectChildCount(node, children, 0);
      return M3ESplitButton<int>(
        items: [
          for (final item in props.items)
            if (item.kind != 3 && item.kind != 4)
              M3ESplitButtonItem(
                value: item.id,
                child: item.label,
                enabled: item.enabled,
              ),
        ],
        label: props.primaryText,
        enabled: props.flags & 1 != 0,
        style: _m3eButtonStyle(props.variant),
        onPressed: () => emit(EventTagId.press, const UnitEventPayload()),
        onSelected: emitId,
      );
    case 4:
      _expectChildCount(node, children, 0);
      return M3EDropdownMenu<int>(
        items: [
          for (final item in props.items)
            M3EDropdownItem(
              label: item.label,
              value: item.id,
              disabled: !item.enabled,
              selected: selected.contains(item.id),
            ),
        ],
        singleSelect: props.flags & 2 == 0,
        searchEnabled: props.flags & 1 != 0,
        onSearchChanged: (value) =>
            emit(EventTagId.textSubmit, TextEventPayload(value)),
        onSelectionChanged: (items) => emitIds(items.map((item) => item.value)),
        emptyBuilder: (_) => props.variant == 1
            ? const Center(child: M3ELoadingIndicator())
            : Center(child: Text(props.secondaryText ?? 'No items')),
      );
    case 5:
      _expectChildCount(node, children, 0);
      final first = DateTime.parse(
        props.items.singleWhere((item) => item.kind == 0).label,
      );
      final last = DateTime.parse(
        props.items.singleWhere((item) => item.kind == 1).label,
      );
      final currentItem = props.items.where((item) => item.kind == 2);
      final selectable = {
        for (final item in props.items.where((item) => item.kind == 3))
          DateTime.parse(item.label),
      };
      return M3ECalendarDatePicker(
        initialDate: DateTime.parse(props.primaryText!),
        firstDate: first,
        lastDate: last,
        currentDate: currentItem.isEmpty
            ? null
            : DateTime.parse(currentItem.single.label),
        initialCalendarMode: props.variant == 0
            ? M3EDatePickerMode.day
            : M3EDatePickerMode.year,
        selectableDayPredicate: selectable.isEmpty
            ? null
            : (date) => selectable.contains(DateUtils.dateOnly(date)),
        onDateChanged: (date) => emit(
          EventTagId.civilDateChanged,
          CivilDateEventPayload(
            year: date.year,
            month: date.month,
            day: date.day,
          ),
        ),
      );
    case 6:
      _expectChildCount(node, children, 0);
      final time = props.primaryText!.split(':').map(int.parse).toList();
      return M3EDialTimePicker(
        value: M3ETime(hour: time[0], minute: time[1]),
        use24HourFormat: props.variant == 1,
        onChanged: (value) => emit(
          EventTagId.civilTimeChanged,
          CivilTimeEventPayload(hour: value.hour, minute: value.minute),
        ),
      );
    case 7:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      return M3ECarousel(
        axis: props.flags & 1 == 0 ? Axis.horizontal : Axis.vertical,
        type: M3ECarouselType.values[props.variant],
        heroAlignment: M3ECarouselHeroAlignment.values[(props.flags >> 1) & 3],
        onTap: (index) => emitId(props.items[index].id),
        onChange: (details) => emitActiveId(props.items[details.focalIndex].id),
        children: [for (final item in itemChildren) item.single],
      );
    case 8:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      if (props.variant == 2) {
        return _ExpressiveSliverPayload(
          sliverBuilder: () => SliverList.builder(
            itemCount: props.items.length,
            itemBuilder: (_, index) => M3ECardListItem(
              index: index,
              position: calculateCardPosition(index, props.items.length),
              outerRadius: M3EListCardListTheme.defaultOuterRadius,
              innerRadius: M3EListCardListTheme.defaultInnerRadius,
              gap: M3EListCardListTheme.defaultGap,
              padding: EdgeInsets.zero,
              onTap: (_) => emitId(props.items[index].id),
              child: itemChildren[index].single,
            ),
          ),
        );
      }
      return props.variant == 0
          ? M3ECardList(
              itemCount: props.items.length,
              padding: EdgeInsets.zero,
              itemBuilder: (_, index) => itemChildren[index].single,
              onTap: (index) => emitId(props.items[index].id),
            )
          : M3ECardList.builder(
              itemCount: props.items.length,
              padding: EdgeInsets.zero,
              itemBuilder: (_, index) => itemChildren[index].single,
              onTap: (index) => emitId(props.items[index].id),
            );
    case 9:
      final actionCount = (props.flags >> 8) & 0xff;
      _expectChildCount(node, children, actionCount + 2);
      return _ExpressiveSelectionHost(
        props: props,
        idle: children.first,
        actions: children.skip(1).take(actionCount).toList(growable: false),
        body: children.last,
        emitSelection: emitIds,
      );
    case 10:
    case 11:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      return _ExpressiveDismissibleHost(
        horizontal: props.component == 11,
        props: props,
        itemChildren: itemChildren,
        emitRequest: emitOrderedIds,
      );
    case 12:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      final expandedIndices = <int>{
        for (var index = 0; index < props.items.length; index++)
          if (selected.contains(props.items[index].id)) index,
      };
      void onExpansionChanged(int index, {required bool isExpanded}) {
        final next = {...selected};
        if (isExpanded) {
          if (props.variant == 1) next.clear();
          next.add(props.items[index].id);
        } else {
          next.remove(props.items[index].id);
        }
        emitIds(next);
      }
      final key = ValueKey(Object.hashAll(props.selectedIds));
      Widget headerBuilder(_, int index, double progress) =>
          Text(props.items[index].label);
      Widget bodyBuilder(_, int index, double progress) =>
          itemChildren[index].single;
      if (props.flags == 2) {
        return _ExpressiveSliverPayload(
          sliverBuilder: () => M3EExpandableList.sliverBuilder(
            key: key,
            itemCount: props.items.length,
            initiallyExpanded: expandedIndices,
            allowMultipleExpanded: props.variant == 0,
            headerBuilder: headerBuilder,
            bodyBuilder: bodyBuilder,
            onExpansionChanged: onExpansionChanged,
          ),
        );
      }
      return props.flags == 1
          ? M3EExpandableList.scrollableBuilder(
              key: key,
              itemCount: props.items.length,
              initiallyExpanded: expandedIndices,
              allowMultipleExpanded: props.variant == 0,
              headerBuilder: headerBuilder,
              bodyBuilder: bodyBuilder,
              onExpansionChanged: onExpansionChanged,
            )
          : M3EExpandableList.builder(
              key: key,
              itemCount: props.items.length,
              initiallyExpanded: expandedIndices,
              allowMultipleExpanded: props.variant == 0,
              headerBuilder: headerBuilder,
              bodyBuilder: bodyBuilder,
              onExpansionChanged: onExpansionChanged,
            );
    case 13:
      _expectChildCount(node, children, 1);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        child: M3EBottomSheet(
          showDragHandle: props.flags & 1 != 0,
          child: children.single,
        ),
      );
    case 14:
      _expectChildCount(node, children, 2);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        child: M3ESideSheet(
          title: _textLabel(children[0], 'side sheet'),
          body: children[1],
        ),
      );
    case 15:
      final hasFloatingActionButton = props.flags & 2 != 0;
      final actions = hasFloatingActionButton
          ? children.take(children.length - 1).toList(growable: false)
          : children;
      return M3EAppBar.bottom(
        actions: actions,
        floatingActionButton: hasFloatingActionButton ? children.last : null,
        safeArea: props.flags & 1 != 0,
      );
    case 16:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      final selectedIndex = props.items.indexWhere(
        (item) => selected.contains(item.id),
      );
      return M3ETabs(
        tabs: [
          for (var index = 0; index < props.items.length; index++)
            M3ETab(
              label: props.items[index].label,
              icon: itemChildren[index].firstOrNull,
            ),
        ],
        selectedIndex: selectedIndex,
        variant: props.variant == 0
            ? M3ETabsVariant.primary
            : M3ETabsVariant.secondary,
        onTabSelected: (index) => emitId(props.items[index].id),
      );
    case 17:
      final resources = RendererResourceScope.of(context);
      Widget preserveResourceScope(Widget child) =>
          RendererResourceScope(resources: resources, child: child);
      final destinationChildCount = props.items.fold<int>(
        0,
        (count, item) => count + item.childCount,
      );
      final itemChildren = _expressiveItemChildren(
        node,
        props.items,
        children.take(destinationChildCount).toList(growable: false),
      );
      var extraChildIndex = destinationChildCount;
      final trailing = props.flags & 4 != 0
          ? preserveResourceScope(children[extraChildIndex++])
          : null;
      final fabIcon = props.flags & 8 != 0
          ? preserveResourceScope(children[extraChildIndex++])
          : null;
      if (extraChildIndex != children.length) {
        throw RendererBuildException(
          'Node ${node.id} has unexpected navigation rail children',
        );
      }
      final selectedIndex = props.items.indexWhere(
        (item) => selected.contains(item.id),
      );
      final sections = <M3ENavigationRailSection>[];
      for (final sectionIndex in {
        for (final item in props.items) item.kind,
      }.toList()..sort()) {
        sections.add(
          M3ENavigationRailSection(
            destinations: [
              for (var index = 0; index < props.items.length; index++)
                if (props.items[index].kind == sectionIndex)
                  M3ENavigationRailDestination(
                    icon: preserveResourceScope(itemChildren[index].single),
                    label: props.items[index].label,
                  ),
            ],
          ),
        );
      }
      return M3ENavigationRail(
        type: props.flags & 1 == 0
            ? M3ENavigationRailType.collapsed
            : M3ENavigationRailType.expanded,
        modality: props.flags & 2 == 0
            ? M3ENavigationRailModality.standard
            : M3ENavigationRailModality.modal,
        sections: sections,
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => emitId(props.items[index].id),
        onTypeChanged: (type) => emit(
          EventTagId.valueChanged,
          BoolEventPayload(type == M3ENavigationRailType.expanded),
        ),
        trailing: trailing,
        trailingAtBottom: props.flags & 16 != 0,
        fab: fabIcon == null
            ? null
            : M3ENavigationRailFabSlot(
                icon: fabIcon,
                label: props.primaryText!,
                onPressed: props.flags & 32 == 0
                    ? null
                    : () => emitId(int.parse(props.secondaryText!)),
              ),
      );
    case 18:
      final itemChildren = _expressiveItemChildren(node, props.items, children);
      final selectedIndex = props.items.indexWhere(
        (item) => selected.contains(item.id),
      );
      return M3ENavigationDrawer(
        headline: props.primaryText,
        destinations: [
          for (var index = 0; index < props.items.length; index++)
            M3ENavigationDestination(
              icon: itemChildren[index].single,
              label: props.items[index].label,
            ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => emitId(props.items[index].id),
      );
    case 19:
      final hasFab = props.flags & 4 != 0;
      final actionChildCount = props.items.fold<int>(
        0,
        (count, item) => count + item.childCount,
      );
      _expressiveItemChildren(
        node,
        props.items,
        children.take(actionChildCount).toList(growable: false),
      );
      _expectChildCount(node, children, actionChildCount + (hasFab ? 1 : 0));
      final activeIndex = props.items.indexWhere(
        (item) => selected.contains(item.id),
      );
      final actions = <M3EToolbarItem>[
        for (var index = 0; index < props.items.length; index++)
          M3EToolbarAction(
            icon: _m3eToolbarIconData(props.items[index].kind),
            label: props.items[index].label.nullIfEmpty,
            semanticLabel: props.items[index].label.nullIfEmpty,
            enabled: props.items[index].enabled,
            active: selected.contains(props.items[index].id),
            onPressed: () => emitId(props.items[index].id),
          ),
      ];
      return props.variant == 0
          ? M3EToolbar(
              axis: props.flags & 1 == 0 ? Axis.horizontal : Axis.vertical,
              expanded: props.flags & 2 != 0,
              onExpandedChanged: (value) =>
                  emit(EventTagId.valueChanged, BoolEventPayload(value)),
              maxInlineActions: (props.flags >> 8) & 0xff,
              activeIndex: activeIndex < 0 ? null : activeIndex,
              onActiveIndexChanged: (index) =>
                  emitActiveId(props.items[index].id),
              fabIcon: hasFab ? children.last : null,
              onFabPressed: !hasFab || props.flags & 8 == 0
                  ? null
                  : () => emitId(int.parse(props.secondaryText!)),
              actions: actions,
            )
          : M3EToolbar.docked(
              maxInlineActions: (props.flags >> 8) & 0xff,
              activeIndex: activeIndex < 0 ? null : activeIndex,
              onActiveIndexChanged: (index) =>
                  emitActiveId(props.items[index].id),
              actions: actions,
            );
    case 20:
      _expectChildCount(node, children, 1);
      return M3EMenu(
        anchorBuilder: (_, open) =>
            GestureDetector(onTap: open, child: children.single),
        children: _m3eMenuNodes(props.items, emitId),
        onSelected: (value) {
          if (value is int) emitId(value);
        },
      );
    case 21:
      _expectChildCount(node, children, 1);
      return M3EBadge(
        alignment: M3EBadgeAlignment.values[props.variant],
        count: props.value?.toInt(),
        showDot: props.value == null,
        child: children.single,
      );
    case 22:
      _expectChildCount(node, children, 0);
      return M3ELoadingIndicator(
        variant: props.variant == 0
            ? M3ELoadingIndicatorVariant.defaultStyle
            : M3ELoadingIndicatorVariant.contained,
        rotationTurns: props.value,
      );
    case 23:
      _expectChildCount(node, children, 1);
      return _ExpressiveRefreshHost(
        props: props,
        emitRequest: emitOrderedIds,
        child: children.single,
      );
    case 24:
      final textProps = props.textInput;
      if (textProps == null) {
        throw RendererBuildException(
          'Node ${node.id} search anchor requires revisioned text input state',
        );
      }
      final hasBarLeading = props.flags & 2 != 0;
      final barTrailingCount = (props.flags >> 8) & 0xff;
      _expectChildCount(
        node,
        children,
        (hasBarLeading ? 1 : 0) + barTrailingCount,
      );
      final barLeading = hasBarLeading ? children.first : null;
      final barTrailing = children
          .skip(hasBarLeading ? 1 : 0)
          .toList(growable: false);
      return TextInputHost(
        node: node,
        props: textProps,
        resources: RendererResourceScope.of(context),
        onEvent: onEvent,
        controllerFactory: (value) => M3ESearchController()..value = value,
        builder: (context, controller, focusNode, onSubmitted) {
          final searchController = controller as M3ESearchController;
          return M3ESearchAnchor.bar(
            searchController: searchController,
            isFullScreen: props.variant == 0,
            barLeading: barLeading,
            barTrailing: barTrailing,
            barHintText: props.primaryText,
            enabled: textProps.enabled,
            keyboardType: _materialKeyboardType(textProps.keyboardType),
            textInputAction: _materialInputAction(textProps.inputAction),
            onSubmitted: onSubmitted,
            onOpen: () {
              focusNode.requestFocus();
              emit(EventTagId.searchOpened, const UnitEventPayload());
            },
            onClose: () {
              focusNode.unfocus();
              emit(EventTagId.searchClosed, const UnitEventPayload());
            },
            suggestionsBuilder: (_, controller) => [
              for (final suggestion in props.items)
                M3EButton.text(
                  onPressed: suggestion.enabled
                      ? () {
                          emitId(suggestion.id);
                          controller.closeView(suggestion.label);
                        }
                      : null,
                  child: Text(suggestion.label),
                ),
            ],
          );
        },
      );
    case 25:
      if (children.isEmpty) {
        throw const RendererBuildException('Tooltip requires an anchor child');
      }
      final actions = children.skip(1).toList(growable: false);
      if (actions.length != props.flags) {
        throw RendererBuildException(
          'Node ${node.id} tooltip action count does not match its children',
        );
      }
      return M3ETooltip(
        message: props.variant == 0 ? props.secondaryText : null,
        richTitle: props.variant == 1 ? props.primaryText : null,
        richMessage: props.variant == 1 ? props.secondaryText : null,
        actions: actions,
        child: children.first,
      );
    case 26:
      final hasLeading = props.flags & 4 != 0;
      final hasTrailing = props.flags & 8 != 0;
      _expectChildCount(
        node,
        children,
        (hasLeading ? 1 : 0) + (hasTrailing ? 1 : 0),
      );
      var childIndex = 0;
      final leading = hasLeading ? children[childIndex++] : null;
      final trailing = hasTrailing ? children[childIndex++] : null;
      return M3EListItem(
        headline: props.primaryText!,
        supportingText: props.secondaryText,
        overline: props.items.single.label.nullIfEmpty,
        leading: leading,
        trailing: trailing,
        selected: props.flags & 2 != 0,
        onTap: props.flags & 1 == 0
            ? null
            : () => emit(EventTagId.press, const UnitEventPayload()),
      );
    case 27:
      final hasIcon = props.flags & 1 != 0;
      final hasContent = props.flags & 2 != 0;
      final actionCount = props.items.single.childCount;
      _expectChildCount(
        node,
        children,
        (hasIcon ? 1 : 0) + (hasContent ? 1 : 0) + actionCount,
      );
      var childIndex = 0;
      final icon = hasIcon ? children[childIndex++] : null;
      final content = hasContent ? children[childIndex++] : null;
      return M3EDialog(
        title: props.primaryText!,
        icon: icon,
        content: content,
        actions: children.skip(childIndex).toList(growable: false),
        topDivider: props.flags & 4 != 0,
        bottomDivider: props.flags & 8 != 0,
      );
    case 28:
      final hasLeading = props.flags & 4 != 0;
      final actionCount = (props.flags >> 8) & 0xff;
      final hasBarLeading = props.flags & 8 != 0;
      final barTrailingCount = (props.flags >> 16) & 0xff;
      final appBarChildren = (hasLeading ? 1 : 0) + actionCount;
      _expectChildCount(
        node,
        children,
        appBarChildren + (hasBarLeading ? 1 : 0) + barTrailingCount,
      );
      final textProps = props.textInput;
      if (textProps == null) {
        throw RendererBuildException(
          'Node ${node.id} search app bar requires revisioned text input state',
        );
      }
      final leading = hasLeading ? children.first : null;
      final actions = children
          .skip(hasLeading ? 1 : 0)
          .take(actionCount)
          .toList(growable: false);
      final barLeading = hasBarLeading ? children[appBarChildren] : null;
      final barTrailing = children
          .skip(appBarChildren + (hasBarLeading ? 1 : 0))
          .toList(growable: false);
      return TextInputHost(
        node: node,
        props: textProps,
        resources: RendererResourceScope.of(context),
        onEvent: onEvent,
        controllerFactory: (value) => M3ESearchController()..value = value,
        builder: (context, controller, focusNode, onSubmitted) {
          final searchController = controller as M3ESearchController;
          return M3EAppBar.search(
            searchController: searchController,
            suggestionsBuilder: (_, controller) => [
              for (final suggestion in props.items)
                M3EButton.text(
                  onPressed: suggestion.enabled
                      ? () {
                          emitId(suggestion.id);
                          controller.closeView(suggestion.label);
                        }
                      : null,
                  child: Text(suggestion.label),
                ),
            ],
            leading: leading,
            actions: actions,
            centerTitle: props.flags & 1 != 0,
            isFullScreen: props.flags & 2 != 0,
            barHintText: props.primaryText,
            barLeading: barLeading,
            barTrailing: barTrailing,
            onSubmitted: onSubmitted,
            onOpen: () {
              focusNode.requestFocus();
              emit(EventTagId.searchOpened, const UnitEventPayload());
            },
            onClose: () {
              focusNode.unfocus();
              emit(EventTagId.searchClosed, const UnitEventPayload());
            },
          );
        },
      );
    case 29:
      _expectChildCount(node, children, 2);
      if (props.items.length != 1) {
        throw RendererBuildException(
          'Node ${node.id} selection leading requires one item descriptor',
        );
      }
      return M3ESelectionLeading(
        selected: props.flags & 1 != 0,
        selectedChild: children.last,
        onTap: () => emitId(props.items.single.id),
        child: children.first,
      );
    case 30:
      final hasLeading = props.flags & 2 != 0;
      final actionCount = (props.flags >> 8) & 0xff;
      _expectChildCount(node, children, (hasLeading ? 1 : 0) + 1 + actionCount);
      final titleIndex = hasLeading ? 1 : 0;
      return M3EAppBar.top(
        leading: hasLeading ? children.first : null,
        title: children[titleIndex],
        actions: children.skip(titleIndex + 1).toList(growable: false),
        centerTitle: props.flags & 1 != 0,
        safeArea: props.flags & 4 != 0,
        semanticLabel: props.primaryText,
      );
    default:
      throw RendererBuildException(
        'Unknown Material Expressive component ${props.component}',
      );
  }
}

final class _ExpressiveSelectionHost extends StatefulWidget {
  const _ExpressiveSelectionHost({
    required this.props,
    required this.idle,
    required this.actions,
    required this.body,
    required this.emitSelection,
  });

  final MaterialExpressiveProps props;
  final Widget idle;
  final List<Widget> actions;
  final Widget body;
  final ValueChanged<Iterable<int>> emitSelection;

  @override
  State<_ExpressiveSelectionHost> createState() =>
      _ExpressiveSelectionHostState();
}

final class _ExpressiveSelectionHostState
    extends State<_ExpressiveSelectionHost> {
  late final M3ESelectionController _controller;

  Set<int> get _selectedIndices => {
    for (var index = 0; index < widget.props.items.length; index++)
      if (widget.props.selectedIds.contains(widget.props.items[index].id))
        index,
  };

  @override
  void initState() {
    super.initState();
    _controller = M3ESelectionController(initialSelected: _selectedIndices);
  }

  @override
  void didUpdateWidget(_ExpressiveSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronizeController();
  }

  void _synchronizeController() {
    final desired = _selectedIndices;
    final current = _controller.selectedIndices;
    if (desired.length == current.length && desired.containsAll(current)) {
      return;
    }
    _controller.clear();
    for (final index in desired) {
      _controller.select(index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = widget.props.selectedIds;
    return PopScope<void>(
      canPop: selectedIds.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selectedIds.isNotEmpty) {
          widget.emitSelection(const <int>[]);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return SizedBox(
            height: height,
            child: M3ESelection(
              controller: _controller,
              itemCount: widget.props.items.length,
              scaffold: false,
              appBar: M3ESelectionAppBar(
                idle: widget.idle,
                actions: widget.actions,
                showSelectAll: widget.props.flags & 1 != 0,
                onClear: () => widget.emitSelection(const <int>[]),
                onAllSelected: (allSelected) => widget.emitSelection(
                  allSelected
                      ? widget.props.items.map((item) => item.id)
                      : const <int>[],
                ),
              ),
              body: widget.body,
            ),
          );
        },
      ),
    );
  }
}

final class _ExpressiveDismissibleHost extends StatefulWidget {
  const _ExpressiveDismissibleHost({
    required this.horizontal,
    required this.props,
    required this.itemChildren,
    required this.emitRequest,
  });

  final bool horizontal;
  final MaterialExpressiveProps props;
  final List<List<Widget>> itemChildren;
  final ValueChanged<Iterable<int>> emitRequest;

  @override
  State<_ExpressiveDismissibleHost> createState() =>
      _ExpressiveDismissibleHostState();
}

final class _ExpressiveDismissibleHostState
    extends State<_ExpressiveDismissibleHost> {
  Completer<bool>? _pending;
  int? _pendingToken;

  int get _token => int.parse(widget.props.secondaryText!);
  int get _state => widget.props.variant;

  @override
  void didUpdateWidget(_ExpressiveDismissibleHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    if (_token != _pendingToken) {
      pending.complete(false);
      _clearPending();
    } else if (_state == 2 || _state == 3) {
      pending.complete(_state == 2);
      _clearPending();
    }
  }

  void _clearPending() {
    _pending = null;
    _pendingToken = null;
  }

  Future<bool> _dismiss(int index, DismissDirection direction) {
    final current = _pending;
    if (current != null && !current.isCompleted) return current.future;
    final completer = Completer<bool>();
    _pending = completer;
    _pendingToken = _token;
    final directionId = switch (direction) {
      DismissDirection.startToEnd => 0,
      DismissDirection.endToStart => 1,
      DismissDirection.up => 2,
      DismissDirection.down => 3,
      DismissDirection.horizontal => 4,
      DismissDirection.vertical => 5,
      DismissDirection.none => 6,
    };
    widget.emitRequest([_token, widget.props.items[index].id, directionId]);
    return completer.future;
  }

  @override
  void dispose() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.horizontal) {
      return M3EDismissibleColumn(
        itemCount: widget.props.items.length,
        itemBuilder: (_, index) => widget.itemChildren[index].single,
        onDismiss: _dismiss,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final nestedInVerticalScroll = !constraints.hasBoundedHeight;
        return M3EDismissibleList(
          itemCount: widget.props.items.length,
          itemBuilder: (_, index) => widget.itemChildren[index].single,
          onDismiss: _dismiss,
          shrinkWrap: nestedInVerticalScroll,
          physics: nestedInVerticalScroll
              ? const NeverScrollableScrollPhysics()
              : null,
        );
      },
    );
  }
}

final class _ExpressiveRefreshHost extends StatefulWidget {
  const _ExpressiveRefreshHost({
    required this.props,
    required this.emitRequest,
    required this.child,
  });

  final MaterialExpressiveProps props;
  final ValueChanged<Iterable<int>> emitRequest;
  final Widget child;

  @override
  State<_ExpressiveRefreshHost> createState() => _ExpressiveRefreshHostState();
}

final class _ExpressiveRefreshHostState extends State<_ExpressiveRefreshHost> {
  final M3ERefreshIndicatorController _controller =
      M3ERefreshIndicatorController();
  Completer<void>? _pending;
  int? _pendingToken;
  int? _lastShownToken;

  int get _token => int.parse(widget.props.secondaryText!);
  int get _state => widget.props.flags;
  int? get _showToken => int.tryParse(widget.props.primaryText ?? '');

  @override
  void didUpdateWidget(_ExpressiveRefreshHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    if (_token != _pendingToken || _state == 2) {
      pending.complete();
      _pending = null;
      _pendingToken = null;
    }
  }

  Future<void> _refresh() {
    final current = _pending;
    if (current != null && !current.isCompleted) return current.future;
    final completer = Completer<void>();
    _pending = completer;
    _pendingToken = _token;
    widget.emitRequest([_token]);
    return completer.future;
  }

  void _scheduleProgrammaticShow() {
    final token = _showToken;
    if (token == null || token == _lastShownToken) return;
    _lastShownToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showToken == token) {
        _controller.show();
      }
    });
  }

  @override
  void dispose() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleProgrammaticShow();
    return switch (widget.props.variant) {
      0 => M3ERefreshIndicator(
        controller: _controller,
        onRefresh: _refresh,
        child: widget.child,
      ),
      1 => M3ERefreshIndicator.contained(
        controller: _controller,
        onRefresh: _refresh,
        child: widget.child,
      ),
      2 => M3ERefreshIndicator.material(
        controller: _controller,
        onRefresh: _refresh,
        child: widget.child,
      ),
      3 => M3ERefreshIndicator.adaptive(
        controller: _controller,
        onRefresh: _refresh,
        child: widget.child,
      ),
      _ => M3ERefreshIndicator.noSpinner(
        controller: _controller,
        onRefresh: _refresh,
        child: widget.child,
      ),
    };
  }
}

List<List<Widget>> _expressiveItemChildren(
  UiNode node,
  List<MaterialExpressiveItemProps> items,
  List<Widget> children, {
  int prefix = 0,
}) {
  var childIndex = prefix;
  final result = <List<Widget>>[];
  for (final item in items) {
    final end = childIndex + item.childCount;
    if (end > children.length) {
      throw RendererBuildException(
        'Node ${node.id} has fewer children than its item descriptors',
      );
    }
    result.add(children.sublist(childIndex, end));
    childIndex = end;
  }
  if (childIndex != children.length) {
    throw RendererBuildException(
      'Node ${node.id} has children not owned by an item descriptor',
    );
  }
  return result;
}

M3EButtonStyle _m3eButtonStyle(int value) => switch (value) {
  0 => M3EButtonStyle.filled,
  1 => M3EButtonStyle.tonal,
  2 => M3EButtonStyle.elevated,
  3 => M3EButtonStyle.outlined,
  _ => M3EButtonStyle.text,
};

M3EButtonSize _m3eButtonSize(int value) => switch (value) {
  0 => M3EButtonSize.xs,
  1 => M3EButtonSize.sm,
  2 => M3EButtonSize.md,
  3 => M3EButtonSize.lg,
  _ => M3EButtonSize.xl,
};

IconData _m3eToolbarIconData(int value) => switch (value) {
  0 => M3EIcons.add,
  1 => M3EIcons.edit,
  2 => M3EIcons.delete,
  3 => M3EIcons.favorite,
  4 => M3EIcons.more_vert,
  5 => M3EIcons.search,
  6 => M3EIcons.share,
  _ => throw RendererBuildException('Unknown toolbar icon $value'),
};

List<M3EMenuNode> _m3eMenuNodes(
  List<MaterialExpressiveItemProps> items,
  void Function(int) onSelected,
) {
  var index = 0;

  M3EMenuNode read() {
    final item = items[index++];
    final children = <M3EMenuNode>[
      for (var i = 0; i < item.childCount; i++) read(),
    ];
    return switch (item.kind) {
      1 => M3EMenuSelectable(
        label: item.label,
        value: item.id,
        selected: item.selected,
        enabled: item.enabled,
      ),
      2 => M3EMenuToggleable(
        label: item.label,
        checked: item.selected,
        enabled: item.enabled,
        onChanged: (_) => onSelected(item.id),
      ),
      3 => const M3EMenuDivider(),
      4 => M3EMenuGroup(label: item.label.nullIfEmpty, children: children),
      5 => M3EMenuSubmenu(
        label: item.label,
        enabled: item.enabled,
        children: children,
      ),
      _ => M3EMenuEntry(
        label: item.label,
        value: item.id,
        enabled: item.enabled,
      ),
    };
  }

  final result = <M3EMenuNode>[];
  while (index < items.length) {
    result.add(read());
  }
  return result;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
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
