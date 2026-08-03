import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _linearTransition = SparseExtentTransitionSpec(
  expandDuration: Duration(milliseconds: 200),
  collapseDuration: Duration(milliseconds: 200),
  expandCurve: SparseExtentTransitionCurve.linear,
  collapseCurve: SparseExtentTransitionCurve.linear,
);

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

  group('SparseExtentListHost transitions', () {
    testWidgets(
      'interpolates extent, moves later rows, and reports only the settled range',
      (tester) async {
        final controller = ScrollController();
        final props = ValueNotifier(_props());
        final ranges = <({int firstIndex, int lastExclusive})>[];

        await _pumpSparseHost(
          tester,
          props: props,
          controller: controller,
          emit: (eventId, payload) {
            if (eventId == VirtualListEvent.visibleRangeChanged) {
              ranges.add(VirtualListEvent.decodeVisibleRange(payload));
            }
          },
        );
        ranges.clear();
        final initialLaterTop = tester.getTopLeft(_item(3)).dy;

        props.value = _props(
          overrides: const [ExtentOverride(index: 2, extent: 120)],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.getSize(_item(2)).height, closeTo(80, 1));
        expect(
          tester.getTopLeft(_item(3)).dy,
          closeTo(initialLaterTop + 40, 1),
        );
        expect(ranges, isEmpty);

        await tester.pump(const Duration(milliseconds: 110));
        await tester.pump();
        expect(tester.getSize(_item(2)).height, 120);
        expect(ranges, hasLength(1));

        props.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      'animates accordion indexes together and anchors the newly expanded row',
      (tester) async {
        final controller = ScrollController();
        final props = ValueNotifier(
          _props(overrides: const [ExtentOverride(index: 1, extent: 120)]),
        );

        await _pumpSparseHost(
          tester,
          props: props,
          controller: controller,
          viewportHeight: 180,
        );
        controller.jumpTo(140);
        await tester.pump();
        final anchoredTop = tester.getTopLeft(_item(3)).dy;

        props.value = _props(
          overrides: const [ExtentOverride(index: 3, extent: 120)],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(tester.getSize(_item(1)).height, closeTo(80, 1));
        expect(tester.getSize(_item(3)).height, closeTo(80, 1));
        expect(tester.getTopLeft(_item(3)).dy, closeTo(anchoredTop, 1));

        await tester.pump(const Duration(milliseconds: 110));
        expect(tester.getSize(_item(3)).height, 120);

        props.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      'retargets from the current extent after a mid-flight reversal',
      (tester) async {
        final controller = ScrollController();
        final props = ValueNotifier(_props());
        await _pumpSparseHost(tester, props: props, controller: controller);

        props.value = _props(
          overrides: const [ExtentOverride(index: 2, extent: 120)],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final interruptedExtent = tester.getSize(_item(2)).height;
        expect(interruptedExtent, closeTo(60, 1));

        props.value = _props();
        await tester.pump();
        expect(tester.getSize(_item(2)).height, closeTo(interruptedExtent, 1));

        await tester.pump(const Duration(milliseconds: 100));
        final reversingExtent = tester.getSize(_item(2)).height;
        expect(reversingExtent, greaterThan(40));
        expect(reversingExtent, lessThan(interruptedExtent));

        await tester.pump(const Duration(milliseconds: 110));
        expect(tester.getSize(_item(2)).height, 40);

        props.dispose();
        controller.dispose();
      },
    );

    testWidgets('releases the preferred anchor when direct scrolling starts', (
      tester,
    ) async {
      final controller = ScrollController();
      final props = ValueNotifier(
        _props(overrides: const [ExtentOverride(index: 1, extent: 120)]),
      );
      await _pumpSparseHost(tester, props: props, controller: controller);
      controller.jumpTo(100);
      await tester.pump();

      props.value = _props(
        overrides: const [ExtentOverride(index: 3, extent: 120)],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final beforeDrag = controller.offset;

      await tester.drag(find.byType(Scrollable), const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.offset, greaterThan(beforeDrag + 20));

      props.dispose();
      controller.dispose();
    });

    testWidgets('reduced motion resolves extent changes immediately', (
      tester,
    ) async {
      final controller = ScrollController();
      final props = ValueNotifier(_props());
      await _pumpSparseHost(
        tester,
        props: props,
        controller: controller,
        disableAnimations: true,
      );

      props.value = _props(
        overrides: const [ExtentOverride(index: 2, extent: 120)],
      );
      await tester.pump();

      expect(tester.getSize(_item(2)).height, 120);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(_item(2)).height, 120);

      props.dispose();
      controller.dispose();
    });

    testWidgets('disposes its ticker when removed during a transition', (
      tester,
    ) async {
      final controller = ScrollController();
      final props = ValueNotifier(_props());
      await _pumpSparseHost(tester, props: props, controller: controller);

      props.value = _props(
        overrides: const [ExtentOverride(index: 2, extent: 120)],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      props.dispose();
      controller.dispose();
    });
  });

  group('MorphingSurfaceHost', () {
    testWidgets('reaches exact compact and expanded surface endpoints', (
      tester,
    ) async {
      await _pumpMorph(tester, progress: 0, expanded: false);
      expect(find.text('Shared header'), findsOneWidget);
      expect(find.text('Compact preview'), findsOneWidget);
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
      expect(find.text('Compact preview'), findsNothing);
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

SparseExtentListProps _props({List<ExtentOverride> overrides = const []}) =>
    SparseExtentListProps(
      totalCount: 8,
      firstIndex: 0,
      defaultItemExtent: 40,
      extentOverrides: overrides,
      overscan: 2,
      axis: ScrollAxis.vertical,
      transition: _linearTransition,
    );

ValueKey<String> _rowKey(int index) => ValueKey('transition-row-$index');

Finder _item(int index) => find.byKey(SparseExtentListHost.itemKey(index));

Future<void> _pumpSparseHost(
  WidgetTester tester, {
  required ValueNotifier<SparseExtentListProps> props,
  required ScrollController controller,
  NativeEventEmitter? emit,
  double viewportHeight = 200,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: disableAnimations,
          accessibleNavigation: disableAnimations,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: viewportHeight,
            child: ValueListenableBuilder(
              valueListenable: props,
              builder: (context, value, _) => SparseExtentListHost(
                props: value,
                controller: controller,
                emit: emit,
                children: List.generate(
                  8,
                  (index) => ColoredBox(
                    key: _rowKey(index),
                    color: index.isEven ? Colors.white : Colors.grey,
                    child: Text('Row $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
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
