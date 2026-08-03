import 'package:flutter/widgets.dart';

final class SparseExtentTransitionScope extends InheritedWidget {
  const SparseExtentTransitionScope({
    required this.progress,
    required this.expanded,
    required this.compactExtent,
    required this.expandedExtent,
    required super.child,
    super.key,
  });

  final double progress;
  final bool expanded;
  final double compactExtent;
  final double expandedExtent;

  static SparseExtentTransitionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SparseExtentTransitionScope>();

  @override
  bool updateShouldNotify(SparseExtentTransitionScope oldWidget) =>
      oldWidget.progress != progress ||
      oldWidget.expanded != expanded ||
      oldWidget.compactExtent != compactExtent ||
      oldWidget.expandedExtent != expandedExtent;
}
