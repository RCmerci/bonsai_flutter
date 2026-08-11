import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/widgets.dart';

BonsaiFlutterHostAdapter createBonsaiFlutterHostAdapter() =>
    const ApplicationHostAdapter();

final class ApplicationHostAdapter implements BonsaiFlutterHostAdapter {
  const ApplicationHostAdapter();

  @override
  Future<Uint8List> createApplicationPayload() async => Uint8List(0);

  @override
  BonsaiFlutterApplicationPlatform? createApplicationPlatform() => null;

  @override
  Widget buildHost({required BuildContext context, required Widget child}) =>
      child;
}
