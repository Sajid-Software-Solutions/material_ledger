import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_logistics_strings.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';

/// Role-safe cross-project dispatch register.
///
/// Every row is derived from the authorized Material Request projection. This
/// centre only organizes and filters that projection; it does not infer action
/// authority or mutate logistics state.
class YorksV1DispatchCentre extends StatefulWidget {
  const YorksV1DispatchCentre({
    super.key,
    required this.requests,
    required this.language,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<YorksV1MaterialRequest> requests;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialRequest> onOpen;
  final VoidCallback onRefresh;

  @override
  State<YorksV1DispatchCentre> createState() => _YorksV1DispatchCentreState();
}

enum _DispatchCentreView { projects, all, attention, completed }

class _YorksV1DispatchCentreState extends State<YorksV1DispatchCentre> {
  static const _all = '__all__';
  static const _pageSize = 15;

  final _search = TextEditingController();
  _DispatchCentreView _view = _DispatchCentreView.projects;
  String _projectId = _all;
  String _requester = _all;
  bool _newestFirst = true;
  int _page = 0;
  final Set<String> _expandedProjects = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) => setState(() {
    update();
    _page = 0;
  });

  @override
  Widget build(BuildContext context) {
    final allRequests = widget.requests
        .where(_isDispatchWorkflowRequest)
        .toList(growable: false);
    final visible = _visibleRequests(allRequests);
    final folders = _projectFolders(visible);
    final metrics = _DispatchCentreMetrics.fromRequests(allRequests);
    final compact = MediaQuery.sizeOf(context).width < 760;

    return ListView(
      key: const ValueKey('dispatch-centre'),
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.md : AppSpacing.xl,
        compact ? AppSpacing.md : AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        _DispatchCentreHeader(
          language: widget.language,
          onRefresh: widget.onRefresh,
        ),
        const SizedBox(height: AppSpacing.lg),
        _DispatchMetrics(
          metrics: metrics,
          language: widget.language,
          onSelect: (view) => _update(() => _view = view),
        ),
        const SizedBox(height: AppSpacing.lg),
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DispatchViewTabs(
                selected: _view,
                language: widget.language,
                attentionCount: metrics.attention,
                onChanged: (view) => _update(() => _view = view),
              ),
              const Divider(height: 1, color: AppColors.line),
              _DispatchFilters(
                language: widget.language,
                searchController: _search,
                projectId: _projectId,
                requester: _requester,
                newestFirst: _newestFirst,
                projects: _projectOptions(allRequests),
                requesters: _requesterOptions(allRequests),
                onSearchChanged: (_) => _update(() {}),
                onProjectChanged: (value) => _update(() => _projectId = value),
                onRequesterChanged: (value) =>
                    _update(() => _requester = value),
                onSortChanged: (value) => _update(() => _newestFirst = value),
                onClear: () => _update(() {
                  _search.clear();
                  _projectId = _all;
                  _requester = _all;
                  _newestFirst = true;
                }),
              ),
              const Divider(height: 1, color: AppColors.line),
              if (visible.isEmpty)
                _DispatchEmpty(language: widget.language)
              else if (_view == _DispatchCentreView.projects)
                _DispatchProjectFolders(
                  folders: folders,
                  language: widget.language,
                  expanded: _expandedProjects,
                  onToggle: (projectId) => setState(() {
                    if (!_expandedProjects.add(projectId)) {
                      _expandedProjects.remove(projectId);
                    }
                  }),
                  onOpen: widget.onOpen,
                )
              else
                _DispatchRegister(
                  requests: _pageItems(visible),
                  language: widget.language,
                  onOpen: widget.onOpen,
                ),
              if (_view != _DispatchCentreView.projects && visible.isNotEmpty)
                _DispatchPagination(
                  page: _page,
                  pageSize: _pageSize,
                  total: visible.length,
                  onPrevious: _page == 0 ? null : () => setState(() => _page--),
                  onNext: (_page + 1) * _pageSize >= visible.length
                      ? null
                      : () => setState(() => _page++),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<YorksV1MaterialRequest> _visibleRequests(
    List<YorksV1MaterialRequest> requests,
  ) {
    final query = _search.text.trim().toLowerCase();
    final visible = requests
        .where((request) {
          if (_projectId != _all && request.projectId != _projectId) {
            return false;
          }
          if (_requester != _all &&
              (request.requesterDisplayName ?? '') != _requester) {
            return false;
          }
          if (!_matchesView(request, _view)) return false;
          if (query.isEmpty) return true;
          return [
            request.requestNumber,
            request.projectReference,
            request.projectName,
            request.scopeName,
            request.requesterDisplayName,
            request.title,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
    visible.sort(
      (a, b) => _newestFirst
          ? b.updatedAt.compareTo(a.updatedAt)
          : a.updatedAt.compareTo(b.updatedAt),
    );
    return visible;
  }

  List<YorksV1MaterialRequest> _pageItems(
    List<YorksV1MaterialRequest> requests,
  ) {
    final safePage = _page.clamp(0, (requests.length - 1) ~/ _pageSize);
    final start = safePage * _pageSize;
    final end = (start + _pageSize).clamp(0, requests.length);
    return requests.sublist(start, end);
  }
}

bool _isDispatchWorkflowRequest(YorksV1MaterialRequest request) =>
    switch (request.state) {
      YorksV1MaterialRequestState.approved ||
      YorksV1MaterialRequestState.partiallyDispatched ||
      YorksV1MaterialRequestState.dispatched ||
      YorksV1MaterialRequestState.partiallyReceived ||
      YorksV1MaterialRequestState.received ||
      YorksV1MaterialRequestState.closed => true,
      _ => false,
    };

bool _isReady(YorksV1MaterialRequest request) => request.dispatchReady;

bool _needsReceiptReview(YorksV1MaterialRequest request) =>
    request.state == YorksV1MaterialRequestState.dispatched ||
    request.state == YorksV1MaterialRequestState.partiallyReceived;

bool _isCompleted(YorksV1MaterialRequest request) =>
    request.state == YorksV1MaterialRequestState.received ||
    request.state == YorksV1MaterialRequestState.closed;

bool _matchesView(YorksV1MaterialRequest request, _DispatchCentreView view) =>
    switch (view) {
      _DispatchCentreView.projects || _DispatchCentreView.all => true,
      _DispatchCentreView.attention =>
        _isReady(request) || _needsReceiptReview(request),
      _DispatchCentreView.completed => _isCompleted(request),
    };

class _DispatchCentreHeader extends StatelessWidget {
  const _DispatchCentreHeader({
    required this.language,
    required this.onRefresh,
  });

  final AppLanguage language;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            YorksV1ShellStrings.operationalWorkspace.active(language),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.blue,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1LogisticsStrings.dispatchCentre.active(language),
            style: AppTypography.displaySmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            YorksV1LogisticsStrings.dispatchCentreDescription.active(language),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
        ],
      );
      final refresh = OutlinedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(YorksV1LogisticsStrings.refresh.active(language)),
      );
      if (constraints.maxWidth < 620) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: AppSpacing.md),
            SizedBox(height: AppSpacing.minTapTarget, child: refresh),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(height: AppSpacing.minTapTarget, child: refresh),
        ],
      );
    },
  );
}

class _DispatchCentreMetrics {
  const _DispatchCentreMetrics({
    required this.total,
    required this.ready,
    required this.receiptRequired,
    required this.completed,
  });

  final int total;
  final int ready;
  final int receiptRequired;
  final int completed;

  int get attention => ready + receiptRequired;

  factory _DispatchCentreMetrics.fromRequests(
    List<YorksV1MaterialRequest> requests,
  ) => _DispatchCentreMetrics(
    total: requests.length,
    ready: requests.where(_isReady).length,
    receiptRequired: requests.where(_needsReceiptReview).length,
    completed: requests.where(_isCompleted).length,
  );
}

class _DispatchMetrics extends StatelessWidget {
  const _DispatchMetrics({
    required this.metrics,
    required this.language,
    required this.onSelect,
  });

  final _DispatchCentreMetrics metrics;
  final AppLanguage language;
  final ValueChanged<_DispatchCentreView> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 920
          ? (constraints.maxWidth - AppSpacing.md * 3) / 4
          : constraints.maxWidth >= 520
          ? (constraints.maxWidth - AppSpacing.md) / 2
          : constraints.maxWidth;
      final data =
          <
            ({
              TranslatableString label,
              int value,
              IconData icon,
              Color color,
              Color background,
              _DispatchCentreView view,
            })
          >[
            (
              label: YorksV1LogisticsStrings.totalDispatchRequests,
              value: metrics.total,
              icon: Icons.receipt_long_outlined,
              color: AppColors.blue,
              background: AppColors.blueContainer,
              view: _DispatchCentreView.all,
            ),
            (
              label: YorksV1LogisticsStrings.readyToDispatch,
              value: metrics.ready,
              icon: Icons.inventory_2_outlined,
              color: AppColors.warning,
              background: AppColors.warningContainer,
              view: _DispatchCentreView.attention,
            ),
            (
              label: YorksV1LogisticsStrings.receiptReviewRequired,
              value: metrics.receiptRequired,
              icon: Icons.local_shipping_outlined,
              color: AppColors.purple,
              background: AppColors.purpleContainer,
              view: _DispatchCentreView.attention,
            ),
            (
              label: YorksV1LogisticsStrings.completedDeliveries,
              value: metrics.completed,
              icon: Icons.task_alt_rounded,
              color: AppColors.success,
              background: AppColors.successContainer,
              view: _DispatchCentreView.completed,
            ),
          ];
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final item in data)
            SizedBox(
              width: width,
              child: _DispatchMetricCard(
                label: item.label.active(language),
                value: item.value,
                icon: item.icon,
                color: item.color,
                background: item.background,
                onTap: () => onSelect(item.view),
              ),
            ),
        ],
      );
    },
  );
}

class _DispatchMetricCard extends StatelessWidget {
  const _DispatchMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('$value', style: AppTypography.headlineSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DispatchViewTabs extends StatelessWidget {
  const _DispatchViewTabs({
    required this.selected,
    required this.language,
    required this.attentionCount,
    required this.onChanged,
  });

  final _DispatchCentreView selected;
  final AppLanguage language;
  final int attentionCount;
  final ValueChanged<_DispatchCentreView> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs =
        <
          ({
            _DispatchCentreView value,
            TranslatableString label,
            IconData icon,
            int? count,
          })
        >[
          (
            value: _DispatchCentreView.projects,
            label: YorksV1LogisticsStrings.projectFolders,
            icon: Icons.folder_outlined,
            count: null,
          ),
          (
            value: _DispatchCentreView.all,
            label: YorksV1LogisticsStrings.allDispatches,
            icon: Icons.table_rows_outlined,
            count: null,
          ),
          (
            value: _DispatchCentreView.attention,
            label: YorksV1LogisticsStrings.attentionRequired,
            icon: Icons.error_outline_rounded,
            count: attentionCount,
          ),
          (
            value: _DispatchCentreView.completed,
            label: YorksV1LogisticsStrings.completedArchive,
            icon: Icons.inventory_2_outlined,
            count: null,
          ),
        ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
              child: _DispatchTab(
                selected: selected == tab.value,
                icon: tab.icon,
                label: tab.label.active(language),
                count: tab.count,
                onTap: () => onChanged(tab.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _DispatchTab extends StatelessWidget {
  const _DispatchTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppSpacing.radiusSm),
    ),
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? AppColors.blue : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? AppColors.blue : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? AppColors.blue : AppColors.inkSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _DispatchFilters extends StatelessWidget {
  const _DispatchFilters({
    required this.language,
    required this.searchController,
    required this.projectId,
    required this.requester,
    required this.newestFirst,
    required this.projects,
    required this.requesters,
    required this.onSearchChanged,
    required this.onProjectChanged,
    required this.onRequesterChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final AppLanguage language;
  final TextEditingController searchController;
  final String projectId;
  final String requester;
  final bool newestFirst;
  final List<({String id, String label})> projects;
  final List<String> requesters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onRequesterChanged;
  final ValueChanged<bool> onSortChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final search = TextField(
          key: const ValueKey('dispatch-search'),
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: YorksV1LogisticsStrings.searchDispatches.active(language),
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        );
        final filters = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: compact ? constraints.maxWidth : 205,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('dispatch-project-filter'),
                initialValue: projectId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1LogisticsStrings.project.active(language),
                ),
                items: [
                  DropdownMenuItem(
                    value: _YorksV1DispatchCentreState._all,
                    child: Text(
                      YorksV1MaterialRequestStrings.allProjects.active(
                        language,
                      ),
                    ),
                  ),
                  for (final project in projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(
                        project.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onProjectChanged(value);
                },
              ),
            ),
            SizedBox(
              width: compact ? constraints.maxWidth : 185,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('dispatch-requester-filter'),
                initialValue: requester,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1MaterialRequestStrings.requestedBy.active(
                    language,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: _YorksV1DispatchCentreState._all,
                    child: Text(
                      YorksV1MaterialRequestStrings.allUsers.active(language),
                    ),
                  ),
                  for (final name in requesters)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (value) {
                  if (value != null) onRequesterChanged(value);
                },
              ),
            ),
            SizedBox(
              width: compact ? constraints.maxWidth : 175,
              child: DropdownButtonFormField<bool>(
                key: const ValueKey('dispatch-sort'),
                initialValue: newestFirst,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: YorksV1MaterialRequestStrings.sortBy.active(
                    language,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: true,
                    child: Text(
                      YorksV1MaterialRequestStrings.latestActivity.active(
                        language,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text(
                      YorksV1MaterialRequestStrings.oldestActivity.active(
                        language,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
            ),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: Text(
                  YorksV1MaterialRequestStrings.clearAll.active(language),
                ),
              ),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.sm),
              filters,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: AppSpacing.sm),
            filters,
          ],
        );
      },
    ),
  );
}

List<({String id, String label})> _projectOptions(
  List<YorksV1MaterialRequest> requests,
) {
  final options = <String, String>{};
  for (final request in requests) {
    options[request.projectId] =
        '${request.projectReference} - ${request.projectName}';
  }
  final result = [
    for (final entry in options.entries) (id: entry.key, label: entry.value),
  ];
  result.sort((a, b) => a.label.compareTo(b.label));
  return result;
}

List<String> _requesterOptions(List<YorksV1MaterialRequest> requests) {
  final names = <String>{
    for (final request in requests)
      if (request.requesterDisplayName?.trim().isNotEmpty == true)
        request.requesterDisplayName!.trim(),
  }.toList(growable: false);
  names.sort();
  return names;
}

class _DispatchProjectFolder {
  const _DispatchProjectFolder({
    required this.projectId,
    required this.reference,
    required this.name,
    required this.requests,
  });

  final String projectId;
  final String reference;
  final String name;
  final List<YorksV1MaterialRequest> requests;

  int get ready => requests.where(_isReady).length;
  int get attention => requests.where(_needsReceiptReview).length;
  int get completed => requests.where(_isCompleted).length;
  int get scopeCount =>
      requests.map((request) => request.scopeId).toSet().length;
  YorksV1MaterialRequest get latest => requests.first;
}

List<_DispatchProjectFolder> _projectFolders(
  List<YorksV1MaterialRequest> requests,
) {
  final grouped = <String, List<YorksV1MaterialRequest>>{};
  for (final request in requests) {
    grouped.putIfAbsent(request.projectId, () => []).add(request);
  }
  final folders = [
    for (final entry in grouped.entries)
      _DispatchProjectFolder(
        projectId: entry.key,
        reference: entry.value.first.projectReference,
        name: entry.value.first.projectName,
        requests: entry.value
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      ),
  ];
  folders.sort((a, b) => b.latest.updatedAt.compareTo(a.latest.updatedAt));
  return folders;
}

class _DispatchProjectFolders extends StatelessWidget {
  const _DispatchProjectFolders({
    required this.folders,
    required this.language,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final List<_DispatchProjectFolder> folders;
  final AppLanguage language;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;
  final ValueChanged<YorksV1MaterialRequest> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      children: [
        for (var index = 0; index < folders.length; index++) ...[
          _DispatchProjectFolderCard(
            folder: folders[index],
            language: language,
            expanded: expanded.contains(folders[index].projectId),
            onToggle: () => onToggle(folders[index].projectId),
            onOpen: onOpen,
          ),
          if (index != folders.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _DispatchProjectFolderCard extends StatelessWidget {
  const _DispatchProjectFolderCard({
    required this.folder,
    required this.language,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final _DispatchProjectFolder folder;
  final AppLanguage language;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<YorksV1MaterialRequest> onOpen;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final identity = Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.warningContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Icon(
                        expanded
                            ? Icons.folder_open_rounded
                            : Icons.folder_rounded,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            folder.reference,
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.blue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            folder.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${folder.scopeCount} ${YorksV1MaterialRequestStrings.scopes.active(language).toLowerCase()}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final summary = _DispatchFolderSummary(
                  folder: folder,
                  language: language,
                );
                final chevron = Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.muted,
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: identity),
                          chevron,
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      summary,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 5, child: identity),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 4, child: summary),
                    const SizedBox(width: AppSpacing.md),
                    chevron,
                  ],
                );
              },
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1, color: AppColors.line),
          _DispatchRegister(
            requests: folder.requests,
            language: language,
            onOpen: onOpen,
            nested: true,
          ),
        ],
      ],
    ),
  );
}

class _DispatchFolderSummary extends StatelessWidget {
  const _DispatchFolderSummary({required this.folder, required this.language});

  final _DispatchProjectFolder folder;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _FolderMetric(
        label: YorksV1MaterialRequestStrings.requests.active(language),
        value: folder.requests.length,
      ),
      const SizedBox(width: AppSpacing.lg),
      _FolderMetric(
        label: YorksV1LogisticsStrings.readyToDispatch.active(language),
        value: folder.ready,
        color: AppColors.warning,
      ),
      const SizedBox(width: AppSpacing.lg),
      _FolderMetric(
        label: YorksV1LogisticsStrings.receiptReview.active(language),
        value: folder.attention,
        color: AppColors.purple,
      ),
      const SizedBox(width: AppSpacing.lg),
      _FolderMetric(
        label: YorksV1LogisticsStrings.completedDeliveries.active(language),
        value: folder.completed,
        color: AppColors.success,
      ),
    ],
  );
}

class _FolderMetric extends StatelessWidget {
  const _FolderMetric({
    required this.label,
    required this.value,
    this.color = AppColors.ink,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 3),
        Text('$value', style: AppTypography.titleMedium.copyWith(color: color)),
      ],
    ),
  );
}

class _DispatchRegister extends StatelessWidget {
  const _DispatchRegister({
    required this.requests,
    required this.language,
    required this.onOpen,
    this.nested = false,
  });

  final List<YorksV1MaterialRequest> requests;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialRequest> onOpen;
  final bool nested;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 820) {
        return Padding(
          padding: EdgeInsets.all(nested ? AppSpacing.sm : AppSpacing.md),
          child: Column(
            children: [
              for (var index = 0; index < requests.length; index++) ...[
                _DispatchRequestCard(
                  request: requests[index],
                  language: language,
                  onOpen: () => onOpen(requests[index]),
                ),
                if (index != requests.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 1120 ? 1120 : constraints.maxWidth,
          child: Table(
            key: const ValueKey('dispatch-register-table'),
            columnWidths: const {
              0: FixedColumnWidth(145),
              1: FlexColumnWidth(2.2),
              2: FlexColumnWidth(1.45),
              3: FlexColumnWidth(1.2),
              4: FixedColumnWidth(72),
              5: FixedColumnWidth(150),
              6: FixedColumnWidth(120),
              7: FixedColumnWidth(64),
            },
            border: const TableBorder(
              horizontalInside: BorderSide(color: AppColors.line),
            ),
            children: [
              _dispatchHeaderRow(language),
              for (final request in requests)
                _dispatchDataRow(request, language, () => onOpen(request)),
            ],
          ),
        ),
      );
    },
  );
}

TableRow _dispatchHeaderRow(AppLanguage language) => TableRow(
  decoration: const BoxDecoration(color: AppColors.surfaceContainerLow),
  children: [
    _TableCell(
      YorksV1MaterialRequestStrings.requestNumber.active(language),
      header: true,
    ),
    _TableCell(YorksV1LogisticsStrings.project.active(language), header: true),
    _TableCell(YorksV1LogisticsStrings.scope.active(language), header: true),
    _TableCell(
      YorksV1MaterialRequestStrings.requestedBy.active(language),
      header: true,
    ),
    _TableCell(
      YorksV1MaterialRequestStrings.items.active(language),
      header: true,
    ),
    _TableCell(YorksV1LogisticsStrings.state.active(language), header: true),
    _TableCell(
      YorksV1MaterialRequestStrings.updated.active(language),
      header: true,
    ),
    const _TableCell('', header: true),
  ],
);

TableRow _dispatchDataRow(
  YorksV1MaterialRequest request,
  AppLanguage language,
  VoidCallback onOpen,
) => TableRow(
  children: [
    _TableCell(
      request.requestNumber ??
          YorksV1MaterialRequestStrings.draft.active(language),
      emphasis: true,
      color: AppColors.blue,
    ),
    _TableCell('${request.projectReference}\n${request.projectName}'),
    _TableCell(request.scopeName),
    _TableCell(
      request.requesterDisplayName ??
          YorksV1MaterialRequestStrings.notProvided.active(language),
    ),
    _TableCell('${request.displayItemCount}'),
    _TableCell(
      yorksV1MaterialRequestStateCopy(request.state).active(language),
      status: request,
      language: language,
    ),
    _TableCell(_dateLabel(request.updatedAt)),
    _TableAction(onOpen: onOpen, language: language),
  ],
);

class _TableCell extends StatelessWidget {
  const _TableCell(
    this.value, {
    this.header = false,
    this.emphasis = false,
    this.color,
    this.status,
    this.language = AppLanguage.english,
  });

  final String value;
  final bool header;
  final bool emphasis;
  final Color? color;
  final YorksV1MaterialRequest? status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: header ? 46 : 64),
    alignment: AlignmentDirectional.centerStart,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    child: status == null
        ? Text(
            value,
            maxLines: header ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: (header ? AppTypography.labelSmall : AppTypography.bodySmall)
                .copyWith(
                  color: color ?? (header ? AppColors.muted : AppColors.ink),
                  fontWeight: header || emphasis
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
          )
        : _DispatchStatePill(request: status!, language: language),
  );
}

class _TableAction extends StatelessWidget {
  const _TableAction({required this.onOpen, required this.language});

  final VoidCallback onOpen;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: IconButton(
      tooltip: YorksV1LogisticsStrings.openDispatchWorkflow.active(language),
      onPressed: onOpen,
      icon: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _DispatchRequestCard extends StatelessWidget {
  const _DispatchRequestCard({
    required this.request,
    required this.language,
    required this.onOpen,
  });

  final YorksV1MaterialRequest request;
  final AppLanguage language;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.blueContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.requestNumber ??
                        YorksV1MaterialRequestStrings.draft.active(language),
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    request.projectName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${request.projectReference} · ${request.scopeName} · ${request.displayItemCount} ${YorksV1MaterialRequestStrings.items.active(language).toLowerCase()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DispatchStatePill(request: request, language: language),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const SizedBox(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
              child: Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DispatchStatePill extends StatelessWidget {
  const _DispatchStatePill({required this.request, required this.language});

  final YorksV1MaterialRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _isCompleted(request)
        ? (AppColors.successContainer, AppColors.onSuccessContainer)
        : _needsReceiptReview(request)
        ? (AppColors.purpleContainer, AppColors.onTertiaryContainer)
        : (AppColors.warningContainer, AppColors.onWarningContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        yorksV1MaterialRequestStateCopy(request.state).active(language),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DispatchPagination extends StatelessWidget {
  const _DispatchPagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageSize;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = page * pageSize + 1;
    final end = (start + pageSize - 1).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$start-$end / $total',
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _DispatchEmpty extends StatelessWidget {
  const _DispatchEmpty({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xxxl),
    child: Column(
      children: [
        const Icon(
          Icons.local_shipping_outlined,
          color: AppColors.muted,
          size: 42,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          YorksV1LogisticsStrings.noDispatchMatches.active(language),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
