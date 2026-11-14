/// Workforce attendance V2 — Take attendance.
///
/// Phone first: a day strip, one card per worker with P / A / Off / ··· pills,
/// a bottom-sheet editor with smart time entry and a Save bar always in reach.
/// Desktop and tablet get the same day as a keyboard-friendly grid.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../accounts/presentation/v2/accounts_v2_safety.dart'
    show AccountsV2AlertDialog;
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';
import 'attendance_dialogs.dart';
import 'attendance_inputs.dart';
import 'attendance_row_editor.dart';

class AttendanceTakeScreen extends ConsumerStatefulWidget {
  const AttendanceTakeScreen({super.key, this.initialCrewId, this.initialDate});

  final String? initialCrewId;
  final String? initialDate;

  @override
  ConsumerState<AttendanceTakeScreen> createState() =>
      _AttendanceTakeScreenState();
}

class _AttendanceTakeScreenState extends ConsumerState<AttendanceTakeScreen> {
  String? _crewId;
  String? _date;

  @override
  void initState() {
    super.initState();
    _crewId = widget.initialCrewId;
    _date = widget.initialDate;
  }

  @override
  void didUpdateWidget(AttendanceTakeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCrewId != oldWidget.initialCrewId &&
        widget.initialCrewId != null) {
      _crewId = widget.initialCrewId;
    }
    if (widget.initialDate != oldWidget.initialDate &&
        widget.initialDate != null) {
      _date = widget.initialDate;
    }
  }

  void _open(String crewId, String date) {
    setState(() {
      _crewId = crewId;
      _date = date;
    });
    context.go(
      Uri(
        path: RoutePaths.yorksV1WorkforceAttendance,
        queryParameters: {'crew': crewId, 'date': date},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = attendanceLanguage(ref);
    final crewsAsync = ref.watch(yorksAttendanceCrewsProvider);
    return crewsAsync.when(
      loading: () => AttendanceLoadState(language: language),
      error: (error, _) => AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () => ref.invalidate(yorksAttendanceCrewsProvider),
      ),
      data: (crews) {
        final visible = [
          for (final crew in crews)
            if (crew.access.take || crew.access.confirm || crew.access.view)
              crew,
        ];
        if (visible.isEmpty) {
          return AttendancePage(
            language: language,
            title: AS.t(AS.takeAttendance, language),
            children: [
              AccountsV2Panel(
                child: AccountsV2Empty(
                  icon: 'users',
                  title: AS.t(AS.crews, language),
                  body: AS.t(AS.noCrews, language),
                ),
              ),
            ],
          );
        }
        final crew =
            visible.where((c) => c.id == _crewId).firstOrNull ??
            visible.where((c) => c.access.take).firstOrNull ??
            visible.first;
        final date = _date ?? attendanceLocalToday();
        return _DayView(
          key: ValueKey('${crew.id}|$date'),
          crews: visible,
          crew: crew,
          date: date,
          language: language,
          onOpen: _open,
        );
      },
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({
    super.key,
    required this.crews,
    required this.crew,
    required this.date,
    required this.language,
    required this.onOpen,
  });

  final List<AttendanceCrew> crews;
  final AttendanceCrew crew;
  final String date;
  final AppLanguage language;
  final void Function(String crewId, String date) onOpen;

  AttendanceDayKey get _key => (crewId: crew.id, date: date);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksAttendanceDayControllerProvider(_key));
    final controller = ref.read(
      yorksAttendanceDayControllerProvider(_key).notifier,
    );
    final day = state.day;
    if (day == null) {
      return AttendanceLoadState(
        language: language,
        error: state.loading ? null : state.error,
        onRetry: controller.load,
      );
    }

    final intro = crew.access.take
        ? (crew.isWorkshop || !crew.needsConfirmation
              ? AS.takeIntroWorkshop
              : AS.takeIntro)
        : AS.takeIntroViewer;

    return AttendancePage(
      language: language,
      title: AS.t(AS.takeAttendance, language),
      subtitle: AS.t(intro, language),
      subtitleOnPhone: false,
      onRefresh: state.dirty ? null : controller.load,
      children: [
        ...AttendanceConfirmationsBanner.forPage(
          ref,
          onConfirm: (month) => context.go(
            Uri(
              path: RoutePaths.yorksV1WorkforceConfirm,
              queryParameters: {'month': month},
            ).toString(),
          ),
        ),
        _DayHeader(
          crews: crews,
          day: day,
          language: language,
          onOpen: onOpen,
          dirty: state.hasLocalChanges && day.editable,
          drafts: {
            ...attendanceDraftDates(
              ref.read(sharedPreferencesProvider),
              actorId: ref.read(yorksV1AuthUserIdProvider) ?? 'anonymous',
              crewId: crew.id,
            ),
            if (state.hasLocalChanges && day.editable) day.date,
          },
        ),
        ..._banners(context, ref, state, controller),
        if (day.editable)
          _Toolbar(
            day: day,
            state: state,
            controller: controller,
            language: language,
          ),
        _WorkerList(state: state, controller: controller, language: language),
        _Footer(state: state, controller: controller, language: language),
      ],
    );
  }

  List<Widget> _banners(
    BuildContext context,
    WidgetRef ref,
    AttendanceDayEditState state,
    AttendanceDayController controller,
  ) {
    final day = state.day!;
    final banners = <Widget>[];
    if (state.error != null) {
      banners.add(
        AccountsV2Note(
          tone: AccountsV2NoteTone.bad,
          trailing: state.error?.code.name == 'conflict'
              ? Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AccountsV2Button(
                      key: const ValueKey('attendance-keep-mine'),
                      label: AS.t(AS.keepMine, language),
                      size: AccountsV2ButtonSize.small,
                      kind: AccountsV2ButtonKind.primary,
                      onPressed: () async {
                        await controller.reloadKeepingMine();
                        if (context.mounted) {
                          attendanceToast(context, AS.t(AS.keptMine, language));
                        }
                      },
                    ),
                    AccountsV2Button(
                      key: const ValueKey('attendance-use-theirs'),
                      label: AS.t(AS.useTheirs, language),
                      size: AccountsV2ButtonSize.small,
                      onPressed: controller.useTheirs,
                    ),
                  ],
                )
              : null,
          child: Text(attendanceErrorText(state.error, language)),
        ),
      );
    }
    if (day.holiday) {
      banners.add(
        AccountsV2Note(
          tone: AccountsV2NoteTone.info,
          child: Text(
            day.holidayName != null
                ? AS.t(AS.holidayBanner, language, {'name': day.holidayName})
                : AS.t(AS.restBanner, language, {
                    'day': attendanceLongDate(day.date),
                  }),
          ),
        ),
      );
    }
    if (day.editable && !day.saved && day.date.compareTo(day.today) < 0) {
      banners.add(
        AccountsV2Note(
          tone: AccountsV2NoteTone.warn,
          child: Text(
            AS.t(AS.earlierBanner, language, {
              'today': attendanceShortDate(day.today),
            }),
          ),
        ),
      );
    }
    final question = day.question;
    if (question != null) {
      banners.add(
        _QuestionBanner(
          question: question,
          canAnswer: question.isOpen && day.access.take && !day.access.confirm,
          language: language,
          onAnswer: (text) async {
            final ok = await controller.answer(text);
            if (ok && context.mounted) {
              attendanceToast(context, AS.t(AS.sentToast, language));
            }
          },
        ),
      );
    }
    if (day.changes.isNotEmpty) {
      banners.add(
        AccountsV2Note(
          tone: AccountsV2NoteTone.info,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in day.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${AS.t(AS.changeLine, language, {'by': change.by, 'worker': change.workerName, 'what': _changeWhat(change), 'why': change.reason})} · ${attendanceStamp(change.at)}',
                    style: v2Style(12.5),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (day.locked) {
      banners.add(
        AccountsV2Note(
          tone: AccountsV2NoteTone.ok,
          child: Text(
            AS.t(AS.lockedBanner, language, {
              'month': attendanceMonthName(day.date),
              'name': day.month.confirmedBy ?? '',
            }),
          ),
        ),
      );
    }
    return banners;
  }

  String _changeWhat(AttendanceChange change) {
    String describe(Map<String, dynamic>? data) {
      if (data == null) return AS.t(AS.removedFromDay, language);
      final status = AttendanceStatus.fromCode(data['status']);
      if (status == AttendanceStatus.present) {
        return '${formatAttendanceTime(data['start_minute'] as int?)}–${formatAttendanceTime(data['finish_minute'] as int?)}';
      }
      return attendanceStatusLabel(status).active(language);
    }

    return '${describe(change.before)} → ${describe(change.after)}';
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.crews,
    required this.day,
    required this.language,
    required this.onOpen,
    this.drafts = const {},
    this.dirty = false,
  });

  final List<AttendanceCrew> crews;
  final AttendanceDay day;
  final Set<String> drafts;
  final bool dirty;
  final AppLanguage language;
  final void Function(String crewId, String date) onOpen;

  @override
  Widget build(BuildContext context) {
    final missing = [
      for (final d in day.month.missingDays)
        if (d != day.date) d,
    ];
    final dayState =
        day.month.days.where((d) => d.date == day.date).firstOrNull?.state ??
        AttendanceDayState.none;
    final phone = AccountsV2Breakpoints.isPhone(context);
    return AccountsV2Panel(
      child: Padding(
        padding: EdgeInsets.all(phone ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceDayStrip(
              days: day.month.days,
              selected: day.date,
              drafts: drafts,
              onSelect: (date) => onOpen(day.crew.id, date),
            ),
            if (drafts.any((d) => d != day.date)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    AS.t(AS.unsavedDays, language),
                    style: v2Style(12.5, weight: FontWeight.w600),
                  ),
                  for (final date in (drafts.toList()..sort()))
                    if (date != day.date)
                      ActionChip(
                        key: ValueKey('attendance-draft-$date'),
                        label: Text(attendanceShortDate(date)),
                        labelStyle: v2Style(
                          12,
                          weight: FontWeight.w600,
                          color: AccountsV2Colors.warn,
                        ),
                        backgroundColor: AccountsV2Colors.warn50,
                        side: BorderSide.none,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onPressed: () => onOpen(day.crew.id, date),
                      ),
                ],
              ),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    AS.t(AS.notEnteredYet, language),
                    style: v2Style(12.5, weight: FontWeight.w600),
                  ),
                  for (final date in missing.take(6))
                    ActionChip(
                      key: ValueKey('attendance-missing-$date'),
                      label: Text(attendanceShortDate(date)),
                      labelStyle: v2Style(
                        12,
                        weight: FontWeight.w600,
                        color: AccountsV2Colors.bad,
                      ),
                      backgroundColor: AccountsV2Colors.bad50,
                      side: BorderSide.none,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onPressed: () => onOpen(day.crew.id, date),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (crews.length > 1)
                        _CrewPicker(
                          crews: crews,
                          crew: day.crew,
                          language: language,
                          onPick: (crew) => onOpen(crew.id, day.date),
                        )
                      else
                        Text(
                          day.crew.name,
                          style: v2Style(13, weight: FontWeight.w600),
                        ),
                      Text(
                        day.crew.workLabel,
                        style: v2Style(12, color: AccountsV2Colors.mut),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attendanceLongDate(day.date),
                        style: v2Style(
                          phone ? 18 : 20,
                          weight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                dirty
                    ? AccountsV2Chip(
                        AS.t(AS.unsavedDay, language),
                        tone: AccountsV2ChipTone.warn,
                      )
                    : AccountsV2Chip(
                        attendanceDayStateLabel(dayState).active(language),
                        tone: attendanceDayStateTone(dayState),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CrewPicker extends StatelessWidget {
  const _CrewPicker({
    required this.crews,
    required this.crew,
    required this.language,
    required this.onPick,
  });

  final List<AttendanceCrew> crews;
  final AttendanceCrew crew;
  final AppLanguage language;
  final ValueChanged<AttendanceCrew> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AttendanceCrew>(
      key: const ValueKey('attendance-crew-picker'),
      tooltip: AS.t(AS.chooseCrew, language),
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final item in crews)
          PopupMenuItem(
            value: item,
            child: Text(item.name, style: v2Style(13)),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                crew.name,
                overflow: TextOverflow.ellipsis,
                style: v2Style(
                  14,
                  weight: FontWeight.w700,
                  color: AccountsV2Colors.pri,
                ),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: AccountsV2Colors.pri,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionBanner extends StatefulWidget {
  const _QuestionBanner({
    required this.question,
    required this.canAnswer,
    required this.language,
    required this.onAnswer,
  });

  final AttendanceQuestion question;
  final bool canAnswer;
  final AppLanguage language;
  final Future<void> Function(String text) onAnswer;

  @override
  State<_QuestionBanner> createState() => _QuestionBannerState();
}

class _QuestionBannerState extends State<_QuestionBanner> {
  final _answer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final language = widget.language;
    return AccountsV2Note(
      tone: q.isOpen ? AccountsV2NoteTone.warn : AccountsV2NoteTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${AS.t(AS.askedBanner, language, {'by': q.askedBy})} ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '“${q.question}”'),
              ],
            ),
          ),
          if (q.answer != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${AS.t(AS.answeredBy, language, {'by': q.answeredBy})} ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '“${q.answer}”'),
                ],
              ),
            ),
          ],
          if (widget.canAnswer) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AccountsV2TextField(
                    key: const ValueKey('attendance-answer-field'),
                    label: AS.t(AS.yourAnswer, language),
                    controller: _answer,
                  ),
                ),
                const SizedBox(width: 8),
                AccountsV2Button(
                  key: const ValueKey('attendance-answer-send'),
                  label: AS.t(AS.sendAnswer, language),
                  kind: AccountsV2ButtonKind.primary,
                  onPressed: _sending
                      ? null
                      : () async {
                          final text = _answer.text.trim();
                          if (text.isEmpty) return;
                          setState(() => _sending = true);
                          await widget.onAnswer(text);
                          if (mounted) setState(() => _sending = false);
                        },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.day,
    required this.state,
    required this.controller,
    required this.language,
  });

  final AttendanceDay day;
  final AttendanceDayEditState state;
  final AttendanceDayController controller;
  final AppLanguage language;

  Future<void> _editShift(BuildContext context) async {
    final crew = day.crew;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => _ShiftDialog(
        start: crew.shiftStart,
        finish: crew.shiftFinish,
        language: language,
      ),
    );
    if (result == null || !context.mounted) return;
    final before = controller.current.rows;
    controller.applyShift(result.$1, result.$2);
    showAttendanceUndo(
      context,
      language: language,
      message: AS.t(AS.shiftToast, language, {
        'start': formatAttendanceTime(result.$1),
        'finish': formatAttendanceTime(result.$2),
      }),
      onUndo: () => controller.restoreRows(before),
    );
  }

  void _added(BuildContext context, List<AttendanceWorker> workers) {
    if (workers.isEmpty) return;
    for (final worker in workers) {
      controller.addWorkerForDay(worker);
    }
    attendanceToast(
      context,
      AS.t(AS.addedForDay, language, {
        'name': workers.map((w) => w.name).join(', '),
        'date': attendanceShortDate(day.date),
      }),
    );
  }

  Future<void> _copy(BuildContext context, String previous) async {
    final before = controller.current.rows;
    final ok = await controller.copyFrom(previous);
    if (ok && context.mounted) {
      showAttendanceUndo(
        context,
        language: language,
        message: AS.t(AS.copiedToast, language, {
          'date': attendanceShortDate(previous),
        }),
        onUndo: () => controller.restoreRows(before),
      );
    }
  }

  void _everyone(BuildContext context) {
    final before = controller.current.rows;
    controller.everyonePresent();
    showAttendanceUndo(
      context,
      language: language,
      message: AS.t(AS.undoEveryone, language),
      onUndo: () => controller.restoreRows(before),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previous = day.previousSameTypeDate;
    final workers = ref.watch(yorksAttendanceWorkersProvider);
    final phone = AccountsV2Breakpoints.isPhone(context);
    final exclude = {for (final row in state.rows) row.worker.id};
    if (phone) {
      // Phones: every action in sight as equal tiles; Add workers opens the
      // picker sheet so the keyboard never hides the matches.
      return AccountsV2Panel(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AttendanceActionTiles(
            tiles: [
              if (!day.holiday)
                AttendanceActionTile(
                  key: const ValueKey('attendance-everyone-present'),
                  icon: 'check',
                  label: AS.t(AS.everyonePresent, language),
                  onPressed: state.unmarkedCount == 0
                      ? null
                      : () => _everyone(context),
                ),
              if (previous != null)
                AttendanceActionTile(
                  key: const ValueKey('attendance-copy-previous'),
                  icon: 'copy',
                  label: AS.t(AS.copyDay, language, {
                    'date': attendanceShortDate(previous),
                  }),
                  onPressed: () => _copy(context, previous),
                ),
              AttendanceActionTile(
                key: const ValueKey('attendance-shift'),
                icon: 'clock',
                label:
                    '${formatAttendanceTime(day.crew.shiftStart)} – ${formatAttendanceTime(day.crew.shiftFinish)}',
                semanticLabel: AS.t(AS.shiftButton, language, {
                  'start': formatAttendanceTime(day.crew.shiftStart),
                  'finish': formatAttendanceTime(day.crew.shiftFinish),
                }),
                onPressed: () => _editShift(context),
              ),
              AttendanceActionTile(
                key: const ValueKey('attendance-add-worker-open'),
                icon: 'plus',
                label: AS.t(AS.addWorkers, language),
                onPressed: workers.valueOrNull == null
                    ? null
                    : () async {
                        final picked = await showAttendanceWorkerPicker(
                          context,
                          language: language,
                          title: AS.t(AS.addWorkers, language),
                          workers: workers.valueOrNull ?? const [],
                          exclude: exclude,
                        );
                        if (picked != null && context.mounted) {
                          _added(context, picked);
                        }
                      },
              ),
            ],
          ),
        ),
      );
    }
    final buttons = <Widget>[
      if (previous != null)
        AccountsV2Button(
          key: const ValueKey('attendance-copy-previous'),
          label: AS.t(AS.copyDay, language, {
            'date': attendanceShortDate(previous),
          }),
          icon: 'copy',
          onPressed: () => _copy(context, previous),
        ),
      if (!day.holiday)
        AccountsV2Button(
          key: const ValueKey('attendance-everyone-present'),
          label: AS.t(AS.everyonePresent, language),
          icon: 'check',
          onPressed: state.unmarkedCount == 0 ? null : () => _everyone(context),
        ),
      AccountsV2Button(
        key: const ValueKey('attendance-shift'),
        label: AS.t(AS.shiftButton, language, {
          'start': formatAttendanceTime(day.crew.shiftStart),
          'finish': formatAttendanceTime(day.crew.shiftFinish),
        }),
        icon: 'clock',
        onPressed: () => _editShift(context),
      ),
    ];
    final addWorker = _AddWorkerField(
      language: language,
      workers: workers.valueOrNull ?? const [],
      exclude: exclude,
      onAdd: (worker) => _added(context, [worker]),
    );
    return AccountsV2Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...buttons,
            SizedBox(width: 320, child: addWorker),
          ],
        ),
      ),
    );
  }
}

class _AddWorkerField extends StatefulWidget {
  const _AddWorkerField({
    required this.language,
    required this.workers,
    required this.exclude,
    required this.onAdd,
  });

  final AppLanguage language;
  final List<AttendanceWorker> workers;
  final Set<String> exclude;
  final ValueChanged<AttendanceWorker> onAdd;

  @override
  State<_AddWorkerField> createState() => _AddWorkerFieldState();
}

class _AddWorkerFieldState extends State<_AddWorkerField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<AttendanceSearchHit<AttendanceWorker>> get _hits =>
      attendanceFuzzySearch(
        _controller.text,
        widget.workers.where((w) => !widget.exclude.contains(w.id)),
        (w) => '${w.name} ${w.number}',
      );

  void _pick(AttendanceWorker worker) {
    widget.onAdd(worker);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final hits = _hits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (hits.isNotEmpty) _pick(hits.first.item);
            },
          },
          child: AccountsV2TextField(
            key: const ValueKey('attendance-add-worker'),
            label: AS.t(AS.addWorkerHint, language),
            controller: _controller,
            search: true,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_controller.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AccountsV2Colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      AS.t(AS.noMatchWorker, language),
                      style: v2Style(12.5, color: AccountsV2Colors.mut),
                    ),
                  )
                else ...[
                  if (hits.first.isCorrection)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text(
                        AS.t(AS.didYouMean, language, {
                          'name': hits.first.item.name,
                        }),
                        style: v2Style(12, color: AccountsV2Colors.warn),
                      ),
                    ),
                  for (final hit in hits)
                    InkWell(
                      onTap: () => _pick(hit.item),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hit.item.name,
                              style: v2Style(13, weight: FontWeight.w600),
                            ),
                            Text(
                              '${hit.item.number} · ${hit.item.designation} · ${hit.item.crewName ?? AS.t(AS.labourPool, language)}',
                              style: v2Style(12, color: AccountsV2Colors.mut),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog({
    required this.start,
    required this.finish,
    required this.language,
  });

  final int start;
  final int finish;
  final AppLanguage language;

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  late final _start = TextEditingController(
    text: formatAttendanceTimeInput(widget.start),
  );
  late final _finish = TextEditingController(
    text: formatAttendanceTimeInput(widget.finish),
  );

  @override
  void dispose() {
    _start.dispose();
    _finish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final start = parseAttendanceTime(_start.text);
    final finish = parseAttendanceTime(_finish.text, after: start.minutes);
    final valid =
        start.minutes != null &&
        finish.minutes != null &&
        finish.minutes! > start.minutes!;
    return AccountsV2AlertDialog(
      title: Text(AS.t(AS.shiftTitle, language)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Row(
          children: [
            Expanded(
              child: AttendanceTimeField(
                key: const ValueKey('attendance-shift-in'),
                label: AS.t(AS.colIn, language),
                controller: _start,
                hint: formatAttendanceTime(start.minutes),
                error: !start.ok,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AttendanceTimeField(
                key: const ValueKey('attendance-shift-out'),
                label: AS.t(AS.colOut, language),
                controller: _finish,
                hint: formatAttendanceTime(finish.minutes),
                error: !finish.ok,
                last: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AS.t(AS.cancel, language)),
        ),
        FilledButton(
          onPressed: valid
              ? () =>
                    Navigator.of(context).pop((start.minutes!, finish.minutes!))
              : null,
          child: Text(AS.t(AS.done, language)),
        ),
      ],
    );
  }
}

class _WorkerList extends StatelessWidget {
  const _WorkerList({
    required this.state,
    required this.controller,
    required this.language,
  });

  final AttendanceDayEditState state;
  final AttendanceDayController controller;
  final AppLanguage language;

  Future<void> _edit(BuildContext context, int index) async {
    var current = index;
    while (current >= 0 && current < state.rows.length) {
      final day = controller.current.day!;
      final rows = controller.current.rows;
      final result = await showAttendanceRowEditor(
        context,
        row: rows[current],
        day: day,
        language: language,
        hasPrevious: current > 0,
        hasNext: current < rows.length - 1,
        presentOnShift: controller.presentOnShift,
      );
      if (result == null) return;
      controller.setRow(result.row.worker.id, result.row);
      current += switch (result.move) {
        AttendanceEditorMove.previous => -1,
        AttendanceEditorMove.next => 1,
        AttendanceEditorMove.close => rows.length,
      };
      if (!context.mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = state.day!;
    final phone = AccountsV2Breakpoints.isNarrow(context);
    if (!phone && day.editable) {
      return AttendanceGrid(
        state: state,
        controller: controller,
        language: language,
        onOpenEditor: (index) => _edit(context, index),
      );
    }
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < state.rows.length; i++)
            _WorkerCard(
              row: state.rows[i],
              day: day,
              language: language,
              editable: day.editable,
              onEdit: () => _edit(context, i),
              onStatus: (status) => status == null
                  ? _edit(context, i)
                  : controller.setStatus(state.rows[i].worker.id, status),
              onRemove: state.rows[i].isMember
                  ? null
                  : () {
                      final before = controller.current.rows;
                      final name = state.rows[i].worker.name;
                      controller.removeDayOnly(state.rows[i].worker.id);
                      showAttendanceUndo(
                        context,
                        language: language,
                        message: AS.t(AS.removedForDay, language, {
                          'name': name,
                        }),
                        onUndo: () => controller.restoreRows(before),
                      );
                    },
            ),
        ],
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.row,
    required this.day,
    required this.language,
    required this.editable,
    required this.onEdit,
    required this.onStatus,
    this.onRemove,
  });

  final AttendanceRow row;
  final AttendanceDay day;
  final AppLanguage language;
  final bool editable;
  final VoidCallback onEdit;

  /// Null opens the editor (··· or leave).
  final ValueChanged<AttendanceStatus?> onStatus;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final minutes = row.minutes(holiday: day.holiday);
    final summary = attendanceRowSummary(
      row,
      holiday: day.holiday,
      language: language,
    );
    final missing = row.needsMarking || minutes.timeMissing;
    final places = attendancePlaceLines(row, language);
    final phone = AccountsV2Breakpoints.isPhone(context);
    Widget pill(String label, AttendanceStatus? status, {String? key}) {
      final selected =
          status != null && row.status == status ||
          (status == null && (row.status?.isLeave ?? false));
      return SizedBox(
        width: _pillSize,
        height: _pillSize,
        child: Material(
          color: selected
              ? (status == AttendanceStatus.absent
                    ? AccountsV2Colors.bad
                    : status == AttendanceStatus.present
                    ? AccountsV2Colors.ok
                    : AccountsV2Colors.pri)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? Colors.transparent : AccountsV2Colors.lineS,
            ),
          ),
          child: Semantics(
            button: true,
            selected: selected,
            label: status == null
                ? AS.t(AS.moreStatuses, language, {'name': row.worker.name})
                : AS.t(AS.markAs, language, {
                    'name': row.worker.name,
                    'status': attendanceStatusLabel(status).active(language),
                  }),
            excludeSemantics: true,
            child: InkWell(
              key: key == null ? null : ValueKey(key),
              borderRadius: BorderRadius.circular(10),
              onTap: () => onStatus(status),
              child: Center(
                child: Text(
                  label,
                  style: v2Style(
                    13,
                    weight: FontWeight.w700,
                    color: selected ? Colors.white : AccountsV2Colors.ink2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final id = row.worker.id;
    final controls = editable
        ? <Widget>[
            if (day.holiday)
              pill(
                AS.t(AS.pillOff, language),
                AttendanceStatus.rest,
                key: 'attendance-pill-off-$id',
              ),
            pill(
              AS.t(AS.pillPresent, language),
              AttendanceStatus.present,
              key: 'attendance-pill-p-$id',
            ),
            pill(
              AS.t(AS.pillAbsent, language),
              AttendanceStatus.absent,
              key: 'attendance-pill-a-$id',
            ),
            pill(
              (row.status?.isLeave ?? false)
                  ? AS.t(AS.pillLeave, language)
                  : '···',
              null,
              key: 'attendance-pill-more-$id',
            ),
            if (onRemove != null)
              IconButton(
                tooltip: AS.t(AS.remove, language),
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 20),
                constraints: const BoxConstraints(
                  minWidth: _pillSize,
                  minHeight: _pillSize,
                ),
              ),
          ]
        : const <Widget>[];
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              row.worker.name,
              style: v2Style(13.5, weight: FontWeight.w700),
            ),
            CrewDocumentBadge(crewId: day.crew.id, workerId: row.worker.id),
            if (!row.isMember)
              AccountsV2Chip(
                row.worker.crewName == null
                    ? AS.t(AS.labourPool, language)
                    : AS.t(AS.fromCrew, language, {
                        'crew': row.worker.crewName,
                      }),
                tone: AccountsV2ChipTone.vio,
              ),
            if (row.changedAfterEntry)
              AccountsV2Chip(
                AS.t(AS.changedChip, language),
                tone: AccountsV2ChipTone.warn,
              ),
          ],
        ),
        Text(
          '${row.worker.number} · ${row.worker.designation}',
          style: v2Style(11.5, color: AccountsV2Colors.mut),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Recorded at another place and not marked here: no "Not
            // marked" warning; the place line below says where.
            if (row.isMarked || !row.busyElsewhere)
              Text(
                summary,
                style: v2Style(
                  12.5,
                  weight: FontWeight.w600,
                  color: missing ? AccountsV2Colors.bad : AccountsV2Colors.ink2,
                ),
              ),
            if (minutes.normalOvertime > 0)
              AccountsV2Chip(
                AS.t(AS.otHours, language, {
                  'h': formatAttendanceHours(minutes.normalOvertime),
                }),
                tone: AccountsV2ChipTone.warn,
              ),
            if (minutes.holidayOvertime > 0)
              AccountsV2Chip(
                AS.t(AS.holHours, language, {
                  'h': formatAttendanceHours(minutes.holidayOvertime),
                }),
                tone: AccountsV2ChipTone.vio,
              ),
          ],
        ),
        for (final line in places)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              key: ValueKey('attendance-place-${row.worker.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    line.bad
                        ? Icons.error_outline_rounded
                        : Icons.place_outlined,
                    size: 14,
                    color: line.bad
                        ? AccountsV2Colors.bad
                        : AccountsV2Colors.mut,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    line.text,
                    style: v2Style(
                      12,
                      weight: line.bad ? FontWeight.w600 : FontWeight.w500,
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
    );
    final avatarSize = phone ? 30.0 : 34.0;
    final avatarGap = phone ? 8.0 : 10.0;
    final controlsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0) const SizedBox(width: _pillGap),
          controls[i],
        ],
      ],
    );
    final status = !editable && row.isMarked
        ? AccountsV2Chip(
            attendanceStatusLabel(row.status).active(language),
            tone: row.status == AttendanceStatus.absent
                ? AccountsV2ChipTone.bad
                : row.status == AttendanceStatus.present
                ? AccountsV2ChipTone.ok
                : AccountsV2ChipTone.neutral,
          )
        : null;
    return Container(
      key: ValueKey('attendance-row-$id'),
      padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The pills sit beside the name while the name keeps a readable
          // width; otherwise (a holiday's extra Off, a worker added for the
          // day) they move under it.
          final controlsWidth = controls.isEmpty
              ? 0.0
              : controls.length * (_pillSize + _pillGap);
          final inline =
              controls.isEmpty ||
              constraints.maxWidth - avatarSize - avatarGap - controlsWidth >=
                  _minNameWidth;
          final head = Row(
            crossAxisAlignment: inline
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              AttendanceAvatar(initials: row.worker.initials, size: avatarSize),
              SizedBox(width: avatarGap),
              Expanded(
                child: InkWell(
                  key: ValueKey('attendance-row-open-$id'),
                  onTap: editable ? onEdit : null,
                  borderRadius: BorderRadius.circular(8),
                  child: details,
                ),
              ),
              if (inline && controls.isNotEmpty) ...[
                const SizedBox(width: _pillGap),
                controlsRow,
              ],
              ?status,
            ],
          );
          if (inline) return head;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: controlsRow,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Status pills are 44px tap targets; the name keeps at least this much
/// room beside them.
const double _pillSize = 44;
const double _pillGap = 4;
const double _minNameWidth = 112;

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.state,
    required this.controller,
    required this.language,
  });

  final AttendanceDayEditState state;
  final AttendanceDayController controller;
  final AppLanguage language;

  String get _summary {
    final parts = [
      AS.t(AS.footerSummary, language, {
        'p': state.presentCount,
        'a': state.absentCount,
        'l': state.leaveCount,
      }),
      if (state.unmarkedCount > 0)
        AS.t(AS.footerUnmarked, language, {'n': state.unmarkedCount}),
      if (state.timeMissingCount > 0)
        AS.t(AS.footerMissing, language, {'n': state.timeMissingCount}),
      if (state.conflictCount > 0)
        AS.t(AS.footerConflicts, language, {'n': state.conflictCount}),
      if (state.elsewhereCount > 0)
        AS.t(AS.footerElsewhere, language, {'n': state.elsewhereCount}),
      if (state.normalOvertime > 0)
        AS.t(AS.otHours, language, {
          'h': formatAttendanceHours(state.normalOvertime),
        }),
      if (state.holidayOvertime > 0)
        AS.t(AS.holHours, language, {
          'h': formatAttendanceHours(state.holidayOvertime),
        }),
    ];
    return parts.join(' · ');
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final day = state.day!;
    AttendanceDay? saved;
    if (day.changeNeedsReason) {
      // The dialog stays open while the server decides and shows a refusal
      // inside it, with the reason still typed.
      final reason = await showAttendanceCommandDialog(
        context,
        language: language,
        title: AS.t(AS.reasonTitle, language, {
          'date': attendanceShortDate(day.date),
        }),
        summary: _summary,
        body: AS.t(AS.reasonBody, language, {'by': day.enteredBy ?? ''}),
        fieldLabel: AS.t(AS.reasonLabel, language),
        confirmLabel: AS.t(AS.saveChanges, language),
        command: (text) async {
          saved = await controller.save(changeReason: text);
          return saved == null ? controller.current.error : null;
        },
      );
      if (reason == null) return;
    } else {
      saved = await controller.save();
    }
    final result = saved;
    if (result == null || !context.mounted) return;
    final savedDay = result;
    ref.invalidate(yorksAttendanceOverviewProvider(null));
    final next = savedDay.month.missingDays
        .where((d) => d != savedDay.date)
        .firstOrNull;
    attendanceToast(
      context,
      next == null || day.saved
          ? AS.t(AS.savedToast, language, {
              'date': attendanceShortDate(savedDay.date),
            })
          : AS.t(AS.savedNextToast, language, {
              'date': attendanceShortDate(savedDay.date),
              'next': attendanceShortDate(next),
            }),
    );
    if (next != null && !day.saved && context.mounted) {
      context.go(
        Uri(
          path: RoutePaths.yorksV1WorkforceAttendance,
          queryParameters: {'crew': savedDay.crew.id, 'date': next},
        ).toString(),
      );
    }
  }

  Future<void> _ask(BuildContext context) async {
    final day = state.day!;
    final text = await showAttendanceCommandDialog(
      context,
      language: language,
      title: AS.t(AS.askTitle, language, {
        'date': attendanceShortDate(day.date),
      }),
      body: AS.t(AS.askBody, language, {'by': day.enteredBy ?? ''}),
      fieldLabel: AS.t(AS.askQuestion, language),
      confirmLabel: AS.t(AS.send, language),
      command: (text) async =>
          await controller.ask(text) ? null : controller.current.error,
    );
    if (text != null && context.mounted) {
      attendanceToast(context, AS.t(AS.sentToast, language));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = state.day!;
    final phone = AccountsV2Breakpoints.isPhone(context);
    final summary = Text(_summary, style: v2Style(13, weight: FontWeight.w600));

    Widget barContent;
    if (day.editable && (state.dirty || !day.saved)) {
      barContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          summary,
          // Phones keep the bar short; the note is on wider screens.
          if (!phone)
            Text(
              AS.t(
                day.crew.needsConfirmation
                    ? AS.draftNote
                    : AS.draftNoteWorkshop,
                language,
              ),
              style: v2Style(11.5, color: AccountsV2Colors.mut),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (state.dirty && day.saved)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: AccountsV2Button(
                    label: AS.t(AS.discardChanges, language),
                    kind: AccountsV2ButtonKind.ghost,
                    onPressed: state.saving ? null : controller.discard,
                  ),
                ),
              Expanded(
                child: AccountsV2Button(
                  key: const ValueKey('attendance-save-day'),
                  block: true,
                  label: day.saved
                      ? AS.t(AS.saveChanges, language)
                      : AS.t(AS.saveDay, language, {
                          'date': attendanceShortDate(day.date),
                        }),
                  icon: state.saving ? 'clock' : 'check',
                  kind: AccountsV2ButtonKind.primary,
                  size: AccountsV2ButtonSize.large,
                  onPressed: state.canSave ? () => _save(context, ref) : null,
                ),
              ),
            ],
          ),
        ],
      );
    } else if (day.saved) {
      barContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${AS.t(AS.enteredByLine, language, {'by': day.enteredBy, 'at': attendanceStamp(day.enteredAt)})}${day.enteredLate ? ' ${AS.t(AS.caughtUpLater, language)}' : ''}',
            style: v2Style(12.5, weight: FontWeight.w600),
          ),
          summary,
          if (day.access.confirm &&
              !day.locked &&
              (day.question == null || !day.question!.isOpen)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AccountsV2Button(
                key: const ValueKey('attendance-ask'),
                label: AS.t(AS.askQuestion, language),
                icon: 'chat',
                onPressed: state.saving ? null : () => _ask(context),
              ),
            ),
          ],
        ],
      );
    } else {
      barContent = Text(
        AS.t(AS.notEnteredLine, language),
        style: v2Style(13, color: AccountsV2Colors.mut),
      );
    }

    final panel = Padding(
      padding: EdgeInsets.all(phone ? 12 : 14),
      child: barContent,
    );
    if (day.editable && (state.dirty || !day.saved)) {
      return AccountsV2BottomBar(
        key: const ValueKey('attendance-save-bar'),
        child: panel,
      );
    }
    return AccountsV2Panel(child: panel);
  }
}
