import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
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
        userDefines: _userDefines({'macos_deployment_target': '26.0'}),
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

  group('iOS deployment target override', () {
    test('uses the workspace deployment target for native compilation', () {
      expect(build_hook.iOSMinimumVersionForTesting(14, '15.0'), '15.0');
      expect(build_hook.iOSDeploymentTargetFlagsForTesting(14, '15.0'), [
        '-mios-version-min=15.0',
      ]);
    });

    test('falls back to the Flutter native-assets target', () {
      expect(build_hook.iOSMinimumVersionForTesting(14, null), '14.0');
      expect(build_hook.iOSDeploymentTargetFlagsForTesting(14, null), isEmpty);
    });

    test('rejects malformed workspace deployment targets', () {
      for (final value in <Object>['15', '15.x', 15, true]) {
        expect(
          () => build_hook.iOSMinimumVersionForTesting(14, value),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('macOS platform contract', () {
    test('links the produced library with macOS minimum 26.0', () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        targetMacOSVersion: 13,
        userDefines: _userDefines({'macos_deployment_target': '26.0'}),
        check: (input, output) async {
          final library = output.assets.code.single.file!;
          final result = await Process.run('xcrun', [
            'vtool',
            '-show-build',
            library.toFilePath(),
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(result.stdout, contains(RegExp(r'\bminos\s+26[.]0\b')));
        },
      );
    });

    test('requires the quoted macOS deployment target user define', () {
      expect(
        testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: _userDefines({'require_ocaml_backend': true}),
          check: (_, _) {},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('macos_deployment_target'),
          ),
        ),
      );
    });

    test('rejects malformed deployment targets', () {
      for (final value in <Object>['26', 26]) {
        expect(
          testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.macOS,
            targetArchitecture: Architecture.arm64,
            userDefines: _userDefines({
              'macos_deployment_target': value,
              'require_ocaml_backend': true,
            }),
            check: (_, _) {},
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('macos_deployment_target'),
            ),
          ),
        );
      }
    });

    test('rejects x86_64 before artifact resolution', () {
      expect(
        testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.x64,
          userDefines: _userDefines({
            'macos_deployment_target': '26.0',
            'require_ocaml_backend': true,
          }),
          check: (_, _) {},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Unsupported macOS architecture x86_64; '
                'bonsai_flutter supports arm64 only.',
          ),
        ),
      );
    });
  });
}

PackageUserDefines _userDefines(Map<String, Object?> defines) =>
    PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: defines,
        basePath: Directory.current.uri,
      ),
    );
