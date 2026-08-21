import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null || data['patch_size_profile'] == null) {
      throw StateError('Patch-size Profile test returned no measurements');
    }
    final results = <Map<String, dynamic>>[];
    for (final rawResult in data['patch_size_profile']! as List<dynamic>) {
      final result = Map<String, dynamic>.from(
        rawResult! as Map<dynamic, dynamic>,
      );
      final samples = <Map<String, dynamic>>[];
      for (final rawSample in result['samples']! as List<dynamic>) {
        final sample = Map<String, dynamic>.from(
          rawSample! as Map<dynamic, dynamic>,
        );
        final reportKey = sample.remove('report_key')! as String;
        final timelineJson = Map<String, dynamic>.from(
          data[reportKey]! as Map<dynamic, dynamic>,
        );
        final summary = TimelineSummary.summarize(
          Timeline.fromJson(timelineJson),
        );
        final frameCount = summary.countFrames();
        final rasterFrameCount = summary.countRasterizations();
        if (frameCount == 0 || rasterFrameCount == 0) {
          throw StateError('$reportKey recorded no complete Flutter frame');
        }
        final buildMicroseconds =
            (summary.computePercentileFrameBuildTimeMillis(100) * 1000).round();
        final rasterMicroseconds =
            (summary.computePercentileFrameRasterizerTimeMillis(100) * 1000)
                .round();
        sample.addAll({
          'frame_count': frameCount,
          'raster_frame_count': rasterFrameCount,
          'build_microseconds': buildMicroseconds,
          'raster_microseconds': rasterMicroseconds,
          'budget_stage_microseconds': math.max(
            buildMicroseconds,
            rasterMicroseconds,
          ),
        });
        samples.add(sample);
      }
      result['samples'] = samples;
      results.add(result);
    }
    await writeResponseData({
      'results': results,
    }, testOutputFilename: 'patch_size_profile_summary');
  },
);
