/// BOQ › Contract Materials status (PRODUCT_DECISIONS.md section 61).
///
/// A read-only view over the BOQ rows tied to contract lines: what Material
/// Requests asked for and what reached site, then, for people who may read
/// project Accounts, what is confirmed delivered and installed, then, for
/// people who may see contract values, the line's rate and amount. Everything
/// comes from `v1_get_boq_contract_status`; a field the server left out is
/// not shown. Editing stays on the sheet.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart' show TranslatableString;
import '../../../../shared/models/yorks_v1_boq.dart';
import '../../../../shared/models/yorks_v1_boq_contract_status.dart';
import '../../../../shared/models/yorks_v1_boq_strings.dart';
import '../../../accounts/domain/accounts_decimal.dart';

const _supply = 'material_supply';
const _installation = 'installation';

YorksAccountsDecimal _decimal(String text) =>
    YorksAccountsDecimal.tryParse(text) ?? YorksAccountsDecimal.zero;

String _qty(String text) =>
    _decimal(text).displayText(maximumFractionDigits: 4);

/// Grouped money, e.g. `813,846.06`. Display only.
String _money(String? text) {
  if (text == null) return '—';
  final raw = _decimal(text).displayText(maximumFractionDigits: 2);
  final negative = raw.startsWith('-');
  final parts = (negative ? raw.substring(1) : raw).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

bool _isLot(String unit) => const {
  'lot',
  'lots',
  'ls',
  'l.s',
  'lump sum',
  'lumpsum',
  'job',
}.contains(unit.trim().toLowerCase().replaceAll(RegExp(r'\.$'), ''));

enum _Progress { none, part, done }

_Progress _progress(YorksV1BoqContractStageStatus stage) {
  final done = _decimal(stage.confirmedQty);
  if (!done.isPositive) return _Progress.none;
  return done.compareTo(_decimal(stage.quantity)) >= 0
      ? _Progress.done
      : _Progress.part;
}

/// "20 of 55", or "50%" of a lump-sum line.
String _partText(AppLanguage language, YorksV1BoqContractStageStatus stage) {
  final done = _decimal(stage.confirmedQty);
  final total = _decimal(stage.quantity);
  if (_isLot(stage.unitCode)) {
    final d = double.tryParse(done.canonicalText) ?? 0;
    final t = double.tryParse(total.canonicalText) ?? 0;
    final pct = t <= 0 ? 0 : (d / t * 100).clamp(0, 100);
    return '${pct.toStringAsFixed(0)}%';
  }
  return YorksV1BoqStrings.contractPartOf
      .active(language)
      .replaceAll('{done}', done.displayText(maximumFractionDigits: 4))
      .replaceAll('{total}', total.displayText(maximumFractionDigits: 4));
}

/// The sheet row's own cells, read the way the Contract Materials sheet
/// stores them: Ref by heading, the rest by canonical mapping.
final class _SheetCells {
  _SheetCells(YorksV1BoqWorksheet worksheet, YorksV1BoqRow row) {
    String? byHeading(String heading) {
      for (final c in worksheet.columns) {
        if (c.heading.trim().toLowerCase() == heading) {
          final v = row.valueFor(c.id);
          if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
        }
      }
      return null;
    }

    String canonical(String key) => '${row.canonicalValues[key] ?? ''}'.trim();
    ref = byHeading('ref') ?? '';
    description = canonical('description');
    quantity = canonical('quantity');
    unit = canonical('unit');
  }

  late final String ref;
  late final String description;
  late final String quantity;
  late final String unit;
}

class YorksV1BoqContractStatusView extends StatelessWidget {
  const YorksV1BoqContractStatusView({
    super.key,
    required this.worksheet,
    required this.status,
    required this.language,
    required this.compact,
  });

  final YorksV1BoqWorksheet worksheet;
  final YorksV1BoqContractStatus status;
  final AppLanguage language;
  final bool compact;

  String _t(TranslatableString s) => s.active(language);

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final row in worksheet.rows)
        if (status.row(row.id) case final s?) (row, s),
    ];
    final note = [
      YorksV1BoqStrings.contractStatusNote.active(language),
      if (status.canViewValues)
        YorksV1BoqStrings.contractStatusPriceNote.active(language),
    ].join(' ');
    final body = compact
        ? _cards(rows)
        : LayoutBuilder(
            builder: (context, constraints) {
              // The full width when there is room; below 980px it scrolls
              // sideways instead of crushing a column.
              final width = constraints.maxWidth < 980
                  ? 980.0
                  : constraints.maxWidth;
              final table = SizedBox(width: width, child: _table(rows));
              return width > constraints.maxWidth
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: table,
                    )
                  : table;
            },
          );
    return ListView(
      key: const ValueKey('boq-contract-status'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  note,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        body,
      ],
    );
  }

  Widget _table(List<(YorksV1BoqRow, YorksV1BoqContractRowStatus)> rows) {
    final progress = status.canViewProgress;
    final values = status.canViewValues;
    final headings = <(String, double, bool)>[
      (_t(YorksV1BoqStrings.contractRef), 76, false),
      (_t(YorksV1BoqStrings.contractDescription), 0, false),
      (_t(YorksV1BoqStrings.contractQty), 64, true),
      (_t(YorksV1BoqStrings.contractUnit), 60, false),
      if (values) (_t(YorksV1BoqStrings.contractRate), 112, true),
      if (values) (_t(YorksV1BoqStrings.contractAmount), 120, true),
      (_t(YorksV1BoqStrings.contractRequested), 96, true),
      (_t(YorksV1BoqStrings.contractOnSite), 88, true),
      if (progress) (_t(YorksV1BoqStrings.contractDelivered), 140, false),
      if (progress) (_t(YorksV1BoqStrings.contractInstalled), 140, false),
    ];
    final columnWidths = <int, TableColumnWidth>{
      for (final (i, h) in headings.indexed)
        i: h.$2 == 0 ? const FlexColumnWidth() : FixedColumnWidth(h.$2),
    };
    Widget cell(Widget child, {bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Align(
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
    final headerStyle = AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
    );
    final textStyle = AppTypography.bodySmall.copyWith(
      color: AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: columnWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            children: [
              for (final h in headings)
                cell(Text(h.$1.toUpperCase(), style: headerStyle), end: h.$3),
            ],
          ),
          for (final (row, s) in rows)
            TableRow(
              key: ValueKey('boq-contract-row-${row.id}'),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              children: [
                ...() {
                  final c = _SheetCells(worksheet, row);
                  final supply = s.stage(_supply);
                  return [
                    cell(Text(c.ref, style: textStyle)),
                    cell(
                      Text(
                        c.description,
                        style: textStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    cell(Text(_qty(c.quantity), style: textStyle), end: true),
                    cell(Text(c.unit, style: textStyle)),
                    if (values)
                      cell(
                        Text(_money(supply?.rate), style: textStyle),
                        end: true,
                      ),
                    if (values)
                      cell(
                        Text(
                          _money(supply?.amount),
                          style: textStyle.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        end: true,
                      ),
                    cell(
                      Text(_qty(s.requestedQty), style: textStyle),
                      end: true,
                    ),
                    cell(
                      Tooltip(
                        message: s.lastDeliveryReference ?? '',
                        child: Text(_qty(s.receivedQty), style: textStyle),
                      ),
                      end: true,
                    ),
                    if (progress) cell(_stagePill(s.stage(_supply), true)),
                    if (progress)
                      cell(_stagePill(s.stage(_installation), false)),
                  ];
                }(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cards(List<(YorksV1BoqRow, YorksV1BoqContractRowStatus)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (row, s)) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _card(row, s),
        ],
      ],
    );
  }

  Widget _card(YorksV1BoqRow row, YorksV1BoqContractRowStatus s) {
    final c = _SheetCells(worksheet, row);
    final supply = s.stage(_supply);
    return Container(
      key: ValueKey('boq-contract-card-${row.id}'),
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${c.ref}  ${c.description}'.trim(),
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${_qty(c.quantity)} ${c.unit}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
          if (status.canViewValues && supply?.amount != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_t(YorksV1BoqStrings.contractRate)} ${_money(supply!.rate)} · '
              '${_t(YorksV1BoqStrings.contractAmount)} ${status.currencyCode ?? 'AED'} ${_money(supply.amount)}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _Pill(
                '${_t(YorksV1BoqStrings.contractRequested)} ${_qty(s.requestedQty)}',
              ),
              _Pill(
                '${_t(YorksV1BoqStrings.contractOnSite)} ${_qty(s.receivedQty)}',
                tone: _decimal(s.receivedQty).isPositive
                    ? _PillTone.warn
                    : _PillTone.neutral,
              ),
              if (status.canViewProgress) _stagePill(s.stage(_supply), true),
              if (status.canViewProgress)
                _stagePill(s.stage(_installation), false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stagePill(YorksV1BoqContractStageStatus? stage, bool supply) {
    if (stage == null) return const Text('—');
    final p = _progress(stage);
    final label = switch (p) {
      _Progress.none =>
        supply
            ? _t(YorksV1BoqStrings.contractNotDelivered)
            : _t(YorksV1BoqStrings.contractNotStarted),
      _Progress.part =>
        '${supply ? _t(YorksV1BoqStrings.contractDelivered) : _t(YorksV1BoqStrings.contractInstalled)} ${_partText(language, stage)}',
      _Progress.done =>
        supply
            ? _t(YorksV1BoqStrings.contractDeliveredAll)
            : _t(YorksV1BoqStrings.contractInstalledAll),
    };
    final tone = switch (p) {
      _Progress.none => _PillTone.neutral,
      _Progress.part => supply ? _PillTone.warn : _PillTone.blue,
      _Progress.done => _PillTone.ok,
    };
    return _Pill(label, tone: tone);
  }
}

enum _PillTone { neutral, warn, blue, ok }

class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.tone = _PillTone.neutral});

  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _PillTone.neutral => (AppColors.neutralContainer, AppColors.neutralText),
      _PillTone.warn => (AppColors.warningContainer, AppColors.warning),
      _PillTone.blue => (AppColors.blueContainer, AppColors.blue),
      _PillTone.ok => (AppColors.successContainer, AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
