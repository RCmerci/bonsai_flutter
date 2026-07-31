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
import '../runtime/foreground_frame_loop.dart';
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
    this.frameEligibilitySource,
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
  final FrameEligibilitySource? frameEligibilitySource;

  @override
  State<BonsaiFlutterRoot> createState() => _BonsaiFlutterRootState();
}

final class _PendingPresentation {
  _PendingPresentation({
    required this.presentationId,
    required this.revision,
    required this.generation,
  });

  final int presentationId;
  final int revision;
  int generation;
  bool postFrameArmed = false;
}

final class _BonsaiFlutterRootState extends State<BonsaiFlutterRoot> {
  RuntimeSession? _runtime;
  StreamSubscription<RuntimeUpdate>? _runtimeUpdates;
  ForegroundFrameLoop? _frameLoop;
  NodeStore? _store;
  EventBatchQueue? _events;
  HostEffectDispatcher? _hostEffects;
  final RendererResourceStore _resources = RendererResourceStore();
  CycleReady? _heldCycle;
  _PendingPresentation? _pendingPresentation;
  Object? _error;
  bool _eligible = true;
  bool _disposed = false;
  int _displayedRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordFrameTimings);
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    _frameLoop?.dispose();
    unawaited(_runtimeUpdates?.cancel());
    final runtime = _runtime;
    if (runtime != null) unawaited(runtime.dispose());
    final hostEffects = _hostEffects;
    if (hostEffects != null) unawaited(hostEffects.dispose());
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
      _hostEffects = HostEffectDispatcher(
        implementation:
            widget.hostEffects ??
            FlutterHostEffectImplementation(resources: _resources),
        onEvent: _onEvent,
      );
      _runtimeUpdates = runtime.updates.listen(
        _handleRuntimeUpdate,
        onError: _reportError,
      );
      final eligibility =
          widget.frameEligibilitySource ?? AppLifecycleFrameEligibilitySource();
      final loop = ForegroundFrameLoop(
        scheduler: SchedulerBindingFrameScheduler(),
        eligibilitySource: eligibility,
        onBeginFrame: _onBeginFrame,
        onGenerationInvalidated: (_) {},
        onEligibilityChanged: (generation, eligible) {
          _eligible = eligible;
          runtime!.setFrameEligibility(
            generation: generation,
            eligible: eligible,
          );
          return !_disposed && _error == null;
        },
        onError: _reportError,
      );
      _frameLoop = loop;
      loop.start();
    } catch (error, stackTrace) {
      if (runtime != null && !identical(runtime, _runtime)) {
        await runtime.dispose();
      }
      _reportError(error, stackTrace);
    }
  }

  void _onBeginFrame(int generation, Duration _) {
    if (_disposed || _error != null) return;
    final pending = _pendingPresentation;
    if (pending != null) {
      if (!pending.postFrameArmed || pending.generation != generation) {
        pending.generation = generation;
        _armPostFrame(pending);
      }
    } else {
      final held = _heldCycle;
      if (held != null) {
        _heldCycle = null;
        _applyCycle(held, generation);
      }
    }
    _runtime?.grantVsync(generation: generation);
  }

  void _handleRuntimeUpdate(RuntimeUpdate update) {
    if (_disposed || _error != null) return;
    switch (update) {
      case CycleReady():
        if (_heldCycle != null || _pendingPresentation != null) {
          _reportError(
            StateError('Runtime produced more than one unresolved cycle'),
            StackTrace.current,
          );
          return;
        }
        _heldCycle = update;
      case RuntimeFatalDiagnostic():
        _reportError(
          BonsaiRuntimeException(
            status: RuntimeStatus.fatalError,
            code: update.diagnostic.code,
            message: update.diagnostic.message,
          ),
          StackTrace.current,
        );
      case RuntimeDebugSnapshot() || RuntimeDisposed():
        break;
    }
  }

  void _applyCycle(CycleReady update, int generation) {
    final runtime = _runtime;
    if (runtime == null || !_eligible || _disposed) {
      _heldCycle = update;
      return;
    }
    Frame? frame;
    PreparedNodeStoreFrame? prepared;
    var committed = false;
    try {
      final bytes = update.bytes.materialize().asUint8List();
      if (bytes.isNotEmpty) {
        try {
          frame = FrameCodec.decode(bytes);
        } catch (_) {
          runtime.presentationRejected(
            generation: generation,
            presentationId: update.presentationId,
            revision: update.revision,
            reason: PresentationRejectionReason.decodeFailed,
          );
          return;
        }
        final store = _store ?? NodeStore();
        try {
          prepared = store.prepare(frame);
        } on FrameApplyException catch (error) {
          final reason = switch (error.code) {
            FrameErrorCode.epochMismatch =>
              PresentationRejectionReason.rendererEpochMismatch,
            FrameErrorCode.revisionMismatch =>
              PresentationRejectionReason.rendererRevisionMismatch,
            _ => PresentationRejectionReason.frameValidationFailed,
          };
          runtime.presentationRejected(
            generation: generation,
            presentationId: update.presentationId,
            revision: update.revision,
            reason: reason,
          );
          return;
        }
        store.commit(prepared);
        committed = true;
        _store = store;
        _events ??= EventBatchQueue(
          runtimeEpoch: frame.runtimeEpoch,
          displayedRevision: () => _displayedRevision,
        );
        _resources.synchronize(store);
        final dispatch = _hostEffects?.dispatch(frame);
        if (dispatch != null) {
          unawaited(
            dispatch.catchError((Object error, StackTrace stackTrace) {
              _reportError(error, stackTrace);
            }),
          );
        }
        if (mounted) setState(() {});
      }
      final pending = _PendingPresentation(
        presentationId: update.presentationId,
        revision: update.revision,
        generation: generation,
      );
      _pendingPresentation = pending;
      _armPostFrame(pending);
    } catch (error, stackTrace) {
      if (!committed) {
        try {
          runtime.presentationRejected(
            generation: generation,
            presentationId: update.presentationId,
            revision: update.revision,
            reason: PresentationRejectionReason.frameValidationFailed,
          );
          return;
        } catch (_) {
          // The original failure remains authoritative.
        }
      }
      _reportError(error, stackTrace);
    }
  }

  void _armPostFrame(_PendingPresentation pending) {
    final loop = _frameLoop;
    if (loop == null || pending.postFrameArmed || !_eligible) return;
    pending.postFrameArmed = true;
    loop.addGuardedPostFrameCallback(
      generation: pending.generation,
      callback: (_) {
        pending.postFrameArmed = false;
        if (_disposed ||
            _error != null ||
            !identical(_pendingPresentation, pending)) {
          return;
        }
        try {
          final runtime = _runtime;
          if (runtime == null) return;
          final events = _events?.prepareBatch(
            runtimeControlRevision: pending.revision,
          );
          final eventBatch = events?.encodedBytes ?? Uint8List(0);
          _displayedRevision = pending.revision;
          runtime.presentationSucceeded(
            generation: pending.generation,
            presentationId: pending.presentationId,
            revision: pending.revision,
            eventBatch: eventBatch,
          );
          if (events != null) _events!.commit(events);
          _pendingPresentation = null;
        } catch (error, stackTrace) {
          _reportError(error, stackTrace);
        }
      },
    );
  }

  void _onEvent(RendererEvent event) {
    final events = _events;
    if (events == null || _error != null || _disposed) return;
    try {
      events.enqueue(event);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
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

  void _reportError(Object error, [StackTrace? stackTrace]) {
    if (_disposed || _error != null) return;
    _frameLoop?.dispose();
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
