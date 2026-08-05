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

Uint8List _encodeApplicationPayload({
  required String databasePath,
  required String applicationSupportDirectory,
}) {
  final database = utf8.encode(databasePath);
  final directory = utf8.encode(applicationSupportDirectory);
  final payload = Uint8List(12 + database.length + directory.length);
  payload.setRange(0, 4, ascii.encode('SWC1'));
  final data = ByteData.sublistView(payload);
  data.setUint32(4, database.length, Endian.little);
  data.setUint32(8, directory.length, Endian.little);
  final databaseStart = 12;
  final directoryStart = databaseStart + database.length;
  payload.setRange(databaseStart, directoryStart, database);
  payload.setRange(directoryStart, payload.length, directory);
  return payload;
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
    applicationPayload: _encodeApplicationPayload(
      databasePath: databasePath,
      applicationSupportDirectory: storageDirectory.path,
    ),
  ).encode();
  return SqliteWorkerBootstrap(
    databasePath: databasePath,
    applicationSupportDirectory: storageDirectory.path,
    runtimeConfig: runtimeConfig,
  );
}

Future<void> _createDirectory(Directory directory) =>
    directory.create(recursive: true);
