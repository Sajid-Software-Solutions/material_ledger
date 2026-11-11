import 'dart:async';

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
    this.retryDelays = const [],
    this.allowStaleFallback = true,
    this.beforeRead,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  }) : assert(maxEntries > 0),
       _delay = delay,
       _now = now ?? DateTime.now;

  final Duration freshCacheDuration;
  final int maxEntries;
  final YorksV1ProtectedReadObserver? onObservation;
  final List<Duration> retryDelays;
  final bool allowStaleFallback;
  final Future<void> Function()? beforeRead;
  final Future<void> Function(Duration)? _delay;
  final DateTime Function() _now;
  final Map<String, _ProtectedReadSlot<T>> _slots = {};
  final Map<Completer<void>, Timer> _retryTimers = {};
  bool _paused = false;
  bool _disposed = false;

  /// Paused projections keep their authorized cache but perform no retry work.
  /// Riverpod calls this when the last screen stops listening.
  void pause() {
    _paused = true;
    for (final entry in _retryTimers.entries.toList(growable: false)) {
      entry.value.cancel();
      if (!entry.key.isCompleted) entry.key.complete();
    }
    _retryTimers.clear();
  }

  void resume() {
    if (!_disposed) _paused = false;
  }

  void dispose() {
    _disposed = true;
    pause();
    _slots.clear();
  }

  bool isStale(String key) =>
      _slots[key]?.hasCachedValue == true && _slots[key]?.stale == true;

  /// Invalidates cached results without starting reads for hidden projections.
  void markAllStale({
    YorksV1ProtectedReadTrigger trigger = YorksV1ProtectedReadTrigger.realtime,
  }) {
    if (_disposed) return;
    for (final key in _slots.keys.toList(growable: false)) {
      markStale(key, trigger: trigger);
    }
  }

  Future<T> load({
    required String key,
    required Future<T> Function() read,
    YorksV1ProtectedReadTrigger trigger =
        YorksV1ProtectedReadTrigger.navigation,
    YorksV1ProtectedReadVisibility visibilityState =
        YorksV1ProtectedReadVisibility.foreground,
  }) {
    if (_disposed || _paused) {
      return Future<T>.error(const YorksV1ProtectedReadCancelled());
    }
    final slot = _slots.putIfAbsent(key, _ProtectedReadSlot<T>.new);
    final effectiveTrigger = slot.pendingTrigger ?? trigger;
    final effectiveVisibility = slot.pendingVisibilityState ?? visibilityState;
    final active = slot.inFlight;
    if (active != null) {
      if (!slot.stale || slot.waitingForRead) {
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
    slot.waitingForRead = beforeRead != null;
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
      final value = await _readWithRetry(() {
        if (slot.waitingForRead) slot.stale = false;
        slot.waitingForRead = false;
        return read();
      });
      if (_disposed) throw const YorksV1ProtectedReadCancelled();
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
      if (error is YorksV1ProtectedReadCancelled) rethrow;
      final canReuseCachedValue = _canReuseCachedValue(error);
      if (canReuseCachedValue) slot.stale = true;
      if (slot.hasCachedValue && canReuseCachedValue && allowStaleFallback) {
        // Returning prior data does not certify a successful refresh. Keep the
        // slot stale so subsequent navigation/manual retry reaches the server.
        slot.stale = true;
        _observe(
          outcome: YorksV1ProtectedReadOutcome.staleFallback,
          trigger: trigger,
          slot: slot,
          visibilityState: visibilityState,
        );
        return slot.cachedValue as T;
      }
      if (!canReuseCachedValue) {
        // A confirmed denial or invalid response ends this record's prior
        // authorization evidence. Later navigation or transport failures must
        // not restore the projection that preceded this failure.
        slot.cachedValue = null;
        slot.hasCachedValue = false;
        slot.cachedAt = null;
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

  Future<T> _readWithRetry(Future<T> Function() read) async {
    var attempt = 0;
    while (true) {
      if (_disposed || _paused) throw const YorksV1ProtectedReadCancelled();
      final gate = beforeRead;
      if (gate != null) await gate();
      if (_disposed || _paused) throw const YorksV1ProtectedReadCancelled();
      try {
        return await read();
      } catch (error) {
        if (!_canReuseCachedValue(error) || attempt >= retryDelays.length) {
          rethrow;
        }
        if (_disposed || _paused) throw const YorksV1ProtectedReadCancelled();
        await _waitForRetry(retryDelays[attempt++]);
      }
    }
  }

  Future<void> _waitForRetry(Duration duration) {
    final customDelay = _delay;
    if (customDelay != null) return customDelay(duration);
    final completion = Completer<void>();
    _retryTimers[completion] = Timer(duration, () {
      _retryTimers.remove(completion);
      completion.complete();
    });
    return completion.future;
  }

  void _observe({
    required YorksV1ProtectedReadOutcome outcome,
    required YorksV1ProtectedReadTrigger trigger,
    required _ProtectedReadSlot<T> slot,
    required YorksV1ProtectedReadVisibility visibilityState,
  }) {
    if (_disposed || _paused) return;
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

/// A projection stopped listening; this is neither an authorization result nor
/// an operation failure and must not be shown as a workflow rejection.
class YorksV1ProtectedReadCancelled implements Exception {
  const YorksV1ProtectedReadCancelled();
}

class _ProtectedReadSlot<T> {
  Future<T>? inFlight;
  Object? inFlightToken;
  Future<T>? trailing;
  bool stale = false;
  bool waitingForRead = false;
  bool hasCachedValue = false;
  T? cachedValue;
  DateTime? cachedAt;
  YorksV1ProtectedReadTrigger? pendingTrigger;
  YorksV1ProtectedReadVisibility? pendingVisibilityState;
  int generation = 0;
}
