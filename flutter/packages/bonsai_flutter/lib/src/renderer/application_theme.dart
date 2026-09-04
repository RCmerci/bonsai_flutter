import 'package:material_ui/material_ui.dart';

import '../protocol/frame.dart';

ThemeData decodeThemeData(ThemeDataValue data) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Color(data.colorScheme.seedArgb),
    brightness: switch (data.brightness) {
      ThemeBrightness.light => Brightness.light,
      ThemeBrightness.dark => Brightness.dark,
    },
    dynamicSchemeVariant: switch (data.colorScheme.variant) {
      ThemeDynamicVariant.tonalSpot => DynamicSchemeVariant.tonalSpot,
      ThemeDynamicVariant.fidelity => DynamicSchemeVariant.fidelity,
      ThemeDynamicVariant.content => DynamicSchemeVariant.content,
      ThemeDynamicVariant.monochrome => DynamicSchemeVariant.monochrome,
      ThemeDynamicVariant.neutral => DynamicSchemeVariant.neutral,
      ThemeDynamicVariant.vibrant => DynamicSchemeVariant.vibrant,
      ThemeDynamicVariant.expressive => DynamicSchemeVariant.expressive,
    },
    contrastLevel: data.colorScheme.contrastLevel,
  );
  final textTheme = _decodeTypography(data.typography, data.brightness);
  final shape = data.shape;
  RoundedRectangleBorder rounded(double radius) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  final buttonStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(rounded(shape.small)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    visualDensity: switch (data.visualDensity) {
      ThemeVisualDensity.adaptive => VisualDensity.adaptivePlatformDensity,
      ThemeVisualDensity.standard => VisualDensity.standard,
      ThemeVisualDensity.comfortable => const VisualDensity(
        horizontal: -1,
        vertical: -1,
      ),
      ThemeVisualDensity.compact => VisualDensity.compact,
    },
    materialTapTargetSize: switch (data.tapTargetSize) {
      ThemeTapTargetSize.padded => MaterialTapTargetSize.padded,
      ThemeTapTargetSize.shrinkWrap => MaterialTapTargetSize.shrinkWrap,
    },
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    cardTheme: CardThemeData(shape: rounded(shape.medium)),
    chipTheme: ChipThemeData(shape: rounded(shape.small)),
    dialogTheme: DialogThemeData(shape: rounded(shape.extraLarge)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: rounded(shape.large),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(shape.extraSmall),
      ),
    ),
  );
}

ThemeMode decodeApplicationThemeMode(ApplicationThemeMode mode) =>
    switch (mode) {
      ApplicationThemeMode.system => ThemeMode.system,
      ApplicationThemeMode.light => ThemeMode.light,
      ApplicationThemeMode.dark => ThemeMode.dark,
    };

TextTheme _decodeTypography(
  ThemeTypographyValue typography,
  ThemeBrightness brightness,
) {
  final baseline = Typography.material2021().black;
  TextStyle? role(TextStyle? base, TextStyleValue? token) {
    final family = typography.fontFamily;
    final fallback = typography.fontFamilyFallback.isEmpty
        ? null
        : typography.fontFamilyFallback;
    if (base == null && token == null && family == null && fallback == null) {
      return null;
    }
    return (base ?? const TextStyle()).copyWith(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: token?.fontSize,
      fontWeight: switch (token?.fontWeight) {
        null => null,
        TextFontWeight.normal => FontWeight.w400,
        TextFontWeight.medium => FontWeight.w500,
        TextFontWeight.semiBold => FontWeight.w600,
        TextFontWeight.bold => FontWeight.w700,
      },
      height: token?.lineHeight,
      color: token?.colorArgb == null ? null : Color(token!.colorArgb!),
    );
  }

  return TextTheme(
    displayLarge: role(baseline.displayLarge, typography.displayLarge),
    displayMedium: role(baseline.displayMedium, typography.displayMedium),
    displaySmall: role(baseline.displaySmall, typography.displaySmall),
    headlineLarge: role(baseline.headlineLarge, typography.headlineLarge),
    headlineMedium: role(baseline.headlineMedium, typography.headlineMedium),
    headlineSmall: role(baseline.headlineSmall, typography.headlineSmall),
    titleLarge: role(baseline.titleLarge, typography.titleLarge),
    titleMedium: role(baseline.titleMedium, typography.titleMedium),
    titleSmall: role(baseline.titleSmall, typography.titleSmall),
    bodyLarge: role(baseline.bodyLarge, typography.bodyLarge),
    bodyMedium: role(baseline.bodyMedium, typography.bodyMedium),
    bodySmall: role(baseline.bodySmall, typography.bodySmall),
    labelLarge: role(baseline.labelLarge, typography.labelLarge),
    labelMedium: role(baseline.labelMedium, typography.labelMedium),
    labelSmall: role(baseline.labelSmall, typography.labelSmall),
  ).apply(
    bodyColor: brightness == ThemeBrightness.light
        ? Colors.black
        : Colors.white,
    displayColor: brightness == ThemeBrightness.light
        ? Colors.black
        : Colors.white,
  );
}
