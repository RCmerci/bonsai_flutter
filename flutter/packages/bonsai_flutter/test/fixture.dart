import 'dart:io';
import 'dart:typed_data';

import 'package:bonsai_flutter/src/protocol/frame.dart';

const testLightThemeData = ThemeDataValue(
  brightness: ThemeBrightness.light,
  colorScheme: ThemeColorSchemeValue(
    seedArgb: 0xff6750a4,
    variant: ThemeDynamicVariant.tonalSpot,
    contrastLevel: 0,
  ),
  typography: ThemeTypographyValue(),
  shape: ThemeShapeValue(
    extraSmall: 4,
    small: 8,
    medium: 12,
    large: 16,
    extraLarge: 28,
  ),
  visualDensity: ThemeVisualDensity.adaptive,
  tapTargetSize: ThemeTapTargetSize.padded,
);

const testDarkThemeData = ThemeDataValue(
  brightness: ThemeBrightness.dark,
  colorScheme: ThemeColorSchemeValue(
    seedArgb: 0xff6750a4,
    variant: ThemeDynamicVariant.fidelity,
    contrastLevel: 0.5,
  ),
  typography: ThemeTypographyValue(fontFamily: 'Inter'),
  shape: ThemeShapeValue(
    extraSmall: 2,
    small: 6,
    medium: 10,
    large: 14,
    extraLarge: 24,
  ),
  visualDensity: ThemeVisualDensity.compact,
  tapTargetSize: ThemeTapTargetSize.shrinkWrap,
);

const testApplicationTheme = ApplicationThemeValue(
  mode: ApplicationThemeMode.system,
  light: testLightThemeData,
  dark: testDarkThemeData,
);

Frame counterSnapshot({required String text}) => Frame(
  runtimeEpoch: 7,
  baseRevision: 0,
  targetRevision: 1,
  kind: FrameKind.fullSnapshot,
  operations: [
    const SetApplicationTheme(title: 'Counter', theme: testApplicationTheme),
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
