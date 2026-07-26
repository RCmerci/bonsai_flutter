import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const HostEffectsExampleApp());
}

final class HostEffectsExampleApp extends StatelessWidget {
  const HostEffectsExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bonsai Flutter Host Effects',
    home: BonsaiFlutterRoot(
      config: Uint8List.fromList(utf8.encode('host_effects')),
    ),
  );
}
