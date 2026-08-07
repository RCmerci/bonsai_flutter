// Generated from protocol/schema.sexp. Do not edit.

abstract final class ProtocolVersion {
  static const int protocolMajor = 1;
  static const int protocolMinor = 16;
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
  static const int listView = 31;
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
  static const int materialDialog = 107;
  static const int materialCircularProgressIndicator = 108;
  static const int cupertinoButton = 112;
  static const int cupertinoSwitch = 113;
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
    31 => 'list_view',
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
    107 => 'material_dialog',
    108 => 'material_circular_progress_indicator',
    112 => 'cupertino_button',
    113 => 'cupertino_switch',
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

  static String? debugName(int id) => switch (id) {
    1 => 'axis',
    2 => 'reverse',
    _ => null,
  };
}

abstract final class ListViewPropId {
  static const int axis = 1;
  static const int reverse = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'axis',
    2 => 'reverse',
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
  static const int brightness = 1;
  static const int colorSeed = 2;

  static String? debugName(int id) => switch (id) {
    1 => 'brightness',
    2 => 'color_seed',
    _ => null,
  };
}

abstract final class MaterialScaffoldPropId {
  static const int hasAppBar = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'has_app_bar',
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

  static String? debugName(int id) => switch (id) {
    1 => 'page_key',
    2 => 'transition',
    3 => 'can_pop',
    4 => 'restoration_id',
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

abstract final class MaterialDialogPropId {
  static const int barrierDismissible = 1;

  static String? debugName(int id) => switch (id) {
    1 => 'barrier_dismissible',
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
