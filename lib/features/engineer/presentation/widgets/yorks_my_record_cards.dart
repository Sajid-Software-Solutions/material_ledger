/// My Yorks from the People record (PRODUCT_DECISIONS section 54): the
/// person's own documents, who they are at Yorks, notes to HR/PRO, their
/// projects and this month's attendance.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

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

/// "Site Engineer · Staff", leaving out a position never recorded.
String yorksMyPositionLine(PeopleMinePerson person, AppLanguage language) => [
  if (person.position.isNotEmpty && person.position != 'Not recorded')
    person.position,
  peopleCategoryLabel(person.category, language),
].join(' · ');

class YorksMyDocumentsCard extends StatelessWidget {
  const YorksMyDocumentsCard({
    super.key,
    required this.language,
    required this.person,
  });

  final AppLanguage language;
  final PeopleMinePerson person;

  @override
  Widget build(BuildContext context) => YorksProfileSectionCard(
    key: const ValueKey('my-yorks-documents'),
    title: _M.t(_M.yourDocuments, language),
    description: _M.t(_M.yourDocumentsDescription, language),
    icon: Icons.badge_outlined,
    children: [
      if (person.documents.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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

/// Who the person is at Yorks: position, the profession on their visa and
/// ID, category, record number, company, joining date and crew.
class YorksMyIdentityCard extends StatelessWidget {
  const YorksMyIdentityCard({
    super.key,
    required this.language,
    required this.person,
  });

  final AppLanguage language;
  final PeopleMinePerson person;

  @override
  Widget build(BuildContext context) {
    final notRecorded = _M.t(_M.notRecorded, language);
    return YorksProfileSectionCard(
      key: const ValueKey('my-yorks-identity-facts'),
      title: _M.t(_M.onYourId, language),
      description: _M.t(_M.onYourIdDescription, language),
      icon: Icons.work_outline_rounded,
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
                label: _M.t(_M.positionInCompany, language),
                value:
                    person.position.isEmpty || person.position == 'Not recorded'
                    ? notRecorded
                    : person.position,
              ),
              YorksProfileFactRow(
                key: const ValueKey('my-yorks-id-profession'),
                label: _M.t(_M.professionOnId, language),
                value: person.idProfession ?? notRecorded,
              ),
              YorksProfileFactRow(
                label: _M.t(_M.category, language),
                value: peopleCategoryLabel(person.category, language),
              ),
              YorksProfileFactRow(
                label: _M.t(_M.recordNumber, language),
                value: person.number,
                forceLtr: true,
              ),
              YorksProfileFactRow(
                label: _M.t(_M.company, language),
                value: person.company,
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

/// The person's notes to HR/PRO and the button to send one.
class YorksTellHrCard extends StatelessWidget {
  const YorksTellHrCard({
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
    final button = OutlinedButton.icon(
      key: const ValueKey('my-yorks-tell-hr'),
      onPressed: onTell,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
      ),
      icon: const Icon(Icons.chat_outlined, size: 18),
      label: Text(_M.t(_M.tellHr, language)),
    );
    if (person.notes.isEmpty) return button;
    return YorksProfileSectionCard(
      key: const ValueKey('my-yorks-notes'),
      title: _M.t(_M.yourNotes, language),
      description: _M.t(_M.tellHrBody, language),
      icon: Icons.chat_outlined,
      children: [
        for (final note in person.notes)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
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
                    color: note.isDone ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: button),
      ],
    );
  }
}

/// Shown until HR/PRO links the account, while loading, or on failure.
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
    return YorksProfileSectionCard(
      key: ValueKey(
        loading
            ? 'my-yorks-record-loading'
            : failed
            ? 'my-yorks-record-failed'
            : 'my-yorks-record-unlinked',
      ),
      title: _M.t(_M.yourDocuments, language),
      description: _M.t(_M.yourDocumentsDescription, language),
      icon: Icons.badge_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: loading
              ? const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      failed
                          ? Icons.cloud_off_outlined
                          : Icons.link_off_rounded,
                      color: AppColors.inkSecondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
    );
  }
}

/// The projects the person is a member of today.
class YorksMyProjectsCard extends StatefulWidget {
  const YorksMyProjectsCard({
    super.key,
    required this.language,
    required this.projects,
    required this.onOpen,
    this.allProjectsCount,
  });

  final AppLanguage language;
  final List<PeopleMineProject> projects;
  final ValueChanged<String> onOpen;

  /// When the role opens every project without a membership.
  final int? allProjectsCount;

  @override
  State<YorksMyProjectsCard> createState() => _YorksMyProjectsCardState();
}

class _YorksMyProjectsCardState extends State<YorksMyProjectsCard> {
  static const _shown = 5;
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final projects = widget.projects;
    final visible = _all || projects.length <= _shown
        ? projects
        : projects.take(_shown).toList();
    return YorksProfileSectionCard(
      key: const ValueKey('my-yorks-projects'),
      title: _M.t(_M.yourProjects, language),
      description: _M.t(_M.yourProjectsDescription, language),
      icon: Icons.account_tree_outlined,
      children: [
        if (projects.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              widget.allProjectsCount != null
                  ? _M.t(_M.allProjects, language, {
                      'n': widget.allProjectsCount,
                    })
                  : _M.t(_M.noProjects, language),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        for (final project in visible)
          InkWell(
            key: ValueKey('my-yorks-project-${project.id}'),
            onTap: () => widget.onOpen(project.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            [
                              project.ref,
                              _M.t(
                                project.role == 'project_engineer'
                                    ? _M.roleProjectEngineer
                                    : _M.roleSiteEngineer,
                                language,
                              ),
                            ].join(' · '),
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      color: AppColors.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!_all && projects.length > _shown)
          TextButton(
            key: const ValueKey('my-yorks-projects-all'),
            onPressed: () => setState(() => _all = true),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
            ),
            child: Text(
              '${_M.t(_M.showAll, language)} · '
              '${_M.t(_M.moreProjects, language, {'n': projects.length - _shown})}',
            ),
          ),
      ],
    );
  }
}

/// This month so far, from the crew day sheets.
class YorksMyAttendanceCard extends StatelessWidget {
  const YorksMyAttendanceCard({
    super.key,
    required this.language,
    required this.attendance,
    this.crewName,
  });

  final AppLanguage language;
  final PeopleMineAttendance attendance;
  final String? crewName;

  @override
  Widget build(BuildContext context) {
    final month = DateTime.tryParse('${attendance.month}-01');
    final overtime = _M.t(_M.hoursMinutes, language, {
      'h': attendance.overtimeMinutes ~/ 60,
      'm': attendance.overtimeMinutes % 60,
    });
    return YorksProfileSectionCard(
      key: const ValueKey('my-yorks-attendance'),
      title: _M.t(_M.yourAttendance, language, {
        'month': month == null
            ? attendance.month
            : DateFormat('MMMM yyyy').format(month),
      }),
      description: _M.t(_M.yourAttendanceDescription, language),
      icon: Icons.fact_check_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: attendance.recordedDays == 0
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    _M.t(_M.noAttendance, language),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    YorksProfileFactRow(
                      key: const ValueKey('my-yorks-attendance-present'),
                      label: _M.t(_M.daysPresent, language),
                      value: _M.t(_M.ofRecorded, language, {
                        'n': attendance.presentDays,
                        'm': attendance.recordedDays,
                      }),
                    ),
                    if (attendance.absentDays > 0)
                      YorksProfileFactRow(
                        label: _M.t(_M.absent, language),
                        value: '${attendance.absentDays}',
                      ),
                    if (attendance.leaveDays > 0)
                      YorksProfileFactRow(
                        label: _M.t(_M.leave, language),
                        value: '${attendance.leaveDays}',
                      ),
                    YorksProfileFactRow(
                      key: const ValueKey('my-yorks-attendance-overtime'),
                      label: _M.t(_M.overtime, language),
                      value: overtime,
                    ),
                    if (crewName != null)
                      YorksProfileFactRow(
                        label: _M.t(_M.crew, language),
                        value: crewName!,
                      ),
                  ],
                ),
        ),
      ],
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
