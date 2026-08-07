import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum RendererViewportAxis { vertical, horizontal }

final class RendererConstraintViolation implements Exception {
  const RendererConstraintViolation({
    required this.nodeId,
    required this.localRevision,
    required this.widgetKind,
    required this.axis,
    required this.constraints,
  });

  final int nodeId;
  final int localRevision;
  final String widgetKind;
  final RendererViewportAxis axis;
  final BoxConstraints constraints;

  String get guidance => switch (axis) {
    RendererViewportAxis.vertical =>
      'Place it in Body.Vertical.fill or use Viewport.Vertical.with_height.',
    RendererViewportAxis.horizontal =>
      'Place it in Body.Horizontal.fill or use Viewport.Horizontal.with_width.',
  };

  @override
  String toString() =>
      '$widgetKind node $nodeId requires bounded ${axis.name} constraints. '
      'Received $constraints. $guidance';
}

final class RendererLayoutError extends StatelessWidget {
  const RendererLayoutError({required this.violation, super.key});

  final RendererConstraintViolation violation;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: violation.axis == RendererViewportAxis.horizontal ? 240 : null,
    height: violation.axis == RendererViewportAxis.vertical ? 72 : null,
    child: ColoredBox(
      color: const Color(0xffffe9e9),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          kDebugMode ? violation.toString() : 'Unable to render this view.',
          textDirection: TextDirection.ltr,
          maxLines: 3,
        ),
      ),
    ),
  );
}

typedef ViewportConstraintBuilder =
    Widget Function(BuildContext context, BoxConstraints constraints);

final class ViewportConstraintGuard extends StatefulWidget {
  const ViewportConstraintGuard({
    required this.nodeId,
    required this.localRevision,
    required this.widgetKind,
    required this.axis,
    required this.builder,
    super.key,
  });

  final int nodeId;
  final int localRevision;
  final String widgetKind;
  final RendererViewportAxis axis;
  final ViewportConstraintBuilder builder;

  @override
  State<ViewportConstraintGuard> createState() =>
      _ViewportConstraintGuardState();
}

final class _ViewportConstraintGuardState
    extends State<ViewportConstraintGuard> {
  ({int nodeId, int localRevision, RendererViewportAxis axis})? _reported;

  @override
  void didUpdateWidget(ViewportConstraintGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId ||
        oldWidget.localRevision != widget.localRevision ||
        oldWidget.axis != widget.axis) {
      _reported = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final bounded = switch (widget.axis) {
        RendererViewportAxis.vertical => constraints.hasBoundedHeight,
        RendererViewportAxis.horizontal => constraints.hasBoundedWidth,
      };
      if (bounded) {
        return widget.builder(context, constraints);
      }

      final violation = RendererConstraintViolation(
        nodeId: widget.nodeId,
        localRevision: widget.localRevision,
        widgetKind: widget.widgetKind,
        axis: widget.axis,
        constraints: constraints,
      );
      final identity = (
        nodeId: widget.nodeId,
        localRevision: widget.localRevision,
        axis: widget.axis,
      );
      if (_reported != identity) {
        _reported = identity;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: violation,
            library: 'bonsai_flutter',
            context: ErrorDescription(
              'while validating ${widget.widgetKind} node ${widget.nodeId}',
            ),
          ),
        );
      }
      return RendererLayoutError(violation: violation);
    },
  );
}
