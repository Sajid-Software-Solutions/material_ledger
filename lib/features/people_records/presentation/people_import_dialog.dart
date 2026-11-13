/// People — import the Staff Documents & Passes tracker.
///
/// The device reads the workbook (people, their documents and gate passes),
/// the server previews what would change, and Import applies every person
/// or none. A row the server or the device could not read blocks the
/// import until the file is fixed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_boq_workbook_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../shared/services/yorks_v1_boq_workbook_service.dart';
import '../../../shared/services/yorks_v1_people_workbook.dart';
import 'people_kit.dart';

/// Returns true when people were imported.
Future<bool?> showPeopleImportDialog(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (_) => const _PeopleImportDialog(),
);

enum _Stage { pick, reading, checking, preview, importing }

class _PeopleImportDialog extends ConsumerStatefulWidget {
  const _PeopleImportDialog();

  @override
  ConsumerState<_PeopleImportDialog> createState() =>
      _PeopleImportDialogState();
}

class _PeopleImportDialogState extends ConsumerState<_PeopleImportDialog> {
  _Stage _stage = _Stage.pick;
  String? _fileName;
  PeopleTrackerRead? _read;
  Map<String, Object?>? _payload;
  PeopleImportResult? _preview;
  String? _error;
  String? _key;

  static String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _choose(AppLanguage language) async {
    final file = await ref
        .read(yorksV1BoqWorkbookFileServiceProvider)
        .selectWorkbook();
    if (file == null || !mounted) return;
    setState(() {
      _stage = _Stage.reading;
      _error = null;
      _preview = null;
      _key = null;
      _fileName = file.fileName;
    });
    try {
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: file.bytes,
        fileName: file.fileName,
      );
      final read = peopleReadTracker(workbook);
      if (!read.readable || read.people.length > peopleImportMaxPeople) {
        setState(() {
          _stage = _Stage.pick;
          _error = PS.t(PS.noStaffSheet, language);
        });
        return;
      }
      final payload = read.toPayload(
        sourceName: file.fileName,
        joiningDate: _today(),
      );
      setState(() {
        _read = read;
        _payload = payload;
        _stage = _Stage.checking;
      });
      final preview = await ref
          .read(yorksV1PeopleRepositoryProvider)
          .previewImport(payload);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _stage = _Stage.preview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.pick;
        _error = peopleErrorText(error, language);
      });
    }
  }

  Future<void> _import(AppLanguage language) async {
    final payload = _payload;
    if (payload == null) return;
    setState(() {
      _stage = _Stage.importing;
      _error = null;
    });
    _key ??= const Uuid().v4();
    try {
      final result = await ref
          .read(yorksV1PeopleRepositoryProvider)
          .import(payload, idempotencyKey: _key!);
      if (!mounted) return;
      peopleToast(
        context,
        PS.t(PS.importDone, language, {
          'n': result.newCount,
          'u': result.updateCount,
        }),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.preview;
        _error = peopleErrorText(error, language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final busy =
        _stage == _Stage.reading ||
        _stage == _Stage.checking ||
        _stage == _Stage.importing;
    final read = _read;
    final preview = _preview;
    final deviceIssues = read?.issueCount ?? 0;
    final blocked =
        preview != null && (preview.hasProblems || deviceIssues > 0);
    final nothing =
        preview != null &&
        !blocked &&
        preview.newCount + preview.updateCount == 0;
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      key: const ValueKey('people-import-dialog'),
      insetPadding: EdgeInsets.all(width < 600 ? AppSpacing.sm : AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.blueContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.upload_file_outlined,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      PS.t(PS.importExcel, language),
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      PS.t(PS.importIntro, language),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    if (_fileName != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: PeoplePill(
                          icon: Icons.description_outlined,
                          label: _fileName!,
                        ),
                      ),
                    ],
                    if (busy) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const LinearProgressIndicator(),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        PS.t(switch (_stage) {
                          _Stage.reading => PS.reading,
                          _Stage.checking => PS.checking,
                          _ => PS.importing,
                        }, language),
                        style: AppTypography.bodySmall,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Banner(
                        key: const ValueKey('people-import-error'),
                        text: _error!,
                        tone: PeopleDocumentStatus.expired,
                      ),
                    ],
                    if (read != null && preview != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _ReadSummary(read: read, language: language),
                      const SizedBox(height: AppSpacing.md),
                      _PreviewCounts(preview: preview, language: language),
                      const SizedBox(height: AppSpacing.md),
                      if (blocked)
                        _Banner(
                          key: const ValueKey('people-import-blocked'),
                          text: PS.t(PS.importBlocked, language),
                          tone: PeopleDocumentStatus.expired,
                        )
                      else if (nothing)
                        _Banner(
                          text: PS.t(PS.importNothing, language),
                          tone: PeopleDocumentStatus.ok,
                        ),
                      const SizedBox(height: AppSpacing.md),
                      _PreviewRows(
                        read: read,
                        preview: preview,
                        language: language,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(PS.t(PS.cancel, language)),
                  ),
                  if (preview == null)
                    FilledButton.icon(
                      key: const ValueKey('people-import-choose'),
                      onPressed: busy ? null : () => _choose(language),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(PS.t(PS.chooseFile, language)),
                    )
                  else ...[
                    OutlinedButton.icon(
                      key: const ValueKey('people-import-choose-again'),
                      onPressed: busy ? null : () => _choose(language),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(PS.t(PS.chooseFile, language)),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('people-import-commit'),
                      onPressed: busy || blocked || nothing
                          ? null
                          : () => _import(language),
                      icon: _stage == _Stage.importing
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        PS.t(
                          _stage == _Stage.importing
                              ? PS.importing
                              : PS.importAction,
                          language,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.tone});

  final String text;
  final PeopleDocumentStatus tone;

  @override
  Widget build(BuildContext context) {
    final colors = peopleStatusColors(tone);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.color.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            tone == PeopleDocumentStatus.ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 19,
            color: colors.color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: colors.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the device read from the workbook.
class _ReadSummary extends StatelessWidget {
  const _ReadSummary({required this.read, required this.language});

  final PeopleTrackerRead read;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final staff = read.people
        .where((person) => person.category == PeopleCategory.staff)
        .length;
    final joined = read.passMatches
        .where((match) => match.matchedName != null && !match.added)
        .length;
    final added = read.passMatches.where((match) => match.added).length;
    final lines = [
      (
        Icons.groups_outlined,
        PS.t(PS.readPeople, language, {
          'n': read.people.length,
          's': staff,
          'l': read.people.length - staff,
        }),
      ),
      if (joined > 0)
        (
          Icons.verified_user_outlined,
          PS.t(PS.readPasses, language, {'n': joined}),
        ),
      if (added > 0)
        (
          Icons.person_add_alt_1_outlined,
          PS.t(PS.readAdded, language, {'n': added}),
        ),
      if (read.skippedRows.isNotEmpty)
        (
          Icons.shield_outlined,
          PS.t(PS.readSkipped, language, {'n': read.skippedRows.length}),
        ),
      if (read.vehicles.isNotEmpty)
        (
          Icons.local_shipping_outlined,
          PS.t(PS.readVehicles, language, {'n': read.vehicles.length}),
        ),
      if (read.issueCount > 0)
        (
          Icons.error_outline_rounded,
          PS.t(PS.readIssues, language, {'n': read.issueCount}),
        ),
    ];
    return Column(
      key: const ValueKey('people-import-read'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, text) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.inkSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(text, style: AppTypography.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PreviewCounts extends StatelessWidget {
  const _PreviewCounts({required this.preview, required this.language});

  final PeopleImportResult preview;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (PS.pNew, preview.newCount, AppColors.blue, AppColors.blueContainer),
      (
        PS.pUpdate,
        preview.updateCount,
        AppColors.purple,
        AppColors.purpleContainer,
      ),
      (
        PS.pUnchanged,
        preview.unchangedCount,
        AppColors.neutralText,
        AppColors.neutralContainer,
      ),
      (
        PS.pProblem,
        preview.problemCount,
        AppColors.error,
        AppColors.errorContainer,
      ),
    ];
    return Column(
      key: const ValueKey('people-import-counts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, value, fg, bg) in tiles)
              Container(
                constraints: const BoxConstraints(minWidth: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PS.t(label, language),
                      style: AppTypography.labelMedium.copyWith(color: fg),
                    ),
                    Text(
                      '$value',
                      style: AppTypography.headlineSmall.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          PS.t(PS.docsSummary, language, {
            'a': preview.documentsNew,
            'r': preview.documentsRenewed,
            'u': preview.documentsUpdated,
          }),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Every person that would change or has a problem.
class _PreviewRows extends StatelessWidget {
  const _PreviewRows({
    required this.read,
    required this.preview,
    required this.language,
  });

  final PeopleTrackerRead read;
  final PeopleImportResult preview;
  final AppLanguage language;

  String _problem(String code) => PS.t(switch (code) {
    'name' => PS.probName,
    'company' => PS.probCompany,
    'repeated' => PS.probRepeated,
    'ambiguous' => PS.probAmbiguous,
    'document' => PS.probDocument,
    _ => PS.probDate,
  }, language);

  String _change(String code) {
    final parts = code.split(':');
    if (parts.length == 2) {
      final kind = peopleKindLabel(
        PeopleDocumentKind.from(parts.first),
        language,
      );
      return '$kind · ${PS.t(switch (parts.last) {
        'new' => PS.add,
        'renewed' => PS.renew,
        _ => PS.edit,
      }, language).toLowerCase()}';
    }
    return code == 'profession'
        ? PS.t(PS.colProfession, language)
        : PS.t(PS.personal, language);
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final (index, row) in preview.rows.indexed)
        if (row.action != 'unchanged' ||
            (index < read.people.length &&
                read.people[index].issues.isNotEmpty))
          (index, row),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('people-import-rows'),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (position, (index, row)) in rows.take(300).indexed)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: position.isEven
                    ? AppColors.surfaceContainerLowest
                    : AppColors.surfaceContainerLow,
                border: position == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.line)),
              ),
              child: () {
                final person = index < read.people.length
                    ? read.people[index]
                    : null;
                final problems = [
                  ...row.problems.map(_problem),
                  if (person != null && person.issues.isNotEmpty)
                    PS.t(PS.probDate, language),
                ];
                final (actionLabel, tone) = switch (row.action) {
                  'new' => (PS.pNew, PeopleDocumentStatus.noExpiry),
                  'update' => (PS.pUpdate, PeopleDocumentStatus.expiring),
                  'problem' => (PS.pProblem, PeopleDocumentStatus.expired),
                  _ => (PS.pUnchanged, PeopleDocumentStatus.ok),
                };
                final colors = problems.isNotEmpty
                    ? peopleStatusColors(PeopleDocumentStatus.expired)
                    : peopleStatusColors(tone);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${row.row ?? ''}',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                row.name,
                                style: AppTypography.labelLarge.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (person?.origin ==
                                  PeopleTrackerOrigin.passSheet)
                                PeoplePill(
                                  label: PS.t(PS.fromPasses, language),
                                  color: AppColors.warning,
                                  background: AppColors.warningContainer,
                                ),
                            ],
                          ),
                          Text(
                            [
                              row.company,
                              peopleCategoryLabel(row.category, language),
                            ].join(' · '),
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            problems.isNotEmpty
                                ? problems.join(' · ')
                                : row.action == 'new'
                                ? [
                                    for (final document
                                        in person?.documents ??
                                            const <PeopleTrackerDocument>[])
                                      peopleKindLabel(document.kind, language),
                                  ].join(', ')
                                : row.changes.map(_change).join(', '),
                            style: AppTypography.bodySmall.copyWith(
                              color: problems.isNotEmpty
                                  ? AppColors.error
                                  : AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PeoplePill(
                      label: PS.t(
                        problems.isNotEmpty ? PS.pProblem : actionLabel,
                        language,
                      ),
                      color: colors.color,
                      background: colors.background,
                    ),
                  ],
                );
              }(),
            ),
        ],
      ),
    );
  }
}
