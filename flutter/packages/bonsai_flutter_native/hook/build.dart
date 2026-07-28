import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

import 'ocaml_artifact.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final packageName = input.packageName;
    final requireOcamlBackend = _requireOcamlBackend(input);
    final target = _ocamlTarget(input);
    File? ocamlObject;
    if (target == null) {
      if (requireOcamlBackend) {
        throw StateError(
          'require_ocaml_backend is enabled, but '
          '${input.config.code.targetOS} is not an Apple target.',
        );
      }
    } else {
      ocamlObject = await OcamlArtifactResolver().resolve(
        nativeArtifactRoot: input.userDefines.path('native_artifact_root'),
        requireOcamlBackend: requireOcamlBackend,
        target: target,
      );
    }
    final embedOcaml = ocamlObject != null;
    final exportList = input.packageRoot.resolve(
      'src/bonsai_flutter_exports.txt',
    );
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: [
        if (!embedOcaml) 'src/$packageName.c',
        if (ocamlObject != null) ocamlObject.path,
        if (input.config.code.targetOS == OS.iOS)
          'src/bonsai_flutter_ios_process_stubs.c',
      ],
      includes: ['src'],
      flags: [
        if (input.config.code.targetOS == OS.macOS ||
            input.config.code.targetOS == OS.iOS) ...[
          '-Wl,-dead_strip',
          '-Wl,-exported_symbols_list,${exportList.toFilePath()}',
        ],
      ],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => stderr.writeln(record.message)),
    );
    output.dependencies.add(exportList);
  });
}

bool _requireOcamlBackend(BuildInput input) {
  final value = input.userDefines['require_ocaml_backend'];
  return switch (value) {
    null => false,
    true || 'true' => true,
    false || 'false' => false,
    _ => throw FormatException(
      'require_ocaml_backend must be true or false, found $value.',
    ),
  };
}

OcamlArtifactTarget? _ocamlTarget(BuildInput input) {
  final config = input.config.code;
  final architecture = switch (config.targetArchitecture) {
    Architecture.arm64 => OcamlTargetArchitecture.arm64,
    Architecture.x64 => OcamlTargetArchitecture.x86_64,
    _ => null,
  };
  if (architecture == null) {
    return null;
  }

  if (config.targetOS == OS.macOS) {
    return OcamlArtifactTarget(
      operatingSystem: OcamlTargetOperatingSystem.macOS,
      architecture: architecture,
      appleSdk: OcamlAppleSdk.macOS,
      // The existing OCaml dependency closure is measured on macOS 26.
      // Do not relabel it with Flutter's lower native-assets link target.
      minimumVersion: '26.0',
    );
  }
  if (config.targetOS == OS.iOS) {
    final sdk = switch (config.iOS.targetSdk) {
      IOSSdk.iPhoneOS => OcamlAppleSdk.iPhoneOS,
      IOSSdk.iPhoneSimulator => throw StateError(
        'iOS Simulator is unsupported; use a physical iPhone.',
      ),
      _ => throw StateError('Unsupported iOS SDK ${config.iOS.targetSdk}.'),
    };
    return OcamlArtifactTarget(
      operatingSystem: OcamlTargetOperatingSystem.iOS,
      architecture: architecture,
      appleSdk: sdk,
      minimumVersion: '${config.iOS.targetVersion}.0',
    );
  }
  return null;
}
