import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      home: BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('mail'))),
    ),
  );
}
