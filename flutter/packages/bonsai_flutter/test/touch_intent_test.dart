import 'package:bonsai_flutter/src/gesture/bonsai_gesture_detector.dart';
import 'package:bonsai_flutter/src/gesture/touch_intent.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TouchIntentTracker', () {
    test('classifies both equality boundaries', () {
      final tracker = TouchIntentTracker();

      tracker.addPointer(_down(pointer: 1));
      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(6, 4))),
        TouchIntent.horizontal,
      );

      tracker.addPointer(_down(pointer: 2));
      expect(
        tracker.classify(_move(pointer: 2, position: const Offset(4, 6))),
        TouchIntent.vertical,
      );
    });

    test('uses cumulative displacement across move samples', () {
      final tracker = TouchIntentTracker()..addPointer(_down(pointer: 1));

      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(2, 3))),
        TouchIntent.ambiguous,
      );
      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(4, 6))),
        TouchIntent.vertical,
      );
    });

    test('keeps sub-threshold and near-diagonal movement ambiguous', () {
      final tracker = TouchIntentTracker()..addPointer(_down(pointer: 1));

      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(5.999, 0))),
        TouchIntent.ambiguous,
      );
      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(6, 4.1))),
        TouchIntent.ambiguous,
      );
    });

    test('allows reversal before a decision', () {
      final tracker = TouchIntentTracker()..addPointer(_down(pointer: 1));

      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(5, 0))),
        TouchIntent.ambiguous,
      );
      expect(
        tracker.classify(_move(pointer: 1, position: const Offset(0, 6))),
        TouchIntent.vertical,
      );
    });

    for (final kind in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.unknown,
    ]) {
      test('does not classify $kind movement', () {
        final tracker = TouchIntentTracker()
          ..addPointer(_down(pointer: 1, kind: kind));

        expect(
          tracker.classify(
            _move(pointer: 1, position: const Offset(0, 100), kind: kind),
          ),
          TouchIntent.ambiguous,
        );
      });
    }
  });

  group('BonsaiGestureDetector', () {
    testWidgets('cancels a tap at decisive vertical touch intent', (
      tester,
    ) async {
      var taps = 0;
      await _pumpDetector(tester, onTap: () => taps += 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(4, -6));
      await gesture.up();
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('keeps a near-diagonal touch eligible to tap', (tester) async {
      var taps = 0;
      await _pumpDetector(tester, onTap: () => taps += 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.touch,
      );

      await gesture.moveBy(const Offset(4.1, -6));
      await gesture.up();
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('cancels a double tap after decisive second-tap movement', (
      tester,
    ) async {
      var doubleTaps = 0;
      await _pumpDetector(tester, onDoubleTap: () => doubleTaps += 1);
      final center = tester.getCenter(find.text('Target'));
      final firstTap = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      await firstTap.up();
      await tester.pump(const Duration(milliseconds: 50));
      final secondTap = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );

      await secondTap.moveBy(const Offset(6, 0));
      await secondTap.up();
      await tester.pump(const Duration(milliseconds: 50));

      expect(doubleTaps, 0);
    });

    testWidgets('cancels a long press at decisive horizontal touch intent', (
      tester,
    ) async {
      var longPresses = 0;
      await _pumpDetector(tester, onLongPress: () => longPresses += 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.touch,
      );

      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(longPresses, 0);
      await gesture.up();
    });

    testWidgets('retains non-touch tap behavior', (tester) async {
      var taps = 0;
      await _pumpDetector(tester, onTap: () => taps += 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.stylus,
      );

      await gesture.moveBy(const Offset(4, -6));
      await gesture.up();
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('horizontal drag rejects decisive vertical touch intent', (
      tester,
    ) async {
      var starts = 0;
      var cancels = 0;
      await _pumpDetector(
        tester,
        onHorizontalDragStart: (_) => starts += 1,
        onHorizontalDragCancel: () => cancels += 1,
        onVerticalDragStart: (_) {},
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.touch,
      );
      expect(starts, 0);

      await gesture.moveBy(const Offset(4, -6));
      await tester.pump();

      expect(starts, 0);
      expect(cancels, 1);
      await gesture.up();
    });

    testWidgets('vertical drag rejects decisive horizontal touch intent', (
      tester,
    ) async {
      var starts = 0;
      var cancels = 0;
      await _pumpDetector(
        tester,
        onHorizontalDragStart: (_) {},
        onVerticalDragStart: (_) => starts += 1,
        onVerticalDragCancel: () => cancels += 1,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Target')),
        kind: PointerDeviceKind.touch,
      );
      expect(starts, 0);

      await gesture.moveBy(const Offset(6, 4));
      await tester.pump();

      expect(starts, 0);
      expect(cancels, 1);
      await gesture.up();
    });
  });
}

PointerDownEvent _down({
  required int pointer,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => PointerDownEvent(pointer: pointer, position: Offset.zero, kind: kind);

PointerMoveEvent _move({
  required int pointer,
  required Offset position,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => PointerMoveEvent(pointer: pointer, position: position, kind: kind);

Future<void> _pumpDetector(
  WidgetTester tester, {
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  VoidCallback? onLongPress,
  GestureDragStartCallback? onHorizontalDragStart,
  GestureDragCancelCallback? onHorizontalDragCancel,
  GestureDragStartCallback? onVerticalDragStart,
  GestureDragCancelCallback? onVerticalDragCancel,
}) {
  final detector = Center(
    child: BonsaiGestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onHorizontalDragStart: onHorizontalDragStart,
      onHorizontalDragCancel: onHorizontalDragCancel,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragCancel: onVerticalDragCancel,
      child: const SizedBox(
        width: 200,
        height: 100,
        child: Center(child: Text('Target')),
      ),
    ),
  );
  return tester.pumpWidget(MaterialApp(home: detector));
}
