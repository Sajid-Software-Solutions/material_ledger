import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/ledger_card.dart';
import '../../../../core/widgets/yorks_v1_active_text.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_centre_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_strings.dart';
import '../../../../shared/models/yorks_v1_material_return_workflow.dart';
import '../../../../shared/models/yorks_v1_quantity.dart';

typedef _S = YorksV1MaterialReturnCentreStrings;
typedef _ReturnItem = YorksV1MaterialReturnRegisterItem;
typedef _State = YorksV1ProjectMaterialReturnState;

/// Material Return Centre home. Same structure as the Material Request Centre:
/// header, clickable metric cards, then one panel with search, sort, an
/// All returns / Projects switcher, filters, results and pagination.
class YorksV1MaterialReturnCentre extends StatefulWidget {
  const YorksV1MaterialReturnCentre({
    super.key,
    required this.language,
    required this.returns,
    required this.loading,
    required this.failed,
    required this.canCreate,
    required this.onCreate,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpen,
    this.onSearchChanged,
    this.serverMatchIds,
    this.now,
  });

  final AppLanguage language;
  final List<YorksV1MaterialReturnRegisterItem> returns;
  final bool loading;
  final bool failed;
  final bool canCreate;
  final VoidCallback? onCreate;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<YorksV1MaterialReturnRegisterItem> onOpen;

  /// Called with the trimmed search text so the host can ask the server to
  /// match item descriptions, which are not part of the register rows.
  final ValueChanged<String>? onSearchChanged;

  /// Return ids the server matched for the current search text.
  final Set<String>? serverMatchIds;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<YorksV1MaterialReturnCentre> createState() =>
      _YorksV1MaterialReturnCentreState();
}

enum _Metric { all, drafts, awaitingApproval, approved, dispatched, confirmed }

enum _View { allReturns, projects }

enum _DateRange { allTime, sevenDays, thirtyDays }

const _attentionIdle = Duration(days: 3);
const _all = '__all__';

bool _isTerminal(_State state) =>
    state == _State.confirmed ||
    state == _State.rejected ||
    state == _State.cancelled;

bool _needsAttention(_ReturnItem item, DateTime now) {
  if (item.state == _State.returnedForChanges) return true;
  if (_isTerminal(item.state) || item.state == _State.draft) return false;
  return now.difference(item.updatedAt) >= _attentionIdle;
}

bool _matchesMetric(_ReturnItem item, _Metric metric) => switch (metric) {
  _Metric.all => true,
  _Metric.drafts =>
    item.state == _State.draft || item.state == _State.returnedForChanges,
  _Metric.awaitingApproval => item.state == _State.awaitingApproval,
  _Metric.approved => item.state == _State.approved,
  _Metric.dispatched => item.state == _State.dispatched,
  _Metric.confirmed => item.state == _State.confirmed,
};

class _ProjectFolder {
  _ProjectFolder(this.id, this.reference, this.name);

  final String id;
  final String reference;
  final String name;
  final List<_ReturnItem> returns = [];

  _ReturnItem get latest => returns.first;
  int get active => returns.where((item) => !_isTerminal(item.state)).length;
  int get received =>
      returns.where((item) => item.state == _State.confirmed).length;
  int get buildingCount => returns.map((item) => item.scopeId).toSet().length;
}

class _YorksV1MaterialReturnCentreState
    extends State<YorksV1MaterialReturnCentre> {
  static const _folderPageSize = 10;
  static const _returnPageSize = 15;

  final _searchController = TextEditingController();
  _Metric _metric = _Metric.all;
  _View _view = _View.allReturns;
  _DateRange _dateRange = _DateRange.allTime;
  String _status = _all;
  String _project = _all;
  String _building = _all;
  String _drafter = _all;
  bool _attentionOnly = false;
  bool _newestFirst = true;
  bool _filtersExpanded = false;
  int _page = 0;
  final Set<String> _expandedProjectIds = {};

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) => setState(() {
    change();
    _page = 0;
  });

  void _clearFilters() {
    _update(() {
      _searchController.clear();
      _metric = _Metric.all;
      _dateRange = _DateRange.allTime;
      _status = _all;
      _project = _all;
      _building = _all;
      _drafter = _all;
      _attentionOnly = false;
    });
    widget.onSearchChanged?.call('');
  }

  int get _activeFilterCount => [
    _status != _all,
    _project != _all,
    _building != _all,
    _drafter != _all,
    _dateRange != _DateRange.allTime,
    _attentionOnly,
    _metric != _Metric.all,
  ].where((active) => active).length;

  List<_ReturnItem> _visible() {
    final now = _now;
    final query = _searchController.text.trim().toLowerCase();
    final cutoff = switch (_dateRange) {
      _DateRange.allTime => null,
      _DateRange.sevenDays => now.subtract(const Duration(days: 7)),
      _DateRange.thirtyDays => now.subtract(const Duration(days: 30)),
    };
    return widget.returns
        .where((item) {
          if (!_matchesMetric(item, _metric)) return false;
          if (_status != _all && item.state.wireValue != _status) return false;
          if (_project != _all && item.projectId != _project) return false;
          if (_building != _all && item.scopeId != _building) return false;
          if (_drafter != _all && item.draftedByDisplayName != _drafter) {
            return false;
          }
          if (cutoff != null && item.updatedAt.isBefore(cutoff)) return false;
          if (_attentionOnly && !_needsAttention(item, now)) return false;
          if (query.isEmpty) return true;
          if (widget.serverMatchIds?.contains(item.id) == true) return true;
          final searchable = [
            item.number,
            item.purpose,
            item.projectReference,
            item.projectName,
            item.scopeName,
            item.draftedByDisplayName,
          ].whereType<String>().join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false)
      ..sort(
        (a, b) => _newestFirst
            ? b.updatedAt.compareTo(a.updatedAt)
            : a.updatedAt.compareTo(b.updatedAt),
      );
  }

  List<_ProjectFolder> _folders(List<_ReturnItem> visible) {
    final folders = <String, _ProjectFolder>{};
    for (final item in visible) {
      folders
          .putIfAbsent(
            item.projectId,
            () => _ProjectFolder(
              item.projectId,
              item.projectReference,
              item.projectName,
            ),
          )
          .returns
          .add(item);
    }
    return folders.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final visible = _visible();
    final folders = _folders(visible);
    final isCompact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        key: const ValueKey('material-return-centre'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isCompact ? AppSpacing.md : AppSpacing.xl,
          isCompact ? AppSpacing.md : AppSpacing.lg,
          isCompact ? AppSpacing.md : AppSpacing.xxl,
          AppSpacing.xxxl,
        ),
        children: [
          _CentreHeader(
            language: language,
            canCreate: widget.canCreate,
            onCreate: widget.onCreate,
            onRefresh: widget.onRefresh,
          ),
          const SizedBox(height: AppSpacing.lg),
          _MetricsGrid(
            returns: widget.returns,
            language: language,
            selected: _metric,
            onSelected: (value) => _update(() {
              _metric = value;
              _view = _View.allReturns;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.failed && widget.returns.isEmpty)
            _LoadError(language: language, onRetry: widget.onRetry)
          else
            _MainPanel(
              language: language,
              now: _now,
              searchController: _searchController,
              onSearchChanged: (value) {
                _update(() {});
                widget.onSearchChanged?.call(value.trim());
              },
              newestFirst: _newestFirst,
              onSortChanged: (value) => _update(() => _newestFirst = value),
              view: _view,
              onViewChanged: (value) => _update(() => _view = value),
              filtersExpanded: _filtersExpanded,
              onFiltersExpandedChanged: (value) =>
                  setState(() => _filtersExpanded = value),
              activeFilterCount: _activeFilterCount,
              filter: _FilterForm(
                language: language,
                returns: widget.returns,
                status: _status,
                project: _project,
                building: _building,
                drafter: _drafter,
                dateRange: _dateRange,
                attentionOnly: _attentionOnly,
                onStatusChanged: (value) => _update(() => _status = value),
                onProjectChanged: (value) => _update(() {
                  _project = value;
                  _building = _all;
                }),
                onBuildingChanged: (value) => _update(() => _building = value),
                onDrafterChanged: (value) => _update(() => _drafter = value),
                onDateRangeChanged: (value) =>
                    _update(() => _dateRange = value),
                onAttentionOnlyChanged: (value) =>
                    _update(() => _attentionOnly = value),
                onClear: _clearFilters,
                onApply: () => setState(() => _filtersExpanded = false),
              ),
              loading: widget.loading && widget.returns.isEmpty,
              emptyRegister: widget.returns.isEmpty,
              folders: folders,
              returns: visible,
              folderPageSize: _folderPageSize,
              returnPageSize: _returnPageSize,
              expandedProjectIds: _expandedProjectIds,
              onProjectExpanded: (projectId) => setState(() {
                if (!_expandedProjectIds.add(projectId)) {
                  _expandedProjectIds.remove(projectId);
                }
              }),
              page: _page,
              onPageChanged: (value) => setState(() => _page = value),
              onOpen: widget.onOpen,
            ),
          if (widget.loading && widget.returns.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (widget.failed && widget.returns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, color: AppColors.muted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: YorksV1ActiveText(
                      copy: _S.loadFailed,
                      language: language,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: YorksV1ActiveText(
                      copy: _S.tryAgain,
                      language: language,
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

class _CentreHeader extends StatelessWidget {
  const _CentreHeader({
    required this.language,
    required this.canCreate,
    required this.onCreate,
    required this.onRefresh,
  });

  final AppLanguage language;
  final bool canCreate;
  final VoidCallback? onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 40 : 46,
          height: compact ? 40 : 46,
          decoration: BoxDecoration(
            color: AppColors.blueContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(
            Icons.assignment_return_outlined,
            color: AppColors.blue,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YorksV1ActiveText(
                copy: YorksV1MaterialReturnStrings.centre,
                language: language,
                style:
                    (compact
                            ? AppTypography.headlineMedium
                            : AppTypography.displaySmall)
                        .copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              YorksV1ActiveText(
                copy: YorksV1MaterialReturnStrings.centreDescription,
                language: language,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: [
        Tooltip(
          message: _S.refresh.active(language),
          child: SizedBox.square(
            dimension: AppSpacing.minTapTarget,
            child: IconButton(
              key: const ValueKey('material-return-centre-refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
        if (canCreate)
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: FilledButton.icon(
              key: const ValueKey('material-return-centre-create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: YorksV1ActiveText(
                copy: YorksV1MaterialReturnStrings.newReturn,
                language: language,
                style: AppTypography.titleSmall.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: AppSpacing.md),
          actions,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: AppSpacing.lg),
        actions,
      ],
    );
  }
}

class _MetricData {
  const _MetricData(
    this.label,
    this.hint,
    this.value,
    this.icon,
    this.foreground,
    this.background,
    this.metric,
  );

  final TranslatableString label;
  final TranslatableString hint;
  final int value;
  final IconData icon;
  final Color foreground;
  final Color background;
  final _Metric metric;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.returns,
    required this.language,
    required this.selected,
    required this.onSelected,
  });

  final List<YorksV1MaterialReturnRegisterItem> returns;
  final AppLanguage language;
  final _Metric selected;
  final ValueChanged<_Metric> onSelected;

  int _count(_Metric metric) =>
      returns.where((item) => _matchesMetric(item, metric)).length;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= AppSpacing.wideBreakpoint
          ? 6
          : width >= AppSpacing.compactBreakpoint
          ? 3
          : 2;
      const gap = AppSpacing.sm;
      final cardWidth = (width - (columns - 1) * gap) / columns;
      final tiles = [
        _MetricData(
          _S.totalReturns,
          _S.allTime,
          _count(_Metric.all),
          Icons.assignment_return_outlined,
          AppColors.blue,
          AppColors.blueContainer,
          _Metric.all,
        ),
        _MetricData(
          _S.draftsMetric,
          _S.withCreator,
          _count(_Metric.drafts),
          Icons.edit_note_rounded,
          AppColors.neutralText,
          AppColors.neutralContainer,
          _Metric.drafts,
        ),
        _MetricData(
          _S.awaitingApprovalMetric,
          _S.engineeringReview,
          _count(_Metric.awaitingApproval),
          Icons.schedule_rounded,
          AppColors.warning,
          AppColors.warningContainer,
          _Metric.awaitingApproval,
        ),
        _MetricData(
          _S.readyToDispatchMetric,
          _S.approvedHint,
          _count(_Metric.approved),
          Icons.task_alt_rounded,
          AppColors.purple,
          AppColors.purpleContainer,
          _Metric.approved,
        ),
        _MetricData(
          _S.inTransitMetric,
          _S.onTheWay,
          _count(_Metric.dispatched),
          Icons.local_shipping_outlined,
          AppColors.blue,
          AppColors.blueContainer,
          _Metric.dispatched,
        ),
        _MetricData(
          _S.receivedMetric,
          _S.backInWarehouse,
          _count(_Metric.confirmed),
          Icons.warehouse_outlined,
          AppColors.success,
          AppColors.successContainer,
          _Metric.confirmed,
        ),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                data: tile,
                language: language,
                selected: selected == tile.metric,
                onTap: () => onSelected(
                  selected == tile.metric ? _Metric.all : tile.metric,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.data,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final _MetricData data;
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(data.icon, color: data.foreground, size: 21),
    );
    final value = Text(
      '${data.value}',
      style: AppTypography.headlineSmall.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
    );
    final hint = YorksV1ActiveText(
      copy: data.hint,
      language: language,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        elevation: selected ? 2 : 1,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? data.foreground : AppColors.line,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: InkWell(
          key: ValueKey('material-return-metric-${data.metric.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 170) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [icon, const Spacer(), value]),
                      const SizedBox(height: AppSpacing.xs),
                      YorksV1ActiveText(
                        copy: data.label,
                        language: language,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      hint,
                    ],
                  );
                }
                return Row(
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          YorksV1ActiveText(
                            copy: data.label,
                            language: language,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          value,
                          hint,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.language,
    required this.now,
    required this.searchController,
    required this.onSearchChanged,
    required this.newestFirst,
    required this.onSortChanged,
    required this.view,
    required this.onViewChanged,
    required this.filtersExpanded,
    required this.onFiltersExpandedChanged,
    required this.activeFilterCount,
    required this.filter,
    required this.loading,
    required this.emptyRegister,
    required this.folders,
    required this.returns,
    required this.folderPageSize,
    required this.returnPageSize,
    required this.expandedProjectIds,
    required this.onProjectExpanded,
    required this.page,
    required this.onPageChanged,
    required this.onOpen,
  });

  final AppLanguage language;
  final DateTime now;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool newestFirst;
  final ValueChanged<bool> onSortChanged;
  final _View view;
  final ValueChanged<_View> onViewChanged;
  final bool filtersExpanded;
  final ValueChanged<bool> onFiltersExpandedChanged;
  final int activeFilterCount;
  final Widget filter;
  final bool loading;
  final bool emptyRegister;
  final List<_ProjectFolder> folders;
  final List<YorksV1MaterialReturnRegisterItem> returns;
  final int folderPageSize;
  final int returnPageSize;
  final Set<String> expandedProjectIds;
  final ValueChanged<String> onProjectExpanded;
  final int page;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<YorksV1MaterialReturnRegisterItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final showProjects = view == _View.projects;
    final totalItems = showProjects ? folders.length : returns.length;
    final pageSize = showProjects ? folderPageSize : returnPageSize;
    final pageCount = totalItems == 0
        ? 1
        : (totalItems + pageSize - 1) ~/ pageSize;
    final currentPage = page.clamp(0, pageCount - 1);
    final start = currentPage * pageSize;
    final end = (start + pageSize).clamp(0, totalItems);

    final Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (totalItems == 0) {
      body = _NoMatchingReturns(language: language, firstUse: emptyRegister);
    } else if (showProjects) {
      body = Column(
        children: [
          for (final folder in folders.sublist(start, end)) ...[
            _ExpandableProjectFolder(
              folder: folder,
              language: language,
              now: now,
              expanded: expandedProjectIds.contains(folder.id),
              onExpanded: () => onProjectExpanded(folder.id),
              onOpen: onOpen,
            ),
            if (folder != folders[end - 1])
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    } else {
      final pageReturns = returns.sublist(start, end);
      body = Column(
        children: [
          for (var index = 0; index < pageReturns.length; index++) ...[
            _ReturnCentreRow(
              item: pageReturns[index],
              language: language,
              now: now,
              onOpen: onOpen,
            ),
            if (index != pageReturns.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }

    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final search = TextField(
                  key: const ValueKey('material-return-centre-search'),
                  controller: searchController,
                  onChanged: onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _S.searchReturns.active(language),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _S.clearSearch.active(language),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                          ),
                  ),
                );
                final sort = _SortControl(
                  language: language,
                  newestFirst: newestFirst,
                  onChanged: onSortChanged,
                );
                final viewSwitcher = _ViewSwitcher(
                  language: language,
                  selected: view,
                  onChanged: onViewChanged,
                );
                final filterButton = _FilterButton(
                  language: language,
                  compact: compact,
                  expanded: filtersExpanded,
                  count: activeFilterCount,
                  onPressed: () => onFiltersExpandedChanged(!filtersExpanded),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [viewSwitcher, filterButton],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: sort,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.md),
                    sort,
                    const SizedBox(width: AppSpacing.xs),
                    viewSwitcher,
                    const SizedBox(width: AppSpacing.xs),
                    filterButton,
                  ],
                );
              },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: filtersExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: filter,
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: body),
          if (!loading && totalItems > 0)
            _Pagination(
              currentPage: currentPage,
              pageCount: pageCount,
              totalItems: totalItems,
              pageSize: pageSize,
              onChanged: onPageChanged,
            ),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.language,
    required this.selected,
    required this.onChanged,
  });

  final AppLanguage language;
  final _View selected;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Wrap(
      children: [
        _ViewOption(
          key: const ValueKey('material-return-centre-view-all'),
          icon: Icons.view_list_rounded,
          label: _S.allReturns.active(language),
          selected: selected == _View.allReturns,
          onPressed: () => onChanged(_View.allReturns),
        ),
        _ViewOption(
          key: const ValueKey('material-return-centre-view-projects'),
          icon: Icons.folder_outlined,
          label: _S.projects.active(language),
          selected: selected == _View.projects,
          onPressed: () => onChanged(_View.projects),
        ),
      ],
    ),
  );
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.surfaceContainerLowest : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.blue : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? AppColors.blue : AppColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.language,
    required this.newestFirst,
    required this.onChanged,
  });

  final AppLanguage language;
  final bool newestFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: AppSpacing.minTapTarget,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<bool>(
        key: const ValueKey('material-return-centre-sort'),
        value: newestFirst,
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
        items: [
          DropdownMenuItem(
            value: true,
            child: Text(_S.latestActivity.active(language)),
          ),
          DropdownMenuItem(
            value: false,
            child: Text(_S.oldestActivity.active(language)),
          ),
        ],
      ),
    ),
  );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.language,
    required this.compact,
    required this.expanded,
    required this.count,
    required this.onPressed,
  });

  final AppLanguage language;
  final bool compact;
  final bool expanded;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.blue,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        style: AppTypography.labelSmall.copyWith(color: Colors.white),
      ),
    );
    final icon = expanded
        ? Icons.filter_alt_off_outlined
        : Icons.filter_alt_outlined;
    if (compact) {
      final active = expanded || count > 0;
      return Tooltip(
        message: _S.filters.active(language),
        child: Stack(
          key: const ValueKey('material-return-centre-filter-button'),
          clipBehavior: Clip.none,
          children: [
            Material(
              color: active
                  ? AppColors.blueContainer
                  : AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: SizedBox.square(
                  dimension: AppSpacing.minTapTarget,
                  child: Icon(
                    icon,
                    size: 19,
                    color: active ? AppColors.blue : AppColors.muted,
                  ),
                ),
              ),
            ),
            if (count > 0) Positioned(right: -2, top: -2, child: badge),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      expanded: expanded,
      child: SizedBox(
        height: AppSpacing.minTapTarget,
        child: OutlinedButton.icon(
          key: const ValueKey('material-return-centre-filter-button'),
          onPressed: onPressed,
          icon: Icon(icon, size: 19),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              YorksV1ActiveText(
                copy: _S.filters,
                language: language,
                style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
              ),
              if (count > 0) ...[const SizedBox(width: 6), badge],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableProjectFolder extends StatelessWidget {
  const _ExpandableProjectFolder({
    required this.folder,
    required this.language,
    required this.now,
    required this.expanded,
    required this.onExpanded,
    required this.onOpen,
  });

  final _ProjectFolder folder;
  final AppLanguage language;
  final DateTime now;
  final bool expanded;
  final VoidCallback onExpanded;
  final ValueChanged<YorksV1MaterialReturnRegisterItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final arrow = Icon(
      key: ValueKey('material-return-project-arrow-${folder.id}'),
      expanded
          ? Icons.keyboard_arrow_up_rounded
          : Icons.keyboard_arrow_down_rounded,
      color: AppColors.muted,
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: expanded
              ? AppColors.blue.withValues(alpha: 0.35)
              : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: expanded
                ? AppColors.blueContainer.withValues(alpha: 0.35)
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('material-return-project-${folder.id}'),
              onTap: onExpanded,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = _FolderIdentity(
                      folder: folder,
                      language: language,
                      expanded: expanded,
                    );
                    if (constraints.maxWidth < 760) {
                      return Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.neutralContainer,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: Text(
                              '${folder.returns.length}',
                              style: AppTypography.labelLarge,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          arrow,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 5, child: identity),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: _FolderSummary(
                            folder: folder,
                            language: language,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: _FolderLatest(
                            folder: folder,
                            language: language,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        arrow,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Container(
                    key: ValueKey(
                      'material-return-project-contents-${folder.id}',
                    ),
                    width: double.infinity,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < folder.returns.length;
                          index++
                        ) ...[
                          _ExplorerReturnRow(
                            item: folder.returns[index],
                            language: language,
                            now: now,
                            onOpen: onOpen,
                          ),
                          if (index != folder.returns.length - 1)
                            const Divider(height: 1, color: AppColors.line),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _FolderIdentity extends StatelessWidget {
  const _FolderIdentity({
    required this.folder,
    required this.language,
    required this.expanded,
  });

  final _ProjectFolder folder;
  final AppLanguage language;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Icon(
          expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
          color: AppColors.warning,
          size: 23,
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.reference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
            ),
            const SizedBox(height: 2),
            Text(
              folder.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            YorksV1ActiveText(
              copy: _S.buildingsCount(folder.buildingCount),
              language: language,
              style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _FolderSummary extends StatelessWidget {
  const _FolderSummary({required this.folder, required this.language});

  final _ProjectFolder folder;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _FolderNumber(
          label: _S.totalReturnsShort,
          value: folder.returns.length,
          language: language,
        ),
      ),
      const SizedBox(
        height: 36,
        child: VerticalDivider(width: AppSpacing.md, color: AppColors.line),
      ),
      Expanded(
        child: _FolderNumber(
          label: _S.active,
          value: folder.active,
          language: language,
          color: AppColors.warning,
        ),
      ),
      const SizedBox(
        height: 36,
        child: VerticalDivider(width: AppSpacing.md, color: AppColors.line),
      ),
      Expanded(
        child: _FolderNumber(
          label: _S.receivedMetric,
          value: folder.received,
          language: language,
          color: AppColors.success,
        ),
      ),
    ],
  );
}

class _FolderNumber extends StatelessWidget {
  const _FolderNumber({
    required this.label,
    required this.value,
    required this.language,
    this.color = AppColors.ink,
  });

  final TranslatableString label;
  final int value;
  final AppLanguage language;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      YorksV1ActiveText(
        copy: label,
        language: language,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: 4),
      Text('$value', style: AppTypography.titleMedium.copyWith(color: color)),
    ],
  );
}

class _FolderLatest extends StatelessWidget {
  const _FolderLatest({required this.folder, required this.language});

  final _ProjectFolder folder;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final item = folder.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        YorksV1ActiveText(
          copy: _S.latestReturn,
          language: language,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 3),
        Text(
          _returnNumber(item, language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
        ),
        const SizedBox(height: 2),
        Text(
          _returnTitle(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 5),
        _ReturnStatePill(state: item.state, language: language),
      ],
    );
  }
}

String _returnNumber(_ReturnItem item, AppLanguage language) =>
    item.number ?? _S.draft.active(language);

String _returnTitle(_ReturnItem item) => item.purpose?.trim().isNotEmpty == true
    ? item.purpose!.trim()
    : item.scopeName;

String _returnMeta(_ReturnItem item, AppLanguage language) =>
    '${item.scopeName} · ${_S.itemsCount(item.lineCount).active(language)} · '
    '${_S.quantity(yorksV1DisplayQuantity(item.totalQuantity)).active(language)}';

class _ReturnKindIcon extends StatelessWidget {
  const _ReturnKindIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(
      Icons.assignment_return_outlined,
      color: AppColors.blue,
      size: size <= 36 ? 20 : 24,
    ),
  );
}

class _ExplorerReturnRow extends StatelessWidget {
  const _ExplorerReturnRow({
    required this.item,
    required this.language,
    required this.now,
    required this.onOpen,
  });

  final _ReturnItem item;
  final AppLanguage language;
  final DateTime now;
  final ValueChanged<YorksV1MaterialReturnRegisterItem> onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('material-return-row-${item.id}'),
      onTap: () => onOpen(item),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              const _ReturnKindIcon(size: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_returnNumber(item, language)} · ${_returnTitle(item)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _returnMeta(item, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _ReturnActionSummary(
                      item: item,
                      language: language,
                      now: now,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ReturnStatePill(state: item.state, language: language),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ReturnCentreRow extends StatelessWidget {
  const _ReturnCentreRow({
    required this.item,
    required this.language,
    required this.now,
    required this.onOpen,
  });

  final _ReturnItem item;
  final AppLanguage language;
  final DateTime now;
  final ValueChanged<YorksV1MaterialReturnRegisterItem> onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        key: ValueKey('material-return-row-${item.id}'),
        onTap: () => onOpen(item),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _returnNumber(item, language),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.projectName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.projectReference} · ${_returnMeta(item, language)}',
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (item.purpose?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.purpose!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  _ReturnActionSummary(
                    item: item,
                    language: language,
                    now: now,
                    compact: compact,
                  ),
                ],
              );
              final state = _ReturnStatePill(
                state: item.state,
                language: language,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _ReturnKindIcon(size: 44),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: details),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 44 + AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: state,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  const _ReturnKindIcon(size: 44),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: details),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 168,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: state,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const SizedBox.square(
                    dimension: AppSpacing.minTapTarget,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ReturnActionSummary extends StatelessWidget {
  const _ReturnActionSummary({
    required this.item,
    required this.language,
    required this.now,
    required this.compact,
  });

  final _ReturnItem item;
  final AppLanguage language;
  final DateTime now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final owner = yorksV1MaterialReturnOwnerCopy(item.state).active(language);
    final next = yorksV1MaterialReturnNextActionCopy(
      item.state,
    ).active(language);
    final terminal = _isTerminal(item.state);
    final idle = now.difference(item.updatedAt);
    final attention = _needsAttention(item, now);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(item.updatedAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          terminal
              ? next
              : '${_S.currentOwner.active(language)}: $owner · ${_S.nextAction.active(language)}: $next',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            _Fact(
              icon: Icons.person_outline_rounded,
              text: item.draftedByDisplayName,
            ),
            _Fact(
              icon: Icons.event_outlined,
              text: '${_S.updated.active(language)}: $date',
            ),
            if (!terminal && item.state != _State.draft && idle.inHours >= 1)
              _Fact(
                icon: attention
                    ? Icons.warning_amber_rounded
                    : Icons.schedule_outlined,
                text: '${_S.waiting.active(language)}: ${_age(idle)}',
                alert: attention,
              ),
          ],
        ),
      ],
    );
  }

  static String _age(Duration idle) {
    if (idle.inHours >= 48) return '${idle.inDays} d';
    if (idle.inHours >= 1) return '${idle.inHours} h';
    return '<1 h';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.alert = false});

  final IconData icon;
  final String text;
  final bool alert;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: alert ? AppColors.error : AppColors.muted),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: alert ? AppColors.error : AppColors.muted,
            fontWeight: alert ? FontWeight.w700 : null,
          ),
        ),
      ),
    ],
  );
}

class _ReturnStatePill extends StatelessWidget {
  const _ReturnStatePill({required this.state, required this.language});

  final _State state;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (state) {
      _State.rejected || _State.cancelled => (
        AppColors.errorContainer,
        AppColors.onErrorContainer,
      ),
      _State.awaitingApproval || _State.returnedForChanges => (
        AppColors.warningContainer,
        AppColors.onWarningContainer,
      ),
      _State.approved => (
        AppColors.purpleContainer,
        AppColors.onTertiaryContainer,
      ),
      _State.confirmed => (
        AppColors.successContainer,
        AppColors.onSuccessContainer,
      ),
      _State.draft => (AppColors.neutralContainer, AppColors.neutralText),
      _State.dispatched => (
        AppColors.blueContainer,
        AppColors.onPrimaryContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        yorksV1ProjectMaterialReturnStateCopy(state).active(language),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: foreground),
      ),
    );
  }
}

class _NoMatchingReturns extends StatelessWidget {
  const _NoMatchingReturns({required this.language, required this.firstUse});

  final AppLanguage language;
  final bool firstUse;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
    child: Column(
      children: [
        Icon(
          firstUse
              ? Icons.assignment_return_outlined
              : Icons.search_off_rounded,
          size: 36,
          color: AppColors.muted,
        ),
        const SizedBox(height: AppSpacing.sm),
        YorksV1ActiveText(
          copy: firstUse ? _S.noReturnsYet : _S.noMatchingReturns,
          language: language,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.language, required this.onRetry});

  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => LedgerCard(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36, color: AppColors.muted),
        const SizedBox(height: AppSpacing.sm),
        YorksV1ActiveText(
          copy: _S.loadFailed,
          language: language,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const ValueKey('material-return-centre-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: YorksV1ActiveText(copy: _S.tryAgain, language: language),
        ),
      ],
    ),
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.currentPage,
    required this.pageCount,
    required this.totalItems,
    required this.pageSize,
    required this.onChanged,
  });

  final int currentPage;
  final int pageCount;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${currentPage * pageSize + 1}–${((currentPage + 1) * pageSize).clamp(0, totalItems)} / $totalItems',
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ),
        IconButton(
          key: const ValueKey('material-return-centre-page-previous'),
          tooltip: MaterialLocalizations.of(context).previousPageTooltip,
          onPressed: currentPage == 0 ? null : () => onChanged(currentPage - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentPage + 1} / $pageCount',
          style: AppTypography.labelLarge,
        ),
        IconButton(
          key: const ValueKey('material-return-centre-page-next'),
          tooltip: MaterialLocalizations.of(context).nextPageTooltip,
          onPressed: currentPage >= pageCount - 1
              ? null
              : () => onChanged(currentPage + 1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _FilterEntry<T> {
  const _FilterEntry(this.value, this.label);

  final T value;
  final String label;
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.id,
    required this.label,
    required this.value,
    required this.language,
    required this.entries,
    required this.onChanged,
  });

  final String id;
  final TranslatableString label;
  final T value;
  final AppLanguage language;
  final List<_FilterEntry<T>> entries;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    key: ValueKey('material-return-filter-$id-$value'),
    initialValue: entries.any((entry) => entry.value == value)
        ? value
        : entries.first.value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label.active(language)),
    items: [
      for (final entry in entries)
        DropdownMenuItem(
          value: entry.value,
          child: Text(entry.label, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _FilterForm extends StatelessWidget {
  const _FilterForm({
    required this.language,
    required this.returns,
    required this.status,
    required this.project,
    required this.building,
    required this.drafter,
    required this.dateRange,
    required this.attentionOnly,
    required this.onStatusChanged,
    required this.onProjectChanged,
    required this.onBuildingChanged,
    required this.onDrafterChanged,
    required this.onDateRangeChanged,
    required this.onAttentionOnlyChanged,
    required this.onClear,
    required this.onApply,
  });

  final AppLanguage language;
  final List<YorksV1MaterialReturnRegisterItem> returns;
  final String status;
  final String project;
  final String building;
  final String drafter;
  final _DateRange dateRange;
  final bool attentionOnly;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onBuildingChanged;
  final ValueChanged<String> onDrafterChanged;
  final ValueChanged<_DateRange> onDateRangeChanged;
  final ValueChanged<bool> onAttentionOnlyChanged;
  final VoidCallback onClear;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final projects = <String, _ReturnItem>{
      for (final item in returns) item.projectId: item,
    };
    final buildings = <String, _ReturnItem>{
      for (final item in returns)
        if (project == _all || item.projectId == project) item.scopeId: item,
    };
    final drafters =
        returns
            .map((item) => item.draftedByDisplayName)
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final showProjectInBuilding = project == _all && projects.length > 1;
    final fields = <Widget>[
      _FilterDropdown<String>(
        id: 'status',
        label: _S.returnStatus,
        value: status,
        language: language,
        onChanged: onStatusChanged,
        entries: [
          _FilterEntry(_all, _S.allStatuses.active(language)),
          for (final state in _State.values)
            _FilterEntry(
              state.wireValue,
              yorksV1ProjectMaterialReturnStateCopy(state).active(language),
            ),
        ],
      ),
      _FilterDropdown<String>(
        id: 'project',
        label: _S.project,
        value: project,
        language: language,
        onChanged: onProjectChanged,
        entries: [
          _FilterEntry(_all, _S.allProjects.active(language)),
          for (final entry in projects.entries)
            _FilterEntry(
              entry.key,
              '${entry.value.projectReference} · ${entry.value.projectName}',
            ),
        ],
      ),
      _FilterDropdown<String>(
        id: 'building',
        label: _S.building,
        value: building,
        language: language,
        onChanged: onBuildingChanged,
        entries: [
          _FilterEntry(_all, _S.allBuildings.active(language)),
          for (final entry in buildings.entries)
            _FilterEntry(
              entry.key,
              showProjectInBuilding
                  ? '${entry.value.projectReference} · ${entry.value.scopeName}'
                  : entry.value.scopeName,
            ),
        ],
      ),
      _FilterDropdown<String>(
        id: 'drafter',
        label: _S.draftedBy,
        value: drafter,
        language: language,
        onChanged: onDrafterChanged,
        entries: [
          _FilterEntry(_all, _S.allUsers.active(language)),
          for (final name in drafters) _FilterEntry(name, name),
        ],
      ),
      _FilterDropdown<_DateRange>(
        id: 'date',
        label: _S.dateRange,
        value: dateRange,
        language: language,
        onChanged: onDateRangeChanged,
        entries: [
          _FilterEntry(_DateRange.allTime, _S.allTime.active(language)),
          _FilterEntry(_DateRange.sevenDays, _S.last7Days.active(language)),
          _FilterEntry(_DateRange.thirtyDays, _S.last30Days.active(language)),
        ],
      ),
      Material(
        color: attentionOnly
            ? AppColors.warningContainer.withValues(alpha: 0.45)
            : AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
          key: const ValueKey('material-return-filter-attention'),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          value: attentionOnly,
          onChanged: onAttentionOnlyChanged,
          title: YorksV1ActiveText(
            copy: _S.attentionRequired,
            language: language,
            style: AppTypography.labelLarge.copyWith(color: AppColors.ink),
          ),
          subtitle: YorksV1ActiveText(
            copy: _S.attentionHint,
            language: language,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
        ),
      ),
    ];

    return LedgerCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.blue, size: 19),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: YorksV1ActiveText(
                  copy: _S.filters,
                  language: language,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('material-return-centre-clear-filters'),
                onPressed: onClear,
                child: YorksV1ActiveText(
                  copy: _S.clearAll,
                  language: language,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              final fieldWidth = columns == 2
                  ? (constraints.maxWidth - AppSpacing.sm) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final field in fields)
                    SizedBox(width: fieldWidth, child: field),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: 190,
              height: AppSpacing.minTapTarget,
              child: FilledButton(
                key: const ValueKey('material-return-centre-apply-filters'),
                onPressed: onApply,
                child: YorksV1ActiveText(
                  copy: _S.applyFilters,
                  language: language,
                  style: AppTypography.titleSmall.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
