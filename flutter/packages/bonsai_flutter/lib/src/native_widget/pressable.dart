import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'native_widget_registry.dart';
import 'virtual_list.dart';

abstract final class PressableEvent {
  static const int activate = 1;
}

final class PressableProps {
  const PressableProps({
    required this.overlayColor,
    required this.releaseDelay,
  });

  final Color overlayColor;
  final Duration releaseDelay;

  void validateChildCount(int childCount) {
    if (childCount != 1) {
      throw const FormatException('Pressable requires exactly one child');
    }
    if (releaseDelay.isNegative ||
        releaseDelay > const Duration(milliseconds: 100)) {
      throw const FormatException(
        'Pressable release delay must be in 0..100ms',
      );
    }
  }

  static PressableProps decode(Uint8List payload) {
    if (payload.length != 8) {
      throw const FormatException('Pressable props must be exactly 8 bytes');
    }
    final data = ByteData.sublistView(payload);
    if (data.getUint8(6) != 0 || data.getUint8(7) != 0) {
      throw const FormatException('Pressable reserved bytes must be zero');
    }
    final props = PressableProps(
      overlayColor: Color(data.getUint32(0, Endian.little)),
      releaseDelay: Duration(milliseconds: data.getUint16(4, Endian.little)),
    );
    props.validateChildCount(1);
    return props;
  }
}

void registerPressable(NativeWidgetRegistry registry) {
  registry.register<PressableProps>(
    NativeWidgetRegistration(
      kindId: NativeWidgetKind.pressable,
      minVersion: 1,
      maxVersion: 1,
      capabilityBits: NativeCapability.stateful | NativeCapability.semantics,
      decodeProps: PressableProps.decode,
      factory: (context) {
        context.props.validateChildCount(context.children.length);
        return PressableHost(
          props: context.props,
          emit: context.emit,
          child: context.children.single,
        );
      },
    ),
  );
}

final class PressableHost extends StatefulWidget {
  const PressableHost({
    required this.props,
    required this.emit,
    required this.child,
    super.key,
  });

  final PressableProps props;
  final NativeEventEmitter? emit;
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
        : widget.props.releaseDelay;
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
    widget.emit?.call(PressableEvent.activate, Uint8List(0));
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
                  child: ColoredBox(color: widget.props.overlayColor),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
