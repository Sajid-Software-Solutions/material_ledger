import '../models/yorks_v1_domain_error.dart';

enum YorksV1ProtectedReadOutcome {
  freshFetch,
  coalesced,
  freshCache,
  trailingRefresh,
  staleFallback,
  failed,
}

enum YorksV1ProtectedReadTrigger {
  navigation,
  confirmedCommand,
  realtime,
  realtimeReconnect,
  foregroundResume,
  manualRetry,
}

enum YorksV1ProtectedReadVisibility { foreground }

class YorksV1ProtectedReadObservation {
  const YorksV1ProtectedReadObservation({
    required this.outcome,
    required this.trigger,
    required this.generation,
    required this.visibilityState,
  });

  final YorksV1ProtectedReadOutcome outcome;
  final YorksV1ProtectedReadTrigger trigger;
  final int generation;
  final YorksV1ProtectedReadVisibility visibilityState;

  bool get coalesced => outcome == YorksV1ProtectedReadOutcome.coalesced;

  String get cacheState => switch (outcome) {
    YorksV1ProtectedReadOutcome.freshCache => 'fresh',
    YorksV1ProtectedReadOutcome.staleFallback => 'stale_fallback',
    _ => 'miss',
  };
}

typedef YorksV1ProtectedReadObserver =
    void Function(YorksV1ProtectedReadObservation observation);

/// Coalesces an authority-scoped protected read without weakening its server
/// authorization boundary.
///
/// The owning Riverpod provider must recreate this coordinator whenever the
/// authenticated user, exact role, or confirmed permission revision changes.
/// That keeps the small last-success cache inside one authority scope only.
///
/// A refresh requested while a read is active becomes one trailing read. Any
/// further refresh requests join that trailing read instead of creating a
/// request fan-out. A transient transport failure may reuse the last success;
/// authentication and authorization failures are always surfaced.
class YorksV1ProtectedReadCoordinator<T> {
  YorksV1ProtectedReadCoordinator({
    this.freshCacheDuration = const Duration(seconds: 3),
    this.maxEntries = 32,
    this.onObservation,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       _now = now ?? DateTime.now;

  final Duration freshCacheDuration;
  final int maxEntries;
  final YorksV1ProtectedReadObserver? onObservation;
  final DateTime Function() _now;
  final Map<String, _ProtectedReadSlot<T>> _slots = {};

  Future<T> load({
    required String key,
    required Future<T> Function() read,
    YorksV1ProtectedReadTrigger trigger =
        YorksV1ProtectedReadTrigger.navigation,
    YorksV1ProtectedReadVisibility visibilityState =
        YorksV1ProtectedReadVisibility.foreground,
  }) {
    final slot = _slots.putIfAbsent(key, _ProtectedReadSlot<T>.new);
    final effectiveTrigger = slot.pendingTrigger ?? trigger;
    final effectiveVisibility = slot.pendingVisibilityState ?? visibilityState;
    final active = slot.inFlight;
    if (active != null) {
      if (!slot.stale) {
        _observe(
          outcome: YorksV1ProtectedReadOutcome.coalesced,
          trigger: effectiveTrigger,
          slot: slot,
          visibilityState: effectiveVisibility,
        );
        return active;
      }
      final trailing = slot.trailing;
      if (trailing != null) {
        _observe(
          outcome: YorksV1ProtectedReadOutcome.coalesced,
          trigger: effectiveTrigger,
          slot: slot,
          visibilityState: effectiveVisibility,
        );
        return trailing;
      }
      return slot.trailing = active.then(
        (_) => _start(
          key: key,
          slot: slot,
          read: read,
          trigger: effectiveTrigger,
          visibilityState: effectiveVisibility,
          successOutcome: YorksV1ProtectedReadOutcome.trailingRefresh,
        ),
        onError: (_) => _start(
          key: key,
          slot: slot,
          read: read,
          trigger: effectiveTrigger,
          visibilityState: effectiveVisibility,
          successOutcome: YorksV1ProtectedReadOutcome.trailingRefresh,
        ),
      );
    }

    final cachedAt = slot.cachedAt;
    if (!slot.stale &&
        slot.hasCachedValue &&
        cachedAt != null &&
        _now().difference(cachedAt) <= freshCacheDuration) {
      _observe(
        outcome: YorksV1ProtectedReadOutcome.freshCache,
        trigger: effectiveTrigger,
        slot: slot,
        visibilityState: effectiveVisibility,
      );
      return Future<T>.value(slot.cachedValue as T);
    }
    return _start(
      key: key,
      slot: slot,
      read: read,
      trigger: effectiveTrigger,
      visibilityState: effectiveVisibility,
      successOutcome: YorksV1ProtectedReadOutcome.freshFetch,
    );
  }

  /// Requests fresh server state for [key]. If a read is already active, the
  /// next [load] joins one trailing read after it.
  void markStale(
    String key, {
    YorksV1ProtectedReadTrigger trigger =
        YorksV1ProtectedReadTrigger.confirmedCommand,
    YorksV1ProtectedReadVisibility visibilityState =
        YorksV1ProtectedReadVisibility.foreground,
  }) {
    final slot = _slots.putIfAbsent(key, _ProtectedReadSlot<T>.new);
    slot.stale = true;
    slot.pendingTrigger = trigger;
    slot.pendingVisibilityState = visibilityState;
  }

  Future<T> _start({
    required String key,
    required _ProtectedReadSlot<T> slot,
    required Future<T> Function() read,
    required YorksV1ProtectedReadTrigger trigger,
    required YorksV1ProtectedReadVisibility visibilityState,
    required YorksV1ProtectedReadOutcome successOutcome,
  }) {
    slot.stale = false;
    slot.trailing = null;
    slot.pendingTrigger = null;
    slot.pendingVisibilityState = null;
    slot.generation += 1;
    final token = Object();
    slot.inFlightToken = token;
    late final Future<T> operation;
    operation =
        _run(
          key: key,
          slot: slot,
          read: read,
          trigger: trigger,
          visibilityState: visibilityState,
          successOutcome: successOutcome,
        ).whenComplete(() {
          if (identical(slot.inFlightToken, token)) {
            slot.inFlight = null;
            slot.inFlightToken = null;
          }
          if (!slot.hasCachedValue &&
              slot.inFlight == null &&
              slot.trailing == null &&
              !slot.stale) {
            _slots.remove(key);
          }
        });
    slot.inFlight = operation;
    return operation;
  }

  Future<T> _run({
    required String key,
    required _ProtectedReadSlot<T> slot,
    required Future<T> Function() read,
    required YorksV1ProtectedReadTrigger trigger,
    required YorksV1ProtectedReadVisibility visibilityState,
    required YorksV1ProtectedReadOutcome successOutcome,
  }) async {
    try {
      final value = await read();
      slot.cachedValue = value;
      slot.hasCachedValue = true;
      slot.cachedAt = _now();
      _trimCache(exceptKey: key);
      _observe(
        outcome: successOutcome,
        trigger: trigger,
        slot: slot,
        visibilityState: visibilityState,
      );
      return value;
    } catch (error) {
      if (slot.hasCachedValue && _canReuseCachedValue(error)) {
        _observe(
          outcome: YorksV1ProtectedReadOutcome.staleFallback,
          trigger: trigger,
          slot: slot,
          visibilityState: visibilityState,
        );
        return slot.cachedValue as T;
      }
      _observe(
        outcome: YorksV1ProtectedReadOutcome.failed,
        trigger: trigger,
        slot: slot,
        visibilityState: visibilityState,
      );
      rethrow;
    }
  }

  void _observe({
    required YorksV1ProtectedReadOutcome outcome,
    required YorksV1ProtectedReadTrigger trigger,
    required _ProtectedReadSlot<T> slot,
    required YorksV1ProtectedReadVisibility visibilityState,
  }) {
    onObservation?.call(
      YorksV1ProtectedReadObservation(
        outcome: outcome,
        trigger: trigger,
        generation: slot.generation,
        visibilityState: visibilityState,
      ),
    );
  }

  void _trimCache({required String exceptKey}) {
    while (_slots.length > maxEntries) {
      String? oldestKey;
      DateTime? oldestAt;
      for (final entry in _slots.entries) {
        if (entry.key == exceptKey || entry.value.inFlight != null) continue;
        final candidateAt =
            entry.value.cachedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (oldestAt == null || candidateAt.isBefore(oldestAt)) {
          oldestAt = candidateAt;
          oldestKey = entry.key;
        }
      }
      if (oldestKey == null) return;
      _slots.remove(oldestKey);
    }
  }

  static bool _canReuseCachedValue(Object error) {
    if (error is! YorksV1DomainException) return false;
    return error.code == YorksV1DomainErrorCode.backendUnavailable ||
        error.code == YorksV1DomainErrorCode.offline;
  }
}

class _ProtectedReadSlot<T> {
  Future<T>? inFlight;
  Object? inFlightToken;
  Future<T>? trailing;
  bool stale = false;
  bool hasCachedValue = false;
  T? cachedValue;
  DateTime? cachedAt;
  YorksV1ProtectedReadTrigger? pendingTrigger;
  YorksV1ProtectedReadVisibility? pendingVisibilityState;
  int generation = 0;
}
