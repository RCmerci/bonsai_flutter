import 'package:material_ui/material_ui.dart';

const double _settledScale = 0.92;
const Offset _settledOffset = Offset(0, -0.03);
const double _settledTopRadius = 16;

Widget? buildModalSheetBackgroundTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) {
  if (child == null || secondaryAnimation.isDismissed) return child;

  final progress = secondaryAnimation.drive(
    CurveTween(curve: Curves.easeInOut),
  );
  return AnimatedBuilder(
    animation: progress,
    child: child,
    builder: (context, transitionChild) => FractionalTranslation(
      translation: Offset.lerp(Offset.zero, _settledOffset, progress.value)!,
      transformHitTests: false,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_settledTopRadius * progress.value),
        ),
        child: Transform.scale(
          scale: 1 + (_settledScale - 1) * progress.value,
          alignment: Alignment.topCenter,
          transformHitTests: false,
          child: transitionChild,
        ),
      ),
    ),
  );
}
