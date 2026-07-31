import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ClockHost());
}

final class ClockHost extends StatelessWidget {
  const ClockHost({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'bonsai_flutter Clock',
    home: BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('clock'))),
  );
}
