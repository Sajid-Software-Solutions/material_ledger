/// Crew requests — the Worker field, like a Material Request item: type a
/// person's name to ask for them, or describe the workers needed (for
/// example "Labour") and set how many. Suggestions open under the field in
/// the Material Request item-search panel style: People (with Free or the
/// crew they are on), then "Use …" to keep what was typed.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import 'crew_request_common.dart';

class CrewWorkerField extends StatefulWidget {
  const CrewWorkerField({
    super.key,
    required this.slot,
    required this.controller,
    required this.workers,
    required this.excludedWorkerIds,
    required this.language,
    required this.onWorker,
    required this.onChanged,
    this.onTyped,
    this.enabled = true,
    this.desktopCell = false,
    this.label,
    this.errorText,
  });

  /// Names the field and its suggestions in keys: `crew-request-worker-<slot>`.
  final String slot;
  final TextEditingController controller;
  final List<AttendanceWorker> workers;

  /// People already named elsewhere on this request.
  final Set<String> excludedWorkerIds;
  final AppLanguage language;
  final ValueChanged<AttendanceWorker> onWorker;
  final ValueChanged<String> onChanged;

  /// The typed text is kept as the row's description.
  final ValueChanged<String>? onTyped;
  final bool enabled;

  /// A borderless spreadsheet cell, as in the Material Request table.
  final bool desktopCell;
  final String? label;
  final String? errorText;

  @override
  State<CrewWorkerField> createState() => _CrewWorkerFieldState();
}

class _CrewWorkerFieldState extends State<CrewWorkerField> {
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _focus = FocusNode();
  final _group = Object();
  OverlayEntry? _entry;
  int _highlight = 0;

  String get _query => widget.controller.text.trim();

  List<AttendanceWorker> get _people => _query.isEmpty
      ? const []
      : [
          for (final hit in attendanceFuzzySearch(
            _query,
            [
              for (final worker in widget.workers)
                if (!widget.excludedWorkerIds.contains(worker.id)) worker,
            ],
            (worker) => '${worker.name} ${worker.number}',
            limit: 6,
          ))
            hit.item,
        ];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant CrewWorkerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _hide();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _refresh();
    } else {
      _hide();
    }
  }

  void _refresh() {
    if (!widget.enabled || !_focus.hasFocus || _query.isEmpty) {
      _hide();
      return;
    }
    _show();
  }

  void _show() {
    final anchorContext = _anchor.currentContext;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (anchorContext == null || overlay == null) return;
    final fieldBox = anchorContext.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final viewport = overlayBox.size;
    final origin = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    const margin = 16.0;
    const gap = 6.0;
    final width = math
        .min(560.0, math.max(280.0, viewport.width - margin * 2))
        .toDouble();
    final below = viewport.height - origin.dy - fieldBox.size.height - margin;
    final above = origin.dy - margin;
    final opensBelow = below >= 220 || below >= above;
    final height = math
        .min(420.0, math.max(140.0, opensBelow ? below : above))
        .toDouble();
    final x = origin.dx.clamp(margin, viewport.width - margin - width);
    _entry ??= OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: opensBelow
                  ? Alignment.bottomLeft
                  : Alignment.topLeft,
              followerAnchor: opensBelow
                  ? Alignment.topLeft
                  : Alignment.bottomLeft,
              offset: Offset(x - origin.dx, opensBelow ? gap : -gap),
              child: SizedBox(
                width: width,
                child: TextFieldTapRegion(
                  groupId: _group,
                  child: _SuggestionPanel(
                    slot: widget.slot,
                    language: widget.language,
                    people: _people,
                    typed: _query,
                    highlight: _highlight,
                    maxHeight: height,
                    onPerson: _pickPerson,
                    onTyped: _keepTyped,
                    onHover: (index) {
                      if (index == _highlight) return;
                      _highlight = index;
                      _entry?.markNeedsBuild();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (_entry!.mounted) {
      _entry!.markNeedsBuild();
    } else {
      overlay.insert(_entry!);
    }
  }

  void _hide() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _pickPerson(AttendanceWorker worker) {
    _hide();
    _focus.unfocus();
    widget.onWorker(worker);
  }

  void _keepTyped() {
    final text = _query;
    _hide();
    if (text.isNotEmpty) widget.onTyped?.call(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _entry == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hide();
      return KeyEventResult.handled;
    }
    // People, then "Use …".
    final count = _people.length + 1;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _highlight = (_highlight + 1) % count;
      _entry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _highlight = (_highlight - 1 + count) % count;
      _entry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    final people = _people;
    if (_entry != null && _highlight < people.length) {
      _pickPerson(people[_highlight]);
    } else {
      _keepTyped();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onKey,
    child: CompositedTransformTarget(
      key: _anchor,
      link: _link,
      child: TextField(
        key: ValueKey('crew-request-worker-${widget.slot}'),
        groupId: _group,
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        textCapitalization: TextCapitalization.words,
        onChanged: (value) {
          _highlight = 0;
          widget.onChanged(value);
          _refresh();
        },
        onSubmitted: (_) => _submit(),
        onTapOutside: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: CRS.t(CRS.tradeHint, widget.language),
          errorText: widget.errorText,
          isDense: widget.desktopCell,
          contentPadding: widget.desktopCell
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
              : null,
          suffixIcon: widget.desktopCell
              ? null
              : const Icon(Icons.search_rounded, color: AppColors.muted),
          border: widget.desktopCell ? InputBorder.none : null,
          enabledBorder: widget.desktopCell ? InputBorder.none : null,
          focusedBorder: widget.desktopCell
              ? const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.blue, width: 2),
                )
              : null,
        ),
      ),
    ),
  );
}

/// The Material Request suggestion panel: people, then "Use …".
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.slot,
    required this.language,
    required this.people,
    required this.typed,
    required this.highlight,
    required this.maxHeight,
    required this.onPerson,
    required this.onTyped,
    required this.onHover,
  });

  final String slot;
  final AppLanguage language;
  final List<AttendanceWorker> people;
  final String typed;
  final int highlight;
  final double maxHeight;
  final ValueChanged<AttendanceWorker> onPerson;
  final VoidCallback onTyped;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (people.isNotEmpty) {
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: [
              const Icon(Icons.badge_outlined, size: 16, color: AppColors.blue),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  CRS.t(CRS.suggestPeople, language).toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.inkSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                '${people.length}',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
      for (final (index, worker) in people.indexed) {
        final onCrew = worker.crewId != null;
        children.add(
          InkWell(
            key: ValueKey('crew-request-suggest-worker-$slot-${worker.id}'),
            canRequestFocus: false,
            onTap: () => onPerson(worker),
            onHover: (hovering) {
              if (hovering) onHover(index);
            },
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              decoration: BoxDecoration(
                color: highlight == index
                    ? AppColors.blue.withValues(alpha: 0.06)
                    : null,
                border: const Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      worker.initials,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          [
                            worker.number,
                            worker.designation,
                          ].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: onCrew
                            ? AppColors.warningContainer
                            : AppColors.successContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Text(
                        onCrew
                            ? CRS.t(CRS.workerOnCrew, language, {
                                'crew': worker.crewName ?? '',
                              })
                            : CRS.t(CRS.workerFree, language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall.copyWith(
                          color: onCrew ? AppColors.warning : AppColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    // Keep what was typed, as "Keep as custom item" on a Material Request.
    children.add(
      InkWell(
        key: ValueKey('crew-request-use-typed-$slot'),
        canRequestFocus: false,
        onTap: onTyped,
        onHover: (hovering) {
          if (hovering) onHover(people.length);
        },
        child: Container(
          color: highlight == people.length
              ? AppColors.blue.withValues(alpha: 0.06)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.add_rounded, size: 19, color: AppColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  CRS.t(CRS.askForAny, language, {'text': typed}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Material(
      key: ValueKey('crew-request-suggestions-$slot'),
      elevation: 8,
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: children,
        ),
      ),
    );
  }
}
