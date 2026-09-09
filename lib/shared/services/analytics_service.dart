import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_configuration.dart';
import '../models/analytics_event.dart';
import '../models/yorks_v1_domain_error.dart';

abstract interface class AnalyticsSink {
  Future<void> initialize(AnalyticsConfiguration configuration);

  Future<void> identify({required String userId, required String role});

  Future<void> reset();

  Future<void> capture({
    required String eventName,
    required Map<String, Object> properties,
  });

  Future<void> screen({
    required String screenName,
    required Map<String, Object> properties,
  });

  Future<bool> isFeatureEnabled(String key);
}

class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();

  @override
  Future<void> initialize(AnalyticsConfiguration configuration) async {}

  @override
  Future<void> identify({required String userId, required String role}) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> capture({
    required String eventName,
    required Map<String, Object> properties,
  }) async {}

  @override
  Future<void> screen({
    required String screenName,
    required Map<String, Object> properties,
  }) async {}

  @override
  Future<bool> isFeatureEnabled(String key) async => false;
}

abstract interface class AnalyticsService {
  bool get enabled;

  Future<void> initialize();

  void identify({required String userId, required String role});

  void reset();

  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  });

  void screenViewed(AnalyticsScreen screen);

  AnalyticsOperation beginOperation(
    String operation, {
    AnalyticsProperties properties = const {},
  });

  AnalyticsFeedbackHandle expectFeedback({
    required String action,
    required AnalyticsScreen screen,
    bool operationWasLoading = false,
  });

  void recordActionAttempt({
    required String action,
    required AnalyticsScreen screen,
    required bool operationWasLoading,
  });

  void recordMaterialSearch({
    required int queryLength,
    required int resultCount,
    required Duration duration,
    AnalyticsSearchContext context = AnalyticsSearchContext.materialRequest,
  });

  void recordMaterialSearchSelection();

  Future<bool> isFeatureEnabled(AnalyticsFeatureFlag flag);

  Future<void> drain();
}

final analyticsServiceProvider = Provider<AnalyticsService>(
  (_) => const NoopAnalyticsService(),
);

class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  bool get enabled => false;

  @override
  Future<void> initialize() async {}

  @override
  void identify({required String userId, required String role}) {}

  @override
  void reset() {}

  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) {}

  @override
  void screenViewed(AnalyticsScreen screen) {}

  @override
  AnalyticsOperation beginOperation(
    String operation, {
    AnalyticsProperties properties = const {},
  }) => const _NoopAnalyticsOperation();

  @override
  AnalyticsFeedbackHandle expectFeedback({
    required String action,
    required AnalyticsScreen screen,
    bool operationWasLoading = false,
  }) => const _NoopAnalyticsFeedbackHandle();

  @override
  void recordActionAttempt({
    required String action,
    required AnalyticsScreen screen,
    required bool operationWasLoading,
  }) {}

  @override
  void recordMaterialSearch({
    required int queryLength,
    required int resultCount,
    required Duration duration,
    AnalyticsSearchContext context = AnalyticsSearchContext.materialRequest,
  }) {}

  @override
  void recordMaterialSearchSelection() {}

  @override
  Future<bool> isFeatureEnabled(AnalyticsFeatureFlag flag) async => false;

  @override
  Future<void> drain() async {}
}

class GuardedAnalyticsService implements AnalyticsService {
  GuardedAnalyticsService({
    required AnalyticsConfiguration configuration,
    required AnalyticsSink sink,
    DateTime Function()? now,
    this.repeatedActionWindow = const Duration(seconds: 2),
    this.noFeedbackWindow = const Duration(seconds: 4),
    this.validationLoopWindow = const Duration(minutes: 2),
  }) : _configuration = configuration,
       _sink = sink,
       _now = now ?? DateTime.now;

  static const _maxBacklog = 100;
  static final _safeCategoricalValue = RegExp(r'^[a-zA-Z0-9_.+-]{1,64}$');
  static final _supabaseUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final AnalyticsConfiguration _configuration;
  final AnalyticsSink _sink;
  final DateTime Function() _now;
  final Duration repeatedActionWindow;
  final Duration noFeedbackWindow;
  final Duration validationLoopWindow;
  final List<Future<void> Function()> _backlog = [];
  final Map<String, _RepeatedActionState> _repeatedActions = {};
  final Map<String, _ValidationFailureState> _validationFailures = {};
  final List<_SearchAttempt> _searchAttempts = [];
  Future<void> _serial = Future<void>.value();
  Future<void>? _initialization;
  bool _ready = false;
  bool _transportFailed = false;
  bool _identityInitialized = false;
  String? _identifiedUserId;
  String? _identifiedRole;
  AnalyticsScreen? _currentScreen;
  AnalyticsSearchContext? _activeSearchContext;
  DateTime? _searchSequenceStartedAt;
  DateTime? _lastSearchAttemptAt;
  bool _searchStruggleReported = false;

  @override
  bool get enabled => _configuration.enabled && !_transportFailed;

  @override
  Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;
    final operation = _initializeOnce();
    _initialization = operation;
    return operation;
  }

  Future<void> _initializeOnce() async {
    if (!enabled) {
      _backlog.clear();
      return;
    }
    try {
      await _sink.initialize(_configuration);
      _ready = true;
      final pending = List<Future<void> Function()>.from(_backlog);
      _backlog.clear();
      for (final action in pending) {
        _schedule(action);
      }
    } catch (_) {
      // Analytics can never block authentication or an operational command.
      _transportFailed = true;
      _backlog.clear();
    }
  }

  @override
  void identify({required String userId, required String role}) {
    final normalizedId = userId.trim();
    final normalizedRole = role.trim();
    if (!enabled ||
        !_supabaseUuid.hasMatch(normalizedId) ||
        !_safeCategoricalValue.hasMatch(normalizedRole)) {
      return;
    }
    if (_identityInitialized &&
        _identifiedUserId == normalizedId &&
        _identifiedRole == normalizedRole) {
      return;
    }
    _identityInitialized = true;
    _identifiedUserId = normalizedId;
    _identifiedRole = normalizedRole;
    _submit(() => _sink.identify(userId: normalizedId, role: normalizedRole));
  }

  @override
  void reset() {
    if (!enabled || (_identityInitialized && _identifiedUserId == null)) {
      return;
    }
    // The first unauthenticated render also resets a persisted SDK identity
    // left by an earlier app process.
    _identityInitialized = true;
    _identifiedUserId = null;
    _identifiedRole = null;
    _searchAttempts.clear();
    _activeSearchContext = null;
    _searchSequenceStartedAt = null;
    _lastSearchAttemptAt = null;
    _searchStruggleReported = false;
    _validationFailures.clear();
    _submit(_sink.reset);
  }

  @override
  void capture(
    AnalyticsEvent event, {
    AnalyticsProperties properties = const {},
  }) {
    if (!enabled) return;
    final safe = _properties(properties);
    _submit(() => _sink.capture(eventName: event.wireName, properties: safe));
    if (event == AnalyticsEvent.formValidationFailed) {
      _recordValidationFailure(properties);
    }
  }

  @override
  void screenViewed(AnalyticsScreen screen) {
    if (!enabled || screen == _currentScreen) return;
    _currentScreen = screen;
    final safe = _properties({AnalyticsProperty.screenName: screen.wireName});
    _submit(() => _sink.screen(screenName: screen.wireName, properties: safe));
  }

  @override
  AnalyticsOperation beginOperation(
    String operation, {
    AnalyticsProperties properties = const {},
  }) {
    if (!enabled || !_safeCategoricalValue.hasMatch(operation)) {
      return const _NoopAnalyticsOperation();
    }
    return _GuardedAnalyticsOperation(
      service: this,
      operation: operation,
      startedAt: _now(),
      properties: Map.unmodifiable(properties),
    );
  }

  @override
  AnalyticsFeedbackHandle expectFeedback({
    required String action,
    required AnalyticsScreen screen,
    bool operationWasLoading = false,
  }) {
    if (!enabled || !_safeCategoricalValue.hasMatch(action)) {
      return const _NoopAnalyticsFeedbackHandle();
    }
    recordActionAttempt(
      action: action,
      screen: screen,
      operationWasLoading: operationWasLoading,
    );
    if (operationWasLoading) {
      // A visible loading state is already feedback. Keep the repeat-action
      // signal but do not start a misleading dead-action timer.
      return const _NoopAnalyticsFeedbackHandle();
    }
    return _GuardedAnalyticsFeedbackHandle(
      Timer(noFeedbackWindow, () {
        capture(
          AnalyticsEvent.uiActionNoFeedback,
          properties: {
            AnalyticsProperty.actionType: action,
            AnalyticsProperty.screenName: screen.wireName,
            AnalyticsProperty.operationWasLoading: operationWasLoading,
            AnalyticsProperty.feedbackExpectedMs:
                noFeedbackWindow.inMilliseconds,
          },
        );
      }),
    );
  }

  @override
  void recordActionAttempt({
    required String action,
    required AnalyticsScreen screen,
    required bool operationWasLoading,
  }) {
    if (!enabled || !_safeCategoricalValue.hasMatch(action)) return;
    final now = _now();
    final current = _repeatedActions[action];
    final withinWindow =
        current != null &&
        now.difference(current.firstAt) <= repeatedActionWindow;
    final next = withinWindow
        ? current.copyWith(
            count: current.count + 1,
            operationWasLoading:
                current.operationWasLoading || operationWasLoading,
          )
        : _RepeatedActionState(
            firstAt: now,
            count: 1,
            operationWasLoading: operationWasLoading,
          );
    _repeatedActions[action] = next;
    if (next.count < 3 || next.reported) return;
    _repeatedActions[action] = next.copyWith(reported: true);
    capture(
      AnalyticsEvent.uiRepeatedActionDetected,
      properties: {
        AnalyticsProperty.actionType: action,
        AnalyticsProperty.screenName: screen.wireName,
        AnalyticsProperty.tapCount: next.count,
        AnalyticsProperty.durationMs: now
            .difference(next.firstAt)
            .inMilliseconds,
        AnalyticsProperty.operationWasLoading: next.operationWasLoading,
      },
    );
  }

  @override
  void recordMaterialSearch({
    required int queryLength,
    required int resultCount,
    required Duration duration,
    AnalyticsSearchContext context = AnalyticsSearchContext.materialRequest,
  }) {
    if (!enabled) return;
    final now = _now();
    if (_activeSearchContext != context ||
        (_lastSearchAttemptAt != null &&
            now.difference(_lastSearchAttemptAt!) >
                const Duration(seconds: 30))) {
      _searchAttempts.clear();
      _searchSequenceStartedAt = now;
      _searchStruggleReported = false;
    }
    _activeSearchContext = context;
    _lastSearchAttemptAt = now;
    _searchSequenceStartedAt ??= now;
    _searchAttempts.add(
      _SearchAttempt(resultCount: resultCount, recordedAt: now),
    );
    _searchAttempts.removeWhere(
      (attempt) =>
          now.difference(attempt.recordedAt) > const Duration(seconds: 30),
    );
    capture(
      context == AnalyticsSearchContext.inventory
          ? AnalyticsEvent.inventorySearched
          : AnalyticsEvent.materialSearchCompleted,
      properties: {
        AnalyticsProperty.queryLengthBucket: _queryLengthBucket(queryLength),
        AnalyticsProperty.resultCount: resultCount,
        AnalyticsProperty.durationMs: duration.inMilliseconds,
        AnalyticsProperty.searchContext: context,
      },
    );
    if (context == AnalyticsSearchContext.inventory && resultCount == 0) {
      capture(
        AnalyticsEvent.inventorySearchNoResults,
        properties: {
          AnalyticsProperty.queryLengthBucket: _queryLengthBucket(queryLength),
          AnalyticsProperty.durationMs: duration.inMilliseconds,
          AnalyticsProperty.searchContext: context,
        },
      );
    }

    final noResultCount = _searchAttempts
        .where((attempt) => attempt.resultCount == 0)
        .length;
    final elapsed = now.difference(_searchSequenceStartedAt!);
    final struggling =
        (_searchAttempts.length >= 3 && noResultCount >= 2) ||
        elapsed >= const Duration(seconds: 15);
    if (!struggling || _searchStruggleReported) return;
    _searchStruggleReported = true;
    capture(
      AnalyticsEvent.materialSearchStruggleDetected,
      properties: {
        AnalyticsProperty.attemptCount: _searchAttempts.length,
        AnalyticsProperty.noResultCount: noResultCount,
        AnalyticsProperty.durationMs: elapsed.inMilliseconds,
        AnalyticsProperty.searchContext: context,
      },
    );
  }

  void _recordValidationFailure(AnalyticsProperties properties) {
    final form = properties[AnalyticsProperty.formType];
    final reason = properties[AnalyticsProperty.validationReason];
    final formValue = form is Enum ? analyticsWireName(form) : form?.toString();
    final reasonValue = reason is Enum
        ? analyticsWireName(reason)
        : reason?.toString();
    if (formValue == null || !_safeCategoricalValue.hasMatch(formValue)) return;
    final safeReason =
        reasonValue != null && _safeCategoricalValue.hasMatch(reasonValue)
        ? reasonValue
        : 'unspecified';
    final key = '$formValue:$safeReason';
    final now = _now();
    final current = _validationFailures[key];
    final withinWindow =
        current != null &&
        now.difference(current.firstAt) <= validationLoopWindow;
    final next = withinWindow
        ? current.copyWith(count: current.count + 1)
        : _ValidationFailureState(firstAt: now, count: 1);
    _validationFailures[key] = next;
    if (next.count < 3 || next.reported) return;
    _validationFailures[key] = next.copyWith(reported: true);
    capture(
      AnalyticsEvent.validationLoopDetected,
      properties: {
        AnalyticsProperty.formType: formValue,
        AnalyticsProperty.validationReason: safeReason,
        AnalyticsProperty.attemptCount: next.count,
        AnalyticsProperty.durationMs: now
            .difference(next.firstAt)
            .inMilliseconds,
      },
    );
  }

  @override
  void recordMaterialSearchSelection() {
    _searchAttempts.clear();
    _activeSearchContext = null;
    _searchSequenceStartedAt = null;
    _lastSearchAttemptAt = null;
    _searchStruggleReported = false;
  }

  @override
  Future<bool> isFeatureEnabled(AnalyticsFeatureFlag flag) async {
    if (!enabled || !_ready) return false;
    try {
      final result = await _sink
          .isFeatureEnabled(flag.wireName)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      capture(
        AnalyticsEvent.featureFlagInteracted,
        properties: {
          AnalyticsProperty.featureFlag: flag.wireName,
          AnalyticsProperty.variant: result ? 'enabled' : 'control',
        },
      );
      return result;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> drain() => _serial;

  void _submit(Future<void> Function() action) {
    if (!enabled) return;
    if (!_ready) {
      if (_backlog.length == _maxBacklog) _backlog.removeAt(0);
      _backlog.add(action);
      return;
    }
    _schedule(action);
  }

  void _schedule(Future<void> Function() action) {
    _serial = _serial.then((_) => action()).catchError((Object _) {
      // PostHog transport failures are deliberately non-blocking and do not
      // recursively generate analytics errors.
    });
  }

  Map<String, Object> _properties(AnalyticsProperties values) {
    final safe = <String, Object>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) continue;
      final normalized = _safeValue(value);
      if (normalized != null) safe[entry.key.wireName] = normalized;
    }
    safe[AnalyticsProperty.schemaVersion.wireName] = analyticsSchemaVersion;
    safe[AnalyticsProperty.appVersion.wireName] =
        _safeValue(_configuration.appVersion) ?? 'unknown';
    safe[AnalyticsProperty.appBuild.wireName] =
        _safeValue(_configuration.appBuild) ?? 'unknown';
    safe[AnalyticsProperty.environment.wireName] =
        _configuration.environment.name;
    safe[AnalyticsProperty.platform.wireName] = _configuration.platform.name;
    if (_identifiedRole != null) {
      safe[AnalyticsProperty.role.wireName] = _identifiedRole!;
    }
    if (_currentScreen != null) {
      safe[AnalyticsProperty.screenName.wireName] = _currentScreen!.wireName;
    }
    return Map.unmodifiable(safe);
  }

  Object? _safeValue(Object value) {
    if (value is bool) return value;
    if (value is int && value >= 0) return value;
    if (value is double && value.isFinite && value >= 0) return value;
    if (value is Enum) return analyticsWireName(value);
    if (value is String && _safeCategoricalValue.hasMatch(value)) return value;
    return null;
  }

  static String _queryLengthBucket(int length) => switch (length) {
    <= 0 => 'empty',
    <= 3 => 'short',
    <= 12 => 'medium',
    _ => 'long',
  };
}

abstract interface class AnalyticsOperation {
  void complete({
    bool cached = false,
    int? resultCount,
    AnalyticsProperties properties = const {},
  });

  void fail(Object error, {AnalyticsProperties properties = const {}});
}

class _NoopAnalyticsOperation implements AnalyticsOperation {
  const _NoopAnalyticsOperation();

  @override
  void complete({
    bool cached = false,
    int? resultCount,
    AnalyticsProperties properties = const {},
  }) {}

  @override
  void fail(Object error, {AnalyticsProperties properties = const {}}) {}
}

class _GuardedAnalyticsOperation implements AnalyticsOperation {
  _GuardedAnalyticsOperation({
    required GuardedAnalyticsService service,
    required this.operation,
    required this.startedAt,
    required this.properties,
  }) : _service = service;

  final GuardedAnalyticsService _service;
  final String operation;
  final DateTime startedAt;
  final AnalyticsProperties properties;
  bool _finished = false;

  @override
  void complete({
    bool cached = false,
    int? resultCount,
    AnalyticsProperties properties = const {},
  }) {
    if (_finished) return;
    _finished = true;
    _service.capture(
      AnalyticsEvent.operationCompleted,
      properties: {
        ...this.properties,
        ...properties,
        AnalyticsProperty.operation: operation,
        AnalyticsProperty.durationMs: _service
            ._now()
            .difference(startedAt)
            .inMilliseconds,
        AnalyticsProperty.success: true,
        AnalyticsProperty.cached: cached,
        AnalyticsProperty.resultCount: ?resultCount,
      },
    );
  }

  @override
  void fail(Object error, {AnalyticsProperties properties = const {}}) {
    if (_finished) return;
    _finished = true;
    final category = analyticsErrorCategory(error);
    final durationMs = _service._now().difference(startedAt).inMilliseconds;
    final failureProperties = <AnalyticsProperty, Object?>{
      ...this.properties,
      ...properties,
      AnalyticsProperty.operation: operation,
      AnalyticsProperty.durationMs: durationMs,
      AnalyticsProperty.success: false,
      AnalyticsProperty.errorCategory: category,
      AnalyticsProperty.retryable: _analyticsErrorIsRetryable(category),
      AnalyticsProperty.networkState: category == AnalyticsErrorCategory.offline
          ? 'offline'
          : 'unknown',
    };
    _service.capture(
      AnalyticsEvent.operationCompleted,
      properties: failureProperties,
    );
    _service.capture(
      AnalyticsEvent.reliabilityError,
      properties: failureProperties,
    );
  }
}

abstract interface class AnalyticsFeedbackHandle {
  void feedbackObserved();
}

class _NoopAnalyticsFeedbackHandle implements AnalyticsFeedbackHandle {
  const _NoopAnalyticsFeedbackHandle();

  @override
  void feedbackObserved() {}
}

class _GuardedAnalyticsFeedbackHandle implements AnalyticsFeedbackHandle {
  _GuardedAnalyticsFeedbackHandle(this._timer);

  final Timer _timer;

  @override
  void feedbackObserved() => _timer.cancel();
}

class _RepeatedActionState {
  const _RepeatedActionState({
    required this.firstAt,
    required this.count,
    required this.operationWasLoading,
    this.reported = false,
  });

  final DateTime firstAt;
  final int count;
  final bool operationWasLoading;
  final bool reported;

  _RepeatedActionState copyWith({
    int? count,
    bool? operationWasLoading,
    bool? reported,
  }) => _RepeatedActionState(
    firstAt: firstAt,
    count: count ?? this.count,
    operationWasLoading: operationWasLoading ?? this.operationWasLoading,
    reported: reported ?? this.reported,
  );
}

class _ValidationFailureState {
  const _ValidationFailureState({
    required this.firstAt,
    required this.count,
    this.reported = false,
  });

  final DateTime firstAt;
  final int count;
  final bool reported;

  _ValidationFailureState copyWith({int? count, bool? reported}) =>
      _ValidationFailureState(
        firstAt: firstAt,
        count: count ?? this.count,
        reported: reported ?? this.reported,
      );
}

class _SearchAttempt {
  const _SearchAttempt({required this.resultCount, required this.recordedAt});

  final int resultCount;
  final DateTime recordedAt;
}

AnalyticsErrorCategory analyticsErrorCategory(Object error) {
  if (error is YorksV1DomainException) {
    return switch (error.code) {
      YorksV1DomainErrorCode.invalidInput ||
      YorksV1DomainErrorCode.invalidTransition ||
      YorksV1DomainErrorCode.quantityCapExceeded ||
      YorksV1DomainErrorCode.immutableRecord ||
      YorksV1DomainErrorCode.incompleteReview =>
        AnalyticsErrorCategory.validation,
      YorksV1DomainErrorCode.unauthenticated =>
        AnalyticsErrorCategory.authentication,
      YorksV1DomainErrorCode.unauthorized =>
        AnalyticsErrorCategory.permissionDenied,
      YorksV1DomainErrorCode.offline => AnalyticsErrorCategory.offline,
      YorksV1DomainErrorCode.conflict => AnalyticsErrorCategory.conflict,
      YorksV1DomainErrorCode.insufficientStock =>
        AnalyticsErrorCategory.insufficientStock,
      YorksV1DomainErrorCode.featureDisabled =>
        AnalyticsErrorCategory.featureDisabled,
      YorksV1DomainErrorCode.backendUnavailable =>
        AnalyticsErrorCategory.network,
      YorksV1DomainErrorCode.unexpectedResponse =>
        AnalyticsErrorCategory.database,
      YorksV1DomainErrorCode.serverRejected => AnalyticsErrorCategory.database,
    };
  }
  if (error is TimeoutException) return AnalyticsErrorCategory.timeout;
  if (error is AuthException) return AnalyticsErrorCategory.authentication;
  if (error is StorageException) return AnalyticsErrorCategory.storage;
  return AnalyticsErrorCategory.unknown;
}

bool _analyticsErrorIsRetryable(AnalyticsErrorCategory category) =>
    switch (category) {
      AnalyticsErrorCategory.offline ||
      AnalyticsErrorCategory.network ||
      AnalyticsErrorCategory.timeout ||
      AnalyticsErrorCategory.database => true,
      _ => false,
    };
