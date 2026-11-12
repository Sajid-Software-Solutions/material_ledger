/// Crew requests — Request crew, and Fix and resubmit a returned request,
/// in the Material Request style: three steps on a phone (Details, People,
/// Review) and numbered sections with a summary on desktop.
///
/// Each line asks for a person by name or for a number of a trade: one
/// field suggests people and trades as the requester types. A person on
/// another crew is shown with a warning; the approver sees it too.
///
/// Nothing reaches the approver until Send succeeds on the server; a refusal
/// is shown with everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_mobile_ui.dart';
import '../../../../shared/models/app_language.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart'
    show
        AS,
        AttendanceAvatar,
        attendanceLanguage,
        attendanceLongDate,
        attendanceToast;
import 'crew_request_common.dart';
import 'crew_request_kit.dart';

enum _Step { details, people, review }

class CrewRequestFormScreen extends ConsumerWidget {
  const CrewRequestFormScreen({super.key, this.requestId});

  /// A returned request to fix and send again.
  final String? requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
    final options = ref.watch(yorksCrewRequestOptionsProvider);
    final existing = requestId == null
        ? null
        : ref.watch(yorksCrewRequestProvider(requestId!));
    final error = options.error ?? existing?.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: CrMessage(
          icon: Icons.cloud_off_outlined,
          message: crewRequestErrorText(error, language),
          action: AS.t(AS.retry, language),
          onPressed: () {
            ref.invalidate(yorksCrewRequestOptionsProvider);
            if (requestId != null) {
              ref.invalidate(yorksCrewRequestProvider(requestId!));
            }
          },
        ),
      );
    }
    final loadedOptions = options.valueOrNull;
    final loadedRequest = existing?.valueOrNull;
    if (loadedOptions == null || (requestId != null && loadedRequest == null)) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!loadedOptions.canRequest) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: CrMessage(
          icon: Icons.groups_outlined,
          message: CRS.t(CRS.noProjects, language),
          action: CRS.t(CRS.back, language),
          onPressed: () => context.go(RoutePaths.yorksV1Workforce),
        ),
      );
    }
    return _CrewRequestForm(
      key: ValueKey('crew-request-form-${requestId ?? 'new'}'),
      options: loadedOptions,
      request: loadedRequest,
      language: language,
    );
  }
}

class _LineDraft {
  _LineDraft({
    String trade = '',
    String quantity = '',
    String note = '',
    this.worker,
  }) : trade = TextEditingController(text: trade),
       quantity = TextEditingController(text: quantity),
       note = TextEditingController(text: note);

  /// What is typed: a name being looked up, or a trade.
  final TextEditingController trade;
  final TextEditingController quantity;
  final TextEditingController note;

  /// The person asked for by name; the line is then for one person.
  AttendanceWorker? worker;

  int? get count => worker != null ? 1 : int.tryParse(quantity.text.trim());
  bool get isBlank =>
      worker == null &&
      trade.text.trim().isEmpty &&
      quantity.text.trim().isEmpty &&
      note.text.trim().isEmpty;
  bool get isValid =>
      worker != null ||
      (trade.text.trim().isNotEmpty &&
          count != null &&
          count! >= 1 &&
          count! <= 200);

  /// How the line reads in the summary.
  String get label => worker != null
      ? (worker!.designation.isEmpty
            ? worker!.name
            : '${worker!.name} (${worker!.designation})')
      : '${count ?? 0} × ${trade.text.trim()}';

  void dispose() {
    trade.dispose();
    quantity.dispose();
    note.dispose();
  }
}

class _CrewRequestForm extends ConsumerStatefulWidget {
  const _CrewRequestForm({
    super.key,
    required this.options,
    required this.language,
    this.request,
  });

  final CrewRequestOptions options;
  final CrewRequest? request;
  final AppLanguage language;

  @override
  ConsumerState<_CrewRequestForm> createState() => _CrewRequestFormState();
}

class _CrewRequestFormState extends ConsumerState<_CrewRequestForm> {
  _Step _step = _Step.details;
  late String _kind;
  String? _projectId;
  String? _targetCrewId;
  late String _neededFrom;
  String? _neededUntil;
  late final TextEditingController _work;
  late final TextEditingController _notes;
  final List<_LineDraft> _lines = [];
  bool _busy = false;
  String? _error;
  String? _idempotencyKey;

  CrewRequestOptions get _options => widget.options;
  AppLanguage get _language => widget.language;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    final projects = _options.projects;
    _kind =
        request?.crewKind ??
        (projects.isEmpty && _options.workshop ? 'workshop' : 'project');
    _projectId =
        request?.projectId ?? (projects.length == 1 ? projects.first.id : null);
    _targetCrewId = request?.targetCrewId;
    _neededFrom =
        request == null || request.neededFrom.compareTo(_options.today) < 0
        ? _options.today
        : request.neededFrom;
    _neededUntil = request?.neededUntil;
    _work = TextEditingController(text: request?.workLabel ?? '');
    _notes = TextEditingController(text: request?.notes ?? '');
    if (request != null && request.lines.isNotEmpty) {
      for (final line in request.lines) {
        final named = line.worker;
        _lines.add(
          _LineDraft(
            trade: named == null ? line.trade : '',
            quantity: named == null ? '${line.quantity}' : '',
            note: line.note ?? '',
            worker: named == null
                ? null
                : _optionWorker(named.id) ??
                      AttendanceWorker(
                        id: named.id,
                        number: named.number,
                        name: named.name,
                        designation: named.designation,
                        crewId: named.crewId,
                        crewName: named.crewName,
                      ),
          ),
        );
      }
    } else {
      _lines.add(_LineDraft());
    }
  }

  @override
  void dispose() {
    _work.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _idempotencyKey = null;
    _error = null;
  });

  AttendanceWorker? _optionWorker(String id) {
    for (final worker in _options.workers) {
      if (worker.id == id) return worker;
    }
    return null;
  }

  /// People already named on another line of this request.
  Set<String> _namedElsewhere(_LineDraft line) => {
    for (final other in _lines)
      if (!identical(other, line) && other.worker != null) other.worker!.id,
  };

  CrewRequestProjectOption? get _project {
    for (final project in _options.projects) {
      if (project.id == _projectId) return project;
    }
    return null;
  }

  bool get _approvedOnSubmit => _kind == 'workshop'
      ? _options.projects.isNotEmpty &&
            _options.projects.every((p) => p.approvedOnSubmit)
      : _project?.approvedOnSubmit ?? false;

  List<CrewRequestCrewOption> get _crews => [
    for (final crew in _options.crews)
      if (crew.kind == _kind &&
          (_kind == 'workshop' || crew.projectId == _projectId))
        crew,
  ];

  bool get _detailsReady => _kind == 'workshop' || _projectId != null;
  List<_LineDraft> get _filled => [
    for (final line in _lines)
      if (!line.isBlank) line,
  ];
  bool get _peopleReady =>
      _filled.isNotEmpty && _filled.every((line) => line.isValid);
  int get _peopleCount =>
      _filled.fold(0, (sum, line) => sum + (line.count ?? 0));

  String get _whereText {
    if (_kind == 'workshop') return CRS.t(CRS.workshop, _language);
    final project = _project;
    return project == null ? '—' : '${project.ref} · ${project.name}';
  }

  String get _datesText => _neededUntil == null
      ? CRS.t(CRS.fromOnwards, _language, {
          'from': attendanceLongDate(_neededFrom),
        })
      : CRS.t(CRS.fromUntil, _language, {
          'from': attendanceLongDate(_neededFrom),
          'until': attendanceLongDate(_neededUntil!),
        });

  Future<void> _pickDate({required bool until}) async {
    final today = DateTime.parse(_options.today);
    final current = DateTime.tryParse(
      until ? (_neededUntil ?? _neededFrom) : _neededFrom,
    );
    final first = until ? DateTime.parse(_neededFrom) : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked == null || !mounted) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (until) {
        _neededUntil = iso;
      } else {
        _neededFrom = iso;
        if (_neededUntil != null && _neededUntil!.compareTo(iso) < 0) {
          _neededUntil = null;
        }
      }
      _idempotencyKey = null;
      _error = null;
    });
  }

  void _close() => context.go(
    widget.request == null
        ? RoutePaths.yorksV1WorkforceRequests
        : crewRequestPath(widget.request!.id),
  );

  Future<void> _submit() async {
    if (!_detailsReady) {
      setState(() => _error = CRS.t(CRS.errProject, _language));
      return;
    }
    if (!_peopleReady) {
      setState(() => _error = CRS.t(CRS.errNoLines, _language));
      return;
    }
    final request = widget.request;
    setState(() {
      _busy = true;
      _error = null;
    });
    _idempotencyKey ??= YorksAttendanceRepository.newKey();
    try {
      final saved = await ref
          .read(yorksAttendanceRepositoryProvider)
          .submitRequest(
            requestId: request?.id,
            crewKind: _kind,
            projectId: _kind == 'project' ? _projectId : null,
            workLabel: _work.text,
            targetCrewId: _targetCrewId,
            neededFrom: _neededFrom,
            neededUntil: _neededUntil,
            notes: _notes.text,
            lines: [
              for (final line in _filled)
                CrewRequestDraftLine(
                  trade: line.worker?.designation ?? line.trade.text,
                  quantity: line.count!,
                  note: line.note.text,
                  workerId: line.worker?.id,
                ),
            ],
            expectedVersion: request?.recordVersion,
            idempotencyKey: _idempotencyKey!,
          );
      if (!mounted) return;
      ref.invalidate(yorksCrewRequestsProvider);
      if (request != null) ref.invalidate(yorksCrewRequestProvider(request.id));
      attendanceToast(
        context,
        CRS.t(CRS.sentToast, _language, {'number': saved.number}),
      );
      context.go(crewRequestPath(saved.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = crewRequestErrorText(error, _language);
      });
    }
  }

  // ─── Fields ────────────────────────────────────────────────────────────────

  Widget _kindField() => YorksMobileSegmentedControl<String>(
    key: const ValueKey('crew-request-kind'),
    selected: _kind,
    enabled: !_busy,
    options: [
      YorksMobileSegmentOption(
        value: 'project',
        label: CRS.t(CRS.kindProject, _language),
      ),
      YorksMobileSegmentOption(
        value: 'workshop',
        label: CRS.t(CRS.kindWorkshop, _language),
      ),
    ],
    onSelected: (value) {
      _kind = value;
      _targetCrewId = null;
      _changed();
    },
  );

  Widget _projectField() => DropdownButtonFormField<String>(
    key: const ValueKey('crew-request-project'),
    initialValue: _projectId,
    isExpanded: true,
    decoration: InputDecoration(labelText: CRS.t(CRS.projectLabel, _language)),
    items: [
      for (final project in _options.projects)
        DropdownMenuItem(
          value: project.id,
          child: Text(
            '${project.ref} · ${project.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: _busy
        ? null
        : (value) {
            _projectId = value;
            _targetCrewId = null;
            _changed();
          },
  );

  Widget _workField() => TextField(
    key: const ValueKey('crew-request-work'),
    controller: _work,
    enabled: !_busy,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(
      labelText: CRS.t(CRS.workLabel, _language),
      hintText: CRS.t(CRS.workHint, _language),
    ),
  );

  Widget _dateField({required bool until}) {
    final value = until ? _neededUntil : _neededFrom;
    return InkWell(
      key: ValueKey(until ? 'crew-request-until' : 'crew-request-from'),
      onTap: _busy ? null : () => _pickDate(until: until),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: CRS.t(until ? CRS.neededUntil : CRS.neededFrom, _language),
          suffixIcon: until && _neededUntil != null && !_busy
              ? IconButton(
                  tooltip: CRS.t(CRS.clearDate, _language),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _neededUntil = null;
                    _idempotencyKey = null;
                  }),
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          value == null ? '' : attendanceLongDate(value),
          style: AppTypography.bodyLarge,
        ),
      ),
    );
  }

  Widget? _crewField() {
    final crews = _crews;
    if (crews.isEmpty) return null;
    if (_targetCrewId != null && crews.every((c) => c.id != _targetCrewId)) {
      _targetCrewId = null;
    }
    return DropdownButtonFormField<String?>(
      key: const ValueKey('crew-request-target'),
      initialValue: _targetCrewId,
      isExpanded: true,
      decoration: InputDecoration(labelText: CRS.t(CRS.targetCrew, _language)),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(CRS.t(CRS.targetCrewAny, _language)),
        ),
        for (final crew in crews)
          DropdownMenuItem<String?>(value: crew.id, child: Text(crew.name)),
      ],
      onChanged: _busy
          ? null
          : (value) {
              _targetCrewId = value;
              _changed();
            },
    );
  }

  List<Widget> _detailFields({required bool twoColumns}) {
    final canProject = _options.projects.isNotEmpty;
    final canWorkshop = _options.workshop;
    final crew = _crewField();
    final left = <Widget>[
      if (canProject && canWorkshop) ...[
        _kindField(),
        const SizedBox(height: AppSpacing.md),
      ],
      if (_kind == 'project') ...[
        _projectField(),
        const SizedBox(height: AppSpacing.md),
      ],
      _workField(),
    ];
    final right = <Widget>[
      _dateField(until: false),
      const SizedBox(height: AppSpacing.md),
      _dateField(until: true),
      if (crew != null) ...[const SizedBox(height: AppSpacing.md), crew],
    ];
    if (!twoColumns) {
      return [...left, const SizedBox(height: AppSpacing.md), ...right];
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Column(children: right)),
        ],
      ),
    ];
  }

  Widget _lineCard(int index, _LineDraft line) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: CrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  CRS.t(CRS.lineNumber, _language, {'n': index + 1}),
                  style: AppTypography.titleSmall,
                ),
              ),
              if (_lines.length > 1)
                IconButton.outlined(
                  key: ValueKey('crew-request-remove-$index'),
                  tooltip: CRS.t(CRS.remove, _language),
                  color: AppColors.error,
                  onPressed: _busy
                      ? null
                      : () {
                          final removed = _lines.removeAt(index);
                          _changed();
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => removed.dispose(),
                          );
                        },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (line.worker != null)
            _namedPerson(index, line)
          else
            ..._nameOrTrade(index, line),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: ValueKey('crew-request-note-$index'),
            controller: line.note,
            enabled: !_busy,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: CRS.t(CRS.lineNote, _language),
            ),
          ),
        ],
      ),
    ),
  );

  /// A person asked for by name: who they are, and a warning when they are
  /// on another crew.
  Widget _namedPerson(int index, _LineDraft line) {
    final worker = line.worker!;
    final onCrew = worker.crewId != null;
    return Column(
      key: ValueKey('crew-request-named-$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Row(
            children: [
              AttendanceAvatar(initials: worker.initials),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.name, style: AppTypography.titleSmall),
                    Text(
                      [
                        worker.number,
                        worker.designation,
                      ].where((part) => part.isNotEmpty).join(' · '),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    CrPill(
                      icon: Icons.badge_outlined,
                      label: CRS.t(CRS.namedPerson, _language),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: ValueKey('crew-request-change-$index'),
                onPressed: _busy
                    ? null
                    : () {
                        line.worker = null;
                        line.trade.clear();
                        _changed();
                      },
                child: Text(CRS.t(CRS.changePerson, _language)),
              ),
            ],
          ),
        ),
        if (onCrew) ...[
          const SizedBox(height: AppSpacing.sm),
          YorksMobileCallout(
            key: ValueKey('crew-request-on-crew-$index'),
            icon: Icons.warning_amber_rounded,
            title: CRS.t(CRS.onCrewWarningTitle, _language, {
              'name': worker.name,
              'crew': worker.crewName ?? '',
            }),
            message: CRS.t(CRS.onCrewWarningBody, _language, {
              'name': worker.name,
            }),
            warning: true,
          ),
        ],
      ],
    );
  }

  /// One field for a name or a trade, with suggestions as it is typed.
  List<Widget> _nameOrTrade(int index, _LineDraft line) {
    final typed = line.trade.text.trim();
    final canon = attendanceCanon(typed);
    final taken = _namedElsewhere(line);
    final people = typed.isEmpty
        ? const <AttendanceWorker>[]
        : [
            for (final hit in attendanceFuzzySearch(
              typed,
              [
                for (final worker in _options.workers)
                  if (!taken.contains(worker.id)) worker,
              ],
              (worker) => '${worker.name} ${worker.number}',
              limit: 5,
            ))
              hit.item,
          ];
    final trades = typed.isEmpty
        ? _options.trades.take(6).toList()
        : [
            for (final hit in attendanceFuzzySearch(
              typed,
              _options.trades,
              (trade) => trade,
              limit: 4,
            ))
              if (attendanceCanon(hit.item) != canon) hit.item,
          ];
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('crew-request-trade-$index'),
              controller: line.trade,
              enabled: !_busy,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: CRS.t(CRS.trade, _language),
                hintText: CRS.t(CRS.tradeHint, _language),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 96,
            child: TextField(
              key: ValueKey('crew-request-quantity-$index'),
              controller: line.quantity,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: CRS.t(CRS.howMany, _language),
              ),
            ),
          ),
        ],
      ),
      if (!_busy && people.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Container(
          key: ValueKey('crew-request-suggest-people-$index'),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  4,
                ),
                child: Text(
                  CRS.t(CRS.suggestPeople, _language),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ),
              for (final worker in people)
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    key: ValueKey(
                      'crew-request-suggest-worker-$index-${worker.id}',
                    ),
                    minTileHeight: 52,
                    leading: AttendanceAvatar(initials: worker.initials),
                    title: Text(worker.name, style: AppTypography.bodyLarge),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            worker.number,
                            worker.designation,
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        if (worker.crewId != null) ...[
                          const SizedBox(height: 4),
                          CrPill(
                            icon: Icons.warning_amber_rounded,
                            label: CRS.t(CRS.workerOnCrew, _language, {
                              'crew': worker.crewName ?? '',
                            }),
                            color: AppColors.warning,
                            background: AppColors.warningContainer,
                          ),
                        ],
                      ],
                    ),
                    trailing: worker.crewId == null
                        ? CrPill(
                            label: CRS.t(CRS.workerFree, _language),
                            color: AppColors.success,
                            background: AppColors.successContainer,
                          )
                        : null,
                    onTap: () {
                      line.worker = worker;
                      line.trade.clear();
                      line.quantity.clear();
                      FocusScope.of(context).unfocus();
                      _changed();
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
      if (!_busy && trades.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        if (typed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              CRS.t(CRS.suggestTrades, _language),
              style: AppTypography.labelMedium.copyWith(color: AppColors.muted),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final trade in trades)
              ActionChip(
                key: ValueKey('crew-request-suggest-trade-$index-$trade'),
                avatar: const Icon(Icons.engineering_outlined, size: 16),
                label: Text(trade),
                onPressed: () {
                  line.trade.text = trade;
                  if (line.quantity.text.trim().isEmpty) {
                    line.quantity.text = '1';
                  }
                  _changed();
                },
              ),
          ],
        ),
      ],
    ];
  }

  Widget _addLine() => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        key: const ValueKey('crew-request-add-line'),
        onPressed: _busy || _lines.length >= 50
            ? null
            : () {
                _lines.add(_LineDraft());
                _changed();
              },
        icon: const Icon(Icons.add_rounded),
        label: Text(CRS.t(CRS.addTrade, _language)),
      ),
      Text(
        CRS.t(CRS.peopleCount, _language, {'n': _peopleCount}),
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ],
  );

  Widget _notesField() => TextField(
    key: const ValueKey('crew-request-notes'),
    controller: _notes,
    enabled: !_busy,
    minLines: 2,
    maxLines: 4,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(labelText: CRS.t(CRS.notesLabel, _language)),
  );

  Widget _summary() {
    final request = widget.request;
    return CrCard(
      key: const ValueKey('crew-request-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  CRS.t(CRS.requestSummary, _language),
                  style: AppTypography.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: CrPill(
              icon: Icons.groups_outlined,
              label: request?.number ?? CRS.t(CRS.eyebrow, _language),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            CRS.t(CRS.completeRequest, _language),
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CRS.t(CRS.completeRequestMessage, _language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          CrReadiness(
            label: CRS.t(CRS.rowWhere, _language),
            ready: _detailsReady,
            language: _language,
          ),
          CrReadiness(
            label: CRS.t(CRS.rowPeople, _language),
            ready: _peopleReady,
            language: _language,
          ),
          CrReadiness(
            label: CRS.t(CRS.rowRoute, _language),
            ready: _detailsReady,
            language: _language,
          ),
          const Divider(height: AppSpacing.xl),
          CrFact(label: CRS.t(CRS.projectLabel, _language), value: _whereText),
          if (_work.text.trim().isNotEmpty)
            CrFact(
              label: CRS.t(CRS.factWork, _language),
              value: _work.text.trim(),
            ),
          CrFact(label: CRS.t(CRS.factNeeded, _language), value: _datesText),
          if (_peopleCount > 0)
            CrFact(
              label: CRS.t(CRS.rowPeople, _language),
              value: [
                for (final line in _filled)
                  if (line.isValid) line.label,
              ].join(', '),
            ),
          CrFact(
            label: CRS.t(CRS.rowRoute, _language),
            value: CRS.t(
              _approvedOnSubmit ? CRS.routeAuto : CRS.routeToPe,
              _language,
            ),
            last: true,
          ),
        ],
      ),
    );
  }

  Widget? _errorBanner() => _error == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: YorksMobileCallout(
              key: const ValueKey('crew-request-error'),
              icon: Icons.error_outline_rounded,
              title: _error!,
              message: '',
              warning: true,
            ),
          ),
        );

  Widget _sendButton() => FilledButton.icon(
    key: const ValueKey('crew-request-send'),
    onPressed: _busy ? null : _submit,
    icon: _busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.send_rounded),
    label: Text(
      _busy
          ? AS.t(AS.saving, _language)
          : CRS.t(widget.request == null ? CRS.send : CRS.sendAgain, _language),
    ),
  );

  // ─── Layouts ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppSpacing.stackedBreakpoint
      ? _mobile()
      : _desktop();

  Widget _mobile() {
    final title = switch (_step) {
      _Step.details => CRS.t(CRS.stepDetails, _language),
      _Step.people => CRS.t(CRS.stepPeople, _language),
      _Step.review => CRS.t(CRS.stepReview, _language),
    };
    final labels = [
      CRS.t(CRS.stepDetails, _language),
      CRS.t(CRS.stepPeople, _language),
      CRS.t(CRS.stepReview, _language),
    ];
    final (prompt, description) = switch (_step) {
      _Step.details => (CRS.detailsPrompt, CRS.detailsDescription),
      _Step.people => (CRS.peoplePrompt, CRS.peopleDescription),
      _Step.review => (CRS.reviewPrompt, CRS.reviewDescription),
    };
    final request = widget.request;
    final route = CRS.t(
      _approvedOnSubmit ? CRS.routeAuto : CRS.routeToPe,
      _language,
    );
    return Scaffold(
      backgroundColor: AppColors.mobileSurface,
      body: Column(
        children: [
          YorksMobileAppBar(
            title: title,
            leading: YorksMobileIconButton(
              key: const ValueKey('crew-request-back'),
              icon: Icons.arrow_back_rounded,
              tooltip: CRS.t(CRS.backAction, _language),
              onPressed: () {
                if (_busy) return;
                switch (_step) {
                  case _Step.details:
                    _close();
                  case _Step.people:
                    setState(() => _step = _Step.details);
                  case _Step.review:
                    setState(() => _step = _Step.people);
                }
              },
            ),
          ),
          Expanded(
            child: ListView(
              key: ValueKey('crew-request-mobile-${_step.name}'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                CrStepIndicator(labels: labels, active: _step.index),
                const SizedBox(height: AppSpacing.xl),
                YorksMobilePageTitle(
                  eyebrow: request == null
                      ? CRS.t(CRS.eyebrow, _language)
                      : request.number,
                  title: CRS.t(prompt, _language),
                  description: CRS.t(description, _language),
                ),
                if (request?.decisionReason != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  YorksMobileCallout(
                    icon: Icons.undo_rounded,
                    title: CRS.t(CRS.stateReturned, _language),
                    message: '“${request!.decisionReason}”',
                    warning: true,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                ...switch (_step) {
                  _Step.details => [
                    YorksMobileCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _detailFields(twoColumns: false),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    YorksMobileCallout(
                      icon: Icons.shield_outlined,
                      title: CRS.t(CRS.rowRoute, _language),
                      message: route,
                    ),
                  ],
                  _Step.people => [
                    _addLine(),
                    const SizedBox(height: AppSpacing.md),
                    for (final (index, line) in _lines.indexed)
                      KeyedSubtree(
                        key: ObjectKey(line),
                        child: _lineCard(index, line),
                      ),
                  ],
                  _Step.review => [
                    _summary(),
                    const SizedBox(height: AppSpacing.md),
                    YorksMobileCard(child: _notesField()),
                  ],
                },
                ?_errorBanner(),
              ],
            ),
          ),
          switch (_step) {
            _Step.details => YorksMobileStickyActions(
              children: [
                FilledButton(
                  key: const ValueKey('crew-request-continue'),
                  onPressed: _detailsReady
                      ? () => setState(() {
                          _step = _Step.people;
                          _error = null;
                        })
                      : null,
                  child: Text(CRS.t(CRS.continueAction, _language)),
                ),
              ],
            ),
            _Step.people => YorksMobileStickyActions(
              summary: CRS.t(CRS.peopleCount, _language, {'n': _peopleCount}),
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _step = _Step.details),
                  child: Text(CRS.t(CRS.backAction, _language)),
                ),
                FilledButton(
                  key: const ValueKey('crew-request-review'),
                  onPressed: _peopleReady
                      ? () => setState(() {
                          _step = _Step.review;
                          _error = null;
                        })
                      : null,
                  child: Text(CRS.t(CRS.reviewAction, _language)),
                ),
              ],
            ),
            _Step.review => YorksMobileStickyActions(
              summary: route,
              children: [_sendButton()],
            ),
          },
        ],
      ),
    );
  }

  Widget _desktop() {
    final request = widget.request;
    final ready = _detailsReady && _peopleReady;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.pageMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.groups_outlined,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request == null
                                        ? CRS.t(CRS.formTitleNew, _language)
                                        : CRS.t(CRS.formTitleFix, _language, {
                                            'number': request.number,
                                          }),
                                    style: AppTypography.headlineSmall.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    CRS.t(CRS.formIntro, _language),
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (request?.decisionReason != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          YorksMobileCallout(
                            icon: Icons.undo_rounded,
                            title: CRS.t(CRS.stateReturned, _language),
                            message: '“${request!.decisionReason}”',
                            warning: true,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CrSection(
                                    number: '1',
                                    title: CRS.t(
                                      CRS.requestInformation,
                                      _language,
                                    ),
                                    description: CRS.t(
                                      CRS.detailsDescription,
                                      _language,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _detailFields(twoColumns: true),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  CrSection(
                                    number: '2',
                                    title: CRS.t(CRS.peopleSection, _language),
                                    description: CRS.t(
                                      CRS.peopleDescription,
                                      _language,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _addLine(),
                                        const SizedBox(height: AppSpacing.md),
                                        for (final (index, line)
                                            in _lines.indexed)
                                          KeyedSubtree(
                                            key: ObjectKey(line),
                                            child: _lineCard(index, line),
                                          ),
                                        _notesField(),
                                      ],
                                    ),
                                  ),
                                  ?_errorBanner(),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            SizedBox(width: 340, child: _summary()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Icon(
                    ready ? Icons.check_circle_outline : Icons.info_outline,
                    color: ready ? AppColors.success : AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      CRS.t(
                        ready ? CRS.readyToSend : CRS.completeBeforeSending,
                        _language,
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: ready ? AppColors.success : AppColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('crew-request-cancel'),
                    onPressed: _busy ? null : _close,
                    child: Text(AS.t(AS.cancel, _language)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _sendButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
