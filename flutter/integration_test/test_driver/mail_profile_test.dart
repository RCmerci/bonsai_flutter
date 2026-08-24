import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

const _frameBudgetMillis = 16.0;
const _minimumFrameCount = 20;
const _reportKeys = [
  'mail_detail_entrance',
  'mail_edge_pop_cancel',
  'mail_edge_pop_commit',
  'mail_row_swipe_cancel',
  'mail_row_swipe_commit',
  'mail_drawer_cancel',
  'mail_drawer_commit',
  'mail_bottom_switch',
  'mail_virtual_append',
];

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) {
      throw StateError('Mail Profile test returned no timeline data');
    }
    final startupSamples = List<Map<String, dynamic>>.from(
      (data['mail_real_row_startup']! as List<dynamic>).map(
        (sample) => Map<String, dynamic>.from(sample as Map<dynamic, dynamic>),
      ),
    );
    final reports = <String, dynamic>{'mail_real_row_startup': startupSamples};
    for (final sample in startupSamples) {
      stdout.writeln('mail_real_row_startup: $sample');
    }
    for (final key in _reportKeys) {
      final timelineJson = Map<String, dynamic>.from(
        data[key]! as Map<dynamic, dynamic>,
      );
      final summary = TimelineSummary.summarize(
        Timeline.fromJson(timelineJson),
      );
      final report = <String, dynamic>{
        'frame_count': summary.countFrames(),
        'raster_frame_count': summary.countRasterizations(),
        '90th_percentile_frame_build_time_millis': summary
            .computePercentileFrameBuildTimeMillis(90),
        '90th_percentile_frame_rasterizer_time_millis': summary
            .computePercentileFrameRasterizerTimeMillis(90),
        'missed_frame_build_budget_count': summary
            .computeMissedFrameBuildBudgetCount(),
        'missed_frame_rasterizer_budget_count': summary
            .computeMissedFrameRasterizerBudgetCount(),
      };
      _verifyReport(key, report);
      reports[key] = report;
      stdout.writeln('$key: $report');
    }
    await writeResponseData(
      reports,
      testOutputFilename: 'mail_profile_summary',
    );
  },
);

void _verifyReport(String key, Map<String, dynamic> report) {
  final frameCount = report['frame_count']! as int;
  final buildP90 = report['90th_percentile_frame_build_time_millis']! as double;
  final rasterP90 =
      report['90th_percentile_frame_rasterizer_time_millis']! as double;
  if (frameCount < _minimumFrameCount) {
    throw StateError('$key recorded only $frameCount frames');
  }
  if (buildP90 > _frameBudgetMillis) {
    throw StateError(
      '$key build p90 ${buildP90}ms exceeded ${_frameBudgetMillis}ms',
    );
  }
  if (rasterP90 > _frameBudgetMillis) {
    throw StateError(
      '$key raster p90 ${rasterP90}ms exceeded ${_frameBudgetMillis}ms',
    );
  }
}
