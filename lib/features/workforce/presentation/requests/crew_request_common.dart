/// Workforce Center — shared pieces for crew request screens: state chips,
/// who has it, the next step, dates and error copy.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../../shared/models/yorks_v1_crew_request_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart';

typedef CRS = CrewRequestStrings;

String crewRequestPath(String id) => '/yorks/workforce/requests/$id';
String crewRequestAssignPath(String id) =>
    '/yorks/workforce/requests/$id/assign';
const crewRequestNewPath = '/yorks/workforce/requests/new';
String crewRequestFixPath(String id) =>
    '$crewRequestNewPath?request=${Uri.encodeQueryComponent(id)}';

({String text, AccountsV2ChipTone tone}) crewRequestStateChip(
  CrewRequestState state,
  AppLanguage language,
) {
  final (TranslatableString copy, AccountsV2ChipTone tone) = switch (state) {
    CrewRequestState.submitted => (CRS.stateSubmitted, AccountsV2ChipTone.warn),
    CrewRequestState.returned => (CRS.stateReturned, AccountsV2ChipTone.bad),
    CrewRequestState.approved => (CRS.stateApproved, AccountsV2ChipTone.pri),
    CrewRequestState.partiallyFulfilled => (
      CRS.statePartial,
      AccountsV2ChipTone.vio,
    ),
    CrewRequestState.fulfilled => (CRS.stateFulfilled, AccountsV2ChipTone.ok),
    CrewRequestState.closed => (CRS.stateClosed, AccountsV2ChipTone.neutral),
    CrewRequestState.rejected => (CRS.stateRejected, AccountsV2ChipTone.bad),
    CrewRequestState.cancelled => (
      CRS.stateCancelled,
      AccountsV2ChipTone.neutral,
    ),
  };
  return (text: CRS.t(copy, language), tone: tone);
}

String crewRequestOwnerLabel(CrewRequest request, AppLanguage language) =>
    switch (request.owner) {
      CrewRequestOwner.projectEngineer => CRS.t(
        CRS.ownerProjectEngineer,
        language,
      ),
      CrewRequestOwner.requester =>
        request.requestedBy.name.isEmpty
            ? CRS.t(CRS.ownerRequester, language)
            : request.requestedBy.name,
      CrewRequestOwner.pr => CRS.t(CRS.ownerPr, language),
      CrewRequestOwner.none => CRS.t(CRS.ownerNone, language),
    };

/// The next step, said for the signed-in person: their action when it is
/// theirs, otherwise who it is waiting for.
String crewRequestNextStep(CrewRequest request, AppLanguage language) {
  if (request.access.decide) return CRS.t(CRS.nextApprove, language);
  if (request.access.resubmit) return CRS.t(CRS.nextFix, language);
  if (request.access.fulfil) return CRS.t(CRS.nextAssign, language);
  if (!request.state.isOpen) return CRS.t(CRS.nextDone, language);
  return CRS.t(CRS.nextWaiting, language, {
    'who': crewRequestOwnerLabel(request, language),
  });
}

String crewRequestRole(String role, AppLanguage language) =>
    YorksV1AuditStrings.roleLabel(role, language);

String crewRequestWhere(CrewRequest request, AppLanguage language) {
  if (request.isWorkshop) return CRS.t(CRS.workshop, language);
  final ref = request.projectRef;
  final name = request.projectName ?? '';
  return ref == null || ref.isEmpty ? name : '$ref · $name';
}

String crewRequestPeople(CrewRequest request) =>
    request.trades.map((t) => '${t.quantity} × ${t.trade}').join(', ');

String crewRequestDates(CrewRequest request, AppLanguage language) {
  final from = attendanceShortDate(request.neededFrom);
  final until = request.neededUntil;
  return until == null
      ? CRS.t(CRS.fromOnwards, language, {'from': from})
      : CRS.t(CRS.fromUntil, language, {
          'from': from,
          'until': attendanceShortDate(until),
        });
}

String crewRequestErrorText(Object? error, AppLanguage language) {
  if (error is YorksV1DomainException) {
    final message = (error.serverMessage ?? '').toUpperCase();
    if (message.contains('WORKER_ON_CREW')) {
      return CRS.t(CRS.errWorkerOnCrew, language);
    }
    if (message.contains('OVER_ASSIGNED')) {
      return CRS.t(CRS.errOverAssigned, language);
    }
    if (message.contains('REQUEST_REASON_REQUIRED')) {
      return CRS.t(CRS.errReasonMissing, language);
    }
  }
  return attendanceErrorText(error, language);
}

/// A state pill for tables and headers.
class CrewRequestStateChip extends StatelessWidget {
  const CrewRequestStateChip({
    super.key,
    required this.request,
    required this.language,
  });

  final CrewRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final chip = crewRequestStateChip(request.state, language);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        AccountsV2Chip(chip.text, tone: chip.tone),
        if (request.overdue)
          AccountsV2Chip(
            CRS.t(CRS.neededNow, language),
            tone: AccountsV2ChipTone.bad,
            icon: 'alert',
          ),
      ],
    );
  }
}

/// Two or three choices as kit buttons, the selected one filled.
class CrewRequestToggle<T> extends StatelessWidget {
  const CrewRequestToggle({
    super.key,
    required this.options,
    required this.selected,
    this.onChanged,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          Semantics(
            selected: value == selected,
            button: true,
            child: AccountsV2Button(
              key: ValueKey('crew-request-toggle-$value'),
              label: label,
              icon: value == selected ? 'check' : null,
              kind: value == selected
                  ? AccountsV2ButtonKind.primary
                  : AccountsV2ButtonKind.normal,
              onPressed: onChanged == null ? null : () => onChanged!(value),
            ),
          ),
      ],
    );
  }
}
