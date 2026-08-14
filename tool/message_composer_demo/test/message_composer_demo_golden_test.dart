import 'dart:io';

import 'package:message_composer_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(_loadSdkFonts);

  testWidgets('renders the populated adaptive demo', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(860, 1680);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MessageComposerDemoApp());
    await tester.enterText(
      find.byType(TextField),
      'Build a concise release plan',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 220));

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile(
        '../../../artifacts/example-screenshots/message-composer-demo.png',
      ),
    );
  });
}

Future<void> _loadSdkFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is required for MessageComposer goldens');
  }
  final fontDirectory = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _loadFonts('Roboto', [
    '$fontDirectory/Roboto-Regular.ttf',
    '$fontDirectory/Roboto-Medium.ttf',
    '$fontDirectory/Roboto-Bold.ttf',
  ]);
  await _loadFont('MaterialIcons', '$fontDirectory/MaterialIcons-Regular.otf');
}

Future<void> _loadFonts(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = await File(path).readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}
