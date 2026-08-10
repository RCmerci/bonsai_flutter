import 'package:bonsai_flutter/src/runtime/foreground_frame_loop.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

final class ScheduledFrame {
  const ScheduledFrame({
    required this.id,
    required this.callback,
    required this.rescheduling,
  });

  final int id;
  final FrameCallback callback;
  final bool rescheduling;
}

final class FakeRuntimeFrameScheduler implements RuntimeFrameScheduler {
  var nextId = 1;
  var framesEnabledValue = true;
  final List<ScheduledFrame> scheduled = [];
  final List<int> canceled = [];
  final List<FrameCallback> postFrameCallbacks = [];
  var throwOnSchedule = false;

  @override
  bool get framesEnabled => framesEnabledValue;

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
  }) {
    if (throwOnSchedule) {
      throw StateError('schedule failed');
    }
    final frame = ScheduledFrame(
      id: nextId++,
      callback: callback,
      rescheduling: rescheduling,
    );
    scheduled.add(frame);
    return frame.id;
  }

  @override
  void cancelFrameCallbackWithId(int id) {
    canceled.add(id);
  }

  @override
  void addPostFrameCallback(FrameCallback callback) {
    postFrameCallbacks.add(callback);
  }

  void fire(int id, {Duration timestamp = Duration.zero}) {
    scheduled.singleWhere((frame) => frame.id == id).callback(timestamp);
  }

  void flushPostFrame({Duration timestamp = Duration.zero}) {
    final callbacks = List<FrameCallback>.of(postFrameCallbacks);
    postFrameCallbacks.clear();
    for (final callback in callbacks) {
      callback(timestamp);
    }
  }
}

final class FakeFrameEligibilitySource implements FrameEligibilitySource {
  FakeFrameEligibilitySource(this.eligible);

  bool eligible;
  void Function(bool)? _listener;
  var disposeCount = 0;

  @override
  bool get isEligible => eligible;

  @override
  void start(void Function(bool isEligible) onChanged) {
    if (_listener != null) {
      throw StateError('eligibility source already started');
    }
    _listener = onChanged;
  }

  void emit(bool value) {
    eligible = value;
    _listener?.call(value);
  }

  @override
  void dispose() {
    disposeCount += 1;
    _listener = null;
  }
}

final class LoopHarness {
  LoopHarness({bool eligible = true})
    : scheduler = FakeRuntimeFrameScheduler(),
      eligibility = FakeFrameEligibilitySource(eligible) {
    loop = ForegroundFrameLoop(
      scheduler: scheduler,
      eligibilitySource: eligibility,
      onBeginFrame: (generation, timestamp) {
        events.add('begin:$generation:${timestamp.inMicroseconds}');
      },
      onGenerationInvalidated: (generation) {
        events.add('invalidated:$generation');
      },
      onEligibilityChanged: (generation, eligible) {
        events.add('eligible:$generation:$eligible');
        return true;
      },
      onError: (error, stackTrace) {
        events.add('error:$error');
      },
    );
  }

  final FakeRuntimeFrameScheduler scheduler;
  final FakeFrameEligibilitySource eligibility;
  final List<String> events = [];
  late final ForegroundFrameLoop loop;
}

void main() {
  test('start registers one callback without rescheduling', () {
    final harness = LoopHarness();

    harness.loop.start();

    expect(harness.scheduler.scheduled, hasLength(1));
    expect(harness.scheduler.scheduled.single.rescheduling, isFalse);
    expect(harness.loop.debugScheduledCallbackId, 1);
  });

  test(
    'each callback registers one successor before reporting begin frame',
    () {
      final harness = LoopHarness();
      harness.loop.start();

      harness.scheduler.fire(1, timestamp: const Duration(microseconds: 5));

      expect(harness.scheduler.scheduled, hasLength(2));
      expect(harness.scheduler.scheduled[1].rescheduling, isTrue);
      expect(harness.events.last, startsWith('begin:'));
      expect(harness.loop.debugScheduledCallbackId, 2);
    },
  );

  test(
    'ineligible transition cancels and invalidates without a later grant',
    () {
      final harness = LoopHarness();
      harness.loop.start();

      harness.eligibility.emit(false);
      harness.scheduler.fire(1);

      expect(harness.scheduler.canceled, [1]);
      expect(
        harness.events.where((event) => event.startsWith('begin:')),
        isEmpty,
      );
      expect(
        harness.events.where((event) => event.startsWith('invalidated:')),
        hasLength(1),
      );
      expect(harness.loop.debugScheduledCallbackId, isNull);
    },
  );

  test('resume creates one new generation and never duplicates callback', () {
    final harness = LoopHarness();
    harness.loop.start();
    harness.eligibility.emit(false);

    harness.eligibility.emit(true);
    harness.eligibility.emit(true);

    expect(harness.scheduler.scheduled, hasLength(2));
    expect(harness.scheduler.scheduled.last.rescheduling, isFalse);
    expect(harness.loop.debugScheduledCallbackId, 2);
  });

  test('independent framesEnabled loss performs no grant or successor', () {
    final harness = LoopHarness();
    harness.loop.start();
    harness.scheduler.framesEnabledValue = false;

    harness.scheduler.fire(1);

    expect(harness.scheduler.scheduled, hasLength(1));
    expect(
      harness.events.where((event) => event.startsWith('begin:')),
      isEmpty,
    );
    expect(harness.loop.debugScheduledCallbackId, isNull);
  });

  test('explicit frame request recovers a live loop without a successor', () {
    final harness = LoopHarness();
    harness.loop.start();
    harness.scheduler.framesEnabledValue = false;
    harness.scheduler.fire(1);
    harness.scheduler.framesEnabledValue = true;

    harness.loop.requestFrame();

    expect(harness.scheduler.scheduled, hasLength(2));
    expect(harness.scheduler.scheduled.last.rescheduling, isFalse);
    expect(harness.loop.debugScheduledCallbackId, 2);
  });

  test('explicit frame request never duplicates a live callback', () {
    final harness = LoopHarness();
    harness.loop.start();

    harness.loop.requestFrame();
    harness.loop.requestFrame();

    expect(harness.scheduler.scheduled, hasLength(1));
    expect(harness.loop.debugScheduledCallbackId, 1);
  });

  test('stale callback cannot clear a resumed generation callback id', () {
    final harness = LoopHarness();
    harness.loop.start();
    harness.eligibility.emit(false);
    harness.eligibility.emit(true);
    expect(harness.loop.debugScheduledCallbackId, 2);

    harness.scheduler.fire(1);

    expect(harness.loop.debugScheduledCallbackId, 2);
    harness.scheduler.fire(2);
    expect(harness.loop.debugScheduledCallbackId, 3);
  });

  test('guarded post-frame callback rejects stale generation', () {
    final harness = LoopHarness();
    harness.loop.start();
    final originalGeneration = harness.loop.generation;
    var postFrames = 0;
    harness.loop.addGuardedPostFrameCallback(
      generation: originalGeneration,
      callback: (_) => postFrames += 1,
    );

    harness.eligibility.emit(false);
    harness.eligibility.emit(true);
    harness.scheduler.flushPostFrame();

    expect(postFrames, 0);
  });

  test('guarded post-frame callback runs for exact live generation', () {
    final harness = LoopHarness();
    harness.loop.start();
    var postFrames = 0;
    harness.loop.addGuardedPostFrameCallback(
      generation: harness.loop.generation,
      callback: (_) => postFrames += 1,
    );

    harness.scheduler.flushPostFrame();

    expect(postFrames, 1);
  });

  test(
    'dispose cancels callback and disposes lifecycle source exactly once',
    () {
      final harness = LoopHarness();
      harness.loop.start();

      harness.loop.dispose();
      harness.loop.dispose();
      harness.scheduler.fire(1);

      expect(harness.scheduler.canceled, [1]);
      expect(harness.eligibility.disposeCount, 1);
      expect(harness.loop.debugScheduledCallbackId, isNull);
      expect(
        harness.events.where((event) => event.startsWith('begin:')),
        isEmpty,
      );
    },
  );

  test('scheduler exception reports terminal error and stores no callback', () {
    final harness = LoopHarness();
    harness.scheduler.throwOnSchedule = true;

    harness.loop.start();

    expect(harness.events, contains('error:Bad state: schedule failed'));
    expect(harness.loop.isTerminal, isTrue);
    expect(harness.loop.debugScheduledCallbackId, isNull);
  });

  testWidgets('AppLifecycle eligibility follows the valid mobile sequence', (
    tester,
  ) async {
    final source = AppLifecycleFrameEligibilitySource();
    final values = <bool>[];
    source.start(values.add);
    addTearDown(source.dispose);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);

    expect(values, [true, true, false, false, false, true, true, false]);
    expect(source.isEligible, isFalse);
  });

  testWidgets('real binding grants at most once per bounded tester frame', (
    tester,
  ) async {
    final eligibility = FakeFrameEligibilitySource(true);
    var grants = 0;
    final loop = ForegroundFrameLoop(
      scheduler: SchedulerBindingFrameScheduler(),
      eligibilitySource: eligibility,
      onBeginFrame: (_, _) => grants += 1,
      onGenerationInvalidated: (_) {},
      onEligibilityChanged: (_, _) => true,
      onError: (error, stackTrace) {
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    addTearDown(loop.dispose);

    loop.start();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    loop.dispose();

    expect(grants, 3);
  });
}
