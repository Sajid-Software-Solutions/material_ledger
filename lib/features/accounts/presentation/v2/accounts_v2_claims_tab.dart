/// R39 Accounts Workspace V2 — Progress & claims tab (P6, read view).
///
/// Shows the claim workbench (`v1_get_claim_workbench`): the current open claim
/// (reference, pipeline status, period, gross) and the confirmed progress by
/// building × stage, with the per-item breakdown for items-mode cells. Monetary
/// columns are drawn only with view_project_commercial_values. Confirming
/// progress, editing claim lines and issuing the invoice are a later P6
/// increment; this slice presents the current position read-only.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/claim_workbench_models.dart';
import 'accounts_v2_common.dart';

class AccountsV2ClaimsTab extends StatelessWidget {
  const AccountsV2ClaimsTab({
    super.key,
    required this.workbench,
    required this.language,
  });

  final YorksAccountsWorkbench workbench;
  final AppLanguage language;

  bool get _canValues =>
      workbench.capabilities['view_project_commercial_values'] == true;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final format = const AccountsV2Format();

    if (workbench.baselineRevisionId == null) {
      return _Empty(message: _t('v2_claims_need_baseline'));
    }

    // Order unique stages by position, keep each stage's cells by building.
    final stageOrder = <String>[];
    final stageLabels = <String, String>{};
    final cellsByStage = <String, List<YorksAccountsWorkbenchCell>>{};
    final sorted = [...workbench.cells]
      ..sort((a, b) {
        final byStage = a.stagePosition.compareTo(b.stagePosition);
        return byStage != 0
            ? byStage
            : a.buildingName.compareTo(b.buildingName);
      });
    for (final c in sorted) {
      if (!stageOrder.contains(c.stageKey)) {
        stageOrder.add(c.stageKey);
        stageLabels[c.stageKey] = c.stageLabel ?? c.stageKey;
      }
      cellsByStage.putIfAbsent(c.stageKey, () => []).add(c);
    }

    final grid = <Widget>[
      for (final stageKey in stageOrder) ...[
        _StageSection(
          title: stageLabels[stageKey] ?? stageKey,
          cells: cellsByStage[stageKey]!,
          canValues: _canValues,
          language: language,
          format: format,
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    ];
    if (grid.isNotEmpty) grid.removeLast();

    final aside = _ClaimSidePanel(
      workbench: workbench,
      canValues: _canValues,
      language: language,
      format: format,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSpacing.stackedBreakpoint;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              aside,
              const SizedBox(height: AppSpacing.lg),
              ...grid,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: grid,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(width: AppSpacing.inspectorWidth, child: aside),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Claim side panel ────────────────────────────────────────────────────────

class _ClaimSidePanel extends StatelessWidget {
  const _ClaimSidePanel({
    required this.workbench,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkbench workbench;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final claim = workbench.claim;
    if (claim == null) {
      return AccountsV2Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountsV2SectionTitle(_t('v2_claim_title')),
            const SizedBox(height: AppSpacing.sm),
            Text(_t('v2_claims_no_claim'), style: AppTypography.bodyMedium),
          ],
        ),
      );
    }
    final status = claim['status'] as String? ?? 'draft';
    final reference = claim['claim_reference'] as String? ?? '—';
    final periodStart = claim['claim_period_start'] as String?;
    final periodEnd = claim['claim_period_end'] as String?;
    final period = (periodStart != null && periodEnd != null)
        ? '$periodStart → $periodEnd'
        : '—';
    final gross = YorksAccountsDecimal.tryParse(
      claim['claimed_ex_vat'] as String? ?? '',
    );
    final lineCount = (claim['lines'] as List?)?.length ?? 0;

    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reference,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
              _ClaimStatusChip(status: status, language: language),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ClaimPipeline(status: status, language: language),
          const SizedBox(height: AppSpacing.md),
          _PanelRow(label: _t('v2_claim_period'), value: period),
          _PanelRow(label: _t('v2_claim_lines'), value: '$lineCount'),
          if (canValues)
            _PanelRow(
              label: _t('v2_claim_gross'),
              value: format.money(gross),
              emphasize: true,
            ),
        ],
      ),
    );
  }
}

class _ClaimPipeline extends StatelessWidget {
  const _ClaimPipeline({required this.status, required this.language});

  final String status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, int)>[
      (accountsV2Text(language, 'v2_claim_status_draft'), 0),
      (accountsV2Text(language, 'v2_claim_status_checked'), 1),
      (accountsV2Text(language, 'v2_claim_status_invoiced'), 2),
    ];
    final current = switch (status) {
      'ready_for_accounts' => 1,
      'invoiced' => 2,
      _ => 0,
    };
    return Row(
      children: [
        for (final step in steps) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: step.$2 <= current
                        ? AppColors.primary
                        : AppColors.line,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  step.$1,
                  style: AppTypography.labelSmall.copyWith(
                    color: step.$2 == current
                        ? AppColors.primary
                        : AppColors.muted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (step.$2 < 2) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ClaimStatusChip extends StatelessWidget {
  const _ClaimStatusChip({required this.status, required this.language});

  final String status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = switch (status) {
      'invoiced' => ('v2_claim_status_invoiced', NexusStatusTone.success),
      'ready_for_accounts' => ('v2_claim_status_checked', NexusStatusTone.info),
      _ => ('v2_claim_status_draft', NexusStatusTone.neutral),
    };
    return StatusChip(label: accountsV2Text(language, key), tone: tone);
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (emphasize
                          ? AppTypography.titleSmall
                          : AppTypography.bodyMedium)
                      .copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stage section (progress grid) ───────────────────────────────────────────

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.title,
    required this.cells,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final String title;
  final List<YorksAccountsWorkbenchCell> cells;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(title),
          const SizedBox(height: AppSpacing.sm),
          for (final cell in cells) ...[
            _CellRow(
              cell: cell,
              canValues: canValues,
              language: language,
              format: format,
            ),
            if (cell.isItemsMode && cell.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (final item in cell.items)
                      _ItemRow(
                        item: item,
                        canValues: canValues,
                        language: language,
                        format: format,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.cell,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkbenchCell cell;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cell.buildingName,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.ink,
                  ),
                ),
                if (cell.isItemsMode)
                  Text(
                    accountsV2Text(language, 'v2_mode_items'),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 68,
            child: Text(
              format.percent(cell.confirmedPercent),
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            ),
          ),
          if (canValues) ...[
            _MoneyCol(
              label: accountsV2Text(language, 'v2_col_eligible'),
              value: format.money(cell.eligible),
            ),
            _MoneyCol(
              label: accountsV2Text(language, 'v2_col_claimed'),
              value: format.money(cell.claimed),
            ),
            _MoneyCol(
              label: accountsV2Text(language, 'v2_col_available'),
              value: format.money(cell.available),
              danger: cell.overClaimed,
            ),
          ],
        ],
      ),
    );
  }
}

class _MoneyCol extends StatelessWidget {
  const _MoneyCol({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: danger ? AppColors.error : AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.canValues,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkbenchItem item;
  final bool canValues;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    item.itemLabel,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.needsReview) ...[
                  const SizedBox(width: AppSpacing.xs),
                  StatusChip.warning(
                    accountsV2Text(language, 'v2_needs_review'),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '${item.confirmedQty.displayText(maximumFractionDigits: 2)} / ${item.quantity.displayText(maximumFractionDigits: 2)} ${item.unitCode}',
              textAlign: TextAlign.end,
              style: AppTypography.bodySmall,
            ),
          ),
          if (canValues)
            SizedBox(
              width: 120,
              child: Text(
                format.money(item.itemValue),
                textAlign: TextAlign.end,
                style: AppTypography.bodySmall.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timeline_outlined,
              size: 32,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
