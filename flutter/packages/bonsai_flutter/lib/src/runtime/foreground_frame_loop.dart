// ignore_for_file: prefer_initializing_formals

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

abstract interface class RuntimeFrameScheduler {
  bool get framesEnabled;

  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
  });

  void cancelFrameCallbackWithId(int id);
  void addPostFrameCallback(FrameCallback callback);
}

final class SchedulerBindingFrameScheduler implements RuntimeFrameScheduler {
  @override
  bool get framesEnabled => SchedulerBinding.instance.framesEnabled;

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
  }) => SchedulerBinding.instance.scheduleFrameCallback(
    callback,
    rescheduling: rescheduling,
  );

  @override
  void cancelFrameCallbackWithId(int id) {
    SchedulerBinding.instance.cancelFrameCallbackWithId(id);
  }

  @override
  void addPostFrameCallback(FrameCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback(callback);
  }
}

abstract interface class FrameEligibilitySource {
  bool get isEligible;
  void start(void Function(bool isEligible) onChanged);
  void dispose();
}

final class AppLifecycleFrameEligibilitySource
    with WidgetsBindingObserver
    implements FrameEligibilitySource {
  void Function(bool)? _onChanged;
  bool _eligible = true;
  bool _started = false;

  @override
  bool get isEligible => _eligible;

  @override
  void start(void Function(bool isEligible) onChanged) {
    if (_started) {
      throw StateError('App lifecycle eligibility source already started');
    }
    _started = true;
    _onChanged = onChanged;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) _eligible = _isEligibleState(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final eligible = _isEligibleState(state);
    _eligible = eligible;
    _onChanged?.call(eligible);
  }

  @override
  void dispose() {
    if (!_started) return;
    _started = false;
    _onChanged = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}

bool _isEligibleState(AppLifecycleState state) => switch (state) {
  AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};

final class ForegroundFrameLoop {
  ForegroundFrameLoop({
    required RuntimeFrameScheduler scheduler,
    required FrameEligibilitySource eligibilitySource,
    required void Function(int generation, Duration timestamp) onBeginFrame,
    required void Function(int generation) onGenerationInvalidated,
    required bool Function(int generation, bool eligible) onEligibilityChanged,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) : _scheduler = scheduler,
       _eligibilitySource = eligibilitySource,
       _onBeginFrame = onBeginFrame,
       _onGenerationInvalidated = onGenerationInvalidated,
       _onEligibilityChanged = onEligibilityChanged,
       _onError = onError;

  final RuntimeFrameScheduler _scheduler;
  final FrameEligibilitySource _eligibilitySource;
  final void Function(int generation, Duration timestamp) _onBeginFrame;
  final void Function(int generation) _onGenerationInvalidated;
  final bool Function(int generation, bool eligible) _onEligibilityChanged;
  final void Function(Object error, StackTrace stackTrace) _onError;

  int generation = 0;
  int? debugScheduledCallbackId;
  bool isTerminal = false;
  bool _started = false;
  bool _disposed = false;
  bool _eligible = false;

  void start() {
    if (_started || _disposed || isTerminal) return;
    _started = true;
    _eligible = _eligibilitySource.isEligible;
    generation += 1;
    _eligibilitySource.start(_handleEligibility);
    final accepted = _onEligibilityChanged(generation, _eligible);
    if (_eligible && accepted) _schedule(rescheduling: false);
  }

  void requestFrame() {
    if (_disposed || isTerminal || !_eligible) return;
    _schedule(rescheduling: false);
  }

  void addGuardedPostFrameCallback({
    required int generation,
    required FrameCallback callback,
  }) {
    if (_disposed || isTerminal) return;
    _scheduler.addPostFrameCallback((timestamp) {
      if (_disposed ||
          isTerminal ||
          !_eligible ||
          generation != this.generation) {
        return;
      }
      callback(timestamp);
    });
  }

  void _handleEligibility(bool eligible) {
    if (_disposed || isTerminal || eligible == _eligible) return;
    _eligible = eligible;
    generation += 1;
    if (!eligible) {
      final scheduled = debugScheduledCallbackId;
      debugScheduledCallbackId = null;
      if (scheduled != null) {
        _scheduler.cancelFrameCallbackWithId(scheduled);
      }
      _onGenerationInvalidated(generation);
      _onEligibilityChanged(generation, false);
      return;
    }
    final accepted = _onEligibilityChanged(generation, true);
    if (accepted && _scheduler.framesEnabled) {
      _schedule(rescheduling: false);
    }
  }

  void _schedule({required bool rescheduling}) {
    if (_disposed ||
        isTerminal ||
        !_eligible ||
        !_scheduler.framesEnabled ||
        debugScheduledCallbackId != null) {
      return;
    }
    try {
      late final int callbackId;
      final callbackGeneration = generation;
      callbackId = _scheduler.scheduleFrameCallback((timestamp) {
        _runFrame(callbackId, callbackGeneration, timestamp);
      }, rescheduling: rescheduling);
      debugScheduledCallbackId = callbackId;
    } catch (error, stackTrace) {
      isTerminal = true;
      debugScheduledCallbackId = null;
      _onError(error, stackTrace);
    }
  }

  void _runFrame(int callbackId, int callbackGeneration, Duration timestamp) {
    if (_disposed ||
        isTerminal ||
        debugScheduledCallbackId != callbackId ||
        callbackGeneration != generation) {
      return;
    }
    debugScheduledCallbackId = null;
    if (!_eligible || !_scheduler.framesEnabled) return;
    _schedule(rescheduling: true);
    if (isTerminal) return;
    try {
      _onBeginFrame(callbackGeneration, timestamp);
    } catch (error, stackTrace) {
      isTerminal = true;
      final scheduled = debugScheduledCallbackId;
      debugScheduledCallbackId = null;
      if (scheduled != null) {
        _scheduler.cancelFrameCallbackWithId(scheduled);
      }
      _onError(error, stackTrace);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final scheduled = debugScheduledCallbackId;
    debugScheduledCallbackId = null;
    if (scheduled != null) {
      _scheduler.cancelFrameCallbackWithId(scheduled);
    }
    _eligibilitySource.dispose();
  }
}
