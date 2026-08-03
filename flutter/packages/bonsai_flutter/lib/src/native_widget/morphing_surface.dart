import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../protocol/frame.dart';
import 'native_widget_registry.dart';
import 'sparse_extent_transition_scope.dart';
import 'virtual_list.dart';

@immutable
final class MorphingSurfaceProps {
  const MorphingSurfaceProps({required this.expanded});

  final bool expanded;

  NativeWidgetProps toNativeWidgetProps() => NativeWidgetProps(
    kindId: NativeWidgetKind.morphingSurface,
    version: 1,
    capabilityBits: NativeCapability.semantics,
    payload: Uint8List.fromList([expanded ? 1 : 0, 0, 0, 0]),
  );

  static MorphingSurfaceProps decode(Uint8List payload) {
    if (payload.length != 4) {
      throw const FormatException(
        'Morphing surface props must contain exactly 4 bytes',
      );
    }
    if (payload[1] != 0 || payload[2] != 0 || payload[3] != 0) {
      throw const FormatException(
        'Morphing surface reserved bytes must be zero',
      );
    }
    return switch (payload[0]) {
      0 => const MorphingSurfaceProps(expanded: false),
      1 => const MorphingSurfaceProps(expanded: true),
      _ => throw const FormatException('Invalid morphing surface target state'),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MorphingSurfaceProps && other.expanded == expanded;

  @override
  int get hashCode => expanded.hashCode;
}

void registerMorphingSurface(NativeWidgetRegistry registry) {
  registry.register<MorphingSurfaceProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.morphingSurface,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits: NativeCapability.semantics,
      decodeProps: MorphingSurfaceProps.decode,
      factory: (context) {
        if (context.children.length != 2) {
          throw ArgumentError('Morphing surface requires exactly two children');
        }
        return _ScopedMorphingSurfaceHost(
          props: context.props,
          compactContent: context.children[0],
          expandedContent: context.children[1],
        );
      },
    ),
  );
}

final class _ScopedMorphingSurfaceHost extends StatelessWidget {
  const _ScopedMorphingSurfaceHost({
    required this.props,
    required this.compactContent,
    required this.expandedContent,
  });

  final MorphingSurfaceProps props;
  final Widget compactContent;
  final Widget expandedContent;

  @override
  Widget build(BuildContext context) {
    final transition = SparseExtentTransitionScope.maybeOf(context);
    return MorphingSurfaceHost(
      progress: transition?.progress ?? (props.expanded ? 1 : 0),
      expanded: props.expanded,
      sharedContent: const SizedBox.shrink(),
      compactContent: compactContent,
      expandedContent: expandedContent,
      compactContentExtent: transition?.compactExtent,
      expandedContentExtent: transition?.expandedExtent,
      expandedStyle: const MorphingSurfaceStyle(
        horizontalInset: 8,
        verticalInset: 6,
        cornerRadius: 16,
        elevation: 3,
      ),
    );
  }
}

@immutable
final class MorphingSurfaceStyle {
  const MorphingSurfaceStyle({
    this.horizontalInset = 0,
    this.verticalInset = 0,
    this.cornerRadius = 0,
    this.elevation = 0,
  });

  final double horizontalInset;
  final double verticalInset;
  final double cornerRadius;
  final double elevation;

  static MorphingSurfaceStyle lerp(
    MorphingSurfaceStyle begin,
    MorphingSurfaceStyle end,
    double progress, {
    double? cornerRadiusProgress,
  }) => MorphingSurfaceStyle(
    horizontalInset: lerpDouble(
      begin.horizontalInset,
      end.horizontalInset,
      progress,
    )!,
    verticalInset: lerpDouble(
      begin.verticalInset,
      end.verticalInset,
      progress,
    )!,
    cornerRadius: lerpDouble(
      begin.cornerRadius,
      end.cornerRadius,
      cornerRadiusProgress ?? progress,
    )!,
    elevation: lerpDouble(begin.elevation, end.elevation, progress)!,
  );
}

/// Morphs compact and expanded content using progress owned by its parent.
///
/// [expanded] is committed application state. It controls hit testing and
/// semantics even while [progress] is between its endpoints.
final class MorphingSurfaceHost extends StatelessWidget {
  const MorphingSurfaceHost({
    required this.progress,
    required this.expanded,
    required this.sharedContent,
    required this.compactContent,
    required this.expandedContent,
    this.collapsedStyle = const MorphingSurfaceStyle(),
    this.expandedStyle = const MorphingSurfaceStyle(),
    this.expandedContentOffset = 8,
    this.compactContentExtent,
    this.expandedContentExtent,
    super.key,
  });

  final double progress;
  final bool expanded;
  final Widget sharedContent;
  final Widget compactContent;
  final Widget expandedContent;
  final MorphingSurfaceStyle collapsedStyle;
  final MorphingSurfaceStyle expandedStyle;
  final double expandedContentOffset;
  final double? compactContentExtent;
  final double? expandedContentExtent;

  static const _cornerRadiusCompletionProgress = 0.5;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true;
    final effectiveProgress = (reduceMotion ? (expanded ? 1.0 : 0.0) : progress)
        .clamp(0.0, 1.0);
    final style = MorphingSurfaceStyle.lerp(
      collapsedStyle,
      expandedStyle,
      effectiveProgress,
      cornerRadiusProgress:
          (effectiveProgress / _cornerRadiusCompletionProgress).clamp(0.0, 1.0),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: style.horizontalInset,
        vertical: style.verticalInset,
      ),
      child: Material(
        elevation: style.elevation,
        borderRadius: BorderRadius.circular(style.cornerRadius),
        // Parent progress already drives shape and elevation each frame.
        animationDuration: Duration.zero,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surface,
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sharedContent,
              Expanded(child: _buildChangingContent(effectiveProgress)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangingContent(double effectiveProgress) {
    if (effectiveProgress <= 0 && !expanded) {
      return compactContent;
    }
    if (effectiveProgress >= 1 && expanded) {
      return expandedContent;
    }

    final compactOpacity = (1 - effectiveProgress / 0.35).clamp(0.0, 1.0);
    final expandedOpacity = ((effectiveProgress - 0.2) / 0.5).clamp(0.0, 1.0);
    final compact = _TransitionContent(
      active: !expanded,
      opacity: compactOpacity,
      child: compactContent,
    );
    final details = _TransitionContent(
      active: expanded,
      opacity: expandedOpacity,
      offset: Offset(0, expandedContentOffset * (1 - expandedOpacity)),
      child: expandedContent,
    );
    return Stack(
      fit: StackFit.expand,
      children: expanded
          ? [
              _position(compact, compactContentExtent),
              _position(details, expandedContentExtent),
            ]
          : [
              _position(details, expandedContentExtent),
              _position(compact, compactContentExtent),
            ],
    );
  }

  Widget _position(Widget child, double? extent) => extent == null
      ? Positioned.fill(child: child)
      : Positioned(top: 0, left: 0, right: 0, height: extent, child: child);
}

final class _TransitionContent extends StatelessWidget {
  const _TransitionContent({
    required this.active,
    required this.opacity,
    required this.child,
    this.offset = Offset.zero,
  });

  final bool active;
  final double opacity;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !active,
    child: ExcludeSemantics(
      excluding: !active,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Opacity(
          opacity: opacity,
          alwaysIncludeSemantics: active,
          child: Transform.translate(offset: offset, child: child),
        ),
      ),
    ),
  );
}
