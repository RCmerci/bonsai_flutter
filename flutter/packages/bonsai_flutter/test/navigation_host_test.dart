import 'dart:ui' show ImageByteFormat, PointerDeviceKind, SemanticsAction;

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/navigation/modal_bottom_sheet_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('declarative pages emit typed system-pop requests', (
    tester,
  ) async {
    final store = NodeStore()..apply(_navigationSnapshot());
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(),
          onEvent: events.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Overlay content'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await tester.pumpAndSettle();

    expect(events, hasLength(1));
    expect(events.single.eventTag, EventTagId.routePop);
    expect(
      events.single.payload,
      const RoutePopEventPayload(pageKey: 'settings', result: null),
    );
  });

  group('Slide navigation', () {
    testWidgets(
      'enters with front-loaded monotonic motion and inbox parallax',
      (tester) async {
        final fixture = await _pumpSlideFixture(tester);

        fixture.pushDetail();
        await tester.pump();
        final start = _pageLeadingEdge(tester, 'Detail');
        final inboxStart = _pageLeadingEdge(tester, 'Inbox');

        await tester.pump(const Duration(milliseconds: 125));
        final quarter = _pageLeadingEdge(tester, 'Detail');
        final inboxQuarter = _pageLeadingEdge(tester, 'Inbox');
        await tester.pump(const Duration(milliseconds: 125));
        final halfway = _pageLeadingEdge(tester, 'Detail');
        await tester.pump(const Duration(milliseconds: 125));
        final threeQuarters = _pageLeadingEdge(tester, 'Detail');
        await tester.pump(const Duration(milliseconds: 125));
        final end = _pageLeadingEdge(tester, 'Detail');

        final width =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        final progressAtQuarter = (width - quarter) / width;
        final progressAtHalfway = (width - halfway) / width;
        final firstQuarterDistance = start - quarter;
        final lastQuarterDistance = threeQuarters - end;

        expect(start, closeTo(width, 1 / tester.view.devicePixelRatio));
        expect(end, closeTo(0, 1 / tester.view.devicePixelRatio));
        expect(
          [start, quarter, halfway, threeQuarters, end],
          orderedEquals(
            [start, quarter, halfway, threeQuarters, end]
              ..sort((a, b) => b.compareTo(a)),
          ),
        );
        expect(progressAtQuarter, greaterThan(0.25));
        expect(progressAtHalfway, greaterThan(0.5));
        expect(firstQuarterDistance, greaterThan(lastQuarterDistance));
        expect(inboxStart, closeTo(0, 1));
        expect(inboxQuarter, lessThan(0));
        expect(inboxQuarter.abs(), lessThan(quarter.abs()));
        expect(find.text('Inbox', skipOffstage: false), findsOneWidget);
      },
    );

    testWidgets('leading-edge drag tracks the finger and can cancel', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(96, 0));
      await tester.pump();

      expect(navigator.userGestureInProgress, isTrue);
      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(96, 2));

      await gesture.up();
      expect(navigator.userGestureInProgress, isTrue);
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('distance edge-pop commit emits one typed detail key', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(260, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(fixture.events.single.eventTag, EventTagId.routePop);
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detail', result: null),
      );
    });

    testWidgets('qualifying leading-edge fling commits exactly once', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      await tester.flingFrom(const Offset(5, 120), const Offset(80, 0), 1200);
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detail', result: null),
      );
    });

    testWidgets('edge-pop guards reject invalid starts and route states', (
      tester,
    ) async {
      final rootOnly = await _pumpSlideFixture(tester, pushable: false);
      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(rootOnly.events, isEmpty);

      final fixture = await _pumpSlideFixture(tester, canPop: false);
      fixture.pushDetail();
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.dragFrom(const Offset(180, 120), const Offset(180, 0));
      await tester.dragFrom(const Offset(5, 120), const Offset(-180, 0));
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('edge-pop cannot begin while the push is transitioning', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester);
      fixture.pushDetail();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.dragFrom(const Offset(5, 120), const Offset(260, 0));
      await tester.pumpAndSettle();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(0, 1));
      expect(fixture.events, isEmpty);
    });

    testWidgets('RTL mirrors the physical leading edge and direction', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(
        tester,
        textDirection: TextDirection.rtl,
      );
      fixture.pushDetail();
      await tester.pumpAndSettle();
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      final gesture = await tester.startGesture(Offset(width - 5, 120));
      await gesture.moveBy(const Offset(-96, 0));
      await tester.pump();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(-96, 2));
      await gesture.moveBy(const Offset(-180, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.events, hasLength(1));
    });

    testWidgets('reduced motion preserves direct interactive tracking', (
      tester,
    ) async {
      final fixture = await _pumpSlideFixture(tester, disableAnimations: true);
      fixture.pushDetail();
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(5, 120));
      await gesture.moveBy(const Offset(72, 0));
      await tester.pump();

      expect(_pageLeadingEdge(tester, 'Detail'), closeTo(72, 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.events, isEmpty);
    });
  });

  group('Modal bottom sheet navigation', () {
    for (final (name, sizing, brightness)
        in <(String, ModalBottomSheetSizing, Brightness)>[
          (
            'content-bounded',
            const ContentBoundedModalSheetSizing(),
            Brightness.light,
          ),
          (
            'scroll-controlled',
            const ScrollControlledModalSheetSizing(),
            Brightness.dark,
          ),
        ]) {
      testWidgets('$name sheet owns a rounded clipped surface', (tester) async {
        await _pumpModalFixture(tester, sizing: sizing, brightness: brightness);

        _expectRoundedModalSheetSurface(tester, childText: 'Modal editor');
      });
    }

    testWidgets('detented sheet clips an opaque child to the rounded surface', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester, brightness: Brightness.dark);

      _expectRoundedModalSheetSurface(tester, childText: 'Detented editor');
    });

    for (final (transition, direction, brightness, size) in [
      (
        PageTransition.none,
        TextDirection.ltr,
        Brightness.light,
        const Size(400, 300),
      ),
      (
        PageTransition.fade,
        TextDirection.ltr,
        Brightness.dark,
        const Size(400, 300),
      ),
      (
        PageTransition.slide,
        TextDirection.rtl,
        Brightness.light,
        const Size(400, 300),
      ),
      (
        PageTransition.none,
        TextDirection.rtl,
        Brightness.dark,
        const Size(400, 220),
      ),
    ]) {
      testWidgets('modal entrance recedes the same mounted lower page for '
          '$transition $direction $brightness $size', (tester) async {
        final fixture = await _pumpModalFixture(
          tester,
          startWithModal: false,
          lowerTransition: transition,
          direction: direction,
          brightness: brightness,
          size: size,
        );
        final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
        final lowerElement = tester.element(lowerFinder);
        final originalRect = tester.getRect(lowerFinder);

        fixture.pushModal();
        await tester.pumpAndSettle();

        final settledRect = tester.getRect(lowerFinder);
        final modalRoute = ModalRoute.of(
          tester.element(find.text('Modal editor')),
        );
        expect(tester.element(lowerFinder), same(lowerElement));
        expect(lowerElement.mounted, isTrue);
        expect(settledRect.width, closeTo(originalRect.width * 0.92, 1));
        expect(
          settledRect.top,
          closeTo(originalRect.top - originalRect.height * 0.03, 1),
        );
        expect(settledRect.overlaps(Offset.zero & size), isTrue);
        expect(modalRoute, isA<ModalBottomSheetRoute<void>>());
      });
    }

    testWidgets('modal and lower route share entrance progress', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        startWithModal: false,
        transitionDurationMilliseconds: 400,
      );
      final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
      final lowerStart = tester.getRect(lowerFinder);

      fixture.pushModal();
      await tester.pump();
      final sheetStart = tester.getRect(find.byType(BottomSheet));
      await tester.pump(const Duration(milliseconds: 100));
      final lowerMid = tester.getRect(lowerFinder);
      final sheetMid = tester.getRect(find.byType(BottomSheet));
      await tester.pumpAndSettle();
      final lowerEnd = tester.getRect(lowerFinder);
      final sheetEnd = tester.getRect(find.byType(BottomSheet));

      expect(
        lowerMid.width,
        inExclusiveRange(lowerEnd.width, lowerStart.width),
      );
      expect(lowerMid.top, inExclusiveRange(lowerEnd.top, lowerStart.top));
      expect(sheetMid.top, inExclusiveRange(sheetEnd.top, sheetStart.top));
    });

    testWidgets('modal exit restores lower geometry and emits one pop', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, startWithModal: false);
      final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
      final lowerElement = tester.element(lowerFinder);
      final originalRect = tester.getRect(lowerFinder);

      fixture.pushModal();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(lowerFinder).width,
        closeTo(originalRect.width * 0.92, 1),
      );
      await tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .maybePop();
      await tester.pumpAndSettle();

      expect(tester.getRect(lowerFinder), originalRect);
      expect(tester.element(lowerFinder), same(lowerElement));
      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'editor', result: null),
      );
    });

    testWidgets('reduced motion skips intermediate lower-route movement', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _pumpModalFixture(
        tester,
        startWithModal: false,
        disableAnimations: true,
      );
      final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
      final originalRect = tester.getRect(lowerFinder);

      fixture.pushModal();
      await tester.pump();

      final presentedRect = tester.getRect(lowerFinder);
      expect(presentedRect.width, closeTo(originalRect.width * 0.92, 1));
      expect(
        presentedRect.top,
        closeTo(originalRect.top - originalRect.height * 0.03, 1),
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
      expect(find.text('Modal editor'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Modal editor')),
        matchesSemantics(label: 'Modal editor'),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Lower action')).owner,
        isNull,
      );
      semantics.dispose();
    });

    testWidgets('standard page does not recede the lower route', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, startWithModal: false);
      final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
      final originalRect = tester.getRect(lowerFinder);

      fixture.pushModal();
      await tester.pumpAndSettle();
      expect(
        tester.getRect(lowerFinder).width,
        closeTo(originalRect.width * 0.92, 1),
      );
      await tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .maybePop();
      await tester.pumpAndSettle();
      fixture.removeModal();
      await tester.pump();

      fixture.pushStandardPage();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(lowerFinder), originalRect);
      await tester.pumpAndSettle();
      expect(tester.getRect(lowerFinder), originalRect);
      expect(find.text('Standard detail'), findsOneWidget);
    });

    testWidgets('stacked modals transform only the immediate lower route', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        startWithModal: false,
        secondModal: true,
      );
      final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
      final lowerElement = tester.element(lowerFinder);

      fixture.pushModal();
      await tester.pumpAndSettle();
      final lowerWithFirstModal = tester.getRect(lowerFinder);
      final firstModalFinder = find.text('Modal editor', skipOffstage: false);
      final firstModalElement = tester.element(firstModalFinder);
      final firstModalBefore = tester.getRect(firstModalFinder);

      fixture.pushSecondModal();
      await tester.pumpAndSettle();

      expect(tester.getRect(lowerFinder), lowerWithFirstModal);
      expect(tester.element(lowerFinder), same(lowerElement));
      expect(tester.element(firstModalFinder), same(firstModalElement));
      expect(
        tester.getRect(firstModalFinder).width,
        closeTo(firstModalBefore.width * 0.92, 1),
      );
      expect(find.text('Top picker'), findsOneWidget);
    });

    testWidgets(
      'uses a non-opaque page route and keeps the lower page mounted',
      (tester) async {
        final fixture = await _pumpModalFixture(tester);
        final lowerElement = tester.element(find.text('Lower action'));
        final modalContext = tester.element(find.text('Modal editor'));
        final route = ModalRoute.of(modalContext)!;

        expect(route, isA<ModalBottomSheetRoute<void>>());
        expect(route.opaque, isFalse);
        expect(route.settings.name, 'editor');
        expect((route.settings as Page<void>).restorationId, 'editor-page');
        expect(find.text('Lower action'), findsOneWidget);
        expect(find.text('Modal editor'), findsOneWidget);
        expect(lowerElement.mounted, isTrue);
        expect(fixture.events, isEmpty);
      },
    );

    testWidgets('transparent nondismissible barrier blocks lower pointers', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        barrierDismissible: false,
        barrierColorArgb: 0x00000000,
      );

      await tester.tap(find.text('Lower action'), warnIfMissed: false);
      await tester.pump();

      expect(fixture.events, isEmpty);
      expect(find.text('Modal editor'), findsOneWidget);
      final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(bottomSheet.enableDrag, isFalse);
      expect(bottomSheet.showDragHandle, isFalse);
    });

    testWidgets('barrier tap honors a live canPop update without remounting', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, canPop: false);
      final route = ModalRoute.of(tester.element(find.text('Modal editor')));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.text = 'retained local state';

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(fixture.events, isEmpty);
      expect(find.text('Modal editor'), findsOneWidget);

      fixture.updateModal(canPop: true);
      await tester.pump();
      expect(
        ModalRoute.of(tester.element(find.text('Modal editor'))),
        same(route),
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        same(editable.controller),
      );
      expect(editable.controller.text, 'retained local state');

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'editor', result: null),
      );
    });

    testWidgets('Back and Escape use live canPop and emit one event', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, canPop: false);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.events, isEmpty);
      expect(find.text('Modal editor'), findsOneWidget);

      fixture.updateModal(canPop: true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'editor', result: null),
      );
    });

    testWidgets('declarative removal ignores native canPop veto', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, canPop: false);

      fixture.removeModal();
      await tester.pumpAndSettle();

      expect(find.text('Modal editor'), findsNothing);
      expect(find.text('Lower action'), findsOneWidget);
      expect(fixture.events, isEmpty);
    });

    testWidgets(
      'automatic input focus waits for the modal entrance to complete',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = await _pumpModalFixture(tester, startWithModal: false);

        fixture.pushModal();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        final editable = tester.widget<EditableText>(find.byType(EditableText));
        final route =
            ModalRoute.of(tester.element(find.text('Modal editor')))!
                as ModalBottomSheetRoute<void>;
        expect(route.animation!.value, inExclusiveRange(0, 1));
        expect(editable.focusNode.hasFocus, isFalse);
        expect(
          tester.getSemantics(find.text('Modal editor')),
          matchesSemantics(label: 'Modal editor'),
        );
        expect(
          FocusScope.of(tester.element(find.text('Modal editor'))).hasFocus,
          isTrue,
        );

        await tester.pumpAndSettle();

        expect(route.animation!.status, AnimationStatus.completed);
        expect(editable.focusNode.hasFocus, isTrue);
        semantics.dispose();
      },
    );

    testWidgets('requestFocus false never activates automatic input focus', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        requestFocus: false,
        startWithModal: false,
      );

      fixture.pushModal();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets(
      'same-key requestFocus update activates settled input without remounting',
      (tester) async {
        final fixture = await _pumpModalFixture(
          tester,
          requestFocus: false,
          startWithModal: false,
        );
        fixture.pushModal();
        await tester.pumpAndSettle();
        final editableFinder = find.byType(EditableText);
        final editableElement = tester.element(editableFinder);
        final editable = tester.widget<EditableText>(editableFinder);
        expect(editable.focusNode.hasFocus, isFalse);

        fixture.updateModal(requestFocus: true);
        await tester.pump();
        await tester.pump();

        expect(tester.element(editableFinder), same(editableElement));
        expect(editable.focusNode.hasFocus, isTrue);
      },
    );

    for (final (name, transitionDuration, disableAnimations) in [
      ('zero duration', 0, false),
      ('reduced motion', 250, true),
    ]) {
      testWidgets(
        '$name activates automatic focus without an artificial wait',
        (tester) async {
          final fixture = await _pumpModalFixture(
            tester,
            transitionDurationMilliseconds: transitionDuration,
            disableAnimations: disableAnimations,
            startWithModal: false,
          );

          fixture.pushModal();
          await tester.pump();
          await tester.pump();

          final route =
              ModalRoute.of(tester.element(find.text('Modal editor')))!
                  as ModalBottomSheetRoute<void>;
          expect(route.transitionDuration, Duration.zero);
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
        },
      );
    }

    testWidgets('an existing keyboard inset bypasses the automatic delay', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        viewInsets: const EdgeInsets.only(bottom: 80),
        startWithModal: false,
      );

      fixture.pushModal();
      await tester.pump();
      await tester.pump();

      final route =
          ModalRoute.of(tester.element(find.text('Modal editor')))!
              as ModalBottomSheetRoute<void>;
      final editableFinder = find.byType(EditableText);
      expect(route.animation!.value, lessThan(1));
      expect(
        tester.widget<EditableText>(editableFinder).focusNode.hasFocus,
        isTrue,
      );
      expect(
        MediaQuery.of(tester.element(editableFinder)).viewInsets.bottom,
        0,
      );
    });

    testWidgets('a pointer tap focuses immediately during modal entrance', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, startWithModal: false);
      fixture.pushModal();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final editableFinder = find.byType(EditableText);
      expect(
        tester.widget<EditableText>(editableFinder).focusNode.hasFocus,
        isFalse,
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      final route =
          ModalRoute.of(tester.element(find.text('Modal editor')))!
              as ModalBottomSheetRoute<void>;
      expect(route.animation!.value, lessThan(1));
      expect(
        tester.widget<EditableText>(editableFinder).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('removing a modal cancels pending automatic focus', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(tester, startWithModal: false);
      fixture.pushModal();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );

      fixture.removeModal();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EditableText), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('a covered modal cannot activate automatic focus late', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        startWithModal: false,
        secondModal: true,
      );
      fixture.pushModal();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      fixture.pushSecondModal(withAutofocusInput: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      var editors = tester
          .widgetList<EditableText>(
            find.byType(EditableText, skipOffstage: false),
          )
          .toList(growable: false);
      expect(editors, hasLength(2));
      expect(editors.first.focusNode.hasFocus, isFalse);
      expect(editors.last.focusNode.hasFocus, isFalse);

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      editors = tester
          .widgetList<EditableText>(
            find.byType(EditableText, skipOffstage: false),
          )
          .toList(growable: false);
      expect(editors.first.focusNode.hasFocus, isFalse);
      expect(editors.last.focusNode.hasFocus, isTrue);
    });

    testWidgets('route owns focus and excludes lower route semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpModalFixture(tester, requestFocus: true);

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        tester.getSemantics(find.text('Modal editor')),
        matchesSemantics(label: 'Modal editor'),
      );
      expect(find.bySemanticsLabel('Lower action'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.bySemanticsLabel('Lower action'), findsNothing);
      semantics.dispose();
    });

    testWidgets('route is the single keyboard-inset owner', (tester) async {
      await _pumpModalFixture(
        tester,
        sizing: const ScrollControlledModalSheetSizing(),
        viewInsets: const EdgeInsets.only(bottom: 80),
      );

      final editableFinder = find.byType(EditableText);
      final editable = tester.widget<EditableText>(editableFinder);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        MediaQuery.of(tester.element(editableFinder)).viewInsets.bottom,
        0,
      );
      expect(tester.getBottomRight(editableFinder).dy, lessThanOrEqualTo(220));
    });

    testWidgets(
      'scroll-controlled compose keeps a fixed large shell while its content '
      'viewport follows the keyboard',
      (tester) async {
        const size = Size(400, 600);
        const topSafeArea = 20.0;
        final contentViewportKey = GlobalKey();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<void> pumpWithInset(double bottomInset) async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: const EdgeInsets.only(top: topSafeArea),
                  viewPadding: const EdgeInsets.only(top: topSafeArea),
                  viewInsets: EdgeInsets.only(bottom: bottomInset),
                ),
                child: Navigator(
                  pages: [
                    const MaterialPage<void>(
                      key: ValueKey('fixed-shell-lower'),
                      canPop: false,
                      child: SizedBox.expand(),
                    ),
                    BonsaiModalBottomSheetPage(
                      key: const ValueKey('fixed-shell-compose'),
                      canPop: true,
                      presentation: const ModalBottomSheetPresentation(
                        barrierDismissible: true,
                        barrierColorArgb: 0x8a000000,
                        barrierLabel: 'Close fixed compose',
                        sizing: ScrollControlledModalSheetSizing(),
                        useSafeArea: true,
                        requestFocus: false,
                        transitionDurationMilliseconds: 0,
                        reverseTransitionDurationMilliseconds: 0,
                      ),
                      child: SizedBox.expand(
                        key: contentViewportKey,
                        child: const Text('Fixed compose editor'),
                      ),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pumpWithInset(0);
        final initialSurface = tester.getRect(
          _roundedModalSheetSurfaceFinder(),
        );
        final initialViewport = tester.getRect(find.byKey(contentViewportKey));
        final contentViewportElement = tester.element(
          find.byKey(contentViewportKey),
        );
        expect(initialSurface, const Rect.fromLTWH(0, 20, 400, 580));
        expect(initialViewport, initialSurface);

        final shellRects = <Rect>[initialSurface];
        final contentBottoms = <double>[initialViewport.bottom];
        for (final inset in [40.0, 80.0, 120.0, 0.0]) {
          await pumpWithInset(inset);
          shellRects.add(tester.getRect(_roundedModalSheetSurfaceFinder()));
          contentBottoms.add(
            tester.getRect(find.byKey(contentViewportKey)).bottom,
          );
          expect(
            tester.element(find.byKey(contentViewportKey)),
            same(contentViewportElement),
          );
          expect(
            MediaQuery.viewInsetsOf(
              tester.element(find.byKey(contentViewportKey)),
            ).bottom,
            0,
          );
        }

        expect(shellRects, everyElement(initialSurface));
        expect(
          contentBottoms,
          orderedEquals([600.0, 560.0, 520.0, 480.0, 600.0]),
        );
      },
    );

    for (final brightness in Brightness.values) {
      for (final (name, sizing) in [
        ('content-bounded', const ContentBoundedModalSheetSizing()),
        ('scroll-controlled', const ScrollControlledModalSheetSizing()),
      ]) {
        testWidgets(
          '$name sheet paints its $brightness surface behind the keyboard',
          (tester) async {
            await _pumpModalFixture(
              tester,
              brightness: brightness,
              sizing: sizing,
              size: const Size(400, 600),
              viewInsets: const EdgeInsets.only(bottom: 80),
            );

            final expectedColor = Theme.of(
              tester.element(find.text('Modal editor')),
            ).colorScheme.surface;
            expect(await _readPixelColor(tester, 4, 560), expectedColor);
            expect(await _readPixelColor(tester, 396, 560), expectedColor);
          },
        );
      }
    }

    for (final (name, sizing) in [
      ('content-bounded', const ContentBoundedModalSheetSizing()),
      ('scroll-controlled', const ScrollControlledModalSheetSizing()),
    ]) {
      testWidgets('$name sheet follows sampled keyboard insets monotonically', (
        tester,
      ) async {
        final fixture = await _pumpModalFixture(
          tester,
          sizing: sizing,
          size: const Size(400, 600),
        );
        final editableFinder = find.byType(EditableText);
        final editableElement = tester.element(editableFinder);
        final sheetRects = <Rect>[];

        for (final inset in [0.0, 40.0, 80.0, 120.0]) {
          await fixture.setViewInsets(EdgeInsets.only(bottom: inset));
          sheetRects.add(tester.getRect(_roundedModalSheetSurfaceFinder()));
          expect(tester.element(editableFinder), same(editableElement));
          expect(
            MediaQuery.of(tester.element(editableFinder)).viewInsets.bottom,
            0,
          );
        }

        if (sizing is ScrollControlledModalSheetSizing) {
          expect(sheetRects, everyElement(const Rect.fromLTWH(0, 0, 400, 600)));
        } else {
          expect(
            sheetRects.map((rect) => rect.bottom),
            orderedEquals([600.0, 560.0, 520.0, 480.0]),
          );
        }
      });
    }

    for (final direction in TextDirection.values) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'safe area and compact large-text layout work for $direction $brightness',
          (tester) async {
            await _pumpModalFixture(
              tester,
              direction: direction,
              brightness: brightness,
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.fromLTRB(12, 20, 16, 10),
              useSafeArea: true,
              sizing: const ScrollControlledModalSheetSizing(),
              size: const Size(320, 220),
            );

            final sheetRect = tester.getRect(find.byType(BottomSheet));
            final labelRect = tester.getRect(find.text('Modal editor'));
            expect(sheetRect.left, greaterThanOrEqualTo(12));
            expect(sheetRect.right, lessThanOrEqualTo(304));
            expect(sheetRect.top, greaterThanOrEqualTo(20));
            expect(sheetRect.bottom, lessThanOrEqualTo(220));
            expect(
              labelRect.overlaps(const Rect.fromLTWH(0, 0, 320, 220)),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('reduced motion resolves route durations to zero', (
      tester,
    ) async {
      final fixture = await _pumpModalFixture(
        tester,
        transitionDurationMilliseconds: 325,
        reverseTransitionDurationMilliseconds: 175,
      );
      final initialRoute =
          ModalRoute.of(tester.element(find.text('Modal editor')))!
              as ModalBottomSheetRoute<void>;
      expect(
        initialRoute.transitionDuration,
        const Duration(milliseconds: 325),
      );
      expect(
        initialRoute.reverseTransitionDuration,
        const Duration(milliseconds: 175),
      );

      await fixture.setReducedMotion(true);
      final reducedRoute =
          ModalRoute.of(tester.element(find.text('Modal editor')))!
              as ModalBottomSheetRoute<void>;
      expect(reducedRoute, same(initialRoute));
      expect(reducedRoute.transitionDuration, Duration.zero);
      expect(reducedRoute.reverseTransitionDuration, Duration.zero);

      fixture.updateModal(canPop: true);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(fixture.events, hasLength(1));
      expect(find.text('Modal editor'), findsNothing);
    });

    testWidgets(
      'stable key preserves route identity and a new key replaces it',
      (tester) async {
        final fixture = await _pumpModalFixture(tester);
        final first = ModalRoute.of(tester.element(find.text('Modal editor')));
        final lowerFinder = find.byKey(_lowerSurfaceKey, skipOffstage: false);
        final lowerElement = tester.element(lowerFinder);
        final lowerRect = tester.getRect(lowerFinder);

        fixture.updateModal(barrierLabel: 'Dismiss editor');
        await tester.pump();
        expect(
          ModalRoute.of(tester.element(find.text('Modal editor'))),
          same(first),
        );
        expect(
          tester
              .widget<ModalBarrier>(find.byType(ModalBarrier).last)
              .semanticsLabel,
          'Dismiss editor',
        );
        expect(tester.element(lowerFinder), same(lowerElement));
        expect(tester.getRect(lowerFinder), lowerRect);

        fixture.updateModal(
          pageKey: 'editor-2',
          restorationId: 'editor-page-2',
        );
        await tester.pumpAndSettle();
        final second = ModalRoute.of(tester.element(find.text('Modal editor')));
        expect(second, isNot(same(first)));
        expect(second!.settings.name, 'editor-2');
        expect((second.settings as Page<void>).restorationId, 'editor-page-2');
        expect(tester.element(lowerFinder), same(lowerElement));
        expect(tester.getRect(lowerFinder), lowerRect);
      },
    );

    testWidgets('two modal pages pop only the top route', (tester) async {
      final fixture = await _pumpModalFixture(tester, secondModal: true);

      expect(find.text('Modal editor'), findsOneWidget);
      expect(find.text('Top picker'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'picker', result: null),
      );
      expect(find.text('Modal editor'), findsOneWidget);
    });

    testWidgets('detented sheet expands before its primary content scrolls', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      final list = find.byType(CustomScrollView);

      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(_primaryScrollPosition(tester).pixels, 0);

      await tester.drag(list, const Offset(0, -260));
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(600, 2));
      expect(_primaryScrollPosition(tester).pixels, 0);

      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(_primaryScrollPosition(tester).pixels, greaterThan(0));

      final before = _primaryScrollPosition(tester).pixels;
      await tester.drag(list, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(600, 2));
      expect(_primaryScrollPosition(tester).pixels, lessThan(before));
      expect(fixture.events, isEmpty);
    });

    testWidgets('reduced motion content drag snaps within one millisecond', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester, disableAnimations: true);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
      );

      await gesture.moveBy(const Offset(0, -180));
      await tester.pump();
      expect(_sheetHeight(tester), inExclusiveRange(300, 600));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(_sheetHeight(tester), closeTo(600, 2));
    });

    testWidgets('detented sheet collapses and then drag-dismisses once', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(
        tester,
        initialDetent: ModalSheetDetent.large,
      );
      final list = find.byType(CustomScrollView);

      expect(_sheetHeight(tester), closeTo(600, 2));
      await tester.drag(list, const Offset(0, 260));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(fixture.events, isEmpty);

      await tester.drag(list, const Offset(0, 260));
      await tester.pumpAndSettle();

      expect(find.text('Detented editor'), findsNothing);
      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detented-editor', result: null),
      );
    });

    testWidgets('detented sheet fling-dismisses exactly once', (tester) async {
      final fixture = await _pumpDetentedFixture(tester);

      await tester.fling(
        find.bySemanticsLabel('Adjust sheet height'),
        const Offset(0, 320),
        1800,
      );
      await tester.pumpAndSettle();

      expect(find.text('Detented editor'), findsNothing);
      expect(fixture.events, hasLength(1));
      expect(
        fixture.events.single.payload,
        const RoutePopEventPayload(pageKey: 'detented-editor', result: null),
      );
    });

    testWidgets('drag dismissal honors live canPop and preserves state', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester, canPop: false);
      final route = ModalRoute.of(tester.element(find.text('Detented editor')));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.text = 'retained detented state';

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(fixture.events, isEmpty);
      expect(find.text('Detented editor'), findsOneWidget);

      fixture.update(canPop: true);
      await tester.pump();
      expect(
        ModalRoute.of(tester.element(find.text('Detented editor'))),
        same(route),
      );
      expect(editable.controller.text, 'retained detented state');

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(fixture.events, hasLength(1));
      expect(find.text('Detented editor'), findsNothing);
    });

    testWidgets('disabling canPop during a drag recovers to medium', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
      );
      await gesture.moveBy(const Offset(0, 180));
      await tester.pump();

      fixture.update(canPop: false);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Detented editor'), findsOneWidget);
      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(fixture.events, isEmpty);
    });

    testWidgets('detent handle supports semantics and reduced motion', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpDetentedFixture(tester, disableAnimations: true);
      var handle = tester.getSemantics(
        find.bySemanticsLabel('Adjust sheet height'),
      );

      expect(handle.getSemanticsData().value, 'Half height');
      expect(
        handle.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      handle.owner!.performAction(handle.id, SemanticsAction.increase);
      await tester.pump();

      expect(_sheetHeight(tester), closeTo(600, 2));
      handle = tester.getSemantics(
        find.bySemanticsLabel('Adjust sheet height'),
      );
      expect(handle.getSemanticsData().value, 'Full height');
      handle.owner!.performAction(handle.id, SemanticsAction.decrease);
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(300, 2));
      semantics.dispose();
    });

    testWidgets('semantic decrease dismisses from the smallest detent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _pumpDetentedFixture(
        tester,
        disableAnimations: true,
      );
      final handle = tester.getSemantics(
        find.bySemanticsLabel('Adjust sheet height'),
      );

      expect(
        handle.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );
      handle.owner!.performAction(handle.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();

      expect(find.text('Detented editor'), findsNothing);
      expect(fixture.events, hasLength(1));
      semantics.dispose();
    });

    for (final policy in const [
      (canPop: false, dismissOnDrag: true),
      (canPop: true, dismissOnDrag: false),
    ]) {
      testWidgets(
        'semantic decrease is unavailable when dismissal is vetoed '
        '(canPop: ${policy.canPop}, dismissOnDrag: ${policy.dismissOnDrag})',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _pumpDetentedFixture(
            tester,
            canPop: policy.canPop,
            dismissOnDrag: policy.dismissOnDrag,
          );
          final handle = tester.getSemantics(
            find.bySemanticsLabel('Adjust sheet height'),
          );

          expect(
            handle.getSemanticsData().hasAction(SemanticsAction.decrease),
            isFalse,
          );
          semantics.dispose();
        },
      );
    }

    testWidgets('detent handle supports physical keyboard adjustment', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(
        tester,
        disableAnimations: true,
      );
      final handle = find.bySemanticsLabel('Adjust sheet height');
      Focus.of(tester.element(handle)).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(600, 2));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(300, 2));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('Detented editor'), findsNothing);
      expect(fixture.events, hasLength(1));
    });

    testWidgets('detent handle accepts touch drag and snaps to large', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester);

      await tester.drag(
        find.bySemanticsLabel('Adjust sheet height'),
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(600, 2));
    });

    testWidgets('horizontal touch intent cancels detent-handle dragging', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Adjust sheet height')),
        kind: PointerDeviceKind.touch,
      );

      await gesture.moveBy(const Offset(6, 4));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -220));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(300, 2));
    });

    testWidgets('stylus keeps detent-handle drag behavior', (tester) async {
      await _pumpDetentedFixture(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Adjust sheet height')),
        kind: PointerDeviceKind.stylus,
      );

      await gesture.moveBy(const Offset(6, 4));
      await gesture.moveBy(const Offset(0, -220));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(300, 2));
    });

    testWidgets('detent handle accepts mouse drag and snaps to large', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester);
      final handle = find.bySemanticsLabel('Adjust sheet height');
      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -220));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(600, 2));
    });

    testWidgets('detent handle tap cycles through configured detents', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester);
      final handle = find.bySemanticsLabel('Adjust sheet height');

      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(600, 2));

      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(300, 2));
    });

    testWidgets('equidistant reconciliation chooses the larger detent', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Adjust sheet height')),
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -150));
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(450, 2));

      fixture.update(barrierLabel: 'Updated while midway');
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(600, 2));
      await gesture.cancel();
    });

    testWidgets('dismissOnDrag false keeps the smallest detent visible', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester, dismissOnDrag: false);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(find.text('Detented editor'), findsOneWidget);
      expect(fixture.events, isEmpty);
    });

    testWidgets('detents use the keyboard-adjusted viewport once', (
      tester,
    ) async {
      await _pumpDetentedFixture(
        tester,
        size: const Size(400, 600),
        viewInsets: const EdgeInsets.only(bottom: 100),
      );

      expect(_sheetHeight(tester), closeTo(250, 2));
      expect(tester.getRect(find.byType(BottomSheet).last).bottom, 500);
      expect(
        MediaQuery.of(
          tester.element(find.byType(EditableText)),
        ).viewInsets.bottom,
        0,
      );
    });

    for (final initialDetent in ModalSheetDetent.values) {
      testWidgets(
        '${initialDetent.name} detent follows sampled keyboard insets monotonically',
        (tester) async {
          final fixture = await _pumpDetentedFixture(
            tester,
            initialDetent: initialDetent,
            size: const Size(400, 600),
          );
          final editableFinder = find.byType(EditableText);
          final editableElement = tester.element(editableFinder);
          final sheetBottoms = <double>[];
          final sheetHeights = <double>[];

          for (final inset in [0.0, 40.0, 80.0, 120.0]) {
            await fixture.setViewInsets(EdgeInsets.only(bottom: inset));
            final rect = tester.getRect(find.byType(BottomSheet).last);
            sheetBottoms.add(rect.bottom);
            sheetHeights.add(rect.height);
            expect(tester.element(editableFinder), same(editableElement));
            expect(
              MediaQuery.of(tester.element(editableFinder)).viewInsets.bottom,
              0,
            );
          }

          expect(sheetBottoms, orderedEquals([600.0, 560.0, 520.0, 480.0]));
          expect(
            sheetHeights,
            orderedEquals(
              initialDetent == ModalSheetDetent.medium
                  ? [300.0, 280.0, 260.0, 240.0]
                  : [600.0, 560.0, 520.0, 480.0],
            ),
          );
        },
      );
    }

    testWidgets('compact large-text detented layout stays in the viewport', (
      tester,
    ) async {
      await _pumpDetentedFixture(
        tester,
        initialDetent: ModalSheetDetent.large,
        size: const Size(320, 220),
        textScaler: const TextScaler.linear(2),
        padding: const EdgeInsets.fromLTRB(12, 20, 16, 10),
        useSafeArea: true,
      );

      final rect = tester.getRect(find.byType(BottomSheet).last);
      expect(rect.left, greaterThanOrEqualTo(12));
      expect(rect.right, lessThanOrEqualTo(304));
      expect(rect.top, greaterThanOrEqualTo(20));
      expect(rect.bottom, lessThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });

    for (final initialDetent in ModalSheetDetent.values) {
      testWidgets(
        '${initialDetent.name} detent preserves focus, modal semantics, safe '
        'geometry, keyboard ownership, RTL, dark theme, and reduced motion',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _pumpDetentedFixture(
            tester,
            canPop: false,
            initialDetent: initialDetent,
            disableAnimations: true,
            size: const Size(320, 400),
            viewInsets: const EdgeInsets.only(bottom: 50),
            padding: const EdgeInsets.fromLTRB(12, 20, 16, 0),
            textScaler: const TextScaler.linear(2),
            useSafeArea: true,
            requestFocus: true,
            textInputAutofocus: true,
            textDirection: TextDirection.rtl,
            brightness: Brightness.dark,
          );

          final route = ModalRoute.of(
            tester.element(find.text('Detented editor')),
          )!;
          final rect = tester.getRect(find.byType(BottomSheet).last);
          final expectedHeight = initialDetent == ModalSheetDetent.medium
              ? 165.0
              : 330.0;
          expect(rect.height, closeTo(expectedHeight, 2));
          expect(rect.left, greaterThanOrEqualTo(12));
          expect(rect.right, lessThanOrEqualTo(304));
          expect(rect.top, greaterThanOrEqualTo(20));
          expect(rect.bottom, lessThanOrEqualTo(350));
          expect(
            MediaQuery.of(
              tester.element(find.byType(EditableText)),
            ).viewInsets.bottom,
            0,
          );
          expect(
            Directionality.of(tester.element(find.text('Detented editor'))),
            TextDirection.rtl,
          );
          expect(
            Theme.of(tester.element(find.text('Detented editor'))).brightness,
            Brightness.dark,
          );
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
          expect(route.transitionDuration, Duration.zero);
          expect(route.reverseTransitionDuration, Duration.zero);
          expect(find.bySemanticsLabel('Lower detented page'), findsNothing);

          await tester.tapAt(const Offset(6, 6));
          await tester.pump();
          expect(find.text('Detented editor'), findsOneWidget);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }

    testWidgets('same key preserves detent and new key uses initial detent', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(600, 2));

      fixture.update(barrierLabel: 'Dismiss detented editor');
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(600, 2));

      fixture.update(
        pageKey: 'detented-editor-2',
        restorationId: 'detented-editor-page-2',
      );
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(300, 2));
    });

    testWidgets('process restoration restarts at the configured detent', (
      tester,
    ) async {
      await _pumpDetentedFixture(tester, disableAnimations: true);
      final firstRoute = ModalRoute.of(
        tester.element(find.text('Detented editor')),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      editable.controller.text = 'restored child state';
      await tester.tap(find.bySemanticsLabel('Adjust sheet height'));
      await tester.pump();
      expect(_sheetHeight(tester), closeTo(600, 2));

      await tester.restartAndRestore();
      await tester.pumpAndSettle();

      final restoredRoute = ModalRoute.of(
        tester.element(find.text('Detented editor')),
      );
      expect(restoredRoute, isNot(same(firstRoute)));
      expect(restoredRoute!.settings.name, 'detented-editor');
      expect(
        (restoredRoute.settings as Page<void>).restorationId,
        'detented-editor-page',
      );
      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'restored child state',
      );
    });

    testWidgets('removing the selected detent moves to the nearest survivor', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(600, 2));

      fixture.update(detents: ModalSheetDetentSet.medium);
      await tester.pumpAndSettle();

      expect(_sheetHeight(tester), closeTo(300, 2));
      expect(find.text('Detented editor'), findsOneWidget);
    });

    testWidgets('primary detented scrollable remains host-effect addressable', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);

      final request = fixture.resources.scrollTo(
        7,
        alignment: 0.5,
        animated: false,
      );
      await tester.pump();
      await request;

      expect(_primaryScrollPosition(tester).pixels, greaterThan(0));
    });

    testWidgets('same-key policy updates preserve primary scroll position', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
      await tester.pumpAndSettle();
      final before = _primaryScrollPosition(tester).pixels;
      expect(before, greaterThan(0));

      fixture.update(
        canPop: false,
        barrierLabel: 'Updated without resetting scroll',
        requestFocus: true,
        transitionDurationMilliseconds: 0,
        reverseTransitionDurationMilliseconds: 0,
      );
      await tester.pump();

      expect(_primaryScrollPosition(tester).pixels, closeTo(before, 0.001));
      expect(_sheetHeight(tester), closeTo(600, 2));
    });

    testWidgets('declarative detented removal ignores canPop veto', (
      tester,
    ) async {
      final fixture = await _pumpDetentedFixture(tester, canPop: false);

      fixture.remove();
      await tester.pumpAndSettle();

      expect(find.text('Detented editor'), findsNothing);
      expect(find.text('Lower detented page'), findsOneWidget);
      expect(fixture.events, isEmpty);
      expect(fixture.resources.liveResourceCount, 0);
    });

    for (final primaryCount in [0, 2]) {
      testWidgets(
        'detented sheet rejects $primaryCount primary vertical scrollables',
        (tester) async {
          final store = NodeStore()
            ..apply(_detentedSnapshot(primaryCount: primaryCount));
          final reportedErrors = <Object>[];
          final previousOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            reportedErrors.add(details.exception);
          };
          addTearDown(() => FlutterError.onError = previousOnError);

          await tester.pumpWidget(
            MaterialApp(
              home: BonsaiFlutterView(
                store: store,
                registry: WidgetRegistry.standard(),
              ),
            ),
          );
          FlutterError.onError = previousOnError;

          final error = reportedErrors
              .whereType<RendererBoundaryError>()
              .single;
          expect(error.cause, isA<RendererBuildException>());
          final message = (error.cause as RendererBuildException).message;
          expect(message, contains(primaryCount == 0 ? '[]' : '[7, 47]'));
        },
      );
    }

    testWidgets('rejects a modal page as the first Navigator page', (
      tester,
    ) async {
      final store = NodeStore()..apply(_modalOnlySnapshot());

      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<RendererBoundaryError>().having(
          (error) => error.cause,
          'cause',
          isA<RendererBuildException>(),
        ),
      );
    });
  });
}

double _pageLeadingEdge(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label, skipOffstage: false)).dx;

final class _SlideFixture {
  _SlideFixture({
    required this.store,
    required this.events,
    required this.canPop,
    required this.pushable,
  });

  final NodeStore store;
  final List<RendererEvent> events;
  final bool canPop;
  final bool pushable;

  void pushDetail() {
    if (!pushable) return;
    store.apply(_detailPageFrame(canPop: canPop));
  }
}

Future<_SlideFixture> _pumpSlideFixture(
  WidgetTester tester, {
  bool canPop = true,
  bool pushable = true,
  bool disableAnimations = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(400, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = NodeStore()..apply(_rootPageFrame());
  final events = <RendererEvent>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 300),
            disableAnimations: disableAnimations,
            accessibleNavigation: disableAnimations,
          ),
          child: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
            onEvent: events.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _SlideFixture(
    store: store,
    events: events,
    canPop: canPop,
    pushable: pushable,
  );
}

Frame _rootPageFrame() => const Frame(
  runtimeEpoch: 72,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'slide-test'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 701),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'inbox',
        presentation: StandardPagePresentation(PageTransition.none),
        canPop: false,
        restorationId: 'inbox-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Inbox'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2]),
    SetChildren(nodeId: 2, children: [3]),
    SetChildren(nodeId: 3, children: [4]),
    SetRoot(1),
  ],
);

Frame _detailPageFrame({required bool canPop}) => Frame(
  runtimeEpoch: 72,
  baseRevision: 1,
  targetRevision: 2,
  kind: FrameKind.incremental,
  operations: [
    CreateNode(
      nodeId: 5,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'detail',
        presentation: StandardPagePresentation(PageTransition.slide),
        canPop: canPop,
        restorationId: 'detail-page',
      ),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 6,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 7,
      kind: NodeKind.text,
      props: TextProps('Detail'),
      eventBindings: [],
    ),
    const SetChildren(nodeId: 5, children: [6]),
    const SetChildren(nodeId: 6, children: [7]),
    const SetChildren(nodeId: 1, children: [2, 5]),
  ],
);

Frame _navigationSnapshot() => const Frame(
  runtimeEpoch: 51,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'app'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 700),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'home',
        presentation: StandardPagePresentation(PageTransition.none),
        canPop: false,
        restorationId: 'home-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 3,
      kind: NodeKind.text,
      props: TextProps('Home'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 4,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'settings',
        presentation: StandardPagePresentation(PageTransition.fade),
        canPop: true,
        restorationId: 'settings-page',
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 5,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 6,
      kind: NodeKind.text,
      props: TextProps('Settings'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 7,
      kind: NodeKind.overlay,
      props: OverlayProps(
        alignment: OverlayAlignment.center,
        dismissible: false,
      ),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 8,
      kind: NodeKind.text,
      props: TextProps('Overlay content'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 9,
      kind: NodeKind.materialDialog,
      props: MaterialDialogProps(barrierDismissible: false),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 10,
      kind: NodeKind.text,
      props: TextProps('Confirm'),
      eventBindings: [],
    ),
    SetChildren(nodeId: 1, children: [2, 4]),
    SetChildren(nodeId: 2, children: [3]),
    SetChildren(nodeId: 4, children: [5]),
    SetChildren(nodeId: 5, children: [6, 7, 9]),
    SetChildren(nodeId: 7, children: [8]),
    SetChildren(nodeId: 9, children: [10]),
    SetRoot(1),
  ],
);

final class _ModalFixture {
  _ModalFixture({
    required this.tester,
    required this.store,
    required this.events,
    required this.pumpApp,
    required this.setViewInsets,
    required this.props,
  });

  final WidgetTester tester;
  final NodeStore store;
  final List<RendererEvent> events;
  final Future<void> Function(bool reducedMotion) pumpApp;
  final Future<void> Function(EdgeInsets viewInsets) setViewInsets;
  PageProps props;
  int _revision = 1;

  void pushModal() {
    store.apply(
      Frame(
        runtimeEpoch: 74,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: [
          CreateNode(
            nodeId: 5,
            kind: NodeKind.page,
            props: props,
            eventBindings: const [],
          ),
          const CreateNode(
            nodeId: 6,
            kind: NodeKind.sizedBox,
            props: SizedBoxProps(width: null, height: 150),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 7,
            kind: NodeKind.column,
            props: LinearProps(),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 8,
            kind: NodeKind.text,
            props: TextProps('Modal editor'),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 9,
            kind: NodeKind.textInput,
            props: TextInputProps(
              sessionId: 74,
              documentRevision: 1,
              value: TextEditingStateValue(
                text: '',
                selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
                composing: null,
              ),
              enabled: true,
              readOnly: false,
              obscureText: false,
              keyboardType: TextKeyboardType.text,
              inputAction: TextInputActionKind.done,
              acceptedLocalRevision: 0,
              updateMode: TextUpdateMode.forceReplace,
              autofocus: true,
            ),
            eventBindings: [],
          ),
          const SetChildren(nodeId: 1, children: [2, 5]),
          const SetChildren(nodeId: 5, children: [6]),
          const SetChildren(nodeId: 6, children: [7]),
          const SetChildren(nodeId: 7, children: [8, 9]),
        ],
      ),
    );
  }

  void pushSecondModal({bool withAutofocusInput = false}) {
    store.apply(
      Frame(
        runtimeEpoch: 74,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: [
          CreateNode(
            nodeId: 20,
            kind: NodeKind.page,
            props: _modalPageProps(
              pageKey: 'picker',
              restorationId: 'picker-page',
              canPop: true,
              barrierDismissible: true,
              barrierColorArgb: 0x66000000,
              barrierLabel: 'Close picker',
              sizing: const ContentBoundedModalSheetSizing(),
              useSafeArea: false,
              requestFocus: true,
              transitionDurationMilliseconds: 250,
              reverseTransitionDurationMilliseconds: 200,
            ),
            eventBindings: const [],
          ),
          const CreateNode(
            nodeId: 21,
            kind: NodeKind.sizedBox,
            props: SizedBoxProps(width: null, height: 80),
            eventBindings: [],
          ),
          const CreateNode(
            nodeId: 22,
            kind: NodeKind.text,
            props: TextProps('Top picker'),
            eventBindings: [],
          ),
          if (withAutofocusInput) ...[
            const CreateNode(
              nodeId: 23,
              kind: NodeKind.column,
              props: LinearProps(),
              eventBindings: [],
            ),
            const CreateNode(
              nodeId: 24,
              kind: NodeKind.textInput,
              props: TextInputProps(
                sessionId: 75,
                documentRevision: 1,
                value: TextEditingStateValue(
                  text: '',
                  selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
                  composing: null,
                ),
                enabled: true,
                readOnly: false,
                obscureText: false,
                keyboardType: TextKeyboardType.text,
                inputAction: TextInputActionKind.done,
                acceptedLocalRevision: 0,
                updateMode: TextUpdateMode.forceReplace,
                autofocus: true,
              ),
              eventBindings: [],
            ),
          ],
          const SetChildren(nodeId: 1, children: [2, 5, 20]),
          const SetChildren(nodeId: 20, children: [21]),
          SetChildren(nodeId: 21, children: [withAutofocusInput ? 23 : 22]),
          if (withAutofocusInput) ...[
            const SetChildren(nodeId: 23, children: [22, 24]),
          ],
        ],
      ),
    );
  }

  void pushStandardPage() {
    store.apply(
      Frame(
        runtimeEpoch: 74,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: const [
          CreateNode(
            nodeId: 30,
            kind: NodeKind.page,
            props: PageProps(
              pageKey: 'standard-detail',
              presentation: StandardPagePresentation(PageTransition.fade),
              canPop: true,
              restorationId: 'standard-detail-page',
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 31,
            kind: NodeKind.materialScaffold,
            props: MaterialScaffoldProps(hasAppBar: false),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 32,
            kind: NodeKind.text,
            props: TextProps('Standard detail'),
            eventBindings: [],
          ),
          SetChildren(nodeId: 1, children: [2, 30]),
          SetChildren(nodeId: 30, children: [31]),
          SetChildren(nodeId: 31, children: [32]),
        ],
      ),
    );
  }

  void updateModal({
    String? pageKey,
    String? restorationId,
    bool? canPop,
    bool? barrierDismissible,
    int? barrierColorArgb,
    String? barrierLabel,
    ModalBottomSheetSizing? sizing,
    bool? useSafeArea,
    bool? requestFocus,
    int? transitionDurationMilliseconds,
    int? reverseTransitionDurationMilliseconds,
  }) {
    final current = props.presentation as ModalBottomSheetPresentation;
    props = PageProps(
      pageKey: pageKey ?? props.pageKey,
      presentation: ModalBottomSheetPresentation(
        barrierDismissible: barrierDismissible ?? current.barrierDismissible,
        barrierColorArgb: barrierColorArgb ?? current.barrierColorArgb,
        barrierLabel: barrierLabel ?? current.barrierLabel,
        sizing: sizing ?? current.sizing,
        useSafeArea: useSafeArea ?? current.useSafeArea,
        requestFocus: requestFocus ?? current.requestFocus,
        transitionDurationMilliseconds:
            transitionDurationMilliseconds ??
            current.transitionDurationMilliseconds,
        reverseTransitionDurationMilliseconds:
            reverseTransitionDurationMilliseconds ??
            current.reverseTransitionDurationMilliseconds,
      ),
      canPop: canPop ?? props.canPop,
      restorationId: restorationId ?? props.restorationId,
    );
    store.apply(
      Frame(
        runtimeEpoch: 74,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 5, props: props)],
      ),
    );
  }

  void removeModal() {
    store.apply(
      Frame(
        runtimeEpoch: 74,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: const [
          SetChildren(nodeId: 1, children: [2]),
          DropNode(9),
          DropNode(8),
          DropNode(7),
          DropNode(6),
          DropNode(5),
        ],
      ),
    );
  }

  Future<void> setReducedMotion(bool value) => pumpApp(value);
}

Future<_ModalFixture> _pumpModalFixture(
  WidgetTester tester, {
  bool canPop = true,
  bool barrierDismissible = true,
  int? barrierColorArgb = 0x8a000000,
  String? barrierLabel = 'Close editor',
  ModalBottomSheetSizing sizing = const ContentBoundedModalSheetSizing(),
  bool useSafeArea = false,
  bool requestFocus = true,
  int transitionDurationMilliseconds = 250,
  int reverseTransitionDurationMilliseconds = 200,
  EdgeInsets viewInsets = EdgeInsets.zero,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection direction = TextDirection.ltr,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  Size size = const Size(400, 300),
  PageTransition lowerTransition = PageTransition.none,
  bool startWithModal = true,
  bool secondModal = false,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final modalProps = _modalPageProps(
    canPop: canPop,
    barrierDismissible: barrierDismissible,
    barrierColorArgb: barrierColorArgb,
    barrierLabel: barrierLabel,
    sizing: sizing,
    useSafeArea: useSafeArea,
    requestFocus: requestFocus,
    transitionDurationMilliseconds: transitionDurationMilliseconds,
    reverseTransitionDurationMilliseconds:
        reverseTransitionDurationMilliseconds,
  );
  final store = NodeStore()
    ..apply(
      _modalSnapshot(
        modalProps,
        lowerTransition: lowerTransition,
        startWithModal: startWithModal,
        secondModal: secondModal,
      ),
    );
  final events = <RendererEvent>[];
  var currentReducedMotion = disableAnimations;
  var currentViewInsets = viewInsets;

  Future<void> pumpApp(bool reducedMotion) async {
    currentReducedMotion = reducedMotion;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: padding,
              viewPadding: padding,
              viewInsets: currentViewInsets,
              textScaler: textScaler,
              disableAnimations: reducedMotion,
              accessibleNavigation: reducedMotion,
            ),
            child: BonsaiFlutterView(
              store: store,
              registry: WidgetRegistry.standard(),
              onEvent: events.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setViewInsets(EdgeInsets nextViewInsets) async {
    currentViewInsets = nextViewInsets;
    await pumpApp(currentReducedMotion);
  }

  await pumpApp(disableAnimations);
  return _ModalFixture(
    tester: tester,
    store: store,
    events: events,
    pumpApp: pumpApp,
    setViewInsets: setViewInsets,
    props: modalProps,
  );
}

PageProps _modalPageProps({
  String pageKey = 'editor',
  String? restorationId = 'editor-page',
  required bool canPop,
  required bool barrierDismissible,
  required int? barrierColorArgb,
  required String? barrierLabel,
  required ModalBottomSheetSizing sizing,
  required bool useSafeArea,
  required bool requestFocus,
  required int transitionDurationMilliseconds,
  required int reverseTransitionDurationMilliseconds,
}) => PageProps(
  pageKey: pageKey,
  presentation: ModalBottomSheetPresentation(
    barrierDismissible: barrierDismissible,
    barrierColorArgb: barrierColorArgb,
    barrierLabel: barrierLabel,
    sizing: sizing,
    useSafeArea: useSafeArea,
    requestFocus: requestFocus,
    transitionDurationMilliseconds: transitionDurationMilliseconds,
    reverseTransitionDurationMilliseconds:
        reverseTransitionDurationMilliseconds,
  ),
  canPop: canPop,
  restorationId: restorationId,
);

const Key _lowerSurfaceKey = ValueKey<int>(3);

Frame _modalSnapshot(
  PageProps modalProps, {
  required PageTransition lowerTransition,
  required bool startWithModal,
  required bool secondModal,
}) => Frame(
  runtimeEpoch: 74,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'modal-test'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 740),
      ],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'lower',
        presentation: StandardPagePresentation(lowerTransition),
        canPop: false,
        restorationId: 'lower-page',
      ),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 3,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 4,
      kind: NodeKind.button,
      props: ButtonProps(enabled: true),
      eventBindings: [EventBinding(eventTag: EventTagId.press, handlerId: 741)],
    ),
    const CreateNode(
      nodeId: 10,
      kind: NodeKind.text,
      props: TextProps('Lower action'),
      eventBindings: [],
    ),
    if (startWithModal) ...[
      CreateNode(
        nodeId: 5,
        kind: NodeKind.page,
        props: modalProps,
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 6,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: null, height: 150),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 7,
        kind: NodeKind.column,
        props: LinearProps(),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 8,
        kind: NodeKind.text,
        props: TextProps('Modal editor'),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 9,
        kind: NodeKind.textInput,
        props: TextInputProps(
          sessionId: 74,
          documentRevision: 1,
          value: TextEditingStateValue(
            text: '',
            selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
            composing: null,
          ),
          enabled: true,
          readOnly: false,
          obscureText: false,
          keyboardType: TextKeyboardType.text,
          inputAction: TextInputActionKind.done,
          acceptedLocalRevision: 0,
          updateMode: TextUpdateMode.forceReplace,
          autofocus: true,
        ),
        eventBindings: [],
      ),
    ],
    if (startWithModal && secondModal) ...[
      CreateNode(
        nodeId: 20,
        kind: NodeKind.page,
        props: _modalPageProps(
          pageKey: 'picker',
          restorationId: 'picker-page',
          canPop: true,
          barrierDismissible: true,
          barrierColorArgb: 0x66000000,
          barrierLabel: 'Close picker',
          sizing: const ContentBoundedModalSheetSizing(),
          useSafeArea: false,
          requestFocus: true,
          transitionDurationMilliseconds: 250,
          reverseTransitionDurationMilliseconds: 200,
        ),
        eventBindings: const [],
      ),
      const CreateNode(
        nodeId: 21,
        kind: NodeKind.sizedBox,
        props: SizedBoxProps(width: null, height: 80),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 22,
        kind: NodeKind.text,
        props: TextProps('Top picker'),
        eventBindings: [],
      ),
    ],
    SetChildren(
      nodeId: 1,
      children: [
        2,
        if (startWithModal) 5,
        if (startWithModal && secondModal) 20,
      ],
    ),
    const SetChildren(nodeId: 2, children: [3]),
    const SetChildren(nodeId: 3, children: [4]),
    const SetChildren(nodeId: 4, children: [10]),
    if (startWithModal) ...[
      const SetChildren(nodeId: 5, children: [6]),
      const SetChildren(nodeId: 6, children: [7]),
      const SetChildren(nodeId: 7, children: [8, 9]),
    ],
    if (startWithModal && secondModal) ...[
      const SetChildren(nodeId: 20, children: [21]),
      const SetChildren(nodeId: 21, children: [22]),
    ],
    const SetRoot(1),
  ],
);

void _expectRoundedModalSheetSurface(
  WidgetTester tester, {
  required String childText,
}) {
  final childContext = tester.element(find.text(childText));
  final expectedColor = Theme.of(childContext).colorScheme.surface;
  final expectedBorderRadius = const BorderRadius.vertical(
    top: Radius.circular(24),
  );
  final textDirection = Directionality.of(childContext);
  final matchingSurfaces = tester
      .widgetList<Material>(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        ),
      )
      .where((material) {
        final shape = material.shape;
        return material.color == expectedColor &&
            material.clipBehavior == Clip.antiAlias &&
            shape is RoundedRectangleBorder &&
            shape.borderRadius.resolve(textDirection) == expectedBorderRadius;
      })
      .toList(growable: false);

  expect(matchingSurfaces, hasLength(1));
}

Finder _roundedModalSheetSurfaceFinder() => find.byWidgetPredicate((widget) {
  if (widget is! Material || widget.clipBehavior != Clip.antiAlias) {
    return false;
  }
  final shape = widget.shape;
  return shape is RoundedRectangleBorder &&
      shape.borderRadius ==
          const BorderRadius.vertical(top: Radius.circular(24));
});

double _sheetHeight(WidgetTester tester) =>
    tester.getRect(find.byType(BottomSheet).last).height;

ScrollPosition _primaryScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

final class _DetentedFixture {
  _DetentedFixture({
    required this.store,
    required this.events,
    required this.resources,
    required this.setViewInsets,
    required this.props,
  });

  final NodeStore store;
  final List<RendererEvent> events;
  final RendererResourceStore resources;
  final Future<void> Function(EdgeInsets viewInsets) setViewInsets;
  PageProps props;
  int _revision = 1;

  void update({
    String? pageKey,
    String? restorationId,
    bool? canPop,
    String? barrierLabel,
    ModalSheetDetentSet? detents,
    bool? requestFocus,
    int? transitionDurationMilliseconds,
    int? reverseTransitionDurationMilliseconds,
  }) {
    final current = props.presentation as ModalBottomSheetPresentation;
    final currentSizing = current.sizing as DetentedModalSheetSizing;
    props = PageProps(
      pageKey: pageKey ?? props.pageKey,
      presentation: ModalBottomSheetPresentation(
        barrierDismissible: current.barrierDismissible,
        barrierColorArgb: current.barrierColorArgb,
        barrierLabel: barrierLabel ?? current.barrierLabel,
        sizing: DetentedModalSheetSizing(
          detents: detents ?? currentSizing.detents,
          initialDetent: currentSizing.initialDetent,
          dismissOnDrag: currentSizing.dismissOnDrag,
          handleSemantics: currentSizing.handleSemantics,
        ),
        useSafeArea: current.useSafeArea,
        requestFocus: requestFocus ?? current.requestFocus,
        transitionDurationMilliseconds:
            transitionDurationMilliseconds ??
            current.transitionDurationMilliseconds,
        reverseTransitionDurationMilliseconds:
            reverseTransitionDurationMilliseconds ??
            current.reverseTransitionDurationMilliseconds,
      ),
      canPop: canPop ?? props.canPop,
      restorationId: restorationId ?? props.restorationId,
    );
    store.apply(
      Frame(
        runtimeEpoch: 76,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 5, props: props)],
      ),
    );
  }

  void remove() {
    store.apply(
      Frame(
        runtimeEpoch: 76,
        baseRevision: _revision,
        targetRevision: ++_revision,
        kind: FrameKind.incremental,
        operations: const [
          SetChildren(nodeId: 1, children: [2]),
          DropNode(5),
          DropNode(6),
          DropNode(7),
          DropNode(71),
          DropNode(8),
          DropNode(9),
          DropNode(10),
          DropNode(11),
          DropNode(12),
          DropNode(13),
          DropNode(14),
          DropNode(15),
          DropNode(20),
          DropNode(21),
          DropNode(22),
          DropNode(23),
          DropNode(24),
          DropNode(25),
        ],
      ),
    );
  }
}

Future<_DetentedFixture> _pumpDetentedFixture(
  WidgetTester tester, {
  bool canPop = true,
  ModalSheetDetentSet detents = ModalSheetDetentSet.mediumAndLarge,
  ModalSheetDetent initialDetent = ModalSheetDetent.medium,
  bool dismissOnDrag = true,
  bool disableAnimations = false,
  Size size = const Size(400, 600),
  EdgeInsets viewInsets = EdgeInsets.zero,
  EdgeInsets padding = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
  bool useSafeArea = false,
  bool requestFocus = false,
  bool textInputAutofocus = false,
  TextDirection textDirection = TextDirection.ltr,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final props = _detentedPageProps(
    canPop: canPop,
    detents: detents,
    initialDetent: initialDetent,
    dismissOnDrag: dismissOnDrag,
    useSafeArea: useSafeArea,
    requestFocus: requestFocus,
  );
  final store = NodeStore()
    ..apply(
      _detentedSnapshot(
        pageProps: props,
        primaryCount: 1,
        textInputAutofocus: textInputAutofocus,
      ),
    );
  final resources = RendererResourceStore();
  addTearDown(resources.dispose);
  final events = <RendererEvent>[];
  var currentViewInsets = viewInsets;

  Future<void> pumpApp() async {
    await tester.pumpWidget(
      MaterialApp(
        restorationScopeId: 'detented-app',
        theme: ThemeData(brightness: brightness),
        home: Directionality(
          textDirection: textDirection,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              viewInsets: currentViewInsets,
              padding: padding,
              viewPadding: padding,
              textScaler: textScaler,
              disableAnimations: disableAnimations,
              accessibleNavigation: disableAnimations,
            ),
            child: BonsaiFlutterView(
              store: store,
              registry: WidgetRegistry.standard(),
              resourceStore: resources,
              onEvent: events.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setViewInsets(EdgeInsets nextViewInsets) async {
    currentViewInsets = nextViewInsets;
    await pumpApp();
  }

  await pumpApp();
  return _DetentedFixture(
    store: store,
    events: events,
    resources: resources,
    setViewInsets: setViewInsets,
    props: props,
  );
}

PageProps _detentedPageProps({
  bool canPop = true,
  ModalSheetDetentSet detents = ModalSheetDetentSet.mediumAndLarge,
  ModalSheetDetent initialDetent = ModalSheetDetent.medium,
  bool dismissOnDrag = true,
  bool useSafeArea = false,
  bool requestFocus = false,
}) => PageProps(
  pageKey: 'detented-editor',
  presentation: ModalBottomSheetPresentation(
    barrierDismissible: true,
    barrierColorArgb: 0x8a000000,
    barrierLabel: 'Close detented editor',
    sizing: DetentedModalSheetSizing(
      detents: detents,
      initialDetent: initialDetent,
      dismissOnDrag: dismissOnDrag,
      handleSemantics: const ModalSheetHandleSemantics(
        label: 'Adjust sheet height',
        mediumValue: 'Half height',
        largeValue: 'Full height',
      ),
    ),
    useSafeArea: useSafeArea,
    requestFocus: requestFocus,
    transitionDurationMilliseconds: 250,
    reverseTransitionDurationMilliseconds: 200,
  ),
  canPop: canPop,
  restorationId: 'detented-editor-page',
);

Frame _detentedSnapshot({
  PageProps? pageProps,
  required int primaryCount,
  bool textInputAutofocus = false,
}) => Frame(
  runtimeEpoch: 76,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: 'detented-test'),
      eventBindings: [
        EventBinding(eventTag: EventTagId.routePop, handlerId: 760),
      ],
    ),
    const CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: PageProps(
        pageKey: 'lower',
        presentation: StandardPagePresentation(PageTransition.none),
        canPop: false,
        restorationId: 'lower-page',
      ),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 3,
      kind: NodeKind.materialScaffold,
      props: MaterialScaffoldProps(hasAppBar: false),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 4,
      kind: NodeKind.text,
      props: TextProps('Lower detented page'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 5,
      kind: NodeKind.page,
      props: pageProps ?? _detentedPageProps(),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 6,
      kind: NodeKind.decoratedBox,
      props: DecoratedBoxProps(backgroundArgb: 0xfff9f9ff, borderRadius: 24),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 7,
      kind: NodeKind.scrollView,
      props: ScrollViewProps(
        axis: ScrollAxis.vertical,
        reverse: false,
        primary: primaryCount > 0,
      ),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 71,
      kind: NodeKind.sliverList,
      props: EmptyProps(),
      eventBindings: [],
    ),
    const CreateNode(
      nodeId: 8,
      kind: NodeKind.text,
      props: TextProps('Detented editor'),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 9,
      kind: NodeKind.textInput,
      props: TextInputProps(
        sessionId: 76,
        documentRevision: 1,
        value: TextEditingStateValue(
          text: '',
          selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
          composing: null,
        ),
        enabled: true,
        readOnly: false,
        obscureText: false,
        keyboardType: TextKeyboardType.text,
        inputAction: TextInputActionKind.done,
        acceptedLocalRevision: 0,
        updateMode: TextUpdateMode.forceReplace,
        autofocus: textInputAutofocus,
      ),
      eventBindings: [],
    ),
    for (var index = 0; index < 6; index += 1) ...[
      CreateNode(
        nodeId: 10 + index,
        kind: NodeKind.sizedBox,
        props: const SizedBoxProps(width: null, height: 140),
        eventBindings: const [],
      ),
      CreateNode(
        nodeId: 20 + index,
        kind: NodeKind.text,
        props: TextProps('Editor row ${index + 1}'),
        eventBindings: const [],
      ),
    ],
    if (primaryCount == 2) ...[
      const CreateNode(
        nodeId: 40,
        kind: NodeKind.column,
        props: LinearProps(),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 47,
        kind: NodeKind.scrollView,
        props: ScrollViewProps(
          axis: ScrollAxis.vertical,
          reverse: false,
          primary: true,
        ),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 471,
        kind: NodeKind.sliverList,
        props: EmptyProps(),
        eventBindings: [],
      ),
      const CreateNode(
        nodeId: 48,
        kind: NodeKind.text,
        props: TextProps('Second primary list'),
        eventBindings: [],
      ),
    ],
    const SetChildren(nodeId: 1, children: [2, 5]),
    const SetChildren(nodeId: 2, children: [3]),
    const SetChildren(nodeId: 3, children: [4]),
    const SetChildren(nodeId: 5, children: [6]),
    SetChildren(nodeId: 6, children: [primaryCount == 2 ? 40 : 7]),
    SetChildren(nodeId: 7, children: [71]),
    SetChildren(
      nodeId: 71,
      children: [8, 9, for (var index = 0; index < 6; index += 1) 10 + index],
    ),
    for (var index = 0; index < 6; index += 1)
      SetChildren(nodeId: 10 + index, children: [20 + index]),
    if (primaryCount == 2) ...[
      const SetChildren(nodeId: 40, children: [7, 47]),
      const SetChildren(nodeId: 47, children: [471]),
      const SetChildren(nodeId: 471, children: [48]),
    ],
    const SetRoot(1),
  ],
);

Frame _modalOnlySnapshot() => Frame(
  runtimeEpoch: 75,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.navigator,
      props: NavigatorProps(restorationScopeId: null),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.page,
      props: _modalPageProps(
        canPop: false,
        barrierDismissible: false,
        barrierColorArgb: null,
        barrierLabel: null,
        sizing: const ContentBoundedModalSheetSizing(),
        useSafeArea: false,
        requestFocus: true,
        transitionDurationMilliseconds: 250,
        reverseTransitionDurationMilliseconds: 200,
      ),
      eventBindings: const [],
    ),
    const CreateNode(
      nodeId: 3,
      kind: NodeKind.text,
      props: TextProps('Invalid modal root'),
      eventBindings: [],
    ),
    const SetChildren(nodeId: 1, children: [2]),
    const SetChildren(nodeId: 2, children: [3]),
    const SetRoot(1),
  ],
);

Future<Color> _readPixelColor(WidgetTester tester, int x, int y) async {
  final renderView = tester.binding.renderViews.single;
  final layer = renderView.debugLayer! as OffsetLayer;
  final capture = await tester.binding.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds);
    final width = image.width;
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    image.dispose();
    return (width: width, bytes: bytes!);
  });
  final offset = (y * capture!.width + x) * 4;
  return Color.fromARGB(
    capture.bytes.getUint8(offset + 3),
    capture.bytes.getUint8(offset),
    capture.bytes.getUint8(offset + 1),
    capture.bytes.getUint8(offset + 2),
  );
}
