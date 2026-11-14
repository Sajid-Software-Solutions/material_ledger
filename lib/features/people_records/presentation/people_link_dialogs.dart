/// People — linking app accounts to people (PRODUCT_DECISIONS section 54).
///
/// Loaded on demand from the person record and the People home. Every link
/// waits for the server; nothing shows as linked before it confirms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_audit_strings.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_my_record_strings.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import 'people_kit.dart';

typedef _M = MyRecordStrings;

/// The message for a refused link, in the person's language.
String peopleLinkErrorText(Object? error, AppLanguage language) {
  if (error is YorksV1DomainException &&
      (error.serverMessage ?? '').contains('V1_PEOPLE_ACCOUNT_TAKEN')) {
    return _M.t(_M.accountTaken, language);
  }
  return peopleErrorText(error, language);
}

/// Picks an account for [person] and links it. Resolves to true once linked.
Future<bool?> showPeopleLinkAccountDialog(
  BuildContext context, {
  required PeoplePerson person,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _LinkAccountDialog(person: person),
);

/// Every account not yet linked, with the people their names match.
Future<void> showPeopleLinkAccountsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _LinkAccountsDialog(),
    );

class _LinkAccountDialog extends ConsumerStatefulWidget {
  const _LinkAccountDialog({required this.person});

  final PeoplePerson person;

  @override
  ConsumerState<_LinkAccountDialog> createState() => _LinkAccountDialogState();
}

class _LinkAccountDialogState extends ConsumerState<_LinkAccountDialog> {
  final _search = TextEditingController();
  final _idempotencyKey = const Uuid().v4();
  String? _running;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _link(PeopleAccount account) async {
    final language = ref.read(languageProvider);
    setState(() {
      _running = account.authUserId;
      _error = null;
    });
    try {
      await ref
          .read(yorksV1PeopleRepositoryProvider)
          .setAccount(
            workerId: widget.person.id,
            authUserId: account.authUserId,
            expectedVersion: widget.person.recordVersion,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = null;
        _error = peopleLinkErrorText(error, language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final suggestions = ref.watch(yorksV1PeopleLinkSuggestionsProvider);
    final query = _search.text.trim().toLowerCase();
    return PopScope(
      canPop: _running == null,
      child: AlertDialog(
        key: const ValueKey('people-link-account-dialog'),
        title: Text(
          _M.t(_M.chooseAccount, language, {'name': widget.person.name}),
        ),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _M.t(_M.chooseAccountBody, language),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('people-link-search'),
                controller: _search,
                enabled: _running == null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _M.t(_M.searchAccounts, language),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: suggestions.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => PeopleMessage(
                    icon: Icons.cloud_off_outlined,
                    title: peopleErrorText(error, language),
                    action: _M.t(_M.retry, language),
                    onPressed: () =>
                        ref.invalidate(yorksV1PeopleLinkSuggestionsProvider),
                  ),
                  data: (data) {
                    final accounts =
                        [
                          for (final item in data.accounts)
                            if (query.isEmpty ||
                                item.account.name.toLowerCase().contains(
                                  query,
                                ) ||
                                (item.account.email ?? '')
                                    .toLowerCase()
                                    .contains(query))
                              item,
                        ]..sort((a, b) {
                          final first = a.suggests(widget.person.id) ? 0 : 1;
                          final second = b.suggests(widget.person.id) ? 0 : 1;
                          return first != second
                              ? first - second
                              : a.account.name.toLowerCase().compareTo(
                                  b.account.name.toLowerCase(),
                                );
                        });
                    if (accounts.isEmpty) {
                      return Center(
                        child: Text(
                          _M.t(
                            data.accounts.isEmpty ? _M.noAccounts : _M.noMatch,
                            language,
                          ),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: accounts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = accounts[index];
                        final suggested = item.suggests(widget.person.id);
                        return _AccountTile(
                          key: ValueKey(
                            'people-link-account-${item.account.authUserId}',
                          ),
                          account: item.account,
                          language: language,
                          suggested: suggested,
                          running: _running == item.account.authUserId,
                          enabled: _running == null,
                          actionLabel: _M.t(_M.link, language),
                          onPressed: () => _link(item.account),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _running == null
                ? () => Navigator.of(context).pop()
                : null,
            child: Text(_M.t(_M.cancel, language)),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.language,
    required this.suggested,
    required this.running,
    required this.enabled,
    required this.actionLabel,
    required this.onPressed,
  });

  final PeopleAccount account;
  final AppLanguage language;
  final bool suggested;
  final bool running;
  final bool enabled;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.blueContainer,
          child: Text(
            account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
            style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.name,
                style: AppTypography.bodyMedium.copyWith(
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
              if (suggested) ...[
                const SizedBox(height: AppSpacing.xxs),
                PeoplePill(
                  label: _M.t(_M.suggested, language),
                  icon: Icons.auto_awesome_outlined,
                  color: AppColors.success,
                  background: AppColors.successContainer,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        running
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: enabled ? onPressed : null,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                child: Text(actionLabel),
              ),
      ],
    ),
  );
}

class _LinkAccountsDialog extends ConsumerStatefulWidget {
  const _LinkAccountsDialog();

  @override
  ConsumerState<_LinkAccountsDialog> createState() =>
      _LinkAccountsDialogState();
}

class _LinkAccountsDialogState extends ConsumerState<_LinkAccountsDialog> {
  final _keys = <String, String>{};
  String? _running;
  String? _error;

  Future<void> _link(PeopleAccount account, PeopleLinkCandidate person) async {
    final language = ref.read(languageProvider);
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    final runKey = '${account.authUserId}:${person.workerId}';
    setState(() {
      _running = runKey;
      _error = null;
    });
    try {
      // The record version is read now, so a stale list never links over a
      // change made since it loaded.
      final record = await repository.get(person.workerId);
      await repository.setAccount(
        workerId: person.workerId,
        authUserId: account.authUserId,
        expectedVersion: record.recordVersion,
        idempotencyKey: _keys.putIfAbsent(runKey, () => const Uuid().v4()),
      );
      if (!mounted) return;
      yorksV1RefreshPeople(ref, workerId: person.workerId);
      peopleToast(context, _M.t(_M.linkedToast, language));
      setState(() => _running = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = null;
        _error = peopleLinkErrorText(error, language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final suggestions = ref.watch(yorksV1PeopleLinkSuggestionsProvider);
    return PopScope(
      canPop: _running == null,
      child: AlertDialog(
        key: const ValueKey('people-link-accounts-dialog'),
        title: Text(_M.t(_M.linkAccountsTitle, language)),
        content: SizedBox(
          width: 620,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _M.t(_M.linkAccountsDescription, language),
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              if (suggestions.valueOrNull case final data?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _M.t(_M.linkSummary, language, {
                    'linked': data.linkedCount,
                    'waiting': data.accounts.length,
                    'matches': data.withSuggestions,
                  }),
                  key: const ValueKey('people-link-summary'),
                  style: AppTypography.labelLarge,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: suggestions.when(
                  skipLoadingOnRefresh: true,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => PeopleMessage(
                    icon: Icons.cloud_off_outlined,
                    title: peopleErrorText(error, language),
                    action: _M.t(_M.retry, language),
                    onPressed: () =>
                        ref.invalidate(yorksV1PeopleLinkSuggestionsProvider),
                  ),
                  data: (data) {
                    if (data.accounts.isEmpty) {
                      return Center(
                        child: Text(
                          _M.t(_M.noAccounts, language),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: data.accounts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _AccountWithPeople(
                        key: ValueKey(
                          'people-link-row-${data.accounts[index].account.authUserId}',
                        ),
                        item: data.accounts[index],
                        language: language,
                        running: _running,
                        onLink: _link,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _running == null
                ? () => Navigator.of(context).pop()
                : null,
            child: Text(_M.t(_M.close, language)),
          ),
        ],
      ),
    );
  }
}

class _AccountWithPeople extends StatelessWidget {
  const _AccountWithPeople({
    super.key,
    required this.item,
    required this.language,
    required this.running,
    required this.onLink,
  });

  final PeopleLinkAccount item;
  final AppLanguage language;
  final String? running;
  final void Function(PeopleAccount, PeopleLinkCandidate) onLink;

  @override
  Widget build(BuildContext context) {
    final account = item.account;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.name,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w800,
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
          const SizedBox(height: AppSpacing.sm),
          if (item.suggestions.isEmpty)
            Text(
              _M.t(_M.noSuggestion, language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final person in item.suggestions)
                  _CandidateButton(
                    key: ValueKey(
                      'people-link-${account.authUserId}-${person.workerId}',
                    ),
                    person: person,
                    language: language,
                    running:
                        running == '${account.authUserId}:${person.workerId}',
                    enabled: running == null,
                    onLink: () => onLink(account, person),
                    onOpen: () {
                      Navigator.of(context).pop();
                      context.go(peoplePersonPath(person.workerId));
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CandidateButton extends StatelessWidget {
  const _CandidateButton({
    super.key,
    required this.person,
    required this.language,
    required this.running,
    required this.enabled,
    required this.onLink,
    required this.onOpen,
  });

  final PeopleLinkCandidate person;
  final AppLanguage language;
  final bool running;
  final bool enabled;
  final VoidCallback onLink;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.xs,
      AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: enabled ? onOpen : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [
                  person.number,
                  if (person.position.isNotEmpty &&
                      person.position != 'Not recorded')
                    person.position,
                  peopleCategoryLabel(person.category, language),
                ].join(' · '),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        running
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : FilledButton.tonal(
                onPressed: enabled ? onLink : null,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                child: Text(_M.t(_M.link, language)),
              ),
      ],
    ),
  );
}
