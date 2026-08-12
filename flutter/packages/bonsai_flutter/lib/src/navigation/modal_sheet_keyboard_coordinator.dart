import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Internal presentation policy for automatic text-input focus.
///
/// The scope intentionally does not affect whether descendants can receive an
/// explicit focus request.
final class ModalSheetAutomaticFocusScope extends InheritedWidget {
  const ModalSheetAutomaticFocusScope({
    required this.ready,
    required super.child,
    super.key,
  });

  final bool ready;

  static bool isReady(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ModalSheetAutomaticFocusScope>()
          ?.ready ??
      true;

  @override
  bool updateShouldNotify(ModalSheetAutomaticFocusScope oldWidget) =>
      ready != oldWidget.ready;
}

/// Applies the engine-provided keyboard inset exactly once around the sheet.
final class ModalSheetKeyboardInsetHost extends StatelessWidget {
  const ModalSheetKeyboardInsetHost({
    required this.backgroundColor,
    required this.child,
    super.key,
  });

  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned(
          right: 0,
          bottom: 0,
          left: 0,
          height: bottomInset,
          child: ColoredBox(color: backgroundColor),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Keeps a fixed sheet shell while resizing only its content for the keyboard.
final class ModalSheetFixedKeyboardViewport extends StatelessWidget {
  const ModalSheetFixedKeyboardViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

/// Stages automatic focus until its route has completed entering.
final class ModalSheetAutomaticFocusCoordinator extends StatefulWidget {
  const ModalSheetAutomaticFocusCoordinator({
    required this.routeAnimation,
    required this.routeIsCurrent,
    required this.requestFocus,
    required this.activateImmediately,
    required this.child,
    super.key,
  });

  final Animation<double> routeAnimation;
  final ValueListenable<bool> routeIsCurrent;
  final bool requestFocus;
  final bool activateImmediately;
  final Widget child;

  @override
  State<ModalSheetAutomaticFocusCoordinator> createState() =>
      _ModalSheetAutomaticFocusCoordinatorState();
}

final class _ModalSheetAutomaticFocusCoordinatorState
    extends State<ModalSheetAutomaticFocusCoordinator> {
  bool _keyboardAlreadyVisible = false;
  bool _pendingActivationCancelled = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.routeAnimation.addStatusListener(_handleRouteStatus);
    widget.routeIsCurrent.addListener(_handleRouteCurrentChanged);
    _synchronizeReadiness(notify: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardAlreadyVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    _synchronizeReadiness(notify: false);
  }

  @override
  void didUpdateWidget(ModalSheetAutomaticFocusCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.routeAnimation, widget.routeAnimation)) {
      oldWidget.routeAnimation.removeStatusListener(_handleRouteStatus);
      widget.routeAnimation.addStatusListener(_handleRouteStatus);
    }
    if (!identical(oldWidget.routeIsCurrent, widget.routeIsCurrent)) {
      oldWidget.routeIsCurrent.removeListener(_handleRouteCurrentChanged);
      widget.routeIsCurrent.addListener(_handleRouteCurrentChanged);
    }
    if (!oldWidget.requestFocus && widget.requestFocus) {
      _pendingActivationCancelled = false;
    }
    _synchronizeReadiness(notify: false);
  }

  @override
  void dispose() {
    widget.routeAnimation.removeStatusListener(_handleRouteStatus);
    widget.routeIsCurrent.removeListener(_handleRouteCurrentChanged);
    super.dispose();
  }

  void _handleRouteStatus(AnimationStatus status) => _synchronizeReadiness();

  void _handleRouteCurrentChanged() {
    if (!_ready &&
        widget.requestFocus &&
        !widget.routeIsCurrent.value &&
        widget.routeAnimation.status != AnimationStatus.completed) {
      _pendingActivationCancelled = true;
    }
    _synchronizeReadiness();
  }

  void _synchronizeReadiness({bool notify = true}) {
    final nextReady = switch ((
      widget.requestFocus,
      _pendingActivationCancelled,
      widget.routeIsCurrent.value,
    )) {
      (false, _, _) || (_, true, _) || (_, _, false) => false,
      _ =>
        widget.activateImmediately ||
            _keyboardAlreadyVisible ||
            widget.routeAnimation.status == AnimationStatus.completed,
    };
    if (_ready == nextReady) return;
    if (notify) {
      setState(() => _ready = nextReady);
    } else {
      _ready = nextReady;
    }
  }

  @override
  Widget build(BuildContext context) =>
      ModalSheetAutomaticFocusScope(ready: _ready, child: widget.child);
}
