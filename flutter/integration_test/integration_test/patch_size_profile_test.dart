import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _configuredCounts = String.fromEnvironment(
  'BONSAI_PATCH_SIZE_COUNTS',
  defaultValue: '32,64,128,256,512,1024,2048,4096',
);
const _warmupCount = int.fromEnvironment(
  'BONSAI_PATCH_SIZE_WARMUPS',
  defaultValue: 1,
);
const _sampleCount = int.fromEnvironment(
  'BONSAI_PATCH_SIZE_SAMPLES',
  defaultValue: 5,
);
const _waitAttempts = 600;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('OCaml patch sizes are correlated with Profile frame timings', (
    tester,
  ) async {
    final counts = _parseCounts(_configuredCounts);
    BonsaiFlutterDebug.reset();
    await tester.pumpWidget(
      BonsaiFlutterRoot(
        config: Uint8List.fromList(utf8.encode('patch_size_profile')),
      ),
    );
    await _waitForPresent(tester, find.text('Expand ${counts.first}'));

    final results = <Map<String, Object>>[];
    for (final count in counts) {
      final samples = <Map<String, Object>>[];
      for (
        var iteration = 0;
        iteration < _warmupCount + _sampleCount;
        iteration += 1
      ) {
        final expandLabel = 'Expand $count';
        final collapseLabel = 'Collapse $count';
        await _prepareControl(tester, expandLabel);
        late final BonsaiFlutterFrameStats expansion;
        String? reportKey;
        if (iteration < _warmupCount) {
          expansion = await _pressPreparedControl(
            tester,
            pressLabel: expandLabel,
            nextLabel: collapseLabel,
          );
        } else {
          reportKey = 'patch_size_${count}_${iteration - _warmupCount}';
          await binding.traceAction(() async {
            expansion = await _pressPreparedControl(
              tester,
              pressLabel: expandLabel,
              nextLabel: collapseLabel,
            );
            await tester.pump(const Duration(milliseconds: 16));
            await tester.pump(const Duration(milliseconds: 16));
          }, reportKey: reportKey);
        }
        expect(expansion.patchBytes, greaterThan(0));
        expect(expansion.patchCount, greaterThanOrEqualTo(count));
        expect(expansion.dirtyNodeCount, greaterThanOrEqualTo(count));
        if (reportKey != null) {
          samples.add(_sample(expansion, reportKey: reportKey));
        }
        await _prepareControl(tester, collapseLabel);
        await _pressPreparedControl(
          tester,
          pressLabel: collapseLabel,
          nextLabel: expandLabel,
        );
      }
      results.add({'node_count': count, 'samples': samples});
    }

    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['patch_size_profile'] = results;
    expect(results, hasLength(counts.length));
    expect(
      results.every(
        (result) => (result['samples']! as List).length == _sampleCount,
      ),
      isTrue,
    );
  });
}

List<int> _parseCounts(String configured) {
  final counts = configured
      .split(',')
      .map((value) => int.parse(value.trim()))
      .toList(growable: false);
  if (counts.isEmpty || counts.any((count) => count <= 0)) {
    throw ArgumentError.value(configured, 'BONSAI_PATCH_SIZE_COUNTS');
  }
  return counts;
}

Future<void> _prepareControl(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
}

Future<BonsaiFlutterFrameStats> _pressPreparedControl(
  WidgetTester tester, {
  required String pressLabel,
  required String nextLabel,
}) async {
  final previousRevision = BonsaiFlutterDebug.frameStats().last.revision;
  final control = find.text(pressLabel);
  await tester.tap(control);
  for (var attempt = 0; attempt < _waitAttempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 8));
    final candidates = BonsaiFlutterDebug.frameStats().where(
      (stats) =>
          stats.revision > previousRevision &&
          stats.frameKind == FrameKind.incremental &&
          stats.nodeStoreApplyDuration != null,
    );
    if (find.text(nextLabel).evaluate().isNotEmpty && candidates.isNotEmpty) {
      return candidates.last;
    }
  }
  fail('Timed out waiting for $pressLabel to produce a timed frame');
}

Map<String, Object> _sample(
  BonsaiFlutterFrameStats stats, {
  required String reportKey,
}) => {
  'report_key': reportKey,
  'patch_bytes': stats.patchBytes,
  'patch_count': stats.patchCount,
  'dirty_node_count': stats.dirtyNodeCount,
  'decode_microseconds': stats.decodeDuration!.inMicroseconds,
  'apply_microseconds': stats.nodeStoreApplyDuration!.inMicroseconds,
};

Future<void> _waitForPresent(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < _waitAttempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 8));
  }
  fail('Timed out waiting for the target widget');
}
