/// Company documents — one record, laid out like a Material Request record:
/// header with its state and commands, what needs attention, the documents
/// table (edit, renew, end), the details, previous documents and the full
/// history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../shared/models/yorks_v1_company_documents.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_company_documents_provider.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'company_attachments.dart';
import 'company_document_dialog.dart';
import 'company_kit.dart';

class CompanyRecordScreen extends ConsumerWidget {
  const CompanyRecordScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final record = ref.watch(yorksV1CompanyRecordProvider(recordId));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: record.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: PeopleMessage(
            icon: Icons.cloud_off_outlined,
            title: companyErrorText(error, language),
            action: PS.t(PS.retry, language),
            onPressed: () =>
                ref.invalidate(yorksV1CompanyRecordProvider(recordId)),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(yorksV1CompanyRecordProvider(recordId)),
          child: _RecordBody(record: data, language: language),
        ),
      ),
    );
  }
}

class _RecordBody extends ConsumerWidget {
  const _RecordBody({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  Future<void> _document(
    BuildContext context,
    WidgetRef ref, {
    CompanyDocument? document,
    bool renew = false,
    CompanyDocumentKind? kind,
  }) async {
    final saved = await showCompanyDocumentDialog(
      context,
      record: record,
      document: document,
      renew: renew,
      kind: kind,
    );
    if (saved == true) yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
  }

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    CompanyDocument document,
  ) async {
    final ended = await showCompanyEndDocumentDialog(
      context,
      record: record,
      document: document,
    );
    if (ended == true) yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
  }

  /// Attaches a copy of one document.
  Future<void> _attach(
    BuildContext context,
    WidgetRef ref,
    CompanyDocument document,
  ) async {
    final added = await showCompanyAttachmentDialog(
      context,
      record: record,
      documentId: document.id,
    );
    if (added == true) yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(yorksV1CompanyDocumentsRepositoryProvider);
    final key = const Uuid().v4();
    final archiving = !record.archived;
    final result = await showAttendanceCommandDialog(
      context,
      language: language,
      title: archiving
          ? CS.t(CS.archiveTitle, language, {'name': record.name})
          : CS.t(CS.restore, language),
      summary: [
        companyKindLabel(record.kind, language),
        record.name,
        if (record.reference != null) record.reference!,
      ].join(' · '),
      body: archiving ? CS.t(CS.archiveBody, language) : null,
      fieldLabel: archiving ? PS.t(PS.reason, language) : null,
      confirmLabel: CS.t(archiving ? CS.archive : CS.restore, language),
      destructive: archiving,
      command: (text) async {
        try {
          await repository.setArchived(
            recordId: record.id,
            archived: archiving,
            reason: text,
            expectedVersion: record.recordVersion,
            idempotencyKey: key,
          );
          return null;
        } catch (error) {
          return companyErrorText(error, language);
        }
      },
    );
    if (result == null || !context.mounted) return;
    peopleToast(
      context,
      CS.t(archiving ? CS.archivedToast : CS.restoredToast, language, {
        'name': record.name,
      }),
    );
    yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final horizontal = width >= AppSpacing.yorksV1DesktopBreakpoint
        ? AppSpacing.xl
        : AppSpacing.md;
    final attached =
        ref
            .watch(yorksV1CompanyAttachmentsProvider(record.id))
            .valueOrNull
            ?.byDocument ??
        const <String, int>{};
    final documents = _DocumentsSection(
      record: record,
      language: language,
      onAdd: (kind) => _document(context, ref, kind: kind),
      onEdit: (document) => _document(context, ref, document: document),
      onRenew: (document) =>
          _document(context, ref, document: document, renew: true),
      onEnd: (document) => _end(context, ref, document),
      onAttach: (document) => _attach(context, ref, document),
      attached: attached,
    );
    final details = _DetailsCard(record: record, language: language);
    return ListView(
      key: const ValueKey('company-record'),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.lg,
        horizontal,
        AppSpacing.xxxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.pageMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('company-record-back'),
                    onPressed: () => context.go(companyPath),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(CS.t(CS.title, language)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _Header(
                  record: record,
                  language: language,
                  onAdd: () => _document(context, ref),
                  onArchive: () => _archive(context, ref),
                ),
                const SizedBox(height: AppSpacing.md),
                if (record.archived)
                  _ArchivedBanner(record: record, language: language)
                else
                  _StatusCard(record: record, language: language),
                const SizedBox(height: AppSpacing.lg),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: documents),
                      const SizedBox(width: AppSpacing.lg),
                      SizedBox(width: 360, child: details),
                    ],
                  )
                else ...[
                  details,
                  const SizedBox(height: AppSpacing.lg),
                  documents,
                ],
                const SizedBox(height: AppSpacing.lg),
                CompanyAttachmentsSection(record: record, language: language),
                const SizedBox(height: AppSpacing.lg),
                _PreviousDocuments(record: record, language: language),
                const SizedBox(height: AppSpacing.md),
                _History(record: record, language: language, expanded: wide),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.record,
    required this.language,
    required this.onAdd,
    required this.onArchive,
  });

  final CompanyRecord record;
  final AppLanguage language;
  final VoidCallback onAdd;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final kindColors = companyKindColors(record.kind);
    final attention = peopleStatusColors(record.attention);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              record.name,
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            PeoplePill(
              icon: companyKindIcon(record.kind),
              label: companyKindLabel(record.kind, language),
              color: kindColors.color,
              background: kindColors.background,
            ),
            if (record.archived)
              PeoplePill(
                icon: Icons.inventory_outlined,
                label: CS.t(CS.archive, language),
                color: AppColors.neutralText,
                background: AppColors.neutralContainer,
              )
            else if (record.documents.isNotEmpty)
              PeoplePill(
                label: peopleStatusLabel(record.attention, language),
                color: attention.color,
                background: attention.background,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            if (record.reference != null)
              '${companyReferenceLabel(record.kind, language)} ${record.reference}',
            if (record.owner != null) record.owner!,
            if (record.kind == CompanyRecordKind.contract &&
                record.details.job != null)
              record.details.job!,
          ].join(' · '),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    );
    if (!record.canManage) return heading;
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('company-record-archive'),
          onPressed: onArchive,
          icon: Icon(
            record.archived
                ? Icons.unarchive_outlined
                : Icons.inventory_outlined,
            size: 18,
          ),
          label: Text(
            CS.t(record.archived ? CS.restore : CS.archive, language),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('company-record-edit'),
          onPressed: () => context.go(companyEditPath(record.id)),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(PS.t(PS.edit, language)),
        ),
        if (!record.archived)
          FilledButton.icon(
            key: const ValueKey('company-record-add-document'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(PS.t(PS.addDocument, language)),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 860
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: AppSpacing.md),
                actions,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.lg),
                actions,
              ],
            ),
    );
  }
}

class _ArchivedBanner extends StatelessWidget {
  const _ArchivedBanner({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('company-record-archived'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.neutralContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Row(
      children: [
        const Icon(Icons.inventory_outlined, color: AppColors.neutralText),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            CS.t(CS.archivedBanner, language, {
              'date': peopleStamp(record.archivedAt),
              'reason': record.archivedReason ?? '',
            }),
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// What needs attention, like the Material Request owner card.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (record.documents.isEmpty) {
      return Container(
        key: const ValueKey('company-record-status'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            const Icon(Icons.post_add_rounded, color: AppColors.muted),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                CS.t(CS.noDocumentsYet, language),
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final worst = [
      for (final document in record.documents)
        if (document.status.needsAttention && document.expiryDate != null)
          document,
    ]..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    final first = worst.firstOrNull;
    final next = record.nextExpiry;
    final status = first?.status ?? PeopleDocumentStatus.ok;
    final colors = peopleStatusColors(status);
    String name(CompanyDocument document) =>
        companyDocumentLabel(document.kind, language, label: document.label);
    final title = first == null
        ? PS.t(PS.allValid, language)
        : PS.t(
            first.status == PeopleDocumentStatus.expired
                ? PS.expiredBanner
                : PS.expiringBanner,
            language,
            {'doc': name(first), 'date': peopleDate(first.expiryDate)},
          );
    final detail = [
      if (first != null) companyDaysText(first.daysLeft, language),
      for (final document in worst.skip(1).take(3))
        '${name(document)} ${peopleDate(document.expiryDate)}',
      if (first == null && next != null)
        PS.t(PS.nextExpiry, language, {
          'doc': companyDocumentLabel(next.kind, language, label: next.label),
          'date': peopleDate(next.expiryDate),
        }),
    ].join(' · ');
    return Container(
      key: const ValueKey('company-record-status'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: status == PeopleDocumentStatus.ok
            ? AppColors.successContainer
            : colors.background,
        border: Border.all(color: colors.color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          Icon(
            status == PeopleDocumentStatus.ok
                ? Icons.verified_rounded
                : status == PeopleDocumentStatus.expired
                ? Icons.error_outline_rounded
                : Icons.schedule_rounded,
            color: colors.color,
            size: 30,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: status == PeopleDocumentStatus.ok
                        ? AppColors.ink
                        : colors.color,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.inkSecondary,
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

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.record,
    required this.language,
    required this.onAdd,
    required this.onEdit,
    required this.onRenew,
    required this.onEnd,
    required this.onAttach,
    this.attached = const {},
  });

  final CompanyRecord record;
  final AppLanguage language;
  final ValueChanged<CompanyDocumentKind> onAdd;
  final ValueChanged<CompanyDocument> onEdit;
  final ValueChanged<CompanyDocument> onRenew;
  final ValueChanged<CompanyDocument> onEnd;
  final ValueChanged<CompanyDocument> onAttach;

  /// How many attachments copy each document, by document id.
  final Map<String, int> attached;

  bool get _canManage => record.canManage && !record.archived;

  /// Every held document, then the usual ones for this kind not yet held.
  List<(CompanyDocumentKind, CompanyDocument?)> get _rows => [
    for (final document in record.documents) (document.kind, document),
    for (final kind in CompanyDocumentKind.expectedFor(record.kind))
      if (record.current(kind) == null) (kind, null),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PeopleSectionHeading(
        title: PS.t(PS.documents, language),
        description: PS.t(PS.documentsDescription, language),
      ),
      const SizedBox(height: AppSpacing.sm),
      LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 760
            ? _table()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (kind, document) in _rows) ...[
                    _DocumentCard(
                      kind: kind,
                      document: document,
                      language: language,
                      canManage: _canManage,
                      onAdd: () => onAdd(kind),
                      onEdit: onEdit,
                      onRenew: onRenew,
                      onEnd: onEnd,
                      onAttach: onAttach,
                      attached: attached[document?.id] ?? 0,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
      ),
    ],
  );

  Widget _table() {
    Widget head(String label, {bool end = false}) => Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Align(
        alignment: end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
    return PeopleSurface(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Table(
          key: const ValueKey('company-documents-table'),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppColors.line),
          ),
          columnWidths: const {
            0: FlexColumnWidth(1.8),
            1: FlexColumnWidth(1.4),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1.4),
            5: FixedColumnWidth(230),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLow,
              ),
              children: [
                head(PS.t(PS.colDocument, language)),
                head(PS.t(PS.colNumber, language)),
                head(PS.t(PS.colIssue, language)),
                head(PS.t(PS.colExpiry, language)),
                head(PS.t(PS.colSites, language)),
                head(PS.t(PS.colAction, language), end: true),
              ],
            ),
            for (final (kind, document) in _rows)
              TableRow(
                key: ValueKey(
                  'company-document-row-${document?.id ?? kind.wire}',
                ),
                children: [
                  cell(
                    Row(
                      children: [
                        Icon(
                          companyDocumentIcon(kind),
                          size: 18,
                          color: document == null
                              ? AppColors.mutedLight
                              : AppColors.inkSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            companyDocumentLabel(
                              kind,
                              language,
                              label: document?.label,
                            ),
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w800,
                              color: document == null
                                  ? AppColors.muted
                                  : AppColors.ink,
                            ),
                          ),
                        ),
                        if (document != null) ...[
                          const SizedBox(width: 6),
                          RecordAttachmentCount(
                            key: ValueKey(
                              'company-document-attached-${document.id}',
                            ),
                            count: attached[document.id] ?? 0,
                            language: language,
                          ),
                        ],
                      ],
                    ),
                  ),
                  cell(
                    Text(
                      document == null
                          ? PS.t(PS.notRecorded, language)
                          : document.number ?? '—',
                      style: AppTypography.bodySmall.copyWith(
                        color: document == null
                            ? AppColors.muted
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  cell(
                    Text(
                      document?.issueDate == null
                          ? '—'
                          : peopleDate(document!.issueDate),
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  cell(
                    document == null
                        ? const Text('—')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CompanyExpiryCell(
                                document: document.expiryDate == null
                                    ? null
                                    : document,
                                language: language,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                companyDaysText(document.daysLeft, language),
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                  ),
                  cell(
                    Text(
                      document?.sites ?? (document?.notes ?? '—'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _RowActions(
                        kind: kind,
                        document: document,
                        language: language,
                        canManage: _canManage,
                        onAdd: () => onAdd(kind),
                        onEdit: onEdit,
                        onRenew: onRenew,
                        onEnd: onEnd,
                        onAttach: onAttach,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.kind,
    required this.document,
    required this.language,
    required this.canManage,
    required this.onAdd,
    required this.onEdit,
    required this.onRenew,
    required this.onEnd,
    required this.onAttach,
  });

  final CompanyDocumentKind kind;
  final CompanyDocument? document;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<CompanyDocument> onEdit;
  final ValueChanged<CompanyDocument> onRenew;
  final ValueChanged<CompanyDocument> onEnd;
  final ValueChanged<CompanyDocument> onAttach;

  Widget _button({
    required Key key,
    required IconData icon,
    required String tooltip,
    required Color color,
    required Color border,
    required VoidCallback onPressed,
  }) => IconButton(
    key: key,
    tooltip: tooltip,
    icon: Icon(icon, color: color, size: 20),
    style: IconButton.styleFrom(
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      minimumSize: const Size(40, 40),
    ),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    if (!canManage) return const SizedBox.shrink();
    final doc = document;
    if (doc == null) {
      return TextButton.icon(
        key: ValueKey('company-document-add-${kind.wire}'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(PS.t(PS.add, language)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          key: ValueKey('company-document-attach-${doc.id}'),
          icon: Icons.attach_file_rounded,
          tooltip: PS.t(PS.addAttachment, language),
          color: AppColors.blue,
          border: AppColors.line,
          onPressed: () => onAttach(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('company-document-edit-${doc.id}'),
          icon: Icons.edit_outlined,
          tooltip: PS.t(PS.edit, language),
          color: AppColors.blue,
          border: AppColors.line,
          onPressed: () => onEdit(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('company-document-renew-${doc.id}'),
          icon: Icons.autorenew_rounded,
          tooltip: PS.t(PS.renew, language),
          color: AppColors.blue,
          border: AppColors.blue,
          onPressed: () => onRenew(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('company-document-end-${doc.id}'),
          icon: Icons.close_rounded,
          tooltip: PS.t(PS.end, language),
          color: AppColors.error,
          border: AppColors.error,
          onPressed: () => onEnd(doc),
        ),
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.kind,
    required this.document,
    required this.language,
    required this.canManage,
    required this.onAdd,
    required this.onEdit,
    required this.onRenew,
    required this.onEnd,
    required this.onAttach,
    this.attached = 0,
  });

  final CompanyDocumentKind kind;
  final CompanyDocument? document;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<CompanyDocument> onEdit;
  final ValueChanged<CompanyDocument> onRenew;
  final ValueChanged<CompanyDocument> onEnd;
  final ValueChanged<CompanyDocument> onAttach;
  final int attached;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    final colors = peopleStatusColors(
      doc?.status ?? PeopleDocumentStatus.noExpiry,
    );
    return PeopleSurface(
      key: ValueKey('company-document-card-${doc?.id ?? kind.wire}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: doc == null
                      ? AppColors.surfaceContainerLow
                      : colors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  companyDocumentIcon(kind),
                  size: 19,
                  color: doc == null ? AppColors.mutedLight : colors.color,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            companyDocumentLabel(
                              kind,
                              language,
                              label: doc?.label,
                            ),
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (doc != null) ...[
                          const SizedBox(width: 6),
                          RecordAttachmentCount(
                            key: ValueKey(
                              'company-document-attached-${doc.id}',
                            ),
                            count: attached,
                            language: language,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      doc == null
                          ? PS.t(PS.notRecorded, language)
                          : [
                              if (doc.number != null) doc.number!,
                              if (doc.expiryDate != null)
                                peopleDate(doc.expiryDate),
                            ].join(' · '),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (doc != null && doc.expiryDate != null)
                PeopleStatusPill(status: doc.status, language: language),
            ],
          ),
          if (doc?.sites != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(doc!.sites!, style: AppTypography.bodySmall),
          ],
          if (doc != null && doc.expiryDate != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              companyDaysText(doc.daysLeft, language),
              style: AppTypography.labelSmall.copyWith(color: colors.color),
            ),
          ],
          if (canManage) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _RowActions(
                kind: kind,
                document: doc,
                language: language,
                canManage: canManage,
                onAdd: onAdd,
                onEdit: onEdit,
                onRenew: onRenew,
                onEnd: onEnd,
                onAttach: onAttach,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    String count(int? value) => value?.toString() ?? '';
    final facts = <(String, String)>[
      (CS.t(CS.whatIsIt, language), companyKindLabel(record.kind, language)),
      (companyReferenceLabel(record.kind, language), record.reference ?? ''),
      if (record.kind != CompanyRecordKind.entity)
        (companyOwnerLabel(record.kind, language), record.owner ?? ''),
      if (record.kind == CompanyRecordKind.contract) ...[
        (CS.t(CS.job, language), record.details.job ?? ''),
        (CS.t(CS.people, language), count(record.details.people)),
        (CS.t(CS.vehicles, language), count(record.details.vehicles)),
        (CS.t(CS.appliedPeople, language), count(record.details.appliedPeople)),
        (
          CS.t(CS.appliedVehicles, language),
          count(record.details.appliedVehicles),
        ),
      ],
      if (record.notes != null) (CS.t(CS.notes, language), record.notes!),
      if (record.sourceNote != null)
        (PS.t(PS.factSource, language), record.sourceNote!),
    ];
    return PeopleSurface(
      key: const ValueKey('company-record-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            CS.t(CS.details, language),
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 3 : 2;
              const gap = AppSpacing.md;
              final width =
                  (constraints.maxWidth - (columns - 1) * gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: AppSpacing.md,
                children: [
                  for (final (label, value) in facts)
                    SizedBox(
                      width: width,
                      child: PeopleFact(label: label, value: value),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreviousDocuments extends StatelessWidget {
  const _PreviousDocuments({required this.record, required this.language});

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (record.previousDocuments.isEmpty) return const SizedBox.shrink();
    return PeopleSurface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: const ValueKey('company-record-previous'),
          leading: const Icon(Icons.history_rounded, color: AppColors.blue),
          title: Text(
            '${PS.t(PS.previous, language)} (${record.previousDocuments.length})',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            for (final document in record.previousDocuments)
              ListTile(
                dense: true,
                leading: Icon(
                  companyDocumentIcon(document.kind),
                  color: AppColors.muted,
                ),
                title: Text(
                  [
                    companyDocumentLabel(
                      document.kind,
                      language,
                      label: document.label,
                    ),
                    if (document.number != null) document.number!,
                    if (document.expiryDate != null)
                      peopleDate(document.expiryDate),
                  ].join(' · '),
                ),
                subtitle: Text(
                  PS.t(PS.endedOn, language, {
                    'date': peopleStamp(document.endedAt),
                    'reason': document.endedReason == 'renewed'
                        ? PS.t(PS.renewedReason, language)
                        : document.endedReason ?? '',
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({
    required this.record,
    required this.language,
    required this.expanded,
  });

  final CompanyRecord record;
  final AppLanguage language;
  final bool expanded;

  String _title(CompanyHistoryEntry entry) {
    final values = {
      'name': entry.actorName,
      'doc': entry.kind == null
          ? ''
          : companyDocumentLabel(
              CompanyDocumentKind.from(entry.kind),
              language,
              label: entry.label,
            ),
    };
    final template = switch ((entry.entity, entry.action)) {
      ('record', 'created') => CS.hCreated,
      ('record', 'imported') => PS.hImported,
      ('record', 'archived') => CS.hArchived,
      ('record', 'restored') => CS.hRestored,
      ('record', _) => PS.hUpdated,
      ('document', 'created') => PS.hDocCreated,
      ('document', 'renewed') => PS.hDocRenewed,
      ('document', 'ended') => PS.hDocEnded,
      ('attachment', 'removed') => PS.hAttachmentRemoved,
      ('attachment', _) => PS.hAttachmentAdded,
      _ => PS.hDocUpdated,
    };
    return CS.t(template, language, values);
  }

  @override
  Widget build(BuildContext context) => PeopleSurface(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: const ValueKey('company-record-history'),
        initiallyExpanded: expanded,
        leading: const Icon(Icons.timeline_rounded, color: AppColors.blue),
        title: Text(
          PS.t(PS.history, language),
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        children: [
          for (final entry in record.history)
            ListTile(
              dense: true,
              title: Text(
                _title(entry),
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                [
                  YorksV1AuditStrings.roleLabel(entry.actorRole, language),
                  peopleStamp(entry.at),
                  if (entry.reason != null) '“${entry.reason}”',
                ].join(' · '),
              ),
            ),
        ],
      ),
    ),
  );
}
