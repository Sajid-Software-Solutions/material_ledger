/// People — one person's record, laid out like a Material Request record:
/// header with state and commands, what needs attention, the documents
/// table (edit, renew, end), personal details, previous documents and the
/// full history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/app_strings.dart';
import '../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_feature_flags_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../shared/models/yorks_v1_my_record_strings.dart';
import 'people_kit.dart';
import 'person_account.dart';
import 'person_attachments.dart';
import 'person_document_dialog.dart';

class PeoplePersonScreen extends ConsumerWidget {
  const PeoplePersonScreen({super.key, required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final person = ref.watch(yorksV1PeoplePersonProvider(workerId));
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: person.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: PeopleMessage(
            icon: Icons.cloud_off_outlined,
            title: peopleErrorText(error, language),
            action: PS.t(PS.retry, language),
            onPressed: () =>
                ref.invalidate(yorksV1PeoplePersonProvider(workerId)),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(yorksV1PeoplePersonProvider(workerId)),
          child: _PersonBody(person: data, language: language),
        ),
      ),
    );
  }
}

class _PersonBody extends ConsumerWidget {
  const _PersonBody({required this.person, required this.language});

  final PeoplePerson person;
  final AppLanguage language;

  Future<void> _document(
    BuildContext context,
    WidgetRef ref, {
    PeopleDocument? document,
    bool renew = false,
    PeopleDocumentKind? kind,
  }) async {
    final saved = await showPeopleDocumentDialog(
      context,
      person: person,
      document: document,
      renew: renew,
      kind: kind,
    );
    if (saved == true) yorksV1RefreshPeople(ref, workerId: person.id);
  }

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    PeopleDocument document,
  ) async {
    final ended = await showPeopleEndDocumentDialog(
      context,
      person: person,
      document: document,
    );
    if (ended == true) yorksV1RefreshPeople(ref, workerId: person.id);
  }

  /// Attaches a copy of one document.
  Future<void> _attach(
    BuildContext context,
    WidgetRef ref,
    PeopleDocument document,
  ) async {
    final added = await showPeopleAttachmentDialog(
      context,
      person: person,
      documentId: document.id,
    );
    if (added == true) yorksV1RefreshPeople(ref, workerId: person.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final attached =
        ref
            .watch(yorksV1PeopleAttachmentsProvider(person.id))
            .valueOrNull
            ?.byDocument ??
        const <String, int>{};
    final wide = width >= 1100;
    final horizontal = width >= AppSpacing.yorksV1DesktopBreakpoint
        ? AppSpacing.xl
        : AppSpacing.md;
    final flags = ref.watch(yorksV1FeatureFlagsProvider);
    final documents = _DocumentsSection(
      person: person,
      language: language,
      onAdd: (kind) => _document(context, ref, kind: kind),
      onEdit: (document) => _document(context, ref, document: document),
      onRenew: (document) =>
          _document(context, ref, document: document, renew: true),
      onEnd: (document) => _end(context, ref, document),
      onAttach: (document) => _attach(context, ref, document),
      attached: attached,
    );
    final details = _DetailsCard(
      person: person,
      language: language,
      canTakeAttendance: flags.workforceAttendanceV2,
    );
    final account = PeopleAccountSection(person: person, language: language);
    return ListView(
      key: const ValueKey('people-person'),
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
                    key: const ValueKey('people-person-back'),
                    onPressed: () => context.go(peoplePath),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(PS.t(PS.title, language)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _Header(
                  person: person,
                  language: language,
                  onAdd: () => _document(context, ref),
                ),
                const SizedBox(height: AppSpacing.md),
                _StatusCard(person: person, language: language),
                if (person.notes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  PeopleNotesSection(person: person, language: language),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: documents),
                      const SizedBox(width: AppSpacing.lg),
                      SizedBox(
                        width: 380,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: AppSpacing.lg),
                            account,
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  details,
                  const SizedBox(height: AppSpacing.lg),
                  account,
                  const SizedBox(height: AppSpacing.lg),
                  documents,
                ],
                const SizedBox(height: AppSpacing.lg),
                PeopleAttachmentsSection(person: person, language: language),
                const SizedBox(height: AppSpacing.lg),
                _PreviousDocuments(person: person, language: language),
                const SizedBox(height: AppSpacing.md),
                _History(person: person, language: language, expanded: wide),
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
    required this.person,
    required this.language,
    required this.onAdd,
  });

  final PeoplePerson person;
  final AppLanguage language;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final attention = peopleStatusColors(person.attention);
    final badges = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          person.name,
          style: AppTypography.headlineSmall.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        PeoplePill(
          icon: Icons.tag_rounded,
          label: person.number,
          color: AppColors.inkSecondary,
          background: AppColors.surfaceContainerLow,
        ),
        PeoplePill(
          icon: person.category == PeopleCategory.staff
              ? Icons.badge_outlined
              : Icons.engineering_outlined,
          label: peopleCategoryLabel(person.category, language),
          color: person.category == PeopleCategory.staff
              ? AppColors.purple
              : AppColors.success,
          background: person.category == PeopleCategory.staff
              ? AppColors.purpleContainer
              : AppColors.successContainer,
        ),
        PeoplePill(
          label: person.attention == PeopleDocumentStatus.ok
              ? PS.t(PS.statusOk, language)
              : peopleStatusLabel(person.attention, language),
          color: attention.color,
          background: attention.background,
        ),
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badges,
        if (person.arabicName != null) ...[
          const SizedBox(height: 2),
          Text(
            person.arabicName!,
            textDirection: TextDirection.rtl,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            person.company,
            if (person.position != 'Not recorded') person.position,
            if (person.crewName != null) person.crewName!,
          ].join(' · '),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
        ),
      ],
    );
    if (!person.canManage) return heading;
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('people-person-edit'),
          onPressed: () => context.go(peopleEditPath(person.id)),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(PS.t(PS.edit, language)),
        ),
        FilledButton.icon(
          key: const ValueKey('people-person-add-document'),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(PS.t(PS.addDocument, language)),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
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

/// What needs attention, like the Material Request owner card.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.person, required this.language});

  final PeoplePerson person;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final worst = [
      for (final document in person.documents)
        if (document.status.needsAttention && document.expiryDate != null)
          document,
    ]..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
    final first = worst.firstOrNull;
    final next = person.nextExpiry;
    final status = first?.status ?? PeopleDocumentStatus.ok;
    final colors = peopleStatusColors(status);
    final title = first == null
        ? PS.t(PS.allValid, language)
        : PS.t(
            first.status == PeopleDocumentStatus.expired
                ? PS.expiredBanner
                : PS.expiringBanner,
            language,
            {
              'doc': peopleKindLabel(first.kind, language, label: first.label),
              'date': peopleDate(first.expiryDate),
            },
          );
    final detail = [
      if (first != null) peopleDaysText(first, language),
      if (worst.length > 1)
        for (final document in worst.skip(1).take(3))
          '${peopleKindLabel(document.kind, language, label: document.label)} '
              '${peopleDate(document.expiryDate)}',
      if (first == null && next != null)
        PS.t(PS.nextExpiry, language, {
          'doc': peopleKindLabel(next.kind, language, label: next.label),
          'date': peopleDate(next.expiryDate),
        }),
    ].join(' · ');
    return Container(
      key: const ValueKey('people-person-status'),
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
    required this.person,
    required this.language,
    required this.onAdd,
    required this.onEdit,
    required this.onRenew,
    required this.onEnd,
    required this.onAttach,
    this.attached = const {},
  });

  final PeoplePerson person;
  final AppLanguage language;
  final ValueChanged<PeopleDocumentKind> onAdd;
  final ValueChanged<PeopleDocument> onEdit;
  final ValueChanged<PeopleDocument> onRenew;
  final ValueChanged<PeopleDocument> onEnd;
  final ValueChanged<PeopleDocument> onAttach;

  /// How many attachments copy each document, by document id.
  final Map<String, int> attached;

  /// Every held document, then a placeholder for each single kind not held.
  List<(PeopleDocumentKind, PeopleDocument?)> get _rows => [
    for (final kind in PeopleDocumentKind.values)
      if (kind.single)
        (kind, person.current(kind))
      else
        for (final document in person.documents)
          if (document.kind == kind) (kind, document),
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
                      canManage: person.canManage,
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
    Widget head(TranslatableString label, {bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Align(
        alignment: end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Text(
          PS.t(label, language),
          style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
    final rows = _rows;
    return PeopleSurface(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Table(
          key: const ValueKey('people-documents-table'),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppColors.line),
          ),
          columnWidths: const {
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(1.5),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1.6),
            5: FixedColumnWidth(230),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLow,
              ),
              children: [
                head(PS.colDocument),
                head(PS.colNumber),
                head(PS.colIssue),
                head(PS.colExpiry),
                head(PS.colSites),
                head(PS.colAction, end: true),
              ],
            ),
            for (final (kind, document) in rows)
              TableRow(
                key: ValueKey(
                  'people-document-row-${document?.id ?? kind.wire}',
                ),
                children: [
                  cell(
                    Row(
                      children: [
                        Icon(
                          peopleKindIcon(kind),
                          size: 18,
                          color: document == null
                              ? AppColors.mutedLight
                              : AppColors.inkSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            peopleKindLabel(
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
                              'people-document-attached-${document.id}',
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
                              PeopleExpiryCell(
                                document: document,
                                language: language,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                peopleDaysText(document, language),
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
                        canManage: person.canManage,
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

  final PeopleDocumentKind kind;
  final PeopleDocument? document;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<PeopleDocument> onEdit;
  final ValueChanged<PeopleDocument> onRenew;
  final ValueChanged<PeopleDocument> onEnd;
  final ValueChanged<PeopleDocument> onAttach;

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
        key: ValueKey('people-document-add-${kind.wire}'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(PS.t(PS.add, language)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          key: ValueKey('people-document-attach-${doc.id}'),
          icon: Icons.attach_file_rounded,
          tooltip: PS.t(PS.addAttachment, language),
          color: AppColors.blue,
          border: AppColors.line,
          onPressed: () => onAttach(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('people-document-edit-${doc.id}'),
          icon: Icons.edit_outlined,
          tooltip: PS.t(PS.edit, language),
          color: AppColors.blue,
          border: AppColors.line,
          onPressed: () => onEdit(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('people-document-renew-${doc.id}'),
          icon: Icons.autorenew_rounded,
          tooltip: PS.t(PS.renew, language),
          color: AppColors.blue,
          border: AppColors.blue,
          onPressed: () => onRenew(doc),
        ),
        const SizedBox(width: 6),
        _button(
          key: ValueKey('people-document-end-${doc.id}'),
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

  final PeopleDocumentKind kind;
  final PeopleDocument? document;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<PeopleDocument> onEdit;
  final ValueChanged<PeopleDocument> onRenew;
  final ValueChanged<PeopleDocument> onEnd;
  final ValueChanged<PeopleDocument> onAttach;
  final int attached;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    final colors = peopleStatusColors(
      doc?.status ?? PeopleDocumentStatus.noExpiry,
    );
    return PeopleSurface(
      key: ValueKey('people-document-card-${doc?.id ?? kind.wire}'),
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
                  peopleKindIcon(kind),
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
                            peopleKindLabel(kind, language, label: doc?.label),
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (doc != null) ...[
                          const SizedBox(width: 6),
                          RecordAttachmentCount(
                            key: ValueKey('people-document-attached-${doc.id}'),
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
              if (doc != null)
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
              peopleDaysText(doc, language),
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
  const _DetailsCard({
    required this.person,
    required this.language,
    required this.canTakeAttendance,
  });

  final PeoplePerson person;
  final AppLanguage language;
  final bool canTakeAttendance;

  @override
  Widget build(BuildContext context) {
    final facts = [
      (PS.factNumber, person.number),
      (PS.colCompany, person.company),
      (
        PS.colProfession,
        person.position == 'Not recorded' ? '' : person.position,
      ),
      (PS.colIdProfession, person.idProfession ?? ''),
      (PS.factCategory, peopleCategoryLabel(person.category, language)),
      (PS.factArabicName, person.arabicName ?? ''),
      (PS.factDob, peopleDate(person.dateOfBirth)),
      (PS.factUnified, person.unifiedNumber ?? ''),
      (PS.factMobile, person.mobile ?? ''),
      (PS.factJoined, peopleDate(person.joiningDate)),
      (PS.factCrew, person.crewName ?? PS.t(PS.noCrew, language)),
      if (person.sourceNote != null) (PS.factSource, person.sourceNote!),
    ];
    return PeopleSurface(
      key: const ValueKey('people-person-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            PS.t(PS.personal, language),
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
                      child: PeopleFact(
                        label: PS.t(label, language),
                        value: value,
                      ),
                    ),
                ],
              );
            },
          ),
          if (canTakeAttendance && person.crewId != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('people-person-attendance'),
              onPressed: () => context.go(
                '/yorks/workforce/attendance?crew=${Uri.encodeQueryComponent(person.crewId!)}',
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(PS.t(PS.takeAttendance, language)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviousDocuments extends StatelessWidget {
  const _PreviousDocuments({required this.person, required this.language});

  final PeoplePerson person;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (person.previousDocuments.isEmpty) return const SizedBox.shrink();
    return PeopleSurface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: const ValueKey('people-person-previous'),
          leading: const Icon(Icons.history_rounded, color: AppColors.blue),
          title: Text(
            '${PS.t(PS.previous, language)} (${person.previousDocuments.length})',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            for (final document in person.previousDocuments)
              ListTile(
                leading: Icon(
                  peopleKindIcon(document.kind),
                  color: AppColors.muted,
                ),
                title: Text(
                  [
                    peopleKindLabel(
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
    required this.person,
    required this.language,
    required this.expanded,
  });

  final PeoplePerson person;
  final AppLanguage language;
  final bool expanded;

  String _title(PeopleHistoryEntry entry) {
    final values = {
      'name': entry.actorName,
      'doc': entry.kind == null
          ? ''
          : peopleKindLabel(
              PeopleDocumentKind.from(entry.kind),
              language,
            ).toLowerCase(),
    };
    if (entry.entity == 'person' &&
        entry.action == 'updated' &&
        entry.changed.contains('account')) {
      return MyRecordStrings.t(MyRecordStrings.hAccount, language, values);
    }
    final template = switch ((entry.entity, entry.action)) {
      ('person', 'created') => PS.hCreated,
      ('person', 'imported') => PS.hImported,
      ('person', _) => PS.hUpdated,
      ('document', 'created') => PS.hDocCreated,
      ('document', 'renewed') => PS.hDocRenewed,
      ('document', 'ended') => PS.hDocEnded,
      ('attachment', 'removed') => PS.hAttachmentRemoved,
      ('attachment', _) => PS.hAttachmentAdded,
      _ => PS.hDocUpdated,
    };
    return PS.t(template, language, values);
  }

  @override
  Widget build(BuildContext context) => PeopleSurface(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: const ValueKey('people-person-history'),
        initiallyExpanded: expanded,
        leading: const Icon(Icons.timeline_rounded, color: AppColors.blue),
        title: Text(
          PS.t(PS.history, language),
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        children: [
          for (final entry in person.history)
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
