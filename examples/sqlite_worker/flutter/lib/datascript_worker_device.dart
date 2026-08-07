import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

import 'application_support_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DataScriptWorkerDeviceProbe());
}

final class DataScriptWorkerDeviceProbe extends StatefulWidget {
  const DataScriptWorkerDeviceProbe({super.key});

  @override
  State<DataScriptWorkerDeviceProbe> createState() =>
      _DataScriptWorkerDeviceProbeState();
}

final class _DataScriptWorkerDeviceProbeState
    extends State<DataScriptWorkerDeviceProbe> {
  String _status = 'Starting OCaml Worker…';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final bootstrap = await resolveSqliteWorkerBootstrap();
      final runtime = await RuntimeClient.start(
        config: Uint8List.fromList(bootstrap.runtimeConfig),
      );
      stderr.writeln('BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED');
      await Future<void>.delayed(const Duration(seconds: 1));
      await runtime.dispose();
      stderr.writeln('BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED');
      if (mounted) setState(() => _status = 'Worker persistence probe passed');
    } catch (error, stackTrace) {
      debugPrint('BONSAI_DATASCRIPT_HOST_FAILURE $error\n$stackTrace');
      if (mounted) setState(() => _status = 'Probe failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(_status))),
  );
}
