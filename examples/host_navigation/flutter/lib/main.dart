import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const HostNavigationExampleApp());
}

final class HostNavigationExampleApp extends StatelessWidget {
  const HostNavigationExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bonsai Flutter Host and Navigation',
    home: Scaffold(
      body: BonsaiFlutterRoot(
        config: Uint8List.fromList(utf8.encode('host_navigation')),
      ),
    ),
  );
}
