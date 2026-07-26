import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('physical iOS environment exposes real device metrics', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    expect(binding.platformDispatcher.views, isNotEmpty);

    final view = binding.platformDispatcher.views.first;
    expect(view.physicalSize.width, greaterThan(0));
    expect(view.physicalSize.height, greaterThan(0));
    expect(view.devicePixelRatio, greaterThan(0));
    expect([
      view.viewPadding.top,
      view.viewPadding.right,
      view.viewPadding.bottom,
      view.viewPadding.left,
    ], everyElement(greaterThanOrEqualTo(0)));
    expect(binding.platformDispatcher.locales, isNotEmpty);
    expect(MediaQueryData.fromView(view).textScaler.scale(1), greaterThan(0));
    expect(
      binding.platformDispatcher.platformBrightness,
      anyOf(Brightness.light, Brightness.dark),
    );
  });
}
