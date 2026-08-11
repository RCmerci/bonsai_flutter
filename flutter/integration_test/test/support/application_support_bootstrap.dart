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
    required this.applicationSupportDirectory,
    required this.runtimeConfig,
  });

  final String databasePath;
  final String applicationSupportDirectory;
  final Uint8List runtimeConfig;
}

Future<SqliteWorkerBootstrap> resolveSqliteWorkerBootstrap({
  ApplicationSupportResolver resolveApplicationSupport = getApplicationSupportDirectory,
  DirectoryCreator? createDirectory,
}) async {
  final support = await resolveApplicationSupport();
  if (!path.isAbsolute(support.path)) {
    throw ArgumentError.value(support.path, 'applicationSupportPath', 'must be absolute');
  }
  final storageDirectory = Directory(path.normalize(path.join(support.path, 'sqlite_worker')));
  await (createDirectory ?? (directory) => directory.create(recursive: true))(storageDirectory);
  final databasePath = path.join(storageDirectory.path, 'todos.sqlite3');
  final database = utf8.encode(databasePath);
  final directory = utf8.encode(storageDirectory.path);
  final payload = Uint8List(12 + database.length + directory.length);
  payload.setRange(0, 4, ascii.encode('SWC1'));
  final data = ByteData.sublistView(payload);
  data.setUint32(4, database.length, Endian.little);
  data.setUint32(8, directory.length, Endian.little);
  payload.setRange(12, 12 + database.length, database);
  payload.setRange(12 + database.length, payload.length, directory);
  return SqliteWorkerBootstrap(
    databasePath: databasePath,
    applicationSupportDirectory: storageDirectory.path,
    runtimeConfig: RuntimeBootstrapConfig(
      entrypoint: 'sqlite_worker',
      launchPolicy: RuntimeLaunchPolicy.replaceExisting,
      applicationPayload: payload,
    ).encode(),
  );
}
