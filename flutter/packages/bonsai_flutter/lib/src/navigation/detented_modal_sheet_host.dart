import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gesture/bonsai_gesture_detector.dart';
import '../protocol/frame.dart';

final class DetentedModalSheetHost extends StatefulWidget {
  const DetentedModalSheetHost({
    required this.sizing,
    required this.canDismiss,
    required this.requestDismiss,
    required this.reducedMotion,
    required this.child,
    super.key,
  });

  final DetentedModalSheetSizing sizing;
  final bool Function() canDismiss;
  final Future<bool> Function() requestDismiss;
  final bool reducedMotion;
  final Widget child;

  @override
  State<DetentedModalSheetHost> createState() => DetentedModalSheetHostState();
}

final class DetentedModalSheetHostState extends State<DetentedModalSheetHost> {
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
  void didUpdateWidget(DetentedModalSheetHost oldWidget) {
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
          child: BonsaiGestureDetector(
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
