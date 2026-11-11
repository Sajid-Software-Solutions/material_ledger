import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../core/zoom/yorks_workspace_zoom.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_material_summary_strings.dart';
import '../../../../shared/models/yorks_v1_project_material_summary.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../../shared/providers/yorks_v1_logistics_provider.dart';
import '../../../../shared/providers/yorks_v1_material_summary_document_provider.dart';
import '../../../../shared/services/yorks_v1_material_summary_document_service.dart';

enum YorksV1MaterialMovementView { summary, register }

/// Project Material Movement tab: the Material Summary (default) and the
/// existing chronological movement register.
class YorksV1ProjectMaterialMovementWorkspace extends StatefulWidget {
  const YorksV1ProjectMaterialMovementWorkspace({
    super.key,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.language,
    required this.register,
    this.initialView = YorksV1MaterialMovementView.summary,
  });

  final String projectId;
  final String projectReference;
  final String projectName;
  final AppLanguage language;
  final Widget register;
  final YorksV1MaterialMovementView initialView;

  @override
  State<YorksV1ProjectMaterialMovementWorkspace> createState() =>
      _YorksV1ProjectMaterialMovementWorkspaceState();
}

class _YorksV1ProjectMaterialMovementWorkspaceState
    extends State<YorksV1ProjectMaterialMovementWorkspace> {
  late YorksV1MaterialMovementView _view = widget.initialView;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppSpacing.compactBreakpoint;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              YorksV1ProjectStrings.materialMovement.active(language),
              style: AppTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _view == YorksV1MaterialMovementView.summary
                  ? YorksV1MaterialSummaryStrings.description.active(language)
                  : YorksV1ProjectStrings.materialMovementDescription.active(
                      language,
                    ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        );
        final switcher = SizedBox(
          width: compact ? double.infinity : 280,
          child: YorksMobileSegmentedControl<YorksV1MaterialMovementView>(
            key: const ValueKey('material-movement-view-switch'),
            options: [
              YorksMobileSegmentOption(
                value: YorksV1MaterialMovementView.summary,
                label: YorksV1MaterialSummaryStrings.summary.active(language),
              ),
              YorksMobileSegmentOption(
                value: YorksV1MaterialMovementView.register,
                label: YorksV1MaterialSummaryStrings.register.active(language),
              ),
            ],
            selected: _view,
            onSelected: (view) => setState(() => _view = view),
          ),
        );
        return LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.all(
                  compact ? AppSpacing.md : AppSpacing.lg,
                ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: AppSpacing.md),
                          switcher,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: AppSpacing.lg),
                          switcher,
                        ],
                      ),
              ),
              const Divider(height: 1),
              if (_view == YorksV1MaterialMovementView.summary)
                YorksV1ProjectMaterialSummaryView(
                  projectId: widget.projectId,
                  projectReference: widget.projectReference,
                  projectName: widget.projectName,
                  language: language,
                  compact: compact,
                )
              else
                widget.register,
            ],
          ),
        );
      },
    );
  }
}

enum _PeriodPreset {
  allTime,
  thisWeek,
  thisMonth,
  lastThreeMonths,
  thisYear,
  custom,
}

class YorksV1ProjectMaterialSummaryView extends ConsumerStatefulWidget {
  const YorksV1ProjectMaterialSummaryView({
    super.key,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.language,
    required this.compact,
  });

  final String projectId;
  final String projectReference;
  final String projectName;
  final AppLanguage language;
  final bool compact;

  @override
  ConsumerState<YorksV1ProjectMaterialSummaryView> createState() =>
      _YorksV1ProjectMaterialSummaryViewState();
}

class _YorksV1ProjectMaterialSummaryViewState
    extends ConsumerState<YorksV1ProjectMaterialSummaryView> {
  static const _pageSize = 50;
  static const _initialMonths = 6;
  static const _initialWeeks = 8;

  late YorksV1MaterialSummaryQuery _query = YorksV1MaterialSummaryQuery(
    projectId: widget.projectId,
  );
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  _PeriodPreset _preset = _PeriodPreset.allTime;
  YorksV1ProjectMaterialSummary? _lastSummary;
  int _overallLimit = _pageSize;
  int _monthLimit = _initialMonths;
  int _weekLimit = _initialWeeks;
  final Set<String> _expandedMonths = {};
  final Set<String> _expandedWeeks = {};
  bool _expansionSeeded = false;
  bool _busy = false;

  AppLanguage get _language => widget.language;

  @override
  void didUpdateWidget(covariant YorksV1ProjectMaterialSummaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _query = YorksV1MaterialSummaryQuery(projectId: widget.projectId);
      _searchController.clear();
      _preset = _PeriodPreset.allTime;
      _lastSummary = null;
      _resetPaging();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetPaging() {
    _overallLimit = _pageSize;
    _monthLimit = _initialMonths;
    _weekLimit = _initialWeeks;
    _expandedMonths.clear();
    _expandedWeeks.clear();
    _expansionSeeded = false;
  }

  void _setQuery(YorksV1MaterialSummaryQuery query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _resetPaging();
    });
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _setQuery(
        YorksV1MaterialSummaryQuery(
          projectId: _query.projectId,
          from: _query.from,
          to: _query.to,
          scopeId: _query.scopeId,
          search: value,
        ),
      );
    });
  }

  Future<void> _selectPreset(_PeriodPreset preset) async {
    final today = yorksV1GulfToday();
    DateTime? from;
    DateTime? to;
    switch (preset) {
      case _PeriodPreset.allTime:
        break;
      case _PeriodPreset.thisWeek:
        from = yorksV1MaterialSummaryWeekStart(today);
        to = today;
      case _PeriodPreset.thisMonth:
        from = DateTime.utc(today.year, today.month);
        to = today;
      case _PeriodPreset.lastThreeMonths:
        from = DateTime.utc(today.year, today.month - 2);
        to = today;
      case _PeriodPreset.thisYear:
        from = DateTime.utc(today.year);
        to = today;
      case _PeriodPreset.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(today.year + 1, 12, 31),
          initialDateRange: _query.from != null && _query.to != null
              ? DateTimeRange(
                  start: DateTime(
                    _query.from!.year,
                    _query.from!.month,
                    _query.from!.day,
                  ),
                  end: DateTime(
                    _query.to!.year,
                    _query.to!.month,
                    _query.to!.day,
                  ),
                )
              : null,
          helpText: YorksV1MaterialSummaryStrings.customRange.active(_language),
        );
        if (picked == null || !mounted) return;
        from = DateTime.utc(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        to = DateTime.utc(picked.end.year, picked.end.month, picked.end.day);
    }
    setState(() => _preset = preset);
    _setQuery(
      YorksV1MaterialSummaryQuery(
        projectId: _query.projectId,
        from: from,
        to: to,
        scopeId: _query.scopeId,
        search: _query.search,
      ),
    );
  }

  void _selectScope(String? scopeId) => _setQuery(
    YorksV1MaterialSummaryQuery(
      projectId: _query.projectId,
      from: _query.from,
      to: _query.to,
      scopeId: scopeId,
      search: _query.search,
    ),
  );

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _preset = _PeriodPreset.allTime);
    _setQuery(YorksV1MaterialSummaryQuery(projectId: _query.projectId));
  }

  String _presetLabel(_PeriodPreset preset) => (switch (preset) {
    _PeriodPreset.allTime => YorksV1MaterialSummaryStrings.allTime,
    _PeriodPreset.thisWeek => YorksV1MaterialSummaryStrings.thisWeek,
    _PeriodPreset.thisMonth => YorksV1MaterialSummaryStrings.thisMonth,
    _PeriodPreset.lastThreeMonths =>
      YorksV1MaterialSummaryStrings.lastThreeMonths,
    _PeriodPreset.thisYear => YorksV1MaterialSummaryStrings.thisYear,
    _PeriodPreset.custom => YorksV1MaterialSummaryStrings.customRange,
  }).active(_language);

  String _periodDescription({bool english = false}) {
    final preset = _preset == _PeriodPreset.allTime
        ? YorksV1MaterialSummaryStrings.allTime
        : null;
    if (preset != null) {
      return english ? preset.primary : preset.active(_language);
    }
    final from = _query.from;
    final to = _query.to;
    final range = [
      if (from != null) yorksV1MaterialSummaryDate(from),
      if (to != null) yorksV1MaterialSummaryDate(to),
    ].join(' – ');
    return range;
  }

  String _buildingDescription(
    YorksV1ProjectMaterialSummary? summary, {
    bool english = false,
  }) {
    final name = summary?.scopeName(_query.scopeId);
    if (name != null) return name;
    return english
        ? YorksV1MaterialSummaryStrings.allBuildings.primary
        : YorksV1MaterialSummaryStrings.allBuildings.active(_language);
  }

  YorksV1MaterialSummaryExportContext _exportContext(
    YorksV1ProjectMaterialSummary summary,
  ) => YorksV1MaterialSummaryExportContext(
    projectReference: widget.projectReference,
    projectName: widget.projectName,
    buildingLabel: _buildingDescription(summary, english: true),
    periodLabel: _periodDescription(english: true),
    search: _query.normalizedSearch,
    generatedAt: summary.generatedAt,
  );

  Future<void> _runExport(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await action();
      if (saved && mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialSummaryStrings.exportSaved.active(_language),
          tone: YorksAppToastTone.success,
        );
      }
    } catch (_) {
      if (mounted) {
        YorksAppToast.show(
          context,
          title: YorksV1MaterialSummaryStrings.exportFailed.active(_language),
          tone: YorksAppToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportExcel(YorksV1ProjectMaterialSummary summary) =>
      _runExport(() async {
        final service = ref.read(yorksV1MaterialSummaryDocumentServiceProvider);
        final exportContext = _exportContext(summary);
        final bytes = service.buildExcel(summary, exportContext);
        return ref
            .read(yorksV1BoqWorkbookFileServiceProvider)
            .saveWorkbook(
              bytes: bytes,
              suggestedName: service.suggestedFileName(exportContext, 'xlsx'),
            );
      });

  Future<void> _exportPdf(YorksV1ProjectMaterialSummary summary) =>
      _runExport(() async {
        final service = ref.read(yorksV1MaterialSummaryDocumentServiceProvider);
        final exportContext = _exportContext(summary);
        final bytes = await service.buildPdf(summary, exportContext);
        await Printing.sharePdf(
          bytes: bytes,
          filename: service.suggestedFileName(exportContext, 'pdf'),
        );
        return false;
      });

  Future<void> _viewPdf(YorksV1ProjectMaterialSummary summary) {
    final service = ref.read(yorksV1MaterialSummaryDocumentServiceProvider);
    final exportContext = _exportContext(summary);
    return showDialog<void>(
      context: context,
      builder: (context) => _MaterialSummaryPdfDialog(
        language: _language,
        fileName: service.suggestedFileName(exportContext, 'pdf'),
        bytes: service.buildPdf(summary, exportContext),
      ),
    );
  }

  void _openRequest(YorksV1MaterialSummaryRequest request) =>
      context.push(RoutePaths.yorksV1MaterialRequestPath(request.id));

  void _seedExpansion(YorksV1ProjectMaterialSummary summary) {
    if (_expansionSeeded) return;
    _expansionSeeded = true;
    if (summary.months.isNotEmpty) {
      _expandedMonths.add(_periodKey(summary.months.first));
    }
    if (summary.weeks.isNotEmpty) {
      _expandedWeeks.add(_periodKey(summary.weeks.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(yorksV1ProjectMaterialSummaryProvider(_query));
    final current = async.valueOrNull;
    if (current != null) _lastSummary = current;
    final summary = current ?? _lastSummary;
    final refreshing = async.isLoading && summary != null;
    final padding = EdgeInsets.all(
      widget.compact ? AppSpacing.md : AppSpacing.lg,
    );

    if (summary != null) _seedExpansion(summary);

    final content = <Widget>[
      _filters(summary),
      SizedBox(
        height: 3,
        child: refreshing
            ? LinearProgressIndicator(
                minHeight: 3,
                semanticsLabel: YorksV1MaterialSummaryStrings.updating.active(
                  _language,
                ),
              )
            : null,
      ),
      const SizedBox(height: AppSpacing.md),
    ];

    if (summary == null) {
      content.add(
        async.hasError
            ? _errorState(async.error)
            : const Padding(
                padding: EdgeInsets.all(AppSpacing.xxxl),
                child: Center(child: CircularProgressIndicator()),
              ),
      );
    } else if (async.hasError && current == null && !async.isLoading) {
      content.add(_errorState(async.error));
    } else if (summary.isEmpty) {
      content.add(_emptyState());
    } else {
      content.addAll([
        _metrics(summary),
        const SizedBox(height: AppSpacing.xl),
        _overallSection(summary),
        const SizedBox(height: AppSpacing.xl),
        _periodSection(
          summary,
          title: YorksV1MaterialSummaryStrings.monthly,
          periods: summary.months,
          limit: _monthLimit,
          expanded: _expandedMonths,
          onShowMore: () => setState(() => _monthLimit += _initialMonths),
          keyPrefix: 'month',
        ),
        const SizedBox(height: AppSpacing.xl),
        _periodSection(
          summary,
          title: YorksV1MaterialSummaryStrings.weekly,
          periods: summary.weeks,
          limit: _weekLimit,
          expanded: _expandedWeeks,
          onShowMore: () => setState(() => _weekLimit += _initialWeeks),
          keyPrefix: 'week',
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${YorksV1MaterialSummaryStrings.dateBasis.active(_language)} '
          '${YorksV1MaterialSummaryStrings.percentagesNote.active(_language)}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ]);
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      ),
    );
  }

  // ─── Filters and actions ───────────────────────────────────────────────

  Widget _filters(YorksV1ProjectMaterialSummary? summary) {
    final search = TextField(
      key: const ValueKey('material-summary-search'),
      controller: _searchController,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      maxLength: YorksV1MaterialSummaryQuery.maxSearchLength,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        hintText: YorksV1MaterialSummaryStrings.searchHint.active(_language),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: YorksV1MaterialSummaryStrings.clearFilters.active(
                  _language,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              ),
      ),
    );
    final scopes = summary?.scopes ?? const <YorksV1MaterialSummaryScope>[];
    final building = _FilterDropdown<String?>(
      key: const ValueKey('material-summary-building'),
      icon: Icons.apartment_rounded,
      label: YorksV1MaterialSummaryStrings.building.active(_language),
      value: scopes.any((scope) => scope.id == _query.scopeId)
          ? _query.scopeId
          : null,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            YorksV1MaterialSummaryStrings.allBuildings.active(_language),
          ),
        ),
        for (final scope in scopes)
          DropdownMenuItem<String?>(
            value: scope.id,
            child: Text(scope.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _selectScope,
    );
    final period = _FilterDropdown<_PeriodPreset>(
      key: const ValueKey('material-summary-period'),
      icon: Icons.calendar_month_rounded,
      label: YorksV1MaterialSummaryStrings.period.active(_language),
      value: _preset,
      items: [
        for (final preset in _PeriodPreset.values)
          DropdownMenuItem(
            value: preset,
            child: Text(
              preset == _preset &&
                      preset != _PeriodPreset.allTime &&
                      _query.from != null
                  ? '${_presetLabel(preset)} · ${_periodDescription()}'
                  : _presetLabel(preset),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (preset) {
        if (preset != null) _selectPreset(preset);
      },
      // Re-selecting "Custom range" reopens the date picker.
      onTapSame: _preset == _PeriodPreset.custom
          ? () => _selectPreset(_PeriodPreset.custom)
          : null,
    );
    final ready = summary != null && !summary.isEmpty && !_busy
        ? summary
        : null;
    final actions = [
      _ActionButton(
        key: const ValueKey('material-summary-export-excel'),
        icon: YorksDataTransferIcons.exportData,
        label: YorksV1MaterialSummaryStrings.exportExcel.active(_language),
        onPressed: ready == null ? null : () => _exportExcel(ready),
      ),
      _ActionButton(
        key: const ValueKey('material-summary-export-pdf'),
        icon: Icons.picture_as_pdf_outlined,
        label: YorksV1MaterialSummaryStrings.exportPdf.active(_language),
        onPressed: ready == null ? null : () => _exportPdf(ready),
      ),
      _ActionButton(
        key: const ValueKey('material-summary-view-pdf'),
        icon: Icons.visibility_outlined,
        label: YorksV1MaterialSummaryStrings.viewPdf.active(_language),
        primary: true,
        onPressed: ready == null ? null : () => _viewPdf(ready),
      ),
    ];
    final clear = _query.hasFilters || _preset != _PeriodPreset.allTime
        ? TextButton.icon(
            key: const ValueKey('material-summary-clear-filters'),
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: Text(
              YorksV1MaterialSummaryStrings.clearFilters.active(_language),
            ),
          )
        : null;

    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: AppSpacing.md),
          building,
          const SizedBox(height: AppSpacing.md),
          period,
          if (clear != null)
            Align(alignment: AlignmentDirectional.centerStart, child: clear),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: actions[0]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: actions[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          actions[2],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 340, child: search),
            SizedBox(width: 220, child: building),
            SizedBox(width: 260, child: period),
            ?clear,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                YorksV1MaterialSummaryStrings.exportsUseFilters.active(
                  _language,
                ),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ),
            Wrap(spacing: AppSpacing.sm, children: actions),
          ],
        ),
      ],
    );
  }

  // ─── States ───────────────────────────────────────────────────────────

  Widget _errorState(Object? error) {
    final denied =
        error is YorksV1DomainException &&
        (error.code == YorksV1DomainErrorCode.unauthorized ||
            error.code == YorksV1DomainErrorCode.unauthenticated);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(
            denied ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
            color: AppColors.muted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            (denied
                    ? YorksV1MaterialSummaryStrings.accessDenied
                    : YorksV1MaterialSummaryStrings.unavailable)
                .active(_language),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
          if (!denied) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('material-summary-retry'),
              onPressed: () =>
                  ref.invalidate(yorksV1ProjectMaterialSummaryProvider(_query)),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                YorksV1MaterialSummaryStrings.tryAgain.active(_language),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final filtered = _query.hasFilters;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.muted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            (filtered
                    ? YorksV1MaterialSummaryStrings.emptyFiltered
                    : YorksV1MaterialSummaryStrings.emptyProject)
                .active(_language),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
          ),
          if (filtered) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _clearFilters,
              child: Text(
                YorksV1MaterialSummaryStrings.clearFilters.active(_language),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Metrics ──────────────────────────────────────────────────────────

  Widget _metrics(YorksV1ProjectMaterialSummary summary) {
    final tiles = [
      _MetricTile(
        icon: Icons.category_outlined,
        label: YorksV1MaterialSummaryStrings.materials.active(_language),
        value: '${summary.items.length}',
      ),
      _MetricTile(
        icon: Icons.receipt_long_outlined,
        label: YorksV1MaterialSummaryStrings.materialRequests.active(_language),
        value: '${summary.requests.length}',
      ),
      _MetricTile(
        icon: Icons.task_alt_rounded,
        label: YorksV1MaterialSummaryStrings.fullySent.active(_language),
        value: '${summary.fullySentCount}',
        tone: AppColors.success,
        tint: AppColors.successContainer,
      ),
      _MetricTile(
        icon: Icons.local_shipping_outlined,
        label: YorksV1MaterialSummaryStrings.awaitingDispatch.active(_language),
        value: '${summary.awaitingDispatchCount}',
        tone: AppColors.warning,
        tint: AppColors.warningContainer,
      ),
    ];
    if (widget.compact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[3]),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        for (var index = 0; index < tiles.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: tiles[index]),
        ],
      ],
    );
  }

  // ─── Overall ──────────────────────────────────────────────────────────

  Widget _overallSection(YorksV1ProjectMaterialSummary summary) {
    final visible = summary.items.take(_overallLimit).toList();
    return Column(
      key: const ValueKey('material-summary-overall'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: YorksV1MaterialSummaryStrings.overall.active(_language),
          trailing:
              '${summary.items.length} ${YorksV1MaterialSummaryStrings.materials.active(_language)}',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.compact) ...[
          for (final item in visible) ...[
            _ItemCard(
              summary: summary,
              item: item,
              quantities: item,
              requestRefs: item.requestRefs,
              language: _language,
              onOpenRequest: _openRequest,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ] else
          _ItemTable(
            summary: summary,
            language: _language,
            onOpenRequest: _openRequest,
            showShare: false,
            rows: [
              for (final item in visible)
                _TableRowData(
                  item: item,
                  quantities: item,
                  requestRefs: item.requestRefs,
                ),
            ],
          ),
        if (summary.items.length > visible.length)
          _ShowMoreButton(
            label:
                '${YorksV1MaterialSummaryStrings.showMore.active(_language)} '
                '(${summary.items.length - visible.length})',
            onPressed: () => setState(() => _overallLimit += _pageSize),
          ),
      ],
    );
  }

  // ─── Monthly / weekly ─────────────────────────────────────────────────

  Widget _periodSection(
    YorksV1ProjectMaterialSummary summary, {
    required TranslatableString title,
    required List<YorksV1MaterialSummaryPeriod> periods,
    required int limit,
    required Set<String> expanded,
    required VoidCallback onShowMore,
    required String keyPrefix,
  }) {
    final visible = periods.take(limit).toList();
    return Column(
      key: ValueKey('material-summary-$keyPrefix-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: title.active(_language),
          trailing: '${periods.length}',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final period in visible) ...[
          _PeriodCard(
            key: ValueKey('material-summary-$keyPrefix-${_periodKey(period)}'),
            summary: summary,
            period: period,
            language: _language,
            compact: widget.compact,
            expanded: expanded.contains(_periodKey(period)),
            onToggle: () => setState(() {
              final key = _periodKey(period);
              if (!expanded.remove(key)) expanded.add(key);
            }),
            onOpenRequest: _openRequest,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (periods.length > visible.length)
          _ShowMoreButton(
            label: YorksV1MaterialSummaryStrings.showMorePeriods.active(
              _language,
            ),
            onPressed: onShowMore,
          ),
      ],
    );
  }
}

String _periodKey(YorksV1MaterialSummaryPeriod period) =>
    yorksV1MaterialSummaryDateKey(period.start);

// ─── Building blocks ─────────────────────────────────────────────────────

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.onTapSame,
  });

  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final VoidCallback? onTapSame;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
        items: items,
        onChanged: (next) {
          if (next == value) {
            onTapSame?.call();
            return;
          }
          onChanged(next);
        },
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.xs + 2),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    const minimum = Size(0, AppSpacing.minTapTarget);
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(minimumSize: minimum),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: minimum),
            child: child,
          );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = AppColors.blue,
    this.tint = AppColors.blueContainer,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: SizedBox.square(
            dimension: 34,
            child: Icon(icon, size: 18, color: tone),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
      ),
      if (trailing != null) ...[
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Text(
            trailing!,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ],
  );
}

class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more_rounded),
        label: Text(label),
      ),
    ),
  );
}

/// Sent-of-requested progress. Values above 100% are clamped visually but
/// the label shows the true percentage.
class _FulfilmentBar extends StatelessWidget {
  const _FulfilmentBar({required this.ratio});

  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final value = ratio;
    final complete = value != null && value >= 1;
    final tone = complete ? AppColors.success : AppColors.blue;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              value: value == null ? 0 : value.clamp(0, 1).toDouble(),
              minHeight: 6,
              color: tone,
              backgroundColor: AppColors.surfaceContainerHigh,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 40,
          child: Text(
            yorksV1MaterialSummaryPercent(value),
            textAlign: TextAlign.end,
            style: AppTypography.labelMedium.copyWith(
              color: complete ? AppColors.success : AppColors.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestLinks extends StatefulWidget {
  const _RequestLinks({
    required this.requests,
    required this.language,
    required this.onOpenRequest,
  });

  final List<YorksV1MaterialSummaryRequest> requests;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialSummaryRequest> onOpenRequest;

  @override
  State<_RequestLinks> createState() => _RequestLinksState();
}

class _RequestLinksState extends State<_RequestLinks> {
  static const _collapsedCount = 3;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    final visible = _showAll ? requests : requests.take(_collapsedCount);
    final hidden = requests.length - _collapsedCount;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final request in visible)
          Tooltip(
            message:
                '${YorksV1MaterialSummaryStrings.openRequest.active(widget.language)} · '
                '${yorksV1MaterialSummaryDate(request.requestedOn)}',
            child: InkWell(
              key: ValueKey('material-summary-request-${request.id}'),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: () => widget.onOpenRequest(request),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  request.number,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.blue,
                  ),
                ),
              ),
            ),
          ),
        if (!_showAll && hidden > 0)
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () => setState(() => _showAll = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '+$hidden',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.inkSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableRowData {
  const _TableRowData({
    required this.item,
    required this.quantities,
    required this.requestRefs,
    this.share,
  });

  final YorksV1MaterialSummaryItem item;
  final YorksV1MaterialSummaryQuantities quantities;
  final List<int> requestRefs;
  final double? share;
}

/// Desktop table. Rows are plain widgets so the page scroll owns scrolling;
/// callers cap the row count with "Show more".
class _ItemTable extends StatelessWidget {
  const _ItemTable({
    required this.summary,
    required this.rows,
    required this.language,
    required this.onOpenRequest,
    required this.showShare,
  });

  final YorksV1ProjectMaterialSummary summary;
  final List<_TableRowData> rows;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialSummaryRequest> onOpenRequest;
  final bool showShare;

  static const _material = 34;
  static const _unit = 7;
  static const _quantity = 9;
  static const _share = 10;
  static const _fulfilment = 14;
  static const _requests = 22;

  @override
  Widget build(BuildContext context) {
    final headerStyle = AppTypography.labelMedium.copyWith(
      color: AppColors.inkSecondary,
      fontWeight: FontWeight.w800,
    );
    Widget header(String text, int flex, {bool end = false}) => Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: headerStyle,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                header(
                  YorksV1MaterialSummaryStrings.material.active(language),
                  _material,
                ),
                header(
                  YorksV1MaterialSummaryStrings.unit.active(language),
                  _unit,
                ),
                header(
                  YorksV1MaterialSummaryStrings.requested.active(language),
                  _quantity,
                  end: true,
                ),
                header(
                  YorksV1MaterialSummaryStrings.sent.active(language),
                  _quantity,
                  end: true,
                ),
                header(
                  YorksV1MaterialSummaryStrings.returned.active(language),
                  _quantity,
                  end: true,
                ),
                if (showShare)
                  header(
                    YorksV1MaterialSummaryStrings.shareOfItem.active(language),
                    _share,
                    end: true,
                  ),
                const SizedBox(width: AppSpacing.lg),
                header(
                  YorksV1MaterialSummaryStrings.sentOfRequested.active(
                    language,
                  ),
                  _fulfilment,
                ),
                const SizedBox(width: AppSpacing.lg),
                header(
                  YorksV1MaterialSummaryStrings.materialRequests.active(
                    language,
                  ),
                  _requests,
                ),
              ],
            ),
          ),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _row(rows[index]),
          ],
        ],
      ),
    );
  }

  Widget _row(_TableRowData row) {
    final item = row.item;
    final numberStyle = AppTypography.bodyMedium.copyWith(
      fontWeight: FontWeight.w700,
    );
    Widget number(String value, int flex, {Color? color}) => Expanded(
      flex: flex,
      child: Text(
        yorksV1MaterialSummaryQuantity(value),
        textAlign: TextAlign.end,
        style: color == null ? numberStyle : numberStyle.copyWith(color: color),
      ),
    );
    final subtitle = [
      if (item.itemCodes.isNotEmpty) item.itemCodes.join(', '),
      if (item.brandOrigins.isNotEmpty) item.brandOrigins.join(', '),
    ].join('  ·  ');
    return Padding(
      key: ValueKey('material-summary-row-${item.index}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: _material,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: _unit,
            child: Text(item.unit, style: AppTypography.bodyMedium),
          ),
          number(row.quantities.requested, _quantity),
          number(row.quantities.sent, _quantity, color: AppColors.blue),
          number(
            row.quantities.returned,
            _quantity,
            color: row.quantities.returnedValue > 0 ? AppColors.success : null,
          ),
          if (showShare)
            Expanded(
              flex: _share,
              child: Text(
                yorksV1MaterialSummaryPercent(row.share),
                textAlign: TextAlign.end,
                style: numberStyle,
              ),
            ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: _fulfilment,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _FulfilmentBar(ratio: row.quantities.sentOfRequested),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: _requests,
            child: _RequestLinks(
              requests: summary.requestsFor(row.requestRefs),
              language: language,
              onOpenRequest: onOpenRequest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile card for one material.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.summary,
    required this.item,
    required this.quantities,
    required this.requestRefs,
    required this.language,
    required this.onOpenRequest,
    this.share,
  });

  final YorksV1ProjectMaterialSummary summary;
  final YorksV1MaterialSummaryItem item;
  final YorksV1MaterialSummaryQuantities quantities;
  final List<int> requestRefs;
  final AppLanguage language;
  final ValueChanged<YorksV1MaterialSummaryRequest> onOpenRequest;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      item.unit,
      if (item.itemCodes.isNotEmpty) item.itemCodes.join(', '),
      if (item.brandOrigins.isNotEmpty) item.brandOrigins.join(', '),
    ].join('  ·  ');
    Widget figure(String label, String value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
          ),
          Text(
            yorksV1MaterialSummaryQuantity(value),
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
    return Container(
      key: ValueKey('material-summary-card-${item.index}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.description,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              figure(
                YorksV1MaterialSummaryStrings.requested.active(language),
                quantities.requested,
              ),
              figure(
                YorksV1MaterialSummaryStrings.sent.active(language),
                quantities.sent,
                color: AppColors.blue,
              ),
              figure(
                YorksV1MaterialSummaryStrings.returned.active(language),
                quantities.returned,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _FulfilmentBar(ratio: quantities.sentOfRequested),
          if (share != null) ...[
            const SizedBox(height: 4),
            Text(
              '${YorksV1MaterialSummaryStrings.shareOfItem.active(language)}: '
              '${yorksV1MaterialSummaryPercent(share)}',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _RequestLinks(
            requests: summary.requestsFor(requestRefs),
            language: language,
            onOpenRequest: onOpenRequest,
          ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatefulWidget {
  const _PeriodCard({
    super.key,
    required this.summary,
    required this.period,
    required this.language,
    required this.compact,
    required this.expanded,
    required this.onToggle,
    required this.onOpenRequest,
  });

  final YorksV1ProjectMaterialSummary summary;
  final YorksV1MaterialSummaryPeriod period;
  final AppLanguage language;
  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<YorksV1MaterialSummaryRequest> onOpenRequest;

  @override
  State<_PeriodCard> createState() => _PeriodCardState();
}

class _PeriodCardState extends State<_PeriodCard> {
  static const _pageSize = 50;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final summary = widget.summary;
    final language = widget.language;
    final requestCount = period.requestRefs.length;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lines = period.lines.take(_limit).toList();
    final header = InkWell(
      onTap: widget.onToggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      yorksV1MaterialSummaryPeriodLabel(period),
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${period.lines.length} ${YorksV1MaterialSummaryStrings.materials.active(language)}'
                      '  ·  $requestCount ${YorksV1MaterialSummaryStrings.materialRequests.active(language)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: widget.expanded ? .5 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                child: const Icon(
                  Icons.expand_more_rounded,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget body = const SizedBox(width: double.infinity);
    if (widget.expanded) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(
          widget.compact ? AppSpacing.sm : AppSpacing.md,
          0,
          widget.compact ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.compact) ...[
              for (final line in lines)
                if (summary.item(line.itemIndex) case final item?) ...[
                  _ItemCard(
                    summary: summary,
                    item: item,
                    quantities: line,
                    requestRefs: line.requestRefs,
                    share: summary.shareOfItem(line),
                    language: language,
                    onOpenRequest: widget.onOpenRequest,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ] else
              _ItemTable(
                summary: summary,
                language: language,
                onOpenRequest: widget.onOpenRequest,
                showShare: true,
                rows: [
                  for (final line in lines)
                    if (summary.item(line.itemIndex) case final item?)
                      _TableRowData(
                        item: item,
                        quantities: line,
                        requestRefs: line.requestRefs,
                        share: summary.shareOfItem(line),
                      ),
                ],
              ),
            if (period.lines.length > lines.length)
              _ShowMoreButton(
                label:
                    '${YorksV1MaterialSummaryStrings.showMore.active(language)} '
                    '(${period.lines.length - lines.length})',
                onPressed: () => setState(() => _limit += _pageSize),
              ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(
          color: widget.expanded
              ? AppColors.blueContainerStrong
              : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(button: true, expanded: widget.expanded, child: header),
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: body,
          ),
        ],
      ),
    );
  }
}

/// In-app preview of the exact PDF bytes that Export PDF produces.
class _MaterialSummaryPdfDialog extends StatelessWidget {
  const _MaterialSummaryPdfDialog({
    required this.language,
    required this.fileName,
    required this.bytes,
  });

  final AppLanguage language;
  final String fileName;
  final Future<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < AppSpacing.compactBreakpoint;
    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              YorksV1MaterialSummaryStrings.title.active(language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('material-summary-pdf-print'),
            tooltip: YorksV1MaterialSummaryStrings.print.active(language),
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              final data = await bytes;
              await Printing.layoutPdf(
                onLayout: (_) async => data,
                name: fileName,
              );
            },
          ),
          IconButton(
            key: const ValueKey('material-summary-pdf-share'),
            tooltip: YorksV1MaterialSummaryStrings.exportPdf.active(language),
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              final data = await bytes;
              await Printing.sharePdf(bytes: data, filename: fileName);
            },
          ),
          IconButton(
            key: const ValueKey('material-summary-pdf-close'),
            tooltip: YorksV1MaterialSummaryStrings.close.active(language),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    final preview = YorksWorkspaceZoomExclusion(
      child: PdfPreview(
        build: (_) => bytes,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        initialPageFormat: PdfPageFormat.a4.landscape,
        useActions: false,
        pdfFileName: fileName,
        loadingWidget: const Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(value: .38, strokeWidth: 2.5),
          ),
        ),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: AppColors.surfaceContainerLow,
            child: preview,
          ),
        ),
      ],
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: content));
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 1100, height: size.height * .88, child: content),
    );
  }
}
