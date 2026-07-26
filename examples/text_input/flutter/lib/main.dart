import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const TextInputExampleApp());
}

final class TextInputExampleApp extends StatelessWidget {
  const TextInputExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bonsai Flutter Text Input',
    home: Scaffold(
      body: BonsaiFlutterRoot(
        config: Uint8List.fromList(utf8.encode('text_input')),
      ),
    ),
  );
}
