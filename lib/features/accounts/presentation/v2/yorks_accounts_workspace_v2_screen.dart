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

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../application/v2/accounts_workspace_v2_controllers.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import 'accounts_v2_claims_tab.dart';
import 'accounts_v2_common.dart';
import 'accounts_v2_contract_tab.dart';
import 'accounts_v2_summary_tab.dart';

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
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabBar(selected: _tab, language: language, onSelected: _select),
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
      case YorksAccountsWorkspaceV2Tab.supplierBills:
      case YorksAccountsWorkspaceV2Tab.history:
        return _ComingSoon(language: language, tab: _tab);
    }
  }
}

// ─── Tab bar ────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.language,
    required this.onSelected,
  });

  final YorksAccountsWorkspaceV2Tab selected;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            for (final tab in YorksAccountsWorkspaceV2Tab.values)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: _TabChip(
                  tab: tab,
                  selected: tab == selected,
                  label: accountsV2Text(language, tab.labelKey),
                  onTap: () => onSelected(tab),
                ),
              ),
          ],
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
  });

  final YorksAccountsWorkspaceV2Tab tab;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.inkSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
                children: [
                  Icon(tab.icon, size: 16, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: AppTypography.titleSmall.copyWith(color: fg),
                  ),
                ],
              ),
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
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ContractTab(setup: setup!, language: language),
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
    return Column(
      children: [
        if (state.hasError)
          _ErrorBanner(language: language, onRetry: controller.load),
        Expanded(
          child: AccountsV2ClaimsTab(workbench: workbench!, language: language),
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

// ─── Placeholder for not-yet-built tabs ──────────────────────────────────────

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.language, required this.tab});

  final AppLanguage language;
  final YorksAccountsWorkspaceV2Tab tab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 32, color: AppColors.muted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              accountsV2Text(language, tab.labelKey),
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              accountsV2Text(language, 'v2_coming_soon_body'),
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
