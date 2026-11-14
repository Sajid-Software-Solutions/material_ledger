/// Workforce attendance V2 — Crews: create a crew for a project (or the
/// workshop), set its usual shift and whether its month needs confirmation,
/// and choose its workers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';
import 'attendance_dialogs.dart';
import 'attendance_inputs.dart';

class AttendanceCrewsScreen extends ConsumerWidget {
  const AttendanceCrewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
    final crewsAsync = ref.watch(yorksAttendanceCrewsProvider);
    return crewsAsync.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(yorksAttendanceCrewsProvider),
      ),
      data: (crews) => AttendancePage(
        language: language,
        title: AS.t(AS.crews, language),
        onRefresh: () async => ref.invalidate(yorksAttendanceCrewsProvider),
        actions: [
          // Engineers, Workshop In-Charge, Admin and PR keep sheets
          // (PRODUCT_DECISIONS section 46); the server rechecks.
          if (ref.watch(yorksAttendanceCanCreateCrewProvider).valueOrNull ??
              false)
            AccountsV2Button(
              key: const ValueKey('attendance-new-crew'),
              label: AS.t(AS.newCrew, language),
              icon: 'plus',
              kind: AccountsV2ButtonKind.primary,
              onPressed: () => _openEditor(context, ref, null, language),
            ),
        ],
        children: [
          if (crews.isEmpty)
            AccountsV2Panel(
              child: AccountsV2Empty(
                icon: 'users',
                title: AS.t(AS.crews, language),
                body: AS.t(AS.noCrews, language),
              ),
            )
          else
            AccountsV2Panel(
              child: AccountsV2Table(
                phoneCards: true,
                columns: [
                  AccountsV2Column(AS.t(AS.colCrew, language), flex: 3),
                  AccountsV2Column(AS.t(AS.usualShift, language), width: 170),
                  AccountsV2Column(
                    AS.t(AS.members, language),
                    width: 90,
                    numeric: true,
                  ),
                  AccountsV2Column(AS.t(AS.colMonth, language), width: 200),
                ],
                rows: [
                  for (final crew in crews)
                    AccountsV2Row(
                      key: ValueKey('attendance-crew-row-${crew.id}'),
                      onTap: crew.access.take || crew.access.manage
                          ? () => _openEditor(context, ref, crew, language)
                          : null,
                      [
                        AccountsV2CellStack(
                          primary: crew.name,
                          secondary: crew.workLabel,
                        ),
                        Text(
                          '${formatAttendanceTime(crew.shiftStart)} – ${formatAttendanceTime(crew.shiftFinish)}',
                          style: v2Style(13),
                        ),
                        Text('${crew.memberCount}', style: v2Style(13)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AccountsV2Chip(
                            crew.needsConfirmation
                                ? AS.t(AS.needsConfirmation, language)
                                : AS.t(AS.monthNotNeeded, language),
                            tone: crew.needsConfirmation
                                ? AccountsV2ChipTone.pri
                                : AccountsV2ChipTone.ok,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          AttendanceHolidaysCard(language: language),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    AttendanceCrew? crew,
    AppLanguage language,
  ) async {
    final saved = await showAccountsV2Drawer<bool>(
      context,
      title: Text(
        crew == null ? AS.t(AS.newCrew, language) : AS.t(AS.editCrew, language),
      ),
      closeLabel: AS.t(AS.cancel, language),
      builder: (context) => _CrewEditor(crew: crew, language: language),
    );
    if (saved == true) ref.invalidate(yorksAttendanceCrewsProvider);
  }
}

class _CrewEditor extends ConsumerStatefulWidget {
  const _CrewEditor({required this.crew, required this.language});

  final AttendanceCrew? crew;
  final AppLanguage language;

  @override
  ConsumerState<_CrewEditor> createState() => _CrewEditorState();
}

class _CrewEditorState extends ConsumerState<_CrewEditor> {
  late final _name = TextEditingController(text: widget.crew?.name ?? '');
  late final _label = TextEditingController(
    text: widget.crew?.kind == 'workshop' ? widget.crew?.workLabel ?? '' : '',
  );
  late final _start = TextEditingController(
    text: formatAttendanceTimeInput(widget.crew?.shiftStart ?? 390),
  );
  late final _finish = TextEditingController(
    text: formatAttendanceTimeInput(widget.crew?.shiftFinish ?? 1020),
  );
  late final _breakStart = TextEditingController(
    text: formatAttendanceTimeInput(
      widget.crew == null ? 750 : widget.crew!.breakStart,
    ),
  );
  late final _breakFinish = TextEditingController(
    text: formatAttendanceTimeInput(
      widget.crew == null ? 780 : widget.crew!.breakFinish,
    ),
  );
  late String _kind = widget.crew?.kind ?? 'project';
  late String? _projectId = widget.crew?.projectId;
  late bool _needsConfirmation = widget.crew?.needsConfirmation ?? true;
  final _added = <AttendanceWorker>[];
  final _removed = <String>{};
  bool _saving = false;
  String? _error;

  AppLanguage get _language => widget.language;

  @override
  void dispose() {
    for (final c in [
      _name,
      _label,
      _start,
      _finish,
      _breakStart,
      _breakFinish,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final start = parseAttendanceTime(_start.text);
    final finish = parseAttendanceTime(_finish.text, after: start.minutes);
    final breakStart = parseAttendanceTime(
      _breakStart.text,
      after: start.minutes,
    );
    final breakFinish = parseAttendanceTime(
      _breakFinish.text,
      after: breakStart.minutes,
    );
    final repository = ref.read(yorksAttendanceRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var crew = widget.crew;
      final editable = crew == null || crew.access.manage;
      if (editable) {
        crew = await repository.saveCrew(
          payload: {
            'crew_id': crew?.id,
            'name': _name.text.trim(),
            'kind': _kind,
            'project_id': _kind == 'project' ? _projectId : null,
            'work_label': _label.text.trim().isEmpty
                ? null
                : _label.text.trim(),
            'needs_confirmation': _kind == 'project' && _needsConfirmation,
            'shift_start_minute': start.minutes,
            'shift_finish_minute': finish.minutes,
            'break_start_minute': breakStart.minutes,
            'break_finish_minute': breakFinish.minutes,
            'is_active': true,
          },
          expectedVersion: widget.crew?.recordVersion ?? 0,
          idempotencyKey: YorksAttendanceRepository.newKey(),
        );
      }
      if (_added.isNotEmpty || _removed.isNotEmpty) {
        await repository.setCrewMembers(
          crewId: crew.id,
          add: [for (final w in _added) w.id],
          remove: _removed.toList(),
          idempotencyKey: YorksAttendanceRepository.newKey(),
        );
      }
      if (!mounted) return;
      attendanceToast(context, AS.t(AS.crewSaved, _language));
      ref.invalidate(yorksAttendanceCrewsProvider);
      ref.invalidate(yorksAttendanceCrewDetailProvider(crew.id));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = attendanceErrorText(error, _language));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A labourer may work at several places a day, so adding them here keeps
  /// every other sheet they are on: there is nothing to confirm.
  Future<void> _pickWorkers(
    List<AttendanceWorker> workers,
    Set<String> memberIds,
  ) async {
    final picked = await showAttendanceWorkerPicker(
      context,
      language: _language,
      title: AS.t(AS.addWorkers, _language),
      workers: workers,
      exclude: memberIds,
    );
    if (picked == null || !mounted) return;
    setState(() {
      for (final worker in picked) {
        _removed.remove(worker.id);
        if (!_added.any((w) => w.id == worker.id)) _added.add(worker);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final crew = widget.crew;
    final canEditSettings = crew == null || crew.access.manage;
    final projects = ref.watch(yorksV1ProjectPortfolioProvider).valueOrNull;
    final detail = crew == null
        ? null
        : ref.watch(yorksAttendanceCrewDetailProvider(crew.id)).valueOrNull;
    final workers = ref.watch(yorksAttendanceWorkersProvider).valueOrNull;
    final members = [
      ...?detail?.members.where((m) => !_removed.contains(m.id)),
      ..._added,
    ];
    final memberIds = {for (final m in members) m.id};
    final valid =
        _name.text.trim().isNotEmpty &&
        (_kind == 'workshop' || _projectId != null) &&
        parseAttendanceTime(_start.text).minutes != null &&
        parseAttendanceTime(_finish.text).minutes != null;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final pad = phone ? 16.0 : 18.0;

    final settings = <Widget>[
      if (_error != null) ...[
        AccountsV2Note(tone: AccountsV2NoteTone.bad, child: Text(_error!)),
        const SizedBox(height: 10),
      ],
      AccountsV2TextField(
        key: const ValueKey('attendance-crew-name'),
        label: AS.t(AS.crewName, language),
        controller: _name,
        enabled: canEditSettings,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: v2Style(13, weight: FontWeight.w600),
          foregroundColor: AccountsV2Colors.ink2,
          selectedForegroundColor: AccountsV2Colors.pri,
          selectedBackgroundColor: AccountsV2Colors.pri50,
          side: const BorderSide(color: AccountsV2Colors.lineS),
        ),
        segments: [
          ButtonSegment(
            value: 'project',
            label: Text(AS.t(AS.crewKindProject, language)),
          ),
          ButtonSegment(
            value: 'workshop',
            label: Text(AS.t(AS.crewKindWorkshop, language)),
          ),
        ],
        selected: {_kind},
        onSelectionChanged: canEditSettings
            ? (value) => setState(() {
                _kind = value.first;
                if (_kind == 'workshop') _needsConfirmation = false;
              })
            : null,
      ),
      const SizedBox(height: 12),
      if (_kind == 'project')
        AccountsV2Select<String?>(
          key: const ValueKey('attendance-crew-project'),
          label: AS.t(AS.projectLabel, language),
          value: _projectId,
          options: [
            (null, '—'),
            for (final item in projects ?? const [])
              (
                item.project.id,
                '${item.project.reference} · ${item.project.name}',
              ),
          ],
          onChanged: canEditSettings
              ? (id) => setState(() => _projectId = id)
              : null,
        )
      else
        AccountsV2TextField(
          label: AS.t(AS.workLabel, language),
          controller: _label,
          enabled: canEditSettings,
        ),
      const SizedBox(height: 16),
      Text(
        AS.t(AS.usualShift, language),
        style: v2Style(12.5, weight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final (i, (label, controller, key)) in [
            (AS.colIn, _start, 'attendance-crew-in'),
            (AS.colBreak, _breakStart, 'attendance-crew-break'),
            (AS.colBack, _breakFinish, 'attendance-crew-back'),
            (AS.colOut, _finish, 'attendance-crew-out'),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AttendanceTimeField(
                key: ValueKey(key),
                label: label.active(language),
                controller: controller,
                enabled: canEditSettings,
                last: i == 3,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ],
      ),
      if (_kind == 'project') ...[
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AS.t(AS.needsConfirmation, language), style: v2Style(13)),
          value: _needsConfirmation,
          activeThumbColor: Colors.white,
          activeTrackColor: AccountsV2Colors.pri,
          onChanged: canEditSettings
              ? (value) => setState(() => _needsConfirmation = value)
              : null,
        ),
      ] else
        const SizedBox(height: 12),
      const Divider(height: 1, color: AccountsV2Colors.line),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              '${AS.t(AS.members, language)} · ${members.length}',
              style: v2Style(14, weight: FontWeight.w700),
            ),
          ),
          AccountsV2Button(
            key: const ValueKey('attendance-crew-add-worker'),
            label: AS.t(AS.addWorkers, language),
            icon: 'plus',
            size: AccountsV2ButtonSize.small,
            onPressed: workers == null
                ? null
                : () => _pickWorkers(workers, memberIds),
          ),
        ],
      ),
      const SizedBox(height: 4),
    ];

    // One scroll for the settings and the members, with Save pinned below
    // and lifted above the keyboard, so nothing is squeezed or hidden.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              key: const ValueKey('attendance-crew-editor-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 12),
              children: [
                ...settings,
                for (final member in members)
                  ListTile(
                    key: ValueKey('attendance-crew-member-${member.id}'),
                    dense: true,
                    minTileHeight: 52,
                    contentPadding: EdgeInsets.zero,
                    leading: AttendanceAvatar(
                      initials: member.initials,
                      size: 32,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            style: v2Style(13.5, weight: FontWeight.w600),
                          ),
                        ),
                        if (crew != null) ...[
                          const SizedBox(width: 6),
                          CrewDocumentBadge(
                            crewId: crew.id,
                            workerId: member.id,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${member.number} · ${member.designation}',
                      style: v2Style(12, color: AccountsV2Colors.mut),
                    ),
                    trailing: IconButton(
                      key: ValueKey('attendance-crew-remove-${member.id}'),
                      tooltip: AS.t(AS.remove, language),
                      icon: const Icon(Icons.close_rounded),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: () => setState(() {
                        _added.removeWhere((w) => w.id == member.id);
                        if (detail?.members.any((m) => m.id == member.id) ??
                            false) {
                          _removed.add(member.id);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AccountsV2Colors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 10, pad, 12),
                child: AccountsV2Button(
                  key: const ValueKey('attendance-crew-save'),
                  block: true,
                  kind: AccountsV2ButtonKind.primary,
                  size: AccountsV2ButtonSize.large,
                  label: AS.t(AS.save, language),
                  icon: _saving ? 'clock' : 'check',
                  onPressed: valid && !_saving ? _save : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Public holidays for this year. Everyone sees them; Admin and PR add and
/// remove them. A holiday inside a confirmed month is refused by the server.
/// Public holidays for the year: shown on Crews and in Configuration ›
/// Workforce. Admin and PR add and remove them.
class AttendanceHolidaysCard extends ConsumerWidget {
  const AttendanceHolidaysCard({
    super.key,
    required this.language,
    this.onChanged,
  });

  final AppLanguage language;

  /// After a holiday is added or removed (Configuration refreshes its
  /// checklist).
  final VoidCallback? onChanged;

  Future<void> _add(BuildContext context, WidgetRef ref, int year) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(year - 1),
      lastDate: DateTime(year + 1, 12, 31),
      helpText: AS.t(AS.holidayDate, language),
    );
    if (picked == null || !context.mounted) return;
    final date = attendanceIso(picked);
    final name = await showAttendanceCommandDialog(
      context,
      language: language,
      title: AS.t(AS.addHoliday, language),
      summary: attendanceFullDate(date),
      fieldLabel: AS.t(AS.holidayName, language),
      confirmLabel: AS.t(AS.save, language),
      command: (text) async {
        try {
          await ref
              .read(yorksAttendanceRepositoryProvider)
              .saveHoliday(date: date, name: text);
          return null;
        } catch (error) {
          return error;
        }
      },
    );
    if (name != null) {
      ref.invalidate(yorksAttendanceHolidaysProvider(year));
      onChanged?.call();
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    int year,
    ({String date, String name}) holiday,
  ) async {
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: AS.t(AS.remove, language),
      body: AS.t(AS.holidayRemoveQuestion, language, {
        'name': holiday.name,
        'date': attendanceFullDate(holiday.date),
      }),
      confirmLabel: AS.t(AS.remove, language),
      destructive: true,
      command: (_) async {
        try {
          await ref
              .read(yorksAttendanceRepositoryProvider)
              .saveHoliday(date: holiday.date, remove: true);
          return null;
        } catch (error) {
          return error;
        }
      },
    );
    if (done != null) {
      ref.invalidate(yorksAttendanceHolidaysProvider(year));
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final async = ref.watch(yorksAttendanceHolidaysProvider(year));
    final data = async.valueOrNull;
    return AccountsV2Panel(
      key: const ValueKey('attendance-holidays-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: '${AS.t(AS.holidays, language)} · $year',
            icon: 'clock',
            subtitle: AS.t(AS.holidaysSub, language),
            actions: [
              if (data?.canManage ?? false)
                AccountsV2Button(
                  key: const ValueKey('attendance-add-holiday'),
                  label: AS.t(AS.addHoliday, language),
                  icon: 'plus',
                  size: AccountsV2ButtonSize.small,
                  onPressed: () => _add(context, ref, year),
                ),
            ],
          ),
          if (async.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text(
                attendanceErrorText(async.error, language),
                style: v2Style(13, color: AccountsV2Colors.bad),
              ),
            )
          else if (data == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (data.holidays.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text(
                AS.t(AS.noHolidays, language),
                style: v2Style(13, color: AccountsV2Colors.mut),
              ),
            )
          else
            for (final holiday in data.holidays)
              Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AccountsV2Colors.line2),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(
                        attendanceLongDate(holiday.date),
                        style: v2Style(13, weight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text(holiday.name, style: v2Style(13))),
                    if (data.canManage)
                      IconButton(
                        tooltip: AS.t(AS.remove, language),
                        onPressed: () => _remove(context, ref, year, holiday),
                        icon: const Icon(Icons.delete_outline_rounded),
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
