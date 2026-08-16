import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/native_widget/sparse_extent_transition_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('morphing surface props round trip and reject malformed payloads', () {
    const props = MorphingSurfaceProps(expanded: true);
    final native = props.toNativeWidgetProps();
    expect(native.kindId, NativeWidgetKind.morphingSurface);
    expect(native.version, 1);
    expect(native.payload, hasLength(4));
    expect(MorphingSurfaceProps.decode(native.payload), props);

    expect(
      () => MorphingSurfaceProps.decode(Uint8List.fromList([2, 0, 0, 0])),
      throwsFormatException,
    );
    expect(
      () => MorphingSurfaceProps.decode(Uint8List.fromList([1, 0, 0])),
      throwsFormatException,
    );
    expect(
      () => MorphingSurfaceProps.decode(Uint8List.fromList([1, 1, 0, 0])),
      throwsFormatException,
    );
  });

  test('sparse extent transition and curve types from frame.dart', () {
    const transition = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 240,
      collapseDurationMs: 190,
      expandCurve: SparseExtentCurve.easeOutCubic,
      collapseCurve: SparseExtentCurve.easeInOutCubic,
    );
    expect(transition.enabled, isTrue);
    expect(transition.expandDurationMs, 240);
    expect(transition.collapseDurationMs, 190);
    expect(transition.expandCurve, SparseExtentCurve.easeOutCubic);
    expect(transition.collapseCurve, SparseExtentCurve.easeInOutCubic);

    // Equality
    const same = SparseExtentTransition(
      enabled: true,
      expandDurationMs: 240,
      collapseDurationMs: 190,
      expandCurve: SparseExtentCurve.easeOutCubic,
      collapseCurve: SparseExtentCurve.easeInOutCubic,
    );
    expect(transition, same);
    expect(transition.hashCode, same.hashCode);

    // Curve wire ids
    expect(SparseExtentCurve.linear.wireId, 0);
    expect(SparseExtentCurve.easeOutCubic.wireId, 4);
    expect(
      SparseExtentCurve.fromWireId(SparseExtentCurve.easeInOutCubic.wireId),
      SparseExtentCurve.easeInOutCubic,
    );
    expect(() => SparseExtentCurve.fromWireId(99), throwsFormatException);
  });

  testWidgets('SparseExtentTransitionScope provides inherited values', (
    tester,
  ) async {
    late SparseExtentTransitionScope? captured;
    await tester.pumpWidget(
      SparseExtentTransitionScope(
        progress: 0.5,
        expanded: true,
        compactExtent: 40,
        expandedExtent: 120,
        child: Builder(
          builder: (context) {
            captured = SparseExtentTransitionScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured, isNotNull);
    expect(captured!.progress, 0.5);
    expect(captured!.expanded, isTrue);
    expect(captured!.compactExtent, 40);
    expect(captured!.expandedExtent, 120);
  });

  group('MorphingSurfaceHost', () {
    testWidgets('reaches exact compact and expanded surface endpoints', (
      tester,
    ) async {
      await _pumpMorph(tester, progress: 0, expanded: false);
      expect(find.text('Shared header'), findsOneWidget);
      expect(find.text('Expanded details'), findsNothing);
      var padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(MorphingSurfaceHost),
          matching: find.byType(Padding),
        ),
      );
      var material = tester.widget<Material>(
        find.descendant(
          of: find.byType(MorphingSurfaceHost),
          matching: find.byType(Material),
        ),
      );
      expect(padding.padding, EdgeInsets.zero);
      expect(material.elevation, 0);
      expect(material.borderRadius, BorderRadius.zero);

      await _pumpMorph(tester, progress: 1, expanded: true);
      expect(find.text('Shared header'), findsOneWidget);
      expect(find.text('Expanded details'), findsOneWidget);
      padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(MorphingSurfaceHost),
          matching: find.byType(Padding),
        ),
      );
      material = tester.widget<Material>(
        find.descendant(
          of: find.byType(MorphingSurfaceHost),
          matching: find.byType(Material),
        ),
      );
      expect(
        padding.padding,
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      );
      expect(material.elevation, 3);
      expect(material.borderRadius, BorderRadius.circular(16));
    });

    testWidgets(
      'finishes the corner radius in the first half of the transition',
      (tester) async {
        await _pumpMorph(tester, progress: 0.25, expanded: true);
        var material = tester.widget<Material>(
          find.descendant(
            of: find.byType(MorphingSurfaceHost),
            matching: find.byType(Material),
          ),
        );

        expect(material.borderRadius, BorderRadius.circular(8));
        expect(material.elevation, 0.75);
        expect(
          _surfacePadding(tester),
          const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        );

        await _pumpMorph(tester, progress: 0.5, expanded: true);
        material = tester.widget<Material>(
          find.descendant(
            of: find.byType(MorphingSurfaceHost),
            matching: find.byType(Material),
          ),
        );

        expect(material.borderRadius, BorderRadius.circular(16));
        expect(material.elevation, 1.5);
        expect(
          _surfacePadding(tester),
          const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        );
      },
    );

    testWidgets(
      'paints parent-driven surface decoration without a second animation',
      (tester) async {
        await _pumpMorph(tester, progress: 0, expanded: false);
        await _pumpMorph(tester, progress: 0.5, expanded: true);

        final physicalShape = tester.widget<PhysicalShape>(
          find.descendant(
            of: find.byType(MorphingSurfaceHost),
            matching: find.byType(PhysicalShape),
          ),
        );
        final paintedShape =
            (physicalShape.clipper as ShapeBorderClipper).shape
                as RoundedRectangleBorder;

        expect(paintedShape.borderRadius, BorderRadius.circular(16));
        expect(physicalShape.elevation, 1.5);
      },
    );

    testWidgets(
      'keeps outgoing visuals but gates their input and semantics during transition',
      (tester) async {
        var compactTaps = 0;
        var expandedTaps = 0;
        final semantics = tester.ensureSemantics();

        await _pumpMorph(
          tester,
          progress: 0.5,
          expanded: true,
          compact: Semantics(
            label: 'Compact action',
            child: GestureDetector(
              key: const ValueKey('compact-action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => compactTaps += 1,
              child: const SizedBox(height: 40, child: Text('Compact preview')),
            ),
          ),
          expandedContent: Semantics(
            label: 'Expanded action',
            child: GestureDetector(
              key: const ValueKey('expanded-action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => expandedTaps += 1,
              child: const SizedBox(
                height: 40,
                child: Text('Expanded details'),
              ),
            ),
          ),
        );

        expect(find.text('Compact preview'), findsOneWidget);
        expect(find.text('Expanded details'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('compact-action')))
              .label,
          isNot(contains('Compact action')),
        );
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('expanded-action')))
              .label,
          contains('Expanded action'),
        );
        await tester.tap(
          find.byKey(const ValueKey('compact-action')),
          warnIfMissed: false,
        );
        expect(compactTaps, 0);
        final expandedTapsBeforeTargetTap = expandedTaps;
        await tester.tap(find.byKey(const ValueKey('expanded-action')));
        expect(compactTaps, 0);
        expect(expandedTaps, expandedTapsBeforeTargetTap + 1);

        semantics.dispose();
      },
    );

    testWidgets('mid-flight direction reversal stays continuous', (
      tester,
    ) async {
      await _pumpMorph(tester, progress: 0.65, expanded: false);
      final before = _surfacePadding(tester);
      expect(find.text('Compact preview'), findsOneWidget);
      expect(find.text('Expanded details'), findsOneWidget);

      await _pumpMorph(tester, progress: 0.6, expanded: true);
      final after = _surfacePadding(tester);
      expect(find.text('Compact preview'), findsOneWidget);
      expect(find.text('Expanded details'), findsOneWidget);
      expect((before.horizontal - after.horizontal).abs(), lessThan(1));
      expect(after.horizontal, isNot(anyOf(0, 16)));
    });

    testWidgets('reduced motion exposes only the committed target', (
      tester,
    ) async {
      await _pumpMorph(
        tester,
        progress: 0.4,
        expanded: true,
        disableAnimations: true,
      );

      expect(find.text('Compact preview'), findsNothing);
      expect(find.text('Expanded details'), findsOneWidget);
      expect(
        _surfacePadding(tester),
        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      );
    });
  });
}

Future<void> _pumpMorph(
  WidgetTester tester, {
  required double progress,
  required bool expanded,
  bool disableAnimations = false,
  Widget compact = const Text('Compact preview'),
  Widget expandedContent = const Text('Expanded details'),
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        disableAnimations: disableAnimations,
        accessibleNavigation: disableAnimations,
      ),
      child: Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: MorphingSurfaceHost(
            progress: progress,
            expanded: expanded,
            sharedContent: const Text('Shared header'),
            compactContent: compact,
            expandedContent: expandedContent,
            collapsedStyle: const MorphingSurfaceStyle(),
            expandedStyle: const MorphingSurfaceStyle(
              horizontalInset: 8,
              verticalInset: 6,
              cornerRadius: 16,
              elevation: 3,
            ),
          ),
        ),
      ),
    ),
  ),
);

EdgeInsets _surfacePadding(WidgetTester tester) =>
    tester
            .widget<Padding>(
              find.descendant(
                of: find.byType(MorphingSurfaceHost),
                matching: find.byType(Padding),
              ),
            )
            .padding
        as EdgeInsets;
