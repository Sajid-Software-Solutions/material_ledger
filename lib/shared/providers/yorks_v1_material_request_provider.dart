import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../controllers/yorks_v1_material_request_draft_controller.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_material_request.dart';
import '../models/yorks_v1_material_request_document.dart';
import '../models/yorks_v1_role.dart';
import '../repositories/yorks_v1_material_request_draft_store.dart';
import '../repositories/yorks_v1_material_request_repository.dart';
import '../services/analytics_service.dart';
import '../sync/connectivity_service.dart';
import 'yorks_v1_identity_provider.dart';
import 'yorks_v1_material_request_repository_provider.dart';
import 'yorks_v1_permission_provider.dart';
import 'language_provider.dart';

const _yorksV1MaterialRequestDraftKeyPrefix =
    'yorks_v1_material_request_drafts_v1';

/// Invalidates the device-local draft index when a single editor persists or
/// removes one of its private recovery records.  This is deliberately local
/// state: incomplete drafts are not exposed through server request lists.
final yorksV1MaterialRequestLocalDraftRevisionProvider =
    StateProvider.family<int, String>((ref, ownerAuthUserId) => 0);

final yorksV1MaterialRequestDraftStoreProvider =
    Provider.family<YorksV1MaterialRequestDraftStore, String>((ref, owner) {
      return YorksV1MaterialRequestDraftStore(
        preferences: ref.watch(sharedPreferencesProvider),
        key: '${_yorksV1MaterialRequestDraftKeyPrefix}_$owner',
      );
    });

class YorksV1MaterialRequestDraftKey {
  const YorksV1MaterialRequestDraftKey({
    required this.ownerAuthUserId,
    required this.draftId,
  });

  final String ownerAuthUserId;
  final String draftId;

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialRequestDraftKey &&
      other.ownerAuthUserId == ownerAuthUserId &&
      other.draftId == draftId;

  @override
  int get hashCode => Object.hash(ownerAuthUserId, draftId);
}

final yorksV1MaterialRequestDraftControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksV1MaterialRequestDraftController,
      YorksV1MaterialRequestDraftState,
      YorksV1MaterialRequestDraftKey
    >((ref, key) {
      final store = ref.watch(
        yorksV1MaterialRequestDraftStoreProvider(key.ownerAuthUserId),
      );
      const uuid = Uuid();
      final controller = YorksV1MaterialRequestDraftController(
        retainForDeletion: () {
          final link = ref.keepAlive();
          return link.close;
        },
        ownerAuthUserId: key.ownerAuthUserId,
        draftId: key.draftId,
        store: store,
        repository: ref.watch(yorksV1MaterialRequestRepositoryProvider),
        uuidFactory: uuid.v4,
        analytics: ref.watch(analyticsServiceProvider),
        isCurrentOwner: () =>
            ref.read(yorksV1AuthUserIdProvider) == key.ownerAuthUserId,
        onLocalDraftsChanged: () {
          final revision = ref.read(
            yorksV1MaterialRequestLocalDraftRevisionProvider(
              key.ownerAuthUserId,
            ).notifier,
          );
          revision.state++;
        },
      );
      return controller;
    });

/// Lightweight server-filtered and paginated register projection. Full lines,
/// comments and commercial-capable detail are fetched only after opening one
/// request.
final yorksV1MaterialRequestSummaryPageProvider = FutureProvider.autoDispose
    .family<
      YorksV1MaterialRequestSummaryPage,
      YorksV1MaterialRequestSummaryQuery
    >((ref, query) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase2Repository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestPhase2Repository)
          .listRequestSummaries(query);
    });

/// Role- and project-scoped operational facts used by both the desktop and
/// mobile Material Request registers. The database projection contains only
/// non-commercial workflow timing and quantity aggregates.
final yorksV1MaterialRequestOperationsDashboardProvider = FutureProvider
    .autoDispose
    .family<YorksV1MaterialRequestOperationsDashboard, String?>((
      ref,
      projectId,
    ) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestOperationsRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestOperationsRepository)
          .getOperationsDashboard(projectId: projectId);
    });

/// One bounded request projection for the landing screen. The provider keeps
/// the same permission-revision invalidation contract as the full register,
/// but never downloads request lines or comments.
final yorksV1MaterialRequestOverviewProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequestOverview, int>((ref, limit) async {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      if (ref.watch(supabaseClientProvider) == null) {
        final requests = await ref.watch(
          yorksV1MaterialRequestListProvider(null).future,
        );
        return YorksV1MaterialRequestOverview.fromRequests(
          requests: requests,
          needsAction: requests.where((item) => item.actorCanAct).length,
          limit: limit,
        );
      }
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestOperationsRepository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return await (repository as YorksV1MaterialRequestOperationsRepository)
          .getOverview(limit: limit);
    });

final yorksV1MaterialRequestCommentPageProvider = FutureProvider.autoDispose
    .family<
      YorksV1MaterialRequestCommentPage,
      ({String requestId, DateTime? beforeCreatedAt, String? beforeId})
    >((ref, query) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase2Repository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestPhase2Repository)
          .listComments(
            requestId: query.requestId,
            beforeCreatedAt: query.beforeCreatedAt,
            beforeId: query.beforeId,
          );
    });

final yorksV1MaterialRequestWorkAssignmentProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequestWorkAssignment, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.watch(yorksV1MaterialRequestRealtimeRevisionProvider);
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase2Repository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestPhase2Repository)
          .getWorkAssignment(requestId);
    });

final yorksV1MaterialRequestChangeSummaryProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequestChangeSummary?, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.watch(yorksV1MaterialRequestRealtimeRevisionProvider);
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase2Repository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestPhase2Repository)
          .getChangeSummary(requestId);
    });

/// The owner-scoped index of recoverable, not-yet-server-saved Material
/// Request input.  It is read only by the authenticated owner's register and
/// never substituted for the authoritative server request projection.
final yorksV1MaterialRequestLocalDraftsProvider =
    Provider.family<List<YorksV1MaterialRequestDraft>, String>((
      ref,
      ownerAuthUserId,
    ) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.watch(
        yorksV1MaterialRequestLocalDraftRevisionProvider(ownerAuthUserId),
      );
      final store = ref.watch(
        yorksV1MaterialRequestDraftStoreProvider(ownerAuthUserId),
      );
      final drafts = store
          .readAll()
          .where(
            (draft) =>
                draft.ownerAuthUserId == ownerAuthUserId &&
                draft.serverRecordVersion == 0 &&
                draft.hasRecoverableContent,
          )
          .toList(growable: false);
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return List.unmodifiable(drafts);
    });

/// Cross-device recovery index. The database function is owner-scoped and
/// returns only the authenticated creator's private, unsubmitted drafts.
final yorksV1MaterialRequestPrivateDraftsProvider = FutureProvider.autoDispose
    .family<List<YorksV1PrivateMaterialRequestDraftRecord>, String>((
      ref,
      ownerAuthUserId,
    ) {
      // Local editor persistence is intentionally not a dependency here.
      // Every keystroke updates the device recovery index; coupling that
      // revision to this server index caused a second list RPC after every
      // row edit. Auto-dispose refreshes this projection when the register is
      // reopened, while explicit destructive actions invalidate it directly.
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase2Repository) {
        return const <YorksV1PrivateMaterialRequestDraftRecord>[];
      }
      const uuid = Uuid();
      return (repository as YorksV1MaterialRequestPhase2Repository)
          .listPrivateDrafts(
            ownerAuthUserId: ownerAuthUserId,
            submissionIdempotencyKeyFactory: uuid.v4,
          );
    });

final yorksV1MaterialRequestListProvider = FutureProvider.autoDispose
    .family<List<YorksV1MaterialRequest>, String?>((ref, projectId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      // Realtime never provides a request projection. Keep the current
      // authorized result on screen while a signal asks this provider to
      // refresh in place. Watching the revision as a normal dependency makes
      // Riverpod report a reload and briefly replaces the page with a spinner.
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .listRequests(projectId: projectId);
    });

/// The kind of server event that asks current Material Request projections to
/// refresh. These are deliberately metadata-only reasons: no workflow record,
/// quantity or commercial value travels through Realtime state.
enum YorksV1MaterialRequestRefreshReason {
  materialRequest,
  arrangement,
  dispatch,
  receiptReview,
  deliveryOrder,
  materialReturn,
  subscriptionReconnected,
}

/// Test seam for the recipient-scoped database-change subscription.
///
/// Production subscribes to `v1_notifications`, whose rows contain only an
/// event code and entity identifier. Tests can inject deterministic signals
/// without needing a real WebSocket or treating a locally supplied payload as
/// workflow authority.
typedef YorksV1MaterialRequestRefreshSignalSubscription =
    Future<bool> Function({
      required Future<void> Function(YorksV1MaterialRequestRefreshReason reason)
      onSignal,
      required void Function(Object? error) onUnavailable,
    });

/// A small revision counter, not a Material Request cache.
///
/// Every active Material Request list/detail/document/logistics provider reads
/// this counter and therefore re-runs its existing authorized RPC when a
/// recipient-scoped Realtime event arrives. This is intentionally the only
/// client-side effect of Realtime: trusted RPCs remain the transaction
/// authority and their projections remain the source of record state.
final yorksV1MaterialRequestRealtimeRevisionProvider =
    StateNotifierProvider.autoDispose<
      YorksV1MaterialRequestRealtimeNotifier,
      int
    >((ref) {
      // Watch the app session solely as an invalidation trigger. The channel
      // uses the current Supabase Auth identity below, never the legacy app
      // user ID, to keep its recipient filter aligned with RLS.
      final appSessionId = ref.watch(authSessionProvider);
      final client = ref.watch(supabaseClientProvider);
      final authUserId = client?.auth.currentUser?.id;
      final notifier = YorksV1MaterialRequestRealtimeNotifier(
        enabled:
            appSessionId != null &&
            authUserId != null &&
            authUserId.trim().isNotEmpty &&
            client != null,
        authUserId: authUserId,
        client: client,
        connectivity: ref.watch(connectivityProvider),
      );
      unawaited(notifier.start());
      return notifier;
    });

/// Backwards-compatible mount point for screens that already request a live
/// action queue. Detail/document providers also watch the revision directly,
/// so the subscription remains active on every Material Request route rather
/// than only on the overview screen.
final yorksV1MaterialRequestLiveRefreshProvider = Provider.autoDispose<void>((
  ref,
) {
  ref.watch(yorksV1MaterialRequestRealtimeRevisionProvider);
});

class YorksV1MaterialRequestRealtimeNotifier extends StateNotifier<int>
    with WidgetsBindingObserver {
  YorksV1MaterialRequestRealtimeNotifier({
    required bool enabled,
    required String? authUserId,
    required SupabaseClient? client,
    ConnectivityService? connectivity,
    YorksV1MaterialRequestRefreshSignalSubscription? signalSubscription,
    Duration fallbackInterval = const Duration(seconds: 20),
  }) : _enabled = enabled,
       _authUserId = authUserId,
       _client = client,
       _connectivity = connectivity ?? const _AlwaysOnlineConnectivity(),
       _signalSubscription = signalSubscription,
       _fallbackInterval = fallbackInterval,
       super(0);

  final bool _enabled;
  final String? _authUserId;
  final SupabaseClient? _client;
  final ConnectivityService _connectivity;
  final YorksV1MaterialRequestRefreshSignalSubscription? _signalSubscription;
  final Duration _fallbackInterval;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _fallbackTimer;
  int _fallbackAttempt = 0;
  bool _started = false;
  bool _disposed = false;
  bool _observingLifecycle = false;
  bool _leftForeground = false;

  /// Starts the safe notification signal.
  ///
  /// A successful Realtime channel is the normal refresh path.  The polling
  /// fallback is intentionally reserved for a failed or dropped subscription:
  /// keeping it active next to a healthy socket re-fetched every active
  /// project/request projection on a timer and created unnecessary traffic on
  /// the Overview screen.
  Future<void> start() async {
    if (!_enabled || _disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
    _connectivitySubscription = _connectivity.onChange.listen(
      _onConnectivityChanged,
    );
    final subscription = _signalSubscription ?? _subscribeToNotificationSignals;
    final subscribed = await subscription(
      onSignal: _refreshAuthorizedProjections,
      onUnavailable: _onSignalUnavailable,
    );
    if (_disposed) return;
    // Re-fetch once a channel has joined. That closes the gap between the
    // initial list/detail RPC and a successful subscription registration.
    if (subscribed) {
      _stopFallbackTimer();
      await _refreshAuthorizedProjections(
        YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
      );
    } else {
      _ensureFallbackTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || _disposed) return;
    if (state == AppLifecycleState.resumed) {
      final wasBackgrounded = _leftForeground;
      _leftForeground = false;
      if (wasBackgrounded) {
        unawaited(
          _refreshAuthorizedProjections(
            YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
          ),
        );
      }
      if (_fallbackTimer == null) _ensureFallbackTimer();
      return;
    }
    _leftForeground = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// Maps an already RLS-filtered notification envelope to a refresh only.
  /// Unknown operational events are intentionally ignored so unrelated legacy
  /// notifications cannot cause the Material Request workspace to churn.
  static YorksV1MaterialRequestRefreshReason? reasonFromNotification(
    Map<String, dynamic> notification,
  ) {
    final entityType = notification['entity_type']?.toString().trim();
    return switch (entityType) {
      'material_request' || 'company_material_request' =>
        YorksV1MaterialRequestRefreshReason.materialRequest,
      'procurement_arrangement' =>
        YorksV1MaterialRequestRefreshReason.arrangement,
      'material_dispatch' => YorksV1MaterialRequestRefreshReason.dispatch,
      'receipt_review' => YorksV1MaterialRequestRefreshReason.receiptReview,
      'delivery_order' => YorksV1MaterialRequestRefreshReason.deliveryOrder,
      'material_return' => YorksV1MaterialRequestRefreshReason.materialReturn,
      _ => null,
    };
  }

  Future<bool> _subscribeToNotificationSignals({
    required Future<void> Function(YorksV1MaterialRequestRefreshReason reason)
    onSignal,
    required void Function(Object? error) onUnavailable,
  }) async {
    final client = _client;
    final authUserId = _authUserId?.trim();
    if (client == null || authUserId == null || authUserId.isEmpty) {
      return false;
    }
    try {
      // Postgres Changes authorizes against the channel JWT. Reset it after a
      // token refresh too, so a channel never relies on an expired identity.
      final token = client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return false;
      await client.realtime.setAuth(token);
      _authSubscription = client.auth.onAuthStateChange.listen((event) {
        final refreshedToken = event.session?.accessToken;
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          unawaited(client.realtime.setAuth(refreshedToken));
        }
      });

      final joined = Completer<bool>();
      final channel = client
          .channel('yorks-v1-material-request-refresh:$authUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'v1_notifications',
            // RLS is the security boundary. The filter narrows the received
            // envelope even further so an Admin browser never consumes other
            // users' notification rows merely to refresh its own projection.
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_auth_user_id',
              value: authUserId,
            ),
            callback: (payload) {
              final reason = reasonFromNotification(payload.newRecord);
              if (reason != null) unawaited(onSignal(reason));
            },
          )
          .subscribe((status, error) {
            if (_disposed) return;
            if (status == RealtimeSubscribeStatus.subscribed) {
              _stopFallbackTimer();
              if (!joined.isCompleted) {
                joined.complete(true);
              } else {
                // A reconnect may have missed a notification; re-fetch the
                // projection instead of trying to replay any local state.
                unawaited(
                  onSignal(
                    YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
                  ),
                );
              }
              return;
            }
            onUnavailable(error);
            if (!joined.isCompleted) joined.complete(false);
          });
      _channel = channel;
      return await joined.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          onUnavailable(
            TimeoutException(
              'Material Request Realtime subscription timed out',
            ),
          );
          return false;
        },
      );
    } catch (error) {
      onUnavailable(error);
      return false;
    }
  }

  Future<void> _refreshAuthorizedProjections(
    YorksV1MaterialRequestRefreshReason _,
  ) async {
    if (!_enabled || _disposed || _leftForeground) return;
    // This revision contains no server domain data. Every dependant uses it
    // only to issue its normal RLS-protected repository read.
    state += 1;
  }

  void _onSignalUnavailable(Object? _) {
    if (_disposed) return;
    _channelIsHealthy = false;
    _ensureFallbackTimer();
    // Deliberately do not synthesize a workflow error or stale transition
    // from a dropped socket. The fallback issues the same authorized read.
  }

  void _ensureFallbackTimer() {
    if (_disposed ||
        _leftForeground ||
        !_connectivity.isOnline ||
        _fallbackTimer != null ||
        _channelIsHealthy) {
      return;
    }
    final shift = _fallbackAttempt.clamp(0, 4);
    final delay = Duration(
      milliseconds: (_fallbackInterval.inMilliseconds * (1 << shift)).clamp(
        1,
        const Duration(minutes: 5).inMilliseconds,
      ),
    );
    _fallbackTimer = Timer(delay, () {
      _fallbackTimer = null;
      _fallbackAttempt++;
      _refreshFromFallback();
    });
  }

  bool _channelIsHealthy = false;

  /// A dropped socket should not turn a definitely-offline device into a
  /// repeating authorized-RPC loop. Connectivity is only a transport hint;
  /// every refresh still reads the normal server-authorized projection.
  void _refreshFromFallback() {
    if (!_connectivity.isOnline || _leftForeground || _disposed) return;
    unawaited(
      _refreshAuthorizedProjections(
        YorksV1MaterialRequestRefreshReason.subscriptionReconnected,
      ),
    );
    _ensureFallbackTimer();
  }

  /// Once connectivity returns, one refresh closes the stale-data window
  /// without waiting for the next fallback interval. A healthy Realtime
  /// channel already handles its own reconnect and has no fallback timer.
  void _onConnectivityChanged(bool online) {
    if (!online) {
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      return;
    }
    if (_disposed || _channelIsHealthy) return;
    _refreshFromFallback();
  }

  void _stopFallbackTimer() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _fallbackAttempt = 0;
    _channelIsHealthy = true;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _stopFallbackTimer();
    unawaited(_authSubscription?.cancel() ?? Future<void>.value());
    unawaited(_connectivitySubscription?.cancel() ?? Future<void>.value());
    final channel = _channel;
    final client = _client;
    if (channel != null && client != null) {
      unawaited(client.removeChannel(channel));
    }
    _channel = null;
    super.dispose();
  }
}

/// Keeps direct notifier tests and non-Riverpod callers transport-neutral.
/// Production always injects [connectivityProvider] above.
class _AlwaysOnlineConnectivity implements ConnectivityService {
  const _AlwaysOnlineConnectivity();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onChange => const Stream<bool>.empty();
}

/// Whether a request belongs in the signed-in role's action queue.
///
/// The owner role comes from the server projection, never from an editable
/// client field. Admin sees the active workflow queue for oversight; ordinary
/// roles see only requests currently owned by their exact V1 role.
bool yorksV1MaterialRequestNeedsAction(
  YorksV1MaterialRequest request,
  YorksV1Role? role,
) {
  if (role == null || request.state.isDraft) return false;
  if (request.state == YorksV1MaterialRequestState.closed ||
      request.state == YorksV1MaterialRequestState.cancelled) {
    return false;
  }
  if (role == YorksV1Role.admin) return true;
  if (request.currentActionOwnerRole == 'project_engineer' &&
      role.isGlobalProjectEngineer) {
    return true;
  }
  return request.currentActionOwnerRole == role.claimValue;
}

final yorksV1MaterialRequestDraftProjectsProvider =
    FutureProvider.autoDispose<List<YorksV1MaterialRequestProjectOption>>((
      ref,
    ) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .listDraftProjects();
    });

final yorksV1MaterialRequestScopesProvider = FutureProvider.autoDispose
    .family<List<YorksV1MaterialRequestScopeOption>, String>((ref, projectId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .listScopes(projectId);
    });

final yorksV1MaterialRequestMentionCandidatesProvider = FutureProvider
    .autoDispose
    .family<List<YorksV1MaterialRequestMention>, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .listMentionCandidates(requestId);
    });

class YorksV1MaterialRequestInventorySearchKey {
  const YorksV1MaterialRequestInventorySearchKey({
    required this.projectId,
    required this.scopeId,
    required this.query,
  });

  final String projectId;
  final String scopeId;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialRequestInventorySearchKey &&
      other.projectId == projectId &&
      other.scopeId == scopeId &&
      other.query == query;

  @override
  int get hashCode => Object.hash(projectId, scopeId, query);
}

final yorksV1MaterialRequestInventorySearchProvider = FutureProvider.autoDispose
    .family<
      List<YorksV1MaterialRequestInventorySuggestion>,
      YorksV1MaterialRequestInventorySearchKey
    >((ref, key) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .searchInventory(
            projectId: key.projectId,
            scopeId: key.scopeId,
            query: key.query,
          );
    });

final yorksV1MaterialRequestDetailProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequest, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .getRequest(requestId);
    });

final yorksV1MaterialRequestPhase3PolicyProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequestPhase3Policy, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      final repository = ref.watch(yorksV1MaterialRequestRepositoryProvider);
      if (repository is! YorksV1MaterialRequestPhase3Repository) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.featureDisabled,
        );
      }
      return (repository as YorksV1MaterialRequestPhase3Repository)
          .getPhase3Policy(requestId);
    });

final yorksV1MaterialRequestDocumentProvider = FutureProvider.autoDispose
    .family<YorksV1MaterialRequestDocumentModel, String>((ref, requestId) {
      yorksV1RefreshProtectedProjectionOnPermissionRevision(ref);
      ref.listen<int>(yorksV1MaterialRequestRealtimeRevisionProvider, (
        previous,
        next,
      ) {
        if (previous != null && previous != next) ref.invalidateSelf();
      });
      return ref
          .watch(yorksV1MaterialRequestRepositoryProvider)
          .getDocumentModel(requestId);
    });
