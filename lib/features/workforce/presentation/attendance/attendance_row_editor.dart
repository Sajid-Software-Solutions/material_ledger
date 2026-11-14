/// Workforce attendance V2 — the per-worker editor (a bottom sheet on phones,
/// a dialog on desktop) and the desktop day grid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';
import 'attendance_inputs.dart';
import 'attendance_place_picker.dart';

enum AttendanceEditorMove { previous, next, close }

typedef AttendanceEditorResult = ({
  AttendanceRow row,
  AttendanceEditorMove move,
});

Future<AttendanceEditorResult?> showAttendanceRowEditor(
  BuildContext context, {
  required AttendanceRow row,
  required AttendanceDay day,
  required AppLanguage language,
  required bool hasPrevious,
  required bool hasNext,
  required AttendanceRow Function(AttendanceRow row) presentOnShift,
}) {
  final editor = _RowEditor(
    initial: row,
    day: day,
    language: language,
    hasPrevious: hasPrevious,
    hasNext: hasNext,
    presentOnShift: presentOnShift,
  );
  if (AccountsV2Breakpoints.isPhone(context)) {
    return showModalBottomSheet<AttendanceEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: editor,
      ),
    );
  }
  return showDialog<AttendanceEditorResult>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: editor,
      ),
    ),
  );
}

class _RowEditor extends StatefulWidget {
  const _RowEditor({
    required this.initial,
    required this.day,
    required this.language,
    required this.hasPrevious,
    required this.hasNext,
    required this.presentOnShift,
  });

  final AttendanceRow initial;
  final AttendanceDay day;
  final AppLanguage language;
  final bool hasPrevious;
  final bool hasNext;
  final AttendanceRow Function(AttendanceRow row) presentOnShift;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late AttendanceRow _row;
  final _in = TextEditingController();
  final _break = TextEditingController();
  final _back = TextEditingController();
  final _out = TextEditingController();
  final _note = TextEditingController();
  final _project = TextEditingController();

  /// The row's building, at a project place.
  String? _scopeId;
  String? _scopeName;

  bool get _projectPlace =>
      widget.day.crew.placeKind == 'project' &&
      widget.day.crew.buildings.isNotEmpty;

  AppLanguage get _language => widget.language;

  @override
  void initState() {
    super.initState();
    // Opening an unmarked worker on a working day starts at Present, unless
    // they are recorded at another place today: then the keeper chooses.
    _row =
        widget.initial.isMarked ||
            widget.day.holiday ||
            widget.initial.busyElsewhere
        ? widget.initial
        : widget.presentOnShift(widget.initial);
    _syncFields();
  }

  void _syncFields() {
    _in.text = formatAttendanceTimeInput(_row.start);
    _break.text = formatAttendanceTimeInput(_row.breakStart);
    _back.text = formatAttendanceTimeInput(_row.breakFinish);
    _out.text = formatAttendanceTimeInput(_row.finish);
    _note.text = _row.overtimeNote ?? '';
    _project.text = _row.workLabel ?? widget.day.crew.workLabel;
    _scopeId = _row.workScopeId;
    _scopeName = _row.workScopeName;
  }

  @override
  void dispose() {
    for (final c in [_in, _break, _back, _out, _note, _project]) {
      c.dispose();
    }
    super.dispose();
  }

  AttendanceParsedTime get _pIn => parseAttendanceTime(_in.text);
  AttendanceParsedTime get _pBreak =>
      parseAttendanceTime(_break.text, after: _pIn.minutes);
  AttendanceParsedTime get _pBack =>
      parseAttendanceTime(_back.text, after: _pBreak.minutes ?? _pIn.minutes);
  AttendanceParsedTime get _pOut =>
      parseAttendanceTime(_out.text, after: _pBack.minutes ?? _pIn.minutes);

  AttendanceRow _current() {
    if (_row.status != AttendanceStatus.present) {
      return _row.copyWith(
        clearTimes: true,
        overtimeNote: null,
        clearNote: true,
      );
    }
    final hasBreak = _pBreak.minutes != null && _pBack.minutes != null;
    final note = _note.text.trim();
    final label = _project.text.trim();
    final crew = widget.day.crew;
    final draft = AttendanceRow(
      worker: _row.worker,
      status: AttendanceStatus.present,
      start: _pIn.minutes,
      breakStart: hasBreak ? _pBreak.minutes : null,
      breakFinish: hasBreak ? _pBack.minutes : null,
      finish: _pOut.minutes,
      // At a place the row is on the place's project, at a building.
      workProjectId: crew.isPlace
          ? (crew.projectId ?? _row.workProjectId)
          : label == crew.workLabel
          ? (_row.workProjectId ?? crew.projectId)
          : null,
      workLabel: _projectPlace || label.isEmpty ? null : label,
      workScopeId: _projectPlace ? _scopeId : _row.workScopeId,
      workScopeName: _projectPlace ? _scopeName : _row.workScopeName,
      overtimeNote: note.isEmpty ? null : note,
      copied: false,
      changedAfterEntry: _row.changedAfterEntry,
      isMember: _row.isMember,
      elsewhere: _row.elsewhere,
      updatedBy: _row.updatedBy,
      updatedByMe: _row.updatedByMe,
    );
    return draft;
  }

  void _setStatus(AttendanceStatus status) {
    setState(() {
      _row = status == AttendanceStatus.present
          ? widget.presentOnShift(_row.copyWith(status: status))
          : _row.copyWith(status: status, clearTimes: true);
      _syncFields();
    });
  }

  void _finish(AttendanceEditorMove move) {
    Navigator.of(context).pop((row: _current(), move: move));
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final day = widget.day;
    final row = _current();
    final present = row.status == AttendanceStatus.present;
    final minutes = row.minutes(holiday: day.holiday);
    final statuses = [
      AttendanceStatus.present,
      AttendanceStatus.absent,
      if (day.holiday) AttendanceStatus.rest,
      AttendanceStatus.annualLeave,
      AttendanceStatus.sickLeave,
      AttendanceStatus.officialLeave,
      AttendanceStatus.unpaidLeave,
    ];

    Widget timeField(
      String label,
      TextEditingController controller,
      AttendanceParsedTime parsed,
      String key, {
      bool last = false,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AttendanceTimeField(
            key: ValueKey(key),
            label: label,
            controller: controller,
            error: !parsed.ok,
            last: last,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 2),
          Text(
            parsed.ok
                ? formatAttendanceTime(parsed.minutes)
                : AS.t(AS.notATime, language),
            style: v2Style(
              11,
              color: parsed.ok ? AccountsV2Colors.mut : AccountsV2Colors.bad,
            ),
          ),
        ],
      ),
    );

    final actions = Row(
      children: [
        AccountsV2Button(
          label: AS.t(AS.previous, language),
          icon: 'caret',
          onPressed: widget.hasPrevious
              ? () => _finish(AttendanceEditorMove.previous)
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AccountsV2Button(
            key: const ValueKey('attendance-editor-done'),
            block: true,
            kind: AccountsV2ButtonKind.primary,
            size: AccountsV2ButtonSize.large,
            label: widget.hasNext
                ? AS.t(AS.saveNext, language)
                : AS.t(AS.done, language),
            onPressed:
                present && (!_pIn.ok || !_pOut.ok || !_pBreak.ok || !_pBack.ok)
                ? null
                : () => _finish(
                    widget.hasNext
                        ? AttendanceEditorMove.next
                        : AttendanceEditorMove.close,
                  ),
          ),
        ),
      ],
    );

    // The details scroll; Previous and Save & next stay pinned at the
    // bottom, above the keyboard.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('attendance-editor-scroll'),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _content(
                context,
                row,
                present,
                minutes,
                statuses,
                timeField,
              ),
            ),
          ),
        ),
        DecoratedBox(
          key: const ValueKey('attendance-editor-actions'),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AccountsV2Colors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: actions,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _content(
    BuildContext context,
    AttendanceRow row,
    bool present,
    AttendanceMinutes minutes,
    List<AttendanceStatus> statuses,
    Widget Function(
      String label,
      TextEditingController controller,
      AttendanceParsedTime parsed,
      String key, {
      bool last,
    })
    timeField,
  ) {
    final language = _language;
    final day = widget.day;
    return [
      Row(
        children: [
          AttendanceAvatar(initials: row.worker.initials, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      row.worker.name,
                      style: v2Style(15, weight: FontWeight.w700),
                    ),
                    CrewDocumentBadge(
                      crewId: day.crew.id,
                      workerId: row.worker.id,
                    ),
                  ],
                ),
                Text(
                  '${row.worker.number} · ${row.worker.designation} · ${attendanceShortDate(day.date)}',
                  style: v2Style(12, color: AccountsV2Colors.mut),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AS.t(AS.cancel, language),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
      // The worker's other places today, so this place's times fit.
      if (row.elsewhere.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('attendance-editor-elsewhere'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AccountsV2Colors.neu,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AS.t(AS.alsoToday, language),
                style: v2Style(12, weight: FontWeight.w700),
              ),
              for (final other in row.elsewhere)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${other.crewName} · ${attendancePlaceTime(other, language)}',
                    style: v2Style(12.5, color: AccountsV2Colors.ink2),
                  ),
                ),
              if (!widget.initial.isMarked && widget.initial.busyElsewhere)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    AS.t(AS.markHereToo, language),
                    style: v2Style(12, color: AccountsV2Colors.mut),
                  ),
                ),
            ],
          ),
        ),
      ],
      for (final line in attendancePlaceLines(row, language))
        if (line.bad)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              line.text,
              key: const ValueKey('attendance-editor-conflict'),
              style: v2Style(
                12.5,
                weight: FontWeight.w700,
                color: AccountsV2Colors.bad,
              ),
            ),
          ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final status in statuses)
            AttendanceChoiceChip(
              key: ValueKey('attendance-editor-status-${status.code}'),
              label: attendanceStatusLabel(status).active(language),
              selected: row.status == status,
              onPressed: () => _setStatus(status),
            ),
        ],
      ),
      if (present) ...[
        const SizedBox(height: 14),
        Text(
          AS.t(AS.timeHint, language),
          style: v2Style(12, weight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            timeField(
              AS.t(AS.colIn, language),
              _in,
              _pIn,
              'attendance-editor-in',
            ),
            const SizedBox(width: 6),
            timeField(
              AS.t(AS.colBreak, language),
              _break,
              _pBreak,
              'attendance-editor-break',
            ),
            const SizedBox(width: 6),
            timeField(
              AS.t(AS.colBack, language),
              _back,
              _pBack,
              'attendance-editor-back',
            ),
            const SizedBox(width: 6),
            timeField(
              AS.t(AS.colOut, language),
              _out,
              _pOut,
              'attendance-editor-out',
              last: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              AS.t(AS.outAt, language),
              style: v2Style(12, color: AccountsV2Colors.mut),
            ),
            for (final minute in const [900, 1020, 1080, 1140])
              AttendanceChoiceChip(
                key: ValueKey('attendance-editor-out-at-$minute'),
                label: formatAttendanceTime(minute),
                selected: _pOut.minutes == minute,
                onPressed: () => setState(
                  () => _out.text = formatAttendanceTimeInput(minute),
                ),
              ),
            AttendanceChoiceChip(
              key: const ValueKey('attendance-editor-toggle-break'),
              label: _break.text.isEmpty
                  ? AS.t(AS.addBreak, language)
                  : AS.t(AS.noBreak, language),
              onPressed: () => setState(() {
                if (_break.text.isEmpty) {
                  _break.text = formatAttendanceTimeInput(
                    day.crew.breakStart ?? 750,
                  );
                  _back.text = formatAttendanceTimeInput(
                    day.crew.breakFinish ?? 780,
                  );
                } else {
                  _break.clear();
                  _back.clear();
                }
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AccountsV2Colors.neu,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              for (final (label, value, color) in [
                (AS.colHours, minutes.worked, AccountsV2Colors.ink),
                (AS.colNormal, minutes.regular, AccountsV2Colors.ink),
                (
                  AS.colOtNormalShort,
                  minutes.normalOvertime,
                  AccountsV2Colors.warn,
                ),
                (
                  AS.colOtHolidayShort,
                  minutes.holidayOvertime,
                  AccountsV2Colors.vio,
                ),
              ])
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        minutes.timeMissing
                            ? '?'
                            : formatAttendanceHours(value, zeroAsDash: true),
                        style: v2Style(
                          16,
                          weight: FontWeight.w700,
                          color: color,
                          tabular: true,
                        ),
                      ),
                      Text(
                        label.active(language),
                        textAlign: TextAlign.center,
                        style: v2Style(11, color: AccountsV2Colors.mut),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_projectPlace) ...[
          Text(
            AS.t(AS.colBuilding, language),
            style: v2Style(12, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final building in day.crew.buildings)
                AttendanceChoiceChip(
                  key: ValueKey('attendance-editor-building-${building.id}'),
                  label: attendanceBuildingName(building, language),
                  selected: _scopeId == building.id,
                  onPressed: () => setState(() {
                    _scopeId = building.id;
                    _scopeName = building.name;
                  }),
                ),
            ],
          ),
        ] else
          AccountsV2TextField(
            key: const ValueKey('attendance-editor-project'),
            label: AS.t(AS.colProject, language),
            hint: AS.t(AS.projectHint, language),
            controller: _project,
            onChanged: (_) => setState(() {}),
          ),
        if (minutes.overtime > 0) ...[
          const SizedBox(height: 10),
          Text(
            AS.t(AS.overtimeNote, language),
            style: v2Style(12, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final note in [
                AS.noteConcrete,
                AS.noteClient,
                AS.noteShutdown,
                AS.noteUrgent,
              ])
                AttendanceChoiceChip(
                  label: note.active(language),
                  selected: _note.text.trim() == note.active(language),
                  onPressed: () =>
                      setState(() => _note.text = note.active(language)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          AccountsV2TextField(
            key: const ValueKey('attendance-editor-note'),
            label: AS.t(AS.overtimeNoteHint, language),
            controller: _note,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    ];
  }
}

// ─── Desktop grid ────────────────────────────────────────────────────────────

/// The day as a keyboard-friendly table: status, In / Break / Back / Out,
/// live hours and the place, one row per worker. Tab moves along the row;
/// typed times are read with the same smart rules as the editor.
class AttendanceGrid extends ConsumerWidget {
  const AttendanceGrid({
    super.key,
    required this.state,
    required this.controller,
    required this.language,
    required this.onOpenEditor,
    this.onPickBuilding,
  });

  final AttendanceDayEditState state;
  final AttendanceDayController controller;
  final AppLanguage language;
  final ValueChanged<int> onOpenEditor;

  /// At a project place: the Building column, changed by tapping.
  final ValueChanged<AttendanceRow>? onPickBuilding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = state.day!;
    final header = v2Style(
      11,
      weight: FontWeight.w700,
      color: AccountsV2Colors.mut,
      letterSpacing: 0.3,
    );
    Widget head(String text, double width, {bool end = false}) => SizedBox(
      width: width,
      child: Text(
        text.toUpperCase(),
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: header,
      ),
    );
    return AccountsV2Panel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: AccountsV2Colors.tableHead,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    head(AS.t(AS.colWorker, language), 230),
                    head(AS.t(AS.colStatus, language), 150),
                    head(AS.t(AS.colIn, language), 78),
                    head(AS.t(AS.colBreak, language), 78),
                    head(AS.t(AS.colBack, language), 78),
                    head(AS.t(AS.colOut, language), 78),
                    head(AS.t(AS.colHours, language), 60, end: true),
                    head(AS.t(AS.colOtNormalShort, language), 74, end: true),
                    head(AS.t(AS.colOtHolidayShort, language), 74, end: true),
                    const SizedBox(width: 12),
                    head(
                      onPickBuilding == null
                          ? AS.t(AS.colProject, language)
                          : AS.t(AS.colBuilding, language),
                      170,
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < state.rows.length; i++)
                _GridRow(
                  key: ValueKey('attendance-grid-${state.rows[i].worker.id}'),
                  row: state.rows[i],
                  day: day,
                  language: language,
                  onChanged: (row) => controller.setRow(row.worker.id, row),
                  presentOnShift: controller.presentOnShift,
                  onOpenEditor: () => onOpenEditor(i),
                  onPickBuilding: onPickBuilding == null
                      ? null
                      : () => onPickBuilding!(state.rows[i]),
                  onRemove: state.rows[i].isMember
                      ? null
                      : () => controller.removeDayOnly(state.rows[i].worker.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridRow extends StatefulWidget {
  const _GridRow({
    super.key,
    required this.row,
    required this.day,
    required this.language,
    required this.onChanged,
    required this.presentOnShift,
    required this.onOpenEditor,
    this.onRemove,
    this.onPickBuilding,
  });

  final AttendanceRow row;
  final AttendanceDay day;
  final AppLanguage language;
  final ValueChanged<AttendanceRow> onChanged;
  final AttendanceRow Function(AttendanceRow row) presentOnShift;
  final VoidCallback onOpenEditor;
  final VoidCallback? onRemove;
  final VoidCallback? onPickBuilding;

  @override
  State<_GridRow> createState() => _GridRowState();
}

class _GridRowState extends State<_GridRow> {
  final _in = TextEditingController();
  final _break = TextEditingController();
  final _back = TextEditingController();
  final _out = TextEditingController();
  final _project = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_GridRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.row.sameEntry(widget.row)) _sync();
  }

  void _sync() {
    final row = widget.row;
    _in.text = formatAttendanceTimeInput(row.start);
    _break.text = formatAttendanceTimeInput(row.breakStart);
    _back.text = formatAttendanceTimeInput(row.breakFinish);
    _out.text = formatAttendanceTimeInput(row.finish);
    _project.text = row.workLabel ?? widget.day.crew.workLabel;
  }

  @override
  void dispose() {
    for (final c in [_in, _break, _back, _out, _project]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reads every time field (with the previous field as context) and saves.
  void _commitTimes() {
    final start = parseAttendanceTime(_in.text);
    final breakStart = parseAttendanceTime(_break.text, after: start.minutes);
    final breakFinish = parseAttendanceTime(
      _back.text,
      after: breakStart.minutes ?? start.minutes,
    );
    final finish = parseAttendanceTime(
      _out.text,
      after: breakFinish.minutes ?? start.minutes,
    );
    if (!start.ok || !breakStart.ok || !breakFinish.ok || !finish.ok) {
      setState(() {});
      return;
    }
    final hasBreak = breakStart.minutes != null && breakFinish.minutes != null;
    widget.onChanged(
      AttendanceRow(
        worker: widget.row.worker,
        status: widget.row.status,
        start: start.minutes,
        breakStart: hasBreak ? breakStart.minutes : null,
        breakFinish: hasBreak ? breakFinish.minutes : null,
        finish: finish.minutes,
        workProjectId: widget.row.workProjectId,
        workLabel: widget.row.workLabel,
        workScopeId: widget.row.workScopeId,
        workScopeName: widget.row.workScopeName,
        overtimeNote: widget.row.overtimeNote,
        changedAfterEntry: widget.row.changedAfterEntry,
        isMember: widget.row.isMember,
        elsewhere: widget.row.elsewhere,
        updatedBy: widget.row.updatedBy,
        updatedByMe: widget.row.updatedByMe,
      ),
    );
  }

  void _commitProject() {
    final label = _project.text.trim();
    widget.onChanged(
      widget.row.copyWith(
        workLabel: label.isEmpty ? null : label,
        clearWork: label.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final day = widget.day;
    final language = widget.language;
    final present = row.status == AttendanceStatus.present;
    final minutes = row.minutes(holiday: day.holiday);
    final statuses = <AttendanceStatus?>[
      null,
      AttendanceStatus.present,
      AttendanceStatus.absent,
      if (day.holiday) AttendanceStatus.rest,
      AttendanceStatus.annualLeave,
      AttendanceStatus.sickLeave,
      AttendanceStatus.officialLeave,
      AttendanceStatus.unpaidLeave,
    ];

    Widget time(TextEditingController controller, String key) => SizedBox(
      width: 78,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Focus(
          onFocusChange: (focused) {
            if (!focused) _commitTimes();
          },
          child: TextField(
            key: ValueKey('$key-${row.worker.id}'),
            controller: controller,
            enabled: present,
            style: v2Style(13, tabular: true),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _commitTimes(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              errorText: parseAttendanceTime(controller.text).ok ? null : '',
              errorStyle: const TextStyle(height: 0, fontSize: 0),
            ),
          ),
        ),
      ),
    );

    Widget number(int value, Color color) => SizedBox(
      width: present ? (value == 0 ? 74 : 74) : 74,
      child: Text(
        present && minutes.timeMissing ? '?' : formatAttendanceHours(value),
        textAlign: TextAlign.end,
        style: v2Style(
          13,
          weight: FontWeight.w600,
          color: color,
          tabular: true,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: row.copied
            ? AccountsV2Colors.pri50.withValues(alpha: 0.45)
            : null,
        border: const Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 230,
            child: Row(
              children: [
                AttendanceAvatar(initials: row.worker.initials, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              row.worker.name,
                              overflow: TextOverflow.ellipsis,
                              style: v2Style(13, weight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 4),
                          CrewDocumentBadge(
                            crewId: widget.day.crew.id,
                            workerId: row.worker.id,
                            compact: true,
                          ),
                        ],
                      ),
                      Text(
                        row.isMember || day.crew.isPlace
                            ? [
                                row.worker.number,
                                row.worker.designation,
                                if (!row.updatedByMe && row.updatedBy != null)
                                  AS.t(AS.savedBy, language, {
                                    'by': row.updatedBy,
                                  }),
                              ].where((part) => part.isNotEmpty).join(' · ')
                            : (row.worker.crewName == null
                                  ? AS.t(AS.labourPool, language)
                                  : AS.t(AS.fromCrew, language, {
                                      'crew': row.worker.crewName,
                                    })),
                        overflow: TextOverflow.ellipsis,
                        style: v2Style(
                          11.5,
                          color: row.isMember || day.crew.isPlace
                              ? AccountsV2Colors.mut
                              : AccountsV2Colors.vio,
                        ),
                      ),
                      // Where else the worker is today, or what clashes.
                      for (final line in attendancePlaceLines(row, language))
                        Tooltip(
                          message: line.text,
                          child: Text(
                            line.text,
                            key: ValueKey(
                              'attendance-grid-place-${row.worker.id}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: v2Style(
                              11,
                              weight: line.bad
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: line.bad
                                  ? AccountsV2Colors.bad
                                  : AccountsV2Colors.mut,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: DropdownButtonFormField<AttendanceStatus?>(
                key: ValueKey('attendance-grid-status-${row.worker.id}'),
                initialValue: row.status,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: v2Style(13),
                items: [
                  for (final status in statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(
                        attendanceStatusLabel(status).active(language),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (status) {
                  if (status == null) {
                    widget.onChanged(row.copyWith(clearStatus: true));
                  } else if (status == AttendanceStatus.present) {
                    widget.onChanged(widget.presentOnShift(row));
                  } else {
                    widget.onChanged(
                      row.copyWith(status: status, clearTimes: true),
                    );
                  }
                },
              ),
            ),
          ),
          time(_in, 'attendance-grid-in'),
          time(_break, 'attendance-grid-break'),
          time(_back, 'attendance-grid-back'),
          time(_out, 'attendance-grid-out'),
          SizedBox(
            width: 60,
            child: Text(
              present && minutes.timeMissing
                  ? '?'
                  : formatAttendanceHours(minutes.worked),
              textAlign: TextAlign.end,
              style: v2Style(13, weight: FontWeight.w700, tabular: true),
            ),
          ),
          number(minutes.normalOvertime, AccountsV2Colors.warn),
          number(minutes.holidayOvertime, AccountsV2Colors.vio),
          const SizedBox(width: 12),
          if (widget.onPickBuilding != null)
            SizedBox(
              width: 170,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AttendanceBuildingChip(
                  key: ValueKey('attendance-grid-building-${row.worker.id}'),
                  label: attendanceRowBuilding(row, day.crew, language),
                  language: language,
                  onTap: widget.onPickBuilding,
                ),
              ),
            )
          else
            SizedBox(
              width: 170,
              child: Focus(
                onFocusChange: (focused) {
                  if (!focused) _commitProject();
                },
                child: TextField(
                  controller: _project,
                  enabled: present,
                  style: v2Style(12.5),
                  onSubmitted: (_) => _commitProject(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: AS.t(AS.editCrew, language),
            onPressed: widget.onOpenEditor,
            icon: const Icon(Icons.edit_outlined, size: 18),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          if (widget.onRemove != null)
            IconButton(
              tooltip: AS.t(AS.remove, language),
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
        ],
      ),
    );
  }
}
