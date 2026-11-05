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

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../data/accounts_receivables_repository.dart';
import '../../data/accounts_records_repository.dart';
import '../../data/accounts_supplier_repository.dart';
import '../../data/v2/accounts_workspace_repository.dart';
import '../../data/v2/client_invoice_document_builder.dart';
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_records_models.dart';
import '../../domain/accounts_supplier_inputs.dart';
import '../../domain/accounts_supplier_models.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claim_workbench_models.dart';
import '../../domain/v2/commercial_setup_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../accounts_providers.dart';
import '../accounts_receivables_providers.dart';
import '../accounts_records_providers.dart';
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

  /// Saves the edited commercial setup. There is no optimistic success: the
  /// server is authoritative, and on success we re-fetch the confirmed values.
  /// Returns null on success or an error message. Concurrency is guarded by the
  /// expected profile version (a stale save is rejected); each attempt carries a
  /// fresh idempotency key, so an automatic retry is not yet a persisted replay
  /// (a follow-up can thread YorksV1CriticalCommandKeyStore like the V1 flow).
  Future<String?> saveSetup({
    required YorksAccountsCommercialSetup setup,
    int? expectedProfileVersion,
    String? note,
  }) async {
    final repository = _repository;
    if (repository == null) return 'accounts_backend_unavailable';
    try {
      await repository.saveCommercialSetup(
        projectId: _projectId,
        expectedProfileVersion: expectedProfileVersion,
        setup: setup.toSetupJson(),
        note: note,
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
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
    required YorksAccountsReceivablesRepository receivablesRepository,
    required String projectId,
  }) : _repository = repository,
       _receivables = receivablesRepository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  final YorksAccountsReceivablesRepository _receivables;
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

  /// Submits the open draft claim to accounts (Mark checked: draft ->
  /// ready_for_accounts). No optimistic success; re-fetches on confirmation.
  Future<String?> markChecked({
    required String claimId,
    required int expectedVersion,
    required String reason,
  }) async {
    try {
      await _receivables.submitClaimToAccounts(
        YorksAccountsEntityActionInput(
          projectId: _projectId,
          entityId: claimId,
          expectedVersion: expectedVersion,
          reason: reason,
        ),
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
    }
  }

  /// Reopens a checked claim back to draft. No optimistic success: on the
  /// server's confirmation the workbench is re-fetched. Returns null on success
  /// or an error message (a version conflict is resolved by the reload).
  Future<String?> reopenClaim({
    required String claimId,
    required int expectedVersion,
    required String reason,
  }) async {
    final repository = _repository;
    if (repository == null) return 'accounts_backend_unavailable';
    try {
      await repository.reopenClaim(
        projectId: _projectId,
        claimId: claimId,
        expectedVersion: expectedVersion,
        reason: reason,
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
    }
  }

  /// Confirms the edited progress percentages and rebuilds the single open
  /// draft claim in one transaction (v1_save_claim_workbench). No optimistic
  /// success: the workbench is re-fetched on the server's confirmation. The
  /// server requires at least one evidence document for any increase.
  Future<String?> saveWorkbench({
    String? claimReference,
    required String periodStart,
    required String periodEnd,
    required List<Map<String, Object?>> entries,
    required List<String> evidenceDocumentIds,
    String? reason,
  }) async {
    final repository = _repository;
    if (repository == null) return 'accounts_backend_unavailable';
    try {
      await repository.saveClaimWorkbench(
        projectId: _projectId,
        claimReference: claimReference,
        periodStart: periodStart,
        periodEnd: periodEnd,
        entries: entries,
        evidenceDocumentIds: evidenceDocumentIds,
        reason: reason,
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
    }
  }

  /// Issues the client invoice for a checked claim (allocates the number,
  /// submits and freezes the document snapshot server-side). Re-fetches on
  /// confirmation; the idempotency key makes a retry a no-op.
  Future<String?> issueInvoice({
    required String claimId,
    required int expectedClaimVersion,
    required String invoiceDate,
    required String submissionDate,
    String? invoiceReference,
  }) async {
    final repository = _repository;
    if (repository == null) return 'accounts_backend_unavailable';
    try {
      await repository.issueInvoice(
        projectId: _projectId,
        claimId: claimId,
        expectedClaimVersion: expectedClaimVersion,
        invoiceReference: invoiceReference,
        invoiceDate: invoiceDate,
        submissionDate: submissionDate,
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
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
        receivablesRepository: ref.watch(
          yorksAccountsReceivablesRepositoryProvider,
        ),
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
    required YorksAccountsWorkspaceRepository? workspaceRepository,
    required String projectId,
  }) : _repository = repository,
       _workspace = workspaceRepository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsReceivablesRepository _repository;
  final YorksAccountsWorkspaceRepository? _workspace;
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

  /// Records client certification for an invoice. No optimistic success: the
  /// tracker is re-fetched on the server's confirmation. Returns null on
  /// success or an error message (a version conflict resolves on reload).
  Future<String?> certify(YorksAccountsCertificationInput input) async {
    try {
      await _repository.recordCertification(
        input,
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
    }
  }

  /// Records a client payment (bank transfer or cash) against an invoice.
  Future<String?> pay(YorksAccountsPaymentInput input) async {
    try {
      await _repository.recordPayment(input, idempotencyKey: const Uuid().v4());
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
    }
  }

  /// Fetches the frozen invoice document snapshot and renders the tax-invoice
  /// PDF. Returns the bytes, or null if the backend is unavailable or the
  /// fetch/build fails (the caller shows a failure message). Pure read — it
  /// never mutates state.
  Future<Uint8List?> buildInvoicePdf(String invoiceId) async {
    final workspace = _workspace;
    if (workspace == null) return null;
    try {
      final doc = await workspace.getInvoiceDocument(_projectId, invoiceId);
      return await YorksClientInvoiceDocumentBuilder.build(doc.document);
    } catch (_) {
      return null;
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
        workspaceRepository: ref.watch(
          yorksAccountsWorkspaceRepositoryProvider,
        ),
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

  /// Approves a draft supplier bill (draft -> approved), after which payments
  /// can be recorded. No optimistic success; re-fetches on confirmation.
  Future<String?> approveBill({
    required String supplierBillId,
    required int expectedVersion,
  }) async {
    try {
      await _repository.approveBill(
        YorksAccountsSupplierBillApprovalInput(
          projectId: _projectId,
          supplierBillId: supplierBillId,
          expectedVersion: expectedVersion,
          adminExceptionReason: null,
        ),
        idempotencyKey: const Uuid().v4(),
      );
      await load();
      return null;
    } catch (error) {
      await refresh();
      return error.toString();
    }
  }

  /// Records a payment against an approved supplier bill. No optimistic
  /// success: the bills list is re-fetched on the server's confirmation.
  Future<String?> recordPayment(YorksAccountsSupplierPaymentInput input) async {
    try {
      await _repository.recordPayment(input, idempotencyKey: const Uuid().v4());
      await load();
      return null;
    } catch (error) {
      // Re-fetch so a version conflict (or any failure) leaves the current
      // server state on screen rather than the stale pre-command projection.
      await refresh();
      return error.toString();
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

/// Loads and refreshes the accounts activity behind the History & files tab,
/// reusing the existing records repository's v1_get_accounts_activity.
final class YorksAccountsHistoryController
    extends StateNotifier<AsyncValue<YorksAccountsActivityProjection>> {
  YorksAccountsHistoryController({
    required YorksAccountsRecordsRepository repository,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsRecordsRepository _repository;
  final String _projectId;

  Future<void> load() async {
    state = const AsyncValue<YorksAccountsActivityProjection>.loading();
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    try {
      final projection = await _repository.getActivity(
        _projectId,
        const YorksAccountsActivityFilters(limit: 50),
      );
      if (!mounted) return;
      state = AsyncValue<YorksAccountsActivityProjection>.data(projection);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsActivityProjection>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }
}

final yorksAccountsHistoryControllerProvider = StateNotifierProvider.autoDispose
    .family<
      YorksAccountsHistoryController,
      AsyncValue<YorksAccountsActivityProjection>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsHistoryController(
        repository: ref.watch(yorksAccountsRecordsRepositoryProvider),
        projectId: projectId,
      );
    });
