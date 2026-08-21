import 'package:flutter/gestures.dart';

enum TouchIntent { ambiguous, horizontal, vertical }

final class TouchIntentTracker {
  static const double intentDistance = 6;
  static const double axisDominanceRatio = 1.5;

  final Map<int, Offset> _touchDownPositions = <int, Offset>{};

  void addPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchDownPositions[event.pointer] = event.position;
    }
  }

  TouchIntent classify(PointerMoveEvent event) {
    final downPosition = _touchDownPositions[event.pointer];
    if (downPosition == null) return TouchIntent.ambiguous;

    final displacement = event.position - downPosition;
    final dx = displacement.dx.abs();
    final dy = displacement.dy.abs();
    if (dx >= intentDistance && dx >= axisDominanceRatio * dy) {
      return TouchIntent.horizontal;
    }
    if (dy >= intentDistance && dy >= axisDominanceRatio * dx) {
      return TouchIntent.vertical;
    }
    return TouchIntent.ambiguous;
  }

  void removePointer(int pointer) => _touchDownPositions.remove(pointer);

  void clear() => _touchDownPositions.clear();
}
