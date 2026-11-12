import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/audit_log.dart';
import '../../../../shared/models/material_plan.dart';
import '../../../../shared/models/material_request.dart';
import '../../../../shared/models/project.dart';
import '../../../../shared/models/project_workspace_snapshot.dart';
import '../../../../shared/models/project_workspace_strings.dart';
import '../../../../shared/models/user_role.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/audit_log_provider.dart';
import '../../../../shared/providers/nexus_feature_flags_provider.dart';
import '../../../../shared/providers/project_provider.dart';
import '../../../../shared/providers/project_workspace_provider.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/providers/users_provider.dart';

enum ProjectWorkspaceSection {
  overview,
  materialPlan,
  requests,
  procurement,
  documents,
  activity,
}

/// V7 project container: one role-safe, connected view over existing records.
///
/// This screen is deliberately read-only at the workspace layer. Existing
/// controlled routes remain responsible for workflow mutations.
class ProjectWorkspaceScreen extends ConsumerStatefulWidget {
  const ProjectWorkspaceScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectWorkspaceScreen> createState() =>
      _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState
    extends ConsumerState<ProjectWorkspaceScreen> {
  ProjectWorkspaceSection _section = ProjectWorkspaceSection.overview;

  Future<void> _editProgress(Project project, UserRole role) async {
    if (role == UserRole.procurement) return;
    final stages = await showDialog<List<ProjectProgressStage>>(
      context: context,
      builder: (context) => _ProgressStageDialog(
        initialStages: project.effectiveProgressStages,
        canConfigureStages: role == UserRole.admin,
      ),
    );
    if (stages == null || !mounted) return;
    final saved = await ref
        .read(projectsProvider.notifier)
        .updateProgressStages(project.id, stages);
    if (!saved || !mounted) return;
    await ref.logAudit(
      action: 'Project progress updated',
      module: AuditModule.platform,
      refId: project.id,
      detail:
          '${stages.length} stages · ${stages.weightedProgress.toStringAsFixed(1)}% overall',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ProjectWorkspaceStrings.saveProgress.primary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(nexusFeatureFlagsProvider).projects;
    final snapshot = enabled
        ? ref.watch(projectWorkspaceProvider(widget.projectId))
        : null;
    final lang = ref.watch(languageProvider);
    final role = ref.watch(currentRoleProvider);

    if (snapshot == null) {
      return _UnavailableWorkspace(lang: lang, role: role);
    }

    final project = snapshot.project;
    final users = ref.watch(usersProvider);
    String userName(String? id) {
      if (id == null) return ProjectWorkspaceStrings.unassigned.primary;
      for (final user in users) {
        if (user.id == id) return user.fullName;
      }
      return id;
    }

    final ownerName = _ownerName(snapshot, userName);
    final action = _actionCopy(snapshot.currentAction);
    final actionTarget = _actionTarget(snapshot, role);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: NexusPageShell(
          eyebrow: ProjectWorkspaceStrings.eyebrow.primary,
          title: project.name,
          description: [
            if ((project.yorksReference ?? '').isNotEmpty)
              project.yorksReference!,
            if ((project.clientName ?? '').isNotEmpty) project.clientName!,
            if ((project.siteLocation ?? '').isNotEmpty) project.siteLocation!,
          ].join(' · '),
          actions: [
            if (actionTarget != null)
              PrimaryButton(
                label: actionTarget.label.primary,
                icon: actionTarget.icon,
                isExpanded: false,
                onPressed: () => actionTarget.open(context),
              ),
          ],
          inspector: _WorkspaceInspector(
            snapshot: snapshot,
            lang: lang,
            ownerName: ownerName,
            userName: userName,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CurrentActionCard(
                title: action.title.primary,
                message: action.message.primary,
                ownerLabel: ProjectWorkspaceStrings.currentOwner.primary,
                ownerName: ownerName,
                tone: action.tone,
                icon: action.icon,
              ),
              const SizedBox(height: AppSpacing.lg),
              _BlockersCard(snapshot: snapshot, lang: lang),
              const SizedBox(height: AppSpacing.lg),
              _WorkspaceSectionSelector(
                selected: _section,
                lang: lang,
                onSelected: (section) => setState(() => _section = section),
              ),
              const SizedBox(height: AppSpacing.lg),
              switch (_section) {
                ProjectWorkspaceSection.overview => _OverviewSection(
                  snapshot: snapshot,
                  lang: lang,
                  role: role,
                  userName: userName,
                  onOpenSection: (section) =>
                      setState(() => _section = section),
                  onEditProgress: () => _editProgress(project, role),
                ),
                ProjectWorkspaceSection.materialPlan => _MaterialPlanSection(
                  snapshot: snapshot,
                  lang: lang,
                  role: role,
                ),
                ProjectWorkspaceSection.requests => _RequestsSection(
                  snapshot: snapshot,
                  lang: lang,
                ),
                ProjectWorkspaceSection.procurement => _ProcurementSection(
                  snapshot: snapshot,
                  lang: lang,
                ),
                ProjectWorkspaceSection.documents => _DocumentsSection(
                  snapshot: snapshot,
                  lang: lang,
                  userName: userName,
                ),
                ProjectWorkspaceSection.activity => _ActivitySection(
                  snapshot: snapshot,
                  lang: lang,
                  userName: userName,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableWorkspace extends StatelessWidget {
  const _UnavailableWorkspace({required this.lang, required this.role});

  final AppLanguage lang;
  final UserRole role;

  String get _projectRoute => role.usesAdminPanel
      ? RoutePaths.adminProjects
      : RoutePaths.engineerProjects;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(_projectRoute),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: NexusSectionCard(
              child: Column(
                children: [
                  const Icon(
                    Icons.folder_off_outlined,
                    color: AppColors.muted,
                    size: 40,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  BilingualText(
                    english: ProjectWorkspaceStrings.unavailable.primary,
                    secondary: ProjectWorkspaceStrings.unavailable.secondary(
                      lang,
                    ),
                    englishStyle: AppTypography.headlineSmall,
                    crossAxisAlignment: CrossAxisAlignment.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    ProjectWorkspaceStrings.unavailableBody.primary,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SecondaryButton(
                    label: ProjectWorkspaceStrings.backToProjects.primary,
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => context.go(_projectRoute),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSectionSelector extends StatelessWidget {
  const _WorkspaceSectionSelector({
    required this.selected,
    required this.lang,
    required this.onSelected,
  });

  final ProjectWorkspaceSection selected;
  final AppLanguage lang;
  final ValueChanged<ProjectWorkspaceSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AppSpacing.compactBreakpoint) {
          return DropdownButtonFormField<ProjectWorkspaceSection>(
            key: const ValueKey('project-workspace-mobile-section-selector'),
            initialValue: selected,
            decoration: InputDecoration(
              labelText: ProjectWorkspaceStrings.chooseSection.primary,
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
            items: [
              for (final section in ProjectWorkspaceSection.values)
                DropdownMenuItem(
                  value: section,
                  child: Text(_sectionCopy(section).primary),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
          );
        }

        return Semantics(
          container: true,
          label: ProjectWorkspaceStrings.chooseSection.primary,
          child: SingleChildScrollView(
            key: const ValueKey('project-workspace-desktop-tabs'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final section in ProjectWorkspaceSection.values) ...[
                  _WorkspaceTab(
                    copy: _sectionCopy(section),
                    selected: selected == section,
                    lang: lang,
                    onTap: () => onSelected(section),
                  ),
                  if (section != ProjectWorkspaceSection.values.last)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.copy,
    required this.selected,
    required this.lang,
    required this.onTap,
  });

  final TranslatableString copy;
  final bool selected;
  final AppLanguage lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryContainer
                : AppColors.surfaceContainerLowest,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: BilingualText(
            english: copy.primary,
            secondary: copy.secondary(lang),
            englishStyle: AppTypography.labelLarge.copyWith(
              color: selected ? AppColors.primary : AppColors.onSurface,
            ),
            gap: 2,
          ),
        ),
      ),
    );
  }
}

class _BlockersCard extends StatelessWidget {
  const _BlockersCard({required this.snapshot, required this.lang});

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    final blockers = snapshot.blockers;
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.blockers.primary,
      trailing: blockers.isEmpty
          ? StatusChip.success(ProjectWorkspaceStrings.ready.primary)
          : StatusChip.warning('${blockers.length}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: blockers.isEmpty
          ? Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 20,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: BilingualText(
                    english: ProjectWorkspaceStrings.noBlockers.primary,
                    secondary: ProjectWorkspaceStrings.noBlockers.secondary(
                      lang,
                    ),
                    englishStyle: AppTypography.bodyMedium,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var index = 0; index < blockers.length; index++)
                  _BlockerRow(
                    copy: _blockerCopy(blockers[index]),
                    lang: lang,
                    showDivider: index != blockers.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _BlockerRow extends StatelessWidget {
  const _BlockerRow({
    required this.copy,
    required this.lang,
    required this.showDivider,
  });

  final TranslatableString copy;
  final AppLanguage lang;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: BilingualText(
              english: copy.primary,
              secondary: copy.secondary(lang),
              englishStyle: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.snapshot,
    required this.lang,
    required this.role,
    required this.userName,
    required this.onOpenSection,
    required this.onEditProgress,
  });

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;
  final UserRole role;
  final String Function(String?) userName;
  final ValueChanged<ProjectWorkspaceSection> onOpenSection;
  final VoidCallback onEditProgress;

  @override
  Widget build(BuildContext context) {
    final project = snapshot.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusSectionCard(
          title: ProjectWorkspaceStrings.projectDetails.primary,
          child: _ResponsiveFacts(
            facts: [
              _Fact(
                ProjectWorkspaceStrings.status,
                project.phase == null
                    ? project.lifecycleStatus.name
                    : '${project.phase!.label} · ${project.phase!.state.label}',
              ),
              _Fact(
                ProjectWorkspaceStrings.yorksReference,
                project.yorksReference,
              ),
              _Fact(ProjectWorkspaceStrings.client, project.clientName),
              _Fact(ProjectWorkspaceStrings.site, project.siteLocation),
              _Fact(
                ProjectWorkspaceStrings.jobNumber,
                project.contractOrJobNumber,
              ),
              _Fact(
                ProjectWorkspaceStrings.startDate,
                _formatDate(project.startDate),
              ),
              _Fact(
                ProjectWorkspaceStrings.expectedEnd,
                _formatDate(project.expectedEndDate),
              ),
            ],
            lang: lang,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NexusSectionCard(
          title: ProjectWorkspaceStrings.buildings.primary,
          child: project.buildings.isEmpty
              ? _EmptyText(
                  copy: ProjectWorkspaceStrings.blockerBuilding,
                  lang: lang,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < project.buildings.length;
                      index++
                    )
                      _BuildingRow(
                        building: project.buildings[index],
                        lang: lang,
                        showDivider: index != project.buildings.length - 1,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NexusSectionCard(
          title: ProjectWorkspaceStrings.connectedRecords.primary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 760
                  ? 3
                  : width >= 460
                  ? 2
                  : 1;
              final tileWidth =
                  (width - ((columns - 1) * AppSpacing.md)) / columns;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _ConnectedRecordTile(
                    width: tileWidth,
                    icon: Icons.view_list_outlined,
                    label: ProjectWorkspaceStrings.materialPlan,
                    value: snapshot.materialPlan == null
                        ? ProjectWorkspaceStrings.notRecorded.primary
                        : snapshot.materialPlan!.status.label,
                    onTap: () =>
                        onOpenSection(ProjectWorkspaceSection.materialPlan),
                  ),
                  _ConnectedRecordTile(
                    width: tileWidth,
                    icon: Icons.assignment_outlined,
                    label: ProjectWorkspaceStrings.requests,
                    value: '${snapshot.requests.length}',
                    onTap: () =>
                        onOpenSection(ProjectWorkspaceSection.requests),
                  ),
                  _ConnectedRecordTile(
                    width: tileWidth,
                    icon: Icons.description_outlined,
                    label: ProjectWorkspaceStrings.documents,
                    value: '${project.attachments.length}',
                    onTap: () =>
                        onOpenSection(ProjectWorkspaceSection.documents),
                  ),
                  _ConnectedRecordTile(
                    width: tileWidth,
                    icon: Icons.history_rounded,
                    label: ProjectWorkspaceStrings.activity,
                    value:
                        '${snapshot.activity.length + (project.createdAt == null ? 0 : 1)}',
                    onTap: () =>
                        onOpenSection(ProjectWorkspaceSection.activity),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProjectProgressCard(
          project: project,
          lang: lang,
          onEdit: role == UserRole.procurement ? null : onEditProgress,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ReadinessCard(snapshot: snapshot, lang: lang),
      ],
    );
  }
}

class _ProjectProgressCard extends StatelessWidget {
  const _ProjectProgressCard({
    required this.project,
    required this.lang,
    required this.onEdit,
  });

  final Project project;
  final AppLanguage lang;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final stages = project.effectiveProgressStages;
    final overall = stages.weightedProgress.clamp(0, 100);
    return NexusSectionCard(
      key: const ValueKey('project-progress-card'),
      title: ProjectWorkspaceStrings.projectProgress.primary,
      description: ProjectWorkspaceStrings.projectProgressDescription.primary,
      trailing: onEdit == null
          ? StatusChip.info('${overall.toStringAsFixed(0)}%')
          : SecondaryButton(
              label: ProjectWorkspaceStrings.editProgress.primary,
              icon: Icons.tune_rounded,
              isExpanded: false,
              onPressed: onEdit,
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ring = SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: overall / 100,
                    strokeWidth: 12,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    color: AppColors.primary,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${overall.toStringAsFixed(0)}%',
                      style: AppTypography.headlineSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ProjectWorkspaceStrings.overall.primary,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          final list = Column(
            children: [
              for (var index = 0; index < stages.length; index++)
                _ProjectProgressRow(
                  stage: stages[index],
                  lang: lang,
                  showDivider: index != stages.length - 1,
                ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              children: [
                ring,
                const SizedBox(height: AppSpacing.xl),
                list,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: AppSpacing.xxl),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectProgressRow extends StatelessWidget {
  const _ProjectProgressRow({
    required this.stage,
    required this.lang,
    required this.showDivider,
  });

  final ProjectProgressStage stage;
  final AppLanguage lang;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final progress = stage.progressPercent.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stage.label, style: AppTypography.labelLarge),
                Text(
                  '${stage.weightPercent.toStringAsFixed(stage.weightPercent % 1 == 0 ? 0 : 1)}% ${ProjectWorkspaceStrings.weight.primary.toLowerCase()}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${progress.toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: AppTypography.labelMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 7,
                backgroundColor: AppColors.surfaceContainerHigh,
                color: progress == 100
                    ? AppColors.success
                    : progress < 20
                    ? AppColors.warning
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStageDialog extends StatefulWidget {
  const _ProgressStageDialog({
    required this.initialStages,
    required this.canConfigureStages,
  });

  final List<ProjectProgressStage> initialStages;
  final bool canConfigureStages;

  @override
  State<_ProgressStageDialog> createState() => _ProgressStageDialogState();
}

class _ProgressStageDialogState extends State<_ProgressStageDialog> {
  late final List<_ProgressStageDraft> _stages = [
    for (final stage in widget.initialStages) _ProgressStageDraft.from(stage),
  ];
  String? _error;

  void _addStage() {
    setState(() {
      _stages.add(
        _ProgressStageDraft(
          id: 'stage-${DateTime.now().microsecondsSinceEpoch}',
          label: '',
          weight: 0,
          progress: 0,
        ),
      );
      _error = null;
    });
  }

  void _save() {
    final valid = _stages.isNotEmpty && _stages.every((stage) => stage.isValid);
    if (!valid) {
      setState(() => _error = ProjectWorkspaceStrings.invalidProgress.primary);
      return;
    }
    final weight = _stages.fold<double>(
      0,
      (total, stage) => total + stage.weight,
    );
    if ((weight - 100).abs() > 0.01) {
      setState(() => _error = ProjectWorkspaceStrings.weightTotalError.primary);
      return;
    }
    Navigator.pop(context, [
      for (final stage in _stages)
        ProjectProgressStage(
          id: stage.id,
          label: stage.label.trim(),
          weightPercent: stage.weight,
          progressPercent: stage.progress,
          updatedAt: stage.updatedAt,
          updatedByUserId: stage.updatedByUserId,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final contentWidth = (viewport.width - 96).clamp(280.0, 760.0).toDouble();
    final contentHeight = (viewport.height - 220)
        .clamp(320.0, 560.0)
        .toDouble();
    return AlertDialog(
      title: Text(ProjectWorkspaceStrings.projectProgress.primary),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ProjectWorkspaceStrings.projectProgressDescription.primary,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView.separated(
                itemCount: _stages.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => _ProgressStageEditor(
                  key: ValueKey(_stages[index].id),
                  stage: _stages[index],
                  canConfigureStage: widget.canConfigureStages,
                  canRemove: widget.canConfigureStages && _stages.length > 1,
                  onRemove: () => setState(() => _stages.removeAt(index)),
                  onChanged: () {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
            ),
            if (widget.canConfigureStages) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _addStage,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(ProjectWorkspaceStrings.addStage.primary),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(ProjectWorkspaceStrings.saveProgress.primary),
        ),
      ],
    );
  }
}

class _ProgressStageEditor extends StatelessWidget {
  const _ProgressStageEditor({
    super.key,
    required this.stage,
    required this.canConfigureStage,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final _ProgressStageDraft stage;
  final bool canConfigureStage;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget name() => TextFormField(
      initialValue: stage.label,
      enabled: canConfigureStage,
      decoration: InputDecoration(
        labelText: ProjectWorkspaceStrings.stageName.primary,
      ),
      onChanged: (value) {
        stage.label = value;
        onChanged();
      },
    );
    Widget weight() => TextFormField(
      initialValue: _number(stage.weight),
      enabled: canConfigureStage,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: ProjectWorkspaceStrings.weight.primary,
      ),
      onChanged: (value) {
        stage.weight = double.tryParse(value) ?? -1;
        onChanged();
      },
    );
    Widget progress() => TextFormField(
      initialValue: _number(stage.progress),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: ProjectWorkspaceStrings.progress.primary,
      ),
      onChanged: (value) {
        stage.progress = double.tryParse(value) ?? -1;
        onChanged();
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final remove = IconButton(
          onPressed: canRemove ? onRemove : null,
          tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          icon: const Icon(Icons.delete_outline_rounded),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: name()),
                  if (canConfigureStage) remove,
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: weight()),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: progress()),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 4, child: name()),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: weight()),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: progress()),
            if (canConfigureStage) remove,
          ],
        );
      },
    );
  }

  String _number(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

class _ProgressStageDraft {
  _ProgressStageDraft({
    required this.id,
    required this.label,
    required this.weight,
    required this.progress,
    this.updatedAt,
    this.updatedByUserId,
  });

  factory _ProgressStageDraft.from(ProjectProgressStage stage) =>
      _ProgressStageDraft(
        id: stage.id,
        label: stage.label,
        weight: stage.weightPercent,
        progress: stage.progressPercent,
        updatedAt: stage.updatedAt,
        updatedByUserId: stage.updatedByUserId,
      );

  final String id;
  String label;
  double weight;
  double progress;
  final DateTime? updatedAt;
  final String? updatedByUserId;

  bool get isValid =>
      label.trim().isNotEmpty &&
      weight.isFinite &&
      weight > 0 &&
      progress.isFinite &&
      progress >= 0 &&
      progress <= 100;
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.snapshot, required this.lang});

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.readiness.primary,
      description: ProjectWorkspaceStrings.readinessDescription.primary,
      child: Column(
        children: [
          for (var index = 0; index < snapshot.readiness.length; index++)
            _ReadinessRow(
              readiness: snapshot.readiness[index],
              lang: lang,
              showDivider: index != snapshot.readiness.length - 1,
            ),
        ],
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.readiness,
    required this.lang,
    required this.showDivider,
  });

  final ProjectWorkspaceReadiness readiness;
  final AppLanguage lang;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final label = _readinessLabel(readiness.kind);
    final state = _readinessStateCopy(readiness.state);
    final tone = switch (readiness.state) {
      ProjectWorkspaceReadinessState.ready => NexusStatusTone.success,
      ProjectWorkspaceReadinessState.inProgress => NexusStatusTone.info,
      ProjectWorkspaceReadinessState.pending => NexusStatusTone.neutral,
      ProjectWorkspaceReadinessState.blocked => NexusStatusTone.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: BilingualText(
              english: label.primary,
              secondary: label.secondary(lang),
              englishStyle: AppTypography.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          StatusChip(label: state.primary, tone: tone),
        ],
      ),
    );
  }
}

class _MaterialPlanSection extends StatelessWidget {
  const _MaterialPlanSection({
    required this.snapshot,
    required this.lang,
    required this.role,
  });

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final plan = snapshot.materialPlan;
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.materialPlan.primary,
      description: ProjectWorkspaceStrings.planConnectedDescription.primary,
      trailing: plan == null
          ? null
          : StatusChip(label: plan.status.label, tone: _planTone(plan.status)),
      child: plan == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EmptyText(
                  copy: ProjectWorkspaceStrings.planNotStarted,
                  lang: lang,
                ),
                if (role == UserRole.engineer) ...[
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: ProjectWorkspaceStrings.openPlan.primary,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.push(
                      RoutePaths.planBuildPath(snapshot.project.id),
                    ),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ResponsiveFacts(
                  facts: [
                    _Fact(ProjectWorkspaceStrings.status, plan.status.label),
                    _Fact(ProjectWorkspaceStrings.version, '${plan.version}'),
                    _Fact(ProjectWorkspaceStrings.items, '${plan.itemCount}'),
                    _Fact(
                      ProjectWorkspaceStrings.comments,
                      '${plan.comments.length}',
                    ),
                    _Fact(
                      ProjectWorkspaceStrings.submitted,
                      _formatDate(plan.submittedAt),
                    ),
                    _Fact(
                      ProjectWorkspaceStrings.approved,
                      _formatDate(plan.approvedAt),
                    ),
                  ],
                  lang: lang,
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: ProjectWorkspaceStrings.openPlan.primary,
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => context.push(
                    role == UserRole.procurement || role == UserRole.admin
                        ? RoutePaths.planReviewProcurementPath(
                            snapshot.project.id,
                          )
                        : plan.status ==
                              MaterialPlanStatus.pendingEngineerApproval
                        ? RoutePaths.planReviewPath(snapshot.project.id)
                        : RoutePaths.planBuildPath(snapshot.project.id),
                  ),
                ),
              ],
            ),
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({required this.snapshot, required this.lang});

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.requests.primary,
      description: ProjectWorkspaceStrings.requestConnectedDescription.primary,
      trailing: StatusChip.info('${snapshot.requests.length}'),
      child: snapshot.requests.isEmpty
          ? _EmptyText(copy: ProjectWorkspaceStrings.noRequests, lang: lang)
          : Column(
              children: [
                for (var index = 0; index < snapshot.requests.length; index++)
                  _RequestRow(
                    request: snapshot.requests[index],
                    lang: lang,
                    showDivider: index != snapshot.requests.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.lang,
    required this.showDivider,
  });

  final MaterialRequest request;
  final AppLanguage lang;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.requestDetailPath(request.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppColors.line))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.assignment_outlined,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.id, style: AppTypography.titleSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${request.itemCount} ${ProjectWorkspaceStrings.items.primary} · '
                    '${DateFormat('d MMM yyyy').format(request.requestDate)}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            StatusChip(
              label: request.status.label,
              tone: _requestTone(request.status),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ProcurementSection extends StatelessWidget {
  const _ProcurementSection({required this.snapshot, required this.lang});

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    final needingAction = snapshot.requests
        .where(
          (request) =>
              request.status == RequestStatus.pending ||
              request.status == RequestStatus.sourcing ||
              request.status == RequestStatus.partial ||
              request.status == RequestStatus.onHold,
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusSectionCard(
          title: ProjectWorkspaceStrings.procurementReadiness.primary,
          child: BilingualText(
            english: ProjectWorkspaceStrings.procurementBoundary.primary,
            secondary: ProjectWorkspaceStrings.procurementBoundary.secondary(
              lang,
            ),
            englishStyle: AppTypography.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NexusSectionCard(
          title: ProjectWorkspaceStrings.requestsNeedingProcurement.primary,
          trailing: StatusChip.info('${needingAction.length}'),
          child: needingAction.isEmpty
              ? _EmptyText(
                  copy: ProjectWorkspaceStrings.noneNeedingProcurement,
                  lang: lang,
                )
              : Column(
                  children: [
                    for (var index = 0; index < needingAction.length; index++)
                      _RequestRow(
                        request: needingAction[index],
                        lang: lang,
                        showDivider: index != needingAction.length - 1,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _FutureRecordCard(
                copy: ProjectWorkspaceStrings.rfq,
                icon: Icons.request_quote_outlined,
                lang: lang,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _FutureRecordCard(
                copy: ProjectWorkspaceStrings.purchaseOrders,
                icon: Icons.receipt_long_outlined,
                lang: lang,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FutureRecordCard extends StatelessWidget {
  const _FutureRecordCard({
    required this.copy,
    required this.icon,
    required this.lang,
  });

  final TranslatableString copy;
  final IconData icon;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return LedgerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          BilingualText(
            english: copy.primary,
            secondary: copy.secondary(lang),
            englishStyle: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          StatusChip(
            label: ProjectWorkspaceStrings.notEnabled.primary,
            tone: NexusStatusTone.outline,
          ),
        ],
      ),
    );
  }
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.snapshot,
    required this.lang,
    required this.userName,
  });

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;
  final String Function(String?) userName;

  @override
  Widget build(BuildContext context) {
    final attachments = snapshot.project.attachments;
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.documents.primary,
      description: ProjectWorkspaceStrings.documentMetadata.primary,
      trailing: StatusChip.info('${attachments.length}'),
      child: attachments.isEmpty
          ? _EmptyText(copy: ProjectWorkspaceStrings.noDocuments, lang: lang)
          : Column(
              children: [
                for (var index = 0; index < attachments.length; index++)
                  _DocumentRow(
                    attachment: attachments[index],
                    project: snapshot.project,
                    actor: userName(attachments[index].addedByUserId),
                    showDivider: index != attachments.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.attachment,
    required this.project,
    required this.actor,
    required this.showDivider,
  });

  final ProjectAttachment attachment;
  final Project project;
  final String actor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    String scope() {
      if (attachment.buildingId == null) {
        return ProjectWorkspaceStrings.projectWide.primary;
      }
      for (final building in project.buildings) {
        if (building.id == attachment.buildingId) {
          return '${building.code} · ${building.name}';
        }
      }
      return attachment.buildingId!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.description_outlined,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.fileName, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    attachment.documentType,
                    if ((attachment.reference ?? '').isNotEmpty)
                      '${ProjectWorkspaceStrings.reference.primary}: '
                          '${attachment.reference}',
                    '${ProjectWorkspaceStrings.scope.primary}: ${scope()}',
                  ].join(' · '),
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                AuditMeta(
                  actor: actor,
                  role: attachment.addedByRole,
                  timestamp: _formatDateTime(attachment.addedAt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.snapshot,
    required this.lang,
    required this.userName,
  });

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;
  final String Function(String?) userName;

  @override
  Widget build(BuildContext context) {
    final project = snapshot.project;
    final hasCreation = project.createdAt != null;
    final count = snapshot.activity.length + (hasCreation ? 1 : 0);
    return NexusSectionCard(
      title: ProjectWorkspaceStrings.activity.primary,
      description: ProjectWorkspaceStrings.auditDescription.primary,
      trailing: StatusChip.info('$count'),
      child: count == 0
          ? _EmptyText(copy: ProjectWorkspaceStrings.noActivity, lang: lang)
          : Column(
              children: [
                for (var index = 0; index < snapshot.activity.length; index++)
                  AuditTrailItem(
                    action: snapshot.activity[index].action,
                    detail:
                        snapshot.activity[index].detail ??
                        snapshot.project.name,
                    actor: snapshot.activity[index].actorName,
                    role: snapshot.activity[index].actorRole.label,
                    timestamp: _formatDateTime(
                      snapshot.activity[index].timestamp,
                    ),
                    showDivider:
                        index != snapshot.activity.length - 1 || hasCreation,
                  ),
                if (hasCreation)
                  AuditTrailItem(
                    action: ProjectWorkspaceStrings.projectCreated.primary,
                    detail: ProjectWorkspaceStrings.sourceRecord.primary,
                    actor: userName(project.createdByUserId),
                    role:
                        project.createdByRole ??
                        ProjectWorkspaceStrings.system.primary,
                    timestamp: _formatDateTime(project.createdAt!),
                    icon: Icons.add_business_outlined,
                    showDivider: false,
                  ),
              ],
            ),
    );
  }
}

class _WorkspaceInspector extends StatelessWidget {
  const _WorkspaceInspector({
    required this.snapshot,
    required this.lang,
    required this.ownerName,
    required this.userName,
  });

  final ProjectWorkspaceSnapshot snapshot;
  final AppLanguage lang;
  final String ownerName;
  final String Function(String?) userName;

  @override
  Widget build(BuildContext context) {
    final project = snapshot.project;
    final engineerIds = <String>{
      ...project.designEngineerUserIds,
      ?project.assignedEngineerId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusSectionCard(
          title: ProjectWorkspaceStrings.responsibility.primary,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InspectorValue(
                label: ProjectWorkspaceStrings.currentOwner,
                value: ownerName,
                lang: lang,
              ),
              const SizedBox(height: AppSpacing.lg),
              _InspectorValue(
                label: ProjectWorkspaceStrings.projectManager,
                value: userName(project.projectManagerUserId),
                lang: lang,
              ),
              const SizedBox(height: AppSpacing.lg),
              _InspectorValue(
                label: ProjectWorkspaceStrings.engineers,
                value: engineerIds.isEmpty
                    ? ProjectWorkspaceStrings.unassigned.primary
                    : engineerIds.map(userName).join(', '),
                lang: lang,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NexusSectionCard(
          title: ProjectWorkspaceStrings.activity.primary,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (project.createdAt != null)
                _AuditBlock(
                  label: ProjectWorkspaceStrings.created,
                  actor: userName(project.createdByUserId),
                  role:
                      project.createdByRole ??
                      ProjectWorkspaceStrings.system.primary,
                  timestamp: _formatDateTime(project.createdAt!),
                  lang: lang,
                ),
              if (project.createdAt != null && project.updatedAt != null)
                const SizedBox(height: AppSpacing.lg),
              if (project.updatedAt != null)
                _AuditBlock(
                  label: ProjectWorkspaceStrings.lastUpdated,
                  actor: userName(project.updatedByUserId),
                  role:
                      project.updatedByRole ??
                      ProjectWorkspaceStrings.system.primary,
                  timestamp: _formatDateTime(project.updatedAt!),
                  lang: lang,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuditBlock extends StatelessWidget {
  const _AuditBlock({
    required this.label,
    required this.actor,
    required this.role,
    required this.timestamp,
    required this.lang,
  });

  final TranslatableString label;
  final String actor;
  final String role;
  final String timestamp;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BilingualText(
          english: label.primary,
          secondary: label.secondary(lang),
          englishStyle: AppTypography.labelMedium,
          gap: 2,
        ),
        const SizedBox(height: AppSpacing.sm),
        AuditMeta(actor: actor, role: role, timestamp: timestamp),
      ],
    );
  }
}

class _InspectorValue extends StatelessWidget {
  const _InspectorValue({
    required this.label,
    required this.value,
    required this.lang,
  });

  final TranslatableString label;
  final String value;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BilingualText(
          english: label.primary,
          secondary: label.secondary(lang),
          englishStyle: AppTypography.labelMedium,
          gap: 2,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTypography.bodyMedium),
      ],
    );
  }
}

class _ResponsiveFacts extends StatelessWidget {
  const _ResponsiveFacts({required this.facts, required this.lang});

  final List<_Fact> facts;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 650 ? 3 : 2;
        final width =
            (constraints.maxWidth - ((columns - 1) * AppSpacing.lg)) / columns;
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            for (final fact in facts)
              SizedBox(
                width: width,
                child: _InspectorValue(
                  label: fact.label,
                  value: (fact.value == null || fact.value!.trim().isEmpty)
                      ? ProjectWorkspaceStrings.notRecorded.primary
                      : fact.value!,
                  lang: lang,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BuildingRow extends StatelessWidget {
  const _BuildingRow({
    required this.building,
    required this.lang,
    required this.showDivider,
  });

  final ProjectBuilding building;
  final AppLanguage lang;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            building.isProjectWide
                ? Icons.hub_outlined
                : Icons.apartment_outlined,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${building.code} · ${building.name}',
                  style: AppTypography.titleSmall,
                ),
                if (building.floorsOrLevels.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${ProjectWorkspaceStrings.floors.primary}: '
                    '${building.floorsOrLevels.join(', ')}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (building.isProjectWide)
            StatusChip(
              label: ProjectWorkspaceStrings.projectWide.primary,
              tone: NexusStatusTone.outline,
            ),
        ],
      ),
    );
  }
}

class _ConnectedRecordTile extends StatelessWidget {
  const _ConnectedRecordTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final TranslatableString label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: LedgerCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.primary, style: AppTypography.labelMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(value, style: AppTypography.titleSmall),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.copy, required this.lang});

  final TranslatableString copy;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context) {
    return BilingualText(
      english: copy.primary,
      secondary: copy.secondary(lang),
      englishStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}

typedef _ActionCopy = ({
  TranslatableString title,
  TranslatableString message,
  NexusStatusTone tone,
  IconData icon,
});

typedef _ActionTarget = ({
  TranslatableString label,
  IconData icon,
  void Function(BuildContext context) open,
});

class _Fact {
  const _Fact(this.label, this.value);

  final TranslatableString label;
  final String? value;
}

TranslatableString _sectionCopy(
  ProjectWorkspaceSection section,
) => switch (section) {
  ProjectWorkspaceSection.overview => ProjectWorkspaceStrings.overview,
  ProjectWorkspaceSection.materialPlan => ProjectWorkspaceStrings.materialPlan,
  ProjectWorkspaceSection.requests => ProjectWorkspaceStrings.requests,
  ProjectWorkspaceSection.procurement => ProjectWorkspaceStrings.procurement,
  ProjectWorkspaceSection.documents => ProjectWorkspaceStrings.documents,
  ProjectWorkspaceSection.activity => ProjectWorkspaceStrings.activity,
};

_ActionCopy _actionCopy(ProjectWorkspaceAction action) => switch (action) {
  ProjectWorkspaceAction.acceptProject => (
    title: ProjectWorkspaceStrings.actionAccept,
    message: ProjectWorkspaceStrings.actionAcceptMessage,
    tone: NexusStatusTone.warning,
    icon: Icons.domain_add_outlined,
  ),
  ProjectWorkspaceAction.prepareMaterialPlan => (
    title: ProjectWorkspaceStrings.actionPreparePlan,
    message: ProjectWorkspaceStrings.actionPreparePlanMessage,
    tone: NexusStatusTone.info,
    icon: Icons.view_list_outlined,
  ),
  ProjectWorkspaceAction.reviewMaterialPlan => (
    title: ProjectWorkspaceStrings.actionReviewPlan,
    message: ProjectWorkspaceStrings.actionReviewPlanMessage,
    tone: NexusStatusTone.info,
    icon: Icons.fact_check_outlined,
  ),
  ProjectWorkspaceAction.approveMaterialPlan => (
    title: ProjectWorkspaceStrings.actionApprovePlan,
    message: ProjectWorkspaceStrings.actionApprovePlanMessage,
    tone: NexusStatusTone.warning,
    icon: Icons.approval_outlined,
  ),
  ProjectWorkspaceAction.reviseMaterialPlan => (
    title: ProjectWorkspaceStrings.actionRevisePlan,
    message: ProjectWorkspaceStrings.actionRevisePlanMessage,
    tone: NexusStatusTone.warning,
    icon: Icons.edit_note_outlined,
  ),
  ProjectWorkspaceAction.submitRequestDraft => (
    title: ProjectWorkspaceStrings.actionSubmitDraft,
    message: ProjectWorkspaceStrings.actionSubmitDraftMessage,
    tone: NexusStatusTone.warning,
    icon: Icons.send_outlined,
  ),
  ProjectWorkspaceAction.processMaterialRequests => (
    title: ProjectWorkspaceStrings.actionProcessRequests,
    message: ProjectWorkspaceStrings.actionProcessRequestsMessage,
    tone: NexusStatusTone.info,
    icon: Icons.inventory_2_outlined,
  ),
  ProjectWorkspaceAction.confirmSiteReceipt => (
    title: ProjectWorkspaceStrings.actionConfirmReceipt,
    message: ProjectWorkspaceStrings.actionConfirmReceiptMessage,
    tone: NexusStatusTone.warning,
    icon: Icons.inventory_outlined,
  ),
  ProjectWorkspaceAction.createMaterialRequest => (
    title: ProjectWorkspaceStrings.actionCreateRequest,
    message: ProjectWorkspaceStrings.actionCreateRequestMessage,
    tone: NexusStatusTone.success,
    icon: Icons.add_task_outlined,
  ),
  ProjectWorkspaceAction.projectOnHold => (
    title: ProjectWorkspaceStrings.actionOnHold,
    message: ProjectWorkspaceStrings.actionOnHoldMessage,
    tone: NexusStatusTone.danger,
    icon: Icons.pause_circle_outline_rounded,
  ),
  ProjectWorkspaceAction.projectComplete => (
    title: ProjectWorkspaceStrings.actionComplete,
    message: ProjectWorkspaceStrings.actionCompleteMessage,
    tone: NexusStatusTone.success,
    icon: Icons.task_alt_rounded,
  ),
};

_ActionTarget? _actionTarget(ProjectWorkspaceSnapshot snapshot, UserRole role) {
  final action = snapshot.currentAction;
  final project = snapshot.project;
  switch (action) {
    case ProjectWorkspaceAction.acceptProject:
      if (role == UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.procurement,
        icon: Icons.arrow_forward_rounded,
        open: (context) => context.push(RoutePaths.procurement),
      );
    case ProjectWorkspaceAction.prepareMaterialPlan:
    case ProjectWorkspaceAction.reviseMaterialPlan:
      if (role != UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.openPlan,
        icon: Icons.arrow_forward_rounded,
        open: (context) => context.push(RoutePaths.planBuildPath(project.id)),
      );
    case ProjectWorkspaceAction.reviewMaterialPlan:
      if (role == UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.openPlan,
        icon: Icons.arrow_forward_rounded,
        open: (context) =>
            context.push(RoutePaths.planReviewProcurementPath(project.id)),
      );
    case ProjectWorkspaceAction.approveMaterialPlan:
      if (role != UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.openPlan,
        icon: Icons.arrow_forward_rounded,
        open: (context) => context.push(RoutePaths.planReviewPath(project.id)),
      );
    case ProjectWorkspaceAction.processMaterialRequests:
      if (role == UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.procurement,
        icon: Icons.arrow_forward_rounded,
        open: (context) => context.push(RoutePaths.procurement),
      );
    case ProjectWorkspaceAction.confirmSiteReceipt:
      if (role != UserRole.engineer) return null;
      MaterialRequest? request;
      for (final candidate in snapshot.requests) {
        if (candidate.status == RequestStatus.dispatched) {
          request = candidate;
          break;
        }
      }
      if (request == null) return null;
      final requestId = request.id;
      return (
        label: ProjectWorkspaceStrings.openRequest,
        icon: Icons.arrow_forward_rounded,
        open: (context) =>
            context.push(RoutePaths.confirmReceiptPath(requestId)),
      );
    case ProjectWorkspaceAction.submitRequestDraft:
      if (role != UserRole.engineer) return null;
      return (
        label: ProjectWorkspaceStrings.requests,
        icon: Icons.arrow_forward_rounded,
        open: (context) =>
            context.push(RoutePaths.requests, extra: project.name),
      );
    case ProjectWorkspaceAction.createMaterialRequest:
      if (role != UserRole.engineer) return null;
      return (
        label: AppStrings.newRequest,
        icon: Icons.add_rounded,
        open: (context) => context.go(RoutePaths.engineerNewRequest),
      );
    case ProjectWorkspaceAction.projectOnHold:
    case ProjectWorkspaceAction.projectComplete:
      return null;
  }
}

String _ownerName(
  ProjectWorkspaceSnapshot snapshot,
  String Function(String?) userName,
) {
  if (snapshot.currentOwnerUserIds.isNotEmpty) {
    return snapshot.currentOwnerUserIds.map(userName).join(', ');
  }
  return switch (snapshot.currentOwnerRole) {
    UserRole.procurement => ProjectWorkspaceStrings.procurementTeam.primary,
    UserRole.engineer => ProjectWorkspaceStrings.engineeringTeam.primary,
    UserRole.accountant => AppStrings.accountantRole.primary,
    UserRole.pr => AppStrings.prRole.primary,
    UserRole.admin => ProjectWorkspaceStrings.adminTeam.primary,
    null => ProjectWorkspaceStrings.noCurrentOwner.primary,
  };
}

TranslatableString _blockerCopy(ProjectWorkspaceBlocker blocker) =>
    switch (blocker) {
      ProjectWorkspaceBlocker.procurementAcceptance =>
        ProjectWorkspaceStrings.blockerAcceptance,
      ProjectWorkspaceBlocker.startDateMissing =>
        ProjectWorkspaceStrings.blockerStartDate,
      ProjectWorkspaceBlocker.physicalBuildingMissing =>
        ProjectWorkspaceStrings.blockerBuilding,
      ProjectWorkspaceBlocker.engineerAssignmentMissing =>
        ProjectWorkspaceStrings.blockerEngineer,
      ProjectWorkspaceBlocker.materialPlanChangesRequested =>
        ProjectWorkspaceStrings.blockerPlanChanges,
      ProjectWorkspaceBlocker.requestOnHold =>
        ProjectWorkspaceStrings.blockerRequestHold,
      ProjectWorkspaceBlocker.projectOnHold =>
        ProjectWorkspaceStrings.blockerProjectHold,
    };

TranslatableString _readinessLabel(ProjectWorkspaceReadinessKind kind) =>
    switch (kind) {
      ProjectWorkspaceReadinessKind.responsibility =>
        ProjectWorkspaceStrings.readinessResponsibility,
      ProjectWorkspaceReadinessKind.buildingScope =>
        ProjectWorkspaceStrings.readinessBuilding,
      ProjectWorkspaceReadinessKind.procurementAcceptance =>
        ProjectWorkspaceStrings.readinessAcceptance,
      ProjectWorkspaceReadinessKind.materialPlan =>
        ProjectWorkspaceStrings.readinessPlan,
      ProjectWorkspaceReadinessKind.execution =>
        ProjectWorkspaceStrings.readinessExecution,
    };

TranslatableString _readinessStateCopy(ProjectWorkspaceReadinessState state) =>
    switch (state) {
      ProjectWorkspaceReadinessState.pending => ProjectWorkspaceStrings.pending,
      ProjectWorkspaceReadinessState.inProgress =>
        ProjectWorkspaceStrings.inProgress,
      ProjectWorkspaceReadinessState.ready => ProjectWorkspaceStrings.ready,
      ProjectWorkspaceReadinessState.blocked => ProjectWorkspaceStrings.blocked,
    };

NexusStatusTone _planTone(MaterialPlanStatus status) => switch (status) {
  MaterialPlanStatus.draft => NexusStatusTone.neutral,
  MaterialPlanStatus.submitted ||
  MaterialPlanStatus.procurementReview => NexusStatusTone.info,
  MaterialPlanStatus.pendingEngineerApproval => NexusStatusTone.warning,
  MaterialPlanStatus.approved => NexusStatusTone.success,
  MaterialPlanStatus.rejected => NexusStatusTone.danger,
  MaterialPlanStatus.superseded => NexusStatusTone.neutral,
};

NexusStatusTone _requestTone(RequestStatus status) => switch (status) {
  RequestStatus.draft => NexusStatusTone.neutral,
  RequestStatus.pending ||
  RequestStatus.sourcing ||
  RequestStatus.partial ||
  RequestStatus.dispatched => NexusStatusTone.info,
  RequestStatus.received => NexusStatusTone.success,
  RequestStatus.onHold => NexusStatusTone.warning,
  RequestStatus.cancelled => NexusStatusTone.danger,
};

String? _formatDate(DateTime? value) =>
    value == null ? null : DateFormat('d MMM yyyy').format(value.toLocal());

String _formatDateTime(DateTime value) =>
    DateFormat('d MMM yyyy · h:mm a').format(value.toLocal());
