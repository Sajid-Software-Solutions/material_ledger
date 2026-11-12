/// Workforce Center — one crew request: its state, who has it now and the
/// next step, the people asked for and assigned, and its history. The
/// actions shown are exactly the ones the server allows the signed-in person.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart';
import '../attendance/attendance_dialogs.dart';
import 'crew_request_common.dart';

class CrewRequestDetailScreen extends ConsumerWidget {
  const CrewRequestDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
    final request = ref.watch(yorksCrewRequestProvider(requestId));
    return request.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(yorksCrewRequestProvider(requestId)),
      ),
      data: (data) => _DetailBody(request: data, language: language),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.request, required this.language});

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
        if (needsReason && text.trim().isEmpty) {
          return CRS.t(CRS.errReasonMissing, language);
        }
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
        if (text.trim().isEmpty) return CRS.t(CRS.errReasonMissing, language);
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
    final chip = crewRequestStateChip(request.state, language);
    final phone = AccountsV2Breakpoints.isPhone(context);
    final actions = <Widget>[
      if (access.decide) ...[
        AccountsV2Button(
          key: const ValueKey('crew-request-approve'),
          label: CRS.t(CRS.approve, language),
          icon: 'check',
          kind: AccountsV2ButtonKind.primary,
          onPressed: () => _decide(context, ref, 'approve'),
        ),
        AccountsV2Button(
          key: const ValueKey('crew-request-return'),
          label: CRS.t(CRS.returnAction, language),
          icon: 'undo',
          onPressed: () => _decide(context, ref, 'return'),
        ),
        AccountsV2Button(
          key: const ValueKey('crew-request-reject'),
          label: CRS.t(CRS.reject, language),
          kind: AccountsV2ButtonKind.ghostDanger,
          onPressed: () => _decide(context, ref, 'reject'),
        ),
      ],
      if (access.fulfil) ...[
        AccountsV2Button(
          key: const ValueKey('crew-request-assign'),
          label: CRS.t(CRS.assignWorkers, language),
          icon: 'users',
          kind: AccountsV2ButtonKind.primary,
          onPressed: () => context.go(crewRequestAssignPath(request.id)),
        ),
        AccountsV2Button(
          key: const ValueKey('crew-request-close'),
          label: CRS.t(CRS.closeRemaining, language),
          onPressed: () => _close(context, ref),
        ),
      ],
      if (access.resubmit)
        AccountsV2Button(
          key: const ValueKey('crew-request-fix'),
          label: CRS.t(CRS.fixResubmit, language),
          icon: 'edit',
          kind: AccountsV2ButtonKind.primary,
          onPressed: () => context.go(crewRequestFixPath(request.id)),
        ),
      if (access.cancel)
        AccountsV2Button(
          key: const ValueKey('crew-request-cancel'),
          label: CRS.t(CRS.cancelRequest, language),
          kind: AccountsV2ButtonKind.ghostDanger,
          onPressed: () => _cancel(context, ref),
        ),
    ];

    final decided = request.decidedBy;
    return AttendancePage(
      language: language,
      eyebrow: CRS.t(CRS.back, language),
      title: request.number,
      subtitle:
          '${crewRequestWhere(request, language)} · ${crewRequestDates(request, language)}',
      readOnly: actions.isEmpty && request.state.isOpen,
      onRefresh: () async => _refresh(ref),
      actions: [
        AccountsV2Button(
          key: const ValueKey('crew-request-back'),
          label: CRS.t(CRS.back, language),
          icon: 'undo',
          kind: AccountsV2ButtonKind.ghost,
          onPressed: () => context.go(
            Uri(
              path: RoutePaths.yorksV1Workforce,
              queryParameters: {'view': 'requests'},
            ).toString(),
          ),
        ),
        if (!phone) ...actions,
      ],
      children: [
        if (request.decisionReason != null &&
            (request.state == CrewRequestState.returned ||
                request.state == CrewRequestState.rejected))
          AccountsV2Note(
            tone: request.state == CrewRequestState.rejected
                ? AccountsV2NoteTone.bad
                : AccountsV2NoteTone.warn,
            child: Text(
              '${decided?.name ?? ''}: “${request.decisionReason}”',
              style: v2Style(13),
            ),
          ),
        AccountsV2Panel(
          key: const ValueKey('crew-request-status'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccountsV2Chip(chip.text, tone: chip.tone),
                    if (request.overdue)
                      AccountsV2Chip(
                        CRS.t(CRS.neededNow, language),
                        tone: AccountsV2ChipTone.bad,
                        icon: 'alert',
                      ),
                    Text(
                      CRS.t(CRS.assignedOf, language, {
                        'a': request.assignedCount,
                        'b': request.requestedCount,
                      }),
                      style: v2Style(13, color: AccountsV2Colors.mut),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Fact(
                  label: CRS.t(CRS.colWith, language),
                  value: crewRequestOwnerLabel(request, language),
                ),
                _Fact(
                  label: CRS.t(CRS.colNext, language),
                  value: crewRequestNextStep(request, language),
                  emphasis: access.mine,
                ),
                _Fact(
                  label: CRS.t(CRS.factProject, language),
                  value: crewRequestWhere(request, language),
                ),
                if (request.workLabel != null)
                  _Fact(
                    label: CRS.t(CRS.factWork, language),
                    value: request.workLabel!,
                  ),
                _Fact(
                  label: CRS.t(CRS.factNeeded, language),
                  value: crewRequestDates(request, language),
                ),
                if (request.targetCrewName != null)
                  _Fact(
                    label: CRS.t(CRS.factCrew, language),
                    value: request.targetCrewName!,
                  ),
                _Fact(
                  label: CRS.t(CRS.factRequestedBy, language),
                  value: CRS.t(CRS.byRoleAt, language, {
                    'name': request.requestedBy.name,
                    'role': crewRequestRole(request.requestedBy.role, language),
                    'at': attendanceStamp(request.submittedAt),
                  }),
                ),
                if (decided != null)
                  _Fact(
                    label: CRS.t(CRS.factDecidedBy, language),
                    value: CRS.t(CRS.byRoleAt, language, {
                      'name': decided.name,
                      'role': crewRequestRole(decided.role, language),
                      'at': attendanceStamp(request.decidedAt),
                    }),
                  ),
                if (request.notes != null)
                  _Fact(
                    label: CRS.t(CRS.factNotes, language),
                    value: request.notes!,
                  ),
              ],
            ),
          ),
        ),
        AccountsV2Panel(
          key: const ValueKey('crew-request-lines'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CRS.t(CRS.linesTitle, language),
                icon: 'users',
              ),
              AccountsV2Table(
                phoneCards: true,
                columns: [
                  AccountsV2Column(CRS.t(CRS.trade, language), flex: 2),
                  AccountsV2Column(
                    CRS.t(CRS.howMany, language),
                    width: 120,
                    numeric: true,
                  ),
                  AccountsV2Column(CRS.t(CRS.colPeople, language), flex: 3),
                  AccountsV2Column(CRS.t(CRS.colState, language), flex: 2),
                ],
                rows: [
                  for (final line in request.lines)
                    AccountsV2Row(
                      key: ValueKey('crew-request-line-${line.id}'),
                      [
                        AccountsV2CellStack(
                          primary: line.trade,
                          secondary: line.note,
                        ),
                        Text('${line.quantity}', style: v2Style(13)),
                        line.assigned.isEmpty
                            ? Text(
                                CRS.t(CRS.noOneYet, language),
                                style: v2Style(13, color: AccountsV2Colors.mut),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final person in line.assigned)
                                    AccountsV2Chip(
                                      '${person.name} · ${person.crewName}',
                                      tone: AccountsV2ChipTone.ok,
                                    ),
                                ],
                              ),
                        _LineDecision(line: line, language: language),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        AccountsV2Panel(
          key: const ValueKey('crew-request-history'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CRS.t(CRS.historyTitle, language),
                icon: 'history',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: AccountsV2Timeline(
                  steps: [
                    for (final (index, event) in request.events.indexed)
                      (
                        title: _eventTitle(event),
                        detail: [
                          '${crewRequestRole(event.actorRole, language)} · ${attendanceStamp(event.at)}',
                          if (event.reason != null) '“${event.reason}”',
                        ].join(' · '),
                        state: index == request.events.length - 1 ? 1 : 2,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (phone && actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

class _LineDecision extends StatelessWidget {
  const _LineDecision({required this.line, required this.language});

  final CrewRequestLine line;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final decision = line.decision;
    if (decision == null) {
      return Text(
        CRS.t(CRS.assignedOf, language, {
          'a': line.assigned.length,
          'b': line.quantity,
        }),
        style: v2Style(13, color: AccountsV2Colors.mut),
      );
    }
    final (label, tone) = switch (decision) {
      CrewRequestLineDecision.full => (CRS.decisionFull, AccountsV2ChipTone.ok),
      CrewRequestLineDecision.partial => (
        CRS.decisionPartial,
        AccountsV2ChipTone.warn,
      ),
      CrewRequestLineDecision.cannotProvide => (
        CRS.decisionCannot,
        AccountsV2ChipTone.bad,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountsV2Chip(CRS.t(label, language), tone: tone),
        if (line.decisionReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '“${line.decisionReason}”',
              style: v2Style(12, color: AccountsV2Colors.mut),
            ),
          ),
      ],
    );
  }
}

/// A label and a value that wraps: long names and notes stay readable on a
/// 360px phone.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final labelText = Text(
      label,
      style: v2Style(12.5, color: AccountsV2Colors.mut),
    );
    final valueText = Text(
      value,
      style: v2Style(
        13.5,
        weight: emphasis ? FontWeight.w700 : FontWeight.w500,
        color: emphasis ? AccountsV2Colors.pri : AccountsV2Colors.ink,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 160, child: labelText),
                const SizedBox(width: 12),
                Expanded(child: valueText),
              ],
            ),
    );
  }
}
