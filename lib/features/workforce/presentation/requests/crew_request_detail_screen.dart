/// Crew requests — one request, laid out like a Company Material Request:
/// number with state and stage, the actions the server allows, who has it
/// and the next step, the people asked and assigned, progress and history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart'
    show AS, attendanceLanguage, attendanceStamp, attendanceToast;
import '../attendance/attendance_dialogs.dart';
import 'crew_request_common.dart';
import 'crew_request_kit.dart';

class CrewRequestDetailScreen extends ConsumerWidget {
  const CrewRequestDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
    final request = ref.watch(yorksCrewRequestProvider(requestId));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: request.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => CrMessage(
          icon: Icons.cloud_off_outlined,
          message: crewRequestErrorText(error, language),
          action: AS.t(AS.retry, language),
          onPressed: () => ref.invalidate(yorksCrewRequestProvider(requestId)),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(yorksCrewRequestProvider(requestId));
            ref.invalidate(yorksCrewRequestsProvider);
          },
          child: _Detail(request: data, language: language),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.request, required this.language});

  final CrewRequest request;
  final AppLanguage language;

  void _refresh(WidgetRef ref) {
    ref.invalidate(yorksCrewRequestProvider(request.id));
    ref.invalidate(yorksCrewRequestsProvider);
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String decision,
  ) async {
    final repository = ref.read(yorksAttendanceRepositoryProvider);
    final key = YorksAttendanceRepository.newKey();
    final values = {'number': request.number};
    final (title, body, confirm, needsReason, destructive) = switch (decision) {
      'approve' => (
        CRS.approveTitle,
        CRS.approveBody,
        CRS.approve,
        false,
        false,
      ),
      'return' => (
        CRS.returnTitle,
        CRS.returnBody,
        CRS.returnAction,
        true,
        false,
      ),
      _ => (CRS.rejectTitle, CRS.rejectBody, CRS.reject, true, true),
    };
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: CRS.t(title, language, values),
      body: CRS.t(body, language),
      summary:
          '${crewRequestWhere(request, language)} · ${crewRequestPeople(request)}',
      confirmLabel: CRS.t(confirm, language),
      fieldLabel: needsReason ? CRS.t(CRS.reasonLabel, language) : null,
      destructive: destructive,
      command: (text) async {
        try {
          await repository.decideRequest(
            requestId: request.id,
            decision: decision,
            reason: needsReason ? text : null,
            expectedVersion: request.recordVersion,
            idempotencyKey: key,
          );
          return null;
        } catch (error) {
          return crewRequestErrorText(error, language);
        }
      },
    );
    if (done == null || !context.mounted) return;
    _refresh(ref);
    attendanceToast(context, switch (decision) {
      'approve' => CRS.t(CRS.approvedToast, language),
      'return' => CRS.t(CRS.returnedToast, language, {
        'name': request.requestedBy.name,
      }),
      _ => CRS.t(CRS.rejectedToast, language),
    });
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(yorksAttendanceRepositoryProvider);
    final key = YorksAttendanceRepository.newKey();
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: CRS.t(CRS.cancelTitle, language, {'number': request.number}),
      body: CRS.t(CRS.cancelBody, language),
      confirmLabel: CRS.t(CRS.cancelRequest, language),
      fieldLabel: CRS.t(CRS.reasonOptional, language),
      fieldOptional: true,
      destructive: true,
      command: (text) async {
        try {
          await repository.cancelRequest(
            requestId: request.id,
            reason: text,
            expectedVersion: request.recordVersion,
            idempotencyKey: key,
          );
          return null;
        } catch (error) {
          return crewRequestErrorText(error, language);
        }
      },
    );
    if (done == null || !context.mounted) return;
    _refresh(ref);
    attendanceToast(context, CRS.t(CRS.cancelledToast, language));
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(yorksAttendanceRepositoryProvider);
    final key = YorksAttendanceRepository.newKey();
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: CRS.t(CRS.closeTitle, language, {'number': request.number}),
      body: CRS.t(CRS.closeBody, language),
      confirmLabel: CRS.t(CRS.closeRemaining, language),
      fieldLabel: CRS.t(CRS.reasonLabel, language),
      command: (text) async {
        try {
          await repository.closeRequest(
            requestId: request.id,
            reason: text,
            expectedVersion: request.recordVersion,
            idempotencyKey: key,
          );
          return null;
        } catch (error) {
          return crewRequestErrorText(error, language);
        }
      },
    );
    if (done == null || !context.mounted) return;
    _refresh(ref);
    attendanceToast(context, CRS.t(CRS.closedToast, language));
  }

  void _showInformation(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Material(
          color: AppColors.surfaceContainerLowest,
          child: SafeArea(
            child: SizedBox(
              width: MediaQuery.sizeOf(
                dialogContext,
              ).width.clamp(0, 440).toDouble(),
              height: double.infinity,
              child: ListView(
                key: const ValueKey('crew-request-information'),
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          CRS.t(CRS.info, language),
                          style: AppTypography.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          dialogContext,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Divider(),
                  CrFact(
                    label: CRS.t(CRS.factProject, language),
                    value: crewRequestWhere(request, language),
                  ),
                  if (request.workLabel != null)
                    CrFact(
                      label: CRS.t(CRS.factWork, language),
                      value: request.workLabel!,
                    ),
                  CrFact(
                    label: CRS.t(CRS.factNeeded, language),
                    value: crewRequestDates(request, language),
                  ),
                  if (request.targetCrewName != null)
                    CrFact(
                      label: CRS.t(CRS.factCrew, language),
                      value: request.targetCrewName!,
                    ),
                  CrFact(
                    label: CRS.t(CRS.factRequestedBy, language),
                    value: CRS.t(CRS.byRoleAt, language, {
                      'name': request.requestedBy.name,
                      'role': crewRequestRole(
                        request.requestedBy.role,
                        language,
                      ),
                      'at': attendanceStamp(request.submittedAt),
                    }),
                  ),
                  if (request.decidedBy != null)
                    CrFact(
                      label: CRS.t(CRS.factDecidedBy, language),
                      value: CRS.t(CRS.byRoleAt, language, {
                        'name': request.decidedBy!.name,
                        'role': crewRequestRole(
                          request.decidedBy!.role,
                          language,
                        ),
                        'at': attendanceStamp(request.decidedAt),
                      }),
                    ),
                  if (request.notes != null)
                    CrFact(
                      label: CRS.t(CRS.factNotes, language),
                      value: request.notes!,
                    ),
                  const Divider(),
                  CrFact(
                    label: CRS.t(CRS.withLabel, language),
                    value: crewRequestOwnerLabel(request, language),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Progress(request: request, language: language),
                ],
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }

  String _eventTitle(CrewRequestEvent event) {
    final values = {
      'name': event.actorName,
      'n': event.detail['added'] ?? 0,
      'crew': event.detail['crew_name'] ?? '',
    };
    final template = switch (event.type) {
      'submitted' => CRS.evSubmitted,
      'resubmitted' => CRS.evResubmitted,
      'approved' when event.detail['approved_on_submit'] == true =>
        CRS.evApprovedOnSubmit,
      'approved' => CRS.evApproved,
      'returned' => CRS.evReturned,
      'rejected' => CRS.evRejected,
      'cancelled' => CRS.evCancelled,
      'workers_assigned' when (event.detail['added'] ?? 0) == 0 =>
        CRS.evDecisions,
      'workers_assigned' => CRS.evAssigned,
      _ => CRS.evClosed,
    };
    return CRS.t(template, language, values);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = request.access;
    final stage = crewRequestStage(request.state);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final actions = <Widget>[
      if (access.decide) ...[
        FilledButton.icon(
          key: const ValueKey('crew-request-approve'),
          onPressed: () => _decide(context, ref, 'approve'),
          icon: const Icon(Icons.check_rounded),
          label: Text(CRS.t(CRS.approve, language)),
        ),
        OutlinedButton(
          key: const ValueKey('crew-request-return'),
          onPressed: () => _decide(context, ref, 'return'),
          child: Text(CRS.t(CRS.returnAction, language)),
        ),
        TextButton(
          key: const ValueKey('crew-request-reject'),
          onPressed: () => _decide(context, ref, 'reject'),
          child: Text(CRS.t(CRS.reject, language)),
        ),
      ],
      if (access.fulfil) ...[
        FilledButton.icon(
          key: const ValueKey('crew-request-assign'),
          onPressed: () => context.go(crewRequestAssignPath(request.id)),
          icon: const Icon(Icons.group_add_outlined),
          label: Text(CRS.t(CRS.assignWorkers, language)),
        ),
        OutlinedButton(
          key: const ValueKey('crew-request-close'),
          onPressed: () => _close(context, ref),
          child: Text(CRS.t(CRS.closeRemaining, language)),
        ),
      ],
      if (access.resubmit)
        FilledButton.icon(
          key: const ValueKey('crew-request-fix'),
          onPressed: () => context.go(crewRequestFixPath(request.id)),
          icon: const Icon(Icons.edit_outlined),
          label: Text(CRS.t(CRS.fixResubmit, language)),
        ),
      if (access.cancel)
        TextButton(
          key: const ValueKey('crew-request-cancel'),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => _cancel(context, ref),
          child: Text(CRS.t(CRS.cancelRequest, language)),
        ),
    ];
    final mine = access.mine;
    final finished = !request.state.isOpen;
    return ListView(
      key: const ValueKey('crew-request-detail'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('crew-request-back'),
                    onPressed: () =>
                        context.go(RoutePaths.yorksV1WorkforceRequests),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(CRS.t(CRS.registerTitle, language)),
                  ),
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final badges = Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          request.number,
                          style: AppTypography.headlineSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        CrPill(
                          icon: request.isWorkshop
                              ? Icons.handyman_outlined
                              : Icons.groups_outlined,
                          label: request.isWorkshop
                              ? CRS.t(CRS.workshop, language)
                              : CRS.t(CRS.eyebrow, language),
                          color: AppColors.inkSecondary,
                          background: AppColors.surfaceContainerLow,
                        ),
                        CrStatePill(request: request, language: language),
                        CrPill(
                          label: CRS.t(CRS.stageOf, language, {
                            'a': stage + 1,
                            'b': 4,
                          }),
                          color: AppColors.success,
                          background: AppColors.successContainer,
                        ),
                        if (request.overdue)
                          CrPill(
                            icon: Icons.warning_amber_rounded,
                            label: CRS.t(CRS.neededNow, language),
                            color: AppColors.error,
                            background: AppColors.errorContainer,
                          ),
                      ],
                    );
                    final info = OutlinedButton.icon(
                      key: const ValueKey('crew-request-information-toggle'),
                      onPressed: () => _showInformation(context),
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text(CRS.t(CRS.info, language)),
                    );
                    return wide
                        ? Row(
                            children: [
                              Expanded(child: badges),
                              const SizedBox(width: 12),
                              info,
                            ],
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [badges, info],
                          );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  crewRequestPeople(request),
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    crewRequestWhere(request, language),
                    if (request.workLabel != null) request.workLabel!,
                    crewRequestDates(request, language),
                  ].join(' · '),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: wide
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Wrap(
                      key: const ValueKey('crew-request-primary-actions'),
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ),
                ],
                if (request.decisionReason != null &&
                    (request.state == CrewRequestState.returned ||
                        request.state == CrewRequestState.rejected)) ...[
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    color: AppColors.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.undo_rounded,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              '${request.decidedBy?.name ?? ''}: “${request.decisionReason}”',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  key: const ValueKey('crew-request-owner'),
                  margin: EdgeInsets.zero,
                  color: finished
                      ? AppColors.successContainer
                      : AppColors.blueContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          finished
                              ? Icons.verified_rounded
                              : Icons.timeline_rounded,
                          color: finished ? AppColors.success : AppColors.blue,
                          size: 30,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                crewRequestNextStep(request, language),
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: mine ? AppColors.blue : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                CRS.t(CRS.currentOwner, language, {
                                  'name': crewRequestOwnerLabel(
                                    request,
                                    language,
                                  ),
                                }),
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _PeopleCard(request: request, language: language),
                const SizedBox(height: 12),
                _Progress(request: request, language: language),
                const SizedBox(height: 12),
                Card(
                  key: const ValueKey('crew-request-history'),
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    initiallyExpanded: wide,
                    title: Text(CRS.t(CRS.historyTitle, language)),
                    children: [
                      for (final event in request.events.reversed)
                        ListTile(
                          title: Text(_eventTitle(event)),
                          subtitle: Text(
                            [
                              crewRequestRole(event.actorRole, language),
                              attendanceStamp(event.at),
                              if (event.reason != null) '“${event.reason}”',
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({required this.request, required this.language});

  final CrewRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('crew-request-lines'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  CRS.t(CRS.linesTitle, language),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                CRS.t(CRS.assignedOf, language, {
                  'a': request.assignedCount,
                  'b': request.requestedCount,
                }),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final line in request.lines)
            Container(
              key: ValueKey('crew-request-line-${line.id}'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.blueContainer,
                    child: Text(
                      '${line.lineNumber}',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.trade,
                                style: AppTypography.titleSmall,
                              ),
                            ),
                            Text(
                              '${line.assigned.length} / ${line.quantity}',
                              style: AppTypography.labelLarge.copyWith(
                                color: line.short == 0
                                    ? AppColors.success
                                    : AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                        if (line.note != null)
                          Text(
                            line.note!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (line.assigned.isEmpty)
                          Text(
                            CRS.t(CRS.noOneYet, language),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.muted,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final person in line.assigned)
                                CrPill(
                                  icon: Icons.person_outline_rounded,
                                  label: '${person.name} · ${person.crewName}',
                                  color: AppColors.success,
                                  background: AppColors.successContainer,
                                ),
                            ],
                          ),
                        if (line.decision != null &&
                            line.decision != CrewRequestLineDecision.full) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${CRS.t(line.decision == CrewRequestLineDecision.partial ? CRS.decisionPartial : CRS.decisionCannot, language)}'
                            '${line.decisionReason == null ? '' : ' · “${line.decisionReason}”'}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.request, required this.language});

  final CrewRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final active = crewRequestStage(request.state);
    final labels = [
      CRS.t(CRS.stageRequested, language),
      CRS.t(CRS.stageApproval, language),
      CRS.t(CRS.stageAssigning, language),
      CRS.t(CRS.stageDone, language),
    ];
    return Card(
      key: const ValueKey('crew-request-progress'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CRS.t(CRS.progressTitle, language),
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              crewRequestStateChip(request.state, language).text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < labels.length; index++)
                  Chip(
                    avatar: Icon(
                      index < active ||
                              (index == active && !request.state.isOpen)
                          ? Icons.check_circle_rounded
                          : index == active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: index <= active ? AppColors.blue : AppColors.muted,
                    ),
                    label: Text(labels[index]),
                    backgroundColor: index == active
                        ? AppColors.blueContainer
                        : AppColors.surfaceContainerLow,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
