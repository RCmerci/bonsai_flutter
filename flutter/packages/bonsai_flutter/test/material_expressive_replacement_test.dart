import 'dart:io';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  final registry = WidgetRegistry.standard();
  late RendererResourceStore resources;
  setUp(() {
    final store = NodeStore()
      ..apply(
        const Frame(
          runtimeEpoch: 1,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            SetApplicationTheme(title: 'Test', theme: testApplicationTheme),
            CreateNode(
              nodeId: 1,
              kind: NodeKind.empty,
              props: EmptyProps(),
              eventBindings: [],
            ),
            SetRoot(1),
          ],
        ),
      );
    resources = RendererResourceStore()..synchronize(store);
  });
  tearDown(() => resources.dispose());

  Widget render(
    UiNode node,
    List<Widget> children, {
    List<RendererEvent>? events,
  }) => MaterialApp(
    home: Material(
      child: RendererResourceScope(
        resources: resources,
        child: Builder(
          builder: (context) => registry.build(
            context,
            node,
            children,
            events == null ? (_) {} : events.add,
          ),
        ),
      ),
    ),
  );

  Finder expressiveType(String name) => find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == name,
    description: 'a $name widget',
  );

  test(
    'renderer dependencies are exact and legacy Material imports are gone',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('material_3_expressive: 1.1.1'));
      expect(pubspec, contains('material_ui: 1.1.1'));

      final legacyImports = <String>[];
      for (final root in ['lib', 'test']) {
        for (final entry in Directory(root).listSync(recursive: true)) {
          if (entry is! File || !entry.path.endsWith('.dart')) continue;
          final source = entry.readAsStringSync();
          if (source.contains(
            'package:flutter/'
            'material.dart',
          )) {
            legacyImports.add(entry.path);
          }
        }
      }
      expect(legacyImports, isEmpty);
    },
  );

  testWidgets('existing action widgets use their M3E renderers', (
    tester,
  ) async {
    for (final (kind, variant, expectedType) in const [
      (
        NodeKind.materialElevatedButton,
        MaterialButtonVariant.elevated,
        'M3EButton',
      ),
      (NodeKind.materialTextButton, MaterialButtonVariant.text, 'M3EButton'),
      (
        NodeKind.materialFilledButton,
        MaterialButtonVariant.filled,
        'M3EButton',
      ),
      (
        NodeKind.materialFilledTonalButton,
        MaterialButtonVariant.filledTonal,
        'M3EButton',
      ),
      (
        NodeKind.materialOutlinedButton,
        MaterialButtonVariant.outlined,
        'M3EButton',
      ),
      (
        NodeKind.materialIconButton,
        MaterialButtonVariant.icon,
        'M3EIconButton',
      ),
    ]) {
      await tester.pumpWidget(
        render(
          _node(
            kind,
            MaterialButtonProps(
              variant: variant,
              enabled: true,
              autofocus: false,
            ),
          ),
          const [Text('Action')],
        ),
      );
      expect(expressiveType(expectedType), findsOneWidget, reason: '$variant');
    }

    for (final variant in const [
      MaterialFloatingActionButtonVariant.small,
      MaterialFloatingActionButtonVariant.standard,
      MaterialFloatingActionButtonVariant.large,
    ]) {
      await tester.pumpWidget(
        render(
          _node(
            NodeKind.materialFloatingActionButton,
            MaterialFloatingActionButtonProps(
              variant: variant,
              enabled: true,
              autofocus: false,
            ),
          ),
          const [Icon(Icons.add)],
        ),
      );
      expect(expressiveType('M3EFab'), findsOneWidget, reason: '$variant');
    }

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialFloatingActionButton,
          const MaterialFloatingActionButtonProps(
            variant: MaterialFloatingActionButtonVariant.extended,
            enabled: true,
            autofocus: false,
          ),
        ),
        const [Icon(Icons.add), Text('Create')],
      ),
    );
    expect(expressiveType('M3EExtendedFab'), findsOneWidget);
  });

  testWidgets('existing selection widgets use their M3E renderers', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialNavigationBar,
          const MaterialNavigationBarProps(
            selectedIndex: 0,
            destinations: [
              MaterialNavigationDestinationProps(
                label: 'Home',
                hasSelectedIcon: false,
                badgeCount: 3,
                semanticLabel: 'Home destination',
              ),
              MaterialNavigationDestinationProps(
                label: 'Settings',
                hasSelectedIcon: false,
              ),
            ],
            autoLayout: false,
            layout: 1,
            alignment: 0,
            labelBehavior: 1,
            iconBehavior: 2,
            size: 0,
            shape: 0,
            density: 1,
            safeArea: false,
            semanticLabel: 'Primary navigation',
          ),
        ),
        const [Icon(Icons.home), Icon(Icons.settings)],
      ),
    );
    final bar = tester.widget<M3ENavigationBar>(
      expressiveType('M3ENavigationBar'),
    );
    expect(bar.autoLayout, isFalse);
    expect(bar.layout, M3ENavBarLayout.wide);
    expect(bar.alignment, M3ENavBarAlignment.start);
    expect(bar.labelBehavior, M3ENavBarLabelBehavior.onlySelected);
    expect(bar.iconBehavior, M3ENavBarIconBehavior.alwaysHide);
    expect(bar.size, M3ENavBarSize.small);
    expect(bar.shapeFamily, M3ENavBarShapeFamily.round);
    expect(bar.density, M3ENavBarDensity.compact);
    expect(bar.safeArea, isFalse);
    expect(bar.destinations.first.badgeCount, 3);

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialRadioGroup,
          const MaterialRadioGroupProps(
            selectedId: 1,
            options: [
              MaterialRadioOptionProps(id: 1, enabled: true, hasLabel: false),
              MaterialRadioOptionProps(id: 2, enabled: false, hasLabel: false),
            ],
          ),
        ),
        const [],
      ),
    );
    expect(expressiveType('M3ERadio<int>'), findsNWidgets(2));

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialSegmentedButton,
          const MaterialSegmentedButtonProps(
            selectedIds: [1],
            enabled: true,
            multiSelectionEnabled: false,
            segments: [
              MaterialSegmentProps(id: 1, hasIcon: false),
              MaterialSegmentProps(id: 2, hasIcon: false),
            ],
          ),
        ),
        const [Text('One'), Text('Two')],
      ),
    );
    expect(expressiveType('M3ESegmentedButton<int>'), findsOneWidget);

    for (final (kind, variant) in const [
      (NodeKind.materialActionChip, MaterialChipVariant.action),
      (NodeKind.materialFilterChip, MaterialChipVariant.filter),
      (NodeKind.materialChoiceChip, MaterialChipVariant.choice),
      (NodeKind.materialInputChip, MaterialChipVariant.input),
    ]) {
      await tester.pumpWidget(
        render(
          _node(
            kind,
            MaterialChipProps(
              variant: variant,
              presentation: MaterialChipPresentation.flat,
              enabled: true,
              selected: false,
              hasLeading: false,
              hasOnDelete: variant == MaterialChipVariant.input,
            ),
          ),
          const [Text('Chip')],
        ),
      );
      expect(expressiveType('M3EChip'), findsOneWidget, reason: '$variant');
    }
  });

  testWidgets('existing value controls use their M3E renderers', (
    tester,
  ) async {
    final cases = <(NodeKind, UiProps, String)>[
      (
        NodeKind.materialCheckbox,
        const MaterialCheckboxProps(value: true, enabled: true),
        'M3ECheckbox',
      ),
      (
        NodeKind.materialSwitch,
        const MaterialSwitchProps(value: true, enabled: true),
        'M3ESwitch',
      ),
      (
        NodeKind.materialSlider,
        const MaterialSliderProps(
          value: 0.5,
          min: 0,
          max: 1,
          divisions: null,
          label: null,
          enabled: true,
          hasOnChange: false,
          kind: 5,
        ),
        'M3ESlider',
      ),
      (
        NodeKind.materialRangeSlider,
        const MaterialRangeSliderProps(
          start: 0.25,
          end: 0.75,
          min: 0,
          max: 1,
          divisions: null,
          labelStart: null,
          labelEnd: null,
          enabled: true,
          hasOnChange: false,
          kind: 1,
        ),
        'M3ERangeSlider',
      ),
    ];
    for (final (kind, props, expectedType) in cases) {
      await tester.pumpWidget(render(_node(kind, props), const []));
      expect(expressiveType(expectedType), findsOneWidget);
    }
  });

  testWidgets('existing containment and feedback use M3E renderers', (
    tester,
  ) async {
    final cases = <(UiNode, List<Widget>, String)>[
      (
        _node(
          NodeKind.materialDivider,
          const MaterialDividerProps(
            thickness: 1,
            orientation: MaterialDividerOrientation.horizontal,
            spacing: 16,
            indent: 0,
            endIndent: 0,
          ),
        ),
        const [],
        'M3EDivider',
      ),
      (
        _node(
          NodeKind.materialCard,
          const MaterialCardProps(
            variant: MaterialCardVariant.filled,
            elevation: 0,
          ),
        ),
        const [Text('Card')],
        'M3ECard',
      ),
      (
        _node(
          NodeKind.materialCircularProgressIndicator,
          const MaterialCircularProgressProps(value: 0.5, wavy: true),
        ),
        const [],
        'M3EProgressIndicator',
      ),
      (
        _node(
          NodeKind.materialLinearProgressIndicator,
          const MaterialLinearProgressProps(value: 0.5, wavy: true),
        ),
        const [],
        'M3EProgressIndicator',
      ),
    ];
    for (final (node, children, expectedType) in cases) {
      await tester.pumpWidget(render(node, children));
      expect(
        expressiveType(expectedType),
        findsOneWidget,
        reason: '${node.kind}',
      );
    }
  });

  testWidgets('revisioned search and text inputs use M3E renderers', (
    tester,
  ) async {
    const value = TextEditingStateValue(
      text: 'hello',
      selection: TextRangeValue(startUtf16: 5, endUtf16: 5),
      composing: null,
    );
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialSearchBar,
          const MaterialSearchBarProps(
            sessionId: 1,
            documentRevision: 2,
            value: value,
            enabled: true,
            readOnly: false,
            keyboardType: TextKeyboardType.text,
            inputAction: TextInputActionKind.search,
            acceptedLocalRevision: 0,
            updateMode: TextUpdateMode.ack,
            autofocus: false,
            maxUtf8Bytes: 64,
            hasLeading: false,
            trailingCount: 0,
            hintText: 'Search',
            hasOnTap: false,
          ),
        ),
        const [],
      ),
    );
    expect(expressiveType('M3ESearchBar'), findsOneWidget);

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialTextField,
          const MaterialTextFieldProps(
            sessionId: 1,
            documentRevision: 2,
            value: value,
            enabled: true,
            readOnly: true,
            obscureText: false,
            keyboardType: TextKeyboardType.multiline,
            inputAction: TextInputActionKind.newline,
            acceptedLocalRevision: 0,
            updateMode: TextUpdateMode.ack,
            autofocus: true,
            maxUtf8Bytes: 64,
            variant: 1,
            label: 'Message',
            supportingText: 'Supporting',
            errorText: null,
            hasLeading: false,
            hasTrailing: false,
            maxLines: 4,
          ),
        ),
        const [],
      ),
    );
    expect(expressiveType('M3ETextField'), findsOneWidget);
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.readOnly, isTrue);
    expect(editableText.focusNode.hasFocus, isTrue);
  });

  testWidgets('bottom app bar keeps the optional FAB out of actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 15,
            variant: 0,
            flags: 2,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [],
          ),
        ),
        const [Icon(Icons.search), Icon(Icons.add)],
      ),
    );

    final appBar = tester.widget<M3EAppBar>(find.byType(M3EAppBar));
    expect(appBar.actions, hasLength(1));
    expect(appBar.floatingActionButton, isNotNull);
    expect(appBar.safeArea, isFalse);
  });

  testWidgets('button group uses only group-level controlled selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 1,
            variant: 0,
            flags: 0,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [41],
            items: [
              MaterialExpressiveItemProps(
                id: 41,
                kind: 1,
                label: 'Selected',
                enabled: true,
                selected: true,
                childCount: 0,
              ),
              MaterialExpressiveItemProps(
                id: 42,
                kind: 0,
                label: 'Other',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
            ],
          ),
        ),
        const [],
      ),
    );

    final group = tester.widget<M3EButtonGroup>(find.byType(M3EButtonGroup));
    expect(group.selectedIndex, 0);
    expect(group.actions, everyElement(isA<M3EButtonGroupAction>()));
    expect(
      group.actions.cast<M3EButtonGroupAction>().map(
        (action) => action.checked,
      ),
      everyElement(isNull),
    );
  });

  testWidgets('nested menu descriptors preserve groups and submenus', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 20,
            variant: 0,
            flags: 0,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [
              MaterialExpressiveItemProps(
                id: 0,
                kind: 4,
                label: 'Group',
                enabled: true,
                selected: false,
                childCount: 1,
              ),
              MaterialExpressiveItemProps(
                id: 1,
                kind: 5,
                label: 'Submenu',
                enabled: true,
                selected: false,
                childCount: 1,
              ),
              MaterialExpressiveItemProps(
                id: 2,
                kind: 0,
                label: 'Leaf',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
            ],
          ),
        ),
        const [Text('Menu')],
      ),
    );

    final menu = tester.widget<M3EMenu>(find.byType(M3EMenu));
    final group = menu.children!.single as M3EMenuGroup;
    final submenu = group.children.single as M3EMenuSubmenu;
    expect(submenu.children.single, isA<M3EMenuEntry>());
  });

  testWidgets('dismiss confirmation waits for the accepted token frame', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    MaterialExpressiveProps props(int state) => MaterialExpressiveProps(
      component: 10,
      variant: state,
      flags: 0,
      primaryText: null,
      secondaryText: '42',
      value: null,
      endValue: null,
      selectedIds: const [],
      items: const [
        MaterialExpressiveItemProps(
          id: 9,
          kind: 0,
          label: '',
          enabled: true,
          selected: false,
          childCount: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          props(0),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.segmentedSelectionChanged,
              handlerId: 99,
            ),
          ],
        ),
        const [Text('Dismiss me')],
        events: events,
      ),
    );
    final dismissible = tester.widget<M3EDismissibleColumn>(
      find.byType(M3EDismissibleColumn),
    );
    final result = dismissible.onDismiss!(0, DismissDirection.endToStart);
    expect(events.single.payload, const Int64ListEventPayload([42, 9, 1]));

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          props(2),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.segmentedSelectionChanged,
              handlerId: 99,
            ),
          ],
        ),
        const [Text('Dismiss me')],
        events: events,
      ),
    );
    expect(await result, isTrue);
  });

  testWidgets('dismissible list accepts an unbounded scroll parent', (
    tester,
  ) async {
    final node = _node(
      NodeKind.materialExpressive,
      const MaterialExpressiveProps(
        component: 11,
        variant: 0,
        flags: 0,
        primaryText: null,
        secondaryText: '1',
        value: null,
        endValue: null,
        selectedIds: [],
        items: [
          MaterialExpressiveItemProps(
            id: 9,
            kind: 0,
            label: '',
            enabled: true,
            selected: false,
            childCount: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: RendererResourceScope(
            resources: resources,
            child: Builder(
              builder: (context) => registry.build(context, node, const [
                Text('Dismiss me'),
              ], (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Dismiss me'), findsOneWidget);
  });

  testWidgets('side sheet accepts an unbounded height inside a scroll view', (
    tester,
  ) async {
    final node = _node(
      NodeKind.materialExpressive,
      const MaterialExpressiveProps(
        component: 14,
        variant: 0,
        flags: 0,
        primaryText: null,
        secondaryText: null,
        value: null,
        endValue: null,
        selectedIds: [],
        items: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: RendererResourceScope(
            resources: resources,
            child: Builder(
              builder: (context) => registry.build(context, node, const [
                Text('Details'),
                Text('Sheet body'),
              ], (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sheet body'), findsOneWidget);
  });

  testWidgets('search app bar uses the M3E search constructor', (tester) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 28,
            variant: 0,
            flags: 2,
            primaryText: 'query',
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [],
            textInput: TextInputProps(
              sessionId: 1,
              documentRevision: 1,
              value: TextEditingStateValue(
                text: 'query',
                selection: TextRangeValue(startUtf16: 5, endUtf16: 5),
                composing: null,
              ),
              enabled: true,
              readOnly: false,
              obscureText: false,
              keyboardType: TextKeyboardType.text,
              inputAction: TextInputActionKind.search,
              acceptedLocalRevision: 0,
              updateMode: TextUpdateMode.forceReplace,
              autofocus: false,
            ),
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.textEdit, handlerId: 1),
            EventBinding(eventTag: EventTagId.textSubmit, handlerId: 2),
            EventBinding(eventTag: EventTagId.focusChanged, handlerId: 3),
          ],
        ),
        const [],
        events: events,
      ),
    );
    expect(find.byType(M3EAppBar), findsOneWidget);
    final controller = tester
        .widget<M3ESearchAnchor>(find.byType(M3ESearchAnchor))
        .searchController!;
    controller.value = const TextEditingValue(
      text: 'query!',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(
      events.where((event) => event.payload is TextEditEventPayload),
      hasLength(1),
    );
    final edit =
        events
                .singleWhere((event) => event.payload is TextEditEventPayload)
                .payload
            as TextEditEventPayload;
    expect(edit.sessionId, 1);
    expect(edit.localRevision, 1);
    expect(edit.baseDocumentRevision, 1);
    expect(edit.text, 'query!');
  });

  testWidgets('selection maps stable IDs to controller indices', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 9,
            variant: 0,
            flags: 1,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [20],
            items: [
              MaterialExpressiveItemProps(
                id: 10,
                kind: 1,
                label: '',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
              MaterialExpressiveItemProps(
                id: 20,
                kind: 3,
                label: '',
                enabled: true,
                selected: true,
                childCount: 0,
              ),
              MaterialExpressiveItemProps(
                id: 30,
                kind: 0,
                label: '',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
            ],
          ),
        ),
        const [SizedBox.shrink(), SizedBox.expand()],
      ),
    );

    final selection = tester.widget<M3ESelection>(find.byType(M3ESelection));
    expect(selection.itemCount, 3);
    expect(selection.controller!.selectedIndices, {1});
  });

  testWidgets('selection accepts an unbounded height inside a scroll view', (
    tester,
  ) async {
    final node = _node(
      NodeKind.materialExpressive,
      const MaterialExpressiveProps(
        component: 9,
        variant: 0,
        flags: 0,
        primaryText: null,
        secondaryText: null,
        value: null,
        endValue: null,
        selectedIds: [10],
        items: [
          MaterialExpressiveItemProps(
            id: 10,
            kind: 0,
            label: '',
            enabled: true,
            selected: true,
            childCount: 0,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: RendererResourceScope(
            resources: resources,
            child: Builder(
              builder: (context) => registry.build(context, node, const [
                Text('Selection'),
                Text('Selected item'),
              ], (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Selected item'), findsOneWidget);
  });

  testWidgets('modal navigation rail preserves renderer resource scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 17,
            variant: 0,
            flags: 3,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [10],
            items: [
              MaterialExpressiveItemProps(
                id: 10,
                kind: 0,
                label: 'Home',
                enabled: true,
                selected: true,
                childCount: 1,
              ),
            ],
          ),
        ),
        [
          Builder(
            builder: (context) {
              RendererResourceScope.of(context);
              return const Icon(Icons.home);
            },
          ),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('toolbar preserves controlled active, overflow, and FAB state', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 19,
            variant: 0,
            flags: 780,
            primaryText: 'Create',
            secondaryText: '99',
            value: null,
            endValue: null,
            selectedIds: [20],
            items: [
              MaterialExpressiveItemProps(
                id: 10,
                kind: 1,
                label: 'Edit',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
              MaterialExpressiveItemProps(
                id: 20,
                kind: 3,
                label: 'Favorite',
                enabled: true,
                selected: true,
                childCount: 0,
              ),
            ],
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.navigationDestinationSelected,
              handlerId: 1,
            ),
            EventBinding(eventTag: EventTagId.radioSelected, handlerId: 2),
            EventBinding(eventTag: EventTagId.valueChanged, handlerId: 3),
          ],
        ),
        const [Icon(Icons.add)],
        events: events,
      ),
    );

    final toolbar = tester.widget<M3EToolbar>(find.byType(M3EToolbar));
    expect(toolbar.actions, everyElement(isA<M3EToolbarAction>()));
    expect(toolbar.maxInlineActions, 3);
    expect(toolbar.expanded, isFalse);
    expect(toolbar.activeIndex, 1);
    expect(toolbar.fabIcon, isA<Icon>());

    toolbar.onExpandedChanged!(true);
    toolbar.onActiveIndexChanged!(0);
    toolbar.onFabPressed!();
    expect(events[0].payload, const BoolEventPayload(true));
    expect(events[1].payload, const Int64EventPayload(10));
    expect(events[2].payload, const Int64EventPayload(99));
  });

  testWidgets('inline pickers emit typed civil values', (tester) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 5,
            variant: 0,
            flags: 0,
            primaryText: '2026-09-04',
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [
              MaterialExpressiveItemProps(
                id: 0,
                kind: 0,
                label: '2020-01-01',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
              MaterialExpressiveItemProps(
                id: 1,
                kind: 1,
                label: '2030-12-31',
                enabled: true,
                selected: false,
                childCount: 0,
              ),
            ],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.civilDateChanged, handlerId: 1),
          ],
        ),
        const [],
        events: events,
      ),
    );
    tester
        .widget<M3ECalendarDatePicker>(find.byType(M3ECalendarDatePicker))
        .onDateChanged(DateTime(2027, 2, 3));
    expect(
      events.single.payload,
      const CivilDateEventPayload(year: 2027, month: 2, day: 3),
    );

    events.clear();
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 6,
            variant: 1,
            flags: 0,
            primaryText: '09:30',
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.civilTimeChanged, handlerId: 2),
          ],
        ),
        const [],
        events: events,
      ),
    );
    tester
        .widget<M3EDialTimePicker>(find.byType(M3EDialTimePicker))
        .onChanged(const M3ETime(hour: 14, minute: 45));
    expect(
      events.single.payload,
      const CivilTimeEventPayload(hour: 14, minute: 45),
    );
  });

  testWidgets('carousel maps layout changes to stable focal item IDs', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 7,
            variant: 0,
            flags: 2,
            primaryText: null,
            secondaryText: null,
            value: null,
            endValue: null,
            selectedIds: [],
            items: [
              MaterialExpressiveItemProps(
                id: 101,
                kind: 0,
                label: '',
                enabled: true,
                selected: false,
                childCount: 1,
              ),
              MaterialExpressiveItemProps(
                id: 303,
                kind: 0,
                label: '',
                enabled: true,
                selected: false,
                childCount: 1,
              ),
            ],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.radioSelected, handlerId: 1),
          ],
        ),
        const [Text('First'), Text('Second')],
        events: events,
      ),
    );

    final carousel = tester.widget<M3ECarousel>(find.byType(M3ECarousel));
    carousel.onChange!(
      const M3ECarouselChangeDetails(
        leadingIndex: 0,
        focalIndex: 1,
        itemCount: 2,
      ),
    );
    expect(events.single.payload, const Int64EventPayload(303));
  });

  testWidgets('refresh exposes a renderer-owned programmatic controller', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpressive,
          const MaterialExpressiveProps(
            component: 23,
            variant: 0,
            flags: 0,
            primaryText: '7',
            secondaryText: '41',
            value: null,
            endValue: null,
            selectedIds: [],
            items: [],
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.segmentedSelectionChanged,
              handlerId: 1,
            ),
          ],
        ),
        const [SingleChildScrollView(child: SizedBox(height: 1000))],
        events: events,
      ),
    );

    final refresh = tester.widget<M3ERefreshIndicator>(
      find.byType(M3ERefreshIndicator),
    );
    expect(refresh.controller, isNotNull);
    expect(events.single.payload, const Int64ListEventPayload([41]));
  });

  testWidgets('expressive sliver forms render native slivers', (tester) async {
    Widget sliverTree(MaterialExpressiveProps props, List<Widget> children) =>
        MaterialApp(
          home: Material(
            child: RendererResourceScope(
              resources: resources,
              child: Builder(
                builder: (context) {
                  final expressive = registry.build(
                    context,
                    _node(NodeKind.materialExpressive, props),
                    children,
                    (_) {},
                  );
                  final sliver = registry.build(
                    context,
                    _node(NodeKind.sliverBox, const EmptyProps()),
                    [expressive],
                    (_) {},
                  );
                  return CustomScrollView(slivers: [sliver]);
                },
              ),
            ),
          ),
        );

    await tester.pumpWidget(
      sliverTree(
        const MaterialExpressiveProps(
          component: 12,
          variant: 0,
          flags: 2,
          primaryText: null,
          secondaryText: null,
          value: null,
          endValue: null,
          selectedIds: [],
          items: [
            MaterialExpressiveItemProps(
              id: 1,
              kind: 0,
              label: 'Header',
              enabled: true,
              selected: false,
              childCount: 1,
            ),
          ],
        ),
        const [Text('Body')],
      ),
    );
    expect(find.byType(SliverToBoxAdapter), findsNothing);
    expect(find.byType(M3EExpandableList), findsOneWidget);

    await tester.pumpWidget(
      sliverTree(
        const MaterialExpressiveProps(
          component: 8,
          variant: 2,
          flags: 0,
          primaryText: null,
          secondaryText: null,
          value: null,
          endValue: null,
          selectedIds: [],
          items: [
            MaterialExpressiveItemProps(
              id: 2,
              kind: 0,
              label: '',
              enabled: true,
              selected: false,
              childCount: 1,
            ),
          ],
        ),
        const [Text('Card')],
      ),
    );
    expect(find.byType(SliverToBoxAdapter), findsNothing);
    expect(expressiveType('M3ECardListItem'), findsOneWidget);
  });
}

UiNode _node(
  NodeKind kind,
  UiProps props, {
  List<EventBinding> bindings = const [],
}) => UiNode(
  id: 1,
  kind: kind,
  props: props,
  eventBindings: bindings,
  parentData: const NoParentData(),
  children: const [],
  localRevision: 0,
  deliveryGeneration: 0,
);
