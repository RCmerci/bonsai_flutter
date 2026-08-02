import 'package:code_assets/code_assets.dart';
import 'package:hooks/src/test.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  test('no-ops when the invoker does not request code assets', () async {
    await testBuildHook(
      mainMethod: build_hook.main,
      extensions: const [],
      check: (input, output) {
        expect(input.config.buildCodeAssets, isFalse);
        expect(output.assets.encodedAssets, isEmpty);
      },
    );
  });

  test('still builds the native library when code assets are requested', () {
    expect(
      testCodeBuildHook(
        mainMethod: build_hook.main,
        check: (input, output) {
          expect(input.config.buildCodeAssets, isTrue);
          expect(output.assets.encodedAssets, hasLength(1));
        },
      ),
      completes,
    );
  });

  group('conditional system SQLite linking', () {
    test('is absent by default and when explicitly disabled', () {
      expect(build_hook.systemLinkFlagsForTesting(OS.macOS, null), isEmpty);
      expect(build_hook.systemLinkFlagsForTesting(OS.iOS, false), isEmpty);
      expect(build_hook.systemLinkFlagsForTesting(OS.macOS, 'false'), isEmpty);
    });

    test('adds Apple system SQLite only for opted-in Apple targets', () {
      expect(build_hook.systemLinkFlagsForTesting(OS.macOS, true), [
        '-lsqlite3',
      ]);
      expect(build_hook.systemLinkFlagsForTesting(OS.iOS, 'true'), [
        '-lsqlite3',
      ]);
      expect(build_hook.systemLinkFlagsForTesting(OS.linux, true), isEmpty);
    });

    test('rejects non-boolean SQLite user defines', () {
      expect(
        () => build_hook.systemLinkFlagsForTesting(OS.macOS, 'yes'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => build_hook.systemLinkFlagsForTesting(OS.iOS, 1),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
