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
  materialFilledButton,
  materialFilledTonalButton,
  materialOutlinedButton,
  materialFloatingActionButton,
  materialNavigationBar,
  materialRadioGroup,
  materialSlider,
  materialRangeSlider,
  materialActionChip,
  materialFilterChip,
  materialChoiceChip,
  materialInputChip,
  materialAlertDialog,
  materialSearchBar,
  materialTooltip,
  materialDataTable,
  materialStepper,
  materialExpansionPanelList,
  materialSimpleDialog,
  materialFullscreenDialog,
  materialCheckbox,
  materialSwitch,
  materialListTile,
  materialDivider,
  materialCard,
  materialCircularProgressIndicator,
  materialLinearProgressIndicator,
  materialSegmentedButton,
  cupertinoButton,
  cupertinoSwitch,
  textInput,
  overlay,
  navigator,
  page,
  safeArea,
  environmentBoundary,
  nativeWidget,
  preferredSize,
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

enum ThemeDynamicVariant {
  tonalSpot,
  fidelity,
  content,
  monochrome,
  neutral,
  vibrant,
  expressive,
}

enum ThemeVisualDensity { adaptive, standard, comfortable, compact }

enum ThemeTapTargetSize { padded, shrinkWrap }

enum ApplicationThemeMode { system, light, dark }

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

final class ModalDialogPresentation extends PagePresentation {
  const ModalDialogPresentation({
    required this.barrierDismissible,
    required this.barrierColorArgb,
    required this.barrierLabel,
    required this.useSafeArea,
    required this.requestFocus,
    required this.transitionDurationMilliseconds,
    required this.reverseTransitionDurationMilliseconds,
  });

  final bool barrierDismissible;
  final int? barrierColorArgb;
  final String? barrierLabel;
  final bool useSafeArea;
  final bool requestFocus;
  final int transitionDurationMilliseconds;
  final int reverseTransitionDurationMilliseconds;

  @override
  bool operator ==(Object other) =>
      other is ModalDialogPresentation &&
      other.barrierDismissible == barrierDismissible &&
      other.barrierColorArgb == barrierColorArgb &&
      other.barrierLabel == barrierLabel &&
      other.useSafeArea == useSafeArea &&
      other.requestFocus == requestFocus &&
      other.transitionDurationMilliseconds == transitionDurationMilliseconds &&
      other.reverseTransitionDurationMilliseconds ==
          reverseTransitionDurationMilliseconds;

  @override
  int get hashCode => Object.hash(
    ModalDialogPresentation,
    barrierDismissible,
    barrierColorArgb,
    barrierLabel,
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

enum MaterialButtonVariant {
  filled,
  filledTonal,
  outlined,
  elevated,
  text,
  icon,
}

enum MaterialFloatingActionButtonLocation {
  startFloat,
  centerFloat,
  endFloat,
  startDocked,
  centerDocked,
  endDocked,
}

enum MaterialFloatingActionButtonVariant { small, standard, large, extended }

enum MaterialChipVariant { action, filter, choice, input }

enum MaterialChipPresentation { flat, elevated }

enum MaterialCardVariant { elevated, filled, outlined }

enum MaterialDividerOrientation { horizontal, vertical }

enum MaterialTooltipTriggerMode { longPress, tap }

enum MaterialStepperOrientation { vertical, horizontal }

enum MaterialStepState { indexed, editing, complete, disabled, error }

enum MaterialExpansionPanelPolicy { multiple, single }

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
    this.cacheExtent,
  });

  final ScrollAxis axis;
  final bool reverse;
  final bool primary;
  final double? cacheExtent;

  @override
  bool operator ==(Object other) =>
      other is ScrollViewProps &&
      other.axis == axis &&
      other.reverse == reverse &&
      other.primary == primary &&
      other.cacheExtent == cacheExtent;

  @override
  int get hashCode =>
      Object.hash(ScrollViewProps, axis, reverse, primary, cacheExtent);
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
  const SliverFillProps();

  @override
  bool operator ==(Object other) => other is SliverFillProps;

  @override
  int get hashCode => 0;
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

String? virtualSliverPropsError(UiProps props) {
  const maxUint32 = 0xffffffff;

  String? validateWindow({
    required int totalCount,
    required int firstIndex,
    required double itemExtent,
    required int overscan,
  }) {
    if (totalCount < 0) return 'Sliver total_count must be non-negative';
    if (firstIndex < 0 || firstIndex > totalCount) {
      return 'Sliver first_index is outside the logical list';
    }
    if (!itemExtent.isFinite || itemExtent <= 0) {
      return 'Sliver item extent must be finite and positive';
    }
    if (overscan < 0 || overscan > maxUint32) {
      return 'Sliver overscan is outside u32';
    }
    return null;
  }

  switch (props) {
    case SliverFixedExtentProps(
      :final totalCount,
      :final firstIndex,
      :final itemExtent,
      :final overscan,
    ):
      return validateWindow(
        totalCount: totalCount,
        firstIndex: firstIndex,
        itemExtent: itemExtent,
        overscan: overscan,
      );
    case SliverVariedExtentProps(
      :final totalCount,
      :final firstIndex,
      :final defaultItemExtent,
      :final overscan,
      :final extentOverrides,
      :final transition,
    ):
      final windowError = validateWindow(
        totalCount: totalCount,
        firstIndex: firstIndex,
        itemExtent: defaultItemExtent,
        overscan: overscan,
      );
      if (windowError != null) return windowError;
      if (extentOverrides.length > totalCount ||
          extentOverrides.length > maxUint32) {
        return 'Sliver override count is outside the logical list';
      }
      int? previousIndex;
      for (final override in extentOverrides) {
        if (override.index < 0 || override.index >= totalCount) {
          return 'Sliver override index is outside the logical list';
        }
        if (previousIndex != null && override.index <= previousIndex) {
          return 'Sliver override indexes must be strictly increasing and unique';
        }
        if (!override.extent.isFinite || override.extent <= 0) {
          return 'Sliver override extent must be finite and positive';
        }
        previousIndex = override.index;
      }
      if (transition != null &&
          (transition.expandDurationMs < 0 ||
              transition.expandDurationMs > maxUint32 ||
              transition.collapseDurationMs < 0 ||
              transition.collapseDurationMs > maxUint32)) {
        return 'Sliver transition duration is outside u32';
      }
      return null;
    case _:
      return null;
  }
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
    this.floating = false,
    this.snap = false,
    this.stretch = false,
    this.toolbarHeight = 56.0,
    this.hasLeading = false,
    this.hasFlexibleSpace = false,
    this.hasBottom = false,
    this.hasActions = false,
    this.forceElevated = false,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
  });

  final bool pinned;
  final double? expandedHeight;
  final double? collapsedHeight;
  final bool floating;
  final bool snap;
  final bool stretch;
  final double toolbarHeight;
  final bool hasLeading;
  final bool hasFlexibleSpace;
  final bool hasBottom;
  final bool hasActions;
  final bool forceElevated;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final int? backgroundColor;
  final int? foregroundColor;
  final double? elevation;

  @override
  bool operator ==(Object other) =>
      other is SliverAppBarProps &&
      other.pinned == pinned &&
      other.expandedHeight == expandedHeight &&
      other.collapsedHeight == collapsedHeight &&
      other.floating == floating &&
      other.snap == snap &&
      other.stretch == stretch &&
      other.toolbarHeight == toolbarHeight &&
      other.hasLeading == hasLeading &&
      other.hasFlexibleSpace == hasFlexibleSpace &&
      other.hasBottom == hasBottom &&
      other.hasActions == hasActions &&
      other.forceElevated == forceElevated &&
      other.automaticallyImplyLeading == automaticallyImplyLeading &&
      other.centerTitle == centerTitle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.elevation == elevation;

  @override
  int get hashCode => Object.hash(
    SliverAppBarProps,
    pinned,
    expandedHeight,
    collapsedHeight,
    floating,
    snap,
    stretch,
    toolbarHeight,
    hasLeading,
    hasFlexibleSpace,
    hasBottom,
    hasActions,
    forceElevated,
    automaticallyImplyLeading,
    centerTitle,
    backgroundColor,
    foregroundColor,
    elevation,
  );
}

final class PreferredSizeProps extends UiProps {
  const PreferredSizeProps({required this.height});

  final double height;

  @override
  bool operator ==(Object other) =>
      other is PreferredSizeProps && other.height == height;

  @override
  int get hashCode => Object.hash(PreferredSizeProps, height);
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

final class ThemeColorSchemeValue {
  const ThemeColorSchemeValue({
    required this.seedArgb,
    required this.variant,
    required this.contrastLevel,
  });
  final int seedArgb;
  final ThemeDynamicVariant variant;
  final double contrastLevel;
  @override
  bool operator ==(Object other) =>
      other is ThemeColorSchemeValue &&
      other.seedArgb == seedArgb &&
      other.variant == variant &&
      other.contrastLevel == contrastLevel;
  @override
  int get hashCode => Object.hash(seedArgb, variant, contrastLevel);
}

final class ThemeTypographyValue {
  const ThemeTypographyValue({
    this.fontFamily,
    this.fontFamilyFallback = const [],
    this.displayLarge,
    this.displayMedium,
    this.displaySmall,
    this.headlineLarge,
    this.headlineMedium,
    this.headlineSmall,
    this.titleLarge,
    this.titleMedium,
    this.titleSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.labelLarge,
    this.labelMedium,
    this.labelSmall,
  });
  final String? fontFamily;
  final List<String> fontFamilyFallback;
  final TextStyleValue? displayLarge, displayMedium, displaySmall;
  final TextStyleValue? headlineLarge, headlineMedium, headlineSmall;
  final TextStyleValue? titleLarge, titleMedium, titleSmall;
  final TextStyleValue? bodyLarge, bodyMedium, bodySmall;
  final TextStyleValue? labelLarge, labelMedium, labelSmall;
  List<TextStyleValue?> get roles => [
    displayLarge,
    displayMedium,
    displaySmall,
    headlineLarge,
    headlineMedium,
    headlineSmall,
    titleLarge,
    titleMedium,
    titleSmall,
    bodyLarge,
    bodyMedium,
    bodySmall,
    labelLarge,
    labelMedium,
    labelSmall,
  ];
  @override
  bool operator ==(Object other) =>
      other is ThemeTypographyValue &&
      other.fontFamily == fontFamily &&
      _listEquals(other.fontFamilyFallback, fontFamilyFallback) &&
      _listEquals(other.roles, roles);
  @override
  int get hashCode => Object.hash(
    fontFamily,
    Object.hashAll(fontFamilyFallback),
    Object.hashAll(roles),
  );
}

final class ThemeShapeValue {
  const ThemeShapeValue({
    required this.extraSmall,
    required this.small,
    required this.medium,
    required this.large,
    required this.extraLarge,
  });
  final double extraSmall, small, medium, large, extraLarge;
  @override
  bool operator ==(Object other) =>
      other is ThemeShapeValue &&
      other.extraSmall == extraSmall &&
      other.small == small &&
      other.medium == medium &&
      other.large == large &&
      other.extraLarge == extraLarge;
  @override
  int get hashCode => Object.hash(extraSmall, small, medium, large, extraLarge);
}

final class ThemeDataValue {
  const ThemeDataValue({
    required this.brightness,
    required this.colorScheme,
    required this.typography,
    required this.shape,
    required this.visualDensity,
    required this.tapTargetSize,
  });
  final ThemeBrightness brightness;
  final ThemeColorSchemeValue colorScheme;
  final ThemeTypographyValue typography;
  final ThemeShapeValue shape;
  final ThemeVisualDensity visualDensity;
  final ThemeTapTargetSize tapTargetSize;
  ThemeDataValue copyWith({
    ThemeBrightness? brightness,
    ThemeColorSchemeValue? colorScheme,
    ThemeTypographyValue? typography,
    ThemeShapeValue? shape,
    ThemeVisualDensity? visualDensity,
    ThemeTapTargetSize? tapTargetSize,
  }) => ThemeDataValue(
    brightness: brightness ?? this.brightness,
    colorScheme: colorScheme ?? this.colorScheme,
    typography: typography ?? this.typography,
    shape: shape ?? this.shape,
    visualDensity: visualDensity ?? this.visualDensity,
    tapTargetSize: tapTargetSize ?? this.tapTargetSize,
  );
  @override
  bool operator ==(Object other) =>
      other is ThemeDataValue &&
      other.brightness == brightness &&
      other.colorScheme == colorScheme &&
      other.typography == typography &&
      other.shape == shape &&
      other.visualDensity == visualDensity &&
      other.tapTargetSize == tapTargetSize;
  @override
  int get hashCode => Object.hash(
    brightness,
    colorScheme,
    typography,
    shape,
    visualDensity,
    tapTargetSize,
  );
}

final class ApplicationThemeValue {
  const ApplicationThemeValue({
    required this.mode,
    required this.light,
    required this.dark,
    this.highContrastLight,
    this.highContrastDark,
  });
  final ApplicationThemeMode mode;
  final ThemeDataValue light, dark;
  final ThemeDataValue? highContrastLight, highContrastDark;
  @override
  bool operator ==(Object other) =>
      other is ApplicationThemeValue &&
      other.mode == mode &&
      other.light == light &&
      other.dark == dark &&
      other.highContrastLight == highContrastLight &&
      other.highContrastDark == highContrastDark;
  @override
  int get hashCode =>
      Object.hash(mode, light, dark, highContrastLight, highContrastDark);
}

final class ThemeProps extends UiProps {
  const ThemeProps({required this.data});

  final ThemeDataValue data;

  @override
  bool operator ==(Object other) => other is ThemeProps && other.data == data;

  @override
  int get hashCode => Object.hash(ThemeProps, data);
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
  const MaterialScaffoldProps({
    required this.hasAppBar,
    this.hasFloatingActionButton = false,
    this.floatingActionButtonLocation =
        MaterialFloatingActionButtonLocation.endFloat,
    this.hasBottomNavigationBar = false,
    this.hasBottomSheet = false,
  });

  final bool hasAppBar;
  final bool hasFloatingActionButton;
  final MaterialFloatingActionButtonLocation floatingActionButtonLocation;
  final bool hasBottomNavigationBar;
  final bool hasBottomSheet;

  @override
  bool operator ==(Object other) =>
      other is MaterialScaffoldProps &&
      other.hasAppBar == hasAppBar &&
      other.hasFloatingActionButton == hasFloatingActionButton &&
      other.floatingActionButtonLocation == floatingActionButtonLocation &&
      other.hasBottomNavigationBar == hasBottomNavigationBar &&
      other.hasBottomSheet == hasBottomSheet;

  @override
  int get hashCode => Object.hash(
    MaterialScaffoldProps,
    hasAppBar,
    hasFloatingActionButton,
    floatingActionButtonLocation,
    hasBottomNavigationBar,
    hasBottomSheet,
  );
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

final class MaterialFloatingActionButtonProps extends UiProps {
  const MaterialFloatingActionButtonProps({
    required this.variant,
    required this.enabled,
    required this.autofocus,
    required this.hasIcon,
  });

  final MaterialFloatingActionButtonVariant variant;
  final bool enabled;
  final bool autofocus;
  final bool hasIcon;

  @override
  bool operator ==(Object other) =>
      other is MaterialFloatingActionButtonProps &&
      other.variant == variant &&
      other.enabled == enabled &&
      other.autofocus == autofocus &&
      other.hasIcon == hasIcon;

  @override
  int get hashCode => Object.hash(
    MaterialFloatingActionButtonProps,
    variant,
    enabled,
    autofocus,
    hasIcon,
  );
}

final class MaterialNavigationDestinationProps {
  const MaterialNavigationDestinationProps({
    required this.label,
    required this.enabled,
    required this.hasSelectedIcon,
  });

  final String label;
  final bool enabled;
  final bool hasSelectedIcon;

  @override
  bool operator ==(Object other) =>
      other is MaterialNavigationDestinationProps &&
      other.label == label &&
      other.enabled == enabled &&
      other.hasSelectedIcon == hasSelectedIcon;

  @override
  int get hashCode => Object.hash(label, enabled, hasSelectedIcon);
}

final class MaterialNavigationBarProps extends UiProps {
  const MaterialNavigationBarProps({
    required this.selectedIndex,
    required this.destinations,
  });

  final int selectedIndex;
  final List<MaterialNavigationDestinationProps> destinations;

  @override
  bool operator ==(Object other) =>
      other is MaterialNavigationBarProps &&
      other.selectedIndex == selectedIndex &&
      _listEquals(other.destinations, destinations);

  @override
  int get hashCode => Object.hash(selectedIndex, Object.hashAll(destinations));
}

final class MaterialRadioOptionProps {
  const MaterialRadioOptionProps({
    required this.id,
    required this.enabled,
    required this.hasLabel,
  });

  final int id;
  final bool enabled;
  final bool hasLabel;

  @override
  bool operator ==(Object other) =>
      other is MaterialRadioOptionProps &&
      other.id == id &&
      other.enabled == enabled &&
      other.hasLabel == hasLabel;

  @override
  int get hashCode => Object.hash(id, enabled, hasLabel);
}

final class MaterialRadioGroupProps extends UiProps {
  const MaterialRadioGroupProps({
    required this.selectedId,
    required this.options,
  });

  final int? selectedId;
  final List<MaterialRadioOptionProps> options;

  @override
  bool operator ==(Object other) =>
      other is MaterialRadioGroupProps &&
      other.selectedId == selectedId &&
      _listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(selectedId, Object.hashAll(options));
}

final class MaterialSegmentProps {
  const MaterialSegmentProps({
    required this.id,
    required this.enabled,
    required this.tooltip,
    required this.hasIcon,
    required this.hasLabel,
  });

  final int id;
  final bool enabled;
  final String? tooltip;
  final bool hasIcon;
  final bool hasLabel;

  @override
  bool operator ==(Object other) =>
      other is MaterialSegmentProps &&
      other.id == id &&
      other.enabled == enabled &&
      other.tooltip == tooltip &&
      other.hasIcon == hasIcon &&
      other.hasLabel == hasLabel;

  @override
  int get hashCode => Object.hash(id, enabled, tooltip, hasIcon, hasLabel);
}

final class MaterialSegmentedButtonProps extends UiProps {
  const MaterialSegmentedButtonProps({
    required this.selectedIds,
    required this.enabled,
    required this.direction,
    required this.multiSelectionEnabled,
    required this.emptySelectionAllowed,
    required this.expandedInsets,
    required this.showSelectedIcon,
    required this.hasSelectedIcon,
    required this.segments,
  });

  final List<int> selectedIds;
  final bool enabled;
  final ScrollAxis direction;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  final EdgeInsetsValue? expandedInsets;
  final bool showSelectedIcon;
  final bool hasSelectedIcon;
  final List<MaterialSegmentProps> segments;

  @override
  bool operator ==(Object other) =>
      other is MaterialSegmentedButtonProps &&
      _listEquals(other.selectedIds, selectedIds) &&
      other.enabled == enabled &&
      other.direction == direction &&
      other.multiSelectionEnabled == multiSelectionEnabled &&
      other.emptySelectionAllowed == emptySelectionAllowed &&
      other.expandedInsets == expandedInsets &&
      other.showSelectedIcon == showSelectedIcon &&
      other.hasSelectedIcon == hasSelectedIcon &&
      _listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(selectedIds),
    enabled,
    direction,
    multiSelectionEnabled,
    emptySelectionAllowed,
    expandedInsets,
    showSelectedIcon,
    hasSelectedIcon,
    Object.hashAll(segments),
  );
}

final class MaterialSliderProps extends UiProps {
  const MaterialSliderProps({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.enabled,
    required this.hasOnChange,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final bool enabled;
  final bool hasOnChange;

  @override
  bool operator ==(Object other) =>
      other is MaterialSliderProps &&
      other.value == value &&
      other.min == min &&
      other.max == max &&
      other.divisions == divisions &&
      other.label == label &&
      other.enabled == enabled &&
      other.hasOnChange == hasOnChange;

  @override
  int get hashCode =>
      Object.hash(value, min, max, divisions, label, enabled, hasOnChange);
}

final class MaterialRangeSliderProps extends UiProps {
  const MaterialRangeSliderProps({
    required this.start,
    required this.end,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelStart,
    required this.labelEnd,
    required this.enabled,
    required this.hasOnChange,
  });

  final double start;
  final double end;
  final double min;
  final double max;
  final int? divisions;
  final String? labelStart;
  final String? labelEnd;
  final bool enabled;
  final bool hasOnChange;

  @override
  bool operator ==(Object other) =>
      other is MaterialRangeSliderProps &&
      other.start == start &&
      other.end == end &&
      other.min == min &&
      other.max == max &&
      other.divisions == divisions &&
      other.labelStart == labelStart &&
      other.labelEnd == labelEnd &&
      other.enabled == enabled &&
      other.hasOnChange == hasOnChange;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    min,
    max,
    divisions,
    labelStart,
    labelEnd,
    enabled,
    hasOnChange,
  );
}

final class MaterialChipProps extends UiProps {
  const MaterialChipProps({
    required this.variant,
    this.presentation = MaterialChipPresentation.flat,
    required this.enabled,
    required this.selected,
    required this.hasAvatar,
    required this.hasDeleteIcon,
    required this.hasOnPress,
    required this.hasOnSelected,
    required this.hasOnDelete,
  });

  final MaterialChipVariant variant;
  final MaterialChipPresentation presentation;
  final bool enabled;
  final bool selected;
  final bool hasAvatar;
  final bool hasDeleteIcon;
  final bool hasOnPress;
  final bool hasOnSelected;
  final bool hasOnDelete;

  @override
  bool operator ==(Object other) =>
      other is MaterialChipProps &&
      other.variant == variant &&
      other.presentation == presentation &&
      other.enabled == enabled &&
      other.selected == selected &&
      other.hasAvatar == hasAvatar &&
      other.hasDeleteIcon == hasDeleteIcon &&
      other.hasOnPress == hasOnPress &&
      other.hasOnSelected == hasOnSelected &&
      other.hasOnDelete == hasOnDelete;

  @override
  int get hashCode => Object.hash(
    variant,
    presentation,
    enabled,
    selected,
    hasAvatar,
    hasDeleteIcon,
    hasOnPress,
    hasOnSelected,
    hasOnDelete,
  );
}

final class MaterialAlertDialogProps extends UiProps {
  const MaterialAlertDialogProps({
    required this.hasIcon,
    required this.hasTitle,
    required this.hasContent,
    required this.actionCount,
  });

  final bool hasIcon;
  final bool hasTitle;
  final bool hasContent;
  final int actionCount;

  @override
  bool operator ==(Object other) =>
      other is MaterialAlertDialogProps &&
      other.hasIcon == hasIcon &&
      other.hasTitle == hasTitle &&
      other.hasContent == hasContent &&
      other.actionCount == actionCount;

  @override
  int get hashCode => Object.hash(hasIcon, hasTitle, hasContent, actionCount);
}

final class MaterialSearchBarProps extends UiProps {
  const MaterialSearchBarProps({
    required this.sessionId,
    required this.documentRevision,
    required this.value,
    required this.enabled,
    required this.readOnly,
    required this.keyboardType,
    required this.inputAction,
    required this.acceptedLocalRevision,
    required this.updateMode,
    required this.autofocus,
    required this.maxUtf8Bytes,
    required this.hasLeading,
    required this.trailingCount,
    required this.hintText,
    required this.hasOnTap,
  });
  final int sessionId;
  final int documentRevision;
  final TextEditingStateValue value;
  final bool enabled;
  final bool readOnly;
  final TextKeyboardType keyboardType;
  final TextInputActionKind inputAction;
  final int acceptedLocalRevision;
  final TextUpdateMode updateMode;
  final bool autofocus;
  final int? maxUtf8Bytes;
  final bool hasLeading;
  final int trailingCount;
  final String? hintText;
  final bool hasOnTap;

  @override
  bool operator ==(Object other) =>
      other is MaterialSearchBarProps &&
      other.sessionId == sessionId &&
      other.documentRevision == documentRevision &&
      other.value == value &&
      other.enabled == enabled &&
      other.readOnly == readOnly &&
      other.keyboardType == keyboardType &&
      other.inputAction == inputAction &&
      other.acceptedLocalRevision == acceptedLocalRevision &&
      other.updateMode == updateMode &&
      other.autofocus == autofocus &&
      other.maxUtf8Bytes == maxUtf8Bytes &&
      other.hasLeading == hasLeading &&
      other.trailingCount == trailingCount &&
      other.hintText == hintText &&
      other.hasOnTap == hasOnTap;

  @override
  int get hashCode => Object.hash(
    sessionId,
    documentRevision,
    value,
    enabled,
    readOnly,
    keyboardType,
    inputAction,
    acceptedLocalRevision,
    updateMode,
    autofocus,
    maxUtf8Bytes,
    hasLeading,
    trailingCount,
    hintText,
    hasOnTap,
  );
}

final class MaterialTooltipProps extends UiProps {
  const MaterialTooltipProps({
    required this.message,
    required this.enabled,
    required this.excludeFromSemantics,
    required this.preferBelow,
    required this.triggerMode,
    required this.waitDurationMs,
    required this.showDurationMs,
    required this.exitDurationMs,
    required this.enableTapToDismiss,
    required this.enableFeedback,
    required this.hasOnTriggered,
  });
  final String message;
  final bool enabled;
  final bool excludeFromSemantics;
  final bool preferBelow;
  final MaterialTooltipTriggerMode triggerMode;
  final int waitDurationMs;
  final int showDurationMs;
  final int exitDurationMs;
  final bool enableTapToDismiss;
  final bool enableFeedback;
  final bool hasOnTriggered;

  @override
  bool operator ==(Object other) =>
      other is MaterialTooltipProps &&
      other.message == message &&
      other.enabled == enabled &&
      other.excludeFromSemantics == excludeFromSemantics &&
      other.preferBelow == preferBelow &&
      other.triggerMode == triggerMode &&
      other.waitDurationMs == waitDurationMs &&
      other.showDurationMs == showDurationMs &&
      other.exitDurationMs == exitDurationMs &&
      other.enableTapToDismiss == enableTapToDismiss &&
      other.enableFeedback == enableFeedback &&
      other.hasOnTriggered == hasOnTriggered;

  @override
  int get hashCode => Object.hash(
    message,
    enabled,
    excludeFromSemantics,
    preferBelow,
    triggerMode,
    waitDurationMs,
    showDurationMs,
    exitDurationMs,
    enableTapToDismiss,
    enableFeedback,
    hasOnTriggered,
  );
}

final class MaterialDataTableColumnProps {
  const MaterialDataTableColumnProps({
    required this.id,
    required this.tooltip,
    required this.numeric,
    required this.sortable,
  });
  final int id;
  final String? tooltip;
  final bool numeric;
  final bool sortable;

  @override
  bool operator ==(Object other) =>
      other is MaterialDataTableColumnProps &&
      other.id == id &&
      other.tooltip == tooltip &&
      other.numeric == numeric &&
      other.sortable == sortable;

  @override
  int get hashCode => Object.hash(id, tooltip, numeric, sortable);
}

final class MaterialDataTableCellProps {
  const MaterialDataTableCellProps({
    required this.placeholder,
    required this.showEditIcon,
    required this.activatable,
  });
  final bool placeholder;
  final bool showEditIcon;
  final bool activatable;

  @override
  bool operator ==(Object other) =>
      other is MaterialDataTableCellProps &&
      other.placeholder == placeholder &&
      other.showEditIcon == showEditIcon &&
      other.activatable == activatable;

  @override
  int get hashCode => Object.hash(placeholder, showEditIcon, activatable);
}

final class MaterialDataTableRowProps {
  const MaterialDataTableRowProps({
    required this.id,
    required this.selected,
    required this.selectionEnabled,
    required this.cells,
  });
  final int id;
  final bool selected;
  final bool selectionEnabled;
  final List<MaterialDataTableCellProps> cells;

  @override
  bool operator ==(Object other) =>
      other is MaterialDataTableRowProps &&
      other.id == id &&
      other.selected == selected &&
      other.selectionEnabled == selectionEnabled &&
      _listEquals(other.cells, cells);

  @override
  int get hashCode =>
      Object.hash(id, selected, selectionEnabled, Object.hashAll(cells));
}

final class MaterialDataTableProps extends UiProps {
  const MaterialDataTableProps({
    required this.columns,
    required this.rows,
    required this.sortColumnId,
    required this.sortAscending,
    required this.selectedRowIds,
    this.hasOnSort = true,
    this.hasOnRowSelected = true,
    this.hasOnSelectAll = false,
    this.hasOnCellActivate = true,
  });
  final List<MaterialDataTableColumnProps> columns;
  final List<MaterialDataTableRowProps> rows;
  final int? sortColumnId;
  final bool sortAscending;
  final List<int> selectedRowIds;
  final bool hasOnSort;
  final bool hasOnRowSelected;
  final bool hasOnSelectAll;
  final bool hasOnCellActivate;

  @override
  bool operator ==(Object other) =>
      other is MaterialDataTableProps &&
      _listEquals(other.columns, columns) &&
      _listEquals(other.rows, rows) &&
      other.sortColumnId == sortColumnId &&
      other.sortAscending == sortAscending &&
      _listEquals(other.selectedRowIds, selectedRowIds) &&
      other.hasOnSort == hasOnSort &&
      other.hasOnRowSelected == hasOnRowSelected &&
      other.hasOnSelectAll == hasOnSelectAll &&
      other.hasOnCellActivate == hasOnCellActivate;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(columns),
    Object.hashAll(rows),
    sortColumnId,
    sortAscending,
    Object.hashAll(selectedRowIds),
    hasOnSort,
    hasOnRowSelected,
    hasOnSelectAll,
    hasOnCellActivate,
  );
}

final class MaterialStepProps {
  const MaterialStepProps({
    required this.id,
    required this.active,
    required this.state,
    required this.hasSubtitle,
    required this.hasLabel,
  });
  final int id;
  final bool active;
  final MaterialStepState state;
  final bool hasSubtitle;
  final bool hasLabel;

  @override
  bool operator ==(Object other) =>
      other is MaterialStepProps &&
      other.id == id &&
      other.active == active &&
      other.state == state &&
      other.hasSubtitle == hasSubtitle &&
      other.hasLabel == hasLabel;

  @override
  int get hashCode => Object.hash(id, active, state, hasSubtitle, hasLabel);
}

final class MaterialStepperProps extends UiProps {
  const MaterialStepperProps({
    required this.orientation,
    required this.currentStepId,
    required this.steps,
  });
  final MaterialStepperOrientation orientation;
  final int currentStepId;
  final List<MaterialStepProps> steps;

  @override
  bool operator ==(Object other) =>
      other is MaterialStepperProps &&
      other.orientation == orientation &&
      other.currentStepId == currentStepId &&
      _listEquals(other.steps, steps);

  @override
  int get hashCode =>
      Object.hash(orientation, currentStepId, Object.hashAll(steps));
}

final class MaterialExpansionPanelProps {
  const MaterialExpansionPanelProps({
    required this.id,
    required this.enabled,
    required this.canTapOnHeader,
  });
  final int id;
  final bool enabled;
  final bool canTapOnHeader;

  @override
  bool operator ==(Object other) =>
      other is MaterialExpansionPanelProps &&
      other.id == id &&
      other.enabled == enabled &&
      other.canTapOnHeader == canTapOnHeader;

  @override
  int get hashCode => Object.hash(id, enabled, canTapOnHeader);
}

final class MaterialExpansionPanelListProps extends UiProps {
  const MaterialExpansionPanelListProps({
    required this.policy,
    required this.expandedIds,
    required this.panels,
  });
  final MaterialExpansionPanelPolicy policy;
  final List<int> expandedIds;
  final List<MaterialExpansionPanelProps> panels;

  @override
  bool operator ==(Object other) =>
      other is MaterialExpansionPanelListProps &&
      other.policy == policy &&
      _listEquals(other.expandedIds, expandedIds) &&
      _listEquals(other.panels, panels);

  @override
  int get hashCode =>
      Object.hash(policy, Object.hashAll(expandedIds), Object.hashAll(panels));
}

final class MaterialSimpleDialogOptionProps {
  const MaterialSimpleDialogOptionProps({
    required this.id,
    required this.enabled,
  });
  final int id;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is MaterialSimpleDialogOptionProps &&
      other.id == id &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, enabled);
}

final class MaterialSimpleDialogProps extends UiProps {
  const MaterialSimpleDialogProps({
    required this.hasTitle,
    required this.options,
  });
  final bool hasTitle;
  final List<MaterialSimpleDialogOptionProps> options;

  @override
  bool operator ==(Object other) =>
      other is MaterialSimpleDialogProps &&
      other.hasTitle == hasTitle &&
      _listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(hasTitle, Object.hashAll(options));
}

final class MaterialFullscreenDialogProps extends UiProps {
  const MaterialFullscreenDialogProps();

  @override
  bool operator ==(Object other) => other is MaterialFullscreenDialogProps;

  @override
  int get hashCode => runtimeType.hashCode;
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
  const MaterialDividerProps({
    this.orientation = MaterialDividerOrientation.horizontal,
    required this.thickness,
    this.spacing = 16,
    this.indent = 0,
    this.endIndent = 0,
  });
  final MaterialDividerOrientation orientation;
  final double thickness;
  final double spacing;
  final double indent;
  final double endIndent;

  @override
  bool operator ==(Object other) =>
      other is MaterialDividerProps &&
      other.orientation == orientation &&
      other.thickness == thickness &&
      other.spacing == spacing &&
      other.indent == indent &&
      other.endIndent == endIndent;

  @override
  int get hashCode =>
      Object.hash(orientation, thickness, spacing, indent, endIndent);
}

final class MaterialCardProps extends UiProps {
  const MaterialCardProps({
    this.variant = MaterialCardVariant.elevated,
    required this.elevation,
  });
  final MaterialCardVariant variant;
  final double elevation;

  @override
  bool operator ==(Object other) =>
      other is MaterialCardProps &&
      other.variant == variant &&
      other.elevation == elevation;

  @override
  int get hashCode => Object.hash(variant, elevation);
}

final class MaterialCircularProgressProps extends UiProps {
  const MaterialCircularProgressProps({this.value});

  final double? value;
}

final class MaterialLinearProgressProps extends UiProps {
  const MaterialLinearProgressProps({this.value});

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

final class SetApplicationTheme extends FrameOperation {
  const SetApplicationTheme({required this.title, required this.theme});
  final String? title;
  final ApplicationThemeValue theme;
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

final class ShowSnackBarRequest extends HostRequest {
  const ShowSnackBarRequest({
    required this.message,
    required this.actionLabel,
    required this.durationMs,
  });

  final String message;
  final String? actionLabel;
  final int durationMs;

  @override
  bool operator ==(Object other) =>
      other is ShowSnackBarRequest &&
      other.message == message &&
      other.actionLabel == actionLabel &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(message, actionLabel, durationMs);
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
