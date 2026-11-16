/// Workforce attendance V2 — inputs shared by Take attendance, the worker
/// editor, the shift dialog and the crew editor, so they behave the same on
/// every screen:
///
/// * time boxes with a number keyboard and Next, which select their time
///   when entered so typing replaces it, and a clock under each one that
///   sets the time on the standard dial instead (PRODUCT_DECISIONS
///   section 62);
/// * a searchable worker picker — a tall sheet on phones, a dialog
///   elsewhere — that adds several workers in one go;
/// * the phone's quick-action tiles.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';

// ─── Time box ────────────────────────────────────────────────────────────────

/// What a time box's clock sets: the time shown at the top of the dial, the
/// time the box reads now and where the dial opens when the box is empty or
/// not a time.
final class AttendanceClock {
  const AttendanceClock({
    required this.title,
    required this.fallback,
    this.current,
  });

  /// Which time is being set ("Out · Gul Zaman").
  final String title;

  /// The box's time as read now, with the box before it as context.
  final int? current;

  /// Minutes from midnight the dial opens at when [current] is null.
  final int fallback;
}

/// The standard clock for one time (PRODUCT_DECISIONS section 62): Flutter's
/// dial, with its own switch to typing the hour and minute, always in
/// 12-hour time as the app writes times. Its short animations follow the
/// device's reduce-motion setting. Resolves to minutes from midnight, or
/// null when closed.
Future<int?> showAttendanceClock(
  BuildContext context, {
  required int initial,
  required String title,
}) async {
  final minutes = initial.clamp(0, 24 * 60 - 1);
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    helpText: title,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
      child: child!,
    ),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

/// The line under a time box: a clock and the time it reads ("6:30 AM"),
/// red "Not a time" when it cannot be read. Tapping opens the clock; the
/// whole line is at least a 44px target.
class AttendanceClockButton extends StatelessWidget {
  const AttendanceClockButton({
    super.key,
    required this.text,
    required this.tooltip,
    required this.onPressed,
    this.error = false,
  });

  final String text;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AccountsV2Colors.bad : AccountsV2Colors.mut;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        value: text,
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: error
                        ? AccountsV2Colors.bad
                        : onPressed == null
                        ? AccountsV2Colors.mut2
                        : AccountsV2Colors.pri,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: v2Style(
                        11.5,
                        weight: error ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A time box ("630", "5", "17:30", "5p"). Phones get a number keyboard with
/// Next; entering the box selects its time, so typing replaces it. With a
/// [clock], the line under the box shows the time it reads and opens the
/// standard clock; a picked time is written back as "5:45p", which reads as
/// exactly that time whatever the box before it says.
class AttendanceTimeField extends StatefulWidget {
  const AttendanceTimeField({
    super.key,
    required this.label,
    required this.controller,
    this.onChanged,
    this.error = false,
    this.enabled = true,
    this.hint,
    this.last = false,
    this.clock,
    this.caption,
    this.clockKey,
    this.language = AppLanguage.english,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool error;
  final bool enabled;
  final String? hint;

  /// The last box of a row: the keyboard shows Done instead of Next.
  final bool last;

  /// Shows the clock line under the box.
  final AttendanceClock? clock;

  /// The clock line's text: the time read, or "Not a time".
  final String? caption;
  final Key? clockKey;
  final AppLanguage language;

  @override
  State<AttendanceTimeField> createState() => _AttendanceTimeFieldState();
}

class _AttendanceTimeFieldState extends State<AttendanceTimeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) return;
    _selectAll();
    // A tap that gives focus places the caret in the same frame; select
    // again once it has.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.hasFocus) _selectAll();
    });
  }

  void _selectAll() {
    final text = widget.controller.text;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  Future<void> _pick(AttendanceClock clock) async {
    final picked = await showAttendanceClock(
      context,
      initial: clock.current ?? clock.fallback,
      title: clock.title,
    );
    if (picked == null || !mounted) return;
    // With its AM/PM the text reads back as exactly the picked time.
    final text = formatAttendanceTimeInput(picked);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.clock;
    final box = _box();
    if (clock == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        AttendanceClockButton(
          key: widget.clockKey,
          text: widget.caption ?? formatAttendanceTime(clock.current),
          error: widget.error,
          tooltip: AS.t(AS.pickOnClock, widget.language, {
            'field': widget.label,
          }),
          onPressed: widget.enabled ? () => _pick(clock) : null,
        ),
      ],
    );
  }

  Widget _box() {
    return AccountsV2TextField(
      label: widget.label,
      controller: widget.controller,
      onChanged: widget.onChanged,
      error: widget.error,
      enabled: widget.enabled,
      hint: widget.hint,
      focusNode: _focus,
      // Digits are enough: "630", "1730", or "5" after a 1 PM start.
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: widget.last
          ? TextInputAction.done
          : TextInputAction.next,
    );
  }
}

// ─── Worker picker ───────────────────────────────────────────────────────────

/// Picks workers by any part of the name or number: a tall sheet on phones
/// and a dialog elsewhere. Tap to tick several, or type and press Enter to
/// tick the best match and start the next name. Resolves to the ticked
/// workers in the order they were ticked, or null when closed.
Future<List<AttendanceWorker>?> showAttendanceWorkerPicker(
  BuildContext context, {
  required AppLanguage language,
  required String title,
  required List<AttendanceWorker> workers,
  Set<String> exclude = const {},
}) {
  final picker = _WorkerPicker(
    language: language,
    title: title,
    workers: [
      for (final worker in workers)
        if (!exclude.contains(worker.id)) worker,
    ],
  );
  if (AccountsV2Breakpoints.isPhone(context)) {
    return showModalBottomSheet<List<AttendanceWorker>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        // Above the keyboard, so the list and Add stay in sight.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(heightFactor: .9, child: picker),
      ),
    );
  }
  return showDialog<List<AttendanceWorker>>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: picker,
      ),
    ),
  );
}

class _WorkerPicker extends StatefulWidget {
  const _WorkerPicker({
    required this.language,
    required this.title,
    required this.workers,
  });

  final AppLanguage language;
  final String title;
  final List<AttendanceWorker> workers;

  @override
  State<_WorkerPicker> createState() => _WorkerPickerState();
}

class _WorkerPickerState extends State<_WorkerPicker> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// Ticked workers, in the order they were ticked.
  final _picked = <String, AttendanceWorker>{};

  /// Everyone, the labour pool first, then by name.
  late final List<AttendanceWorker> _everyone = [...widget.workers]
    ..sort((a, b) {
      final pool = (a.crewId == null ? 0 : 1).compareTo(
        b.crewId == null ? 0 : 1,
      );
      return pool != 0
          ? pool
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Matches for [text], best first; null when nothing is typed.
  List<AttendanceSearchHit<AttendanceWorker>>? _hits(String text) =>
      text.trim().isEmpty
      ? null
      : attendanceFuzzySearch(
          text,
          widget.workers,
          (w) => '${w.name} ${w.number}',
          limit: 30,
        );

  void _toggle(AttendanceWorker worker) {
    setState(() {
      if (_picked.remove(worker.id) == null) _picked[worker.id] = worker;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final hits = _hits(_search.text);
    final items = hits == null ? _everyone : [for (final h in hits) h.item];
    final correction =
        hits != null && hits.isNotEmpty && hits.first.isCorrection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: v2Style(17, weight: FontWeight.w700),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: AccountsV2TextField(
            key: const ValueKey('attendance-picker-search'),
            label: AS.t(AS.searchWorkers, language),
            controller: _search,
            focusNode: _searchFocus,
            search: true,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            // Enter ticks the best match and clears the box for the next
            // name, keeping the keyboard up.
            onSubmitted: (text) {
              final best = _hits(text)?.firstOrNull?.item;
              if (best != null) {
                setState(() {
                  _picked.putIfAbsent(best.id, () => best);
                  _search.clear();
                });
              }
              _searchFocus.requestFocus();
            },
          ),
        ),
        if (correction)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
            child: Text(
              AS.t(AS.didYouMean, language, {'name': items.first.name}),
              style: v2Style(12, color: AccountsV2Colors.warn),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    AS.t(AS.noMatchWorker, language),
                    style: v2Style(13, color: AccountsV2Colors.mut),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('attendance-picker-list'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final worker = items[index];
                    return _PickerRow(
                      worker: worker,
                      selected: _picked.containsKey(worker.id),
                      language: language,
                      onTap: () => _toggle(worker),
                    );
                  },
                ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AccountsV2Colors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_picked.isNotEmpty)
                  SingleChildScrollView(
                    key: const ValueKey('attendance-picker-picked'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        for (final worker in _picked.values)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: InputChip(
                              label: Text(worker.name),
                              labelStyle: v2Style(
                                12.5,
                                weight: FontWeight.w600,
                                color: AccountsV2Colors.pri,
                              ),
                              backgroundColor: AccountsV2Colors.pri50,
                              side: BorderSide.none,
                              deleteIconColor: AccountsV2Colors.pri,
                              deleteButtonTooltipMessage: AS.t(
                                AS.remove,
                                language,
                              ),
                              onDeleted: () => _toggle(worker),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: AccountsV2Button(
                    key: const ValueKey('attendance-picker-add'),
                    block: true,
                    kind: AccountsV2ButtonKind.primary,
                    size: AccountsV2ButtonSize.large,
                    icon: 'plus',
                    label: _picked.isEmpty
                        ? AS.t(AS.addWorkers, language)
                        : AS.t(AS.addCount, language, {'n': _picked.length}),
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_picked.values.toList()),
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

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.worker,
    required this.selected,
    required this.language,
    required this.onTap,
  });

  final AttendanceWorker worker;
  final bool selected;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AccountsV2Colors.pri50 : Colors.white,
        child: InkWell(
          key: ValueKey('attendance-picker-worker-${worker.id}'),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                AttendanceAvatar(initials: worker.initials, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        worker.name,
                        style: v2Style(14, weight: FontWeight.w600),
                      ),
                      Text(
                        // Attendance is taken at places, not crews: the
                        // worker's company tells namesakes apart.
                        [
                          worker.number,
                          worker.designation,
                          worker.company,
                        ].where((part) => part.isNotEmpty).join(' · '),
                        style: v2Style(12, color: AccountsV2Colors.mut),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 24,
                  color: selected
                      ? AccountsV2Colors.pri
                      : AccountsV2Colors.lineS,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheets a labourer is on ("On Sweihan site crew, Workshop +1"), or
/// Labour pool.
String attendanceWorkerSheets(AttendanceWorker worker, AppLanguage language) {
  final names = [for (final crew in worker.crews) crew.name];
  if (names.isEmpty) return AS.t(AS.labourPool, language);
  final shown = names.take(2).join(', ');
  return AS.t(AS.onCrews, language, {
    'crews': names.length > 2 ? '$shown +${names.length - 2}' : shown,
  });
}

// ─── Phone quick actions ─────────────────────────────────────────────────────

/// One phone quick action: an icon over a short label (two lines at most), in
/// a row of equal tiles that all stay in sight, at least 64px tall.
class AttendanceActionTile extends StatelessWidget {
  const AttendanceActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;

  /// Read aloud instead of [label] when the label is shortened.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AccountsV2Colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AccountsV2Icon(
                      icon,
                      size: 20,
                      color: enabled
                          ? AccountsV2Colors.pri
                          : AccountsV2Colors.mut,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: v2Style(
                        12,
                        weight: FontWeight.w600,
                        color: AccountsV2Colors.ink2,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone quick actions side by side, equal widths and heights.
class AttendanceActionTiles extends StatelessWidget {
  const AttendanceActionTiles({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

// ─── Choice chips ────────────────────────────────────────────────────────────

/// A choice in the worker editor (status, Out at, a break, an overtime
/// note), drawn like the status pills: a bordered rounded box, blue when
/// chosen, a 44px tap target on phones.
class AttendanceChoiceChip extends StatelessWidget {
  const AttendanceChoiceChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final foreground = selected ? AccountsV2Colors.pri : AccountsV2Colors.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AccountsV2Colors.pri50 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? AccountsV2Colors.pri : AccountsV2Colors.lineS,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: phone ? 44 : 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 16, color: foreground),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: v2Style(
                      13,
                      weight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
