/// Workforce Center — Request crew, and Fix and resubmit a returned request.
///
/// Nothing reaches the approver until Send succeeds on the server; a refusal
/// is shown on the form with everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_repository.dart';
import '../../domain/crew_request_models.dart';
import '../attendance/attendance_common.dart';
import 'crew_request_common.dart';

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
      return AttendanceLoadState(
        language: language,
        error: error,
        onRetry: () {
          ref.invalidate(yorksCrewRequestOptionsProvider);
          if (requestId != null) {
            ref.invalidate(yorksCrewRequestProvider(requestId!));
          }
        },
      );
    }
    final loadedOptions = options.valueOrNull;
    final loadedRequest = existing?.valueOrNull;
    if (loadedOptions == null || (requestId != null && loadedRequest == null)) {
      return AttendanceLoadState(language: language);
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
  _LineDraft({String trade = '', String quantity = '', String note = ''})
    : trade = TextEditingController(text: trade),
      quantity = TextEditingController(text: quantity),
      note = TextEditingController(text: note);

  final TextEditingController trade;
  final TextEditingController quantity;
  final TextEditingController note;

  int? get count => int.tryParse(quantity.text.trim());
  bool get isBlank =>
      trade.text.trim().isEmpty &&
      quantity.text.trim().isEmpty &&
      note.text.trim().isEmpty;
  bool get isValid =>
      trade.text.trim().isNotEmpty &&
      count != null &&
      count! >= 1 &&
      count! <= 200;

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
        _lines.add(
          _LineDraft(
            trade: line.trade,
            quantity: '${line.quantity}',
            note: line.note ?? '',
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

  CrewRequestProjectOption? get _project {
    for (final project in _options.projects) {
      if (project.id == _projectId) return project;
    }
    return null;
  }

  bool get _approvedOnSubmit => _kind == 'workshop'
      ? _options.projects.isEmpty
            ? false
            : _options.projects.every((p) => p.approvedOnSubmit)
      : _project?.approvedOnSubmit ?? false;

  List<CrewRequestCrewOption> get _crews => [
    for (final crew in _options.crews)
      if (crew.kind == _kind &&
          (_kind == 'workshop' || crew.projectId == _projectId))
        crew,
  ];

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

  Future<void> _submit() async {
    final lines = [
      for (final line in _lines)
        if (!line.isBlank) line,
    ];
    if (_kind == 'project' && _projectId == null) {
      setState(() => _error = CRS.t(CRS.errProject, _language));
      return;
    }
    if (lines.isEmpty || lines.any((line) => !line.isValid)) {
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
              for (final line in lines)
                CrewRequestDraftLine(
                  trade: line.trade.text,
                  quantity: line.count!,
                  note: line.note.text,
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

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final request = widget.request;
    final canProject = _options.projects.isNotEmpty;
    final canWorkshop = _options.workshop;
    if (!canProject && !canWorkshop) {
      return AttendancePage(
        language: language,
        title: CRS.t(CRS.formTitleNew, language),
        children: [
          AccountsV2Panel(
            child: AccountsV2Empty(
              icon: 'users',
              title: CRS.t(CRS.noProjects, language),
              action: AccountsV2Button(
                label: CRS.t(CRS.back, language),
                icon: 'undo',
                onPressed: () => context.go(RoutePaths.yorksV1Workforce),
              ),
            ),
          ),
        ],
      );
    }
    final crews = _crews;
    if (_targetCrewId != null && crews.every((c) => c.id != _targetCrewId)) {
      _targetCrewId = null;
    }
    return AttendancePage(
      language: language,
      eyebrow: CRS.t(CRS.back, language),
      title: request == null
          ? CRS.t(CRS.formTitleNew, language)
          : CRS.t(CRS.formTitleFix, language, {'number': request.number}),
      subtitle: CRS.t(CRS.formIntro, language),
      actions: [
        AccountsV2Button(
          label: AS.t(AS.cancel, language),
          onPressed: _busy
              ? null
              : () => context.go(
                  request == null
                      ? RoutePaths.yorksV1Workforce
                      : crewRequestPath(request.id),
                ),
        ),
      ],
      children: [
        if (request?.decisionReason != null)
          AccountsV2Note(
            tone: AccountsV2NoteTone.warn,
            child: Text(
              '${CRS.t(CRS.factReason, language)}: “${request!.decisionReason}”',
              style: v2Style(13),
            ),
          ),
        AccountsV2Panel(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canProject && canWorkshop) ...[
                  Text(
                    CRS.t(CRS.forLabel, language),
                    style: v2Style(12.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  CrewRequestToggle<String>(
                    key: const ValueKey('crew-request-kind'),
                    options: [
                      ('project', CRS.t(CRS.kindProject, language)),
                      ('workshop', CRS.t(CRS.kindWorkshop, language)),
                    ],
                    selected: _kind,
                    onChanged: _busy
                        ? null
                        : (value) {
                            _kind = value;
                            _targetCrewId = null;
                            _changed();
                          },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_kind == 'project') ...[
                  AccountsV2Select<String?>(
                    key: const ValueKey('crew-request-project'),
                    label: CRS.t(CRS.projectLabel, language),
                    value: _projectId,
                    options: [
                      if (_projectId == null) (null, '—'),
                      for (final project in _options.projects)
                        (project.id, '${project.ref} · ${project.name}'),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            _projectId = value;
                            _targetCrewId = null;
                            _changed();
                          },
                  ),
                  const SizedBox(height: 12),
                ],
                AccountsV2TextField(
                  key: const ValueKey('crew-request-work'),
                  label: CRS.t(CRS.workLabel, language),
                  hint: CRS.t(CRS.workHint, language),
                  controller: _work,
                  enabled: !_busy,
                  onChanged: (_) => _changed(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _DateButton(
                      key: const ValueKey('crew-request-from'),
                      label: CRS.t(CRS.neededFrom, language),
                      value: attendanceLongDate(_neededFrom),
                      onPressed: _busy ? null : () => _pickDate(until: false),
                    ),
                    _DateButton(
                      key: const ValueKey('crew-request-until'),
                      label: CRS.t(CRS.neededUntil, language),
                      value: _neededUntil == null
                          ? '—'
                          : attendanceLongDate(_neededUntil!),
                      onPressed: _busy ? null : () => _pickDate(until: true),
                      onClear: _neededUntil == null || _busy
                          ? null
                          : () => setState(() {
                              _neededUntil = null;
                              _idempotencyKey = null;
                            }),
                      clearLabel: CRS.t(CRS.clearDate, language),
                    ),
                  ],
                ),
                if (crews.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AccountsV2Select<String?>(
                    key: const ValueKey('crew-request-target'),
                    label: CRS.t(CRS.targetCrew, language),
                    value: _targetCrewId,
                    options: [
                      (null, CRS.t(CRS.targetCrewAny, language)),
                      for (final crew in crews) (crew.id, crew.name),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            _targetCrewId = value;
                            _changed();
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: CRS.t(CRS.peopleNeeded, language),
                icon: 'users',
              ),
              for (final (index, line) in _lines.indexed)
                _LineEditor(
                  key: ObjectKey(line),
                  index: index,
                  line: line,
                  trades: _options.trades,
                  language: language,
                  enabled: !_busy,
                  onChanged: _changed,
                  onRemove: _lines.length == 1
                      ? null
                      : () {
                          final removed = _lines.removeAt(index);
                          _changed();
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => removed.dispose(),
                          );
                        },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AccountsV2Button(
                    key: const ValueKey('crew-request-add-line'),
                    label: CRS.t(CRS.addTrade, language),
                    icon: 'plus',
                    onPressed: _busy || _lines.length >= 50
                        ? null
                        : () {
                            _lines.add(_LineDraft());
                            _changed();
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
        AccountsV2Panel(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccountsV2TextField(
                  key: const ValueKey('crew-request-notes'),
                  label: CRS.t(CRS.notesLabel, language),
                  controller: _notes,
                  enabled: !_busy,
                  onChanged: (_) => _changed(),
                ),
                const SizedBox(height: 12),
                AccountsV2Note(
                  tone: _approvedOnSubmit
                      ? AccountsV2NoteTone.ok
                      : AccountsV2NoteTone.info,
                  child: Text(
                    CRS.t(
                      _approvedOnSubmit
                          ? CRS.approvedOnSubmitHint
                          : CRS.waitsForApprovalHint,
                      language,
                    ),
                    style: v2Style(12.5),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: AccountsV2Note(
                      key: const ValueKey('crew-request-error'),
                      tone: AccountsV2NoteTone.bad,
                      child: Text(_error!, style: v2Style(13)),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AccountsV2Button(
                    key: const ValueKey('crew-request-send'),
                    label: _busy
                        ? AS.t(AS.saving, language)
                        : CRS.t(
                            request == null ? CRS.send : CRS.sendAgain,
                            language,
                          ),
                    icon: 'check',
                    kind: AccountsV2ButtonKind.primary,
                    size: AccountsV2ButtonSize.large,
                    onPressed: _busy ? null : _submit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    super.key,
    required this.label,
    required this.value,
    this.onPressed,
    this.onClear,
    this.clearLabel,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;
  final VoidCallback? onClear;
  final String? clearLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: v2Style(12.5, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AccountsV2Button(label: value, onPressed: onPressed),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              AccountsV2Button(
                label: clearLabel ?? '',
                kind: AccountsV2ButtonKind.ghost,
                onPressed: onClear,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.index,
    required this.line,
    required this.trades,
    required this.language,
    required this.enabled,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final _LineDraft line;
  final List<String> trades;
  final AppLanguage language;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final typed = line.trade.text.trim().toLowerCase();
    final suggestions = [
      for (final trade in trades)
        if (trade.toLowerCase() != typed &&
            (typed.isEmpty || trade.toLowerCase().contains(typed)))
          trade,
    ].take(6).toList();
    final phone = AccountsV2Breakpoints.isPhone(context);
    final tradeField = AccountsV2TextField(
      key: ValueKey('crew-request-trade-$index'),
      label: CRS.t(CRS.trade, language),
      hint: CRS.t(CRS.tradeHint, language),
      controller: line.trade,
      enabled: enabled,
      onChanged: (_) => onChanged(),
    );
    final quantityField = AccountsV2TextField(
      key: ValueKey('crew-request-quantity-$index'),
      label: CRS.t(CRS.howMany, language),
      controller: line.quantity,
      numeric: true,
      enabled: enabled,
      width: phone ? null : 120,
      onChanged: (_) => onChanged(),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AccountsV2Colors.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone) ...[
            tradeField,
            const SizedBox(height: 8),
            quantityField,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tradeField),
                const SizedBox(width: 10),
                quantityField,
              ],
            ),
          if (suggestions.isNotEmpty && enabled) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final trade in suggestions)
                  AccountsV2Button(
                    label: trade,
                    icon: 'plus',
                    size: AccountsV2ButtonSize.small,
                    kind: AccountsV2ButtonKind.ghost,
                    onPressed: () {
                      line.trade.text = trade;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AccountsV2TextField(
                  key: ValueKey('crew-request-note-$index'),
                  label: CRS.t(CRS.lineNote, language),
                  controller: line.note,
                  enabled: enabled,
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                AccountsV2Button(
                  key: ValueKey('crew-request-remove-$index'),
                  label: CRS.t(CRS.remove, language),
                  kind: AccountsV2ButtonKind.ghostDanger,
                  onPressed: enabled ? onRemove : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
