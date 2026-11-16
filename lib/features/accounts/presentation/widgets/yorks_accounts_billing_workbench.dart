import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/analytics_event.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../domain/accounts_decimal.dart';
import '../../domain/accounts_models.dart';

/// Expandable, responsive commercial-progress workbench.
///
/// All values are supplied by the protected R39 projections. This widget does
/// not infer commercial authority, issue commands, or manufacture monthly data.
class YorksAccountsBillingWorkbench extends ConsumerStatefulWidget {
  const YorksAccountsBillingWorkbench({
    super.key,
    required this.baseline,
    required this.progress,
    required this.language,
    required this.onAction,
  });

  final YorksAccountsBaselineProjection baseline;
  final YorksAccountsProgressProjection progress;
  final AppLanguage language;
  final Future<bool> Function(YorksAccountsProgressEntry entry) onAction;

  @override
  ConsumerState<YorksAccountsBillingWorkbench> createState() =>
      _YorksAccountsBillingWorkbenchState();
}

class _YorksAccountsBillingWorkbenchState
    extends ConsumerState<YorksAccountsBillingWorkbench> {
  String? _expandedBuildingId;
  YorksAccountsProgressEntry? _selectedEntry;

  @override
  void initState() {
    super.initState();
    _adoptFirstGroup();
  }

  @override
  void didUpdateWidget(covariant YorksAccountsBillingWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableIds = widget.progress.progress
        .map((entry) => entry.buildingScopeId)
        .toSet();
    if (!availableIds.contains(_expandedBuildingId)) {
      _adoptFirstGroup();
    }
    final selectedId = _selectedEntry?.progressEntryId;
    if (selectedId != null) {
      _selectedEntry = widget.progress.progress
          .where((entry) => entry.progressEntryId == selectedId)
          .firstOrNull;
    }
  }

  void _adoptFirstGroup() {
    _expandedBuildingId = widget.progress.progress.firstOrNull?.buildingScopeId;
    _selectedEntry = widget.progress.progress.firstOrNull;
  }

  String _t(String key) => YorksV1AccountsStrings.text(widget.language, key);

  void _toggle(String buildingId, List<YorksAccountsProgressEntry> entries) {
    final expanding = _expandedBuildingId != buildingId;
    setState(() {
      _expandedBuildingId = expanding ? buildingId : null;
      if (expanding) _selectedEntry = entries.firstOrNull;
    });
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsBuildingGroupToggled,
          properties: {
            AnalyticsProperty.actionType: expanding ? 'expand' : 'collapse',
            AnalyticsProperty.itemCount: entries.length,
            AnalyticsProperty.source: 'billing_progress',
          },
        );
  }

  void _select(YorksAccountsProgressEntry entry) {
    setState(() => _selectedEntry = entry);
    ref
        .read(analyticsServiceProvider)
        .capture(
          AnalyticsEvent.accountsRecordOpened,
          properties: {
            AnalyticsProperty.objectType: 'billing_stage',
            AnalyticsProperty.recordState: entry.reviewStatus.wireValue,
            AnalyticsProperty.source: 'building_workbench',
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    return LayoutBuilder(
      builder: (context, constraints) {
        final showDetails = constraints.maxWidth >= 1120;
        final workbench = _Surface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkbenchHeader(
                title: _t('building_stage_workbench'),
                subtitle: _t('building_stage_workbench_body'),
                countLabel:
                    '${groups.length} ${_t('physical_buildings').toLowerCase()} · '
                    '${widget.progress.progress.length} ${_t('billing_stages').toLowerCase()}',
              ),
              for (final group in groups)
                _BuildingGroup(
                  key: ValueKey(
                    'accounts-building-group-${group.allocation.buildingScopeId}',
                  ),
                  group: group,
                  expanded:
                      _expandedBuildingId == group.allocation.buildingScopeId,
                  selectedEntryId: _selectedEntry?.progressEntryId,
                  canViewValues: widget.progress.capabilities.canViewValues,
                  language: widget.language,
                  canAct: (entry) =>
                      _hasAvailableProgressAction(widget.progress, entry),
                  onToggle: () =>
                      _toggle(group.allocation.buildingScopeId, group.entries),
                  onSelect: _select,
                  onAction: widget.onAction,
                ),
            ],
          ),
        );
        if (!showDetails) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              workbench,
              if (_selectedEntry != null) ...[
                const SizedBox(height: AppSpacing.md),
                _StageDetails(
                  entry: _selectedEntry!,
                  language: widget.language,
                  canViewValues: widget.progress.capabilities.canViewValues,
                  canAct: _hasAvailableProgressAction(
                    widget.progress,
                    _selectedEntry!,
                  ),
                  onAction: () => widget.onAction(_selectedEntry!),
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: workbench),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 318,
              child: _selectedEntry == null
                  ? const SizedBox.shrink()
                  : _StageDetails(
                      entry: _selectedEntry!,
                      language: widget.language,
                      canViewValues: widget.progress.capabilities.canViewValues,
                      canAct: _hasAvailableProgressAction(
                        widget.progress,
                        _selectedEntry!,
                      ),
                      onAction: () => widget.onAction(_selectedEntry!),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<_BuildingProgressGroup> _groups() {
    final entriesByBuilding = <String, List<YorksAccountsProgressEntry>>{};
    for (final entry in widget.progress.progress) {
      entriesByBuilding.putIfAbsent(entry.buildingScopeId, () => []).add(entry);
    }
    final allocations = widget.baseline.buildingAllocations
        .where(
          (allocation) =>
              entriesByBuilding.containsKey(allocation.buildingScopeId),
        )
        .toList(growable: false);
    return [
      for (final allocation in allocations)
        _BuildingProgressGroup(
          allocation: allocation,
          entries: (entriesByBuilding[allocation.buildingScopeId]!
            ..sort(
              (left, right) =>
                  left.stagePosition.compareTo(right.stagePosition),
            )),
          stageWeights: widget.baseline.stageAllocations,
        ),
    ];
  }
}

class _BuildingProgressGroup {
  const _BuildingProgressGroup({
    required this.allocation,
    required this.entries,
    required this.stageWeights,
  });

  final YorksAccountsBuildingAllocation allocation;
  final List<YorksAccountsProgressEntry> entries;
  final List<YorksAccountsStageAllocation> stageWeights;

  double get progress {
    var weighted = 0.0;
    for (final entry in entries) {
      final weight = stageWeights
          .where((stage) => stage.stageKey == entry.stageKey)
          .firstOrNull;
      final stageWeight =
          double.tryParse(weight?.allocationPercent.canonicalText ?? '') ?? 0;
      final confirmed =
          double.tryParse(entry.confirmedPercent.canonicalText) ?? 0;
      weighted += stageWeight * confirmed / 10000;
    }
    return weighted.clamp(0, 1);
  }

  int get pendingCount => entries
      .where((entry) => entry.reviewStatus == YorksAccountsReviewStatus.pending)
      .length;
}

class _BuildingGroup extends StatelessWidget {
  const _BuildingGroup({
    super.key,
    required this.group,
    required this.expanded,
    required this.selectedEntryId,
    required this.canViewValues,
    required this.language,
    required this.canAct,
    required this.onToggle,
    required this.onSelect,
    required this.onAction,
  });

  final _BuildingProgressGroup group;
  final bool expanded;
  final String? selectedEntryId;
  final bool canViewValues;
  final AppLanguage language;
  final bool Function(YorksAccountsProgressEntry entry) canAct;
  final VoidCallback onToggle;
  final ValueChanged<YorksAccountsProgressEntry> onSelect;
  final Future<bool> Function(YorksAccountsProgressEntry entry) onAction;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: group.allocation.buildingName,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    final identity = Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.apartment_rounded,
                            color: Color(0xFF146BE8),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.allocation.buildingName ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${_percent(group.allocation.allocationPercent)} ${_t('of_contract')} · '
                                '${group.entries.length} ${_t('billing_stages').toLowerCase()}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final summary = Row(
                      children: [
                        Expanded(
                          child: _ProgressBar(
                            value: group.progress,
                            label: _ratioPercent(group.progress),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        if (group.pendingCount > 0)
                          _Pill(
                            '${group.pendingCount} ${_t('pending').toLowerCase()}',
                            color: const Color(0xFFFFF0D7),
                            foreground: const Color(0xFF9A5800),
                          ),
                        if (canViewValues) ...[
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(
                            width: 128,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  group.allocation.allocatedValue == null
                                      ? '—'
                                      : _money(
                                          group.allocation.allocatedValue!,
                                        ),
                                  style: AppTypography.labelMedium.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  _t('allocated_value'),
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                        ),
                      ],
                    );
                    if (compact) {
                      return Column(
                        children: [
                          identity,
                          const SizedBox(height: AppSpacing.md),
                          summary,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 310, child: identity),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: summary),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          AnimatedSize(
            // Not Duration.zero under reduced motion: a zero-length size
            // change re-lays the building out inside its own layout.
            // Flutter already runs animations at 5% (one frame) when the
            // device asks for reduced motion.
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? KeyedSubtree(
                    key: ValueKey(
                      'accounts-building-expanded-${group.allocation.buildingScopeId}',
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 820
                          ? Column(
                              children: [
                                for (final entry in group.entries)
                                  _StageCard(
                                    entry: entry,
                                    selected:
                                        entry.progressEntryId ==
                                        selectedEntryId,
                                    canViewValues: canViewValues,
                                    language: language,
                                    canAct: canAct(entry),
                                    onSelect: () => onSelect(entry),
                                    onAction: () => onAction(entry),
                                  ),
                              ],
                            )
                          : _StageTable(
                              entries: group.entries,
                              selectedEntryId: selectedEntryId,
                              canViewValues: canViewValues,
                              language: language,
                              canAct: canAct,
                              onSelect: onSelect,
                              onAction: onAction,
                            ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _StageTable extends StatelessWidget {
  const _StageTable({
    required this.entries,
    required this.selectedEntryId,
    required this.canViewValues,
    required this.language,
    required this.canAct,
    required this.onSelect,
    required this.onAction,
  });

  final List<YorksAccountsProgressEntry> entries;
  final String? selectedEntryId;
  final bool canViewValues;
  final AppLanguage language;
  final bool Function(YorksAccountsProgressEntry entry) canAct;
  final ValueChanged<YorksAccountsProgressEntry> onSelect;
  final Future<bool> Function(YorksAccountsProgressEntry entry) onAction;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(
      width: canViewValues ? 1030 : 760,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F8FD)),
        headingRowHeight: 44,
        dataRowMinHeight: 54,
        dataRowMaxHeight: 62,
        columnSpacing: 20,
        showCheckboxColumn: false,
        columns: [
          DataColumn(label: Text(_t('stage'))),
          DataColumn(numeric: true, label: Text(_t('suggested_progress'))),
          DataColumn(numeric: true, label: Text(_t('confirmed_progress'))),
          if (canViewValues)
            DataColumn(numeric: true, label: Text(_t('stage_value'))),
          if (canViewValues)
            DataColumn(numeric: true, label: Text(_t('eligible_amount'))),
          DataColumn(label: Text(_t('evidence'))),
          DataColumn(label: Text(_t('review_status'))),
          DataColumn(label: Text(_t('action'))),
        ],
        rows: [
          for (final entry in entries)
            DataRow(
              selected: entry.progressEntryId == selectedEntryId,
              onSelectChanged: (_) => onSelect(entry),
              cells: [
                DataCell(
                  SizedBox(
                    width: 170,
                    child: Text(
                      entry.stageLabel ?? entry.stageKey,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall,
                    ),
                  ),
                ),
                DataCell(Text(_percent(entry.suggestedPercent))),
                DataCell(
                  SizedBox(
                    width: 112,
                    child: _ProgressBar(
                      value: _percentValue(entry.confirmedPercent),
                      label: _percent(entry.confirmedPercent),
                    ),
                  ),
                ),
                if (canViewValues)
                  DataCell(
                    Text(
                      entry.stageValue == null
                          ? '—'
                          : _money(entry.stageValue!),
                    ),
                  ),
                if (canViewValues)
                  DataCell(
                    Text(
                      entry.confirmedEligible == null
                          ? '—'
                          : _money(entry.confirmedEligible!),
                    ),
                  ),
                DataCell(
                  _Pill(
                    '${entry.evidenceDocumentIds.length} ${_t('files').toLowerCase()}',
                  ),
                ),
                DataCell(_ReviewPill(entry.reviewStatus, language)),
                DataCell(
                  canAct(entry)
                      ? TextButton(
                          onPressed: () => onAction(entry),
                          child: Text(_t('open_action')),
                        )
                      : Text('—', style: AppTypography.bodySmall),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.entry,
    required this.selected,
    required this.canViewValues,
    required this.language,
    required this.canAct,
    required this.onSelect,
    required this.onAction,
  });

  final YorksAccountsProgressEntry entry;
  final bool selected;
  final bool canViewValues;
  final AppLanguage language;
  final bool canAct;
  final VoidCallback onSelect;
  final VoidCallback onAction;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFEAF4FF) : Colors.transparent,
    child: InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.stageLabel ?? entry.stageKey,
                    style: AppTypography.titleSmall,
                  ),
                ),
                _ReviewPill(entry.reviewStatus, language),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ProgressBar(
              value: _percentValue(entry.confirmedPercent),
              label:
                  '${_t('confirmed_progress')} ${_percent(entry.confirmedPercent)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Pill(
                  '${_t('suggested_progress')} ${_percent(entry.suggestedPercent)}',
                ),
                _Pill(
                  '${entry.evidenceDocumentIds.length} ${_t('files').toLowerCase()}',
                ),
                if (canViewValues && entry.confirmedEligible != null)
                  _Pill(_money(entry.confirmedEligible!)),
              ],
            ),
            if (canAct) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(_t('open_action')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _StageDetails extends StatelessWidget {
  const _StageDetails({
    required this.entry,
    required this.language,
    required this.canViewValues,
    required this.canAct,
    required this.onAction,
  });

  final YorksAccountsProgressEntry entry;
  final AppLanguage language;
  final bool canViewValues;
  final bool canAct;
  final VoidCallback onAction;

  String _t(String key) => YorksV1AccountsStrings.text(language, key);

  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('line_details'),
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _ReviewPill(entry.reviewStatus, language),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          entry.stageLabel ?? entry.stageKey,
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          entry.buildingName ?? '—',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _DetailFact(
          label: _t('confirmed_progress'),
          value: _percent(entry.confirmedPercent),
        ),
        _DetailFact(
          label: _t('suggested_progress'),
          value: _percent(entry.suggestedPercent),
          valueColor: const Color(0xFF0B8F58),
        ),
        if (canViewValues) ...[
          _DetailFact(
            label: _t('stage_value'),
            value: entry.stageValue == null ? '—' : _money(entry.stageValue!),
          ),
          _DetailFact(
            label: _t('eligible_amount'),
            value: entry.confirmedEligible == null
                ? '—'
                : _money(entry.confirmedEligible!),
          ),
          _DetailFact(
            label: _t('available'),
            value: entry.availableToClaim == null
                ? '—'
                : _money(entry.availableToClaim!),
          ),
        ],
        _DetailFact(
          label: _t('evidence'),
          value:
              '${entry.evidenceDocumentIds.length} ${_t('files').toLowerCase()}',
        ),
        _DetailFact(
          label: _t('action_owner'),
          value: _wireLabel(language, entry.actionOwner),
        ),
        if (entry.updatedAt != null)
          _DetailFact(
            label: _t('last_update'),
            value: _shortDate(entry.updatedAt!.toLocal()),
          ),
        if (entry.evidenceSummary?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entry.evidenceSummary!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
        if (canAct) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_t('open_action')),
          ),
        ],
      ],
    ),
  );
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.title,
    required this.subtitle,
    required this.countLabel,
  });

  final String title;
  final String subtitle;
  final String countLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.account_tree_outlined,
            color: Color(0xFF146BE8),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 720)
          _Pill(countLabel, color: const Color(0xFFF0F5FB)),
      ],
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 9,
            backgroundColor: const Color(0xFFDDE6F0),
            color: const Color(0xFF2382EA),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Text(label, style: AppTypography.labelSmall),
    ],
  );
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.labelSmall.copyWith(
              color: valueColor ?? const Color(0xFF142443),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReviewPill extends StatelessWidget {
  const _ReviewPill(this.status, this.language);

  final YorksAccountsReviewStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      YorksAccountsReviewStatus.approved => (
        const Color(0xFFDDF7E9),
        const Color(0xFF087849),
      ),
      YorksAccountsReviewStatus.pending => (
        const Color(0xFFFFEECF),
        const Color(0xFF9C5900),
      ),
      YorksAccountsReviewStatus.returned => (
        const Color(0xFFFFE0E3),
        const Color(0xFFC51E2E),
      ),
      YorksAccountsReviewStatus.notRequired => (
        const Color(0xFFE9EFF6),
        const Color(0xFF4A5B73),
      ),
    };
    return _Pill(
      _wireLabel(language, status.wireValue),
      color: colors.$1,
      foreground: colors.$2,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
    this.label, {
    this.color = const Color(0xFFEAF3FF),
    this.foreground = const Color(0xFF145FC8),
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}

bool _hasAvailableProgressAction(
  YorksAccountsProgressProjection projection,
  YorksAccountsProgressEntry entry,
) {
  final available = entry.nextActions
      .where((action) => action.isAvailable)
      .map((action) => action.code)
      .toSet();
  return (projection.commands.allows('suggest_progress') &&
          available.contains('suggest_progress')) ||
      (projection.commands.allows('confirm_progress') &&
          available.contains('confirm_progress')) ||
      (projection.commands.allows('review_progress') &&
          available.contains('review_progress'));
}

double _percentValue(YorksAccountsDecimal value) =>
    ((double.tryParse(value.canonicalText) ?? 0) / 100).clamp(0, 1);

String _percent(YorksAccountsDecimal value) {
  final parsed = double.tryParse(value.canonicalText) ?? 0;
  return '${parsed.toStringAsFixed(parsed == parsed.roundToDouble() ? 0 : 1)}%';
}

String _ratioPercent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _money(YorksAccountsDecimal value) {
  final raw = value.canonicalText;
  final negative = raw.startsWith('-');
  final parts = (negative ? raw.substring(1) : raw).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final fraction = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
  return 'AED ${negative ? '-' : ''}$whole.$fraction';
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} '
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} '
    '${value.year}';

String _wireLabel(AppLanguage language, String value) {
  final localized = YorksV1AccountsStrings.text(language, value);
  if (localized != value) return localized;
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
