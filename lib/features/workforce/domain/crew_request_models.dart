/// Workforce Center — crew requests, as the server returns them
/// (docs/yorks-v1/WORKFORCE_CENTER_DESIGN.md).
library;

import 'attendance_models.dart';

String _s(Object? value) => value?.toString() ?? '';
String? _ns(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

int _i(Object? value) => value is num ? value.toInt() : 0;
DateTime? _dt(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
List<Map<String, dynamic>> _list(Object? value) => [
  for (final item in (value as List? ?? const []))
    Map<String, dynamic>.from(item as Map),
];

enum CrewRequestState {
  submitted('submitted'),
  returned('returned'),
  approved('approved'),
  partiallyFulfilled('partially_fulfilled'),
  fulfilled('fulfilled'),
  completed('completed'),
  closed('closed'),
  rejected('rejected'),
  cancelled('cancelled');

  const CrewRequestState(this.wire);
  final String wire;

  static CrewRequestState from(Object? value) => values.firstWhere(
    (state) => state.wire == value,
    orElse: () => CrewRequestState.submitted,
  );

  /// Still moving: someone has a next step. Workers on site stay open until
  /// the request is finished.
  bool get isOpen =>
      this == submitted ||
      this == returned ||
      this == approved ||
      this == partiallyFulfilled ||
      this == fulfilled;
}

/// Who holds the request now.
enum CrewRequestOwner { projectEngineer, requester, pr, none }

CrewRequestOwner _owner(Object? value) => switch (value) {
  'project_engineer' => CrewRequestOwner.projectEngineer,
  'requester' => CrewRequestOwner.requester,
  'pr' => CrewRequestOwner.pr,
  _ => CrewRequestOwner.none,
};

final class CrewRequestAccess {
  const CrewRequestAccess({
    this.view = false,
    this.decide = false,
    this.fulfil = false,
    this.cancel = false,
    this.resubmit = false,
    this.finish = false,
  });

  factory CrewRequestAccess.fromJson(Map<String, dynamic>? json) =>
      CrewRequestAccess(
        view: json?['view'] == true,
        decide: json?['decide'] == true,
        fulfil: json?['fulfil'] == true,
        cancel: json?['cancel'] == true,
        resubmit: json?['resubmit'] == true,
        finish: json?['finish'] == true,
      );

  final bool view;
  final bool decide;
  final bool fulfil;
  final bool cancel;
  final bool resubmit;

  /// Work done: finish the request and release its workers.
  final bool finish;

  /// The signed-in person has the next step. Finishing waits on the work,
  /// so it alone does not make the request theirs.
  bool get mine => decide || fulfil || resubmit;
}

final class CrewRequestPerson {
  const CrewRequestPerson({required this.name, required this.role});

  factory CrewRequestPerson.fromJson(Map<String, dynamic>? json) =>
      CrewRequestPerson(name: _s(json?['name']), role: _s(json?['role']));

  final String name;
  final String role;
}

/// A worker asked for by name, with the crew they are on now (if any).
final class CrewRequestNamedWorker {
  const CrewRequestNamedWorker({
    required this.id,
    required this.name,
    required this.number,
    required this.designation,
    this.crewId,
    this.crewName,
  });

  factory CrewRequestNamedWorker.fromJson(Map<String, dynamic> json) =>
      CrewRequestNamedWorker(
        id: _s(json['id']),
        name: _s(json['name']),
        number: _s(json['number']),
        designation: _s(json['designation']),
        crewId: _ns(json['crew_id']),
        crewName: _ns(json['crew_name']),
      );

  final String id;
  final String name;
  final String number;
  final String designation;
  final String? crewId;
  final String? crewName;
}

final class CrewRequestAssignee {
  const CrewRequestAssignee({
    required this.workerId,
    required this.number,
    required this.name,
    required this.designation,
    required this.crewName,
    this.assignedAt,
    this.releasedAt,
  });

  factory CrewRequestAssignee.fromJson(Map<String, dynamic> json) =>
      CrewRequestAssignee(
        workerId: _s(json['worker_id']),
        number: _s(json['number']),
        name: _s(json['name']),
        designation: _s(json['designation']),
        crewName: _s(json['crew_name']),
        assignedAt: _dt(json['assigned_at']),
        releasedAt: _dt(json['released_at']),
      );

  final String workerId;
  final String number;
  final String name;
  final String designation;
  final String crewName;
  final DateTime? assignedAt;

  /// When they left the crew: released, finished, or moved elsewhere.
  final DateTime? releasedAt;

  bool get onSite => releasedAt == null;
}

enum CrewRequestLineDecision { full, partial, cannotProvide }

CrewRequestLineDecision? _decision(Object? value) => switch (value) {
  'full' => CrewRequestLineDecision.full,
  'partial' => CrewRequestLineDecision.partial,
  'cannot_provide' => CrewRequestLineDecision.cannotProvide,
  _ => null,
};

extension CrewRequestLineDecisionWire on CrewRequestLineDecision {
  String get wire => switch (this) {
    CrewRequestLineDecision.full => 'full',
    CrewRequestLineDecision.partial => 'partial',
    CrewRequestLineDecision.cannotProvide => 'cannot_provide',
  };
}

final class CrewRequestLine {
  const CrewRequestLine({
    required this.id,
    required this.lineNumber,
    required this.trade,
    required this.quantity,
    this.note,
    this.decision,
    this.decisionReason,
    this.assigned = const [],
    this.worker,
  });

  factory CrewRequestLine.fromJson(Map<String, dynamic> json) =>
      CrewRequestLine(
        id: _s(json['id']),
        lineNumber: _i(json['line_number']),
        trade: _s(json['trade']),
        quantity: _i(json['quantity']),
        note: _ns(json['note']),
        decision: _decision(json['decision']),
        decisionReason: _ns(json['decision_reason']),
        assigned: [
          for (final item in _list(json['assigned']))
            CrewRequestAssignee.fromJson(item),
        ],
        worker: json['worker'] is Map
            ? CrewRequestNamedWorker.fromJson(
                Map<String, dynamic>.from(json['worker'] as Map),
              )
            : null,
      );

  final String id;
  final int lineNumber;
  final String trade;
  final int quantity;
  final String? note;
  final CrewRequestLineDecision? decision;
  final String? decisionReason;
  final List<CrewRequestAssignee> assigned;

  /// Set when the requester asked for this person by name.
  final CrewRequestNamedWorker? worker;

  /// A named worker who is on another crew and not yet assigned here: the
  /// requester and approver see a warning.
  bool get namedOnOtherCrew =>
      worker?.crewId != null && assigned.every((a) => a.workerId != worker!.id);

  int get short => (quantity - assigned.length).clamp(0, quantity);
}

final class CrewRequestEvent {
  const CrewRequestEvent({
    required this.type,
    required this.actorName,
    required this.actorRole,
    required this.toState,
    this.reason,
    this.detail = const {},
    this.at,
  });

  factory CrewRequestEvent.fromJson(Map<String, dynamic> json) =>
      CrewRequestEvent(
        type: _s(json['type']),
        actorName: _s(json['actor_name']),
        actorRole: _s(json['actor_role']),
        toState: CrewRequestState.from(json['to_state']),
        reason: _ns(json['reason']),
        detail: Map<String, dynamic>.from(json['detail'] as Map? ?? const {}),
        at: _dt(json['at']),
      );

  final String type;
  final String actorName;
  final String actorRole;
  final CrewRequestState toState;
  final String? reason;
  final Map<String, dynamic> detail;
  final DateTime? at;
}

final class CrewRequest {
  const CrewRequest({
    required this.id,
    required this.number,
    required this.state,
    required this.crewKind,
    required this.neededFrom,
    required this.requestedBy,
    required this.lastActor,
    required this.recordVersion,
    required this.owner,
    required this.access,
    this.projectId,
    this.projectName,
    this.projectRef,
    this.workLabel,
    this.targetCrewId,
    this.targetCrewName,
    this.neededUntil,
    this.notes,
    this.submittedAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionReason,
    this.updatedAt,
    this.overdue = false,
    this.requestedCount = 0,
    this.assignedCount = 0,
    this.trades = const [],
    this.lines = const [],
    this.events = const [],
  });

  factory CrewRequest.fromJson(Map<String, dynamic> json) => CrewRequest(
    id: _s(json['id']),
    number: _s(json['number']),
    state: CrewRequestState.from(json['state']),
    crewKind: _s(json['crew_kind']),
    projectId: _ns(json['project_id']),
    projectName: _ns(json['project_name']),
    projectRef: _ns(json['project_ref']),
    workLabel: _ns(json['work_label']),
    targetCrewId: _ns(json['target_crew_id']),
    targetCrewName: _ns(json['target_crew_name']),
    neededFrom: _s(json['needed_from']),
    neededUntil: _ns(json['needed_until']),
    notes: _ns(json['notes']),
    requestedBy: CrewRequestPerson.fromJson(
      json['requested_by'] as Map<String, dynamic>?,
    ),
    submittedAt: _dt(json['submitted_at']),
    decidedBy: json['decided_by'] == null
        ? null
        : CrewRequestPerson.fromJson(
            Map<String, dynamic>.from(json['decided_by'] as Map),
          ),
    decidedAt: _dt(json['decided_at']),
    decisionReason: _ns(json['decision_reason']),
    lastActor: CrewRequestPerson.fromJson(
      json['last_actor'] == null
          ? null
          : Map<String, dynamic>.from(json['last_actor'] as Map),
    ),
    updatedAt: _dt(json['updated_at']),
    recordVersion: _i(json['record_version']),
    owner: _owner(json['owner']),
    overdue: json['overdue'] == true,
    requestedCount: _i(json['requested_count']),
    assignedCount: _i(json['assigned_count']),
    trades: [
      for (final item in _list(json['trades']))
        (
          trade: _s(item['trade']),
          quantity: _i(item['quantity']),
          workerName: _ns(item['worker_name']),
        ),
    ],
    access: CrewRequestAccess.fromJson(
      json['access'] == null
          ? null
          : Map<String, dynamic>.from(json['access'] as Map),
    ),
    lines: [
      for (final item in _list(json['lines'])) CrewRequestLine.fromJson(item),
    ],
    events: [
      for (final item in _list(json['events'])) CrewRequestEvent.fromJson(item),
    ],
  );

  final String id;
  final String number;
  final CrewRequestState state;
  final String crewKind;
  final String? projectId;
  final String? projectName;
  final String? projectRef;
  final String? workLabel;
  final String? targetCrewId;
  final String? targetCrewName;
  final String neededFrom;
  final String? neededUntil;
  final String? notes;
  final CrewRequestPerson requestedBy;
  final DateTime? submittedAt;
  final CrewRequestPerson? decidedBy;
  final DateTime? decidedAt;
  final String? decisionReason;
  final CrewRequestPerson lastActor;
  final DateTime? updatedAt;
  final int recordVersion;
  final CrewRequestOwner owner;
  final bool overdue;
  final int requestedCount;
  final int assignedCount;
  final List<({String trade, int quantity, String? workerName})> trades;
  final CrewRequestAccess access;
  final List<CrewRequestLine> lines;
  final List<CrewRequestEvent> events;

  bool get isWorkshop => crewKind == 'workshop';

  /// Workers this request brought who are still on the crew.
  int get onSiteCount => [
    for (final line in lines)
      for (final person in line.assigned)
        if (person.onSite) person,
  ].length;
}

final class CrewRequestRegister {
  const CrewRequestRegister({
    required this.today,
    required this.canRequest,
    required this.requests,
  });

  factory CrewRequestRegister.fromJson(Map<String, dynamic> json) =>
      CrewRequestRegister(
        today: _s(json['today']),
        canRequest: json['can_request'] == true,
        requests: [
          for (final item in _list(json['requests']))
            CrewRequest.fromJson(item),
        ],
      );

  final String today;
  final bool canRequest;
  final List<CrewRequest> requests;

  /// Requests where the signed-in person has the next step.
  List<CrewRequest> get mine => [
    for (final request in requests)
      if (request.access.mine) request,
  ];

  int get open => requests.where((r) => r.state.isOpen).length;
}

final class CrewRequestProjectOption {
  const CrewRequestProjectOption({
    required this.id,
    required this.name,
    required this.ref,
    required this.approvedOnSubmit,
  });

  final String id;
  final String name;
  final String ref;
  final bool approvedOnSubmit;
}

final class CrewRequestCrewOption {
  const CrewRequestCrewOption({
    required this.id,
    required this.name,
    required this.kind,
    this.projectId,
    this.shiftStart,
    this.shiftFinish,
  });

  final String id;
  final String name;
  final String kind;
  final String? projectId;
  final int? shiftStart;
  final int? shiftFinish;
}

final class CrewRequestOptions {
  const CrewRequestOptions({
    required this.today,
    required this.workshop,
    required this.projects,
    required this.trades,
    required this.crews,
    required this.workers,
  });

  factory CrewRequestOptions.fromJson(Map<String, dynamic> json) =>
      CrewRequestOptions(
        today: _s(json['today']),
        workshop: json['workshop'] == true,
        projects: [
          for (final item in _list(json['projects']))
            CrewRequestProjectOption(
              id: _s(item['id']),
              name: _s(item['name']),
              ref: _s(item['ref']),
              approvedOnSubmit: item['approved_on_submit'] == true,
            ),
        ],
        trades: [
          for (final item in (json['trades'] as List? ?? const []))
            item.toString(),
        ],
        crews: [
          for (final item in _list(json['crews']))
            CrewRequestCrewOption(
              id: _s(item['id']),
              name: _s(item['name']),
              kind: _s(item['kind']),
              projectId: _ns(item['project_id']),
              shiftStart: item['shift_start_minute'] is num
                  ? (item['shift_start_minute'] as num).toInt()
                  : null,
              shiftFinish: item['shift_finish_minute'] is num
                  ? (item['shift_finish_minute'] as num).toInt()
                  : null,
            ),
        ],
        workers: [
          for (final item in _list(json['workers']))
            AttendanceWorker.fromJson(item),
        ],
      );

  final String today;
  final bool workshop;
  final List<CrewRequestProjectOption> projects;
  final List<String> trades;
  final List<CrewRequestCrewOption> crews;
  final List<AttendanceWorker> workers;

  bool get canRequest => workshop || projects.isNotEmpty;
}

/// One line as typed in the request form.
final class CrewRequestDraftLine {
  const CrewRequestDraftLine({
    required this.trade,
    required this.quantity,
    this.note,
    this.workerId,
  });

  /// A designation, or the named worker's designation.
  final String trade;
  final int quantity;
  final String? note;

  /// Set when a person is asked for by name (always one person).
  final String? workerId;

  Map<String, Object?> toJson() => {
    if (workerId != null) 'worker_id': workerId,
    if (workerId == null || trade.trim().isNotEmpty) 'trade': trade.trim(),
    'quantity': workerId == null ? quantity : 1,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };
}

/// One line of PR's assignment.
final class CrewRequestFulfilLine {
  const CrewRequestFulfilLine({
    required this.lineId,
    required this.workerIds,
    this.decision,
    this.reason,
  });

  final String lineId;
  final List<String> workerIds;
  final CrewRequestLineDecision? decision;
  final String? reason;

  Map<String, Object?> toJson() => {
    'line_id': lineId,
    'worker_ids': workerIds,
    if (decision != null && decision != CrewRequestLineDecision.full)
      'decision': decision!.wire,
    if (reason != null && reason!.trim().isNotEmpty) 'reason': reason!.trim(),
  };
}
