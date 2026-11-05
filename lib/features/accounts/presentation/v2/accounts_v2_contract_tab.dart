/// R39 Accounts Workspace V2 — Contract tab (P6, read view).
///
/// Shows the current commercial setup (`v1_get_project_commercial_setup`): the
/// contract header, the building split, the billing stages with their
/// measurement mode, the per-building item breakdown for items-mode stages, and
/// the invoice-numbering settings — alongside the live Setup-check panel and the
/// "How amounts are worked out" explainer. Inline editing and save arrive in a
/// later P6 increment; this slice presents the approved values. Commercial
/// content is drawn only when the actor has commercial-value access.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/v2/commercial_setup_read_models.dart';
import 'accounts_v2_common.dart';

class AccountsV2ContractTab extends StatelessWidget {
  const AccountsV2ContractTab({
    super.key,
    required this.setup,
    required this.language,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final format = AccountsV2Format(currencyCode: setup.currencyCode ?? 'AED');

    if (!setup.hasCommercialValues) {
      return _CommercialHidden(
        language: language,
        hasBaseline: setup.hasBaseline,
      );
    }

    final main = <Widget>[
      _ContractHeaderCard(setup: setup, language: language, format: format),
      const SizedBox(height: AppSpacing.lg),
      _BuildingsCard(setup: setup, language: language, format: format),
      const SizedBox(height: AppSpacing.lg),
      _StagesCard(setup: setup, language: language, format: format),
    ];
    for (final stage in setup.stages.where((s) => s.isItemsMode)) {
      final items = setup.itemsForStage(stage.stageKey);
      if (items.isEmpty) continue;
      main
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(
          _ItemsCard(
            stage: stage,
            items: items,
            language: language,
            format: format,
          ),
        );
    }
    if (setup.invoiceSettings != null) {
      main
        ..add(const SizedBox(height: AppSpacing.lg))
        ..add(
          _InvoiceNumberingCard(
            settings: setup.invoiceSettings!,
            language: language,
          ),
        );
    }

    final aside = <Widget>[
      _SetupCheckCard(setup: setup, language: language, format: format),
      const SizedBox(height: AppSpacing.lg),
      _HowAmountsCard(language: language),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppSpacing.stackedBreakpoint;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ...main,
              const SizedBox(height: AppSpacing.lg),
              ...aside,
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
                    children: main,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: AppSpacing.inspectorWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: aside,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ─── Contract header ─────────────────────────────────────────────────────────

class _ContractHeaderCard extends StatelessWidget {
  const _ContractHeaderCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final terms = setup.paymentTermsDays == null
        ? '—'
        : '${setup.paymentTermsDays} ${_t('v2_days_suffix')}';
    final nextInvoice = setup.invoiceSettings?.nextInvoiceNumber ?? '—';
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_contract_summary_title')),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Field(
                label: _t('v2_contract_value'),
                value: format.money(setup.contractValue),
                emphasize: true,
              ),
              _Field(
                label: '${_t('v2_contract_value')} · ${_t('v2_incl_vat')}',
                value: format.money(setup.contractInclVat),
              ),
              _Field(
                label: _t('v2_vat_label'),
                value: format.percent(setup.vatRatePercent),
              ),
              _Field(label: _t('v2_payment_terms_label'), value: terms),
              _Field(label: _t('v2_next_invoice_label'), value: nextInvoice),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style:
              (emphasize ? AppTypography.titleMedium : AppTypography.titleSmall)
                  .copyWith(
                    color: AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
        ),
      ],
    );
  }
}

// ─── Buildings ───────────────────────────────────────────────────────────────

class _BuildingsCard extends StatelessWidget {
  const _BuildingsCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_buildings_title'),
            trailing: _PercentBadge(
              percent: setup.buildingTotalPercent,
              ok: setup.buildingsHundred,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SplitHeader(
            left: _t('v2_buildings_title'),
            middle: _t('v2_share_label'),
            right: _t('v2_value_label'),
          ),
          for (final b in setup.buildings)
            _SplitRow(
              left: b.name,
              middle: format.percent(b.allocationPercent),
              right: format.money(b.value),
            ),
        ],
      ),
    );
  }
}

// ─── Stages ────────────────────────────────────────────────────────────────

class _StagesCard extends StatelessWidget {
  const _StagesCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            _t('v2_stages_title'),
            trailing: _PercentBadge(
              percent: setup.stageTotalPercent,
              ok: setup.stagesHundred,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final s in setup.stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.stageName,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        _ModeChip(isItems: s.isItemsMode, language: language),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      format.percent(s.allocationPercent),
                      textAlign: TextAlign.end,
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(
                      format.money(s.value),
                      textAlign: TextAlign.end,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.isItems, required this.language});

  final bool isItems;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final label = accountsV2Text(
      language,
      isItems ? 'v2_mode_items' : 'v2_mode_percent',
    );
    return isItems
        ? StatusChip.info(label)
        : StatusChip(label: label, tone: NexusStatusTone.neutral);
  }
}

// ─── Items ─────────────────────────────────────────────────────────────────

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.stage,
    required this.items,
    required this.language,
    required this.format,
  });

  final YorksAccountsSetupReadStage stage;
  final List<YorksAccountsSetupReadItem> items;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    // Group by building name in the server-provided order.
    final byBuilding = <String, List<YorksAccountsSetupReadItem>>{};
    for (final it in items) {
      byBuilding.putIfAbsent(it.buildingName, () => []).add(it);
    }
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            '${_t('v2_items_title')} · ${stage.stageName}',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in byBuilding.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xxs,
              ),
              child: Text(
                entry.key,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: AppSpacing.xl,
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 44,
                columns: [
                  DataColumn(label: Text(_t('v2_item_label'))),
                  DataColumn(label: Text(_t('v2_qty_label')), numeric: true),
                  DataColumn(label: Text(_t('v2_unit_label'))),
                  DataColumn(label: Text(_t('v2_weight_label')), numeric: true),
                  DataColumn(label: Text(_t('v2_value_label')), numeric: true),
                ],
                rows: [
                  for (final it in entry.value)
                    DataRow(
                      cells: [
                        DataCell(Text(it.itemLabel)),
                        DataCell(
                          Text(
                            it.quantity.displayText(maximumFractionDigits: 2),
                          ),
                        ),
                        DataCell(Text(it.unitCode)),
                        DataCell(
                          Text(
                            format.percent(
                              it.weightPercentOfContract,
                              maximumFractionDigits: 4,
                            ),
                          ),
                        ),
                        DataCell(Text(format.money(it.value))),
                      ],
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

// ─── Invoice numbering ───────────────────────────────────────────────────────

class _InvoiceNumberingCard extends StatelessWidget {
  const _InvoiceNumberingCard({required this.settings, required this.language});

  final YorksAccountsSetupReadInvoiceSettings settings;
  final AppLanguage language;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_invoice_numbering_title')),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Field(
                label: _t('v2_next_invoice_label'),
                value: settings.nextInvoiceNumber,
              ),
              if (settings.scopeLine != null && settings.scopeLine!.isNotEmpty)
                _Field(
                  label: _t('v2_scope_line_label'),
                  value: settings.scopeLine!,
                ),
              if (settings.attentionName != null &&
                  settings.attentionName!.isNotEmpty)
                _Field(
                  label: _t('v2_attention_name_label'),
                  value: settings.attentionName!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Setup check ─────────────────────────────────────────────────────────────

class _SetupCheckCard extends StatelessWidget {
  const _SetupCheckCard({
    required this.setup,
    required this.language,
    required this.format,
  });

  final YorksAccountsCommercialSetupRead setup;
  final AppLanguage language;
  final AccountsV2Format format;

  String _t(String key) => accountsV2Text(language, key);

  @override
  Widget build(BuildContext context) {
    final contractOk = (setup.contractValue?.isPositive) ?? false;
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(_t('v2_setup_check_title')),
          const SizedBox(height: AppSpacing.sm),
          _CheckRow(
            label: _t('v2_check_contract'),
            ok: contractOk,
            detail: format.money(setup.contractValue),
          ),
          _CheckRow(
            label: _t('v2_check_buildings'),
            ok: setup.buildingsHundred,
            detail: format.percent(setup.buildingTotalPercent),
          ),
          _CheckRow(
            label: _t('v2_check_stages'),
            ok: setup.stagesHundred,
            detail: format.percent(setup.stageTotalPercent),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.ok,
    required this.detail,
  });

  final String label;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel_outlined,
            size: 18,
            color: ok ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.bodyMedium)),
          Text(
            detail,
            style: AppTypography.labelLarge.copyWith(
              color: ok ? AppColors.success : AppColors.error,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── How amounts are worked out ──────────────────────────────────────────────

class _HowAmountsCard extends StatelessWidget {
  const _HowAmountsCard({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return AccountsV2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountsV2SectionTitle(
            accountsV2Text(language, 'v2_how_amounts_title'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            accountsV2Text(language, 'v2_how_amounts_body'),
            style: AppTypography.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ─── Shared bits ─────────────────────────────────────────────────────────────

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent, required this.ok});

  final YorksAccountsDecimal percent;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final text = '${percent.displayText(maximumFractionDigits: 2)}%';
    return ok ? StatusChip.success(text) : StatusChip.warning(text);
  }
}

class _SplitHeader extends StatelessWidget {
  const _SplitHeader({
    required this.left,
    required this.middle,
    required this.right,
  });

  final String left;
  final String middle;
  final String right;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelMedium.copyWith(color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          SizedBox(
            width: 72,
            child: Text(middle, style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 140,
            child: Text(right, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.left,
    required this.middle,
    required this.right,
  });

  final String left;
  final String middle;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              middle,
              textAlign: TextAlign.end,
              style: AppTypography.bodyMedium,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              right,
              textAlign: TextAlign.end,
              style: AppTypography.titleSmall.copyWith(
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

class _CommercialHidden extends StatelessWidget {
  const _CommercialHidden({required this.language, required this.hasBaseline});

  final AppLanguage language;
  final bool hasBaseline;

  @override
  Widget build(BuildContext context) {
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
              style: AppTypography.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
