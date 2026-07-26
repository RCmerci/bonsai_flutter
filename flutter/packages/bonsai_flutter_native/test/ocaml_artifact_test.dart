import 'dart:io';

import 'package:test/test.dart';

import '../hook/ocaml_artifact.dart';

const _macOSTarget = OcamlArtifactTarget(
  operatingSystem: OcamlTargetOperatingSystem.macOS,
  architecture: OcamlTargetArchitecture.arm64,
  appleSdk: OcamlAppleSdk.macOS,
  minimumVersion: '26.0',
);

const _iPhoneOSTarget = OcamlArtifactTarget(
  operatingSystem: OcamlTargetOperatingSystem.iOS,
  architecture: OcamlTargetArchitecture.arm64,
  appleSdk: OcamlAppleSdk.iPhoneOS,
  minimumVersion: '13.0',
);

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'bonsai_flutter_ocaml_artifact_test.',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('target-specific selection', () {
    test('selects the macOS arm64 object', () async {
      final object = _createObject(
        temporaryDirectory,
        'macos/arm64/native_embed.exe.o',
      );

      final selected =
          await _resolverFor(
            const OcamlArtifactMetadata(
              platform: OcamlMachOPlatform.macOS,
              architecture: OcamlTargetArchitecture.arm64,
              appleSdk: OcamlAppleSdk.macOS,
              minimumVersion: '26.0',
            ),
          ).resolve(
            nativeArtifactRoot: temporaryDirectory.uri,
            requireOcamlBackend: true,
            target: _macOSTarget,
          );

      expect(selected?.path, object.path);
    });

    test('selects the iPhoneOS arm64 object', () async {
      final object = _createObject(
        temporaryDirectory,
        'ios/iphoneos/arm64/native_embed.exe.o',
      );

      final selected =
          await _resolverFor(
            const OcamlArtifactMetadata(
              platform: OcamlMachOPlatform.iOS,
              architecture: OcamlTargetArchitecture.arm64,
              appleSdk: OcamlAppleSdk.iPhoneOS,
              minimumVersion: '13.0',
            ),
          ).resolve(
            nativeArtifactRoot: temporaryDirectory.uri,
            requireOcamlBackend: true,
            target: _iPhoneOSTarget,
          );

      expect(selected?.path, object.path);
    });
  });

  group('strict validation', () {
    test('rejects a missing target object before linking', () async {
      await expectLater(
        _resolverFor(_deviceMetadata).resolve(
          nativeArtifactRoot: temporaryDirectory.uri,
          requireOcamlBackend: true,
          target: _iPhoneOSTarget,
        ),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('ios/iphoneos/arm64/native_embed.exe.o'),
              )
              .having(
                (error) => error.message,
                'message',
                allOf(contains('iOS'), contains('arm64'), contains('13.0')),
              ),
        ),
      );
    });

    test('rejects a macOS object for iPhoneOS', () async {
      await _expectMetadataFailure(
        temporaryDirectory,
        const OcamlArtifactMetadata(
          platform: OcamlMachOPlatform.macOS,
          architecture: OcamlTargetArchitecture.arm64,
          appleSdk: OcamlAppleSdk.macOS,
          minimumVersion: '26.0',
        ),
        contains('platform'),
      );
    });

    test('rejects the wrong architecture', () async {
      await _expectMetadataFailure(
        temporaryDirectory,
        const OcamlArtifactMetadata(
          platform: OcamlMachOPlatform.iOS,
          architecture: OcamlTargetArchitecture.x86_64,
          appleSdk: OcamlAppleSdk.iPhoneOS,
          minimumVersion: '13.0',
        ),
        contains('architecture'),
      );
    });

    test('rejects an inconsistent deployment target', () async {
      await _expectMetadataFailure(
        temporaryDirectory,
        const OcamlArtifactMetadata(
          platform: OcamlMachOPlatform.iOS,
          architecture: OcamlTargetArchitecture.arm64,
          appleSdk: OcamlAppleSdk.iPhoneOS,
          minimumVersion: '14.0',
        ),
        contains('minimum version'),
      );
    });
  });

  group('required backend', () {
    test(
      'allows the truthful C-only fallback only when explicitly optional',
      () {
        expect(
          _resolverFor(_deviceMetadata).resolve(
            nativeArtifactRoot: null,
            requireOcamlBackend: false,
            target: _iPhoneOSTarget,
          ),
          completion(isNull),
        );
      },
    );

    test('require_ocaml_backend prevents the C-only fallback', () {
      expect(
        _resolverFor(_deviceMetadata).resolve(
          nativeArtifactRoot: null,
          requireOcamlBackend: true,
          target: _iPhoneOSTarget,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('require_ocaml_backend'), contains('iPhoneOS')),
          ),
        ),
      );
    });
  });
}

const _deviceMetadata = OcamlArtifactMetadata(
  platform: OcamlMachOPlatform.iOS,
  architecture: OcamlTargetArchitecture.arm64,
  appleSdk: OcamlAppleSdk.iPhoneOS,
  minimumVersion: '13.0',
);

OcamlArtifactResolver _resolverFor(OcamlArtifactMetadata metadata) =>
    OcamlArtifactResolver(inspect: (_) async => metadata);

File _createObject(Directory root, String relativePath) {
  final file = File.fromUri(root.uri.resolve(relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(const [0xCF, 0xFA, 0xED, 0xFE]);
  return file;
}

Future<void> _expectMetadataFailure(
  Directory root,
  OcamlArtifactMetadata metadata,
  Matcher messageMatcher,
) async {
  _createObject(root, 'ios/iphoneos/arm64/native_embed.exe.o');

  await expectLater(
    _resolverFor(metadata).resolve(
      nativeArtifactRoot: root.uri,
      requireOcamlBackend: true,
      target: _iPhoneOSTarget,
    ),
    throwsA(
      isA<StateError>()
          .having((error) => error.message, 'message', messageMatcher)
          .having(
            (error) => error.message,
            'message',
            allOf(contains('iPhoneOS'), contains('arm64'), contains('13.0')),
          ),
    ),
  );
}
