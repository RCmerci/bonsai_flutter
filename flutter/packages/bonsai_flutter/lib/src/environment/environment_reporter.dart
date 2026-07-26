import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../protocol/event_batch.dart';
import '../protocol/generated_protocol.dart';
import '../renderer/widget_registry.dart';

final class EnvironmentReporter extends StatefulWidget {
  const EnvironmentReporter({
    required this.onEvent,
    required this.child,
    super.key,
  });

  final RendererEventCallback onEvent;
  final Widget child;

  @override
  State<EnvironmentReporter> createState() => _EnvironmentReporterState();
}

final class _EnvironmentReporterState extends State<EnvironmentReporter>
    with WidgetsBindingObserver {
  EnvironmentSnapshot? _lastSent;
  EnvironmentSnapshot? _scheduled;
  bool _callbackScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _schedule(_snapshot(context));
    return widget.child;
  }

  void _schedule(EnvironmentSnapshot snapshot) {
    _scheduled = snapshot;
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callbackScheduled = false;
      if (!mounted) return;
      final next = _scheduled;
      if (next == null || next == _lastSent) return;
      _lastSent = next;
      widget.onEvent(
        RendererEvent(
          nodeId: 0,
          eventTag: EventTagId.environmentChanged,
          handlerId: 0,
          payload: EnvironmentEventPayload(next),
        ),
      );
    });
  }
}

EnvironmentSnapshot _snapshot(BuildContext context) {
  final mediaQuery =
      MediaQuery.maybeOf(context) ?? MediaQueryData.fromView(View.of(context));
  final locale =
      Localizations.maybeLocaleOf(context) ??
      PlatformDispatcher.instance.locale;
  final size = mediaQuery.size;
  return EnvironmentSnapshot(
    viewportWidth: size.width,
    viewportHeight: size.height,
    devicePixelRatio: mediaQuery.devicePixelRatio,
    textScale: mediaQuery.textScaler.scale(1),
    brightness: mediaQuery.platformBrightness == Brightness.dark
        ? EnvironmentBrightness.dark
        : EnvironmentBrightness.light,
    platform: _platformName(),
    locale: locale.toLanguageTag(),
    safeArea: _insets(mediaQuery.padding),
    keyboardInsets: _insets(mediaQuery.viewInsets),
    accessibleNavigation: mediaQuery.accessibleNavigation,
    boldText: mediaQuery.boldText,
    invertColors: mediaQuery.invertColors,
    disableAnimations: mediaQuery.disableAnimations,
    reducedMotion: mediaQuery.disableAnimations,
    highContrast: mediaQuery.highContrast,
    orientation: size.width > size.height
        ? EnvironmentOrientation.landscape
        : EnvironmentOrientation.portrait,
    pointerKinds: _pointerKinds(),
  );
}

EnvironmentInsets _insets(EdgeInsets value) => EnvironmentInsets(
  left: value.left,
  top: value.top,
  right: value.right,
  bottom: value.bottom,
);

String _platformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

int _pointerKinds() {
  if (kIsWeb) return 0x0f;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => 0x05,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => 0x0a,
    TargetPlatform.fuchsia => 0x01,
  };
}
