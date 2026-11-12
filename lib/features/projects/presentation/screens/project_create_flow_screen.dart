import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_notification.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/audit_log.dart';
import '../../../../shared/models/project.dart';
import '../../../../shared/models/project_create_strings.dart';
import '../../../../shared/models/project_creation_draft.dart';
import '../../../../shared/models/user_role.dart';
import '../../../../shared/providers/audit_log_provider.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/notification_provider.dart';
import '../../../../shared/providers/project_creation_draft_provider.dart';
import '../../../../shared/providers/project_provider.dart';
import '../../../../shared/providers/session_provider.dart';
import '../../../../shared/providers/users_provider.dart';

const _uuid = Uuid();
const _projectWideValue = '__project_wide__';

/// The frozen V7 project-creation contract: three stages on browser and the
/// same information in focused, stacked sections on smaller screens.
class ProjectCreateFlowScreen extends ConsumerStatefulWidget {
  const ProjectCreateFlowScreen({super.key});

  @override
  ConsumerState<ProjectCreateFlowScreen> createState() =>
      _ProjectCreateFlowScreenState();
}

class _ProjectCreateFlowScreenState
    extends ConsumerState<ProjectCreateFlowScreen> {
  final _stageOneKey = GlobalKey<FormState>();
  final _stageTwoKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  final _nameController = TextEditingController();
  final _secondaryNameController = TextEditingController();
  final _clientController = TextEditingController();
  final _contractController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _consultantController = TextEditingController();
  final _mainContractorController = TextEditingController();
  final _subcontractorsController = TextEditingController();
  final _otherContractorsController = TextEditingController();
  final _scrollController = ScrollController();

  late final String _ownerUserId;
  late ProjectCreationDraft _draft;
  Timer? _saveTimer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final actor = ref.read(currentUserProvider);
    _ownerUserId = actor?.id ?? 'local-unknown-user';
    _draft = ref.read(projectCreationDraftProvider(_ownerUserId));

    if (_draft.designEngineerUserIds.isEmpty &&
        actor?.role == UserRole.engineer) {
      _draft = _draft.copyWith(designEngineerUserIds: [actor!.id]);
    } else if (_draft.designEngineerUserIds.isEmpty) {
      final engineers = ref
          .read(usersProvider)
          .where((user) => user.active && user.role == UserRole.engineer)
          .toList();
      if (engineers.isNotEmpty) {
        _draft = _draft.copyWith(designEngineerUserIds: [engineers.first.id]);
      }
    }

    _referenceController.text = _draft.yorksReference;
    _nameController.text = _draft.name;
    _secondaryNameController.text = _draft.secondaryName;
    _clientController.text = _draft.clientName;
    _contractController.text = _draft.contractOrJobNumber;
    _locationController.text = _draft.siteLocation;
    _notesController.text = _draft.siteNotes;
    _consultantController.text = _draft.consultant;
    _mainContractorController.text = _draft.mainContractor;
    _subcontractorsController.text = _draft.subContractorNames.join(', ');
    _otherContractorsController.text = _draft.otherContractorNames.join(', ');

    for (final controller in _controllers) {
      controller.addListener(_updateTextDraft);
    }
  }

  List<TextEditingController> get _controllers => [
    _referenceController,
    _nameController,
    _secondaryNameController,
    _clientController,
    _contractController,
    _locationController,
    _notesController,
    _consultantController,
    _mainContractorController,
    _subcontractorsController,
    _otherContractorsController,
  ];

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final controller in _controllers) {
      controller
        ..removeListener(_updateTextDraft)
        ..dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _updateTextDraft() {
    _setDraft(
      _draft.copyWith(
        yorksReference: _referenceController.text,
        name: _nameController.text,
        secondaryName: _secondaryNameController.text,
        clientName: _clientController.text,
        contractOrJobNumber: _contractController.text,
        siteLocation: _locationController.text,
        siteNotes: _notesController.text,
        consultant: _consultantController.text,
        mainContractor: _mainContractorController.text,
        subContractorNames: _splitNames(_subcontractorsController.text),
        otherContractorNames: _splitNames(_otherContractorsController.text),
      ),
    );
  }

  void _setDraft(ProjectCreationDraft value, {bool autosave = true}) {
    if (!mounted) return;
    setState(() => _draft = value);
    if (!autosave) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _persistDraft);
  }

  Future<void> _persistDraft({bool notify = false}) async {
    _saveTimer?.cancel();
    await ref
        .read(projectCreationDraftProvider(_ownerUserId).notifier)
        .save(_draft);
    if (notify && mounted) {
      final lang = ref.read(languageProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ProjectCreateStrings.draftSaved.primary),
          action: SnackBarAction(
            label: ProjectCreateStrings.draftSaved.secondary(lang),
            onPressed: () {},
          ),
        ),
      );
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ProjectCreateStrings.requiredMessage.primary;
    }
    return null;
  }

  bool _validateStageOne() {
    final state = _stageOneKey.currentState;
    final completeRequiredValues = [
      _draft.yorksReference,
      _draft.name,
      _draft.clientName,
      _draft.siteLocation,
    ].every((value) => value.trim().isNotEmpty);
    final validFields = state?.validate() ?? completeRequiredValues;
    String? message;
    if (_draft.startDate == null) {
      message = ProjectCreateStrings.startRequired.primary;
    } else if (_draft.expectedEndDate != null &&
        _draft.expectedEndDate!.isBefore(_draft.startDate!)) {
      message = ProjectCreateStrings.invalidEndDate.primary;
    } else if (_draft.designEngineerUserIds.isEmpty) {
      message = ProjectCreateStrings.engineerRequired.primary;
    } else if (!ref
        .read(projectsProvider.notifier)
        .isYorksReferenceAvailable(_draft.yorksReference)) {
      message = ProjectCreateStrings.referenceInUse.primary;
    }
    if (!validFields || message != null) {
      _showError(message ?? ProjectCreateStrings.requiredMessage.primary);
      return false;
    }
    return true;
  }

  bool _validateStageTwo() {
    final state = _stageTwoKey.currentState;
    final completeBuildings =
        _draft.buildings.isNotEmpty &&
        _draft.buildings.every(
          (building) =>
              building.code.trim().isNotEmpty &&
              building.name.trim().isNotEmpty,
        );
    final validFields = state?.validate() ?? completeBuildings;
    if (_draft.buildings.isEmpty) {
      _showError(ProjectCreateStrings.buildingRequired.primary);
      return false;
    }
    final codes = _draft.buildings
        .map((building) => building.code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toList();
    if (codes.toSet().length != codes.length) {
      _showError(ProjectCreateStrings.duplicateBuildingCode.primary);
      return false;
    }
    if (!validFields) {
      _showError(ProjectCreateStrings.buildingRequired.primary);
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
  }

  Future<void> _continue() async {
    if (_draft.currentStep == 0 && !_validateStageOne()) return;
    if (_draft.currentStep == 1 && !_validateStageTwo()) return;
    final next = (_draft.currentStep + 1).clamp(0, 2);
    _setDraft(_draft.copyWith(currentStep: next));
    _scrollToTop();
    await _persistDraft();
  }

  void _back() {
    if (_draft.currentStep == 0) {
      context.pop();
      return;
    }
    _setDraft(_draft.copyWith(currentStep: _draft.currentStep - 1));
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  Future<void> _discard() async {
    if (!_draft.hasMeaningfulContent) {
      context.pop();
      return;
    }
    final lang = ref.read(languageProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ProjectCreateStrings.discardQuestion.primary),
        content: Text(ProjectCreateStrings.discardQuestion.secondary(lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.cancel.primary),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ProjectCreateStrings.discardDraft.primary),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(projectCreationDraftProvider(_ownerUserId).notifier)
        .discard();
    if (mounted) context.pop();
  }

  Future<void> _createProject() async {
    if (_saving) return;
    if (!_validateStageOne()) {
      _setDraft(_draft.copyWith(currentStep: 0));
      return;
    }
    if (!_validateStageTwo()) {
      _setDraft(_draft.copyWith(currentStep: 1));
      return;
    }

    final actor = ref.read(currentUserProvider);
    if (actor == null) {
      _showError(ProjectCreateStrings.createFailed.primary);
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final project = _draft.toProject(
      projectId: _uuid.v4(),
      createdAt: now,
      actorUserId: actor.id,
      actorRole: actor.role.name,
      commonBuildingId: _uuid.v4(),
    );
    final created = await ref
        .read(projectsProvider.notifier)
        .addProject(project);
    if (!created) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(ProjectCreateStrings.createFailed.primary);
      }
      return;
    }

    if (actor.role == UserRole.engineer) {
      final lang = ref.read(languageProvider);
      ref
          .read(notificationsProvider.notifier)
          .add(
            type: NotificationType.project,
            title: AppStrings.notifNewProjectTitle.primary,
            titleSecondary: AppStrings.notifNewProjectTitle.secondary(lang),
            body: project.name,
            refId: project.id,
            route: RoutePaths.procurement,
            audience: UserRole.procurement.name,
          );
    }
    await ref.logAudit(
      action: 'V7 project created',
      module: AuditModule.materials,
      refId: project.id,
      detail:
          '${project.yorksReference} · ${project.name} · '
          '${project.buildings.length - 1} physical building(s)',
    );
    await ref
        .read(projectCreationDraftProvider(_ownerUserId).notifier)
        .discard();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ProjectCreateStrings.created.primary)),
    );
    switch (actor.role) {
      case UserRole.engineer:
        context.go(RoutePaths.engineerProjects);
        return;
      case UserRole.procurement:
        context.go(RoutePaths.procurement);
        return;
      case UserRole.accountant:
      case UserRole.pr:
        context.go(RoutePaths.engineerHome);
        return;
      case UserRole.admin:
        context.go(RoutePaths.adminProjects);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final stepContent = switch (_draft.currentStep) {
      0 => _StageOne(
        formKey: _stageOneKey,
        draft: _draft,
        lang: lang,
        referenceController: _referenceController,
        nameController: _nameController,
        secondaryNameController: _secondaryNameController,
        clientController: _clientController,
        contractController: _contractController,
        locationController: _locationController,
        notesController: _notesController,
        consultantController: _consultantController,
        mainContractorController: _mainContractorController,
        subcontractorsController: _subcontractorsController,
        otherContractorsController: _otherContractorsController,
        requiredValidator: _required,
        onDraftChanged: _setDraft,
      ),
      1 => _StageTwo(
        formKey: _stageTwoKey,
        draft: _draft,
        lang: lang,
        requiredValidator: _required,
        onDraftChanged: _setDraft,
        onAddAttachment: _addAttachment,
      ),
      _ => _ReviewStage(draft: _draft, lang: lang),
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            NexusPageShell(
              eyebrow: ProjectCreateStrings.eyebrow.primary,
              title: ProjectCreateStrings.title.primary,
              description: ProjectCreateStrings.subtitle.primary,
              controller: _scrollController,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 900;
                  final steps = _StepNavigation(
                    currentStep: _draft.currentStep,
                    lang: lang,
                    desktop: desktop,
                    onSelected: (step) {
                      if (step >= _draft.currentStep) return;
                      _setDraft(_draft.copyWith(currentStep: step));
                    },
                  );
                  final content = NexusSectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: stepContent,
                        ),
                        const Divider(height: 1, color: AppColors.line),
                        _Footer(
                          currentStep: _draft.currentStep,
                          lang: lang,
                          saving: _saving,
                          onBack: _back,
                          onSaveDraft: () => _persistDraft(notify: true),
                          onContinue: _draft.currentStep == 2
                              ? _createProject
                              : _continue,
                        ),
                      ],
                    ),
                  );
                  if (desktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 230, child: steps),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: content),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      steps,
                      const SizedBox(height: AppSpacing.md),
                      content,
                    ],
                  );
                },
              ),
            ),
            PositionedDirectional(
              top: AppSpacing.sm,
              end: AppSpacing.sm,
              child: IconButton(
                key: const ValueKey('discard-project-draft'),
                tooltip: ProjectCreateStrings.discardDraft.primary,
                onPressed: _discard,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAttachment() async {
    final actor = ref.read(currentUserProvider);
    if (actor == null) return;
    final result = await showDialog<ProjectAttachment>(
      context: context,
      builder: (dialogContext) => _ProjectAttachmentDialog(
        buildings: _draft.buildings,
        actorUserId: actor.id,
        actorRole: actor.role.name,
      ),
    );
    if (result == null || !mounted) return;
    _setDraft(_draft.copyWith(attachments: [..._draft.attachments, result]));
  }
}

class _ProjectAttachmentDialog extends StatefulWidget {
  const _ProjectAttachmentDialog({
    required this.buildings,
    required this.actorUserId,
    required this.actorRole,
  });

  final List<ProjectBuilding> buildings;
  final String actorUserId;
  final String actorRole;

  @override
  State<_ProjectAttachmentDialog> createState() =>
      _ProjectAttachmentDialogState();
}

class _ProjectAttachmentDialogState extends State<_ProjectAttachmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fileController = TextEditingController();
  final _typeController = TextEditingController();
  final _referenceController = TextEditingController();
  String _appliesTo = _projectWideValue;

  @override
  void dispose() {
    _fileController.dispose();
    _typeController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ProjectCreateStrings.requiredMessage.primary;
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      ProjectAttachment(
        id: _uuid.v4(),
        fileName: _fileController.text.trim(),
        documentType: _typeController.text.trim(),
        reference: _emptyToNull(_referenceController.text),
        buildingId: _appliesTo == _projectWideValue ? null : _appliesTo,
        addedAt: DateTime.now().toUtc(),
        addedByUserId: widget.actorUserId,
        addedByRole: widget.actorRole,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(ProjectCreateStrings.addDocument.primary),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('attachment-file-name'),
                  controller: _fileController,
                  validator: _required,
                  decoration: InputDecoration(
                    labelText: ProjectCreateStrings.fileName.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('attachment-document-type'),
                  controller: _typeController,
                  validator: _required,
                  decoration: InputDecoration(
                    labelText: ProjectCreateStrings.documentType.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _referenceController,
                  decoration: InputDecoration(
                    labelText: ProjectCreateStrings.reference.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _appliesTo,
                  decoration: InputDecoration(
                    labelText: ProjectCreateStrings.appliesTo.primary,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _projectWideValue,
                      child: Text(ProjectCreateStrings.projectWide.primary),
                    ),
                    for (final building in widget.buildings)
                      DropdownMenuItem(
                        value: building.id,
                        child: Text(
                          '${building.code} · ${building.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _appliesTo = value ?? _projectWideValue),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel.primary),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(AppStrings.addLabel.primary),
        ),
      ],
    );
  }
}

class _StepNavigation extends StatelessWidget {
  const _StepNavigation({
    required this.currentStep,
    required this.lang,
    required this.desktop,
    required this.onSelected,
  });

  final int currentStep;
  final AppLanguage lang;
  final bool desktop;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = [
      ProjectCreateStrings.stepOne,
      ProjectCreateStrings.stepTwo,
      ProjectCreateStrings.stepThree,
    ];
    if (!desktop) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                child: _StepItem(
                  index: index,
                  label: labels[index],
                  currentStep: currentStep,
                  lang: lang,
                  compact: true,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          for (var index = 0; index < labels.length; index++)
            _StepItem(
              index: index,
              label: labels[index],
              currentStep: currentStep,
              lang: lang,
              compact: false,
              onTap: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.index,
    required this.label,
    required this.currentStep,
    required this.lang,
    required this.compact,
    required this.onTap,
  });

  final int index;
  final TranslatableString label;
  final int currentStep;
  final AppLanguage lang;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentStep;
    final completed = index < currentStep;
    return Semantics(
      selected: selected,
      button: completed,
      label:
          '${ProjectCreateStrings.stepOf.primary} ${index + 1}: '
          '${label.primary}',
      child: InkWell(
        onTap: completed ? onTap : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.xxs : AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: compact
              ? Column(
                  children: [
                    _StepCircle(
                      number: index + 1,
                      selected: selected,
                      completed: completed,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      label.primary,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _StepCircle(
                      number: index + 1,
                      selected: selected,
                      completed: completed,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label.primary, style: AppTypography.labelLarge),
                          Text(
                            label.secondary(lang),
                            style: _secondaryStyle(
                              lang,
                              11,
                            ).copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.number,
    required this.selected,
    required this.completed,
  });

  final int number;
  final bool selected;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected || completed ? AppColors.navy : AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected || completed ? AppColors.navy : AppColors.lineStrong,
        ),
      ),
      child: completed
          ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
          : Text(
              '$number',
              style: AppTypography.labelSmall.copyWith(
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
    );
  }
}

class _StageOne extends ConsumerWidget {
  const _StageOne({
    required this.formKey,
    required this.draft,
    required this.lang,
    required this.referenceController,
    required this.nameController,
    required this.secondaryNameController,
    required this.clientController,
    required this.contractController,
    required this.locationController,
    required this.notesController,
    required this.consultantController,
    required this.mainContractorController,
    required this.subcontractorsController,
    required this.otherContractorsController,
    required this.requiredValidator,
    required this.onDraftChanged,
  });

  final GlobalKey<FormState> formKey;
  final ProjectCreationDraft draft;
  final AppLanguage lang;
  final TextEditingController referenceController;
  final TextEditingController nameController;
  final TextEditingController secondaryNameController;
  final TextEditingController clientController;
  final TextEditingController contractController;
  final TextEditingController locationController;
  final TextEditingController notesController;
  final TextEditingController consultantController;
  final TextEditingController mainContractorController;
  final TextEditingController subcontractorsController;
  final TextEditingController otherContractorsController;
  final FormFieldValidator<String> requiredValidator;
  final ValueChanged<ProjectCreationDraft> onDraftChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref
        .watch(usersProvider)
        .where((user) => user.active)
        .toList();
    final engineers = users
        .where((user) => user.role == UserRole.engineer)
        .toList();
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StageHeader(
            title: ProjectCreateStrings.stepOne,
            description: ProjectCreateStrings.essentialsDescription,
            lang: lang,
          ),
          const SizedBox(height: AppSpacing.xl),
          _ResponsiveFields(
            children: [
              _TextFieldBlock(
                fieldKey: const ValueKey('project-yorks-reference'),
                label: ProjectCreateStrings.yorksReference,
                lang: lang,
                controller: referenceController,
                required: true,
                validator: requiredValidator,
              ),
              _TextFieldBlock(
                label: ProjectCreateStrings.contractNumber,
                lang: lang,
                controller: contractController,
              ),
              _TextFieldBlock(
                fieldKey: const ValueKey('project-name'),
                label: AppStrings.projectName,
                lang: lang,
                controller: nameController,
                required: true,
                validator: requiredValidator,
              ),
              _TextFieldBlock(
                label: ProjectCreateStrings.secondaryName,
                lang: lang,
                controller: secondaryNameController,
              ),
              _TextFieldBlock(
                fieldKey: const ValueKey('project-client'),
                label: AppStrings.clientName,
                lang: lang,
                controller: clientController,
                required: true,
                validator: requiredValidator,
              ),
              _TextFieldBlock(
                fieldKey: const ValueKey('project-location'),
                label: AppStrings.siteLocation,
                lang: lang,
                controller: locationController,
                required: true,
                validator: requiredValidator,
              ),
              _DateField(
                fieldKey: const ValueKey('project-start-date'),
                label: AppStrings.startDate,
                lang: lang,
                value: draft.startDate,
                required: true,
                onChanged: (value) =>
                    onDraftChanged(draft.copyWith(startDate: value)),
              ),
              _DateField(
                label: AppStrings.expectedEndDate,
                lang: lang,
                value: draft.expectedEndDate,
                onChanged: (value) =>
                    onDraftChanged(draft.copyWith(expectedEndDate: value)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _TextFieldBlock(
            label: AppStrings.notes,
            lang: lang,
            controller: notesController,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Divider(color: AppColors.line),
          const SizedBox(height: AppSpacing.xl),
          _FieldLabel(label: ProjectCreateStrings.projectManager, lang: lang),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String?>(
            key: const ValueKey('project-manager'),
            initialValue: draft.projectManagerUserId,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(AppStrings.optional.primary),
              ),
              for (final user in users)
                DropdownMenuItem<String?>(
                  value: user.id,
                  child: Text('${user.fullName} · ${user.role.label}'),
                ),
            ],
            onChanged: (value) =>
                onDraftChanged(draft.copyWith(projectManagerUserId: value)),
          ),
          const SizedBox(height: AppSpacing.lg),
          _FieldLabel(
            label: ProjectCreateStrings.designEngineers,
            lang: lang,
            required: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ProjectCreateStrings.responsibilityHint.primary,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final engineer in engineers)
                FilterChip(
                  key: ValueKey('engineer-${engineer.id}'),
                  label: Text(engineer.fullName),
                  selected: draft.designEngineerUserIds.contains(engineer.id),
                  onSelected: (selected) {
                    final ids = [...draft.designEngineerUserIds];
                    selected ? ids.add(engineer.id) : ids.remove(engineer.id);
                    onDraftChanged(
                      draft.copyWith(
                        designEngineerUserIds: ids.toSet().toList(),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Divider(color: AppColors.line),
          const SizedBox(height: AppSpacing.xl),
          _ResponsiveFields(
            children: [
              _TextFieldBlock(
                label: ProjectCreateStrings.consultant,
                lang: lang,
                controller: consultantController,
              ),
              _TextFieldBlock(
                label: ProjectCreateStrings.mainContractor,
                lang: lang,
                controller: mainContractorController,
              ),
              _TextFieldBlock(
                label: ProjectCreateStrings.subcontractors,
                lang: lang,
                controller: subcontractorsController,
                hint: ProjectCreateStrings.commaSeparated.primary,
              ),
              _TextFieldBlock(
                fieldKey: const ValueKey('other-contractors'),
                label: ProjectCreateStrings.otherContractors,
                lang: lang,
                controller: otherContractorsController,
                hint: ProjectCreateStrings.commaSeparated.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageTwo extends StatelessWidget {
  const _StageTwo({
    required this.formKey,
    required this.draft,
    required this.lang,
    required this.requiredValidator,
    required this.onDraftChanged,
    required this.onAddAttachment,
  });

  final GlobalKey<FormState> formKey;
  final ProjectCreationDraft draft;
  final AppLanguage lang;
  final FormFieldValidator<String> requiredValidator;
  final ValueChanged<ProjectCreationDraft> onDraftChanged;
  final VoidCallback onAddAttachment;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StageHeader(
            title: ProjectCreateStrings.stepTwo,
            description: ProjectCreateStrings.buildingsDescription,
            lang: lang,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (var index = 0; index < draft.buildings.length; index++) ...[
            _BuildingEditor(
              key: ValueKey('building-editor-${draft.buildings[index].id}'),
              index: index,
              building: draft.buildings[index],
              lang: lang,
              canRemove: draft.buildings.length > 1,
              requiredValidator: requiredValidator,
              onChanged: (building) {
                final buildings = [...draft.buildings];
                buildings[index] = building;
                onDraftChanged(draft.copyWith(buildings: buildings));
              },
              onRemove: () {
                final buildingId = draft.buildings[index].id;
                onDraftChanged(
                  draft.copyWith(
                    buildings: [
                      for (final building in draft.buildings)
                        if (building.id != buildingId) building,
                    ],
                    attachments: [
                      for (final attachment in draft.attachments)
                        if (attachment.buildingId == buildingId)
                          ProjectAttachment(
                            id: attachment.id,
                            fileName: attachment.fileName,
                            documentType: attachment.documentType,
                            reference: attachment.reference,
                            buildingId: null,
                            addedAt: attachment.addedAt,
                            addedByUserId: attachment.addedByUserId,
                            addedByRole: attachment.addedByRole,
                          )
                        else
                          attachment,
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: ProjectCreateStrings.addBuilding.primary,
              icon: Icons.add_rounded,
              isExpanded: false,
              onPressed: () => onDraftChanged(
                draft.copyWith(
                  buildings: [
                    ...draft.buildings,
                    ProjectBuilding(id: _uuid.v4(), code: '', name: ''),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const Divider(color: AppColors.line),
          const SizedBox(height: AppSpacing.xl),
          _StageHeader(
            title: ProjectCreateStrings.documents,
            description: ProjectCreateStrings.documentsDescription,
            lang: lang,
            small: true,
          ),
          const SizedBox(height: AppSpacing.md),
          if (draft.attachments.isEmpty)
            Text(
              ProjectCreateStrings.noDocuments.primary,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            )
          else
            for (final attachment in draft.attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(attachment.fileName),
                subtitle: Text(
                  '${attachment.documentType} · '
                  '${_scopeName(attachment.buildingId, draft.buildings)}',
                ),
                trailing: IconButton(
                  tooltip: AppStrings.delete.primary,
                  onPressed: () => onDraftChanged(
                    draft.copyWith(
                      attachments: [
                        for (final item in draft.attachments)
                          if (item.id != attachment.id) item,
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: ProjectCreateStrings.addDocument.primary,
              icon: Icons.attach_file_rounded,
              isExpanded: false,
              onPressed: onAddAttachment,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingEditor extends StatelessWidget {
  const _BuildingEditor({
    super.key,
    required this.index,
    required this.building,
    required this.lang,
    required this.canRemove,
    required this.requiredValidator,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final ProjectBuilding building;
  final AppLanguage lang;
  final bool canRemove;
  final FormFieldValidator<String> requiredValidator;
  final ValueChanged<ProjectBuilding> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ProjectCreateStrings.building.primary} ${index + 1}',
                  style: AppTypography.titleMedium,
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: ProjectCreateStrings.removeBuilding.primary,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ResponsiveFields(
            children: [
              _InitialTextFieldBlock(
                fieldKey: ValueKey('building-code-${building.id}'),
                label: ProjectCreateStrings.buildingCode,
                lang: lang,
                initialValue: building.code,
                required: true,
                validator: requiredValidator,
                onChanged: (value) => onChanged(building.copyWith(code: value)),
              ),
              _InitialTextFieldBlock(
                fieldKey: ValueKey('building-name-${building.id}'),
                label: ProjectCreateStrings.buildingName,
                lang: lang,
                initialValue: building.name,
                required: true,
                validator: requiredValidator,
                onChanged: (value) => onChanged(building.copyWith(name: value)),
              ),
              _InitialTextFieldBlock(
                label: ProjectCreateStrings.floors,
                lang: lang,
                initialValue: building.floorsOrLevels.join(', '),
                hint: ProjectCreateStrings.floorsHint.primary,
                onChanged: (value) => onChanged(
                  building.copyWith(floorsOrLevels: _splitNames(value)),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLabel(label: ProjectCreateStrings.frpRoom, lang: lang),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(ProjectCreateStrings.no.primary),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(ProjectCreateStrings.yes.primary),
                      ),
                    ],
                    selected: {building.hasFrpRoom},
                    onSelectionChanged: (value) =>
                        onChanged(building.copyWith(hasFrpRoom: value.single)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewStage extends ConsumerWidget {
  const _ReviewStage({required this.draft, required this.lang});

  final ProjectCreationDraft draft;
  final AppLanguage lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final actor = ref.watch(currentUserProvider);
    String userName(String? id) {
      if (id == null) return '—';
      for (final user in users) {
        if (user.id == id) return user.fullName;
      }
      return id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageHeader(
          title: ProjectCreateStrings.stepThree,
          description: ProjectCreateStrings.reviewDescription,
          lang: lang,
        ),
        const SizedBox(height: AppSpacing.xl),
        _ReviewSection(
          title: ProjectCreateStrings.reviewIdentity.primary,
          rows: [
            _ReviewRow(
              ProjectCreateStrings.yorksReference.primary,
              draft.yorksReference,
            ),
            _ReviewRow(AppStrings.projectName.primary, draft.name),
            _ReviewRow(AppStrings.clientName.primary, draft.clientName),
            _ReviewRow(AppStrings.siteLocation.primary, draft.siteLocation),
            _ReviewRow(
              AppStrings.startDate.primary,
              _dateText(draft.startDate),
            ),
            _ReviewRow(
              AppStrings.expectedEndDate.primary,
              _dateText(draft.expectedEndDate),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewSection(
          title: ProjectCreateStrings.responsibility.primary,
          rows: [
            _ReviewRow(
              ProjectCreateStrings.projectManager.primary,
              userName(draft.projectManagerUserId),
            ),
            _ReviewRow(
              ProjectCreateStrings.designEngineers.primary,
              draft.designEngineerUserIds.map(userName).join(', '),
            ),
            _ReviewRow(
              ProjectCreateStrings.createdBy.primary,
              '${actor?.fullName ?? '—'} · ${actor?.role.label ?? '—'}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewSection(
          title: ProjectCreateStrings.stepTwo.primary,
          rows: [
            for (final building in draft.buildings)
              _ReviewRow(
                '${building.code} · ${building.name}',
                [
                  if (building.floorsOrLevels.isNotEmpty)
                    building.floorsOrLevels.join(', '),
                  '${ProjectCreateStrings.frpRoom.primary}: '
                      '${building.hasFrpRoom ? ProjectCreateStrings.yes.primary : ProjectCreateStrings.no.primary}',
                ].join(' · '),
              ),
            _ReviewRow(ProjectCreateStrings.projectWide.primary, 'COMMON'),
          ],
        ),
        if (draft.subContractorNames.isNotEmpty ||
            draft.otherContractorNames.isNotEmpty ||
            draft.consultant.trim().isNotEmpty ||
            draft.mainContractor.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _ReviewSection(
            title: ProjectCreateStrings.optionalParties.primary,
            rows: [
              _ReviewRow(
                ProjectCreateStrings.consultant.primary,
                _display(draft.consultant),
              ),
              _ReviewRow(
                ProjectCreateStrings.mainContractor.primary,
                _display(draft.mainContractor),
              ),
              _ReviewRow(
                ProjectCreateStrings.subcontractors.primary,
                _display(draft.subContractorNames.join(', ')),
              ),
              _ReviewRow(
                ProjectCreateStrings.otherContractors.primary,
                _display(draft.otherContractorNames.join(', ')),
              ),
            ],
          ),
        ],
        if (draft.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _ReviewSection(
            title: ProjectCreateStrings.documents.primary,
            rows: [
              for (final attachment in draft.attachments)
                _ReviewRow(
                  attachment.fileName,
                  '${attachment.documentType} · '
                  '${_scopeName(attachment.buildingId, draft.buildings)}',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.rows});

  final String title;
  final List<_ReviewRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            color: AppColors.surface,
            child: Text(title, style: AppTypography.titleSmall),
          ),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 170,
                    child: Text(
                      row.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _display(row.value),
                      style: AppTypography.bodyMedium,
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

class _ReviewRow {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.currentStep,
    required this.lang,
    required this.saving,
    required this.onBack,
    required this.onSaveDraft,
    required this.onContinue,
  });

  final int currentStep;
  final AppLanguage lang;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSaveDraft;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final controls = [
            SecondaryButton(
              label: ProjectCreateStrings.back.primary,
              icon: Icons.arrow_back_rounded,
              isExpanded: compact,
              onPressed: saving ? null : onBack,
            ),
            SecondaryButton(
              label: ProjectCreateStrings.saveDraft.primary,
              icon: Icons.save_outlined,
              isExpanded: compact,
              onPressed: saving ? null : onSaveDraft,
            ),
            PrimaryButton(
              label: currentStep == 2
                  ? ProjectCreateStrings.create.primary
                  : ProjectCreateStrings.next.primary,
              icon: currentStep == 2
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded,
              isTrailingIcon: true,
              isExpanded: compact,
              isLoading: saving,
              onPressed: saving ? null : onContinue,
            ),
          ];
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ProjectCreateStrings.autosaved.primary,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...[
                  for (final control in controls) ...[
                    control,
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            );
          }
          return Row(
            children: [
              Text(
                ProjectCreateStrings.autosaved.primary,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              for (final control in controls) ...[
                control,
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.title,
    required this.description,
    required this.lang,
    this.small = false,
  });

  final TranslatableString title;
  final TranslatableString description;
  final AppLanguage lang;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.primary,
          style: small
              ? AppTypography.titleLarge
              : AppTypography.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          title.secondary(lang),
          style: _secondaryStyle(
            lang,
            12,
          ).copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(description.primary, style: AppTypography.bodyMedium),
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            for (final child in children)
              SizedBox(
                width: (constraints.maxWidth - AppSpacing.lg) / 2,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    required this.lang,
    this.required = false,
  });

  final TranslatableString label;
  final AppLanguage lang;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${label.primary}${required ? ' *' : ''}',
          style: AppTypography.labelLarge,
        ),
        Text(
          label.secondary(lang),
          style: _secondaryStyle(
            lang,
            11,
          ).copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TextFieldBlock extends StatelessWidget {
  const _TextFieldBlock({
    required this.label,
    required this.lang,
    required this.controller,
    this.fieldKey,
    this.required = false,
    this.validator,
    this.hint,
    this.maxLines = 1,
  });

  final Key? fieldKey;
  final TranslatableString label;
  final AppLanguage lang;
  final TextEditingController controller;
  final bool required;
  final FormFieldValidator<String>? validator;
  final String? hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label: label, lang: lang, required: required),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          key: fieldKey,
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _InitialTextFieldBlock extends StatelessWidget {
  const _InitialTextFieldBlock({
    required this.label,
    required this.lang,
    required this.initialValue,
    required this.onChanged,
    this.fieldKey,
    this.required = false,
    this.validator,
    this.hint,
  });

  final Key? fieldKey;
  final TranslatableString label;
  final AppLanguage lang;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool required;
  final FormFieldValidator<String>? validator;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label: label, lang: lang, required: required),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          key: fieldKey,
          initialValue: initialValue,
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.lang,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    this.required = false,
  });

  final Key? fieldKey;
  final TranslatableString label;
  final AppLanguage lang;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label: label, lang: lang, required: required),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          key: fieldKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
            alignment: Alignment.centerLeft,
            side: const BorderSide(color: AppColors.lineStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
          onPressed: () async {
            final now = DateTime.now();
            final selected = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 15),
            );
            if (selected != null) onChanged(selected);
          },
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(value == null ? '—' : DateFormat.yMMMd().format(value!)),
              const Spacer(),
              if (value != null && !required)
                IconButton(
                  tooltip: AppStrings.cancel.primary,
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

List<String> _splitNames(String value) {
  return value
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _scopeName(String? buildingId, List<ProjectBuilding> buildings) {
  if (buildingId == null) return ProjectCreateStrings.projectWide.primary;
  for (final building in buildings) {
    if (building.id == buildingId) {
      return '${building.code} · ${building.name}';
    }
  }
  return ProjectCreateStrings.projectWide.primary;
}

String _dateText(DateTime? value) =>
    value == null ? '—' : DateFormat.yMMMd().format(value);

String _display(String value) => value.trim().isEmpty ? '—' : value.trim();

TextStyle _secondaryStyle(AppLanguage lang, double size) {
  if (lang == AppLanguage.hindi) {
    return AppTypography.bodySmall.copyWith(fontSize: size);
  }
  return AppTypography.urduStyle(englishFontSize: size + 2);
}
