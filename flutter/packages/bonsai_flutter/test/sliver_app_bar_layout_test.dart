import 'package:material_ui/material_ui.dart';
import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'fixture.dart';
import 'package:bonsai_flutter/src/renderer/sliver_app_bar_host.dart';
import 'package:flutter_test/flutter_test.dart';

Widget compose(Widget toolbar, Widget bottom, double inset) =>
    SliverAppBarHost(toolbar: toolbar, bottom: bottom, topInset: inset);

class Header extends SliverPersistentHeaderDelegate {
  Header(this.height, this.child);
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(Header oldDelegate) => true;
}

void main() {
  testWidgets('composition preserves retained ownership through padding', (
    tester,
  ) async {
    final standard = WidgetRegistry.standard();
    final registry = WidgetRegistry({
      for (final kind in NodeKind.values) kind: standard.build,
      NodeKind.sliverFill: (context, node, children, onEvent) => compose(
        SliverAppBar(pinned: false, expandedHeight: 200, title: children[0]),
        SliverPersistentHeader(pinned: true, delegate: Header(48, children[1])),
        0,
      ),
    }, NativeWidgetRegistry(capabilityBits: NativeCapability.core));
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: const [
            SetApplicationTheme(
              title: 'Prototype',
              theme: testApplicationTheme,
            ),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.scrollView,
              props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.sliverPadding,
              props: SliverPaddingProps(
                EdgeInsetsValue(left: 12, top: 16, right: 12, bottom: 16),
              ),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 3,
              kind: NodeKind.sliverFill,
              props: SliverFillProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 4,
              kind: NodeKind.text,
              props: TextProps('Toolbar'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 5,
              kind: NodeKind.gesture,
              props: GestureProps(),
              eventBindings: [
                EventBinding(eventTag: EventTagId.tap, handlerId: 100),
              ],
            ),
            CreateNode(
              nodeId: 6,
              kind: NodeKind.text,
              props: TextProps('Retained bottom'),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 7,
              kind: NodeKind.sliverBox,
              props: EmptyProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 8,
              kind: NodeKind.sizedBox,
              props: SizedBoxProps(width: null, height: 3000),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 9,
              kind: NodeKind.empty,
              props: EmptyProps(),
              eventBindings: [],
            ),
            SetChildren(nodeId: 8, children: [9]),
            SetChildren(nodeId: 5, children: [6]),
            SetChildren(nodeId: 3, children: [4, 5]),
            SetChildren(nodeId: 2, children: [3]),
            SetChildren(nodeId: 7, children: [8]),
            SetChildren(nodeId: 1, children: [2, 7]),
            SetRoot(1),
          ],
        ),
      );
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: registry,
          onEvent: events.add,
        ),
      ),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(1200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retained bottom'));
    await tester.pumpAndSettle();
    expect(events.where((event) => event.handlerId == 100), hasLength(1));
    store.apply(
      const Frame(
        runtimeEpoch: 1,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 6, props: TextProps('Updated bottom')),
        ],
      ),
    );
    await tester.pump();
    expect(find.text('Updated bottom'), findsOneWidget);
    expect(scrollable.position.pixels, 1200);
    await tester.tap(find.text('Updated bottom'));
    await tester.pumpAndSettle();
    expect(events.where((event) => event.handlerId == 100), hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('revealing page content accounts for the bottom and top inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: CustomScrollView(
            slivers: [
              compose(
                const SliverAppBar(pinned: false, expandedHeight: 200),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: Header(
                    48,
                    const SizedBox.expand(key: ValueKey('reveal-bottom')),
                  ),
                ),
                24,
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: const [
                    SizedBox(height: 1200),
                    Text('Reveal target'),
                    SizedBox(height: 1800),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Scrollable.ensureVisible(tester.element(find.text('Reveal target')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Reveal target')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('reveal-bottom'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stretch expands only the native region', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            compose(
              const SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: 200,
                flexibleSpace: SizedBox.expand(key: ValueKey('flexible')),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: Header(
                  48,
                  const SizedBox.expand(key: ValueKey('stretch-bottom')),
                ),
              ),
              0,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 3000)),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, 140));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('flexible'))).height,
      greaterThan(200),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('stretch-bottom'))).height,
      48,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stretch-bottom'))).dy,
      closeTo(
        tester.getBottomLeft(find.byKey(const ValueKey('flexible'))).dy,
        .01,
      ),
    );
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  for (final pinned in [false, true]) {
    for (final floating in [false, true]) {
      for (final inset in [0.0, 24.0]) {
        testWidgets(
          'independent header pinned=$pinned floating=$floating inset=$inset',
          (tester) async {
            final controller = ScrollController();
            addTearDown(controller.dispose);
            var taps = 0;
            Widget build(double height) => MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(padding: EdgeInsets.only(top: inset)),
                child: CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: compose(
                        SliverAppBar(
                          pinned: pinned,
                          floating: floating,
                          snap: floating,
                          expandedHeight: 200,
                          title: const Text('Toolbar'),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: Header(
                            height,
                            Material(
                              child: InkWell(
                                key: const ValueKey('bottom'),
                                onTap: () => taps++,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        inset,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 3000)),
                  ],
                ),
              ),
            );
            await tester.pumpWidget(build(48));
            expect(tester.takeException(), isNull);
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('bottom'))).dy,
              closeTo(200 + inset, .01),
            );
            controller.jumpTo(1200);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('bottom'))).dy,
              closeTo(inset + (pinned ? 56 : 0), .01),
            );
            await tester.tap(find.byKey(const ValueKey('bottom')));
            await tester.pumpAndSettle();
            expect(taps, 1);
            await tester.pumpWidget(build(72));
            await tester.pump();
            expect(controller.offset, 1200);
            expect(
              tester.getSize(find.byKey(const ValueKey('bottom'))).height,
              72,
            );
            if (floating) {
              final gesture = await tester.startGesture(const Offset(400, 400));
              await gesture.moveBy(const Offset(0, 30));
              await tester.pump();
              await gesture.moveBy(const Offset(0, 90));
              await tester.pump();
              await gesture.up();
              for (var frame = 0; frame < 25; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                final bottomY = tester
                    .getTopLeft(find.byKey(const ValueKey('bottom')))
                    .dy;
                final toolbarBottom = tester
                    .getBottomLeft(find.byType(AppBar))
                    .dy;
                expect(
                  bottomY,
                  closeTo(toolbarBottom < inset ? inset : toolbarBottom, .01),
                );
                expect(tester.takeException(), isNull);
              }
              expect(
                tester.getBottomLeft(find.byType(AppBar)).dy,
                greaterThan(inset + 50),
              );
            }
          },
        );
      }
    }
  }
}
