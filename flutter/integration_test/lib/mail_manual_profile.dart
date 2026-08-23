import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(BonsaiFlutterRoot(config: Uint8List.fromList(utf8.encode('mail'))));
}
