import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_workforce_administration_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../application/workforce_administration_controller.dart';
import '../../application/workforce_providers.dart';
import '../../domain/workforce_administration_models.dart';
import '../../domain/workforce_configuration_models.dart';
import '../../domain/workforce_foundation_models.dart';

enum _AdministrationSection { workers, teams, setup, access }

class YorksWorkforceAdministrationScreen extends ConsumerStatefulWidget {
  const YorksWorkforceAdministrationScreen({super.key});

  @override
  ConsumerState<YorksWorkforceAdministrationScreen> createState() =>
      _YorksWorkforceAdministrationScreenState();
}

class _YorksWorkforceAdministrationScreenState
    extends ConsumerState<YorksWorkforceAdministrationScreen> {
  _AdministrationSection _section = _AdministrationSection.workers;
  bool _loadScheduled = false;

  void _scheduleLoad(YorksWorkforceAdministrationState state) {
    if (state.status != YorksWorkforceAdministrationStatus.idle) {
      _loadScheduled = false;
      return;
    }
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(yorksWorkforceAdministrationControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksWorkforceAdministrationControllerProvider);
    final controller = ref.read(
      yorksWorkforceAdministrationControllerProvider.notifier,
    );
    _scheduleLoad(state);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final sections = <_AdministrationSection>[
      if (controller.canManageWorkers) _AdministrationSection.workers,
      if (controller.canManageTeams) _AdministrationSection.teams,
      if (controller.canManageConfiguration) _AdministrationSection.setup,
      _AdministrationSection.access,
    ];
    if (!sections.contains(_section)) _section = sections.first;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            if (state.status == YorksWorkforceAdministrationStatus.loading ||
                state.status == YorksWorkforceAdministrationStatus.saving)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.load,
                child: ListView(
                  key: const PageStorageKey('workforce-administration'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    compact ? AppSpacing.mobileScreenVertical : AppSpacing.xxl,
                    compact
                        ? AppSpacing.mobileScreenHorizontal
                        : AppSpacing.xxl,
                    AppSpacing.colossal,
                  ),
                  children: [
                    _Header(
                      language: language,
                      compact: compact,
                      onRefresh: controller.load,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _StateBanner(
                      language: language,
                      state: state,
                      onRetry: controller.load,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final section in sections)
                          ChoiceChip(
                            key: Key('workforce-admin-${section.name}'),
                            label: Text(_t(language, section.name)),
                            selected: _section == section,
                            onSelected: (_) => setState(() {
                              _section = section;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (state.hasConfirmedData)
                      switch (_section) {
                        _AdministrationSection.workers => _WorkersSection(
                          language: language,
                          state: state,
                          controller: controller,
                        ),
                        _AdministrationSection.teams => _TeamsSection(
                          language: language,
                          state: state,
                          controller: controller,
                        ),
                        _AdministrationSection.setup => _SetupSection(
                          language: language,
                          state: state,
                          controller: controller,
                        ),
                        _AdministrationSection.access => _AccessSection(
                          language: language,
                        ),
                      }
                    else if (state.status ==
                            YorksWorkforceAdministrationStatus.loading ||
                        state.status == YorksWorkforceAdministrationStatus.idle)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxxl),
                        child: Center(child: Text(_t(language, 'loading'))),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.language,
    required this.compact,
    required this.onRefresh,
  });

  final AppLanguage language;
  final bool compact;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_t(language, 'title'), style: AppTypography.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(_t(language, 'body'), style: AppTypography.bodyMedium),
      ],
    );
    final refresh = IconButton.outlined(
      tooltip: _t(language, 'refresh'),
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh),
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.minTapTarget,
        height: AppSpacing.minTapTarget,
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          copy,
          const SizedBox(height: AppSpacing.sm),
          refresh,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        refresh,
      ],
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.language,
    required this.state,
    required this.onRetry,
  });

  final AppLanguage language;
  final YorksWorkforceAdministrationState state;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final visible = switch (state.status) {
      YorksWorkforceAdministrationStatus.saved ||
      YorksWorkforceAdministrationStatus.offline ||
      YorksWorkforceAdministrationStatus.conflict ||
      YorksWorkforceAdministrationStatus.uncertain ||
      YorksWorkforceAdministrationStatus.forbidden ||
      YorksWorkforceAdministrationStatus.sessionExpired ||
      YorksWorkforceAdministrationStatus.unavailable ||
      YorksWorkforceAdministrationStatus.failure => true,
      _ => false,
    };
    if (!visible) return const SizedBox.shrink();
    final failure = state.status != YorksWorkforceAdministrationStatus.saved;
    final text = switch (state.status) {
      YorksWorkforceAdministrationStatus.saved => _t(language, 'saved'),
      YorksWorkforceAdministrationStatus.forbidden ||
      YorksWorkforceAdministrationStatus.sessionExpired ||
      YorksWorkforceAdministrationStatus.unavailable => _t(
        language,
        'access_denied',
      ),
      YorksWorkforceAdministrationStatus.offline => _t(language, 'offline'),
      YorksWorkforceAdministrationStatus.conflict => _t(language, 'conflict'),
      YorksWorkforceAdministrationStatus.uncertain => _t(language, 'uncertain'),
      _ => _t(language, 'load_failed'),
    };
    return Container(
      decoration: BoxDecoration(
        color: failure ? AppColors.errorContainer : AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: failure ? AppColors.error : AppColors.success,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            failure ? Icons.error_outline : Icons.cloud_done_outlined,
            color: failure ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text)),
          if (failure)
            TextButton(onPressed: onRetry, child: Text(_t(language, 'retry'))),
        ],
      ),
    );
  }
}

class _WorkersSection extends StatelessWidget {
  const _WorkersSection({
    required this.language,
    required this.state,
    required this.controller,
  });

  final AppLanguage language;
  final YorksWorkforceAdministrationState state;
  final YorksWorkforceAdministrationController controller;

  @override
  Widget build(BuildContext context) {
    final foundation = state.foundation!;
    return _Panel(
      title: _t(language, 'workers'),
      action: FilledButton.icon(
        key: const Key('workforce-admin-add-worker'),
        onPressed: () =>
            _showWorkerDialog(context, language, controller, state),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(_t(language, 'add_worker')),
      ),
      child: foundation.workers.isEmpty
          ? _Empty(text: _t(language, 'empty_workers'))
          : Column(
              children: [
                for (final worker in foundation.workers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _WorkerCard(
                      language: language,
                      worker: worker,
                      onEdit: () => _showWorkerDialog(
                        context,
                        language,
                        controller,
                        state,
                        worker: worker,
                      ),
                      onTransfer: () => _showAssignmentDialog(
                        context,
                        language,
                        controller,
                        state,
                        worker,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.language,
    required this.worker,
    required this.onEdit,
    required this.onTransfer,
  });

  final AppLanguage language;
  final YorksWorkforceWorker worker;
  final VoidCallback onEdit;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final assignment = worker.effectiveAssignment;
    final destination =
        assignment?.projectName ??
        assignment?.internalLocationName ??
        assignment?.teamName ??
        _t(language, 'unassigned');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 240, maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(worker.fullName, style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${worker.number} · ${worker.designation}'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${_t(language, worker.status.wireValue)} · $destination',
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(_t(language, 'edit_worker')),
                ),
                FilledButton.tonalIcon(
                  onPressed: onTransfer,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(_t(language, 'transfer_worker')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamsSection extends StatelessWidget {
  const _TeamsSection({
    required this.language,
    required this.state,
    required this.controller,
  });

  final AppLanguage language;
  final YorksWorkforceAdministrationState state;
  final YorksWorkforceAdministrationController controller;

  @override
  Widget build(BuildContext context) {
    final teams = state.foundation!.teams;
    return _Panel(
      title: _t(language, 'teams'),
      action: FilledButton.icon(
        key: const Key('workforce-admin-add-team'),
        onPressed: () => _showTeamDialog(context, language, controller, state),
        icon: const Icon(Icons.group_add_outlined),
        label: Text(_t(language, 'add_team')),
      ),
      child: teams.isEmpty
          ? _Empty(text: _t(language, 'empty_teams'))
          : Column(
              children: [
                for (final team in teams)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      minVerticalPadding: AppSpacing.md,
                      title: Text(team.name),
                      subtitle: Text(
                        '${team.code} · ${team.isActive ? _t(language, 'active') : _t(language, 'inactive')}',
                      ),
                      trailing: IconButton(
                        tooltip: _t(language, 'edit'),
                        onPressed: () => _showTeamDialog(
                          context,
                          language,
                          controller,
                          state,
                          team: team,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.action,
    required this.child,
  });

  final String title;
  final Widget action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Text(title, style: AppTypography.titleLarge),
              action,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
    child: Center(child: Text(text, textAlign: TextAlign.center)),
  );
}

class _SetupSection extends StatelessWidget {
  const _SetupSection({
    required this.language,
    required this.state,
    required this.controller,
  });

  final AppLanguage language;
  final YorksWorkforceAdministrationState state;
  final YorksWorkforceAdministrationController controller;

  @override
  Widget build(BuildContext context) {
    final foundation = state.foundation!;
    final configuration = state.configuration;
    return Column(
      children: [
        _Panel(
          title: _t(language, 'trades_locations'),
          action: Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showCodeNameDialog(
                  context,
                  language,
                  titleKey: 'add_trade',
                  onSave: (payload) => controller.saveTrade(payload),
                  codeKey: 'trade_code',
                  nameKey: 'trade_name',
                  idKey: 'trade_id',
                ),
                icon: const Icon(Icons.handyman_outlined),
                label: Text(_t(language, 'add_trade')),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showCodeNameDialog(
                  context,
                  language,
                  titleKey: 'add_location',
                  onSave: (payload) => controller.saveInternalLocation(payload),
                  codeKey: 'location_code',
                  nameKey: 'location_name',
                  idKey: 'internal_location_id',
                  includeDepartment: true,
                ),
                icon: const Icon(Icons.business_outlined),
                label: Text(_t(language, 'add_location')),
              ),
            ],
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final trade in foundation.trades)
                ActionChip(
                  avatar: const Icon(Icons.handyman_outlined, size: 18),
                  label: Text('${trade.code} · ${trade.name}'),
                  onPressed: () => _showCodeNameDialog(
                    context,
                    language,
                    titleKey: 'edit_trade',
                    onSave: (payload) => controller.saveTrade(
                      payload,
                      expectedVersion: trade.recordVersion,
                    ),
                    codeKey: 'trade_code',
                    nameKey: 'trade_name',
                    idKey: 'trade_id',
                    id: trade.id,
                    initialCode: trade.code,
                    initialName: trade.name,
                    initialDescription: trade.description,
                    initialActive: trade.isActive,
                  ),
                ),
              for (final location in foundation.internalLocations)
                ActionChip(
                  avatar: const Icon(Icons.business_outlined, size: 18),
                  label: Text('${location.code} · ${location.name}'),
                  onPressed: () => _showCodeNameDialog(
                    context,
                    language,
                    titleKey: 'edit_location',
                    onSave: (payload) => controller.saveInternalLocation(
                      payload,
                      expectedVersion: location.recordVersion,
                    ),
                    codeKey: 'location_code',
                    nameKey: 'location_name',
                    idKey: 'internal_location_id',
                    id: location.id,
                    initialCode: location.code,
                    initialName: location.name,
                    initialDepartment: location.department,
                    initialActive: location.isActive,
                    includeDepartment: true,
                  ),
                ),
              if (foundation.trades.isEmpty &&
                  foundation.internalLocations.isEmpty)
                Text(_t(language, 'empty_setup')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Panel(
          title: _t(language, 'calendars_shifts'),
          action: Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    _showCalendarDialog(context, language, controller),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_t(language, 'add_calendar')),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showShiftDialog(context, language, controller),
                icon: const Icon(Icons.schedule_outlined),
                label: Text(_t(language, 'add_shift')),
              ),
              FilledButton.tonalIcon(
                onPressed: configuration == null
                    ? null
                    : () => _showScheduleDialog(
                        context,
                        language,
                        controller,
                        state,
                      ),
                icon: const Icon(Icons.event_available_outlined),
                label: Text(_t(language, 'link_schedule')),
              ),
            ],
          ),
          child: configuration == null
              ? Text(_t(language, 'load_failed'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final calendar in configuration.calendars)
                      ListTile(
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: Text(calendar.name),
                        subtitle: Text(
                          '${calendar.code} · ${calendar.timezoneName}',
                        ),
                        trailing: IconButton(
                          tooltip: _t(language, 'edit'),
                          onPressed: () => _showCalendarDialog(
                            context,
                            language,
                            controller,
                            calendar: calendar,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    for (final shift in configuration.shiftTemplates)
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(shift.name),
                        subtitle: Text(
                          '${shift.code} · ${shift.scheduledMinutes} ${_t(language, 'minutes')}',
                        ),
                        trailing: IconButton(
                          tooltip: _t(language, 'edit'),
                          onPressed: () => _showShiftDialog(
                            context,
                            language,
                            controller,
                            shift: shift,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    for (final schedule in configuration.teamScheduleLinks)
                      ListTile(
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(schedule.teamName),
                        subtitle: Text(
                          '${schedule.calendarName} · ${schedule.validFrom}',
                        ),
                        trailing: IconButton(
                          tooltip: _t(language, 'edit'),
                          onPressed: () => _showScheduleDialog(
                            context,
                            language,
                            controller,
                            state,
                            schedule: schedule,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    if (configuration.calendars.isEmpty &&
                        configuration.shiftTemplates.isEmpty &&
                        configuration.teamScheduleLinks.isEmpty)
                      _Empty(text: _t(language, 'empty_setup')),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AccessSection extends StatelessWidget {
  const _AccessSection({required this.language});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _InfoCard(
        icon: Icons.manage_accounts_outlined,
        title: _t(language, 'app_users'),
        body: _t(language, 'app_users_body'),
        action: FilledButton.icon(
          onPressed: () => context.go('/users'),
          icon: const Icon(Icons.open_in_new),
          label: Text(_t(language, 'open_user_management')),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _InfoCard(
        icon: Icons.fact_check_outlined,
        title: _t(language, 'attendance_access_title'),
        body: _t(language, 'attendance_access_body'),
      ),
      const SizedBox(height: AppSpacing.lg),
      _InfoCard(
        icon: Icons.history_outlined,
        title: _t(language, 'history_title'),
        body: _t(language, 'history_body'),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(body, style: AppTypography.bodyMedium),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showWorkerDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller,
  YorksWorkforceAdministrationState state, {
  YorksWorkforceWorker? worker,
}) async {
  final formKey = GlobalKey<FormState>();
  final number = TextEditingController(text: worker?.number);
  final name = TextEditingController(text: worker?.fullName);
  final preferred = TextEditingController(text: worker?.preferredDisplayName);
  final designation = TextEditingController(text: worker?.designation);
  final department = TextEditingController(text: worker?.department);
  final employer = TextEditingController(text: worker?.employerCompany);
  final mobile = TextEditingController(text: worker?.mobileNumber);
  final joining = TextEditingController(
    text: worker?.joiningDate ?? _todayIso(),
  );
  final leaving = TextEditingController(text: worker?.leavingDate);
  final notes = TextEditingController(text: worker?.notes);
  var type = worker?.workerType ?? YorksWorkforceWorkerType.yorksEmployee;
  var status = worker?.status ?? YorksWorkforceWorkerStatus.active;
  var tradeId = worker?.tradeId ?? '';
  var linkedUserId = worker?.linkedAuthUserId ?? '';
  var submitting = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: !submitting,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          _t(language, worker == null ? 'add_worker' : 'edit_worker'),
        ),
        content: SizedBox(
          width: 640,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _requiredField(number, _t(language, 'worker_number')),
                  _requiredField(name, _t(language, 'full_name')),
                  _requiredField(designation, _t(language, 'designation')),
                  _requiredField(employer, _t(language, 'employer')),
                  _requiredDateField(joining, _t(language, 'joining_date')),
                  ExpansionTile(
                    key: const Key('workforce-worker-optional-details'),
                    title: Text(_t(language, 'optional_details')),
                    initiallyExpanded: worker != null,
                    children: [
                      _field(preferred, _t(language, 'preferred_name')),
                      _field(department, _t(language, 'department')),
                      DropdownButtonFormField<YorksWorkforceWorkerType>(
                        isExpanded: true,
                        initialValue: type,
                        decoration: _decoration(_t(language, 'worker_type')),
                        items: [
                          for (final option in YorksWorkforceWorkerType.values)
                            DropdownMenuItem(
                              value: option,
                              child: Text(
                                _t(language, option.wireValue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                if (value != null) type = value;
                              }),
                      ),
                      DropdownButtonFormField<YorksWorkforceWorkerStatus>(
                        isExpanded: true,
                        initialValue: status,
                        decoration: _decoration(_t(language, 'status')),
                        items: [
                          for (final option
                              in YorksWorkforceWorkerStatus.values)
                            DropdownMenuItem(
                              value: option,
                              child: Text(
                                _t(language, option.wireValue),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                if (value != null) status = value;
                              }),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: tradeId,
                        decoration: _decoration(_t(language, 'trade')),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(_t(language, 'none')),
                          ),
                          for (final trade in state.foundation!.trades)
                            DropdownMenuItem(
                              value: trade.id,
                              child: Text(
                                '${trade.code} · ${trade.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                tradeId = value ?? '';
                              }),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: linkedUserId,
                        decoration: _decoration(_t(language, 'linked_user')),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(_t(language, 'none')),
                          ),
                          for (final user in state.options!.users)
                            DropdownMenuItem(
                              value: user.authUserId,
                              child: Text(
                                '${user.displayName} · ${user.exactRole}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                linkedUserId = value ?? '';
                              }),
                      ),
                      _field(mobile, _t(language, 'mobile')),
                      _dateField(leaving, _t(language, 'leaving_date')),
                      _field(notes, _t(language, 'notes'), maxLines: 3),
                    ].separatedBy(const SizedBox(height: AppSpacing.md)),
                  ),
                ].separatedBy(const SizedBox(height: AppSpacing.md)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: Text(_t(language, 'cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;
                    if (status == YorksWorkforceWorkerStatus.leftCompany &&
                        leaving.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_t(language, 'leaving_required')),
                        ),
                      );
                      return;
                    }
                    setDialogState(() => submitting = true);
                    final saved = await controller.saveWorker({
                      'worker_id': worker?.id,
                      'worker_number': number.text.trim(),
                      'full_name': name.text.trim(),
                      'preferred_display_name': preferred.text.trim(),
                      'designation': designation.text.trim(),
                      'trade_id': _nullIfEmpty(tradeId),
                      'department': department.text.trim(),
                      'employer_company': employer.text.trim(),
                      'worker_type': type.wireValue,
                      'mobile_number': mobile.text.trim(),
                      'joining_date': joining.text.trim(),
                      'leaving_date': _nullIfEmpty(leaving.text),
                      'current_status': status.wireValue,
                      'linked_auth_user_id': _nullIfEmpty(linkedUserId),
                      'notes': notes.text.trim(),
                    }, expectedVersion: worker?.recordVersion);
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext);
                    } else if (dialogContext.mounted) {
                      setDialogState(() => submitting = false);
                    }
                  },
            child: Text(_t(language, 'save')),
          ),
        ],
      ),
    ),
  );
  for (final controller in [
    number,
    name,
    preferred,
    designation,
    department,
    employer,
    mobile,
    joining,
    leaving,
    notes,
  ]) {
    controller.dispose();
  }
}

Future<void> _showAssignmentDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller,
  YorksWorkforceAdministrationState state,
  YorksWorkforceWorker worker,
) async {
  final formKey = GlobalKey<FormState>();
  final current = worker.effectiveAssignment;
  final validFrom = TextEditingController(text: _todayIso());
  final validTo = TextEditingController();
  final reason = TextEditingController();
  var kind = current?.kind ?? 'primary';
  var teamId = current?.teamId ?? '';
  var supervisorId = current?.supervisorAuthUserId ?? '';
  var projectId = current?.projectId ?? '';
  var scopeId = current?.projectScopeId ?? '';
  var locationId = current?.internalLocationId ?? '';
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedProject = state.options!.projects
            .where((project) => project.id == projectId)
            .firstOrNull;
        return AlertDialog(
          title: Text(
            '${_t(language, 'transfer_worker')} · ${worker.fullName}',
          ),
          content: SizedBox(
            width: 640,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: _decoration(_t(language, 'assignment_kind')),
                      items: [
                        DropdownMenuItem(
                          value: 'primary',
                          child: Text(_t(language, 'primary')),
                        ),
                        DropdownMenuItem(
                          value: 'temporary',
                          child: Text(_t(language, 'temporary')),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              kind = value ?? 'primary';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: teamId,
                      decoration: _decoration(_t(language, 'teams')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final team in state.foundation!.teams.where(
                          (team) => team.isActive,
                        ))
                          DropdownMenuItem(
                            value: team.id,
                            child: Text('${team.code} · ${team.name}'),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              teamId = value ?? '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: supervisorId,
                      decoration: _decoration(_t(language, 'supervisor')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final user in state.options!.users.where(
                          (user) => user.isActive,
                        ))
                          DropdownMenuItem(
                            value: user.authUserId,
                            child: Text(user.displayName),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              supervisorId = value ?? '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: projectId,
                      decoration: _decoration(_t(language, 'project')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final project in state.options!.projects.where(
                          (project) => project.state == 'active',
                        ))
                          DropdownMenuItem(
                            value: project.id,
                            child: Text(
                              '${project.reference} · ${project.name}',
                            ),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              projectId = value ?? '';
                              scopeId = '';
                              if (projectId.isNotEmpty) locationId = '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('assignment-scope-$projectId'),
                      initialValue: scopeId,
                      decoration: _decoration(_t(language, 'project_scope')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final scope
                            in selectedProject?.scopes.where(
                                  (scope) => scope.isActive,
                                ) ??
                                const <
                                  YorksWorkforceAdministrationScopeOption
                                >[])
                          DropdownMenuItem(
                            value: scope.id,
                            child: Text('${scope.code} · ${scope.name}'),
                          ),
                      ],
                      onChanged: submitting || projectId.isEmpty
                          ? null
                          : (value) => setDialogState(() {
                              scopeId = value ?? '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('assignment-location-$projectId'),
                      initialValue: locationId,
                      decoration: _decoration(
                        _t(language, 'internal_location'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final location
                            in state.foundation!.internalLocations.where(
                              (location) => location.isActive,
                            ))
                          DropdownMenuItem(
                            value: location.id,
                            child: Text('${location.code} · ${location.name}'),
                          ),
                      ],
                      onChanged: submitting || projectId.isNotEmpty
                          ? null
                          : (value) => setDialogState(() {
                              locationId = value ?? '';
                            }),
                    ),
                    _requiredDateField(validFrom, _t(language, 'valid_from')),
                    _dateField(validTo, _t(language, 'valid_to')),
                    _requiredField(reason, _t(language, 'reason'), maxLines: 2),
                  ].separatedBy(const SizedBox(height: AppSpacing.md)),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: Text(_t(language, 'cancel')),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (formKey.currentState?.validate() != true) return;
                      if (kind == 'temporary' && validTo.text.trim().isEmpty) {
                        _snack(context, _t(language, 'temporary_end_required'));
                        return;
                      }
                      if (teamId.isEmpty &&
                          supervisorId.isEmpty &&
                          projectId.isEmpty &&
                          locationId.isEmpty) {
                        _snack(
                          context,
                          _t(language, 'assignment_target_required'),
                        );
                        return;
                      }
                      setDialogState(() => submitting = true);
                      final saved = await controller.transferWorkerAssignment(
                        {
                          'worker_id': worker.id,
                          'assignment_kind': kind,
                          'team_id': _nullIfEmpty(teamId),
                          'supervisor_auth_user_id': _nullIfEmpty(supervisorId),
                          'project_id': _nullIfEmpty(projectId),
                          'project_scope_id': _nullIfEmpty(scopeId),
                          'internal_location_id': _nullIfEmpty(locationId),
                          'valid_from': validFrom.text.trim(),
                          'valid_to': _nullIfEmpty(validTo.text),
                          'reason': reason.text.trim(),
                        },
                        expectedCurrentAssignmentId: current?.kind == kind
                            ? current?.id
                            : null,
                        expectedCurrentVersion: current?.kind == kind
                            ? current?.recordVersion
                            : null,
                      );
                      if (dialogContext.mounted && saved) {
                        Navigator.pop(dialogContext);
                      } else if (dialogContext.mounted) {
                        setDialogState(() => submitting = false);
                      }
                    },
              child: Text(_t(language, 'save')),
            ),
          ],
        );
      },
    ),
  );
  validFrom.dispose();
  validTo.dispose();
  reason.dispose();
}

Future<void> _showTeamDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller,
  YorksWorkforceAdministrationState state, {
  YorksWorkforceTeam? team,
}) async {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController(text: team?.code);
  final name = TextEditingController(text: team?.name);
  final department = TextEditingController(text: team?.department);
  final validFrom = TextEditingController(text: team?.validFrom ?? _todayIso());
  final validTo = TextEditingController(text: team?.validTo);
  var supervisorId = team?.defaultSupervisorAuthUserId ?? '';
  var projectId = team?.defaultProjectId ?? '';
  var scopeId = team?.defaultProjectScopeId ?? '';
  var locationId = team?.defaultInternalLocationId ?? '';
  var active = team?.isActive ?? true;
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedProject = state.options!.projects
            .where((project) => project.id == projectId)
            .firstOrNull;
        return AlertDialog(
          title: Text(_t(language, team == null ? 'add_team' : 'edit_team')),
          content: SizedBox(
            width: 640,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _requiredField(code, _t(language, 'team_code')),
                    _requiredField(name, _t(language, 'team_name')),
                    _field(department, _t(language, 'department')),
                    DropdownButtonFormField<String>(
                      initialValue: supervisorId,
                      decoration: _decoration(_t(language, 'supervisor')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final user in state.options!.users.where(
                          (user) => user.isActive,
                        ))
                          DropdownMenuItem(
                            value: user.authUserId,
                            child: Text(user.displayName),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              supervisorId = value ?? '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: projectId,
                      decoration: _decoration(_t(language, 'project')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final project in state.options!.projects.where(
                          (project) => project.state == 'active',
                        ))
                          DropdownMenuItem(
                            value: project.id,
                            child: Text(
                              '${project.reference} · ${project.name}',
                            ),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() {
                              projectId = value ?? '';
                              scopeId = '';
                              if (projectId.isNotEmpty) locationId = '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('team-scope-$projectId'),
                      initialValue: scopeId,
                      decoration: _decoration(_t(language, 'project_scope')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final scope
                            in selectedProject?.scopes.where(
                                  (scope) => scope.isActive,
                                ) ??
                                const <
                                  YorksWorkforceAdministrationScopeOption
                                >[])
                          DropdownMenuItem(
                            value: scope.id,
                            child: Text('${scope.code} · ${scope.name}'),
                          ),
                      ],
                      onChanged: submitting || projectId.isEmpty
                          ? null
                          : (value) => setDialogState(() {
                              scopeId = value ?? '';
                            }),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('team-location-$projectId'),
                      initialValue: locationId,
                      decoration: _decoration(
                        _t(language, 'internal_location'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(_t(language, 'none')),
                        ),
                        for (final location
                            in state.foundation!.internalLocations.where(
                              (location) => location.isActive,
                            ))
                          DropdownMenuItem(
                            value: location.id,
                            child: Text('${location.code} · ${location.name}'),
                          ),
                      ],
                      onChanged: submitting || projectId.isNotEmpty
                          ? null
                          : (value) => setDialogState(() {
                              locationId = value ?? '';
                            }),
                    ),
                    _requiredDateField(validFrom, _t(language, 'valid_from')),
                    _dateField(validTo, _t(language, 'valid_to')),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_t(language, 'active')),
                      value: active,
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(() => active = value),
                    ),
                  ].separatedBy(const SizedBox(height: AppSpacing.md)),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: Text(_t(language, 'cancel')),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (formKey.currentState?.validate() != true) return;
                      setDialogState(() => submitting = true);
                      final saved = await controller.saveTeam({
                        'team_id': team?.id,
                        'team_code': code.text.trim(),
                        'team_name': name.text.trim(),
                        'department': department.text.trim(),
                        'default_supervisor_auth_user_id': _nullIfEmpty(
                          supervisorId,
                        ),
                        'default_project_id': _nullIfEmpty(projectId),
                        'default_project_scope_id': _nullIfEmpty(scopeId),
                        'default_internal_location_id': _nullIfEmpty(
                          locationId,
                        ),
                        'valid_from': validFrom.text.trim(),
                        'valid_to': _nullIfEmpty(validTo.text),
                        'is_active': active,
                      }, expectedVersion: team?.recordVersion);
                      if (dialogContext.mounted && saved) {
                        Navigator.pop(dialogContext);
                      } else if (dialogContext.mounted) {
                        setDialogState(() => submitting = false);
                      }
                    },
              child: Text(_t(language, 'save')),
            ),
          ],
        );
      },
    ),
  );
  code.dispose();
  name.dispose();
  department.dispose();
  validFrom.dispose();
  validTo.dispose();
}

Future<void> _showCodeNameDialog(
  BuildContext context,
  AppLanguage language, {
  required String titleKey,
  required Future<bool> Function(Map<String, Object?>) onSave,
  required String codeKey,
  required String nameKey,
  required String idKey,
  String? id,
  String? initialCode,
  String? initialName,
  String? initialDescription,
  String? initialDepartment,
  bool initialActive = true,
  bool includeDepartment = false,
}) async {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController(text: initialCode);
  final name = TextEditingController(text: initialName);
  final description = TextEditingController(text: initialDescription);
  final department = TextEditingController(text: initialDepartment);
  var active = initialActive;
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(_t(language, titleKey)),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(code, _t(language, 'code')),
                _requiredField(name, _t(language, 'name')),
                if (includeDepartment)
                  _field(department, _t(language, 'department'))
                else
                  _field(description, _t(language, 'description')),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t(language, 'active')),
                  value: active,
                  onChanged: submitting
                      ? null
                      : (value) => setDialogState(() => active = value),
                ),
              ].separatedBy(const SizedBox(height: AppSpacing.md)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: Text(_t(language, 'cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;
                    setDialogState(() => submitting = true);
                    final saved = await onSave({
                      idKey: id,
                      codeKey: code.text.trim(),
                      nameKey: name.text.trim(),
                      if (includeDepartment)
                        'department': department.text.trim()
                      else
                        'description': description.text.trim(),
                      'is_active': active,
                    });
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext);
                    } else if (dialogContext.mounted) {
                      setDialogState(() => submitting = false);
                    }
                  },
            child: Text(_t(language, 'save')),
          ),
        ],
      ),
    ),
  );
  code.dispose();
  name.dispose();
  description.dispose();
  department.dispose();
}

Future<void> _showCalendarDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller, {
  YorksWorkforceCalendarConfiguration? calendar,
}) async {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController(text: calendar?.code);
  final name = TextEditingController(text: calendar?.name);
  final timezone = TextEditingController(text: calendar?.timezoneName);
  final scheduled = TextEditingController(
    text: calendar?.standardScheduledMinutes.toString(),
  );
  final breakMinutes = TextEditingController(
    text: calendar?.breakMinutes.toString(),
  );
  final validFrom = TextEditingController(
    text: calendar?.validFrom ?? _todayIso(),
  );
  final validTo = TextEditingController(text: calendar?.validTo);
  final workingDays = <int>{
    ...?calendar?.weekdays
        .where(
          (weekday) =>
              weekday.dayType == YorksWorkforceDayType.regularWorkingDay,
        )
        .map((weekday) => weekday.isoWeekday),
  };
  var active = calendar?.isActive ?? true;
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          _t(language, calendar == null ? 'add_calendar' : 'edit_calendar'),
        ),
        content: SizedBox(
          width: 640,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _requiredField(code, _t(language, 'code')),
                  _requiredField(name, _t(language, 'name')),
                  _requiredField(timezone, _t(language, 'timezone')),
                  _requiredIntegerField(
                    scheduled,
                    _t(language, 'scheduled_minutes'),
                    minimum: 1,
                  ),
                  _requiredIntegerField(
                    breakMinutes,
                    _t(language, 'break_minutes'),
                    minimum: 0,
                  ),
                  _requiredDateField(validFrom, _t(language, 'valid_from')),
                  _dateField(validTo, _t(language, 'valid_to')),
                  Text(
                    _t(language, 'working_days'),
                    style: AppTypography.titleSmall,
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var day = 1; day <= 7; day += 1)
                        FilterChip(
                          label: Text(_t(language, 'weekday_$day')),
                          selected: workingDays.contains(day),
                          onSelected: submitting
                              ? null
                              : (selected) => setDialogState(() {
                                  if (selected) {
                                    workingDays.add(day);
                                  } else {
                                    workingDays.remove(day);
                                  }
                                }),
                        ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t(language, 'active')),
                    value: active,
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() => active = value),
                  ),
                ].separatedBy(const SizedBox(height: AppSpacing.md)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: Text(_t(language, 'cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;
                    if (workingDays.isEmpty) {
                      _snack(context, _t(language, 'working_day_required'));
                      return;
                    }
                    setDialogState(() => submitting = true);
                    final saved = await controller.saveCalendar({
                      'calendar_id': calendar?.id,
                      'calendar_code': code.text.trim(),
                      'calendar_name': name.text.trim(),
                      'timezone_name': timezone.text.trim(),
                      'standard_scheduled_minutes': int.parse(
                        scheduled.text.trim(),
                      ),
                      'break_minutes': int.parse(breakMinutes.text.trim()),
                      'valid_from': validFrom.text.trim(),
                      'valid_to': _nullIfEmpty(validTo.text),
                      'is_active': active,
                      'weekdays': [
                        for (var day = 1; day <= 7; day += 1)
                          {
                            'iso_weekday': day,
                            'day_type': workingDays.contains(day)
                                ? 'regular_working_day'
                                : 'weekly_off',
                          },
                      ],
                    }, expectedVersion: calendar?.recordVersion);
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext);
                    } else if (dialogContext.mounted) {
                      setDialogState(() => submitting = false);
                    }
                  },
            child: Text(_t(language, 'save')),
          ),
        ],
      ),
    ),
  );
  for (final controller in [
    code,
    name,
    timezone,
    scheduled,
    breakMinutes,
    validFrom,
    validTo,
  ]) {
    controller.dispose();
  }
}

Future<void> _showShiftDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller, {
  YorksWorkforceShiftTemplate? shift,
}) async {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController(text: shift?.code);
  final name = TextEditingController(text: shift?.name);
  final start = TextEditingController(text: shift?.startTime);
  final end = TextEditingController(text: shift?.endTime);
  final scheduled = TextEditingController(
    text: shift?.scheduledMinutes.toString(),
  );
  final breakMinutes = TextEditingController(
    text: shift?.breakMinutes.toString(),
  );
  final validFrom = TextEditingController(
    text: shift?.validFrom ?? _todayIso(),
  );
  final validTo = TextEditingController(text: shift?.validTo);
  var kind = shift?.kind ?? YorksWorkforceShiftKind.normalSite;
  var active = shift?.isActive ?? true;
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(_t(language, shift == null ? 'add_shift' : 'edit_shift')),
        content: SizedBox(
          width: 640,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _requiredField(code, _t(language, 'code')),
                  _requiredField(name, _t(language, 'name')),
                  DropdownButtonFormField<YorksWorkforceShiftKind>(
                    initialValue: kind,
                    decoration: _decoration(_t(language, 'shift_kind')),
                    items: [
                      for (final option in YorksWorkforceShiftKind.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(_t(language, option.wireValue)),
                        ),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() {
                            if (value != null) kind = value;
                          }),
                  ),
                  _timeField(start, _t(language, 'start_time')),
                  _timeField(end, _t(language, 'end_time')),
                  _requiredIntegerField(
                    scheduled,
                    _t(language, 'scheduled_minutes'),
                    minimum: 1,
                  ),
                  _requiredIntegerField(
                    breakMinutes,
                    _t(language, 'break_minutes'),
                    minimum: 0,
                  ),
                  _requiredDateField(validFrom, _t(language, 'valid_from')),
                  _dateField(validTo, _t(language, 'valid_to')),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t(language, 'active')),
                    value: active,
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() => active = value),
                  ),
                ].separatedBy(const SizedBox(height: AppSpacing.md)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: Text(_t(language, 'cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;
                    if ((start.text.trim().isEmpty) !=
                        (end.text.trim().isEmpty)) {
                      _snack(context, _t(language, 'both_times_required'));
                      return;
                    }
                    setDialogState(() => submitting = true);
                    final saved = await controller.saveShift({
                      'shift_template_id': shift?.id,
                      'shift_code': code.text.trim(),
                      'shift_name': name.text.trim(),
                      'shift_kind': kind.wireValue,
                      'start_time': _nullIfEmpty(start.text),
                      'end_time': _nullIfEmpty(end.text),
                      'scheduled_minutes': int.parse(scheduled.text.trim()),
                      'break_minutes': int.parse(breakMinutes.text.trim()),
                      'valid_from': validFrom.text.trim(),
                      'valid_to': _nullIfEmpty(validTo.text),
                      'is_active': active,
                    }, expectedVersion: shift?.recordVersion);
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext);
                    } else if (dialogContext.mounted) {
                      setDialogState(() => submitting = false);
                    }
                  },
            child: Text(_t(language, 'save')),
          ),
        ],
      ),
    ),
  );
  for (final controller in [
    code,
    name,
    start,
    end,
    scheduled,
    breakMinutes,
    validFrom,
    validTo,
  ]) {
    controller.dispose();
  }
}

Future<void> _showScheduleDialog(
  BuildContext context,
  AppLanguage language,
  YorksWorkforceAdministrationController controller,
  YorksWorkforceAdministrationState state, {
  YorksWorkforceTeamScheduleLink? schedule,
}) async {
  final configuration = state.configuration!;
  final formKey = GlobalKey<FormState>();
  final validFrom = TextEditingController(
    text: schedule?.validFrom ?? _todayIso(),
  );
  final validTo = TextEditingController(text: schedule?.validTo);
  final reason = TextEditingController(text: schedule?.reason);
  var teamId = schedule?.teamId ?? '';
  var calendarId = schedule?.calendarId ?? '';
  var shiftId = schedule?.shiftTemplateId ?? '';
  var submitting = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(_t(language, 'link_schedule')),
        content: SizedBox(
          width: 620,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: teamId,
                    decoration: _decoration(_t(language, 'teams')),
                    validator: _requiredSelection(language),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(_t(language, 'none')),
                      ),
                      for (final team in state.foundation!.teams.where(
                        (team) => team.isActive,
                      ))
                        DropdownMenuItem(
                          value: team.id,
                          child: Text('${team.code} · ${team.name}'),
                        ),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() {
                            teamId = value ?? '';
                          }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: calendarId,
                    decoration: _decoration(_t(language, 'calendar')),
                    validator: _requiredSelection(language),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(_t(language, 'none')),
                      ),
                      for (final calendar in configuration.calendars.where(
                        (calendar) => calendar.isActive,
                      ))
                        DropdownMenuItem(
                          value: calendar.id,
                          child: Text('${calendar.code} · ${calendar.name}'),
                        ),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() {
                            calendarId = value ?? '';
                          }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: shiftId,
                    decoration: _decoration(_t(language, 'shift')),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(_t(language, 'none')),
                      ),
                      for (final shift in configuration.shiftTemplates.where(
                        (shift) => shift.isActive,
                      ))
                        DropdownMenuItem(
                          value: shift.id,
                          child: Text('${shift.code} · ${shift.name}'),
                        ),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) => setDialogState(() {
                            shiftId = value ?? '';
                          }),
                  ),
                  _requiredDateField(validFrom, _t(language, 'valid_from')),
                  _dateField(validTo, _t(language, 'valid_to')),
                  _requiredField(reason, _t(language, 'reason'), maxLines: 2),
                ].separatedBy(const SizedBox(height: AppSpacing.md)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(dialogContext),
            child: Text(_t(language, 'cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;
                    setDialogState(() => submitting = true);
                    final saved = await controller.saveTeamSchedule({
                      'team_schedule_link_id': schedule?.id,
                      'team_id': teamId,
                      'calendar_id': calendarId,
                      'shift_template_id': _nullIfEmpty(shiftId),
                      'valid_from': validFrom.text.trim(),
                      'valid_to': _nullIfEmpty(validTo.text),
                      'reason': reason.text.trim(),
                    }, expectedVersion: schedule?.recordVersion);
                    if (dialogContext.mounted && saved) {
                      Navigator.pop(dialogContext);
                    } else if (dialogContext.mounted) {
                      setDialogState(() => submitting = false);
                    }
                  },
            child: Text(_t(language, 'save')),
          ),
        ],
      ),
    ),
  );
  validFrom.dispose();
  validTo.dispose();
  reason.dispose();
}

InputDecoration _decoration(String label) => InputDecoration(
  labelText: label,
  border: const OutlineInputBorder(),
  alignLabelWithHint: true,
);

TextFormField _field(
  TextEditingController controller,
  String label, {
  int maxLines = 1,
}) => TextFormField(
  controller: controller,
  decoration: _decoration(label),
  maxLines: maxLines,
);

TextFormField _requiredField(
  TextEditingController controller,
  String label, {
  int maxLines = 1,
}) => TextFormField(
  controller: controller,
  decoration: _decoration(label),
  maxLines: maxLines,
  validator: (value) => value == null || value.trim().isEmpty ? label : null,
);

TextFormField _requiredDateField(
  TextEditingController controller,
  String label,
) => TextFormField(
  controller: controller,
  decoration: _decoration(label).copyWith(hintText: 'YYYY-MM-DD'),
  keyboardType: TextInputType.datetime,
  validator: (value) => _validateDate(value, required: true),
);

TextFormField _dateField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      decoration: _decoration(label).copyWith(hintText: 'YYYY-MM-DD'),
      keyboardType: TextInputType.datetime,
      validator: (value) => _validateDate(value, required: false),
    );

TextFormField _timeField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      decoration: _decoration(label).copyWith(hintText: 'HH:MM'),
      keyboardType: TextInputType.datetime,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return null;
        return RegExp(
              r'^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$',
            ).hasMatch(text)
            ? null
            : label;
      },
    );

TextFormField _requiredIntegerField(
  TextEditingController controller,
  String label, {
  required int minimum,
}) => TextFormField(
  controller: controller,
  decoration: _decoration(label),
  keyboardType: TextInputType.number,
  validator: (value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < minimum ? label : null;
  },
);

String? Function(String?) _requiredSelection(AppLanguage language) =>
    (value) => value == null || value.isEmpty ? _t(language, 'required') : null;

String? _validateDate(String? value, {required bool required}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return required ? 'YYYY-MM-DD' : null;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return 'YYYY-MM-DD';
  final parsed = DateTime.tryParse(text);
  if (parsed == null || _isoDate(parsed) != text) return 'YYYY-MM-DD';
  return null;
}

String _todayIso() => _isoDate(DateTime.now());

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String? _nullIfEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _t(AppLanguage language, String key) =>
    YorksV1WorkforceAdministrationStrings.text(language, key);

extension _SeparatedWidgets on Iterable<Widget> {
  List<Widget> separatedBy(Widget separator) {
    final output = <Widget>[];
    for (final widget in this) {
      if (output.isNotEmpty) output.add(separator);
      output.add(widget);
    }
    return output;
  }
}
