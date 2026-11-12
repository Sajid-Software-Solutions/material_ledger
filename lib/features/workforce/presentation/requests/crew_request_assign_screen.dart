/// Workforce Center — PR assigns workers to an approved crew request.
///
/// Like a Material Request arrangement: each line is filled from free
/// workers, and a line left short is recorded as Partial or Cannot provide
/// now with a reason. Everything is saved in one server command, or nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/attendance_time.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart';
import 'crew_request_common.dart';

class CrewRequestAssignScreen extends ConsumerWidget {
  const CrewRequestAssignScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = attendanceLanguage(ref);
    final request = ref.watch(yorksCrewRequestProvider(requestId));
    final options = ref.watch(yorksCrewRequestOptionsProvider);
    final error = request.error ?? options.error;
    if (error != null) {
      return AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () {
          ref.invalidate(yorksCrewRequestProvider(requestId));
          ref.invalidate(yorksCrewRequestOptionsProvider);
        },
      );
    }
    final loadedRequest = request.valueOrNull;
    final loadedOptions = options.valueOrNull;
    if (loadedRequest == null || loadedOptions == null) {
      return AttendanceLoadState(language: language);
    }
    if (!loadedRequest.access.fulfil) {
      return AttendancePage(
        language: language,
        title: loadedRequest.number,
        children: [
          AccountsV2Panel(
            child: AccountsV2Empty(
              icon: 'shield',
              title: crewRequestNextStep(loadedRequest, language),
              action: AccountsV2Button(
                label: AS.t(AS.retry, language),
                icon: 'undo',
                onPressed: () => context.go(crewRequestPath(requestId)),
              ),
            ),
          ),
        ],
      );
    }
    return _AssignForm(
      key: ValueKey(
        'crew-request-assign-${loadedRequest.id}-${loadedRequest.recordVersion}',
      ),
      request: loadedRequest,
      options: loadedOptions,
      language: language,
    );
  }
}

class _LineChoice {
  _LineChoice(CrewRequestLine line)
    : decision = line.decision == CrewRequestLineDecision.full
          ? null
          : line.decision,
      reason = TextEditingController(text: line.decisionReason ?? ''),
      search = TextEditingController();

  final Set<String> chosen = {};
  CrewRequestLineDecision? decision;
  final TextEditingController reason;
  final TextEditingController search;

  void dispose() {
    reason.dispose();
    search.dispose();
  }
}

class _AssignForm extends ConsumerStatefulWidget {
  const _AssignForm({
    super.key,
    required this.request,
    required this.options,
    required this.language,
  });

  final CrewRequest request;
  final CrewRequestOptions options;
  final AppLanguage language;

  @override
  ConsumerState<_AssignForm> createState() => _AssignFormState();
}

class _AssignFormState extends ConsumerState<_AssignForm> {
  late final Map<String, _LineChoice> _choices = {
    for (final line in widget.request.lines) line.id: _LineChoice(line),
  };
  late bool _newCrew;
  String? _crewId;
  late final TextEditingController _crewName;
  late final TextEditingController _shiftStart;
  late final TextEditingController _shiftFinish;
  bool _busy = false;
  String? _error;
  String? _key;

  CrewRequest get _request => widget.request;
  AppLanguage get _language => widget.language;

  List<CrewRequestCrewOption> get _crews => [
    for (final crew in widget.options.crews)
      if (crew.kind == _request.crewKind &&
          crew.projectId == _request.projectId)
        crew,
  ];

  @override
  void initState() {
    super.initState();
    final crews = _crews;
    _crewId =
        _request.targetCrewId != null &&
            crews.any((c) => c.id == _request.targetCrewId)
        ? _request.targetCrewId
        : (crews.length == 1 ? crews.first.id : null);
    _newCrew = crews.isEmpty;
    final label = [
      if (_request.projectRef != null) _request.projectRef!,
      _request.workLabel ?? _request.trades.firstOrNull?.trade ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
    _crewName = TextEditingController(text: label);
    _shiftStart = TextEditingController(text: formatAttendanceTimeInput(390));
    _shiftFinish = TextEditingController(text: formatAttendanceTimeInput(1020));
  }

  @override
  void dispose() {
    for (final choice in _choices.values) {
      choice.dispose();
    }
    _crewName.dispose();
    _shiftStart.dispose();
    _shiftFinish.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _key = null;
    _error = null;
  });

  /// Workers free to join: active, on no crew, not chosen on another line.
  List<AttendanceWorker> _free(CrewRequestLine line) {
    final takenElsewhere = {
      for (final entry in _choices.entries)
        if (entry.key != line.id) ...entry.value.chosen,
      // Already on this request.
      for (final requestLine in _request.lines)
        for (final person in requestLine.assigned) person.workerId,
    };
    final trade = attendanceCanon(line.trade);
    final free = [
      for (final worker in widget.options.workers)
        if (worker.crewId == null && !takenElsewhere.contains(worker.id))
          worker,
    ];
    final query = _choices[line.id]!.search.text;
    if (query.trim().isNotEmpty) {
      return [
        for (final hit in attendanceFuzzySearch(
          query,
          free,
          (worker) => '${worker.name} ${worker.number} ${worker.designation}',
          limit: 30,
        ))
          hit.item,
      ];
    }
    free.sort((a, b) {
      final am = attendanceCanon(a.designation).contains(trade) ? 0 : 1;
      final bm = attendanceCanon(b.designation).contains(trade) ? 0 : 1;
      if (am != bm) return am - bm;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return free.take(30).toList();
  }

  int get _chosenCount =>
      _choices.values.fold(0, (sum, choice) => sum + choice.chosen.length);

  Future<void> _save() async {
    final lines = <CrewRequestFulfilLine>[];
    for (final line in _request.lines) {
      final choice = _choices[line.id]!;
      final total = line.assigned.length + choice.chosen.length;
      final short = total < line.quantity;
      final touched =
          choice.chosen.isNotEmpty ||
          (choice.decision != null && choice.decision != line.decision) ||
          (choice.decision != null &&
              choice.reason.text.trim() != (line.decisionReason ?? ''));
      if (!touched) continue;
      if (short && choice.reason.text.trim().isEmpty) {
        setState(() => _error = CRS.t(CRS.errReasonMissing, _language));
        return;
      }
      lines.add(
        CrewRequestFulfilLine(
          lineId: line.id,
          workerIds: choice.chosen.toList(),
          decision: short
              ? (total > 0
                    ? CrewRequestLineDecision.partial
                    : CrewRequestLineDecision.cannotProvide)
              : null,
          reason: short ? choice.reason.text : null,
        ),
      );
    }
    if (lines.isEmpty) {
      setState(() => _error = CRS.t(CRS.errNothingToSave, _language));
      return;
    }
    Map<String, Object?>? newCrew;
    if (_chosenCount > 0) {
      if (_newCrew) {
        final start = parseAttendanceTime(_shiftStart.text).minutes;
        final finish = parseAttendanceTime(
          _shiftFinish.text,
          after: start,
        ).minutes;
        if (_crewName.text.trim().isEmpty ||
            start == null ||
            finish == null ||
            finish <= start) {
          setState(() => _error = CRS.t(CRS.errCrewMissing, _language));
          return;
        }
        newCrew = {
          'name': _crewName.text.trim(),
          'shift_start_minute': start,
          'shift_finish_minute': finish,
        };
      } else if (_crewId == null) {
        setState(() => _error = CRS.t(CRS.errCrewMissing, _language));
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _key ??= YorksAttendanceRepository.newKey();
    try {
      await ref
          .read(yorksAttendanceRepositoryProvider)
          .fulfilRequest(
            requestId: _request.id,
            crewId: _chosenCount > 0 && !_newCrew ? _crewId : null,
            newCrew: newCrew,
            lines: lines,
            expectedVersion: _request.recordVersion,
            idempotencyKey: _key!,
          );
      if (!mounted) return;
      ref.invalidate(yorksCrewRequestProvider(_request.id));
      ref.invalidate(yorksCrewRequestsProvider);
      ref.invalidate(yorksCrewRequestOptionsProvider);
      ref.invalidate(yorksAttendanceCrewsProvider);
      attendanceToast(context, CRS.t(CRS.assignedToast, _language));
      context.go(crewRequestPath(_request.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = crewRequestErrorText(error, _language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final crews = _crews;
    final chosen = _chosenCount;
    return AttendancePage(
      language: language,
      eyebrow: CRS.t(CRS.back, language),
      title: CRS.t(CRS.assignTitle, language, {'number': _request.number}),
      subtitle:
          '${crewRequestWhere(_request, language)} · ${crewRequestDates(_request, language)}',
      actions: [
        AccountsV2Button(
          label: AS.t(AS.cancel, language),
          onPressed: _busy
              ? null
              : () => context.go(crewRequestPath(_request.id)),
        ),
      ],
      children: [
        AccountsV2Note(
          child: Text(CRS.t(CRS.assignIntro, language), style: v2Style(13)),
        ),
        AccountsV2Panel(
          key: const ValueKey('crew-request-assign-crew'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  CRS.t(CRS.joinCrew, language),
                  style: v2Style(12.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (crews.isNotEmpty)
                  CrewRequestToggle<bool>(
                    key: const ValueKey('crew-request-assign-mode'),
                    options: [
                      (false, CRS.t(CRS.existingCrew, language)),
                      (true, CRS.t(CRS.newCrew, language)),
                    ],
                    selected: _newCrew,
                    onChanged: _busy
                        ? null
                        : (value) {
                            _newCrew = value;
                            _changed();
                          },
                  ),
                const SizedBox(height: 10),
                if (!_newCrew)
                  AccountsV2Select<String?>(
                    key: const ValueKey('crew-request-assign-crew-select'),
                    label: CRS.t(CRS.crewLabel, language),
                    value: _crewId,
                    options: [
                      if (_crewId == null) (null, '—'),
                      for (final crew in crews) (crew.id, crew.name),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            _crewId = value;
                            _changed();
                          },
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AccountsV2TextField(
                        key: const ValueKey('crew-request-assign-crew-name'),
                        label: CRS.t(CRS.newCrewName, language),
                        controller: _crewName,
                        enabled: !_busy,
                        width: 320,
                        onChanged: (_) => _changed(),
                      ),
                      AccountsV2TextField(
                        key: const ValueKey('crew-request-assign-start'),
                        label: CRS.t(CRS.shiftStarts, language),
                        controller: _shiftStart,
                        enabled: !_busy,
                        width: 140,
                        onChanged: (_) => _changed(),
                      ),
                      AccountsV2TextField(
                        key: const ValueKey('crew-request-assign-finish'),
                        label: CRS.t(CRS.shiftEnds, language),
                        controller: _shiftFinish,
                        enabled: !_busy,
                        width: 140,
                        onChanged: (_) => _changed(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        for (final line in _request.lines)
          _LineCard(
            key: ValueKey('crew-request-assign-line-${line.id}'),
            line: line,
            choice: _choices[line.id]!,
            free: _free(line),
            language: language,
            enabled: !_busy,
            onChanged: _changed,
          ),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: AccountsV2Note(
              key: const ValueKey('crew-request-assign-error'),
              tone: AccountsV2NoteTone.bad,
              child: Text(_error!, style: v2Style(13)),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AccountsV2Button(
            key: const ValueKey('crew-request-assign-save'),
            label: _busy
                ? AS.t(AS.saving, language)
                : chosen > 0
                ? CRS.t(CRS.saveAssign, language, {'n': chosen})
                : CRS.t(CRS.saveDecisions, language),
            icon: 'check',
            kind: AccountsV2ButtonKind.primary,
            size: AccountsV2ButtonSize.large,
            onPressed: _busy ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.choice,
    required this.free,
    required this.language,
    required this.enabled,
    required this.onChanged,
  });

  final CrewRequestLine line;
  final _LineChoice choice;
  final List<AttendanceWorker> free;
  final AppLanguage language;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final total = line.assigned.length + choice.chosen.length;
    final remaining = line.quantity - total;
    final complete = line.short == 0;
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title: '${line.quantity} × ${line.trade}',
            icon: 'users',
            subtitle: complete
                ? CRS.t(CRS.lineComplete, language)
                : CRS.t(CRS.chosenOf, language, {
                    'a': total,
                    'b': line.quantity,
                  }),
          ),
          if (line.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                '“${line.note}”',
                style: v2Style(12.5, color: AccountsV2Colors.mut),
              ),
            ),
          if (line.assigned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                CRS.t(CRS.alreadyAssigned, language, {
                  'names': line.assigned.map((a) => a.name).join(', '),
                }),
                style: v2Style(12.5),
              ),
            ),
          if (!complete) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: AccountsV2TextField(
                key: ValueKey('crew-request-assign-search-${line.id}'),
                label: CRS.t(CRS.searchWorkers, language),
                controller: choice.search,
                search: true,
                enabled: enabled,
                onChanged: (_) => onChanged(),
              ),
            ),
            if (free.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  CRS.t(CRS.noFreeWorkers, language),
                  style: v2Style(12.5, color: AccountsV2Colors.mut),
                ),
              )
            else
              for (final worker in free)
                // Its own Material so the tap ripple shows on the card.
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    key: ValueKey(
                      'crew-request-assign-worker-${line.id}-${worker.id}',
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: choice.chosen.contains(worker.id),
                    onChanged:
                        !enabled ||
                            (!choice.chosen.contains(worker.id) &&
                                remaining <= 0)
                        ? null
                        : (value) {
                            if (value == true) {
                              choice.chosen.add(worker.id);
                            } else {
                              choice.chosen.remove(worker.id);
                            }
                            onChanged();
                          },
                    secondary: AttendanceAvatar(initials: worker.initials),
                    title: Text(worker.name, style: v2Style(13.5)),
                    subtitle: Text(
                      [
                        worker.number,
                        worker.designation,
                        worker.company,
                      ].where((part) => part.isNotEmpty).join(' · '),
                      style: v2Style(12, color: AccountsV2Colors.mut),
                    ),
                  ),
                ),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${total > 0 ? CRS.t(CRS.decisionPartial, language) : CRS.t(CRS.decisionCannot, language)} · ${CRS.t(CRS.whyShort, language)}',
                      style: v2Style(12.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    AccountsV2TextField(
                      key: ValueKey('crew-request-assign-reason-${line.id}'),
                      label: CRS.t(CRS.reasonLabel, language),
                      controller: choice.reason,
                      enabled: enabled,
                      onChanged: (_) {
                        choice.decision = total > 0
                            ? CrewRequestLineDecision.partial
                            : CrewRequestLineDecision.cannotProvide;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
