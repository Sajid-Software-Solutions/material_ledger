import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_worker_record.dart';
import '../repositories/yorks_v1_worker_record_repository.dart';
import '../services/analytics_service.dart';
import '../sync/connectivity_service.dart';
import 'language_provider.dart';
import 'yorks_v1_feature_flags_provider.dart';
import 'yorks_v1_identity_provider.dart';

final yorksV1WorkerRecordRepositoryProvider =
    Provider<YorksV1WorkerRecordRepository>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return YorksV1SupabaseWorkerRecordRepository(
        featureFlags: ref.watch(yorksV1FeatureFlagsProvider),
        connectivity: ref.watch(connectivityProvider),
        dataClient: client == null
            ? null
            : SupabaseYorksV1WorkerRecordDataClient(client),
        analytics: ref.watch(analyticsServiceProvider),
      );
    });

class YorksV1WorkerRecordsState {
  const YorksV1WorkerRecordsState({
    this.query = const YorksV1WorkerRecordQuery(),
    this.page,
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final YorksV1WorkerRecordQuery query;

  /// The most recent confirmed first page (counts, totals, companies).
  final YorksV1WorkerRecordPage? page;

  /// Every row loaded so far for [query].
  final List<YorksV1WorkerRecord> items;
  final bool isLoading;
  final bool isLoadingMore;
  final YorksV1DomainErrorCode? error;

  bool get hasMore => page != null && items.length < page!.totalCount;
}

/// Register state for the Workers tab. Nothing is shown optimistically: rows
/// appear only after the protected projection returns them.
class YorksV1WorkerRecordsController
    extends StateNotifier<YorksV1WorkerRecordsState> {
  YorksV1WorkerRecordsController(this._repository)
    : super(const YorksV1WorkerRecordsState());

  final YorksV1WorkerRecordRepository _repository;
  int _serial = 0;
  Timer? _searchDebounce;

  Future<void> load() => _loadFirstPage(state.query);

  Future<void> refresh() => _loadFirstPage(state.query);

  void setSearch(String search) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_loadFirstPage(state.query.copyWith(search: search)));
    });
  }

  Future<void> setCompany(String? company) => _loadFirstPage(
    state.query.copyWith(company: company, clearCompany: company == null),
  );

  Future<void> setStatus(YorksV1WorkerStatus? status) => _loadFirstPage(
    state.query.copyWith(status: status, clearStatus: status == null),
  );

  Future<void> _loadFirstPage(YorksV1WorkerRecordQuery query) async {
    final serial = ++_serial;
    final first = query.copyWith(offset: 0);
    state = YorksV1WorkerRecordsState(
      query: first,
      page: state.page,
      items: state.items,
      isLoading: true,
    );
    try {
      final page = await _repository.listRecords(first);
      if (!mounted || serial != _serial) return;
      state = YorksV1WorkerRecordsState(
        query: first,
        page: page,
        items: page.items,
      );
    } on YorksV1DomainException catch (error) {
      if (!mounted || serial != _serial) return;
      // Keep the last confirmed rows visible; a failure is never an empty list.
      state = YorksV1WorkerRecordsState(
        query: first,
        page: state.page,
        items: state.items,
        error: error.code,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final serial = ++_serial;
    final next = state.query.copyWith(offset: state.items.length);
    state = YorksV1WorkerRecordsState(
      query: state.query,
      page: state.page,
      items: state.items,
      isLoadingMore: true,
    );
    try {
      final page = await _repository.listRecords(next);
      if (!mounted || serial != _serial) return;
      final known = {for (final item in state.items) item.workerId};
      state = YorksV1WorkerRecordsState(
        query: state.query,
        page: state.page,
        items: List.unmodifiable([
          ...state.items,
          for (final item in page.items)
            if (known.add(item.workerId)) item,
        ]),
      );
    } on YorksV1DomainException catch (error) {
      if (!mounted || serial != _serial) return;
      state = YorksV1WorkerRecordsState(
        query: state.query,
        page: state.page,
        items: state.items,
        error: error.code,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}

final yorksV1WorkerRecordsControllerProvider =
    StateNotifierProvider.autoDispose<
      YorksV1WorkerRecordsController,
      YorksV1WorkerRecordsState
    >((ref) {
      // A different signed-in person or role must never see cached rows.
      ref.watch(yorksV1AuthUserIdProvider);
      ref.watch(yorksV1CurrentRoleProvider);
      final controller = YorksV1WorkerRecordsController(
        ref.watch(yorksV1WorkerRecordRepositoryProvider),
      );
      unawaited(controller.load());
      return controller;
    });

/// Short-lived signed link for one stored photo.
final yorksV1WorkerPhotoUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, objectPath) {
      ref.watch(yorksV1AuthUserIdProvider);
      return ref
          .watch(yorksV1WorkerRecordRepositoryProvider)
          .photoUrl(objectPath);
    });
