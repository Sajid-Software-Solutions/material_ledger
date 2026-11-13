/// Crew requests — New Crew Request, and Fix and resubmit a returned request,
/// laid out exactly like a Material Request.
///
/// Desktop: the request header with its commands, a Request Information
/// card, and a numbered Workers card holding a spreadsheet table (S.No,
/// Worker, Qty, Note, Action) with Similar, row-below and delete per row,
/// beside a Request Status panel. Phone: Details, Workers and Review steps,
/// a worker basket, and a focused one-worker editor.
///
/// Each row asks for a person by name or for any worker with a designation:
/// the Worker field suggests both as the requester types. A person on
/// another crew carries a warning the approver also sees. Nothing reaches
/// the approver until Send succeeds on the server; a refusal is shown with
/// everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/yorks_mobile_ui.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../materials/presentation/screens/yorks_v1_material_request_screens.dart'
    show
        YorksV1MaterialFormAction,
        YorksV1MaterialFormCard,
        YorksV1MaterialFormField,
        YorksV1MaterialFormMeta;
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_models.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart'
    show
        AS,
        AttendanceAvatar,
        attendanceLanguage,
        attendanceLongDate,
        attendanceShortDate,
        attendanceToast;
import 'crew_request_common.dart';
import 'crew_request_kit.dart';
import 'crew_request_worker_field.dart';

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

/// One row: a person by name, or a designation and how many.
class _LineDraft {
  _LineDraft({
    String designation = '',
    String quantity = '',
    String note = '',
    this.worker,
  }) : text = TextEditingController(text: designation),
       quantity = TextEditingController(text: quantity),
       note = TextEditingController(text: note);

  /// The designation typed, or the name being looked up.
  final TextEditingController text;
  final TextEditingController quantity;
  final TextEditingController note;
  final GlobalKey rowKey = GlobalKey();

  /// The person asked for by name; the row is then for one person.
  AttendanceWorker? worker;

  int? get count => worker != null ? 1 : int.tryParse(quantity.text.trim());
  bool get hasWorker => worker != null || text.text.trim().isNotEmpty;
  bool get hasCount => count != null && count! >= 1 && count! <= 200;
  bool get isBlank =>
      worker == null &&
      text.text.trim().isEmpty &&
      quantity.text.trim().isEmpty &&
      note.text.trim().isEmpty;
  bool get isValid => hasWorker && hasCount;

  /// The person's name, or the designation.
  String get title => worker?.name ?? text.text.trim();

  /// How the row reads in summaries.
  String get label => worker != null
      ? (worker!.designation.isEmpty
            ? worker!.name
            : '${worker!.name} (${worker!.designation})')
      : '${count ?? 0} × ${text.text.trim()}';

  _LineDraft copy() => _LineDraft(
    designation: text.text,
    quantity: quantity.text,
    note: note.text,
    worker: worker,
  );

  /// Another worker like this one: the same designation, never the same
  /// named person.
  _LineDraft similar() => _LineDraft(
    designation: worker?.designation ?? text.text.trim(),
    quantity: worker != null ? '1' : quantity.text.trim(),
  );

  void dispose() {
    text.dispose();
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
  bool _attempted = false;
  String? _error;
  String? _idempotencyKey;

  /// The phone's one-worker editor: a copy being edited, and which row it
  /// replaces (null when adding).
  _LineDraft? _editor;
  int? _editorIndex;
  bool _editorAttempted = false;
  final _namedQuantity = TextEditingController(text: '1');

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
            designation: named == null ? line.trade : '',
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
    _namedQuantity.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    _editor?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _idempotencyKey = null;
    _error = null;
  });

  void _disposeLater(_LineDraft line) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());

  AttendanceWorker? _optionWorker(String id) {
    for (final worker in _options.workers) {
      if (worker.id == id) return worker;
    }
    return null;
  }

  /// People already named on another row of this request.
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

  /// A row to point out after Send was tried: incomplete, or the only row
  /// when nothing was entered at all.
  bool _flagged(_LineDraft line) =>
      _attempted &&
      ((!line.isBlank && !line.isValid) ||
          (_filled.isEmpty && identical(line, _lines.first)));

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

  String get _crewText {
    for (final crew in _crews) {
      if (crew.id == _targetCrewId) return crew.name;
    }
    return CRS.t(CRS.targetCrewAny, _language);
  }

  String get _routeText =>
      CRS.t(_approvedOnSubmit ? CRS.routeAuto : CRS.routeToPe, _language);

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

  Future<void> _scrollToFirstFlagged() async {
    for (final line in _lines) {
      if (!_flagged(line)) continue;
      final target = line.rowKey.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          alignment: 0.2,
        );
      }
      return;
    }
  }

  Future<void> _submit() async {
    setState(() => _attempted = true);
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
                  trade: line.worker?.designation ?? line.text.text,
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

  // ─── Rows ──────────────────────────────────────────────────────────────────

  void _addRow({int? after}) {
    _lines.insert(after == null ? _lines.length : after + 1, _LineDraft());
    _changed();
  }

  void _addSimilar(int index) {
    _lines.insert(index + 1, _lines[index].similar());
    _changed();
  }

  void _removeRow(int index) {
    if (_lines.length == 1) {
      final line = _lines.single;
      line.worker = null;
      line.text.clear();
      line.quantity.clear();
      line.note.clear();
    } else {
      _disposeLater(_lines.removeAt(index));
    }
    _changed();
  }

  void _pickWorker(_LineDraft line, AttendanceWorker worker) {
    line.worker = worker;
    line.text.clear();
    line.quantity.clear();
    _changed();
  }

  void _clearWorker(_LineDraft line) {
    line.worker = null;
    line.text.clear();
    _changed();
  }

  // ─── Phone editor ──────────────────────────────────────────────────────────

  void _openEditor([int? index]) => setState(() {
    _editor = index == null ? _LineDraft() : _lines[index].copy();
    _editorIndex = index;
    _editorAttempted = false;
  });

  void _closeEditor() {
    final editor = _editor;
    setState(() {
      _editor = null;
      _editorIndex = null;
    });
    if (editor != null) _disposeLater(editor);
  }

  void _saveEditor() {
    final editor = _editor!;
    if (!editor.isValid) {
      setState(() => _editorAttempted = true);
      return;
    }
    final index = _editorIndex;
    if (index != null && index < _lines.length) {
      _disposeLater(_lines[index]);
      _lines[index] = editor;
    } else {
      for (final blank in _lines.where((line) => line.isBlank).toList()) {
        _lines.remove(blank);
        _disposeLater(blank);
      }
      _lines.add(editor);
    }
    _editor = null;
    _editorIndex = null;
    _changed();
  }

  // ─── Shared pieces ─────────────────────────────────────────────────────────

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

  Widget _projectField({bool labelled = true}) =>
      DropdownButtonFormField<String>(
        key: const ValueKey('crew-request-project'),
        initialValue: _projectId,
        isExpanded: true,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
        decoration: InputDecoration(
          labelText: labelled ? CRS.t(CRS.projectLabel, _language) : null,
          prefixIcon: labelled
              ? null
              : const Icon(Icons.apartment_outlined, size: 20),
        ),
        hint: Text(
          CRS.t(CRS.projectLabel, _language),
          overflow: TextOverflow.ellipsis,
        ),
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

  Widget _workField({bool labelled = true}) => TextField(
    key: const ValueKey('crew-request-work'),
    controller: _work,
    enabled: !_busy,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(
      labelText: labelled ? CRS.t(CRS.workLabel, _language) : null,
      hintText: CRS.t(CRS.workHint, _language),
    ),
  );

  Widget _dateField({required bool until, bool labelled = true}) {
    final value = until ? _neededUntil : _neededFrom;
    return InkWell(
      key: ValueKey(until ? 'crew-request-until' : 'crew-request-from'),
      onTap: _busy ? null : () => _pickDate(until: until),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelled
              ? CRS.t(until ? CRS.neededUntil : CRS.neededFrom, _language)
              : null,
          suffixIcon: until && _neededUntil != null && !_busy
              ? IconButton(
                  tooltip: CRS.t(CRS.clearDate, _language),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _neededUntil = null;
                    _idempotencyKey = null;
                  }),
                )
              : const Icon(Icons.event_outlined),
        ),
        child: Text(
          value == null
              ? ''
              // A desktop cell keeps the short date on one line.
              : labelled
              ? attendanceLongDate(value)
              : attendanceShortDate(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
        ),
      ),
    );
  }

  Widget? _crewField({bool labelled = true}) {
    final crews = _crews;
    if (crews.isEmpty) return null;
    if (_targetCrewId != null && crews.every((c) => c.id != _targetCrewId)) {
      _targetCrewId = null;
    }
    return DropdownButtonFormField<String?>(
      key: const ValueKey('crew-request-target'),
      initialValue: _targetCrewId,
      isExpanded: true,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
      decoration: InputDecoration(
        labelText: labelled ? CRS.t(CRS.targetCrew, _language) : null,
      ),
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

  Widget _notesField({bool labelled = true}) => TextField(
    key: const ValueKey('crew-request-notes'),
    controller: _notes,
    enabled: !_busy,
    minLines: 2,
    maxLines: 4,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(
      labelText: labelled ? CRS.t(CRS.notesLabel, _language) : null,
      hintText: labelled ? null : CRS.t(CRS.notesLabel, _language),
    ),
  );

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

  Widget? _returnedCallout() {
    final reason = widget.request?.decisionReason;
    if (reason == null) return null;
    return YorksMobileCallout(
      icon: Icons.undo_rounded,
      title: CRS.t(CRS.stateReturned, _language),
      message: '“$reason”',
      warning: true,
    );
  }

  /// "Rahim Shah is on Ruwais crew" — the approver sees the same warning.
  Widget _onCrewWarning(String key, AttendanceWorker worker) =>
      YorksMobileCallout(
        key: ValueKey(key),
        icon: Icons.warning_amber_rounded,
        title: CRS.t(CRS.onCrewWarningTitle, _language, {
          'name': worker.name,
          'crew': worker.crewName ?? '',
        }),
        message: CRS.t(CRS.onCrewWarningBody, _language, {'name': worker.name}),
        warning: true,
      );

  Widget _statusPill(AttendanceWorker worker) => worker.crewId == null
      ? CrPill(
          label: CRS.t(CRS.workerFree, _language),
          color: AppColors.success,
          background: AppColors.successContainer,
        )
      : CrPill(
          icon: Icons.warning_amber_rounded,
          label: CRS.t(CRS.workerOnCrew, _language, {
            'crew': worker.crewName ?? '',
          }),
          color: AppColors.warning,
          background: AppColors.warningContainer,
        );

  String _workerMeta(AttendanceWorker worker) => [
    worker.number,
    worker.designation,
  ].where((part) => part.isNotEmpty).join(' · ');

  // ─── Layouts ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppSpacing.stackedBreakpoint
      ? (_editor != null ? _editorPage() : _mobile())
      : _desktop();

  // ─── Desktop: the Material Request composer ────────────────────────────────

  Widget _desktop() => Scaffold(
    backgroundColor: AppColors.surface,
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth >= AppSpacing.yorksV1DesktopBreakpoint
              ? AppSpacing.xxxl + AppSpacing.xs
              : AppSpacing.lg;
          final side = constraints.maxWidth >= 1240;
          final returned = _returnedCallout();
          final main = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (returned != null) ...[
                returned,
                const SizedBox(height: AppSpacing.lg),
              ],
              _informationCard(),
              const SizedBox(height: AppSpacing.xxxl),
              _workersCard(),
              ?_errorBanner(),
            ],
          );
          return SingleChildScrollView(
            key: const ValueKey('crew-request-desktop'),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.xxxl,
              horizontal,
              72,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(),
                    const SizedBox(height: AppSpacing.lg),
                    if (side)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: main),
                          const SizedBox(width: AppSpacing.lg),
                          SizedBox(width: 360, child: _statusPanel()),
                        ],
                      )
                    else ...[
                      main,
                      const SizedBox(height: AppSpacing.lg),
                      _statusPanel(),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  /// The Material Request header: eyebrow, title with stage, guidance,
  /// metadata and the commands.
  Widget _hero() {
    final request = widget.request;
    final sendButton = YorksV1MaterialFormAction(
      key: const ValueKey('crew-request-send'),
      label: _busy
          ? AS.t(AS.saving, _language)
          : CRS.t(request == null ? CRS.send : CRS.sendAgain, _language),
      icon: Icons.send_rounded,
      primary: true,
      onPressed: _busy ? null : _submit,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 920;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CRS.t(CRS.eyebrowRequests, _language).toUpperCase(),
              style: AppTypography.eyebrow,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  request == null
                      ? CRS.t(CRS.formTitleNew, _language)
                      : CRS.t(CRS.formTitleFix, _language, {
                          'number': request.number,
                        }),
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: .18),
                    ),
                  ),
                  child: Text(
                    CRS.t(CRS.stageOf, _language, {'a': 1, 'b': 4}),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSuccessContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              CRS.t(CRS.formIntro, _language),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                YorksV1MaterialFormMeta(
                  icon: Icons.tag_rounded,
                  value:
                      request?.number ?? CRS.t(CRS.assignedOnSend, _language),
                ),
                YorksV1MaterialFormMeta(
                  icon: Icons.person_outline_rounded,
                  value:
                      request?.requestedBy.name ?? ref.watch(actorNameProvider),
                ),
                if (_kind == 'workshop' || _project != null)
                  YorksV1MaterialFormMeta(
                    icon: Icons.business_outlined,
                    value: _whereText,
                  ),
                YorksV1MaterialFormMeta(
                  icon: Icons.groups_outlined,
                  value: CRS.t(CRS.peopleCount, _language, {'n': _peopleCount}),
                ),
              ],
            ),
          ],
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            YorksV1MaterialFormAction(
              key: const ValueKey('crew-request-cancel'),
              label: AS.t(AS.cancel, _language),
              onPressed: _busy ? null : _close,
            ),
            sendButton,
          ],
        );
        return Container(
          key: const ValueKey('crew-request-hero'),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: AppSpacing.lg),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: AppSpacing.xl),
                    actions,
                  ],
                ),
        );
      },
    );
  }

  Widget _informationCard() => YorksV1MaterialFormCard(
    key: const ValueKey('crew-request-information-card'),
    title: CRS.t(CRS.requestInformation, _language),
    description: CRS.t(CRS.detailsDescription, _language),
    child: LayoutBuilder(
      builder: (context, constraints) {
        Widget block(TranslatableString label, Widget child) =>
            YorksV1MaterialFormField(
              label: CRS.t(label, _language),
              child: child,
            );
        final crew = _crewField(labelled: false);
        final both = _options.projects.isNotEmpty && _options.workshop;
        final where = _kind == 'project'
            ? block(CRS.projectLabel, _projectField(labelled: false))
            : block(
                CRS.forLabel,
                InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.handyman_outlined, size: 20),
                  ),
                  child: Text(
                    CRS.t(CRS.workshop, _language),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              );
        final work = block(CRS.workLabel, _workField(labelled: false));
        final from = block(
          CRS.neededFrom,
          _dateField(until: false, labelled: false),
        );
        final until = block(
          CRS.neededUntil,
          _dateField(until: true, labelled: false),
        );
        final crewBlock = crew == null ? null : block(CRS.targetCrew, crew);
        final kind = both ? block(CRS.forLabel, _kindField()) : null;
        const gap = SizedBox(width: AppSpacing.lg);
        const rowGap = SizedBox(height: AppSpacing.lg);
        if (constraints.maxWidth >= 1000) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: where),
                  gap,
                  Expanded(flex: 3, child: work),
                  gap,
                  Expanded(flex: 2, child: from),
                  gap,
                  Expanded(flex: 2, child: until),
                ],
              ),
              if (crewBlock != null || kind != null) ...[
                rowGap,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: crewBlock ?? const SizedBox()),
                    gap,
                    Expanded(flex: 3, child: kind ?? const SizedBox()),
                    gap,
                    const Expanded(flex: 4, child: SizedBox()),
                  ],
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kind != null) ...[kind, rowGap],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: where),
                gap,
                Expanded(flex: 5, child: work),
              ],
            ),
            rowGap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: from),
                gap,
                Expanded(child: until),
                if (crewBlock != null) ...[gap, Expanded(child: crewBlock)],
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _workersCard() {
    final anyFlagged = _lines.any(_flagged);
    final onCrew = [
      for (final (index, line) in _lines.indexed)
        if (line.worker?.crewId != null) (index, line.worker!),
    ];
    return YorksV1MaterialFormCard(
      key: const ValueKey('crew-request-workers-card'),
      sectionNumber: 2,
      title: CRS.t(CRS.peopleSection, _language),
      description: CRS.t(CRS.peopleDescription, _language),
      actions: [
        YorksV1MaterialFormAction(
          key: const ValueKey('crew-request-add-line'),
          label: CRS.t(CRS.addTrade, _language),
          icon: Icons.person_add_alt_1_outlined,
          primary: true,
          onPressed: _busy || _lines.length >= 50 ? null : () => _addRow(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (anyFlagged) ...[
            _AttentionBanner(
              message: CRS.t(CRS.rowsAttention, _language),
              action: CRS.t(CRS.reviewRows, _language),
              onReview: _scrollToFirstFlagged,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _table(),
          for (final (index, worker) in onCrew) ...[
            const SizedBox(height: AppSpacing.md),
            _onCrewWarning('crew-request-on-crew-$index', worker),
          ],
          const SizedBox(height: AppSpacing.lg),
          YorksV1MaterialFormField(
            label: CRS.t(CRS.notesLabel, _language),
            child: _notesField(labelled: false),
          ),
        ],
      ),
    );
  }

  /// The Material Request spreadsheet: S.No, Worker, Qty, Note, Action.
  Widget _table() {
    final header = AppTypography.labelSmall.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: AppColors.surfaceContainerLow),
        children: [
          _Cell(child: Text(CRS.t(CRS.colNumber, _language), style: header)),
          _Cell(
            child: Text(
              CRS.t(CRS.colWorker, _language).toUpperCase(),
              style: header,
            ),
          ),
          _Cell(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                CRS.t(CRS.colQty, _language).toUpperCase(),
                style: header,
              ),
            ),
          ),
          _Cell(
            child: Text(
              CRS.t(CRS.colNote, _language).toUpperCase(),
              style: header,
            ),
          ),
          _Cell(
            child: Text(
              CRS.t(CRS.colAction, _language).toUpperCase(),
              style: header,
            ),
          ),
        ],
      ),
    ];
    for (final (index, line) in _lines.indexed) {
      final flagged = _flagged(line);
      final worker = line.worker;
      rows.add(
        TableRow(
          key: ObjectKey(line),
          decoration: flagged
              ? BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.45),
                  border: const BorderDirectional(
                    start: BorderSide(color: AppColors.error, width: 3),
                  ),
                )
              : null,
          children: [
            _Cell(
              key: line.rowKey,
              child: Text(
                '${index + 1}',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.inkSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _Cell(
              child: worker != null
                  ? _personCell(index, line, worker)
                  : _Marked(
                      markerKey: ValueKey('crew-request-worker-error-$index'),
                      message: flagged && !line.hasWorker
                          ? CRS.t(CRS.workerRequired, _language)
                          : null,
                      child: CrewWorkerField(
                        slot: '$index',
                        controller: line.text,
                        workers: _options.workers,
                        designations: _options.trades,
                        excludedWorkerIds: _namedElsewhere(line),
                        language: _language,
                        enabled: !_busy,
                        desktopCell: true,
                        onChanged: (_) => _changed(),
                        onWorker: (picked) => _pickWorker(line, picked),
                        onDesignation: (_) {
                          if (line.quantity.text.trim().isEmpty) {
                            line.quantity.text = '1';
                          }
                          _changed();
                        },
                      ),
                    ),
            ),
            _Cell(
              child: worker != null
                  ? Tooltip(
                      message: CRS.t(CRS.namedQtyHint, _language),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '1',
                            key: ValueKey('crew-request-quantity-named-$index'),
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ),
                      ),
                    )
                  : _Marked(
                      markerKey: ValueKey('crew-request-quantity-error-$index'),
                      message: flagged && line.hasWorker && !line.hasCount
                          ? CRS.t(CRS.qtyRequired, _language)
                          : null,
                      child: _CellField(
                        fieldKey: ValueKey('crew-request-quantity-$index'),
                        controller: line.quantity,
                        enabled: !_busy,
                        number: true,
                        onChanged: _changed,
                      ),
                    ),
            ),
            _Cell(
              child: _CellField(
                fieldKey: ValueKey('crew-request-note-$index'),
                controller: line.note,
                enabled: !_busy,
                hint: CRS.t(CRS.colNote, _language),
                onChanged: _changed,
              ),
            ),
            _Cell(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RowButton(
                    buttonKey: ValueKey('crew-request-similar-$index'),
                    icon: Icons.copy_all_outlined,
                    color: AppColors.blue,
                    border: AppColors.blue,
                    tooltip: CRS.t(CRS.addSimilarRow, _language),
                    onPressed: _busy || !line.hasWorker || _lines.length >= 50
                        ? null
                        : () => _addSimilar(index),
                  ),
                  const SizedBox(width: 6),
                  _RowButton(
                    buttonKey: ValueKey('crew-request-below-$index'),
                    icon: Icons.add_box_outlined,
                    color: AppColors.blue,
                    border: AppColors.line,
                    tooltip: CRS.t(CRS.addRowBelow, _language),
                    onPressed: _busy || _lines.length >= 50
                        ? null
                        : () => _addRow(after: index),
                  ),
                  const SizedBox(width: 6),
                  _RowButton(
                    buttonKey: ValueKey('crew-request-remove-$index'),
                    icon: Icons.close_rounded,
                    color: AppColors.error,
                    border: AppColors.error,
                    tooltip: CRS.t(CRS.remove, _language),
                    onPressed: _busy ? null : () => _removeRow(index),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return DecoratedBox(
      key: const ValueKey('crew-request-table'),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(54),
            1: FlexColumnWidth(3.4),
            2: FixedColumnWidth(96),
            3: FlexColumnWidth(2.2),
            4: FixedColumnWidth(176),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppColors.line),
            verticalInside: BorderSide(color: AppColors.line),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    );
  }

  /// A person asked for by name, in the Worker cell. The Free or crew tag
  /// sits beside the name when there is room, otherwise under it.
  Widget _personCell(int index, _LineDraft line, AttendanceWorker worker) =>
      LayoutBuilder(
        key: ValueKey('crew-request-named-$index'),
        builder: (context, constraints) {
          final roomy = constraints.maxWidth >= 380;
          return Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Row(
              children: [
                AttendanceAvatar(initials: worker.initials),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        worker.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _workerMeta(worker),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      if (!roomy) ...[
                        const SizedBox(height: 4),
                        _statusPill(worker),
                      ],
                    ],
                  ),
                ),
                if (roomy) ...[const SizedBox(width: 8), _statusPill(worker)],
                _changeButton(index, line),
              ],
            ),
          );
        },
      );

  Widget _changeButton(int index, _LineDraft line) => IconButton(
    key: ValueKey('crew-request-change-$index'),
    tooltip: CRS.t(CRS.changePerson, _language),
    onPressed: _busy ? null : () => _clearWorker(line),
    icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.blue),
  );

  /// The Material Request "Request Status" panel.
  Widget _statusPanel() {
    final request = widget.request;
    final ready = _detailsReady && _peopleReady;
    return Container(
      key: const ValueKey('crew-request-summary'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 19,
                color: AppColors.blue,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  CRS.t(CRS.requestStatus, _language),
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: ready
                      ? AppColors.successContainer
                      : AppColors.warningContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  CRS.t(ready ? CRS.ready : CRS.addWorkersChip, _language),
                  style: AppTypography.labelMedium.copyWith(
                    color: ready
                        ? AppColors.onSuccessContainer
                        : AppColors.onWarningContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CrStepIndicator(
            labels: [
              CRS.t(CRS.stageRequested, _language),
              CRS.t(CRS.stageApproval, _language),
              CRS.t(CRS.stageOnSiteShort, _language),
              CRS.t(CRS.stageDone, _language),
            ],
            active: 0,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Notice(text: _routeText),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),
          Text(
            CRS.t(CRS.reviewHeading, _language),
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CrFact(
            label: CRS.t(CRS.factRequestNumber, _language),
            value: request?.number ?? CRS.t(CRS.assignedOnSend, _language),
          ),
          CrFact(label: CRS.t(CRS.projectLabel, _language), value: _whereText),
          CrFact(label: CRS.t(CRS.factNeeded, _language), value: _datesText),
          CrFact(label: CRS.t(CRS.targetCrew, _language), value: _crewText),
          if (_peopleCount > 0)
            CrFact(
              label: CRS.t(CRS.rowPeople, _language),
              value: [
                for (final line in _filled)
                  if (line.isValid) line.label,
              ].join(', '),
            ),
          CrFact(
            label: CRS.t(CRS.factRequestedBy, _language),
            value: request?.requestedBy.name ?? ref.watch(actorNameProvider),
            last: true,
          ),
        ],
      ),
    );
  }

  // ─── Phone: Details, Workers, Review ───────────────────────────────────────

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
    final returned = _returnedCallout();
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
                if (returned != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  returned,
                ],
                const SizedBox(height: AppSpacing.lg),
                ...switch (_step) {
                  _Step.details => _detailsBody(),
                  _Step.people => _basketBody(),
                  _Step.review => _reviewBody(),
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
              summary: _routeText,
              children: [
                FilledButton.icon(
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
                        : CRS.t(
                            request == null ? CRS.send : CRS.sendAgain,
                            _language,
                          ),
                  ),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }

  List<Widget> _detailsBody() {
    final crew = _crewField();
    return [
      YorksMobileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_options.projects.isNotEmpty && _options.workshop) ...[
              _kindField(),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_kind == 'project') ...[
              _projectField(),
              const SizedBox(height: AppSpacing.md),
            ],
            _workField(),
            const SizedBox(height: AppSpacing.md),
            _dateField(until: false),
            const SizedBox(height: AppSpacing.md),
            _dateField(until: true),
            if (crew != null) ...[const SizedBox(height: AppSpacing.md), crew],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      YorksMobileCallout(
        icon: Icons.shield_outlined,
        title: CRS.t(CRS.rowRoute, _language),
        message: _routeText,
      ),
    ];
  }

  /// The worker basket, like the Material Request basket.
  List<Widget> _basketBody() {
    final filled = [
      for (final (index, line) in _lines.indexed)
        if (!line.isBlank) (index, line),
    ];
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          key: const ValueKey('crew-request-add-line'),
          onPressed: _busy || _lines.length >= 50 ? null : () => _openEditor(),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
          label: Text(CRS.t(CRS.addTrade, _language)),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      ),
      const SizedBox(height: 16),
      YorksMobileSectionHeader(
        title: CRS.t(CRS.selectedWorkers, _language),
        subtitle: CRS.t(CRS.peopleCount, _language, {'n': _peopleCount}),
      ),
      const SizedBox(height: 10),
      if (filled.isEmpty)
        YorksMobileCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 24,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 10),
                Text(
                  CRS.t(CRS.noWorkersYet, _language),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        )
      else
        for (final (position, (index, line)) in filled.indexed) ...[
          _mobileCard(position + 1, index, line),
          const SizedBox(height: 10),
        ],
    ];
  }

  Widget _numberBox(int number, {bool review = false}) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: review ? AppColors.blueContainer : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$number',
      style: AppTypography.labelMedium.copyWith(
        color: review ? AppColors.blue : null,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  String _lineMeta(_LineDraft line) {
    final worker = line.worker;
    final note = line.note.text.trim();
    return [
      if (worker != null) _workerMeta(worker),
      if (worker == null)
        '${CRS.t(CRS.colQty, _language)} ${line.count ?? '—'}',
      if (note.isNotEmpty) note,
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  Widget _mobileCard(int number, int index, _LineDraft line) {
    final flagged = _flagged(line);
    final worker = line.worker;
    return YorksMobileCard(
      key: ValueKey('crew-request-card-$index'),
      color: flagged
          ? AppColors.errorContainer
          : AppColors.surfaceContainerLowest,
      onTap: _busy ? null : () => _openEditor(index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _numberBox(number),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _lineMeta(line),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    if (worker != null) ...[
                      const SizedBox(height: 6),
                      _statusPill(worker),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RowButton(
                  buttonKey: ValueKey('crew-request-edit-$index'),
                  icon: Icons.edit_outlined,
                  color: AppColors.blue,
                  border: AppColors.line,
                  tooltip: CRS.t(CRS.editWorker, _language),
                  onPressed: _busy ? null : () => _openEditor(index),
                ),
                const SizedBox(width: 6),
                _RowButton(
                  buttonKey: ValueKey('crew-request-similar-$index'),
                  icon: Icons.copy_all_outlined,
                  color: AppColors.blue,
                  border: AppColors.blue,
                  tooltip: CRS.t(CRS.addSimilarRow, _language),
                  onPressed: _busy || _lines.length >= 50
                      ? null
                      : () => _addSimilar(index),
                ),
                const SizedBox(width: 6),
                _RowButton(
                  buttonKey: ValueKey('crew-request-remove-$index'),
                  icon: Icons.close_rounded,
                  color: AppColors.error,
                  border: AppColors.error,
                  tooltip: CRS.t(CRS.remove, _language),
                  onPressed: _busy ? null : () => _removeRow(index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _reviewBody() {
    final filled = _filled;
    return [
      YorksMobileCard(
        key: const ValueKey('crew-request-summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CrFact(
              label: CRS.t(CRS.projectLabel, _language),
              value: _whereText,
            ),
            if (_work.text.trim().isNotEmpty)
              CrFact(
                label: CRS.t(CRS.factWork, _language),
                value: _work.text.trim(),
              ),
            CrFact(label: CRS.t(CRS.factNeeded, _language), value: _datesText),
            CrFact(label: CRS.t(CRS.targetCrew, _language), value: _crewText),
            CrFact(
              label: CRS.t(CRS.rowRoute, _language),
              value: _routeText,
              last: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      YorksMobileSectionHeader(
        title: CRS.t(CRS.selectedWorkers, _language),
        subtitle: CRS.t(CRS.peopleCount, _language, {'n': _peopleCount}),
      ),
      const SizedBox(height: 10),
      for (final (position, line) in filled.indexed) ...[
        YorksMobileCard(
          key: ValueKey('crew-request-review-$position'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _numberBox(position + 1, review: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line.label,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (line.note.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  line.note.text.trim(),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
              if (line.worker?.crewId != null) ...[
                const SizedBox(height: 8),
                _statusPill(line.worker!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      YorksMobileCard(child: _notesField()),
    ];
  }

  /// The focused one-worker editor, like the Material Request custom item.
  Widget _editorPage() {
    final editor = _editor!;
    final worker = editor.worker;
    final editing = _editorIndex != null;
    final title = CRS.t(
      editing ? CRS.editWorker : CRS.addWorkerTitle,
      _language,
    );
    return Scaffold(
      backgroundColor: AppColors.mobileSurface,
      body: Column(
        children: [
          YorksMobileAppBar(
            title: title,
            leading: YorksMobileIconButton(
              key: const ValueKey('crew-request-editor-back'),
              icon: Icons.arrow_back_rounded,
              tooltip: CRS.t(CRS.backAction, _language),
              onPressed: _closeEditor,
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('crew-request-editor'),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
              children: [
                Text(
                  title,
                  style: AppTypography.headlineMedium.copyWith(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  CRS.t(CRS.peopleDescription, _language),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 14),
                YorksMobileCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (worker != null)
                        _editorPerson(editor, worker)
                      else
                        CrewWorkerField(
                          slot: 'editor',
                          controller: editor.text,
                          workers: _options.workers,
                          designations: _options.trades,
                          excludedWorkerIds: {
                            for (final (index, line) in _lines.indexed)
                              if (index != _editorIndex && line.worker != null)
                                line.worker!.id,
                          },
                          language: _language,
                          label: CRS.t(CRS.colWorker, _language),
                          errorText: _editorAttempted && !editor.hasWorker
                              ? CRS.t(CRS.workerRequired, _language)
                              : null,
                          onChanged: (_) => setState(() {}),
                          onWorker: (picked) => setState(() {
                            editor.worker = picked;
                            editor.text.clear();
                            editor.quantity.clear();
                          }),
                          onDesignation: (_) => setState(() {
                            if (editor.quantity.text.trim().isEmpty) {
                              editor.quantity.text = '1';
                            }
                          }),
                        ),
                      const SizedBox(height: 12),
                      if (worker != null)
                        TextField(
                          key: const ValueKey('crew-request-quantity-editor'),
                          controller: _namedQuantity,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: CRS.t(CRS.colQty, _language),
                            helperText: CRS.t(CRS.namedQtyHint, _language),
                          ),
                        )
                      else
                        TextField(
                          key: const ValueKey('crew-request-quantity-editor'),
                          controller: editor.quantity,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: CRS.t(CRS.colQty, _language),
                            errorText:
                                _editorAttempted &&
                                    editor.hasWorker &&
                                    !editor.hasCount
                                ? CRS.t(CRS.qtyRequired, _language)
                                : null,
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('crew-request-note-editor'),
                        controller: editor.note,
                        decoration: InputDecoration(
                          labelText: CRS.t(CRS.lineNote, _language),
                        ),
                      ),
                    ],
                  ),
                ),
                if (worker?.crewId != null) ...[
                  const SizedBox(height: 12),
                  _onCrewWarning('crew-request-on-crew-editor', worker!),
                ],
              ],
            ),
          ),
          YorksMobileStickyActions(
            children: [
              OutlinedButton(
                onPressed: _closeEditor,
                child: Text(CRS.t(CRS.backAction, _language)),
              ),
              FilledButton.icon(
                key: const ValueKey('crew-request-editor-save'),
                onPressed: _saveEditor,
                icon: Icon(editing ? Icons.check_rounded : Icons.add_rounded),
                label: Text(
                  CRS.t(editing ? CRS.saveChanges : CRS.addTrade, _language),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editorPerson(_LineDraft editor, AttendanceWorker worker) => Container(
    key: const ValueKey('crew-request-named-editor'),
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
                _workerMeta(worker),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 6),
              _statusPill(worker),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('crew-request-change-editor'),
          onPressed: () => setState(() {
            editor.worker = null;
            editor.text.clear();
          }),
          child: Text(CRS.t(CRS.changePerson, _language)),
        ),
      ],
    ),
  );
}

/// A Material Request table cell: steady 56 px rows.
class _Cell extends StatelessWidget {
  const _Cell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    ),
  );
}

/// A borderless spreadsheet cell field, focused with a blue outline.
class _CellField extends StatelessWidget {
  const _CellField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.number = false,
    this.hint,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final bool number;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    enabled: enabled,
    keyboardType: number ? TextInputType.number : null,
    textAlign: number ? TextAlign.end : TextAlign.start,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.blue, width: 2),
      ),
    ),
  );
}

/// The Material Request red dot on a missing cell.
class _Marked extends StatelessWidget {
  const _Marked({
    required this.markerKey,
    required this.message,
    required this.child,
  });

  final Key markerKey;
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      if (message != null)
        PositionedDirectional(
          top: 0,
          end: 0,
          child: Tooltip(
            message: message!,
            excludeFromSemantics: true,
            child: Semantics(
              label: message,
              liveRegion: true,
              child: SizedBox.square(
                key: markerKey,
                dimension: 20,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// The Material Request row buttons: Similar, row below, edit, delete.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.buttonKey,
    required this.icon,
    required this.color,
    required this.border,
    required this.tooltip,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final Color color;
  final Color border;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    tooltip: tooltip,
    icon: Icon(icon, color: onPressed == null ? AppColors.muted : color),
    style: IconButton.styleFrom(
      side: BorderSide(color: onPressed == null ? AppColors.line : border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(44, 44),
    ),
    onPressed: onPressed,
  );
}

/// The Material Request "rows need attention" banner.
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({
    required this.message,
    required this.action,
    required this.onReview,
  });

  final String message;
  final String action;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('crew-request-attention'),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.errorContainer,
      border: Border.all(color: AppColors.error),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 19,
          color: AppColors.error,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(onPressed: onReview, child: Text(action)),
      ],
    ),
  );
}

/// The Material Request notice in the status panel.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.warningContainer.withValues(alpha: .62),
      border: Border.all(color: AppColors.warning.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: AppColors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
