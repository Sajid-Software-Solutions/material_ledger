import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_models.dart';
import '../../domain/accounts_portfolio_models.dart';

/// Project Accounts landing view. Every amount originates in an authorized
/// Accounts projection; the widget never loads records or changes workflow state.
class YorksProjectAccountsOverview extends StatelessWidget {
  const YorksProjectAccountsOverview({
    super.key,
    required this.overview,
    required this.baseline,
    required this.progress,
    required this.language,
    required this.onBilling,
    required this.onClaims,
    required this.onReceipts,
  });

  final YorksAccountsProjectOverviewProjection overview;
  final YorksAccountsBaselineProjection baseline;
  final YorksAccountsProgressProjection progress;
  final AppLanguage language;
  final VoidCallback onBilling;
  final VoidCallback onClaims;
  final VoidCallback onReceipts;

  String t(String key) => YorksV1AccountsStrings.text(language, key);
  String money(YorksAccountsDecimal? value) {
    if (value == null) return '—';
    final raw = value.canonicalText;
    final negative = raw.startsWith('-');
    final parts = (negative ? raw.substring(1) : raw).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    return '${baseline.baseline?.currencyCode ?? 'AED'} ${negative ? '-' : ''}$whole.$fraction';
  }

  YorksAccountsDecimal? receivable(String key) {
    final value = overview.receivables?[key];
    return value is String ? YorksAccountsDecimal.tryParse(value) : null;
  }

  double ratio(YorksAccountsDecimal? a, YorksAccountsDecimal? b) {
    final numerator = double.tryParse(a?.canonicalText ?? '') ?? 0;
    final denominator = double.tryParse(b?.canonicalText ?? '') ?? 0;
    return denominator <= 0 ? 0 : (numerator / denominator).clamp(0, 1);
  }

  String percent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    if (baseline.baseline == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _decoration(),
        child: Column(
          children: [
            _icon(Icons.description_outlined, const Color(0xFF1766D5)),
            const SizedBox(height: 10),
            Text(
              t('set_commercial_baseline'),
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              t('billing_progress_body'),
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
            if (baseline.capabilities.canConfigure) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onBilling,
                child: Text(t('set_commercial_baseline')),
              ),
            ],
          ],
        ),
      );
    }
    final canViewValues =
        overview.capabilities.viewValues &&
        baseline.capabilities.canViewValues &&
        progress.capabilities.canViewValues;
    final contract = canViewValues ? baseline.baseline?.contractValue : null;
    final confirmed = canViewValues ? progress.totals?.confirmedEligible : null;
    final available = canViewValues ? progress.totals?.availableToClaim : null;
    final certified = canViewValues ? receivable('certified') : null;
    final paid = canViewValues ? receivable('amount_paid_till_date') : null;
    final due = canViewValues ? receivable('still_due') : null;
    final allocations = baseline.buildingAllocations;
    final positions = allocations
        .map((allocation) {
          final rows = progress.progress.where(
            (entry) => entry.buildingScopeId == allocation.buildingScopeId,
          );
          final eligible = rows.fold(
            YorksAccountsDecimal.zero,
            (YorksAccountsDecimal sum, entry) =>
                sum + (entry.confirmedEligible ?? YorksAccountsDecimal.zero),
          );
          return (allocation: allocation, eligible: eligible);
        })
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final gap = width < 600 ? 10.0 : 12.0;
        final columns = width >= 1210
            ? 6
            : width >= 740
            ? 3
            : width >= 320
            ? 2
            : 1;
        final cardWidth = (width - gap * (columns - 1)) / columns;
        final cards = <Widget>[
          _metric(
            Icons.description_outlined,
            const Color(0xFF1766D5),
            'contract_value',
            contract,
            'net_active_baseline',
          ),
          _metric(
            Icons.task_alt_rounded,
            const Color(0xFF0D9D61),
            'confirmed',
            confirmed,
            'net_contract_share',
            detailValue: contract == null || confirmed == null
                ? null
                : percent(ratio(confirmed, contract)),
          ),
          _metric(
            Icons.bar_chart_rounded,
            const Color(0xFF1662D0),
            'available',
            available,
            'net_subject_to_review',
          ),
          _metric(
            Icons.receipt_long_outlined,
            const Color(0xFF6846D9),
            'certified',
            certified,
            'gross_including_vat',
          ),
          _metric(
            Icons.payments_outlined,
            const Color(0xFF089861),
            'paid',
            paid,
            'actual_receipts_only',
          ),
          _metric(
            Icons.schedule_outlined,
            const Color(0xFFDA7015),
            'still_due',
            due,
            'certified_balance',
          ),
        ];
        final top = <Widget>[
          _panel(
            'action_required',
            Icons.assignment_outlined,
            _actions(context, available),
            subtitle: 'relevant_actions',
            flex: 5,
          ),
          _panel(
            'commercial_progress_building',
            Icons.bar_chart_rounded,
            _progressByBuilding(positions, canViewValues),
            flex: 3,
          ),
          if (canViewValues)
            _panel(
              'client_collections',
              Icons.payments_outlined,
              _collections(certified, paid, due),
              flex: 3,
            ),
        ];
        final bottom = <Widget>[
          _panel(
            'position_by_building',
            Icons.account_tree_outlined,
            _positionByBuilding(positions, contract, canViewValues),
            subtitle: 'weighted_commercial_progress',
            flex: 5,
          ),
          if (canViewValues)
            _panel(
              'eligible_value_building',
              Icons.donut_large_rounded,
              _eligibleByBuilding(positions, confirmed),
              flex: 3,
            ),
          _panel(
            'baseline_snapshot',
            Icons.description_outlined,
            _baselineSnapshot(),
            flex: 3,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  SizedBox(width: cardWidth, child: card),
              ],
            ),
            SizedBox(height: gap),
            _responsivePanels(top, width, gap),
            SizedBox(height: gap),
            _responsivePanels(bottom, width, gap),
          ],
        );
      },
    );
  }

  Widget _metric(
    IconData icon,
    Color color,
    String title,
    YorksAccountsDecimal? value,
    String detail, {
    String? detailValue,
  }) => Container(
    height: 122,
    padding: const EdgeInsets.all(12),
    decoration: _decoration(),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _icon(icon, color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                t(title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  money(value),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF152341),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detailValue == null ? t(detail) : '${t(detail)} · $detailValue',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _responsivePanels(List<Widget> panels, double width, double gap) {
    if (width < 1060) {
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final panel in panels)
            SizedBox(
              width: width >= 700 && panel != panels.first
                  ? (width - gap) / 2
                  : width,
              child: panel,
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < panels.length; index++) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(flex: index == 0 ? 5 : 3, child: panels[index]),
        ],
      ],
    );
  }

  Widget _panel(
    String title,
    IconData icon,
    Widget body, {
    String? subtitle,
    int flex = 1,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 248),
    padding: const EdgeInsets.all(15),
    decoration: _decoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF1261CE), size: 23),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                t(title),
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF152341),
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32, top: 2),
            child: Text(
              t(subtitle),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        const SizedBox(height: 12),
        body,
      ],
    ),
  );

  Widget _actions(BuildContext context, YorksAccountsDecimal? available) {
    final pending = progress.progress
        .where(
          (entry) =>
              entry.reviewStatus == YorksAccountsReviewStatus.pending &&
              progress.capabilities.canReview,
        )
        .toList();
    final suggestions = progress.progress
        .where(
          (entry) =>
              entry.suggestedPercent.compareTo(entry.confirmedPercent) > 0 &&
              progress.capabilities.canConfirm &&
              entry.reviewStatus != YorksAccountsReviewStatus.pending,
        )
        .toList();
    final actions = <(IconData, String, String, VoidCallback)>[
      if (pending.isNotEmpty)
        (
          Icons.schedule_outlined,
          'review_progress',
          '${pending.first.buildingName ?? '—'} · ${pending.first.stageLabel ?? pending.first.stageKey}',
          onBilling,
        ),
      if (suggestions.isNotEmpty)
        (
          Icons.rate_review_outlined,
          'review_progress',
          '${suggestions.first.buildingName ?? '—'} · ${suggestions.first.stageLabel ?? suggestions.first.stageKey}',
          onBilling,
        ),
      if (overview.capabilities.prepareClaim && available?.isPositive == true)
        (
          Icons.description_outlined,
          'prepare_claim',
          t('available_capacity_requires_review'),
          onClaims,
        ),
      if (overview.capabilities.viewValues &&
          (receivable('still_due')?.isPositive ?? false))
        (
          Icons.receipt_long_outlined,
          'review_client_balance',
          t('certified_balance'),
          onReceipts,
        ),
    ];
    if (actions.isEmpty) return _empty();
    return Column(
      children: [
        for (final action in actions.take(3))
          InkWell(
            onTap: action.$4,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  _icon(action.$1, const Color(0xFF1766D5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(action.$2), style: AppTypography.labelMedium),
                        Text(
                          action.$3,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF1454B2),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _progressByBuilding(
    List<
      ({
        YorksAccountsBuildingAllocation allocation,
        YorksAccountsDecimal eligible,
      })
    >
    positions,
    bool canViewValues,
  ) {
    if (positions.isEmpty) return _empty();
    return Column(
      children: [
        for (final row in positions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    row.allocation.buildingName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: canViewValues
                          ? ratio(row.eligible, row.allocation.allocatedValue)
                          : _buildingPercent(row.allocation.buildingScopeId),
                      minHeight: 27,
                      color: const Color(0xFF3788EA),
                      backgroundColor: const Color(0xFFDDE7F1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    percent(
                      canViewValues
                          ? ratio(row.eligible, row.allocation.allocatedValue)
                          : _buildingPercent(row.allocation.buildingScopeId),
                    ),
                    textAlign: TextAlign.end,
                    style: AppTypography.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  double _buildingPercent(String buildingId) {
    final rows = progress.progress
        .where((entry) => entry.buildingScopeId == buildingId)
        .toList();
    if (rows.isEmpty) return 0;
    final stages = baseline.stageAllocations;
    final sum = rows.fold<double>(0, (total, row) {
      final weight = stages
          .where((stage) => stage.stageKey == row.stageKey)
          .firstOrNull;
      final stageRatio =
          double.tryParse(weight?.allocationPercent.canonicalText ?? '') ?? 0;
      final confirmed =
          double.tryParse(row.confirmedPercent.canonicalText) ?? 0;
      return total + stageRatio * confirmed / 10000;
    });
    return sum.clamp(0, 1);
  }

  Widget _collections(
    YorksAccountsDecimal? certified,
    YorksAccountsDecimal? paid,
    YorksAccountsDecimal? due,
  ) => Column(
    children: [
      _fact('certified_gross', money(certified)),
      _fact('paid', money(paid)),
      _fact('still_due', money(due), emphasis: true),
      _fact('pdc', money(receivable('pdc_exposure'))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(6),
          border: const Border(
            left: BorderSide(color: Color(0xFF6DAAF4), width: 3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF277AE0)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('held_pdc_note'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _fact(String key, String value, {bool emphasis = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(t(key), style: AppTypography.bodySmall)),
        Text(
          value,
          style: AppTypography.labelSmall.copyWith(
            color: emphasis ? const Color(0xFFD42626) : const Color(0xFF152341),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _positionByBuilding(
    List<
      ({
        YorksAccountsBuildingAllocation allocation,
        YorksAccountsDecimal eligible,
      })
    >
    positions,
    YorksAccountsDecimal? contract,
    bool canViewValues,
  ) {
    if (positions.isEmpty) return _empty();
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 560;
        return Column(
          children: [
            if (!mobile)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                color: const Color(0xFFF4F8FD),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        t('building'),
                        style: AppTypography.labelSmall,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t('confirmed'),
                        style: AppTypography.labelSmall,
                      ),
                    ),
                    if (canViewValues)
                      Expanded(
                        flex: 3,
                        child: Text(
                          t('eligible_net'),
                          textAlign: TextAlign.end,
                          style: AppTypography.labelSmall,
                        ),
                      ),
                    if (canViewValues)
                      Expanded(
                        flex: 2,
                        child: Text(
                          t('of_contract'),
                          textAlign: TextAlign.end,
                          style: AppTypography.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            for (final row in positions)
              if (mobile)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.allocation.buildingName ?? '—',
                        style: AppTypography.labelMedium.copyWith(
                          color: const Color(0xFF1454B2),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${t('confirmed')}: ${percent(canViewValues ? ratio(row.eligible, row.allocation.allocatedValue) : _buildingPercent(row.allocation.buildingScopeId))}',
                        style: AppTypography.bodySmall,
                      ),
                      if (canViewValues)
                        Text(
                          '${t('eligible_net')}: ${money(row.eligible)} · '
                          '${t('of_contract')}: ${percent(ratio(row.eligible, contract))}',
                          style: AppTypography.bodySmall,
                        ),
                    ],
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          row.allocation.buildingName ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                            color: const Color(0xFF1454B2),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          percent(
                            canViewValues
                                ? ratio(
                                    row.eligible,
                                    row.allocation.allocatedValue,
                                  )
                                : _buildingPercent(
                                    row.allocation.buildingScopeId,
                                  ),
                          ),
                          style: AppTypography.labelSmall,
                        ),
                      ),
                      if (canViewValues)
                        Expanded(
                          flex: 3,
                          child: Text(
                            money(row.eligible),
                            textAlign: TextAlign.end,
                            style: AppTypography.labelSmall,
                          ),
                        ),
                      if (canViewValues)
                        Expanded(
                          flex: 2,
                          child: Text(
                            percent(ratio(row.eligible, contract)),
                            textAlign: TextAlign.end,
                            style: AppTypography.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                t('common_excluded'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _eligibleByBuilding(
    List<
      ({
        YorksAccountsBuildingAllocation allocation,
        YorksAccountsDecimal eligible,
      })
    >
    positions,
    YorksAccountsDecimal? total,
  ) {
    if (positions.isEmpty || total == null || total.isZero) return _empty();
    const colors = [
      Color(0xFF2769D4),
      Color(0xFF54AAEF),
      Color(0xFF19A276),
      Color(0xFF6847D9),
      Color(0xFFF19D3B),
    ];
    final fractions = positions
        .map((row) => ratio(row.eligible, total))
        .toList();
    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _AccountsDonutPainter(fractions, colors),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    baseline.baseline?.currencyCode ?? 'AED',
                    style: AppTypography.bodySmall,
                  ),
                  SizedBox(
                    width: 88,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        money(total).split(' ').last.split('.').first,
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        t('eligible_net'),
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < positions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          positions[i].allocation.buildingName ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      Text(
                        percent(fractions[i]),
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _baselineSnapshot() {
    final active = baseline.baseline;
    if (active == null) return _empty();
    final stages = baseline.stageAllocations;
    final sorted = [...stages]
      ..sort((a, b) => a.position.compareTo(b.position));
    return Column(
      children: [
        _fact(
          'revision',
          '${active.revisionNumber} · ${t('status_${active.status}')}',
        ),
        _fact('physical_buildings', '${baseline.physicalBuildings.length}'),
        _fact(
          'billing_stages',
          sorted.isEmpty
              ? '—'
              : sorted
                    .map((stage) => '${stage.allocationPercent.displayText()}%')
                    .join(' / '),
        ),
        if (baseline.capabilities.canViewValues) ...[
          _fact(
            'payment_terms',
            active.paymentTermsDays == null
                ? '—'
                : '${active.paymentTermsDays} ${t('days_from_submission')}',
          ),
          _fact(
            'vat_rate',
            active.vatRate == null ? '—' : '${active.vatRate!.displayText()}%',
          ),
        ],
      ],
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      t('no_records'),
      style: AppTypography.bodySmall.copyWith(color: AppColors.inkSecondary),
    ),
  );
  Widget _icon(IconData icon, Color color) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, color: color, size: 22),
  );
  BoxDecoration _decoration() => BoxDecoration(
    color: Colors.white,
    border: Border.all(color: const Color(0xFFD6E2F2)),
    borderRadius: BorderRadius.circular(9),
  );
}

class _AccountsDonutPainter extends CustomPainter {
  const _AccountsDonutPainter(this.fractions, this.colors);
  final List<double> fractions;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..color = const Color(0xFFE2EAF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24;
    canvas.drawArc(rect.deflate(14), 0, math.pi * 2, false, base);
    var start = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = fractions[i] * math.pi * 2;
      canvas.drawArc(
        rect.deflate(14),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _AccountsDonutPainter oldDelegate) =>
      oldDelegate.fractions != fractions || oldDelegate.colors != colors;
}
