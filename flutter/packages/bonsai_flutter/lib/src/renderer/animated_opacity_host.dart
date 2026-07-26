import 'package:flutter/widgets.dart';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import 'renderer_event.dart';
import 'renderer_resource_store.dart';

final class AnimatedOpacityHost extends StatefulWidget {
  const AnimatedOpacityHost({
    required this.nodeId,
    required this.opacity,
    required this.animation,
    required this.completionBinding,
    required this.onEvent,
    required this.child,
    super.key,
  });

  final int nodeId;
  final double opacity;
  final AnimationIntent animation;
  final EventBinding? completionBinding;
  final RendererEventCallback? onEvent;
  final Widget child;

  @override
  State<AnimatedOpacityHost> createState() => _AnimatedOpacityHostState();
}

final class _AnimatedOpacityHostState extends State<AnimatedOpacityHost>
    with SingleTickerProviderStateMixin {
  late RendererResourceStore _resources;
  late AnimationResourceHandle _resource;
  bool _initialized = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resources = RendererResourceScope.of(context);
    _resource = _resources.acquireAnimation(
      nodeId: widget.nodeId,
      vsync: this,
      initialValue: widget.opacity,
    );
    _initialized = true;
  }

  @override
  void didUpdateWidget(AnimatedOpacityHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousResource = _resource;
    _resource = _resources.acquireAnimation(
      nodeId: widget.nodeId,
      vsync: this,
      initialValue: widget.opacity,
    );
    if (!identical(previousResource, _resource)) {
      return;
    }
    if (oldWidget.opacity == widget.opacity &&
        oldWidget.animation == widget.animation) {
      return;
    }
    _applyTarget();
  }

  @override
  void dispose() {
    _generation += 1;
    super.dispose();
  }

  void _applyTarget() {
    final generation = ++_generation;
    final animation = widget.animation;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations || animation.durationMilliseconds == 0) {
      _resource.controller.value = widget.opacity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _emitCompletion(animation.id, generation);
      });
      return;
    }
    _resource.controller
        .animateTo(
          widget.opacity,
          duration: Duration(milliseconds: animation.durationMilliseconds),
          curve: _curve(animation.curve),
        )
        .orCancel
        .then(
          (_) => _emitCompletion(animation.id, generation),
          onError: (Object error, StackTrace stackTrace) {
            if (error is! TickerCanceled) {
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stackTrace,
                  library: 'bonsai_flutter',
                  context: ErrorDescription(
                    'while running opacity animation ${animation.id}',
                  ),
                ),
              );
            }
          },
        );
  }

  void _emitCompletion(int animationId, int generation) {
    if (!mounted || generation != _generation) return;
    final binding = widget.completionBinding;
    final onEvent = widget.onEvent;
    if (binding == null || onEvent == null) return;
    onEvent(
      RendererEvent(
        nodeId: widget.nodeId,
        eventTag: binding.eventTag,
        handlerId: binding.handlerId,
        payload: Int64EventPayload(animationId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return widget.child;
    return AnimatedBuilder(
      animation: _resource.controller,
      builder: (_, child) =>
          Opacity(opacity: _resource.controller.value, child: child),
      child: widget.child,
    );
  }
}

Curve _curve(AnimationCurveValue curve) => switch (curve) {
  AnimationCurveValue.linear => Curves.linear,
  AnimationCurveValue.easeIn => Curves.easeIn,
  AnimationCurveValue.easeOut => Curves.easeOut,
  AnimationCurveValue.easeInOut => Curves.easeInOut,
};
