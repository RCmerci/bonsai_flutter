import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets('gallery state and interaction are owned by OCaml', (
    tester,
  ) async {
    final client = await tester.runAsync(
      () => _bounded(
        RuntimeClient.start(config: Uint8List.fromList(utf8.encode('gallery'))),
        'RuntimeClient.start',
      ),
    );
    expect(client, isNotNull);
    final harness = RuntimeHarness(client!);
    addTearDown(() => _bounded(harness.dispose(), 'RuntimeHarness.dispose'));

    final initialCycle = await tester.runAsync(
      () => _bounded(harness.grant(), 'initial gallery grant'),
    );
    expect(initialCycle, isNotNull);
    final initialFrame = FrameCodec.decode(initialCycle!.bytes);
    final store = NodeStore()..apply(initialFrame);
    final queue = EventBatchQueue(
      runtimeEpoch: initialFrame.runtimeEpoch,
      displayedRevision: () => store.revision,
    );
    final resources = RendererResourceStore();
    final nativeWidgets =
        NativeWidgetRegistry(
          capabilityBits:
              NativeCapability.stateful |
              NativeCapability.resource |
              NativeCapability.semantics,
        )..register<String>(
          NativeWidgetRegistration(
            kindId: 1001,
            minVersion: 1,
            maxVersion: 1,
            capabilityBits:
                NativeCapability.stateful |
                NativeCapability.resource |
                NativeCapability.semantics,
            decodeProps: (payload) => utf8.decode(payload),
            factory: (context) {
              final focusNode = context.resource<FocusNode>(
                create: FocusNode.new,
                dispose: (focusNode) => focusNode.dispose(),
              );
              return ElevatedButton(
                focusNode: focusNode,
                onPressed: () => context.emit?.call(1, Uint8List(0)),
                child: Text(context.props),
              );
            },
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(
            store: store,
            registry: WidgetRegistry.standard(nativeWidgets: nativeWidgets),
            resourceStore: resources,
            onEvent: queue.enqueue,
          ),
        ),
      ),
    );

    expect(find.text('Bonsai Flutter Gallery'), findsOneWidget);
    expect(
      find.text('OCaml owns every value and handler on this page'),
      findsOneWidget,
    );
    expect(find.byType(Padding), findsWidgets);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(ElevatedButton), findsWidgets);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.text('Native card: 0'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(resources.liveResourceCount, 3);
    expect(
      tester
          .widgetList<Theme>(find.byType(Theme))
          .any((theme) => theme.data.brightness == Brightness.dark),
      isTrue,
    );
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any(
            (semantics) =>
                semantics.properties.label == 'Bonsai Flutter gallery',
          ),
      isTrue,
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final batch = queue.takeBatch();
    expect(batch, isNotNull);
    final updateResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(batch!)),
        'gallery checkbox pump',
      ),
    );
    expect(updateResponse, isNotNull);
    final incremental = FrameCodec.decode(updateResponse!.bytes);
    expect(incremental.kind, FrameKind.incremental);
    expect(incremental.operations.whereType<CreateNode>(), isEmpty);
    expect(incremental.operations.whereType<DropNode>(), isEmpty);
    expect(
      incremental.operations.whereType<UpdateProps>().map(
        (operation) => operation.props,
      ),
      containsAll([
        const MaterialCheckboxProps(value: true, enabled: true),
        const SemanticsProps(
          label: 'Bonsai Flutter gallery',
          enabled: true,
          checked: true,
        ),
      ]),
    );

    store.apply(incremental);
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    Future<void> tapListTileAndExpect(bool expectedValue) async {
      await tester.tap(find.text('Typed ListTile'));
      await tester.pump();
      final listTileBatch = queue.takeBatch();
      expect(listTileBatch, isNotNull);
      final listTileResponse = await tester.runAsync(
        () => _bounded(
          harness.advance(events: EventBatchCodec.encode(listTileBatch!)),
          'gallery list tile pump',
        ),
      );
      expect(listTileResponse, isNotNull);
      expect(
        listTileResponse!.bytes,
        isNotEmpty,
        reason: 'ListTile press must update the OCaml selection state',
      );
      final listTileFrame = FrameCodec.decode(listTileResponse.bytes);
      store.apply(listTileFrame);
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).value,
        expectedValue,
      );
    }

    await tester.ensureVisible(find.text('Typed ListTile'));
    await tester.pumpAndSettle();
    await tapListTileAndExpect(false);
    await tapListTileAndExpect(true);

    final longPressTarget = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onLongPress != null,
    );
    expect(longPressTarget, findsOneWidget);
    await tester.ensureVisible(longPressTarget);
    await tester.pumpAndSettle();
    await tester.longPress(longPressTarget);
    await tester.pump();
    final longPressBatch = queue.takeBatch();
    expect(longPressBatch, isNotNull);
    expect(
      longPressBatch!.events.map((event) => event.eventTag),
      contains(EventTagId.longPress),
    );
    final longPressResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(longPressBatch)),
        'gallery long press pump',
      ),
    );
    expect(longPressResponse, isNotNull);
    final longPressFrame = FrameCodec.decode(longPressResponse!.bytes);
    store.apply(longPressFrame);
    await tester.pump();
    expect(find.text('Pointer event received in OCaml'), findsOneWidget);

    const editedUnicodeText = 'Type 中文 or 😀 edited';
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final textFocusBatch = queue.takeBatch();
    expect(textFocusBatch, isNotNull);
    final textFocusResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(textFocusBatch!)),
        'gallery Unicode text focus pump',
      ),
    );
    expect(textFocusResponse, isNotNull);
    final textFocusFrame = FrameCodec.decode(textFocusResponse!.bytes);
    store.apply(textFocusFrame);
    await tester.pump();

    await tester.enterText(find.byType(TextField), editedUnicodeText);
    await tester.pump();
    final textEditBatch = queue.takeBatch();
    expect(textEditBatch, isNotNull);
    final textEditResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(textEditBatch!)),
        'gallery Unicode text edit pump',
      ),
    );
    expect(textEditResponse, isNotNull);
    final textEditFrame = FrameCodec.decode(textEditResponse!.bytes);
    store.apply(textEditFrame);
    await tester.pump();
    expect(
      find.text('Canonical OCaml value: $editedUnicodeText'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Native card: 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Native card: 0'));
    await tester.pump();
    final nativeBatch = queue.takeBatch();
    expect(nativeBatch, isNotNull);
    final nativeResponse = await tester.runAsync(
      () => _bounded(
        harness.advance(events: EventBatchCodec.encode(nativeBatch!)),
        'gallery native-event pump',
      ),
    );
    expect(nativeResponse, isNotNull);
    final nativeFrame = FrameCodec.decode(nativeResponse!.bytes);
    expect(nativeFrame.kind, FrameKind.incremental);
    expect(nativeFrame.operations.whereType<CreateNode>(), isEmpty);
    expect(nativeFrame.operations.whereType<DropNode>(), isEmpty);
    final nativeUpdate = nativeFrame.operations
        .whereType<UpdateProps>()
        .map((operation) => operation.props)
        .whereType<NativeWidgetProps>()
        .single;
    expect(utf8.decode(nativeUpdate.payload), 'Native card: 1');
    store.apply(nativeFrame);
    await tester.pump();
    expect(find.text('Native card: 1'), findsOneWidget);
    expect(resources.liveResourceCount, 3);

    await tester.pumpWidget(const SizedBox.shrink());
    resources.dispose();
    expect(resources.liveResourceCount, 0);
    harness.acknowledge();
  });
}
