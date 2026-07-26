import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const NavigationExampleApp());
}

final class NavigationExampleApp extends StatelessWidget {
  const NavigationExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bonsai Flutter Navigation',
    home: BonsaiFlutterRoot(
      config: Uint8List.fromList(utf8.encode('navigation')),
    ),
  );
}
