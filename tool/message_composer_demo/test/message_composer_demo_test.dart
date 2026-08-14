import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:message_composer_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with the adaptive composer in its voice state', (
    tester,
  ) async {
    await tester.pumpWidget(const MessageComposerDemoApp());

    expect(find.text('MessageComposer'), findsOneWidget);
    expect(find.text('Adaptive demo'), findsOneWidget);
    expect(
      find.text('Type a draft, then swipe down to collapse it.'),
      findsOneWidget,
    );
    expect(find.byType(MessageComposer), findsOneWidget);
    expect(find.byTooltip('Start voice input'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsNothing);
  });

  testWidgets('downward swipe collapses and tapping reopens the draft', (
    tester,
  ) async {
    await tester.pumpWidget(const MessageComposerDemoApp());
    final composer = find.byType(MessageComposer);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Keep this\ndraft');
    await tester.pumpAndSettle();
    final expandedHeight = tester.getSize(composer).height;

    await tester.drag(composer, const Offset(0, 80));
    await tester.pumpAndSettle();
    final collapsedHeight = tester.getSize(composer).height;

    expect(collapsedHeight, lessThan(expandedHeight));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this\ndraft',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(composer).height, greaterThan(collapsedHeight));
  });

  testWidgets('sending adds a message and resets to voice state', (
    tester,
  ) async {
    await tester.pumpWidget(const MessageComposerDemoApp());

    await tester.enterText(find.byType(TextField), '  Ship the adaptive UI  ');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '  Ship the adaptive UI  ',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '  Ship the adaptive UI  ',
    );
    expect(find.byTooltip('Send message'), findsOneWidget);
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();

    expect(find.text('Ship the adaptive UI'), findsOneWidget);
    expect(
      find.text('Message received by the temporary demo.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.byTooltip('Start voice input'), findsOneWidget);
  });

  testWidgets('secondary actions provide visible feedback', (tester) async {
    await tester.pumpWidget(const MessageComposerDemoApp());

    for (final action in <(String, String)>[
      ('Add attachment', 'Attachment action'),
      ('Open input tools', 'Input tools action'),
      ('Start dictation', 'Dictation action'),
      ('Start voice input', 'Voice action'),
    ]) {
      await tester.tap(find.byTooltip(action.$1));
      await tester.pump();
      expect(find.text(action.$2), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('theme toggle switches between dark and light modes', (
    tester,
  ) async {
    await tester.pumpWidget(const MessageComposerDemoApp());

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.byTooltip('Use light theme'));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(find.byTooltip('Use dark theme'), findsOneWidget);
  });
}
