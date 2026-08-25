import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

const _outerKey = ValueKey('expandable-composer');

void main() {
  testWidgets(
    'collapsed composer occupies only its FAB and does not reserve body space',
    (tester) async {
      const viewport = Size(390, 844);
      const bodyKey = ValueKey('full-scaffold-body');
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(key: bodyKey),
            floatingActionButton: _composer(),
          ),
        ),
      );

      expect(tester.getBottomRight(find.byKey(bodyKey)).dy, viewport.height);
      expect(
        tester.getRect(find.byKey(_outerKey)),
        tester.getRect(find.byType(FloatingActionButton)),
      );
    },
  );

  testWidgets(
    'scaffold owns every FAB location above a real bottom navigation bar',
    (tester) async {
      const viewport = Size(390, 844);
      const navigationHeight = 80.0;
      const bodyKey = ValueKey('body-above-navigation');
      const navigationKey = ValueKey('real-bottom-navigation');
      const standardFabKey = ValueKey('standard-extended-fab');
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Widget host({
        required Widget floatingActionButton,
        required FloatingActionButtonLocation location,
      }) => MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(key: bodyKey),
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: location,
          bottomNavigationBar: const SizedBox(
            key: navigationKey,
            height: navigationHeight,
          ),
        ),
      );

      for (final location in [
        FloatingActionButtonLocation.startFloat,
        FloatingActionButtonLocation.centerFloat,
        FloatingActionButtonLocation.endFloat,
        FloatingActionButtonLocation.startDocked,
        FloatingActionButtonLocation.centerDocked,
        FloatingActionButtonLocation.endDocked,
      ]) {
        await tester.pumpWidget(
          host(
            floatingActionButton: FloatingActionButton.extended(
              key: standardFabKey,
              heroTag: null,
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Capture'),
            ),
            location: location,
          ),
        );
        await tester.pumpAndSettle();
        final standardRect = tester.getRect(find.byKey(standardFabKey));

        await tester.pumpWidget(
          host(floatingActionButton: _composer(), location: location),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(FloatingActionButton)),
          standardRect,
          reason: '$location must be owned entirely by Scaffold',
        );
        expect(
          tester.getBottomRight(find.byKey(bodyKey)).dy,
          tester.getTopLeft(find.byKey(navigationKey)).dy,
        );
      }
    },
  );

  testWidgets(
    'collapsed state is one real enabled extended FAB without editor',
    (tester) async {
      await tester.pumpWidget(_app(child: _composer()));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.isExtended, isTrue);
      expect(fab.heroTag, isNull);
      expect(fab.onPressed, isNotNull);
      expect(
        tester
            .getSemantics(find.byType(FloatingActionButton))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    },
  );

  testWidgets(
    'compact presentation is one standard icon-only FAB with shared semantics',
    (tester) async {
      await tester.pumpWidget(
        _app(
          child: _composer(
            fabPresentation: ExpandableMessageComposerFabPresentation.compact,
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Capture'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.isExtended, isFalse);
      expect(fab.mini, isFalse);
      expect(fab.heroTag, isNull);
      expect(
        tester.getSize(find.byType(FloatingActionButton)),
        const Size(56, 56),
      );
      final semantics = tester
          .getSemantics(find.byType(FloatingActionButton))
          .getSemanticsData();
      expect(semantics.label, 'Open capture');
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    },
  );

  testWidgets(
    'same-key collapsed presentation updates retain State without side effects',
    (tester) async {
      var presentation = ExpandableMessageComposerFabPresentation.extended;
      final changes = <String>[];
      late StateSetter setHostState;
      await tester.pumpWidget(
        _app(
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return _composer(
                fabPresentation: presentation,
                animationDuration: Duration.zero,
                onChanged: changes.add,
              );
            },
          ),
        ),
      );
      final composerState = tester.state(
        find.byType(ExpandableMessageComposer),
      );

      for (final next in [
        ExpandableMessageComposerFabPresentation.compact,
        ExpandableMessageComposerFabPresentation.extended,
        ExpandableMessageComposerFabPresentation.compact,
        ExpandableMessageComposerFabPresentation.extended,
      ]) {
        setHostState(() => presentation = next);
        await tester.pump();
        expect(
          tester.state(find.byType(ExpandableMessageComposer)),
          same(composerState),
        );
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .isExtended,
          next == ExpandableMessageComposerFabPresentation.extended,
        );
        expect(find.byType(BottomSheet), findsNothing);
      }
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'presentation morph is continuous interruptible and curve configurable',
    (tester) async {
      var presentation = ExpandableMessageComposerFabPresentation.extended;
      var duration = const Duration(milliseconds: 400);
      var curve = Curves.linear;
      late StateSetter setHostState;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: Scaffold(
            floatingActionButton: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return _composer(
                  fabPresentation: presentation,
                  animationDuration: duration,
                  animationCurve: curve,
                );
              },
            ),
          ),
        ),
      );
      final composerState = tester.state(
        find.byType(ExpandableMessageComposer),
      );
      final extendedWidth = tester
          .getSize(find.byType(FloatingActionButton))
          .width;
      final extendedShape = tester
          .widget<RawMaterialButton>(find.byType(RawMaterialButton))
          .shape;

      setHostState(
        () => presentation = ExpandableMessageComposerFabPresentation.compact,
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(FloatingActionButton)).width,
        extendedWidth,
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.bySemanticsLabel('Open capture'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      final quarterWidth = tester
          .getSize(find.byType(FloatingActionButton))
          .width;
      expect(quarterWidth, inExclusiveRange(56, extendedWidth));
      final labelOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('Capture'), matching: find.byType(Opacity)),
      );
      expect(labelOpacity.opacity, inExclusiveRange(0, 1));
      final intermediateShape = tester
          .widget<RawMaterialButton>(find.byType(RawMaterialButton))
          .shape;
      expect(intermediateShape, isNot(equals(extendedShape)));
      expect(intermediateShape, isNot(isA<CircleBorder>()));

      setHostState(
        () => presentation = ExpandableMessageComposerFabPresentation.extended,
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(FloatingActionButton)).width,
        closeTo(quarterWidth, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final reversedWidth = tester
          .getSize(find.byType(FloatingActionButton))
          .width;
      expect(reversedWidth, greaterThan(quarterWidth));
      expect(reversedWidth, lessThan(extendedWidth));

      setHostState(() {
        duration = const Duration(milliseconds: 100);
        curve = Curves.easeOut;
      });
      await tester.pump();
      expect(
        tester.getSize(find.byType(FloatingActionButton)).width,
        closeTo(reversedWidth, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byType(FloatingActionButton)).width,
        extendedWidth,
      );
      expect(
        tester.state(find.byType(ExpandableMessageComposer)),
        same(composerState),
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
    },
  );

  testWidgets('configured curve changes sampled presentation progress', (
    tester,
  ) async {
    Future<double> midpointWidth(Curve curve, Key key) async {
      var presentation = ExpandableMessageComposerFabPresentation.extended;
      late StateSetter setHostState;
      await tester.pumpWidget(
        _app(
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return _composer(
                key: key,
                fabPresentation: presentation,
                animationDuration: const Duration(milliseconds: 200),
                animationCurve: curve,
              );
            },
          ),
        ),
      );
      setHostState(
        () => presentation = ExpandableMessageComposerFabPresentation.compact,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return tester.getSize(find.byType(FloatingActionButton)).width;
    }

    final linearWidth = await midpointWidth(
      Curves.linear,
      const ValueKey('linear'),
    );
    final easeInWidth = await midpointWidth(
      Curves.easeIn,
      const ValueKey('ease-in'),
    );
    expect(easeInWidth, greaterThan(linearWidth));
  });

  testWidgets('zero duration and reduced motion settle without later frames', (
    tester,
  ) async {
    for (final reducedMotion in [false, true]) {
      var presentation = ExpandableMessageComposerFabPresentation.extended;
      late StateSetter setHostState;
      await tester.pumpWidget(
        _app(
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return _composer(
                  key: ValueKey(reducedMotion),
                  fabPresentation: presentation,
                  animationDuration: reducedMotion
                      ? const Duration(milliseconds: 400)
                      : Duration.zero,
                );
              },
            ),
          ),
        ),
      );

      setHostState(
        () => presentation = ExpandableMessageComposerFabPresentation.compact,
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(FloatingActionButton)),
        const Size(56, 56),
      );
      expect(find.text('Capture'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getSize(find.byType(FloatingActionButton)),
        const Size(56, 56),
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
    }
  });

  testWidgets(
    'morph preserves scaffold placement anchors in LTR RTL and every location',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final direction in TextDirection.values) {
        for (final location in [
          FloatingActionButtonLocation.startFloat,
          FloatingActionButtonLocation.centerFloat,
          FloatingActionButtonLocation.endFloat,
          FloatingActionButtonLocation.startDocked,
          FloatingActionButtonLocation.centerDocked,
          FloatingActionButtonLocation.endDocked,
        ]) {
          var presentation = ExpandableMessageComposerFabPresentation.extended;
          late StateSetter setHostState;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                floatingActionButtonTheme: const FloatingActionButtonThemeData(
                  extendedIconLabelSpacing: 12,
                ),
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
                child: Directionality(
                  textDirection: direction,
                  child: Scaffold(
                    floatingActionButtonLocation: location,
                    floatingActionButton: StatefulBuilder(
                      builder: (context, setState) {
                        setHostState = setState;
                        return _composer(
                          enabled: false,
                          fabPresentation: presentation,
                          animationDuration: const Duration(milliseconds: 200),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final before = tester.getRect(find.byType(FloatingActionButton));
          setHostState(
            () =>
                presentation = ExpandableMessageComposerFabPresentation.compact,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final during = tester.getRect(find.byType(FloatingActionButton));
          final locationName = location.toString();
          if (locationName.contains('center')) {
            expect(during.center.dx, closeTo(before.center.dx, 0.01));
          } else {
            final physicallyLeft =
                locationName.contains('start') ==
                (direction == TextDirection.ltr);
            expect(
              physicallyLeft ? during.left : during.right,
              closeTo(physicallyLeft ? before.left : before.right, 0.01),
              reason: '$direction $location',
            );
          }
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(
            tester
                .getSemantics(find.byType(FloatingActionButton))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
        }
      }
    },
  );

  testWidgets('disabled FAB retains geometry and disabled semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _composer()));
    final enabledRect = tester.getRect(find.byType(FloatingActionButton));

    await tester.pumpWidget(_app(child: _composer(enabled: false)));
    final disabledRect = tester.getRect(find.byType(FloatingActionButton));
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );

    expect(disabledRect, enabledRect);
    expect(fab.onPressed, isNull);
    final semantics = tester
        .getSemantics(find.byType(FloatingActionButton))
        .getSemanticsData();
    expect(semantics.label, contains('Open capture'));
    expect(semantics.hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('FAB presents an animated Material 3 modal bottom sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(child: _composer()));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final initialTop = tester.getTopLeft(sheet).dy;
    final bottomSheet = tester.widget<BottomSheet>(sheet);
    expect(bottomSheet.enableDrag, isTrue);
    expect(bottomSheet.showDragHandle, isTrue);
    expect(
      tester.getSize(find.byType(MessageComposer)).width,
      lessThanOrEqualTo(640),
    );
    final shape = bottomSheet.shape! as RoundedRectangleBorder;
    final borderRadius = shape.borderRadius as BorderRadius;
    expect(borderRadius.topLeft.x, 28);
    expect(borderRadius.topRight.x, 28);
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .last
          .dismissible,
      isTrue,
    );

    await tester.pump(const Duration(milliseconds: 100));
    final intermediateTop = tester.getTopLeft(sheet).dy;
    await tester.pumpAndSettle();
    final settledTop = tester.getTopLeft(sheet).dy;
    expect(intermediateTop, lessThan(initialTop));
    expect(intermediateTop, greaterThan(settledTop));
  });

  testWidgets('modal composer is content on the sheet single surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          floatingActionButton: _composer(animationDuration: Duration.zero),
        ),
      ),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    final sheet = find.byType(BottomSheet);
    final composer = find.byType(MessageComposer);
    final editor = find.byType(TextField);
    expect(sheet, findsOneWidget);
    expect(
      tester.widget<BottomSheet>(sheet).backgroundColor,
      theme.colorScheme.surfaceContainerLow,
    );

    final nestedMaterials = tester.widgetList<Material>(
      find.descendant(of: composer, matching: find.byType(Material)),
    );
    expect(
      nestedMaterials.where(
        (material) =>
            material.type != MaterialType.transparency &&
            material.color != Colors.transparent,
      ),
      isEmpty,
    );
    expect(
      nestedMaterials.where(
        (material) => material.shape != null || material.borderRadius != null,
      ),
      isEmpty,
    );
    expect(
      tester.getTopLeft(editor).dx - tester.getTopLeft(sheet).dx,
      closeTo(16, 0.01),
    );
  });

  testWidgets('standard motion focuses in the first mounted sheet frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _composer()));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_editorFocus(tester).hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_editorFocus(tester).hasFocus, isTrue);
    await tester.pumpAndSettle();
    expect(_editorFocus(tester).hasFocus, isTrue);
  });

  testWidgets('zero-duration sheet focuses in the next mounted frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(child: _composer(animationDuration: Duration.zero)),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_editorFocus(tester).hasFocus, isTrue);
  });

  testWidgets('modal route excludes the background FAB semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _composer()));
    await _expand(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.bySemanticsLabel('Open capture'), findsNothing);
    expect(_editorFocus(tester).hasFocus, isTrue);
  });

  testWidgets('downward swipe collapses an empty draft and unfocuses', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _composer()));
    await _expand(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_editorFocus(tester).hasFocus, isTrue);

    await tester.drag(find.byType(MessageComposer), const Offset(0, 80));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'Unicode draft survives collapse and re-expansion byte-for-byte',
    (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(_app(child: _composer(onChanged: changes.add)));
      await _expand(tester);
      const draft = '  你好 👋\nsecond line  ';
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      await tester.drag(find.byType(MessageComposer), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(changes, [draft]);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );
      expect(
        utf8.encode(draft),
        utf8.encode(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ),
      );
    },
  );

  testWidgets('focus loss stays open while scrim tap and Escape dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(_app(child: _composer()));
    await _expand(tester);
    _editorFocus(tester).unfocus();
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(MessageComposer), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    await _expand(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('leading and trailing actions emit exact raw current text', (
    tester,
  ) async {
    final presses = <(int, String)>[];
    final changes = <String>[];
    await tester.pumpWidget(
      _app(
        child: _composer(
          buttons: const [
            MessageComposerButton(
              id: 1,
              tooltip: 'Leading action',
              position: MessageComposerButtonPosition.leading,
              child: Text('LEAD'),
            ),
            MessageComposerButton(
              id: 2,
              tooltip: 'Trailing action',
              visibility: MessageComposerButtonVisibility.whenNonEmpty,
              style: MessageComposerButtonStyle.filled,
              child: Text('SEND'),
            ),
          ],
          onChanged: changes.add,
          onButtonPressed: (id, text) => presses.add((id, text)),
        ),
      ),
    );
    await _expand(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(changes, ['   ']);
    await tester.tap(find.byTooltip('Leading action'));
    expect(presses, [(1, '   ')]);

    await tester.enterText(find.byType(TextField), ' exact 🚀 ');
    await tester.pump();
    await tester.tap(find.byTooltip('Trailing action'));
    expect(presses.last, (2, ' exact 🚀 '));
  });

  testWidgets(
    'short upward and decisive-horizontal touch drags do not collapse',
    (tester) async {
      await tester.pumpWidget(_app(child: _composer()));
      await _expand(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.drag(find.byType(MessageComposer), const Offset(0, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MessageComposer), findsOneWidget);
      await tester.drag(find.byType(MessageComposer), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MessageComposer), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MessageComposer)),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(6, 4));
      await gesture.moveBy(const Offset(0, 80));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MessageComposer), findsOneWidget);
    },
  );

  testWidgets('disablement during entrance keeps the sheet mounted and inert', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      _app(
        child: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return _composer(enabled: enabled);
          },
        ),
      ),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(BottomSheet), findsOneWidget);

    setHostState(() => enabled = false);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(_editorFocus(tester).hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_editorFocus(tester).hasFocus, isFalse);

    setHostState(() => enabled = true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(_editorFocus(tester).hasFocus, isTrue);
  });

  testWidgets(
    'saving props disable the mounted editor and action, then restore the exact draft and focus',
    (tester) async {
      var saving = false;
      late StateSetter setHostState;
      await tester.pumpWidget(
        _app(
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return _composer(
                enabled: !saving,
                buttons: [
                  MessageComposerButton(
                    id: 1,
                    tooltip: saving
                        ? 'Saving journal block'
                        : 'Save journal block',
                    style: MessageComposerButtonStyle.filled,
                    enabled: !saving,
                    child: const Text('SAVE'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await _expand(tester);
      const draft = '  保存 👩🏽‍💻 exact draft  ';
      await tester.enterText(find.byType(TextField), draft);

      setHostState(() => saving = true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.byTooltip('Save journal block'), findsNothing);
      expect(find.byTooltip('Saving journal block'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithText(IconButton, 'SAVE'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );

      setHostState(() => saving = false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(find.byTooltip('Saving journal block'), findsNothing);
      expect(find.byTooltip('Save journal block'), findsOneWidget);
      expect(_editorFocus(tester).hasFocus, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );
    },
  );

  testWidgets(
    'presentation update during the modal retains route draft controller focus and actions',
    (tester) async {
      var presentation = ExpandableMessageComposerFabPresentation.extended;
      final changes = <String>[];
      final presses = <(int, String)>[];
      late StateSetter setHostState;
      await tester.pumpWidget(
        _app(
          child: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return _composer(
                fabPresentation: presentation,
                animationDuration: Duration.zero,
                buttons: const [
                  MessageComposerButton(
                    id: 1,
                    tooltip: 'Send exact draft',
                    style: MessageComposerButtonStyle.filled,
                    child: Text('SEND'),
                  ),
                ],
                onChanged: changes.add,
                onButtonPressed: (id, text) => presses.add((id, text)),
              );
            },
          ),
        ),
      );
      final composerState = tester.state(
        find.byType(ExpandableMessageComposer),
      );
      await _expand(tester);
      const draft = '  保留 👩🏽‍💻\nexact whitespace  ';
      await tester.enterText(find.byType(TextField), draft);
      await tester.pump();
      final textField = tester.widget<TextField>(find.byType(TextField));
      final controller = textField.controller;
      final focusNode = textField.focusNode;
      final route = ModalRoute.of(tester.element(find.byType(MessageComposer)));
      expect(route, isNotNull);
      expect(focusNode!.hasFocus, isTrue);
      expect(changes, [draft]);

      setHostState(
        () => presentation = ExpandableMessageComposerFabPresentation.compact,
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.state(find.byType(ExpandableMessageComposer)),
        same(composerState),
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(MessageComposer))),
        same(route),
      );
      final updatedTextField = tester.widget<TextField>(find.byType(TextField));
      expect(updatedTextField.controller, same(controller));
      expect(updatedTextField.focusNode, same(focusNode));
      expect(updatedTextField.controller!.text, draft);
      expect(updatedTextField.focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<IconButton>(find.widgetWithText(IconButton, 'SEND'))
            .onPressed,
        isNotNull,
      );
      expect(changes, [draft]);
      expect(presses, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .isExtended,
        isFalse,
      );
      expect(find.text('Capture'), findsNothing);
    },
  );

  testWidgets('changing the widget key resets local state and draft', (
    tester,
  ) async {
    var generation = 1;
    late StateSetter setHostState;
    await tester.pumpWidget(
      _app(
        child: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return _composer(key: ValueKey(generation));
          },
        ),
      ),
    );
    await _expand(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'old draft');
    setHostState(() => generation = 2);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await _expand(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'expanded surface follows the iOS keyboard inset and returns to safe area',
    (tester) async {
      const viewport = Size(390, 844);
      const safeAreaBottom = 34.0;
      const keyboardHeight = 300.0;
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Widget host({required bool keyboardVisible}) => MediaQuery(
        data: MediaQueryData(
          size: viewport,
          padding: EdgeInsets.only(
            bottom: keyboardVisible ? 0 : safeAreaBottom,
          ),
          viewPadding: const EdgeInsets.only(bottom: safeAreaBottom),
          viewInsets: EdgeInsets.only(
            bottom: keyboardVisible ? keyboardHeight : 0,
          ),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            floatingActionButton: _composer(),
          ),
        ),
      );

      await tester.pumpWidget(host(keyboardVisible: false));
      await _expand(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      final surface = find.byType(MessageComposer);
      expect(
        tester.getBottomRight(surface).dy,
        closeTo(viewport.height - safeAreaBottom, 0.01),
      );

      await tester.pumpWidget(host(keyboardVisible: true));
      await tester.pump();
      expect(
        tester.getBottomRight(surface).dy,
        closeTo(viewport.height - keyboardHeight, 0.01),
      );

      await tester.pumpWidget(host(keyboardVisible: false));
      await tester.pump();
      expect(
        tester.getBottomRight(surface).dy,
        closeTo(viewport.height - safeAreaBottom, 0.01),
      );
    },
  );

  testWidgets(
    'narrow RTL large-text safe-area and keyboard layouts do not overflow',
    (tester) async {
      for (final direction in TextDirection.values) {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(3.2),
              padding: EdgeInsets.only(bottom: 24),
              viewInsets: EdgeInsets.only(bottom: 180),
            ),
            child: Directionality(
              textDirection: direction,
              child: MaterialApp(
                home: Scaffold(
                  body: const Align(
                    key: ValueKey('adaptive-body'),
                    alignment: Alignment.bottomCenter,
                    child: Text('FINAL BODY ROW'),
                  ),
                  floatingActionButton: _composer(
                    key: ValueKey(direction),
                    fabLabel: 'Capture a very long message',
                    animationDuration: Duration.zero,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bodyHeight = tester
            .getSize(find.byKey(const ValueKey('adaptive-body')))
            .height;
        expect(bodyHeight, greaterThan(100));
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'one\ntwo\nthree\nfour\nfive',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(BottomSheet)).width,
          lessThanOrEqualTo(320),
        );
        expect(
          tester.getBottomRight(find.byType(MessageComposer)).dy,
          lessThanOrEqualTo(640 - 180),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('adaptive-body'))).height,
          bodyHeight,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('collapsed alignment follows logical end in LTR and RTL', (
    tester,
  ) async {
    Future<double> centerFor(TextDirection direction) async {
      await tester.pumpWidget(_app(direction: direction, child: _composer()));
      return tester.getCenter(find.byType(FloatingActionButton)).dx;
    }

    final ltr = await centerFor(TextDirection.ltr);
    final rtl = await centerFor(TextDirection.rtl);
    expect(ltr, greaterThan(rtl));
  });

  testWidgets('standard registry builds ordered children and emits events', (
    tester,
  ) async {
    final props = ExpandableMessageComposerProps(
      enabled: true,
      fabPresentation: ExpandableMessageComposerFabPresentation.extended,
      fabLabel: 'Capture',
      fabTooltip: 'Open capture',
      animationDurationMilliseconds: 0,
      animationCurve: AnimationCurveValue.easeOut,
      maxLines: 5,
      hintText: 'Ask from OCaml',
      buttons: const [
        MessageComposerButtonProps(
          id: 7,
          tooltip: 'OCaml action',
          position: MessageComposerButtonPosition.trailing,
          visibility: MessageComposerButtonVisibility.always,
          style: MessageComposerButtonStyle.filled,
          enabled: true,
        ),
      ],
    );
    final store = _nativeStore(
      props,
      children: const [(2, 'OCAML ICON'), (3, 'OCAML ACTION')],
    );
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(),
            onEvent: events.add,
          ),
        ),
      ),
    );
    expect(find.byType(UnsupportedNativeWidget), findsNothing);
    expect(find.text('OCAML ICON'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.text('OCAML ACTION'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  native 🚀  ');
    await tester.tap(find.byTooltip('OCaml action'));

    expect(events, hasLength(2));
    final changed = events[0].payload as NativeEventPayload;
    expect(changed.kindId, NativeWidgetKind.expandableMessageComposer);
    expect(changed.eventId, ExpandableMessageComposerEvent.textChanged);
    expect(utf8.decode(changed.payload), '  native 🚀  ');
    final pressed = events[1].payload as NativeEventPayload;
    expect(pressed.eventId, ExpandableMessageComposerEvent.buttonPressed);
    final payload = Uint8List.fromList(pressed.payload);
    expect(ByteData.sublistView(payload).getUint32(0, Endian.little), 7);
    expect(utf8.decode(payload.sublist(4)), '  native 🚀  ');
  });

  testWidgets(
    'registry presentation-only UpdateProps retains the same composer State',
    (tester) async {
      ExpandableMessageComposerProps propsFor(
        ExpandableMessageComposerFabPresentation presentation,
      ) => ExpandableMessageComposerProps(
        enabled: true,
        fabPresentation: presentation,
        fabLabel: 'Capture',
        fabTooltip: 'Open capture',
        animationDurationMilliseconds: 0,
        animationCurve: AnimationCurveValue.easeOut,
        maxLines: 5,
        hintText: 'Ask from OCaml',
        buttons: const [],
      );

      final extended = propsFor(
        ExpandableMessageComposerFabPresentation.extended,
      );
      final compact = propsFor(
        ExpandableMessageComposerFabPresentation.compact,
      );
      final store = _nativeStore(extended, children: const [(2, 'OCAML ICON')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: BonsaiFlutterView(
              store: store,
              registry: WidgetRegistry.standard(),
            ),
          ),
        ),
      );
      final composerState = tester.state(
        find.byType(ExpandableMessageComposer),
      );
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .isExtended,
        isTrue,
      );

      store.apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: store.revision,
          targetRevision: store.revision + 1,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(nodeId: 1, props: compact.toNativeWidgetProps()),
          ],
        ),
      );
      await tester.pump();

      expect(
        tester.state(find.byType(ExpandableMessageComposer)),
        same(composerState),
      );
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .isExtended,
        isFalse,
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
    },
  );

  testWidgets('registry accepts only schema version 2', (tester) async {
    final props = ExpandableMessageComposerProps(
      enabled: true,
      fabPresentation: ExpandableMessageComposerFabPresentation.extended,
      fabLabel: 'Capture',
      fabTooltip: 'Open capture',
      animationDurationMilliseconds: 0,
      animationCurve: AnimationCurveValue.easeOut,
      maxLines: 5,
      hintText: '',
      buttons: const [],
    );
    expect(props.toNativeWidgetProps().version, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: _nativeStore(
            props,
            children: const [(2, 'OCAML ICON')],
            schemaVersion: 1,
          ),
          registry: WidgetRegistry.standard(),
        ),
      ),
    );
    expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    expect(find.textContaining('version 1'), findsOneWidget);
  });

  testWidgets('registry rejects child-count mismatch', (tester) async {
    final props = ExpandableMessageComposerProps(
      enabled: true,
      fabPresentation: ExpandableMessageComposerFabPresentation.extended,
      fabLabel: 'Capture',
      fabTooltip: 'Open capture',
      animationDurationMilliseconds: 200,
      animationCurve: AnimationCurveValue.easeOut,
      maxLines: 5,
      hintText: '',
      buttons: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: _nativeStore(props, children: const []),
          registry: WidgetRegistry.standard(),
        ),
      ),
    );
    expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    expect(find.textContaining('exactly 1 children'), findsOneWidget);
  });

  test(
    'props round trip Unicode metadata and validate all wire boundaries',
    () {
      const props = ExpandableMessageComposerProps(
        enabled: false,
        fabPresentation: ExpandableMessageComposerFabPresentation.compact,
        fabLabel: '捕获 ✨',
        fabTooltip: '打开 🚀',
        animationDurationMilliseconds: 65535,
        animationCurve: AnimationCurveValue.easeInOut,
        maxLines: 65535,
        hintText: '写点什么 👋',
        buttons: [
          MessageComposerButtonProps(
            id: 0xffffffff,
            tooltip: '发送 🚀',
            position: MessageComposerButtonPosition.leading,
            visibility: MessageComposerButtonVisibility.whenNonEmpty,
            style: MessageComposerButtonStyle.filled,
            enabled: false,
          ),
        ],
      );
      expect(ExpandableMessageComposerProps.decode(props.encode()), props);
      expect(props.encode()[20], 1);
      expect(
        props,
        isNot(
          const ExpandableMessageComposerProps(
            enabled: false,
            fabPresentation: ExpandableMessageComposerFabPresentation.extended,
            fabLabel: '捕获 ✨',
            fabTooltip: '打开 🚀',
            animationDurationMilliseconds: 65535,
            animationCurve: AnimationCurveValue.easeInOut,
            maxLines: 65535,
            hintText: '写点什么 👋',
            buttons: [
              MessageComposerButtonProps(
                id: 0xffffffff,
                tooltip: '发送 🚀',
                position: MessageComposerButtonPosition.leading,
                visibility: MessageComposerButtonVisibility.whenNonEmpty,
                style: MessageComposerButtonStyle.filled,
                enabled: false,
              ),
            ],
          ),
        ),
      );
      final valid = props.encode();
      final malformed = <Uint8List>[
        Uint8List(23),
        Uint8List.fromList(valid)..[0] = 2,
        Uint8List.fromList(valid)..[1] = 4,
        Uint8List.fromList(valid)
          ..[4] = 0
          ..[5] = 0,
        Uint8List.fromList(valid)..[20] = 2,
        Uint8List.fromList(valid)..[21] = 1,
        Uint8List.fromList(valid)..[22] = 1,
        Uint8List.fromList(valid)..[23] = 1,
        Uint8List.fromList(valid)..[24] = 0xff,
        Uint8List.fromList([...valid, 0]),
        Uint8List.fromList(valid.sublist(0, valid.length - 1)),
      ];
      for (final payload in malformed) {
        expect(
          () => ExpandableMessageComposerProps.decode(payload),
          throwsFormatException,
        );
      }
      expect(
        () => ExpandableMessageComposerProps(
          enabled: true,
          fabPresentation: ExpandableMessageComposerFabPresentation.extended,
          fabLabel: '',
          fabTooltip: '',
          animationDurationMilliseconds: -1,
          animationCurve: AnimationCurveValue.easeOut,
          maxLines: 0,
          hintText: '',
          buttons: const [],
        ).encode(),
        throwsArgumentError,
      );
    },
  );

  test('direct widget rejects invalid public constructor values', () {
    expect(
      () => ExpandableMessageComposer(
        fabPresentation: ExpandableMessageComposerFabPresentation.extended,
        fabLabel: '',
        fabTooltip: 'Open',
        fabIcon: const Icon(Icons.add),
        buttons: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => ExpandableMessageComposer(
        fabPresentation: ExpandableMessageComposerFabPresentation.extended,
        fabLabel: 'Capture',
        fabTooltip: '',
        fabIcon: const Icon(Icons.add),
        animationDuration: const Duration(microseconds: -1),
        buttons: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => ExpandableMessageComposer(
        fabPresentation: ExpandableMessageComposerFabPresentation.extended,
        fabLabel: 'Capture',
        fabTooltip: 'Open',
        fabIcon: const Icon(Icons.add),
        maxLines: 0,
        buttons: const [],
      ),
      throwsArgumentError,
    );
  });
}

ExpandableMessageComposer _composer({
  Key? key = _outerKey,
  bool enabled = true,
  ExpandableMessageComposerFabPresentation fabPresentation =
      ExpandableMessageComposerFabPresentation.extended,
  String fabLabel = 'Capture',
  Duration animationDuration = const Duration(milliseconds: 200),
  Curve animationCurve = Curves.easeOut,
  List<MessageComposerButton> buttons = const [],
  ValueChanged<String>? onChanged,
  MessageComposerButtonCallback? onButtonPressed,
}) => ExpandableMessageComposer(
  key: key,
  enabled: enabled,
  fabPresentation: fabPresentation,
  fabLabel: fabLabel,
  fabTooltip: 'Open capture',
  fabIcon: const Icon(Icons.add),
  animationDuration: animationDuration,
  animationCurve: animationCurve,
  maxLines: 5,
  hintText: 'Ask anything',
  buttons: buttons,
  onChanged: onChanged,
  onButtonPressed: onButtonPressed,
);

Widget _app({
  required Widget child,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(floatingActionButton: child),
  ),
);

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

FocusNode _editorFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!;

NodeStore _nativeStore(
  ExpandableMessageComposerProps props, {
  required List<(int, String)> children,
  int? schemaVersion,
}) {
  final encodedProps = props.toNativeWidgetProps();
  final nativeProps = schemaVersion == null
      ? encodedProps
      : NativeWidgetProps(
          kindId: encodedProps.kindId,
          version: schemaVersion,
          capabilityBits: encodedProps.capabilityBits,
          payload: encodedProps.payload,
        );
  final operations = <FrameOperation>[
    const SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
    CreateNode(
      nodeId: 1,
      kind: NodeKind.nativeWidget,
      props: nativeProps,
      eventBindings: const [
        EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 9),
      ],
    ),
    for (final (id, text) in children)
      CreateNode(
        nodeId: id,
        kind: NodeKind.text,
        props: TextProps(text),
        eventBindings: const [],
      ),
    SetChildren(nodeId: 1, children: [for (final (id, _) in children) id]),
    const SetRoot(1),
  ];
  return NodeStore()..apply(
    Frame(
      runtimeEpoch: 1,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: operations,
    ),
  );
}
