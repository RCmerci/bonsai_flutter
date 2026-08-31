import 'dart:typed_data';

import 'package:bonsai_flutter/src/application_platform/application_platform.dart';
import 'package:bonsai_flutter/src/protocol/binary_codec.dart';
import 'package:bonsai_flutter/src/protocol/frame.dart';
import 'package:bonsai_flutter/src/protocol/generated_protocol.dart';
import 'package:bonsai_flutter/src/store/node_store.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  test('application theme structured value round-trips every token group', () {
    const typography = ThemeTypographyValue(
      fontFamily: 'Inter',
      fontFamilyFallback: ['Noto Sans', 'sans-serif'],
      displayLarge: TextStyleValue(fontSize: 57, lineHeight: 1.12),
      headlineMedium: TextStyleValue(fontSize: 28),
      titleSmall: TextStyleValue(fontWeight: TextFontWeight.semiBold),
      bodyLarge: TextStyleValue(fontSize: 16),
      labelSmall: TextStyleValue(fontSize: 11),
    );
    const highContrastDark = ThemeDataValue(
      brightness: ThemeBrightness.dark,
      colorScheme: ThemeColorSchemeValue(
        seedArgb: 0xff123456,
        variant: ThemeDynamicVariant.monochrome,
        contrastLevel: 1,
      ),
      typography: typography,
      shape: ThemeShapeValue(
        extraSmall: 0,
        small: 2,
        medium: 4,
        large: 8,
        extraLarge: 16,
      ),
      visualDensity: ThemeVisualDensity.comfortable,
      tapTargetSize: ThemeTapTargetSize.padded,
    );
    const theme = ApplicationThemeValue(
      mode: ApplicationThemeMode.system,
      light: testLightThemeData,
      dark: testDarkThemeData,
      highContrastLight: testLightThemeData,
      highContrastDark: highContrastDark,
    );
    const frame = Frame(
      runtimeEpoch: 51,
      baseRevision: 0,
      targetRevision: 1,
      kind: FrameKind.fullSnapshot,
      operations: [
        SetApplicationTheme(title: 'Theme test', theme: theme),
        CreateNode(
          nodeId: 1,
          kind: NodeKind.text,
          props: TextProps('body'),
          eventBindings: [],
        ),
        SetRoot(1),
      ],
    );

    final decoded = FrameCodec.decode(FrameCodec.encode(frame));
    final operation = decoded.operations.first as SetApplicationTheme;

    expect(operation.title, 'Theme test');
    expect(operation.theme, theme);
  });

  test('application theme codec rejects invalid contrast and font names', () {
    final invalidValues = [
      testLightThemeData.copyWith(
        colorScheme: const ThemeColorSchemeValue(
          seedArgb: 0xff6750a4,
          variant: ThemeDynamicVariant.tonalSpot,
          contrastLevel: 1.01,
        ),
      ),
      testLightThemeData.copyWith(
        typography: const ThemeTypographyValue(fontFamily: '   '),
      ),
      testLightThemeData.copyWith(
        shape: const ThemeShapeValue(
          extraSmall: 4,
          small: 8,
          medium: double.nan,
          large: 16,
          extraLarge: 28,
        ),
      ),
    ];

    for (final value in invalidValues) {
      final frame = Frame(
        runtimeEpoch: 51,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          SetApplicationTheme(
            title: 'Invalid',
            theme: ApplicationThemeValue(
              mode: ApplicationThemeMode.light,
              light: value,
              dark: testDarkThemeData,
            ),
          ),
        ],
      );
      expect(() => FrameCodec.encode(frame), throwsA(isA<ProtocolException>()));
    }
  });

  group('binary frame codec', () {
    test('matches the shared counter full-snapshot fixture byte for byte', () {
      final encoded = FrameCodec.encode(counterSnapshot(text: 'Count: 0'));
      final expected = readHexFixture('ocaml_counter_full.hex');

      expect(encoded, orderedEquals(expected));
      expect(encoded.length, expected.length);
      expect(encoded.sublist(0, 4), [0x42, 0x46, 0x46, 0x52]);
      expect(readUint16(encoded, 4), 1);
      expect(readUint16(encoded, 6), ProtocolVersion.protocolMinor);
      expect(readUint16(encoded, 8), 48);
      expect(encoded[10], 2);
      expect(readUint64(encoded, 12), 7);
      expect(readUint64(encoded, 20), 0);
      expect(readUint64(encoded, 28), 1);
      expect(readUint32(encoded, 36), encoded.length - 48);
    });

    test('round trips an incremental Unicode property update', () {
      const frame = Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: TextProps('计数: 1'))],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect(decoded.runtimeEpoch, 7);
      expect(decoded.baseRevision, 1);
      expect(decoded.targetRevision, 2);
      expect(decoded.kind, FrameKind.incremental);
      expect(decoded.operations, hasLength(1));
      final update = decoded.operations.single as UpdateProps;
      expect(update.nodeId, 2);
      expect(update.props, const TextProps('计数: 1'));
    });

    test('round trips the complete Material component protocol surface', () {
      const props = <UiProps>[
        MaterialScaffoldProps(
          hasAppBar: true,
          hasFloatingActionButton: true,
          floatingActionButtonLocation:
              MaterialFloatingActionButtonLocation.endDocked,
          hasBottomNavigationBar: true,
          hasBottomSheet: true,
        ),
        MaterialButtonProps(
          variant: MaterialButtonVariant.filledTonal,
          enabled: true,
          autofocus: false,
        ),
        MaterialFloatingActionButtonProps(
          variant: MaterialFloatingActionButtonVariant.extended,
          enabled: true,
          autofocus: false,
          hasIcon: true,
        ),
        MaterialNavigationBarProps(
          selectedIndex: 0,
          destinations: [
            MaterialNavigationDestinationProps(
              label: 'Home',
              enabled: true,
              hasSelectedIcon: true,
            ),
            MaterialNavigationDestinationProps(
              label: 'Settings',
              enabled: false,
              hasSelectedIcon: false,
            ),
          ],
        ),
        MaterialAlertDialogProps(
          hasIcon: true,
          hasTitle: true,
          hasContent: true,
          actionCount: 2,
        ),
        MaterialRadioGroupProps(
          selectedId: -7,
          options: [
            MaterialRadioOptionProps(id: -7, enabled: true, hasLabel: true),
            MaterialRadioOptionProps(id: 9, enabled: false, hasLabel: false),
          ],
        ),
        MaterialSegmentedButtonProps(
          selectedIds: [-7, 9],
          enabled: true,
          direction: ScrollAxis.vertical,
          multiSelectionEnabled: true,
          emptySelectionAllowed: true,
          expandedInsets: EdgeInsetsValue(left: 8, top: 4, right: 8, bottom: 4),
          showSelectedIcon: true,
          hasSelectedIcon: true,
          segments: [
            MaterialSegmentProps(
              id: -7,
              enabled: true,
              tooltip: 'List view',
              hasIcon: true,
              hasLabel: true,
            ),
            MaterialSegmentProps(
              id: 9,
              enabled: false,
              tooltip: null,
              hasIcon: false,
              hasLabel: true,
            ),
          ],
        ),
        MaterialSliderProps(
          value: 0.25,
          min: 0,
          max: 1,
          divisions: 4,
          label: 'Quarter',
          enabled: true,
          hasOnChange: true,
        ),
        MaterialRangeSliderProps(
          start: 0.2,
          end: 0.8,
          min: 0,
          max: 1,
          divisions: null,
          labelStart: null,
          labelEnd: null,
          enabled: true,
          hasOnChange: false,
        ),
        MaterialChipProps(
          variant: MaterialChipVariant.input,
          enabled: true,
          selected: true,
          hasAvatar: true,
          hasDeleteIcon: true,
          hasOnPress: true,
          hasOnSelected: true,
          hasOnDelete: true,
        ),
        MaterialLinearProgressProps(value: 0.5),
      ];
      final operations = <FrameOperation>[
        for (var index = 0; index < props.length; index += 1)
          UpdateProps(nodeId: index + 1, props: props[index]),
        const UpdateProps(
          nodeId: 30,
          props: PageProps(
            pageKey: 'confirm',
            presentation: ModalDialogPresentation(
              barrierDismissible: false,
              barrierColorArgb: 0x7f000000,
              barrierLabel: 'Close confirmation',
              useSafeArea: true,
              requestFocus: true,
              transitionDurationMilliseconds: 180,
              reverseTransitionDurationMilliseconds: 120,
            ),
            canPop: true,
            restorationId: 'confirm-dialog',
          ),
        ),
        const HostRequestOperation(
          requestId: 91,
          request: ShowSnackBarRequest(
            message: 'Saved',
            actionLabel: 'Undo',
            durationMs: 1500,
          ),
        ),
      ];
      final frame = Frame(
        runtimeEpoch: 77,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: operations,
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect(decoded.operations, hasLength(operations.length));
      expect(
        FrameCodec.encode(decoded),
        orderedEquals(FrameCodec.encode(frame)),
      );
      expect(
        (decoded.operations.first as UpdateProps).props,
        const MaterialScaffoldProps(
          hasAppBar: true,
          hasFloatingActionButton: true,
          floatingActionButtonLocation:
              MaterialFloatingActionButtonLocation.endDocked,
          hasBottomNavigationBar: true,
          hasBottomSheet: true,
        ),
      );
      expect((decoded.operations[3] as UpdateProps).props, props[3]);
      expect((decoded.operations[8] as UpdateProps).props, props[8]);
      expect(
        ((decoded.operations[10] as UpdateProps).props
                as MaterialLinearProgressProps)
            .value,
        0.5,
      );
      expect(
        (decoded.operations[11] as UpdateProps).props,
        const PageProps(
          pageKey: 'confirm',
          presentation: ModalDialogPresentation(
            barrierDismissible: false,
            barrierColorArgb: 0x7f000000,
            barrierLabel: 'Close confirmation',
            useSafeArea: true,
            requestFocus: true,
            transitionDurationMilliseconds: 180,
            reverseTransitionDurationMilliseconds: 120,
          ),
          canPop: true,
          restorationId: 'confirm-dialog',
        ),
      );
    });

    test('round trips additional Material component properties', () {
      const props = <UiProps>[
        MaterialSearchBarProps(
          sessionId: 3,
          documentRevision: 8,
          value: TextEditingStateValue(
            text: 'find',
            selection: TextRangeValue(startUtf16: 1, endUtf16: 4),
            composing: TextRangeValue(startUtf16: 0, endUtf16: 4),
          ),
          enabled: true,
          readOnly: false,
          keyboardType: TextKeyboardType.text,
          inputAction: TextInputActionKind.search,
          acceptedLocalRevision: 5,
          updateMode: TextUpdateMode.correction,
          autofocus: true,
          maxUtf8Bytes: 64,
          hasLeading: true,
          trailingCount: 2,
          hintText: 'Search',
          hasOnTap: true,
        ),
        MaterialTooltipProps(
          message: 'Details',
          enabled: true,
          excludeFromSemantics: false,
          preferBelow: false,
          triggerMode: MaterialTooltipTriggerMode.tap,
          waitDurationMs: 20,
          showDurationMs: 1500,
          exitDurationMs: 100,
          enableTapToDismiss: true,
          enableFeedback: false,
          hasOnTriggered: true,
        ),
        MaterialDataTableProps(
          columns: [
            MaterialDataTableColumnProps(
              id: 11,
              tooltip: 'Name',
              numeric: false,
              sortable: true,
            ),
            MaterialDataTableColumnProps(
              id: 12,
              tooltip: null,
              numeric: true,
              sortable: false,
            ),
          ],
          rows: [
            MaterialDataTableRowProps(
              id: 21,
              selected: true,
              selectionEnabled: true,
              cells: [
                MaterialDataTableCellProps(
                  placeholder: false,
                  showEditIcon: true,
                  activatable: true,
                ),
                MaterialDataTableCellProps(
                  placeholder: false,
                  showEditIcon: false,
                  activatable: false,
                ),
              ],
            ),
          ],
          sortColumnId: 11,
          sortAscending: false,
          selectedRowIds: [21],
          hasOnSort: true,
          hasOnRowSelected: true,
          hasOnSelectAll: true,
          hasOnCellActivate: true,
        ),
        MaterialStepperProps(
          orientation: MaterialStepperOrientation.horizontal,
          currentStepId: 31,
          steps: [
            MaterialStepProps(
              id: 31,
              active: true,
              state: MaterialStepState.editing,
              hasSubtitle: true,
              hasLabel: true,
            ),
          ],
        ),
        MaterialExpansionPanelListProps(
          policy: MaterialExpansionPanelPolicy.single,
          expandedIds: [41],
          panels: [
            MaterialExpansionPanelProps(
              id: 41,
              enabled: true,
              canTapOnHeader: true,
            ),
          ],
        ),
        MaterialSimpleDialogProps(
          hasTitle: true,
          options: [MaterialSimpleDialogOptionProps(id: 51, enabled: true)],
        ),
        MaterialFullscreenDialogProps(),
        MaterialChipProps(
          variant: MaterialChipVariant.action,
          presentation: MaterialChipPresentation.elevated,
          enabled: true,
          selected: false,
          hasAvatar: true,
          hasDeleteIcon: false,
          hasOnPress: true,
          hasOnSelected: false,
          hasOnDelete: false,
        ),
        MaterialCardProps(variant: MaterialCardVariant.filled, elevation: 2),
        MaterialDividerProps(
          orientation: MaterialDividerOrientation.vertical,
          thickness: 2,
          spacing: 24,
          indent: 4,
          endIndent: 8,
        ),
      ];
      final frame = Frame(
        runtimeEpoch: 77,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          for (var index = 0; index < props.length; index += 1)
            UpdateProps(nodeId: index + 1, props: props[index]),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      final decodedProps = [
        for (final operation in decoded.operations)
          (operation as UpdateProps).props,
      ];

      expect(decodedProps, props);
    });

    test('rejects malformed Material controls at the Dart wire boundary', () {
      Frame frame(UiProps props) => Frame(
        runtimeEpoch: 77,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 1, props: props)],
      );

      final invalid = <UiProps>[
        const MaterialNavigationBarProps(
          selectedIndex: 2,
          destinations: [
            MaterialNavigationDestinationProps(
              label: 'Home',
              enabled: true,
              hasSelectedIcon: false,
            ),
            MaterialNavigationDestinationProps(
              label: 'Settings',
              enabled: true,
              hasSelectedIcon: false,
            ),
          ],
        ),
        const MaterialRadioGroupProps(
          selectedId: 1,
          options: [
            MaterialRadioOptionProps(id: 1, enabled: true, hasLabel: false),
            MaterialRadioOptionProps(id: 1, enabled: true, hasLabel: false),
          ],
        ),
        const MaterialSegmentedButtonProps(
          selectedIds: [2, 1],
          enabled: true,
          direction: ScrollAxis.horizontal,
          multiSelectionEnabled: true,
          emptySelectionAllowed: false,
          expandedInsets: null,
          showSelectedIcon: true,
          hasSelectedIcon: false,
          segments: [
            MaterialSegmentProps(
              id: 1,
              enabled: true,
              tooltip: null,
              hasIcon: false,
              hasLabel: true,
            ),
            MaterialSegmentProps(
              id: 2,
              enabled: true,
              tooltip: null,
              hasIcon: false,
              hasLabel: true,
            ),
          ],
        ),
        const MaterialSliderProps(
          value: double.nan,
          min: 0,
          max: 1,
          divisions: null,
          label: null,
          enabled: true,
          hasOnChange: true,
        ),
        const MaterialRangeSliderProps(
          start: 0.8,
          end: 0.2,
          min: 0,
          max: 1,
          divisions: 4,
          labelStart: null,
          labelEnd: null,
          enabled: true,
          hasOnChange: true,
        ),
        const MaterialChipProps(
          variant: MaterialChipVariant.input,
          presentation: MaterialChipPresentation.elevated,
          enabled: true,
          selected: false,
          hasAvatar: false,
          hasDeleteIcon: false,
          hasOnPress: false,
          hasOnSelected: false,
          hasOnDelete: false,
        ),
        const MaterialDataTableProps(
          columns: [
            MaterialDataTableColumnProps(
              id: 1,
              tooltip: null,
              numeric: false,
              sortable: false,
            ),
          ],
          rows: [
            MaterialDataTableRowProps(
              id: 2,
              selected: false,
              selectionEnabled: true,
              cells: [],
            ),
          ],
          sortColumnId: null,
          sortAscending: true,
          selectedRowIds: [],
        ),
        const MaterialStepperProps(
          orientation: MaterialStepperOrientation.vertical,
          currentStepId: 1,
          steps: [],
        ),
        const MaterialExpansionPanelListProps(
          policy: MaterialExpansionPanelPolicy.single,
          expandedIds: [1, 2],
          panels: [
            MaterialExpansionPanelProps(
              id: 1,
              enabled: true,
              canTapOnHeader: false,
            ),
            MaterialExpansionPanelProps(
              id: 2,
              enabled: true,
              canTapOnHeader: false,
            ),
          ],
        ),
        const MaterialSimpleDialogProps(hasTitle: false, options: []),
        const MaterialCardProps(
          variant: MaterialCardVariant.outlined,
          elevation: -1,
        ),
        const MaterialDividerProps(
          orientation: MaterialDividerOrientation.vertical,
          thickness: 1,
          spacing: -1,
          indent: 0,
          endIndent: 0,
        ),
      ];

      for (final props in invalid) {
        expect(
          () => FrameCodec.encode(frame(props)),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
          reason: '${props.runtimeType}',
        );
      }
    });

    test(
      'round trips linear progress modes and rejects invalid values at the wire boundary',
      () {
        Frame frame(double? value) => Frame(
          runtimeEpoch: 78,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.materialLinearProgressIndicator,
              props: MaterialLinearProgressProps(value: value),
              eventBindings: const [],
            ),
            const SetRoot(1),
          ],
        );

        for (final value in <double?>[null, 0, 0.375, 1]) {
          final decoded = FrameCodec.decode(FrameCodec.encode(frame(value)));
          final node = decoded.operations.first as CreateNode;
          final props = node.props as MaterialLinearProgressProps;
          expect(props.value, value);
        }

        for (final invalid in const [
          -0.01,
          1.01,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          expect(
            () => FrameCodec.encode(frame(invalid)),
            throwsProtocolCode(ProtocolErrorCode.invalidProps),
          );
        }

        final valid = FrameCodec.encode(frame(0.375));
        for (final invalid in const [
          -0.01,
          1.01,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          expectDecodeError(
            replaceFloat64(valid, 0.375, invalid),
            ProtocolErrorCode.invalidProps,
          );
        }
      },
    );

    test('round trips every styled text property', () {
      const props = TextProps(
        'Quarterly planning',
        style: TextStyleValue(
          fontSize: 16,
          fontWeight: TextFontWeight.semiBold,
          lineHeight: 1.4,
          colorArgb: 0xff183758,
        ),
        textAlign: TextAlignValue.end,
        maxLines: 2,
        overflow: TextOverflowValue.ellipsis,
      );
      const frame = Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: props)],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect((decoded.operations.single as UpdateProps).props, props);
    });

    test('decodes the protocol 1.12 text property layout', () {
      final decoded = FrameCodec.decode(
        readHexFixture('legacy_1_12_counter_full.hex'),
      );

      expect(decoded.runtimeEpoch, 7);
      expect(decoded.baseRevision, 0);
      expect(decoded.targetRevision, 1);
      expect(decoded.kind, FrameKind.fullSnapshot);
      expect(decoded.operations, hasLength(4));
      expect(
        decoded.operations
            .whereType<CreateNode>()
            .map((operation) => operation.props)
            .whereType<TextProps>()
            .single,
        const TextProps('Count: 0'),
      );
    });

    test('round trips host requests and declarative navigation props', () {
      const frame = Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          HostRequestOperation(
            requestId: 20,
            request: ClipboardWriteRequest('剪贴板😀'),
          ),
          HostRequestOperation(
            requestId: 21,
            request: PickFileRequest(
              allowedExtensions: ['txt', 'md'],
              allowMultiple: true,
            ),
          ),
          CancelHostRequestOperation(requestId: 21),
          UpdateProps(
            nodeId: 30,
            props: PageProps(
              pageKey: 'settings',
              presentation: StandardPagePresentation(PageTransition.fade),
              canPop: true,
              restorationId: 'settings-page',
            ),
          ),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect(decoded.operations, hasLength(4));
      final clipboard = decoded.operations[0] as HostRequestOperation;
      expect(clipboard.requestId, 20);
      expect((clipboard.request as ClipboardWriteRequest).text, '剪贴板😀');
      final picker =
          (decoded.operations[1] as HostRequestOperation).request
              as PickFileRequest;
      expect(picker.allowedExtensions, ['txt', 'md']);
      expect(picker.allowMultiple, isTrue);
      expect(
        (decoded.operations[2] as CancelHostRequestOperation).requestId,
        21,
      );
      expect(
        (decoded.operations[3] as UpdateProps).props,
        const PageProps(
          pageKey: 'settings',
          presentation: StandardPagePresentation(PageTransition.fade),
          canPop: true,
          restorationId: 'settings-page',
        ),
      );
    });

    test('round trips every modal bottom sheet option and stable updates', () {
      const before = PageProps(
        pageKey: 'editor',
        presentation: ModalBottomSheetPresentation(
          barrierDismissible: false,
          barrierColorArgb: 0x7f102030,
          barrierLabel: 'Close editor',
          sizing: DetentedModalSheetSizing(
            detents: ModalSheetDetentSet.mediumAndLarge,
            initialDetent: ModalSheetDetent.medium,
            dismissOnDrag: true,
            handleSemantics: ModalSheetHandleSemantics(
              label: 'Adjust sheet height',
              mediumValue: 'Half height',
              largeValue: 'Full height',
            ),
          ),
          useSafeArea: true,
          requestFocus: false,
          transitionDurationMilliseconds: 0,
          reverseTransitionDurationMilliseconds: 175,
        ),
        canPop: false,
        restorationId: 'editor-page',
      );
      const after = PageProps(
        pageKey: 'editor',
        presentation: ModalBottomSheetPresentation(
          barrierDismissible: true,
          barrierColorArgb: 0x7f102030,
          barrierLabel: 'Close editor',
          sizing: DetentedModalSheetSizing(
            detents: ModalSheetDetentSet.mediumAndLarge,
            initialDetent: ModalSheetDetent.large,
            dismissOnDrag: false,
            handleSemantics: ModalSheetHandleSemantics(
              label: 'Resize editor',
              mediumValue: 'Collapsed',
              largeValue: 'Expanded',
            ),
          ),
          useSafeArea: true,
          requestFocus: true,
          transitionDurationMilliseconds: 325,
          reverseTransitionDurationMilliseconds: 175,
        ),
        canPop: true,
        restorationId: 'editor-page',
      );
      const frame = Frame(
        runtimeEpoch: 73,
        baseRevision: 4,
        targetRevision: 5,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 30, props: before),
          UpdateProps(nodeId: 30, props: after),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      final updates = decoded.operations.cast<UpdateProps>();
      final decodedBefore = updates.first.props as PageProps;
      final decodedAfter = updates.last.props as PageProps;

      expect(decodedBefore.canPop, isFalse);
      expect(decodedAfter.canPop, isTrue);
      final beforeModal =
          decodedBefore.presentation as ModalBottomSheetPresentation;
      final afterModal =
          decodedAfter.presentation as ModalBottomSheetPresentation;
      expect(beforeModal.barrierDismissible, isFalse);
      expect(afterModal.barrierDismissible, isTrue);
      expect(beforeModal.requestFocus, isFalse);
      expect(afterModal.requestFocus, isTrue);
      expect(beforeModal.transitionDurationMilliseconds, 0);
      expect(afterModal.transitionDurationMilliseconds, 325);
      expect(afterModal.reverseTransitionDurationMilliseconds, 175);
      expect(afterModal.barrierColorArgb, 0x7f102030);
      expect(afterModal.barrierLabel, 'Close editor');
      expect(
        beforeModal.sizing,
        const DetentedModalSheetSizing(
          detents: ModalSheetDetentSet.mediumAndLarge,
          initialDetent: ModalSheetDetent.medium,
          dismissOnDrag: true,
          handleSemantics: ModalSheetHandleSemantics(
            label: 'Adjust sheet height',
            mediumValue: 'Half height',
            largeValue: 'Full height',
          ),
        ),
      );
      expect(
        afterModal.sizing,
        const DetentedModalSheetSizing(
          detents: ModalSheetDetentSet.mediumAndLarge,
          initialDetent: ModalSheetDetent.large,
          dismissOnDrag: false,
          handleSemantics: ModalSheetHandleSemantics(
            label: 'Resize editor',
            mediumValue: 'Collapsed',
            largeValue: 'Expanded',
          ),
        ),
      );
    });

    test('round trips bounded and scroll-controlled modal sizing', () {
      for (final sizing in const <ModalBottomSheetSizing>[
        ContentBoundedModalSheetSizing(),
        ScrollControlledModalSheetSizing(),
      ]) {
        final props = PageProps(
          pageKey: 'modal',
          presentation: ModalBottomSheetPresentation(
            barrierDismissible: true,
            barrierColorArgb: null,
            barrierLabel: null,
            sizing: sizing,
            useSafeArea: false,
            requestFocus: true,
            transitionDurationMilliseconds: 250,
            reverseTransitionDurationMilliseconds: 200,
          ),
          canPop: true,
          restorationId: null,
        );
        final frame = Frame(
          runtimeEpoch: 73,
          baseRevision: 4,
          targetRevision: 5,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 30, props: props)],
        );

        expect(
          (FrameCodec.decode(FrameCodec.encode(frame)).operations.single
                  as UpdateProps)
              .props,
          props,
        );
      }
    });

    test('round trips every configured modal detent set', () {
      const semantics = ModalSheetHandleSemantics(
        label: 'Adjust sheet height',
        mediumValue: 'Half height',
        largeValue: 'Full height',
      );
      for (final sizing in const [
        DetentedModalSheetSizing(
          detents: ModalSheetDetentSet.medium,
          initialDetent: ModalSheetDetent.medium,
          dismissOnDrag: true,
          handleSemantics: semantics,
        ),
        DetentedModalSheetSizing(
          detents: ModalSheetDetentSet.large,
          initialDetent: ModalSheetDetent.large,
          dismissOnDrag: false,
          handleSemantics: semantics,
        ),
        DetentedModalSheetSizing(
          detents: ModalSheetDetentSet.mediumAndLarge,
          initialDetent: ModalSheetDetent.large,
          dismissOnDrag: true,
          handleSemantics: semantics,
        ),
      ]) {
        final props = PageProps(
          pageKey: 'detents',
          presentation: ModalBottomSheetPresentation(
            barrierDismissible: true,
            barrierColorArgb: null,
            barrierLabel: null,
            sizing: sizing,
            useSafeArea: false,
            requestFocus: true,
            transitionDurationMilliseconds: 250,
            reverseTransitionDurationMilliseconds: 200,
          ),
          canPop: true,
          restorationId: null,
        );
        final frame = Frame(
          runtimeEpoch: 74,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 30, props: props)],
        );

        expect(
          (FrameCodec.decode(FrameCodec.encode(frame)).operations.single
                  as UpdateProps)
              .props,
          props,
        );
      }
    });

    test('rejects invalid modal enum, flags, colors, and durations', () {
      PageProps modal({
        int? barrierColorArgb = 0x7f102030,
        int transitionDurationMilliseconds = 250,
        int reverseTransitionDurationMilliseconds = 200,
        ModalBottomSheetSizing sizing = const ContentBoundedModalSheetSizing(),
      }) => PageProps(
        pageKey: 'modal',
        presentation: ModalBottomSheetPresentation(
          barrierDismissible: true,
          barrierColorArgb: barrierColorArgb,
          barrierLabel: null,
          sizing: sizing,
          useSafeArea: false,
          requestFocus: true,
          transitionDurationMilliseconds: transitionDurationMilliseconds,
          reverseTransitionDurationMilliseconds:
              reverseTransitionDurationMilliseconds,
        ),
        canPop: true,
        restorationId: null,
      );

      Frame frame(PageProps props) => Frame(
        runtimeEpoch: 73,
        baseRevision: 4,
        targetRevision: 5,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 30, props: props)],
      );

      for (final invalid in [-1, 0x100000000]) {
        expect(
          () => FrameCodec.encode(
            frame(modal(transitionDurationMilliseconds: invalid)),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
        expect(
          () => FrameCodec.encode(
            frame(modal(reverseTransitionDurationMilliseconds: invalid)),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }
      for (final invalid in [-1, 0x100000000]) {
        expect(
          () => FrameCodec.encode(frame(modal(barrierColorArgb: invalid))),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }

      final encoded = FrameCodec.encode(frame(modal()));
      const propsOffset = ProtocolLimits.headerBytes + 5 + 5 + 8 + 2 + 8;
      const pageKeyBytes = 4 + 5;
      const transitionBytes = 1;
      const canPopBytes = 1;
      const restorationIdBytes = 1;
      const presentationOffset =
          propsOffset +
          pageKeyBytes +
          transitionBytes +
          canPopBytes +
          restorationIdBytes;
      expectDecodeError(
        mutate(encoded, presentationOffset, 0xff),
        ProtocolErrorCode.invalidProps,
      );

      const modalSizingOffset = presentationOffset + 8;
      expectDecodeError(
        mutate(encoded, modalSizingOffset, 0xff),
        ProtocolErrorCode.invalidProps,
      );

      final detentedEncoded = FrameCodec.encode(
        frame(
          modal(
            sizing: const DetentedModalSheetSizing(
              detents: ModalSheetDetentSet.mediumAndLarge,
              initialDetent: ModalSheetDetent.medium,
              dismissOnDrag: true,
              handleSemantics: ModalSheetHandleSemantics(
                label: 'Adjust sheet height',
                mediumValue: 'Half height',
                largeValue: 'Full height',
              ),
            ),
          ),
        ),
      );
      const modalDetentsOffset = presentationOffset + 19;
      const modalInitialDetentOffset = presentationOffset + 20;
      const modalDismissOnDragOffset = presentationOffset + 21;
      expectDecodeError(
        mutate(detentedEncoded, modalDetentsOffset, 0xff),
        ProtocolErrorCode.invalidProps,
      );
      expectDecodeError(
        mutate(detentedEncoded, modalInitialDetentOffset, 0xff),
        ProtocolErrorCode.invalidProps,
      );
      expectDecodeError(
        mutate(detentedEncoded, modalDismissOnDragOffset, 2),
        ProtocolErrorCode.invalidProps,
      );
      expectDecodeError(
        mutate(detentedEncoded, modalSizingOffset, 0),
        ProtocolErrorCode.invalidProps,
      );
      expectDecodeError(
        mutate(encoded, modalSizingOffset, 2),
        ProtocolErrorCode.invalidProps,
      );

      expect(
        () => FrameCodec.encode(
          frame(
            modal(
              sizing: const DetentedModalSheetSizing(
                detents: ModalSheetDetentSet.medium,
                initialDetent: ModalSheetDetent.large,
                dismissOnDrag: true,
                handleSemantics: ModalSheetHandleSemantics(
                  label: 'Adjust sheet height',
                  mediumValue: 'Half height',
                  largeValue: 'Full height',
                ),
              ),
            ),
          ),
        ),
        throwsProtocolCode(ProtocolErrorCode.invalidProps),
      );
      for (final semantics in const [
        ModalSheetHandleSemantics(
          label: '',
          mediumValue: 'Half height',
          largeValue: 'Full height',
        ),
        ModalSheetHandleSemantics(
          label: 'Adjust sheet height',
          mediumValue: '',
          largeValue: 'Full height',
        ),
        ModalSheetHandleSemantics(
          label: 'Adjust sheet height',
          mediumValue: 'Half height',
          largeValue: '',
        ),
        ModalSheetHandleSemantics(
          label: '   ',
          mediumValue: 'Half height',
          largeValue: 'Full height',
        ),
      ]) {
        expect(
          () => FrameCodec.encode(
            frame(
              modal(
                sizing: DetentedModalSheetSizing(
                  detents: ModalSheetDetentSet.mediumAndLarge,
                  initialDetent: ModalSheetDetent.medium,
                  dismissOnDrag: true,
                  handleSemantics: semantics,
                ),
              ),
            ),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }
      final modalFlagsStart = presentationOffset + 1;
      expectDecodeError(
        mutate(encoded, modalFlagsStart, 2),
        ProtocolErrorCode.invalidProps,
      );
      final requestFocusOffset = presentationOffset + 10;
      expectDecodeError(
        mutate(encoded, requestFocusOffset, 2),
        ProtocolErrorCode.invalidProps,
      );
    });

    test('decodes the generated cross-language modal fixture', () {
      final frame = FrameCodec.decode(
        readHexFixture('ocaml_modal_bottom_sheet_update.hex'),
      );
      final props = (frame.operations.single as UpdateProps).props as PageProps;

      expect(props.pageKey, 'editor');
      expect(props.canPop, isTrue);
      expect(props.restorationId, 'editor-page');
      expect(
        props.presentation,
        const ModalBottomSheetPresentation(
          barrierDismissible: true,
          barrierColorArgb: 0x7f102030,
          barrierLabel: 'Close editor',
          sizing: DetentedModalSheetSizing(
            detents: ModalSheetDetentSet.mediumAndLarge,
            initialDetent: ModalSheetDetent.medium,
            dismissOnDrag: true,
            handleSemantics: ModalSheetHandleSemantics(
              label: 'Adjust sheet height',
              mediumValue: 'Half height',
              largeValue: 'Full height',
            ),
          ),
          useSafeArea: true,
          requestFocus: true,
          transitionDurationMilliseconds: 325,
          reverseTransitionDurationMilliseconds: 175,
        ),
      );
    });

    test('round trips byte-exact bounded application requests', () {
      final below = Uint8List.fromList([0, 1, 127, 128, 255]);
      final equal = Uint8List(maximumApplicationPlatformPayloadBytes)
        ..[0] = 1
        ..[maximumApplicationPlatformPayloadBytes - 1] = 255;
      final frame = Frame(
        runtimeEpoch: 71,
        baseRevision: 3,
        targetRevision: 4,
        kind: FrameKind.incremental,
        operations: [
          ApplicationRequestOperation(requestId: 91, payload: below),
          ApplicationRequestOperation(requestId: 92, payload: equal),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      final first = decoded.operations[0] as ApplicationRequestOperation;
      final second = decoded.operations[1] as ApplicationRequestOperation;
      expect(first.requestId, 91);
      expect(first.payload, [0, 1, 127, 128, 255]);
      expect(second.requestId, 92);
      expect(second.payload, orderedEquals(equal));
    });

    test('rejects oversized application request lengths before slicing', () {
      final valid = FrameCodec.encode(
        Frame(
          runtimeEpoch: 71,
          baseRevision: 3,
          targetRevision: 4,
          kind: FrameKind.incremental,
          operations: [
            ApplicationRequestOperation(
              requestId: 91,
              payload: Uint8List.fromList([1]),
            ),
          ],
        ),
      );
      const applicationRequestBodyOffset = ProtocolLimits.headerBytes + 10;
      final malformed = Uint8List.fromList(valid);
      writeUint32(
        malformed,
        applicationRequestBodyOffset + 8,
        maximumApplicationPlatformPayloadBytes + 1,
      );

      expectDecodeError(
        malformed,
        ProtocolErrorCode.applicationPayloadTooLarge,
      );
      expect(
        () => FrameCodec.encode(
          Frame(
            runtimeEpoch: 71,
            baseRevision: 3,
            targetRevision: 4,
            kind: FrameKind.incremental,
            operations: [
              ApplicationRequestOperation(
                requestId: 92,
                payload: Uint8List(maximumApplicationPlatformPayloadBytes + 1),
              ),
            ],
          ),
        ),
        throwsProtocolCode(ProtocolErrorCode.applicationPayloadTooLarge),
      );
    });

    test('round trips layout, semantics, theme, and checkbox properties', () {
      const frame = Frame(
        runtimeEpoch: 9,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.padding,
            props: PaddingProps(
              EdgeInsetsValue(left: 12, top: 8, right: 12, bottom: 8),
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 2,
            kind: NodeKind.center,
            props: CenterProps(widthFactor: null, heightFactor: 1.5),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 3,
            kind: NodeKind.scrollView,
            props: ScrollViewProps(
              axis: ScrollAxis.vertical,
              reverse: false,
              primary: true,
            ),
            eventBindings: [
              EventBinding(
                eventTag: EventTagId.scrollNotification,
                handlerId: 80,
              ),
            ],
          ),
          CreateNode(
            nodeId: 4,
            kind: NodeKind.semantics,
            props: SemanticsProps(
              label: 'Accept terms',
              role: SemanticsRoleValue.checkbox,
              enabled: true,
              checked: false,
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 5,
            kind: NodeKind.theme,
            props: ThemeProps(data: testDarkThemeData),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 6,
            kind: NodeKind.materialCheckbox,
            props: MaterialCheckboxProps(value: false, enabled: true),
            eventBindings: [
              EventBinding(eventTag: EventTagId.valueChanged, handlerId: 81),
            ],
          ),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      final nodes = decoded.operations.whereType<CreateNode>().toList();
      expect(
        nodes.map((node) => node.kind),
        orderedEquals([
          NodeKind.padding,
          NodeKind.center,
          NodeKind.scrollView,
          NodeKind.semantics,
          NodeKind.theme,
          NodeKind.materialCheckbox,
        ]),
      );
      expect(
        nodes.map((node) => node.props),
        orderedEquals([
          const PaddingProps(
            EdgeInsetsValue(left: 12, top: 8, right: 12, bottom: 8),
          ),
          const CenterProps(widthFactor: null, heightFactor: 1.5),
          const ScrollViewProps(
            axis: ScrollAxis.vertical,
            reverse: false,
            primary: true,
          ),
          const SemanticsProps(
            label: 'Accept terms',
            role: SemanticsRoleValue.checkbox,
            enabled: true,
            checked: false,
          ),
          const ThemeProps(data: testDarkThemeData),
          const MaterialCheckboxProps(value: false, enabled: true),
        ]),
      );
    });

    test('rejects primary horizontal scrollables', () {
      for (final props in const <UiProps>[
        ScrollViewProps(
          axis: ScrollAxis.horizontal,
          reverse: false,
          primary: true,
        ),
      ]) {
        final kind = NodeKind.scrollView;
        final frame = Frame(
          runtimeEpoch: 9,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: kind,
              props: props,
              eventBindings: const [],
            ),
            const SetRoot(1),
          ],
        );

        expect(
          () => FrameCodec.encode(frame),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }
    });

    test('enforces sliver u32 boundaries during encoding', () {
      Frame frame(UiProps props, NodeKind kind) => Frame(
        runtimeEpoch: 9,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: kind,
            props: props,
            eventBindings: const [],
          ),
          const SetRoot(1),
        ],
      );

      for (final boundary in const [0, 0xffffffff]) {
        expect(
          FrameCodec.decode(
            FrameCodec.encode(
              frame(
                SliverFixedExtentProps(
                  totalCount: 1,
                  firstIndex: 0,
                  itemExtent: 48,
                  overscan: boundary,
                ),
                NodeKind.sliverFixedExtent,
              ),
            ),
          ),
          isA<Frame>(),
        );
        expect(
          FrameCodec.decode(
            FrameCodec.encode(
              frame(
                SliverVariedExtentProps(
                  totalCount: 1,
                  firstIndex: 0,
                  defaultItemExtent: 48,
                  overscan: boundary,
                  extentOverrides: const [],
                  transition: SparseExtentTransition(
                    enabled: true,
                    expandDurationMs: boundary,
                    collapseDurationMs: boundary,
                    expandCurve: SparseExtentCurve.linear,
                    collapseCurve: SparseExtentCurve.linear,
                  ),
                ),
                NodeKind.sliverVariedExtent,
              ),
            ),
          ),
          isA<Frame>(),
        );
      }

      for (final invalid in const [-1, 0x100000000]) {
        expect(
          () => FrameCodec.encode(
            frame(
              SliverFixedExtentProps(
                totalCount: 1,
                firstIndex: 0,
                itemExtent: 48,
                overscan: invalid,
              ),
              NodeKind.sliverFixedExtent,
            ),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
        expect(
          () => FrameCodec.encode(
            frame(
              SliverVariedExtentProps(
                totalCount: 1,
                firstIndex: 0,
                defaultItemExtent: 48,
                overscan: invalid,
                extentOverrides: const [],
              ),
              NodeKind.sliverVariedExtent,
            ),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
        expect(
          () => FrameCodec.encode(
            frame(
              SliverVariedExtentProps(
                totalCount: 1,
                firstIndex: 0,
                defaultItemExtent: 48,
                overscan: 0,
                extentOverrides: const [],
                transition: SparseExtentTransition(
                  enabled: true,
                  expandDurationMs: invalid,
                  collapseDurationMs: invalid,
                  expandCurve: SparseExtentCurve.linear,
                  collapseCurve: SparseExtentCurve.linear,
                ),
              ),
              NodeKind.sliverVariedExtent,
            ),
          ),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }
    });

    test(
      'enforces virtual sliver window invariants in both codec directions',
      () {
        Frame frame(UiProps props, NodeKind kind) => Frame(
          runtimeEpoch: 9,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: kind,
              props: props,
              eventBindings: const [],
            ),
            const SetRoot(1),
          ],
        );

        for (final entry in <(NodeKind, UiProps)>[
          (
            NodeKind.sliverFixedExtent,
            const SliverFixedExtentProps(
              totalCount: 10,
              firstIndex: 11,
              itemExtent: 48,
              overscan: 0,
            ),
          ),
          (
            NodeKind.sliverVariedExtent,
            const SliverVariedExtentProps(
              totalCount: 10,
              firstIndex: 11,
              defaultItemExtent: 48,
              overscan: 0,
              extentOverrides: [],
            ),
          ),
          (
            NodeKind.sliverVariedExtent,
            const SliverVariedExtentProps(
              totalCount: 10,
              firstIndex: 0,
              defaultItemExtent: 48,
              overscan: 0,
              extentOverrides: [
                SparseExtentOverride(index: 4, extent: 60),
                SparseExtentOverride(index: 3, extent: 70),
              ],
            ),
          ),
          (
            NodeKind.sliverVariedExtent,
            const SliverVariedExtentProps(
              totalCount: 10,
              firstIndex: 0,
              defaultItemExtent: 48,
              overscan: 0,
              extentOverrides: [
                SparseExtentOverride(index: 3, extent: 60),
                SparseExtentOverride(index: 3, extent: 70),
              ],
            ),
          ),
          (
            NodeKind.sliverVariedExtent,
            const SliverVariedExtentProps(
              totalCount: 10,
              firstIndex: 0,
              defaultItemExtent: 48,
              overscan: 0,
              extentOverrides: [SparseExtentOverride(index: 10, extent: 60)],
            ),
          ),
        ]) {
          expect(
            () => FrameCodec.encode(frame(entry.$2, entry.$1)),
            throwsProtocolCode(ProtocolErrorCode.invalidProps),
            reason: 'invalid virtual sliver props were encoded: ${entry.$2}',
          );
        }

        final fixed = FrameCodec.encode(
          frame(
            const SliverFixedExtentProps(
              totalCount: 1001,
              firstIndex: 1000,
              itemExtent: 48,
              overscan: 0,
            ),
            NodeKind.sliverFixedExtent,
          ),
        );
        final invalidFirstIndex = Uint8List.fromList(fixed);
        writeUint64(
          invalidFirstIndex,
          findUint64(invalidFirstIndex, 1000),
          1002,
        );
        expectDecodeError(invalidFirstIndex, ProtocolErrorCode.invalidProps);

        final varied = FrameCodec.encode(
          frame(
            const SliverVariedExtentProps(
              totalCount: 1000,
              firstIndex: 0,
              defaultItemExtent: 48,
              overscan: 0,
              extentOverrides: [
                SparseExtentOverride(index: 101, extent: 60),
                SparseExtentOverride(index: 202, extent: 70),
              ],
            ),
            NodeKind.sliverVariedExtent,
          ),
        );
        final secondOverrideOffset = findUint64(varied, 202);
        for (final invalidIndex in const [101, 100, 1000]) {
          final malformed = Uint8List.fromList(varied);
          writeUint64(malformed, secondOverrideOffset, invalidIndex);
          expectDecodeError(malformed, ProtocolErrorCode.invalidProps);
        }

        for (final entry in <(NodeKind, UiProps)>[
          (
            NodeKind.sliverFixedExtent,
            const SliverFixedExtentProps(
              totalCount: 0,
              firstIndex: 0,
              itemExtent: 48,
              overscan: 0xffffffff,
            ),
          ),
          (
            NodeKind.sliverVariedExtent,
            const SliverVariedExtentProps(
              totalCount: 10,
              firstIndex: 10,
              defaultItemExtent: 48,
              overscan: 0xffffffff,
              extentOverrides: [SparseExtentOverride(index: 9, extent: 60)],
              transition: SparseExtentTransition(
                enabled: true,
                expandDurationMs: 0xffffffff,
                collapseDurationMs: 0xffffffff,
                expandCurve: SparseExtentCurve.linear,
                collapseCurve: SparseExtentCurve.linear,
              ),
            ),
          ),
        ]) {
          expect(
            FrameCodec.decode(FrameCodec.encode(frame(entry.$2, entry.$1))),
            isA<Frame>(),
          );
        }
      },
    );

    test('rejects invalid scroll cache extents in both codec directions', () {
      Frame frame(double cacheExtent) => Frame(
        runtimeEpoch: 9,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.scrollView,
            props: ScrollViewProps(
              axis: ScrollAxis.vertical,
              reverse: false,
              cacheExtent: cacheExtent,
            ),
            eventBindings: const [],
          ),
          const SetRoot(1),
        ],
      );

      expect(
        (FrameCodec.decode(FrameCodec.encode(frame(0))).operations.first
                as CreateNode)
            .props,
        const ScrollViewProps(
          axis: ScrollAxis.vertical,
          reverse: false,
          cacheExtent: 0,
        ),
      );
      for (final invalid in const [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => FrameCodec.encode(frame(invalid)),
          throwsProtocolCode(ProtocolErrorCode.invalidProps),
        );
      }
      final valid = FrameCodec.encode(frame(123.25));
      for (final invalid in const [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expectDecodeError(
          replaceFloat64(valid, 123.25, invalid),
          ProtocolErrorCode.invalidProps,
        );
      }
    });

    test(
      'enforces every sliver app bar invariant in both codec directions',
      () {
        Frame frame(SliverAppBarProps props) => Frame(
          runtimeEpoch: 9,
          baseRevision: 0,
          targetRevision: 1,
          kind: FrameKind.fullSnapshot,
          operations: [
            CreateNode(
              nodeId: 1,
              kind: NodeKind.sliverAppBar,
              props: props,
              eventBindings: const [],
            ),
            const SetRoot(1),
          ],
        );

        const validProps = SliverAppBarProps(
          pinned: true,
          expandedHeight: 200,
          collapsedHeight: 100,
          floating: true,
          snap: true,
          toolbarHeight: 56,
          elevation: 4,
        );
        expect(
          (FrameCodec.decode(
                    FrameCodec.encode(frame(validProps)),
                  ).operations.first
                  as CreateNode)
              .props,
          validProps,
        );

        for (final props in const [
          SliverAppBarProps(pinned: false, toolbarHeight: 0),
          SliverAppBarProps(pinned: false, toolbarHeight: -1),
          SliverAppBarProps(pinned: false, toolbarHeight: double.nan),
          SliverAppBarProps(pinned: false, toolbarHeight: double.infinity),
          SliverAppBarProps(pinned: false, expandedHeight: -1),
          SliverAppBarProps(pinned: false, collapsedHeight: -1),
          SliverAppBarProps(
            pinned: false,
            expandedHeight: 100,
            collapsedHeight: 120,
          ),
          SliverAppBarProps(pinned: false, collapsedHeight: 40),
          SliverAppBarProps(pinned: false, snap: true),
          SliverAppBarProps(pinned: false, elevation: -1),
          SliverAppBarProps(pinned: false, elevation: double.nan),
          SliverAppBarProps(pinned: false, elevation: double.infinity),
        ]) {
          expect(
            () => FrameCodec.encode(frame(props)),
            throwsProtocolCode(ProtocolErrorCode.invalidProps),
            reason: 'invalid props were encoded: $props',
          );
        }

        final valid = FrameCodec.encode(frame(validProps));
        final expandedOffset = findFloat64(valid, 200);
        for (final malformed in [
          replaceFloat64At(valid, expandedOffset, -1),
          replaceFloat64At(valid, expandedOffset, double.nan),
          replaceFloat64At(valid, expandedOffset, double.infinity),
          replaceFloat64(valid, 100, -1),
          replaceFloat64At(valid, expandedOffset, 50),
          replaceFloat64(valid, 100, 40),
          replaceFloat64(valid, 56, 0),
          replaceFloat64(valid, 4, -1),
          replaceFloat64(valid, 4, double.nan),
          replaceFloat64(valid, 4, double.infinity),
        ]) {
          expectDecodeError(malformed, ProtocolErrorCode.invalidProps);
        }
        expectDecodeError(
          mutate(valid, expandedOffset + 17, 0),
          ProtocolErrorCode.invalidProps,
        );
      },
    );

    test('round trips revisioned UTF-16 text input properties', () {
      const props = TextInputProps(
        sessionId: 7,
        documentRevision: 9,
        value: TextEditingStateValue(
          text: '拼😀音',
          selection: TextRangeValue(startUtf16: 4, endUtf16: 4),
          composing: TextRangeValue(startUtf16: 0, endUtf16: 4),
        ),
        enabled: true,
        readOnly: false,
        obscureText: false,
        keyboardType: TextKeyboardType.text,
        inputAction: TextInputActionKind.done,
        acceptedLocalRevision: 11,
        updateMode: TextUpdateMode.correction,
        autofocus: true,
        maxUtf8Bytes: 12,
      );
      const frame = Frame(
        runtimeEpoch: 10,
        baseRevision: 4,
        targetRevision: 5,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 12, props: props)],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect((decoded.operations.single as UpdateProps).props, props);
    });

    test(
      'rejects invalid UTF-8 byte limits while preserving unlimited input',
      () {
        TextInputProps propsWithLimit(int? maxUtf8Bytes) => TextInputProps(
          sessionId: 7,
          documentRevision: 9,
          value: const TextEditingStateValue(
            text: '',
            selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
            composing: null,
          ),
          enabled: true,
          readOnly: false,
          obscureText: false,
          keyboardType: TextKeyboardType.text,
          inputAction: TextInputActionKind.done,
          acceptedLocalRevision: 0,
          updateMode: TextUpdateMode.ack,
          autofocus: false,
          maxUtf8Bytes: maxUtf8Bytes,
        );

        Frame frame(TextInputProps props) => Frame(
          runtimeEpoch: 10,
          baseRevision: 4,
          targetRevision: 5,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 12, props: props)],
        );

        final unlimited = propsWithLimit(null);
        expect(
          (FrameCodec.decode(
                    FrameCodec.encode(frame(unlimited)),
                  ).operations.single
                  as UpdateProps)
              .props,
          unlimited,
        );
        for (final invalid in [
          0,
          -1,
          ProtocolLimits.maxStringBytes + 1,
          0x100000000,
        ]) {
          expect(
            () => FrameCodec.encode(frame(propsWithLimit(invalid))),
            throwsA(isA<ProtocolException>()),
            reason: 'maxUtf8Bytes=$invalid must be protocol-invalid',
          );
        }
      },
    );

    test('decoded full snapshot can be applied atomically', () {
      final decoded = FrameCodec.decode(
        readHexFixture('ocaml_counter_full.hex'),
      );
      final store = NodeStore()..apply(decoded);

      expect(store.runtimeEpoch, 7);
      expect(store.revision, 1);
      expect(store.rootId, 1);
      expect(store.node(2).props, const TextProps('Count: 0'));
    });

    test('round trips the typed core visual and layout surface', () {
      const frame = Frame(
        runtimeEpoch: 9,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 1, props: RichTextProps(['Hello', ' world'])),
          UpdateProps(
            nodeId: 2,
            props: IconProps(
              codePoint: 0xe145,
              fontFamily: 'MaterialIcons',
              size: 20,
              colorArgb: 0xff102030,
            ),
          ),
          UpdateProps(
            nodeId: 3,
            props: ImageProps(
              uri: 'https://example.invalid/image.png',
              fit: ImageFitValue.contain,
              width: 120,
              height: 80,
            ),
          ),
          UpdateProps(nodeId: 4, props: AlignProps(AlignmentValue.bottomEnd)),
          UpdateProps(nodeId: 5, props: SizedBoxProps(width: 100, height: 40)),
          UpdateProps(
            nodeId: 6,
            props: ConstrainedBoxProps(
              minWidth: 10,
              maxWidth: 100,
              minHeight: 20,
              maxHeight: 200,
            ),
          ),
          UpdateProps(
            nodeId: 7,
            props: DecoratedBoxProps(
              backgroundArgb: 0xff28323c,
              borderRadius: 8,
            ),
          ),
          UpdateProps(nodeId: 8, props: ClipProps(ClipBehaviorValue.antiAlias)),
          UpdateProps(nodeId: 9, props: OpacityProps(0.5)),
          UpdateProps(
            nodeId: 10,
            props: TransformProps([
              2,
              0,
              0,
              0,
              0,
              3,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            ]),
          ),
          UpdateProps(nodeId: 11, props: SliverFillProps()),
          UpdateProps(
            nodeId: 12,
            props: SafeAreaProps(
              left: true,
              top: true,
              right: true,
              bottom: true,
              minimum: EdgeInsetsValue(left: 1, top: 2, right: 3, bottom: 4),
            ),
          ),
          UpdateProps(nodeId: 13, props: EnvironmentBoundaryProps()),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      expect(
        decoded.operations.cast<UpdateProps>().map(
          (operation) => operation.props.runtimeType,
        ),
        [
          RichTextProps,
          IconProps,
          ImageProps,
          AlignProps,
          SizedBoxProps,
          ConstrainedBoxProps,
          DecoratedBoxProps,
          ClipProps,
          OpacityProps,
          TransformProps,
          SliverFillProps,
          SafeAreaProps,
          EnvironmentBoundaryProps,
        ],
      );
    });

    test('decodes a frame from a non-zero-offset Uint8List view', () {
      final encoded = FrameCodec.encode(counterSnapshot(text: 'Offset 😀'));
      final backing = Uint8List(encoded.length + 13);
      backing.setRange(7, 7 + encoded.length, encoded);
      final visible = Uint8List.sublistView(backing, 7, 7 + encoded.length);

      final decoded = FrameCodec.decode(visible);

      expect(
        decoded.operations
            .whereType<CreateNode>()
            .map((operation) => operation.props)
            .whereType<TextProps>()
            .single,
        const TextProps('Offset 😀'),
      );
    });

    test('preserves operation body trailing-byte checks', () {
      final valid = FrameCodec.encode(counterSnapshot(text: 'Count: 0'));
      const operationOffset = ProtocolLimits.headerBytes + 5;
      final bodyLength = readUint32(valid, operationOffset + 1);
      final bodyEnd = operationOffset + 5 + bodyLength;
      final withTrailingByte = Uint8List(valid.length + 1)
        ..setRange(0, bodyEnd, valid)
        ..[bodyEnd] = 0
        ..setRange(bodyEnd + 1, valid.length + 1, valid, bodyEnd);
      writeUint32(withTrailingByte, operationOffset + 1, bodyLength + 1);
      writeUint32(withTrailingByte, 36, readUint32(valid, 36) + 1);

      expectDecodeError(withTrailingByte, ProtocolErrorCode.trailingBytes);
    });

    test('rejects malformed headers and payloads deterministically', () {
      final valid = readHexFixture('ocaml_counter_full.hex');

      expectDecodeError(mutate(valid, 0, 0), ProtocolErrorCode.invalidMagic);
      expectDecodeError(
        Uint8List.sublistView(valid, 0, 47),
        ProtocolErrorCode.truncatedInput,
      );
      expectDecodeError(
        mutate(valid, 4, 2),
        ProtocolErrorCode.unsupportedVersion,
      );
      expectDecodeError(mutate(valid, 8, 47), ProtocolErrorCode.invalidHeader);
      expectDecodeError(
        mutate(valid, 10, 99),
        ProtocolErrorCode.invalidFrameKind,
      );
      expectDecodeError(mutate(valid, 11, 1), ProtocolErrorCode.invalidFlags);
      expectDecodeError(mutate(valid, 44, 1), ProtocolErrorCode.invalidHeader);

      final wrongLength = Uint8List.fromList(valid);
      writeUint32(wrongLength, 36, readUint32(valid, 36) + 1);
      expectDecodeError(wrongLength, ProtocolErrorCode.invalidPayloadLength);

      expectDecodeError(
        Uint8List.fromList([...valid, 0]),
        ProtocolErrorCode.invalidPayloadLength,
      );
      expectDecodeError(
        mutate(valid, 48, 0xff),
        ProtocolErrorCode.unknownOperation,
      );
      final firstCreateBody = findOperationBody(valid, OperationId.createNode);
      expectDecodeError(
        mutate(valid, firstCreateBody + 8, 0xff),
        ProtocolErrorCode.unknownNodeKind,
      );
      final textBody = findCreateBody(valid, NodeKindId.text);
      expectDecodeError(
        mutate(valid, textBody + 14, 0xff),
        ProtocolErrorCode.invalidUtf8,
      );
      expectDecodeError(
        mutate(valid, 48, 2),
        ProtocolErrorCode.invalidOperationOrder,
      );
    });

    test('rejects values above configured limits before allocation', () {
      final oversized = 'x' * (ProtocolLimits.maxStringBytes + 1);
      final frame = counterSnapshot(text: oversized);

      expect(
        () => FrameCodec.encode(frame),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.stringTooLarge,
          ),
        ),
      );
    });
  });
}

Matcher throwsProtocolCode(ProtocolErrorCode code) => throwsA(
  isA<ProtocolException>().having((error) => error.code, 'code', code),
);

void expectDecodeError(Uint8List bytes, ProtocolErrorCode code) {
  expect(() => FrameCodec.decode(bytes), throwsProtocolCode(code));
}

Uint8List mutate(Uint8List source, int offset, int value) {
  final result = Uint8List.fromList(source);
  result[offset] = value;
  return result;
}

int readUint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);

int findOperationBody(Uint8List bytes, int operationId) {
  var offset = 48;
  while (offset < bytes.length) {
    final bodyLength = readUint32(bytes, offset + 1);
    if (bytes[offset] == operationId) return offset + 5;
    offset += 5 + bodyLength;
  }
  throw StateError('Operation $operationId not found');
}

int findCreateBody(Uint8List bytes, int nodeKindId) {
  var offset = 48;
  while (offset < bytes.length) {
    final bodyLength = readUint32(bytes, offset + 1);
    final body = offset + 5;
    if (bytes[offset] == OperationId.createNode &&
        readUint16(bytes, body + 8) == nodeKindId) {
      return body;
    }
    offset += 5 + bodyLength;
  }
  throw StateError('CreateNode for kind $nodeKindId not found');
}

int readUint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

int readUint64(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint64(offset, Endian.little);

void writeUint32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);

void writeUint64(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint64(offset, value, Endian.little);

int findUint64(Uint8List bytes, int value) {
  for (var offset = 0; offset <= bytes.length - 8; offset += 1) {
    if (readUint64(bytes, offset) == value) return offset;
  }
  throw StateError('uint64 value $value was not found');
}

int findFloat64(Uint8List bytes, double value) {
  final expected = ByteData(8)..setFloat64(0, value, Endian.little);
  for (var offset = 0; offset <= bytes.length - 8; offset += 1) {
    var matches = true;
    for (var index = 0; index < 8; index += 1) {
      if (bytes[offset + index] != expected.getUint8(index)) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  throw StateError('float64 value $value was not found');
}

Uint8List replaceFloat64(Uint8List source, double before, double after) =>
    replaceFloat64At(source, findFloat64(source, before), after);

Uint8List replaceFloat64At(Uint8List source, int offset, double value) {
  final result = Uint8List.fromList(source);
  ByteData.sublistView(result).setFloat64(offset, value, Endian.little);
  return result;
}
