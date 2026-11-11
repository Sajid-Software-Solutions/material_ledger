import 'dart:async';

/// Gives consequential writes priority over new noncritical register reads.
///
/// A lease covers the bounded command attempt and its immediate reconciliation,
/// never an indefinitely unknown outcome. Already-running reads are not cancelled.
class YorksV1ReadActivityGate {
  int _leases = 0;
  bool _disposed = false;
  Completer<void>? _idle;
  final Map<Object, void Function()> _pending = {};
  bool _scheduled = false;

  bool get isActive => !_disposed && _leases > 0;

  void Function() begin() {
    if (_disposed) return () {};
    _leases++;
    _idle ??= Completer<void>();
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      _leases--;
      if (_leases == 0) {
        _idle?.complete();
        _idle = null;
        _schedulePending();
      }
    };
  }

  Future<void> waitForIdle() async {
    // A second command may begin before a waiting reader gets its microtask.
    while (isActive) {
      await _idle!.future;
    }
  }

  /// Realtime and command invalidations for one projection share one refresh.
  /// Callers cancel their key on disposal, and must retain the normal authority
  /// checks in the provider they invalidate.
  void whenIdle(Object key, void Function() refresh) {
    if (_disposed) return;
    _pending[key] = refresh;
    _schedulePending();
  }

  void cancel(Object key) => _pending.remove(key);

  void _schedulePending() {
    if (_scheduled || isActive || _disposed || _pending.isEmpty) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed || isActive) return;
      final pending = List<void Function()>.of(_pending.values);
      _pending.clear();
      for (final refresh in pending) {
        refresh();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _idle?.complete();
    _idle = null;
  }
}
