/// User Management — the People record an app account belongs to
/// (PRODUCT_DECISIONS section 56). Replaces the legacy "HR employee record"
/// while People records are on. HR/PRO and Admin link and unlink; other
/// People viewers only read. Nothing shows as linked before the server
/// confirms it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_my_record_strings.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'people_kit.dart';
import 'people_link_dialogs.dart' deferred as link_dialogs;

typedef _M = MyRecordStrings;

class AccountPeopleRecordSection extends ConsumerWidget {
  const AccountPeopleRecordSection({
    super.key,
    required this.appUserId,
    required this.accountName,
    required this.language,
    required this.onOpenRecord,
  });

  final String appUserId;
  final String accountName;
  final AppLanguage language;

  /// Opens the person's record; the caller closes its own panel first.
  final ValueChanged<String> onOpenRecord;

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    PeopleAccount account,
  ) async {
    await link_dialogs.loadLibrary();
    if (!context.mounted) return;
    final linked = await link_dialogs.showPeopleLinkPersonDialog(
      context,
      account: account,
    );
    if (linked != true) return;
    yorksV1RefreshPeople(ref);
    if (context.mounted) peopleToast(context, _M.t(_M.linkedToast, language));
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    PeoplePerson person,
  ) async {
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    final idempotencyKey = const Uuid().v4();
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: _M.t(_M.unlinkTitle, language),
      summary: '${person.name} · ${person.number}',
      body: _M.t(_M.unlinkPersonBody, language, {'name': accountName}),
      confirmLabel: _M.t(_M.unlink, language),
      destructive: true,
      command: (_) async {
        try {
          await repository.setAccount(
            workerId: person.id,
            authUserId: null,
            expectedVersion: person.recordVersion,
            idempotencyKey: idempotencyKey,
          );
          return null;
        } catch (error) {
          return peopleErrorText(error, language);
        }
      },
    );
    if (done == null) return;
    yorksV1RefreshPeople(ref, workerId: person.id);
    if (context.mounted) {
      peopleToast(context, _M.t(_M.unlinkedToast, language));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksV1PeopleAccountPersonProvider(appUserId));
    return KeyedSubtree(
      key: const ValueKey('user-people-record'),
      child: state.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (error, _) => _Line(
          key: const ValueKey('user-people-record-failed'),
          icon: Icons.cloud_off_outlined,
          iconColor: AppColors.muted,
          title: _M.t(_M.recordUnavailable, language),
          subtitle: peopleErrorText(error, language),
          trailing: TextButton(
            onPressed: () =>
                ref.invalidate(yorksV1PeopleAccountPersonProvider(appUserId)),
            child: Text(_M.t(_M.retry, language)),
          ),
        ),
        data: (data) {
          final person = data.person;
          final account = data.account;
          if (person == null) {
            return _Line(
              key: const ValueKey('user-people-record-none'),
              icon: Icons.link_off_rounded,
              iconColor: AppColors.muted,
              title: _M.t(_M.noPeopleRecord, language),
              subtitle: _M.t(
                data.canLink ? _M.noPeopleRecordHint : _M.hrLinksPeople,
                language,
              ),
              trailing: data.canLink && account != null
                  ? OutlinedButton(
                      key: const ValueKey('user-people-record-link'),
                      onPressed: () => _link(context, ref, account),
                      child: Text(_M.t(_M.link, language)),
                    )
                  : null,
            );
          }
          bool recorded(String value) =>
              value.trim().isNotEmpty && value.trim() != 'Not recorded';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line(
                key: const ValueKey('user-people-record-linked'),
                icon: Icons.badge_outlined,
                iconColor: AppColors.blue,
                title: person.name,
                subtitle: [
                  person.number,
                  if (recorded(person.company)) person.company,
                ].join(' · '),
                detail: [
                  if (recorded(person.position)) person.position,
                  peopleCategoryLabel(person.category, language),
                ].join(' · '),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('user-people-record-open'),
                    onPressed: () => onOpenRecord(person.id),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(_M.t(_M.openRecord, language)),
                  ),
                  if (data.canLink)
                    TextButton.icon(
                      key: const ValueKey('user-people-record-unlink'),
                      onPressed: () => _unlink(context, ref, person),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: Text(_M.t(_M.unlink, language)),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// An icon, a bold line and its details, with an optional action; the same
/// shape as the panel's other rows.
class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.detail,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: iconColor),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            if (detail != null && detail!.isNotEmpty)
              Text(
                detail!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
          ],
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: AppSpacing.sm),
        trailing!,
      ],
    ],
  );
}
