import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = WidgetRegistry.standard();

  Widget render(
    UiNode node,
    List<Widget> children, {
    List<RendererEvent>? events,
  }) => MaterialApp(
    home: Material(
      child: Builder(
        builder: (context) =>
            registry.build(context, node, children, events?.add),
      ),
    ),
  );

  testWidgets('scaffold maps every logical slot to the native Scaffold', (
    tester,
  ) async {
    final node = _node(
      NodeKind.materialScaffold,
      const MaterialScaffoldProps(
        hasAppBar: true,
        hasFloatingActionButton: true,
        floatingActionButtonLocation:
            MaterialFloatingActionButtonLocation.endDocked,
        hasBottomNavigationBar: true,
        hasBottomSheet: true,
      ),
    );
    final appBar = AppBar(title: const Text('Title'));
    const fab = FloatingActionButton(onPressed: null, child: Icon(Icons.add));
    const navigation = SizedBox(key: ValueKey('navigation'));
    const sheet = SizedBox(key: ValueKey('sheet'));
    const body = SizedBox(key: ValueKey('body'));

    await tester.pumpWidget(
      render(node, [appBar, fab, navigation, sheet, body]),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, same(appBar));
    expect(scaffold.floatingActionButton, same(fab));
    expect(
      scaffold.floatingActionButtonLocation,
      FloatingActionButtonLocation.endDocked,
    );
    expect(scaffold.bottomNavigationBar, same(navigation));
    expect(scaffold.bottomSheet, same(sheet));
    expect(scaffold.body, same(body));
    expect(find.byType(Column), findsNothing);
  });

  testWidgets(
    'button and floating action variants use Material 3 constructors',
    (tester) async {
      const cases = <(NodeKind, MaterialButtonVariant, Type)>[
        (
          NodeKind.materialFilledButton,
          MaterialButtonVariant.filled,
          M3EButton,
        ),
        (
          NodeKind.materialFilledTonalButton,
          MaterialButtonVariant.filledTonal,
          M3EButton,
        ),
        (
          NodeKind.materialOutlinedButton,
          MaterialButtonVariant.outlined,
          M3EButton,
        ),
        (
          NodeKind.materialElevatedButton,
          MaterialButtonVariant.elevated,
          M3EButton,
        ),
        (NodeKind.materialTextButton, MaterialButtonVariant.text, M3EButton),
        (
          NodeKind.materialIconButton,
          MaterialButtonVariant.icon,
          M3EIconButton,
        ),
      ];
      for (final (kind, variant, widgetType) in cases) {
        await tester.pumpWidget(
          render(
            _node(
              kind,
              MaterialButtonProps(
                variant: variant,
                enabled: true,
                autofocus: false,
              ),
              bindings: const [
                EventBinding(eventTag: EventTagId.press, handlerId: 10),
              ],
            ),
            const [Text('Action')],
            events: <RendererEvent>[],
          ),
        );
        expect(find.byType(widgetType), findsOneWidget, reason: '$variant');
      }

      final fabCases = <MaterialFloatingActionButtonVariant>[
        MaterialFloatingActionButtonVariant.small,
        MaterialFloatingActionButtonVariant.standard,
        MaterialFloatingActionButtonVariant.large,
      ];
      for (final variant in fabCases) {
        await tester.pumpWidget(
          render(
            _node(
              NodeKind.materialFloatingActionButton,
              MaterialFloatingActionButtonProps(
                variant: variant,
                enabled: true,
                autofocus: false,
              ),
              bindings: const [
                EventBinding(eventTag: EventTagId.press, handlerId: 11),
              ],
            ),
            const [Icon(Icons.add)],
            events: <RendererEvent>[],
          ),
        );
        expect(find.byType(M3EFab), findsOneWidget);
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
            bindings: const [
              EventBinding(eventTag: EventTagId.press, handlerId: 12),
            ],
          ),
          const [Icon(Icons.add), Text('Create')],
          events: <RendererEvent>[],
        ),
      );
      expect(find.byType(M3EExtendedFab), findsOneWidget);
    },
  );

  testWidgets('navigation bar is controlled and emits a typed index event', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialNavigationBar,
          const MaterialNavigationBarProps(
            selectedIndex: 0,
            destinations: [
              MaterialNavigationDestinationProps(
                label: 'Home',
                hasSelectedIcon: true,
              ),
              MaterialNavigationDestinationProps(
                label: 'Settings',
                hasSelectedIcon: false,
              ),
            ],
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.navigationDestinationSelected,
              handlerId: 20,
            ),
          ],
        ),
        const [Icon(Icons.home), Icon(Icons.home_filled), Icon(Icons.settings)],
        events: events,
      ),
    );

    final bar = tester.widget<M3ENavigationBar>(find.byType(M3ENavigationBar));
    expect(bar.selectedIndex, 0);
    expect(bar.destinations, hasLength(2));
    bar.onDestinationSelected!(1);
    expect(events.single.payload, const Int64EventPayload(1));
    expect(events.single.eventTag, EventTagId.navigationDestinationSelected);
  });

  testWidgets('radio group validates and emits stable signed option IDs', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialRadioGroup,
          const MaterialRadioGroupProps(
            selectedId: -7,
            options: [
              MaterialRadioOptionProps(id: -7, enabled: true, hasLabel: true),
              MaterialRadioOptionProps(id: 9, enabled: false, hasLabel: false),
            ],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.radioSelected, handlerId: 30),
          ],
        ),
        const [Text('First')],
        events: events,
      ),
    );

    expect(find.byType(M3ERadio<int>), findsNWidgets(2));
    final radios = tester.widgetList<M3ERadio<int>>(find.byType(M3ERadio<int>));
    expect(radios.first.groupValue, -7);
    expect(radios.last.onChanged, isNull);
    radios.first.onChanged!(-7);
    expect(events.single.payload, const Int64EventPayload(-7));
  });

  testWidgets('sliders coalesce change and always deliver change-end', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialSlider,
          const MaterialSliderProps(
            value: 0.25,
            min: 0,
            max: 1,
            divisions: 4,
            label: 'Quarter',
            enabled: true,
            hasOnChange: true,
            kind: 0,
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.sliderChanged, handlerId: 40),
            EventBinding(eventTag: EventTagId.sliderChangeEnd, handlerId: 41),
          ],
        ),
        const [],
        events: events,
      ),
    );
    final slider = tester.widget<M3ESlider>(find.byType(M3ESlider));
    slider.onChanged!(0.5);
    slider.onChanged!(0.75);
    expect(events, isEmpty);
    await tester.pump();
    expect(events.single.payload, const FloatEventPayload(0.75));
    slider.onChangeEnd!(1);
    expect(events.last.eventTag, EventTagId.sliderChangeEnd);
    expect(events.last.payload, const FloatEventPayload(1));

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialRangeSlider,
          const MaterialRangeSliderProps(
            start: 0.2,
            end: 0.8,
            min: 0,
            max: 1,
            divisions: null,
            labelStart: null,
            labelEnd: null,
            enabled: true,
            hasOnChange: false,
            kind: 0,
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.rangeSliderChangeEnd,
              handlerId: 42,
            ),
          ],
        ),
        const [],
        events: events,
      ),
    );
    final range = tester.widget<M3ERangeSlider>(find.byType(M3ERangeSlider));
    expect(range.onChanged, isNull);
    range.onChangeEnd!(const M3ESliderRange(0.1, 0.9));
    expect(
      events.last.payload,
      const FloatRangeEventPayload(start: 0.1, end: 0.9),
    );
  });

  testWidgets('all chip roles preserve child slots and events', (tester) async {
    const chipCases = <(NodeKind, MaterialChipVariant, Type)>[
      (NodeKind.materialActionChip, MaterialChipVariant.action, M3EChip),
      (NodeKind.materialFilterChip, MaterialChipVariant.filter, M3EChip),
      (NodeKind.materialChoiceChip, MaterialChipVariant.choice, M3EChip),
      (NodeKind.materialInputChip, MaterialChipVariant.input, M3EChip),
    ];
    for (final (kind, variant, type) in chipCases) {
      await tester.pumpWidget(
        render(
          _node(
            kind,
            MaterialChipProps(
              variant: variant,
              enabled: true,
              selected: true,
              hasLeading: false,
              hasOnDelete: variant == MaterialChipVariant.input,
            ),
            bindings: const [
              EventBinding(eventTag: EventTagId.press, handlerId: 50),
              EventBinding(eventTag: EventTagId.valueChanged, handlerId: 51),
              EventBinding(eventTag: EventTagId.delete, handlerId: 52),
            ],
          ),
          const [Text('Chip')],
          events: <RendererEvent>[],
        ),
      );
      expect(find.byType(type), findsOneWidget, reason: '$variant');
    }
  });

  testWidgets('chip, card, and divider variants map to Material constructors', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialActionChip,
          const MaterialChipProps(
            variant: MaterialChipVariant.action,
            presentation: MaterialChipPresentation.elevated,
            enabled: true,
            selected: false,
            hasLeading: false,
            hasOnDelete: false,
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.press, handlerId: 70),
          ],
        ),
        const [Text('Assist')],
        events: <RendererEvent>[],
      ),
    );
    final chip = tester.widget<M3EChip>(find.byType(M3EChip));
    expect(chip.elevated, isTrue);

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialCard,
          const MaterialCardProps(
            variant: MaterialCardVariant.outlined,
            elevation: 2,
          ),
        ),
        const [Text('Card')],
      ),
    );
    final card = tester.widget<M3ECard>(find.byType(M3ECard));
    expect(card.variant, M3ECardVariant.outlined);
    expect(card.padding, EdgeInsets.zero);

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialDivider,
          const MaterialDividerProps(
            orientation: MaterialDividerOrientation.vertical,
            thickness: 2,
            spacing: 20,
            indent: 3,
            endIndent: 4,
          ),
        ),
        const [],
      ),
    );
    final divider = tester.widget<M3EDivider>(find.byType(M3EDivider));
    expect(divider.axis, M3EDividerAxis.vertical);
    expect(divider.thickness, 2);
    expect(divider.indent, 3);
    expect(divider.endIndent, 4);
  });

  testWidgets('dialog family maps child slots and typed events', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialSimpleDialog,
          const MaterialSimpleDialogProps(
            hasTitle: true,
            options: [MaterialSimpleDialogOptionProps(id: -5, enabled: true)],
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.dialogOptionSelected,
              handlerId: 72,
            ),
          ],
        ),
        const [Text('Choose'), Text('Option')],
        events: events,
      ),
    );
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.text('Option'));
    expect(events.last.payload, const Int64EventPayload(-5));

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialFullscreenDialog,
          const MaterialFullscreenDialogProps(),
        ),
        const [Text('Fullscreen')],
      ),
    );
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('table, stepper, and expansion panels emit stable IDs', (
    tester,
  ) async {
    final events = <RendererEvent>[];
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialDataTable,
          const MaterialDataTableProps(
            columns: [
              MaterialDataTableColumnProps(
                id: 10,
                tooltip: null,
                numeric: false,
                sortable: true,
              ),
            ],
            rows: [
              MaterialDataTableRowProps(
                id: 20,
                selected: false,
                selectionEnabled: true,
                cells: [
                  MaterialDataTableCellProps(
                    placeholder: false,
                    showEditIcon: false,
                    activatable: true,
                  ),
                ],
              ),
            ],
            sortColumnId: 10,
            sortAscending: true,
            selectedRowIds: [],
          ),
          bindings: const [
            EventBinding(
              eventTag: EventTagId.tableSortRequested,
              handlerId: 80,
            ),
            EventBinding(eventTag: EventTagId.tableRowSelected, handlerId: 81),
            EventBinding(
              eventTag: EventTagId.tableCellActivated,
              handlerId: 82,
            ),
          ],
        ),
        const [Text('Name'), Text('Ada')],
        events: events,
      ),
    );
    final table = tester.widget<DataTable>(find.byType(DataTable));
    table.columns.single.onSort!(0, false);
    expect(
      events.last.payload,
      const Int64BoolEventPayload(id: 10, value: false),
    );
    table.rows.single.onSelectChanged!(true);
    expect(
      events.last.payload,
      const Int64BoolEventPayload(id: 20, value: true),
    );
    table.rows.single.cells.single.onTap!();
    expect(
      events.last.payload,
      const Int64PairEventPayload(first: 20, second: 10),
    );

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialStepper,
          const MaterialStepperProps(
            orientation: MaterialStepperOrientation.vertical,
            currentStepId: 2,
            steps: [
              MaterialStepProps(
                id: 2,
                active: true,
                state: MaterialStepState.indexed,
                hasSubtitle: false,
                hasLabel: false,
              ),
            ],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.stepSelected, handlerId: 83),
          ],
        ),
        const [Text('Title'), Text('Content')],
        events: events,
      ),
    );
    tester.widget<Stepper>(find.byType(Stepper)).onStepTapped!(0);
    expect(events.last.payload, const Int64EventPayload(2));

    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialExpansionPanelList,
          const MaterialExpansionPanelListProps(
            policy: MaterialExpansionPanelPolicy.multiple,
            expandedIds: [7],
            panels: [
              MaterialExpansionPanelProps(
                id: 7,
                enabled: true,
                canTapOnHeader: true,
              ),
            ],
          ),
          bindings: const [
            EventBinding(eventTag: EventTagId.expansionChanged, handlerId: 84),
          ],
        ),
        const [Text('Header'), Text('Body')],
        events: events,
      ),
    );
    tester
        .widget<ExpansionPanelList>(find.byType(ExpansionPanelList))
        .expansionCallback!(0, true);
    expect(events.last.payload, const Int64ListEventPayload([]));
  });

  testWidgets('stepper replaces Flutter state when ordered IDs change', (
    tester,
  ) async {
    UiNode stepper(int id, {required bool active}) => _node(
      NodeKind.materialStepper,
      MaterialStepperProps(
        orientation: MaterialStepperOrientation.vertical,
        currentStepId: id,
        steps: [
          MaterialStepProps(
            id: id,
            active: active,
            state: MaterialStepState.indexed,
            hasSubtitle: false,
            hasLabel: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      render(stepper(1, active: false), const [Text('One'), Text('Body')]),
    );
    final initialState = tester.state(find.byType(Stepper));

    await tester.pumpWidget(
      render(stepper(1, active: true), const [Text('One'), Text('Updated')]),
    );
    expect(tester.state(find.byType(Stepper)), same(initialState));

    await tester.pumpWidget(
      render(stepper(2, active: true), const [Text('Two'), Text('Body')]),
    );
    expect(tester.state(find.byType(Stepper)), isNot(same(initialState)));
  });

  testWidgets('renderer rejects malformed Material child slot ordering', (
    tester,
  ) async {
    await tester.pumpWidget(
      render(
        _node(
          NodeKind.materialInputChip,
          const MaterialChipProps(
            variant: MaterialChipVariant.input,
            enabled: true,
            selected: false,
            hasLeading: true,
            hasOnDelete: false,
          ),
        ),
        const [Text('Only one child')],
      ),
    );

    expect(tester.takeException(), isA<RendererBuildException>());
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
