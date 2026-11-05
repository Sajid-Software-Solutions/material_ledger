/// R39 Accounts Workspace V2 — per-tab controllers (P6).
///
/// Thin Riverpod controllers over [YorksAccountsWorkspaceRepository]. They keep
/// the last successful projection on screen while a refresh is in flight and
/// recreate (disposing the protected projection) whenever the server-controlled
/// role or the permission epoch changes, mirroring the V1 Accounts controller.
///
/// Widgets never call Supabase: the path stays Widget → controller → repository
/// → RPC. These controllers never show an optimistic success for a critical
/// transition; commands return the server result and the controller re-fetches.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../data/accounts_receivables_repository.dart';
import '../../data/accounts_supplier_repository.dart';
import '../../data/v2/accounts_workspace_repository.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_supplier_models.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claim_workbench_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../accounts_providers.dart';
import '../accounts_receivables_providers.dart';
import '../accounts_supplier_providers.dart';

/// Repository for the V2 RPCs. Null when Supabase is not configured, so the
/// release build stays fail-closed rather than rendering an empty workspace.
final yorksAccountsWorkspaceRepositoryProvider =
    Provider<YorksAccountsWorkspaceRepository?>((ref) {
      final client = ref.watch(yorksAccountsRpcClientProvider);
      return client == null ? null : YorksAccountsWorkspaceRepository(client);
    });

/// Loads and refreshes the Summary workspace projection for one project.
final class YorksAccountsWorkspaceController
    extends StateNotifier<AsyncValue<YorksAccountsWorkspace>> {
  YorksAccountsWorkspaceController({
    required YorksAccountsWorkspaceRepository? repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  final String _projectId;

  /// Full (re)load. Shows the loading state first; used by the initial build
  /// and the error-state Retry action.
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsWorkspace>.loading();
    await _fetch();
  }

  /// Background refresh in response to an authorized Realtime re-fetch signal.
  /// Keeps the current data on screen while the request is in flight.
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsWorkspace>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final workspace = await repository.getWorkspace(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsWorkspace>.data(workspace);
    } catch (error, stackTrace) {
      if (!mounted) return;
      // Keep the last good projection visible beneath the error banner.
      state = AsyncValue<YorksAccountsWorkspace>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsWorkspaceControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsWorkspaceController,
      AsyncValue<YorksAccountsWorkspace>,
      String
    >((ref, projectId) {
      // A navigation change must not discard a confirmed projection, but a
      // role or capability-revision change must. These watches recreate the
      // controller (and drop its protected data) on any authority change.
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsWorkspaceController(
        repository: ref.watch(yorksAccountsWorkspaceRepositoryProvider),
        projectId: projectId,
      );
    });

/// Loads and refreshes the commercial setup behind the Contract tab.
final class YorksAccountsContractController
    extends StateNotifier<AsyncValue<YorksAccountsCommercialSetupRead>> {
  YorksAccountsContractController({
    required YorksAccountsWorkspaceRepository? repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  final String _projectId;

  Future<void> load() async {
    state = const AsyncValue<YorksAccountsCommercialSetupRead>.loading();
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsCommercialSetupRead>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final setup = await repository.getCommercialSetup(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsCommercialSetupRead>.data(setup);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsCommercialSetupRead>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsContractControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsContractController,
      AsyncValue<YorksAccountsCommercialSetupRead>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsContractController(
        repository: ref.watch(yorksAccountsWorkspaceRepositoryProvider),
        projectId: projectId,
      );
    });

/// Loads and refreshes the claim workbench behind the Progress & claims tab.
final class YorksAccountsWorkbenchController
    extends StateNotifier<AsyncValue<YorksAccountsWorkbench>> {
  YorksAccountsWorkbenchController({
    required YorksAccountsWorkspaceRepository? repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  final String _projectId;

  Future<void> load() async {
    state = const AsyncValue<YorksAccountsWorkbench>.loading();
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsWorkbench>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final workbench = await repository.getClaimWorkbench(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsWorkbench>.data(workbench);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsWorkbench>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsWorkbenchControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsWorkbenchController,
      AsyncValue<YorksAccountsWorkbench>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsWorkbenchController(
        repository: ref.watch(yorksAccountsWorkspaceRepositoryProvider),
        projectId: projectId,
      );
    });

/// Loads and refreshes the client invoice tracker behind the Invoices &
/// payments tab. It reuses the existing receivables repository (the invoice
/// list already carries ex/incl VAT, certified, paid, balance and PDC exposure
/// per invoice), so the tab needs no new read.
final class YorksAccountsInvoicesController
    extends StateNotifier<AsyncValue<YorksAccountsInvoicesProjection>> {
  YorksAccountsInvoicesController({
    required YorksAccountsReceivablesRepository repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsReceivablesRepository _repository;
  final String _projectId;

  Future<void> load() async {
    state = const AsyncValue<YorksAccountsInvoicesProjection>.loading();
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    try {
      final projection = await _repository.listInvoices(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsInvoicesProjection>.data(projection);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsInvoicesProjection>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsInvoicesControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsInvoicesController,
      AsyncValue<YorksAccountsInvoicesProjection>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsInvoicesController(
        repository: ref.watch(yorksAccountsReceivablesRepositoryProvider),
        projectId: projectId,
      );
    });

/// Loads and refreshes the supplier bills behind the Supplier bills tab,
/// reusing the existing supplier repository's v1_list_supplier_bills.
final class YorksAccountsSupplierBillsController
    extends StateNotifier<AsyncValue<YorksAccountsSupplierBillsProjection>> {
  YorksAccountsSupplierBillsController({
    required YorksAccountsSupplierRepository repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsSupplierRepository _repository;
  final String _projectId;

  Future<void> load() async {
    state = const AsyncValue<YorksAccountsSupplierBillsProjection>.loading();
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    try {
      final projection = await _repository.listBills(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsSupplierBillsProjection>.data(projection);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsSupplierBillsProjection>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsSupplierBillsControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsSupplierBillsController,
      AsyncValue<YorksAccountsSupplierBillsProjection>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsSupplierBillsController(
        repository: ref.watch(yorksAccountsSupplierRepositoryProvider),
        projectId: projectId,
      );
    });
