import 'dart:async';
import 'dart:typed_data';

import 'package:bonsai_flutter/bonsai_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'application_support_bootstrap.dart';

typedef StartupNow = Duration Function();

void main() {
  runApp(const SqliteWorkerApplication());
}

final class SqliteWorkerApplication extends StatelessWidget {
  const SqliteWorkerApplication({super.key});

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: SqliteWorkerHost(),
  );
}

final class SqliteWorkerHost extends StatefulWidget {
  const SqliteWorkerHost({
    this.resolveApplicationSupport = getApplicationSupportDirectory,
    this.createDirectory,
    this.runtimeStarter,
    this.startupNow,
    super.key,
  });

  final ApplicationSupportResolver resolveApplicationSupport;
  final DirectoryCreator? createDirectory;
  final RuntimeStarter? runtimeStarter;
  final StartupNow? startupNow;

  @override
  State<SqliteWorkerHost> createState() => _SqliteWorkerHostState();
}

final class _SqliteWorkerHostState extends State<SqliteWorkerHost> {
  late final Stopwatch _startupStopwatch;
  late final StartupNow _now;
  late final Duration _startupStartedAt;
  SqliteWorkerBootstrap? _bootstrap;
  Object? _bootstrapError;
  Duration? _storageBootstrap;
  Duration? _storageBootstrapFailure;
  Duration? _runtimeAndWorker;
  Duration? _runtimeAndWorkerFailure;
  Duration? _firstOcamlFrame;
  Duration? _firstFlutterPresentation;
  Duration? _runtimeReadyAt;
  Duration? _firstFrameAt;

  @override
  void initState() {
    super.initState();
    _startupStopwatch = Stopwatch()..start();
    _now = widget.startupNow ?? () => _startupStopwatch.elapsed;
    _startupStartedAt = _now();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _startupStopwatch.stop();
    super.dispose();
  }

  Duration _elapsed(Duration startedAt) {
    final elapsed = _now() - startedAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _prepare() async {
    try {
      final bootstrap = await resolveSqliteWorkerBootstrap(
        resolveApplicationSupport: widget.resolveApplicationSupport,
        createDirectory: widget.createDirectory,
      );
      if (!mounted) return;
      setState(() {
        _storageBootstrap = _elapsed(_startupStartedAt);
        _bootstrap = bootstrap;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storageBootstrapFailure = _elapsed(_startupStartedAt);
        _bootstrapError = error;
      });
    }
  }

  Future<RuntimeSession> _startRuntime(Uint8List config) async {
    final startedAt = _now();
    try {
      final starter =
          widget.runtimeStarter ??
          ((config) => RuntimeClient.start(config: config));
      final runtime = await starter(config);
      final readyAt = _now();
      if (mounted) {
        setState(() {
          _runtimeAndWorker = _durationBetween(startedAt, readyAt);
          _runtimeReadyAt = readyAt;
        });
      }
      return _StartupObservedRuntime(
        runtime,
        onFirstCycle: _recordFirstCycle,
        onFirstPresentation: _recordFirstPresentation,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _runtimeAndWorkerFailure = _elapsed(startedAt));
      }
      rethrow;
    }
  }

  Duration _durationBetween(Duration startedAt, Duration finishedAt) {
    final elapsed = finishedAt - startedAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void _recordFirstCycle() {
    if (!mounted || _firstOcamlFrame != null) return;
    final finishedAt = _now();
    final startedAt = _runtimeReadyAt ?? finishedAt;
    setState(() {
      _firstOcamlFrame = _durationBetween(startedAt, finishedAt);
      _firstFrameAt = finishedAt;
    });
  }

  void _recordFirstPresentation() {
    if (!mounted || _firstFlutterPresentation != null) return;
    final finishedAt = _now();
    final startedAt = _firstFrameAt ?? finishedAt;
    setState(() {
      _firstFlutterPresentation = _durationBetween(startedAt, finishedAt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _bootstrapError;
    if (error != null) {
      return _withStartupTiming(
        _MessageScreen(
          title: 'Unable to prepare Todo storage',
          detail: error.toString(),
        ),
      );
    }
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      return _withStartupTiming(
        const _MessageScreen(title: 'Preparing Todo database…'),
      );
    }
    return _withStartupTiming(
      BonsaiFlutterRoot(
        config: Uint8List.fromList(bootstrap.runtimeConfig),
        runtimeStarter: _startRuntime,
        loading: const _MessageScreen(title: 'Starting Todo worker…'),
        errorBuilder: (context, runtimeError) => _MessageScreen(
          title: 'Unable to start Todo worker',
          detail: runtimeError.toString(),
        ),
      ),
    );
  }

  Widget _withStartupTiming(Widget child) => Stack(
    children: [
      Positioned.fill(child: child),
      Positioned(
        right: 12,
        bottom: 12,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xfff1f0f4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DefaultTextStyle(
                style: const TextStyle(color: Color(0xff45464f), fontSize: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Host startup timings',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _stageText(
                        'Storage bootstrap',
                        _storageBootstrap,
                        _storageBootstrapFailure,
                      ),
                    ),
                    Text(
                      _stageText(
                        'Runtime + Worker ready',
                        _runtimeAndWorker,
                        _runtimeAndWorkerFailure,
                      ),
                    ),
                    Text(
                      _stageText('First OCaml frame', _firstOcamlFrame, null),
                    ),
                    Text(
                      _stageText(
                        'First Flutter presentation',
                        _firstFlutterPresentation,
                        null,
                      ),
                    ),
                    Text(_totalText()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  String _stageText(String label, Duration? duration, Duration? failure) {
    if (duration != null) return '$label: ${_formatDuration(duration)}';
    if (failure != null) {
      return '$label: failed after ${_formatDuration(failure)}';
    }
    return '$label: pending';
  }

  String _totalText() {
    final stages = [
      _storageBootstrap,
      _runtimeAndWorker,
      _firstOcamlFrame,
      _firstFlutterPresentation,
    ];
    if (stages.any((stage) => stage == null)) return 'Total startup: pending';
    final total = stages.whereType<Duration>().fold(
      Duration.zero,
      (sum, stage) => sum + stage,
    );
    return 'Total startup: ${_formatDuration(total)}';
  }

  String _formatDuration(Duration duration) =>
      '${(duration.inMicroseconds / 1000).toStringAsFixed(3)} ms';
}

final class _StartupObservedRuntime implements RuntimeSession {
  _StartupObservedRuntime(
    this._delegate, {
    required this.onFirstCycle,
    required this.onFirstPresentation,
  });

  final RuntimeSession _delegate;
  final void Function() onFirstCycle;
  final void Function() onFirstPresentation;
  bool _cycleRecorded = false;
  bool _presentationRecorded = false;

  @override
  Stream<RuntimeUpdate> get updates => _delegate.updates.map((update) {
    if (!_cycleRecorded && update is CycleReady) {
      _cycleRecorded = true;
      onFirstCycle();
    }
    return update;
  });

  @override
  void grantVsync({required int generation}) =>
      _delegate.grantVsync(generation: generation);

  @override
  void setFrameEligibility({required int generation, required bool eligible}) =>
      _delegate.setFrameEligibility(generation: generation, eligible: eligible);

  @override
  void presentationSucceeded({
    required int generation,
    required int presentationId,
    required int revision,
    required Uint8List eventBatch,
  }) {
    _delegate.presentationSucceeded(
      generation: generation,
      presentationId: presentationId,
      revision: revision,
      eventBatch: eventBatch,
    );
    if (!_presentationRecorded) {
      _presentationRecorded = true;
      onFirstPresentation();
    }
  }

  @override
  void presentationRejected({
    required int generation,
    required int presentationId,
    required int revision,
    required PresentationRejectionReason reason,
  }) => _delegate.presentationRejected(
    generation: generation,
    presentationId: presentationId,
    revision: revision,
    reason: reason,
  );

  @override
  Future<RuntimeDebugSnapshot> debugSnapshot() => _delegate.debugSnapshot();

  @override
  Future<void> dispose() => _delegate.dispose();
}

final class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfffafafa),
    child: DefaultTextStyle(
      style: const TextStyle(color: Color(0xff1b1b1f), fontSize: 16),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, textAlign: TextAlign.center),
              if (detail case final detail?) ...[
                const SizedBox(height: 12),
                Text(detail, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
