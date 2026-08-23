// Generated from protocol/schema.sexp. Do not edit.

abstract final class ProtocolVersion {
  static const int protocolMajor = 1;
  static const int protocolMinor = 21;
}

abstract final class ProtocolLimits {
  static const int headerBytes = 48;
  static const int maxFrameBytes = 16777216;
  static const int maxStringBytes = 1048576;
  static const int maxApplicationPayloadBytes = 1048576;
  static const int maxOperations = 1000000;
  static const int maxNodes = 1000000;
}

abstract final class FrameKindId {
  static const int handshake = 1;
  static const int fullSnapshot = 2;
  static const int incrementalFrame = 3;
  static const int eventBatch = 4;
  static const int runtimeError = 5;

  static String? debugName(int id) => switch (id) {
    1 => 'handshake',
    2 => 'full_snapshot',
    3 => 'incremental_frame',
    4 => 'event_batch',
    5 => 'runtime_error',
    _ => null,
  };
}

abstract final class OperationId {
  static const int beginFrame = 1;
  static const int createNode = 2;
  static const int updateProps = 3;
  static const int updateEventBindings = 4;
  static const int setChildren = 5;
  static const int setRoot = 6;
  static const int dropNode = 7;
  static const int hostRequest = 8;
  static const int runtimeNotification = 9;
  static const int endFrame = 10;
  static const int applicationRequest = 11;
  static const int setApplicationTheme = 12;

  static String? debugName(int id) => switch (id) {
    1 => 'begin_frame',
    2 => 'create_node',
    3 => 'update_props',
    4 => 'update_event_bindings',
    5 => 'set_children',
    6 => 'set_root',
    7 => 'drop_node',
    8 => 'host_request',
    9 => 'runtime_notification',
    10 => 'end_frame',
    11 => 'application_request',
    12 => 'set_application_theme',
    _ => null,
  };
}

abstract final class NodeKindId {
  static const int empty = 1;
  static const int text = 2;
  static const int richText = 3;
  static const int icon = 4;
  static const int image = 5;
  static const int row = 16;
  static const int column = 17;
  static const int flex = 18;
  static const int stack = 19;
  static const int positioned = 20;
  static const int padding = 21;
  static const int align = 22;
  static const int center = 23;
  static const int sizedBox = 24;
  static const int constrainedBox = 25;
  static const int decoratedBox = 26;
  static const int clip = 27;
  static const int opacity = 28;
  static const int transform = 29;
  static const int scrollView = 30;
  static const int sliverBox = 32;
  static const int sliverList = 33;
  static const int sliverFill = 34;
  static const int sliverFixedExtent = 35;
  static const int sliverVariedExtent = 36;
  static const int sliverPadding = 37;
  static const int sliverAppBar = 38;
  static const int preferredSize = 39;
  static const int gesture = 48;
  static const int button = 49;
  static const int textInput = 50;
  static const int focusScope = 51;
  static const int mouseRegion = 52;
  static const int keyboardListener = 53;
  static const int pressable = 54;
  static const int semantics = 64;
  static const int overlay = 65;
  static const int navigator = 66;
  static const int page = 67;
  static const int safeArea = 68;
  static const int theme = 69;
  static const int environmentBoundary = 70;
  static const int animatedOpacity = 71;
  static const int materialScaffold = 96;
  static const int materialAppBar = 97;
  static const int materialElevatedButton = 98;
  static const int materialTextButton = 99;
  static const int materialIconButton = 100;
  static const int materialCheckbox = 101;
  static const int materialSwitch = 102;
  static const int materialTextField = 103;
  static const int materialListTile = 104;
  static const int materialDivider = 105;
  static const int materialCard = 106;
  static const int reservedNodeKind107 = 107;
  static const int materialCircularProgressIndicator = 108;
  static const int materialFilledButton = 109;
  static const int materialFilledTonalButton = 110;
  static const int materialOutlinedButton = 111;
  static const int cupertinoButton = 112;
  static const int cupertinoSwitch = 113;
  static const int materialFloatingActionButton = 114;
  static const int materialNavigationBar = 115;
  static const int materialRadioGroup = 116;
  static const int materialSlider = 117;
  static const int materialRangeSlider = 118;
  static const int materialActionChip = 119;
  static const int materialFilterChip = 120;
  static const int materialChoiceChip = 121;
  static const int materialInputChip = 122;
  static const int materialAlertDialog = 123;
  static const int nativeWidget = 128;

  static String? debugName(int id) => switch (id) {
    1 => 'empty',
    2 => 'text',
    3 => 'rich_text',
    4 => 'icon',
    5 => 'image',
    16 => 'row',
    17 => 'column',
    18 => 'flex',
    19 => 'stack',
    20 => 'positioned',
    21 => 'padding',
    22 => 'align',
    23 => 'center',
    24 => 'sized_box',
    25 => 'constrained_box',
    26 => 'decorated_box',
    27 => 'clip',
    28 => 'opacity',
    29 => 'transform',
    30 => 'scroll_view',
    32 => 'sliver_box',
    33 => 'sliver_list',
    34 => 'sliver_fill',
    35 => 'sliver_fixed_extent',
    36 => 'sliver_varied_extent',
    37 => 'sliver_padding',
    38 => 'sliver_app_bar',
    39 => 'preferred_size',
    48 => 'gesture',
    49 => 'button',
    50 => 'text_input',
    51 => 'focus_scope',
    52 => 'mouse_region',
    53 => 'keyboard_listener',
    54 => 'pressable',
    64 => 'semantics',
    65 => 'overlay',
    66 => 'navigator',
    67 => 'page',
    68 => 'safe_area',
    69 => 'theme',
    70 => 'environment_boundary',
    71 => 'animated_opacity',
    96 => 'material_scaffold',
    97 => 'material_app_bar',
    98 => 'material_elevated_button',
    99 => 'material_text_button',
    100 => 'material_icon_button',
    101 => 'material_checkbox',
    102 => 'material_switch',
    103 => 'material_text_field',
    104 => 'material_list_tile',
    105 => 'material_divider',
    106 => 'material_card',
    107 => 'reserved_node_kind_107',
    108 => 'material_circular_progress_indicator',
    109 => 'material_filled_button',
    110 => 'material_filled_tonal_button',
    111 => 'material_outlined_button',
    112 => 'cupertino_button',
    113 => 'cupertino_switch',
    114 => 'material_floating_action_button',
    115 => 'material_navigation_bar',
    116 => 'material_radio_group',
    117 => 'material_slider',
    118 => 'material_range_slider',
    119 => 'material_action_chip',
    120 => 'material_filter_chip',
    121 => 'material_choice_chip',
    122 => 'material_input_chip',
    123 => 'material_alert_dialog',
    128 => 'native_widget',
    _ => null,
  };
}

abstract final class EventTagId {
  static const int press = 1;
  static const int longPress = 2;
  static const int tap = 3;
  static const int doubleTap = 4;
  static const int pointerEnter = 5;
  static const int pointerLeave = 6;
  static const int pointerDown = 7;
  static const int pointerUp = 8;
  static const int key = 9;
  static const int focusChanged = 10;
  static const int textEdit = 11;
  static const int textSubmit = 12;
  static const int scrollNotification = 13;
  static const int visibleRangeChanged = 14;
  static const int animationCompleted = 15;
  static const int routePop = 16;
  static const int layoutObserved = 17;
  static const int valueChanged = 18;
  static const int hostResponse = 19;
  static const int environmentChanged = 20;
  static const int nativeEvent = 21;
  static const int semanticsAction = 22;
  static const int resyncRequested = 23;
  static const int textLimitReached = 24;
  static const int applicationResponse = 25;
  static const int applicationRequestError = 26;
  static const int applicationEvent = 27;
  static const int navigationDestinationSelected = 28;
  static const int radioSelected = 29;
  static const int sliderChanged = 30;
  static const int sliderChangeEnd = 31;
  static const int rangeSliderChanged = 32;
  static const int rangeSliderChangeEnd = 33;
  static const int delete = 34;

  static String? debugName(int id) => switch (id) {
    1 => 'press',
    2 => 'long_press',
    3 => 'tap',
    4 => 'double_tap',
    5 => 'pointer_enter',
    6 => 'pointer_leave',
    7 => 'pointer_down',
    8 => 'pointer_up',
    9 => 'key',
    10 => 'focus_changed',
    11 => 'text_edit',
    12 => 'text_submit',
    13 => 'scroll_notification',
    14 => 'visible_range_changed',
    15 => 'animation_completed',
    16 => 'route_pop',
    17 => 'layout_observed',
    18 => 'value_changed',
    19 => 'host_response',
    20 => 'environment_changed',
    21 => 'native_event',
    22 => 'semantics_action',
    23 => 'resync_requested',
    24 => 'text_limit_reached',
    25 => 'application_response',
    26 => 'application_request_error',
    27 => 'application_event',
    28 => 'navigation_destination_selected',
    29 => 'radio_selected',
    30 => 'slider_changed',
    31 => 'slider_change_end',
    32 => 'range_slider_changed',
    33 => 'range_slider_change_end',
    34 => 'delete',
    _ => null,
  };
}

abstract final class HostRequestId {
  static const int clipboardRead = 1;
  static const int clipboardWrite = 2;
  static const int openUrl = 3;
  static const int pickFile = 4;
  static const int saveFile = 5;
  static const int requestFocus = 6;
  static const int clearFocus = 7;
  static const int scrollTo = 8;
  static const int setWindowTitle = 9;
  static const int setWindowSize = 10;
  static const int showNativeMenu = 11;
  static const int hapticFeedback = 12;
  static const int platformInformation = 13;
  static const int measureLayout = 14;
  static const int showSnackBar = 15;

  static String? debugName(int id) => switch (id) {
    1 => 'clipboard_read',
    2 => 'clipboard_write',
    3 => 'open_url',
    4 => 'pick_file',
    5 => 'save_file',
    6 => 'request_focus',
    7 => 'clear_focus',
    8 => 'scroll_to',
    9 => 'set_window_title',
    10 => 'set_window_size',
    11 => 'show_native_menu',
    12 => 'haptic_feedback',
    13 => 'platform_information',
    14 => 'measure_layout',
    15 => 'show_snack_bar',
    _ => null,
  };
}

abstract final class RuntimeErrorId {
  static const int protocolError = 1;
  static const int revisionMismatch = 2;
  static const int duplicateKey = 3;
  static const int unsupportedNodeKind = 4;
  static const int invalidProp = 5;
  static const int handlerMissing = 6;
  static const int staleEvent = 7;
  static const int hostEffectFailure = 8;
  static const int ocamlException = 9;
  static const int dartRendererException = 10;
  static const int lifecycleException = 11;
  static const int nativeLibraryLoadingError = 12;

  static String? debugName(int id) => switch (id) {
    1 => 'protocol_error',
    2 => 'revision_mismatch',
    3 => 'duplicate_key',
    4 => 'unsupported_node_kind',
    5 => 'invalid_prop',
    6 => 'handler_missing',
    7 => 'stale_event',
    8 => 'host_effect_failure',
    9 => 'ocaml_exception',
    10 => 'dart_renderer_exception',
    11 => 'lifecycle_exception',
    12 => 'native_library_loading_error',
    _ => null,
  };
}

abstract final class CommonPropId {
  static const int testId = 1;
  static const int semantics = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'test_id',
    2 => 'semantics',
    _ => null,
  };
}

abstract final class TextPropId {
  static const int value = 1;
  static const int textStyle = 2;
  static const int textAlign = 3;
  static const int maxLines = 4;
  static const int overflow = 5;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    2 => 'text_style',
    3 => 'text_align',
    4 => 'max_lines',
    5 => 'overflow',
    _ => null,
  };
}

abstract final class RichTextPropId {
  static const int spans = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'spans',
    _ => null,
  };
}

abstract final class IconPropId {
  static const int codePoint = 1;
  static const int fontFamily = 2;
  static const int size = 3;
  static const int color = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'code_point',
    2 => 'font_family',
    3 => 'size',
    4 => 'color',
    _ => null,
  };
}

abstract final class ImagePropId {
  static const int uri = 1;
  static const int fit = 2;
  static const int width = 3;
  static const int height = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'uri',
    2 => 'fit',
    3 => 'width',
    4 => 'height',
    _ => null,
  };
}

abstract final class RowPropId {
  static const int mainAxisAlignment = 1;
  static const int mainAxisSize = 2;
  static const int crossAxisAlignment = 3;
  static const int textDirection = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'main_axis_alignment',
    2 => 'main_axis_size',
    3 => 'cross_axis_alignment',
    4 => 'text_direction',
    _ => null,
  };
}

abstract final class ColumnPropId {
  static const int mainAxisAlignment = 1;
  static const int mainAxisSize = 2;
  static const int crossAxisAlignment = 3;
  static const int textDirection = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'main_axis_alignment',
    2 => 'main_axis_size',
    3 => 'cross_axis_alignment',
    4 => 'text_direction',
    _ => null,
  };
}

abstract final class PaddingPropId {
  static const int insets = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'insets',
    _ => null,
  };
}

abstract final class AlignPropId {
  static const int alignment = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'alignment',
    _ => null,
  };
}

abstract final class CenterPropId {
  static const int widthFactor = 1;
  static const int heightFactor = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'width_factor',
    2 => 'height_factor',
    _ => null,
  };
}

abstract final class SizedBoxPropId {
  static const int width = 1;
  static const int height = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'width',
    2 => 'height',
    _ => null,
  };
}

abstract final class ConstrainedBoxPropId {
  static const int minWidth = 1;
  static const int maxWidth = 2;
  static const int minHeight = 3;
  static const int maxHeight = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'min_width',
    2 => 'max_width',
    3 => 'min_height',
    4 => 'max_height',
    _ => null,
  };
}

abstract final class DecoratedBoxPropId {
  static const int background = 1;
  static const int borderRadius = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'background',
    2 => 'border_radius',
    _ => null,
  };
}

abstract final class ClipPropId {
  static const int behavior = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'behavior',
    _ => null,
  };
}

abstract final class OpacityPropId {
  static const int opacity = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'opacity',
    _ => null,
  };
}

abstract final class AnimatedOpacityPropId {
  static const int opacity = 1;
  static const int animationId = 2;
  static const int durationMs = 3;
  static const int curve = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'opacity',
    2 => 'animation_id',
    3 => 'duration_ms',
    4 => 'curve',
    _ => null,
  };
}

abstract final class TransformPropId {
  static const int matrix4 = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'matrix4',
    _ => null,
  };
}

abstract final class ScrollViewPropId {
  static const int axis = 1;
  static const int reverse = 2;
  static const int primary = 3;
  static const int cacheExtent = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'axis',
    2 => 'reverse',
    3 => 'primary',
    4 => 'cache_extent',
    _ => null,
  };
}

abstract final class SliverFillPropId {
  static String? debugName(int id) => switch (id) {
    _ => null,
  };
}

abstract final class SliverFixedExtentPropId {
  static const int totalCount = 1;
  static const int firstIndex = 2;
  static const int itemExtent = 3;
  static const int overscan = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'total_count',
    2 => 'first_index',
    3 => 'item_extent',
    4 => 'overscan',
    _ => null,
  };
}

abstract final class SliverVariedExtentPropId {
  static const int totalCount = 1;
  static const int firstIndex = 2;
  static const int defaultItemExtent = 3;
  static const int overscan = 4;
  static const int overrideCount = 5;
  static const int overrides = 6;
  static const int transitionEnabled = 7;
  static const int expandDurationMs = 8;
  static const int collapseDurationMs = 9;
  static const int expandCurve = 10;
  static const int collapseCurve = 11;

  static String? debugName(int id) => switch (id) {
    1 => 'total_count',
    2 => 'first_index',
    3 => 'default_item_extent',
    4 => 'overscan',
    5 => 'override_count',
    6 => 'overrides',
    7 => 'transition_enabled',
    8 => 'expand_duration_ms',
    9 => 'collapse_duration_ms',
    10 => 'expand_curve',
    11 => 'collapse_curve',
    _ => null,
  };
}

abstract final class SliverPaddingPropId {
  static const int insets = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'insets',
    _ => null,
  };
}

abstract final class SliverAppBarPropId {
  static const int pinned = 1;
  static const int expandedHeight = 2;
  static const int collapsedHeight = 3;
  static const int floating = 4;
  static const int snap = 5;
  static const int stretch = 6;
  static const int toolbarHeight = 7;
  static const int hasLeading = 8;
  static const int hasFlexibleSpace = 9;
  static const int hasBottom = 10;
  static const int hasActions = 11;
  static const int forceElevated = 12;
  static const int automaticallyImplyLeading = 13;
  static const int centerTitle = 14;
  static const int backgroundColor = 15;
  static const int foregroundColor = 16;
  static const int elevation = 17;

  static String? debugName(int id) => switch (id) {
    1 => 'pinned',
    2 => 'expanded_height',
    3 => 'collapsed_height',
    4 => 'floating',
    5 => 'snap',
    6 => 'stretch',
    7 => 'toolbar_height',
    8 => 'has_leading',
    9 => 'has_flexible_space',
    10 => 'has_bottom',
    11 => 'has_actions',
    12 => 'force_elevated',
    13 => 'automatically_imply_leading',
    14 => 'center_title',
    15 => 'background_color',
    16 => 'foreground_color',
    17 => 'elevation',
    _ => null,
  };
}

abstract final class PreferredSizePropId {
  static const int height = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'height',
    _ => null,
  };
}

abstract final class FocusScopePropId {
  static const int autofocus = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'autofocus',
    _ => null,
  };
}

abstract final class MouseRegionPropId {
  static const int opaque = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'opaque',
    _ => null,
  };
}

abstract final class KeyboardListenerPropId {
  static const int autofocus = 1;
  static const int keyPolicy = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'autofocus',
    2 => 'key_policy',
    _ => null,
  };
}

abstract final class ButtonPropId {
  static const int enabled = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    _ => null,
  };
}

abstract final class SemanticsPropId {
  static const int label = 1;
  static const int hint = 2;
  static const int value = 3;
  static const int role = 4;
  static const int enabled = 5;
  static const int selected = 6;
  static const int checked = 7;
  static const int focusable = 8;
  static const int obscured = 9;
  static const int liveRegion = 10;
  static const int headingLevel = 11;
  static const int sortKey = 12;
  static const int actions = 13;

  static String? debugName(int id) => switch (id) {
    1 => 'label',
    2 => 'hint',
    3 => 'value',
    4 => 'role',
    5 => 'enabled',
    6 => 'selected',
    7 => 'checked',
    8 => 'focusable',
    9 => 'obscured',
    10 => 'live_region',
    11 => 'heading_level',
    12 => 'sort_key',
    13 => 'actions',
    _ => null,
  };
}

abstract final class ThemePropId {
  static const int data = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'data',
    _ => null,
  };
}

abstract final class MaterialScaffoldPropId {
  static const int hasAppBar = 1;
  static const int hasFloatingActionButton = 2;
  static const int floatingActionButtonLocation = 3;
  static const int hasBottomNavigationBar = 4;
  static const int hasBottomSheet = 5;

  static String? debugName(int id) => switch (id) {
    1 => 'has_app_bar',
    2 => 'has_floating_action_button',
    3 => 'floating_action_button_location',
    4 => 'has_bottom_navigation_bar',
    5 => 'has_bottom_sheet',
    _ => null,
  };
}

abstract final class MaterialAppBarPropId {
  static const int centerTitle = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'center_title',
    _ => null,
  };
}

abstract final class MaterialElevatedButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialTextButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialIconButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialFilledButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialFilledTonalButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialOutlinedButtonPropId {
  static const int enabled = 1;
  static const int autofocus = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'autofocus',
    _ => null,
  };
}

abstract final class MaterialFloatingActionButtonPropId {
  static const int variant = 1;
  static const int enabled = 2;
  static const int autofocus = 3;
  static const int hasIcon = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'variant',
    2 => 'enabled',
    3 => 'autofocus',
    4 => 'has_icon',
    _ => null,
  };
}

abstract final class MaterialNavigationBarPropId {
  static const int selectedIndex = 1;
  static const int destinations = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'selected_index',
    2 => 'destinations',
    _ => null,
  };
}

abstract final class MaterialRadioGroupPropId {
  static const int selectedId = 1;
  static const int options = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'selected_id',
    2 => 'options',
    _ => null,
  };
}

abstract final class MaterialSliderPropId {
  static const int value = 1;
  static const int min = 2;
  static const int max = 3;
  static const int divisions = 4;
  static const int label = 5;
  static const int enabled = 6;
  static const int hasOnChange = 7;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    2 => 'min',
    3 => 'max',
    4 => 'divisions',
    5 => 'label',
    6 => 'enabled',
    7 => 'has_on_change',
    _ => null,
  };
}

abstract final class MaterialRangeSliderPropId {
  static const int start = 1;
  static const int endValue = 2;
  static const int min = 3;
  static const int max = 4;
  static const int divisions = 5;
  static const int labelStart = 6;
  static const int labelEnd = 7;
  static const int enabled = 8;
  static const int hasOnChange = 9;

  static String? debugName(int id) => switch (id) {
    1 => 'start',
    2 => 'end_value',
    3 => 'min',
    4 => 'max',
    5 => 'divisions',
    6 => 'label_start',
    7 => 'label_end',
    8 => 'enabled',
    9 => 'has_on_change',
    _ => null,
  };
}

abstract final class MaterialActionChipPropId {
  static const int enabled = 1;
  static const int selected = 2;
  static const int hasAvatar = 3;
  static const int hasDeleteIcon = 4;
  static const int hasOnPress = 5;
  static const int hasOnSelected = 6;
  static const int hasOnDelete = 7;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'selected',
    3 => 'has_avatar',
    4 => 'has_delete_icon',
    5 => 'has_on_press',
    6 => 'has_on_selected',
    7 => 'has_on_delete',
    _ => null,
  };
}

abstract final class MaterialFilterChipPropId {
  static const int enabled = 1;
  static const int selected = 2;
  static const int hasAvatar = 3;
  static const int hasDeleteIcon = 4;
  static const int hasOnPress = 5;
  static const int hasOnSelected = 6;
  static const int hasOnDelete = 7;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'selected',
    3 => 'has_avatar',
    4 => 'has_delete_icon',
    5 => 'has_on_press',
    6 => 'has_on_selected',
    7 => 'has_on_delete',
    _ => null,
  };
}

abstract final class MaterialChoiceChipPropId {
  static const int enabled = 1;
  static const int selected = 2;
  static const int hasAvatar = 3;
  static const int hasDeleteIcon = 4;
  static const int hasOnPress = 5;
  static const int hasOnSelected = 6;
  static const int hasOnDelete = 7;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'selected',
    3 => 'has_avatar',
    4 => 'has_delete_icon',
    5 => 'has_on_press',
    6 => 'has_on_selected',
    7 => 'has_on_delete',
    _ => null,
  };
}

abstract final class MaterialInputChipPropId {
  static const int enabled = 1;
  static const int selected = 2;
  static const int hasAvatar = 3;
  static const int hasDeleteIcon = 4;
  static const int hasOnPress = 5;
  static const int hasOnSelected = 6;
  static const int hasOnDelete = 7;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'selected',
    3 => 'has_avatar',
    4 => 'has_delete_icon',
    5 => 'has_on_press',
    6 => 'has_on_selected',
    7 => 'has_on_delete',
    _ => null,
  };
}

abstract final class MaterialAlertDialogPropId {
  static const int hasIcon = 1;
  static const int hasTitle = 2;
  static const int hasContent = 3;
  static const int actionCount = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'has_icon',
    2 => 'has_title',
    3 => 'has_content',
    4 => 'action_count',
    _ => null,
  };
}

abstract final class MaterialCheckboxPropId {
  static const int value = 1;
  static const int enabled = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    2 => 'enabled',
    _ => null,
  };
}

abstract final class MaterialSwitchPropId {
  static const int value = 1;
  static const int enabled = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    2 => 'enabled',
    _ => null,
  };
}

abstract final class MaterialListTilePropId {
  static const int enabled = 1;
  static const int selected = 2;
  static const int hasSubtitle = 3;
  static const int hasLeading = 4;
  static const int hasTrailing = 5;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    2 => 'selected',
    3 => 'has_subtitle',
    4 => 'has_leading',
    5 => 'has_trailing',
    _ => null,
  };
}

abstract final class MaterialDividerPropId {
  static const int thickness = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'thickness',
    _ => null,
  };
}

abstract final class MaterialCardPropId {
  static const int elevation = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'elevation',
    _ => null,
  };
}

abstract final class MaterialCircularProgressIndicatorPropId {
  static const int value = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    _ => null,
  };
}

abstract final class CupertinoButtonPropId {
  static const int enabled = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'enabled',
    _ => null,
  };
}

abstract final class CupertinoSwitchPropId {
  static const int value = 1;
  static const int enabled = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'value',
    2 => 'enabled',
    _ => null,
  };
}

abstract final class TextInputPropId {
  static const int sessionId = 1;
  static const int documentRevision = 2;
  static const int value = 3;
  static const int enabled = 4;
  static const int readOnly = 5;
  static const int obscureText = 6;
  static const int keyboardType = 7;
  static const int inputAction = 8;
  static const int acceptedLocalRevision = 9;
  static const int updateMode = 10;
  static const int autofocus = 11;
  static const int maxUtf8Bytes = 12;

  static String? debugName(int id) => switch (id) {
    1 => 'session_id',
    2 => 'document_revision',
    3 => 'value',
    4 => 'enabled',
    5 => 'read_only',
    6 => 'obscure_text',
    7 => 'keyboard_type',
    8 => 'input_action',
    9 => 'accepted_local_revision',
    10 => 'update_mode',
    11 => 'autofocus',
    12 => 'max_utf8_bytes',
    _ => null,
  };
}

abstract final class OverlayPropId {
  static const int alignment = 1;
  static const int dismissible = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'alignment',
    2 => 'dismissible',
    _ => null,
  };
}

abstract final class NavigatorPropId {
  static const int restorationScopeId = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'restoration_scope_id',
    _ => null,
  };
}

abstract final class PagePropId {
  static const int pageKey = 1;
  static const int transition = 2;
  static const int canPop = 3;
  static const int restorationId = 4;
  static const int presentation = 5;
  static const int modalBarrierDismissible = 6;
  static const int modalBarrierColor = 7;
  static const int modalBarrierLabel = 8;
  static const int modalUseSafeArea = 10;
  static const int modalRequestFocus = 11;
  static const int modalTransitionDurationMs = 12;
  static const int modalReverseTransitionDurationMs = 13;
  static const int modalSizing = 14;
  static const int modalDetents = 15;
  static const int modalInitialDetent = 16;
  static const int modalDismissOnDrag = 17;
  static const int modalHandleSemanticsLabel = 18;
  static const int modalMediumSemanticsValue = 19;
  static const int modalLargeSemanticsValue = 20;
  static const int dialogBarrierDismissible = 21;
  static const int dialogBarrierColor = 22;
  static const int dialogBarrierLabel = 23;
  static const int dialogUseSafeArea = 24;
  static const int dialogRequestFocus = 25;
  static const int dialogTransitionDurationMs = 26;
  static const int dialogReverseTransitionDurationMs = 27;

  static String? debugName(int id) => switch (id) {
    1 => 'page_key',
    2 => 'transition',
    3 => 'can_pop',
    4 => 'restoration_id',
    5 => 'presentation',
    6 => 'modal_barrier_dismissible',
    7 => 'modal_barrier_color',
    8 => 'modal_barrier_label',
    10 => 'modal_use_safe_area',
    11 => 'modal_request_focus',
    12 => 'modal_transition_duration_ms',
    13 => 'modal_reverse_transition_duration_ms',
    14 => 'modal_sizing',
    15 => 'modal_detents',
    16 => 'modal_initial_detent',
    17 => 'modal_dismiss_on_drag',
    18 => 'modal_handle_semantics_label',
    19 => 'modal_medium_semantics_value',
    20 => 'modal_large_semantics_value',
    21 => 'dialog_barrier_dismissible',
    22 => 'dialog_barrier_color',
    23 => 'dialog_barrier_label',
    24 => 'dialog_use_safe_area',
    25 => 'dialog_request_focus',
    26 => 'dialog_transition_duration_ms',
    27 => 'dialog_reverse_transition_duration_ms',
    _ => null,
  };
}

abstract final class SafeAreaPropId {
  static const int left = 1;
  static const int top = 2;
  static const int right = 3;
  static const int bottom = 4;
  static const int minimum = 5;

  static String? debugName(int id) => switch (id) {
    1 => 'left',
    2 => 'top',
    3 => 'right',
    4 => 'bottom',
    5 => 'minimum',
    _ => null,
  };
}

abstract final class PressablePropId {
  static const int overlayColor = 1;
  static const int releaseDelayMs = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'overlay_color',
    2 => 'release_delay_ms',
    _ => null,
  };
}

abstract final class NativeWidgetPropId {
  static const int kindId = 1;
  static const int version = 2;
  static const int capabilities = 3;
  static const int payload = 4;

  static String? debugName(int id) => switch (id) {
    1 => 'kind_id',
    2 => 'version',
    3 => 'capabilities',
    4 => 'payload',
    _ => null,
  };
}
