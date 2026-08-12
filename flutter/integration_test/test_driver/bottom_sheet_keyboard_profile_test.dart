import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

const _frameBudgetMillis = 16.0;
const _minimumFrameCount = 20;

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) {
      throw StateError('Bottom-sheet keyboard Profile test returned no data');
    }
    final timelineJson = Map<String, dynamic>.from(
      data['bottom_sheet_keyboard_entrance']! as Map<dynamic, dynamic>,
    );
    final summary = TimelineSummary.summarize(Timeline.fromJson(timelineJson));
    final recordBaseline = data['bottom_sheet_record_baseline']! as bool;
    final report = <String, dynamic>{
      'record_baseline': recordBaseline,
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
      'choreography': data['bottom_sheet_keyboard_choreography'],
      'route_progress': data['bottom_sheet_route_progress'],
      'first_focus_route_progress': data['bottom_sheet_focus_route_progress'],
    };
    _verifyReport(report);
    stdout.writeln('bottom_sheet_keyboard_entrance: $report');
    await writeResponseData(
      report,
      testOutputFilename: recordBaseline
          ? 'bottom_sheet_keyboard_profile_baseline'
          : 'bottom_sheet_keyboard_profile_summary',
    );
  },
);

void _verifyReport(Map<String, dynamic> report) {
  final frameCount = report['frame_count']! as int;
  final buildP90 = report['90th_percentile_frame_build_time_millis']! as double;
  final rasterP90 =
      report['90th_percentile_frame_rasterizer_time_millis']! as double;
  if (frameCount < _minimumFrameCount) {
    throw StateError('Keyboard entrance recorded only $frameCount frames');
  }
  if (buildP90 > _frameBudgetMillis) {
    throw StateError(
      'Keyboard entrance build p90 ${buildP90}ms exceeded '
      '${_frameBudgetMillis}ms',
    );
  }
  if (rasterP90 > _frameBudgetMillis) {
    throw StateError(
      'Keyboard entrance raster p90 ${rasterP90}ms exceeded '
      '${_frameBudgetMillis}ms',
    );
  }
}
