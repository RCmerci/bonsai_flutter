import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';

import '../debug/frame_stats.dart';
import '../environment/environment_reporter.dart';
import '../host_effects/host_effect_dispatcher.dart';
import '../protocol/binary_codec.dart';
import '../protocol/frame.dart';
import '../renderer/node_host.dart';
import '../renderer/renderer_resource_store.dart';
import '../renderer/widget_registry.dart';
import '../runtime/event_batch_queue.dart';
import '../runtime/runtime_client.dart';
import '../store/node_store.dart';

typedef RuntimeStarter = Future<RuntimeSession> Function(Uint8List config);
typedef RuntimeErrorBuilder =
    Widget Function(BuildContext context, Object error);

final class BonsaiFlutterRoot extends StatefulWidget {
  BonsaiFlutterRoot({
    required this.config,
    RuntimeStarter? runtimeStarter,
    WidgetRegistry? registry,
    this.loading,
    this.errorBuilder,
    this.hostEffects,
    super.key,
  }) : runtimeStarter =
           runtimeStarter ?? ((config) => RuntimeClient.start(config: config)),
       registry = registry ?? WidgetRegistry.standard();

  final Uint8List config;
  final RuntimeStarter runtimeStarter;
  final WidgetRegistry registry;
  final Widget? loading;
  final RuntimeErrorBuilder? errorBuilder;
  final HostEffectImplementation? hostEffects;

  @override
  State<BonsaiFlutterRoot> createState() => _BonsaiFlutterRootState();
}

final class _BonsaiFlutterRootState extends State<BonsaiFlutterRoot> {
  RuntimeSession? _runtime;
  NodeStore? _store;
  EventBatchQueue? _events;
  HostEffectDispatcher? _hostEffects;
  final RendererResourceStore _resources = RendererResourceStore();
  Object? _error;
  Future<void> _draining = Future.value();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordFrameTimings);
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.dispose());
    }
    final hostEffects = _hostEffects;
    if (hostEffects != null) {
      unawaited(hostEffects.dispose());
    }
    _resources.dispose();
    WidgetsBinding.instance.removeTimingsCallback(_recordFrameTimings);
    super.dispose();
  }

  Future<void> _start() async {
    RuntimeSession? runtime;
    try {
      runtime = await widget.runtimeStarter(Uint8List.fromList(widget.config));
      if (_disposed) {
        await runtime.dispose();
        return;
      }
      _runtime = runtime;
      final response = await runtime.step(Uint8List(0));
      _requireSuccess(response);
      if (response.bytes.isEmpty) {
        throw StateError('Initial runtime step returned no frame');
      }
      final frame = FrameCodec.decode(response.bytes);
      DebugFrameRecorder.recordRuntimeResponse(
        frame,
        ffiDuration: response.ffiDuration,
        isolateTransferDuration: response.isolateTransferDuration,
      );
      if (frame.kind != FrameKind.fullSnapshot) {
        throw StateError('Initial runtime step must return a full snapshot');
      }
      final store = NodeStore()..apply(frame);
      _store = store;
      _resources.synchronize(store);
      _events = EventBatchQueue(
        runtimeEpoch: frame.runtimeEpoch,
        displayedRevision: () => store.revision,
      );
      _hostEffects = HostEffectDispatcher(
        implementation:
            widget.hostEffects ??
            FlutterHostEffectImplementation(resources: _resources),
        onEvent: _onEvent,
      );
      _dispatchHostOperations(frame);
      if (mounted) {
        setState(() {});
      }
      await _acknowledgeAfterFrame(
        runtime,
        frame.runtimeEpoch,
        frame.targetRevision,
      );
    } catch (error, stackTrace) {
      if (runtime != null && !identical(runtime, _runtime)) {
        await runtime.dispose();
      }
      _reportError(error, stackTrace);
    }
  }

  void _onEvent(RendererEvent event) {
    final events = _events;
    if (events == null || _error != null || _disposed) return;
    try {
      events.enqueue(event);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      return;
    }
    _draining = _draining.then((_) => _drainEvents()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _reportError(error, stackTrace);
    });
  }

  Future<void> _drainEvents() async {
    final runtime = _runtime;
    final events = _events;
    final store = _store;
    if (runtime == null || events == null || store == null || _disposed) return;
    for (
      var batch = events.takeBatch();
      batch != null;
      batch = events.takeBatch()
    ) {
      final response = await runtime.sendEventBatch(batch);
      if (_isRecoverableStaleEvent(response)) continue;
      _requireSuccess(response);
      if (response.bytes.isEmpty) continue;
      final frame = FrameCodec.decode(response.bytes);
      DebugFrameRecorder.recordRuntimeResponse(
        frame,
        ffiDuration: response.ffiDuration,
        isolateTransferDuration: response.isolateTransferDuration,
      );
      try {
        store.apply(frame);
        _resources.synchronize(store);
      } on FrameApplyException catch (error) {
        if (error.code == FrameErrorCode.revisionMismatch ||
            error.code == FrameErrorCode.epochMismatch) {
          events.requestResync();
          continue;
        }
        rethrow;
      }
      _dispatchHostOperations(frame);
      await _acknowledgeAfterFrame(
        runtime,
        frame.runtimeEpoch,
        frame.targetRevision,
      );
    }
  }

  void _dispatchHostOperations(Frame frame) {
    final dispatcher = _hostEffects;
    if (dispatcher == null) return;
    unawaited(
      dispatcher.dispatch(frame).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _reportError(error, stackTrace);
      }),
    );
  }

  Future<void> _acknowledgeAfterFrame(
    RuntimeSession runtime,
    int runtimeEpoch,
    int revision,
  ) {
    final completer = Completer<void>();
    final presentation = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (_disposed) {
          completer.complete();
          return;
        }
        presentation.stop();
        final lifecycle = Stopwatch()..start();
        _requireSuccess(await runtime.framePresented(revision));
        lifecycle.stop();
        DebugFrameRecorder.recordPresented(
          runtimeEpoch,
          revision,
          latency: presentation.elapsed,
          lifecycleDuration: lifecycle.elapsed,
        );
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    final store = _store;
    if (store == null || timings.isEmpty) return;
    final timing = timings.last;
    final accounted =
        timing.buildDuration.inMicroseconds +
        timing.rasterDuration.inMicroseconds;
    final unaccounted = timing.totalSpan.inMicroseconds - accounted;
    DebugFrameRecorder.recordFlutterTiming(
      store.runtimeEpoch!,
      store.revision,
      buildDuration: timing.buildDuration,
      layoutDuration: Duration(microseconds: unaccounted < 0 ? 0 : unaccounted),
      paintDuration: timing.rasterDuration,
    );
  }

  void _requireSuccess(RuntimeResponse response) {
    if (response.status != RuntimeStatus.ok) {
      throw BonsaiRuntimeException(
        status: response.status,
        code: response.errorCode,
        message:
            response.errorMessage ?? 'Runtime returned ${response.status.name}',
      );
    }
  }

  bool _isRecoverableStaleEvent(RuntimeResponse response) =>
      response.status == RuntimeStatus.recoverableError &&
      response.errorCode == RuntimeErrorCode.staleEvent;

  void _reportError(Object error, StackTrace stackTrace) {
    if (_disposed || _error != null) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'bonsai_flutter',
        context: ErrorDescription('while driving the OCaml runtime'),
      ),
    );
    if (mounted) {
      setState(() => _error = error);
    } else {
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          Text('Bonsai runtime error: $error');
    }
    final store = _store;
    if (store == null) {
      return widget.loading ?? const SizedBox.shrink();
    }
    return EnvironmentReporter(
      onEvent: _onEvent,
      child: BonsaiFlutterView(
        store: store,
        registry: widget.registry,
        onEvent: _onEvent,
        resourceStore: _resources,
      ),
    );
  }
}
