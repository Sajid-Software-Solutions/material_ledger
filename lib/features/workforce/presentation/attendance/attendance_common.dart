/// Workforce attendance V2 — shared pieces for every attendance screen:
/// the page frame, day strips, status colours, date labels and error copy.
///
/// The look reuses the measured prototype kit already used by Accounts, so
/// both prototypes read as one Yorks design.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_attendance_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_time.dart';

typedef AS = AttendanceStrings;

AppLanguage attendanceLanguage(WidgetRef ref) => ref.watch(languageProvider);

// ─── Dates ───────────────────────────────────────────────────────────────────

/// "Mon 9 Nov".
String attendanceShortDate(String iso) =>
    DateFormat('EEE d MMM').format(attendanceDate(iso));

/// "Monday 9 November".
String attendanceLongDate(String iso) =>
    DateFormat('EEEE d MMMM').format(attendanceDate(iso));

/// "Monday 9 November 2026".
String attendanceFullDate(String iso) =>
    DateFormat('EEEE d MMMM y').format(attendanceDate(iso));

/// "November".
String attendanceMonthName(String iso) =>
    DateFormat('MMMM').format(attendanceDate(iso));

/// "November 2026".
String attendanceMonthYear(String iso) =>
    DateFormat('MMMM y').format(attendanceDate(iso));

/// "9 Nov 14:05".
String attendanceStamp(DateTime? at) =>
    at == null ? '' : DateFormat('d MMM HH:mm').format(at.toLocal());

/// `YYYY-MM-DD` for [iso] shifted by [days].
String attendanceShift(String iso, int days) =>
    attendanceIso(attendanceDate(iso).add(Duration(days: days)));

// ─── Labels and tones ────────────────────────────────────────────────────────

TranslatableString attendanceStatusLabel(AttendanceStatus? status) =>
    switch (status) {
      AttendanceStatus.present => AS.present,
      AttendanceStatus.absent => AS.absent,
      AttendanceStatus.rest => AS.restDay,
      AttendanceStatus.annualLeave => AS.annualLeave,
      AttendanceStatus.sickLeave => AS.sickLeave,
      AttendanceStatus.officialLeave => AS.officialLeave,
      AttendanceStatus.unpaidLeave => AS.unpaidLeave,
      null => AS.notMarked,
    };

TranslatableString attendanceDayStateLabel(AttendanceDayState state) =>
    switch (state) {
      AttendanceDayState.entered => AS.dayEntered,
      AttendanceDayState.question => AS.dayQuestion,
      AttendanceDayState.none => AS.dayNone,
      AttendanceDayState.off => AS.restDay,
      AttendanceDayState.locked => AS.dayLocked,
      AttendanceDayState.future => AS.dayNone,
    };

AccountsV2ChipTone attendanceDayStateTone(AttendanceDayState state) =>
    switch (state) {
      AttendanceDayState.entered => AccountsV2ChipTone.ok,
      AttendanceDayState.question => AccountsV2ChipTone.warn,
      AttendanceDayState.none => AccountsV2ChipTone.bad,
      AttendanceDayState.locked => AccountsV2ChipTone.pri,
      AttendanceDayState.off ||
      AttendanceDayState.future => AccountsV2ChipTone.neutral,
    };

/// The month chip: "Confirmed by Faisal", "Ready to confirm" …
({String text, AccountsV2ChipTone tone}) attendanceMonthChip(
  AttendanceMonth month,
  AppLanguage language,
) => switch (month.state) {
  AttendanceMonthState.notNeeded => (
    text: AS.t(AS.monthNotNeeded, language),
    tone: AccountsV2ChipTone.ok,
  ),
  AttendanceMonthState.confirmed => (
    text: AS.t(AS.monthConfirmedBy, language, {
      'name': (month.confirmedBy ?? '').split(' ').first,
    }),
    tone: AccountsV2ChipTone.pri,
  ),
  AttendanceMonthState.ready => (
    text: AS.t(AS.monthReady, language),
    tone: AccountsV2ChipTone.warn,
  ),
  AttendanceMonthState.recording => (
    text: AS.t(AS.monthRecording, language, {
      'date': attendanceShortDate(month.lastDay),
    }),
    tone: AccountsV2ChipTone.neutral,
  ),
};

String attendanceErrorText(Object? error, AppLanguage language) {
  if (error is! YorksV1DomainException) return AS.t(AS.errGeneric, language);
  final message = (error.serverMessage ?? '').toUpperCase();
  TranslatableString pick() {
    if (error.code == YorksV1DomainErrorCode.offline) return AS.errOffline;
    if (error.code == YorksV1DomainErrorCode.conflict) return AS.errConflict;
    if (message.contains('MONTH_LOCKED')) return AS.errLocked;
    if (message.contains('FUTURE_DATE')) return AS.errFuture;
    if (message.contains('DAY_UNMARKED')) return AS.errUnmarked;
    if (message.contains('TIME_MISSING')) return AS.errTime;
    if (message.contains('REST_DAY_NOT_ALLOWED')) return AS.errRest;
    if (message.contains('WORKER_ON_OTHER_CREW')) return AS.errOtherCrew;
    if (message.contains('CHANGE_REASON_REQUIRED') ||
        message.contains('REASON_REQUIRED')) {
      return AS.errReason;
    }
    if (message.contains('MONTH_NOT_ENDED')) return AS.errNotEnded;
    if (message.contains('MONTH_INCOMPLETE')) return AS.errIncomplete;
    if (message.contains('CREW_NAME_TAKEN')) return AS.errCrewName;
    if (error.code == YorksV1DomainErrorCode.unauthorized) return AS.errDenied;
    return AS.errGeneric;
  }

  return AS.t(pick(), language);
}

/// Attendance messages float clear of the sticky Save bar (about 140px on a
/// phone, 120px on a wider screen).
EdgeInsets attendanceSnackMargin(BuildContext context) {
  final phone = MediaQuery.sizeOf(context).width <= 640;
  return EdgeInsets.fromLTRB(12, 0, 12, phone ? 150 : 130);
}

void attendanceToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: attendanceSnackMargin(context),
      ),
    );
}

// ─── Page frame ──────────────────────────────────────────────────────────────

/// Title, intro and actions above a column of cards, in the prototype's
/// measurements. A bottom bar (the Save bar) stays in reach on phones.
class AttendancePage extends StatelessWidget {
  const AttendancePage({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.readOnly = false,
    this.language = AppLanguage.english,
    this.onRefresh,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool readOnly;
  final AppLanguage language;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = AccountsV2Viewport.fromWorkspace(constraints.maxWidth);
        return AccountsV2Viewport(
          width: width,
          child: Builder(
            builder: (context) {
              final phone = AccountsV2Breakpoints.isPhone(context);
              final pad = phone ? 14.0 : 22.0;
              final head = Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null)
                          Text(
                            eyebrow!,
                            style: v2Style(
                              12,
                              weight: FontWeight.w600,
                              color: AccountsV2Colors.mut,
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: v2Style(
                                phone ? 19 : 22,
                                weight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            if (readOnly)
                              AccountsV2Chip(
                                AS.t(AS.readOnly, language),
                                icon: 'expand',
                              ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: v2Style(13, color: AccountsV2Colors.mut),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              );
              final list = ListView(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
                children: [
                  head,
                  const SizedBox(height: accountsV2Gap),
                  AccountsV2Stack(children: children),
                ],
              );
              return ColoredBox(
                color: AccountsV2Colors.bg,
                child: AccountsV2BottomBarHost(
                  child: onRefresh == null
                      ? list
                      : RefreshIndicator(onRefresh: onRefresh!, child: list),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Loading and error states for a whole attendance page.
class AttendanceLoadState extends StatelessWidget {
  const AttendanceLoadState({
    super.key,
    required this.language,
    this.error,
    this.onRetry,
  });

  final AppLanguage language;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const ColoredBox(
        color: AccountsV2Colors.bg,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ColoredBox(
      color: AccountsV2Colors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AccountsV2Panel(
              child: AccountsV2Empty(
                icon: 'alert',
                title: attendanceErrorText(error, language),
                action: onRetry == null
                    ? null
                    : AccountsV2Button(
                        label: AS.t(AS.retry, language),
                        icon: 'undo',
                        onPressed: onRetry,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Day strips ──────────────────────────────────────────────────────────────

Color _stateColor(AttendanceDayState state) => switch (state) {
  AttendanceDayState.entered => AccountsV2Colors.ok,
  AttendanceDayState.question => AccountsV2Colors.org,
  AttendanceDayState.none => AccountsV2Colors.bad,
  AttendanceDayState.locked => AccountsV2Colors.navy,
  AttendanceDayState.off || AttendanceDayState.future => AccountsV2Colors.mut2,
};

String _stateSymbol(AttendanceDayState state) => switch (state) {
  AttendanceDayState.entered || AttendanceDayState.locked => '',
  AttendanceDayState.question => '?',
  AttendanceDayState.none => '!',
  AttendanceDayState.off => '–',
  AttendanceDayState.future => '',
};

/// The app font has no check mark glyph, so entered days draw an icon.
Widget _stateMark(AttendanceDayState state, {double size = 11}) =>
    state == AttendanceDayState.entered || state == AttendanceDayState.locked
    ? Icon(Icons.check_rounded, size: size + 2, color: _stateColor(state))
    : Text(
        _stateSymbol(state),
        style: v2Style(
          size,
          weight: FontWeight.w700,
          color: _stateColor(state),
          height: 1,
        ),
      );

/// The 8-day status squares on the overview.
class AttendanceStatusSquares extends StatelessWidget {
  const AttendanceStatusSquares({super.key, required this.days});

  final List<({String date, AttendanceDayState state, bool holiday})> days;

  @override
  Widget build(BuildContext context) {
    // Shrinks rather than wraps or overflows in a narrow phone card.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: _squares(),
    );
  }

  Widget _squares() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Tooltip(
            message: attendanceShortDate(days[i].date),
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: days[i].state == AttendanceDayState.none
                    ? Colors.white
                    : _stateColor(days[i].state).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _stateColor(days[i].state).withValues(
                    alpha: days[i].state == AttendanceDayState.none
                        ? 0.8
                        : 0.25,
                  ),
                ),
              ),
              child: _stateMark(days[i].state),
            ),
          ),
        ],
      ],
    );
  }
}

/// The legend under the crews card.
class AttendanceLegend extends StatelessWidget {
  const AttendanceLegend({super.key, required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    Widget item(AttendanceDayState state, TranslatableString label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stateMark(state, size: 12),
        const SizedBox(width: 4),
        Text(
          label.active(language),
          style: v2Style(12, color: AccountsV2Colors.mut),
        ),
      ],
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(AttendanceDayState.entered, AS.dayEntered),
        item(AttendanceDayState.question, AS.dayQuestion),
        item(AttendanceDayState.none, AS.dayNone),
        item(AttendanceDayState.off, AS.restDay),
      ],
    );
  }
}

/// A month of day chips: weekday, number and a status dot. Future days are
/// disabled; the selected day is highlighted and scrolled into view.
class AttendanceDayStrip extends StatefulWidget {
  const AttendanceDayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.onSelect,
    this.drafts = const {},
  });

  final List<({String date, AttendanceDayState state, bool holiday})> days;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// Days with entries kept on this device and not yet saved.
  final Set<String> drafts;

  @override
  State<AttendanceDayStrip> createState() => _AttendanceDayStripState();
}

class _AttendanceDayStripState extends State<AttendanceDayStrip> {
  final _controller = ScrollController();
  static const _chipWidth = 52.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(AttendanceDayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    if (!mounted || !_controller.hasClients) return;
    final index = widget.days.indexWhere((d) => d.date == widget.selected);
    if (index < 0) return;
    final viewport = _controller.position.viewportDimension;
    final target = (index * (_chipWidth + 6)) - viewport / 2 + _chipWidth / 2;
    _controller.jumpTo(
      target.clamp(0, _controller.position.maxScrollExtent).toDouble(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final day = widget.days[index];
          final selected = day.date == widget.selected;
          final future = day.state == AttendanceDayState.future;
          final draft = widget.drafts.contains(day.date);
          final date = attendanceDate(day.date);
          return Semantics(
            button: true,
            selected: selected,
            label: attendanceLongDate(day.date),
            child: InkWell(
              key: ValueKey('attendance-day-${day.date}'),
              onTap: future ? null : () => widget.onSelect(day.date),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: _chipWidth,
                decoration: BoxDecoration(
                  color: selected
                      ? AccountsV2Colors.pri
                      : day.holiday
                      ? AccountsV2Colors.neu
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AccountsV2Colors.pri
                        : draft
                        ? AccountsV2Colors.warn
                        : AccountsV2Colors.line,
                    width: draft && !selected ? 1.6 : 1,
                  ),
                ),
                child: Opacity(
                  opacity: future ? 0.4 : 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: v2Style(
                          10.5,
                          weight: FontWeight.w600,
                          color: selected ? Colors.white : AccountsV2Colors.mut,
                        ),
                      ),
                      Text(
                        '${date.day}',
                        style: v2Style(
                          16,
                          weight: FontWeight.w700,
                          color: selected ? Colors.white : AccountsV2Colors.ink,
                          height: 1.2,
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: future
                              ? Colors.transparent
                              : selected
                              ? Colors.white
                              : _stateColor(day.state),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A round initials badge for a worker.
class AttendanceAvatar extends StatelessWidget {
  const AttendanceAvatar({super.key, required this.initials, this.size = 34});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AccountsV2Colors.pri50,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: v2Style(
          size * 0.36,
          weight: FontWeight.w700,
          color: AccountsV2Colors.pri,
        ),
      ),
    );
  }
}

/// Summary of one row: "6:30 AM – 5 PM · break 12:30 PM–1 PM".
String attendanceRowSummary(
  AttendanceRow row, {
  required bool holiday,
  required AppLanguage language,
}) {
  final status = row.status;
  if (status == null) return AS.t(AS.notMarked, language);
  if (status != AttendanceStatus.present) {
    return attendanceStatusLabel(status).active(language);
  }
  final minutes = row.minutes(holiday: holiday);
  if (minutes.timeMissing) return AS.t(AS.timeMissing, language);
  final range =
      '${formatAttendanceTime(row.start)} – ${formatAttendanceTime(row.finish)}';
  if (row.breakStart == null) return range;
  return '$range · ${AS.t(AS.breakRange, language, {'a': formatAttendanceTime(row.breakStart), 'b': formatAttendanceTime(row.breakFinish)})}';
}
