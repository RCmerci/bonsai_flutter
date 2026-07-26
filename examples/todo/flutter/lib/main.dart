import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const TodoHost());
}

final class TodoHost extends StatelessWidget {
  const TodoHost({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'bonsai_flutter Todo',
    home: BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('todo'))),
  );
}
