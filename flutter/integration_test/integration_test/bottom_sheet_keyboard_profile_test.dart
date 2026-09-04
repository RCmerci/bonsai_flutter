import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter/src/navigation/modal_bottom_sheet_route.dart';
import 'package:bonsai_flutter/src/text_input/text_input_host.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _recordBaseline = bool.fromEnvironment('BONSAI_RECORD_KEYBOARD_BASELINE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('modal entrance and automatic keyboard use separate phases', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_ProfileHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _ProfileHarness(key: harnessKey)),
    );
    await tester.pumpAndSettle();

    final samples = <Map<String, Object>>[];
    await binding.traceAction(() async {
      harnessKey.currentState!.pushCompose();
      await tester.pump();
      var stableKeyboardFrames = 0;
      var previousInset = -1.0;
      for (var frame = 0; frame < 150; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
        final editableFinder = find.byType(EditableText);
        final route = harnessKey.currentState!.composeRoute;
        if (editableFinder.evaluate().isEmpty || route == null) continue;
        final context = tester.element(editableFinder);
        final view = View.of(context);
        final devicePixelRatio = view.devicePixelRatio;
        final viewportHeight = view.physicalSize.height / devicePixelRatio;
        final bottomInset = view.viewInsets.bottom / devicePixelRatio;
        final sheetRect = tester.getRect(_roundedModalSheetSurfaceFinder());
        final focused = tester
            .widget<EditableText>(editableFinder)
            .focusNode
            .hasFocus;
        samples.add({
          'frame': frame,
          'route_progress': route.animation!.value,
          'route_duration_millis': route.transitionDuration.inMilliseconds,
          'disable_animations': MediaQuery.disableAnimationsOf(context),
          'accessible_navigation': MediaQuery.accessibleNavigationOf(context),
          'sheet_top': sheetRect.top,
          'sheet_bottom': sheetRect.bottom,
          'keyboard_top': viewportHeight - bottomInset,
          'bottom_inset': bottomInset,
          'focused': focused,
        });

        final keyboardStable =
            bottomInset > 0 && (bottomInset - previousInset).abs() < 0.5;
        stableKeyboardFrames = keyboardStable ? stableKeyboardFrames + 1 : 0;
        previousInset = bottomInset;
        if (route.animation!.status == AnimationStatus.completed &&
            stableKeyboardFrames >= 10) {
          break;
        }
      }
    }, reportKey: 'bottom_sheet_keyboard_entrance');

    final harness = harnessKey.currentState!;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['bottom_sheet_record_baseline'] = _recordBaseline;
    binding.reportData!['bottom_sheet_keyboard_choreography'] = samples;
    binding.reportData!['bottom_sheet_route_progress'] = harness.routeSamples;
    binding.reportData!['bottom_sheet_focus_route_progress'] =
        harness.firstFocusRouteProgress;
    expect(samples, isNotEmpty);
    expect(
      harness.routeSamples.any(
        (sample) => (sample['route_progress']! as double) < 0.99,
      ),
      isTrue,
      reason: 'The Profile fixture must sample the live route entrance.',
    );
    expect(
      samples.any((sample) => (sample['bottom_inset']! as double) > 0),
      isTrue,
      reason: 'The physical-device lane requires the software keyboard.',
    );
    if (!_recordBaseline) {
      _verifyStagedChoreography(
        samples,
        firstFocusRouteProgress: harness.firstFocusRouteProgress,
      );
    }
  });
}

void _verifyStagedChoreography(
  List<Map<String, Object>> samples, {
  required double? firstFocusRouteProgress,
}) {
  expect(
    firstFocusRouteProgress,
    isNotNull,
    reason: 'The autofocus input never acquired focus.',
  );
  expect(
    firstFocusRouteProgress!,
    closeTo(1, 0.001),
    reason: 'Automatic focus must begin only after the route settles.',
  );

  final keyboardSamples = samples
      .where((sample) => (sample['bottom_inset']! as double) > 0.5)
      .toList(growable: false);
  expect(keyboardSamples, isNotEmpty);
  final settledSamples = samples
      .where((sample) => (sample['route_progress']! as double) >= 0.999)
      .toList(growable: false);
  expect(settledSamples, isNotEmpty);
  final settledSheetTop = settledSamples.first['sheet_top']! as double;
  final settledSheetBottom = settledSamples.first['sheet_bottom']! as double;
  for (final sample in settledSamples) {
    expect(sample['route_progress']! as double, closeTo(1, 0.001));
    expect(sample['sheet_top']! as double, closeTo(settledSheetTop, 1));
    expect(sample['sheet_bottom']! as double, closeTo(settledSheetBottom, 1));
  }
  for (final sample in keyboardSamples) {
    expect(
      sample['sheet_bottom']! as double,
      closeTo(
        (sample['keyboard_top']! as double) +
            (sample['bottom_inset']! as double),
        1,
      ),
    );
  }

  _expectMonotonic(
    samples.map((sample) => sample['sheet_top']! as double),
    nonIncreasing: true,
    label: 'sheet top',
  );
  _expectMonotonic(
    keyboardSamples.map((sample) => sample['keyboard_top']! as double),
    nonIncreasing: true,
    label: 'keyboard top',
  );
}

void _expectMonotonic(
  Iterable<double> values, {
  required bool nonIncreasing,
  required String label,
}) {
  final samples = values.toList(growable: false);
  for (var index = 1; index < samples.length; index += 1) {
    final delta = samples[index] - samples[index - 1];
    if (nonIncreasing) {
      expect(delta, lessThanOrEqualTo(1), reason: '$label reversed at $index');
    } else {
      expect(
        delta,
        greaterThanOrEqualTo(-1),
        reason: '$label reversed at $index',
      );
    }
  }
}

Finder _roundedModalSheetSurfaceFinder() => find.byWidgetPredicate((widget) {
  if (widget is! Material || widget.clipBehavior != Clip.antiAlias) {
    return false;
  }
  final shape = widget.shape;
  return shape is RoundedRectangleBorder &&
      shape.borderRadius ==
          const BorderRadius.vertical(top: Radius.circular(24));
});

final class _ProfileHarness extends StatefulWidget {
  const _ProfileHarness({super.key});

  @override
  State<_ProfileHarness> createState() => _ProfileHarnessState();
}

final class _ProfileHarnessState extends State<_ProfileHarness> {
  final _resources = RendererResourceStore();
  final _inputStore = NodeStore();
  final _stopwatch = Stopwatch();
  final routeSamples = <Map<String, Object>>[];
  late final _ProfileNavigatorObserver _observer;
  late final TextInputResourceHandle _inputHandle;
  BonsaiModalBottomSheetRoute? composeRoute;
  double? firstFocusRouteProgress;
  bool _showCompose = false;

  @override
  void initState() {
    super.initState();
    _inputStore.apply(_textInputSnapshot());
    _resources.synchronize(_inputStore);
    _inputHandle = _resources.acquireTextInput(
      9,
      _textInputProps.textInputProps,
    );
    _inputHandle.focusNode.addListener(_recordFocus);
    _observer = _ProfileNavigatorObserver(_observeComposeRoute);
  }

  void pushCompose() {
    _stopwatch
      ..reset()
      ..start();
    setState(() => _showCompose = true);
  }

  void _observeComposeRoute(BonsaiModalBottomSheetRoute route) {
    composeRoute = route;
    route.animation!.addListener(_recordRouteProgress);
    _recordRouteProgress();
  }

  void _recordRouteProgress() {
    final route = composeRoute;
    if (route == null) return;
    routeSamples.add({
      'elapsed_microseconds': _stopwatch.elapsedMicroseconds,
      'route_progress': route.animation!.value,
      'focused': _inputHandle.focusNode.hasFocus,
    });
  }

  void _recordFocus() {
    if (!_inputHandle.focusNode.hasFocus || firstFocusRouteProgress != null) {
      return;
    }
    firstFocusRouteProgress = composeRoute?.animation?.value;
  }

  @override
  void dispose() {
    composeRoute?.animation?.removeListener(_recordRouteProgress);
    _inputHandle.focusNode.removeListener(_recordFocus);
    _resources.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    observers: [_observer],
    pages: [
      const MaterialPage<void>(
        key: ValueKey('keyboard-profile-inbox'),
        canPop: false,
        child: Scaffold(body: Center(child: Text('Keyboard profile inbox'))),
      ),
      if (_showCompose)
        BonsaiModalBottomSheetPage(
          key: const ValueKey('keyboard-profile-compose'),
          canPop: true,
          presentation: const ModalBottomSheetPresentation(
            barrierDismissible: true,
            barrierColorArgb: 0x8a000000,
            barrierLabel: 'Close compose',
            sizing: ScrollControlledModalSheetSizing(),
            useSafeArea: true,
            requestFocus: true,
            transitionDurationMilliseconds: 250,
            reverseTransitionDurationMilliseconds: 200,
          ),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const Text('New message'),
                TextInputHost(
                  node: _inputStore.nodes[9]!,
                  props: _textInputProps.textInputProps,
                  resources: _resources,
                ),
              ],
            ),
          ),
        ),
    ],
    onDidRemovePage: (_) {},
  );
}

final class _ProfileNavigatorObserver extends NavigatorObserver {
  _ProfileNavigatorObserver(this.onComposePush);

  final void Function(BonsaiModalBottomSheetRoute route) onComposePush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is BonsaiModalBottomSheetRoute) onComposePush(route);
  }
}

const _textInputProps = MaterialTextFieldProps(
  sessionId: 98,
  documentRevision: 1,
  value: TextEditingStateValue(
    text: '',
    selection: TextRangeValue(startUtf16: 0, endUtf16: 0),
    composing: null,
  ),
  enabled: true,
  readOnly: false,
  obscureText: false,
  keyboardType: TextKeyboardType.multiline,
  inputAction: TextInputActionKind.newline,
  acceptedLocalRevision: 0,
  updateMode: TextUpdateMode.forceReplace,
  autofocus: true,
  maxUtf8Bytes: null,
  variant: 0,
  label: null,
  supportingText: null,
  errorText: null,
  hasLeading: false,
  hasTrailing: false,
  maxLines: 1,
);

Frame _textInputSnapshot() => const Frame(
  runtimeEpoch: 98,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    CreateNode(
      nodeId: 9,
      kind: NodeKind.materialTextField,
      props: _textInputProps,
      eventBindings: [],
    ),
    SetRoot(9),
  ],
);
