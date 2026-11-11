import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/yorks_v1_workforce_administration_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../application/workforce_providers.dart';
import '../../domain/workforce_foundation_models.dart';

// Independently staged until the assigned-team creation acceptance gate passes.
const workforceTeamWorkersEnabled = bool.fromEnvironment(
  'YORKS_WORKFORCE_TEAM_WORKERS',
);

class YorksWorkforceTeamWorkersScreen extends ConsumerStatefulWidget {
  const YorksWorkforceTeamWorkersScreen({super.key});
  @override
  ConsumerState<YorksWorkforceTeamWorkersScreen> createState() =>
      _TeamWorkersState();
}

class _TeamWorkersState extends ConsumerState<YorksWorkforceTeamWorkersScreen> {
  String t(String key) => YorksV1WorkforceAdministrationStrings.text(
    ref.read(languageProvider),
    key,
  );
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(yorksWorkforceTeamWorkersProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final state = ref.watch(yorksWorkforceTeamWorkersProvider);
    final controller = ref.read(yorksWorkforceTeamWorkersProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('team_workers_failed')),
                  TextButton(
                    onPressed: () => controller.load(),
                    child: Text(t('retry')),
                  ),
                ],
              ),
            ),
            data: (data) {
              final teams = data['teams'] as List;
              final workers = data['workers'] as List;
              return ListView(
                children: [
                  Text(t('workers'), style: AppTypography.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(t('assigned_team_workers')),
                  const SizedBox(height: AppSpacing.lg),
                  if (teams.isEmpty)
                    Text(t('no_assigned_teams'))
                  else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(controller.teamId),
                      initialValue: controller.teamId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t('teams')),
                      items: [
                        for (final team in teams)
                          DropdownMenuItem(
                            value: team['id'] as String,
                            child: Text(
                              team['name'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => controller.load(selectedTeam: id),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(t('add_worker')),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (workers.isEmpty) Text(t('empty_workers')),
                    for (final worker in workers)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(worker['name'] as String),
                          subtitle: Text(
                            '${worker['number']} · ${worker['designation']}',
                          ),
                        ),
                      ),
                    if (data['has_more'] == true ||
                        (data['has_more'] == null && workers.length == 50))
                      TextButton(
                        onPressed: controller.loadMore,
                        child: Text(t('more_workers')),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final controller = ref.read(yorksWorkforceTeamWorkersProvider.notifier);
    final form = GlobalKey<FormState>();
    final fields = {
      for (final key in [
        'full_name',
        'worker_number',
        'designation',
        'employer',
        'joining_date',
      ])
        key: '',
    };
    fields['joining_date'] = DateTime.now().toIso8601String().substring(0, 10);
    var type = YorksWorkforceWorkerType.yorksEmployee;
    var busy = false;
    String? failure;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, change) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(t('add_worker')),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in fields.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: TextFormField(
                            initialValue: entry.value,
                            onChanged: (value) => fields[entry.key] = value,
                            enabled: !busy,
                            decoration: InputDecoration(
                              labelText: t(entry.key),
                              helperMaxLines: 3,
                              helperText: entry.key == 'worker_number'
                                  ? t('number_optional')
                                  : null,
                            ),
                            validator: (value) {
                              if (entry.key == 'worker_number') return null;
                              if (value == null || value.trim().isEmpty) {
                                return t('required');
                              }
                              if (entry.key == 'joining_date' &&
                                  (DateTime.tryParse(value) == null ||
                                      !RegExp(
                                        r'^\d{4}-\d{2}-\d{2}$',
                                      ).hasMatch(value))) {
                                return t('date_hint');
                              }
                              return null;
                            },
                          ),
                        ),
                      DropdownButtonFormField<YorksWorkforceWorkerType>(
                        initialValue: type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('worker_type'),
                        ),
                        items: [
                          for (final value in YorksWorkforceWorkerType.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(
                                t(value.wireValue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => change(() => type = value!),
                      ),
                      if (failure != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            failure!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: Text(t('cancel')),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (form.currentState?.validate() != true) return;
                        change(() {
                          busy = true;
                          failure = null;
                        });
                        try {
                          final saved = await controller.create({
                            'full_name': fields['full_name']!.trim(),
                            'worker_number': fields['worker_number']!.trim(),
                            'designation': fields['designation']!.trim(),
                            'employer_company': fields['employer']!.trim(),
                            'joining_date': fields['joining_date']!.trim(),
                            'worker_type': type.wireValue,
                          });
                          if (dialogContext.mounted) {
                            if (saved) {
                              Navigator.pop(dialogContext);
                            } else {
                              change(() {
                                busy = false;
                                failure = t('team_worker_save_failed');
                              });
                            }
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            change(() {
                              busy = false;
                              failure = t('team_worker_save_failed');
                            });
                          }
                        }
                      },
                child: Text(t('add_worker')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
