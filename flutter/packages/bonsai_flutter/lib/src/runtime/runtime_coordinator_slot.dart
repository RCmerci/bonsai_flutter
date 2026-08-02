enum RuntimeCoordinatorState { empty, starting, active, disposing }

final class RuntimeCoordinatorLease {
  RuntimeCoordinatorLease._();
}

final class RuntimeCoordinatorSlot {
  RuntimeCoordinatorState _state = RuntimeCoordinatorState.empty;
  RuntimeCoordinatorLease? _owner;

  RuntimeCoordinatorLease acquire() {
    if (_state != RuntimeCoordinatorState.empty) {
      throw StateError('A Dart runtime coordinator lease is already active');
    }
    final lease = RuntimeCoordinatorLease._();
    _owner = lease;
    _state = RuntimeCoordinatorState.starting;
    return lease;
  }

  void activate(RuntimeCoordinatorLease lease) {
    _requireOwner(lease, RuntimeCoordinatorState.starting);
    _state = RuntimeCoordinatorState.active;
  }

  void beginDisposal(RuntimeCoordinatorLease lease) {
    _requireOwner(lease, RuntimeCoordinatorState.active);
    _state = RuntimeCoordinatorState.disposing;
  }

  void release(RuntimeCoordinatorLease lease) {
    if (!identical(_owner, lease)) return;
    _owner = null;
    _state = RuntimeCoordinatorState.empty;
  }

  void _requireOwner(
    RuntimeCoordinatorLease lease,
    RuntimeCoordinatorState expected,
  ) {
    if (!identical(_owner, lease) || _state != expected) {
      throw StateError('Coordinator lease does not own the $expected slot');
    }
  }
}

final runtimeCoordinatorSlot = RuntimeCoordinatorSlot();
