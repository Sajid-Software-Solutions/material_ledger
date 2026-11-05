/// R39 Accounts Workspace V2 — Summary tab (P6).
///
/// Renders the Summary projection (`v1_get_project_accounts_workspace`):
/// the four-step strip, KPI tiles, the contract money-flow bar, the
/// needs-attention list, the cash position and the building × stage heatmap.
/// Commercial blocks are absent (not zeroed) when the actor lacks the
/// capability, so each is drawn only when its model is present.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/accounts_workspace_models.dart';
import 'accounts_v2_common.dart';

/// Maps a workspace step key to the tab it jumps to.
YorksAccountsWorkspaceV2Tab _tabForStep(String stepKey) => switch (stepKey) {
  'setup' => YorksAccountsWorkspaceV2Tab.contract,
  'progress' => YorksAccountsWorkspaceV2Tab.claims,
  'invoice' => YorksAccountsWorkspaceV2Tab.invoices,
  'paid' => YorksAccountsWorkspaceV2Tab.invoices,
  _ => YorksAccountsWorkspaceV2Tab.summary,
};

class AccountsV2SummaryTab extends StatelessWidget {
  const AccountsV2SummaryTab({
    super.key,
    required this.workspace,
    required this.language,
    required this.format,
    required this.onOpenTab,
    required this.onAttentionAction,
    required this.onOpenCell,
    this.onExportCsv,
  });

  final YorksAccountsWorkspace workspace;
  final AppLanguage language;
  final AccountsV2Format format;
  final ValueChanged<YorksAccountsWorkspaceV2Tab> onOpenTab;
  final ValueChanged<YorksAccountsWorkspaceAttention> onAttentionAction;
  final void Function(String stageKey, String buildingScopeId) onOpenCell;
  final VoidCallback? onExportCsv;

  @override
  Widget build(BuildContext context) {
    final kpis = workspace.kpis;
    final moneyFlow = workspace.moneyFlow;
    final cash = workspace.cash;
    final heatmap = workspace.heatmap;

    final children = <Widget>[
      _StepStrip(
        steps: workspace.steps,
        language: language,
        onTap: (step) => onOpenTab(_tabForStep(step.key)),
      ),
      const SizedBox(height: AppSpacing.lg),
    ];

    if (kpis != null) {
      children
        ..add(
          _KpiRow(
            kpis: kpis,
            supplier: workspace.supplier,
            language: language,
            format: format,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.lg));
      if (moneyFlow != null) {
        children
          ..add(
            _MoneyFlowCard(
              moneyFlow: moneyFlow,
              contractValue: kpis.contractValue,
              language: language,
              format: format,
              onExportCsv: onExportCsv,
            ),
          )
          ..add(const SizedBox(height: AppSpacing.lg));
      }
    } else {
      children
        ..add(
          _NoCommercialCard(
            workspace: workspace,
            language: language,
            onSetup: () => onOpenTab(YorksAccountsWorkspaceV2Tab.contract),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.lg));
    }

    children
      ..add(
        _AttentionCard(
          attention: workspace.attention,
          language: language,
          onAction: onAttentionAction,
        ),
      )
      ..add(const SizedBox(height: AppSpacing.lg));

    if (cash != null) {
      children
        ..add(_CashCard(cash: cash, language: language, format: format))
        ..add(const SizedBox(height: AppSpacing.lg));
    }

    if (heatmap.isNotEmpty && kpis != null) {
      children.add(
        _HeatmapCard(
          cells: heatmap,
          language: language,
          format: format,
          onOpenCell: onOpenCell,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: children,
    );
  }
}

// ─── Step strip ────────────────────────────────────────────────────────────

class _StepStrip extends StatelessWidget {
  const _StepStrip({
    required this.steps,
    required this.language,
    required this.onTap,
  });

  final List<YorksAccountsWorkspaceStep> steps;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceStep> onTap;

  static const _icons = <String, IconData>{
    'setup': Icons.tune_outlined,
    'progress': Icons.timeline_outlined,
    'invoice': Icons.receipt_long_outlined,
    'paid': Icons.payments_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppSpacing.compactBreakpoint;
          final tiles = <Widget>[];
          for (var i = 0; i < steps.length; i++) {
            tiles.add(
              Expanded(
                child: _StepTile(
                  step: steps[i],
                  icon: _icons[steps[i].key] ?? Icons.circle_outlined,
                  language: language,
                  onTap: () => onTap(steps[i]),
                ),
              ),
            );
            if (!compact && i < steps.length - 1) {
              tiles.add(const _StepConnector());
            }
          }
          return compact
              ? Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      _StepTile(
                        step: steps[i],
                        icon: _icons[steps[i].key] ?? Icons.circle_outlined,
                        language: language,
                        onTap: () => onTap(steps[i]),
                        dense: true,
                      ),
                      if (i < steps.length - 1)
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: tiles,
                );
        },
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: AppColors.line,
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.icon,
    required this.language,
    required this.onTap,
    this.dense = false,
  });

  final YorksAccountsWorkspaceStep step;
  final IconData icon;
  final AppLanguage language;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color accent;
    final Color background;
    if (step.isDone) {
      accent = AppColors.success;
      background = AppColors.successContainer;
    } else if (step.isCurrent) {
      accent = AppColors.primary;
      background = AppColors.blueContainer;
    } else {
      accent = AppColors.muted;
      background = AppColors.surfaceContainer;
    }
    final label = accountsV2Text(language, 'v2_step_${step.key}');
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: dense ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: dense
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: step.isDone
                    ? Icon(Icons.check, size: 16, color: accent)
                    : Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.titleSmall.copyWith(
                    color: step.state.isEmpty ? AppColors.muted : AppColors.ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KPI row ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.kpis,
    required this.supplier,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkspaceKpis kpis;
  final YorksAccountsWorkspaceSupplier? supplier;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    final invoicedRatio = format.ratio(kpis.invoiced, kpis.contractValue);
    final tiles = <Widget>[
      _KpiTile(
        title: accountsV2Text(language, 'v2_kpi_contract'),
        value: format.money(kpis.contractValue),
        caption:
            '${format.money(kpis.contractInclVat)} ${accountsV2Text(language, 'v2_incl_vat')}',
      ),
      _KpiTile(
        title: accountsV2Text(language, 'v2_kpi_invoiced'),
        value: format.money(kpis.invoiced),
        caption:
            '${format.percentOfRatio(invoicedRatio)} ${accountsV2Text(language, 'v2_of_contract')} · ${accountsV2Text(language, 'v2_excl_vat')}',
      ),
      _KpiTile(
        title: accountsV2Text(language, 'v2_kpi_received'),
        value: format.money(kpis.received),
        caption: accountsV2Text(language, 'v2_cleared_money'),
        accent: AppColors.success,
      ),
      _KpiTile(
        title: accountsV2Text(language, 'v2_kpi_outstanding'),
        value: format.money(kpis.outstanding),
        caption: kpis.chequesInHand.isPositive
            ? '${format.money(kpis.chequesInHand)} ${accountsV2Text(language, 'v2_plus_cheques')}'
            : accountsV2Text(language, 'v2_incl_vat'),
        accent: kpis.outstanding.isPositive ? AppColors.warning : null,
      ),
    ];
    if (supplier != null) {
      tiles.add(
        _KpiTile(
          title: accountsV2Text(language, 'v2_kpi_supplier_unpaid'),
          value: format.money(supplier!.unpaid),
          caption: supplier!.overdueCount > 0
              ? '${supplier!.overdueCount} ${accountsV2Text(language, 'v2_overdue_count_suffix')}'
              : '',
          accent: supplier!.overdueCount > 0 ? AppColors.error : null,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Target ~210px tiles; at least one, at most five across.
        final perRow = (constraints.maxWidth / 210).floor().clamp(1, 5);
        final spacing = AppSpacing.md;
        final tileWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.title,
    required this.value,
    required this.caption,
    this.accent,
  });

  final String title;
  final String value;
  final String caption;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: accent ?? AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              caption,
              style: AppTypography.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Money-flow bar ────────────────────────────────────────────────────────

class _MoneyFlowCard extends StatelessWidget {
  const _MoneyFlowCard({
    required this.moneyFlow,
    required this.contractValue,
    required this.language,
    required this.format,
    this.onExportCsv,
  });

  final YorksAccountsWorkspaceMoneyFlow moneyFlow;
  final YorksAccountsDecimal contractValue;
  final AppLanguage language;
  final AccountsV2Format format;
  final VoidCallback? onExportCsv;

  int _flex(YorksAccountsDecimal value) {
    final r = format.ratio(value, contractValue);
    return (r * 1000).round();
  }

  @override
  Widget build(BuildContext context) {
    final segments = <(_FlowKind, YorksAccountsDecimal)>[
      (_FlowKind.paid, moneyFlow.paid),
      (_FlowKind.invoicedWaiting, moneyFlow.invoicedWaiting),
      (_FlowKind.doneNotInvoiced, moneyFlow.doneNotInvoiced),
      (_FlowKind.remaining, moneyFlow.remaining),
    ];
    final totalFlex = segments.fold<int>(0, (a, s) => a + _flex(s.$2));
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            accountsV2Text(language, 'v2_money_flow_title'),
            trailing: onExportCsv == null
                ? null
                : TextButton.icon(
                    onPressed: onExportCsv,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text(accountsV2Text(language, 'v2_export_csv')),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: SizedBox(
              height: 16,
              child: totalFlex == 0
                  ? const ColoredBox(color: AppColors.surfaceContainerHigh)
                  : Row(
                      children: [
                        for (final s in segments)
                          if (_flex(s.$2) > 0)
                            Expanded(
                              flex: _flex(s.$2),
                              child: ColoredBox(color: s.$1.color),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in segments)
                _FlowLegend(
                  color: s.$1.color,
                  label: accountsV2Text(language, s.$1.labelKey),
                  value: format.money(s.$2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _FlowKind {
  paid('v2_flow_paid', AppColors.success),
  invoicedWaiting('v2_flow_invoiced_waiting', AppColors.primary),
  doneNotInvoiced('v2_flow_done_not_invoiced', AppColors.warning),
  remaining('v2_flow_remaining', AppColors.lineStrong);

  const _FlowKind(this.labelKey, this.color);
  final String labelKey;
  final Color color;
}

class _FlowLegend extends StatelessWidget {
  const _FlowLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Attention list ──────────────────────────────────────────────────────

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.attention,
    required this.language,
    required this.onAction,
  });

  final List<YorksAccountsWorkspaceAttention> attention;
  final AppLanguage language;
  final ValueChanged<YorksAccountsWorkspaceAttention> onAction;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            accountsV2Text(language, 'v2_attention_title'),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (attention.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      accountsV2Text(language, 'v2_attention_empty'),
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final item in attention) ...[
              _AttentionRow(
                item: item,
                language: language,
                onAction: () => onAction(item),
              ),
            ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.item,
    required this.language,
    required this.onAction,
  });

  final YorksAccountsWorkspaceAttention item;
  final AppLanguage language;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tone = switch (item.severity) {
      'bad' => NexusStatusTone.danger,
      'warn' => NexusStatusTone.warning,
      'ok' => NexusStatusTone.success,
      _ => NexusStatusTone.info,
    };
    final palette = NexusStatusPalette.forTone(tone);
    final title = accountsV2Text(language, 'v2_att_${item.kind}');
    final count = item.params['count'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count is num && count > 0 ? '$title ($count)' : title,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            ),
          ),
          if (item.actionKey != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onAction,
              child: Text(
                accountsV2Text(language, 'v2_action_${item.actionKey}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cash position ─────────────────────────────────────────────────────────

class _CashCard extends StatelessWidget {
  const _CashCard({
    required this.cash,
    required this.language,
    required this.format,
  });

  final YorksAccountsWorkspaceCash cash;
  final AppLanguage language;
  final AccountsV2Format format;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(accountsV2Text(language, 'v2_cash_title')),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CashCell(
                  label: accountsV2Text(language, 'v2_cash_received'),
                  value: format.money(cash.received),
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _CashCell(
                  label: accountsV2Text(language, 'v2_cash_paid_suppliers'),
                  value: format.money(cash.paidToSuppliers),
                  color: AppColors.warning,
                ),
              ),
              Expanded(
                child: _CashCell(
                  label: accountsV2Text(language, 'v2_cash_net'),
                  value: format.money(cash.net),
                  color: cash.net.isNegative ? AppColors.error : AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashCell extends StatelessWidget {
  const _CashCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Heatmap ─────────────────────────────────────────────────────────────

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({
    required this.cells,
    required this.language,
    required this.format,
    required this.onOpenCell,
  });

  final List<YorksAccountsWorkspaceHeatmapCell> cells;
  final AppLanguage language;
  final AccountsV2Format format;
  final void Function(String stageKey, String buildingScopeId) onOpenCell;

  @override
  Widget build(BuildContext context) {
    // Ordered unique stages and buildings by first appearance.
    final stageKeys = <String>[];
    final stageLabels = <String, String>{};
    final buildingIds = <String>[];
    final buildingNames = <String, String>{};
    final byCell = <String, YorksAccountsWorkspaceHeatmapCell>{};
    for (final c in cells) {
      if (!stageKeys.contains(c.stageKey)) {
        stageKeys.add(c.stageKey);
        stageLabels[c.stageKey] = c.stageLabel ?? c.stageKey;
      }
      if (!buildingIds.contains(c.buildingScopeId)) {
        buildingIds.add(c.buildingScopeId);
        buildingNames[c.buildingScopeId] = c.buildingName;
      }
      byCell['${c.stageKey}|${c.buildingScopeId}'] = c;
    }

    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(accountsV2Text(language, 'v2_heatmap_title')),
          const SizedBox(height: AppSpacing.md),
          if (stageKeys.isEmpty || buildingIds.isEmpty)
            Text(
              accountsV2Text(language, 'v2_heatmap_empty'),
              style: AppTypography.bodyMedium,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 150),
                      for (final b in buildingIds)
                        _HeatHeader(buildingNames[b] ?? b),
                    ],
                  ),
                  for (final stage in stageKeys)
                    Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              stageLabels[stage] ?? stage,
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        for (final b in buildingIds)
                          _HeatCell(
                            cell: byCell['$stage|$b'],
                            format: format,
                            onTap: () => onOpenCell(stage, b),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeatHeader extends StatelessWidget {
  const _HeatHeader(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          name,
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.cell,
    required this.format,
    required this.onTap,
  });

  final YorksAccountsWorkspaceHeatmapCell? cell;
  final AccountsV2Format format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cell = this.cell;
    final percentValue =
        double.tryParse(cell?.invoicedPercent.canonicalText ?? '') ?? 0;
    final alpha = (percentValue / 100).clamp(0.0, 1.0);
    final fill = Color.alphaBlend(
      AppColors.primary.withValues(alpha: alpha * 0.85),
      AppColors.surfaceContainerLowest,
    );
    final textColor = alpha > 0.5 ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: cell == null ? null : onTap,
        child: Container(
          width: 92,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cell == null ? AppColors.surfaceContainer : fill,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            cell == null
                ? '—'
                : format.percentOfRatio(alpha, fractionDigits: 0),
            style: AppTypography.labelLarge.copyWith(
              color: cell == null ? AppColors.muted : textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── No-commercial / no-baseline card ────────────────────────────────────

class _NoCommercialCard extends StatelessWidget {
  const _NoCommercialCard({
    required this.workspace,
    required this.language,
    required this.onSetup,
  });

  final YorksAccountsWorkspace workspace;
  final AppLanguage language;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final noBaseline = !workspace.hasBaseline;
    final canConfigure = workspace.capabilities.viewProjectAccounts;
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                noBaseline ? Icons.description_outlined : Icons.lock_outline,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  noBaseline
                      ? accountsV2Text(language, 'v2_no_baseline_title')
                      : accountsV2Text(language, 'v2_commercial_hidden'),
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          if (noBaseline) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              accountsV2Text(language, 'v2_no_baseline_body'),
              style: AppTypography.bodyMedium,
            ),
            if (canConfigure) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onSetup,
                child: Text(accountsV2Text(language, 'v2_step_setup')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
