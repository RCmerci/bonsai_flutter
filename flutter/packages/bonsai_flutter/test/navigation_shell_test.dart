import 'fixture.dart';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shellKind = 3;
const _scrollableBodyKey = ValueKey('scrollable-body');
const _animatedBottomNavigationKey = ValueKey('animated-bottom-navigation');

void main() {
  testWidgets('retains destination bodies and fixes bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _pumpShell(tester);
    final primaryElement = tester.element(find.text('Primary body'));
    final bottomBefore = tester.getBottomLeft(find.text('Bottom navigation'));

    fixture.update(selectedIndex: 1);
    await tester.pump();

    expect(find.text('Secondary body'), findsOneWidget);
    expect(find.text('Primary body'), findsNothing);
    expect(
      identical(
        tester.element(find.text('Primary body', skipOffstage: false)),
        primaryElement,
      ),
      isTrue,
    );
    expect(tester.getBottomLeft(find.text('Bottom navigation')), bottomBefore);
    expect(bottomBefore.dy, lessThanOrEqualTo(844));
  });

  testWidgets('bottom navigation hover matches the app corner radius', (
    tester,
  ) async {
    const destinationKey = ValueKey('destination');
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationShellHost(
          props: const NavigationShellProps(
            selectedIndex: 0,
            destinationCount: 1,
            drawerOpen: false,
            drawerEnabled: false,
          ),
          emit: null,
          bodies: const [SizedBox.shrink()],
          drawer: const SizedBox.shrink(),
          bottomNavigation: TextButton(
            key: destinationKey,
            onPressed: _ignorePress,
            child: const Text('Destination'),
          ),
        ),
      ),
    );

    final context = tester.element(find.byKey(destinationKey));
    final shape = TextButtonTheme.of(
      context,
    ).style?.shape?.resolve({WidgetState.hovered});

    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
  });

  testWidgets('delegates the bottom safe area to navigation content', (
    tester,
  ) async {
    const navigationKey = ValueKey('bottom-navigation');
    await tester.pumpWidget(
      const MaterialApp(
        home: NavigationShellHost(
          props: NavigationShellProps(
            selectedIndex: 0,
            destinationCount: 1,
            drawerOpen: false,
            drawerEnabled: false,
          ),
          emit: null,
          bodies: [SizedBox.shrink()],
          drawer: SizedBox.shrink(),
          bottomNavigation: SizedBox(
            key: navigationKey,
            height: 64,
            child: Text('Bottom navigation'),
          ),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.byKey(navigationKey),
        matching: find.byType(SafeArea),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'vertical scroll toward the end hides and toward the start restores the bar',
    (tester) async {
      final fixture = await _pumpScrollableShell(tester);
      final initialTop = tester.getTopLeft(
        find.byKey(_animatedBottomNavigationKey),
      );

      await tester.drag(find.byKey(_scrollableBodyKey), const Offset(0, -240));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getTopLeft(find.byKey(_animatedBottomNavigationKey)).dy,
        greaterThan(initialTop.dy),
        reason: 'bottom navigation did not animate toward the screen edge',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(_animatedBottomNavigationKey)).dy,
        844,
      );
      expect(fixture.emissions, isEmpty, reason: 'scrolling crossed FFI');

      await tester.drag(find.byKey(_scrollableBodyKey), const Offset(0, 240));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(_animatedBottomNavigationKey)),
        initialTop,
      );
      expect(fixture.emissions, isEmpty, reason: 'scrolling crossed FFI');
    },
  );

  testWidgets('requires 16 logical pixels in one direction before hiding', (
    tester,
  ) async {
    await _pumpScrollableShell(tester);
    final navigation = find.byKey(_animatedBottomNavigationKey);
    final initialTop = tester.getTopLeft(navigation);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(_scrollableBodyKey),
        matching: find.byType(Scrollable),
      ),
    );

    _dispatchUserScrollStart(scrollable);
    _dispatchUserScrollUpdate(scrollable, 15);
    await tester.pump();
    expect(tester.getTopLeft(navigation), initialTop);

    _dispatchUserScrollUpdate(scrollable, -1);
    _dispatchUserScrollUpdate(scrollable, 1);
    _dispatchUserScrollUpdate(scrollable, 14);
    await tester.pump();
    expect(
      tester.getTopLeft(navigation),
      initialTop,
      reason: 'a direction change did not reset the accumulated distance',
    );

    _dispatchUserScrollUpdate(scrollable, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getTopLeft(navigation).dy,
      greaterThan(initialTop.dy),
      reason: '16 logical pixels did not start the hide animation',
    );
  });

  testWidgets('horizontal scrolling does not hide the bottom navigation', (
    tester,
  ) async {
    await _pumpScrollableShell(tester, axis: Axis.horizontal);
    final initialTop = tester.getTopLeft(
      find.byKey(_animatedBottomNavigationKey),
    );

    await tester.drag(find.byKey(_scrollableBodyKey), const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(_animatedBottomNavigationKey)),
      initialTop,
    );
  });

  testWidgets('reduced motion changes bottom navigation visibility instantly', (
    tester,
  ) async {
    await _pumpScrollableShell(tester, disableAnimations: true);

    await tester.drag(find.byKey(_scrollableBodyKey), const Offset(0, -240));
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(_animatedBottomNavigationKey)).dy, 844);
  });

  testWidgets(
    'leading-edge drawer tracks locally and emits only settled state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = await _pumpShell(tester);

      final gesture = await tester.startGesture(const Offset(5, 220));
      await gesture.moveBy(const Offset(180, 0));
      await tester.pump();
      expect(fixture.events, isEmpty, reason: 'drawer deltas crossed FFI');
      expect(find.text('Drawer content'), findsOneWidget);
      await gesture.moveBy(const Offset(150, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_drawerStates(fixture.events), [1]);
      expect(find.byType(ModalBarrier), findsWidgets);

      fixture.events.clear();
      await tester.tapAt(const Offset(380, 220));
      await tester.pumpAndSettle();
      expect(_drawerStates(fixture.events), [0]);
    },
  );

  testWidgets(
    'requested open, system Back, and disabled drawer stay synchronized',
    (tester) async {
      final fixture = await _pumpShell(tester, drawerOpen: true);
      await tester.pumpAndSettle();
      expect(find.text('Drawer content'), findsOneWidget);
      expect(_drawerStates(fixture.events), [1]);

      fixture.events.clear();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_drawerStates(fixture.events), [0]);

      fixture.update(drawerEnabled: false, drawerOpen: false);
      await tester.pumpAndSettle();
      fixture.events.clear();
      final gesture = await tester.startGesture(const Offset(5, 220));
      await gesture.moveBy(const Offset(300, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fixture.events, isEmpty);
      expect(find.text('Drawer content'), findsNothing);
    },
  );

  testWidgets('RTL mirrors the drawer edge and direction', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _pumpShell(tester, textDirection: TextDirection.rtl);

    final gesture = await tester.startGesture(const Offset(385, 220));
    await gesture.moveBy(const Offset(-320, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_drawerStates(fixture.events), [1]);
  });

  testWidgets('rejects malformed props and child counts', (tester) async {
    for (final payload in <Uint8List>[
      Uint8List(11),
      _shellPayload(destinationCount: 0),
      _shellPayload(destinationCount: 2, selectedIndex: 2),
      _shellPayload(destinationCount: 2)..[1] = 1,
    ]) {
      final fixture = _ShellFixture(
        payload: payload,
        childCount: 4,
        textDirection: TextDirection.ltr,
      );
      await tester.pumpWidget(fixture.widget);
      expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    }
    for (final childCount in [0, 1, 3, 5]) {
      final fixture = _ShellFixture(
        payload: _shellPayload(destinationCount: 2),
        childCount: childCount,
        textDirection: TextDirection.ltr,
      );
      await tester.pumpWidget(fixture.widget);
      expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    }
  });

  testWidgets('dropping an open shell has no late lifecycle work', (
    tester,
  ) async {
    await _pumpShell(tester, drawerOpen: true);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

void _ignorePress() {}

List<int> _drawerStates(List<RendererEvent> events) => [
  for (final event in events)
    if (event.payload case final NativeEventPayload payload)
      if (payload.kindId == _shellKind && payload.eventId == 1)
        payload.payload.single,
];

Future<_ShellFixture> _pumpShell(
  WidgetTester tester, {
  bool drawerOpen = false,
  bool drawerEnabled = true,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  final fixture = _ShellFixture(
    payload: _shellPayload(
      destinationCount: 2,
      drawerOpen: drawerOpen,
      drawerEnabled: drawerEnabled,
    ),
    childCount: 4,
    textDirection: textDirection,
  );
  await tester.pumpWidget(fixture.widget);
  await tester.pump();
  return fixture;
}

Future<_ScrollableShellFixture> _pumpScrollableShell(
  WidgetTester tester, {
  Axis axis = Axis.vertical,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _ScrollableShellFixture(
    axis: axis,
    disableAnimations: disableAnimations,
  );
  await tester.pumpWidget(fixture.widget);
  await tester.pump();
  return fixture;
}

void _dispatchUserScrollStart(ScrollableState scrollable) {
  ScrollStartNotification(
    metrics: scrollable.position,
    context: scrollable.context,
    dragDetails: DragStartDetails(),
  ).dispatch(scrollable.context);
}

void _dispatchUserScrollUpdate(ScrollableState scrollable, double delta) {
  ScrollUpdateNotification(
    metrics: scrollable.position,
    context: scrollable.context,
    dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
    scrollDelta: delta,
  ).dispatch(scrollable.context);
}

Uint8List _shellPayload({
  required int destinationCount,
  int selectedIndex = 0,
  bool drawerOpen = false,
  bool drawerEnabled = true,
}) {
  final data = ByteData(12)
    ..setUint8(0, (drawerOpen ? 1 : 0) | (drawerEnabled ? 2 : 0))
    ..setUint32(4, selectedIndex, Endian.little)
    ..setUint32(8, destinationCount, Endian.little);
  return data.buffer.asUint8List();
}

final class _ShellFixture {
  _ShellFixture({
    required this.payload,
    required this.childCount,
    required this.textDirection,
  }) {
    _rebuildStore();
  }

  Uint8List payload;
  final int childCount;
  final TextDirection textDirection;
  final events = <RendererEvent>[];
  late NodeStore store;

  Widget get widget => MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: BonsaiFlutterView(store: store, onEvent: events.add),
    ),
  );

  void update({int? selectedIndex, bool? drawerOpen, bool? drawerEnabled}) {
    final current = ByteData.sublistView(payload);
    final flags = current.getUint8(0);
    payload = _shellPayload(
      destinationCount: current.getUint32(8, Endian.little),
      selectedIndex: selectedIndex ?? current.getUint32(4, Endian.little),
      drawerOpen: drawerOpen ?? (flags & 1) != 0,
      drawerEnabled: drawerEnabled ?? (flags & 2) != 0,
    );
    store.apply(
      Frame(
        runtimeEpoch: 1,
        baseRevision: store.revision,
        targetRevision: store.revision + 1,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 1, props: _nativeProps())],
      ),
    );
  }

  void _rebuildStore() {
    final labels = [
      'Primary body',
      'Secondary body',
      'Drawer content',
      'Bottom navigation',
    ];
    final children = List.generate(
      childCount,
      (index) => CreateNode(
        nodeId: index + 2,
        kind: NodeKind.text,
        props: TextProps(index < labels.length ? labels[index] : 'Extra'),
        eventBindings: const [],
      ),
    );
    store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const SetApplicationTheme(
              title: 'Test',
              theme: testApplicationTheme,
            ),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.nativeWidget,
              props: _nativeProps(),
              eventBindings: const [
                EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 11),
              ],
            ),
            ...children,
            SetChildren(
              nodeId: 1,
              children: List.generate(childCount, (index) => index + 2),
            ),
            const SetRoot(1),
          ],
        ),
      );
  }

  NativeWidgetProps _nativeProps() => NativeWidgetProps(
    kindId: _shellKind,
    version: 1,
    capabilityBits:
        NativeCapability.stateful |
        NativeCapability.resource |
        NativeCapability.semantics,
    payload: payload,
  );
}

final class _ScrollableShellFixture {
  _ScrollableShellFixture({
    required this.axis,
    required this.disableAnimations,
  });

  final Axis axis;
  final bool disableAnimations;
  final emissions = <(int, Uint8List)>[];

  Widget get widget => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: NavigationShellHost(
        props: const NavigationShellProps(
          selectedIndex: 0,
          destinationCount: 1,
          drawerOpen: false,
          drawerEnabled: false,
        ),
        emit: (eventId, payload) => emissions.add((eventId, payload)),
        bodies: [
          ListView(
            key: _scrollableBodyKey,
            scrollDirection: axis,
            children: [
              SizedBox(
                width: axis == Axis.horizontal ? 2000 : 1,
                height: axis == Axis.vertical ? 2000 : 1,
              ),
            ],
          ),
        ],
        drawer: const SizedBox.shrink(),
        bottomNavigation: const SizedBox(
          key: _animatedBottomNavigationKey,
          height: 64,
          child: ColoredBox(color: Colors.white),
        ),
      ),
    ),
  );
}
