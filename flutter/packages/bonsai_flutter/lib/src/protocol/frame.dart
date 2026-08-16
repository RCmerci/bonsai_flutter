import 'dart:typed_data';

enum FrameKind { fullSnapshot, incremental }

enum NodeKind {
  empty,
  text,
  richText,
  icon,
  image,
  row,
  column,
  stack,
  button,
  padding,
  align,
  center,
  sizedBox,
  constrainedBox,
  decoratedBox,
  clip,
  opacity,
  animatedOpacity,
  transform,
  scrollView,
  sliverBox,
  sliverList,
  sliverFill,
  sliverFixedExtent,
  sliverVariedExtent,
  sliverPadding,
  sliverAppBar,
  gesture,
  focusScope,
  mouseRegion,
  keyboardListener,
  pressable,
  semantics,
  theme,
  materialScaffold,
  materialAppBar,
  materialElevatedButton,
  materialTextButton,
  materialIconButton,
  materialCheckbox,
  materialSwitch,
  materialListTile,
  materialDivider,
  materialCard,
  materialCircularProgressIndicator,
  cupertinoButton,
  cupertinoSwitch,
  textInput,
  overlay,
  navigator,
  page,
  safeArea,
  environmentBoundary,
  materialDialog,
  nativeWidget,
}

enum ScrollAxis { horizontal, vertical }

enum AlignmentValue {
  topStart,
  topCenter,
  topEnd,
  centerStart,
  center,
  centerEnd,
  bottomStart,
  bottomCenter,
  bottomEnd,
}

enum ImageFitValue {
  fill,
  contain,
  cover,
  fitWidth,
  fitHeight,
  none,
  scaleDown,
}

enum ClipBehaviorValue { hardEdge, antiAlias, antiAliasWithSaveLayer }

enum ThemeBrightness { light, dark }

enum TextFontWeight { normal, medium, semiBold, bold }

enum TextAlignValue { start, center, end }

enum TextOverflowValue { clip, fade, ellipsis, visible }

enum SemanticsRoleValue {
  generic(0),
  button(1),
  link(2),
  image(3),
  header(4),
  textField(5),
  checkbox(6),
  switchControl(7),
  slider(8);

  const SemanticsRoleValue(this.wireId);

  final int wireId;
}

enum SemanticsActionValue {
  tap(1),
  longPress(2),
  focus(3),
  increase(4),
  decrease(5),
  copy(6),
  cut(7),
  paste(8),
  dismiss(9);

  const SemanticsActionValue(this.wireId);

  final int wireId;

  static const int tapWireId = 1;
}

enum TextKeyboardType { text, multiline, number, email, phone, url }

enum TextInputActionKind { done, newline, next, previous, search, send, go }

enum TextUpdateMode { ack, correction, forceReplace }

enum PageTransition { none, fade, slide }

sealed class PagePresentation {
  const PagePresentation();
}

final class StandardPagePresentation extends PagePresentation {
  const StandardPagePresentation(this.transition);

  final PageTransition transition;

  @override
  bool operator ==(Object other) =>
      other is StandardPagePresentation && other.transition == transition;

  @override
  int get hashCode => Object.hash(StandardPagePresentation, transition);
}

enum ModalSheetDetent { medium, large }

enum ModalSheetDetentSet { medium, large, mediumAndLarge }

sealed class ModalBottomSheetSizing {
  const ModalBottomSheetSizing();
}

final class ContentBoundedModalSheetSizing extends ModalBottomSheetSizing {
  const ContentBoundedModalSheetSizing();

  @override
  bool operator ==(Object other) => other is ContentBoundedModalSheetSizing;

  @override
  int get hashCode => Object.hash(ContentBoundedModalSheetSizing, 0);
}

final class ScrollControlledModalSheetSizing extends ModalBottomSheetSizing {
  const ScrollControlledModalSheetSizing();

  @override
  bool operator ==(Object other) => other is ScrollControlledModalSheetSizing;

  @override
  int get hashCode => Object.hash(ScrollControlledModalSheetSizing, 0);
}

final class ModalSheetHandleSemantics {
  const ModalSheetHandleSemantics({
    required this.label,
    required this.mediumValue,
    required this.largeValue,
  });

  final String label;
  final String mediumValue;
  final String largeValue;

  @override
  bool operator ==(Object other) =>
      other is ModalSheetHandleSemantics &&
      other.label == label &&
      other.mediumValue == mediumValue &&
      other.largeValue == largeValue;

  @override
  int get hashCode => Object.hash(label, mediumValue, largeValue);
}

final class DetentedModalSheetSizing extends ModalBottomSheetSizing {
  const DetentedModalSheetSizing({
    required this.detents,
    required this.initialDetent,
    required this.dismissOnDrag,
    required this.handleSemantics,
  });

  final ModalSheetDetentSet detents;
  final ModalSheetDetent initialDetent;
  final bool dismissOnDrag;
  final ModalSheetHandleSemantics handleSemantics;

  @override
  bool operator ==(Object other) =>
      other is DetentedModalSheetSizing &&
      other.detents == detents &&
      other.initialDetent == initialDetent &&
      other.dismissOnDrag == dismissOnDrag &&
      other.handleSemantics == handleSemantics;

  @override
  int get hashCode =>
      Object.hash(detents, initialDetent, dismissOnDrag, handleSemantics);
}

final class ModalBottomSheetPresentation extends PagePresentation {
  const ModalBottomSheetPresentation({
    required this.barrierDismissible,
    required this.barrierColorArgb,
    required this.barrierLabel,
    required this.sizing,
    required this.useSafeArea,
    required this.requestFocus,
    required this.transitionDurationMilliseconds,
    required this.reverseTransitionDurationMilliseconds,
  });

  final bool barrierDismissible;
  final int? barrierColorArgb;
  final String? barrierLabel;
  final ModalBottomSheetSizing sizing;
  final bool useSafeArea;
  final bool requestFocus;
  final int transitionDurationMilliseconds;
  final int reverseTransitionDurationMilliseconds;

  @override
  bool operator ==(Object other) =>
      other is ModalBottomSheetPresentation &&
      other.barrierDismissible == barrierDismissible &&
      other.barrierColorArgb == barrierColorArgb &&
      other.barrierLabel == barrierLabel &&
      other.sizing == sizing &&
      other.useSafeArea == useSafeArea &&
      other.requestFocus == requestFocus &&
      other.transitionDurationMilliseconds == transitionDurationMilliseconds &&
      other.reverseTransitionDurationMilliseconds ==
          reverseTransitionDurationMilliseconds;

  @override
  int get hashCode => Object.hash(
    ModalBottomSheetPresentation,
    barrierDismissible,
    barrierColorArgb,
    barrierLabel,
    sizing,
    useSafeArea,
    requestFocus,
    transitionDurationMilliseconds,
    reverseTransitionDurationMilliseconds,
  );
}

enum OverlayAlignment {
  topStart,
  topCenter,
  topEnd,
  centerStart,
  center,
  centerEnd,
  bottomStart,
  bottomCenter,
  bottomEnd,
}

sealed class ParentDataValue {
  const ParentDataValue();
}

final class NoParentData extends ParentDataValue {
  const NoParentData();
}

enum FlexParentFit { loose, tight }

enum MaterialButtonVariant { elevated, text, icon }

enum KeyEventPolicy { handled, ignored }

final class FlexParentData extends ParentDataValue {
  const FlexParentData({required this.flex, required this.fit});

  final int flex;
  final FlexParentFit fit;
}

final class StackPositionData extends ParentDataValue {
  const StackPositionData({this.left, this.top, this.right, this.bottom});

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
}

sealed class UiProps {
  const UiProps();
}

final class EmptyProps extends UiProps {
  const EmptyProps();

  @override
  bool operator ==(Object other) => other is EmptyProps;

  @override
  int get hashCode => 1;
}

final class EnvironmentBoundaryProps extends UiProps {
  const EnvironmentBoundaryProps();
}

final class LinearProps extends UiProps {
  const LinearProps();

  @override
  bool operator ==(Object other) => other is LinearProps;

  @override
  int get hashCode => 2;
}

final class TextStyleValue {
  const TextStyleValue({
    this.fontSize,
    this.fontWeight,
    this.lineHeight,
    this.colorArgb,
  });

  final double? fontSize;
  final TextFontWeight? fontWeight;
  final double? lineHeight;
  final int? colorArgb;

  @override
  bool operator ==(Object other) =>
      other is TextStyleValue &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(fontSize, fontWeight, lineHeight, colorArgb);
}

final class TextProps extends UiProps {
  const TextProps(
    this.value, {
    this.style,
    this.textAlign = TextAlignValue.start,
    this.maxLines,
    this.overflow = TextOverflowValue.clip,
  });

  final String value;
  final TextStyleValue? style;
  final TextAlignValue textAlign;
  final int? maxLines;
  final TextOverflowValue overflow;

  @override
  bool operator ==(Object other) =>
      other is TextProps &&
      other.value == value &&
      other.style == style &&
      other.textAlign == textAlign &&
      other.maxLines == maxLines &&
      other.overflow == overflow;

  @override
  int get hashCode =>
      Object.hash(TextProps, value, style, textAlign, maxLines, overflow);
}

final class RichTextProps extends UiProps {
  const RichTextProps(this.spans);

  final List<String> spans;
}

final class IconProps extends UiProps {
  const IconProps({
    required this.codePoint,
    required this.fontFamily,
    required this.size,
    required this.colorArgb,
  });

  final int codePoint;
  final String? fontFamily;
  final double? size;
  final int? colorArgb;
}

final class ImageProps extends UiProps {
  const ImageProps({
    required this.uri,
    required this.fit,
    required this.width,
    required this.height,
  });

  final String uri;
  final ImageFitValue fit;
  final double? width;
  final double? height;
}

final class ButtonProps extends UiProps {
  const ButtonProps({required this.enabled});

  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is ButtonProps && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(ButtonProps, enabled);
}

final class PressableProps extends UiProps {
  const PressableProps({
    required this.overlayColorArgb,
    required this.releaseDelayMs,
  });

  final int overlayColorArgb;
  final int releaseDelayMs;

  @override
  bool operator ==(Object other) =>
      other is PressableProps &&
      other.overlayColorArgb == overlayColorArgb &&
      other.releaseDelayMs == releaseDelayMs;

  @override
  int get hashCode =>
      Object.hash(PressableProps, overlayColorArgb, releaseDelayMs);
}

final class EdgeInsetsValue {
  const EdgeInsetsValue({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsetsValue &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

final class PaddingProps extends UiProps {
  const PaddingProps(this.insets);

  final EdgeInsetsValue insets;

  @override
  bool operator ==(Object other) =>
      other is PaddingProps && other.insets == insets;

  @override
  int get hashCode => Object.hash(PaddingProps, insets);
}

final class AlignProps extends UiProps {
  const AlignProps(this.alignment);

  final AlignmentValue alignment;
}

final class CenterProps extends UiProps {
  const CenterProps({this.widthFactor, this.heightFactor});

  final double? widthFactor;
  final double? heightFactor;

  @override
  bool operator ==(Object other) =>
      other is CenterProps &&
      other.widthFactor == widthFactor &&
      other.heightFactor == heightFactor;

  @override
  int get hashCode => Object.hash(CenterProps, widthFactor, heightFactor);
}

final class SizedBoxProps extends UiProps {
  const SizedBoxProps({required this.width, required this.height});

  final double? width;
  final double? height;
}

final class ConstrainedBoxProps extends UiProps {
  const ConstrainedBoxProps({
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
  });

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
}

final class DecoratedBoxProps extends UiProps {
  const DecoratedBoxProps({
    required this.backgroundArgb,
    required this.borderRadius,
  });

  final int? backgroundArgb;
  final double borderRadius;
}

final class ClipProps extends UiProps {
  const ClipProps(this.behavior);

  final ClipBehaviorValue behavior;
}

enum AnimationCurveValue { linear, easeIn, easeOut, easeInOut }

final class AnimationIntent {
  const AnimationIntent({
    required this.id,
    required this.durationMilliseconds,
    required this.curve,
  });

  final int id;
  final int durationMilliseconds;
  final AnimationCurveValue curve;

  @override
  bool operator ==(Object other) =>
      other is AnimationIntent &&
      other.id == id &&
      other.durationMilliseconds == durationMilliseconds &&
      other.curve == curve;

  @override
  int get hashCode =>
      Object.hash(AnimationIntent, id, durationMilliseconds, curve);
}

final class OpacityProps extends UiProps {
  const OpacityProps(this.opacity);

  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is OpacityProps && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(OpacityProps, opacity);
}

final class AnimatedOpacityProps extends UiProps {
  const AnimatedOpacityProps({required this.opacity, required this.animation});

  final double opacity;
  final AnimationIntent animation;

  @override
  bool operator ==(Object other) =>
      other is AnimatedOpacityProps &&
      other.opacity == opacity &&
      other.animation == animation;

  @override
  int get hashCode => Object.hash(AnimatedOpacityProps, opacity, animation);
}

final class TransformProps extends UiProps {
  const TransformProps(this.matrix4);

  final List<double> matrix4;
}

final class ScrollViewProps extends UiProps {
  const ScrollViewProps({
    required this.axis,
    required this.reverse,
    this.primary = false,
  });

  final ScrollAxis axis;
  final bool reverse;
  final bool primary;

  @override
  bool operator ==(Object other) =>
      other is ScrollViewProps &&
      other.axis == axis &&
      other.reverse == reverse &&
      other.primary == primary;

  @override
  int get hashCode => Object.hash(ScrollViewProps, axis, reverse, primary);
}

enum SparseExtentCurve {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  easeOutCubic,
  easeInOutCubic;

  int get wireId => switch (this) {
    linear => 0,
    easeIn => 1,
    easeOut => 2,
    easeInOut => 3,
    easeOutCubic => 4,
    easeInOutCubic => 5,
  };

  static SparseExtentCurve fromWireId(int value) => switch (value) {
    0 => linear,
    1 => easeIn,
    2 => easeOut,
    3 => easeInOut,
    4 => easeOutCubic,
    5 => easeInOutCubic,
    _ => throw const FormatException('invalid sparse extent curve'),
  };
}

final class SparseExtentTransition {
  const SparseExtentTransition({
    required this.enabled,
    required this.expandDurationMs,
    required this.collapseDurationMs,
    required this.expandCurve,
    required this.collapseCurve,
  });

  final bool enabled;
  final int expandDurationMs;
  final int collapseDurationMs;
  final SparseExtentCurve expandCurve;
  final SparseExtentCurve collapseCurve;

  @override
  bool operator ==(Object other) =>
      other is SparseExtentTransition &&
      other.enabled == enabled &&
      other.expandDurationMs == expandDurationMs &&
      other.collapseDurationMs == collapseDurationMs &&
      other.expandCurve == expandCurve &&
      other.collapseCurve == collapseCurve;

  @override
  int get hashCode => Object.hash(
    enabled,
    expandDurationMs,
    collapseDurationMs,
    expandCurve,
    collapseCurve,
  );
}

final class SparseExtentOverride {
  const SparseExtentOverride({required this.index, required this.extent});

  final int index;
  final double extent;

  @override
  bool operator ==(Object other) =>
      other is SparseExtentOverride &&
      other.index == index &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(index, extent);
}

final class SliverFillProps extends UiProps {
  const SliverFillProps({required this.flex});

  final int flex;

  @override
  bool operator ==(Object other) =>
      other is SliverFillProps && other.flex == flex;

  @override
  int get hashCode => Object.hash(SliverFillProps, flex);
}

final class SliverFixedExtentProps extends UiProps {
  const SliverFixedExtentProps({
    required this.totalCount,
    required this.firstIndex,
    required this.itemExtent,
    required this.overscan,
  });

  final int totalCount;
  final int firstIndex;
  final double itemExtent;
  final int overscan;

  @override
  bool operator ==(Object other) =>
      other is SliverFixedExtentProps &&
      other.totalCount == totalCount &&
      other.firstIndex == firstIndex &&
      other.itemExtent == itemExtent &&
      other.overscan == overscan;

  @override
  int get hashCode => Object.hash(
    SliverFixedExtentProps,
    totalCount,
    firstIndex,
    itemExtent,
    overscan,
  );
}

final class SliverVariedExtentProps extends UiProps {
  const SliverVariedExtentProps({
    required this.totalCount,
    required this.firstIndex,
    required this.defaultItemExtent,
    required this.overscan,
    required this.extentOverrides,
    this.transition,
  });

  final int totalCount;
  final int firstIndex;
  final double defaultItemExtent;
  final int overscan;
  final List<SparseExtentOverride> extentOverrides;
  final SparseExtentTransition? transition;

  @override
  bool operator ==(Object other) =>
      other is SliverVariedExtentProps &&
      other.totalCount == totalCount &&
      other.firstIndex == firstIndex &&
      other.defaultItemExtent == defaultItemExtent &&
      other.overscan == overscan &&
      _listEquals(other.extentOverrides, extentOverrides) &&
      other.transition == transition;

  @override
  int get hashCode => Object.hash(
    SliverVariedExtentProps,
    totalCount,
    firstIndex,
    defaultItemExtent,
    overscan,
    Object.hashAll(extentOverrides),
    transition,
  );
}

final class SliverPaddingProps extends UiProps {
  const SliverPaddingProps(this.insets);

  final EdgeInsetsValue insets;

  @override
  bool operator ==(Object other) =>
      other is SliverPaddingProps && other.insets == insets;

  @override
  int get hashCode => Object.hash(SliverPaddingProps, insets);
}

final class SliverAppBarProps extends UiProps {
  const SliverAppBarProps({
    required this.pinned,
    this.expandedHeight,
    this.collapsedHeight,
  });

  final bool pinned;
  final double? expandedHeight;
  final double? collapsedHeight;

  @override
  bool operator ==(Object other) =>
      other is SliverAppBarProps &&
      other.pinned == pinned &&
      other.expandedHeight == expandedHeight &&
      other.collapsedHeight == collapsedHeight;

  @override
  int get hashCode =>
      Object.hash(SliverAppBarProps, pinned, expandedHeight, collapsedHeight);
}

final class GestureProps extends UiProps {
  const GestureProps();
}

final class FocusScopeProps extends UiProps {
  const FocusScopeProps({required this.autofocus});

  final bool autofocus;
}

final class MouseRegionProps extends UiProps {
  const MouseRegionProps({required this.opaque});

  final bool opaque;
}

final class KeyboardListenerProps extends UiProps {
  const KeyboardListenerProps({
    required this.autofocus,
    required this.keyPolicy,
  });

  final bool autofocus;
  final KeyEventPolicy keyPolicy;
}

final class SemanticsProps extends UiProps {
  const SemanticsProps({
    this.label,
    this.hint,
    this.value,
    this.role = SemanticsRoleValue.generic,
    this.enabled,
    this.selected,
    this.checked,
    this.focusable,
    this.obscured = false,
    this.liveRegion = false,
    this.headingLevel,
    this.sortKey,
    this.actions = const {},
  });

  final String? label;
  final String? hint;
  final String? value;
  final SemanticsRoleValue role;
  final bool? enabled;
  final bool? selected;
  final bool? checked;
  final bool? focusable;
  final bool obscured;
  final bool liveRegion;
  final int? headingLevel;
  final double? sortKey;
  final Set<SemanticsActionValue> actions;

  @override
  bool operator ==(Object other) =>
      other is SemanticsProps &&
      other.label == label &&
      other.hint == hint &&
      other.value == value &&
      other.role == role &&
      other.enabled == enabled &&
      other.selected == selected &&
      other.checked == checked &&
      other.focusable == focusable &&
      other.obscured == obscured &&
      other.liveRegion == liveRegion &&
      other.headingLevel == headingLevel &&
      other.sortKey == sortKey &&
      other.actions.length == actions.length &&
      other.actions.containsAll(actions);

  @override
  int get hashCode => Object.hash(
    SemanticsProps,
    label,
    hint,
    value,
    role,
    enabled,
    selected,
    checked,
    focusable,
    obscured,
    liveRegion,
    headingLevel,
    sortKey,
    Object.hashAllUnordered(actions),
  );
}

final class ThemeProps extends UiProps {
  const ThemeProps({required this.brightness, required this.colorSeedArgb});

  final ThemeBrightness brightness;
  final int colorSeedArgb;

  @override
  bool operator ==(Object other) =>
      other is ThemeProps &&
      other.brightness == brightness &&
      other.colorSeedArgb == colorSeedArgb;

  @override
  int get hashCode => Object.hash(ThemeProps, brightness, colorSeedArgb);
}

final class MaterialCheckboxProps extends UiProps {
  const MaterialCheckboxProps({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is MaterialCheckboxProps &&
      other.value == value &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(MaterialCheckboxProps, value, enabled);
}

final class MaterialScaffoldProps extends UiProps {
  const MaterialScaffoldProps({required this.hasAppBar});

  final bool hasAppBar;
}

final class MaterialAppBarProps extends UiProps {
  const MaterialAppBarProps({required this.centerTitle});

  final bool centerTitle;
}

final class MaterialButtonProps extends UiProps {
  const MaterialButtonProps({
    required this.variant,
    required this.enabled,
    required this.autofocus,
  });

  final MaterialButtonVariant variant;
  final bool enabled;
  final bool autofocus;
}

final class MaterialSwitchProps extends UiProps {
  const MaterialSwitchProps({required this.value, required this.enabled});

  final bool value;
  final bool enabled;
}

final class MaterialListTileProps extends UiProps {
  const MaterialListTileProps({
    required this.enabled,
    required this.selected,
    required this.hasSubtitle,
    required this.hasLeading,
    required this.hasTrailing,
  });

  final bool enabled;
  final bool selected;
  final bool hasSubtitle;
  final bool hasLeading;
  final bool hasTrailing;
}

final class MaterialDividerProps extends UiProps {
  const MaterialDividerProps({required this.thickness});

  final double thickness;
}

final class MaterialCardProps extends UiProps {
  const MaterialCardProps({required this.elevation});

  final double elevation;
}

final class MaterialProgressProps extends UiProps {
  const MaterialProgressProps({this.value});

  final double? value;
}

final class CupertinoButtonProps extends UiProps {
  const CupertinoButtonProps({required this.enabled});

  final bool enabled;
}

final class CupertinoSwitchProps extends UiProps {
  const CupertinoSwitchProps({required this.value, required this.enabled});

  final bool value;
  final bool enabled;
}

final class TextRangeValue {
  const TextRangeValue({required this.startUtf16, required this.endUtf16});

  final int startUtf16;
  final int endUtf16;

  @override
  bool operator ==(Object other) =>
      other is TextRangeValue &&
      other.startUtf16 == startUtf16 &&
      other.endUtf16 == endUtf16;

  @override
  int get hashCode => Object.hash(TextRangeValue, startUtf16, endUtf16);
}

final class TextEditingStateValue {
  const TextEditingStateValue({
    required this.text,
    required this.selection,
    required this.composing,
  });

  final String text;
  final TextRangeValue selection;
  final TextRangeValue? composing;

  @override
  bool operator ==(Object other) =>
      other is TextEditingStateValue &&
      other.text == text &&
      other.selection == selection &&
      other.composing == composing;

  @override
  int get hashCode =>
      Object.hash(TextEditingStateValue, text, selection, composing);
}

final class TextInputProps extends UiProps {
  const TextInputProps({
    required this.sessionId,
    required this.documentRevision,
    required this.value,
    required this.enabled,
    required this.readOnly,
    required this.obscureText,
    required this.keyboardType,
    required this.inputAction,
    required this.acceptedLocalRevision,
    required this.updateMode,
    required this.autofocus,
    this.maxUtf8Bytes,
  });

  final int sessionId;
  final int documentRevision;
  final TextEditingStateValue value;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final TextKeyboardType keyboardType;
  final TextInputActionKind inputAction;
  final int acceptedLocalRevision;
  final TextUpdateMode updateMode;
  final bool autofocus;
  final int? maxUtf8Bytes;

  @override
  bool operator ==(Object other) =>
      other is TextInputProps &&
      other.sessionId == sessionId &&
      other.documentRevision == documentRevision &&
      other.value == value &&
      other.enabled == enabled &&
      other.readOnly == readOnly &&
      other.obscureText == obscureText &&
      other.keyboardType == keyboardType &&
      other.inputAction == inputAction &&
      other.acceptedLocalRevision == acceptedLocalRevision &&
      other.updateMode == updateMode &&
      other.autofocus == autofocus &&
      other.maxUtf8Bytes == maxUtf8Bytes;

  @override
  int get hashCode => Object.hash(
    TextInputProps,
    sessionId,
    documentRevision,
    value,
    enabled,
    readOnly,
    obscureText,
    keyboardType,
    inputAction,
    acceptedLocalRevision,
    updateMode,
    autofocus,
    maxUtf8Bytes,
  );
}

final class OverlayProps extends UiProps {
  const OverlayProps({required this.alignment, required this.dismissible});

  final OverlayAlignment alignment;
  final bool dismissible;

  @override
  bool operator ==(Object other) =>
      other is OverlayProps &&
      other.alignment == alignment &&
      other.dismissible == dismissible;

  @override
  int get hashCode => Object.hash(OverlayProps, alignment, dismissible);
}

final class NavigatorProps extends UiProps {
  const NavigatorProps({this.restorationScopeId});

  final String? restorationScopeId;

  @override
  bool operator ==(Object other) =>
      other is NavigatorProps && other.restorationScopeId == restorationScopeId;

  @override
  int get hashCode => Object.hash(NavigatorProps, restorationScopeId);
}

final class PageProps extends UiProps {
  const PageProps({
    required this.pageKey,
    required this.presentation,
    required this.canPop,
    required this.restorationId,
  });

  final String pageKey;
  final PagePresentation presentation;
  final bool canPop;
  final String? restorationId;

  @override
  bool operator ==(Object other) =>
      other is PageProps &&
      other.pageKey == pageKey &&
      other.presentation == presentation &&
      other.canPop == canPop &&
      other.restorationId == restorationId;

  @override
  int get hashCode =>
      Object.hash(PageProps, pageKey, presentation, canPop, restorationId);
}

final class SafeAreaProps extends UiProps {
  const SafeAreaProps({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.minimum,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final EdgeInsetsValue minimum;
}

final class MaterialDialogProps extends UiProps {
  const MaterialDialogProps({required this.barrierDismissible});

  final bool barrierDismissible;

  @override
  bool operator ==(Object other) =>
      other is MaterialDialogProps &&
      other.barrierDismissible == barrierDismissible;

  @override
  int get hashCode => Object.hash(MaterialDialogProps, barrierDismissible);
}

final class NativeWidgetProps extends UiProps {
  NativeWidgetProps({
    required this.kindId,
    required this.version,
    required this.capabilityBits,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  final int kindId;
  final int version;
  final int capabilityBits;
  final Uint8List payload;

  @override
  bool operator ==(Object other) =>
      other is NativeWidgetProps &&
      other.kindId == kindId &&
      other.version == version &&
      other.capabilityBits == capabilityBits &&
      _frameBytesEqual(other.payload, payload);

  @override
  int get hashCode => Object.hash(
    NativeWidgetProps,
    kindId,
    version,
    capabilityBits,
    Object.hashAll(payload),
  );
}

final class EventBinding {
  const EventBinding({required this.eventTag, required this.handlerId});

  final int eventTag;
  final int handlerId;
}

sealed class FrameOperation {
  const FrameOperation();
}

final class CreateNode extends FrameOperation {
  const CreateNode({
    required this.nodeId,
    required this.kind,
    required this.props,
    required this.eventBindings,
    this.parentData = const NoParentData(),
  });

  final int nodeId;
  final NodeKind kind;
  final UiProps props;
  final List<EventBinding> eventBindings;
  final ParentDataValue parentData;
}

final class UpdateProps extends FrameOperation {
  const UpdateProps({required this.nodeId, required this.props});

  final int nodeId;
  final UiProps props;
}

final class UpdateEventBindings extends FrameOperation {
  const UpdateEventBindings({
    required this.nodeId,
    required this.eventBindings,
  });

  final int nodeId;
  final List<EventBinding> eventBindings;
}

final class SetChildren extends FrameOperation {
  const SetChildren({required this.nodeId, required this.children});

  final int nodeId;
  final List<int> children;
}

final class SetRoot extends FrameOperation {
  const SetRoot(this.nodeId);

  final int nodeId;
}

final class DropNode extends FrameOperation {
  const DropNode(this.nodeId);

  final int nodeId;
}

sealed class HostRequest {
  const HostRequest();
}

final class ClipboardReadRequest extends HostRequest {
  const ClipboardReadRequest();
}

final class ClipboardWriteRequest extends HostRequest {
  const ClipboardWriteRequest(this.text);
  final String text;
}

final class OpenUrlRequest extends HostRequest {
  const OpenUrlRequest(this.uri);
  final String uri;
}

final class PickFileRequest extends HostRequest {
  const PickFileRequest({
    required this.allowedExtensions,
    required this.allowMultiple,
  });

  final List<String> allowedExtensions;
  final bool allowMultiple;
}

final class SaveFileRequest extends HostRequest {
  const SaveFileRequest({this.suggestedName, required this.data});

  final String? suggestedName;
  final List<int> data;
}

final class RequestFocusRequest extends HostRequest {
  const RequestFocusRequest(this.nodeId);
  final int nodeId;
}

final class ClearFocusRequest extends HostRequest {
  const ClearFocusRequest();
}

final class ScrollToRequest extends HostRequest {
  const ScrollToRequest({
    required this.nodeId,
    required this.alignment,
    required this.animated,
  });

  final int nodeId;
  final double alignment;
  final bool animated;
}

final class SetWindowTitleRequest extends HostRequest {
  const SetWindowTitleRequest(this.title);
  final String title;
}

final class SetWindowSizeRequest extends HostRequest {
  const SetWindowSizeRequest({required this.width, required this.height});
  final double width;
  final double height;
}

final class NativeMenuItemValue {
  const NativeMenuItemValue({
    required this.itemId,
    required this.label,
    required this.enabled,
  });

  final String itemId;
  final String label;
  final bool enabled;
}

final class ShowNativeMenuRequest extends HostRequest {
  const ShowNativeMenuRequest(this.items);
  final List<NativeMenuItemValue> items;
}

enum HapticKind { light, medium, heavy, selection }

final class HapticFeedbackRequest extends HostRequest {
  const HapticFeedbackRequest(this.kind);
  final HapticKind kind;
}

final class PlatformInformationRequest extends HostRequest {
  const PlatformInformationRequest();
}

final class MeasureLayoutRequest extends HostRequest {
  const MeasureLayoutRequest(this.nodeId);
  final int nodeId;
}

final class HostRequestOperation extends FrameOperation {
  const HostRequestOperation({required this.requestId, required this.request});

  final int requestId;
  final HostRequest request;
}

final class CancelHostRequestOperation extends FrameOperation {
  const CancelHostRequestOperation({required this.requestId});
  final int requestId;
}

final class ApplicationRequestOperation extends FrameOperation {
  ApplicationRequestOperation({
    required this.requestId,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  final int requestId;
  final Uint8List payload;
}

final class RuntimeStatsOperation extends FrameOperation {
  const RuntimeStatsOperation({
    required this.eventBatchSize,
    required this.bonsaiFlushNanoseconds,
    required this.resultReadNanoseconds,
    required this.reconcileNanoseconds,
    required this.encodeNanoseconds,
    required this.patchCount,
    required this.patchBytes,
    required this.lifecycleNanoseconds,
    required this.fullSnapshotCount,
    required this.resyncCount,
  });

  final int eventBatchSize;
  final int bonsaiFlushNanoseconds;
  final int resultReadNanoseconds;
  final int reconcileNanoseconds;
  final int encodeNanoseconds;
  final int patchCount;
  final int patchBytes;
  final int lifecycleNanoseconds;
  final int fullSnapshotCount;
  final int resyncCount;
}

final class Frame {
  const Frame({
    required this.runtimeEpoch,
    required this.baseRevision,
    required this.targetRevision,
    required this.kind,
    required this.operations,
  });

  final int runtimeEpoch;
  final int baseRevision;
  final int targetRevision;
  final FrameKind kind;
  final List<FrameOperation> operations;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

bool _frameBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
