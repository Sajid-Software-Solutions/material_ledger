import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/zoom/yorks_workspace_zoom.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_workforce_strings.dart';
import '../../application/workforce_monthly_period_controller.dart';
import '../../application/workforce_providers.dart';
import '../../application/workforce_report_controller.dart';
import '../../application/workforce_review_controller.dart';
import '../../data/workforce_report_service.dart';
import '../../domain/workforce_report_models.dart';
import '../../domain/workforce_review_models.dart';

final class YorksWorkforceReportsPanel extends ConsumerStatefulWidget {
  const YorksWorkforceReportsPanel({
    required this.language,
    required this.monthlyState,
    required this.reviewState,
    required this.compact,
    super.key,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState monthlyState;
  final YorksWorkforceReviewState reviewState;
  final bool compact;

  @override
  ConsumerState<YorksWorkforceReportsPanel> createState() =>
      _YorksWorkforceReportsPanelState();
}

final class _YorksWorkforceReportsPanelState
    extends ConsumerState<YorksWorkforceReportsPanel> {
  YorksWorkforceReportKind _kind =
      YorksWorkforceReportKind.supervisorTeamMonthly;
  final ScrollController _horizontalController = ScrollController();
  late String _workDate;
  String? _selectedSnapshotId;
  bool _historyScheduled = false;

  String _t(String key) => YorksV1WorkforceStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _workDate =
        widget.monthlyState.selectedDate ?? widget.monthlyState.periodMonth;
  }

  @override
  void didUpdateWidget(covariant YorksWorkforceReportsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.monthlyState.selectedDate !=
            widget.monthlyState.selectedDate &&
        widget.monthlyState.selectedDate != null) {
      _workDate = widget.monthlyState.selectedDate!;
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(yorksWorkforceReportControllerProvider);
    final controller = ref.read(
      yorksWorkforceReportControllerProvider.notifier,
    );
    _scheduleHistory(state, controller);
    final request = _request();
    final reason = _disabledReason(request);

    return Material(
      key: const Key('workforce-reports-panel'),
      color: AppColors.surfaceContainerLowest,
      elevation: 1,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          widget.compact ? AppSpacing.lg : AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: AppSpacing.lg),
            _statusBanner(context, state),
            const SizedBox(height: AppSpacing.lg),
            _controls(context, state, request, reason, controller),
            if (reason != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                reason,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
            if (state.artifact != null) ...[
              const SizedBox(height: AppSpacing.xl),
              _artifact(context, state, controller),
            ],
            const SizedBox(height: AppSpacing.xl),
            _history(context, state, controller),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const Icon(Icons.assessment_outlined, color: AppColors.primary),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('reports_title'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _t('reports_body'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _controls(
    BuildContext context,
    YorksWorkforceReportState state,
    YorksWorkforceReportRequest? request,
    String? reason,
    YorksWorkforceReportController controller,
  ) {
    final children = <Widget>[
      SizedBox(
        width: 330,
        child: DropdownButtonFormField<YorksWorkforceReportKind>(
          key: const Key('workforce-report-type'),
          initialValue: _kind,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _t('reports_type'),
            prefixIcon: const Icon(Icons.description_outlined),
          ),
          items: YorksWorkforceReportKind.values
              .map(
                (kind) => DropdownMenuItem(
                  value: kind,
                  child: Text(
                    _t('report_${kind.wire}'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: state.isBusy
              ? null
              : (value) {
                  if (value != null) setState(() => _kind = value);
                },
        ),
      ),
      if (_kind == YorksWorkforceReportKind.dailyAttendanceRegister)
        SizedBox(
          width: 210,
          child: OutlinedButton.icon(
            key: const Key('workforce-report-date'),
            onPressed: state.isBusy ? null : () => _pickDate(context),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              MaterialLocalizations.of(
                context,
              ).formatMediumDate(DateTime.parse(_workDate)),
            ),
          ),
        ),
      if (_kind.requiresApprovedSnapshot && _availableSnapshots.isNotEmpty)
        SizedBox(
          width: widget.compact ? double.infinity : 280,
          child: DropdownButtonFormField<String>(
            key: ValueKey('workforce-report-snapshot-$_effectiveSnapshotId'),
            initialValue: _effectiveSnapshotId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('reports_snapshot'),
              prefixIcon: const Icon(Icons.verified_outlined),
            ),
            items: _availableSnapshots
                .map(
                  (snapshot) => DropdownMenuItem(
                    value: snapshot.id,
                    child: Text(
                      'R${snapshot.revisionNumber} · '
                      '${snapshot.hash.substring(0, 12)}…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: state.isBusy
                ? null
                : (value) => setState(() => _selectedSnapshotId = value),
          ),
        ),
      FilledButton.icon(
        key: const Key('workforce-report-generate'),
        onPressed: state.isBusy || request == null || reason != null
            ? null
            : () => controller.generate(request),
        icon: state.status == YorksWorkforceReportStatus.generating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : const Icon(Icons.auto_awesome_outlined),
        label: Text(
          state.status == YorksWorkforceReportStatus.generating
              ? _t('reports_generating')
              : _t('reports_generate'),
        ),
      ),
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _artifact(
    BuildContext context,
    YorksWorkforceReportState state,
    YorksWorkforceReportController controller,
  ) {
    final artifact = state.artifact!;
    final prepared = state.excelBytes != null && state.pdfBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('report_${artifact.kind.wire}'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            _sourcePill(context, artifact),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${artifact.totals.rowCount} ${_t('reports_rows')} · '
          '${artifact.generatedBy} · ${artifact.sourceHash.substring(0, 12)}…',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        _previewTable(context, artifact),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: prepared
                  ? () => _previewPdf(context, state, controller)
                  : null,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_t('reports_preview')),
            ),
            OutlinedButton.icon(
              onPressed: prepared ? controller.saveExcel : null,
              icon: const Icon(Icons.table_view_outlined),
              label: Text(_t('reports_download_excel')),
            ),
            OutlinedButton.icon(
              onPressed: prepared ? controller.savePdf : null,
              icon: const Icon(Icons.download_outlined),
              label: Text(_t('reports_download_pdf')),
            ),
            OutlinedButton.icon(
              onPressed: prepared ? controller.printPdf : null,
              icon: const Icon(Icons.print_outlined),
              label: Text(_t('reports_print')),
            ),
            OutlinedButton.icon(
              onPressed: prepared ? controller.sharePdf : null,
              icon: const Icon(Icons.ios_share_outlined),
              label: Text(_t('reports_share')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _previewTable(
    BuildContext context,
    YorksWorkforceReportArtifact artifact,
  ) => Container(
    constraints: const BoxConstraints(maxHeight: 360),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Scrollbar(
      controller: _horizontalController,
      thumbVisibility: !widget.compact,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(
              AppColors.surfaceContainerLow,
            ),
            columns: [
              for (final column in artifact.columns)
                DataColumn(label: Text(column.label)),
            ],
            rows: [
              for (final row in artifact.rows.take(12))
                DataRow(
                  cells: [
                    for (final column in artifact.columns)
                      DataCell(Text(row[column.key]?.toString() ?? '—')),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _history(
    BuildContext context,
    YorksWorkforceReportState state,
    YorksWorkforceReportController controller,
  ) {
    final items = state.history?.items ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('reports_history'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: state.isBusy ? null : controller.loadHistory,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _t('reports_history_empty'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          )
        else
          ...items
              .take(5)
              .map(
                (artifact) => ListTile(
                  minTileHeight: 52,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    artifact.isApproved
                        ? Icons.verified_outlined
                        : Icons.schedule_outlined,
                    color: artifact.isApproved
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  title: Text(_t('report_${artifact.kind.wire}')),
                  subtitle: Text(
                    '${artifact.generatedBy} · ${artifact.totals.rowCount} ${_t('reports_rows')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    controller.selectHistoryArtifact(artifact);
                    await controller.prepareSelectedArtifact();
                  },
                ),
              ),
      ],
    );
  }

  Widget _statusBanner(BuildContext context, YorksWorkforceReportState state) {
    final key = switch (state.status) {
      YorksWorkforceReportStatus.offline => 'reports_online_required',
      YorksWorkforceReportStatus.forbidden ||
      YorksWorkforceReportStatus.sessionExpired ||
      YorksWorkforceReportStatus.unavailable => 'reports_access_changed',
      YorksWorkforceReportStatus.conflict ||
      YorksWorkforceReportStatus.uncertain ||
      YorksWorkforceReportStatus.failure => 'reports_failed',
      _ => null,
    };
    return key == null
        ? const SizedBox.shrink()
        : _notice(context, Icons.info_outline, _t(key), AppColors.warning);
  }

  Widget _sourcePill(
    BuildContext context,
    YorksWorkforceReportArtifact artifact,
  ) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: artifact.isApproved
          ? AppColors.successContainer
          : AppColors.warningContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      _t(
        artifact.isApproved
            ? 'reports_approved_source'
            : 'reports_current_source',
      ),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: artifact.isApproved ? AppColors.success : AppColors.warning,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _notice(
    BuildContext context,
    IconData icon,
    String message,
    Color color,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    ),
  );

  YorksWorkforceReportRequest? _request() {
    final snapshot = _effectiveSnapshotId;
    final teamId = widget.monthlyState.selectedTeamId;
    final detail = widget.monthlyState.workerDetail;
    final projectId = detail?.worker.projects.firstOrNull?.id;
    return switch (_kind) {
      YorksWorkforceReportKind.dailyAttendanceRegister when teamId != null =>
        YorksWorkforceReportRequest(
          kind: _kind,
          workDate: _workDate,
          teamId: teamId,
        ),
      final kind when kind.requiresApprovedSnapshot && snapshot != null =>
        YorksWorkforceReportRequest(
          kind: kind,
          snapshotIds: [snapshot],
          periodMonth: widget.monthlyState.periodMonth,
          teamId: kind == YorksWorkforceReportKind.supervisorTeamMonthly
              ? teamId
              : null,
          workerId: kind == YorksWorkforceReportKind.workerMonthlyTimesheet
              ? detail?.worker.workerId
              : null,
          projectId: kind == YorksWorkforceReportKind.projectWorkforce
              ? projectId
              : null,
        ),
      final kind when !kind.requiresApprovedSnapshot =>
        YorksWorkforceReportRequest(
          kind: kind,
          periodMonth: widget.monthlyState.periodMonth,
        ),
      _ => null,
    };
  }

  String? _disabledReason(YorksWorkforceReportRequest? request) {
    if (request == null) {
      return _kind.requiresApprovedSnapshot
          ? _t('reports_snapshot_required')
          : _t('reports_date_required');
    }
    if (_kind == YorksWorkforceReportKind.workerMonthlyTimesheet &&
        request.workerId == null) {
      return _t('reports_worker_required');
    }
    if (_kind == YorksWorkforceReportKind.projectWorkforce &&
        request.projectId == null) {
      return _t('reports_project_required');
    }
    return null;
  }

  List<YorksWorkforceApprovedSnapshot> get _availableSnapshots {
    final snapshots = widget.reviewState.lifecycle?.approvedSnapshots;
    if (snapshots == null || snapshots.isEmpty) return const [];
    final ordered = [...snapshots]
      ..sort((a, b) => b.revisionNumber.compareTo(a.revisionNumber));
    return ordered;
  }

  String? get _effectiveSnapshotId {
    final snapshots = _availableSnapshots;
    if (snapshots.isEmpty) return null;
    final selected = _selectedSnapshotId;
    if (selected != null &&
        snapshots.any((snapshot) => snapshot.id == selected)) {
      return selected;
    }
    return snapshots.first.id;
  }

  void _scheduleHistory(
    YorksWorkforceReportState state,
    YorksWorkforceReportController controller,
  ) {
    if (_historyScheduled || state.status != YorksWorkforceReportStatus.idle) {
      return;
    }
    _historyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.loadHistory();
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final current = DateTime.parse(_workDate);
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _workDate =
          '${selected.year.toString().padLeft(4, '0')}-'
          '${selected.month.toString().padLeft(2, '0')}-'
          '${selected.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _previewPdf(
    BuildContext context,
    YorksWorkforceReportState state,
    YorksWorkforceReportController controller,
  ) async {
    if (!await controller.previewPdf() || !context.mounted) return;
    final bytes = state.pdfBytes;
    final artifact = state.artifact;
    if (bytes == null || artifact == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(_t('reports_preview')),
                subtitle: Text(_t('report_${artifact.kind.wire}')),
                trailing: IconButton(
                  tooltip: _t('close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: YorksWorkspaceZoomExclusion(
                  child: PdfPreview(
                    build: (_) async => bytes,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    pdfFileName: YorksWorkforceReportService().fileName(
                      artifact,
                      'pdf',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
