/// R39 Accounts Workspace V2 — six-tab workspace screen (P6).
///
/// The flag-guarded replacement for the per-project Accounts surface. It hosts
/// the six job-shaped tabs (Summary, Contract, Progress & claims, Invoices &
/// payments, Supplier bills, History & files).
///
/// It reads authority and data only through Riverpod controllers — it never
/// calls Supabase directly — and recreates its protected projection on any
/// role/permission change via the controller's watched authority inputs.
library;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../application/accounts_controller.dart'
    show YorksAccountsViewStatus;
import '../../application/accounts_records_providers.dart';
import '../../application/v2/accounts_workspace_v2_controllers.dart';
import '../../domain/accounts_models.dart'
    show YorksAccountsPhysicalBuilding, YorksAccountsStageTemplate;
import '../../domain/v2/accounts_master_file_parser.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import '../../domain/v2/claims_list_models.dart';
import '../../domain/v2/variations_models.dart';
import 'accounts_v2_claims_tab.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_contract_tab.dart';
import 'accounts_v2_history_tab.dart';
import 'accounts_v2_invoices_tab.dart';
import 'accounts_v2_pdc_register_card.dart';
import 'accounts_v2_summary_tab.dart';
import 'accounts_v2_supplier_tab.dart';
import '../widgets/yorks_accounts_progress_action_sheet.dart';
import '../widgets/yorks_accounts_records_views.dart'
    show showYorksAccountsDocumentUploadDialog;
import '../widgets/yorks_accounts_supplier_action_sheets.dart';

/// The workspace on its own page, for an Accountant, who has project Accounts
/// scope but no access to the technical project shell around it.
class YorksAccountsProjectPage extends ConsumerWidget {
  const YorksAccountsProjectPage({
    super.key,
    required this.projectId,
    required this.initialTab,
  });

  final String projectId;
  final YorksAccountsWorkspaceV2Tab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final setup = ref
        .watch(yorksAccountsContractControllerProvider(projectId))
        .valueOrNull;
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: accountsV2Text(language, 'v2_all_projects'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/yorks/accounts'),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (setup?.projectReference != null)
                        Text(
                          setup!.projectReference!,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      Text(
                        setup?.projectName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: YorksAccountsWorkspaceV2Screen(
              projectId: projectId,
              initialTab: initialTab,
            ),
          ),
        ],
      ),
    );
  }
}

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
    _refreshTab(tab);
    _rememberTab(tab);
  }

  /// A change on one tab affects the others (saving a contract creates the
  /// progress grid; issuing an invoice moves the claim), so a tab re-fetches when
  /// opened. Each controller keeps its last data on screen meanwhile.
  void _refreshTab(YorksAccountsWorkspaceV2Tab tab) {
    final id = widget.projectId;
    void refreshIfLoaded<T extends StateNotifier<Object?>>(
      ProviderListenable<T> notifier,
      ProviderBase<Object?> provider,
      Future<void> Function(T) refresh,
    ) {
      if (ref.exists(provider)) refresh(ref.read(notifier));
    }

    final workspace = yorksAccountsWorkspaceControllerProvider(id);
    refreshIfLoaded(workspace.notifier, workspace, (c) => c.refresh());
    switch (tab) {
      case YorksAccountsWorkspaceV2Tab.summary:
        break;
      case YorksAccountsWorkspaceV2Tab.contract:
        final contract = yorksAccountsContractControllerProvider(id);
        refreshIfLoaded(contract.notifier, contract, (c) => c.refresh());
        final variations = yorksAccountsVariationsControllerProvider(id);
        refreshIfLoaded(variations.notifier, variations, (c) => c.refresh());
      case YorksAccountsWorkspaceV2Tab.claims:
        final workbench = yorksAccountsWorkbenchControllerProvider(id);
        refreshIfLoaded(workbench.notifier, workbench, (c) => c.refresh());
        final claims = yorksAccountsClaimsListControllerProvider(id);
        refreshIfLoaded(claims.notifier, claims, (c) => c.refresh());
      case YorksAccountsWorkspaceV2Tab.invoices:
        final invoices = yorksAccountsInvoicesControllerProvider(id);
        refreshIfLoaded(invoices.notifier, invoices, (c) => c.refresh());
        final pdcs = yorksAccountsPdcRegisterControllerProvider(id);
        refreshIfLoaded(pdcs.notifier, pdcs, (c) => c.refresh());
      case YorksAccountsWorkspaceV2Tab.supplierBills:
        final bills = yorksAccountsSupplierBillsControllerProvider(id);
        refreshIfLoaded(bills.notifier, bills, (c) => c.refresh());
      case YorksAccountsWorkspaceV2Tab.history:
        final history = yorksAccountsHistoryControllerProvider(id);
        refreshIfLoaded(history.notifier, history, (c) => c.refresh());
        final documents = yorksAccountsDocumentsControllerProvider(id);
        if (ref.exists(documents)) ref.read(documents.notifier).load();
    }
  }

  /// Keeps the address bar on the open tab, so a browser refresh or a shared
  /// link returns here, without rebuilding the page through a navigation.
  void _rememberTab(YorksAccountsWorkspaceV2Tab tab) {
    final segment = switch (tab) {
      YorksAccountsWorkspaceV2Tab.summary => 'overview',
      YorksAccountsWorkspaceV2Tab.contract => 'contract',
      YorksAccountsWorkspaceV2Tab.claims => 'claims',
      YorksAccountsWorkspaceV2Tab.invoices => 'client-invoices',
      YorksAccountsWorkspaceV2Tab.supplierBills => 'supplier-bills',
      YorksAccountsWorkspaceV2Tab.history => 'history',
    };
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse('/yorks/projects/${widget.projectId}/accounts/$segment'),
      replace: true,
    );
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
                        child: _KeepInViewWhenSelected(
                          selected: tab == selected,
                          child: _chip(tab),
                        ),
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

/// Scrolls a chip into view when it becomes the selected one, so a phone always
/// shows which tab is open.
class _KeepInViewWhenSelected extends StatefulWidget {
  const _KeepInViewWhenSelected({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_KeepInViewWhenSelected> createState() =>
      _KeepInViewWhenSelectedState();
}

class _KeepInViewWhenSelectedState extends State<_KeepInViewWhenSelected> {
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: 0.5);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(_KeepInViewWhenSelected oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
          // Selecting a chip under the pointer must not carry over its hover
          // highlight: the theme's opaque one hid the white label until the pointer
          // moved away. A fresh state per selection leaves nothing behind.
          key: ValueKey<bool>(selected),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: onTap,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            final tint = selected ? AppColors.onPrimary : AppColors.ink;
            if (states.contains(WidgetState.pressed)) {
              return tint.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.focused)) {
              return tint.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return tint.withValues(alpha: 0.06);
            }
            return null;
          }),
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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
    }
    final data = setup!;
    // Contract variations (VO register); empty while loading or without access.
    final variations =
        ref
            .watch(yorksAccountsVariationsControllerProvider(projectId))
            .valueOrNull
            ?.variations ??
        const <YorksAccountsVariation>[];
    final variationsController = ref.read(
      yorksAccountsVariationsControllerProvider(projectId).notifier,
    );
    final options = ref
        .watch(yorksAccountsContractOptionsProvider(projectId))
        .valueOrNull;
    final canManageInvoices =
        ref
            .watch(yorksAccountsWorkbenchControllerProvider(projectId))
            .valueOrNull
            ?.canManageInvoices ??
        false;
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ContractTab(
            setup: data,
            language: language,
            canEdit: data.canConfigure,
            buildingOptions: [
              for (final b
                  in options?.physicalBuildings ??
                      const <YorksAccountsPhysicalBuilding>[])
                (
                  scopeId: b.buildingScopeId,
                  name: b.buildingName,
                  code: b.scopeCode,
                ),
            ],
            stageOptions: [
              for (final t
                  in options?.stageTemplates ??
                      const <YorksAccountsStageTemplate>[])
                (
                  key: t.stageKey,
                  label: t.stageLabel,
                  percent: t.allocationPercent,
                ),
            ],
            canManageInvoices: canManageInvoices,
            onSaveInvoiceSettings: controller.saveInvoiceSettings,
            onImportMasterFile: () async {
              final selected = await ref
                  .read(yorksV1BoqWorkbookFileServiceProvider)
                  .selectWorkbook();
              if (selected == null) return null;
              final workbook = ref
                  .read(yorksV1BoqWorkbookCodecProvider)
                  .decode(bytes: selected.bytes, fileName: selected.fileName);
              final draft = const YorksAccountsMasterFileParser().parse(
                sheets: {for (final s in workbook.sheets) s.name: s.rows},
                expectedContractValue: data.contractValue,
                currencyCode: data.currencyCode ?? 'AED',
              );
              return (
                draft: draft,
                fileName: selected.fileName,
                sha256: crypto.sha256.convert(selected.bytes).toString(),
              );
            },
            onApplyImport: (setup, note) => controller.saveSetup(
              setup: setup,
              expectedProfileVersion: data.profileVersion,
              note: note,
            ),
            variations: variations,
            onSaveVariation:
                ({
                  String? variationId,
                  required String voNumber,
                  String? description,
                  String? amount,
                  required String status,
                  int? expectedVersion,
                }) => variationsController.saveVariation(
                  variationId: variationId,
                  voNumber: voNumber,
                  description: description,
                  amount: amount,
                  status: status,
                  expectedVersion: expectedVersion,
                ),
            onSave: (form) => controller.saveSetup(
              setup: form,
              expectedProfileVersion: data.profileVersion,
            ),
            onSaveReferences:
                ({
                  String? clientTrn,
                  String? workOrderNumber,
                  String? workOrderDate,
                  String? contractNumber,
                  String? retentionPercent,
                  int? expectedProfileVersion,
                }) => controller.saveReferences(
                  clientTrn: clientTrn,
                  workOrderNumber: workOrderNumber,
                  workOrderDate: workOrderDate,
                  contractNumber: contractNumber,
                  retentionPercent: retentionPercent,
                  expectedProfileVersion: expectedProfileVersion,
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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
    }
    final data = workbench!;
    final canConfirm = data.canConfirmProgress;
    // All claims for the claim-cards row (commercial-gated; empty when the
    // actor lacks access or the list is still loading).
    final claims =
        ref
            .watch(yorksAccountsClaimsListControllerProvider(projectId))
            .valueOrNull
            ?.claims ??
        const <YorksAccountsClaimSummary>[];
    // Evidence the server accepts: operational documents linked to the project.
    final projectDocuments =
        ref
            .watch(yorksV1DocumentWorkspaceProvider(projectId))
            .valueOrNull
            ?.documents ??
        const <YorksV1Document>[];
    final evidenceDocuments = <YorksAccountsEvidenceDoc>[
      for (final doc in projectDocuments)
        if (doc.classification == YorksV1DocumentClassification.operational &&
            !doc.isArchived)
          (id: doc.id, name: doc.currentVersion.fileName),
    ];
    // The claim cards come from their own list, so a change to a claim has to
    // reload it as well as the workbench.
    Future<String?> reloadClaimsAfter(Future<String?> command) async {
      final error = await command;
      if (error != null) return error;
      await ref
          .read(yorksAccountsClaimsListControllerProvider(projectId).notifier)
          .refresh();
      return null;
    }

    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ClaimsTab(
            workbench: data,
            language: language,
            canRecordProgress: canConfirm && data.canPrepareClaim,
            onUploadEvidence: () async {
              final selected = await ref
                  .read(yorksV1DocumentFileServiceProvider)
                  .selectDocument();
              if (selected == null) return null;
              final known = projectDocuments.map((d) => d.id).toSet();
              final workspace = await ref
                  .read(yorksV1DocumentsRepositoryProvider)
                  .upload(
                    YorksV1DocumentUploadInput(
                      projectId: projectId,
                      entityType: YorksV1DocumentEntityType.project,
                      entityId: projectId,
                      classification: YorksV1DocumentClassification.operational,
                      fileName: selected.fileName,
                      mimeType: selected.mimeType,
                      bytes: selected.bytes,
                      idempotencyKey: const Uuid().v4(),
                    ),
                  );
              ref.invalidate(yorksV1DocumentWorkspaceProvider(projectId));
              final added = workspace.documents.where(
                (d) => !known.contains(d.id),
              );
              return added.isEmpty ? null : added.first.id;
            },
            // Site Engineers suggest, and a confirmer without claim access
            // confirms, one cell at a time through the existing checked sheet.
            onUpdateCell:
                (canConfirm && data.canPrepareClaim) ||
                    !(canConfirm || data.canSuggestProgress)
                ? null
                : (cell) async {
                    final progress = await controller.fetchProgress();
                    if (progress == null || !context.mounted) return;
                    final entry = progress.progress.where(
                      (e) => e.progressEntryId == cell.progressEntryId,
                    );
                    if (entry.isEmpty) return;
                    final changed = await showYorksAccountsProgressActionSheet(
                      context,
                      projectId: projectId,
                      entry: entry.first,
                      projection: progress,
                      language: language,
                    );
                    if (!changed) return;
                    await controller.refresh();
                    if (context.mounted) {
                      _showFileMessage(context, language, 'v2_cell_saved');
                    }
                  },
            onPreviewInvoice: !data.canManageInvoices
                ? null
                : (claimId) async {
                    final bytes = await controller.buildInvoicePreview(claimId);
                    if (bytes == null) return 'error';
                    await Printing.layoutPdf(onLayout: (_) async => bytes);
                    return null;
                  },
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
                }) => reloadClaimsAfter(
                  controller.saveWorkbench(
                    claimReference: claimReference,
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    entries: entries,
                    evidenceDocumentIds: evidenceDocumentIds,
                    reason: reason,
                  ),
                ),
            onMarkChecked:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) => reloadClaimsAfter(
                  controller.markChecked(
                    claimId: claimId,
                    expectedVersion: expectedVersion,
                    reason: reason,
                  ),
                ),
            onReopen:
                ({
                  required String claimId,
                  required int expectedVersion,
                  required String reason,
                }) => reloadClaimsAfter(
                  controller.reopenClaim(
                    claimId: claimId,
                    expectedVersion: expectedVersion,
                    reason: reason,
                  ),
                ),
            onIssue:
                ({
                  required String claimId,
                  required int expectedClaimVersion,
                  required String invoiceDate,
                  required String submissionDate,
                  String? invoiceReference,
                }) => reloadClaimsAfter(
                  controller.issueInvoice(
                    claimId: claimId,
                    expectedClaimVersion: expectedClaimVersion,
                    invoiceDate: invoiceDate,
                    submissionDate: submissionDate,
                    invoiceReference: invoiceReference,
                  ),
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

  Future<void> _refreshAfterCheque(WidgetRef ref) async {
    await ref
        .read(yorksAccountsInvoicesControllerProvider(projectId).notifier)
        .refresh();
    final workspace = yorksAccountsWorkspaceControllerProvider(projectId);
    if (ref.exists(workspace)) await ref.read(workspace.notifier).refresh();
  }

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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
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
          // A cleared cheque records a payment, so the invoice figures and the
          // workspace change too; show them without waiting for a tab switch.
          onTransition: (input) async {
            final error = await registerController.transition(input);
            if (error == null) await _refreshAfterCheque(ref);
            return error;
          },
          onReplace: (input) async {
            final error = await registerController.replace(input);
            if (error == null) await _refreshAfterCheque(ref);
            return error;
          },
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
            onRevise: controller.revise,
            onCreatePdc: (input) async {
              final error = await controller.createPdc(input);
              if (error == null) {
                await ref
                    .read(
                      yorksAccountsPdcRegisterControllerProvider(
                        projectId,
                      ).notifier,
                    )
                    .refresh();
              }
              return error;
            },
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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
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
            onAddBill: !projection.commands.createBill
                ? null
                : () async {
                    final saved = await showYorksAccountsSupplierBillDraftSheet(
                      context,
                      projectId: projectId,
                      language: language,
                    );
                    if (saved) await controller.refresh();
                  },
            onOpenBill: (bill) async {
              await showYorksAccountsSupplierBillActionsSheet(
                context,
                projectId: projectId,
                supplierBillId: bill.supplierBillId,
                language: language,
              );
              // Always reload: an edit made inside the sheet leaves it open, so
              // closing it afterwards doesn't report a change.
              await controller.refresh();
            },
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

  Future<void> _addFile(
    BuildContext context,
    YorksV1AccountsDocumentWorkspace workspace,
  ) async {
    final saved = await showYorksAccountsDocumentUploadDialog(
      context,
      projectId: projectId,
      language: language,
      workspace: workspace,
    );
    if (saved == null || !context.mounted) return;
    _showFileMessage(
      context,
      language,
      saved ? 'v2_files_saved' : 'v2_files_failed',
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    YorksV1DocumentVersion version,
  ) async {
    try {
      final bytes = await ref
          .read(yorksAccountsDocumentsControllerProvider(projectId).notifier)
          .download(version);
      await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: bytes,
            fileName: version.fileName,
            mimeType: version.mimeType,
          );
    } catch (_) {
      if (context.mounted) {
        _showFileMessage(context, language, 'v2_files_failed');
      }
    }
  }

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
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
    }
    // Attached files for the Files panel. This controller doesn't load itself, so
    // start it here; a failed load leaves the panel empty, as for no access.
    final docsState = ref.watch(
      yorksAccountsDocumentsControllerProvider(projectId),
    );
    if (docsState.status == YorksAccountsViewStatus.idle) {
      Future.microtask(() async {
        try {
          await ref
              .read(
                yorksAccountsDocumentsControllerProvider(projectId).notifier,
              )
              .load();
        } catch (_) {}
      });
    }
    final docs = docsState.workspace?.documents ?? const [];
    final files = <YorksAccountsHistoryFile>[
      for (final doc in docs)
        (
          name: doc.currentVersion.fileName,
          reference: doc.currentVersion.businessReference,
          uploadedBy: doc.currentVersion.uploadedByDisplayName,
          onDownload: () => _download(context, ref, doc.currentVersion),
        ),
    ];
    final documentsWorkspace = docsState.workspace;
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2HistoryTab(
            projection: projection!,
            language: language,
            files: files,
            onAddFile: documentsWorkspace?.canUpload == true
                ? () => _addFile(context, documentsWorkspace!)
                : null,
          ),
        ),
      ],
    );
  }
}

void _showFileMessage(BuildContext context, AppLanguage language, String key) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(accountsV2Text(language, key))));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.language,
    required this.onRetry,
    this.error,
  });

  final AppLanguage language;
  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    // A refusal is the answer, not a failure: retrying can't change it.
    final failure = error;
    if (failure is YorksV1DomainException &&
        failure.code == YorksV1DomainErrorCode.unauthorized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 32, color: AppColors.muted),
              const SizedBox(height: AppSpacing.sm),
              Text(
                accountsV2Text(language, 'v2_commercial_hidden'),
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
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
