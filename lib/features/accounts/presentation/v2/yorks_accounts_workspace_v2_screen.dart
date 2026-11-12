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
import '../../application/v2/accounts_unsaved_drafts.dart';
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
import 'accounts_v2_safety.dart';
import 'accounts_v2_summary_tab.dart';
import 'accounts_v2_supplier_drawer.dart';
import 'accounts_v2_supplier_tab.dart';
import 'kit/accounts_v2_kit.dart';
import 'kit/accounts_v2_report_buttons.dart';
import 'kit/accounts_v2_setup_checks.dart';
import '../../domain/accounts_records_models.dart' show YorksAccountsReportKind;
import '../../domain/accounts_receivables_models.dart'
    show YorksAccountsDueState;
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

  /// A record the Overview asked to open: the tab opens it once, then clears it.
  String? _focusInvoiceId;
  String? _focusBillId;
  bool _focusRevise = false;

  /// A building and stage the Overview asked the claims tab to open.
  String? _focusBuildingId;
  String? _focusStageKey;

  void _select(YorksAccountsWorkspaceV2Tab tab) {
    if (tab == _tab) return;
    // Leaving a tab with unsaved edits keeps them (the tab hands them to the
    // drafts store as it closes); say so, so nobody thinks they were lost.
    final drafts = ref.read(
      yorksAccountsUnsavedDraftsProvider(widget.projectId),
    );
    final keptKey = switch (_tab) {
      YorksAccountsWorkspaceV2Tab.contract
          when drafts.has(YorksAccountsDraftSection.contract) =>
        'v2u_kept_contract',
      YorksAccountsWorkspaceV2Tab.claims
          when drafts.has(YorksAccountsDraftSection.claimsPrefix) =>
        'v2u_kept_claims',
      _ => null,
    };
    if (keptKey != null) {
      showAccountsV2Message(
        context,
        accountsV2Text(ref.read(languageProvider), keptKey),
      );
    }
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
    final materials = yorksAccountsMaterialSourcesControllerProvider(id);
    switch (tab) {
      case YorksAccountsWorkspaceV2Tab.summary:
        break;
      case YorksAccountsWorkspaceV2Tab.contract:
        final contract = yorksAccountsContractControllerProvider(id);
        refreshIfLoaded(contract.notifier, contract, (c) => c.refresh());
        final variations = yorksAccountsVariationsControllerProvider(id);
        refreshIfLoaded(variations.notifier, variations, (c) => c.refresh());
        refreshIfLoaded(materials.notifier, materials, (c) => c.refresh());
      case YorksAccountsWorkspaceV2Tab.claims:
        final workbench = yorksAccountsWorkbenchControllerProvider(id);
        refreshIfLoaded(workbench.notifier, workbench, (c) => c.refresh());
        final claims = yorksAccountsClaimsListControllerProvider(id);
        refreshIfLoaded(claims.notifier, claims, (c) => c.refresh());
        // Deliveries to site arrive outside Accounts.
        refreshIfLoaded(materials.notifier, materials, (c) => c.refresh());
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

  /// The contract tab's state, so the tab bar's Import Master File button can
  /// start the import the contract tab owns.
  final _contractKey = GlobalKey<AccountsV2ContractTabState>();

  /// Buttons at the end of the tab bar for the open tab (`.subact`).
  List<Widget> _tabActions(AppLanguage language) {
    switch (_tab) {
      case YorksAccountsWorkspaceV2Tab.summary:
        return [
          AccountsV2ReportButton(
            projectId: widget.projectId,
            kind: YorksAccountsReportKind.projectSummary,
            output: AccountsV2ReportOutput.excel,
            language: language,
            icon: 'download',
          ),
          AccountsV2ReportButton(
            projectId: widget.projectId,
            kind: YorksAccountsReportKind.projectSummary,
            output: AccountsV2ReportOutput.print,
            language: language,
          ),
        ];
      case YorksAccountsWorkspaceV2Tab.contract:
        final setup = ref
            .watch(yorksAccountsContractControllerProvider(widget.projectId))
            .valueOrNull;
        if (setup == null || !setup.canConfigure) return const [];
        return [
          AccountsV2Button(
            label: accountsV2Text(language, 'v2_import_master'),
            icon: 'upload',
            onPressed: () => _contractKey.currentState?.startImport(),
          ),
        ];
      case YorksAccountsWorkspaceV2Tab.claims:
      case YorksAccountsWorkspaceV2Tab.invoices:
      case YorksAccountsWorkspaceV2Tab.supplierBills:
      case YorksAccountsWorkspaceV2Tab.history:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    // The workspace projection carries the claim and supplier badges; the
    // contract and invoices give the setup and overdue counts. Each falls back
    // to no badge while it loads or when the person cannot see it.
    final workspace = ref
        .watch(yorksAccountsWorkspaceControllerProvider(widget.projectId))
        .valueOrNull;
    final badges = workspace?.badges ?? YorksAccountsWorkspaceBadges.empty;
    final setup = ref
        .watch(yorksAccountsContractControllerProvider(widget.projectId))
        .valueOrNull;
    final setupToFix = setup == null || !setup.hasBaseline
        ? 0
        : accountsV2SetupChecks(setup).where((c) => !c.ok).length;
    final invoices = ref
        .watch(yorksAccountsInvoicesControllerProvider(widget.projectId))
        .valueOrNull;
    final overdueInvoices =
        invoices?.invoices
            .where((i) => i.dueState == YorksAccountsDueState.overdue)
            .length ??
        0;
    final drafts = ref.watch(
      yorksAccountsUnsavedDraftsProvider(widget.projectId),
    );
    return LayoutBuilder(
      builder: (context, constraints) => AccountsV2Viewport(
        width: AccountsV2Viewport.fromWorkspace(constraints.maxWidth),
        child: Builder(
          builder: (context) => _page(
            context,
            language,
            badges,
            setupToFix,
            overdueInvoices,
            drafts,
          ),
        ),
      ),
    );
  }

  Widget _page(
    BuildContext context,
    AppLanguage language,
    YorksAccountsWorkspaceBadges badges,
    int setupToFix,
    int overdueInvoices,
    YorksAccountsUnsavedDrafts drafts,
  ) {
    final unsaved = (accountsV2Text(language, 'v2u_badge'), true);
    final phone = AccountsV2Breakpoints.isPhone(context);
    return ColoredBox(
      color: AccountsV2Colors.bg,
      child: SingleChildScrollView(
        padding: phone
            ? const EdgeInsets.fromLTRB(14, 12, 14, 50)
            : const EdgeInsets.fromLTRB(18, 16, 18, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SubBar(
              selected: _tab,
              language: language,
              badges: {
                if (drafts.has(YorksAccountsDraftSection.contract))
                  YorksAccountsWorkspaceV2Tab.contract: unsaved
                else if (setupToFix > 0)
                  YorksAccountsWorkspaceV2Tab.contract: ('$setupToFix', true),
                if (drafts.has(YorksAccountsDraftSection.claimsPrefix))
                  YorksAccountsWorkspaceV2Tab.claims: unsaved
                else if (badges.claimsDraft)
                  YorksAccountsWorkspaceV2Tab.claims: (
                    accountsV2Text(language, 'v2_badge_draft'),
                    false,
                  ),
                if (overdueInvoices > 0)
                  YorksAccountsWorkspaceV2Tab.invoices: (
                    '$overdueInvoices',
                    true,
                  ),
                if ((badges.supplierCount ?? 0) > 0)
                  YorksAccountsWorkspaceV2Tab.supplierBills: (
                    '${badges.supplierCount}',
                    false,
                  ),
              },
              actions: _tabActions(language),
              onSelected: _select,
            ),
            const SizedBox(height: accountsV2Gap),
            _buildBody(language),
          ],
        ),
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
          onOpenTarget: (target) {
            _focusInvoiceId = target.invoiceId;
            _focusBillId = target.billId;
            _select(target.tab);
          },
          onOpenCell: (stageKey, buildingScopeId) {
            _focusStageKey = stageKey;
            _focusBuildingId = buildingScopeId;
            _select(YorksAccountsWorkspaceV2Tab.claims);
          },
        );
      case YorksAccountsWorkspaceV2Tab.contract:
        return _ContractBody(
          projectId: widget.projectId,
          language: language,
          tabKey: _contractKey,
        );
      case YorksAccountsWorkspaceV2Tab.claims:
        final building = _focusBuildingId;
        final stage = _focusStageKey;
        _focusBuildingId = null;
        _focusStageKey = null;
        return _ClaimsBody(
          projectId: widget.projectId,
          language: language,
          focusBuildingId: building,
          focusStageKey: stage,
          onOpenContract: () => _select(YorksAccountsWorkspaceV2Tab.contract),
          onOpenInvoice: (invoiceId, {bool revise = false}) {
            _focusInvoiceId = invoiceId;
            _focusRevise = revise;
            _select(YorksAccountsWorkspaceV2Tab.invoices);
          },
        );
      case YorksAccountsWorkspaceV2Tab.invoices:
        return _InvoicesBody(
          projectId: widget.projectId,
          language: language,
          focusInvoiceId: _focusInvoiceId,
          focusRevise: _focusRevise,
          onFocusHandled: () {
            _focusInvoiceId = null;
            _focusRevise = false;
          },
          onOpenClaims: () => _select(YorksAccountsWorkspaceV2Tab.claims),
        );
      case YorksAccountsWorkspaceV2Tab.supplierBills:
        return _SupplierBody(
          projectId: widget.projectId,
          language: language,
          focusBillId: _focusBillId,
          onFocusHandled: () => _focusBillId = null,
        );
      case YorksAccountsWorkspaceV2Tab.history:
        return _HistoryBody(
          projectId: widget.projectId,
          language: language,
          onOpenTarget: (target) {
            _focusInvoiceId = target.invoiceId;
            _focusBillId = target.billId;
            _select(target.tab);
          },
        );
    }
  }
}

// ─── Tab bar ────────────────────────────────────────────────────────────────

/// The prototype icon for each tab.
String _tabIcon(YorksAccountsWorkspaceV2Tab tab) => switch (tab) {
  YorksAccountsWorkspaceV2Tab.summary => 'grid',
  YorksAccountsWorkspaceV2Tab.contract => 'doc',
  YorksAccountsWorkspaceV2Tab.claims => 'chart',
  YorksAccountsWorkspaceV2Tab.invoices => 'receipt',
  YorksAccountsWorkspaceV2Tab.supplierBills => 'archive',
  YorksAccountsWorkspaceV2Tab.history => 'history',
};

/// Underlined tabs on one ruled line, with the open tab's buttons at the end
/// (`.subbar`, `.atabs`, `.subact`). Narrow windows put the buttons below.
class _SubBar extends StatelessWidget {
  const _SubBar({
    required this.selected,
    required this.language,
    required this.badges,
    required this.actions,
    required this.onSelected,
  });

  final YorksAccountsWorkspaceV2Tab selected;
  final AppLanguage language;

  /// Badge text and whether it is a warning in red, per tab.
  final Map<YorksAccountsWorkspaceV2Tab, (String, bool)> badges;
  final List<Widget> actions;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, tab)
                in YorksAccountsWorkspaceV2Tab.values.indexed) ...[
              if (i > 0) const SizedBox(width: 4),
              _KeepInViewWhenSelected(
                selected: tab == selected,
                child: _SubTab(
                  icon: _tabIcon(tab),
                  label: accountsV2Text(language, tab.labelKey),
                  badge: badges[tab],
                  selected: tab == selected,
                  onTap: () => onSelected(tab),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final actionRow = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: actions,
    );
    if (actions.isEmpty) return tabs;
    if (AccountsV2Breakpoints.isNarrow(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tabs,
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerEnd, child: actionRow),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: tabs),
        const SizedBox(width: 12),
        actionRow,
      ],
    );
  }
}

/// Scrolls a tab into view when it becomes the selected one, so a phone always
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

/// One sub-tab (`.atab`): 44 high, pale blue and underlined when open.
class _SubTab extends StatelessWidget {
  const _SubTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String icon;
  final String label;
  final bool selected;
  final (String, bool)? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AccountsV2Colors.pri : AccountsV2Colors.ink2;
    const radius = BorderRadius.vertical(top: Radius.circular(8));
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, ${badge!.$1}',
      child: Material(
        color: selected ? AccountsV2Colors.pri50 : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey<bool>(selected),
          borderRadius: radius,
          onTap: onTap,
          hoverColor: selected ? Colors.transparent : AccountsV2Colors.hover,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? AccountsV2Colors.pri : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AccountsV2Icon(icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  style: v2Style(
                    12.5,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                    height: 1.2,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  AccountsV2TabBadge(badge!.$1, bad: badge!.$2),
                ],
              ],
            ),
          ),
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
    required this.onOpenTarget,
    required this.onOpenCell,
  });

  final String projectId;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onOpenTab;
  final ValueChanged<AccountsV2OverviewTarget> onOpenTarget;
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

    if (state.isLoading && workspace == null) return const _Loading();
    if (state.hasError && workspace == null) {
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
    }
    final ws = workspace!;
    // The records behind Needs Attention, read only where this person may see
    // them; each stays null (server summary lines instead) until it loads.
    final values = ws.capabilities.viewProjectCommercialValues;
    final setup = ref
        .watch(yorksAccountsContractControllerProvider(projectId))
        .valueOrNull;
    final invoices = values
        ? ref
              .watch(yorksAccountsInvoicesControllerProvider(projectId))
              .valueOrNull
              ?.invoices
        : null;
    final cheques = values
        ? ref
              .watch(yorksAccountsPdcRegisterControllerProvider(projectId))
              .valueOrNull
              ?.pdcs
        : null;
    final claims = values
        ? ref
              .watch(yorksAccountsClaimsListControllerProvider(projectId))
              .valueOrNull
              ?.claims
        : null;
    final bills = ws.capabilities.viewSupplierCosts
        ? ref
              .watch(yorksAccountsSupplierBillsControllerProvider(projectId))
              .valueOrNull
              ?.items
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.hasError) ...[
          _ErrorBanner(language: language, onRetry: controller.load),
          const SizedBox(height: accountsV2Gap),
        ],
        AccountsV2SummaryTab(
          workspace: ws,
          language: language,
          setup: setup,
          invoices: invoices,
          cheques: cheques,
          claims: claims,
          bills: bills,
          onOpenTab: onOpenTab,
          onOpenTarget: onOpenTarget,
          onOpenCell: onOpenCell,
        ),
      ],
    );
  }
}

class _ContractBody extends ConsumerWidget {
  const _ContractBody({
    required this.projectId,
    required this.language,
    required this.tabKey,
  });

  final String projectId;
  final AppLanguage language;
  final GlobalKey<AccountsV2ContractTabState> tabKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAccountsContractControllerProvider(projectId));
    final controller = ref.read(
      yorksAccountsContractControllerProvider(projectId).notifier,
    );
    final setup = state.valueOrNull;

    if (state.isLoading && setup == null) {
      return const _Loading();
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
    final materialSources = ref
        .watch(yorksAccountsMaterialSourcesControllerProvider(projectId))
        .valueOrNull;
    final materialController = ref.read(
      yorksAccountsMaterialSourcesControllerProvider(projectId).notifier,
    );
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        AccountsV2ContractTab(
          key: tabKey,
          setup: data,
          drafts: ref.read(yorksAccountsUnsavedDraftsProvider(projectId)),
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
          materialSources: materialSources,
          onSaveMaterialLinks: (links, reason) =>
              materialController.saveLinks(links: links, reason: reason),
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
          // A new contract revision can change the items deliveries count
          // against, so the BOQ links read again after one.
          onApplyImport: (setup, note) async {
            final error = await controller.saveSetup(
              setup: setup,
              expectedProfileVersion: data.profileVersion,
              note: note,
            );
            if (error == null) await materialController.refresh();
            return error;
          },
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
          onSave: (form, expectedProfileVersion) async {
            final error = await controller.saveSetup(
              setup: form,
              expectedProfileVersion: expectedProfileVersion,
            );
            if (error == null) await materialController.refresh();
            return error;
          },
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
      ],
    );
  }
}

class _ClaimsBody extends ConsumerWidget {
  const _ClaimsBody({
    required this.projectId,
    required this.language,
    required this.onOpenContract,
    required this.onOpenInvoice,
    this.focusBuildingId,
    this.focusStageKey,
  });

  final String projectId;
  final AppLanguage language;
  final VoidCallback onOpenContract;
  final YorksOpenInvoiceAction onOpenInvoice;
  final String? focusBuildingId;
  final String? focusStageKey;

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
      return const _Loading();
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
    final claimsState = ref.watch(
      yorksAccountsClaimsListControllerProvider(projectId),
    );
    final claims =
        claimsState.valueOrNull?.claims ?? const <YorksAccountsClaimSummary>[];
    final setup = ref
        .watch(yorksAccountsContractControllerProvider(projectId))
        .valueOrNull;
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

    // Saving rebuilds the draft under a new id and deleting ends it, so both
    // return the workbench to the open claim.
    Future<String?> thenOpenClaim(Future<String?> command) async {
      final error = await reloadClaimsAfter(command);
      if (error == null && controller.activeClaimId != null) {
        await controller.selectClaim(null);
      }
      return error;
    }

    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        AccountsV2ClaimsTab(
          workbench: data,
          language: language,
          drafts: ref.read(yorksAccountsUnsavedDraftsProvider(projectId)),
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
          // Without commercial access the list is empty by design, so it
          // counts as loaded once it stops loading.
          claimsLoaded: !claimsState.isLoading || claimsState.hasValue,
          setup: setup,
          materialSources: ref
              .watch(yorksAccountsMaterialSourcesControllerProvider(projectId))
              .valueOrNull,
          onOpenContract: onOpenContract,
          onOpenInvoice: onOpenInvoice,
          focusBuildingId: focusBuildingId,
          focusStageKey: focusStageKey,
          onSelectClaim: (id) => controller.selectClaim(id),
          onCancelClaim:
              ({
                required String claimId,
                required int expectedVersion,
                required String reason,
              }) => thenOpenClaim(
                controller.cancelClaim(
                  claimId: claimId,
                  expectedVersion: expectedVersion,
                  reason: reason,
                ),
              ),
          onRestoreClaim:
              ({
                required String claimId,
                required int expectedVersion,
                required String reason,
              }) => thenOpenClaim(
                controller.restoreClaim(
                  claimId: claimId,
                  expectedVersion: expectedVersion,
                  reason: reason,
                ),
              ),
          onSaveWorkbench:
              ({
                String? claimReference,
                required String periodStart,
                required String periodEnd,
                required List<Map<String, Object?>> entries,
                required List<String> evidenceDocumentIds,
                String? reason,
              }) => thenOpenClaim(
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
      ],
    );
  }
}

class _InvoicesBody extends ConsumerWidget {
  const _InvoicesBody({
    required this.projectId,
    required this.language,
    required this.onOpenClaims,
    this.focusInvoiceId,
    this.focusRevise = false,
    this.onFocusHandled,
  });

  final String projectId;
  final AppLanguage language;
  final VoidCallback onOpenClaims;
  final String? focusInvoiceId;
  final bool focusRevise;
  final VoidCallback? onFocusHandled;

  Future<void> _attach(
    BuildContext context,
    YorksV1AccountsDocumentWorkspace workspace,
    String invoiceId,
  ) async {
    final saved = await showYorksAccountsDocumentUploadDialog(
      context,
      projectId: projectId,
      language: language,
      workspace: workspace,
      initialType: YorksV1AccountsDocumentType.clientInvoice,
      initialTargetEntityId: invoiceId,
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

  Future<void> _refreshAfterCheque(WidgetRef ref) async {
    await ref
        .read(yorksAccountsInvoicesControllerProvider(projectId).notifier)
        .refresh();
    final workspace = yorksAccountsWorkspaceControllerProvider(projectId);
    if (ref.exists(workspace)) await ref.read(workspace.notifier).refresh();
  }

  /// A payment or cancellation can move a cheque and every figure around it.
  Future<String?> _thenRefreshAll(
    WidgetRef ref,
    Future<String?> Function() command,
  ) async {
    final error = await command();
    if (error != null) return error;
    await ref
        .read(yorksAccountsPdcRegisterControllerProvider(projectId).notifier)
        .refresh();
    final workspace = yorksAccountsWorkspaceControllerProvider(projectId);
    if (ref.exists(workspace)) await ref.read(workspace.notifier).refresh();
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAccountsInvoicesControllerProvider(projectId));
    final controller = ref.read(
      yorksAccountsInvoicesControllerProvider(projectId).notifier,
    );
    final projection = state.valueOrNull;

    if (state.isLoading && projection == null) {
      return const _Loading();
    }
    if (state.hasError && projection == null) {
      return _ErrorState(
        language: language,
        onRetry: controller.load,
        error: state.error,
      );
    }

    // Claim numbers (#01 …) for the tracker, oldest claim first.
    final claims =
        ref
            .watch(yorksAccountsClaimsListControllerProvider(projectId))
            .valueOrNull
            ?.claims ??
        const <YorksAccountsClaimSummary>[];
    final live = [
      for (final c in claims.reversed)
        if (c.status != 'cancelled') c,
    ];
    final claimNumbers = {
      for (final (i, c) in live.indexed) c.claimId: c.claimNumber ?? i + 1,
    };
    // Files attached to each invoice, from the Accounts documents.
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
    final docsWorkspace = docsState.workspace;
    List<AccountsV2InvoiceFile> filesFor(String invoiceId) => [
      for (final doc in docsWorkspace?.documents ?? const <YorksV1Document>[])
        if (doc.isLinkedTo(
          YorksV1DocumentEntityType.accountsClientInvoice,
          invoiceId,
        ))
          (
            name: doc.currentVersion.fileName,
            onOpen: () => _download(context, ref, doc.currentVersion),
          ),
    ];

    // Cheque register: commercial, so the whole card is drawn only with
    // view_project_commercial_values. The read is gated server-side too; here we
    // simply omit it when the actor cannot see values or the register is empty.
    Widget? registerCard;
    if (projection!.capabilities.canViewValues) {
      final registerState = ref.watch(
        yorksAccountsPdcRegisterControllerProvider(projectId),
      );
      final register = registerState.valueOrNull;
      if (register != null) {
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
          onEdit: (input) async {
            final error = await registerController.edit(input);
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
        AccountsV2InvoicesTab(
          projection: projection,
          language: language,
          onCertify: controller.certify,
          onPay: controller.pay,
          onReversePayment: (input) =>
              _thenRefreshAll(ref, () => controller.reversePayment(input)),
          onCorrectPayment: (input) =>
              _thenRefreshAll(ref, () => controller.correctPayment(input)),
          onCorrectCertification: (input) => _thenRefreshAll(
            ref,
            () => controller.correctCertification(input),
          ),
          onCancelInvoice: (input) =>
              _thenRefreshAll(ref, () => controller.cancelInvoice(input)),
          onRestoreInvoice: (input) =>
              _thenRefreshAll(ref, () => controller.restoreInvoice(input)),
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
          claimNumbers: claimNumbers,
          filesFor: filesFor,
          onAttach: docsWorkspace?.canUpload == true
              ? (invoiceId) => _attach(context, docsWorkspace!, invoiceId)
              : null,
          onOpenClaims: onOpenClaims,
          focusInvoiceId: focusInvoiceId,
          focusRevise: focusRevise,
          onFocusHandled: onFocusHandled,
        ),
      ],
    );
  }
}

class _SupplierBody extends ConsumerWidget {
  const _SupplierBody({
    required this.projectId,
    required this.language,
    this.focusBillId,
    this.onFocusHandled,
  });

  final String projectId;
  final AppLanguage language;
  final String? focusBillId;
  final VoidCallback? onFocusHandled;

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
      return const _Loading();
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
        AccountsV2SupplierTab(
          projection: projection!,
          language: language,
          onAddBill: !projection.commands.createBill
              ? null
              : () async {
                  final saved = await showAccountsV2SupplierBillForm(
                    context,
                    projectId: projectId,
                    language: language,
                  );
                  if (saved) await controller.refresh();
                },
          onOpenBill: (bill) async {
            await showAccountsV2SupplierBillDrawer(
              context,
              projectId: projectId,
              bill: bill,
              language: language,
            );
            // Always reload: an edit made inside the drawer leaves it open, so
            // closing it afterwards doesn't report a change.
            await controller.refresh();
          },
          invoicedTotal: invoicedTotal,
          focusBillId: focusBillId,
          onFocusHandled: onFocusHandled,
        ),
      ],
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({
    required this.projectId,
    required this.language,
    this.onOpenTarget,
  });

  final String projectId;
  final AppLanguage language;
  final ValueChanged<AccountsV2OverviewTarget>? onOpenTarget;

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
      return const _Loading();
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
          id: doc.id,
        ),
    ];
    final documentsWorkspace = docsState.workspace;
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        AccountsV2HistoryTab(
          projection: projection!,
          language: language,
          files: files,
          onAddFile: documentsWorkspace?.canUpload == true
              ? () => _addFile(context, documentsWorkspace!)
              : null,
          onOpenRecord: onOpenTarget,
        ),
      ],
    );
  }
}

/// A spinner with room around it, inside the page scroll.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 80),
    child: Center(child: CircularProgressIndicator()),
  );
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
