import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const GalleryApp());
}

final class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final nativeWidgets =
        NativeWidgetRegistry(
          capabilityBits:
              NativeCapability.stateful |
              NativeCapability.resource |
              NativeCapability.semantics,
        )..register<String>(
          NativeWidgetRegistration(
            kindId: 1001,
            minVersion: 1,
            maxVersion: 1,
            capabilityBits:
                NativeCapability.stateful |
                NativeCapability.resource |
                NativeCapability.semantics,
            decodeProps: (payload) => utf8.decode(payload),
            factory: (context) {
              final focusNode = context.resource<FocusNode>(
                create: FocusNode.new,
                dispose: (focusNode) => focusNode.dispose(),
              );
              return ElevatedButton(
                focusNode: focusNode,
                onPressed: () => context.emit?.call(1, Uint8List(0)),
                child: Text(context.props),
              );
            },
          ),
        );
    return MaterialApp(
      title: 'Bonsai Flutter Gallery',
      home: BonsaiFlutterRoot(
        config: Uint8List.fromList(utf8.encode('gallery')),
        registry: WidgetRegistry.standard(nativeWidgets: nativeWidgets),
      ),
    );
  }
}
