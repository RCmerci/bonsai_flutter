import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  group('OCaml frame fixtures', () {
    test('decodes the empty incremental frame', () {
      final frame = decodeOcamlFixture('ocaml_empty_incremental.hex');

      expect(frame.runtimeEpoch, 7);
      expect(frame.baseRevision, 1);
      expect(frame.targetRevision, 2);
      expect(frame.kind, FrameKind.incremental);
      expect(frame.operations, isEmpty);
      expectFixtureMatchesDartEncoding(
        'ocaml_empty_incremental.hex',
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [],
        ),
      );
    });

    test('decodes the Counter full snapshot', () {
      final frame = decodeOcamlFixture('ocaml_counter_full.hex');

      expect(frame.runtimeEpoch, 7);
      expect(frame.baseRevision, 0);
      expect(frame.targetRevision, 1);
      expect(frame.kind, FrameKind.fullSnapshot);
      expect(frame.operations, hasLength(4));
      final column = frame.operations[0] as CreateNode;
      expect(column.nodeId, 1);
      expect(column.kind, NodeKind.column);
      expect(column.props, const LinearProps());
      final text = frame.operations[1] as CreateNode;
      expect(text.nodeId, 2);
      expect(text.kind, NodeKind.text);
      expect(text.props, const TextProps('Count: 0'));
      final children = frame.operations[2] as SetChildren;
      expect(children.nodeId, 1);
      expect(children.children, [2]);
      expect((frame.operations[3] as SetRoot).nodeId, 1);
      expectFixtureMatchesDartEncoding(
        'ocaml_counter_full.hex',
        counterSnapshot(text: 'Count: 0'),
      );
    });

    test('decodes a Unicode props update', () {
      final frame = decodeOcamlFixture('ocaml_unicode_update.hex');

      expect(frame.runtimeEpoch, 7);
      expect(frame.baseRevision, 1);
      expect(frame.targetRevision, 2);
      expect(frame.kind, FrameKind.incremental);
      expect(frame.operations, hasLength(1));
      final update = frame.operations.single as UpdateProps;
      expect(update.nodeId, 2);
      expect(update.props, const TextProps('计数: 😀'));
      expectFixtureMatchesDartEncoding(
        'ocaml_unicode_update.hex',
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 1,
          targetRevision: 2,
          kind: FrameKind.incremental,
          operations: [UpdateProps(nodeId: 2, props: TextProps('计数: 😀'))],
        ),
      );
    });

    test('decodes reordered children', () {
      final frame = decodeOcamlFixture('ocaml_reordered_children.hex');

      expect(frame.runtimeEpoch, 7);
      expect(frame.baseRevision, 2);
      expect(frame.targetRevision, 3);
      expect(frame.kind, FrameKind.incremental);
      final children = frame.operations.single as SetChildren;
      expect(children.nodeId, 1);
      expect(children.children, [3, 2]);
      expectFixtureMatchesDartEncoding(
        'ocaml_reordered_children.hex',
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 2,
          targetRevision: 3,
          kind: FrameKind.incremental,
          operations: [
            SetChildren(nodeId: 1, children: [3, 2]),
          ],
        ),
      );
    });

    test('decodes a typed host request', () {
      final frame = decodeOcamlFixture('ocaml_host_request.hex');

      expect(frame.runtimeEpoch, 31);
      expect(frame.baseRevision, 2);
      expect(frame.targetRevision, 3);
      final operation = frame.operations.single as HostRequestOperation;
      expect(operation.requestId, 41);
      expect((operation.request as ClipboardWriteRequest).text, '剪贴板😀');
      expectFixtureMatchesDartEncoding(
        'ocaml_host_request.hex',
        const Frame(
          runtimeEpoch: 31,
          baseRevision: 2,
          targetRevision: 3,
          kind: FrameKind.incremental,
          operations: [
            HostRequestOperation(
              requestId: 41,
              request: ClipboardWriteRequest('剪贴板😀'),
            ),
          ],
        ),
      );
    });

    test('decodes an opaque application request byte for byte', () {
      final frame = decodeOcamlFixture('ocaml_application_request.hex');

      expect(frame.runtimeEpoch, 41);
      expect(frame.baseRevision, 8);
      expect(frame.targetRevision, 9);
      final operation = frame.operations.single as ApplicationRequestOperation;
      expect(operation.requestId, 501);
      expect(operation.payload, [
        0,
        111,
        112,
        97,
        113,
        117,
        101,
        255,
        97,
        112,
        112,
        108,
        105,
        99,
        97,
        116,
        105,
        111,
        110,
        128,
      ]);
      expectFixtureMatchesDartEncoding(
        'ocaml_application_request.hex',
        Frame(
          runtimeEpoch: 41,
          baseRevision: 8,
          targetRevision: 9,
          kind: FrameKind.incremental,
          operations: [
            ApplicationRequestOperation(
              requestId: 501,
              payload: Uint8List.fromList([
                0,
                111,
                112,
                97,
                113,
                117,
                101,
                255,
                97,
                112,
                112,
                108,
                105,
                99,
                97,
                116,
                105,
                111,
                110,
                128,
              ]),
            ),
          ],
        ),
      );
    });

    test('decodes animated opacity introduced in protocol 1.12', () {
      final frame = decodeOcamlFixture('ocaml_animated_opacity.hex');

      expect(frame.runtimeEpoch, 7);
      expect(frame.baseRevision, 3);
      expect(frame.targetRevision, 4);
      final update = frame.operations.single as UpdateProps;
      expect(update.nodeId, 9);
      expect(
        update.props,
        const AnimatedOpacityProps(
          opacity: 0.25,
          animation: AnimationIntent(
            id: 7001,
            durationMilliseconds: 250,
            curve: AnimationCurveValue.easeInOut,
          ),
        ),
      );
      expectFixtureMatchesDartEncoding(
        'ocaml_animated_opacity.hex',
        const Frame(
          runtimeEpoch: 7,
          baseRevision: 3,
          targetRevision: 4,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: 9,
              props: AnimatedOpacityProps(
                opacity: 0.25,
                animation: AnimationIntent(
                  id: 7001,
                  durationMilliseconds: 250,
                  curve: AnimationCurveValue.easeInOut,
                ),
              ),
            ),
          ],
        ),
      );
    });

    test('decodes a bounded text input introduced in protocol 1.15', () {
      final frame = decodeOcamlFixture('ocaml_bounded_text_input.hex');
      final update = frame.operations.single as UpdateProps;
      final props = update.props as TextInputProps;

      expect(update.nodeId, 12);
      expect(props.maxUtf8Bytes, 64);
      expect(props.value.text, '拼😀音');
      expectFixtureMatchesDartEncoding(
        'ocaml_bounded_text_input.hex',
        const Frame(
          runtimeEpoch: 10,
          baseRevision: 4,
          targetRevision: 5,
          kind: FrameKind.incremental,
          operations: [
            UpdateProps(
              nodeId: 12,
              props: TextInputProps(
                sessionId: 7,
                documentRevision: 9,
                value: TextEditingStateValue(
                  text: '拼😀音',
                  selection: TextRangeValue(startUtf16: 4, endUtf16: 4),
                  composing: TextRangeValue(startUtf16: 0, endUtf16: 4),
                ),
                enabled: true,
                readOnly: false,
                obscureText: false,
                keyboardType: TextKeyboardType.text,
                inputAction: TextInputActionKind.done,
                acceptedLocalRevision: 11,
                updateMode: TextUpdateMode.correction,
                autofocus: true,
                maxUtf8Bytes: 64,
              ),
            ),
          ],
        ),
      );
    });

    test('shared incremental fixture enforces epoch and revision', () {
      final fixture = decodeOcamlFixture('ocaml_unicode_update.hex');
      final wrongEpochStore = NodeStore()
        ..apply(
          Frame(
            runtimeEpoch: 8,
            baseRevision: 0,
            targetRevision: 1,
            kind: FrameKind.fullSnapshot,
            operations: counterSnapshot(text: 'Count: 0').operations,
          ),
        );

      expect(
        () => wrongEpochStore.apply(fixture),
        throwsA(
          isA<FrameApplyException>().having(
            (error) => error.code,
            'code',
            FrameErrorCode.epochMismatch,
          ),
        ),
      );

      final wrongRevisionStore = NodeStore()
        ..apply(counterSnapshot(text: 'Count: 0'))
        ..apply(
          const Frame(
            runtimeEpoch: 7,
            baseRevision: 1,
            targetRevision: 2,
            kind: FrameKind.incremental,
            operations: [],
          ),
        );
      expect(
        () => wrongRevisionStore.apply(fixture),
        throwsA(
          isA<FrameApplyException>().having(
            (error) => error.code,
            'code',
            FrameErrorCode.revisionMismatch,
          ),
        ),
      );
    });

    test('decodes a bounded body with a sparse viewport and overlay', () {
      final frame = decodeOcamlFixture('ocaml_viewport_body.hex');
      final creates = frame.operations.whereType<CreateNode>().toList();

      final basePosition =
          creates.singleWhere((node) => node.nodeId == 3).parentData
              as StackPositionData;
      expect(basePosition.left, 0);
      expect(basePosition.top, 0);
      expect(basePosition.right, 0);
      expect(basePosition.bottom, 0);
      expect(
        creates.singleWhere((node) => node.nodeId == 4).parentData,
        const NoParentData(),
      );
      final viewportFlex =
          creates.singleWhere((node) => node.nodeId == 6).parentData
              as FlexParentData;
      expect(viewportFlex.flex, 1);
      expect(viewportFlex.fit, FlexParentFit.tight);
      final overlayPosition =
          creates.singleWhere((node) => node.nodeId == 7).parentData
              as StackPositionData;
      expect(overlayPosition.left, isNull);
      expect(overlayPosition.top, isNull);
      expect(overlayPosition.right, 16);
      expect(overlayPosition.bottom, 16);
      final sparse = creates.singleWhere((node) => node.nodeId == 6);
      expect(sparse.kind, NodeKind.nativeWidget);
      expect(
        (sparse.props as NativeWidgetProps).kindId,
        NativeWidgetKind.sparseExtentList,
      );
      expectFixtureMatchesDartEncoding('ocaml_viewport_body.hex', frame);
    });

    test('decodes an OCaml primary vertical scrollable byte-exactly', () {
      final frame = decodeOcamlFixture('ocaml_primary_scroll.hex');
      final update = frame.operations.single as UpdateProps;

      expect(update.nodeId, 71);
      expect(
        update.props,
        const ListViewProps(
          axis: ScrollAxis.vertical,
          reverse: false,
          primary: true,
        ),
      );
      expectFixtureMatchesDartEncoding('ocaml_primary_scroll.hex', frame);
    });
  });
}

Frame decodeOcamlFixture(String name) {
  final file = hexFixtureFile(name);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing OCaml-generated cross-language fixture: $name',
  );
  return FrameCodec.decode(readHexFixture(name));
}

void expectFixtureMatchesDartEncoding(String name, Frame frame) {
  expect(
    FrameCodec.encode(frame),
    orderedEquals(readHexFixture(name)),
    reason: 'Dart and OCaml encoded different bytes for $name',
  );
}
