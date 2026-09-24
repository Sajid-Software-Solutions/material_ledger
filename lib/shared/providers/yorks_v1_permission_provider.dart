import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_permission_management.dart';
import '../repositories/yorks_v1_permission_repository.dart';
import '../services/yorks_v1_critical_command_key_store.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';

final yorksV1PermissionRpcClientProvider =
    Provider<YorksV1PermissionRpcClient?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return client == null ? null : SupabaseYorksV1PermissionRpcClient(client);
    });

final yorksV1PermissionRepositoryProvider =
    Provider<YorksV1PermissionRepository>((ref) {
      return YorksV1SupabasePermissionRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        connectivity: ref.watch(connectivityProvider),
        rpcClient: ref.watch(yorksV1PermissionRpcClientProvider),
      );
    });

/// Server-projected role ceiling and target-aware account commands.
///
/// `null` selects create mode. Loading, authorization failure and malformed
/// responses remain [AsyncError]/[AsyncLoading], which connected User
/// Management interprets as no available mutation rather than applying a
/// client-side role hierarchy fallback.
final yorksV1UserAdminOptionsProvider = FutureProvider.autoDispose
    .family<YorksV1UserAdminOptions, String?>((ref, targetAppUserId) {
      // A current-actor permission revision may change the delegation ceiling
      // even while the target remains the same.
      ref.watch(
        yorksV1CurrentPermissionSnapshotProvider.select(
          (state) => state.snapshot?.revision,
        ),
      );
      return ref
          .watch(yorksV1PermissionRepositoryProvider)
          .getUserAdminOptions(targetAppUserId: targetAppUserId);
    });

/// Makes an RLS/RPC-backed projection re-fetch after a confirmed person-
/// permission revision while preserving its prior [AsyncValue] during the
/// refresh. Screens still apply an immediate record-level permission boundary
/// so a revoked row cannot remain visible during the server round trip.
void yorksV1RefreshProtectedProjectionOnPermissionRevision(Ref ref) {
  ref.listen<int?>(
    yorksV1CurrentPermissionSnapshotProvider.select(
      (state) => state.snapshot?.revision,
    ),
    (previous, next) {
      if (previous != null && previous != next) ref.invalidateSelf();
    },
  );
}

class YorksV1CurrentPermissionSnapshotState {
  const YorksV1CurrentPermissionSnapshotState({
    this.snapshot,
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isStale = false,
    this.isRevisionSignalHealthy = false,
    this.error,
    this.stackTrace,
  });

  final YorksV1CurrentPermissionSnapshot? snapshot;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isStale;
  final bool isRevisionSignalHealthy;
  final Object? error;
  final StackTrace? stackTrace;

  bool get hasConfirmedSnapshot => snapshot != null;

  YorksV1DomainErrorCode? get domainErrorCode => error is YorksV1DomainException
      ? (error! as YorksV1DomainException).code
      : null;

  /// A confirmed snapshot remains usable while an ordinary background refresh
  /// is in flight. The protected command still re-authorizes on the server,
  /// and a confirmed revision event pauses writes until replacement authority
  /// arrives. Realtime transport health alone is not authorization.
  bool get isTrustedForWrites =>
      snapshot != null &&
      snapshot!.user.isActive &&
      !isInitialLoading &&
      !isStale &&
      domainErrorCode != YorksV1DomainErrorCode.unauthenticated &&
      domainErrorCode != YorksV1DomainErrorCode.unauthorized;

  bool allows(String capabilityKey, {String? projectId}) =>
      snapshot?.allows(capabilityKey, projectId: projectId) ?? false;

  YorksV1CurrentPermissionSnapshotState copyWith({
    YorksV1CurrentPermissionSnapshot? snapshot,
    bool clearSnapshot = false,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isStale,
    bool? isRevisionSignalHealthy,
    Object? error,
    StackTrace? stackTrace,
    bool clearError = false,
  }) => YorksV1CurrentPermissionSnapshotState(
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isStale: isStale ?? this.isStale,
    isRevisionSignalHealthy:
        isRevisionSignalHealthy ?? this.isRevisionSignalHealthy,
    error: clearError ? null : error ?? this.error,
    stackTrace: clearError ? null : stackTrace ?? this.stackTrace,
  );
}

/// Presentation-only compatibility decision for one capability while Yorks
/// moves from exact-role checks to person-specific permissions one protected
/// consumer at a time.
///
/// A shadow capability deliberately preserves [legacyAllowed]. Its candidate
/// value is parity evidence only and can never grant client access. Once the
/// catalogue marks a capability enforced, only the server-confirmed
/// authoritative projection is considered. Database RLS/RPC checks remain the
/// final authority for every read and command.
class YorksV1HybridPermissionDecision {
  const YorksV1HybridPermissionDecision({
    required this.canRead,
    required this.canWrite,
    required this.authorizationMode,
  });

  const YorksV1HybridPermissionDecision.denied()
    : canRead = false,
      canWrite = false,
      authorizationMode = null;

  final bool canRead;
  final bool canWrite;
  final YorksV1PermissionCapabilityAuthorizationMode? authorizationMode;
}

typedef YorksV1HybridPermissionResolver =
    bool? Function(
      String capabilityKey, {
      required bool legacyAllowed,
      bool requireWrite,
      bool organizationSummary,
      String? projectId,
    });

extension YorksV1HybridPermissionStateAccess
    on YorksV1CurrentPermissionSnapshotState {
  YorksV1HybridPermissionDecision hybridDecision(
    String capabilityKey, {
    required bool legacyAllowed,
    bool organizationSummary = false,
    String? projectId,
  }) {
    final confirmed = snapshot;
    final capability = confirmed?.capability(capabilityKey);
    final usableRead =
        confirmed != null &&
        confirmed.user.isActive &&
        capability != null &&
        capability.catalog.isOperational;
    if (!usableRead) {
      return const YorksV1HybridPermissionDecision.denied();
    }

    final allowed = switch (capability.authorizationMode) {
      // Never read candidateEffective here. In shadow the existing exact-role
      // behavior stays authoritative until the server consumer is cut over.
      YorksV1PermissionCapabilityAuthorizationMode.shadow => legacyAllowed,
      YorksV1PermissionCapabilityAuthorizationMode.enforced =>
        organizationSummary
            ? _allowsOrganizationSummary(confirmed, capability, capabilityKey)
            : confirmed.allows(capabilityKey, projectId: projectId),
    };
    return YorksV1HybridPermissionDecision(
      canRead: allowed,
      // Routine refresh deliberately keeps both navigation and eligible
      // actions steady. A revision signal marks the snapshot stale before its
      // protected replacement is fetched.
      canWrite: allowed && isTrustedForWrites,
      authorizationMode: capability.authorizationMode,
    );
  }

  bool _allowsOrganizationSummary(
    YorksV1CurrentPermissionSnapshot confirmed,
    YorksV1PermissionCapabilityAccess capability,
    String capabilityKey,
  ) {
    if (capabilityKey == YorksV1CapabilityKeys.workforceView) {
      return allowsWorkforceSummary(capabilityKey);
    }
    if (!capability.catalog.requiresProjectAccess) {
      return capability.authoritativeEffective == true;
    }
    // A module entry point is visible when the actor is authoritatively
    // allowed on at least one project they can actually access. An explicit
    // project grant never widens membership and a grant for an inaccessible
    // project therefore remains invisible.
    return confirmed.projectAccess.any(
      (project) =>
          project.hasAccess &&
          confirmed.allows(capabilityKey, projectId: project.projectId),
    );
  }

  /// Workforce responsibility is resolved by its own dated server model, not
  /// technical project membership. A project-scoped grant may therefore open
  /// the module summary even when the capability catalogue deliberately does
  /// not require V1 `project_members` access. The roster RPC remains the
  /// authoritative row filter.
  bool allowsWorkforceSummary(String capabilityKey) {
    final confirmed = snapshot;
    final capability = confirmed?.capability(capabilityKey);
    if (confirmed == null ||
        !confirmed.user.isActive ||
        capability == null ||
        !capability.catalog.isOperational) {
      return false;
    }
    return capability.authoritativeEffective == true ||
        capability.projectOverrides.any(
          (override) => override.authoritativeEffective,
        );
  }

  bool hybridAllows(
    String capabilityKey, {
    required bool legacyAllowed,
    bool requireWrite = false,
    bool organizationSummary = false,
    String? projectId,
  }) {
    final decision = hybridDecision(
      capabilityKey,
      legacyAllowed: legacyAllowed,
      organizationSummary: organizationSummary,
      projectId: projectId,
    );
    return requireWrite ? decision.canWrite : decision.canRead;
  }

  /// Tri-state route decision used while the first protected projection is
  /// loading or temporarily unavailable. `null` means "not decided yet": the
  /// router keeps the browser URL stable and the workspace shell paints only
  /// its neutral verification/retry state. Authentication or authorization
  /// failures remain confirmed denials and never fall back to a role grant.
  bool? hybridRouteAllows(
    String capabilityKey, {
    required bool legacyAllowed,
    bool requireWrite = false,
    bool organizationSummary = false,
    String? projectId,
  }) {
    if (snapshot == null &&
        (isInitialLoading ||
            domainErrorCode == YorksV1DomainErrorCode.offline ||
            domainErrorCode == YorksV1DomainErrorCode.backendUnavailable)) {
      return null;
    }
    return hybridAllows(
      capabilityKey,
      legacyAllowed: legacyAllowed,
      requireWrite: requireWrite,
      organizationSummary: organizationSummary,
      projectId: projectId,
    );
  }
}

typedef YorksV1PermissionRevisionSignalSubscription =
    Future<bool> Function({
      required Future<void> Function() onSignal,
      required void Function(Object? error) onUnavailable,
    });

final yorksV1CurrentPermissionSnapshotProvider =
    StateNotifierProvider<
      YorksV1CurrentPermissionSnapshotController,
      YorksV1CurrentPermissionSnapshotState
    >((ref) {
      final flags = ref.watch(yorksV1FeatureFlagsProvider);
      final authUserId = ref.watch(yorksV1AuthUserIdProvider);
      final exactRole = ref.watch(yorksV1CurrentRoleProvider);
      final client = ref.watch(supabaseClientProvider);
      final enabled =
          flags.foundation &&
          authUserId != null &&
          authUserId.trim().isNotEmpty &&
          exactRole != null &&
          client != null;
      final initialFailure = !flags.foundation
          ? const YorksV1DomainException(YorksV1DomainErrorCode.featureDisabled)
          : authUserId == null || exactRole == null
          ? const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated)
          : client == null
          ? const YorksV1DomainException(
              YorksV1DomainErrorCode.backendUnavailable,
            )
          : null;
      final controller = YorksV1CurrentPermissionSnapshotController(
        enabled: enabled,
        authUserId: authUserId,
        client: client,
        repository: ref.watch(yorksV1PermissionRepositoryProvider),
        initialFailure: initialFailure,
      );
      unawaited(controller.start());
      return controller;
    });

class YorksV1CurrentPermissionSnapshotController
    extends StateNotifier<YorksV1CurrentPermissionSnapshotState>
    with WidgetsBindingObserver {
  YorksV1CurrentPermissionSnapshotController({
    required bool enabled,
    required String? authUserId,
    required SupabaseClient? client,
    required YorksV1PermissionRepository repository,
    YorksV1DomainException? initialFailure,
    YorksV1PermissionRevisionSignalSubscription? revisionSignalSubscription,
    Duration safetyRefreshInterval = const Duration(minutes: 15),
    Duration foregroundRefreshThreshold = const Duration(minutes: 2),
    Duration verificationRetryInterval = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _enabled = enabled,
       _authUserId = authUserId?.trim(),
       _client = client,
       _repository = repository,
       _revisionSignalSubscription = revisionSignalSubscription,
       _safetyRefreshInterval = safetyRefreshInterval,
       _foregroundRefreshThreshold = foregroundRefreshThreshold,
       _verificationRetryInterval = verificationRetryInterval,
       _now = now ?? DateTime.now,
       super(
         YorksV1CurrentPermissionSnapshotState(
           isInitialLoading: enabled,
           error: enabled ? null : initialFailure,
         ),
       );

  final bool _enabled;
  final String? _authUserId;
  final SupabaseClient? _client;
  final YorksV1PermissionRepository _repository;
  final YorksV1PermissionRevisionSignalSubscription?
  _revisionSignalSubscription;
  final Duration _safetyRefreshInterval;
  final Duration _foregroundRefreshThreshold;
  final Duration _verificationRetryInterval;
  final DateTime Function() _now;
  final List<RealtimeChannel> _channels = [];
  final _disposedSignal = Completer<void>();
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _queuedRefreshRequiresFreshAuthority = false;
  Completer<bool>? _initialJoin;
  Timer? _safetyRefreshTimer;
  Timer? _verificationRetryTimer;
  int _verificationRetryAttempt = 0;
  Timer? _assignmentTransitionTimer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _observingLifecycle = false;
  DateTime? _leftForegroundAt;
  bool _revisionSignalHealthy = false;
  int _authorizationGeneration = 0;
  Future<void>? _retryInFlight;

  Future<void> retryVerification() {
    if (_disposed || !_enabled) return Future<void>.value();
    return _retryInFlight ??= _retryVerificationOnce().whenComplete(() {
      _retryInFlight = null;
    });
  }

  Future<void> _retryVerificationOnce() async {
    if (!_revisionSignalHealthy) {
      await _authSubscription?.cancel();
      _authSubscription = null;
      final client = _client;
      if (client != null) {
        for (final channel in _channels) {
          await client.removeChannel(channel);
        }
      }
      _channels.clear();
      _initialJoin = null;
      try {
        _revisionSignalHealthy = await _subscribeToRevisionSignal();
      } catch (error) {
        _markRevisionSignalUnavailable(error);
      }
    }
    if (!_disposed) await refresh(authorityMayHaveChanged: state.isStale);
  }

  Future<void> start() async {
    if (!_enabled || _disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
    final signalJoin = Future.any<bool>([
      _subscribeToRevisionSignal(),
      _disposedSignal.future.then((_) => false),
    ]);

    // Do not hold the first protected projection behind a Realtime join. The
    // snapshot can power actions immediately. The command rechecks authority
    // on the server; a Realtime join is only an invalidation signal.
    await refresh();
    // Poll even when the first RPC failed. Otherwise a simultaneous initial
    // RPC + Realtime outage can strand the app on its verification state until
    // a lifecycle event or manual retry.
    if (!_disposed) _startSafetyRefresh();

    late final bool signalsReady;
    try {
      signalsReady = await signalJoin;
    } catch (error) {
      if (!_disposed) _markRevisionSignalUnavailable(error);
      return;
    }
    if (!signalsReady || _disposed) {
      if (!_disposed && state.error == null) {
        _markRevisionSignalUnavailable(
          const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          ),
        );
      }
      return;
    }
    _revisionSignalHealthy = true;
    // Close the gap between the first RPC and a late channel join. Keep the
    // confirmed action available while this ordinary catch-up read runs; only
    // a real revision event may mark it stale.
    if (state.snapshot == null ||
        state.isStale ||
        !state.isRevisionSignalHealthy) {
      await refresh(authorityMayHaveChanged: state.isStale);
    }
    if (!_disposed) _startSafetyRefresh();
  }

  /// Keeps the prior confirmed snapshot visible while the protected RPC is in
  /// flight, then atomically replaces it. An initial load has no permissions.
  Future<void> refresh({bool authorityMayHaveChanged = false}) async {
    if (!_enabled || _disposed) return;
    if (_refreshing) {
      // Background checks never stack another identical RPC behind the one in
      // flight. A real revision signal queues exactly one authoritative reload
      // and pauses writes until that replacement is confirmed.
      if (authorityMayHaveChanged) {
        _refreshQueued = true;
        _queuedRefreshRequiresFreshAuthority = true;
        final retained = state.snapshot;
        if (retained != null && !state.isStale) {
          state = state.copyWith(isStale: true, isRefreshing: true);
        }
      }
      return;
    }
    _refreshing = true;
    var requireFreshAuthority = authorityMayHaveChanged;
    try {
      do {
        requireFreshAuthority =
            requireFreshAuthority || _queuedRefreshRequiresFreshAuthority;
        _refreshQueued = false;
        _queuedRefreshRequiresFreshAuthority = false;
        final retaining = state.snapshot != null;
        state = state.copyWith(
          isInitialLoading: !retaining,
          isRefreshing: retaining,
          isStale: retaining && (state.isStale || requireFreshAuthority),
          isRevisionSignalHealthy: _revisionSignalHealthy,
          clearError: true,
        );
        final generation = _authorizationGeneration;
        try {
          final snapshot = await _repository.getCurrentSnapshot();
          if (_disposed || generation != _authorizationGeneration) return;
          if (_refreshQueued) continue;
          state = YorksV1CurrentPermissionSnapshotState(
            snapshot: snapshot,
            isStale: false,
            isRevisionSignalHealthy: _revisionSignalHealthy,
          );
          _verificationRetryTimer?.cancel();
          _verificationRetryTimer = null;
          _verificationRetryAttempt = 0;
          _scheduleAssignmentTransition(snapshot);
        } catch (error, stackTrace) {
          if (_disposed || generation != _authorizationGeneration) return;
          if (_refreshQueued) continue;
          final failure = _domainFailure(error);
          final previous = state.snapshot;
          final mustPurge =
              previous == null ||
              failure.code == YorksV1DomainErrorCode.unauthenticated ||
              failure.code == YorksV1DomainErrorCode.unauthorized;
          final retainedAuthorityIsCurrent = !mustPurge && !state.isStale;
          state = YorksV1CurrentPermissionSnapshotState(
            snapshot: mustPurge ? null : previous,
            isStale: !mustPurge && !retainedAuthorityIsCurrent,
            isRevisionSignalHealthy: _revisionSignalHealthy,
            error: failure,
            stackTrace: stackTrace,
          );
          if (mustPurge) {
            _assignmentTransitionTimer?.cancel();
            _assignmentTransitionTimer = null;
          } else if (state.isStale) {
            _scheduleVerificationRetry();
          }
          if (previous == null &&
              failure.code != YorksV1DomainErrorCode.unauthenticated &&
              failure.code != YorksV1DomainErrorCode.unauthorized) {
            _scheduleVerificationRetry();
          }
        }
        requireFreshAuthority = false;
      } while (_refreshQueued && _enabled && !_disposed);
    } finally {
      _refreshing = false;
    }
  }

  /// Used for logout or a confirmed authentication failure. It synchronously
  /// drops every presentation grant.
  void invalidateForAuthorizationFailure([Object? error]) {
    if (_disposed) return;
    _authorizationGeneration++;
    _refreshQueued = false;
    _queuedRefreshRequiresFreshAuthority = false;
    _assignmentTransitionTimer?.cancel();
    _assignmentTransitionTimer = null;
    _verificationRetryTimer?.cancel();
    _verificationRetryTimer = null;
    state = YorksV1CurrentPermissionSnapshotState(
      error: YorksV1DomainException(
        error is YorksV1DomainException
            ? error.code
            : YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      ),
      stackTrace: StackTrace.current,
    );
  }

  void _scheduleVerificationRetry() {
    if (_disposed || !_enabled || _verificationRetryTimer != null) return;
    if (state.snapshot != null && !state.isStale) return;
    final factor =
        1 << (_verificationRetryAttempt > 4 ? 4 : _verificationRetryAttempt);
    _verificationRetryAttempt++;
    _verificationRetryTimer = Timer(_verificationRetryInterval * factor, () {
      _verificationRetryTimer = null;
      unawaited(refresh(authorityMayHaveChanged: state.isStale));
    });
  }

  void _markRevisionSignalUnavailable(Object? error) {
    if (_disposed) return;
    _revisionSignalHealthy = false;
    if (state.domainErrorCode == YorksV1DomainErrorCode.unauthenticated ||
        state.domainErrorCode == YorksV1DomainErrorCode.unauthorized) {
      return;
    }
    final previous = state.snapshot;
    state = YorksV1CurrentPermissionSnapshotState(
      snapshot: previous,
      isStale: state.isStale,
      isRevisionSignalHealthy: false,
      error: YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
        cause: error,
      ),
      stackTrace: StackTrace.current,
    );
    if (previous == null || state.isStale) _scheduleVerificationRetry();
  }

  Future<bool> _subscribeToRevisionSignal() async {
    final injected = _revisionSignalSubscription;
    if (injected != null) {
      final ready = await injected(
        onSignal: () => refresh(authorityMayHaveChanged: true),
        onUnavailable: _markRevisionSignalUnavailable,
      );
      if (ready && !_disposed) _revisionSignalHealthy = true;
      return ready;
    }
    final client = _client;
    final authUserId = _authUserId;
    if (client == null || authUserId == null || authUserId.isEmpty) {
      invalidateForAuthorizationFailure(
        const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
      );
      return false;
    }
    final session = client.auth.currentSession;
    if (session == null ||
        session.accessToken.isEmpty ||
        client.auth.currentUser?.id != authUserId) {
      invalidateForAuthorizationFailure(
        const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
      );
      return false;
    }
    try {
      await client.realtime.setAuth(session.accessToken);
    } catch (error) {
      _markRevisionSignalUnavailable(error);
      return false;
    }
    _authSubscription = client.auth.onAuthStateChange.listen((event) {
      if (_disposed) return;
      final refreshed = event.session;
      if (refreshed == null || refreshed.user.id != authUserId) {
        invalidateForAuthorizationFailure(
          const YorksV1DomainException(YorksV1DomainErrorCode.unauthenticated),
        );
        return;
      }
      if (refreshed.accessToken.isNotEmpty) {
        unawaited(_refreshRealtimeAuth(client, refreshed.accessToken));
      }
    });
    final initialJoin = Completer<bool>();
    _initialJoin = initialJoin;
    final channel = client
        .channel('v1-permission-revision:$authUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'v1_permission_revisions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'auth_user_id',
            value: authUserId,
          ),
          callback: (_) => unawaited(refresh(authorityMayHaveChanged: true)),
        )
        .subscribe((status, error) {
          if (_disposed) return;
          if (status == RealtimeSubscribeStatus.subscribed) {
            final wasJoined = initialJoin.isCompleted;
            final reconnected = !_revisionSignalHealthy;
            _revisionSignalHealthy = true;
            if (!initialJoin.isCompleted) initialJoin.complete(true);
            if (wasJoined && reconnected) {
              unawaited(refresh(authorityMayHaveChanged: state.isStale));
              _startSafetyRefresh();
            }
            return;
          }
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            _markRevisionSignalUnavailable(error);
            if (!initialJoin.isCompleted) initialJoin.complete(false);
          }
        });
    _channels.add(channel);
    return initialJoin.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        if (!initialJoin.isCompleted) initialJoin.complete(false);
        _markRevisionSignalUnavailable(
          TimeoutException('Permission revision signal did not become ready'),
        );
        return false;
      },
    );
  }

  static YorksV1DomainException _domainFailure(Object error) =>
      error is YorksV1DomainException
      ? error
      : YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        );

  Future<void> _refreshRealtimeAuth(
    SupabaseClient client,
    String accessToken,
  ) async {
    try {
      await client.realtime.setAuth(accessToken);
    } catch (error) {
      _markRevisionSignalUnavailable(error);
    }
  }

  void _startSafetyRefresh() {
    if (_disposed || _safetyRefreshTimer != null) return;
    _safetyRefreshTimer = Timer.periodic(
      _safetyRefreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  void _scheduleAssignmentTransition(
    YorksV1CurrentPermissionSnapshot snapshot,
  ) {
    _assignmentTransitionTimer?.cancel();
    _assignmentTransitionTimer = null;
    final transitionAt = snapshot.nextTransitionAt;
    if (_disposed || transitionAt == null) return;

    // Both timestamps come from Postgres, avoiding dependence on a device
    // clock that may be several minutes wrong. A small boundary allowance
    // ensures the follow-up resolver sees the assignment as started/expired.
    final serverDelay = transitionAt.difference(snapshot.generatedAt);
    final delay = serverDelay.isNegative ? Duration.zero : serverDelay;
    _assignmentTransitionTimer = Timer(
      delay + const Duration(milliseconds: 250),
      () => unawaited(refresh(authorityMayHaveChanged: true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      final leftAt = _leftForegroundAt;
      _leftForegroundAt = null;
      final foregroundGap = leftAt == null
          ? Duration.zero
          : _now().difference(leftAt);
      final authorityNeedsRefresh =
          this.state.snapshot == null ||
          this.state.isStale ||
          !_revisionSignalHealthy ||
          foregroundGap >= _foregroundRefreshThreshold;
      if (leftAt != null && authorityNeedsRefresh) {
        unawaited(refresh(authorityMayHaveChanged: this.state.isStale));
      }
      return;
    }
    _leftForegroundAt ??= _now();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshQueued = false;
    _queuedRefreshRequiresFreshAuthority = false;
    if (!_disposedSignal.isCompleted) _disposedSignal.complete();
    _safetyRefreshTimer?.cancel();
    _safetyRefreshTimer = null;
    _verificationRetryTimer?.cancel();
    _verificationRetryTimer = null;
    _assignmentTransitionTimer?.cancel();
    _assignmentTransitionTimer = null;
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    final join = _initialJoin;
    if (join != null && !join.isCompleted) join.complete(false);
    final client = _client;
    if (client != null) {
      for (final channel in _channels) {
        unawaited(client.removeChannel(channel));
      }
    }
    _channels.clear();
    super.dispose();
  }
}

class YorksV1UserPermissionWorkspaceState {
  const YorksV1UserPermissionWorkspaceState({
    this.workspace,
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isSaving = false,
    this.error,
    this.stackTrace,
  });

  final YorksV1UserPermissionWorkspace? workspace;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isSaving;
  final Object? error;
  final StackTrace? stackTrace;

  bool get hasWorkspace => workspace != null;

  YorksV1DomainErrorCode? get domainErrorCode => error is YorksV1DomainException
      ? (error! as YorksV1DomainException).code
      : null;

  bool get isUnauthorized =>
      domainErrorCode == YorksV1DomainErrorCode.unauthorized ||
      domainErrorCode == YorksV1DomainErrorCode.unauthenticated;

  bool get isConflict => domainErrorCode == YorksV1DomainErrorCode.conflict;

  bool get isTrustedForWrites =>
      workspace != null &&
      workspace!.target.isActive &&
      !isInitialLoading &&
      !isRefreshing &&
      !isSaving &&
      error == null;

  YorksV1UserPermissionWorkspaceState copyWith({
    YorksV1UserPermissionWorkspace? workspace,
    bool clearWorkspace = false,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isSaving,
    Object? error,
    StackTrace? stackTrace,
    bool clearError = false,
  }) => YorksV1UserPermissionWorkspaceState(
    workspace: clearWorkspace ? null : workspace ?? this.workspace,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : error ?? this.error,
    stackTrace: clearError ? null : stackTrace ?? this.stackTrace,
  );
}

final yorksV1UserPermissionWorkspaceControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksV1UserPermissionWorkspaceController,
      YorksV1UserPermissionWorkspaceState,
      String
    >((ref, targetAppUserId) {
      final controller = YorksV1UserPermissionWorkspaceController(
        repository: ref.watch(yorksV1PermissionRepositoryProvider),
        targetAppUserId: targetAppUserId,
        commandKeys: YorksV1CriticalCommandKeyStore(
          preferences: ref.watch(sharedPreferencesProvider),
          actorAuthUserId: ref.watch(yorksV1AuthUserIdProvider) ?? '',
        ),
        canIssueCommands: () => ref
            .read(yorksV1CurrentPermissionSnapshotProvider)
            .isTrustedForWrites,
      );
      scheduleMicrotask(controller.load);
      return controller;
    });

/// RLS-protected invalidation for an administrator inspecting another user's
/// access workspace. The target key is the stable `AppUser.id`, matching the
/// revision row and workspace RPC contract. Realtime remains a refresh signal;
/// the protected RPC supplies the complete authoritative replacement.
final yorksV1TargetPermissionRevisionSyncProvider = Provider.autoDispose
    .family<void, String>((ref, targetAppUserId) {
      final target = targetAppUserId.trim();
      final client = ref.watch(supabaseClientProvider);
      if (target.isEmpty || client == null) return;
      final workspaceProvider =
          yorksV1UserPermissionWorkspaceControllerProvider(target);
      final controller = ref.read(workspaceProvider.notifier);
      var disposed = false;
      RealtimeChannel? channel;
      Timer? deferredRefresh;

      void refreshTarget() {
        if (disposed) return;
        // A commit event can arrive before the command response. Wait for that
        // response so an invalidation refresh cannot race the atomic result.
        if (ref.read(workspaceProvider).isSaving) {
          deferredRefresh?.cancel();
          deferredRefresh = Timer(
            const Duration(milliseconds: 500),
            refreshTarget,
          );
          return;
        }
        unawaited(controller.refresh());
      }

      final safetyTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => refreshTarget(),
      );
      scheduleMicrotask(() async {
        if (disposed) return;
        final session = client.auth.currentSession;
        if (session == null || session.accessToken.isEmpty) return;
        try {
          await client.realtime.setAuth(session.accessToken);
          if (disposed) return;
          channel = client
              .channel('v1-target-permission-revision:$target')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'v1_permission_revisions',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'app_user_id',
                  value: target,
                ),
                callback: (_) => refreshTarget(),
              )
              .subscribe((status, error) {
                if (disposed) return;
                if (status == RealtimeSubscribeStatus.subscribed) {
                  // Close the load/subscription race and surface a remote
                  // change immediately when the channel reconnects.
                  refreshTarget();
                }
              });
        } catch (_) {
          // The safety timer remains the read-only fallback. Every mutation is
          // still expected-revision checked by the server transaction.
        }
      });

      ref.onDispose(() {
        disposed = true;
        safetyTimer.cancel();
        deferredRefresh?.cancel();
        final activeChannel = channel;
        if (activeChannel != null) {
          unawaited(client.removeChannel(activeChannel));
        }
      });
    });

class YorksV1UserPermissionWorkspaceController
    extends StateNotifier<YorksV1UserPermissionWorkspaceState> {
  YorksV1UserPermissionWorkspaceController({
    required YorksV1PermissionRepository repository,
    required String targetAppUserId,
    required YorksV1CriticalCommandKeyStore commandKeys,
    bool Function()? canIssueCommands,
  }) : _repository = repository,
       _targetAppUserId = targetAppUserId.trim(),
       _commandKeys = commandKeys,
       _canIssueCommands = canIssueCommands ?? _alwaysAllowCommandAttempt,
       super(const YorksV1UserPermissionWorkspaceState(isInitialLoading: true));

  final YorksV1PermissionRepository _repository;
  final String _targetAppUserId;
  final YorksV1CriticalCommandKeyStore _commandKeys;
  final bool Function() _canIssueCommands;
  int _requestSerial = 0;

  Future<void> load() => _load(retainConfirmed: false);

  Future<void> refresh() => _load(retainConfirmed: true);

  Future<void> _load({required bool retainConfirmed}) async {
    final serial = ++_requestSerial;
    final retaining = retainConfirmed && state.workspace != null;
    state = state.copyWith(
      isInitialLoading: !retaining,
      isRefreshing: retaining,
      clearError: true,
    );
    try {
      final workspace = await _repository.getUserWorkspace(
        targetAppUserId: _targetAppUserId,
      );
      if (!mounted || serial != _requestSerial) return;
      state = YorksV1UserPermissionWorkspaceState(workspace: workspace);
    } catch (error, stackTrace) {
      if (!mounted || serial != _requestSerial) return;
      final failure = _domainFailure(error);
      final mustPurge =
          failure.code == YorksV1DomainErrorCode.unauthenticated ||
          failure.code == YorksV1DomainErrorCode.unauthorized;
      state = state.copyWith(
        clearWorkspace: mustPurge,
        isInitialLoading: false,
        isRefreshing: false,
        error: failure,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> setAssignment({
    required String capabilityKey,
    required YorksV1PermissionAssignmentEffect effect,
    required YorksV1PermissionScope scope,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
    required String reason,
    required int expectedRevision,
  }) async {
    if (!effect.isExplicit) {
      return _rejectInvalidInput();
    }
    final payload = <String, Object?>{
      'capability_key': capabilityKey.trim(),
      'effect': effect.wireValue,
      'scope_kind': scope.kind.wireValue,
      'project_ids': scope.projectIds,
      'effective_from': effectiveFrom?.toUtc().toIso8601String(),
      'effective_until': effectiveUntil?.toUtc().toIso8601String(),
      'reason': reason.trim(),
      'expected_revision': expectedRevision,
    };
    final entityId = [
      _targetAppUserId,
      capabilityKey.trim(),
      scope.kind.wireValue,
      ...scope.projectIds,
    ].join(':');
    return _runCommand(
      operation: 'set_user_permission_assignment',
      entityId: entityId,
      payload: payload,
      expectedRevision: expectedRevision,
      invoke: (idempotencyKey) => _repository.setAssignment(
        YorksV1SetPermissionAssignmentInput(
          targetAppUserId: _targetAppUserId,
          capabilityKey: capabilityKey,
          effect: effect,
          scope: scope,
          effectiveFrom: effectiveFrom,
          effectiveUntil: effectiveUntil,
          reason: reason,
          expectedRevision: expectedRevision,
          idempotencyKey: idempotencyKey,
        ),
      ),
    );
  }

  Future<bool> clearAssignment({
    required String assignmentId,
    required String reason,
    required int expectedRevision,
  }) {
    final payload = <String, Object?>{
      'assignment_id': assignmentId.trim(),
      'reason': reason.trim(),
      'expected_revision': expectedRevision,
    };
    return _runCommand(
      operation: 'clear_user_permission_assignment',
      entityId: '$_targetAppUserId:${assignmentId.trim()}',
      payload: payload,
      expectedRevision: expectedRevision,
      invoke: (idempotencyKey) => _repository.clearAssignment(
        YorksV1ClearPermissionAssignmentInput(
          targetAppUserId: _targetAppUserId,
          assignmentId: assignmentId,
          reason: reason,
          expectedRevision: expectedRevision,
          idempotencyKey: idempotencyKey,
        ),
      ),
    );
  }

  Future<bool> applyChanges({
    required List<YorksV1PermissionChange> changes,
    required String reason,
    required int expectedRevision,
    bool assignOrganizationWorkforceResponsibility = false,
  }) {
    final payload = <String, Object?>{
      'changes': changes
          .map((change) => change.toRpcJson())
          .toList(growable: false),
      'reason': reason.trim(),
      'expected_revision': expectedRevision,
      'assign_organization_workforce_responsibility':
          assignOrganizationWorkforceResponsibility,
    };
    return _runCommand(
      operation: 'apply_user_permission_changes',
      entityId: '$_targetAppUserId:reviewed_batch',
      payload: payload,
      expectedRevision: expectedRevision,
      invoke: (idempotencyKey) {
        final input = YorksV1ApplyPermissionChangesInput(
          targetAppUserId: _targetAppUserId,
          changes: List.unmodifiable(changes),
          reason: reason,
          expectedRevision: expectedRevision,
          idempotencyKey: idempotencyKey,
        );
        if (!assignOrganizationWorkforceResponsibility) {
          return _repository.applyChanges(input);
        }
        final workforceRepository = _repository;
        if (workforceRepository
            is! YorksV1WorkforceAccessPermissionRepository) {
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          );
        }
        return (workforceRepository
                as YorksV1WorkforceAccessPermissionRepository)
            .applyChangesWithWorkforce(
              input: input,
              assignOrganizationResponsibility: true,
            );
      },
    );
  }

  Future<bool> assignWorkforceOrganizationResponsibility({
    required String reason,
    required int expectedRevision,
  }) {
    final payload = <String, Object?>{
      'target_app_user_id': _targetAppUserId,
      'reason': reason.trim(),
      'expected_revision': expectedRevision,
    };
    return _runCommand(
      operation: 'assign_user_workforce_organization',
      entityId: '$_targetAppUserId:workforce:organization',
      payload: payload,
      expectedRevision: expectedRevision,
      invoke: (idempotencyKey) {
        final workforceRepository = _repository;
        if (workforceRepository
            is! YorksV1WorkforceAccessPermissionRepository) {
          throw const YorksV1DomainException(
            YorksV1DomainErrorCode.backendUnavailable,
          );
        }
        return (workforceRepository
                as YorksV1WorkforceAccessPermissionRepository)
            .assignWorkforceOrganizationResponsibility(
              targetAppUserId: _targetAppUserId,
              reason: reason,
              idempotencyKey: idempotencyKey,
            );
      },
    );
  }

  Future<YorksV1PermissionHistoryPage> listHistory({
    int limit = 50,
    DateTime? beforeOccurredAt,
    String? beforeId,
  }) => _repository.listHistory(
    YorksV1PermissionHistoryQuery(
      targetAppUserId: _targetAppUserId,
      limit: limit,
      beforeOccurredAt: beforeOccurredAt,
      beforeId: beforeId,
    ),
  );

  Future<bool> _runCommand({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required int expectedRevision,
    required Future<YorksV1UserPermissionWorkspace> Function(
      String idempotencyKey,
    )
    invoke,
  }) async {
    final confirmed = state.workspace;
    final commandAuthorityHealthy = _canIssueCommands();
    if (confirmed == null ||
        state.isSaving ||
        !commandAuthorityHealthy ||
        expectedRevision != confirmed.revision) {
      return _rejectInvalidInput(
        !commandAuthorityHealthy
            ? const YorksV1DomainException(
                YorksV1DomainErrorCode.backendUnavailable,
              )
            : expectedRevision != confirmed?.revision
            ? const YorksV1DomainException(YorksV1DomainErrorCode.conflict)
            : null,
      );
    }
    state = state.copyWith(isSaving: true, clearError: true);
    String? idempotencyKey;
    try {
      idempotencyKey = await _commandKeys.acquire(
        operation: operation,
        entityId: entityId,
        payload: payload,
      );
      final workspace = await invoke(idempotencyKey);
      await _commandKeys.confirm(
        operation: operation,
        entityId: entityId,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return false;
      // This is the first local state change: it uses only the complete,
      // server-confirmed workspace returned by the trusted transaction.
      state = YorksV1UserPermissionWorkspaceState(workspace: workspace);
      return true;
    } catch (error, stackTrace) {
      if (!mounted) return false;
      final failure = _domainFailure(error);
      if (failure.code == YorksV1DomainErrorCode.conflict) {
        await _reloadAfterConflict(failure, stackTrace);
      } else {
        state = state.copyWith(
          isSaving: false,
          error: failure,
          stackTrace: stackTrace,
        );
      }
      return false;
    }
  }

  Future<void> _reloadAfterConflict(
    YorksV1DomainException conflict,
    StackTrace stackTrace,
  ) async {
    try {
      final fresh = await _repository.getUserWorkspace(
        targetAppUserId: _targetAppUserId,
      );
      if (!mounted) return;
      state = YorksV1UserPermissionWorkspaceState(
        workspace: fresh,
        error: conflict,
        stackTrace: stackTrace,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isSaving: false,
        error: conflict,
        stackTrace: stackTrace,
      );
    }
  }

  bool _rejectInvalidInput([YorksV1DomainException? error]) {
    state = state.copyWith(
      isSaving: false,
      error:
          error ??
          const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput),
      stackTrace: StackTrace.current,
    );
    return false;
  }

  static YorksV1DomainException _domainFailure(Object error) =>
      error is YorksV1DomainException
      ? error
      : YorksV1DomainException(
          YorksV1DomainErrorCode.backendUnavailable,
          cause: error,
        );

  static bool _alwaysAllowCommandAttempt() => true;

  @override
  void dispose() {
    _requestSerial++;
    super.dispose();
  }
}
