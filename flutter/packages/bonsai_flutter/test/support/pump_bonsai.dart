import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBonsaiFrames(
  WidgetTester tester, {
  required int count,
  Duration step = const Duration(milliseconds: 16),
}) async {
  if (count < 0) {
    throw RangeError.value(count, 'count');
  }
  for (var frame = 0; frame < count; frame += 1) {
    await tester.pump(step);
  }
}

Future<void> pumpBonsaiUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required int maxFrames,
  Duration step = const Duration(milliseconds: 16),
  String Function()? diagnostics,
}) async {
  if (maxFrames <= 0) {
    throw RangeError.value(maxFrames, 'maxFrames');
  }
  for (var frame = 0; frame < maxFrames; frame += 1) {
    if (predicate()) return;
    await tester.pump(step);
  }
  if (predicate()) return;
  final detail = diagnostics?.call();
  throw TestFailure(
    'Bonsai predicate was not satisfied after $maxFrames frames'
    '${detail == null || detail.isEmpty ? '' : ': $detail'}',
  );
}
