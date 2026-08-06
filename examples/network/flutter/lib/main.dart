import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const NetworkApplication());
}

final class NetworkApplication extends StatelessWidget {
  const NetworkApplication({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'bonsai_flutter Secure Network Lab',
    debugShowCheckedModeBanner: false,
    home: NetworkHost(),
  );
}

final class NetworkHost extends StatelessWidget {
  const NetworkHost({this.runtimeStarter, super.key});

  final RuntimeStarter? runtimeStarter;

  @override
  Widget build(BuildContext context) => Material(
    child: BonsaiFlutterRoot(
      config: Uint8List.fromList(utf8.encode('network')),
      runtimeStarter: runtimeStarter,
      loading: const _MessageScreen(title: 'Starting Secure Network Lab…'),
      errorBuilder: (context, error) => _MessageScreen(
        title: 'Unable to start Secure Network Lab',
        detail: error.toString(),
      ),
    ),
  );
}

final class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center),
            if (detail case final detail?) ...[
              const SizedBox(height: 12),
              Text(detail, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    ),
  );
}
