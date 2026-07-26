import 'dart:io';

import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final ocamlObject = input.userDefines
        .path('ocaml_complete_object')
        ?.toFilePath();
    final embedOcaml = ocamlObject != null;
    if (ocamlObject != null && !File(ocamlObject).existsSync()) {
      throw StateError('OCaml complete object does not exist: $ocamlObject');
    }
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: [if (!embedOcaml) 'src/$packageName.c', ?ocamlObject],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => stderr.writeln(record.message)),
    );
  });
}
