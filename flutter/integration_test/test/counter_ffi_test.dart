// This probe intentionally imports the staged transitive native package.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/runtime_harness.dart';

const _operationTimeout = Duration(seconds: 10);

Future<T> _bounded<T>(Future<T> future, String operation) => future.timeout(
  _operationTimeout,
  onTimeout: () => throw TimeoutException('$operation timed out'),
);

void main() {
  testWidgets(
    'Flutter button press crosses FFI and applies one OCaml text patch',
    (tester) async {
      expect(nativeProtocolVersion, const NativeProtocolVersion(1, 14));

      final client = await tester.runAsync(
        () => _bounded(
          RuntimeClient.start(
            config: Uint8List.fromList(utf8.encode('counter')),
          ),
          'RuntimeClient.start',
        ),
      );
      expect(client, isNotNull);
      final harness = RuntimeHarness(client!);
      addTearDown(() => _bounded(harness.dispose(), 'RuntimeHarness.dispose'));

      final initialCycle = await tester.runAsync(
        () => _bounded(harness.grant(), 'initial frame grant'),
      );
      expect(initialCycle, isNotNull);
      final initialFrame = FrameCodec.decode(initialCycle!.bytes);
      expect(initialFrame.kind, FrameKind.fullSnapshot);
      expect(initialFrame.targetRevision, 1);
      expect(initialCycle.revision, 1);

      final store = NodeStore()..apply(initialFrame);
      final queue = EventBatchQueue(
        runtimeEpoch: initialFrame.runtimeEpoch,
        displayedRevision: () => store.revision,
      );
      var rendererEventSeen = false;
      await tester.pumpWidget(
        MaterialApp(
          home: BonsaiFlutterView(
            store: store,
            onEvent: (event) {
              rendererEventSeen = true;
              queue.enqueue(event);
            },
          ),
        ),
      );
      expect(find.text('Count: 0'), findsOneWidget);
      expect(find.text('Increment'), findsOneWidget);
      final rootBefore = tester.element(
        find.byKey(ValueKey<int>(store.rootId!)),
      );
      final buttonNode = store.nodes.values.singleWhere(
        (node) => node.kind == NodeKind.materialElevatedButton,
      );
      final buttonBefore = tester.element(
        find.byKey(ValueKey<int>(buttonNode.id)),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(rendererEventSeen, isTrue);
      final batch = queue.takeBatch();
      expect(batch, isNotNull);
      final response = await tester.runAsync(
        () => _bounded(
          harness.advance(events: EventBatchCodec.encode(batch!)),
          'button event pump',
        ),
      );
      expect(response, isNotNull);
      final incrementalFrame = FrameCodec.decode(response!.bytes);
      expect(incrementalFrame.kind, FrameKind.incremental);
      expect(incrementalFrame.baseRevision, 1);
      expect(incrementalFrame.targetRevision, 2);
      expect(response.revision, 2);
      final uiOperations = incrementalFrame.operations
          .where((operation) => operation is! RuntimeStatsOperation)
          .toList(growable: false);
      expect(uiOperations, hasLength(1));
      expect(
        uiOperations.single,
        isA<UpdateProps>().having(
          (operation) => operation.props,
          'props',
          isA<TextProps>().having((props) => props.value, 'value', 'Count: 1'),
        ),
      );

      final applied = store.apply(incrementalFrame);
      expect(applied.dirtyNodeIds, hasLength(1));
      await tester.pump();
      expect(find.text('Count: 0'), findsNothing);
      expect(find.text('Count: 1'), findsOneWidget);
      expect(
        identical(
          tester.element(find.byKey(ValueKey<int>(store.rootId!))),
          rootBefore,
        ),
        isTrue,
      );
      expect(
        identical(
          tester.element(find.byKey(ValueKey<int>(buttonNode.id))),
          buttonBefore,
        ),
        isTrue,
      );

      harness.acknowledge();
    },
  );
}
