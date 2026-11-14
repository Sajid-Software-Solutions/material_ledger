/// My Yorks from the People record (PRODUCT_DECISIONS section 54): one card
/// with the person's identity, their own documents, who they are at Yorks
/// and their notes to HR/PRO.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_my_record_strings.dart';
import '../../../../shared/models/yorks_v1_people.dart';
import '../../../../shared/models/yorks_v1_profile_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../people_records/presentation/people_kit.dart';
import 'yorks_my_profile_components.dart';

typedef _M = MyRecordStrings;

/// How the person's documents stand, for the header.
({String label, Color color}) yorksMyDocumentsSummary(
  PeopleMinePerson person,
  AppLanguage language,
) => switch (person.attention) {
  PeopleDocumentStatus.expired => (
    label: _M.t(_M.documentsExpired, language),
    color: const Color(0xFFFFB4AB),
  ),
  PeopleDocumentStatus.expiring => (
    label: _M.t(_M.documentsExpiring, language, {'n': person.needingAttention}),
    color: const Color(0xFFFFD580),
  ),
  _ => (
    label: _M.t(_M.documentsValid, language),
    color: const Color(0xFF65E6B5),
  ),
};

/// Whether HR/PRO has filled a field in; "Not recorded" is the placeholder
/// a new record carries until they do.
bool yorksMyRecorded(String value) =>
    value.trim().isNotEmpty && value.trim() != 'Not recorded';

/// "Site Engineer · Staff", leaving out a position never recorded.
String yorksMyPositionLine(PeopleMinePerson person, AppLanguage language) => [
  if (yorksMyRecorded(person.position)) person.position,
  peopleCategoryLabel(person.category, language),
].join(' · ');

/// "WR-000137 · Yorks (Abu Dhabi)", leaving out a company never recorded.
String yorksMyRecordLine(PeopleMinePerson person) => [
  person.number,
  if (yorksMyRecorded(person.company)) person.company,
].join(' · ');

/// The person's identity on top and their own record below, in one card.
class YorksMyProfileCard extends StatelessWidget {
  const YorksMyProfileCard({
    super.key,
    required this.header,
    this.children = const [],
  });

  /// A [YorksIdentityHero] built with `attached: true`.
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('my-yorks-profile-card'),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A0D2F57),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: AppColors.line),
          children[index],
        ],
      ],
    ),
  );
}

/// One titled part of [YorksMyProfileCard].
class _CardSection extends StatelessWidget {
  const _CardSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: AppTypography.titleSmall),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class YorksMyDocumentsSection extends StatelessWidget {
  const YorksMyDocumentsSection({
    super.key,
    required this.language,
    required this.person,
  });

  final AppLanguage language;
  final PeopleMinePerson person;

  @override
  Widget build(BuildContext context) => _CardSection(
    key: const ValueKey('my-yorks-documents'),
    title: _M.t(_M.yourDocuments, language),
    icon: Icons.badge_outlined,
    children: [
      if (person.documents.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            _M.t(_M.noDocuments, language),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
        )
      else
        for (final document in person.documents)
          _MyDocumentRow(document: document, language: language),
    ],
  );
}

class _MyDocumentRow extends StatelessWidget {
  const _MyDocumentRow({required this.document, required this.language});

  final PeopleMineDocument document;
  final AppLanguage language;

  bool get _isDate =>
      document.status == PeopleDocumentStatus.ok &&
      (document.daysLeft ?? 0) > 0;

  String get _expiry {
    final days = document.daysLeft;
    if (days == null) return PS.t(PS.noExpiry, language);
    if (days < 0) return PS.t(PS.expiredAgo, language, {'n': -days});
    if (days == 0) return PS.t(PS.expiresToday, language);
    if (document.status == PeopleDocumentStatus.expiring) {
      return PS.t(PS.daysLeft, language, {'n': days});
    }
    return peopleDate(document.expiryDate);
  }

  @override
  Widget build(BuildContext context) {
    final colors = peopleStatusColors(document.status);
    final title = peopleKindLabel(
      document.kind,
      language,
      label: document.label,
    );
    final meta = [
      if (document.numberLast4 != null)
        _M.t(_M.endsWith, language, {'n': document.numberLast4}),
      if (document.sites != null) document.sites!,
    ].join(' · ');
    return Semantics(
      container: true,
      label: [title, meta, _expiry].where((part) => part.isNotEmpty).join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                peopleKindIcon(document.kind),
                color: AppColors.blue,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  _expiry,
                  // A date reads left to right in every language.
                  textDirection: _isDate ? TextDirection.ltr : null,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who the person is at Yorks, beyond what the header already shows:
/// position, the profession on their visa and ID, company, joining date and
/// crew. A field HR/PRO has not filled in says so.
class YorksMyFactsSection extends StatelessWidget {
  const YorksMyFactsSection({
    super.key,
    required this.language,
    required this.person,
  });

  final AppLanguage language;
  final PeopleMinePerson person;

  @override
  Widget build(BuildContext context) {
    final notRecorded = _M.t(_M.notRecorded, language);
    String orNotRecorded(String? value) =>
        value != null && yorksMyRecorded(value) ? value : notRecorded;
    return _CardSection(
      key: const ValueKey('my-yorks-identity-facts'),
      title: _M.t(_M.onYourId, language),
      icon: Icons.work_outline_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YorksProfileFactRow(
                label: _M.t(_M.positionInCompany, language),
                value: orNotRecorded(person.position),
              ),
              YorksProfileFactRow(
                key: const ValueKey('my-yorks-id-profession'),
                label: _M.t(_M.professionOnId, language),
                value: orNotRecorded(person.idProfession),
              ),
              YorksProfileFactRow(
                label: _M.t(_M.company, language),
                value: orNotRecorded(person.company),
              ),
              if (person.joiningDate != null)
                YorksProfileFactRow(
                  label: _M.t(_M.joined, language),
                  value: peopleDate(person.joiningDate),
                ),
              if (person.crewName != null)
                YorksProfileFactRow(
                  label: _M.t(_M.crew, language),
                  value: person.crewName!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The person's notes to HR/PRO, if any, and the button to send one.
class YorksMyNotesSection extends StatelessWidget {
  const YorksMyNotesSection({
    super.key,
    required this.language,
    required this.person,
    required this.onTell,
  });

  final AppLanguage language;
  final PeopleMinePerson person;
  final VoidCallback onTell;

  @override
  Widget build(BuildContext context) {
    final button = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: OutlinedButton.icon(
        key: const ValueKey('my-yorks-tell-hr'),
        onPressed: onTell,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
        ),
        icon: const Icon(Icons.chat_outlined, size: 18),
        label: Text(_M.t(_M.tellHr, language)),
      ),
    );
    if (person.notes.isEmpty) return button;
    return Column(
      key: const ValueKey('my-yorks-notes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardSection(
          title: _M.t(_M.yourNotes, language),
          icon: Icons.chat_outlined,
          children: [
            for (final note in person.notes)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '“${note.message}”',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      note.isDone
                          ? _M.t(_M.noteDoneOn, language, {
                              'date': peopleStamp(note.doneAt),
                            })
                          : _M.t(_M.noteWaiting, language, {
                              'date': peopleStamp(note.at),
                            }),
                      style: AppTypography.bodySmall.copyWith(
                        color: note.isDone
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        button,
      ],
    );
  }
}

/// Inside the card until HR/PRO links the account, while loading, or on
/// failure.
class YorksMyRecordNotice extends StatelessWidget {
  const YorksMyRecordNotice.unlinked({super.key, required this.language})
    : loading = false,
      onRetry = null;

  const YorksMyRecordNotice.loading({super.key, required this.language})
    : loading = true,
      onRetry = null;

  const YorksMyRecordNotice.failed({
    super.key,
    required this.language,
    required VoidCallback this.onRetry,
  }) : loading = false;

  final AppLanguage language;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = onRetry != null;
    return Padding(
      key: ValueKey(
        loading
            ? 'my-yorks-record-loading'
            : failed
            ? 'my-yorks-record-failed'
            : 'my-yorks-record-unlinked',
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: loading
          ? const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  failed ? Icons.cloud_off_outlined : Icons.link_off_rounded,
                  color: AppColors.inkSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _M.t(
                          failed ? _M.recordUnavailable : _M.notLinkedTitle,
                          language,
                        ),
                        style: AppTypography.titleSmall,
                      ),
                      if (!failed) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          _M.t(_M.notLinkedBody, language),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(_M.t(_M.retry, language)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// How the person signs in, now that the header shows their record.
class YorksMyAccountCard extends StatelessWidget {
  const YorksMyAccountCard({
    super.key,
    required this.language,
    required this.email,
    required this.role,
  });

  final AppLanguage language;
  final String email;
  final YorksV1Role role;

  @override
  Widget build(BuildContext context) => YorksProfileSectionCard(
    key: const ValueKey('my-yorks-account'),
    title: _M.t(_M.yourAccount, language),
    description: _M.t(_M.yourAccountDescription, language),
    icon: Icons.person_outline_rounded,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YorksProfileFactRow(
              label: _M.t(_M.signedInEmail, language),
              value: email,
              forceLtr: true,
            ),
            YorksProfileFactRow(
              label: _M.t(_M.appRole, language),
              value: YorksV1ProfileStrings.role(role, language),
            ),
          ],
        ),
      ),
    ],
  );
}
