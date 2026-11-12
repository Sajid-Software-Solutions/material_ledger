/// Workforce attendance V2 — Monthly sheets: the paper DAILY TIME SHEET,
/// filled from daily attendance, per worker. Print / PDF for everyone who can
/// see the crew; Excel for those allowed to export.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/app_language.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../accounts/presentation/v2/kit/accounts_v2_kit.dart';
import '../../application/attendance_providers.dart';
import '../../data/attendance_sheet_service.dart';
import '../../domain/attendance_models.dart';
import '../../domain/attendance_search.dart';
import '../../domain/attendance_time.dart';
import 'attendance_common.dart';

class AttendanceSheetsScreen extends ConsumerStatefulWidget {
  const AttendanceSheetsScreen({super.key, this.initialCrewId});

  final String? initialCrewId;

  @override
  ConsumerState<AttendanceSheetsScreen> createState() =>
      _AttendanceSheetsScreenState();
}

class _AttendanceSheetsScreenState
    extends ConsumerState<AttendanceSheetsScreen> {
  String? _crewId;
  String? _month;
  String? _workerId;
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _crewId = widget.initialCrewId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _file(
    AttendanceMonthSheet sheet,
    Future<void> Function() run,
    AppLanguage language,
  ) async {
    setState(() => _busy = true);
    try {
      await run();
    } catch (_) {
      if (mounted) attendanceToast(context, AS.t(AS.fileFailed, language));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        if (crews.isEmpty) {
          return AttendancePage(
            language: language,
            title: AS.t(AS.monthlySheets, language),
            children: [
              AccountsV2Panel(
                child: AccountsV2Empty(
                  icon: 'doc',
                  title: AS.t(AS.crews, language),
                  body: AS.t(AS.noCrews, language),
                ),
              ),
            ],
          );
        }
        final crew =
            crews.where((c) => c.id == _crewId).firstOrNull ?? crews.first;
        final today = attendanceLocalToday();
        final current = attendanceMonthOf(today);
        final month = _month ?? current;
        final months = [
          for (var i = 0; i < 6; i++)
            attendanceIso(
              DateTime(
                attendanceDate(current).year,
                attendanceDate(current).month - i,
              ),
            ),
        ];
        final sheetAsync = ref.watch(
          yorksAttendanceMonthSheetProvider((crewId: crew.id, month: month)),
        );
        final readOnly = crews.every((c) => c.access.readOnly);
        final service = const YorksAttendanceSheetService();
        final files = ref.read(yorksV1DocumentFileServiceProvider);
        final sheet = sheetAsync.valueOrNull;

        return AttendancePage(
          language: language,
          title: AS.t(AS.monthlySheets, language),
          subtitle: AS.t(AS.sheetsIntro, language),
          readOnly: readOnly,
          onRefresh: () async => ref.invalidate(
            yorksAttendanceMonthSheetProvider((crewId: crew.id, month: month)),
          ),
          actions: [
            if (sheet != null) ...[
              AccountsV2Button(
                key: const ValueKey('attendance-sheet-print'),
                label: AS.t(AS.print, language),
                icon: _busy ? 'clock' : 'print',
                onPressed: _busy
                    ? null
                    : () => _file(
                        sheet,
                        () => service.printPdf(
                          sheet,
                          workers: _selectedWorkers(sheet),
                        ),
                        language,
                      ),
              ),
              AccountsV2Button(
                key: const ValueKey('attendance-sheet-pdf'),
                label: AS.t(AS.savePdf, language),
                icon: 'pdf',
                onPressed: _busy
                    ? null
                    : () => _file(sheet, () async {
                        final saved = await files.saveDocument(
                          bytes: await service.buildPdf(
                            sheet,
                            workers: _selectedWorkers(sheet),
                          ),
                          fileName: '${service.fileStem(sheet)}.pdf',
                          mimeType: YorksAttendanceSheetService.pdfMimeType,
                        );
                        if (saved && context.mounted) {
                          attendanceToast(
                            context,
                            AS.t(AS.fileSaved, language),
                          );
                        }
                      }, language),
              ),
              if (sheet.canExport)
                AccountsV2Button(
                  key: const ValueKey('attendance-sheet-excel'),
                  label: AS.t(AS.exportExcel, language),
                  icon: 'sheet',
                  onPressed: _busy
                      ? null
                      : () => _file(sheet, () async {
                          final saved = await files.saveDocument(
                            bytes: service.buildExcel(sheet),
                            fileName: '${service.fileStem(sheet)}.xlsx',
                            mimeType: YorksAttendanceSheetService.xlsxMimeType,
                          );
                          if (saved && context.mounted) {
                            attendanceToast(
                              context,
                              AS.t(AS.fileSaved, language),
                            );
                          }
                        }, language),
                ),
            ],
          ],
          children: [
            AccountsV2Panel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    AccountsV2Select<String>(
                      key: const ValueKey('attendance-sheet-crew'),
                      label: AS.t(AS.colCrew, language),
                      value: crew.id,
                      width: 260,
                      options: [for (final c in crews) (c.id, c.name)],
                      onChanged: (id) => setState(() {
                        _crewId = id;
                        _workerId = null;
                      }),
                    ),
                    AccountsV2Select<String>(
                      key: const ValueKey('attendance-sheet-month'),
                      label: AS.t(AS.colMonth, language),
                      value: month,
                      width: 190,
                      options: [
                        for (final m in months) (m, attendanceMonthYear(m)),
                      ],
                      onChanged: (m) => setState(() => _month = m),
                    ),
                  ],
                ),
              ),
            ),
            sheetAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => AccountsV2Note(
                tone: AccountsV2NoteTone.bad,
                child: Text(attendanceErrorText(error, language)),
              ),
              data: (sheet) => _SheetBody(
                sheet: sheet,
                language: language,
                search: _search,
                selectedWorkerId: _workerId,
                onSearch: () => setState(() {}),
                onSelect: (id) => setState(() => _workerId = id),
              ),
            ),
          ],
        );
      },
    );
  }

  List<AttendanceSheetWorker> _selectedWorkers(AttendanceMonthSheet sheet) {
    final selected = sheet.workers
        .where((w) => w.worker.id == _workerId)
        .firstOrNull;
    return selected == null ? sheet.workers : [selected];
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.sheet,
    required this.language,
    required this.search,
    required this.selectedWorkerId,
    required this.onSearch,
    required this.onSelect,
  });

  final AttendanceMonthSheet sheet;
  final AppLanguage language;
  final TextEditingController search;
  final String? selectedWorkerId;
  final VoidCallback onSearch;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim();
    final hits = query.isEmpty
        ? null
        : attendanceFuzzySearch(
            query,
            sheet.workers,
            (w) =>
                '${w.worker.name} ${w.worker.number} ${w.worker.designation}',
          ).map((hit) => hit.item).toList();
    final list = hits ?? sheet.workers;
    final selected =
        sheet.workers
            .where((w) => w.worker.id == selectedWorkerId)
            .firstOrNull ??
        (sheet.workers.isEmpty ? null : sheet.workers.first);
    final chip = attendanceMonthChip(sheet.month, language);
    return AccountsV2Stack(
      children: [
        AccountsV2Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountsV2CardHead(
                title: AS.t(AS.workersIn, language, {
                  'n': sheet.workers.length,
                  'crew': sheet.crew.name,
                }),
                icon: 'users',
                actions: [AccountsV2Chip(chip.text, tone: chip.tone)],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: AccountsV2TextField(
                  key: const ValueKey('attendance-sheet-search'),
                  label: AS.t(AS.searchWorkerHint, language),
                  controller: search,
                  search: true,
                  onChanged: (_) => onSearch(),
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Text(
                    AS.t(AS.noMatch, language),
                    style: v2Style(13, color: AccountsV2Colors.mut),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final w in list.take(hits == null ? 60 : 6))
                        ChoiceChip(
                          key: ValueKey(
                            'attendance-sheet-worker-${w.worker.id}',
                          ),
                          label: Text(w.worker.name),
                          selected: w.worker.id == selected?.worker.id,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) => onSelect(w.worker.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (selected != null)
          AccountsV2Breakpoints.isNarrow(context)
              ? _PhoneSheet(sheet: sheet, worker: selected, language: language)
              : _PaperSheet(sheet: sheet, worker: selected, language: language),
      ],
    );
  }
}

class _Totals {
  int presentDays = 0;
  int regular = 0;
  int normal = 0;
  int holiday = 0;
}

_Totals _totals(AttendanceMonthSheet sheet, AttendanceSheetWorker worker) {
  final totals = _Totals();
  for (final day in worker.days) {
    final holiday =
        sheet.month.days
            .where((d) => d.date == day.date)
            .firstOrNull
            ?.holiday ??
        false;
    final m = day.row.minutes(holiday: holiday);
    if (day.row.status == AttendanceStatus.present) totals.presentDays++;
    totals.regular += m.regular;
    totals.normal += m.normalOvertime;
    totals.holiday += m.holidayOvertime;
  }
  return totals;
}

String _statusText(
  AttendanceMonthSheet sheet,
  String date,
  AttendanceRow? row,
  bool holiday,
  AppLanguage language,
) {
  if (row == null) return holiday ? '' : AS.t(AS.dayNone, language);
  if (sheet.month.isConfirmed) return AS.t(AS.statusConfirmed, language);
  return (sheet.enteredBy[date]?.changed ?? false)
      ? AS.t(AS.statusEnteredChanged, language)
      : AS.t(AS.dayEntered, language);
}

/// The desktop paper layout.
class _PaperSheet extends StatelessWidget {
  const _PaperSheet({
    required this.sheet,
    required this.worker,
    required this.language,
  });

  final AttendanceMonthSheet sheet;
  final AttendanceSheetWorker worker;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final start = attendanceDate(sheet.month.month);
    final last = attendanceDate(sheet.month.lastDay);
    final today = attendanceLocalToday();
    final byDate = {for (final d in worker.days) d.date: d.row};
    final totals = _totals(sheet, worker);
    final cell = v2Style(12, tabular: true);
    final head = v2Style(
      11,
      weight: FontWeight.w700,
      color: AccountsV2Colors.ink2,
    );
    TableRow headRow() => TableRow(
      decoration: const BoxDecoration(color: AccountsV2Colors.tableHead),
      children: [
        for (final label in [
          AS.t(AS.paperDate, language),
          AS.t(AS.paperDay, language),
          AS.t(AS.colIn, language),
          AS.t(AS.paperBrk, language),
          AS.t(AS.colIn, language),
          AS.t(AS.colOut, language),
          AS.t(AS.paperNor, language),
          AS.t(AS.paperHol, language),
          AS.t(AS.paperProject, language),
          AS.t(AS.colStatus, language),
        ])
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(label, style: head),
          ),
      ],
    );
    final rows = <TableRow>[headRow()];
    final takers = <String>{};
    for (
      var date = start;
      !date.isAfter(last);
      date = date.add(const Duration(days: 1))
    ) {
      final iso = attendanceIso(date);
      final row = byDate[iso];
      final holiday =
          sheet.month.days.where((d) => d.date == iso).firstOrNull?.holiday ??
          false;
      final m = row?.minutes(holiday: holiday);
      final entry = sheet.enteredBy[iso];
      if (entry != null) takers.add(entry.by);
      final future = iso.compareTo(today) > 0;
      String firstIn() {
        if (row == null) return '';
        if (row.status == AttendanceStatus.present) {
          return formatAttendanceTime(row.start);
        }
        if (row.status == AttendanceStatus.rest) return '';
        return attendanceStatusLabel(row.status).active(language);
      }

      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: holiday ? AccountsV2Colors.neu : null,
          ),
          children: [
            for (final (text, bold) in [
              (DateFormat('d MMM').format(date), false),
              (DateFormat('EEEE').format(date), false),
              (
                firstIn(),
                row != null && row.status != AttendanceStatus.present,
              ),
              (formatAttendanceTime(row?.breakStart), false),
              (formatAttendanceTime(row?.breakFinish), false),
              (formatAttendanceTime(row?.finish), false),
              (formatAttendanceHours(m?.normalOvertime ?? 0), false),
              (formatAttendanceHours(m?.holidayOvertime ?? 0), false),
              (
                row == null ? '' : (row.workLabel ?? sheet.crew.workLabel),
                false,
              ),
              (
                future ? '' : _statusText(sheet, iso, row, holiday, language),
                false,
              ),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  text,
                  style: bold
                      ? cell.copyWith(fontWeight: FontWeight.w700)
                      : cell,
                ),
              ),
          ],
        ),
      );
      if (date.weekday == DateTime.saturday || date == last) {
        rows.add(
          TableRow(
            children: [
              for (var i = 0; i < 8; i++) const SizedBox(),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  AS.t(AS.paperSiteInCharge, language, {
                    'names': takers.isEmpty ? '—' : takers.join(', '),
                  }),
                  style: v2Style(11, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(),
            ],
          ),
        );
        takers.clear();
      }
    }
    rows.add(
      TableRow(
        decoration: const BoxDecoration(color: AccountsV2Colors.tableHead),
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(AS.t(AS.paperTotal, language), style: head),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              AS.t(AS.paperTotalLine, language, {
                'n': totals.presentDays,
                'h': formatAttendanceHours(totals.regular, zeroAsDash: true),
              }),
              style: head,
            ),
          ),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              formatAttendanceHours(totals.normal, zeroAsDash: true),
              style: head,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              formatAttendanceHours(totals.holiday, zeroAsDash: true),
              style: head,
            ),
          ),
          const SizedBox(),
          const SizedBox(),
        ],
      ),
    );

    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: v2Style(12.5, color: AccountsV2Colors.mut),
            ),
          ),
          Expanded(
            child: Text(value, style: v2Style(12.5, weight: FontWeight.w700)),
          ),
        ],
      ),
    );

    return AccountsV2Panel(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                AS.t(AS.paperTitle, language),
                style: v2Style(17, weight: FontWeight.w800, letterSpacing: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            field(AS.t(AS.paperName, language), worker.worker.name),
            field(
              AS.t(AS.paperMonth, language),
              attendanceMonthYear(sheet.month.month),
            ),
            field(AS.t(AS.paperEmpId, language), worker.worker.number),
            field(
              AS.t(AS.paperDesignation, language),
              worker.worker.designation,
            ),
            field(
              AS.t(AS.paperCrew, language),
              '${sheet.crew.name} · ${sheet.crew.workLabel}',
            ),
            const SizedBox(height: 10),
            Table(
              border: TableBorder.all(color: AccountsV2Colors.line),
              columnWidths: const {
                0: FixedColumnWidth(70),
                1: FixedColumnWidth(96),
                2: FixedColumnWidth(84),
                3: FixedColumnWidth(76),
                4: FixedColumnWidth(76),
                5: FixedColumnWidth(76),
                6: FixedColumnWidth(48),
                7: FixedColumnWidth(48),
                8: FlexColumnWidth(),
                9: FixedColumnWidth(118),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: rows,
            ),
          ],
        ),
      ),
    );
  }
}

/// Phones: a card with the month's totals and one line per day.
class _PhoneSheet extends StatelessWidget {
  const _PhoneSheet({
    required this.sheet,
    required this.worker,
    required this.language,
  });

  final AttendanceMonthSheet sheet;
  final AttendanceSheetWorker worker;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final totals = _totals(sheet, worker);
    final today = attendanceLocalToday();
    final byDate = {for (final d in worker.days) d.date: d.row};
    final days = [
      for (final day in sheet.month.days)
        if (day.date.compareTo(today) <= 0) day,
    ].reversed.toList();
    return AccountsV2Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountsV2CardHead(
            title:
                '${worker.worker.name} · ${attendanceMonthYear(sheet.month.month)}',
            icon: 'doc',
            subtitle: '${worker.worker.number} · ${worker.worker.designation}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: AccountsV2Grid(
              columns: 2,
              children: [
                AccountsV2MiniStat(
                  label: AS.t(AS.present, language),
                  value: '${totals.presentDays}',
                  caption: '',
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.colNormal, language),
                  value: formatAttendanceHours(
                    totals.regular,
                    zeroAsDash: true,
                  ),
                  caption: '',
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.colOtNormal, language),
                  value: formatAttendanceHours(totals.normal, zeroAsDash: true),
                  caption: '',
                  tone: AccountsV2ValueTone.warn,
                ),
                AccountsV2MiniStat(
                  label: AS.t(AS.colOtHoliday, language),
                  value: formatAttendanceHours(
                    totals.holiday,
                    zeroAsDash: true,
                  ),
                  caption: '',
                  tone: AccountsV2ValueTone.vio,
                ),
              ],
            ),
          ),
          for (final day in days)
            Builder(
              builder: (context) {
                final row = byDate[day.date];
                final summary = row == null
                    ? (day.holiday
                          ? AS.t(AS.restDay, language)
                          : AS.t(AS.dayNone, language))
                    : attendanceRowSummary(
                        row,
                        holiday: day.holiday,
                        language: language,
                      );
                return Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AccountsV2Colors.line2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          attendanceShortDate(day.date),
                          style: v2Style(12, weight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          summary,
                          style: v2Style(
                            12.5,
                            color: row == null && !day.holiday
                                ? AccountsV2Colors.bad
                                : AccountsV2Colors.ink2,
                          ),
                        ),
                      ),
                      Text(
                        _statusText(
                          sheet,
                          day.date,
                          row,
                          day.holiday,
                          language,
                        ),
                        style: v2Style(11.5, color: AccountsV2Colors.mut),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
