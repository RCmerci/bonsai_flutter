import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'touch_intent.dart';

final class BonsaiTapGestureRecognizer extends TapGestureRecognizer {
  BonsaiTapGestureRecognizer({super.debugOwner, super.supportedDevices});

  final TouchIntentTracker _intentTracker = TouchIntentTracker();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _intentTracker.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _intentTracker.classify(event) != TouchIntent.ambiguous) {
      _intentTracker.removePointer(event.pointer);
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _intentTracker.removePointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _intentTracker.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

final class BonsaiDoubleTapGestureRecognizer
    extends DoubleTapGestureRecognizer {
  BonsaiDoubleTapGestureRecognizer({super.debugOwner, super.supportedDevices});

  final TouchIntentTracker _intentTracker = TouchIntentTracker();
  final Map<int, PointerRoute> _intentRoutes = <int, PointerRoute>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _intentTracker.addPointer(event);
    super.addAllowedPointer(event);
    void route(PointerEvent routedEvent) => _handleIntentEvent(routedEvent);
    _intentRoutes[event.pointer] = route;
    GestureBinding.instance.pointerRouter.addRoute(
      event.pointer,
      route,
      event.transform,
    );
  }

  void _handleIntentEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _intentTracker.classify(event) != TouchIntent.ambiguous) {
      rejectGesture(event.pointer);
      _stopIntentTracking(event.pointer);
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _stopIntentTracking(event.pointer);
    }
  }

  void _stopIntentTracking(int pointer) {
    final route = _intentRoutes.remove(pointer);
    if (route != null) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, route);
    }
    _intentTracker.removePointer(pointer);
  }

  @override
  void dispose() {
    for (final entry in _intentRoutes.entries.toList(growable: false)) {
      GestureBinding.instance.pointerRouter.removeRoute(entry.key, entry.value);
    }
    _intentRoutes.clear();
    _intentTracker.clear();
    super.dispose();
  }
}

final class BonsaiLongPressGestureRecognizer
    extends LongPressGestureRecognizer {
  BonsaiLongPressGestureRecognizer({super.debugOwner, super.supportedDevices});

  final TouchIntentTracker _intentTracker = TouchIntentTracker();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _intentTracker.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _intentTracker.classify(event) != TouchIntent.ambiguous) {
      _intentTracker.removePointer(event.pointer);
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _intentTracker.removePointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _intentTracker.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

final class BonsaiHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  BonsaiHorizontalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
  });

  final TouchIntentTracker _intentTracker = TouchIntentTracker();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _intentTracker.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _intentTracker.classify(event) == TouchIntent.vertical) {
      _intentTracker.removePointer(event.pointer);
      rejectGesture(event.pointer);
      return;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _intentTracker.removePointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _intentTracker.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

final class BonsaiVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  BonsaiVerticalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
  });

  final TouchIntentTracker _intentTracker = TouchIntentTracker();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _intentTracker.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent &&
        _intentTracker.classify(event) == TouchIntent.horizontal) {
      _intentTracker.removePointer(event.pointer);
      rejectGesture(event.pointer);
      return;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _intentTracker.removePointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _intentTracker.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

final class BonsaiGestureDetector extends StatelessWidget {
  const BonsaiGestureDetector({
    required this.child,
    this.behavior,
    this.excludeFromSemantics = false,
    this.supportedDevices,
    this.dragStartBehavior = DragStartBehavior.start,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onTap,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.onDoubleTapCancel,
    this.onLongPress,
    this.onHorizontalDragDown,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
    this.onVerticalDragDown,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    super.key,
  });

  final Widget child;
  final HitTestBehavior? behavior;
  final bool excludeFromSemantics;
  final Set<PointerDeviceKind>? supportedDevices;
  final DragStartBehavior dragStartBehavior;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onDoubleTapDown;
  final GestureDoubleTapCallback? onDoubleTap;
  final GestureTapCancelCallback? onDoubleTapCancel;
  final GestureLongPressCallback? onLongPress;
  final GestureDragDownCallback? onHorizontalDragDown;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  final GestureDragDownCallback? onVerticalDragDown;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: behavior,
    excludeFromSemantics: excludeFromSemantics,
    gestures: <Type, GestureRecognizerFactory>{
      if (onTapDown != null ||
          onTapUp != null ||
          onTapCancel != null ||
          onTap != null)
        BonsaiTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<BonsaiTapGestureRecognizer>(
              () => BonsaiTapGestureRecognizer(
                debugOwner: this,
                supportedDevices: supportedDevices,
              ),
              (recognizer) => recognizer
                ..onTapDown = onTapDown
                ..onTapUp = onTapUp
                ..onTapCancel = onTapCancel
                ..onTap = onTap,
            ),
      if (onDoubleTapDown != null ||
          onDoubleTap != null ||
          onDoubleTapCancel != null)
        BonsaiDoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              BonsaiDoubleTapGestureRecognizer
            >(
              () => BonsaiDoubleTapGestureRecognizer(
                debugOwner: this,
                supportedDevices: supportedDevices,
              ),
              (recognizer) => recognizer
                ..onDoubleTapDown = onDoubleTapDown
                ..onDoubleTap = onDoubleTap
                ..onDoubleTapCancel = onDoubleTapCancel,
            ),
      if (onLongPress != null)
        BonsaiLongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              BonsaiLongPressGestureRecognizer
            >(
              () => BonsaiLongPressGestureRecognizer(
                debugOwner: this,
                supportedDevices: supportedDevices,
              ),
              (recognizer) => recognizer..onLongPress = onLongPress,
            ),
      if (onHorizontalDragDown != null ||
          onHorizontalDragStart != null ||
          onHorizontalDragUpdate != null ||
          onHorizontalDragEnd != null ||
          onHorizontalDragCancel != null)
        BonsaiHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              BonsaiHorizontalDragGestureRecognizer
            >(
              () => BonsaiHorizontalDragGestureRecognizer(
                debugOwner: this,
                supportedDevices: supportedDevices,
              ),
              (recognizer) => recognizer
                ..dragStartBehavior = dragStartBehavior
                ..onDown = onHorizontalDragDown
                ..onStart = onHorizontalDragStart
                ..onUpdate = onHorizontalDragUpdate
                ..onEnd = onHorizontalDragEnd
                ..onCancel = onHorizontalDragCancel,
            ),
      if (onVerticalDragDown != null ||
          onVerticalDragStart != null ||
          onVerticalDragUpdate != null ||
          onVerticalDragEnd != null ||
          onVerticalDragCancel != null)
        BonsaiVerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              BonsaiVerticalDragGestureRecognizer
            >(
              () => BonsaiVerticalDragGestureRecognizer(
                debugOwner: this,
                supportedDevices: supportedDevices,
              ),
              (recognizer) => recognizer
                ..dragStartBehavior = dragStartBehavior
                ..onDown = onVerticalDragDown
                ..onStart = onVerticalDragStart
                ..onUpdate = onVerticalDragUpdate
                ..onEnd = onVerticalDragEnd
                ..onCancel = onVerticalDragCancel,
            ),
    },
    child: child,
  );
}
