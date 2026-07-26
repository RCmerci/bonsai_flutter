import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CounterHost());
}

final class CounterHost extends StatelessWidget {
  const CounterHost({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'bonsai_flutter Counter',
    home: BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('counter'))),
  );
}
