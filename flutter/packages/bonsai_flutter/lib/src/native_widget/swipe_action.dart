import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'native_widget_registry.dart';
import 'virtual_list.dart';

enum SwipeActionDirection { startToEnd, endToStart }

enum SwipeActionDisposition { dismiss, rebound }

abstract final class SwipeActionEvent {
  static const int commit = 1;

  static Uint8List encodeDirection(SwipeActionDirection direction) =>
      Uint8List.fromList([
        switch (direction) {
          SwipeActionDirection.startToEnd => 0,
          SwipeActionDirection.endToStart => 1,
        },
      ]);
}

final class SwipeActionProps {
  const SwipeActionProps({
    required this.startEnabled,
    required this.endEnabled,
    required this.startLabel,
    required this.endLabel,
    required this.startBackground,
    required this.endBackground,
    required this.startDisposition,
    required this.endDisposition,
  });

  final bool startEnabled;
  final bool endEnabled;
  final String startLabel;
  final String endLabel;
  final Color startBackground;
  final Color endBackground;
  final SwipeActionDisposition startDisposition;
  final SwipeActionDisposition endDisposition;

  void validateChildCount(int childCount) {
    if (childCount != 3) {
      throw const FormatException(
        'Swipe action must have exactly three children',
      );
    }
  }

  static SwipeActionProps decode(Uint8List payload) {
    if (payload.length < 20) {
      throw const FormatException(
        'Swipe action props must contain a 20-byte header',
      );
    }
    final data = ByteData.sublistView(payload);
    final flags = data.getUint8(0);
    if (flags & ~0x03 != 0) {
      throw FormatException(
        'Unknown swipe action flags 0x${flags.toRadixString(16)}',
      );
    }
    final startDisposition = _decodeDisposition(data.getUint8(1));
    final endDisposition = _decodeDisposition(data.getUint8(2));
    if (data.getUint8(3) != 0) {
      throw const FormatException('Swipe action reserved byte must be zero');
    }
    final startLength = data.getUint32(12, Endian.little);
    final endLength = data.getUint32(16, Endian.little);
    final exactLength = 20 + startLength + endLength;
    if (payload.length != exactLength) {
      throw FormatException(
        'Swipe action props must be exactly $exactLength bytes',
      );
    }
    final startEnabled = flags & 1 != 0;
    final endEnabled = flags & 2 != 0;
    final startLabel = utf8.decode(
      payload.sublist(20, 20 + startLength),
      allowMalformed: false,
    );
    final endLabel = utf8.decode(
      payload.sublist(20 + startLength),
      allowMalformed: false,
    );
    if (startEnabled && startLabel.isEmpty) {
      throw const FormatException(
        'Enabled start swipe action must have a label',
      );
    }
    if (endEnabled && endLabel.isEmpty) {
      throw const FormatException('Enabled end swipe action must have a label');
    }
    if (!startEnabled && !endEnabled) {
      throw const FormatException(
        'Swipe action must enable at least one action',
      );
    }
    return SwipeActionProps(
      startEnabled: startEnabled,
      endEnabled: endEnabled,
      startLabel: startLabel,
      endLabel: endLabel,
      startBackground: Color(data.getUint32(4, Endian.little)),
      endBackground: Color(data.getUint32(8, Endian.little)),
      startDisposition: startDisposition,
      endDisposition: endDisposition,
    );
  }
}

SwipeActionDisposition _decodeDisposition(int value) => switch (value) {
  0 => SwipeActionDisposition.dismiss,
  1 => SwipeActionDisposition.rebound,
  _ => throw FormatException('Unknown swipe action disposition $value'),
};

void registerSwipeAction(NativeWidgetRegistry registry) {
  registry.register<SwipeActionProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.swipeAction,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits:
          NativeCapability.stateful |
          NativeCapability.resource |
          NativeCapability.semantics,
      decodeProps: SwipeActionProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        return _SwipeActionHost(
          props: context.props,
          emit: context.emit,
          content: context.children[0],
          startIcon: context.children[1],
          endIcon: context.children[2],
        );
      },
    ),
  );
}

final class _SwipeActionHost extends StatefulWidget {
  const _SwipeActionHost({
    required this.props,
    required this.emit,
    required this.content,
    required this.startIcon,
    required this.endIcon,
  });

  final SwipeActionProps props;
  final NativeEventEmitter? emit;
  final Widget content;
  final Widget startIcon;
  final Widget endIcon;

  @override
  State<_SwipeActionHost> createState() => _SwipeActionHostState();
}

final class _SwipeActionHostState extends State<_SwipeActionHost>
    with SingleTickerProviderStateMixin {
  static const _cancelDuration = Duration(milliseconds: 200);
  static const _dismissDuration = Duration(milliseconds: 220);
  static const _reboundDuration = Duration(milliseconds: 190);
  static const _flingVelocity = 800.0;
  static const _pillInset = 4.0;
  static const _pillMinWidth = 8.0;
  static const _pillMaxWidth = 144.0;

  late final AnimationController _controller;
  Animation<double>? _offsetAnimation;
  double _logicalOffset = 0;
  double _rowWidth = 0;
  bool _thresholdHapticFired = false;
  bool _commitInProgress = false;
  bool _disposed = false;
  int _animationGeneration = 0;
  double? _dragDownX;
  VoidCallback? _animationCompletion;
  int? _completionGeneration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _offsetAnimation;
        if (animation != null && mounted) {
          setState(() => _logicalOffset = animation.value);
        }
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed ||
            _completionGeneration != _animationGeneration) {
          return;
        }
        final completion = _animationCompletion;
        _animationCompletion = null;
        _completionGeneration = null;
        completion?.call();
      });
  }

  @override
  void dispose() {
    _disposed = true;
    _animationGeneration += 1;
    _controller.dispose();
    super.dispose();
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;
  double get _physicalOffset => _isRtl ? -_logicalOffset : _logicalOffset;

  double get _commitDistance => (_rowWidth * 0.28).clamp(72.0, 112.0);

  SwipeActionDirection? get _activeDirection {
    if (_logicalOffset > 0) return SwipeActionDirection.startToEnd;
    if (_logicalOffset < 0) return SwipeActionDirection.endToStart;
    return null;
  }

  bool _enabled(SwipeActionDirection direction) => switch (direction) {
    SwipeActionDirection.startToEnd => widget.props.startEnabled,
    SwipeActionDirection.endToStart => widget.props.endEnabled,
  };

  SwipeActionDisposition _disposition(SwipeActionDirection direction) =>
      switch (direction) {
        SwipeActionDirection.startToEnd => widget.props.startDisposition,
        SwipeActionDirection.endToStart => widget.props.endDisposition,
      };

  void _onDragDown(DragDownDetails details) {
    _dragDownX = details.globalPosition.dx;
  }

  void _onDragStart(DragStartDetails details) {
    if (_commitInProgress) return;
    _animationGeneration += 1;
    _animationCompletion = null;
    _completionGeneration = null;
    _controller.stop();
    _offsetAnimation = null;
    _thresholdHapticFired = false;
    final dragDownX = _dragDownX;
    if (dragDownX != null) {
      final physicalDelta = details.globalPosition.dx - dragDownX;
      final logicalDelta = _isRtl ? -physicalDelta : physicalDelta;
      final direction = logicalDelta >= 0
          ? SwipeActionDirection.startToEnd
          : SwipeActionDirection.endToStart;
      _setDragOffset(_enabled(direction) ? logicalDelta : 0);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_commitInProgress) return;
    final logicalDelta = _isRtl ? -details.delta.dx : details.delta.dx;
    final candidate = _logicalOffset + logicalDelta;
    final direction = candidate >= 0
        ? SwipeActionDirection.startToEnd
        : SwipeActionDirection.endToStart;
    _setDragOffset(_enabled(direction) ? candidate : 0);
  }

  void _setDragOffset(double offset) {
    setState(() => _logicalOffset = offset);
    if (!_thresholdHapticFired && offset.abs() >= _commitDistance) {
      _thresholdHapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_commitInProgress) return;
    final physicalVelocity = details.primaryVelocity ?? 0;
    final logicalVelocity = _isRtl ? -physicalVelocity : physicalVelocity;
    final direction =
        _activeDirection ??
        (logicalVelocity >= 0
            ? SwipeActionDirection.startToEnd
            : SwipeActionDirection.endToStart);
    final velocityCommits =
        logicalVelocity.abs() >= _flingVelocity &&
        ((logicalVelocity > 0 &&
                direction == SwipeActionDirection.startToEnd) ||
            (logicalVelocity < 0 &&
                direction == SwipeActionDirection.endToStart));
    if (!_enabled(direction) ||
        (_logicalOffset.abs() < _commitDistance && !velocityCommits)) {
      _animateTo(0, _cancelDuration);
      return;
    }
    _commit(direction);
  }

  void _commit(SwipeActionDirection direction) {
    if (_commitInProgress || !_enabled(direction)) return;
    _commitInProgress = true;
    final disposition = _disposition(direction);
    final target = disposition == SwipeActionDisposition.dismiss
        ? (direction == SwipeActionDirection.startToEnd
              ? _rowWidth
              : -_rowWidth)
        : 0.0;
    final duration = disposition == SwipeActionDisposition.dismiss
        ? _dismissDuration
        : _reboundDuration;
    _animateTo(
      target,
      duration,
      onComplete: () {
        widget.emit?.call(
          SwipeActionEvent.commit,
          SwipeActionEvent.encodeDirection(direction),
        );
        if (disposition == SwipeActionDisposition.rebound && mounted) {
          setState(() => _commitInProgress = false);
        }
      },
    );
  }

  void _animateTo(
    double target,
    Duration duration, {
    VoidCallback? onComplete,
  }) {
    final generation = ++_animationGeneration;
    _animationCompletion = null;
    _completionGeneration = null;
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true;
    if (reduceMotion || duration == Duration.zero) {
      setState(() => _logicalOffset = target);
      if (!_disposed && generation == _animationGeneration) onComplete?.call();
      return;
    }
    _controller
      ..stop()
      ..duration = duration
      ..reset();
    _offsetAnimation = Tween<double>(
      begin: _logicalOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _animationCompletion = () {
      if (_disposed || !mounted || generation != _animationGeneration) return;
      setState(() => _logicalOffset = target);
      onComplete?.call();
    };
    _completionGeneration = generation;
    _controller.forward();
  }

  Map<CustomSemanticsAction, VoidCallback> _semanticsActions() => {
    if (widget.props.startEnabled)
      CustomSemanticsAction(label: widget.props.startLabel): () =>
          _commit(SwipeActionDirection.startToEnd),
    if (widget.props.endEnabled)
      CustomSemanticsAction(label: widget.props.endLabel): () =>
          _commit(SwipeActionDirection.endToStart),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _rowWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final direction = _activeDirection;
      final physicalOffset = _physicalOffset;
      return Semantics(
        key: const ValueKey<String>('bonsai-swipe-action-host'),
        customSemanticsActions: _semanticsActions(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.start,
          onHorizontalDragDown: _commitInProgress ? null : _onDragDown,
          onHorizontalDragStart: _commitInProgress ? null : _onDragStart,
          onHorizontalDragUpdate: _commitInProgress ? null : _onDragUpdate,
          onHorizontalDragEnd: _commitInProgress ? null : _onDragEnd,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (direction != null) _feedback(direction),
                Transform.translate(
                  offset: Offset(physicalOffset, 0),
                  child: KeyedSubtree(
                    key: const ValueKey<String>('bonsai-swipe-action-content'),
                    child: widget.content,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _feedback(SwipeActionDirection direction) {
    final physicalStart = direction == SwipeActionDirection.startToEnd
        ? !_isRtl
        : _isRtl;
    final width = _logicalOffset.abs().clamp(_pillMinWidth, _pillMaxWidth);
    final background = direction == SwipeActionDirection.startToEnd
        ? widget.props.startBackground
        : widget.props.endBackground;
    final icon = direction == SwipeActionDirection.startToEnd
        ? widget.startIcon
        : widget.endIcon;
    return Positioned(
      key: const ValueKey<String>('bonsai-swipe-action-pill'),
      left: physicalStart ? 0 : null,
      right: physicalStart ? null : 0,
      top: _pillInset,
      bottom: _pillInset,
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: ExcludeSemantics(child: IgnorePointer(child: icon)),
        ),
      ),
    );
  }
}
