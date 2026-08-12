import 'package:flutter/material.dart';

import '../protocol/frame.dart';
import 'detented_modal_sheet_host.dart';
import 'modal_sheet_background_transition.dart';
import 'modal_sheet_keyboard_coordinator.dart';

const _modalSheetBorderRadius = BorderRadius.vertical(top: Radius.circular(24));

Widget _buildModalSheetSurface(BuildContext context, Widget child) => Material(
  color: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(borderRadius: _modalSheetBorderRadius),
  clipBehavior: Clip.antiAlias,
  child: child,
);

final class BonsaiModalBottomSheetPage extends Page<void> {
  const BonsaiModalBottomSheetPage({
    required this.child,
    required this.presentation,
    super.key,
    super.name,
    super.restorationId,
    super.canPop,
  });

  final Widget child;
  final ModalBottomSheetPresentation presentation;

  @override
  Route<void> createRoute(BuildContext context) => BonsaiModalBottomSheetRoute(
    page: this,
    defaultBarrierLabel: MaterialLocalizations.of(context).scrimLabel,
  );
}

final class BonsaiModalBottomSheetRoute extends ModalBottomSheetRoute<void> {
  BonsaiModalBottomSheetRoute({
    required BonsaiModalBottomSheetPage page,
    required String defaultBarrierLabel,
  }) : _defaultBarrierLabel = defaultBarrierLabel,
       super(
         settings: page,
         builder: (_) => page.child,
         barrierLabel: page.presentation.barrierLabel ?? defaultBarrierLabel,
         modalBarrierColor: page.presentation.barrierColorArgb == null
             ? null
             : Color(page.presentation.barrierColorArgb!),
         isDismissible: page.presentation.barrierDismissible,
         isScrollControlled:
             page.presentation.sizing is! ContentBoundedModalSheetSizing,
         useSafeArea: page.presentation.useSafeArea,
         requestFocus: page.presentation.requestFocus,
         enableDrag: false,
         showDragHandle: false,
         backgroundColor: Colors.transparent,
         elevation: 0,
         sheetAnimationStyle: AnimationStyle(
           duration: Duration(
             milliseconds: page.presentation.transitionDurationMilliseconds,
           ),
           reverseDuration: Duration(
             milliseconds:
                 page.presentation.reverseTransitionDurationMilliseconds,
           ),
         ),
       );

  final String _defaultBarrierLabel;
  final ValueNotifier<bool> _routeIsCurrent = ValueNotifier(false);

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _buildBackgroundTransition;

  Widget? _buildBackgroundTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => buildModalSheetBackgroundTransition(
    context,
    animation,
    secondaryAnimation,
    allowSnapshotting,
    child,
  );

  BonsaiModalBottomSheetPage get _page =>
      settings as BonsaiModalBottomSheetPage;
  ModalBottomSheetPresentation get _presentation => _page.presentation;

  bool get _reducedMotion {
    final context = navigator?.context;
    if (context == null) return false;
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  @override
  WidgetBuilder get builder => (context) {
    final sizing = _presentation.sizing;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final usesFixedLargeShell = sizing is ScrollControlledModalSheetSizing;
    Widget child = _page.child;
    if (sizing is DetentedModalSheetSizing) {
      bool canDismiss() => sizing.dismissOnDrag && _page.canPop;
      final pageChild = child;
      child = BottomSheet(
        onClosing: () {},
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (_) => DetentedModalSheetHost(
          sizing: sizing,
          canDismiss: canDismiss,
          requestDismiss: () async {
            if (!canDismiss()) return false;
            return navigator?.maybePop() ?? false;
          },
          reducedMotion: _reducedMotion,
          child: pageChild,
        ),
      );
    }
    if (usesFixedLargeShell) {
      child = ModalSheetFixedKeyboardViewport(child: child);
    }
    child = _buildModalSheetSurface(context, child);
    if (usesFixedLargeShell) {
      child = SizedBox.expand(child: child);
    } else {
      child = ModalSheetKeyboardInsetHost(
        backgroundColor: surfaceColor,
        child: child,
      );
    }
    return ModalSheetAutomaticFocusCoordinator(
      routeAnimation: animation!,
      routeIsCurrent: _routeIsCurrent,
      requestFocus: requestFocus,
      activateImmediately: transitionDuration == Duration.zero,
      child: child,
    );
  };

  @override
  TickerFuture didPush() {
    _routeIsCurrent.value = true;
    return super.didPush();
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    _routeIsCurrent.value = nextRoute == null;
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    super.didPopNext(nextRoute);
    _routeIsCurrent.value = true;
  }

  @override
  bool didPop(void result) {
    _routeIsCurrent.value = false;
    return super.didPop(result);
  }

  @override
  void dispose() {
    _routeIsCurrent.dispose();
    super.dispose();
  }

  @override
  bool get barrierDismissible => _presentation.barrierDismissible;

  @override
  Color get barrierColor => _presentation.barrierColorArgb == null
      ? Colors.black54
      : Color(_presentation.barrierColorArgb!);

  @override
  String get barrierLabel => _presentation.barrierLabel ?? _defaultBarrierLabel;

  @override
  bool get isScrollControlled =>
      _presentation.sizing is! ContentBoundedModalSheetSizing;

  @override
  bool get useSafeArea => _presentation.useSafeArea;

  @override
  bool get requestFocus => _presentation.requestFocus;

  @override
  bool get enableDrag => false;

  @override
  bool get showDragHandle => false;

  @override
  AnimationStyle get sheetAnimationStyle => _reducedMotion
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: Duration(
            milliseconds: _presentation.transitionDurationMilliseconds,
          ),
          reverseDuration: Duration(
            milliseconds: _presentation.reverseTransitionDurationMilliseconds,
          ),
        );

  @override
  Duration get transitionDuration => _reducedMotion
      ? Duration.zero
      : Duration(milliseconds: _presentation.transitionDurationMilliseconds);

  @override
  Duration get reverseTransitionDuration => _reducedMotion
      ? Duration.zero
      : Duration(
          milliseconds: _presentation.reverseTransitionDurationMilliseconds,
        );

  @override
  void changedInternalState() {
    super.changedInternalState();
    _synchronizeAnimationDurations();
  }

  @override
  void changedExternalState() {
    super.changedExternalState();
    _synchronizeAnimationDurations();
  }

  void _synchronizeAnimationDurations() {
    controller
      ?..duration = transitionDuration
      ..reverseDuration = reverseTransitionDuration;
  }
}
