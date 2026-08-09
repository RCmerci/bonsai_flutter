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
  minimumVersion: '15.0',
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

  test('selects the explicit CLI profile', () {
    expect(
      OcamlArtifactVariant.fromProfileName('debug'),
      OcamlArtifactVariant.debug,
    );
    expect(
      OcamlArtifactVariant.fromProfileName('profile'),
      OcamlArtifactVariant.profile,
    );
    expect(
      OcamlArtifactVariant.fromProfileName('release'),
      OcamlArtifactVariant.release,
    );
  });

  test('requires a supported explicit CLI profile', () {
    expect(
      () => OcamlArtifactVariant.fromProfileName(null),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => OcamlArtifactVariant.fromProfileName('benchmark'),
      throwsA(isA<FormatException>()),
    );
  });

  test('selects the profile-specific artifact path', () {
    expect(
      _macOSTarget.artifactPathFor(variant: OcamlArtifactVariant.profile),
      'macos/arm64/profile/native_embed.exe.o',
    );
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
              minimumVersion: '15.0',
            ),
          ).resolve(
            nativeArtifactRoot: temporaryDirectory.uri,
            requireOcamlBackend: true,
            target: _iPhoneOSTarget,
          );

      expect(selected?.path, object.path);
    });

    test('selects the debug artifact variant', () async {
      final object = _createObject(
        temporaryDirectory,
        'macos/arm64/debug/native_embed.exe.o',
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
            variant: OcamlArtifactVariant.debug,
          );

      expect(selected?.path, object.path);
    });

    test('selects the release artifact variant', () async {
      final object = _createObject(
        temporaryDirectory,
        'ios/iphoneos/arm64/release/native_embed.exe.o',
      );

      final selected = await _resolverFor(_deviceMetadata).resolve(
        nativeArtifactRoot: temporaryDirectory.uri,
        requireOcamlBackend: true,
        target: _iPhoneOSTarget,
        variant: OcamlArtifactVariant.release,
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
                allOf(contains('iOS'), contains('arm64'), contains('15.0')),
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
  minimumVersion: '15.0',
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
            allOf(contains('iPhoneOS'), contains('arm64'), contains('15.0')),
          ),
    ),
  );
}
