/// Workforce attendance V2 — inputs shared by Take attendance, the worker
/// editor, the shift dialog and the crew editor, so they behave the same on
/// every screen:
///
/// * time boxes with a number keyboard and Next, which select their time
///   when entered so typing replaces it;
/// * a searchable worker picker — a tall sheet on phones, a dialog
///   elsewhere — that adds several workers in one go;
/// * the phone's quick-action tiles.
library;

import 'package:flutter/material.dart';

import '../../../../shared/models/app_language.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import 'attendance_common.dart';

// ─── Time box ────────────────────────────────────────────────────────────────

/// A time box ("630", "5", "17:30", "5p"). Phones get a number keyboard with
/// Next; entering the box selects its time, so typing replaces it.
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
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool error;
  final bool enabled;
  final String? hint;

  /// The last box of a row: the keyboard shows Done instead of Next.
  final bool last;

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

  @override
  Widget build(BuildContext context) {
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
                        '${worker.number} · ${worker.designation} · ${worker.crewName ?? AS.t(AS.labourPool, language)}',
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
