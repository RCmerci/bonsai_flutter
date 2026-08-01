import 'dart:async';

import 'package:flutter/material.dart';

import '../protocol/frame.dart';

final class PressableHost extends StatefulWidget {
  const PressableHost({
    required this.props,
    required this.onPress,
    required this.child,
    super.key,
  });

  final PressableProps props;
  final VoidCallback? onPress;
  final Widget child;

  @override
  State<PressableHost> createState() => _PressableHostState();
}

final class _PressableHostState extends State<PressableHost> {
  bool _pressed = false;
  bool _activationPending = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_activationPending || _pressed) return;
    setState(() => _pressed = true);
  }

  void _handleTapCancel() {
    if (_activationPending || !_pressed) return;
    setState(() => _pressed = false);
  }

  void _handleTapUp(TapUpDetails details) => _beginActivation();

  void _handleSemanticTap() {
    if (_activationPending) return;
    if (!_pressed) setState(() => _pressed = true);
    _beginActivation();
  }

  void _beginActivation() {
    if (_activationPending) return;
    _activationPending = true;
    final generation = ++_generation;
    final delay = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: widget.props.releaseDelayMs);
    if (delay == Duration.zero) {
      _emitActivation(generation);
    } else {
      unawaited(_finishActivation(generation, delay));
    }
  }

  Future<void> _finishActivation(int generation, Duration delay) async {
    await Future<void>.delayed(delay);
    _emitActivation(generation);
  }

  void _emitActivation(int generation) {
    if (_disposed || !mounted || generation != _generation) return;
    widget.onPress?.call();
    if (!mounted) return;
    setState(() {
      _pressed = false;
      _activationPending = false;
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    onTap: _handleSemanticTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ClipRect(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_pressed)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color(widget.props.overlayColorArgb),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
