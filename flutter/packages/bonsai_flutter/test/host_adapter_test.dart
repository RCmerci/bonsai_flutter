import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ApplicationAdapter implements BonsaiFlutterHostAdapter {
  _ApplicationAdapter(this.payload);

  final Uint8List payload;
  var payloadRequests = 0;

  @override
  Future<Uint8List> createApplicationPayload() async {
    payloadRequests += 1;
    return Uint8List.fromList(payload);
  }

  @override
  BonsaiFlutterApplicationPlatform? createApplicationPlatform() => null;

  @override
  Widget buildHost({required BuildContext context, required Widget child}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: KeyedSubtree(
          key: const Key('application-services'),
          child: child,
        ),
      );
}

void main() {
  testWidgets('adapter provides async payload and application-owned services', (
    tester,
  ) async {
    final BonsaiFlutterHostAdapter adapter = _ApplicationAdapter(
      Uint8List.fromList([0, 1, 255]),
    );

    expect(await adapter.createApplicationPayload(), [0, 1, 255]);
    await tester.pumpWidget(
      Builder(
        builder: (context) => adapter.buildHost(
          context: context,
          child: const SizedBox(key: Key('generated-host')),
        ),
      ),
    );

    expect((adapter as _ApplicationAdapter).payloadRequests, 1);
    expect(adapter.createApplicationPlatform(), isNull);
    expect(find.byKey(const Key('application-services')), findsOneWidget);
    expect(find.byKey(const Key('generated-host')), findsOneWidget);
  });
}
