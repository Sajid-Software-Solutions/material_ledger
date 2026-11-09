import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_logistics.dart';
import '../../../../shared/models/yorks_v1_material_request.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../../shared/models/yorks_v1_audit_workspace.dart';
import '../../../../shared/models/yorks_v1_rental.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_role_overview_strings.dart';
import 'yorks_v1_role_overview_spec.dart';

typedef _S = YorksV1RoleOverviewStrings;

/// Every server projection the role Overviews read. All of them are existing
/// protected, non-commercial projections; a role only receives the ones it
/// is allowed to load (the others stay `null`).
class YorksRoleOverviewInputs {
  const YorksRoleOverviewInputs({
    required this.role,
    required this.language,
    required this.now,
    required this.projects,
    required this.portfolio,
    required this.requests,
    required this.myWork,
    required this.exceptions,
    this.displayName,
    this.active,
    this.mine,
    this.closed,
    this.inventory,
    this.operations,
    this.drafts,
    this.rentals,
    this.audit,
    this.auditLoading = false,
    this.canCreateProject = false,
    this.canCreateRequest = false,
    this.canBrowseInventory = false,
    this.canManageUsers = false,
    this.canReadProject = _always,
    this.canReadRequest = _always,
  });

  static bool _always(String _) => true;

  /// Client-side mirror of the scoped read capability. The server already
  /// filters every projection; this only keeps a revoked project from
  /// lingering until the next refresh.
  final bool Function(String projectId) canReadProject;
  final bool Function(String projectId) canReadRequest;

  final YorksV1Role? role;
  final AppLanguage language;
  final DateTime now;
  final String? displayName;
  final AsyncValue<YorksV1ProjectOverview> projects;
  final AsyncValue<List<YorksV1ProjectPortfolioItem>> portfolio;
  final AsyncValue<YorksV1MaterialRequestOverview> requests;

  /// Records the signed-in person can act on now.
  final AsyncValue<YorksV1MaterialRequestSummaryPage> myWork;
  final AsyncValue<YorksV1MaterialRequestSummaryPage> exceptions;

  /// Open requests after submission, newest activity first.
  final AsyncValue<YorksV1MaterialRequestSummaryPage>? active;

  /// The signed-in person's own requests.
  final AsyncValue<YorksV1MaterialRequestSummaryPage>? mine;

  /// Requests closed in the last seven days.
  final AsyncValue<YorksV1MaterialRequestSummaryPage>? closed;
  final AsyncValue<YorksV1InventoryWorkspace?>? inventory;
  final AsyncValue<YorksV1MaterialRequestOperationsDashboard>? operations;
  final AsyncValue<List<YorksV1PrivateMaterialRequestDraftRecord>>? drafts;

  /// Admin only: the aggregate rental position.
  final AsyncValue<YorksV1RentalPortfolio?>? rentals;

  /// Admin only: the protected audit workspace (`null` when not loaded).
  final YorksV1AuditWorkspace? audit;
  final bool auditLoading;
  final bool canCreateProject;
  final bool canCreateRequest;
  final bool canBrowseInventory;
  final bool canManageUsers;
}

/// Navigation used by the cards. Every target is an existing guarded route;
/// the Overview never performs a workflow transition itself.
class YorksRoleOverviewNavigation {
  const YorksRoleOverviewNavigation({
    required this.openRequest,
    required this.openRequests,
    required this.openProjects,
    required this.openProject,
    this.newRequest,
    this.newProject,
    this.openDraft,
    this.openInventory,
    this.openDispatches,
    this.openReturns,
    this.newReturn,
    this.openUsers,
    this.openDuctSizer,
    this.openEspCalculator,
    this.openRentals,
    this.openAudit,
  });

  final void Function(YorksV1MaterialRequestSummary request) openRequest;
  final VoidCallback openRequests;
  final VoidCallback openProjects;
  final void Function(String projectId) openProject;
  final VoidCallback? newRequest;
  final VoidCallback? newProject;
  final void Function(YorksV1PrivateMaterialRequestDraftRecord draft)?
  openDraft;
  final VoidCallback? openInventory;
  final VoidCallback? openDispatches;
  final VoidCallback? openReturns;
  final VoidCallback? newReturn;
  final VoidCallback? openUsers;
  final VoidCallback? openDuctSizer;
  final VoidCallback? openEspCalculator;
  final VoidCallback? openRentals;
  final VoidCallback? openAudit;
}

/// Builds the Overview for the signed-in role.
YorksRoleOverviewSpec buildYorksRoleOverviewSpec(
  YorksRoleOverviewInputs input,
  YorksRoleOverviewNavigation nav,
) {
  final b = _Builder(input, nav);
  return switch (input.role) {
    YorksV1Role.siteEngineer => b.siteEngineer(),
    YorksV1Role.procurement => b.procurement(),
    YorksV1Role.seniorMechanicalEngineer => b.seniorMechanical(),
    YorksV1Role.projectManager => b.projectManager(),
    YorksV1Role.workshopInCharge => b.workshop(),
    YorksV1Role.documentController => b.documentController(),
    YorksV1Role.admin => b.admin(),
    YorksV1Role.projectEngineer ||
    YorksV1Role.accountant ||
    null => b.projectEngineer(),
  };
}

// ─── Request helpers ──────────────────────────────────────────────────────

/// What a record is waiting for, read only from the trusted state and the
/// server's current action code.
enum YorksOverviewWorkKind {
  approve,
  approveArrangement,
  arrange,
  dispatch,
  replacement,
  receipt,
  close,
  changes,
  other,
}

YorksOverviewWorkKind yorksOverviewWorkKind(YorksV1MaterialRequestSummary s) {
  final code = s.currentActionCode;
  if (code == 'replacement_dispatch_required') {
    return YorksOverviewWorkKind.replacement;
  }
  if (code == 'receipt_review_required') return YorksOverviewWorkKind.receipt;
  if (code == 'material_request_close_review' || code == 'close_request') {
    return YorksOverviewWorkKind.close;
  }
  return switch (s.state) {
    YorksV1MaterialRequestState.submitted ||
    YorksV1MaterialRequestState.awaitingRequestApproval =>
      YorksOverviewWorkKind.approve,
    YorksV1MaterialRequestState.awaitingApproval =>
      YorksOverviewWorkKind.approveArrangement,
    YorksV1MaterialRequestState.changesRequested =>
      YorksOverviewWorkKind.changes,
    YorksV1MaterialRequestState.approvedForArrangement ||
    YorksV1MaterialRequestState.arranging => YorksOverviewWorkKind.arrange,
    YorksV1MaterialRequestState.approved ||
    YorksV1MaterialRequestState.partiallyDispatched =>
      YorksOverviewWorkKind.dispatch,
    YorksV1MaterialRequestState.dispatched ||
    YorksV1MaterialRequestState.partiallyReceived =>
      YorksOverviewWorkKind.receipt,
    YorksV1MaterialRequestState.received => YorksOverviewWorkKind.close,
    _ => YorksOverviewWorkKind.other,
  };
}

/// Seven-step position used by the request tracker.
int yorksOverviewStage(YorksV1MaterialRequestState state) => switch (state) {
  YorksV1MaterialRequestState.draft ||
  YorksV1MaterialRequestState.cancelled => 1,
  YorksV1MaterialRequestState.submitted ||
  YorksV1MaterialRequestState.awaitingRequestApproval ||
  YorksV1MaterialRequestState.changesRequested => 2,
  YorksV1MaterialRequestState.approvedForArrangement ||
  YorksV1MaterialRequestState.arranging ||
  YorksV1MaterialRequestState.awaitingApproval => 3,
  YorksV1MaterialRequestState.approved => 4,
  YorksV1MaterialRequestState.partiallyDispatched ||
  YorksV1MaterialRequestState.dispatched ||
  YorksV1MaterialRequestState.partiallyReceived => 5,
  YorksV1MaterialRequestState.received => 6,
  YorksV1MaterialRequestState.closed => 7,
};

const _openStates = <YorksV1MaterialRequestState>[
  YorksV1MaterialRequestState.submitted,
  YorksV1MaterialRequestState.awaitingRequestApproval,
  YorksV1MaterialRequestState.changesRequested,
  YorksV1MaterialRequestState.approvedForArrangement,
  YorksV1MaterialRequestState.arranging,
  YorksV1MaterialRequestState.awaitingApproval,
  YorksV1MaterialRequestState.approved,
  YorksV1MaterialRequestState.partiallyDispatched,
  YorksV1MaterialRequestState.dispatched,
  YorksV1MaterialRequestState.partiallyReceived,
  YorksV1MaterialRequestState.received,
];

/// States an open request can be in, for the "active" projection query.
List<YorksV1MaterialRequestState> get yorksOverviewOpenStates => _openStates;

YorksOverviewLoad _loadOf(AsyncValue<Object?>? value) {
  if (value == null) return YorksOverviewLoad.ready;
  if (value.hasValue) return YorksOverviewLoad.ready;
  if (value.hasError) return YorksOverviewLoad.error;
  return YorksOverviewLoad.loading;
}

YorksOverviewLoad _worst(Iterable<YorksOverviewLoad> loads) {
  if (loads.contains(YorksOverviewLoad.error)) return YorksOverviewLoad.error;
  if (loads.contains(YorksOverviewLoad.loading)) {
    return YorksOverviewLoad.loading;
  }
  return YorksOverviewLoad.ready;
}

class _Builder {
  _Builder(this.input, this.nav);

  final YorksRoleOverviewInputs input;
  final YorksRoleOverviewNavigation nav;

  AppLanguage get lang => input.language;
  String t(TranslatableString s) => s.active(lang);
  String tf(TranslatableString s, Map<String, Object> values) {
    var out = s.active(lang);
    values.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
    return out;
  }

  // Data -------------------------------------------------------------------

  /// Server-confirmed project counts.
  YorksV1ProjectOverview? get projects => input.projects.valueOrNull;

  /// Every readable project, for per-project tables and lists.
  late final List<YorksV1ProjectPortfolioItem> portfolio =
      (input.portfolio.valueOrNull ?? const <YorksV1ProjectPortfolioItem>[])
          .where((item) => input.canReadProject(item.project.id))
          .toList(growable: false);
  YorksV1MaterialRequestOverview? get counts => input.requests.valueOrNull;

  List<YorksV1MaterialRequestSummary> _visible(
    AsyncValue<YorksV1MaterialRequestSummaryPage>? page,
  ) => (page?.valueOrNull?.items ?? const <YorksV1MaterialRequestSummary>[])
      .where((s) => input.canReadRequest(s.projectId))
      .toList(growable: false);

  late final List<YorksV1MaterialRequestSummary> work = _visible(input.myWork);
  int get workTotal {
    final page = input.myWork.valueOrNull;
    if (page == null) return work.length;
    final hidden = page.items.length - work.length;
    return page.totalCount - hidden;
  }

  late final List<YorksV1MaterialRequestSummary> exceptionItems = _visible(
    input.exceptions,
  );
  int get exceptionTotal {
    final page = input.exceptions.valueOrNull;
    if (page == null) return exceptionItems.length;
    final hidden = page.items.length - exceptionItems.length;
    return page.totalCount - hidden;
  }

  late final List<YorksV1MaterialRequestSummary> activeItems = _visible(
    input.active,
  );
  late final List<YorksV1MaterialRequestSummary> mineItems = _visible(
    input.mine,
  );
  YorksV1InventoryWorkspace? get inventory => input.inventory?.valueOrNull;
  List<YorksV1PrivateMaterialRequestDraftRecord> get drafts =>
      input.drafts?.valueOrNull ?? const [];

  Iterable<YorksV1MaterialRequestSummary> workOf(
    Set<YorksOverviewWorkKind> kinds,
  ) => work.where((s) => kinds.contains(yorksOverviewWorkKind(s)));

  // Formatting ---------------------------------------------------------------

  String age(double hours) {
    if (hours < 1) return t(_S.underAnHour);
    if (hours < 24) return tf(_S.hoursShort, {'n': hours.floor()});
    return tf(_S.daysShort, {'n': (hours / 24).floor()});
  }

  YorksOverviewEmphasis ageEmphasis(double hours) => hours >= 120
      ? YorksOverviewEmphasis.bad
      : hours >= 48
      ? YorksOverviewEmphasis.warn
      : YorksOverviewEmphasis.none;

  String date(DateTime value) =>
      DateFormat('d MMM', 'en_US').format(value.toLocal());

  int daysUntil(DateTime value) {
    final today = DateUtils.dateOnly(input.now.toLocal());
    return DateUtils.dateOnly(value.toLocal()).difference(today).inDays;
  }

  String lines(int n) => tf(n == 1 ? _S.oneLine : _S.lines, {'n': n});

  String ref(YorksV1MaterialRequestSummary s) =>
      s.requestNumber?.trim().isNotEmpty == true
      ? s.requestNumber!
      : t(_S.draft);

  String where(YorksV1MaterialRequestSummary s) =>
      '${s.projectName} · ${s.scopeName} · ${lines(s.itemCount)}';

  String roleOf(String? exactRole) =>
      YorksV1ProjectStrings.roleLabel(exactRole).active(lang);

  /// Who has the request now. A request with no named owner falls back to
  /// its next step instead of showing an empty owner.
  String ownerOf(YorksV1MaterialRequestSummary s) {
    if (s.actorCanAct) return t(_S.youNextStep);
    if (s.currentActionOwnerRole?.trim().isNotEmpty == true) {
      return yorksV1MaterialRequestOwnerRoleCopy(
        s.currentActionOwnerRole,
      ).active(lang);
    }
    return yorksV1MaterialRequestNextActionCodeCopy(
      state: s.state,
      currentActionCode: s.currentActionCode,
    ).active(lang);
  }

  String? submittedBy(YorksV1MaterialRequestSummary s) {
    final name = s.requesterDisplayName?.trim();
    if (name == null || name.isEmpty) return null;
    // The signed-in person's own request needs no byline.
    if (name == input.displayName?.trim()) return null;
    final role = s.requesterExactRole ?? s.requesterProjectRole;
    return role == null
        ? tf(_S.submittedBy, {'name': name})
        : tf(_S.submittedByRole, {'name': name, 'role': roleOf(role)});
  }

  bool urgent(YorksV1MaterialRequestSummary s) =>
      s.timing == YorksV1MaterialRequestTiming.urgent ||
      s.requiredOnSiteOverdue;

  /// Urgent first, then the oldest in the current step.
  List<YorksV1MaterialRequestSummary> ordered(
    Iterable<YorksV1MaterialRequestSummary> items,
  ) {
    final list = items.toList();
    list.sort((a, b) {
      final u = (urgent(b) ? 1 : 0) - (urgent(a) ? 1 : 0);
      if (u != 0) return u;
      return b.currentActionAgeHours.compareTo(a.currentActionAgeHours);
    });
    return list;
  }

  (String?, YorksOverviewEmphasis) tagOf(YorksV1MaterialRequestSummary s) {
    if (s.requiredOnSiteOverdue) {
      return (t(_S.requiredDatePassed), YorksOverviewEmphasis.bad);
    }
    if (s.timing == YorksV1MaterialRequestTiming.urgent) {
      return (t(_S.urgent), YorksOverviewEmphasis.bad);
    }
    final scheduled = s.scheduledDate;
    if (scheduled != null) {
      return (
        tf(_S.neededOn, {'date': date(scheduled)}),
        YorksOverviewEmphasis.strong,
      );
    }
    return (null, YorksOverviewEmphasis.none);
  }

  // Queue rows ---------------------------------------------------------------

  (IconData, YorksOverviewTone, String, String, String) kindCopy(
    YorksOverviewWorkKind kind,
  ) => switch (kind) {
    YorksOverviewWorkKind.approve => (
      Icons.check_rounded,
      YorksOverviewTone.blue,
      'approve',
      t(_S.approveRequest),
      t(_S.review),
    ),
    YorksOverviewWorkKind.approveArrangement => (
      Icons.fact_check_outlined,
      YorksOverviewTone.blue,
      'approve',
      t(_S.approveArrangement),
      t(_S.review),
    ),
    YorksOverviewWorkKind.arrange => (
      Icons.inventory_2_outlined,
      YorksOverviewTone.blue,
      'arrange',
      t(_S.arrangeRequest),
      t(_S.arrange),
    ),
    YorksOverviewWorkKind.dispatch => (
      Icons.local_shipping_outlined,
      YorksOverviewTone.green,
      'dispatch',
      t(_S.dispatchRequest),
      t(_S.dispatch),
    ),
    YorksOverviewWorkKind.replacement => (
      Icons.local_shipping_outlined,
      YorksOverviewTone.orange,
      'dispatch',
      t(_S.dispatchReplacement),
      t(_S.dispatch),
    ),
    YorksOverviewWorkKind.receipt => (
      Icons.local_shipping_outlined,
      YorksOverviewTone.green,
      'receipt',
      t(_S.confirmReceipt),
      t(_S.reviewReceipt),
    ),
    YorksOverviewWorkKind.close => (
      Icons.archive_outlined,
      YorksOverviewTone.neutral,
      'close',
      t(_S.closeRequest),
      t(_S.close),
    ),
    YorksOverviewWorkKind.changes => (
      Icons.undo_rounded,
      YorksOverviewTone.orange,
      'changes',
      t(_S.updateReturnedRequest),
      t(_S.editRequest),
    ),
    YorksOverviewWorkKind.other => (
      Icons.description_outlined,
      YorksOverviewTone.blue,
      'other',
      yorksV1MaterialRequestNextActionCodeCopy(
        state: YorksV1MaterialRequestState.submitted,
      ).active(lang),
      t(_S.open),
    ),
  };

  List<YorksOverviewQueueRow> queueRows(
    Iterable<YorksV1MaterialRequestSummary> items,
  ) {
    final rows = <YorksOverviewQueueRow>[];
    var first = true;
    for (final s in ordered(items)) {
      final kind = yorksOverviewWorkKind(s);
      final (icon, tone, tab, title, action) = kindCopy(kind);
      final (tag, tagTone) = tagOf(s);
      rows.add(
        YorksOverviewQueueRow(
          tab: tab,
          icon: icon,
          tone: tone,
          title: kind == YorksOverviewWorkKind.other
              ? yorksV1MaterialRequestNextActionCodeCopy(
                  state: s.state,
                  currentActionCode: s.currentActionCode,
                ).active(lang)
              : title,
          reference: ref(s),
          meta: where(s),
          tag: tag,
          tagTone: tagTone,
          byline: submittedBy(s),
          age: age(s.currentActionAgeHours),
          ageEmphasis: ageEmphasis(s.currentActionAgeHours),
          actionLabel: action,
          primary: first,
          onTap: () => nav.openRequest(s),
        ),
      );
      first = false;
    }
    return rows;
  }

  List<YorksOverviewQueueRow> draftRows() => [
    for (final record in drafts)
      YorksOverviewQueueRow(
        tab: 'draft',
        icon: Icons.edit_outlined,
        tone: YorksOverviewTone.neutral,
        title: record.draft.title?.trim().isNotEmpty == true
            ? record.draft.title!.trim()
            : t(_S.untitledDraft),
        reference: t(_S.draft),
        meta: lines(record.draft.lines.length),
        byline: tf(_S.savedToAccount, {'when': date(record.serverUpdatedAt)}),
        age: age(input.now.difference(record.serverUpdatedAt).inMinutes / 60),
        actionLabel: t(_S.continueDraft),
        onTap: nav.openDraft == null ? null : () => nav.openDraft!(record),
      ),
  ];

  // Shared cards -------------------------------------------------------------

  YorksOverviewQueueSection workQueue({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<YorksOverviewQueueTab> tabs,
    required String clearTitle,
    required String clearBody,
    Set<YorksOverviewWorkKind>? kinds,
    List<YorksOverviewQueueRow> extra = const [],
    String? footnote,
  }) {
    final items = kinds == null ? work : workOf(kinds).toList();
    final rows = [...queueRows(items), ...extra];
    return YorksOverviewQueueSection(
      id: id,
      icon: icon,
      title: title,
      subtitle: subtitle,
      tabs: tabs,
      rows: rows,
      total: kinds == null ? workTotal + extra.length : rows.length,
      clearTitle: clearTitle,
      clearBody: clearBody,
      footnote: footnote,
      onOpenAll: nav.openRequests,
      load: _worst([
        _loadOf(input.myWork),
        if (extra.isNotEmpty || input.drafts != null) _loadOf(input.drafts),
      ]),
      onRetry: nav.openRequests,
    );
  }

  YorksOverviewListItem exceptionItem(YorksV1MaterialRequestSummary s) {
    final code = s.exceptionCodes.isEmpty ? null : s.exceptionCodes.first;
    final (icon, tone) = switch (code) {
      YorksV1MaterialRequestExceptionCode.unavailableSupply => (
        Icons.report_problem_outlined,
        YorksOverviewTone.red,
      ),
      YorksV1MaterialRequestExceptionCode.partialArrangement => (
        Icons.inventory_2_outlined,
        YorksOverviewTone.orange,
      ),
      YorksV1MaterialRequestExceptionCode.lateExternalSupply => (
        Icons.schedule_rounded,
        YorksOverviewTone.red,
      ),
      YorksV1MaterialRequestExceptionCode.overdueReturn => (
        Icons.assignment_return_outlined,
        YorksOverviewTone.violet,
      ),
      YorksV1MaterialRequestExceptionCode.replacementRequired => (
        Icons.local_shipping_outlined,
        YorksOverviewTone.orange,
      ),
      _ => (Icons.local_shipping_outlined, YorksOverviewTone.red),
    };
    final label = code == null
        ? t(_S.exception)
        : yorksV1MaterialRequestExceptionCopy(code).active(lang);
    final more = s.exceptionCodes.length > 1
        ? ' ${tf(_S.plusMore, {'n': s.exceptionCodes.length - 1})}'
        : '';
    return YorksOverviewListItem(
      icon: icon,
      tone: tone,
      title: '$label · ${ref(s)}$more',
      detail: where(s),
      trailing: age(s.currentActionAgeHours),
      trailingEmphasis: ageEmphasis(s.currentActionAgeHours),
      onTap: () => nav.openRequest(s),
    );
  }

  YorksOverviewListSection exceptionList({
    required String id,
    required String title,
    required String subtitle,
    bool Function(YorksV1MaterialRequestSummary)? filter,
  }) {
    final items = filter == null
        ? exceptionItems
        : exceptionItems.where(filter).toList();
    return YorksOverviewListSection(
      id: id,
      icon: Icons.report_problem_outlined,
      title: title,
      subtitle: subtitle,
      items: [for (final s in ordered(items)) exceptionItem(s)],
      emptyText: t(_S.noExceptions),
      linkLabel: exceptionTotal > 6 ? t(_S.viewAll) : null,
      onLink: nav.openRequests,
      load: _loadOf(input.exceptions),
      onRetry: nav.openRequests,
    );
  }

  YorksOverviewListSection neededThisWeek() {
    final horizon = input.now.add(const Duration(days: 7));
    final items =
        activeItems
            .where(
              (s) =>
                  s.scheduledDate != null &&
                  s.state != YorksV1MaterialRequestState.received &&
                  (s.requiredOnSiteOverdue ||
                      !s.scheduledDate!.isAfter(horizon)),
            )
            .toList()
          ..sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));
    return YorksOverviewListSection(
      id: 'sched',
      icon: Icons.event_outlined,
      title: t(_S.neededThisWeek),
      subtitle: t(_S.neededThisWeekSub),
      items: [
        for (final s in items)
          () {
            final days = daysUntil(s.scheduledDate!);
            final overdue = days < 0 || s.requiredOnSiteOverdue;
            return YorksOverviewListItem(
              icon: Icons.event_outlined,
              tone: overdue
                  ? YorksOverviewTone.red
                  : days <= 2
                  ? YorksOverviewTone.gold
                  : YorksOverviewTone.blue,
              title: '${ref(s)} · ${s.title ?? s.scopeName}',
              detail:
                  '${s.projectName} · ${yorksV1MaterialRequestStateCopy(s.state).active(lang)}',
              trailing: overdue
                  ? tf(_S.overdueDays, {'n': -days < 1 ? 1 : -days})
                  : date(s.scheduledDate!),
              trailingSub: overdue
                  ? tf(_S.neededOn, {'date': date(s.scheduledDate!)})
                  : days == 0
                  ? t(_S.today)
                  : days == 1
                  ? t(_S.tomorrow)
                  : tf(_S.inDays, {'n': days}),
              trailingEmphasis: overdue
                  ? YorksOverviewEmphasis.bad
                  : days <= 2
                  ? YorksOverviewEmphasis.warn
                  : YorksOverviewEmphasis.none,
              onTap: () => nav.openRequest(s),
            );
          }(),
      ],
      emptyText: t(_S.nothingNeededThisWeek),
      load: _loadOf(input.active),
    );
  }

  YorksOverviewPipelineSection requestPipeline({
    required String id,
    required String title,
    required String subtitle,
    String? footnote,
    bool procurementOrder = false,
  }) {
    final c = counts;
    final stages = procurementOrder
        ? [
            YorksOverviewStage(
              label: t(_S.stageApprovedToArrange),
              count: c?.newToArrange ?? 0,
              tone: YorksOverviewTone.blue,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageWaitingEngineering),
              hint: t(_S.stageWaitingEngineeringHint),
              count: c?.approvals ?? 0,
              tone: YorksOverviewTone.violet,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageReadyToDispatch),
              count: c?.dispatchReady ?? 0,
              tone: YorksOverviewTone.gold,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageDispatchedReceiptOpen),
              count: c?.receiptPending ?? 0,
              tone: YorksOverviewTone.green,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageReceived),
              hint: t(_S.stageReceivedHint),
              count: c?.received ?? 0,
              tone: YorksOverviewTone.neutral,
              onTap: nav.openRequests,
            ),
          ]
        : [
            YorksOverviewStage(
              label: t(_S.stageEngineeringApproval),
              count: c?.approvals ?? 0,
              tone: YorksOverviewTone.blue,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageProcurementArrangement),
              count: c?.newToArrange ?? 0,
              tone: YorksOverviewTone.violet,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageReadyForDelivery),
              count: c?.dispatchReady ?? 0,
              tone: YorksOverviewTone.gold,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageDispatched),
              hint: t(_S.stageDispatchedHint),
              count: c?.receiptPending ?? 0,
              tone: YorksOverviewTone.green,
              onTap: nav.openRequests,
            ),
            YorksOverviewStage(
              label: t(_S.stageReceived),
              hint: t(_S.stageReceivedHint),
              count: c?.received ?? 0,
              tone: YorksOverviewTone.neutral,
              onTap: nav.openRequests,
            ),
          ];
    return YorksOverviewPipelineSection(
      id: id,
      icon: Icons.layers_outlined,
      title: title,
      subtitle: subtitle,
      stages: stages,
      footnote: footnote,
      load: _loadOf(input.requests),
    );
  }

  List<YorksV1LogisticsInventoryItem> belowMinimum() {
    final items = inventory?.items ?? const <YorksV1LogisticsInventoryItem>[];
    final out = <YorksV1LogisticsInventoryItem>[];
    for (final item in items) {
      if (!item.isActive) continue;
      final min = double.tryParse(item.minimumStock ?? '');
      final available = double.tryParse(item.availableQuantity) ?? 0;
      if (min != null && min > 0 && available < min) out.add(item);
    }
    out.sort((a, b) {
      final av = double.tryParse(a.availableQuantity) ?? 0;
      final bv = double.tryParse(b.availableQuantity) ?? 0;
      return av.compareTo(bv);
    });
    return out;
  }

  String qty(String value) {
    final n = double.tryParse(value);
    if (n == null) return value;
    return n == n.roundToDouble()
        ? NumberFormat('#,##0', 'en_US').format(n)
        : NumberFormat('#,##0.###', 'en_US').format(n);
  }

  YorksOverviewTableSection stockTable({required bool readOnly}) {
    final items = belowMinimum();
    return YorksOverviewTableSection(
      id: 'stock',
      icon: Icons.inventory_2_outlined,
      title: t(_S.belowMinimumStock),
      subtitle: readOnly
          ? tf(_S.belowMinimumSubReadOnly, {'n': items.length})
          : tf(_S.belowMinimumSub, {'n': items.length}),
      linkLabel: nav.openInventory == null ? null : t(_S.openInventory),
      onLink: nav.openInventory,
      columns: [
        YorksOverviewTableColumn(t(_S.colItem), flex: 26),
        YorksOverviewTableColumn(t(_S.colOnHand), numeric: true),
        YorksOverviewTableColumn(t(_S.colReserved), numeric: true),
        YorksOverviewTableColumn(t(_S.colAvailable), numeric: true),
        YorksOverviewTableColumn(t(_S.colMinimum), numeric: true),
      ],
      mobileColumns: const [3, 4],
      rows: [
        for (final item in items.take(8))
          YorksOverviewTableRow(
            onTap: nav.openInventory,
            cells: [
              YorksOverviewCell(
                item.description,
                subtitle: [
                  if (item.categoryName?.trim().isNotEmpty == true)
                    item.categoryName!,
                  item.unit,
                ].join(' · '),
              ),
              YorksOverviewCell(qty(item.onHandQuantity)),
              YorksOverviewCell(qty(item.reservedQuantity)),
              YorksOverviewCell(
                qty(item.availableQuantity),
                emphasis: (double.tryParse(item.availableQuantity) ?? 0) <= 0
                    ? YorksOverviewEmphasis.bad
                    : YorksOverviewEmphasis.warn,
              ),
              YorksOverviewCell(qty(item.minimumStock ?? '0')),
            ],
          ),
      ],
      emptyText: t(_S.noLowStock),
      load: _loadOf(input.inventory),
    );
  }

  YorksOverviewToolsSection tools(String title) => YorksOverviewToolsSection(
    id: 'tools',
    icon: Icons.straighten_rounded,
    title: title,
    tools: [
      YorksOverviewTool(
        icon: Icons.straighten_rounded,
        label: t(_S.ductSizer),
        description: t(_S.ductSizerSub),
        onTap: nav.openDuctSizer,
      ),
      YorksOverviewTool(
        icon: Icons.speed_rounded,
        label: t(_S.espCalculator),
        description: t(_S.espCalculatorSub),
        onTap: nav.openEspCalculator,
      ),
    ],
  );

  /// Per-project table built from the project projection, with the work and
  /// exceptions that belong to each project.
  YorksOverviewTableSection projectTable({
    required String id,
    required String title,
    required String subtitle,
    bool attentionOnly = false,
    bool showWaiting = true,
  }) {
    final waiting = <String, int>{};
    for (final s in work) {
      waiting[s.projectId] = (waiting[s.projectId] ?? 0) + 1;
    }
    final problems = <String, int>{};
    for (final s in exceptionItems) {
      problems[s.projectId] = (problems[s.projectId] ?? 0) + 1;
    }
    var items = portfolio
        .where(
          (p) =>
              p.project.state != YorksV1ProjectLifecycle.archived &&
              p.project.state != YorksV1ProjectLifecycle.completed,
        )
        .toList();
    int score(YorksV1ProjectPortfolioItem p) =>
        (problems[p.project.id] ?? 0) * 3 +
        (waiting[p.project.id] ?? 0) +
        (p.project.state == YorksV1ProjectLifecycle.onHold ? 4 : 0) +
        (p.activeProjectEngineerCount == 0 ? 4 : 0);
    if (attentionOnly) items = items.where((p) => score(p) > 0).toList();
    items.sort((a, b) {
      final s = score(b).compareTo(score(a));
      if (s != 0) return s;
      return b.project.updatedAt.compareTo(a.project.updatedAt);
    });
    YorksOverviewCell stateCell(YorksV1ProjectLifecycle state) =>
        YorksOverviewCell(
          YorksV1ProjectStrings.stateLabel(state).active(lang),
          chip: true,
          emphasis: switch (state) {
            YorksV1ProjectLifecycle.active => YorksOverviewEmphasis.ok,
            YorksV1ProjectLifecycle.onHold => YorksOverviewEmphasis.warn,
            YorksV1ProjectLifecycle.completed => YorksOverviewEmphasis.strong,
            _ => YorksOverviewEmphasis.none,
          },
        );
    return YorksOverviewTableSection(
      id: id,
      icon: Icons.account_tree_outlined,
      title: title,
      subtitle: subtitle,
      linkLabel: t(_S.allProjects),
      onLink: nav.openProjects,
      columns: [
        YorksOverviewTableColumn(t(_S.colProject), flex: 30),
        YorksOverviewTableColumn(t(_S.colState), flex: 11),
        if (showWaiting)
          YorksOverviewTableColumn(
            t(_S.colWaitingOnYou),
            numeric: true,
            flex: 11,
          ),
        YorksOverviewTableColumn(t(_S.colExceptions), numeric: true, flex: 10),
        YorksOverviewTableColumn(t(_S.colTeam), flex: 16),
        YorksOverviewTableColumn(t(_S.colLastUpdated), flex: 12),
      ],
      mobileColumns: showWaiting ? const [1, 2, 3, 4] : const [1, 2, 3],
      rows: [
        for (final p in items.take(8))
          YorksOverviewTableRow(
            onTap: () => nav.openProject(p.project.id),
            cells: [
              YorksOverviewCell(
                '${p.project.reference} · ${p.project.name}',
                subtitle: [
                  if (p.project.siteLocation?.trim().isNotEmpty == true)
                    p.project.siteLocation!.trim()
                  else if (p.clientName?.trim().isNotEmpty == true)
                    p.clientName!.trim(),
                  tf(
                    p.activeBuildingCount == 1
                        ? _S.oneBuilding
                        : _S.buildingsCount,
                    {'n': p.activeBuildingCount},
                  ),
                ].join(' · '),
              ),
              stateCell(p.project.state),
              if (showWaiting)
                YorksOverviewCell(
                  '${waiting[p.project.id] ?? 0}',
                  emphasis: YorksOverviewEmphasis.strong,
                ),
              YorksOverviewCell(
                '${problems[p.project.id] ?? 0}',
                emphasis: (problems[p.project.id] ?? 0) > 0
                    ? YorksOverviewEmphasis.bad
                    : YorksOverviewEmphasis.none,
              ),
              p.activeProjectEngineerCount == 0
                  ? YorksOverviewCell(
                      t(_S.noProjectEngineer),
                      emphasis: YorksOverviewEmphasis.warn,
                    )
                  : YorksOverviewCell(
                      tf(_S.teamCounts, {
                        'pe': p.activeProjectEngineerCount,
                        'se': p.activeSiteEngineerCount,
                      }),
                    ),
              YorksOverviewCell(date(p.project.updatedAt)),
            ],
          ),
      ],
      emptyText: attentionOnly
          ? t(_S.noProjectsNeedAttention)
          : t(_S.noProjectsYet),
      load: _worst([
        _loadOf(input.portfolio),
        _loadOf(input.myWork),
        _loadOf(input.exceptions),
      ]),
    );
  }

  List<YorksOverviewAction> actions(List<YorksOverviewAction?> list) =>
      list.whereType<YorksOverviewAction>().toList();

  YorksOverviewAction? newRequestAction({bool primary = true}) =>
      input.canCreateRequest && nav.newRequest != null
      ? YorksOverviewAction(
          icon: Icons.add_rounded,
          label: t(_S.newMaterialRequest),
          onTap: nav.newRequest,
          primary: primary,
        )
      : null;

  YorksOverviewAction? newProjectAction() =>
      input.canCreateProject && nav.newProject != null
      ? YorksOverviewAction(
          icon: Icons.account_tree_outlined,
          label: t(_S.newProject),
          onTap: nav.newProject,
        )
      : null;

  String greeting() {
    final first = (input.displayName ?? '').trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? t(_S.goodDay) : first;
  }

  String scopeAssigned() {
    final n = projects?.total;
    if (n == null) return t(_S.assignedProjects);
    return tf(n == 1 ? _S.oneAssignedProject : _S.assignedProjectsCount, {
      'n': n,
    });
  }

  YorksOverviewLoad get countsLoad => _loadOf(input.requests);

  YorksOverviewKpi kpi({
    required String id,
    required IconData icon,
    required YorksOverviewTone tone,
    required String label,
    required int? value,
    required String caption,
    YorksOverviewEmphasis emphasis = YorksOverviewEmphasis.none,
    String? target,
    String? tab,
    VoidCallback? onTap,
    YorksOverviewLoad? load,
    bool actionable = false,
  }) {
    final v = value ?? 0;
    return YorksOverviewKpi(
      id: id,
      icon: icon,
      tone: tone,
      label: label,
      value: '$v',
      caption: actionable && v == 0 ? t(_S.nothingWaiting) : caption,
      emphasis: v == 0 && emphasis != YorksOverviewEmphasis.none
          ? (actionable ? YorksOverviewEmphasis.ok : YorksOverviewEmphasis.none)
          : emphasis,
      targetSection: target,
      queueTab: tab,
      onTap: onTap,
      load: load ?? (value == null ? countsLoad : YorksOverviewLoad.ready),
    );
  }

  String oldestCaption(Iterable<YorksV1MaterialRequestSummary> items) {
    if (items.isEmpty) return '';
    final oldest = items
        .map((s) => s.currentActionAgeHours)
        .reduce((a, b) => a > b ? a : b);
    final urgentCount = items.where(urgent).length;
    final parts = [
      tf(_S.oldest, {'age': age(oldest)}),
    ];
    if (urgentCount > 0) parts.add(tf(_S.urgentCount, {'n': urgentCount}));
    return parts.join(' · ');
  }

  // ─── Project Engineer ───────────────────────────────────────────────────

  YorksOverviewQueueSection peQueue() => workQueue(
    id: 'work',
    icon: Icons.format_list_bulleted_rounded,
    title: t(_S.waitingForYou),
    subtitle: t(_S.waitingForYouSub),
    tabs: [
      YorksOverviewQueueTab('all', t(_S.tabAll)),
      YorksOverviewQueueTab('approve', t(_S.tabApprove)),
      YorksOverviewQueueTab('receipt', t(_S.tabReceipts)),
      YorksOverviewQueueTab('close', t(_S.tabClose)),
      YorksOverviewQueueTab('changes', t(_S.tabChanges)),
    ],
    clearTitle: t(_S.nothingWaitingForYou),
    clearBody: t(_S.nothingWaitingForYouBody),
    footnote: t(_S.ageFootnote),
  );

  YorksRoleOverviewSpec projectEngineer() {
    final approvals = workOf({
      YorksOverviewWorkKind.approve,
      YorksOverviewWorkKind.approveArrangement,
    });
    final receipts = workOf({YorksOverviewWorkKind.receipt});
    final c = counts;
    final workLoad = _loadOf(input.myWork);
    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('project_engineer'),
      description: t(_S.peDescription),
      scope: scopeAssigned(),
      actions: actions([newRequestAction(), newProjectAction()]),
      kpis: [
        kpi(
          id: 'approve',
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiWaitingApproval),
          value: workLoad.isReadyValue ? approvals.length : null,
          load: workLoad,
          caption: oldestCaption(approvals),
          target: 'work',
          tab: 'approve',
          actionable: true,
        ),
        kpi(
          id: 'procurement',
          icon: Icons.inventory_2_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiWithProcurement),
          value: c?.newToArrange,
          caption: t(_S.kpiWithProcurementSub),
          target: 'pipe',
        ),
        kpi(
          id: 'receipt',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.green,
          label: t(_S.kpiReceiptOpen),
          value: workLoad.isReadyValue ? receipts.length : null,
          load: workLoad,
          caption: t(_S.kpiReceiptOpenSub),
          target: 'work',
          tab: 'receipt',
          actionable: true,
        ),
        kpi(
          id: 'exceptions',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiExceptions),
          value: input.exceptions.hasValue ? exceptionTotal : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiExceptionsSub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'exc',
        ),
        kpi(
          id: 'drafts',
          icon: Icons.edit_outlined,
          tone: YorksOverviewTone.neutral,
          label: t(_S.kpiDraftsChanges),
          value: c?.draftsAndChanges,
          caption: t(_S.kpiDraftsChangesSub),
          onTap: nav.openRequests,
        ),
      ],
      left: [peQueue()],
      right: [
        requestPipeline(
          id: 'pipe',
          title: t(_S.requestsOnMyProjects),
          subtitle: t(_S.requestsByStageSub),
          footnote: t(_S.pipelineFootnote),
        ),
        exceptionList(
          id: 'exc',
          title: t(_S.exceptionsToFollowUp),
          subtitle: t(_S.exceptionsToFollowUpSub),
        ),
        neededThisWeek(),
      ],
      full: [
        projectTable(
          id: 'proj',
          title: t(_S.myProjects),
          subtitle: t(_S.myProjectsSub),
        ),
      ],
      phoneOrder: const ['work', 'exc', 'sched', 'pipe', 'proj'],
    );
  }

  // ─── Site Engineer ──────────────────────────────────────────────────────

  YorksRoleOverviewSpec siteEngineer() {
    final receipts = workOf({YorksOverviewWorkKind.receipt});
    final changes = workOf({YorksOverviewWorkKind.changes});
    final workLoad = _loadOf(input.myWork);
    final mineOpen = mineItems
        .where(
          (s) =>
              s.state != YorksV1MaterialRequestState.draft &&
              s.state != YorksV1MaterialRequestState.closed &&
              s.state != YorksV1MaterialRequestState.cancelled,
        )
        .toList();
    final waitingOnOthers = mineOpen.where((s) => !s.actorCanAct).length;
    final missingDamaged = exceptionItems
        .where(
          (s) => s.exceptionCodes.any(
            (c) =>
                c == YorksV1MaterialRequestExceptionCode.missingReceipt ||
                c == YorksV1MaterialRequestExceptionCode.damagedReceipt ||
                c == YorksV1MaterialRequestExceptionCode.replacementRequired,
          ),
        )
        .toList();
    final onTheWay = activeItems
        .where(
          (s) =>
              s.state == YorksV1MaterialRequestState.dispatched ||
              s.state == YorksV1MaterialRequestState.partiallyDispatched ||
              s.state == YorksV1MaterialRequestState.approved,
        )
        .toList();

    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('site_engineer'),
      description: t(_S.seDescription),
      scope: scopeAssigned(),
      actions: actions([
        newRequestAction(),
        if (nav.newReturn != null)
          YorksOverviewAction(
            icon: Icons.assignment_return_outlined,
            label: t(_S.createReturn),
            onTap: nav.newReturn,
          ),
      ]),
      kpis: [
        kpi(
          id: 'receipt',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.green,
          label: t(_S.kpiDeliveriesToConfirm),
          value: workLoad.isReadyValue ? receipts.length : null,
          load: workLoad,
          caption: t(_S.kpiDeliveriesToConfirmSub),
          target: 'todo',
          tab: 'receipt',
          actionable: true,
        ),
        kpi(
          id: 'changes',
          icon: Icons.undo_rounded,
          tone: YorksOverviewTone.orange,
          label: t(_S.kpiReturnedForChanges),
          value: workLoad.isReadyValue ? changes.length : null,
          load: workLoad,
          caption: t(_S.kpiReturnedForChangesSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'todo',
          tab: 'changes',
          actionable: true,
        ),
        kpi(
          id: 'drafts',
          icon: Icons.edit_outlined,
          tone: YorksOverviewTone.neutral,
          label: t(_S.kpiMyDrafts),
          value: input.drafts?.hasValue == true ? drafts.length : null,
          load: _loadOf(input.drafts),
          caption: t(_S.kpiMyDraftsSub),
          target: 'todo',
          tab: 'draft',
        ),
        kpi(
          id: 'mine',
          icon: Icons.schedule_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiWaitingOnOthers),
          value: input.mine?.hasValue == true ? waitingOnOthers : null,
          load: _loadOf(input.mine),
          caption: t(_S.kpiWaitingOnOthersSub),
          target: 'mine',
        ),
        kpi(
          id: 'rep',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiMissingDamaged),
          value: input.exceptions.hasValue ? missingDamaged.length : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiMissingDamagedSub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'rep',
        ),
      ],
      left: [
        workQueue(
          id: 'todo',
          icon: Icons.format_list_bulleted_rounded,
          title: t(_S.toDoOnSite),
          subtitle: t(_S.toDoOnSiteSub),
          tabs: [
            YorksOverviewQueueTab('all', t(_S.tabAll)),
            YorksOverviewQueueTab('receipt', t(_S.tabReceipts)),
            YorksOverviewQueueTab('changes', t(_S.tabChanges)),
            YorksOverviewQueueTab('draft', t(_S.tabDrafts)),
            YorksOverviewQueueTab('close', t(_S.tabClose)),
          ],
          extra: draftRows(),
          clearTitle: t(_S.upToDate),
          clearBody: t(_S.upToDateBody),
          footnote: t(_S.seFootnote),
        ),
        YorksOverviewTrackSection(
          id: 'mine',
          icon: Icons.assignment_outlined,
          title: t(_S.myRequests),
          subtitle: t(_S.myRequestsSub),
          linkLabel: t(_S.allMyRequests),
          onLink: nav.openRequests,
          stageNames: stageNames,
          items: [
            for (final s in mineOpen.take(8))
              YorksOverviewTrackItem(
                reference: ref(s),
                title: s.title ?? s.scopeName,
                stage: yorksOverviewStage(s.state),
                stageLabel: stageNames[yorksOverviewStage(s.state) - 1],
                owner: ownerOf(s),
                age: age(s.currentActionAgeHours),
                note: s.exceptionCodes.isNotEmpty
                    ? yorksV1MaterialRequestExceptionCopy(
                        s.exceptionCodes.first,
                      ).active(lang)
                    : tagOf(s).$1,
                noteEmphasis: s.exceptionCodes.isNotEmpty || urgent(s)
                    ? YorksOverviewEmphasis.warn
                    : YorksOverviewEmphasis.none,
                warning: s.exceptionCodes.isNotEmpty,
                onTap: () => nav.openRequest(s),
              ),
          ],
          emptyText: t(_S.noOpenRequests),
          load: _loadOf(input.mine),
        ),
      ],
      right: [
        YorksOverviewListSection(
          id: 'arr',
          icon: Icons.local_shipping_outlined,
          title: t(_S.onTheWay),
          subtitle: t(_S.onTheWaySub),
          items: [
            for (final s in onTheWay)
              YorksOverviewListItem(
                icon: s.state == YorksV1MaterialRequestState.approved
                    ? Icons.inventory_2_outlined
                    : Icons.local_shipping_outlined,
                tone: s.state == YorksV1MaterialRequestState.approved
                    ? YorksOverviewTone.gold
                    : YorksOverviewTone.green,
                title: '${ref(s)} · ${s.scopeName}',
                detail:
                    '${yorksV1MaterialRequestStateCopy(s.state).active(lang)} · ${lines(s.itemCount)}',
                trailing: s.scheduledDate == null
                    ? age(s.currentActionAgeHours)
                    : tf(_S.neededOn, {'date': date(s.scheduledDate!)}),
                trailingEmphasis: s.requiredOnSiteOverdue
                    ? YorksOverviewEmphasis.bad
                    : YorksOverviewEmphasis.ok,
                onTap: () => nav.openRequest(s),
              ),
          ],
          emptyText: t(_S.nothingOnTheWay),
          load: _loadOf(input.active),
        ),
        YorksOverviewListSection(
          id: 'rep',
          icon: Icons.report_problem_outlined,
          title: t(_S.missingOrDamaged),
          subtitle: t(_S.missingOrDamagedSub),
          items: [for (final s in missingDamaged) exceptionItem(s)],
          emptyText: t(_S.nothingMissing),
          load: _loadOf(input.exceptions),
        ),
        tools(t(_S.siteTools)),
      ],
      phoneOrder: const ['todo', 'arr', 'mine', 'rep', 'tools'],
    );
  }

  List<String> get stageNames => [
    t(_S.stageCreated),
    t(_S.stageEngineeringApproval),
    t(_S.stageProcurementArrangement),
    t(_S.stageReadyForDelivery),
    t(_S.stageDispatched),
    t(_S.stageReceived),
    t(_S.stageCompleted),
  ];

  // ─── Procurement ────────────────────────────────────────────────────────

  YorksRoleOverviewSpec procurement() {
    final arrange = workOf({YorksOverviewWorkKind.arrange});
    final dispatch = workOf({
      YorksOverviewWorkKind.dispatch,
      YorksOverviewWorkKind.replacement,
    });
    final workLoad = _loadOf(input.myWork);
    final stock = belowMinimum();
    final late = exceptionItems
        .where(
          (s) => s.exceptionCodes.contains(
            YorksV1MaterialRequestExceptionCode.lateExternalSupply,
          ),
        )
        .toList();
    final waitingReceipt =
        activeItems
            .where(
              (s) =>
                  s.state == YorksV1MaterialRequestState.dispatched ||
                  s.state == YorksV1MaterialRequestState.partiallyReceived,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.currentActionAgeHours.compareTo(a.currentActionAgeHours),
          );
    final ops = input.operations?.valueOrNull;
    String hours(double? h) => h == null
        ? '—'
        : h >= 24
        ? tf(_S.daysDecimal, {'n': (h / 24).toStringAsFixed(1)})
        : tf(_S.hoursDecimal, {'n': h.toStringAsFixed(1)});

    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('procurement'),
      description: t(_S.procDescription),
      scope: t(_S.procScope),
      actions: actions([
        YorksOverviewAction(
          icon: Icons.inventory_2_outlined,
          label: t(_S.openRequestsAction),
          onTap: nav.openRequests,
          primary: true,
        ),
        if (nav.openInventory != null)
          YorksOverviewAction(
            icon: Icons.inventory_outlined,
            label: t(_S.browseInventory),
            onTap: nav.openInventory,
          ),
        if (nav.openDispatches != null)
          YorksOverviewAction(
            icon: Icons.local_shipping_outlined,
            label: t(_S.dispatches),
            onTap: nav.openDispatches,
          ),
      ]),
      kpis: [
        kpi(
          id: 'arrange',
          icon: Icons.inventory_2_outlined,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiToArrange),
          value: workLoad.isReadyValue ? arrange.length : null,
          load: workLoad,
          caption: oldestCaption(arrange),
          target: 'work',
          tab: 'arrange',
          actionable: true,
        ),
        kpi(
          id: 'dispatch',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.green,
          label: t(_S.kpiReadyToDispatch),
          value: workLoad.isReadyValue ? dispatch.length : null,
          load: workLoad,
          caption: oldestCaption(dispatch),
          target: 'work',
          tab: 'dispatch',
          actionable: true,
        ),
        kpi(
          id: 'stock',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.belowMinimumStock),
          value: input.inventory?.hasValue == true ? stock.length : null,
          load: _loadOf(input.inventory),
          caption: tf(_S.outOfStockCount, {
            'n': inventory?.summary.outOfStockCount ?? 0,
          }),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'stock',
        ),
        kpi(
          id: 'late',
          icon: Icons.schedule_rounded,
          tone: YorksOverviewTone.orange,
          label: t(_S.kpiSupplierLate),
          value: input.exceptions.hasValue ? late.length : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiSupplierLateSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'ext',
        ),
        kpi(
          id: 'chase',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiWaitingSiteReceipt),
          value: counts?.receiptPending,
          caption: t(_S.kpiWaitingSiteReceiptSub),
          target: 'chase',
        ),
      ],
      left: [
        workQueue(
          id: 'work',
          icon: Icons.format_list_bulleted_rounded,
          title: t(_S.yourWorkQueue),
          subtitle: t(_S.yourWorkQueueSub),
          tabs: [
            YorksOverviewQueueTab('all', t(_S.tabAll)),
            YorksOverviewQueueTab('arrange', t(_S.tabToArrange)),
            YorksOverviewQueueTab('dispatch', t(_S.tabToDispatch)),
          ],
          clearTitle: t(_S.nothingForProcurement),
          clearBody: t(_S.nothingForProcurementBody),
          footnote: t(_S.procFootnote),
        ),
        stockTable(readOnly: false),
      ],
      right: [
        requestPipeline(
          id: 'flow',
          title: t(_S.yourPipeline),
          subtitle: t(_S.yourPipelineSub),
          procurementOrder: true,
        ),
        exceptionList(
          id: 'ext',
          title: t(_S.supplierDeliveries),
          subtitle: t(_S.supplierDeliveriesSub),
          filter: (s) =>
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.lateExternalSupply,
              ) ||
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.unavailableSupply,
              ),
        ),
        YorksOverviewListSection(
          id: 'chase',
          icon: Icons.local_shipping_outlined,
          title: t(_S.waitingForSiteReceipt),
          subtitle: t(_S.waitingForSiteReceiptSub),
          items: [
            for (final s in waitingReceipt)
              YorksOverviewListItem(
                icon: Icons.local_shipping_outlined,
                tone: s.currentActionAgeHours >= 72
                    ? YorksOverviewTone.orange
                    : YorksOverviewTone.green,
                title: '${ref(s)} · ${s.projectName}',
                detail: '${s.scopeName} · ${lines(s.itemCount)}',
                trailing: age(s.currentActionAgeHours),
                trailingEmphasis: s.currentActionAgeHours >= 72
                    ? YorksOverviewEmphasis.warn
                    : YorksOverviewEmphasis.none,
                onTap: () => nav.openRequest(s),
              ),
          ],
          emptyText: t(_S.nothingAwaitingReceipt),
          load: _loadOf(input.active),
        ),
        YorksOverviewMoneySection(
          id: 'ins',
          icon: Icons.insights_outlined,
          title: t(_S.last30Days),
          subtitle: t(_S.last30DaysSub),
          rows: [
            YorksOverviewMoneyRow(
              t(_S.avgArrangementTime),
              hours(ops?.averageArrangementHours),
            ),
            YorksOverviewMoneyRow(
              t(_S.warehouseFillRate),
              ops?.warehouseFillRatePercent == null
                  ? '—'
                  : '${ops!.warehouseFillRatePercent!.round()}%',
              emphasis: YorksOverviewEmphasis.ok,
            ),
            YorksOverviewMoneyRow(
              t(_S.avgReceiptTime),
              hours(ops?.averageReceiptTurnaroundHours),
            ),
            YorksOverviewMoneyRow(
              t(_S.replacementOwed),
              ops == null
                  ? '—'
                  : tf(_S.unitsCount, {
                      'n': qty(ops.outstandingReplacementQuantity),
                    }),
              emphasis:
                  (double.tryParse(
                            ops?.outstandingReplacementQuantity ?? '0',
                          ) ??
                          0) >
                      0
                  ? YorksOverviewEmphasis.bad
                  : YorksOverviewEmphasis.none,
            ),
          ],
          load: _loadOf(input.operations),
        ),
      ],
      phoneOrder: const ['work', 'ext', 'stock', 'chase'],
    );
  }

  // ─── Senior Mechanical Engineer ─────────────────────────────────────────

  YorksOverviewQueueSection approvalsQueue(String subtitle) => workQueue(
    id: 'appr',
    icon: Icons.check_circle_outline_rounded,
    title: t(_S.approvalsAcrossYorks),
    subtitle: subtitle,
    tabs: [
      YorksOverviewQueueTab('all', t(_S.tabAll)),
      YorksOverviewQueueTab('approve', t(_S.tabApprove)),
      YorksOverviewQueueTab('receipt', t(_S.tabReceipts)),
      YorksOverviewQueueTab('close', t(_S.tabClose)),
    ],
    clearTitle: t(_S.noApprovalsWaiting),
    clearBody: t(_S.noApprovalsWaitingBody),
    footnote: t(_S.ageFootnote),
  );

  YorksRoleOverviewSpec seniorMechanical() {
    final approvals = workOf({
      YorksOverviewWorkKind.approve,
      YorksOverviewWorkKind.approveArrangement,
    });
    final workLoad = _loadOf(input.myWork);
    final cannotSupply = exceptionItems
        .where(
          (s) =>
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.unavailableSupply,
              ) ||
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.partialArrangement,
              ),
        )
        .toList();
    final noPe = portfolio
        .where(
          (p) =>
              p.activeProjectEngineerCount == 0 &&
              p.project.state != YorksV1ProjectLifecycle.archived &&
              p.project.state != YorksV1ProjectLifecycle.completed,
        )
        .toList();
    final stock = belowMinimum();
    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('senior_mechanical_engineer'),
      description: t(_S.smeDescription),
      scope: t(_S.smeScope),
      actions: actions([
        YorksOverviewAction(
          icon: Icons.check_rounded,
          label: t(_S.reviewApprovals),
          onTap: nav.openRequests,
          primary: true,
        ),
        if (input.canManageUsers && nav.openUsers != null)
          YorksOverviewAction(
            icon: Icons.manage_accounts_outlined,
            label: t(_S.userManagement),
            onTap: nav.openUsers,
          ),
        if (input.canBrowseInventory && nav.openInventory != null)
          YorksOverviewAction(
            icon: Icons.inventory_outlined,
            label: t(_S.browseInventory),
            onTap: nav.openInventory,
          ),
      ]),
      kpis: [
        kpi(
          id: 'approve',
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiApprovalsWaiting),
          value: workLoad.isReadyValue ? approvals.length : null,
          load: workLoad,
          caption: oldestCaption(approvals),
          target: 'appr',
          tab: 'approve',
          actionable: true,
        ),
        kpi(
          id: 'supply',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiCannotSupply),
          value: input.exceptions.hasValue ? cannotSupply.length : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiCannotSupplySub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'supply',
        ),
        kpi(
          id: 'stock',
          icon: Icons.inventory_2_outlined,
          tone: YorksOverviewTone.orange,
          label: t(_S.belowMinimumStock),
          value: input.inventory?.hasValue == true ? stock.length : null,
          load: _loadOf(input.inventory),
          caption: t(_S.readOnly),
          target: 'stock',
        ),
        kpi(
          id: 'nope',
          icon: Icons.account_tree_outlined,
          tone: YorksOverviewTone.gold,
          label: t(_S.kpiNoProjectEngineer),
          value: input.portfolio.hasValue ? noPe.length : null,
          load: _loadOf(input.portfolio),
          caption: t(_S.kpiNoProjectEngineerSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'nope',
        ),
        kpi(
          id: 'open',
          icon: Icons.assignment_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiOpenRequests),
          value: counts?.open,
          caption: t(_S.kpiOpenRequestsSub),
          target: 'flow',
        ),
      ],
      left: [
        approvalsQueue(t(_S.smeApprovalsSub)),
        exceptionList(
          id: 'supply',
          title: t(_S.supplyConstraints),
          subtitle: t(_S.supplyConstraintsSub),
          filter: (s) =>
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.unavailableSupply,
              ) ||
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.partialArrangement,
              ) ||
              s.exceptionCodes.contains(
                YorksV1MaterialRequestExceptionCode.lateExternalSupply,
              ),
        ),
      ],
      right: [
        YorksOverviewListSection(
          id: 'nope',
          icon: Icons.account_tree_outlined,
          title: t(_S.projectsWithoutPe),
          subtitle: t(_S.projectsWithoutPeSub),
          items: [
            for (final p in noPe)
              YorksOverviewListItem(
                icon: Icons.account_tree_outlined,
                tone: YorksOverviewTone.gold,
                title: '${p.project.reference} · ${p.project.name}',
                detail: YorksV1ProjectStrings.stateLabel(
                  p.project.state,
                ).active(lang),
                trailing: t(_S.assign),
                trailingEmphasis: YorksOverviewEmphasis.warn,
                onTap: () => nav.openProject(p.project.id),
              ),
          ],
          emptyText: t(_S.everyProjectHasPe),
          load: _loadOf(input.portfolio),
        ),
        requestPipeline(
          id: 'flow',
          title: t(_S.allMaterialRequests),
          subtitle: t(_S.requestsByStageSub),
        ),
        if (input.canBrowseInventory) stockTable(readOnly: true),
        tools(t(_S.engineeringTools)),
      ],
      phoneOrder: const ['appr', 'supply', 'nope', 'flow', 'stock'],
    );
  }

  // ─── Project Manager ────────────────────────────────────────────────────

  YorksRoleOverviewSpec projectManager() {
    final approvals = workOf({
      YorksOverviewWorkKind.approve,
      YorksOverviewWorkKind.approveArrangement,
    });
    final workLoad = _loadOf(input.myWork);
    final p = projects;
    final onHold = portfolio
        .where((i) => i.project.state == YorksV1ProjectLifecycle.onHold)
        .toList();
    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('project_manager'),
      description: t(_S.pmDescription),
      scope: t(_S.orgWide),
      actions: actions([
        YorksOverviewAction(
          icon: Icons.check_rounded,
          label: t(_S.reviewApprovals),
          onTap: nav.openRequests,
          primary: true,
        ),
        YorksOverviewAction(
          icon: Icons.account_tree_outlined,
          label: t(_S.projects),
          onTap: nav.openProjects,
        ),
      ]),
      kpis: [
        kpi(
          id: 'active',
          icon: Icons.account_tree_outlined,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiActiveProjects),
          value: p?.active,
          load: _loadOf(input.projects),
          caption: p == null
              ? ''
              : tf(_S.onHoldAndTotal, {'hold': p.onHold, 'total': p.total}),
          target: 'risk',
        ),
        kpi(
          id: 'approve',
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiApprovalsWaiting),
          value: workLoad.isReadyValue ? approvals.length : null,
          load: workLoad,
          caption: oldestCaption(approvals),
          target: 'appr',
          tab: 'approve',
          actionable: true,
        ),
        kpi(
          id: 'exc',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiDeliveryExceptions),
          value: input.exceptions.hasValue ? exceptionTotal : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiDeliveryExceptionsSub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'exc',
        ),
        kpi(
          id: 'hold',
          icon: Icons.pause_circle_outline_rounded,
          tone: YorksOverviewTone.orange,
          label: t(_S.kpiOnHold),
          value: p?.onHold,
          load: _loadOf(input.projects),
          caption: t(_S.kpiOnHoldSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'hold',
        ),
        kpi(
          id: 'open',
          icon: Icons.assignment_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiOpenRequests),
          value: counts?.open,
          caption: t(_S.kpiOpenRequestsSub),
          target: 'flow',
        ),
      ],
      top: [
        projectTable(
          id: 'risk',
          title: t(_S.projectsNeedingAttention),
          subtitle: t(_S.projectsNeedingAttentionSub),
          attentionOnly: true,
          showWaiting: false,
        ),
      ],
      left: [
        approvalsQueue(t(_S.pmApprovalsSub)),
        YorksOverviewListSection(
          id: 'hold',
          icon: Icons.pause_circle_outline_rounded,
          title: t(_S.projectsOnHold),
          subtitle: t(_S.projectsOnHoldSub),
          items: [
            for (final i in onHold)
              YorksOverviewListItem(
                icon: Icons.pause_circle_outline_rounded,
                tone: YorksOverviewTone.orange,
                title: '${i.project.reference} · ${i.project.name}',
                detail: tf(_S.sinceDate, {'date': date(i.project.updatedAt)}),
                trailing: tf(_S.daysShort, {
                  'n': input.now.difference(i.project.updatedAt).inDays,
                }),
                trailingEmphasis: YorksOverviewEmphasis.warn,
                onTap: () => nav.openProject(i.project.id),
              ),
          ],
          emptyText: t(_S.noProjectsOnHold),
          load: _loadOf(input.portfolio),
        ),
      ],
      right: [
        requestPipeline(
          id: 'flow',
          title: t(_S.allMaterialRequests),
          subtitle: t(_S.requestsByStageSub),
        ),
        exceptionList(
          id: 'exc',
          title: t(_S.deliveryExceptions),
          subtitle: t(_S.exceptionsToFollowUpSub),
        ),
        neededThisWeek(),
      ],
      phoneOrder: const ['appr', 'risk', 'exc', 'hold', 'flow'],
    );
  }

  // ─── Workshop In-Charge ─────────────────────────────────────────────────

  YorksRoleOverviewSpec workshop() {
    final approvals = workOf({
      YorksOverviewWorkKind.approve,
      YorksOverviewWorkKind.approveArrangement,
    });
    final workLoad = _loadOf(input.myWork);
    final c = counts;
    final mineOpen = mineItems
        .where(
          (s) =>
              s.state != YorksV1MaterialRequestState.draft &&
              s.state != YorksV1MaterialRequestState.closed &&
              s.state != YorksV1MaterialRequestState.cancelled,
        )
        .toList();
    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('workshop_in_charge'),
      description: t(_S.wicDescription),
      scope: t(_S.orgWide),
      actions: actions([
        newRequestAction(),
        YorksOverviewAction(
          icon: Icons.straighten_rounded,
          label: t(_S.ductSizer),
          onTap: nav.openDuctSizer,
        ),
      ]),
      kpis: [
        kpi(
          id: 'approve',
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiApprovalsWaiting),
          value: workLoad.isReadyValue ? approvals.length : null,
          load: workLoad,
          caption: oldestCaption(approvals),
          target: 'work',
          tab: 'approve',
          actionable: true,
        ),
        kpi(
          id: 'open',
          icon: Icons.assignment_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiOpenRequests),
          value: c?.open,
          caption: t(_S.kpiOpenRequestsSub),
          target: 'wpipe',
        ),
        kpi(
          id: 'ready',
          icon: Icons.inventory_2_outlined,
          tone: YorksOverviewTone.gold,
          label: t(_S.kpiReadyForDelivery),
          value: c?.dispatchReady,
          caption: t(_S.kpiReadyForDeliverySub),
          target: 'wpipe',
        ),
        kpi(
          id: 'receipt',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.green,
          label: t(_S.kpiReceiptOpen),
          value: c?.receiptPending,
          caption: t(_S.kpiReceiptOpenSub),
          target: 'work',
          tab: 'receipt',
        ),
        kpi(
          id: 'exc',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiExceptions),
          value: input.exceptions.hasValue ? exceptionTotal : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiExceptionsSub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'exc',
        ),
      ],
      left: [
        workQueue(
          id: 'work',
          icon: Icons.format_list_bulleted_rounded,
          title: t(_S.yourNextActions),
          subtitle: t(_S.yourNextActionsSub),
          tabs: [
            YorksOverviewQueueTab('all', t(_S.tabAll)),
            YorksOverviewQueueTab('approve', t(_S.tabApprove)),
            YorksOverviewQueueTab('receipt', t(_S.tabReceipts)),
            YorksOverviewQueueTab('close', t(_S.tabClose)),
            YorksOverviewQueueTab('changes', t(_S.tabChanges)),
          ],
          clearTitle: t(_S.nothingWaitingForYou),
          clearBody: t(_S.nothingWaitingForYouBody),
          footnote: t(_S.ageFootnote),
        ),
        YorksOverviewTrackSection(
          id: 'wreq',
          icon: Icons.assignment_outlined,
          title: t(_S.myRequests),
          subtitle: t(_S.myRequestsSub),
          linkLabel: t(_S.allMyRequests),
          onLink: nav.openRequests,
          stageNames: stageNames,
          items: [
            for (final s in mineOpen.take(8))
              YorksOverviewTrackItem(
                reference: ref(s),
                title: s.title ?? s.scopeName,
                stage: yorksOverviewStage(s.state),
                stageLabel: stageNames[yorksOverviewStage(s.state) - 1],
                owner: ownerOf(s),
                age: age(s.currentActionAgeHours),
                note: tagOf(s).$1,
                warning: s.exceptionCodes.isNotEmpty,
                onTap: () => nav.openRequest(s),
              ),
          ],
          emptyText: t(_S.noOpenRequests),
          load: _loadOf(input.mine),
        ),
      ],
      right: [
        requestPipeline(
          id: 'wpipe',
          title: t(_S.requestsByStage),
          subtitle: t(_S.requestsByStageSub),
        ),
        exceptionList(
          id: 'exc',
          title: t(_S.exceptionsToFollowUp),
          subtitle: t(_S.exceptionsToFollowUpSub),
        ),
        tools(t(_S.workshopTools)),
      ],
      phoneOrder: const ['work', 'wreq', 'exc', 'wpipe', 'tools'],
    );
  }

  // ─── Document Controller ────────────────────────────────────────────────

  YorksRoleOverviewSpec documentController() {
    final approvals = workOf({
      YorksOverviewWorkKind.approve,
      YorksOverviewWorkKind.approveArrangement,
    });
    final workLoad = _loadOf(input.myWork);
    final closed = input.closed?.valueOrNull;
    final c = counts;
    return YorksRoleOverviewSpec(
      greeting: greeting(),
      title: t(_S.overview),
      roleLabel: roleOf('document_controller'),
      description: t(_S.dcDescription),
      scope: t(_S.orgWide),
      actions: actions([
        YorksOverviewAction(
          icon: Icons.account_tree_outlined,
          label: t(_S.projects),
          onTap: nav.openProjects,
          primary: true,
        ),
        YorksOverviewAction(
          icon: Icons.assignment_outlined,
          label: t(_S.materialRequests),
          onTap: nav.openRequests,
        ),
      ]),
      kpis: [
        kpi(
          id: 'receipt',
          icon: Icons.local_shipping_outlined,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiReceiptOpen),
          value: c?.receiptPending,
          caption: t(_S.kpiReceiptOpenDcSub),
          target: 'flow',
        ),
        kpi(
          id: 'exc',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.orange,
          label: t(_S.kpiReceiptExceptions),
          value: input.exceptions.hasValue
              ? exceptionItems
                    .where(
                      (s) => s.exceptionCodes.any(
                        (c) =>
                            c ==
                                YorksV1MaterialRequestExceptionCode
                                    .missingReceipt ||
                            c ==
                                YorksV1MaterialRequestExceptionCode
                                    .damagedReceipt,
                      ),
                    )
                    .length
              : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiReceiptExceptionsSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'exc',
        ),
        kpi(
          id: 'ready',
          icon: Icons.archive_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiReadyToClose),
          value: c?.received,
          caption: t(_S.kpiReadyToCloseSub),
          target: 'flow',
        ),
        kpi(
          id: 'closed',
          icon: Icons.inventory_outlined,
          tone: YorksOverviewTone.green,
          label: t(_S.kpiClosedThisWeek),
          value: closed?.totalCount,
          load: _loadOf(input.closed),
          caption: t(_S.kpiClosedThisWeekSub),
          target: 'closed',
        ),
        kpi(
          id: 'approve',
          icon: Icons.check_rounded,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiApprovalsWaiting),
          value: workLoad.isReadyValue ? approvals.length : null,
          load: workLoad,
          caption: t(_S.kpiApprovalsDcSub),
          target: 'work',
          tab: 'approve',
          actionable: true,
        ),
      ],
      left: [
        workQueue(
          id: 'work',
          icon: Icons.format_list_bulleted_rounded,
          title: t(_S.waitingForYou),
          subtitle: t(_S.waitingForYouSub),
          tabs: [
            YorksOverviewQueueTab('all', t(_S.tabAll)),
            YorksOverviewQueueTab('approve', t(_S.tabApprove)),
            YorksOverviewQueueTab('receipt', t(_S.tabReceipts)),
            YorksOverviewQueueTab('close', t(_S.tabClose)),
          ],
          clearTitle: t(_S.nothingWaitingForYou),
          clearBody: t(_S.nothingWaitingForYouBody),
          footnote: t(_S.ageFootnote),
        ),
        exceptionList(
          id: 'exc',
          title: t(_S.receiptEvidence),
          subtitle: t(_S.receiptEvidenceSub),
          filter: (s) => s.exceptionCodes.any(
            (c) =>
                c == YorksV1MaterialRequestExceptionCode.missingReceipt ||
                c == YorksV1MaterialRequestExceptionCode.damagedReceipt ||
                c == YorksV1MaterialRequestExceptionCode.replacementRequired,
          ),
        ),
      ],
      right: [
        YorksOverviewListSection(
          id: 'closed',
          icon: Icons.archive_outlined,
          title: t(_S.closedThisWeek),
          subtitle: t(_S.closedThisWeekSub),
          items: [
            for (final s in _visible(input.closed))
              YorksOverviewListItem(
                icon: Icons.archive_outlined,
                tone: YorksOverviewTone.green,
                title: '${ref(s)} · ${lines(s.itemCount)}',
                detail: '${s.projectName} · ${s.scopeName}',
                trailing: date(s.updatedAt),
                trailingEmphasis: YorksOverviewEmphasis.ok,
                onTap: () => nav.openRequest(s),
              ),
          ],
          emptyText: t(_S.nothingClosedThisWeek),
          load: _loadOf(input.closed),
        ),
        requestPipeline(
          id: 'flow',
          title: t(_S.allMaterialRequests),
          subtitle: t(_S.requestsByStageSub),
        ),
      ],
      phoneOrder: const ['work', 'exc', 'closed', 'flow'],
    );
  }

  String aed(double value) =>
      'AED ${NumberFormat('#,##0.00', 'en_US').format(value)}';

  YorksOverviewMoneySection rentalCard() {
    final summary = input.rentals?.valueOrNull?.summary;
    return YorksOverviewMoneySection(
      id: 'rent',
      icon: Icons.apartment_outlined,
      title: t(_S.rentals),
      subtitle: t(_S.rentalsSub),
      linkLabel: nav.openRentals == null ? null : t(_S.rentalProperties),
      onLink: nav.openRentals,
      rows: summary == null
          ? const []
          : [
              YorksOverviewMoneyRow(
                t(_S.occupied),
                tf(_S.unitsOf, {
                  'n': summary.occupied,
                  'total': summary.totalProperties,
                }),
              ),
              YorksOverviewMoneyRow(
                t(_S.collectedThisMonth),
                aed(summary.collectedThisMonth),
                emphasis: YorksOverviewEmphasis.ok,
              ),
              YorksOverviewMoneyRow(
                t(_S.rentOutstanding),
                aed(summary.outstanding),
                emphasis: summary.outstanding > 0
                    ? YorksOverviewEmphasis.bad
                    : YorksOverviewEmphasis.none,
              ),
              YorksOverviewMoneyRow(
                t(_S.leasesExpiring),
                '${summary.expiringWithin90}',
                emphasis: summary.expiringWithin90 > 0
                    ? YorksOverviewEmphasis.warn
                    : YorksOverviewEmphasis.none,
              ),
              YorksOverviewMoneyRow(
                t(_S.chequesNeedingAttention),
                '${summary.chequeAttention}',
                emphasis: summary.chequeAttention > 0
                    ? YorksOverviewEmphasis.warn
                    : YorksOverviewEmphasis.none,
              ),
            ],
      load: _loadOf(input.rentals),
    );
  }

  YorksOverviewListSection recentActivity() {
    final events = [...?input.audit?.events]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    String when(DateTime at) {
      final local = at.toLocal();
      final today = DateUtils.dateOnly(input.now.toLocal());
      if (DateUtils.dateOnly(local) == today) {
        return DateFormat('HH:mm', 'en_US').format(local);
      }
      return date(local);
    }

    return YorksOverviewListSection(
      id: 'act',
      icon: Icons.history_rounded,
      title: t(_S.recentActivity),
      subtitle: t(_S.recentActivitySub),
      linkLabel: nav.openAudit == null ? null : t(_S.openAuditTrail),
      onLink: nav.openAudit,
      items: [
        for (final e in events.take(6))
          YorksOverviewListItem(
            icon: switch (e.severity) {
              YorksV1AuditSeverity.critical => Icons.shield_outlined,
              YorksV1AuditSeverity.warning => Icons.report_problem_outlined,
              _ => Icons.history_rounded,
            },
            tone: switch (e.severity) {
              YorksV1AuditSeverity.critical => YorksOverviewTone.red,
              YorksV1AuditSeverity.warning => YorksOverviewTone.orange,
              _ => YorksOverviewTone.blue,
            },
            title: [
              YorksV1AuditStrings.eventLabel(e.eventType, lang),
              if (e.reference.trim().isNotEmpty) e.reference,
            ].join(' · '),
            detail: [
              e.actorDisplayName,
              YorksV1AuditStrings.roleLabel(e.actorExactRole, lang),
              if (e.projectRef?.trim().isNotEmpty == true) e.projectRef!,
            ].join(' · '),
            trailing: when(e.occurredAt),
            onTap: nav.openAudit,
          ),
      ],
      emptyText: t(_S.noRecentActivity),
      load: input.audit == null
          ? YorksOverviewLoad.loading
          : YorksOverviewLoad.ready,
    );
  }

  // ─── Admin ──────────────────────────────────────────────────────────────

  YorksRoleOverviewSpec admin() {
    final p = projects;
    final c = counts;
    final stock = belowMinimum();
    final noPe = portfolio
        .where(
          (i) =>
              i.activeProjectEngineerCount == 0 &&
              i.project.state != YorksV1ProjectLifecycle.archived &&
              i.project.state != YorksV1ProjectLifecycle.completed,
        )
        .length;
    return YorksRoleOverviewSpec(
      greeting: t(_S.goodDay),
      title: t(_S.overview),
      roleLabel: roleOf('admin'),
      description: t(_S.adminDescription),
      scope: t(_S.orgWide),
      actions: actions([
        newProjectAction() == null
            ? null
            : YorksOverviewAction(
                icon: Icons.add_rounded,
                label: t(_S.newProject),
                onTap: nav.newProject,
                primary: true,
              ),
        YorksOverviewAction(
          icon: Icons.assignment_outlined,
          label: t(_S.viewAllRequests),
          onTap: nav.openRequests,
        ),
        if (nav.openUsers != null)
          YorksOverviewAction(
            icon: Icons.manage_accounts_outlined,
            label: t(_S.userManagement),
            onTap: nav.openUsers,
          ),
      ]),
      kpis: [
        kpi(
          id: 'projects',
          icon: Icons.account_tree_outlined,
          tone: YorksOverviewTone.blue,
          label: t(_S.kpiActiveProjects),
          value: p?.active,
          load: _loadOf(input.projects),
          caption: p == null
              ? ''
              : tf(_S.onHoldAndTotal, {'hold': p.onHold, 'total': p.total}),
          target: 'projects',
        ),
        kpi(
          id: 'flow',
          icon: Icons.assignment_outlined,
          tone: YorksOverviewTone.violet,
          label: t(_S.kpiOpenRequests),
          value: c?.open,
          caption: c == null
              ? ''
              : tf(_S.waitingApprovalOrArrangement, {
                  'n': c.approvals + c.newToArrange,
                }),
          target: 'flow',
        ),
        kpi(
          id: 'exc',
          icon: Icons.report_problem_outlined,
          tone: YorksOverviewTone.red,
          label: t(_S.kpiDeliveryExceptions),
          value: input.exceptions.hasValue ? exceptionTotal : null,
          load: _loadOf(input.exceptions),
          caption: t(_S.kpiDeliveryExceptionsSub),
          emphasis: YorksOverviewEmphasis.bad,
          target: 'exc',
        ),
        kpi(
          id: 'stock',
          icon: Icons.inventory_2_outlined,
          tone: YorksOverviewTone.orange,
          label: t(_S.belowMinimumStock),
          value: input.inventory?.hasValue == true ? stock.length : null,
          load: _loadOf(input.inventory),
          caption: tf(_S.outOfStockCount, {
            'n': inventory?.summary.outOfStockCount ?? 0,
          }),
          target: 'stock',
        ),
        kpi(
          id: 'nope',
          icon: Icons.person_off_outlined,
          tone: YorksOverviewTone.gold,
          label: t(_S.kpiNoProjectEngineer),
          value: input.portfolio.hasValue ? noPe : null,
          load: _loadOf(input.portfolio),
          caption: t(_S.kpiNoProjectEngineerSub),
          emphasis: YorksOverviewEmphasis.warn,
          target: 'projects',
        ),
      ],
      left: [
        exceptionList(
          id: 'exc',
          title: t(_S.deliveryExceptions),
          subtitle: t(_S.exceptionsToFollowUpSub),
        ),
        if (input.audit != null || input.auditLoading) recentActivity(),
        if (input.canBrowseInventory) stockTable(readOnly: false),
      ],
      right: [
        requestPipeline(
          id: 'flow',
          title: t(_S.allMaterialRequests),
          subtitle: c == null
              ? t(_S.requestsByStageSub)
              : tf(_S.totalRequestsSub, {'n': c.total}),
        ),
        if (input.rentals != null) rentalCard(),
        neededThisWeek(),
      ],
      top: [
        projectTable(
          id: 'projects',
          title: t(_S.projectsNeedingAttention),
          subtitle: t(_S.projectsNeedingAttentionSub),
          attentionOnly: true,
          showWaiting: false,
        ),
      ],
      phoneOrder: const ['projects', 'exc', 'flow', 'act', 'rent', 'stock'],
    );
  }
}

extension on YorksOverviewLoad {
  bool get isReadyValue => this == YorksOverviewLoad.ready;
}
