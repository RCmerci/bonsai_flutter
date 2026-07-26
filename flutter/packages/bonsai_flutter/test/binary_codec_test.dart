import 'dart:typed_data';

import 'package:bonsai_flutter/src/protocol/binary_codec.dart';
import 'package:bonsai_flutter/src/protocol/frame.dart';
import 'package:bonsai_flutter/src/protocol/generated_protocol.dart';
import 'package:bonsai_flutter/src/store/node_store.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  group('binary frame codec', () {
    test('matches the shared counter full-snapshot fixture byte for byte', () {
      final encoded = FrameCodec.encode(counterSnapshot(text: 'Count: 0'));
      final expected = readHexFixture('counter_full.hex');

      expect(encoded, orderedEquals(expected));
      expect(encoded.length, 144);
      expect(encoded.sublist(0, 4), [0x42, 0x46, 0x46, 0x52]);
      expect(readUint16(encoded, 4), 1);
      expect(readUint16(encoded, 6), 12);
      expect(readUint16(encoded, 8), 48);
      expect(encoded[10], 2);
      expect(readUint64(encoded, 12), 7);
      expect(readUint64(encoded, 20), 0);
      expect(readUint64(encoded, 28), 1);
      expect(readUint32(encoded, 36), 96);
    });

    test('round trips an incremental Unicode property update', () {
      const frame = Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 2, props: TextProps('计数: 1'))],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect(decoded.runtimeEpoch, 7);
      expect(decoded.baseRevision, 1);
      expect(decoded.targetRevision, 2);
      expect(decoded.kind, FrameKind.incremental);
      expect(decoded.operations, hasLength(1));
      final update = decoded.operations.single as UpdateProps;
      expect(update.nodeId, 2);
      expect(update.props, const TextProps('计数: 1'));
    });

    test('round trips host requests and declarative navigation props', () {
      const frame = Frame(
        runtimeEpoch: 7,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          HostRequestOperation(
            requestId: 20,
            request: ClipboardWriteRequest('剪贴板😀'),
          ),
          HostRequestOperation(
            requestId: 21,
            request: PickFileRequest(
              allowedExtensions: ['txt', 'md'],
              allowMultiple: true,
            ),
          ),
          CancelHostRequestOperation(requestId: 21),
          UpdateProps(
            nodeId: 30,
            props: PageProps(
              pageKey: 'settings',
              transition: PageTransition.fade,
              canPop: true,
              restorationId: 'settings-page',
            ),
          ),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect(decoded.operations, hasLength(4));
      final clipboard = decoded.operations[0] as HostRequestOperation;
      expect(clipboard.requestId, 20);
      expect((clipboard.request as ClipboardWriteRequest).text, '剪贴板😀');
      final picker =
          (decoded.operations[1] as HostRequestOperation).request
              as PickFileRequest;
      expect(picker.allowedExtensions, ['txt', 'md']);
      expect(picker.allowMultiple, isTrue);
      expect(
        (decoded.operations[2] as CancelHostRequestOperation).requestId,
        21,
      );
      expect(
        (decoded.operations[3] as UpdateProps).props,
        const PageProps(
          pageKey: 'settings',
          transition: PageTransition.fade,
          canPop: true,
          restorationId: 'settings-page',
        ),
      );
    });

    test('round trips layout, semantics, theme, and checkbox properties', () {
      const frame = Frame(
        runtimeEpoch: 9,
        baseRevision: 0,
        targetRevision: 1,
        kind: FrameKind.fullSnapshot,
        operations: [
          CreateNode(
            nodeId: 1,
            kind: NodeKind.padding,
            props: PaddingProps(
              EdgeInsetsValue(left: 12, top: 8, right: 12, bottom: 8),
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 2,
            kind: NodeKind.center,
            props: CenterProps(widthFactor: null, heightFactor: 1.5),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 3,
            kind: NodeKind.scrollView,
            props: ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
            eventBindings: [
              EventBinding(
                eventTag: EventTagId.scrollNotification,
                handlerId: 80,
              ),
            ],
          ),
          CreateNode(
            nodeId: 4,
            kind: NodeKind.semantics,
            props: SemanticsProps(
              label: 'Accept terms',
              role: SemanticsRoleValue.checkbox,
              enabled: true,
              checked: false,
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 5,
            kind: NodeKind.theme,
            props: ThemeProps(
              brightness: ThemeBrightness.dark,
              colorSeedArgb: 0xff2060a0,
            ),
            eventBindings: [],
          ),
          CreateNode(
            nodeId: 6,
            kind: NodeKind.materialCheckbox,
            props: MaterialCheckboxProps(value: false, enabled: true),
            eventBindings: [
              EventBinding(eventTag: EventTagId.valueChanged, handlerId: 81),
            ],
          ),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      final nodes = decoded.operations.whereType<CreateNode>().toList();
      expect(
        nodes.map((node) => node.kind),
        orderedEquals([
          NodeKind.padding,
          NodeKind.center,
          NodeKind.scrollView,
          NodeKind.semantics,
          NodeKind.theme,
          NodeKind.materialCheckbox,
        ]),
      );
      expect(
        nodes.map((node) => node.props),
        orderedEquals([
          const PaddingProps(
            EdgeInsetsValue(left: 12, top: 8, right: 12, bottom: 8),
          ),
          const CenterProps(widthFactor: null, heightFactor: 1.5),
          const ScrollViewProps(axis: ScrollAxis.vertical, reverse: false),
          const SemanticsProps(
            label: 'Accept terms',
            role: SemanticsRoleValue.checkbox,
            enabled: true,
            checked: false,
          ),
          const ThemeProps(
            brightness: ThemeBrightness.dark,
            colorSeedArgb: 0xff2060a0,
          ),
          const MaterialCheckboxProps(value: false, enabled: true),
        ]),
      );
    });

    test('round trips revisioned UTF-16 text input properties', () {
      const props = TextInputProps(
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
      );
      const frame = Frame(
        runtimeEpoch: 10,
        baseRevision: 4,
        targetRevision: 5,
        kind: FrameKind.incremental,
        operations: [UpdateProps(nodeId: 12, props: props)],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));

      expect((decoded.operations.single as UpdateProps).props, props);
    });

    test('decoded full snapshot can be applied atomically', () {
      final decoded = FrameCodec.decode(readHexFixture('counter_full.hex'));
      final store = NodeStore()..apply(decoded);

      expect(store.runtimeEpoch, 7);
      expect(store.revision, 1);
      expect(store.rootId, 1);
      expect(store.node(2).props, const TextProps('Count: 0'));
    });

    test('round trips the typed core visual and layout surface', () {
      const frame = Frame(
        runtimeEpoch: 9,
        baseRevision: 1,
        targetRevision: 2,
        kind: FrameKind.incremental,
        operations: [
          UpdateProps(nodeId: 1, props: RichTextProps(['Hello', ' world'])),
          UpdateProps(
            nodeId: 2,
            props: IconProps(
              codePoint: 0xe145,
              fontFamily: 'MaterialIcons',
              size: 20,
              colorArgb: 0xff102030,
            ),
          ),
          UpdateProps(
            nodeId: 3,
            props: ImageProps(
              uri: 'https://example.invalid/image.png',
              fit: ImageFitValue.contain,
              width: 120,
              height: 80,
            ),
          ),
          UpdateProps(nodeId: 4, props: AlignProps(AlignmentValue.bottomEnd)),
          UpdateProps(nodeId: 5, props: SizedBoxProps(width: 100, height: 40)),
          UpdateProps(
            nodeId: 6,
            props: ConstrainedBoxProps(
              minWidth: 10,
              maxWidth: 100,
              minHeight: 20,
              maxHeight: 200,
            ),
          ),
          UpdateProps(
            nodeId: 7,
            props: DecoratedBoxProps(
              backgroundArgb: 0xff28323c,
              borderRadius: 8,
            ),
          ),
          UpdateProps(nodeId: 8, props: ClipProps(ClipBehaviorValue.antiAlias)),
          UpdateProps(nodeId: 9, props: OpacityProps(0.5)),
          UpdateProps(
            nodeId: 10,
            props: TransformProps([
              2,
              0,
              0,
              0,
              0,
              3,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            ]),
          ),
          UpdateProps(
            nodeId: 11,
            props: ListViewProps(axis: ScrollAxis.vertical, reverse: false),
          ),
          UpdateProps(
            nodeId: 12,
            props: SafeAreaProps(
              left: true,
              top: true,
              right: true,
              bottom: true,
              minimum: EdgeInsetsValue(left: 1, top: 2, right: 3, bottom: 4),
            ),
          ),
          UpdateProps(nodeId: 13, props: EnvironmentBoundaryProps()),
        ],
      );

      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      expect(
        decoded.operations.cast<UpdateProps>().map(
          (operation) => operation.props.runtimeType,
        ),
        [
          RichTextProps,
          IconProps,
          ImageProps,
          AlignProps,
          SizedBoxProps,
          ConstrainedBoxProps,
          DecoratedBoxProps,
          ClipProps,
          OpacityProps,
          TransformProps,
          ListViewProps,
          SafeAreaProps,
          EnvironmentBoundaryProps,
        ],
      );
    });

    test('rejects malformed headers and payloads deterministically', () {
      final valid = readHexFixture('counter_full.hex');

      expectDecodeError(mutate(valid, 0, 0), ProtocolErrorCode.invalidMagic);
      expectDecodeError(
        Uint8List.sublistView(valid, 0, 47),
        ProtocolErrorCode.truncatedInput,
      );
      expectDecodeError(
        mutate(valid, 4, 2),
        ProtocolErrorCode.unsupportedVersion,
      );
      expectDecodeError(mutate(valid, 8, 47), ProtocolErrorCode.invalidHeader);
      expectDecodeError(
        mutate(valid, 10, 99),
        ProtocolErrorCode.invalidFrameKind,
      );
      expectDecodeError(mutate(valid, 11, 1), ProtocolErrorCode.invalidFlags);
      expectDecodeError(mutate(valid, 44, 1), ProtocolErrorCode.invalidHeader);

      final wrongLength = Uint8List.fromList(valid);
      writeUint32(wrongLength, 36, readUint32(valid, 36) + 1);
      expectDecodeError(wrongLength, ProtocolErrorCode.invalidPayloadLength);

      expectDecodeError(
        Uint8List.fromList([...valid, 0]),
        ProtocolErrorCode.invalidPayloadLength,
      );
      expectDecodeError(
        mutate(valid, 48, 0xff),
        ProtocolErrorCode.unknownOperation,
      );
      expectDecodeError(
        mutate(valid, 66, 0xff),
        ProtocolErrorCode.unknownNodeKind,
      );
      expectDecodeError(mutate(valid, 90, 0xff), ProtocolErrorCode.invalidUtf8);
      expectDecodeError(
        mutate(valid, 48, 2),
        ProtocolErrorCode.invalidOperationOrder,
      );
    });

    test('rejects values above configured limits before allocation', () {
      final oversized = 'x' * (ProtocolLimits.maxStringBytes + 1);
      final frame = counterSnapshot(text: oversized);

      expect(
        () => FrameCodec.encode(frame),
        throwsA(
          isA<ProtocolException>().having(
            (error) => error.code,
            'code',
            ProtocolErrorCode.stringTooLarge,
          ),
        ),
      );
    });
  });
}

void expectDecodeError(Uint8List bytes, ProtocolErrorCode code) {
  expect(
    () => FrameCodec.decode(bytes),
    throwsA(
      isA<ProtocolException>().having((error) => error.code, 'code', code),
    ),
  );
}

Uint8List mutate(Uint8List source, int offset, int value) {
  final result = Uint8List.fromList(source);
  result[offset] = value;
  return result;
}

int readUint16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);

int readUint32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

int readUint64(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint64(offset, Endian.little);

void writeUint32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
