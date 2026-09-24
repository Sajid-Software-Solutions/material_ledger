import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'yorks_v1_domain_error.dart';
import 'yorks_v1_item_description.dart';
import 'yorks_v1_team_chat.dart';

const Object _keep = Object();

/// Keeps controlled Material Request and Delivery Order descriptions legible
/// without changing the remainder of a user-entered material name.
String normalizeYorksV1MaterialRequestItemDescription(String value) {
  return normalizeYorksV1ItemDescription(value);
}

/// A controlled request timing value. The server independently enforces the
/// scheduled-date rule; this enum is only a typed client representation.
enum YorksV1MaterialRequestTiming {
  urgent('urgent'),
  normal('normal'),
  scheduled('scheduled');

  const YorksV1MaterialRequestTiming(this.wireValue);

  final String wireValue;

  static YorksV1MaterialRequestTiming? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final timing in values) {
      if (timing.wireValue == value) return timing;
    }
    return null;
  }
}

/// Presentation intent for the shared draft route. It prevents a generated
/// local UUID from being mistaken for an existing normalized request.
enum YorksV1MaterialRequestDraftEntryMode {
  newDraft('new'),
  resumePrivateDraft('private'),
  resumeSavedDraft('saved'),
  editExistingRequest('edit'),
  legacy('legacy');

  const YorksV1MaterialRequestDraftEntryMode(this.wireValue);

  final String wireValue;

  bool get loadsNormalizedRequest =>
      this == resumeSavedDraft || this == editExistingRequest;

  static YorksV1MaterialRequestDraftEntryMode fromWireValue(Object? value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return legacy;
  }
}

/// The immutable state machine for normalized Yorks material requests.
enum YorksV1MaterialRequestState {
  draft('draft'),
  submitted('submitted'),
  awaitingRequestApproval('awaiting_request_approval'),
  changesRequested('changes_requested'),
  approvedForArrangement('approved_for_arrangement'),
  arranging('arranging'),
  awaitingApproval('awaiting_approval'),
  approved('approved'),
  partiallyDispatched('partially_dispatched'),
  dispatched('dispatched'),
  partiallyReceived('partially_received'),
  received('received'),
  closed('closed'),
  cancelled('cancelled');

  const YorksV1MaterialRequestState(this.wireValue);

  final String wireValue;

  static YorksV1MaterialRequestState? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }

  bool get isDraft => this == YorksV1MaterialRequestState.draft;
  bool get isSubmittedOrLater => !isDraft;
}

/// The coarse phone-register groups are deliberately defined once so the
/// server query and the local fallback cannot disagree about which workflow
/// records belong under the same tab.
const yorksV1MaterialRequestSubmittedRegisterStates =
    <YorksV1MaterialRequestState>{
      YorksV1MaterialRequestState.submitted,
      YorksV1MaterialRequestState.awaitingRequestApproval,
      YorksV1MaterialRequestState.changesRequested,
      YorksV1MaterialRequestState.approvedForArrangement,
      YorksV1MaterialRequestState.arranging,
      YorksV1MaterialRequestState.awaitingApproval,
    };

const yorksV1MaterialRequestApprovedRegisterStates =
    <YorksV1MaterialRequestState>{
      YorksV1MaterialRequestState.approved,
      YorksV1MaterialRequestState.partiallyDispatched,
      YorksV1MaterialRequestState.dispatched,
      YorksV1MaterialRequestState.partiallyReceived,
      YorksV1MaterialRequestState.received,
      YorksV1MaterialRequestState.closed,
    };

class YorksV1MaterialRequestMention {
  const YorksV1MaterialRequestMention({
    required this.authUserId,
    required this.displayName,
    required this.exactRole,
  });

  final String authUserId;
  final String displayName;
  final String exactRole;

  factory YorksV1MaterialRequestMention.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestMention(
    authUserId: _requiredString(json, 'auth_user_id'),
    displayName: _requiredString(json, 'display_name'),
    exactRole: _requiredString(json, 'exact_role'),
  );
}

class YorksV1MaterialRequestComment {
  YorksV1MaterialRequestComment({
    required this.id,
    required this.requestId,
    required this.body,
    required this.authorAuthUserId,
    required this.authorRole,
    required this.authorExactRole,
    required this.authorDisplayName,
    required this.createdAt,
    required List<YorksV1MaterialRequestMention> mentions,
    List<YorksV1ChatAttachment> attachments = const [],
    this.conversationId,
    this.parentCommentId,
    this.replyPreview,
    this.contextType,
    this.contextEntityId,
  }) : mentions = List.unmodifiable(mentions),
       attachments = List.unmodifiable(attachments);

  final String id;
  final String requestId;
  final String body;
  final String authorAuthUserId;
  final String authorRole;
  final String authorExactRole;
  final String authorDisplayName;
  final DateTime createdAt;
  final List<YorksV1MaterialRequestMention> mentions;
  final List<YorksV1ChatAttachment> attachments;
  final String? conversationId;
  final String? parentCommentId;
  final YorksV1ChatReplyPreview? replyPreview;
  final String? contextType;
  final String? contextEntityId;

  factory YorksV1MaterialRequestComment.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestComment(
    id: _requiredString(json, 'id'),
    requestId: _requiredString(json, 'request_id'),
    body: _requiredString(json, 'body'),
    authorAuthUserId: _requiredString(json, 'author_auth_user_id'),
    authorRole: _requiredString(json, 'author_role'),
    authorExactRole: _requiredString(json, 'author_exact_role'),
    authorDisplayName: _requiredString(json, 'author_display_name'),
    createdAt: _requiredDate(json, 'created_at'),
    mentions: _maps(
      json['mentions'],
    ).map(YorksV1MaterialRequestMention.fromRpcJson).toList(growable: false),
    attachments: _maps(
      json['attachments'],
    ).map(YorksV1ChatAttachment.fromRpcJson).toList(growable: false),
    conversationId: _trimToNull(json['conversation_id']),
    parentCommentId: _trimToNull(json['parent_comment_id']),
    replyPreview: json['reply_preview'] is Map
        ? YorksV1ChatReplyPreview.fromRpcJson(
            Map<String, dynamic>.from(json['reply_preview'] as Map),
          )
        : null,
    contextType: json['context'] is Map
        ? _trimToNull((json['context'] as Map)['type'])
        : null,
    contextEntityId: json['context'] is Map
        ? _trimToNull((json['context'] as Map)['entity_id'])
        : null,
  );
}

class YorksV1MaterialRequestCommentPage {
  YorksV1MaterialRequestCommentPage({
    required List<YorksV1MaterialRequestComment> items,
    required this.hasMore,
    this.nextBeforeCreatedAt,
    this.nextBeforeId,
  }) : items = List.unmodifiable(items);

  final List<YorksV1MaterialRequestComment> items;
  final bool hasMore;
  final DateTime? nextBeforeCreatedAt;
  final String? nextBeforeId;

  factory YorksV1MaterialRequestCommentPage.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestCommentPage(
    items: _maps(
      json['items'],
    ).map(YorksV1MaterialRequestComment.fromRpcJson).toList(growable: false),
    hasMore: json['has_more'] == true,
    nextBeforeCreatedAt: _nullableDate(json['next_before_created_at']),
    nextBeforeId: _trimToNull(json['next_before_id']),
  );
}

class YorksV1MaterialRequestWorkAssignment {
  const YorksV1MaterialRequestWorkAssignment({
    required this.requestId,
    required this.assignmentVersion,
    required this.canManage,
    this.assigneeAuthUserId,
    this.assigneeDisplayName,
    this.assigneeExactRole,
    this.assignedAt,
  });

  final String requestId;
  final int assignmentVersion;
  final String? assigneeAuthUserId;
  final String? assigneeDisplayName;
  final String? assigneeExactRole;
  final DateTime? assignedAt;
  final bool canManage;

  bool get isAssigned => assigneeAuthUserId != null;

  factory YorksV1MaterialRequestWorkAssignment.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestWorkAssignment(
    requestId: _requiredString(json, 'request_id'),
    assignmentVersion: _nonNegativeInt(json['assignment_version']),
    assigneeAuthUserId: _trimToNull(json['assignee_auth_user_id']),
    assigneeDisplayName: _trimToNull(json['assignee_display_name']),
    assigneeExactRole: _trimToNull(json['assignee_exact_role']),
    assignedAt: _nullableDate(json['assigned_at']),
    canManage: json['can_manage'] == true,
  );
}

class YorksV1MaterialRequestChangeSummary {
  const YorksV1MaterialRequestChangeSummary({
    required this.fromRequestVersion,
    required this.toRequestVersion,
    required this.itemsAdded,
    required this.itemsRemoved,
    required this.quantityOrUnitChanged,
    required this.descriptionChanged,
    required this.titleChanged,
    required this.timingChanged,
    required this.deliveryNoteChanged,
  });

  final int fromRequestVersion;
  final int toRequestVersion;
  final int itemsAdded;
  final int itemsRemoved;
  final int quantityOrUnitChanged;
  final int descriptionChanged;
  final bool titleChanged;
  final bool timingChanged;
  final bool deliveryNoteChanged;

  bool get hasChanges =>
      itemsAdded > 0 ||
      itemsRemoved > 0 ||
      quantityOrUnitChanged > 0 ||
      descriptionChanged > 0 ||
      titleChanged ||
      timingChanged ||
      deliveryNoteChanged;

  factory YorksV1MaterialRequestChangeSummary.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestChangeSummary(
    fromRequestVersion: _positiveInt(json['from_request_version']),
    toRequestVersion: _positiveInt(json['to_request_version']),
    itemsAdded: _nonNegativeInt(json['items_added']),
    itemsRemoved: _nonNegativeInt(json['items_removed']),
    quantityOrUnitChanged: _nonNegativeInt(json['quantity_or_unit_changed']),
    descriptionChanged: _nonNegativeInt(json['description_changed']),
    titleChanged: json['title_changed'] == true,
    timingChanged: json['timing_changed'] == true,
    deliveryNoteChanged: json['delivery_note_changed'] == true,
  );
}

class YorksV1MaterialRequestSummary {
  const YorksV1MaterialRequestSummary({
    required this.id,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.scopeId,
    required this.scopeName,
    required this.state,
    required this.recordVersion,
    required this.timing,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.workAssignment,
    this.changeSummary,
    this.requestNumber,
    this.jobContractReference,
    this.title,
    this.scheduledDate,
    this.deliveryNote,
    this.requesterDisplayName,
    this.requesterProjectRole,
    this.requesterExactRole,
    this.currentActionOwnerRole,
    this.currentActionCode,
    this.currentActionStartedAt,
    this.currentActionAgeHours = 0,
    this.requiredOnSiteOverdue = false,
    this.actorCanAct = false,
    this.exceptionCodes = const [],
    this.submittedAt,
  });

  final String id;
  final String projectId;
  final String projectReference;
  final String projectName;
  final String? jobContractReference;
  final String scopeId;
  final String scopeName;
  final YorksV1MaterialRequestState state;
  final int recordVersion;
  final String? requestNumber;
  final String? title;
  final YorksV1MaterialRequestTiming timing;
  final DateTime? scheduledDate;
  final String? deliveryNote;
  final String? requesterDisplayName;
  final String? requesterProjectRole;
  final String? requesterExactRole;
  final String? currentActionOwnerRole;
  final String? currentActionCode;
  final DateTime? currentActionStartedAt;
  final double currentActionAgeHours;
  final bool requiredOnSiteOverdue;
  final bool actorCanAct;
  final List<YorksV1MaterialRequestExceptionCode> exceptionCodes;
  final int itemCount;
  final DateTime? submittedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final YorksV1MaterialRequestWorkAssignment workAssignment;
  final YorksV1MaterialRequestChangeSummary? changeSummary;

  factory YorksV1MaterialRequestSummary.fromRpcJson(Map<String, dynamic> json) {
    final state = YorksV1MaterialRequestState.fromWireValue(json['state']);
    final timing = YorksV1MaterialRequestTiming.fromWireValue(json['timing']);
    final assignment = json['work_assignment'];
    if (state == null || timing == null || assignment is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestSummary(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      projectReference: _requiredString(json, 'project_ref'),
      projectName: _requiredString(json, 'project_name'),
      jobContractReference: _trimToNull(json['job_contract_reference']),
      scopeId: _requiredString(json, 'scope_id'),
      scopeName: _requiredString(json, 'scope_name'),
      state: state,
      recordVersion: _positiveInt(json['record_version']),
      requestNumber: _trimToNull(json['request_number']),
      title: _trimToNull(json['title']),
      timing: timing,
      scheduledDate: _nullableDate(json['scheduled_date']),
      deliveryNote: _trimToNull(json['delivery_note']),
      requesterDisplayName: _trimToNull(json['requester_display_name']),
      requesterProjectRole: _trimToNull(json['requester_project_role']),
      requesterExactRole: _trimToNull(json['requester_exact_role']),
      currentActionOwnerRole: _trimToNull(json['current_action_owner_role']),
      currentActionCode: _trimToNull(json['current_action_code']),
      currentActionStartedAt: _nullableDate(json['current_action_started_at']),
      currentActionAgeHours: _nonNegativeDouble(
        json['current_action_age_hours'],
      ),
      requiredOnSiteOverdue: json['required_on_site_overdue'] == true,
      actorCanAct: json['actor_can_act'] == true,
      exceptionCodes: _exceptionCodes(json['exception_codes']),
      itemCount: _nonNegativeInt(json['item_count']),
      submittedAt: _nullableDate(json['submitted_at']),
      createdAt: _requiredDate(json, 'created_at'),
      updatedAt: _requiredDate(json, 'updated_at'),
      workAssignment: YorksV1MaterialRequestWorkAssignment.fromRpcJson(
        Map<String, dynamic>.from(assignment),
      ),
      changeSummary: json['change_summary'] is Map
          ? YorksV1MaterialRequestChangeSummary.fromRpcJson(
              Map<String, dynamic>.from(json['change_summary'] as Map),
            )
          : null,
    );
  }
}

class YorksV1MaterialRequestSummaryMetrics {
  const YorksV1MaterialRequestSummaryMetrics({
    required this.total,
    required this.open,
    required this.inProgress,
    required this.dispatched,
    required this.received,
    required this.closed,
    this.myWork = 0,
    this.exceptions = 0,
    this.requiredDateOverdue = 0,
  });

  final int total;
  final int open;
  final int inProgress;
  final int dispatched;
  final int received;
  final int closed;
  final int myWork;
  final int exceptions;
  final int requiredDateOverdue;

  factory YorksV1MaterialRequestSummaryMetrics.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestSummaryMetrics(
    total: _nonNegativeInt(json['total']),
    open: _nonNegativeInt(json['open']),
    inProgress: _nonNegativeInt(json['in_progress']),
    dispatched: _nonNegativeInt(json['dispatched']),
    received: _nonNegativeInt(json['received']),
    closed: _nonNegativeInt(json['closed']),
    myWork: _nonNegativeInt(json['my_work'] ?? 0),
    exceptions: _nonNegativeInt(json['exceptions'] ?? 0),
    requiredDateOverdue: _nonNegativeInt(json['required_date_overdue'] ?? 0),
  );
}

/// Bounded, non-commercial read model for the first operational screen.
///
/// Counts cover the complete authorized request set, while [items] contains
/// only the newest/most relevant summary rows. No request lines, comments or
/// commercial fields are present; opening an item fetches its normal protected
/// detail projection by ID.
class YorksV1MaterialRequestOverview {
  YorksV1MaterialRequestOverview({
    required List<YorksV1MaterialRequest> items,
    required this.total,
    required this.open,
    required this.needsAction,
    required this.approvals,
    required this.deliveryExceptions,
    required this.receiptPending,
    required this.draftsAndChanges,
    required this.received,
    required this.closed,
    required this.dispatchReady,
    required this.newToArrange,
  }) : items = List.unmodifiable(items);

  final List<YorksV1MaterialRequest> items;
  final int total;
  final int open;
  final int needsAction;
  final int approvals;
  final int deliveryExceptions;
  final int receiptPending;
  final int draftsAndChanges;
  final int received;
  final int closed;
  final int dispatchReady;
  final int newToArrange;

  factory YorksV1MaterialRequestOverview.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final counts = json['counts'];
    if (counts is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final values = Map<String, dynamic>.from(counts);
    return YorksV1MaterialRequestOverview(
      items: _maps(json['items'])
          .map(YorksV1MaterialRequestSummary.fromRpcJson)
          .map((item) => item.toRegisterProjection())
          .toList(growable: false),
      total: _nonNegativeInt(values['total']),
      open: _nonNegativeInt(values['open']),
      needsAction: _nonNegativeInt(values['needs_action']),
      approvals: _nonNegativeInt(values['approvals']),
      deliveryExceptions: _nonNegativeInt(values['delivery_exceptions']),
      receiptPending: _nonNegativeInt(values['receipt_pending']),
      draftsAndChanges: _nonNegativeInt(values['drafts_and_changes']),
      received: _nonNegativeInt(values['received']),
      closed: _nonNegativeInt(values['closed']),
      dispatchReady: _nonNegativeInt(values['dispatch_ready']),
      newToArrange: _nonNegativeInt(values['new_to_arrange']),
    );
  }

  factory YorksV1MaterialRequestOverview.fromRequests({
    required List<YorksV1MaterialRequest> requests,
    required int needsAction,
    int limit = 6,
  }) => YorksV1MaterialRequestOverview(
    items: requests.take(limit.clamp(1, 15)).toList(growable: false),
    total: requests.length,
    open: requests
        .where(
          (item) =>
              item.state != YorksV1MaterialRequestState.draft &&
              item.state != YorksV1MaterialRequestState.received &&
              item.state != YorksV1MaterialRequestState.closed &&
              item.state != YorksV1MaterialRequestState.cancelled,
        )
        .length,
    needsAction: needsAction,
    approvals: requests
        .where(
          (item) =>
              item.state ==
                  YorksV1MaterialRequestState.awaitingRequestApproval ||
              item.state == YorksV1MaterialRequestState.awaitingApproval,
        )
        .length,
    deliveryExceptions: requests
        .where(
          (item) =>
              item.state == YorksV1MaterialRequestState.changesRequested ||
              item.state == YorksV1MaterialRequestState.partiallyDispatched ||
              item.state == YorksV1MaterialRequestState.partiallyReceived,
        )
        .length,
    receiptPending: requests
        .where(
          (item) =>
              item.state == YorksV1MaterialRequestState.dispatched ||
              item.state == YorksV1MaterialRequestState.partiallyReceived,
        )
        .length,
    draftsAndChanges: requests
        .where(
          (item) =>
              item.state == YorksV1MaterialRequestState.draft ||
              item.state == YorksV1MaterialRequestState.changesRequested,
        )
        .length,
    received: requests
        .where((item) => item.state == YorksV1MaterialRequestState.received)
        .length,
    closed: requests
        .where((item) => item.state == YorksV1MaterialRequestState.closed)
        .length,
    dispatchReady: requests
        .where(
          (item) =>
              item.state == YorksV1MaterialRequestState.approved ||
              item.state == YorksV1MaterialRequestState.partiallyDispatched,
        )
        .length,
    newToArrange: requests
        .where(
          (item) =>
              item.state ==
                  YorksV1MaterialRequestState.approvedForArrangement ||
              item.state == YorksV1MaterialRequestState.arranging,
        )
        .length,
  );
}

enum YorksV1MaterialRequestExceptionCode {
  unavailableSupply('unavailable_supply'),
  partialArrangement('partial_arrangement'),
  lateExternalSupply('late_external_supply'),
  missingReceipt('missing_receipt'),
  damagedReceipt('damaged_receipt'),
  replacementRequired('replacement_required'),
  overdueReturn('overdue_return');

  const YorksV1MaterialRequestExceptionCode(this.wireValue);

  final String wireValue;

  static YorksV1MaterialRequestExceptionCode? fromWireValue(Object? value) {
    final wireValue = value?.toString().trim();
    for (final code in values) {
      if (code.wireValue == wireValue) return code;
    }
    return null;
  }
}

class YorksV1MaterialRequestOperationsDashboard {
  const YorksV1MaterialRequestOperationsDashboard({
    required this.myWorkCount,
    required this.exceptionRequestCount,
    required this.requiredDateOverdueCount,
    required this.actionDuePolicy,
    required this.outstandingReplacementQuantity,
    this.averageApprovalHours,
    this.averageArrangementHours,
    this.warehouseFillRatePercent,
    this.averageReceiptTurnaroundHours,
    this.averageReturnClosureHours,
  });

  final int myWorkCount;
  final int exceptionRequestCount;
  final int requiredDateOverdueCount;
  final String actionDuePolicy;
  final double? averageApprovalHours;
  final double? averageArrangementHours;
  final double? warehouseFillRatePercent;
  final double? averageReceiptTurnaroundHours;
  final String outstandingReplacementQuantity;
  final double? averageReturnClosureHours;

  factory YorksV1MaterialRequestOperationsDashboard.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestOperationsDashboard(
    myWorkCount: _nonNegativeInt(json['my_work_count']),
    exceptionRequestCount: _nonNegativeInt(json['exception_request_count']),
    requiredDateOverdueCount: _nonNegativeInt(
      json['required_date_overdue_count'],
    ),
    actionDuePolicy: _trimToNull(json['action_due_policy']) ?? 'not_configured',
    averageApprovalHours: _nullableDouble(json['average_approval_hours']),
    averageArrangementHours: _nullableDouble(json['average_arrangement_hours']),
    warehouseFillRatePercent: _nullableDouble(
      json['warehouse_fill_rate_percent'],
    ),
    averageReceiptTurnaroundHours: _nullableDouble(
      json['average_receipt_turnaround_hours'],
    ),
    outstandingReplacementQuantity:
        _trimToNull(json['outstanding_replacement_quantity']) ?? '0',
    averageReturnClosureHours: _nullableDouble(
      json['average_return_closure_hours'],
    ),
  );
}

class YorksV1MaterialRequestSummaryPage {
  YorksV1MaterialRequestSummaryPage({
    required List<YorksV1MaterialRequestSummary> items,
    required this.totalCount,
    required this.limit,
    required this.offset,
    required this.hasMore,
    required this.metrics,
  }) : items = List.unmodifiable(items);

  final List<YorksV1MaterialRequestSummary> items;
  final int totalCount;
  final int limit;
  final int offset;
  final bool hasMore;
  final YorksV1MaterialRequestSummaryMetrics metrics;

  factory YorksV1MaterialRequestSummaryPage.fromRpcJson(
    Map<String, dynamic> json,
  ) {
    final metrics = json['metrics'];
    if (metrics is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequestSummaryPage(
      items: _maps(
        json['items'],
      ).map(YorksV1MaterialRequestSummary.fromRpcJson).toList(growable: false),
      totalCount: _nonNegativeInt(json['total_count']),
      limit: _positiveInt(json['limit']),
      offset: _nonNegativeInt(json['offset']),
      hasMore: json['has_more'] == true,
      metrics: YorksV1MaterialRequestSummaryMetrics.fromRpcJson(
        Map<String, dynamic>.from(metrics),
      ),
    );
  }
}

enum YorksV1MaterialRequestRegisterView {
  total('total'),
  mine('mine'),
  assigned('assigned'),
  myWork('my_work'),
  exceptions('exceptions');

  const YorksV1MaterialRequestRegisterView(this.wireValue);

  final String wireValue;
}

class YorksV1MaterialRequestSummaryQuery {
  YorksV1MaterialRequestSummaryQuery({
    this.projectId,
    this.search,
    List<YorksV1MaterialRequestState>? states,
    this.scopeId,
    this.requester,
    this.updatedAfter,
    this.attentionOnly = false,
    this.metric = 'all',
    this.registerView = YorksV1MaterialRequestRegisterView.total,
    this.newestFirst = true,
    this.limit = 15,
    this.offset = 0,
  }) : states = List.unmodifiable(states ?? const []);

  final String? projectId;
  final String? search;
  final List<YorksV1MaterialRequestState> states;
  final String? scopeId;
  final String? requester;
  final DateTime? updatedAfter;
  final bool attentionOnly;
  final String metric;
  final YorksV1MaterialRequestRegisterView registerView;
  final bool newestFirst;
  final int limit;
  final int offset;

  YorksV1MaterialRequestSummaryQuery copyWith({
    int? limit,
    int? offset,
    YorksV1MaterialRequestRegisterView? registerView,
  }) => YorksV1MaterialRequestSummaryQuery(
    projectId: projectId,
    search: search,
    states: states,
    scopeId: scopeId,
    requester: requester,
    updatedAfter: updatedAfter,
    attentionOnly: attentionOnly,
    metric: metric,
    registerView: registerView ?? this.registerView,
    newestFirst: newestFirst,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );

  Map<String, Object?> toRpcParameters() => {
    'p_project_id': _trimToNull(projectId),
    'p_search': _trimToNull(search),
    'p_states': states.isEmpty
        ? null
        : states.map((state) => state.wireValue).toList(growable: false),
    'p_scope_id': _trimToNull(scopeId),
    'p_requester': _trimToNull(requester),
    'p_updated_after': updatedAfter?.toUtc().toIso8601String(),
    'p_attention_only': attentionOnly,
    'p_metric': metric,
    'p_register_view': registerView.wireValue,
    'p_sort': newestFirst ? 'updated_desc' : 'updated_asc',
    'p_limit': limit,
    'p_offset': offset,
  };

  @override
  bool operator ==(Object other) =>
      other is YorksV1MaterialRequestSummaryQuery &&
      other.projectId == projectId &&
      other.search == search &&
      _sameStates(other.states, states) &&
      other.scopeId == scopeId &&
      other.requester == requester &&
      other.updatedAfter == updatedAfter &&
      other.attentionOnly == attentionOnly &&
      other.metric == metric &&
      other.registerView == registerView &&
      other.newestFirst == newestFirst &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(
    projectId,
    search,
    Object.hashAll(states),
    scopeId,
    requester,
    updatedAfter,
    attentionOnly,
    metric,
    registerView,
    newestFirst,
    limit,
    offset,
  );
}

bool _sameStates(
  List<YorksV1MaterialRequestState> left,
  List<YorksV1MaterialRequestState> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class YorksV1MaterialRequestDecision {
  const YorksV1MaterialRequestDecision({
    required this.id,
    required this.decision,
    required this.requestRecordVersion,
    required this.decidedByDisplayName,
    required this.decidedByRole,
    required this.decidedByExactRole,
    required this.decidedAt,
    this.reason,
  });

  final String id;
  final String decision;
  final String? reason;
  final int requestRecordVersion;
  final String decidedByDisplayName;
  final String decidedByRole;
  final String decidedByExactRole;
  final DateTime decidedAt;

  factory YorksV1MaterialRequestDecision.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestDecision(
    id: _requiredString(json, 'id'),
    decision: _requiredString(json, 'decision'),
    reason: _trimToNull(json['reason']),
    requestRecordVersion: _positiveInt(json['request_record_version']),
    decidedByDisplayName: _requiredString(json, 'decided_by_display_name'),
    decidedByRole: _requiredString(json, 'decided_by_role'),
    decidedByExactRole: _requiredString(json, 'decided_by_exact_role'),
    decidedAt: _requiredDate(json, 'decided_at'),
  );
}

enum YorksV1MaterialRequestSuggestionSource {
  selectedScopeBoq('scope_boq'),
  projectBoq('project_boq'),
  inventory('inventory');

  const YorksV1MaterialRequestSuggestionSource(this.wireValue);

  final String wireValue;

  static YorksV1MaterialRequestSuggestionSource fromWireValue(Object? value) =>
      switch (value) {
        'scope_boq' => YorksV1MaterialRequestSuggestionSource.selectedScopeBoq,
        'project_boq' => YorksV1MaterialRequestSuggestionSource.projectBoq,
        _ => YorksV1MaterialRequestSuggestionSource.inventory,
      };
}

/// A non-commercial material discovery result. The historical class name is
/// retained for source compatibility, but results may now come from the
/// selected BOQ scope, another BOQ scope in the project, or inventory.
class YorksV1MaterialRequestInventorySuggestion {
  const YorksV1MaterialRequestInventorySuggestion({
    required this.id,
    required this.description,
    required this.unit,
    this.source = YorksV1MaterialRequestSuggestionSource.inventory,
    this.itemCode,
    this.brandOrigin,
    this.size,
    this.model,
    this.equipmentTag,
    this.sourceBoqGroupId,
    this.sourceBoqRowId,
    this.sourceScopeId,
    this.sourceScopeName,
    this.sourceGroupName,
  });

  final String id;
  final YorksV1MaterialRequestSuggestionSource source;
  final String? itemCode;
  final String description;
  final String? brandOrigin;
  final String? size;
  final String? model;
  final String? equipmentTag;
  final String unit;
  final String? sourceBoqGroupId;
  final String? sourceBoqRowId;
  final String? sourceScopeId;
  final String? sourceScopeName;
  final String? sourceGroupName;

  bool get retainsBoqProvenance =>
      source == YorksV1MaterialRequestSuggestionSource.selectedScopeBoq &&
      sourceBoqGroupId != null &&
      sourceBoqRowId != null;

  factory YorksV1MaterialRequestInventorySuggestion.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestInventorySuggestion(
    id: _requiredString(json, 'id'),
    source: YorksV1MaterialRequestSuggestionSource.fromWireValue(
      json['source_kind'],
    ),
    itemCode: _trimToNull(json['item_code']),
    description: _requiredString(json, 'item_description'),
    brandOrigin: _trimToNull(json['brand_origin']),
    size: _trimToNull(json['size']),
    model: _trimToNull(json['model']),
    equipmentTag: _trimToNull(json['equipment_tag']),
    unit: _requiredString(json, 'unit'),
    sourceBoqGroupId: _trimToNull(json['source_boq_group_id']),
    sourceBoqRowId: _trimToNull(json['source_boq_row_id']),
    sourceScopeId: _trimToNull(json['source_scope_id']),
    sourceScopeName: _trimToNull(json['source_scope_name']),
    sourceGroupName: _trimToNull(json['source_group_name']),
  );
}

/// The source snapshot is retained for traceability only. BOQ changes after a
/// line is copied never rewrite this request line.
enum YorksV1MaterialRequestLineSource {
  boq('boq'),
  excel('excel'),
  custom('custom');

  const YorksV1MaterialRequestLineSource(this.wireValue);

  final String wireValue;

  static YorksV1MaterialRequestLineSource fromWireValue(Object? value) {
    if (value is String) {
      for (final source in values) {
        if (source.wireValue == value) return source;
      }
    }
    return YorksV1MaterialRequestLineSource.custom;
  }
}

/// Minimal non-commercial project picker record for MR drafting. It is not a
/// project workspace projection and intentionally carries no party/cost data.
class YorksV1MaterialRequestProjectOption {
  const YorksV1MaterialRequestProjectOption({
    required this.id,
    required this.reference,
    required this.name,
    required this.state,
  });

  final String id;
  final String reference;
  final String name;
  final String state;

  factory YorksV1MaterialRequestProjectOption.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestProjectOption(
    id: _requiredString(json, 'id'),
    reference: _requiredString(json, 'project_ref'),
    name: _requiredString(json, 'name'),
    state: _requiredString(json, 'state'),
  );
}

/// Minimal scope picker record. Common is an explicit system-provided scope,
/// never an instruction to multiply the same line across physical buildings.
class YorksV1MaterialRequestScopeOption {
  const YorksV1MaterialRequestScopeOption({
    required this.id,
    required this.projectId,
    required this.name,
    required this.kind,
    this.deliveryAddress,
  });

  final String id;
  final String projectId;
  final String name;
  final String kind;
  final String? deliveryAddress;

  bool get isCommon => kind == 'common';

  factory YorksV1MaterialRequestScopeOption.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestScopeOption(
    id: _requiredString(json, 'id'),
    projectId: _requiredString(json, 'project_id'),
    name: _requiredString(json, 'name'),
    kind: _requiredString(json, 'scope_kind'),
    deliveryAddress: _trimToNull(json['delivery_address']),
  );
}

/// One controlled MR line. Quantities are decimal text on the client to avoid
/// treating a Dart binary double as a commercial or transaction authority.
class YorksV1MaterialRequestLine {
  const YorksV1MaterialRequestLine({
    required this.id,
    required this.displayOrder,
    required this.source,
    required this.description,
    required this.quantity,
    required this.unit,
    this.brandOrigin,
    this.size,
    this.model,
    this.equipmentTag,
    this.planningModelTag,
    this.quantityIsSuggested = false,
    this.sourceBoqGroupId,
    this.sourceBoqRowId,
    this.unitCost,
    this.totalCost,
    this.currencyCode,
  });

  final String id;
  final int displayOrder;
  final YorksV1MaterialRequestLineSource source;
  final String description;
  final String? brandOrigin;

  /// Non-commercial technical context copied from BOQ/import rows. A model or
  /// equipment tag is intentionally separate from the manufacturer serial
  /// captured during receipt/asset registration.
  final String? size;
  final String? model;
  final String? equipmentTag;

  /// Compatibility field for pre-R35-size/model/tag records. New records use
  /// [model] and [equipmentTag] so source semantics are not collapsed.
  final String? planningModelTag;
  final bool quantityIsSuggested;
  final String quantity;
  final String unit;
  final String? sourceBoqGroupId;
  final String? sourceBoqRowId;

  /// These fields are present only in a server-authorized commercial
  /// projection. They are never persisted in a local engineering draft.
  final String? unitCost;
  final String? totalCost;
  final String? currencyCode;

  YorksV1MaterialRequestLine copyWith({
    YorksV1MaterialRequestLineSource? source,
    String? description,
    Object? brandOrigin = _keep,
    Object? size = _keep,
    Object? model = _keep,
    Object? equipmentTag = _keep,
    Object? planningModelTag = _keep,
    String? quantity,
    String? unit,
    bool? quantityIsSuggested,
    Object? sourceBoqGroupId = _keep,
    Object? sourceBoqRowId = _keep,
  }) => YorksV1MaterialRequestLine(
    id: id,
    displayOrder: displayOrder,
    source: source ?? this.source,
    description: description == null
        ? this.description
        : normalizeYorksV1MaterialRequestItemDescription(description),
    brandOrigin: identical(brandOrigin, _keep)
        ? this.brandOrigin
        : normalizeYorksV1OptionalItemText(brandOrigin),
    size: identical(size, _keep)
        ? this.size
        : normalizeYorksV1OptionalItemText(size),
    model: identical(model, _keep)
        ? this.model
        : normalizeYorksV1OptionalItemText(model),
    equipmentTag: identical(equipmentTag, _keep)
        ? this.equipmentTag
        : normalizeYorksV1OptionalItemText(equipmentTag),
    planningModelTag: identical(planningModelTag, _keep)
        ? this.planningModelTag
        : normalizeYorksV1OptionalItemText(planningModelTag),
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    quantityIsSuggested:
        quantityIsSuggested ??
        (quantity != null && quantity.trim() != this.quantity.trim()
            ? false
            : this.quantityIsSuggested),
    sourceBoqGroupId: identical(sourceBoqGroupId, _keep)
        ? this.sourceBoqGroupId
        : _trimToNull(sourceBoqGroupId),
    sourceBoqRowId: identical(sourceBoqRowId, _keep)
        ? this.sourceBoqRowId
        : _trimToNull(sourceBoqRowId),
    unitCost: unitCost,
    totalCost: totalCost,
    currencyCode: currencyCode,
  );

  bool get hasDescription => description.trim().isNotEmpty;

  bool get hasControlledUnit => unit.trim().isNotEmpty;

  bool get hasValidQuantity => _isPositiveDecimal(quantity);

  bool get hasValidOperationalValues =>
      hasDescription && hasControlledUnit && hasValidQuantity;

  Map<String, dynamic> toDraftJson() => {
    'id': id,
    'displayOrder': displayOrder,
    'source': source.wireValue,
    'description': normalizeYorksV1MaterialRequestItemDescription(description),
    'brandOrigin': normalizeYorksV1OptionalItemText(brandOrigin),
    'size': normalizeYorksV1OptionalItemText(size),
    'model': normalizeYorksV1OptionalItemText(model),
    'equipmentTag': normalizeYorksV1OptionalItemText(equipmentTag),
    'planningModelTag': normalizeYorksV1OptionalItemText(planningModelTag),
    'quantityIsSuggested': quantityIsSuggested,
    'quantity': quantity,
    'unit': unit,
    'sourceBoqGroupId': sourceBoqGroupId,
    'sourceBoqRowId': sourceBoqRowId,
  };

  Map<String, dynamic> toRpcJson() {
    final safeSize = normalizeYorksV1OptionalItemText(size);
    final safeModel = normalizeYorksV1OptionalItemText(model);
    final safeEquipmentTag = normalizeYorksV1OptionalItemText(equipmentTag);
    final safePlanningModelTag = normalizeYorksV1OptionalItemText(
      planningModelTag,
    );

    // The normalized RPC preserves every canonical technical value selected
    // from BOQ. Unknown worksheet-only columns remain in the BOQ worksheet and
    // are deliberately not promoted into this controlled MR schema.
    final technicalAttributes = <String, dynamic>{};
    if (safeSize != null) {
      technicalAttributes['size'] = safeSize;
    }
    if (safeModel != null) {
      technicalAttributes['model'] = safeModel;
    }
    if (safeEquipmentTag != null) {
      technicalAttributes['equipment_tag'] = safeEquipmentTag;
    }
    if (safePlanningModelTag != null) {
      technicalAttributes['planning_model_tag'] = safePlanningModelTag;
    }
    if (source == YorksV1MaterialRequestLineSource.boq) {
      technicalAttributes['quantity_suggested'] = quantityIsSuggested;
    }
    return {
      'id': id.trim(),
      'display_order': displayOrder,
      'source_kind': source.wireValue,
      'source_boq_group_id': _trimToNull(sourceBoqGroupId),
      'source_boq_row_id': _trimToNull(sourceBoqRowId),
      'item_description': normalizeYorksV1MaterialRequestItemDescription(
        description,
      ),
      'brand_origin': normalizeYorksV1OptionalItemText(brandOrigin),
      // Always send the object because the deployed function validates that it
      // exists even when empty.
      'technical_attributes': technicalAttributes,
      'requested_qty': quantity.trim(),
      'unit': unit.trim(),
    };
  }

  factory YorksV1MaterialRequestLine.fromDraftJson(Map<String, dynamic> json) {
    return YorksV1MaterialRequestLine(
      id: _string(json['id']),
      displayOrder: _positiveInt(json['displayOrder'] ?? json['display_order']),
      source: YorksV1MaterialRequestLineSource.fromWireValue(json['source']),
      description: normalizeYorksV1MaterialRequestItemDescription(
        _string(json['description'] ?? json['item_description']),
      ),
      brandOrigin: normalizeYorksV1OptionalItemText(
        json['brandOrigin'] ?? json['brand_origin'],
      ),
      size: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'size') ?? json['size'],
      ),
      model: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'model') ?? json['model'],
      ),
      equipmentTag: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'equipment_tag') ??
            json['equipmentTag'] ??
            json['equipment_tag'],
      ),
      planningModelTag: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'planning_model_tag') ??
            json['planningModelTag'] ??
            json['planning_model_tag'],
      ),
      quantityIsSuggested:
          _technicalText(json['technical_attributes'], 'quantity_suggested') ==
              'true' ||
          json['quantityIsSuggested'] == true ||
          json['quantity_suggested'] == true,
      quantity: _string(json['quantity'] ?? json['requested_qty']),
      unit: _string(json['unit']),
      sourceBoqGroupId: _trimToNull(
        json['sourceBoqGroupId'] ?? json['source_boq_group_id'],
      ),
      sourceBoqRowId: _trimToNull(
        json['sourceBoqRowId'] ?? json['source_boq_row_id'],
      ),
    );
  }

  factory YorksV1MaterialRequestLine.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1MaterialRequestLine(
      id: _requiredString(json, 'id'),
      displayOrder: _positiveInt(json['display_order']),
      source: YorksV1MaterialRequestLineSource.fromWireValue(
        json['source_kind'],
      ),
      description: normalizeYorksV1MaterialRequestItemDescription(
        _requiredString(json, 'item_description'),
      ),
      brandOrigin: normalizeYorksV1OptionalItemText(json['brand_origin']),
      size: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'size'),
      ),
      model: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'model'),
      ),
      equipmentTag: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'equipment_tag'),
      ),
      planningModelTag: normalizeYorksV1OptionalItemText(
        _technicalText(json['technical_attributes'], 'planning_model_tag'),
      ),
      quantityIsSuggested:
          _technicalText(json['technical_attributes'], 'quantity_suggested') ==
          'true',
      quantity: _string(json['requested_qty']),
      unit: _requiredString(json, 'unit'),
      sourceBoqGroupId: _trimToNull(json['source_boq_group_id']),
      sourceBoqRowId: _trimToNull(json['source_boq_row_id']),
      unitCost: _trimToNull(json['unit_cost']),
      totalCost: _trimToNull(json['total_cost']),
      currencyCode: _trimToNull(json['currency_code']),
    );
  }
}

String? _technicalText(Object? attributes, String key) {
  if (attributes is! Map) return null;
  return _trimToNull(attributes[key]);
}

/// The server-authoritative request projection. For an unauthorized user, the
/// raw response has no commercial keys; [YorksV1MaterialRequestLine] therefore
/// carries null commercial values rather than masked or zeroed costs.
class YorksV1MaterialRequest {
  YorksV1MaterialRequest({
    required this.id,
    required this.projectId,
    required this.projectReference,
    required this.projectName,
    required this.scopeId,
    required this.scopeName,
    required this.state,
    required this.recordVersion,
    required this.createdAt,
    required this.updatedAt,
    required List<YorksV1MaterialRequestLine> lines,
    required this.timing,
    this.itemCount,
    this.canEditBeforeApproval = false,
    this.canDecideRequest = false,
    this.postApprovalEditEnabled = false,
    this.postApprovalAmendmentPending = false,
    this.procurementEditorAuthUserId,
    this.canManagePostApprovalEdit = false,
    this.canEditPostApproval = false,
    this.requestDecision,
    this.comments = const [],
    this.requestNumber,
    this.jobContractReference,
    this.title,
    this.scheduledDate,
    this.deliveryNote,
    this.requesterDisplayName,
    this.requesterProjectRole,
    this.requesterExactRole,
    this.documentIdentityVerified = false,
    this.currentActionOwnerRole,
    this.currentActionCode,
    this.currentActionStartedAt,
    this.currentActionAgeHours = 0,
    this.requiredOnSiteOverdue = false,
    this.actorCanAct = false,
    this.exceptionCodes = const [],
    this.submittedAt,
    this.cancelledAt,
    this.cancellationReason,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final String projectId;
  final String projectReference;
  final String projectName;
  final String? jobContractReference;
  final String scopeId;
  final String scopeName;
  final YorksV1MaterialRequestState state;
  final int recordVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final YorksV1MaterialRequestTiming timing;
  final bool canEditBeforeApproval;
  final bool canDecideRequest;
  final bool postApprovalEditEnabled;
  final bool postApprovalAmendmentPending;
  final String? procurementEditorAuthUserId;
  final bool canManagePostApprovalEdit;
  final bool canEditPostApproval;
  final YorksV1MaterialRequestDecision? requestDecision;
  final List<YorksV1MaterialRequestComment> comments;
  final List<YorksV1MaterialRequestLine> lines;
  final int? itemCount;
  int get displayItemCount => itemCount ?? lines.length;
  final String? requestNumber;
  final String? title;
  final DateTime? scheduledDate;
  final String? deliveryNote;
  final String? requesterDisplayName;
  final String? requesterProjectRole;

  /// The immutable exact server-controlled Auth role captured at submission.
  /// [requesterProjectRole] remains the normalized workflow role.
  final String? requesterExactRole;
  final bool documentIdentityVerified;
  final String? currentActionOwnerRole;
  final String? currentActionCode;
  final DateTime? currentActionStartedAt;
  final double currentActionAgeHours;
  final bool requiredOnSiteOverdue;
  final bool actorCanAct;
  final List<YorksV1MaterialRequestExceptionCode> exceptionCodes;
  final DateTime? submittedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  factory YorksV1MaterialRequest.fromRpcJson(Map<String, dynamic> json) {
    final state = YorksV1MaterialRequestState.fromWireValue(json['state']);
    final timing = YorksV1MaterialRequestTiming.fromWireValue(json['timing']);
    if (state == null || timing == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final rawLines = json['lines'];
    if (rawLines is! List) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    return YorksV1MaterialRequest(
      id: _requiredString(json, 'id'),
      projectId: _requiredString(json, 'project_id'),
      projectReference: _requiredString(json, 'project_ref'),
      projectName: _requiredString(json, 'project_name'),
      jobContractReference: _trimToNull(json['job_contract_reference']),
      scopeId: _requiredString(json, 'scope_id'),
      scopeName: _requiredString(json, 'scope_name'),
      state: state,
      recordVersion: _positiveInt(json['record_version']),
      createdAt: _requiredDate(json, 'created_at'),
      updatedAt: _requiredDate(json, 'updated_at'),
      timing: timing,
      canEditBeforeApproval: json['can_edit_before_approval'] == true,
      canDecideRequest: json['can_decide_request'] == true,
      postApprovalEditEnabled: json['post_approval_edit_enabled'] == true,
      postApprovalAmendmentPending:
          json['post_approval_amendment_pending'] == true,
      procurementEditorAuthUserId: _trimToNull(
        json['procurement_editor_auth_user_id'],
      ),
      canManagePostApprovalEdit: json['can_manage_post_approval_edit'] == true,
      canEditPostApproval: json['can_edit_post_approval'] == true,
      requestDecision: json['request_decision'] is Map
          ? YorksV1MaterialRequestDecision.fromRpcJson(
              Map<String, dynamic>.from(json['request_decision'] as Map),
            )
          : null,
      comments: _maps(
        json['comments'],
      ).map(YorksV1MaterialRequestComment.fromRpcJson).toList(growable: false),
      lines: [
        for (final line in rawLines)
          if (line is Map)
            YorksV1MaterialRequestLine.fromRpcJson(
              Map<String, dynamic>.from(line),
            ),
      ],
      itemCount: json['item_count'] == null
          ? null
          : _nonNegativeInt(json['item_count']),
      requestNumber: _trimToNull(json['request_number']),
      title: _trimToNull(json['title']),
      scheduledDate: _nullableDate(json['scheduled_date']),
      deliveryNote: _trimToNull(json['delivery_note']),
      requesterDisplayName: _trimToNull(json['requester_display_name']),
      requesterProjectRole: _trimToNull(json['requester_project_role']),
      requesterExactRole: _trimToNull(json['requester_exact_role']),
      documentIdentityVerified: json['document_identity_verified'] == true,
      currentActionOwnerRole: _trimToNull(json['current_action_owner_role']),
      currentActionCode: _trimToNull(json['current_action_code']),
      currentActionStartedAt: _nullableDate(json['current_action_started_at']),
      currentActionAgeHours: _nonNegativeDouble(
        json['current_action_age_hours'],
      ),
      requiredOnSiteOverdue: json['required_on_site_overdue'] == true,
      actorCanAct: json['actor_can_act'] == true,
      exceptionCodes: _exceptionCodes(json['exception_codes']),
      submittedAt: _nullableDate(json['submitted_at']),
      cancelledAt: _nullableDate(json['cancelled_at']),
      cancellationReason: _trimToNull(json['cancellation_reason']),
    );
  }
}

extension YorksV1MaterialRequestSummaryRegisterAdapter
    on YorksV1MaterialRequestSummary {
  /// Presentation-only adapter for the existing register widgets. It carries
  /// no line/comment projection; opening the row always navigates by ID and
  /// fetches the full authorized detail separately.
  YorksV1MaterialRequest toRegisterProjection() => YorksV1MaterialRequest(
    id: id,
    projectId: projectId,
    projectReference: projectReference,
    projectName: projectName,
    jobContractReference: jobContractReference,
    scopeId: scopeId,
    scopeName: scopeName,
    state: state,
    recordVersion: recordVersion,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lines: const [],
    itemCount: itemCount,
    timing: timing,
    requestNumber: requestNumber,
    title: title,
    scheduledDate: scheduledDate,
    deliveryNote: deliveryNote,
    requesterDisplayName: requesterDisplayName,
    requesterProjectRole: requesterProjectRole,
    requesterExactRole: requesterExactRole,
    currentActionOwnerRole: currentActionOwnerRole,
    currentActionCode: currentActionCode,
    currentActionStartedAt: currentActionStartedAt,
    currentActionAgeHours: currentActionAgeHours,
    requiredOnSiteOverdue: requiredOnSiteOverdue,
    actorCanAct: actorCanAct,
    exceptionCodes: exceptionCodes,
    submittedAt: submittedAt,
  );
}

/// Per-user/device recoverable input. It deliberately excludes commercial
/// values and survives an interrupted submission until the server confirms it.
class YorksV1MaterialRequestDraft {
  const YorksV1MaterialRequestDraft({
    required this.id,
    required this.ownerAuthUserId,
    required this.submissionIdempotencyKey,
    required this.updatedAt,
    this.serverRecordVersion = 0,
    this.localRevision = 0,
    this.pendingSaveOperationId,
    this.pendingSaveExpectedVersion,
    this.pendingSaveRevision,
    this.pendingSavePayloadHash,
    this.pendingSubmissionApproval,
    this.privateSyncVersion = 0,
    this.privateSyncedAt,
    this.projectId,
    this.scopeId,
    this.title,
    this.timing = YorksV1MaterialRequestTiming.normal,
    this.scheduledDate,
    this.deliveryNote,
    this.lines = const [],
  });

  static const Object _keep = Object();

  final String id;
  final String ownerAuthUserId;
  final String submissionIdempotencyKey;
  final int serverRecordVersion;
  final int localRevision;

  /// One durable logical save intent. It remains frozen across a timeout and
  /// browser restart until the authoritative receipt is found or the same
  /// idempotent operation is deliberately replayed.
  final String? pendingSaveOperationId;
  final int? pendingSaveExpectedVersion;
  final int? pendingSaveRevision;
  final String? pendingSavePayloadHash;

  /// Null means no unresolved submission. False/true freezes the original
  /// Submit/Approve intent until an authorized result check confirms it.
  final bool? pendingSubmissionApproval;
  final int privateSyncVersion;
  final DateTime? privateSyncedAt;
  final String? projectId;
  final String? scopeId;
  final String? title;
  final YorksV1MaterialRequestTiming timing;
  final DateTime? scheduledDate;
  final String? deliveryNote;
  final List<YorksV1MaterialRequestLine> lines;
  final DateTime updatedAt;

  factory YorksV1MaterialRequestDraft.empty({
    required String id,
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) => YorksV1MaterialRequestDraft(
    id: id,
    ownerAuthUserId: ownerAuthUserId,
    submissionIdempotencyKey: submissionIdempotencyKey,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  YorksV1MaterialRequestDraft copyWith({
    int? serverRecordVersion,
    int? localRevision,
    Object? pendingSaveOperationId = _keep,
    Object? pendingSaveExpectedVersion = _keep,
    Object? pendingSaveRevision = _keep,
    Object? pendingSavePayloadHash = _keep,
    Object? pendingSubmissionApproval = _keep,
    int? privateSyncVersion,
    Object? privateSyncedAt = _keep,
    Object? projectId = _keep,
    Object? scopeId = _keep,
    Object? title = _keep,
    Object? submissionIdempotencyKey = _keep,
    YorksV1MaterialRequestTiming? timing,
    Object? scheduledDate = _keep,
    Object? deliveryNote = _keep,
    List<YorksV1MaterialRequestLine>? lines,
    DateTime? updatedAt,
  }) => YorksV1MaterialRequestDraft(
    id: id,
    ownerAuthUserId: ownerAuthUserId,
    submissionIdempotencyKey: identical(submissionIdempotencyKey, _keep)
        ? this.submissionIdempotencyKey
        : submissionIdempotencyKey as String,
    serverRecordVersion: serverRecordVersion ?? this.serverRecordVersion,
    localRevision: localRevision ?? this.localRevision,
    pendingSaveOperationId: identical(pendingSaveOperationId, _keep)
        ? this.pendingSaveOperationId
        : pendingSaveOperationId as String?,
    pendingSaveExpectedVersion: identical(pendingSaveExpectedVersion, _keep)
        ? this.pendingSaveExpectedVersion
        : pendingSaveExpectedVersion as int?,
    pendingSaveRevision: identical(pendingSaveRevision, _keep)
        ? this.pendingSaveRevision
        : pendingSaveRevision as int?,
    pendingSavePayloadHash: identical(pendingSavePayloadHash, _keep)
        ? this.pendingSavePayloadHash
        : pendingSavePayloadHash as String?,
    pendingSubmissionApproval: identical(pendingSubmissionApproval, _keep)
        ? this.pendingSubmissionApproval
        : pendingSubmissionApproval as bool?,
    privateSyncVersion: privateSyncVersion ?? this.privateSyncVersion,
    privateSyncedAt: identical(privateSyncedAt, _keep)
        ? this.privateSyncedAt
        : privateSyncedAt as DateTime?,
    projectId: identical(projectId, _keep)
        ? this.projectId
        : projectId as String?,
    scopeId: identical(scopeId, _keep) ? this.scopeId : scopeId as String?,
    title: identical(title, _keep) ? this.title : title as String?,
    timing: timing ?? this.timing,
    scheduledDate: identical(scheduledDate, _keep)
        ? this.scheduledDate
        : scheduledDate as DateTime?,
    deliveryNote: identical(deliveryNote, _keep)
        ? this.deliveryNote
        : deliveryNote as String?,
    lines: List.unmodifiable(lines ?? this.lines),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool get canSubmitLocally =>
      _trimToNull(projectId) != null &&
      _trimToNull(scopeId) != null &&
      (timing != YorksV1MaterialRequestTiming.scheduled ||
          scheduledDate != null) &&
      lines.isNotEmpty &&
      lines.every((line) => line.hasValidOperationalValues);

  /// A draft is recoverable even before the server has enough information to
  /// accept it.  Save Draft therefore never uses submission validation as its
  /// gate; the controller persists this model locally and only sends it to
  /// the server once the server-side draft contract can be satisfied.
  bool get canSaveLocally => true;

  /// Local-only drafts are intentionally recoverable before they satisfy the
  /// connected save/submit contract.  Keep an empty, never-edited editor out
  /// of the resume list, but retain every meaningful field or line entered by
  /// its owner on this device.
  bool get hasRecoverableContent =>
      _trimToNull(projectId) != null ||
      _trimToNull(scopeId) != null ||
      _trimToNull(title) != null ||
      _trimToNull(deliveryNote) != null ||
      scheduledDate != null ||
      lines.isNotEmpty;

  YorksV1SaveMaterialRequestDraftInput toSaveInput() =>
      YorksV1SaveMaterialRequestDraftInput(draft: this);

  bool get hasPendingSave =>
      _trimToNull(pendingSaveOperationId) != null &&
      pendingSaveExpectedVersion != null &&
      pendingSaveRevision != null &&
      _trimToNull(pendingSavePayloadHash) != null;

  String savePayloadHash() => sha256
      .convert(utf8.encode(jsonEncode(toSaveInput().toRpcPayload())))
      .toString();

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerAuthUserId': ownerAuthUserId,
    'submissionIdempotencyKey': submissionIdempotencyKey,
    'serverRecordVersion': serverRecordVersion,
    'localRevision': localRevision,
    'pendingSaveOperationId': pendingSaveOperationId,
    'pendingSaveExpectedVersion': pendingSaveExpectedVersion,
    'pendingSaveRevision': pendingSaveRevision,
    'pendingSavePayloadHash': pendingSavePayloadHash,
    'pendingSubmissionApproval': pendingSubmissionApproval,
    'privateSyncVersion': privateSyncVersion,
    'privateSyncedAt': privateSyncedAt?.toUtc().toIso8601String(),
    'projectId': projectId,
    'scopeId': scopeId,
    'title': _trimToNull(title),
    'timing': timing.wireValue,
    'scheduledDate': _calendarDateText(scheduledDate),
    'deliveryNote': _trimToNull(deliveryNote),
    'lines': [for (final line in lines) line.toDraftJson()],
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory YorksV1MaterialRequestDraft.fromJson(Map<String, dynamic> json) {
    return YorksV1MaterialRequestDraft(
      id: _string(json['id']),
      ownerAuthUserId: _string(json['ownerAuthUserId']),
      submissionIdempotencyKey: _string(json['submissionIdempotencyKey']),
      serverRecordVersion: _nonNegativeInt(json['serverRecordVersion']),
      localRevision: _nonNegativeInt(json['localRevision']),
      pendingSaveOperationId: _trimToNull(json['pendingSaveOperationId']),
      pendingSaveExpectedVersion: json['pendingSaveExpectedVersion'] is num
          ? _nonNegativeInt(json['pendingSaveExpectedVersion'])
          : null,
      pendingSaveRevision: json['pendingSaveRevision'] is num
          ? _nonNegativeInt(json['pendingSaveRevision'])
          : null,
      pendingSavePayloadHash: _trimToNull(json['pendingSavePayloadHash']),
      pendingSubmissionApproval: json['pendingSubmissionApproval'] is bool
          ? json['pendingSubmissionApproval'] as bool
          : null,
      privateSyncVersion: _nonNegativeInt(json['privateSyncVersion']),
      privateSyncedAt: _nullableDate(json['privateSyncedAt']),
      projectId: _trimToNull(json['projectId']),
      scopeId: _trimToNull(json['scopeId']),
      title: _trimToNull(json['title']),
      timing:
          YorksV1MaterialRequestTiming.fromWireValue(json['timing']) ??
          YorksV1MaterialRequestTiming.normal,
      scheduledDate: _calendarDate(json['scheduledDate']),
      deliveryNote: _trimToNull(json['deliveryNote']),
      lines: _maps(
        json['lines'],
      ).map(YorksV1MaterialRequestLine.fromDraftJson).toList(growable: false),
      updatedAt:
          _nullableDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class YorksV1PrivateMaterialRequestDraftRecord {
  const YorksV1PrivateMaterialRequestDraftRecord({
    required this.draftId,
    required this.syncVersion,
    required this.draft,
    required this.clientUpdatedAt,
    required this.serverUpdatedAt,
  });

  final String draftId;
  final int syncVersion;
  final YorksV1MaterialRequestDraft draft;
  final DateTime clientUpdatedAt;
  final DateTime serverUpdatedAt;

  factory YorksV1PrivateMaterialRequestDraftRecord.fromRpcJson(
    Map<String, dynamic> json, {
    required String ownerAuthUserId,
    required String submissionIdempotencyKey,
  }) {
    final data = json['draft_data'];
    if (data is! Map) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unexpectedResponse,
      );
    }
    final draftData = Map<String, dynamic>.from(data);
    final syncVersion = _positiveInt(json['sync_version']);
    final serverUpdatedAt = _requiredDate(json, 'server_updated_at');
    return YorksV1PrivateMaterialRequestDraftRecord(
      draftId: _requiredString(json, 'draft_id'),
      syncVersion: syncVersion,
      clientUpdatedAt: _requiredDate(json, 'client_updated_at'),
      serverUpdatedAt: serverUpdatedAt,
      draft: YorksV1MaterialRequestDraft(
        id: _requiredString(json, 'draft_id'),
        ownerAuthUserId: ownerAuthUserId,
        submissionIdempotencyKey: submissionIdempotencyKey,
        privateSyncVersion: syncVersion,
        privateSyncedAt: serverUpdatedAt,
        projectId: _trimToNull(draftData['project_id']),
        scopeId: _trimToNull(draftData['scope_id']),
        title: _trimToNull(draftData['title']),
        timing:
            YorksV1MaterialRequestTiming.fromWireValue(draftData['timing']) ??
            YorksV1MaterialRequestTiming.normal,
        scheduledDate: _calendarDate(draftData['scheduled_date']),
        deliveryNote: _trimToNull(draftData['delivery_note']),
        lines: _maps(
          draftData['lines'],
        ).map(YorksV1MaterialRequestLine.fromDraftJson).toList(growable: false),
        updatedAt: _requiredDate(json, 'client_updated_at'),
      ),
    );
  }
}

class YorksV1SyncPrivateMaterialRequestDraftInput {
  const YorksV1SyncPrivateMaterialRequestDraftInput({
    required this.draft,
    required this.idempotencyKey,
  });

  final YorksV1MaterialRequestDraft draft;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'draft_id': draft.id.trim(),
    'expected_sync_version': draft.privateSyncVersion,
    'client_updated_at': draft.updatedAt.toUtc().toIso8601String(),
    'draft_data': {
      'project_id': _trimToNull(draft.projectId),
      'scope_id': _trimToNull(draft.scopeId),
      'title': _trimToNull(draft.title),
      'timing': draft.timing.wireValue,
      'scheduled_date': _calendarDateText(draft.scheduledDate),
      'delivery_note': _trimToNull(draft.deliveryNote),
      'lines': [for (final line in draft.lines) line.toRpcJson()],
    },
  };
}

class YorksV1AssignMaterialRequestWorkInput {
  const YorksV1AssignMaterialRequestWorkInput({
    required this.requestId,
    required this.expectedRequestVersion,
    required this.expectedAssignmentVersion,
    required this.idempotencyKey,
    this.assigneeAuthUserId,
    this.reason,
  });

  final String requestId;
  final int expectedRequestVersion;
  final int expectedAssignmentVersion;
  final String? assigneeAuthUserId;
  final String? reason;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'expected_request_version': expectedRequestVersion,
    'expected_assignment_version': expectedAssignmentVersion,
    'assignee_auth_user_id': _trimToNull(assigneeAuthUserId),
    'reason': _trimToNull(reason),
  };
}

class YorksV1SaveMaterialRequestDraftInput {
  const YorksV1SaveMaterialRequestDraftInput({required this.draft});

  final YorksV1MaterialRequestDraft draft;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': draft.id,
    'expected_version': draft.serverRecordVersion,
    'project_id': _trimToNull(draft.projectId),
    'scope_id': _trimToNull(draft.scopeId),
    'title': _trimToNull(draft.title),
    'timing': draft.timing.wireValue,
    'scheduled_date': _calendarDateText(draft.scheduledDate),
    'delivery_note': _trimToNull(draft.deliveryNote),
    'lines': [for (final line in draft.lines) line.toRpcJson()],
  };
}

class YorksV1MaterialRequestDraftSaveAcknowledgement {
  const YorksV1MaterialRequestDraftSaveAcknowledgement({
    required this.requestId,
    required this.recordVersion,
    required this.operationId,
    required this.payloadHash,
    required this.committedAt,
  });

  final String requestId;
  final int recordVersion;
  final String operationId;
  final String payloadHash;
  final DateTime committedAt;

  factory YorksV1MaterialRequestDraftSaveAcknowledgement.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestDraftSaveAcknowledgement(
    requestId: _requiredString(json, 'request_id'),
    recordVersion: _positiveInt(json['record_version']),
    operationId: _requiredString(json, 'operation_id'),
    payloadHash: _requiredString(json, 'payload_hash'),
    committedAt: _requiredDate(json, 'committed_at'),
  );
}

class YorksV1SubmitMaterialRequestInput {
  const YorksV1SubmitMaterialRequestInput({
    required this.requestId,
    required this.expectedVersion,
    required this.idempotencyKey,
  });

  final String requestId;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'expected_version': expectedVersion,
  };
}

class YorksV1UpdateMaterialRequestForApprovalInput {
  const YorksV1UpdateMaterialRequestForApprovalInput({
    required this.draft,
    required this.idempotencyKey,
  });

  final YorksV1MaterialRequestDraft draft;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => draft.toSaveInput().toRpcPayload();
}

enum YorksV1MaterialRequestReviewDecision {
  approved('approved'),
  returned('returned');

  const YorksV1MaterialRequestReviewDecision(this.wireValue);
  final String wireValue;
}

class YorksV1DecideMaterialRequestInput {
  const YorksV1DecideMaterialRequestInput({
    required this.requestId,
    required this.expectedVersion,
    required this.decision,
    required this.idempotencyKey,
    this.reason,
  });

  final String requestId;
  final int expectedVersion;
  final YorksV1MaterialRequestReviewDecision decision;
  final String? reason;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'expected_version': expectedVersion,
    'decision': decision.wireValue,
    'reason': _trimToNull(reason),
  };
}

class YorksV1AddMaterialRequestCommentInput {
  const YorksV1AddMaterialRequestCommentInput({
    required this.requestId,
    required this.body,
    required this.idempotencyKey,
    this.mentionedAuthUserIds = const [],
    this.attachmentIds = const [],
    this.parentCommentId,
    this.contextType,
    this.contextEntityId,
  });

  final String requestId;
  final String body;
  final String idempotencyKey;
  final List<String> mentionedAuthUserIds;
  final List<String> attachmentIds;
  final String? parentCommentId;
  final String? contextType;
  final String? contextEntityId;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'body': body.trim(),
    'mentioned_auth_user_ids': [
      for (final id in mentionedAuthUserIds) id.trim(),
    ],
    'attachment_ids': [for (final id in attachmentIds) id.trim()],
    if (_trimToNull(parentCommentId) != null)
      'parent_comment_id': parentCommentId!.trim(),
    if (_trimToNull(contextType) != null) 'context_type': contextType!.trim(),
    if (_trimToNull(contextEntityId) != null)
      'context_entity_id': contextEntityId!.trim(),
  };
}

class YorksV1CancelMaterialRequestInput {
  const YorksV1CancelMaterialRequestInput({
    required this.requestId,
    required this.expectedVersion,
    required this.reason,
    required this.idempotencyKey,
  });

  final String requestId;
  final int expectedVersion;
  final String reason;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'expected_version': expectedVersion,
    'reason': reason.trim(),
  };
}

class YorksV1MaterialRequestPhase3Policy {
  const YorksV1MaterialRequestPhase3Policy({
    required this.requestId,
    required this.allowAuthorizedCreatorSelfApproval,
    required this.requireExternalSourceReadiness,
    required this.canCreateReplacement,
    required this.replacementExists,
    this.replacementRequestId,
    this.replacementOfRequestId,
  });

  final String requestId;
  final bool allowAuthorizedCreatorSelfApproval;
  final bool requireExternalSourceReadiness;
  final bool canCreateReplacement;
  final bool replacementExists;
  final String? replacementRequestId;
  final String? replacementOfRequestId;

  factory YorksV1MaterialRequestPhase3Policy.fromRpcJson(
    Map<String, dynamic> json,
  ) => YorksV1MaterialRequestPhase3Policy(
    requestId: _requiredString(json, 'request_id'),
    allowAuthorizedCreatorSelfApproval:
        json['allow_authorized_creator_self_approval'] == true,
    requireExternalSourceReadiness:
        json['require_external_source_readiness'] == true,
    canCreateReplacement: json['can_create_replacement'] == true,
    replacementExists: json['replacement_exists'] == true,
    replacementRequestId: _trimToNull(json['replacement_request_id']),
    replacementOfRequestId: _trimToNull(json['replacement_of_request_id']),
  );
}

class YorksV1CreateReplacementMaterialRequestInput {
  const YorksV1CreateReplacementMaterialRequestInput({
    required this.sourceRequestId,
    required this.expectedSourceVersion,
    required this.idempotencyKey,
  });

  final String sourceRequestId;
  final int expectedSourceVersion;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'source_request_id': sourceRequestId.trim(),
    'expected_source_version': expectedSourceVersion,
  };
}

class YorksV1CloseMaterialRequestInput {
  const YorksV1CloseMaterialRequestInput({
    required this.requestId,
    required this.expectedVersion,
    required this.idempotencyKey,
  });

  final String requestId;
  final int expectedVersion;
  final String idempotencyKey;

  Map<String, dynamic> toRpcPayload() => {
    'request_id': requestId.trim(),
    'expected_version': expectedVersion,
  };
}

String _string(Object? value) => switch (value) {
  String text => text,
  num number => number.toString(),
  _ => '',
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _trimToNull(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

String? _trimToNull(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

int _nonNegativeInt(Object? value) => switch (value) {
  int integer when integer >= 0 => integer,
  num number when number >= 0 => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

int _positiveInt(Object? value) {
  final parsed = _nonNegativeInt(value);
  return parsed > 0 ? parsed : 1;
}

double _nonNegativeDouble(Object? value) {
  final parsed = _nullableDouble(value) ?? 0;
  return parsed < 0 ? 0 : parsed;
}

double? _nullableDouble(Object? value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text.trim()),
  _ => null,
};

List<YorksV1MaterialRequestExceptionCode> _exceptionCodes(Object? value) {
  if (value is! List) return const [];
  final result = <YorksV1MaterialRequestExceptionCode>[];
  for (final item in value) {
    final code = YorksV1MaterialRequestExceptionCode.fromWireValue(item);
    if (code != null) result.add(code);
  }
  return List.unmodifiable(result);
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _nullableDate(json[key]);
  if (value == null) {
    throw const YorksV1DomainException(
      YorksV1DomainErrorCode.unexpectedResponse,
    );
  }
  return value;
}

DateTime? _nullableDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

DateTime? _calendarDate(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String? _calendarDateText(DateTime? value) {
  if (value == null) return null;
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

bool _isPositiveDecimal(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) return false;
  return (num.tryParse(normalized) ?? 0) > 0;
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is Map) Map<String, dynamic>.from(entry),
  ];
}
