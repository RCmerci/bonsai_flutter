import 'dart:convert';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'mail_runtime_trace.dart';

void main() {
  runApp(const MailExampleApp());
}

void _writeRuntimeTrace(String message) {
  if (kDebugMode) debugPrint(message);
}

final class MailExampleApp extends StatelessWidget {
  const MailExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bonsai Mail',
    debugShowCheckedModeBanner: false,
    home: BonsaiFlutterRoot(
      config: Uint8List.fromList(
        utf8.encode(kDebugMode ? 'mail-debug' : 'mail'),
      ),
      runtimeStarter: (config) =>
          startTracedMailRuntime(config, trace: _writeRuntimeTrace),
    ),
  );
}
