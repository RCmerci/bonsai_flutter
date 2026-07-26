import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('environment reporter emits only semantic changes', (
    tester,
  ) async {
    final events = <RendererEvent>[];

    Future<void> pump(Size size) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 2,
          textScaler: const TextScaler.linear(1.25),
          platformBrightness: Brightness.dark,
          padding: const EdgeInsets.only(top: 24),
          viewInsets: const EdgeInsets.only(bottom: 280),
          highContrast: true,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EnvironmentReporter(
            onEvent: events.add,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await pump(const Size(1440, 900));
    await tester.pump();
    expect(events, hasLength(1));
    final first = events.single.payload as EnvironmentEventPayload;
    expect(first.snapshot.viewportWidth, 1440);
    expect(first.snapshot.viewportHeight, 900);
    expect(first.snapshot.textScale, 1.25);
    expect(first.snapshot.brightness, EnvironmentBrightness.dark);
    expect(first.snapshot.highContrast, isTrue);

    await pump(const Size(1440, 900));
    await tester.pump();
    expect(events, hasLength(1));

    await pump(const Size(1200, 900));
    await tester.pump();
    expect(events, hasLength(2));
    expect(
      (events.last.payload as EnvironmentEventPayload).snapshot.viewportWidth,
      1200,
    );
  });
}
