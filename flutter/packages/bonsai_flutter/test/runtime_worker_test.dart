import 'dart:isolate';
import 'dart:typed_data';

import 'package:bonsai_flutter/src/runtime/runtime_protocol.dart';
import 'package:bonsai_flutter/src/runtime/runtime_worker.dart';
import 'package:bonsai_flutter_native/bonsai_flutter_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_runtime_native.dart';

final class WorkerHarness {
  WorkerHarness({
    required Iterable<int> clockReadings,
    Iterable<NativeOutput> pumpOutputs = const [],
  }) : native = FakeRuntimeNative(),
       clock = FakeRuntimeMonotonicClock(clockReadings) {
    native.pumpOutputs.addAll(pumpOutputs);
    worker = RuntimeWorker.forTesting(
      nativeRuntime: native,
      monotonicClock: clock,
      emitUpdate: updates.add,
    );
  }

  final FakeRuntimeNative native;
  final FakeRuntimeMonotonicClock clock;
  final List<RuntimeUpdate> updates = [];
  late final RuntimeWorker worker;

  Future<void> send(RuntimeCommand command) => worker.handle(command);
}

NativeOutput cycle({
  required int presentationId,
  required int revision,
  List<int> bytes = const [],
  NativeStatus status = NativeStatus.ok,
  NativeRuntimeErrorCode errorCode = NativeRuntimeErrorCode.none,
  String? errorMessage,
}) => FakeRuntimeNative.successOutput(
  presentationId: presentationId,
  revision: revision,
  bytes: bytes,
  status: status,
  errorCode: errorCode,
  errorMessage: errorMessage,
);

CycleReady onlyCycleReady(WorkerHarness harness) =>
    harness.updates.whereType<CycleReady>().single;

void main() {
  test(
    'first eligible grant performs one pump and enters token barrier',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [
          cycle(presentationId: 1, revision: 1, bytes: [1, 2]),
        ],
      );

      await harness.send(
        const VisibilityChanged(generation: 1, eligible: true),
      );
      await harness.send(const VsyncGranted(1));

      expect(harness.native.calls, hasLength(1));
      final pump = harness.native.calls.single as PumpCall;
      expect(pump.monotonicNowNanoseconds, 10);
      expect(pump.input, isEmpty);
      expect(onlyCycleReady(harness).presentationId, 1);
      expect(harness.worker.state, RuntimeWorkerState.awaitingPresentation);
    },
  );

  test(
    'one hundred grants behind the barrier coalesce without native calls',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [cycle(presentationId: 1, revision: 1)],
      );
      await harness.send(
        const VisibilityChanged(generation: 1, eligible: true),
      );
      await harness.send(const VsyncGranted(1));

      for (var index = 0; index < 100; index += 1) {
        await harness.send(const VsyncGranted(1));
      }

      expect(harness.native.calls.whereType<PumpCall>(), hasLength(1));
      final snapshot = await harness.worker.debugSnapshot();
      expect(snapshot.hasCoalescedGrant, isTrue);
      expect(snapshot.unresolvedPresentationId, 1);
      expect(snapshot.pumpCount, 1);
    },
  );

  test(
    'success acknowledgment is serialized before one coalesced pump',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10, 20, 30],
        pumpOutputs: [
          cycle(presentationId: 1, revision: 1),
          cycle(presentationId: 2, revision: 1),
        ],
      );
      await harness.send(
        const VisibilityChanged(generation: 1, eligible: true),
      );
      await harness.send(const VsyncGranted(1));
      await harness.send(const VsyncGranted(1));

      await harness.send(
        PresentationSucceeded(
          generation: 1,
          presentationId: 1,
          revision: 1,
          events: TransferableTypedData.fromList([
            Uint8List.fromList([9]),
          ]),
        ),
      );

      expect(harness.clock.readCount, 3);
      expect(harness.native.calls, hasLength(3));
      final acknowledgment =
          harness.native.calls[1] as PresentationSucceededCall;
      final followUp = harness.native.calls[2] as PumpCall;
      expect(acknowledgment.monotonicNowNanoseconds, 20);
      expect(followUp.monotonicNowNanoseconds, 30);
      expect(followUp.input, [9]);
      expect(harness.updates.whereType<CycleReady>().first.presentationId, 1);
      expect(harness.updates.whereType<CycleReady>().last.presentationId, 2);
    },
  );

  test(
    'recoverable no-byte pump still emits a token and enters barrier',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [
          cycle(
            presentationId: 4,
            revision: 3,
            status: NativeStatus.recoverableError,
            errorCode: NativeRuntimeErrorCode.staleEvent,
            errorMessage: 'dropped stale input',
          ),
        ],
      );
      await harness.send(
        const VisibilityChanged(generation: 2, eligible: true),
      );
      await harness.send(const VsyncGranted(2));

      final update = onlyCycleReady(harness);
      expect(update.bytes.materialize().asUint8List(), isEmpty);
      expect(update.presentationId, 4);
      expect(update.revision, 3);
      expect(update.recoverableDiagnostic?.code, RuntimeErrorCode.staleEvent);
      expect(harness.worker.state, RuntimeWorkerState.awaitingPresentation);
    },
  );

  test(
    'wrong token and wrong revision reach no acknowledgment native call',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [cycle(presentationId: 4, revision: 3)],
      );
      await harness.send(
        const VisibilityChanged(generation: 2, eligible: true),
      );
      await harness.send(const VsyncGranted(2));
      await harness.send(
        PresentationSucceeded(
          generation: 2,
          presentationId: 5,
          revision: 3,
          events: TransferableTypedData.fromList([Uint8List(0)]),
        ),
      );

      expect(
        harness.native.calls.whereType<PresentationSucceededCall>(),
        isEmpty,
      );
      expect(harness.updates.whereType<RuntimeFatalDiagnostic>(), hasLength(1));
      expect(harness.worker.state, RuntimeWorkerState.terminal);
    },
  );

  test(
    'visibility loss invalidates grants but retains unresolved token',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [cycle(presentationId: 6, revision: 2)],
      );
      await harness.send(
        const VisibilityChanged(generation: 3, eligible: true),
      );
      await harness.send(const VsyncGranted(3));
      await harness.send(const VsyncGranted(3));
      await harness.send(
        const VisibilityChanged(generation: 4, eligible: false),
      );
      final snapshot = await harness.worker.debugSnapshot();

      expect(snapshot.liveGeneration, 4);
      expect(snapshot.eligible, isFalse);
      expect(snapshot.hasCoalescedGrant, isFalse);
      expect(snapshot.unresolvedPresentationId, 6);
      expect(snapshot.pumpCount, 1);
      expect(harness.native.calls.whereType<PumpCall>(), hasLength(1));
    },
  );

  test('retained token rejects an old generation before native call', () async {
    final harness = WorkerHarness(
      clockReadings: [10, 1000],
      pumpOutputs: [cycle(presentationId: 6, revision: 2)],
    );
    await harness.send(const VisibilityChanged(generation: 3, eligible: true));
    await harness.send(const VsyncGranted(3));
    await harness.send(const VisibilityChanged(generation: 4, eligible: false));
    await harness.send(const VisibilityChanged(generation: 5, eligible: true));

    await harness.send(
      PresentationSucceeded(
        generation: 3,
        presentationId: 6,
        revision: 2,
        events: TransferableTypedData.fromList([Uint8List(0)]),
      ),
    );
    expect(
      harness.native.calls.whereType<PresentationSucceededCall>(),
      isEmpty,
    );
    expect(harness.worker.state, RuntimeWorkerState.terminal);
  });

  test('retained token accepts the new live eligible generation', () async {
    final harness = WorkerHarness(
      clockReadings: [10, 1000],
      pumpOutputs: [cycle(presentationId: 6, revision: 2)],
    );
    await harness.send(const VisibilityChanged(generation: 3, eligible: true));
    await harness.send(const VsyncGranted(3));
    await harness.send(const VisibilityChanged(generation: 4, eligible: false));
    await harness.send(const VisibilityChanged(generation: 5, eligible: true));

    await harness.send(
      PresentationSucceeded(
        generation: 5,
        presentationId: 6,
        revision: 2,
        events: TransferableTypedData.fromList([Uint8List(0)]),
      ),
    );
    final call = harness.native.calls
        .whereType<PresentationSucceededCall>()
        .single;
    expect(call.monotonicNowNanoseconds, 1000);
  });

  test('rejection releases the barrier and consumes one live grant', () async {
    final harness = WorkerHarness(
      clockReadings: [10, 20],
      pumpOutputs: [
        cycle(presentationId: 8, revision: 4),
        cycle(presentationId: 9, revision: 5),
      ],
    );
    await harness.send(const VisibilityChanged(generation: 7, eligible: true));
    await harness.send(const VsyncGranted(7));
    await harness.send(const VsyncGranted(7));
    await harness.send(
      const PresentationRejected(
        generation: 7,
        presentationId: 8,
        revision: 4,
        reason: PresentationRejectionReason.decodeFailed,
      ),
    );

    expect(
      harness.native.calls.whereType<PresentationRejectedCall>(),
      hasLength(1),
    );
    expect(harness.native.calls.whereType<PumpCall>(), hasLength(2));
  });

  test('checked stopwatch conversion covers long uptime and int64 edge', () {
    const maxInt64 = 0x7fffffffffffffff;
    final lastValidMicroseconds = maxInt64 ~/ 1000;

    expect(
      checkedNanosecondsFromElapsedMicroseconds(10 * 1000 * 1000),
      10000000000,
    );
    expect(
      checkedNanosecondsFromElapsedMicroseconds(lastValidMicroseconds),
      lastValidMicroseconds * 1000,
    );
    expect(
      () =>
          checkedNanosecondsFromElapsedMicroseconds(lastValidMicroseconds + 1),
      throwsStateError,
    );
    expect(
      () => checkedNanosecondsFromElapsedMicroseconds(-1),
      throwsStateError,
    );
  });

  test(
    'fatal native status emits one terminal update and disposes once',
    () async {
      final harness = WorkerHarness(
        clockReadings: [10],
        pumpOutputs: [
          cycle(
            presentationId: 0,
            revision: 0,
            status: NativeStatus.fatalError,
            errorCode: NativeRuntimeErrorCode.ocamlException,
            errorMessage: 'boom',
          ),
        ],
      );
      await harness.send(
        const VisibilityChanged(generation: 1, eligible: true),
      );
      await harness.send(const VsyncGranted(1));
      await harness.send(const VsyncGranted(1));

      expect(harness.updates.whereType<RuntimeFatalDiagnostic>(), hasLength(1));
      expect(harness.native.disposeCount, 1);
      expect(harness.worker.state, RuntimeWorkerState.terminal);
    },
  );

  test('dispose is exact once and later commands fail synchronously', () async {
    final harness = WorkerHarness(clockReadings: const []);

    await harness.send(const DisposeRuntime());
    await harness.send(const DisposeRuntime());

    expect(harness.native.disposeCount, 1);
    expect(
      () => harness.worker.handle(const VsyncGranted(1)),
      throwsStateError,
    );
  });
}
