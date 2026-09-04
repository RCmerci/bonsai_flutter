import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../protocol/frame.dart';
import '../renderer/renderer_resource_store.dart';
import '../store/node_store.dart';

abstract final class NativeWidgetKind {
  static const int slidable = 2;
  static const int navigationShell = 3;
  static const int morphingSurface = 5;
  static const int messageComposer = 6;
  static const int expandableMessageComposer = 7;
  static const int slidableAutoCloseBehavior = 8;
}

abstract final class NativeCapability {
  static const int stateful = 1 << 0;
  static const int resource = 1 << 1;
  static const int semantics = 1 << 2;
  static const int semanticsCanvas = 1 << 3;
  static const int virtualized = 1 << 4;

  static const int core =
      stateful | resource | semantics | semanticsCanvas | virtualized;
}

typedef NativePropsDecoder<Props extends Object> =
    Props Function(Uint8List payload);
typedef NativeWidgetFactory<Props extends Object> =
    Widget Function(NativeWidgetBuildContext<Props> context);
typedef NativeEventEmitter = void Function(int eventId, Uint8List eventPayload);

abstract interface class _ErasedNativeWidgetRegistration {
  int get kindId;
  int get minVersion;
  int get maxVersion;
  int get capabilityBits;

  Widget build({
    required BuildContext context,
    required UiNode node,
    required NativeWidgetProps nativeProps,
    required List<Widget> children,
    required RendererResourceStore resources,
    required NativeEventEmitter? emit,
  });
}

final class NativeWidgetRegistration<Props extends Object>
    implements _ErasedNativeWidgetRegistration {
  const NativeWidgetRegistration({
    required this.kindId,
    required this.minVersion,
    required this.maxVersion,
    required this.capabilityBits,
    required this.decodeProps,
    required this.factory,
  });

  @override
  final int kindId;
  @override
  final int minVersion;
  @override
  final int maxVersion;
  @override
  final int capabilityBits;
  final NativePropsDecoder<Props> decodeProps;
  final NativeWidgetFactory<Props> factory;

  @override
  Widget build({
    required BuildContext context,
    required UiNode node,
    required NativeWidgetProps nativeProps,
    required List<Widget> children,
    required RendererResourceStore resources,
    required NativeEventEmitter? emit,
  }) => factory(
    NativeWidgetBuildContext<Props>(
      context: context,
      node: node,
      nativeProps: nativeProps,
      props: decodeProps(nativeProps.payload),
      children: children,
      resources: resources,
      emit: emit,
    ),
  );
}

final class NativeWidgetBuildContext<Props extends Object> {
  const NativeWidgetBuildContext({
    required this.context,
    required this.node,
    required this.nativeProps,
    required this.props,
    required this.children,
    required this.resources,
    required this.emit,
  });

  final BuildContext context;
  final UiNode node;
  final NativeWidgetProps nativeProps;
  final Props props;
  final List<Widget> children;
  final RendererResourceStore resources;
  final NativeEventEmitter? emit;

  Resource resource<Resource extends Object>({
    required Resource Function() create,
    required void Function(Resource resource) dispose,
  }) => resources.acquireNativeResource<Resource>(
    nodeId: node.id,
    kindId: nativeProps.kindId,
    version: nativeProps.version,
    create: create,
    dispose: dispose,
  );
}

final class NativeWidgetRegistry {
  NativeWidgetRegistry({required this.capabilityBits});

  final int capabilityBits;
  final Map<int, _ErasedNativeWidgetRegistration> _registrations = {};

  void register<Props extends Object>(
    NativeWidgetRegistration<Props> registration,
  ) {
    if (registration.kindId <= 0 || registration.kindId > 0xffffffff) {
      throw ArgumentError.value(
        registration.kindId,
        'kindId',
        'must be in 1..4294967295',
      );
    }
    if (registration.minVersion <= 0 ||
        registration.maxVersion < registration.minVersion ||
        registration.maxVersion > 0xffff) {
      throw ArgumentError('Native widget version range is invalid');
    }
    if (_registrations.containsKey(registration.kindId)) {
      throw StateError(
        'Native widget kind ${registration.kindId} is already registered',
      );
    }
    _registrations[registration.kindId] = registration;
  }

  Widget build({
    required BuildContext context,
    required UiNode node,
    required NativeWidgetProps props,
    required List<Widget> children,
    required RendererResourceStore resources,
    required NativeEventEmitter? emit,
  }) {
    final registration = _registrations[props.kindId];
    if (registration == null) {
      return UnsupportedNativeWidget(
        message: 'Unsupported native widget kind ${props.kindId}',
      );
    }
    if (props.version < registration.minVersion ||
        props.version > registration.maxVersion) {
      return UnsupportedNativeWidget(
        message:
            'Unsupported version ${props.version} for native widget '
            'kind ${props.kindId}',
      );
    }
    final unsupportedCapabilities =
        props.capabilityBits & ~(capabilityBits & registration.capabilityBits);
    if (unsupportedCapabilities != 0) {
      return UnsupportedNativeWidget(
        message:
            'Unsupported capabilities 0x'
            '${unsupportedCapabilities.toRadixString(16)} for native widget '
            'kind ${props.kindId}',
      );
    }
    try {
      return registration.build(
        context: context,
        node: node,
        nativeProps: props,
        children: children,
        resources: resources,
        emit: emit,
      );
    } on Object catch (error) {
      return UnsupportedNativeWidget(
        message: 'Invalid props for native widget kind ${props.kindId}: $error',
      );
    }
  }
}

final class UnsupportedNativeWidget extends StatelessWidget {
  const UnsupportedNativeWidget({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    label: message,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    ),
  );
}
