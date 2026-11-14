/// People — the person's app account and the notes they sent HR/PRO from
/// My Yorks (PRODUCT_DECISIONS section 54).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../shared/models/yorks_v1_my_record_strings.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'people_kit.dart';
import 'people_link_dialogs.dart' deferred as link_dialogs;

typedef _M = MyRecordStrings;

/// Who signs in as this person, and for HR/PRO and Admin, link or unlink.
class PeopleAccountSection extends ConsumerWidget {
  const PeopleAccountSection({
    super.key,
    required this.person,
    required this.language,
  });

  final PeoplePerson person;
  final AppLanguage language;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    await link_dialogs.loadLibrary();
    if (!context.mounted) return;
    final linked = await link_dialogs.showPeopleLinkAccountDialog(
      context,
      person: person,
    );
    if (linked != true) return;
    yorksV1RefreshPeople(ref, workerId: person.id);
    if (context.mounted) peopleToast(context, _M.t(_M.linkedToast, language));
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    final idempotencyKey = const Uuid().v4();
    final done = await showAttendanceCommandDialog(
      context,
      language: language,
      title: _M.t(_M.unlinkTitle, language),
      summary: [
        person.account?.name ?? '',
        if (person.account?.email != null) person.account!.email!,
      ].join(' · '),
      body: _M.t(_M.unlinkBody, language, {'name': person.account?.name}),
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
    final account = person.account;
    return PeopleSurface(
      key: const ValueKey('people-person-account'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_iphone_rounded, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _M.t(_M.appAccount, language),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _M.t(_M.appAccountDescription, language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          if (account == null)
            Text(
              _M.t(_M.notLinked, language),
              key: const ValueKey('people-person-account-none'),
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.inkSecondary,
              ),
            )
          else ...[
            Text(
              account.name,
              key: const ValueKey('people-person-account-name'),
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              [
                if (account.email != null) account.email!,
                if (account.role.isNotEmpty)
                  YorksV1AuditStrings.roleLabel(account.role, language),
              ].join(' · '),
              textDirection: TextDirection.ltr,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
          if (person.canLink) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('people-person-link'),
                  onPressed: () => _link(context, ref),
                  icon: Icon(
                    account == null
                        ? Icons.link_rounded
                        : Icons.swap_horiz_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _M.t(
                      account == null ? _M.linkAccount : _M.changeAccount,
                      language,
                    ),
                  ),
                ),
                if (account != null)
                  OutlinedButton.icon(
                    key: const ValueKey('people-person-unlink'),
                    onPressed: () => _unlink(context, ref),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: Text(_M.t(_M.unlink, language)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Notes the person sent from My Yorks. HR/PRO marks each done.
class PeopleNotesSection extends ConsumerStatefulWidget {
  const PeopleNotesSection({
    super.key,
    required this.person,
    required this.language,
  });

  final PeoplePerson person;
  final AppLanguage language;

  @override
  ConsumerState<PeopleNotesSection> createState() => _PeopleNotesSectionState();
}

class _PeopleNotesSectionState extends ConsumerState<PeopleNotesSection> {
  final _keys = <String, String>{};
  String? _running;

  Future<void> _done(PeopleNote note) async {
    final language = widget.language;
    setState(() => _running = note.id);
    try {
      await ref
          .read(yorksV1PeopleRepositoryProvider)
          .noteDone(
            noteId: note.id,
            idempotencyKey: _keys.putIfAbsent(note.id, () => const Uuid().v4()),
          );
      if (!mounted) return;
      yorksV1RefreshPeople(ref, workerId: widget.person.id);
      peopleToast(context, _M.t(_M.noteDoneToast, language));
    } catch (error) {
      if (mounted) peopleToast(context, peopleErrorText(error, language));
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final language = widget.language;
    if (person.notes.isEmpty) return const SizedBox.shrink();
    final open = person.notes.where((note) => !note.isDone).length;
    return PeopleSurface(
      key: const ValueKey('people-person-notes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_outlined, color: AppColors.blue),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _M.t(_M.notesFrom, language, {'name': person.name}),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (open > 0)
                PeoplePill(
                  label: _M.t(_M.openNotes, language, {'n': open}),
                  color: AppColors.warning,
                  background: AppColors.warningContainer,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _M.t(_M.notesDescription, language),
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          for (final note in person.notes) ...[
            const Divider(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${note.message}”',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        note.isDone
                            ? _M.t(_M.doneBy, language, {
                                'name': note.doneBy ?? '',
                                'date': peopleStamp(note.doneAt),
                              })
                            : peopleStamp(note.at),
                        style: AppTypography.bodySmall.copyWith(
                          color: note.isDone
                              ? AppColors.success
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!note.isDone && person.canManage) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _running == note.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton.icon(
                          key: ValueKey('people-note-done-${note.id}'),
                          onPressed: _running == null
                              ? () => _done(note)
                              : null,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(_M.t(_M.markDone, language)),
                        ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the People-wide list of accounts to link (HR/PRO and Admin).
Future<void> showPeopleLinkAccounts(BuildContext context) async {
  await link_dialogs.loadLibrary();
  if (!context.mounted) return;
  await link_dialogs.showPeopleLinkAccountsDialog(context);
}
