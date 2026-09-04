import 'fixture.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('standalone composer owns its outlined card surface', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: MessageComposer(buttons: [])),
      ),
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(MessageComposer),
            matching: find.byType(Material),
          ),
        )
        .single;
    expect(material.color, theme.colorScheme.surfaceContainerHighest);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(24));
    expect(shape.side.color, theme.colorScheme.outlineVariant);
  });

  testWidgets('renders arbitrary custom button content in configured slots', (
    tester,
  ) async {
    final presses = <(int, String)>[];
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          buttons: const [
            MessageComposerButton(
              id: 10,
              tooltip: 'Add attachment',
              position: MessageComposerButtonPosition.leading,
              child: Text('ATTACH'),
            ),
            MessageComposerButton(
              id: 20,
              tooltip: 'Start voice input',
              visibility: MessageComposerButtonVisibility.whenEmpty,
              style: MessageComposerButtonStyle.filled,
              child: Text('VOICE'),
            ),
            MessageComposerButton(
              id: 21,
              tooltip: 'Send message',
              visibility: MessageComposerButtonVisibility.whenNonEmpty,
              style: MessageComposerButtonStyle.filled,
              child: Text('SEND'),
            ),
          ],
          onButtonPressed: (id, text) => presses.add((id, text)),
        ),
      ),
    );

    expect(find.text('ATTACH'), findsOneWidget);
    expect(find.text('VOICE'), findsOneWidget);
    expect(find.text('SEND'), findsNothing);

    await tester.tap(find.byTooltip('Add attachment'));
    expect(presses, [(10, '')]);

    await tester.enterText(find.byType(TextField), '  Hello 👋  ');
    await tester.pump();
    expect(find.text('VOICE'), findsNothing);
    expect(find.text('SEND'), findsOneWidget);

    await tester.tap(find.byTooltip('Send message'));
    expect(presses.last, (21, '  Hello 👋  '));
  });

  testWidgets('reports text changes without owning application state', (
    tester,
  ) async {
    final changes = <String>[];
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          controller: controller,
          buttons: const [],
          onChanged: changes.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'draft');
    expect(changes, ['draft']);
    expect(controller.text, 'draft');
  });

  testWidgets('downward swipe collapses a populated composer and unfocuses', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          key: const ValueKey('composer'),
          controller: controller,
          focusNode: focusNode,
          buttons: const [],
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'draft\nwith two lines');
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(find.byKey(const ValueKey('composer')))
        .height;
    expect(focusNode.hasFocus, isTrue);

    await tester.drag(find.byType(MessageComposer), const Offset(0, 80));
    await tester.pumpAndSettle();

    final collapsedHeight = tester
        .getSize(find.byKey(const ValueKey('composer')))
        .height;
    expect(collapsedHeight, lessThan(expandedHeight));
    expect(focusNode.hasFocus, isFalse);
    expect(controller.text, 'draft\nwith two lines');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('composer'))).height,
      greaterThan(collapsedHeight),
    );
    expect(controller.text, 'draft\nwith two lines');
  });

  testWidgets('upward and short downward drags do not collapse', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          key: const ValueKey('composer'),
          focusNode: focusNode,
          buttons: const [],
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(find.byKey(const ValueKey('composer')))
        .height;

    await tester.drag(find.byType(MessageComposer), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('composer'))).height,
      expandedHeight,
    );
    expect(focusNode.hasFocus, isTrue);

    await tester.drag(find.byType(MessageComposer), const Offset(0, 10));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('composer'))).height,
      expandedHeight,
    );
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('decisive horizontal touch intent cancels composer dragging', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          key: const ValueKey('composer'),
          focusNode: focusNode,
          buttons: const [],
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'draft\nwith two lines');
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(find.byKey(const ValueKey('composer')))
        .height;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MessageComposer)),
      kind: PointerDeviceKind.touch,
    );

    await gesture.moveBy(const Offset(6, 4));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('composer'))).height,
      expandedHeight,
    );
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('stylus keeps the existing composer drag behavior', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          key: const ValueKey('composer'),
          focusNode: focusNode,
          buttons: const [],
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'draft\nwith two lines');
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(find.byKey(const ValueKey('composer')))
        .height;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MessageComposer)),
      kind: PointerDeviceKind.stylus,
    );

    await gesture.moveBy(const Offset(6, 4));
    await gesture.moveBy(const Offset(0, 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('composer'))).height,
      expandedHeight,
    );
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('disabled composer disables editing and custom buttons', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          enabled: false,
          buttons: const [
            MessageComposerButton(
              id: 1,
              tooltip: 'Disabled action',
              child: Text('ACTION'),
            ),
          ],
          onButtonPressed: (_, _) => pressed = true,
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester.widgetList<IconButton>(find.byType(IconButton)).single.onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Disabled action'));
    expect(pressed, isFalse);
  });

  testWidgets('per-button enabled state is independent', (tester) async {
    final pressed = <int>[];
    await tester.pumpWidget(
      _TestApp(
        child: MessageComposer(
          buttons: const [
            MessageComposerButton(
              id: 1,
              tooltip: 'Disabled action',
              enabled: false,
              child: Text('OFF'),
            ),
            MessageComposerButton(
              id: 2,
              tooltip: 'Enabled action',
              child: Text('ON'),
            ),
          ],
          onButtonPressed: (id, _) => pressed.add(id),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Disabled action'));
    await tester.tap(find.byTooltip('Enabled action'));
    expect(pressed, [2]);
  });

  testWidgets('standard native registry builds composer and emits events', (
    tester,
  ) async {
    final props = MessageComposerProps(
      enabled: true,
      autofocus: false,
      maxLines: 5,
      hintText: 'Ask from OCaml',
      buttons: const [
        MessageComposerButtonProps(
          id: 7,
          tooltip: 'Custom OCaml button',
          position: MessageComposerButtonPosition.trailing,
          visibility: MessageComposerButtonVisibility.always,
          style: MessageComposerButtonStyle.filled,
          enabled: true,
        ),
      ],
    );
    final store = NodeStore()
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
              props: props.toNativeWidgetProps(),
              eventBindings: const [
                EventBinding(eventTag: EventTagId.nativeEvent, handlerId: 9),
              ],
            ),
            const CreateNode(
              nodeId: 2,
              kind: NodeKind.text,
              props: TextProps('OCAML ACTION'),
              eventBindings: [],
            ),
            const SetChildren(nodeId: 1, children: [2]),
            const SetRoot(1),
          ],
        ),
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
    expect(find.text('OCAML ACTION'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Ask from OCaml',
    );

    await tester.enterText(find.byType(TextField), 'native text');
    await tester.tap(find.byTooltip('Custom OCaml button'));

    expect(events, hasLength(2));
    final changed = events[0].payload as NativeEventPayload;
    expect(changed.kindId, NativeWidgetKind.messageComposer);
    expect(changed.eventId, MessageComposerEvent.textChanged);
    expect(utf8.decode(changed.payload), 'native text');
    final pressed = events[1].payload as NativeEventPayload;
    expect(pressed.eventId, MessageComposerEvent.buttonPressed);
    final buttonPayload = Uint8List.fromList(pressed.payload);
    expect(ByteData.sublistView(buttonPayload).getUint32(0, Endian.little), 7);
    expect(utf8.decode(buttonPayload.sublist(4)), 'native text');
  });

  test('native props round trip Unicode and button metadata', () {
    const props = MessageComposerProps(
      enabled: false,
      autofocus: true,
      maxLines: 9,
      hintText: '提问 ✨',
      buttons: [
        MessageComposerButtonProps(
          id: 42,
          tooltip: '发送 🚀',
          position: MessageComposerButtonPosition.leading,
          visibility: MessageComposerButtonVisibility.whenNonEmpty,
          style: MessageComposerButtonStyle.filled,
          enabled: false,
        ),
      ],
    );

    expect(MessageComposerProps.decode(props.encode()), props);
  });

  test('native props reject malformed payloads and invalid metadata', () {
    expect(
      () => MessageComposerProps.decode(Uint8List(11)),
      throwsFormatException,
    );

    final valid = const MessageComposerProps(
      enabled: true,
      autofocus: false,
      maxLines: 1,
      hintText: '',
      buttons: [],
    ).encode();
    final reserved = Uint8List.fromList(valid)..[6] = 1;
    expect(() => MessageComposerProps.decode(reserved), throwsFormatException);
    final zeroLines = Uint8List.fromList(valid)
      ..[2] = 0
      ..[3] = 0;
    expect(() => MessageComposerProps.decode(zeroLines), throwsFormatException);

    expect(
      () => MessageComposerProps(
        enabled: true,
        autofocus: false,
        maxLines: 5,
        hintText: '',
        buttons: const [
          MessageComposerButtonProps(
            id: 1,
            tooltip: 'One',
            position: MessageComposerButtonPosition.trailing,
            visibility: MessageComposerButtonVisibility.always,
            style: MessageComposerButtonStyle.plain,
            enabled: true,
          ),
          MessageComposerButtonProps(
            id: 1,
            tooltip: 'Duplicate',
            position: MessageComposerButtonPosition.trailing,
            visibility: MessageComposerButtonVisibility.always,
            style: MessageComposerButtonStyle.plain,
            enabled: true,
          ),
        ],
      ).encode(),
      throwsArgumentError,
    );
  });

  testWidgets('native host rejects a mismatched custom button child count', (
    tester,
  ) async {
    final props = const MessageComposerProps(
      enabled: true,
      autofocus: false,
      maxLines: 5,
      hintText: '',
      buttons: [
        MessageComposerButtonProps(
          id: 1,
          tooltip: 'Missing child',
          position: MessageComposerButtonPosition.trailing,
          visibility: MessageComposerButtonVisibility.always,
          style: MessageComposerButtonStyle.plain,
          enabled: true,
        ),
      ],
    );
    final store = NodeStore()
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
              props: props.toNativeWidgetProps(),
              eventBindings: const [],
            ),
            const SetRoot(1),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: BonsaiFlutterView(
          store: store,
          registry: WidgetRegistry.standard(),
        ),
      ),
    );

    expect(find.byType(UnsupportedNativeWidget), findsOneWidget);
    expect(find.textContaining('exactly 1 button children'), findsOneWidget);
  });
}

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}
