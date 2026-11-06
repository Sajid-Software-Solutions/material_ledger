/// R39 Accounts Workspace V2 — six-tab workspace screen (P6).
///
/// The flag-guarded replacement for the per-project Accounts surface. It hosts
/// the six job-shaped tabs (Summary, Contract, Progress & claims, Invoices &
/// payments, Supplier bills, History & files). Only Summary is wired to the
/// live workspace projection in this slice; the other five render a labelled
/// placeholder and are built out in later P6 increments.
///
/// It reads authority and data only through Riverpod controllers — it never
/// calls Supabase directly — and recreates its protected projection on any
/// role/permission change via the controller's watched authority inputs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../application/accounts_records_providers.dart';
import '../../application/v2/accounts_workspace_v2_controllers.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claims_list_models.dart';
import 'accounts_v2_claims_tab.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_contract_tab.dart';
import 'accounts_v2_history_tab.dart';
import 'accounts_v2_invoices_tab.dart';
import 'accounts_v2_pdc_register_card.dart';
import 'accounts_v2_summary_tab.dart';
import 'accounts_v2_supplier_tab.dart';

class YorksAccountsWorkspaceV2Screen extends ConsumerStatefulWidget {
  const YorksAccountsWorkspaceV2Screen({
    super.key,
    required this.projectId,
    this.initialTab = YorksAccountsWorkspaceV2Tab.summary,
  });

  final String projectId;
  final YorksAccountsWorkspaceV2Tab initialTab;

  @override
  ConsumerState<YorksAccountsWorkspaceV2Screen> createState() =>
      _YorksAccountsWorkspaceV2ScreenState();
}

class _YorksAccountsWorkspaceV2ScreenState
    extends ConsumerState<YorksAccountsWorkspaceV2Screen> {
  late YorksAccountsWorkspaceV2Tab _tab = widget.initialTab;

  void _select(YorksAccountsWorkspaceV2Tab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  YorksAccountsWorkspaceV2Tab _tabForAction(String? actionKey) =>
      switch (actionKey) {
        'open_contract' => YorksAccountsWorkspaceV2Tab.contract,
        'open_invoice' ||
        'open_invoices' ||
        'certify' => YorksAccountsWorkspaceV2Tab.invoices,
        'open_claim' || 'start_claim' => YorksAccountsWorkspaceV2Tab.claims,
        'open_supplier_bills' => YorksAccountsWorkspaceV2Tab.supplierBills,
        _ => YorksAccountsWorkspaceV2Tab.summary,
      };

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    // The workspace projection carries the tab badges (open-draft claim,
    // overdue supplier bills); watch it at the shell so badges stay correct on
    // every tab, falling back to none while it loads or on any tab error.
    final badges =
        ref
            .watch(yorksAccountsWorkspaceControllerProvider(widget.projectId))
            .valueOrNull
            ?.badges ??
        YorksAccountsWorkspaceBadges.empty;
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabBar(
            selected: _tab,
            language: language,
            badges: badges,
            onSelected: _select,
          ),
          const Divider(height: 1, color: AppColors.line),
          Expanded(child: _buildBody(language)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLanguage language) {
    switch (_tab) {
      case YorksAccountsWorkspaceV2Tab.summary:
        return _SummaryBody(
          projectId: widget.projectId,
          language: language,
          onOpenTab: _select,
          onAttentionAction: (item) => _select(_tabForAction(item.actionKey)),
          onOpenCell: (_, _) => _select(YorksAccountsWorkspaceV2Tab.claims),
        );
      case YorksAccountsWorkspaceV2Tab.contract:
        return _ContractBody(projectId: widget.projectId, language: language);
      case YorksAccountsWorkspaceV2Tab.claims:
        return _ClaimsBody(projectId: widget.projectId, language: language);
      case YorksAccountsWorkspaceV2Tab.invoices:
        return _InvoicesBody(projectId: widget.projectId, language: language);
      case YorksAccountsWorkspaceV2Tab.supplierBills:
        return _SupplierBody(projectId: widget.projectId, language: language);
      case YorksAccountsWorkspaceV2Tab.history:
        return _HistoryBody(projectId: widget.projectId, language: language);
    }
  }
}

// ─── Tab bar ────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.language,
    required this.badges,
    required this.onSelected,
  });

  final YorksAccountsWorkspaceV2Tab selected;
  final AppLanguage language;
  final YorksAccountsWorkspaceBadges badges;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onSelected;

  // Prototype layout: two symmetric rows of three.
  static const _topRow = [
    YorksAccountsWorkspaceV2Tab.summary,
    YorksAccountsWorkspaceV2Tab.contract,
    YorksAccountsWorkspaceV2Tab.claims,
  ];
  static const _bottomRow = [
    YorksAccountsWorkspaceV2Tab.invoices,
    YorksAccountsWorkspaceV2Tab.supplierBills,
    YorksAccountsWorkspaceV2Tab.history,
  ];

  String? _badgeFor(YorksAccountsWorkspaceV2Tab tab) {
    switch (tab) {
      case YorksAccountsWorkspaceV2Tab.claims:
        return badges.claimsDraft
            ? accountsV2Text(language, 'v2_badge_draft')
            : null;
      case YorksAccountsWorkspaceV2Tab.supplierBills:
        final count = badges.supplierCount;
        return (count != null && count > 0) ? '$count' : null;
      default:
        return null;
    }
  }

  _TabChip _chip(YorksAccountsWorkspaceV2Tab tab) => _TabChip(
    tab: tab,
    selected: tab == selected,
    label: accountsV2Text(language, tab.labelKey),
    badge: _badgeFor(tab),
    onTap: () => onSelected(tab),
  );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Desktop: the symmetric 3 + 3 grid. Narrow: a single scrolling row
            // so the longer labels stay readable instead of being squeezed.
            if (constraints.maxWidth < AppSpacing.compactBreakpoint) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in YorksAccountsWorkspaceV2Tab.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: _chip(tab),
                      ),
                  ],
                ),
              );
            }
            Widget gridRow(List<YorksAccountsWorkspaceV2Tab> tabs) => Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  Expanded(child: _chip(tabs[i])),
                  if (i < tabs.length - 1) const SizedBox(width: AppSpacing.sm),
                ],
              ],
            );
            return Column(
              children: [
                gridRow(_topRow),
                const SizedBox(height: AppSpacing.sm),
                gridRow(_bottomRow),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.selected,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final YorksAccountsWorkspaceV2Tab tab;
  final bool selected;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.inkSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge',
      child: Material(
        color: selected ? AppColors.primary : AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tab.icon, size: 16, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(color: fg),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _TabBadge(text: badge!, selected: selected),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small count/status pill inside a tab chip.
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.onPrimary.withValues(alpha: 0.22)
            : AppColors.warningContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: selected ? AppColors.onPrimary : AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Summary body (AsyncValue handling) ──────────────────────────────────────

class _SummaryBody extends ConsumerWidget {
  const _SummaryBody({
    required this.projectId,
    required this.language,
    required this.onOpenTab,
    required this.onAttentionAction,
    required this.onOpenCell,
  });

  final String projectId;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onOpenTab;
  final ValueChanged<YorksAccountsWorkspaceAttention> onAttentionAction;
  final void Function(String stageKey, String buildingScopeId) onOpenCell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      yorksAccountsWorkspaceControllerProvider(projectId),
    );
    final controller = ref.read(
      yorksAccountsWorkspaceControllerProvider(projectId).notifier,
    );
    final workspace = state.valueOrNull;

    Widget summary(YorksAccountsWorkspace ws) => AccountsV2SummaryTab(
      workspace: ws,
      language: language,
      format: const AccountsV2Format(),
      onOpenTab: onOpenTab,
      onAttentionAction: onAttentionAction,
      onOpenCell: onOpenCell,
    );

    if (state.isLoading && workspace == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && workspace == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }
    // Data (possibly with a stale-data error banner on top).
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(child: summary(workspace!)),
      ],
    );
  }
}

class _ContractBody extends ConsumerWidget {
  const _ContractBody({required this.projectId, required this.language});

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAccountsContractControllerProvider(projectId));
    final controller = ref.read(
      yorksAccountsContractControllerProvider(projectId).notifier,
    );
    final setup = state.valueOrNull;

    if (state.isLoading && setup == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && setup == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }
    final data = setup!;
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ContractTab(
            setup: data,
            language: language,
            canEdit: data.canConfigure,
            onSave: (form) => controller.saveSetup(
              setup: form,
              expectedProfileVersion: data.profileVersion,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClaimsBody extends ConsumerWidget {
  const _ClaimsBody({required this.projectId, required this.language});

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      yorksAccountsWorkbenchControllerProvider(projectId),
    );
    final controller = ref.read(
      yorksAccountsWorkbenchControllerProvider(projectId).notifier,
    );
    final workbench = state.valueOrNull;

    if (state.isLoading && workbench == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && workbench == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }
    final data = workbench!;
    final canConfirm = data.capabilities['can_confirm'] == true;
    // All claims for the claim-cards row (commercial-gated; empty when the
    // actor lacks access or the list is still loading).
    final claims =
        ref
            .watch(yorksAccountsClaimsListControllerProvider(projectId))
            .valueOrNull
            ?.claims ??
        const <YorksAccountsClaimSummary>[];
    final docsWorkspace = ref
        .watch(yorksAccountsDocumentsControllerProvider(projectId))
        .workspace;
    final evidenceDocuments = <YorksAccountsEvidenceDoc>[
      for (final doc in docsWorkspace?.documents ?? const [])
        (id: doc.id, name: doc.fileName),
    ];
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ClaimsTab(
            workbench: data,
            language: language,
            canRecordProgress: canConfirm,
            evidenceDocuments: evidenceDocuments,
            claims: claims,
            onSelectClaim: (id) => controller.selectClaim(id),
            onSaveWorkbench:
                ({
                  String? claimReference,
                  required String periodStart,
                  required String periodEnd,
                  required List<Map<String, Object?>> entries,
                  required List<String> evidenceDocumentIds,
                  String? reason,
                }) => controller.saveWorkbench(
                  claimReference: claimReference,
                  periodStart: periodStart,
                  periodEnd: periodEnd,
                  entries: entries,
                  evidenceDocumentIds: evidenceDocumentIds,
                  reason: reason,
                ),
            onMarkChecked:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) => controller.markChecked(
                  claimId: claimId,
                  expectedVersion: expectedVersion,
                  reason: reason,
                ),
            onReopen:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) => controller.reopenClaim(
                  claimId: claimId,
                  expectedVersion: expectedVersion,
                  reason: reason,
                ),
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) => controller.issueInvoice(
                  claimId: claimId,
                  expectedClaimVersion: expectedClaimVersion,
                  invoiceDate: invoiceDate,
                  submissionDate: submissionDate,
                  invoiceReference: invoiceReference,
                ),
          ),
        ),
      ],
    );
  }
}

class _InvoicesBody extends ConsumerWidget {
  const _InvoicesBody({required this.projectId, required this.language});

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAccountsInvoicesControllerProvider(projectId));
    final controller = ref.read(
      yorksAccountsInvoicesControllerProvider(projectId).notifier,
    );
    final projection = state.valueOrNull;

    if (state.isLoading && projection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && projection == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }

    // Cheque register: commercial, so the whole card is drawn only with
    // view_project_commercial_values. The read is gated server-side too; here we
    // simply omit it when the actor cannot see values or the register is empty.
    Widget? registerCard;
    if (projection!.capabilities.canViewValues) {
      final registerState = ref.watch(
        yorksAccountsPdcRegisterControllerProvider(projectId),
      );
      final register = registerState.valueOrNull;
      if (register != null && register.pdcs.isNotEmpty) {
        final registerController = ref.read(
          yorksAccountsPdcRegisterControllerProvider(projectId).notifier,
        );
        registerCard = AccountsV2PdcRegisterCard(
          projectId: projectId,
          register: register,
          language: language,
          canManage: projection.capabilities.managePdc,
          onTransition: registerController.transition,
          onReplace: registerController.replace,
        );
      }
    }

    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2InvoicesTab(
            projection: projection,
            language: language,
            onCertify: controller.certify,
            onPay: controller.pay,
            onReversePayment: controller.reversePayment,
            onPrintInvoice: (invoiceId) async {
              final bytes = await controller.buildInvoicePdf(invoiceId);
              if (bytes == null) return 'error';
              await Printing.layoutPdf(onLayout: (_) async => bytes);
              return null;
            },
            onOpenDetail: controller.fetchInvoiceDetail,
            trailing: registerCard,
          ),
        ),
      ],
    );
  }
}

class _SupplierBody extends ConsumerWidget {
  const _SupplierBody({required this.projectId, required this.language});

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      yorksAccountsSupplierBillsControllerProvider(projectId),
    );
    final controller = ref.read(
      yorksAccountsSupplierBillsControllerProvider(projectId).notifier,
    );
    final projection = state.valueOrNull;

    if (state.isLoading && projection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && projection == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }
    // Client-invoiced total (ex VAT) for the "cost vs invoiced" KPI. Present
    // only with view_project_commercial_values; null otherwise (KPI omitted).
    final invoicedTotal = ref
        .watch(yorksAccountsWorkspaceControllerProvider(projectId))
        .valueOrNull
        ?.kpis
        ?.invoiced;
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2SupplierTab(
            projection: projection!,
            language: language,
            invoicedTotal: invoicedTotal,
            onPay: controller.recordPayment,
            onApprove:
                ({
                  required String supplierBillId,
                  required int expectedVersion,
                }) => controller.approveBill(
                  supplierBillId: supplierBillId,
                  expectedVersion: expectedVersion,
                ),
          ),
        ),
      ],
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({required this.projectId, required this.language});

  final String projectId;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAccountsHistoryControllerProvider(projectId));
    final controller = ref.read(
      yorksAccountsHistoryControllerProvider(projectId).notifier,
    );
    final projection = state.valueOrNull;

    if (state.isLoading && projection == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && projection == null) {
      return _ErrorState(language: language, onRetry: controller.load);
    }
    // Attached files for the Files panel, from the shared documents workspace.
    final docs =
        ref
            .watch(yorksAccountsDocumentsControllerProvider(projectId))
            .workspace
            ?.documents ??
        const [];
    final files = <YorksAccountsHistoryFile>[
      for (final doc in docs)
        (
          name: doc.currentVersion.fileName,
          reference: doc.currentVersion.businessReference,
          uploadedBy: doc.currentVersion.uploadedByDisplayName,
        ),
    ];
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2HistoryTab(
            projection: projection!,
            language: language,
            files: files,
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 32,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              accountsV2Text(language, 'v2_error_title'),
              style: AppTypography.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: onRetry,
              child: Text(accountsV2Text(language, 'v2_retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_outlined,
              size: 18,
              color: AppColors.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                accountsV2Text(language, 'v2_error_title'),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(accountsV2Text(language, 'v2_retry')),
            ),
          ],
        ),
      ),
    );
  }
}
