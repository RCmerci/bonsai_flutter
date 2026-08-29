import 'package:flutter/foundation.dart';

import '../protocol/frame.dart';
import '../store/node_store.dart';
import 'frame_stats.dart';

abstract final class BonsaiFlutterDebug {
  static List<BonsaiFlutterFrameStats> frameStats() =>
      DebugFrameRecorder.snapshot();

  static String dumpNodeStore(NodeStore store) {
    if (kReleaseMode) return '<debug dump disabled>';
    final rootId = store.rootId;
    if (rootId == null) return '<empty NodeStore>';
    final output = StringBuffer();

    void writeNode(int nodeId, int depth) {
      final node = store.node(nodeId);
      if (output.isNotEmpty) output.writeln();
      output
        ..write('  ' * depth)
        ..write(_kindName(node.kind))
        ..write(' id=${node.id}');
      if (node.props case TextProps(:final value)) {
        output.write(' ${_quoted(value)}');
      }
      for (final childId in node.children) {
        writeNode(childId, depth + 1);
      }
    }

    writeNode(rootId, 0);
    return output.toString();
  }

  static void reset() => DebugFrameRecorder.reset();
}

String _kindName(NodeKind kind) => switch (kind) {
  NodeKind.empty => 'Empty',
  NodeKind.text => 'Text',
  NodeKind.richText => 'RichText',
  NodeKind.icon => 'Icon',
  NodeKind.image => 'Image',
  NodeKind.row => 'Row',
  NodeKind.column => 'Column',
  NodeKind.stack => 'Stack',
  NodeKind.button => 'Button',
  NodeKind.padding => 'Padding',
  NodeKind.align => 'Align',
  NodeKind.center => 'Center',
  NodeKind.sizedBox => 'SizedBox',
  NodeKind.constrainedBox => 'ConstrainedBox',
  NodeKind.decoratedBox => 'DecoratedBox',
  NodeKind.clip => 'Clip',
  NodeKind.opacity => 'Opacity',
  NodeKind.animatedOpacity => 'AnimatedOpacity',
  NodeKind.transform => 'Transform',
  NodeKind.scrollView => 'ScrollView',
  NodeKind.sliverBox => 'SliverBox',
  NodeKind.sliverList => 'SliverList',
  NodeKind.sliverFill => 'SliverFill',
  NodeKind.sliverFixedExtent => 'SliverFixedExtent',
  NodeKind.sliverVariedExtent => 'SliverVariedExtent',
  NodeKind.sliverPadding => 'SliverPadding',
  NodeKind.sliverAppBar => 'SliverAppBar',
  NodeKind.preferredSize => 'PreferredSize',
  NodeKind.gesture => 'Gesture',
  NodeKind.focusScope => 'FocusScope',
  NodeKind.mouseRegion => 'MouseRegion',
  NodeKind.keyboardListener => 'KeyboardListener',
  NodeKind.pressable => 'Pressable',
  NodeKind.semantics => 'Semantics',
  NodeKind.theme => 'Theme',
  NodeKind.materialScaffold => 'MaterialScaffold',
  NodeKind.materialAppBar => 'MaterialAppBar',
  NodeKind.materialElevatedButton => 'MaterialElevatedButton',
  NodeKind.materialTextButton => 'MaterialTextButton',
  NodeKind.materialIconButton => 'MaterialIconButton',
  NodeKind.materialFilledButton => 'MaterialFilledButton',
  NodeKind.materialFilledTonalButton => 'MaterialFilledTonalButton',
  NodeKind.materialOutlinedButton => 'MaterialOutlinedButton',
  NodeKind.materialFloatingActionButton => 'MaterialFloatingActionButton',
  NodeKind.materialNavigationBar => 'MaterialNavigationBar',
  NodeKind.materialRadioGroup => 'MaterialRadioGroup',
  NodeKind.materialSlider => 'MaterialSlider',
  NodeKind.materialRangeSlider => 'MaterialRangeSlider',
  NodeKind.materialActionChip => 'MaterialActionChip',
  NodeKind.materialFilterChip => 'MaterialFilterChip',
  NodeKind.materialChoiceChip => 'MaterialChoiceChip',
  NodeKind.materialInputChip => 'MaterialInputChip',
  NodeKind.materialAlertDialog => 'MaterialAlertDialog',
  NodeKind.materialSearchBar => 'MaterialSearchBar',
  NodeKind.materialTooltip => 'MaterialTooltip',
  NodeKind.materialDataTable => 'MaterialDataTable',
  NodeKind.materialStepper => 'MaterialStepper',
  NodeKind.materialExpansionPanelList => 'MaterialExpansionPanelList',
  NodeKind.materialSimpleDialog => 'MaterialSimpleDialog',
  NodeKind.materialFullscreenDialog => 'MaterialFullscreenDialog',
  NodeKind.materialCheckbox => 'MaterialCheckbox',
  NodeKind.materialSwitch => 'MaterialSwitch',
  NodeKind.materialListTile => 'MaterialListTile',
  NodeKind.materialDivider => 'MaterialDivider',
  NodeKind.materialCard => 'MaterialCard',
  NodeKind.materialCircularProgressIndicator =>
    'MaterialCircularProgressIndicator',
  NodeKind.materialLinearProgressIndicator => 'MaterialLinearProgressIndicator',
  NodeKind.materialSegmentedButton => 'MaterialSegmentedButton',
  NodeKind.cupertinoButton => 'CupertinoButton',
  NodeKind.cupertinoSwitch => 'CupertinoSwitch',
  NodeKind.textInput => 'TextInput',
  NodeKind.overlay => 'Overlay',
  NodeKind.navigator => 'Navigator',
  NodeKind.page => 'Page',
  NodeKind.safeArea => 'SafeArea',
  NodeKind.environmentBoundary => 'EnvironmentBoundary',
  NodeKind.nativeWidget => 'NativeWidget',
};

String _quoted(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}
