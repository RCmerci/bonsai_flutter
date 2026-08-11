import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';

import '../protocol/event_batch.dart';
import '../protocol/frame.dart';
import '../renderer/renderer_event.dart';
import 'modal_bottom_sheet_route.dart';

final class NavigationEntry {
  const NavigationEntry({required this.props, required this.child});

  final PageProps props;
  final Widget child;
}

final class BonsaiStandardPage extends Page<void> {
  const BonsaiStandardPage({
    required this.child,
    required this.transition,
    super.key,
    super.name,
    super.restorationId,
    super.canPop,
  });

  final Widget child;
  final PageTransition transition;

  @override
  Route<void> createRoute(BuildContext context) => switch (transition) {
    PageTransition.none ||
    PageTransition.fade => BonsaiStandardPageRoute(page: this),
    PageTransition.slide => throw StateError(
      'Slide pages must use CupertinoPage',
    ),
  };
}

final class BonsaiStandardPageRoute extends PageRouteBuilder<void> {
  BonsaiStandardPageRoute({required BonsaiStandardPage page})
    : super(
        settings: page,
        pageBuilder: (_, _, _) => page.child,
        transitionsBuilder: page.transition == PageTransition.fade
            ? (_, animation, _, routeChild) =>
                  FadeTransition(opacity: animation, child: routeChild)
            : (_, _, _, routeChild) => routeChild,
        transitionDuration: page.transition == PageTransition.none
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: page.transition == PageTransition.none
            ? Duration.zero
            : const Duration(milliseconds: 300),
      );

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      (nextRoute is ModalRoute<void> &&
          nextRoute.delegatedTransition != null) ||
      super.canTransitionTo(nextRoute);
}

final class NavigationHost extends StatefulWidget {
  const NavigationHost({
    required this.restorationScopeId,
    required this.pages,
    required this.nodeId,
    required this.binding,
    required this.onEvent,
    super.key,
  });

  final String? restorationScopeId;
  final List<NavigationEntry> pages;
  final int nodeId;
  final EventBinding? binding;
  final RendererEventCallback? onEvent;

  @override
  State<NavigationHost> createState() => NavigationHostState();
}

final class NavigationHostState extends State<NavigationHost> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
    child: Navigator(
      key: _navigatorKey,
      restorationScopeId: widget.restorationScopeId,
      pages: [
        for (final page in widget.pages)
          switch (page.props.presentation) {
            StandardPagePresentation(transition: PageTransition.slide) =>
              cupertino.CupertinoPage<void>(
                key: ValueKey<String>(page.props.pageKey),
                name: page.props.pageKey,
                restorationId: page.props.restorationId,
                canPop: page.props.canPop,
                child: page.child,
              ),
            StandardPagePresentation(:final transition) => BonsaiStandardPage(
              key: ValueKey<String>(page.props.pageKey),
              name: page.props.pageKey,
              restorationId: page.props.restorationId,
              canPop: page.props.canPop,
              transition: transition,
              child: page.child,
            ),
            final ModalBottomSheetPresentation presentation =>
              BonsaiModalBottomSheetPage(
                key: ValueKey<String>(page.props.pageKey),
                name: page.props.pageKey,
                restorationId: page.props.restorationId,
                canPop: page.props.canPop,
                presentation: presentation,
                child: page.child,
              ),
          },
      ],
      onDidRemovePage: (page) {
        final binding = widget.binding;
        final onEvent = widget.onEvent;
        if (binding == null || onEvent == null) return;
        onEvent(
          RendererEvent(
            nodeId: widget.nodeId,
            eventTag: binding.eventTag,
            handlerId: binding.handlerId,
            payload: RoutePopEventPayload(pageKey: page.name!, result: null),
          ),
        );
      },
    ),
  );
}
