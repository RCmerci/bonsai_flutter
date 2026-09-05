import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps both retained slots in one logical sliver without bounding pinning to
/// the app bar's scroll extent. Native headers still own collapse and snap.
class SliverAppBarHost extends MultiChildRenderObjectWidget {
  SliverAppBarHost({
    required Widget toolbar,
    required Widget? bottom,
    required this.topInset,
    super.key,
  }) : super(children: [toolbar, ?bottom]);
  final double topInset;

  @override
  RenderSliverAppBarHost createRenderObject(BuildContext context) =>
      RenderSliverAppBarHost(topInset);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverAppBarHost renderObject,
  ) {
    renderObject.topInset = topInset;
  }
}

class RenderSliverAppBarHost extends RenderSliverMainAxisGroup {
  RenderSliverAppBarHost(this._topInset);
  double _topInset;
  set topInset(double value) {
    if (_topInset == value) return;
    _topInset = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    var scrollExtent = 0.0;
    var layoutExtent = 0.0;
    var paintEnd = constraints.overlap;
    var maxPaintExtent = 0.0;
    var paintStart = 0.0;
    var obstruction = 0.0;
    var child = firstChild;
    while (child != null) {
      final offset = math.max(0.0, constraints.scrollOffset - scrollExtent);
      // Negative viewport overlap drives native stretch. Only the fixed bottom
      // clamps overlap; it follows the toolbar's visible paint edge each frame.
      final overlap = child == firstChild
          ? constraints.overlap
          : math.max(0.0, math.max(paintEnd, _topInset) - layoutExtent);
      child.layout(
        constraints.copyWith(
          scrollOffset: offset,
          precedingScrollExtent:
              constraints.precedingScrollExtent + scrollExtent,
          overlap: overlap,
          remainingPaintExtent: math.max(
            0,
            constraints.remainingPaintExtent - layoutExtent,
          ),
          cacheOrigin: math.max(constraints.cacheOrigin, -offset),
          remainingCacheExtent: math.max(
            0,
            constraints.remainingCacheExtent - layoutExtent,
          ),
        ),
        parentUsesSize: true,
      );
      final g = child.geometry!;
      if (g.scrollOffsetCorrection != null) {
        geometry = SliverGeometry(
          scrollOffsetCorrection: g.scrollOffsetCorrection,
        );
        return;
      }
      final position = layoutExtent + g.paintOrigin;
      paintStart = math.min(paintStart, position);
      (child.parentData! as SliverPhysicalParentData).paintOffset =
          constraints.axis == Axis.vertical
          ? Offset(0, position)
          : Offset(position, 0);
      paintEnd = math.max(paintEnd, position + g.paintExtent);
      scrollExtent += g.scrollExtent;
      layoutExtent += g.layoutExtent;
      maxPaintExtent += g.maxPaintExtent;
      // Reveal operations must also avoid the usable-top inset after an
      // unpinned toolbar leaves. A pinned toolbar already includes that inset.
      if (child != firstChild) obstruction = math.max(obstruction, _topInset);
      obstruction += g.maxScrollObstructionExtent;
      child = childAfter(child);
    }
    final paintExtent = (paintEnd - paintStart).clamp(
      0.0,
      constraints.remainingPaintExtent - paintStart,
    );
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintOrigin: paintStart,
      paintExtent: paintExtent,
      layoutExtent: math.min(layoutExtent, paintExtent),
      maxPaintExtent: math.max(maxPaintExtent, paintExtent),
      maxScrollObstructionExtent: obstruction,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: scrollExtent),
      hasVisualOverflow: true,
    );
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as SliverPhysicalParentData;
      data.paintOffset -= constraints.axis == Axis.vertical
          ? Offset(0, paintStart)
          : Offset(paintStart, 0);
      switch (applyGrowthDirectionToAxisDirection(
        constraints.axisDirection,
        constraints.growthDirection,
      )) {
        case AxisDirection.up:
          data.paintOffset = Offset(
            0,
            paintExtent - data.paintOffset.dy - child.geometry!.paintExtent,
          );
        case AxisDirection.left:
          data.paintOffset = Offset(
            paintExtent - data.paintOffset.dx - child.geometry!.paintExtent,
            0,
          );
        case AxisDirection.down:
        case AxisDirection.right:
          break;
      }
      child = childAfter(child);
    }
  }
}
