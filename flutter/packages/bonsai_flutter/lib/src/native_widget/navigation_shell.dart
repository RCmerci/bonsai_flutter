import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'native_widget_registry.dart';
import 'virtual_list.dart';

abstract final class NavigationShellEvent {
  static const int drawerStateChanged = 1;

  static Uint8List encodeDrawerState(bool open) =>
      Uint8List.fromList([open ? 1 : 0]);
}

final class NavigationShellProps {
  const NavigationShellProps({
    required this.selectedIndex,
    required this.destinationCount,
    required this.drawerOpen,
    required this.drawerEnabled,
  });

  final int selectedIndex;
  final int destinationCount;
  final bool drawerOpen;
  final bool drawerEnabled;

  void validateChildCount(int childCount) {
    if (destinationCount <= 0) {
      throw const FormatException(
        'Navigation shell requires at least one destination',
      );
    }
    if (selectedIndex < 0 || selectedIndex >= destinationCount) {
      throw const FormatException(
        'Navigation shell selected index is outside destinations',
      );
    }
    if (childCount != destinationCount + 2) {
      throw FormatException(
        'Navigation shell requires ${destinationCount + 2} children',
      );
    }
  }

  static NavigationShellProps decode(Uint8List payload) {
    if (payload.length != 12) {
      throw const FormatException(
        'Navigation shell props must be exactly 12 bytes',
      );
    }
    final data = ByteData.sublistView(payload);
    final flags = data.getUint8(0);
    if (flags & ~3 != 0 ||
        data.getUint8(1) != 0 ||
        data.getUint8(2) != 0 ||
        data.getUint8(3) != 0) {
      throw const FormatException('Navigation shell flags are invalid');
    }
    final props = NavigationShellProps(
      selectedIndex: data.getUint32(4, Endian.little),
      destinationCount: data.getUint32(8, Endian.little),
      drawerOpen: flags & 1 != 0,
      drawerEnabled: flags & 2 != 0,
    );
    props.validateChildCount(props.destinationCount + 2);
    return props;
  }
}

void registerNavigationShell(NativeWidgetRegistry registry) {
  registry.register<NavigationShellProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.navigationShell,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics,
      decodeProps: NavigationShellProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        return NavigationShellHost(
          props: context.props,
          emit: context.emit,
          bodies: context.children
              .take(context.props.destinationCount)
              .toList(),
          drawer: context.children[context.props.destinationCount],
          bottomNavigation:
              context.children[context.props.destinationCount + 1],
        );
      },
    ),
  );
}

final class NavigationShellHost extends StatefulWidget {
  const NavigationShellHost({
    required this.props,
    required this.emit,
    required this.bodies,
    required this.drawer,
    required this.bottomNavigation,
    super.key,
  });

  final NavigationShellProps props;
  final NativeEventEmitter? emit;
  final List<Widget> bodies;
  final Widget drawer;
  final Widget bottomNavigation;

  @override
  State<NavigationShellHost> createState() => _NavigationShellHostState();
}

final class _NavigationShellHostState extends State<NavigationShellHost>
    with SingleTickerProviderStateMixin {
  static const _bottomNavigationAnimationDuration = Duration(milliseconds: 200);
  static const _bottomNavigationScrollThreshold = 16.0;
  static const _bottomNavigationShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _bottomNavigationController;
  late final Animation<double> _bottomNavigationAnimation;
  double _accumulatedScrollDelta = 0;
  bool _bottomNavigationVisible = true;
  bool _disposed = false;
  bool _drawerOpen = false;
  bool _pointerDown = false;
  bool _syncScheduled = false;
  bool? _pendingDrawerState;
  bool? _lastEmittedDrawerState;

  @override
  void initState() {
    super.initState();
    _bottomNavigationController = AnimationController(
      duration: _bottomNavigationAnimationDuration,
      value: 1,
      vsync: this,
    );
    _bottomNavigationAnimation = CurvedAnimation(
      parent: _bottomNavigationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scheduleDrawerSync();
  }

  @override
  void didUpdateWidget(NavigationShellHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.props.drawerOpen != widget.props.drawerOpen ||
        oldWidget.props.drawerEnabled != widget.props.drawerEnabled) {
      _scheduleDrawerSync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _bottomNavigationController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case ScrollStartNotification():
        _accumulatedScrollDelta = 0;
      case ScrollUpdateNotification(
        dragDetails: final dragDetails,
        scrollDelta: final scrollDelta,
      ):
        if (dragDetails != null && scrollDelta != null) {
          _accumulateScrollDelta(scrollDelta);
        }
      case ScrollEndNotification():
        _accumulatedScrollDelta = 0;
    }
    return false;
  }

  void _accumulateScrollDelta(double delta) {
    if (delta == 0) return;
    if (_accumulatedScrollDelta != 0 &&
        delta.sign != _accumulatedScrollDelta.sign) {
      _accumulatedScrollDelta = delta;
    } else {
      _accumulatedScrollDelta += delta;
    }
    if (_accumulatedScrollDelta.abs() < _bottomNavigationScrollThreshold) {
      return;
    }
    _setBottomNavigationVisible(_accumulatedScrollDelta < 0);
    _accumulatedScrollDelta = 0;
  }

  void _setBottomNavigationVisible(bool visible) {
    if (_bottomNavigationVisible == visible) return;
    _bottomNavigationVisible = visible;
    if (MediaQuery.disableAnimationsOf(context)) {
      _bottomNavigationController.value = visible ? 1 : 0;
    } else if (visible) {
      _bottomNavigationController.forward();
    } else {
      _bottomNavigationController.reverse();
    }
  }

  void _scheduleDrawerSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (_disposed || !mounted) return;
      final scaffold = _scaffoldKey.currentState;
      if (scaffold == null) return;
      final requestedOpen =
          widget.props.drawerEnabled && widget.props.drawerOpen;
      if (requestedOpen && !_drawerOpen) {
        scaffold.openDrawer();
      } else if (!requestedOpen && _drawerOpen) {
        scaffold.closeDrawer();
      }
    });
  }

  void _handleDrawerChanged(bool open) {
    _drawerOpen = open;
    _pendingDrawerState = open;
    if (!_pointerDown) _scheduleSettledEvent();
  }

  void _scheduleSettledEvent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || _pointerDown) return;
      final open = _pendingDrawerState;
      if (open == null || open == _lastEmittedDrawerState) return;
      _lastEmittedDrawerState = open;
      _pendingDrawerState = null;
      widget.emit?.call(
        NavigationShellEvent.drawerStateChanged,
        NavigationShellEvent.encodeDrawerState(open),
      );
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDown = true;
  }

  void _handlePointerEnded(PointerEvent event) {
    _pointerDown = false;
    _scheduleSettledEvent();
  }

  Widget _buildScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final bottomNavigationButtonStyle =
        (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          shape: const WidgetStatePropertyAll(_bottomNavigationShape),
        );
    return Scaffold(
      key: _scaffoldKey,
      drawer: widget.props.drawerEnabled ? Drawer(child: widget.drawer) : null,
      drawerEnableOpenDragGesture: widget.props.drawerEnabled,
      onDrawerChanged: _handleDrawerChanged,
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(
                index: widget.props.selectedIndex,
                children: widget.bodies,
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _bottomNavigationAnimation,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _bottomNavigationAnimation,
              child: Theme(
                data: theme.copyWith(
                  textButtonTheme: TextButtonThemeData(
                    style: bottomNavigationButtonStyle,
                  ),
                ),
                child: widget.bottomNavigation,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _handlePointerDown,
    onPointerUp: _handlePointerEnded,
    onPointerCancel: _handlePointerEnded,
    child: _buildScaffold(context),
  );
}
