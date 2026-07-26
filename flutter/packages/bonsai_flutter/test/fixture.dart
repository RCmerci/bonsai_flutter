import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/src/protocol/frame.dart';

Frame counterSnapshot({required String text}) => Frame(
  runtimeEpoch: 7,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const CreateNode(
      nodeId: 1,
      kind: NodeKind.column,
      props: LinearProps(),
      eventBindings: [],
    ),
    CreateNode(
      nodeId: 2,
      kind: NodeKind.text,
      props: TextProps(text),
      eventBindings: const [],
    ),
    const SetChildren(nodeId: 1, children: [2]),
    const SetRoot(1),
  ],
);

File hexFixtureFile(String name) =>
    File('../../../protocol/generated/fixtures/$name');

Uint8List readHexFixture(String name) {
  final file = hexFixtureFile(name);
  final compact = file.readAsStringSync().replaceAll(RegExp(r'\s+'), '');
  if (compact.length.isOdd) {
    throw FormatException('Hex fixture has an odd number of digits', name);
  }
  return Uint8List.fromList([
    for (var index = 0; index < compact.length; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}
