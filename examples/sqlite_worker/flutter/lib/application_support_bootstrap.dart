import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef ApplicationSupportResolver = Future<Directory> Function();
typedef DirectoryCreator = Future<void> Function(Directory directory);

final class SqliteWorkerBootstrap {
  const SqliteWorkerBootstrap({
    required this.databasePath,
    required this.runtimeConfig,
  });

  final String databasePath;
  final Uint8List runtimeConfig;
}

Future<SqliteWorkerBootstrap> resolveSqliteWorkerBootstrap({
  ApplicationSupportResolver resolveApplicationSupport =
      getApplicationSupportDirectory,
  DirectoryCreator? createDirectory,
}) async {
  final support = await resolveApplicationSupport();
  if (!path.isAbsolute(support.path)) {
    throw ArgumentError.value(
      support.path,
      'applicationSupportPath',
      'must be absolute',
    );
  }
  final storageDirectory = Directory(
    path.normalize(path.join(support.path, 'sqlite_worker')),
  );
  await (createDirectory ?? _createDirectory)(storageDirectory);
  final databasePath = path.join(storageDirectory.path, 'todos.sqlite3');
  final runtimeConfig = RuntimeBootstrapConfig(
    entrypoint: 'sqlite_worker',
    launchPolicy: RuntimeLaunchPolicy.replaceExisting,
    applicationPayload: Uint8List.fromList(utf8.encode(databasePath)),
  ).encode();
  return SqliteWorkerBootstrap(
    databasePath: databasePath,
    runtimeConfig: runtimeConfig,
  );
}

Future<void> _createDirectory(Directory directory) =>
    directory.create(recursive: true);
