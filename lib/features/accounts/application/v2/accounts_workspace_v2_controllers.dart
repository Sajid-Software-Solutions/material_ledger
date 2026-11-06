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

import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/providers/language_provider.dart'
    show sharedPreferencesProvider;
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/services/yorks_v1_critical_command_key_store.dart';
import '../../data/accounts_receivables_repository.dart';
import '../../data/accounts_records_repository.dart';
import '../../data/accounts_supplier_repository.dart';
import '../../data/v2/accounts_workspace_repository.dart';
import '../../data/v2/client_invoice_document_builder.dart';
import '../../domain/accounts_models.dart' show YorksAccountsBaselineProjection;
import '../../domain/accounts_receivables_inputs.dart';
import '../../domain/accounts_receivables_models.dart';
import '../../domain/accounts_records_models.dart';
import '../../domain/accounts_supplier_inputs.dart';
import '../../domain/accounts_supplier_models.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claim_workbench_models.dart';
import '../../domain/v2/claims_list_models.dart';
import '../../domain/v2/commercial_setup_models.dart';
import '../../domain/v2/variations_models.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import '../../domain/v2/pdc_register_models.dart';
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

/// Builds the per-actor critical-command key store (persisted idempotency
/// leases) from the same inputs the V1 Accounts controller uses.
YorksV1CriticalCommandKeyStore _commandKeys(Ref ref) =>
    YorksV1CriticalCommandKeyStore(
      preferences: ref.watch(sharedPreferencesProvider),
      actorAuthUserId: ref.watch(yorksV1AuthUserIdProvider) ?? '',
    );

/// The reason a command failed: the server's own code when it sent one (read by
/// `accountsV2ErrorText`), otherwise the domain category.
String _commandFailureCode(Object error) => error is YorksV1DomainException
    ? (error.serverMessage ?? error.code.name)
    : YorksV1DomainErrorCode.serverRejected.name;

/// Shared command runner for the editable V2 controllers. It wraps a critical
/// command in a persisted idempotency lease (so a retry after an ambiguous
/// failure replays the same server key), re-fetches the confirmed projection on
/// success, and re-fetches current state on failure (so a version conflict
/// leaves the current values on screen). There is never an optimistic success.
mixin _AccountsCommandRunner<T> on StateNotifier<AsyncValue<T>> {
  YorksV1CriticalCommandKeyStore get commandKeys;
  Future<void> load();
  Future<void> refresh();

  Future<String?> runCommand({
    required String operation,
    required String entityId,
    required Map<String, Object?> payload,
    required Future<void> Function(String idempotencyKey) action,
  }) async {
    final key = await commandKeys.acquire(
      operation: operation,
      entityId: entityId,
      payload: payload,
    );
    try {
      await action(key);
      await commandKeys.confirm(
        operation: operation,
        entityId: entityId,
        idempotencyKey: key,
      );
      await load();
      return null;
    } catch (error) {
      // Keep the lease (a retry reuses the key) and re-fetch so a conflict
      // leaves the current server state on screen, not the stale projection.
      await refresh();
      return _commandFailureCode(error);
    }
  }
}

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
    extends StateNotifier<AsyncValue<YorksAccountsCommercialSetupRead>>
    with _AccountsCommandRunner<YorksAccountsCommercialSetupRead> {
  YorksAccountsContractController({
    required YorksAccountsWorkspaceRepository? repository,
    required this.commandKeys,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsCommercialSetupRead>.loading();
    await _fetch();
  }

  @override
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

  /// Saves the edited commercial setup. No optimistic success; concurrency is
  /// guarded by the expected profile version and the persisted idempotency
  /// lease (a retry of the same edit replays the same server key).
  Future<String?> saveSetup({
    required YorksAccountsCommercialSetup setup,
    int? expectedProfileVersion,
    String? note,
  }) {
    final json = setup.toSetupJson();
    return runCommand(
      operation: 'save_commercial_setup',
      entityId: _projectId,
      payload: {'setup': json, 'version': expectedProfileVersion},
      action: (key) async {
        final repository = _repository;
        if (repository == null) {
          throw StateError('accounts_backend_unavailable');
        }
        await repository.saveCommercialSetup(
          projectId: _projectId,
          expectedProfileVersion: expectedProfileVersion,
          setup: json,
          note: note,
          idempotencyKey: key,
        );
      },
    );
  }

  /// Saves invoice numbering. No optimistic success; re-fetches on confirmation.
  Future<String?> saveInvoiceSettings({
    required String invoicePrefix,
    String? scopeLine,
    String? attentionName,
    String? billToPartyId,
    int? expectedVersion,
  }) {
    return runCommand(
      operation: 'save_invoice_settings',
      entityId: _projectId,
      payload: {
        'prefix': invoicePrefix,
        'scope_line': scopeLine,
        'attention': attentionName,
        'bill_to': billToPartyId,
        'version': expectedVersion,
      },
      action: (key) async {
        final repository = _repository;
        if (repository == null) {
          throw StateError('accounts_backend_unavailable');
        }
        await repository.saveInvoiceSettings(
          projectId: _projectId,
          invoicePrefix: invoicePrefix,
          scopeLine: scopeLine,
          attentionName: attentionName,
          billToPartyId: billToPartyId,
          expectedVersion: expectedVersion,
          idempotencyKey: key,
        );
      },
    );
  }

  /// Saves the editable contract references (TRN, work order, contract no) on
  /// the profile. No optimistic success; re-fetches on confirmation.
  Future<String?> saveReferences({
    String? clientTrn,
    String? workOrderNumber,
    String? workOrderDate,
    String? contractNumber,
    String? retentionPercent,
    int? expectedProfileVersion,
  }) {
    return runCommand(
      operation: 'save_contract_references',
      entityId: _projectId,
      payload: {
        'client_trn': clientTrn,
        'work_order_number': workOrderNumber,
        'work_order_date': workOrderDate,
        'contract_number': contractNumber,
        'retention_percent': retentionPercent,
        'version': expectedProfileVersion,
      },
      action: (key) async {
        final repository = _repository;
        if (repository == null) {
          throw StateError('accounts_backend_unavailable');
        }
        await repository.saveContractReferences(
          projectId: _projectId,
          clientTrn: clientTrn,
          workOrderNumber: workOrderNumber,
          workOrderDate: workOrderDate,
          contractNumber: contractNumber,
          retentionPercent: retentionPercent,
          expectedVersion: expectedProfileVersion,
          idempotencyKey: key,
        );
      },
    );
  }
}

/// The project's physical buildings and the default stage template, which a
/// first contract needs because the setup read has none until a baseline exists.
/// An unavailable read yields empty lists; the screen then explains what's needed.
final yorksAccountsContractOptionsProvider = FutureProvider.autoDispose
    .family<YorksAccountsBaselineProjection?, String>((ref, projectId) async {
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      try {
        return await ref
            .watch(yorksAccountsRepositoryProvider)
            .getBaseline(projectId);
      } catch (_) {
        return null;
      }
    });

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
        commandKeys: _commandKeys(ref),
        projectId: projectId,
      );
    });

/// Loads and refreshes the claim workbench behind the Progress & claims tab.
final class YorksAccountsWorkbenchController
    extends StateNotifier<AsyncValue<YorksAccountsWorkbench>>
    with _AccountsCommandRunner<YorksAccountsWorkbench> {
  YorksAccountsWorkbenchController({
    required YorksAccountsWorkspaceRepository? repository,
    required YorksAccountsReceivablesRepository receivablesRepository,
    required this.commandKeys,
    required String projectId,
  }) : _repository = repository,
       _receivables = receivablesRepository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  final YorksAccountsReceivablesRepository _receivables;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  /// The claim the workbench is viewing. `null` is the open draft (the default
  /// v1_get_claim_workbench behaviour); a value loads that historical claim.
  String? _activeClaimId;
  String? get activeClaimId => _activeClaimId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsWorkbench>.loading();
    await _fetch();
  }

  @override
  Future<void> refresh() => _fetch();

  /// Switches the workbench to a specific claim (or back to the open draft when
  /// `claimId` is null) and reloads it.
  Future<void> selectClaim(String? claimId) {
    _activeClaimId = claimId;
    return load();
  }

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
      final workbench = await repository.getClaimWorkbench(
        _projectId,
        claimId: _activeClaimId,
      );
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
  }) => runCommand(
    operation: 'submit_claim',
    entityId: claimId,
    payload: {'version': expectedVersion, 'reason': reason},
    action: (key) => _receivables.submitClaimToAccounts(
      YorksAccountsEntityActionInput(
        projectId: _projectId,
        entityId: claimId,
        expectedVersion: expectedVersion,
        reason: reason,
      ),
      idempotencyKey: key,
    ),
  );

  /// Reopens a checked claim back to draft. No optimistic success: on the
  /// server's confirmation the workbench is re-fetched. Returns null on success
  /// or an error message (a version conflict is resolved by the reload).
  Future<String?> reopenClaim({
    required String claimId,
    required int expectedVersion,
    required String reason,
  }) => runCommand(
    operation: 'reopen_claim',
    entityId: claimId,
    payload: {'version': expectedVersion, 'reason': reason},
    action: (key) async {
      final repository = _repository;
      if (repository == null) throw StateError('accounts_backend_unavailable');
      await repository.reopenClaim(
        projectId: _projectId,
        claimId: claimId,
        expectedVersion: expectedVersion,
        reason: reason,
        idempotencyKey: key,
      );
    },
  );

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
  }) => runCommand(
    operation: 'save_claim_workbench',
    entityId: _projectId,
    payload: {
      'period_start': periodStart,
      'period_end': periodEnd,
      'entries': entries,
      'evidence': evidenceDocumentIds,
    },
    action: (key) async {
      final repository = _repository;
      if (repository == null) throw StateError('accounts_backend_unavailable');
      await repository.saveClaimWorkbench(
        projectId: _projectId,
        claimReference: claimReference,
        periodStart: periodStart,
        periodEnd: periodEnd,
        entries: entries,
        evidenceDocumentIds: evidenceDocumentIds,
        reason: reason,
        idempotencyKey: key,
      );
    },
  );

  /// Renders the invoice a checked claim would produce, without issuing it. Pure
  /// read; returns null if the backend is unavailable or the render fails.
  Future<Uint8List?> buildInvoicePreview(String claimId) async {
    final repository = _repository;
    if (repository == null) return null;
    try {
      final doc = await repository.previewInvoiceDocument(_projectId, claimId);
      return await YorksClientInvoiceDocumentBuilder.build(doc.document);
    } catch (_) {
      return null;
    }
  }

  /// Issues the client invoice for a checked claim (allocates the number,
  /// submits and freezes the document snapshot server-side). No optimistic
  /// success; re-fetches on confirmation. The persisted idempotency lease means
  /// a retry of the same issue replays the same server key.
  Future<String?> issueInvoice({
    required String claimId,
    required int expectedClaimVersion,
    required String invoiceDate,
    required String submissionDate,
    String? invoiceReference,
  }) => runCommand(
    operation: 'issue_invoice',
    entityId: claimId,
    payload: {
      'version': expectedClaimVersion,
      'invoice_date': invoiceDate,
      'submission_date': submissionDate,
      'reference': invoiceReference,
    },
    action: (key) async {
      final repository = _repository;
      if (repository == null) throw StateError('accounts_backend_unavailable');
      await repository.issueInvoice(
        projectId: _projectId,
        claimId: claimId,
        expectedClaimVersion: expectedClaimVersion,
        invoiceReference: invoiceReference,
        invoiceDate: invoiceDate,
        submissionDate: submissionDate,
        idempotencyKey: key,
      );
    },
  );
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
        commandKeys: _commandKeys(ref),
        projectId: projectId,
      );
    });

/// Loads the project's claims (newest first) for the Progress & claims
/// claim-cards row, reusing the commercial-gated v1_list_client_claims. Read
/// only; an access-denied error simply yields no cards row in the UI.
final class YorksAccountsClaimsListController
    extends StateNotifier<AsyncValue<YorksAccountsClaimsList>> {
  YorksAccountsClaimsListController({
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
    state = const AsyncValue<YorksAccountsClaimsList>.loading();
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsClaimsList>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final list = await repository.getClaimsList(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsClaimsList>.data(list);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsClaimsList>.error(error, stackTrace);
    }
  }

  Future<void> refresh() => load();
}

final yorksAccountsClaimsListControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsClaimsListController,
      AsyncValue<YorksAccountsClaimsList>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsClaimsListController(
        repository: ref.watch(yorksAccountsWorkspaceRepositoryProvider),
        projectId: projectId,
      );
    });

/// Loads the contract variations (VO register) and creates/edits them. The
/// register is display-only (no contract-value side effects).
final class YorksAccountsVariationsController
    extends StateNotifier<AsyncValue<YorksAccountsVariationsList>>
    with _AccountsCommandRunner<YorksAccountsVariationsList> {
  YorksAccountsVariationsController({
    required YorksAccountsWorkspaceRepository? repository,
    required this.commandKeys,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _repository;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsVariationsList>.loading();
    await _fetch();
  }

  @override
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsVariationsList>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final list = await repository.getVariations(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsVariationsList>.data(list);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsVariationsList>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }

  /// Creates (variationId null) or edits a variation. No optimistic success;
  /// the register re-fetches on the server's confirmation.
  Future<String?> saveVariation({
    String? variationId,
    required String voNumber,
    String? description,
    String? amount,
    required String status,
    int? expectedVersion,
  }) {
    return runCommand(
      operation: 'save_variation',
      entityId: variationId ?? 'new',
      payload: {
        'variation_id': variationId,
        'vo_number': voNumber,
        'description': description,
        'amount': amount,
        'status': status,
        'version': expectedVersion,
      },
      action: (key) async {
        final repository = _repository;
        if (repository == null) {
          throw StateError('accounts_backend_unavailable');
        }
        await repository.saveVariation(
          projectId: _projectId,
          variationId: variationId,
          voNumber: voNumber,
          description: description,
          amount: amount,
          status: status,
          expectedVersion: expectedVersion,
          idempotencyKey: key,
        );
      },
    );
  }
}

final yorksAccountsVariationsControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsVariationsController,
      AsyncValue<YorksAccountsVariationsList>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsVariationsController(
        repository: ref.watch(yorksAccountsWorkspaceRepositoryProvider),
        commandKeys: _commandKeys(ref),
        projectId: projectId,
      );
    });

/// Loads and refreshes the client invoice tracker behind the Invoices &
/// payments tab. It reuses the existing receivables repository (the invoice
/// list already carries ex/incl VAT, certified, paid, balance and PDC exposure
/// per invoice), so the tab needs no new read.
final class YorksAccountsInvoicesController
    extends StateNotifier<AsyncValue<YorksAccountsInvoicesProjection>>
    with _AccountsCommandRunner<YorksAccountsInvoicesProjection> {
  YorksAccountsInvoicesController({
    required YorksAccountsReceivablesRepository repository,
    required YorksAccountsWorkspaceRepository? workspaceRepository,
    required this.commandKeys,
    required String projectId,
  }) : _repository = repository,
       _workspace = workspaceRepository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsReceivablesRepository _repository;
  final YorksAccountsWorkspaceRepository? _workspace;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsInvoicesProjection>.loading();
    await _fetch();
  }

  @override
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
  Future<String?> certify(YorksAccountsCertificationInput input) => runCommand(
    operation: 'certify_invoice',
    entityId: input.invoiceId,
    payload: input.idempotencyPayload(),
    action: (key) =>
        _repository.recordCertification(input, idempotencyKey: key),
  );

  /// Records a client payment (bank transfer or cash) against an invoice.
  Future<String?> pay(YorksAccountsPaymentInput input) => runCommand(
    operation: 'pay_invoice',
    entityId: input.invoiceId,
    payload: input.idempotencyPayload(),
    action: (key) => _repository.recordPayment(input, idempotencyKey: key),
  );

  /// Reverses a recorded receipt (an append-only reversal entry; the original
  /// stays on the ledger). No optimistic success: the tracker re-fetches on the
  /// server's confirmation.
  Future<String?> reversePayment(YorksAccountsPaymentReversalInput input) =>
      runCommand(
        operation: 'reverse_payment',
        entityId: input.originalPaymentId,
        payload: input.idempotencyPayload(),
        action: (key) => _repository.reversePayment(input, idempotencyKey: key),
      );

  /// Records a cheque against an invoice. No optimistic success.
  Future<String?> createPdc(YorksAccountsPdcCreateInput input) => runCommand(
    operation: 'create_pdc',
    entityId: input.invoiceId,
    payload: input.idempotencyPayload(),
    action: (key) => _repository.createPdc(input, idempotencyKey: key),
  );

  /// Revises an issued invoice (R.n): clones a successor draft claim from the
  /// predecessor while the predecessor invoice stays submitted. The server
  /// (v1_revise_client_invoice) rejects it once a certification, net payment or
  /// active PDC exists (D7). No optimistic success; the tracker re-fetches on
  /// the server's confirmation. Returns null on success or an error message.
  Future<String?> revise({
    required String invoiceId,
    required int expectedVersion,
    required String reason,
  }) => runCommand(
    operation: 'revise_invoice',
    entityId: invoiceId,
    payload: {'version': expectedVersion, 'reason': reason},
    action: (key) async {
      final workspace = _workspace;
      if (workspace == null) throw StateError('accounts_backend_unavailable');
      await workspace.reviseInvoice(
        projectId: _projectId,
        invoiceId: invoiceId,
        expectedVersion: expectedVersion,
        reason: reason,
        idempotencyKey: key,
      );
    },
  );

  /// Fetches the full invoice detail (invoice, certifications, payments and
  /// cheques) for the drawer. Pure read; returns null on failure.
  Future<YorksAccountsInvoiceDetailProjection?> fetchInvoiceDetail(
    String invoiceId,
  ) async {
    try {
      return await _repository.getInvoice(_projectId, invoiceId);
    } catch (_) {
      return null;
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
        commandKeys: _commandKeys(ref),
        projectId: projectId,
      );
    });

/// Loads the project cheque (PDC) register behind the Invoices & payments tab
/// and runs the lifecycle transitions (deposit / clear / bounce / return /
/// cancel) through the existing receivables transition command. The read is
/// gated behind `view_project_commercial_values`, so for an actor without that
/// capability it surfaces as an error and the register card simply stays hidden.
final class YorksAccountsPdcRegisterController
    extends StateNotifier<AsyncValue<YorksAccountsProjectPdcRegister>>
    with _AccountsCommandRunner<YorksAccountsProjectPdcRegister> {
  YorksAccountsPdcRegisterController({
    required YorksAccountsWorkspaceRepository? workspaceRepository,
    required YorksAccountsReceivablesRepository receivablesRepository,
    required this.commandKeys,
    required String projectId,
  }) : _workspace = workspaceRepository,
       _receivables = receivablesRepository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsWorkspaceRepository? _workspace;
  final YorksAccountsReceivablesRepository _receivables;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsProjectPdcRegister>.loading();
    await _fetch();
  }

  @override
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    final workspace = _workspace;
    if (workspace == null) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsProjectPdcRegister>.error(
        StateError('accounts_backend_unavailable'),
        StackTrace.current,
      );
      return;
    }
    try {
      final register = await workspace.getProjectPdcRegister(_projectId);
      if (!mounted) return;
      state = AsyncValue<YorksAccountsProjectPdcRegister>.data(register);
    } catch (error, stackTrace) {
      if (!mounted) return;
      state = AsyncValue<YorksAccountsProjectPdcRegister>.error(
        error,
        stackTrace,
      ).copyWithPrevious(state);
    }
  }

  /// Moves a cheque to its next lifecycle state. No optimistic success: the
  /// register is re-fetched on the server's confirmation. Returns null on
  /// success or an error message (a version conflict resolves on reload).
  Future<String?> transition(YorksAccountsPdcTransitionInput input) {
    if (!input.isValid) {
      return Future<String?>.value('R39_ACCOUNTS_INVALID_PDC_TRANSITION');
    }
    return runCommand(
      operation: 'transition_pdc',
      entityId: input.pdcId,
      payload: input.idempotencyPayload(),
      action: (key) => _receivables.transitionPdc(input, idempotencyKey: key),
    );
  }

  /// Replaces a returned or bounced cheque with a re-presented one. The old
  /// cheque is marked replaced and linked to the new one; no optimistic
  /// success — the register re-fetches on the server's confirmation.
  Future<String?> replace(YorksAccountsPdcReplacementInput input) {
    if (!input.isValid) {
      return Future<String?>.value(
        'R39_ACCOUNTS_PDC_REPLACEMENT_FIELDS_REQUIRED',
      );
    }
    return runCommand(
      operation: 'replace_pdc',
      entityId: input.originalPdcId,
      payload: input.idempotencyPayload(),
      action: (key) => _receivables.replacePdc(input, idempotencyKey: key),
    );
  }
}

final yorksAccountsPdcRegisterControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      YorksAccountsPdcRegisterController,
      AsyncValue<YorksAccountsProjectPdcRegister>,
      String
    >((ref, projectId) {
      ref.keepAlive();
      ref.watch(yorksV1CurrentRoleProvider);
      ref.watch(yorksAccountsPermissionEpochProvider);
      return YorksAccountsPdcRegisterController(
        workspaceRepository: ref.watch(
          yorksAccountsWorkspaceRepositoryProvider,
        ),
        receivablesRepository: ref.watch(
          yorksAccountsReceivablesRepositoryProvider,
        ),
        commandKeys: _commandKeys(ref),
        projectId: projectId,
      );
    });

/// Loads and refreshes the supplier bills behind the Supplier bills tab,
/// reusing the existing supplier repository's v1_list_supplier_bills.
final class YorksAccountsSupplierBillsController
    extends StateNotifier<AsyncValue<YorksAccountsSupplierBillsProjection>>
    with _AccountsCommandRunner<YorksAccountsSupplierBillsProjection> {
  YorksAccountsSupplierBillsController({
    required YorksAccountsSupplierRepository repository,
    required this.commandKeys,
    required String projectId,
  }) : _repository = repository,
       _projectId = projectId,
       super(const AsyncValue.loading()) {
    load();
  }

  final YorksAccountsSupplierRepository _repository;
  @override
  final YorksV1CriticalCommandKeyStore commandKeys;
  final String _projectId;

  @override
  Future<void> load() async {
    state = const AsyncValue<YorksAccountsSupplierBillsProjection>.loading();
    await _fetch();
  }

  @override
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
  }) => runCommand(
    operation: 'approve_supplier_bill',
    entityId: supplierBillId,
    payload: {'version': expectedVersion},
    action: (key) => _repository.approveBill(
      YorksAccountsSupplierBillApprovalInput(
        projectId: _projectId,
        supplierBillId: supplierBillId,
        expectedVersion: expectedVersion,
        adminExceptionReason: null,
      ),
      idempotencyKey: key,
    ),
  );

  /// Records a payment against an approved supplier bill. No optimistic
  /// success: the bills list is re-fetched on the server's confirmation.
  Future<String?> recordPayment(YorksAccountsSupplierPaymentInput input) =>
      runCommand(
        operation: 'pay_supplier_bill',
        entityId: input.supplierBillId,
        payload: input.idempotencyPayload(),
        action: (key) => _repository.recordPayment(input, idempotencyKey: key),
      );
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
        commandKeys: _commandKeys(ref),
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
