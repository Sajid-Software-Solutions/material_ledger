import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_workforce_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_notification_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../application/workforce_collaboration_controller.dart';
import '../../application/workforce_monthly_period_controller.dart';
import '../../application/workforce_providers.dart';
import '../../application/workforce_review_controller.dart';
import '../../domain/workforce_attendance_models.dart';
import '../../domain/workforce_collaboration_models.dart';
import '../../domain/workforce_daily_roster_models.dart';
import '../../domain/workforce_monthly_period_models.dart';
import '../../domain/workforce_review_models.dart';
import '../../domain/workforce_timesheet_models.dart';
import 'yorks_workforce_reports_panel.dart';

/// Guarded monthly workspace with the T07 review and approval lifecycle.
class YorksWorkforceTimesheetsScreen extends ConsumerStatefulWidget {
  const YorksWorkforceTimesheetsScreen({super.key, this.initialPeriodId});

  final String? initialPeriodId;

  @override
  ConsumerState<YorksWorkforceTimesheetsScreen> createState() =>
      _YorksWorkforceTimesheetsScreenState();
}

class _YorksWorkforceTimesheetsScreenState
    extends ConsumerState<YorksWorkforceTimesheetsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  bool _initialLoadScheduled = false;
  bool _targetAttempted = false;
  bool _openingTarget = false;
  String? _scheduledReviewContext;
  String? _scheduledCollaborationContext;
  String? _openedNotificationLocation;
  RouteInformationProvider? _notificationRouteInformation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final information = GoRouter.maybeOf(context)?.routeInformationProvider;
    if (!identical(information, _notificationRouteInformation)) {
      _notificationRouteInformation?.removeListener(
        _scheduleNotificationTarget,
      );
      _notificationRouteInformation = information;
      information?.addListener(_scheduleNotificationTarget);
    }
    _notificationPageUri();
    if (_openedNotificationLocation != null) _scheduleNotificationTarget();
  }

  Uri? _notificationPageUri() =>
      GoRouter.maybeOf(context) == null ? null : GoRouterState.of(context).uri;

  void _scheduleNotificationTarget() {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final uri = _notificationPageUri();
    if (uri == null || uri.path != '/yorks/workforce/timesheets') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _notificationPageUri() != uri ||
          uri.queryParameters['period_id'] != widget.initialPeriodId ||
          _openedNotificationLocation == uri.toString()) {
        return;
      }
      setState(() {
        _targetAttempted = false;
        _scheduledReviewContext = null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant YorksWorkforceTimesheetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPeriodId != widget.initialPeriodId) {
      _targetAttempted = false;
      _scheduledReviewContext = null;
    }
  }

  @override
  void dispose() {
    _notificationRouteInformation?.removeListener(_scheduleNotificationTarget);
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleInitialLoad(YorksWorkforceMonthlyState state) {
    if (widget.initialPeriodId != null && !_targetAttempted) {
      _targetAttempted = true;
      _openingTarget = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openNotificationPeriod(),
      );
      return;
    }
    if (_openingTarget ||
        (widget.initialPeriodId != null &&
            state.status == YorksWorkforceMonthlyStatus.idle)) {
      return;
    }
    if (state.status != YorksWorkforceMonthlyStatus.idle) {
      _initialLoadScheduled = false;
      return;
    }
    if (_initialLoadScheduled) return;
    _initialLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(yorksWorkforceMonthlyControllerProvider.notifier).initialize();
    });
  }

  Future<void> _openNotificationPeriod() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final periodId = widget.initialPeriodId;
    final uri = _notificationPageUri();
    _openedNotificationLocation = uri?.toString();
    final owner = ref.read(yorksV1AuthUserIdProvider);
    bool stillCurrent() =>
        mounted &&
        widget.initialPeriodId == periodId &&
        ref.read(yorksV1AuthUserIdProvider) == owner &&
        _notificationPageUri() == uri &&
        ModalRoute.of(context)?.isCurrent != false;
    final review = ref.read(yorksWorkforceReviewControllerProvider.notifier);
    final loaded = await review.load(periodId: periodId);
    if (!stillCurrent()) return;
    final lifecycle = ref
        .read(yorksWorkforceReviewControllerProvider)
        .lifecycle;
    if (loaded && lifecycle != null && lifecycle.periodId == periodId) {
      final monthly = ref.read(
        yorksWorkforceMonthlyControllerProvider.notifier,
      );
      final teamsLoaded = await monthly.loadTeams(
        periodMonth: lifecycle.periodMonth,
      );
      if (!stillCurrent()) return;
      final periodLoaded =
          teamsLoaded && await monthly.changeTeam(lifecycle.teamId);
      if (!stillCurrent()) return;
      final projection = ref
          .read(yorksWorkforceMonthlyControllerProvider)
          .projection;
      if (periodLoaded && projection?.period?.id == periodId) {
        _scheduledReviewContext = periodId;
        final notificationId = uri?.queryParameters['notificationId'];
        if (owner != null &&
            notificationId != null &&
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              caseSensitive: false,
            ).hasMatch(notificationId)) {
          await WidgetsBinding.instance.endOfFrame;
          if (!stillCurrent()) return;
          try {
            await ref
                .read(yorksV1NotificationsProvider.notifier)
                .markSeen(notificationId);
          } catch (_) {
            // A failed acknowledgement retains the authoritative unread state.
          }
        }
      }
    }
    if (mounted) setState(() => _openingTarget = false);
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final state = ref.read(yorksWorkforceMonthlyControllerProvider);
      final filters = state.filters;
      if (filters == null) return;
      ref
          .read(yorksWorkforceMonthlyControllerProvider.notifier)
          .changeFilters(filters.copyWith(query: value, workerOffset: 0));
    });
  }

  void _scheduleReviewLoad(YorksWorkforceMonthlyState monthly) {
    if (_openingTarget ||
        (widget.initialPeriodId != null && monthly.projection == null)) {
      return;
    }
    final periodId = monthly.projection?.period?.id;
    final context = periodId ?? 'queue';
    if (_scheduledReviewContext == context) return;
    _scheduledReviewContext = context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(yorksWorkforceReviewControllerProvider.notifier)
          .load(periodId: periodId);
    });
  }

  void _scheduleCollaborationLoad(YorksWorkforceMonthlyState monthly) {
    final periodId = monthly.projection?.period?.id;
    if (periodId == null || _scheduledCollaborationContext == periodId) return;
    _scheduledCollaborationContext = periodId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(yorksWorkforceCollaborationControllerProvider.notifier)
          .load(periodId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksWorkforceMonthlyControllerProvider);
    final controller = ref.read(
      yorksWorkforceMonthlyControllerProvider.notifier,
    );
    final reviewState = ref.watch(yorksWorkforceReviewControllerProvider);
    final reviewController = ref.read(
      yorksWorkforceReviewControllerProvider.notifier,
    );
    final collaborationState = ref.watch(
      yorksWorkforceCollaborationControllerProvider,
    );
    final collaborationController = ref.read(
      yorksWorkforceCollaborationControllerProvider.notifier,
    );
    final authority = ref.watch(yorksWorkforceAuthorityEpochProvider);
    _scheduleInitialLoad(state);
    _scheduleReviewLoad(state);
    _scheduleCollaborationLoad(state);

    return YorksWorkforceMonthlyView(
      language: language,
      state: state,
      reviewState: reviewState,
      collaborationState: collaborationState,
      canExportReports: authority.canExportReports,
      searchController: _searchController,
      onSearchChanged: _onSearchChanged,
      onRetry: () {
        final filters = state.filters;
        if (filters == null) {
          controller.loadTeams(periodMonth: state.periodMonth);
        } else {
          controller.loadPeriod(filters);
        }
      },
      onMonthChanged: controller.changeMonth,
      onTeamChanged: controller.changeTeam,
      onValidate: controller.validatePeriod,
      onWorkerChanged: controller.openWorker,
      onCloseWorker: controller.closeWorker,
      onDateChanged: controller.selectDate,
      onLoadMoreWorkers: controller.loadMoreWorkers,
      onIssueFilter: ({severity, issueCode, workerId}) => controller.loadIssues(
        severity: severity,
        issueCode: issueCode,
        workerId: workerId,
      ),
      onLoadMoreIssues: controller.loadMoreIssues,
      onReviewRetry: () {
        if (widget.initialPeriodId != null && state.projection == null) {
          _openingTarget = true;
          unawaited(_openNotificationPeriod());
          return;
        }
        _scheduledReviewContext = null;
        reviewController.load(periodId: state.projection?.period?.id);
      },
      onReviewQueueSelect: (periodId) =>
          reviewController.load(periodId: periodId),
      onReviewAction: (action) => _runReviewAction(
        context,
        action,
        state,
        controller,
        reviewController,
      ),
      onCollaborationRetry: () {
        final periodId = state.projection?.period?.id;
        if (periodId != null) collaborationController.load(periodId);
      },
      onOpenDiscussion: () {
        final periodId = state.projection?.period?.id;
        if (periodId != null) {
          collaborationController.openDiscussion(periodId);
        }
      },
      onSendDiscussionMessage: (body) async {
        final periodId = state.projection?.period?.id;
        if (periodId == null) return false;
        return collaborationController.sendMessage(
          YorksWorkforceDiscussionMessageInput(
            periodId: periodId,
            body: body,
            linkedEntityType: 'workforce_monthly_period',
            linkedEntityId: periodId,
          ),
        );
      },
      onUploadEvidence: () =>
          _uploadPeriodEvidence(context, state, collaborationController),
    );
  }

  Future<void> _uploadPeriodEvidence(
    BuildContext context,
    YorksWorkforceMonthlyState monthly,
    YorksWorkforceCollaborationController controller,
  ) async {
    final periodId = monthly.projection?.period?.id;
    if (periodId == null) return;
    final language = ref.read(languageProvider);
    final evidenceType = await showDialog<YorksWorkforceEvidenceType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          YorksV1WorkforceStrings.text(
            language,
            'monthly_collaboration_evidence_type',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(
                YorksV1WorkforceStrings.text(
                  language,
                  'monthly_collaboration_monthly_attachment',
                ),
              ),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(YorksWorkforceEvidenceType.monthlyTimesheetAttachment),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                YorksV1WorkforceStrings.text(
                  language,
                  'monthly_collaboration_other_document',
                ),
              ),
              onTap: () => Navigator.of(
                dialogContext,
              ).pop(YorksWorkforceEvidenceType.otherWorkforceDocument),
            ),
          ],
        ),
      ),
    );
    if (evidenceType == null || !context.mounted) return;
    final selected = await ref
        .read(yorksV1DocumentFileServiceProvider)
        .selectDocument();
    if (selected == null || !mounted) return;
    final succeeded = await controller.uploadEvidence(
      YorksWorkforceEvidenceUploadInput(
        entityType: 'workforce_monthly_period',
        entityId: periodId,
        fileName: selected.fileName,
        mimeType: selected.mimeType,
        byteSize: selected.bytes.lengthInBytes,
        sha256: sha256.convert(selected.bytes).toString(),
        evidenceType: evidenceType,
        periodId: periodId,
      ),
      bytes: selected.bytes,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          YorksV1WorkforceStrings.text(
            language,
            succeeded
                ? 'monthly_collaboration_upload_succeeded'
                : 'monthly_collaboration_upload_failed',
          ),
        ),
      ),
    );
  }

  Future<void> _runReviewAction(
    BuildContext context,
    YorksWorkforceMonthlyReviewAction action,
    YorksWorkforceMonthlyState monthly,
    YorksWorkforceMonthlyController monthlyController,
    YorksWorkforceReviewController reviewController,
  ) async {
    final lifecycle = ref
        .read(yorksWorkforceReviewControllerProvider)
        .lifecycle;
    if (lifecycle == null) return;
    final language = ref.read(languageProvider);
    final reason = await _showReasonDialog(context, language, action);
    if (reason == null || !context.mounted) return;
    YorksWorkforceReviewLifecycle? result;
    switch (action) {
      case YorksWorkforceMonthlyReviewAction.submit:
        final warningIds = await monthlyController.loadAllIssueIds(
          YorksWorkforceMonthlyIssueSeverity.warning,
        );
        if (warningIds == null || !context.mounted) return;
        result = await reviewController.submit(
          warningIssueIds: warningIds,
          reason: reason,
        );
      case YorksWorkforceMonthlyReviewAction.returnForCorrection:
        final affected = _selectedAffectedEntry(monthly);
        if (affected == null) {
          _showSelectionMessage(context, language);
          return;
        }
        result = await reviewController.returnForCorrection(
          affectedEntries: [affected],
          reason: reason,
        );
      case YorksWorkforceMonthlyReviewAction.correct:
        final correction = await _showCorrectionDialog(
          context,
          language,
          monthly,
          reason,
        );
        if (correction == null || !context.mounted) return;
        result = await reviewController.correctDuringReview(
          workDate: correction.$1,
          row: correction.$2,
          reason: reason,
        );
      case YorksWorkforceMonthlyReviewAction.verify:
        result = await reviewController.verify(reason);
      case YorksWorkforceMonthlyReviewAction.approveAndLock:
        result = await reviewController.approveAndLock(reason);
      case YorksWorkforceMonthlyReviewAction.requestReopen:
        final affected = _selectedAffectedEntry(monthly);
        if (affected == null) {
          _showSelectionMessage(context, language);
          return;
        }
        result = await reviewController.requestReopen(
          affectedEntries: [affected],
          reason: reason,
        );
      case YorksWorkforceMonthlyReviewAction.authorizeReopen:
        final request = lifecycle.reopenRequests
            .where((item) => item.isPending)
            .firstOrNull;
        if (request == null) return;
        result = await reviewController.authorizeReopen(
          requestId: request.id,
          reason: reason,
        );
    }
    if (result == null || !mounted) return;
    final filters = monthly.filters;
    if (filters != null && result.periodId == monthly.projection?.period?.id) {
      await monthlyController.loadPeriod(filters);
    }
  }

  YorksWorkforceAffectedEntry? _selectedAffectedEntry(
    YorksWorkforceMonthlyState state,
  ) {
    final workerId = state.workerDetail?.worker.workerId;
    final date = state.selectedDate;
    if (workerId == null || date == null) return null;
    return YorksWorkforceAffectedEntry(workerId: workerId, workDate: date);
  }

  void _showSelectionMessage(BuildContext context, AppLanguage language) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          YorksV1WorkforceStrings.text(language, 'monthly_review_select_entry'),
        ),
      ),
    );
  }

  Future<String?> _showReasonDialog(
    BuildContext context,
    AppLanguage language,
    YorksWorkforceMonthlyReviewAction action,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1WorkforceStrings.text(language, action.labelKey)),
        content: TextField(
          key: const Key('monthly-review-reason-field'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: YorksV1WorkforceStrings.text(
              language,
              'monthly_review_reason',
            ),
            hintText: YorksV1WorkforceStrings.text(
              language,
              'monthly_review_reason_hint',
            ),
          ),
          onSubmitted: (value) {
            final reason = value.trim();
            if (reason.isNotEmpty) Navigator.of(dialogContext).pop(reason);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              YorksV1WorkforceStrings.text(language, 'monthly_review_cancel'),
            ),
          ),
          FilledButton(
            key: const Key('monthly-review-confirm-reason'),
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.of(dialogContext).pop(reason);
            },
            child: Text(
              YorksV1WorkforceStrings.text(language, 'monthly_review_confirm'),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<(String, YorksWorkforceDailyRosterSaveRow)?> _showCorrectionDialog(
    BuildContext context,
    AppLanguage language,
    YorksWorkforceMonthlyState state,
    String reason,
  ) async {
    final detail = state.workerDetail;
    final selectedDate = state.selectedDate;
    if (detail == null || selectedDate == null) {
      _showSelectionMessage(context, language);
      return null;
    }
    final day = detail.days
        .where((candidate) => candidate.workDate == selectedDate)
        .firstOrNull;
    final attendance = day?.attendance;
    if (day == null || attendance == null || day.isFuture) {
      _showSelectionMessage(context, language);
      return null;
    }
    final allocation = day.allocation;
    if (allocation?['targets_restricted'] == true) return null;
    final targetMaps = (allocation?['targets'] as List<Object?>? ?? const [])
        .map((value) => Map<String, dynamic>.from(value! as Map))
        .toList(growable: false);
    var status = YorksWorkforceAttendanceStatus.fromWire(
      attendance['attendance_status'],
    );
    final regularController = TextEditingController(
      text: '${attendance['regular_minutes']}',
    );
    final overtimeController = TextEditingController(
      text: '${attendance['overtime_minutes']}',
    );
    final overtimeReasonController = TextEditingController(
      text: attendance['overtime_reason'] as String? ?? '',
    );
    final activityControllers = targetMaps
        .map(
          (target) => TextEditingController(
            text: target['activity_task'] as String? ?? '',
          ),
        )
        .toList(growable: false);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            YorksV1WorkforceStrings.text(language, 'monthly_correct'),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<YorksWorkforceAttendanceStatus>(
                    initialValue: status,
                    decoration: InputDecoration(
                      labelText: YorksV1WorkforceStrings.text(
                        language,
                        'monthly_day_attendance',
                      ),
                    ),
                    items: YorksWorkforceAttendanceStatus.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              YorksV1WorkforceStrings.text(
                                language,
                                value.wireValue,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: targetMaps.isNotEmpty
                        ? null
                        : (value) {
                            if (value != null) setState(() => status = value);
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: regularController,
                          readOnly: targetMaps.isNotEmpty,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: YorksV1WorkforceStrings.text(
                              language,
                              'monthly_review_regular_minutes',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextField(
                          controller: overtimeController,
                          readOnly: targetMaps.isNotEmpty,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: YorksV1WorkforceStrings.text(
                              language,
                              'monthly_review_overtime_minutes',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: overtimeReasonController,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: YorksV1WorkforceStrings.text(
                        language,
                        'note_exception',
                      ),
                    ),
                  ),
                  for (
                    var index = 0;
                    index < activityControllers.length;
                    index++
                  ) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: activityControllers[index],
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText:
                            '${YorksV1WorkforceStrings.text(language, 'monthly_review_activity')} ${index + 1}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                YorksV1WorkforceStrings.text(language, 'monthly_review_cancel'),
              ),
            ),
            FilledButton(
              key: const Key('monthly-review-confirm-correction'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                YorksV1WorkforceStrings.text(
                  language,
                  'monthly_review_confirm',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      regularController.dispose();
      overtimeController.dispose();
      overtimeReasonController.dispose();
      for (final controller in activityControllers) {
        controller.dispose();
      }
      return null;
    }
    final regular = int.tryParse(regularController.text.trim());
    final overtime = int.tryParse(overtimeController.text.trim());
    final allocations = <YorksWorkforceAllocationInput>[];
    if (regular != null && overtime != null) {
      for (var index = 0; index < targetMaps.length; index++) {
        final target = targetMaps[index];
        allocations.add(
          YorksWorkforceAllocationInput(
            targetKind: YorksWorkforceAllocationTargetKind.fromWire(
              target['target_kind'],
            ),
            projectId: target['project_id'] as String?,
            projectScopeId: target['project_scope_id'] as String?,
            internalLocationId: target['internal_location_id'] as String?,
            activityTask: activityControllers[index].text,
            notes: target['notes'] as String?,
            regularMinutes: target['regular_minutes'] as int,
            overtimeMinutes: target['overtime_minutes'] as int,
            startTime: target['start_time_local'] as String?,
            endTime: target['end_time_local'] as String?,
          ),
        );
      }
    }
    final row = regular == null || overtime == null
        ? null
        : YorksWorkforceDailyRosterSaveRow(
            workerId: detail.worker.workerId,
            expectedAttendanceVersion: attendance['record_version'] as int,
            status: status,
            regularMinutes: regular,
            overtimeMinutes: overtime,
            overtimeReason: overtimeReasonController.text,
            reason: reason,
            allocationAction: allocations.isEmpty
                ? YorksWorkforceRosterAllocationAction.preserve
                : YorksWorkforceRosterAllocationAction.replace,
            expectedAllocationVersion:
                allocation?['allocation_set_version'] as int?,
            allocations: allocations.isEmpty ? null : allocations,
          );
    regularController.dispose();
    overtimeController.dispose();
    overtimeReasonController.dispose();
    for (final controller in activityControllers) {
      controller.dispose();
    }
    return row?.isValid == true ? (selectedDate, row!) : null;
  }
}

/// Presentation-only surface kept separate from the RPC/controller boundary so
/// responsive, RTL and accessibility evidence can use immutable projections.
const _workforceMonthlyDesktopBreakpoint = 1200.0;

class YorksWorkforceMonthlyView extends StatelessWidget {
  const YorksWorkforceMonthlyView({
    required this.language,
    required this.state,
    this.reviewState = const YorksWorkforceReviewState(),
    this.collaborationState = const YorksWorkforceCollaborationState(),
    this.canExportReports = false,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRetry,
    required this.onMonthChanged,
    required this.onTeamChanged,
    required this.onValidate,
    required this.onWorkerChanged,
    required this.onCloseWorker,
    required this.onDateChanged,
    required this.onLoadMoreWorkers,
    required this.onIssueFilter,
    required this.onLoadMoreIssues,
    this.onReviewRetry,
    this.onReviewQueueSelect,
    this.onReviewAction,
    this.onCollaborationRetry,
    this.onOpenDiscussion,
    this.onSendDiscussionMessage,
    this.onUploadEvidence,
    super.key,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final YorksWorkforceReviewState reviewState;
  final YorksWorkforceCollaborationState collaborationState;
  final bool canExportReports;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRetry;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<String> onTeamChanged;
  final VoidCallback onValidate;
  final ValueChanged<String> onWorkerChanged;
  final VoidCallback onCloseWorker;
  final ValueChanged<String> onDateChanged;
  final VoidCallback onLoadMoreWorkers;
  final void Function({
    YorksWorkforceMonthlyIssueSeverity? severity,
    String? issueCode,
    String? workerId,
  })
  onIssueFilter;
  final VoidCallback onLoadMoreIssues;
  final VoidCallback? onReviewRetry;
  final ValueChanged<String>? onReviewQueueSelect;
  final ValueChanged<YorksWorkforceMonthlyReviewAction>? onReviewAction;
  final VoidCallback? onCollaborationRetry;
  final VoidCallback? onOpenDiscussion;
  final Future<bool> Function(String body)? onSendDiscussionMessage;
  final VoidCallback? onUploadEvidence;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppSpacing.compactBreakpoint;
    final tablet = !compact && width < _workforceMonthlyDesktopBreakpoint;
    final dense = compact || tablet;
    final projection = state.projection;

    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: compact ? AppColors.mobileSurface : AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              if (state.isBusy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => onRetry(),
                  child: CustomScrollView(
                    key: const PageStorageKey('workforce-monthly-view'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          compact
                              ? AppSpacing.mobileScreenHorizontal
                              : tablet
                              ? AppSpacing.lg
                              : AppSpacing.xxl,
                          compact
                              ? AppSpacing.mobileScreenVertical
                              : tablet
                              ? AppSpacing.lg
                              : AppSpacing.xxl,
                          compact
                              ? AppSpacing.mobileScreenHorizontal
                              : tablet
                              ? AppSpacing.lg
                              : AppSpacing.xxl,
                          AppSpacing.colossal,
                        ),
                        sliver: SliverList.list(
                          children: [
                            _MonthlyHeader(
                              language: language,
                              state: state,
                              compact: compact,
                              stacked: tablet,
                              onMonthChanged: onMonthChanged,
                              onTeamChanged: onTeamChanged,
                              onValidate: state.canValidate && !compact
                                  ? onValidate
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _MonthlyStateBanner(
                              language: language,
                              state: state,
                              compact: compact,
                              onRetry: onRetry,
                            ),
                            if (!dense && state.workerDetail != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _WorkerMonthDetail(
                                      language: language,
                                      detail: state.workerDetail!,
                                      selectedDate: state.selectedDate,
                                      compact: false,
                                      onClose: onCloseWorker,
                                      onDateChanged: onDateChanged,
                                    ),
                                  ),
                                  if (onReviewRetry != null ||
                                      reviewState.status !=
                                          YorksWorkforceReviewStatus.idle) ...[
                                    const SizedBox(width: AppSpacing.lg),
                                    SizedBox(
                                      width: 360,
                                      child: _MonthlyReviewPanel(
                                        language: language,
                                        state: reviewState,
                                        compact: true,
                                        allowActions: true,
                                        hasSelectedEntry:
                                            state.selectedDate != null &&
                                            reviewState.lifecycle?.periodId ==
                                                state.projection?.period?.id,
                                        onRetry: onReviewRetry,
                                        onQueueSelect: onReviewQueueSelect,
                                        onAction: onReviewAction,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            if ((onReviewRetry != null ||
                                    reviewState.status !=
                                        YorksWorkforceReviewStatus.idle) &&
                                (dense || state.workerDetail == null)) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _MonthlyReviewPanel(
                                language: language,
                                state: reviewState,
                                compact: dense,
                                allowActions: !compact,
                                hasSelectedEntry:
                                    state.workerDetail != null &&
                                    state.selectedDate != null &&
                                    reviewState.lifecycle?.periodId ==
                                        state.projection?.period?.id,
                                onRetry: onReviewRetry,
                                onQueueSelect: onReviewQueueSelect,
                                onAction: onReviewAction,
                              ),
                            ],
                            if (projection?.period != null &&
                                (onCollaborationRetry != null ||
                                    collaborationState.status !=
                                        YorksWorkforceCollaborationStatus
                                            .idle)) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _MonthlyCollaborationPanel(
                                language: language,
                                state: collaborationState,
                                periodId: projection!.period!.id,
                                compact: compact,
                                onRetry: onCollaborationRetry,
                                onOpenDiscussion: onOpenDiscussion,
                                onSendMessage: onSendDiscussionMessage,
                                onUploadEvidence: onUploadEvidence,
                              ),
                            ],
                            if (canExportReports) ...[
                              const SizedBox(height: AppSpacing.lg),
                              YorksWorkforceReportsPanel(
                                language: language,
                                monthlyState: state,
                                reviewState: reviewState,
                                compact: compact,
                              ),
                            ],
                            if (projection?.summary != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              if (tablet) ...[
                                _TabletMonthlyBody(
                                  language: language,
                                  state: state,
                                  searchController: searchController,
                                  onSearchChanged: onSearchChanged,
                                  onWorkerChanged: onWorkerChanged,
                                  onLoadMoreWorkers: onLoadMoreWorkers,
                                  onIssueFilter: onIssueFilter,
                                  onLoadMoreIssues: onLoadMoreIssues,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                _MonthlySummaryGrid(
                                  language: language,
                                  summary: projection!.summary!,
                                  compact: true,
                                ),
                              ] else ...[
                                _MonthlySummaryGrid(
                                  language: language,
                                  summary: projection!.summary!,
                                  compact: compact,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                              if (compact && state.workerDetail == null)
                                _CompactMonthlyBody(
                                  language: language,
                                  state: state,
                                  onWorkerChanged: onWorkerChanged,
                                  searchController: searchController,
                                  onSearchChanged: onSearchChanged,
                                  onLoadMore: onLoadMoreWorkers,
                                )
                              else if (!compact && !tablet)
                                _DesktopMonthlyBody(
                                  language: language,
                                  state: state,
                                  searchController: searchController,
                                  onSearchChanged: onSearchChanged,
                                  onWorkerChanged: onWorkerChanged,
                                  onLoadMoreWorkers: onLoadMoreWorkers,
                                  onIssueFilter: onIssueFilter,
                                  onLoadMoreIssues: onLoadMoreIssues,
                                ),
                              if (state.workerDetail != null && dense) ...[
                                const SizedBox(height: AppSpacing.lg),
                                _WorkerMonthDetail(
                                  language: language,
                                  detail: state.workerDetail!,
                                  selectedDate: state.selectedDate,
                                  compact: dense,
                                  onClose: onCloseWorker,
                                  onDateChanged: onDateChanged,
                                ),
                              ],
                            ] else if (projection?.isAbsent == true) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _EmptyPeriodCard(
                                language: language,
                                canValidate: state.canValidate,
                                compact: compact,
                                onValidate: onValidate,
                              ),
                            ] else if (state.status ==
                                YorksWorkforceMonthlyStatus.loading) ...[
                              const SizedBox(height: AppSpacing.lg),
                              const _MonthlySkeleton(),
                            ],
                          ],
                        ),
                      ),
                    ],
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

class _MonthlyCollaborationPanel extends StatefulWidget {
  const _MonthlyCollaborationPanel({
    required this.language,
    required this.state,
    required this.periodId,
    required this.compact,
    required this.onRetry,
    required this.onOpenDiscussion,
    required this.onSendMessage,
    required this.onUploadEvidence,
  });

  final AppLanguage language;
  final YorksWorkforceCollaborationState state;
  final String periodId;
  final bool compact;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenDiscussion;
  final Future<bool> Function(String body)? onSendMessage;
  final VoidCallback? onUploadEvidence;

  @override
  State<_MonthlyCollaborationPanel> createState() =>
      _MonthlyCollaborationPanelState();
}

class _MonthlyCollaborationPanelState
    extends State<_MonthlyCollaborationPanel> {
  final _messageController = TextEditingController();

  String _t(String key) => YorksV1WorkforceStrings.text(widget.language, key);

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final projection = state.projection?.periodId == widget.periodId
        ? state.projection
        : null;
    final denied =
        state.status == YorksWorkforceCollaborationStatus.forbidden ||
        state.status == YorksWorkforceCollaborationStatus.sessionExpired ||
        state.status == YorksWorkforceCollaborationStatus.unavailable;
    final failure = switch (state.status) {
      YorksWorkforceCollaborationStatus.offline =>
        'monthly_collaboration_offline',
      YorksWorkforceCollaborationStatus.conflict =>
        'monthly_collaboration_conflict',
      YorksWorkforceCollaborationStatus.uncertain =>
        'monthly_collaboration_uncertain',
      YorksWorkforceCollaborationStatus.failure =>
        'monthly_collaboration_failed',
      _ => null,
    };

    return _Panel(
      padding: EdgeInsets.all(widget.compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('monthly_collaboration_title'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _t(
                        widget.compact
                            ? 'monthly_collaboration_mobile_read_only'
                            : 'monthly_collaboration_body',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: _t('refresh'),
                  onPressed: state.isBusy ? null : widget.onRetry,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          if (state.isBusy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (denied || failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            _CollaborationNotice(
              icon: denied ? Icons.lock_outline : Icons.info_outline,
              label: _t(denied ? 'monthly_collaboration_denied' : failure!),
            ),
          ] else if (projection == null) ...[
            const SizedBox(height: AppSpacing.lg),
            _CollaborationNotice(
              icon: Icons.hourglass_empty_outlined,
              label: _t('monthly_collaboration_loading'),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.lg),
            if (widget.compact)
              _buildCompact(context, projection)
            else
              _buildDesktop(context, projection),
          ],
        ],
      ),
    );
  }

  Widget _buildCompact(
    BuildContext context,
    YorksWorkforceCollaborationProjection projection,
  ) {
    final messages = projection.discussion?.messages.length ?? 0;
    return Column(
      children: [
        _CollaborationCountRow(
          icon: Icons.chat_bubble_outline,
          label: _t('monthly_collaboration_discussion'),
          value: messages,
        ),
        _CollaborationCountRow(
          icon: Icons.attach_file,
          label: _t('monthly_collaboration_evidence'),
          value: projection.documents.length,
        ),
        _CollaborationCountRow(
          icon: Icons.notifications_none,
          label: _t('monthly_collaboration_notifications'),
          value: projection.unreadNotificationCount,
        ),
      ],
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    YorksWorkforceCollaborationProjection projection,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 5, child: _buildDiscussion(context, projection)),
      const SizedBox(width: AppSpacing.md),
      Expanded(flex: 3, child: _buildEvidence(context, projection)),
      const SizedBox(width: AppSpacing.md),
      Expanded(flex: 3, child: _buildNotifications(context, projection)),
    ],
  );

  Widget _buildDiscussion(
    BuildContext context,
    YorksWorkforceCollaborationProjection projection,
  ) {
    final thread = projection.discussion;
    return _CollaborationSection(
      icon: Icons.chat_bubble_outline,
      title: _t('monthly_collaboration_discussion'),
      badge: thread?.messages.length ?? 0,
      child: thread == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('monthly_collaboration_no_discussion'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    key: const Key('workforce-open-discussion'),
                    onPressed: widget.state.isBusy
                        ? null
                        : widget.onOpenDiscussion,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(_t('monthly_collaboration_open_discussion')),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                if (thread.messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      _t('monthly_collaboration_no_messages'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  )
                else
                  ...thread.messages.reversed
                      .take(4)
                      .toList()
                      .reversed
                      .map(
                        (message) => _CollaborationMessageRow(
                          label: message.isSystem
                              ? _systemEventLabel(message.systemEventCode)
                              : message.body ??
                                    _t('monthly_collaboration_message'),
                          meta: message.isSystem
                              ? _t('monthly_collaboration_system_event')
                              : message.senderDisplayName ??
                                    _t('monthly_collaboration_participant'),
                          isSystem: message.isSystem,
                        ),
                      ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('workforce-discussion-message'),
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 4000,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _t('monthly_collaboration_message_hint'),
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: _t('monthly_collaboration_send'),
                      onPressed: widget.state.isBusy ? null : _send,
                      icon: const Icon(Icons.send_outlined),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ],
            ),
    );
  }

  Widget _buildEvidence(
    BuildContext context,
    YorksWorkforceCollaborationProjection projection,
  ) => _CollaborationSection(
    icon: Icons.attach_file,
    title: _t('monthly_collaboration_evidence'),
    badge: projection.documents.length,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (projection.documents.isEmpty)
          Text(
            _t('monthly_collaboration_no_evidence'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          )
        else
          ...projection.documents.take(4).map((document) {
            final version = document.currentVersion;
            return _CollaborationMessageRow(
              label: version.fileName,
              meta: _evidenceLabel(document.evidenceType),
              isSystem: false,
            );
          }),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            key: const Key('workforce-add-evidence'),
            onPressed: widget.state.isBusy ? null : widget.onUploadEvidence,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_t('monthly_collaboration_add_evidence')),
          ),
        ),
      ],
    ),
  );

  Widget _buildNotifications(
    BuildContext context,
    YorksWorkforceCollaborationProjection projection,
  ) => _CollaborationSection(
    icon: Icons.notifications_none,
    title: _t('monthly_collaboration_notifications'),
    badge: projection.unreadNotificationCount,
    child: projection.notifications.isEmpty
        ? Text(
            _t('monthly_collaboration_no_notifications'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          )
        : Column(
            children: projection.notifications
                .take(5)
                .map(
                  (item) => _CollaborationMessageRow(
                    label: _notificationLabel(item.eventCode),
                    meta: item.itemCount > 1
                        ? '${item.itemCount} ${_t('monthly_collaboration_items')}'
                        : _t(
                            item.isUnread
                                ? 'monthly_collaboration_unread'
                                : 'monthly_collaboration_seen',
                          ),
                    isSystem: true,
                  ),
                )
                .toList(growable: false),
          ),
  );

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || widget.state.isBusy) return;
    final succeeded = await widget.onSendMessage?.call(body) ?? false;
    if (succeeded && mounted) _messageController.clear();
  }

  String _systemEventLabel(String? code) => _t(switch (code) {
    'workforce_period_submitted' => 'monthly_collaboration_event_submitted',
    'workforce_period_returned' => 'monthly_collaboration_event_returned',
    'workforce_correction_completed' => 'monthly_collaboration_event_corrected',
    'workforce_period_verified' => 'monthly_collaboration_event_verified',
    'workforce_period_approved_locked' =>
      'monthly_collaboration_event_approved',
    'workforce_reopen_requested' =>
      'monthly_collaboration_event_reopen_requested',
    'workforce_reopen_approved' => 'monthly_collaboration_event_reopened',
    _ => 'monthly_collaboration_system_event',
  });

  String _notificationLabel(String code) => _t(switch (code) {
    'workforce_monthly_period_incomplete' =>
      'monthly_collaboration_notice_incomplete',
    'workforce_daily_attendance_missing' =>
      'monthly_collaboration_notice_missing',
    'workforce_period_submitted' => 'monthly_collaboration_event_submitted',
    'workforce_period_returned' => 'monthly_collaboration_event_returned',
    'workforce_correction_completed' => 'monthly_collaboration_event_corrected',
    'workforce_period_verified' => 'monthly_collaboration_event_verified',
    'workforce_final_approval_required' =>
      'monthly_collaboration_notice_final_approval',
    'workforce_period_approved_locked' =>
      'monthly_collaboration_event_approved',
    'workforce_reopen_requested' =>
      'monthly_collaboration_event_reopen_requested',
    'workforce_reopen_approved' => 'monthly_collaboration_event_reopened',
    _ => 'monthly_collaboration_notification',
  });

  String _evidenceLabel(YorksWorkforceEvidenceType type) => _t(switch (type) {
    YorksWorkforceEvidenceType.medicalCertificate =>
      'monthly_collaboration_evidence_medical',
    YorksWorkforceEvidenceType.leaveDocument =>
      'monthly_collaboration_evidence_leave',
    YorksWorkforceEvidenceType.overtimeAuthorization =>
      'monthly_collaboration_evidence_overtime',
    YorksWorkforceEvidenceType.workerTransferNote =>
      'monthly_collaboration_evidence_transfer',
    YorksWorkforceEvidenceType.siteAttendanceSheet =>
      'monthly_collaboration_evidence_site_sheet',
    YorksWorkforceEvidenceType.dailySupportingPhoto =>
      'monthly_collaboration_evidence_photo',
    YorksWorkforceEvidenceType.monthlyTimesheetAttachment =>
      'monthly_collaboration_monthly_attachment',
    YorksWorkforceEvidenceType.otherWorkforceDocument =>
      'monthly_collaboration_other_document',
  });
}

class _CollaborationSection extends StatelessWidget {
  const _CollaborationSection({
    required this.icon,
    required this.title,
    required this.badge,
    required this.child,
  });

  final IconData icon;
  final String title;
  final int badge;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$badge',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _CollaborationMessageRow extends StatelessWidget {
  const _CollaborationMessageRow({
    required this.label,
    required this.meta,
    required this.isSystem,
  });

  final String label;
  final String meta;
  final bool isSystem;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isSystem ? Icons.auto_awesome_outlined : Icons.circle,
          size: isSystem ? 16 : 7,
          color: isSystem ? AppColors.primary : AppColors.success,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CollaborationNotice extends StatelessWidget {
  const _CollaborationNotice({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class _CollaborationCountRow extends StatelessWidget {
  const _CollaborationCountRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label)),
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

enum YorksWorkforceMonthlyReviewAction {
  submit('monthly_submit'),
  returnForCorrection('monthly_return'),
  correct('monthly_correct'),
  verify('monthly_verify'),
  approveAndLock('monthly_approve_lock'),
  requestReopen('monthly_request_reopen'),
  authorizeReopen('monthly_authorize_reopen');

  const YorksWorkforceMonthlyReviewAction(this.labelKey);
  final String labelKey;
}

class _MonthlyReviewPanel extends StatelessWidget {
  const _MonthlyReviewPanel({
    required this.language,
    required this.state,
    required this.compact,
    required this.allowActions,
    required this.hasSelectedEntry,
    required this.onRetry,
    required this.onQueueSelect,
    required this.onAction,
  });

  final AppLanguage language;
  final YorksWorkforceReviewState state;
  final bool compact;
  final bool allowActions;
  final bool hasSelectedEntry;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onQueueSelect;
  final ValueChanged<YorksWorkforceMonthlyReviewAction>? onAction;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final lifecycle = state.lifecycle;
    final queue = state.queue;
    final errorKey = switch (state.status) {
      YorksWorkforceReviewStatus.conflict => 'monthly_review_conflict',
      YorksWorkforceReviewStatus.uncertain => 'monthly_review_uncertain',
      YorksWorkforceReviewStatus.forbidden ||
      YorksWorkforceReviewStatus.sessionExpired ||
      YorksWorkforceReviewStatus.unavailable => 'monthly_review_denied',
      YorksWorkforceReviewStatus.offline => 'monthly_online_required',
      YorksWorkforceReviewStatus.failure => 'monthly_load_failed',
      _ => null,
    };
    final actions = lifecycle == null
        ? const <_ReviewActionSpec>[]
        : <_ReviewActionSpec>[
            if (lifecycle.actions.canSubmit)
              const _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.submit,
                icon: Icons.send_outlined,
                primary: true,
              ),
            if (lifecycle.actions.canReturn)
              _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.returnForCorrection,
                icon: Icons.undo_outlined,
                enabled: hasSelectedEntry,
              ),
            if (lifecycle.actions.canCorrect)
              _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.correct,
                icon: Icons.edit_note_outlined,
                enabled: hasSelectedEntry,
              ),
            if (lifecycle.actions.canVerify)
              const _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.verify,
                icon: Icons.verified_outlined,
                primary: true,
              ),
            if (lifecycle.actions.canFinalApprove)
              const _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.approveAndLock,
                icon: Icons.lock_outline,
                primary: true,
              ),
            if (lifecycle.actions.canRequestReopen)
              _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.requestReopen,
                icon: Icons.lock_open_outlined,
                enabled: hasSelectedEntry,
              ),
            if (lifecycle.actions.canAuthorizeReopen &&
                lifecycle.reopenRequests.any((item) => item.isPending))
              const _ReviewActionSpec(
                action: YorksWorkforceMonthlyReviewAction.authorizeReopen,
                icon: Icons.admin_panel_settings_outlined,
                primary: true,
              ),
          ];

    return _Panel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.approval_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('monthly_review_queue'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _t('monthly_review_queue_body'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (state.isBusy)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (errorKey != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ReviewMessage(
              color: state.status == YorksWorkforceReviewStatus.forbidden
                  ? AppColors.error
                  : AppColors.warning,
              icon: Icons.info_outline,
              message: _t(errorKey),
              onRetry: onRetry,
              retryLabel: _t('retry'),
            ),
          ],
          if (queue != null && queue.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: queue.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: AppSpacing.sm,
                        ),
                        child: OutlinedButton.icon(
                          key: Key('monthly-review-queue-${item.periodId}'),
                          onPressed: onQueueSelect == null
                              ? null
                              : () => onQueueSelect!(item.periodId),
                          icon: const Icon(Icons.groups_2_outlined),
                          label: Text(
                            '${item.teamName} · ${_monthLabel(item.periodMonth)}',
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ] else if (queue != null && lifecycle == null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _t('monthly_review_empty'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
          if (lifecycle != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusPill(
                  icon:
                      lifecycle.status ==
                          YorksWorkforceMonthlyPeriodStatus.locked
                      ? Icons.lock_outline
                      : Icons.pending_actions_outlined,
                  label: _t(_reviewStatusKey(lifecycle.status)),
                  color: _reviewStatusColor(lifecycle.status),
                ),
                _ReviewMeta(
                  label: _t('monthly_review_revision'),
                  value: '${lifecycle.approvalRevisionNumber}',
                ),
                if (lifecycle.approvedSnapshots.isNotEmpty)
                  _ReviewMeta(
                    label: _t('monthly_review_snapshot'),
                    value: lifecycle.approvedSnapshots.last.hash.substring(
                      0,
                      8,
                    ),
                  ),
              ],
            ),
            if (lifecycle.transitions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '${_t('monthly_review_timeline')}: '
                '${lifecycle.transitions.map((item) => item.action.replaceAll('_', ' ')).join('  •  ')}',
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (!allowActions)
              _ReviewMessage(
                color: AppColors.primary,
                icon: Icons.desktop_windows_outlined,
                message: _t('monthly_review_compact'),
              )
            else if (actions.isEmpty)
              Text(
                _t('monthly_review_no_action'),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: actions
                    .map(
                      (spec) => SizedBox(
                        height: 44,
                        child: spec.primary
                            ? FilledButton.icon(
                                key: Key('monthly-review-${spec.action.name}'),
                                onPressed: spec.enabled && onAction != null
                                    ? () => onAction!(spec.action)
                                    : null,
                                icon: Icon(spec.icon),
                                label: Text(_t(spec.action.labelKey)),
                              )
                            : OutlinedButton.icon(
                                key: Key('monthly-review-${spec.action.name}'),
                                onPressed: spec.enabled && onAction != null
                                    ? () => onAction!(spec.action)
                                    : null,
                                icon: Icon(spec.icon),
                                label: Text(_t(spec.action.labelKey)),
                              ),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ],
      ),
    );
  }
}

final class _ReviewActionSpec {
  const _ReviewActionSpec({
    required this.action,
    required this.icon,
    this.primary = false,
    this.enabled = true,
  });

  final YorksWorkforceMonthlyReviewAction action;
  final IconData icon;
  final bool primary;
  final bool enabled;
}

class _ReviewMeta extends StatelessWidget {
  const _ReviewMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Text('$label · $value'),
  );
}

class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.color,
    required this.icon,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final Color color;
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          if (onRetry != null)
            IconButton(
              tooltip: retryLabel,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    ),
  );
}

String _monthLabel(String value) =>
    value.length >= 7 ? value.substring(0, 7) : value;

String _reviewStatusKey(
  YorksWorkforceMonthlyPeriodStatus status,
) => switch (status) {
  YorksWorkforceMonthlyPeriodStatus.draft => 'monthly_status_draft',
  YorksWorkforceMonthlyPeriodStatus.readyForReview => 'monthly_status_ready',
  YorksWorkforceMonthlyPeriodStatus.submitted =>
    'monthly_review_status_submitted',
  YorksWorkforceMonthlyPeriodStatus.underReview =>
    'monthly_review_status_under_review',
  YorksWorkforceMonthlyPeriodStatus.returnedForCorrection =>
    'monthly_review_status_returned',
  YorksWorkforceMonthlyPeriodStatus.awaitingFinalApproval =>
    'monthly_review_status_awaiting',
  YorksWorkforceMonthlyPeriodStatus.locked => 'monthly_review_status_locked',
  YorksWorkforceMonthlyPeriodStatus.reopened =>
    'monthly_review_status_reopened',
};

Color _reviewStatusColor(
  YorksWorkforceMonthlyPeriodStatus status,
) => switch (status) {
  YorksWorkforceMonthlyPeriodStatus.locked => AppColors.success,
  YorksWorkforceMonthlyPeriodStatus.readyForReview => AppColors.success,
  YorksWorkforceMonthlyPeriodStatus.draft => AppColors.warning,
  YorksWorkforceMonthlyPeriodStatus.returnedForCorrection => AppColors.error,
  YorksWorkforceMonthlyPeriodStatus.awaitingFinalApproval => AppColors.warning,
  _ => AppColors.primary,
};

class _MonthlyHeader extends StatelessWidget {
  const _MonthlyHeader({
    required this.language,
    required this.state,
    required this.compact,
    required this.stacked,
    required this.onMonthChanged,
    required this.onTeamChanged,
    required this.onValidate,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final bool compact;
  final bool stacked;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<String> onTeamChanged;
  final VoidCallback? onValidate;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final teams = state.teamProjection?.teams ?? const [];
    final selected = teams.any((team) => team.id == state.selectedTeamId)
        ? state.selectedTeamId
        : null;
    final validateLabel = state.projection?.period == null
        ? _t('monthly_validate')
        : _t('monthly_revalidate');

    final controls = <Widget>[
      SizedBox(
        width: compact || stacked ? double.infinity : 280,
        child: DropdownButtonFormField<String>(
          key: const Key('monthly-team-selector'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _t('monthly_team'),
            prefixIcon: const Icon(Icons.groups_2_outlined),
          ),
          hint: Text(_t('monthly_select_team')),
          items: teams
              .map(
                (team) => DropdownMenuItem(
                  value: team.id,
                  child: Text(
                    '${team.code} · ${team.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: state.isBusy
              ? null
              : (value) {
                  if (value != null) onTeamChanged(value);
                },
        ),
      ),
      SizedBox(
        width: compact || stacked ? double.infinity : 210,
        child: Semantics(
          button: true,
          label: _t('monthly_select_month'),
          child: OutlinedButton.icon(
            key: const Key('monthly-month-selector'),
            onPressed: state.isBusy
                ? null
                : () => _pickMonth(context, state.periodMonth),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(_formatMonth(context, state.periodMonth)),
            ),
          ),
        ),
      ),
      if (!compact)
        FilledButton.icon(
          key: const Key('monthly-validate-button'),
          onPressed: onValidate,
          icon: state.status == YorksWorkforceMonthlyStatus.validating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Icon(Icons.fact_check_outlined),
          label: Text(validateLabel),
        ),
    ];

    return _Panel(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.calendar_view_month_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('monthly_timesheets'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _t('monthly_body'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (!compact && state.projection?.period != null)
                _PeriodStatusPill(
                  language: language,
                  period: state.projection!.period!,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (compact || stacked)
            Column(
              children: controls
                  .map(
                    (control) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: control,
                    ),
                  )
                  .toList(growable: false),
            )
          else
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: controls,
            ),
        ],
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context, String value) async {
    final parsed = DateTime.tryParse(value) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: _t('monthly_select_month'),
    );
    if (selected == null) return;
    onMonthChanged(
      '${selected.year.toString().padLeft(4, '0')}-'
      '${selected.month.toString().padLeft(2, '0')}-01',
    );
  }
}

class _MonthlyStateBanner extends StatelessWidget {
  const _MonthlyStateBanner({
    required this.language,
    required this.state,
    required this.compact,
    required this.onRetry,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final bool compact;
  final VoidCallback onRetry;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final Color container;
    late final IconData icon;
    String? title;
    String? body;
    var retry = false;

    switch (state.status) {
      case YorksWorkforceMonthlyStatus.forbidden:
      case YorksWorkforceMonthlyStatus.sessionExpired:
      case YorksWorkforceMonthlyStatus.unavailable:
        color = AppColors.error;
        container = AppColors.errorContainer;
        icon = Icons.lock_outline;
        title = _t('monthly_access_changed_title');
        body = _t('monthly_access_changed_body');
      case YorksWorkforceMonthlyStatus.offline:
        color = AppColors.warning;
        container = AppColors.warningContainer;
        icon = Icons.cloud_off_outlined;
        title = _t('monthly_online_required');
        body = _t('monthly_online_required_body');
      case YorksWorkforceMonthlyStatus.conflict:
        color = AppColors.warning;
        container = AppColors.warningContainer;
        icon = Icons.sync_problem_outlined;
        title = _t('monthly_validation_conflict_title');
        body = _t('monthly_validation_conflict_body');
        retry = true;
      case YorksWorkforceMonthlyStatus.uncertain:
        color = AppColors.warning;
        container = AppColors.warningContainer;
        icon = Icons.help_outline;
        title = _t('monthly_validation_uncertain_title');
        body = _t('monthly_validation_uncertain_body');
        retry = true;
      case YorksWorkforceMonthlyStatus.failure:
        color = AppColors.error;
        container = AppColors.errorContainer;
        icon = Icons.error_outline;
        title = _t('monthly_load_failed');
        body = _t('monthly_load_failed_body');
        retry = true;
      case YorksWorkforceMonthlyStatus.validated:
        color = AppColors.success;
        container = AppColors.successContainer;
        icon = Icons.verified_outlined;
        title = _t('monthly_validated');
      case YorksWorkforceMonthlyStatus.validating:
        color = AppColors.primary;
        container = AppColors.primaryContainer;
        icon = Icons.fact_check_outlined;
        title = _t('monthly_validating');
      case YorksWorkforceMonthlyStatus.idle:
      case YorksWorkforceMonthlyStatus.loading:
      case YorksWorkforceMonthlyStatus.ready:
        final period = state.projection?.period;
        if (period?.isStale == true) {
          color = AppColors.warning;
          container = AppColors.warningContainer;
          icon = Icons.update_outlined;
          title = _t('monthly_stale_title');
          body = _t('monthly_stale_body');
        } else if (compact && state.projection != null) {
          color = AppColors.primary;
          container = AppColors.primaryContainer;
          icon = Icons.visibility_outlined;
          title = _t('monthly_read_only_title');
          body = _t('monthly_read_only_body');
        } else {
          return const SizedBox.shrink();
        }
    }

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: container,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: const TextStyle(color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (retry)
              TextButton(onPressed: onRetry, child: Text(_t('monthly_retry'))),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeriodCard extends StatelessWidget {
  const _EmptyPeriodCard({
    required this.language,
    required this.canValidate,
    required this.compact,
    required this.onValidate,
  });

  final AppLanguage language;
  final bool canValidate;
  final bool compact;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 42,
            color: AppColors.muted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            YorksV1WorkforceStrings.text(language, 'monthly_absent_title'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            YorksV1WorkforceStrings.text(language, 'monthly_absent_body'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (!compact && canValidate) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onValidate,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                YorksV1WorkforceStrings.text(language, 'monthly_validate'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _MonthlySummaryGrid extends StatelessWidget {
  const _MonthlySummaryGrid({
    required this.language,
    required this.summary,
    required this.compact,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlySummary summary;
  final bool compact;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final metrics = <({String key, String value, IconData icon, Color color})>[
      (
        key: 'monthly_metric_workers',
        value: '${summary.workerCount}',
        icon: Icons.groups_2_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'monthly_metric_scheduled',
        value: '${summary.scheduledDayCount}',
        icon: Icons.event_available_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'monthly_metric_present',
        value: '${summary.presentDayCount}',
        icon: Icons.how_to_reg_outlined,
        color: AppColors.success,
      ),
      (
        key: 'monthly_metric_absent',
        value: '${summary.absentDayCount}',
        icon: Icons.person_off_outlined,
        color: AppColors.error,
      ),
      (
        key: 'monthly_metric_leave',
        value: '${summary.leaveDayCount}',
        icon: Icons.beach_access_outlined,
        color: AppColors.tertiary,
      ),
      (
        key: 'monthly_metric_missing',
        value: '${summary.missingDayCount}',
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'monthly_metric_regular',
        value: _minutes(language, summary.regularMinutes),
        icon: Icons.schedule_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'monthly_metric_overtime',
        value: _minutes(language, summary.overtimeMinutes),
        icon: Icons.more_time_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'monthly_metric_blocking',
        value: '${summary.blockingIssueCount}',
        icon: Icons.block_outlined,
        color: AppColors.error,
      ),
      (
        key: 'monthly_metric_warnings',
        value: '${summary.warningIssueCount}',
        icon: Icons.warning_amber_outlined,
        color: AppColors.warning,
      ),
      (
        key: 'monthly_metric_projects',
        value: '${summary.projectCount}',
        icon: Icons.business_outlined,
        color: AppColors.primary,
      ),
      (
        key: 'monthly_metric_locations',
        value: '${summary.locationCount}',
        icon: Icons.location_on_outlined,
        color: AppColors.tertiary,
      ),
    ];
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = compact
              ? 2
              : constraints.maxWidth >= 1120
              ? 6
              : 4;
          final gap = AppSpacing.md * (columns - 1);
          final width = (constraints.maxWidth - gap) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('monthly_summary'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _MetricTile(
                          label: _t(metric.key),
                          value: metric.value,
                          icon: metric.icon,
                          color: metric.color,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabletMonthlyBody extends StatelessWidget {
  const _TabletMonthlyBody({
    required this.language,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onWorkerChanged,
    required this.onLoadMoreWorkers,
    required this.onIssueFilter,
    required this.onLoadMoreIssues,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onWorkerChanged;
  final VoidCallback onLoadMoreWorkers;
  final void Function({
    YorksWorkforceMonthlyIssueSeverity? severity,
    String? issueCode,
    String? workerId,
  })
  onIssueFilter;
  final VoidCallback onLoadMoreIssues;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final issues = _IssueRail(
      language: language,
      state: state,
      onFilter: onIssueFilter,
      onLoadMore: onLoadMoreIssues,
    );
    final workers = _TabletMonthlyWorkerList(
      language: language,
      state: state,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      onWorkerChanged: onWorkerChanged,
      onLoadMoreWorkers: onLoadMoreWorkers,
      height: landscape ? 560 : 500,
    );
    if (!landscape) {
      return Column(
        key: const Key('workforce-tablet-monthly-portrait'),
        children: [
          issues,
          const SizedBox(height: AppSpacing.lg),
          workers,
        ],
      );
    }
    return Row(
      key: const Key('workforce-tablet-monthly-landscape'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: issues),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: workers),
      ],
    );
  }
}

class _TabletMonthlyWorkerList extends StatelessWidget {
  const _TabletMonthlyWorkerList({
    required this.language,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onWorkerChanged,
    required this.onLoadMoreWorkers,
    required this.height,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onWorkerChanged;
  final VoidCallback onLoadMoreWorkers;
  final double height;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final workers = state.projection?.workers ?? const [];
    final selectedWorkerId = state.workerDetail?.worker.workerId;
    final boundedHeight = math.min(
      height,
      math.max(
        240.0,
        126.0 + workers.length * 82.0 + (state.canLoadMore ? 61.0 : 0.0),
      ),
    );
    return KeyedSubtree(
      key: const Key('workforce-tablet-monthly-worker-list'),
      child: _Panel(
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: boundedHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('monthly_workers'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        hintText: _t('monthly_search_workers'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: workers.isEmpty
                    ? Center(
                        child: Text(
                          _t('monthly_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.separated(
                        key: const Key('workforce-tablet-monthly-workers'),
                        itemCount: workers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final worker = workers[index];
                          final selected = worker.workerId == selectedWorkerId;
                          return Semantics(
                            button: true,
                            selected: selected,
                            label:
                                '${worker.workerName}, ${worker.workerNumber}, ${_monthlyWorkerStatusLabel(language, worker.status)}',
                            child: Material(
                              color: selected
                                  ? AppColors.primaryContainer
                                  : AppColors.surfaceContainerLowest,
                              child: InkWell(
                                key: Key(
                                  'workforce-tablet-monthly-worker-${worker.workerId}',
                                ),
                                onTap: () => onWorkerChanged(worker.workerId),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 82,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.sm,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                worker.workerName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                '${worker.workerNumber} · ${worker.tradeName ?? '—'}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${worker.presentDayCount}/${worker.scheduledDayCount} · ${_minutes(language, worker.regularMinutes)} · ${worker.missingDayCount} ${_t('monthly_metric_missing')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        _WorkerStatusPill(
                                          language: language,
                                          status: worker.status,
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        const SizedBox.square(
                                          dimension: 44,
                                          child: Icon(
                                            Icons.chevron_right,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (state.canLoadMore) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: state.isBusy ? null : onLoadMoreWorkers,
                      icon: const Icon(Icons.expand_more),
                      label: Text(_t('monthly_load_more')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopMonthlyBody extends StatelessWidget {
  const _DesktopMonthlyBody({
    required this.language,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onWorkerChanged,
    required this.onLoadMoreWorkers,
    required this.onIssueFilter,
    required this.onLoadMoreIssues,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onWorkerChanged;
  final VoidCallback onLoadMoreWorkers;
  final void Function({
    YorksWorkforceMonthlyIssueSeverity? severity,
    String? issueCode,
    String? workerId,
  })
  onIssueFilter;
  final VoidCallback onLoadMoreIssues;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= 980;
      final workers = _WorkerSummaryTable(
        language: language,
        state: state,
        searchController: searchController,
        onSearchChanged: onSearchChanged,
        onWorkerChanged: onWorkerChanged,
        onLoadMore: onLoadMoreWorkers,
      );
      final issues = _IssueRail(
        language: language,
        state: state,
        onFilter: onIssueFilter,
        onLoadMore: onLoadMoreIssues,
      );
      if (!sideBySide) {
        return Column(
          children: [
            issues,
            const SizedBox(height: AppSpacing.lg),
            workers,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: workers),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(width: 330, child: issues),
        ],
      );
    },
  );
}

class _WorkerSummaryTable extends StatelessWidget {
  const _WorkerSummaryTable({
    required this.language,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
    required this.onWorkerChanged,
    required this.onLoadMore,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onWorkerChanged;
  final VoidCallback onLoadMore;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final workers = state.projection?.workers ?? const [];
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t('monthly_workers'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: _t('monthly_search_workers'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (workers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                _t('monthly_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            _HorizontalTableScroller(
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  AppColors.surfaceContainerLow,
                ),
                columns: [
                  DataColumn(label: Text(_t('monthly_worker_name'))),
                  DataColumn(label: Text(_t('monthly_worker_trade'))),
                  DataColumn(label: Text(_t('monthly_worker_scheduled'))),
                  DataColumn(label: Text(_t('monthly_worker_present'))),
                  DataColumn(label: Text(_t('monthly_worker_regular'))),
                  DataColumn(label: Text(_t('monthly_worker_overtime'))),
                  DataColumn(label: Text(_t('monthly_worker_missing'))),
                  DataColumn(label: Text(_t('monthly_worker_status'))),
                ],
                rows: workers
                    .map(
                      (worker) => DataRow(
                        onSelectChanged: (_) =>
                            onWorkerChanged(worker.workerId),
                        cells: [
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 190,
                                maxWidth: 260,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    worker.workerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    worker.workerNumber,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(Text(worker.tradeName ?? '—')),
                          DataCell(Text('${worker.scheduledDayCount}')),
                          DataCell(Text('${worker.presentDayCount}')),
                          DataCell(
                            Text(_minutes(language, worker.regularMinutes)),
                          ),
                          DataCell(
                            Text(_minutes(language, worker.overtimeMinutes)),
                          ),
                          DataCell(Text('${worker.missingDayCount}')),
                          DataCell(
                            _WorkerStatusPill(
                              language: language,
                              status: worker.status,
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          if (state.canLoadMore)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: state.isBusy ? null : onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: Text(_t('monthly_load_more')),
              ),
            ),
        ],
      ),
    );
  }
}

class _HorizontalTableScroller extends StatefulWidget {
  const _HorizontalTableScroller({required this.child});

  final Widget child;

  @override
  State<_HorizontalTableScroller> createState() =>
      _HorizontalTableScrollerState();
}

class _HorizontalTableScrollerState extends State<_HorizontalTableScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: widget.child,
    ),
  );
}

class _IssueRail extends StatelessWidget {
  const _IssueRail({
    required this.language,
    required this.state,
    required this.onFilter,
    required this.onLoadMore,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final void Function({
    YorksWorkforceMonthlyIssueSeverity? severity,
    String? issueCode,
    String? workerId,
  })
  onFilter;
  final VoidCallback onLoadMore;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final issueProjection = state.issueProjection;
    final counts = state.projection?.issueCounts ?? const [];
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const Icon(
                  Icons.rule_folder_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _t('monthly_issue_filters'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (issueProjection != null)
                  IconButton(
                    tooltip: _t('monthly_issue_clear_filters'),
                    onPressed: () => onFilter(),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (issueProjection == null)
            if (counts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  _t('monthly_issue_none'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              )
            else
              ...counts.map(
                (count) => _IssueCountButton(
                  language: language,
                  count: count,
                  onPressed: () => onFilter(
                    severity: count.severity,
                    issueCode: count.issueCode,
                  ),
                ),
              )
          else if (issueProjection.issues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                _t('monthly_issue_none'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else ...[
            ...issueProjection.issues.map(
              (issue) => _IssueListTile(
                language: language,
                issue: issue,
                onTap: issue.workerId == null
                    ? null
                    : () => onFilter(workerId: issue.workerId),
              ),
            ),
            if (state.canLoadMoreIssues)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: OutlinedButton(
                  onPressed: state.isBusy ? null : onLoadMore,
                  child: Text(_t('monthly_load_more')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompactMonthlyBody extends StatelessWidget {
  const _CompactMonthlyBody({
    required this.language,
    required this.state,
    required this.onWorkerChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.onLoadMore,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyState state;
  final ValueChanged<String> onWorkerChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final workers = state.projection?.workers ?? const [];
    return Column(
      children: [
        TextField(
          key: const Key('workforce-month-worker-search'),
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: YorksV1WorkforceStrings.text(
              language,
              'monthly_search_workers',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...workers.map(
          (worker) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _Panel(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: () => onWorkerChanged(worker.workerId),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  worker.workerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${worker.workerNumber} · ${worker.tradeName ?? '—'}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _WorkerStatusPill(
                            language: language,
                            status: worker.status,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _InlineFact(
                            icon: Icons.event_available_outlined,
                            value:
                                '${worker.presentDayCount}/${worker.scheduledDayCount}',
                          ),
                          _InlineFact(
                            icon: Icons.schedule_outlined,
                            value: _minutes(language, worker.regularMinutes),
                          ),
                          _InlineFact(
                            icon: Icons.more_time_outlined,
                            value: _minutes(language, worker.overtimeMinutes),
                          ),
                          _InlineFact(
                            icon: Icons.pending_actions_outlined,
                            value: '${worker.missingDayCount}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (state.canLoadMore)
          OutlinedButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more),
            label: Text(YorksV1WorkforceStrings.text(language, 'load_more')),
          ),
      ],
    );
  }
}

class _WorkerMonthDetail extends StatelessWidget {
  const _WorkerMonthDetail({
    required this.language,
    required this.detail,
    required this.selectedDate,
    required this.compact,
    required this.onClose,
    required this.onDateChanged,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyWorkerDetail detail;
  final String? selectedDate;
  final bool compact;
  final VoidCallback onClose;
  final ValueChanged<String> onDateChanged;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    YorksWorkforceMonthlyDay? selected;
    for (final day in detail.days) {
      if (day.workDate == selectedDate) selected = day;
    }
    selected ??= detail.days.firstOrNull;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.worker.workerName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${detail.worker.workerNumber} · ${detail.worker.tradeName ?? '—'}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t('monthly_close'),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = <Widget>[
                _WorkerMetricChip(
                  icon: Icons.schedule_outlined,
                  label: _t('monthly_metric_regular'),
                  value: _minutes(language, detail.worker.regularMinutes),
                  color: AppColors.primary,
                ),
                _WorkerMetricChip(
                  icon: Icons.more_time_outlined,
                  label: _t('monthly_metric_overtime'),
                  value: _minutes(language, detail.worker.overtimeMinutes),
                  color: AppColors.warning,
                ),
                _WorkerMetricChip(
                  icon: Icons.medical_services_outlined,
                  label: _t('monthly_metric_leave'),
                  value: '${detail.worker.leaveDayCount}',
                  color: AppColors.success,
                ),
                _WorkerMetricChip(
                  icon: Icons.event_busy_outlined,
                  label: _t('monthly_metric_weekly_off'),
                  value: '${detail.worker.weeklyOffDayCount}',
                  color: AppColors.purple,
                ),
              ];
              if (MediaQuery.sizeOf(context).width <
                  AppSpacing.compactBreakpoint) {
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: (constraints.maxWidth - AppSpacing.sm) / 2,
                        child: metric,
                      ),
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: metrics,
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _t('monthly_calendar'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (compact &&
              MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint)
            Column(
              key: const Key('workforce-worker-month-day-list'),
              children: [
                for (final day in detail.days)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Material(
                      color: selected?.workDate == day.workDate
                          ? AppColors.blueContainer
                          : AppColors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        side: const BorderSide(color: AppColors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: Key('workforce-month-day-${day.workDate}'),
                        onTap: () => onDateChanged(day.workDate),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                day.workDate,
                                style: AppTypography.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(_monthlyAttendanceLabel(language, day)),
                              Wrap(
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  Text(
                                    '${_t('regular_hours')}: ${_minutes(language, day.regularMinutes)}',
                                  ),
                                  Text(
                                    '${_t('overtime_hours')}: ${_minutes(language, day.overtimeMinutes)}',
                                  ),
                                ],
                              ),
                              Text(
                                _monthlyTargetLabel(day),
                                style: AppTypography.bodySmall,
                              ),
                              if (selected?.workDate == day.workDate) ...[
                                const Divider(),
                                _DayFacts(
                                  language: language,
                                  day: day,
                                  compact: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else if (compact)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final day in detail.days)
                  _CalendarDayButton(
                    language: language,
                    day: day,
                    selected: selected?.workDate == day.workDate,
                    onPressed: () => onDateChanged(day.workDate),
                  ),
              ],
            )
          else
            _WorkerDayTable(
              language: language,
              days: detail.days,
              selectedDate: selected?.workDate,
              onDateChanged: onDateChanged,
            ),
          if (selected != null &&
              (!compact ||
                  MediaQuery.sizeOf(context).width >=
                      AppSpacing.compactBreakpoint)) ...[
            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${_t('monthly_day_detail')} · ${selected.workDate}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            _DayFacts(language: language, day: selected, compact: compact),
          ],
        ],
      ),
    );
  }
}

class _WorkerMetricChip extends StatelessWidget {
  const _WorkerMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: color.withValues(alpha: .24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.labelSmall),
              Text(
                value,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WorkerDayTable extends StatelessWidget {
  const _WorkerDayTable({
    required this.language,
    required this.days,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final AppLanguage language;
  final List<YorksWorkforceMonthlyDay> days;
  final String? selectedDate;
  final ValueChanged<String> onDateChanged;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) => _HorizontalTableScroller(
    child: DataTable(
      headingRowColor: const WidgetStatePropertyAll(
        AppColors.surfaceContainerLow,
      ),
      columns: [
        DataColumn(label: Text(_t('date'))),
        DataColumn(label: Text(_t('status'))),
        DataColumn(label: Text(_t('regular'))),
        DataColumn(label: Text(_t('overtime'))),
        DataColumn(label: Text(_t('target'))),
        DataColumn(label: Text(_t('supervisor'))),
        DataColumn(label: Text(_t('monthly_worker_issues'))),
      ],
      rows: days
          .map(
            (day) => DataRow(
              selected: selectedDate == day.workDate,
              onSelectChanged: (_) => onDateChanged(day.workDate),
              cells: [
                DataCell(Text(day.workDate.substring(8))),
                DataCell(
                  _StatusPill(
                    icon: _dailyIcon(day.dailyStatus),
                    label: _monthlyAttendanceLabel(language, day),
                    color: _dailyColor(day.dailyStatus),
                  ),
                ),
                DataCell(Text(_minutes(language, day.regularMinutes))),
                DataCell(Text(_minutes(language, day.overtimeMinutes))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 190,
                      maxWidth: 260,
                    ),
                    child: Text(
                      _monthlyTargetLabel(day),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(day.assignment['supervisor_name'] as String? ?? '—'),
                ),
                DataCell(
                  Text('${day.blockingIssueCount + day.warningIssueCount}'),
                ),
              ],
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _DayFacts extends StatelessWidget {
  const _DayFacts({
    required this.language,
    required this.day,
    required this.compact,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyDay day;
  final bool compact;

  String _t(String key) => YorksV1WorkforceStrings.text(language, key);

  @override
  Widget build(BuildContext context) {
    final facts = [
      (
        _t('monthly_day_type'),
        day.dayType == null ? '—' : _dayTypeLabel(language, day.dayType!),
      ),
      (_t('monthly_day_scheduled'), _minutes(language, day.scheduledMinutes)),
      (_t('monthly_day_regular'), _minutes(language, day.regularMinutes)),
      (_t('monthly_day_overtime'), _minutes(language, day.overtimeMinutes)),
      (_t('monthly_day_allocation'), _minutes(language, day.allocationMinutes)),
      (
        _t('monthly_worker_issues'),
        '${day.blockingIssueCount + day.warningIssueCount}',
      ),
    ];
    if (compact &&
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint) {
      return Column(
        children: [
          for (final fact in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(fact.$1, style: AppTypography.bodySmall),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(fact.$2, style: AppTypography.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: facts
          .map(
            (fact) => SizedBox(
              width: compact ? 145 : 190,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fact.$1,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      fact.$2,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CalendarDayButton extends StatelessWidget {
  const _CalendarDayButton({
    required this.language,
    required this.day,
    required this.selected,
    required this.onPressed,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyDay day;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _dailyColor(day.dailyStatus);
    final number = int.tryParse(day.workDate.substring(8)) ?? 0;
    return Semantics(
      button: true,
      selected: selected,
      label: '${day.workDate}, ${_dailyStatusLabel(language, day.dailyStatus)}',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryContainer
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : color.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$number',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Icon(_dailyIcon(day.dailyStatus), size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodStatusPill extends StatelessWidget {
  const _PeriodStatusPill({required this.language, required this.period});

  final AppLanguage language;
  final YorksWorkforceMonthlyPeriod period;

  @override
  Widget build(BuildContext context) {
    final status = period.effectiveStatus;
    final label = YorksV1WorkforceStrings.text(
      language,
      _reviewStatusKey(status),
    );
    return _StatusPill(
      icon: status == YorksWorkforceMonthlyPeriodStatus.locked
          ? Icons.lock_outline
          : status == YorksWorkforceMonthlyPeriodStatus.readyForReview
          ? Icons.check_circle_outline
          : status == YorksWorkforceMonthlyPeriodStatus.draft
          ? Icons.edit_note_outlined
          : Icons.pending_actions_outlined,
      label: label,
      color: _reviewStatusColor(status),
    );
  }
}

class _WorkerStatusPill extends StatelessWidget {
  const _WorkerStatusPill({required this.language, required this.status});

  final AppLanguage language;
  final YorksWorkforceMonthlyWorkerStatus status;

  @override
  Widget build(BuildContext context) {
    final (key, icon, color) = switch (status) {
      YorksWorkforceMonthlyWorkerStatus.complete => (
        'monthly_worker_status_complete',
        Icons.check_circle_outline,
        AppColors.success,
      ),
      YorksWorkforceMonthlyWorkerStatus.hasWarnings => (
        'monthly_worker_status_warnings',
        Icons.warning_amber_outlined,
        AppColors.warning,
      ),
      YorksWorkforceMonthlyWorkerStatus.hasErrors => (
        'monthly_worker_status_errors',
        Icons.error_outline,
        AppColors.error,
      ),
    };
    return _StatusPill(
      icon: icon,
      label: YorksV1WorkforceStrings.text(language, key),
      color: color,
    );
  }
}

String _monthlyWorkerStatusLabel(
  AppLanguage language,
  YorksWorkforceMonthlyWorkerStatus status,
) => YorksV1WorkforceStrings.text(language, switch (status) {
  YorksWorkforceMonthlyWorkerStatus.complete =>
    'monthly_worker_status_complete',
  YorksWorkforceMonthlyWorkerStatus.hasWarnings =>
    'monthly_worker_status_warnings',
  YorksWorkforceMonthlyWorkerStatus.hasErrors => 'monthly_worker_status_errors',
});

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      border: Border.all(color: color.withValues(alpha: 0.24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _IssueCountButton extends StatelessWidget {
  const _IssueCountButton({
    required this.language,
    required this.count,
    required this.onPressed,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyIssueCount count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final blocking =
        count.severity == YorksWorkforceMonthlyIssueSeverity.blocking;
    final color = blocking ? AppColors.error : AppColors.warning;
    return InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                blocking ? Icons.error_outline : Icons.warning_amber_outlined,
                color: color,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _issueLabel(language, count.issueCode),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  '${count.count}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueListTile extends StatelessWidget {
  const _IssueListTile({
    required this.language,
    required this.issue,
    required this.onTap,
  });

  final AppLanguage language;
  final YorksWorkforceMonthlyIssue issue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final blocking =
        issue.severity == YorksWorkforceMonthlyIssueSeverity.blocking;
    final color = blocking ? AppColors.error : AppColors.warning;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              blocking ? Icons.error_outline : Icons.warning_amber_outlined,
              color: color,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _issueLabel(language, issue.issueCode),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (issue.workerName != null || issue.workDate != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        issue.workerName,
                        issue.workDate,
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 86),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: AppColors.muted),
      const SizedBox(width: AppSpacing.xs),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _MonthlySkeleton extends StatelessWidget {
  const _MonthlySkeleton();

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ),
    ),
  );
}

String _formatMonth(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? value
      : MaterialLocalizations.of(context).formatMonthYear(parsed);
}

String _minutes(AppLanguage language, int value) {
  final hours = value ~/ 60;
  final minutes = value.remainder(60);
  final hoursUnit = YorksV1WorkforceStrings.text(language, 'hours');
  if (minutes == 0) return '$hours $hoursUnit';
  final minutesUnit = YorksV1WorkforceStrings.text(language, 'minutes');
  return '$hours $hoursUnit ${minutes.toString().padLeft(2, '0')} '
      '$minutesUnit';
}

String _monthlyAttendanceLabel(
  AppLanguage language,
  YorksWorkforceMonthlyDay day,
) {
  final status = day.attendance?['attendance_status'];
  if (status is String && status.isNotEmpty) {
    return YorksV1WorkforceStrings.text(language, status);
  }
  if (day.isRequired && !day.isFuture) {
    return YorksV1WorkforceStrings.text(language, 'not_entered');
  }
  if (day.dayType != null) return _dayTypeLabel(language, day.dayType!);
  return _dailyStatusLabel(language, day.dailyStatus);
}

String _monthlyTargetLabel(YorksWorkforceMonthlyDay day) {
  final targets = day.allocation?['targets'];
  if (targets is List) {
    final labels = targets
        .whereType<Map>()
        .map((target) {
          final kind = target['target_kind'];
          if (kind == 'project_work') {
            return [target['project_ref'], target['project_scope_name']]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' · ');
          }
          return target['internal_location_name'] as String? ?? '';
        })
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (labels.isNotEmpty) return labels.join(' + ');
  }
  final project = [
    day.assignment['project_ref'],
    day.assignment['project_scope_name'],
  ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
  if (project.isNotEmpty) return project;
  return day.assignment['internal_location_name'] as String? ?? '—';
}

String _issueLabel(AppLanguage language, String code) =>
    YorksV1WorkforceStrings.text(language, 'monthly_issue_$code');

String _dayTypeLabel(AppLanguage language, String dayType) =>
    YorksV1WorkforceStrings.text(language, 'monthly_day_type_$dayType');

String _dailyStatusLabel(
  AppLanguage language,
  YorksWorkforceMonthlyDailyStatus status,
) => YorksV1WorkforceStrings.text(language, switch (status) {
  YorksWorkforceMonthlyDailyStatus.future => 'monthly_day_status_future',
  YorksWorkforceMonthlyDailyStatus.notStarted =>
    'monthly_day_status_not_started',
  YorksWorkforceMonthlyDailyStatus.complete => 'monthly_day_status_complete',
  YorksWorkforceMonthlyDailyStatus.hasWarnings => 'monthly_day_status_warnings',
  YorksWorkforceMonthlyDailyStatus.hasErrors => 'monthly_day_status_errors',
});

Color _dailyColor(YorksWorkforceMonthlyDailyStatus status) => switch (status) {
  YorksWorkforceMonthlyDailyStatus.complete => AppColors.success,
  YorksWorkforceMonthlyDailyStatus.hasWarnings => AppColors.warning,
  YorksWorkforceMonthlyDailyStatus.hasErrors => AppColors.error,
  YorksWorkforceMonthlyDailyStatus.future => AppColors.muted,
  YorksWorkforceMonthlyDailyStatus.notStarted => AppColors.primary,
};

IconData _dailyIcon(YorksWorkforceMonthlyDailyStatus status) =>
    switch (status) {
      YorksWorkforceMonthlyDailyStatus.complete => Icons.check,
      YorksWorkforceMonthlyDailyStatus.hasWarnings => Icons.priority_high,
      YorksWorkforceMonthlyDailyStatus.hasErrors => Icons.close,
      YorksWorkforceMonthlyDailyStatus.future => Icons.schedule,
      YorksWorkforceMonthlyDailyStatus.notStarted => Icons.more_horiz,
    };
