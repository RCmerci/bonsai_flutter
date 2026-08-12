import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/navigation/modal_sheet_keyboard_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final boundaryCase
      in <({String name, int limit, String below, String equal, String above})>[
        (name: 'ASCII', limit: 3, below: 'ab', equal: 'abc', above: 'abcd'),
        (name: 'CJK', limit: 6, below: '拼', equal: '拼音', above: '拼音a'),
        (
          name: 'emoji surrogate pair',
          limit: 4,
          below: 'a',
          equal: '😀',
          above: '😀a',
        ),
        (
          name: 'combining mark',
          limit: 3,
          below: 'e',
          equal: 'é',
          above: 'éa',
        ),
      ]) {
    testWidgets(
      'enforces ${boundaryCase.name} below, equal, and above UTF-8 byte boundaries',
      (tester) async {
        final store = NodeStore()
          ..apply(
            textInputSnapshot(
              maxUtf8Bytes: boundaryCase.limit,
              text: '',
              selectionOffset: 0,
            ),
          );
        final events = <RendererEvent>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BonsaiFlutterView(store: store, onEvent: events.add),
            ),
          ),
        );
        final controller = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller;

        controller.value = TextEditingValue(
          text: boundaryCase.below,
          selection: TextSelection.collapsed(offset: boundaryCase.below.length),
        );
        controller.value = TextEditingValue(
          text: boundaryCase.equal,
          selection: TextSelection.collapsed(offset: boundaryCase.equal.length),
        );
        controller.value = TextEditingValue(
          text: boundaryCase.above,
          selection: TextSelection.collapsed(offset: boundaryCase.above.length),
        );
        await tester.pump();

        expect(controller.text, boundaryCase.equal);
        final edits = events
            .where((event) => event.eventTag == EventTagId.textEdit)
            .toList();
        expect(
          edits.map((event) => (event.payload as TextEditEventPayload).text),
          [boundaryCase.below, boundaryCase.equal],
        );
        final limits = events
            .where((event) => event.eventTag == EventTagId.textLimitReached)
            .toList();
        expect(limits, hasLength(1));
        expect(limits.single.payload, const UnitEventPayload());
      },
    );
  }

  testWidgets('oversized paste never enters an EventBatch', (tester) async {
    final store = NodeStore()
      ..apply(
        textInputSnapshot(maxUtf8Bytes: 8, text: 'valid', selectionOffset: 5),
      );
    final queue = EventBatchQueue(
      runtimeEpoch: 91,
      displayedRevision: () => store.revision,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    final oversizedPaste = '😀' * (ProtocolLimits.maxStringBytes ~/ 4 + 1);

    expect(
      () => controller.value = TextEditingValue(
        text: oversizedPaste,
        selection: TextSelection.collapsed(offset: oversizedPaste.length),
      ),
      returnsNormally,
    );

    expect(controller.text, 'valid');
    final prepared = queue.prepareBatch();
    expect(prepared.encodedBytes.length, lessThan(128));
    final events = EventBatchCodec.decode(prepared.encodedBytes).events;
    expect(events, hasLength(1));
    expect(events.single.eventTag, EventTagId.textLimitReached);
    expect(events.single.payload, const UnitEventPayload());
  });

  testWidgets(
    'oversized active IME composition restores the complete valid value',
    (tester) async {
      final store = NodeStore()
        ..apply(
          textInputSnapshot(maxUtf8Bytes: 4, text: '', selectionOffset: 0),
        );
      final events = <RendererEvent>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      final controller = tester
          .widget<EditableText>(find.byType(EditableText))
          .controller;
      const lastValid = TextEditingValue(
        text: '拼a',
        selection: TextSelection(baseOffset: 1, extentOffset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      controller.value = lastValid;

      expect(
        () => controller.value = const TextEditingValue(
          text: '拼音',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
        returnsNormally,
      );
      await tester.pump();

      expect(controller.value, lastValid);
      expect(
        events.where((event) => event.eventTag == EventTagId.textEdit),
        hasLength(1),
      );
      expect(
        events.where((event) => event.eventTag == EventTagId.textLimitReached),
        hasLength(1),
      );
    },
  );

  testWidgets('unlimited text input has no application-specific limit', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(textInputSnapshot(text: '', selectionOffset: 0));
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    final text = 'ASCII 拼音 😀 é ' * 1000;

    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();

    expect(controller.text, text);
    expect(
      events.where((event) => event.eventTag == EventTagId.textEdit),
      hasLength(1),
    );
    expect(
      events.where((event) => event.eventTag == EventTagId.textLimitReached),
      isEmpty,
    );
  });

  testWidgets(
    'text input preserves local echo and rejects a stale correction',
    (tester) async {
      final store = NodeStore()..apply(textInputSnapshot());
      final resources = RendererResourceStore();
      final events = <RendererEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BonsaiFlutterView(
              store: store,
              resourceStore: resources,
              onEvent: events.add,
            ),
          ),
        ),
      );
      final controller = tester
          .widget<EditableText>(find.byType(EditableText))
          .controller;
      expect(controller.text, '拼');

      controller.value = const TextEditingValue(
        text: '拼😀音',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.pump();

      final editEvent = events.singleWhere(
        (event) => event.eventTag == EventTagId.textEdit,
      );
      expect(
        editEvent.payload,
        const TextEditEventPayload(
          sessionId: 10,
          localRevision: 1,
          baseDocumentRevision: 4,
          text: '拼😀音',
          selectionStartUtf16: 4,
          selectionEndUtf16: 4,
          composingStartUtf16: 0,
          composingEndUtf16: 4,
        ),
      );

      store.apply(
        textInputUpdate(
          targetRevision: 2,
          props: textInputProps(
            documentRevision: 4,
            acceptedLocalRevision: 0,
            updateMode: TextUpdateMode.correction,
            text: 'stale server value',
            selectionOffset: 18,
          ),
        ),
      );
      await tester.pump();

      expect(controller.text, '拼😀音');
      expect(
        identical(
          tester.widget<EditableText>(find.byType(EditableText)).controller,
          controller,
        ),
        isTrue,
      );

      store.apply(
        textInputUpdate(
          baseRevision: 2,
          targetRevision: 3,
          props: textInputProps(
            documentRevision: 5,
            acceptedLocalRevision: 1,
            updateMode: TextUpdateMode.correction,
            text: '拼😀音!',
            selectionOffset: 5,
          ),
        ),
      );
      await tester.pump();

      expect(controller.text, '拼😀音!');
      expect(
        events.where((event) => event.eventTag == EventTagId.textEdit),
        hasLength(1),
      );
      expect(resources.liveResourceCount, 1);
    },
  );

  testWidgets('text edit keeps the callback revision until the host rebuilds', (
    tester,
  ) async {
    final store = NodeStore()..apply(textInputSnapshot());
    final queue = EventBatchQueue(
      runtimeEpoch: 91,
      displayedRevision: () => store.revision,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: queue.enqueue),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;

    store.apply(
      const Frame(
        runtimeEpoch: 91,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateEventBindings(
            nodeId: 1,
            eventBindings: [
              EventBinding(eventTag: EventTagId.textEdit, handlerId: 201),
              EventBinding(eventTag: EventTagId.textSubmit, handlerId: 202),
              EventBinding(eventTag: EventTagId.focusChanged, handlerId: 203),
            ],
          ),
        ],
      ),
    );
    controller.text = 'before rebuild';

    final beforeRebuild = queue.takeBatch()!.events.single;
    expect(beforeRebuild.displayedRevision, 1);
    expect(beforeRebuild.handlerId, 101);

    await tester.pump();
    expect(
      identical(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        controller,
      ),
      isTrue,
    );
    controller.text = 'after rebuild';

    final afterRebuild = queue.takeBatch()!.events.single;
    expect(afterRebuild.displayedRevision, 2);
    expect(afterRebuild.handlerId, 201);

    store.apply(
      const Frame(
        runtimeEpoch: 91,
        baseRevision: 2,
        targetRevision: 3,
        kind: FrameKind.incremental,
        operations: [
          UpdateEventBindings(
            nodeId: 1,
            eventBindings: [
              EventBinding(eventTag: EventTagId.textEdit, handlerId: 201),
              EventBinding(eventTag: EventTagId.textSubmit, handlerId: 202),
              EventBinding(eventTag: EventTagId.focusChanged, handlerId: 203),
            ],
          ),
        ],
      ),
    );
    controller.text = 'same handler in the next frame';

    final unchangedBinding = queue.takeBatch()!.events.single;
    expect(unchangedBinding.displayedRevision, 3);
    expect(unchangedBinding.handlerId, 201);
  });

  testWidgets(
    'text input normalizes controller selections to protocol UTF-16 ranges',
    (tester) async {
      final store = NodeStore()..apply(textInputSnapshot());
      final events = <RendererEvent>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BonsaiFlutterView(store: store, onEvent: events.add),
          ),
        ),
      );
      final controller = tester
          .widget<EditableText>(find.byType(EditableText))
          .controller;

      controller.value = const TextEditingValue(
        text: 'A😀B',
        selection: TextSelection.collapsed(offset: 2),
      );
      controller.value = const TextEditingValue(
        text: 'A😀B',
        selection: TextSelection(baseOffset: 4, extentOffset: 1),
      );
      controller.value = const TextEditingValue(
        text: 'A😀B',
        selection: TextSelection(baseOffset: -1, extentOffset: -1),
      );
      await tester.pump();

      final edits = events
          .where((event) => event.eventTag == EventTagId.textEdit)
          .map((event) => event.payload as TextEditEventPayload)
          .toList();
      expect(
        edits
            .map((edit) => (edit.selectionStartUtf16, edit.selectionEndUtf16))
            .toList(),
        [(3, 3), (1, 4), (4, 4)],
      );
      for (final edit in edits) {
        expect(
          () => EventBatchCodec.encode(
            EventBatch(
              runtimeEpoch: 91,
              events: [
                UiEvent(
                  sequence: edit.localRevision,
                  displayedRevision: store.revision,
                  nodeId: 1,
                  handlerId: 101,
                  eventTag: EventTagId.textEdit,
                  payload: edit,
                ),
              ],
            ),
          ),
          returnsNormally,
        );
      }
    },
  );

  testWidgets('focus, submit, force replace, and disposal are typed', (
    tester,
  ) async {
    final store = NodeStore()..apply(textInputSnapshot());
    final resources = RendererResourceStore();
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(
            store: store,
            resourceStore: resources,
            onEvent: events.add,
          ),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;

    final focusRequest = resources.requestFocus(1);
    await tester.pump();
    await focusRequest;
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(
      events
          .where((event) => event.eventTag == EventTagId.focusChanged)
          .last
          .payload,
      const BoolEventPayload(true),
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      events
          .where((event) => event.eventTag == EventTagId.textSubmit)
          .single
          .payload,
      const TextEventPayload('拼'),
    );

    store.apply(
      textInputUpdate(
        targetRevision: 2,
        props: textInputProps(
          sessionId: 11,
          documentRevision: 5,
          acceptedLocalRevision: 0,
          updateMode: TextUpdateMode.forceReplace,
          text: 'reset',
          selectionOffset: 5,
        ),
      ),
    );
    await tester.pump();
    expect(controller.text, 'reset');
    expect(resources.liveResourceCount, 1);

    store.apply(
      const Frame(
        runtimeEpoch: 91,
        baseRevision: 0,
        targetRevision: 3,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 2,
            kind: NodeKind.text,
            props: TextProps('removed'),
            eventBindings: [],
          ),
          SetRoot(2),
        ],
      ),
    );
    await tester.pump();
    expect(resources.liveResourceCount, 0);
    expect(resources.disposedResourceCount, 1);
  });

  testWidgets('keyed reorder retains controller and node drop disposes it', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 92,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const CreateNode(
              nodeId: 1,
              kind: NodeKind.column,
              props: LinearProps(),
              eventBindings: [],
            ),
            CreateNode(
              nodeId: 2,
              kind: NodeKind.textInput,
              props: textInputProps(),
              eventBindings: const [
                EventBinding(eventTag: EventTagId.textEdit, handlerId: 101),
                EventBinding(eventTag: EventTagId.textSubmit, handlerId: 102),
                EventBinding(eventTag: EventTagId.focusChanged, handlerId: 103),
              ],
            ),
            const CreateNode(
              nodeId: 3,
              kind: NodeKind.text,
              props: TextProps('sibling'),
              eventBindings: [],
            ),
            const SetChildren(nodeId: 1, children: [2, 3]),
            const SetRoot(1),
          ],
        ),
      );
    final resources = RendererResourceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, resourceStore: resources),
        ),
      ),
    );
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;

    store.apply(
      const Frame(
        runtimeEpoch: 92,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          SetChildren(nodeId: 1, children: [3, 2]),
        ],
      ),
    );
    await tester.pump();
    expect(
      identical(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        controller,
      ),
      isTrue,
    );
    expect(resources.createdResourceCount, 1);

    store.apply(
      const Frame(
        runtimeEpoch: 92,
        baseRevision: 2,
        targetRevision: 3,
        kind: FrameKind.incremental,
        operations: [
          SetChildren(nodeId: 1, children: [3]),
          DropNode(2),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(EditableText), findsNothing);
    expect(resources.liveResourceCount, 0);
    expect(resources.disposedResourceCount, 1);
  });

  testWidgets('paste, delete, and focus switch emit ordered typed events', (
    tester,
  ) async {
    final store = NodeStore()
      ..apply(
        Frame(
          runtimeEpoch: 93,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            const CreateNode(
              nodeId: 1,
              kind: NodeKind.column,
              props: LinearProps(),
              eventBindings: [],
            ),
            for (final nodeId in [2, 3])
              CreateNode(
                nodeId: nodeId,
                kind: NodeKind.textInput,
                props: textInputProps(sessionId: nodeId),
                eventBindings: [
                  EventBinding(
                    eventTag: EventTagId.textEdit,
                    handlerId: 100 + nodeId,
                  ),
                  EventBinding(
                    eventTag: EventTagId.textSubmit,
                    handlerId: 200 + nodeId,
                  ),
                  EventBinding(
                    eventTag: EventTagId.focusChanged,
                    handlerId: 300 + nodeId,
                  ),
                ],
              ),
            const SetChildren(nodeId: 1, children: [2, 3]),
            const SetRoot(1),
          ],
        ),
      );
    final events = <RendererEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BonsaiFlutterView(store: store, onEvent: events.add),
        ),
      ),
    );
    final editors = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    editors.first.controller.value = const TextEditingValue(
      text: '拼 paste',
      selection: TextSelection.collapsed(offset: 7),
    );
    editors.first.controller.value = const TextEditingValue(
      text: '拼',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    final edits = events
        .where((event) => event.eventTag == EventTagId.textEdit)
        .map((event) => event.payload as TextEditEventPayload)
        .toList();
    expect(edits.map((edit) => edit.localRevision), [1, 2]);
    expect(edits.map((edit) => edit.text), ['拼 paste', '拼']);

    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    final focusEvents = events
        .where((event) => event.eventTag == EventTagId.focusChanged)
        .toList();
    expect(
      focusEvents.map((event) => (event.nodeId, event.payload)),
      containsAllInOrder([
        (2, const BoolEventPayload(true)),
        (2, const BoolEventPayload(false)),
        (3, const BoolEventPayload(true)),
      ]),
    );
  });

  testWidgets('autofocus remains immediate without an activation scope', (
    tester,
  ) async {
    await _pumpAutofocusInput(tester);

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('a closed activation scope delays only automatic focus', (
    tester,
  ) async {
    await _pumpAutofocusInput(tester, automaticFocusReady: false);
    final editable = tester.widget<EditableText>(find.byType(EditableText));

    expect(editable.focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('opening the activation scope focuses without remounting input', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    final store = NodeStore()..apply(textInputSnapshot(autofocus: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, value, child) =>
                ModalSheetAutomaticFocusScope(ready: value, child: child!),
            child: BonsaiFlutterView(store: store),
          ),
        ),
      ),
    );
    await tester.pump();
    final editableFinder = find.byType(EditableText);
    final editableElement = tester.element(editableFinder);
    final editable = tester.widget<EditableText>(editableFinder);
    expect(editable.focusNode.hasFocus, isFalse);

    ready.value = true;
    await tester.pump();
    await tester.pump();

    expect(tester.element(editableFinder), same(editableElement));
    expect(editable.focusNode.hasFocus, isTrue);
  });
}

Future<void> _pumpAutofocusInput(
  WidgetTester tester, {
  bool? automaticFocusReady,
}) async {
  final store = NodeStore()..apply(textInputSnapshot(autofocus: true));
  Widget child = BonsaiFlutterView(store: store);
  if (automaticFocusReady != null) {
    child = ModalSheetAutomaticFocusScope(
      ready: automaticFocusReady,
      child: child,
    );
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

Frame textInputSnapshot({
  int? maxUtf8Bytes,
  String text = '拼',
  int selectionOffset = 1,
  bool autofocus = false,
}) => Frame(
  runtimeEpoch: 91,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 1,
      kind: NodeKind.textInput,
      props: textInputProps(
        maxUtf8Bytes: maxUtf8Bytes,
        text: text,
        selectionOffset: selectionOffset,
        autofocus: autofocus,
      ),
      eventBindings: const [
        EventBinding(eventTag: EventTagId.textEdit, handlerId: 101),
        EventBinding(eventTag: EventTagId.textSubmit, handlerId: 102),
        EventBinding(eventTag: EventTagId.focusChanged, handlerId: 103),
        EventBinding(eventTag: EventTagId.textLimitReached, handlerId: 104),
      ],
    ),
    const SetRoot(1),
  ],
);

Frame textInputUpdate({
  int baseRevision = 1,
  required int targetRevision,
  required TextInputProps props,
}) => Frame(
  runtimeEpoch: 91,
  baseRevision: baseRevision,
  targetRevision: targetRevision,
  kind: FrameKind.incremental,
  operations: [UpdateProps(nodeId: 1, props: props)],
);

TextInputProps textInputProps({
  int sessionId = 10,
  int documentRevision = 4,
  int acceptedLocalRevision = 0,
  TextUpdateMode updateMode = TextUpdateMode.forceReplace,
  String text = '拼',
  int selectionOffset = 1,
  int? maxUtf8Bytes,
  bool autofocus = false,
}) => TextInputProps(
  sessionId: sessionId,
  documentRevision: documentRevision,
  acceptedLocalRevision: acceptedLocalRevision,
  updateMode: updateMode,
  value: TextEditingStateValue(
    text: text,
    selection: TextRangeValue(
      startUtf16: selectionOffset,
      endUtf16: selectionOffset,
    ),
    composing: null,
  ),
  enabled: true,
  readOnly: false,
  obscureText: false,
  keyboardType: TextKeyboardType.text,
  inputAction: TextInputActionKind.done,
  autofocus: autofocus,
  maxUtf8Bytes: maxUtf8Bytes,
);
