import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/controllers/yorks_v1_project_controller.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_project_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_project_team_directory_member.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_project_controller_provider.dart';
import '../../../../shared/providers/yorks_v1_project_creation_draft_provider.dart';
import '../../../../shared/providers/yorks_v1_project_team_directory_provider.dart';
import '../../../../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/services/yorks_v1_document_file_service.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';

/// The normalized Yorks V1 R35 project creation experience.
///
/// This screen intentionally owns only recoverable local draft input and
/// delegates the committed create command to [YorksV1ProjectCommandController].
/// It never writes projects, scopes, memberships or BOQ groups locally.
class YorksV1LegacyProjectCreateFlowScreen extends ConsumerStatefulWidget {
  const YorksV1LegacyProjectCreateFlowScreen({
    super.key,
    this.onProjectCreated,
    this.editItem,
    this.onProjectUpdated,
  });

  /// Lets route composition move to the authoritative project workspace after
  /// the server has committed the project. It is deliberately called only
  /// after the local creation draft was discarded.
  final ValueChanged<YorksV1Project>? onProjectCreated;

  /// Supplying an authorized portfolio item changes this five-stage surface
  /// into an edit flow. The server is still the authority for every update.
  final YorksV1ProjectPortfolioItem? editItem;
  final ValueChanged<YorksV1Project>? onProjectUpdated;

  bool get isEditing => editItem != null;

  @override
  ConsumerState<YorksV1LegacyProjectCreateFlowScreen> createState() =>
      _YorksV1LegacyProjectCreateFlowScreenState();
}

/// Resolves the current authorized project projection before presenting the
/// same five-stage R35 setup form in update mode.
class YorksV1LegacyProjectEditFlowScreen extends ConsumerWidget {
  const YorksV1LegacyProjectEditFlowScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(yorksV1ProjectPortfolioProvider);
    return portfolio.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => _AccessState(
        title: YorksV1ProjectStrings.noPermission,
        description: YorksV1ProjectStrings.projectUpdateFailed,
        language: ref.watch(languageProvider),
      ),
      data: (items) {
        final item = items.where((value) => value.project.id == projectId);
        if (item.isEmpty) {
          return _AccessState(
            title: YorksV1ProjectStrings.noPermission,
            description: YorksV1ProjectStrings.noPermissionDescription,
            language: ref.watch(languageProvider),
          );
        }
        return YorksV1LegacyProjectCreateFlowScreen(
          editItem: item.first,
          onProjectUpdated: (_) =>
              context.go(RoutePaths.yorksV1ProjectPath(projectId)),
        );
      },
    );
  }
}

class _YorksV1LegacyProjectCreateFlowScreenState
    extends ConsumerState<YorksV1LegacyProjectCreateFlowScreen>
    with WidgetsBindingObserver {
  final _detailsFormKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _referenceController = TextEditingController();
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _jobOrContractController = TextEditingController();
  final _siteController = TextEditingController();
  final _notesController = TextEditingController();
  final _consultantController = TextEditingController();
  final _mainContractorController = TextEditingController();
  final _subcontractorController = TextEditingController();
  final _otherContractorController = TextEditingController();
  final _buildingCodeController = TextEditingController();
  final _buildingNameController = TextEditingController();
  final _buildingFloorsController = TextEditingController();
  final _buildingDeliveryAddressController = TextEditingController();

  Timer? _draftSaveTimer;
  YorksV1ProjectCreationDraft? _pendingDraft;
  YorksV1ProjectCreationDraft? _editDraft;
  String? _activeAuthUserId;
  Set<YorksV1ProjectValidationCode> _validationErrors = const {};
  bool _hasFrpRoom = false;
  int? _editingBuildingIndex;
  bool _isCreating = false;
  List<YorksV1SelectedDocument> _selectedAttachmentFiles = const [];

  List<TextEditingController> get _controllers => [
    _referenceController,
    _nameController,
    _clientController,
    _jobOrContractController,
    _siteController,
    _notesController,
    _consultantController,
    _mainContractorController,
    _subcontractorController,
    _otherContractorController,
    _buildingCodeController,
    _buildingNameController,
    _buildingFloorsController,
    _buildingDeliveryAddressController,
  ];

  bool get _isEditing => widget.isEditing;

  void _seedEditDraft(String authUserId) {
    final item = widget.editItem;
    if (item == null || _editDraft != null) return;
    YorksV1ProjectPartyInput? partyFor(YorksV1ProjectPartyKind kind) {
      for (final party in item.parties) {
        if (party.kind == kind) return party;
      }
      return null;
    }

    final client = partyFor(YorksV1ProjectPartyKind.client);
    _editDraft = YorksV1ProjectCreationDraft(
      ownerAuthUserId: authUserId,
      currentStage: YorksV1ProjectCreationStage.projectDetails,
      creationIdempotencyKey: const Uuid().v4(),
      reference: item.project.reference,
      name: item.project.name,
      clientName: client?.name ?? item.clientName,
      jobOrContractReference: item.project.jobOrContractReference,
      siteLocation: item.project.siteLocation,
      startDate: item.project.startDate,
      endDate: item.project.endDate,
      notes: item.project.notes,
      parties: [
        for (final party in item.parties)
          if (party.kind != YorksV1ProjectPartyKind.client) party,
      ],
      buildings: item.buildings,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingDraft());
    }
  }

  @override
  void dispose() {
    // A text edit may still be inside the short debounce window when a route
    // is popped or the app is backgrounded.  Start the owner-scoped local save
    // before tearing down the screen so a recovery session resumes exactly at
    // the last entered value rather than the previous field value.
    unawaited(_flushPendingDraft());
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final authUserId = ref.watch(yorksV1AuthUserIdProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final permissionState = ref.watch(yorksV1CurrentPermissionSnapshotProvider);
    final permission = yorksV1FeatureActionAccess(
      permissionState,
      _isEditing
          ? YorksV1CapabilityKeys.projectsEdit
          : YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: role?.canCreateProject == true,
      projectId: widget.editItem?.project.id,
    );

    if (authUserId == null || authUserId.trim().isEmpty) {
      return _AccessState(
        title: YorksV1ProjectStrings.signInRequired,
        description: YorksV1ProjectStrings.signInRequired,
        language: language,
      );
    }
    if (role == null || !permission.isVisible) {
      return _AccessState(
        title: YorksV1ProjectStrings.noPermission,
        description: YorksV1ProjectStrings.noPermissionDescription,
        language: language,
      );
    }
    if (_activeAuthUserId != authUserId) {
      _draftSaveTimer?.cancel();
      _pendingDraft = null;
      _activeAuthUserId = authUserId;
      _validationErrors = const {};
      _selectedAttachmentFiles = const [];
      _editDraft = null;
      _editingBuildingIndex = null;
    }

    _seedEditDraft(authUserId);
    final draft = _isEditing
        ? _editDraft!
        : ref.watch(yorksV1ProjectCreationDraftProvider(authUserId));
    _synchronizeControllers(_pendingDraft ?? draft);
    final commandState = ref.watch(yorksV1ProjectCommandControllerProvider);

    // The directory is needed only on the access and review stages. Keeping
    // the request out of the remaining creation flow both minimises the
    // exposure window for this safe projection and avoids needless RPC calls.
    final teamDirectory =
        draft.currentStage == YorksV1ProjectCreationStage.partiesAndAccess ||
            draft.currentStage == YorksV1ProjectCreationStage.reviewAndCreate
        ? ref.watch(yorksV1ActiveProjectTeamDirectoryProvider)
        : null;

    final saving =
        _isCreating ||
        ((commandState.operation ==
                    YorksV1ProjectCommandOperation.createProject ||
                commandState.operation ==
                    YorksV1ProjectCommandOperation.updateProject) &&
            commandState.status == YorksV1ProjectCommandStatus.saving);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop =
                constraints.maxWidth >=
                    AppSpacing.yorksV1ShellDesktopBreakpoint ||
                MediaQuery.sizeOf(context).width >=
                    AppSpacing.yorksV1ShellDesktopBreakpoint;
            final content = _buildStageContent(
              draft: draft,
              language: language,
              creatorRole: role,
              creatorAuthUserId: authUserId,
              teamDirectory: teamDirectory,
            );
            final navigation = _StageNavigation(
              currentStage: draft.currentStage,
              language: language,
              vertical: desktop,
              onSelect: _selectStage,
            );
            final footer = _StageActions(
              stage: draft.currentStage,
              language: language,
              saving: saving,
              onBack: _back,
              onContinue: _continue,
              onSkip: _skipAttachments,
              onCreate: permission.canWrite ? _createProject : null,
              primaryLabel: _isEditing
                  ? YorksV1ProjectStrings.updateProject
                  : YorksV1ProjectStrings.createAndView,
            );
            if (!desktop) {
              return ColoredBox(
                color: AppColors.mobileSurface,
                child: Column(
                  children: [
                    Material(
                      color: AppColors.surfaceContainerLowest,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                        child: navigation,
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.line),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _R35CreationStageHeader(stage: draft.currentStage),
                            const SizedBox(height: 4),
                            YorksV1ActionAvailabilityNotice(
                              access: permission,
                              language: language,
                              onRetry: () => ref
                                  .read(
                                    yorksV1CurrentPermissionSnapshotProvider
                                        .notifier,
                                  )
                                  .retryVerification(),
                            ),
                            content,
                          ],
                        ),
                      ),
                    ),
                    Material(
                      color: AppColors.surfaceContainerLowest,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.line),
                            ),
                          ),
                          child: footer,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final horizontal = desktop ? 30.0 : 14.0;
            return ColoredBox(
              color: desktop ? AppColors.surface : AppColors.mobileSurface,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  desktop ? 26 : 18,
                  horizontal,
                  96,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.pageMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      YorksR35PageHeader(
                        eyebrow: YorksV1ProjectStrings
                            .projectCreationEyebrow
                            .primary,
                        title:
                            (_isEditing
                                    ? YorksV1ProjectStrings.editProject
                                    : YorksV1ProjectStrings.createProject)
                                .primary,
                        description:
                            (_isEditing
                                    ? YorksV1ProjectStrings
                                          .editProjectDescription
                                    : YorksV1ProjectStrings
                                          .createProjectDescription)
                                .primary,
                        actions: [
                          if (!_isEditing)
                            SizedBox(
                              height: AppSpacing.minTapTarget,
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => _saveDraft(draft),
                                child: Text(
                                  YorksV1ProjectStrings.saveDraft.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      YorksV1ActionAvailabilityNotice(
                        access: permission,
                        language: language,
                        onRetry: () => ref
                            .read(
                              yorksV1CurrentPermissionSnapshotProvider.notifier,
                            )
                            .retryVerification(),
                      ),
                      const SizedBox(height: 19),
                      _R35ProjectCreationFrame(
                        navigation: navigation,
                        verticalNavigation: desktop,
                        currentStage: draft.currentStage,
                        content: content,
                        footer: footer,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStageContent({
    required YorksV1ProjectCreationDraft draft,
    required AppLanguage language,
    required YorksV1Role creatorRole,
    required String creatorAuthUserId,
    required AsyncValue<List<YorksV1ProjectTeamDirectoryMember>>? teamDirectory,
  }) {
    final stage = draft.currentStage;
    final stageBody = switch (stage) {
      YorksV1ProjectCreationStage.projectDetails => _DetailsStage(
        formKey: _detailsFormKey,
        language: language,
        referenceController: _referenceController,
        nameController: _nameController,
        clientController: _clientController,
        jobOrContractController: _jobOrContractController,
        siteController: _siteController,
        notesController: _notesController,
        startDate: draft.startDate,
        endDate: draft.endDate,
        validationErrors: _validationErrors,
        onReferenceChanged: (value) =>
            _queueDraft((current) => current.copyWith(reference: value)),
        onNameChanged: (value) =>
            _queueDraft((current) => current.copyWith(name: value)),
        onClientChanged: (value) =>
            _queueDraft((current) => current.copyWith(clientName: value)),
        onJobOrContractChanged: (value) => _queueDraft(
          (current) => current.copyWith(jobOrContractReference: value),
        ),
        onSiteChanged: (value) =>
            _queueDraft((current) => current.copyWith(siteLocation: value)),
        onNotesChanged: (value) =>
            _queueDraft((current) => current.copyWith(notes: value)),
        onSelectStartDate: () => _selectDate(isStartDate: true),
        onSelectEndDate: () => _selectDate(isStartDate: false),
      ),
      YorksV1ProjectCreationStage.partiesAndAccess => _PartiesAndAccessStage(
        draft: draft,
        language: language,
        consultantController: _consultantController,
        mainContractorController: _mainContractorController,
        subcontractorController: _subcontractorController,
        otherContractorController: _otherContractorController,
        validationErrors: _validationErrors,
        creatorRole: creatorRole,
        creatorAuthUserId: creatorAuthUserId,
        teamDirectory: teamDirectory!,
        onConsultantChanged: (value) =>
            _setSingleParty(YorksV1ProjectPartyKind.consultant, value),
        onMainContractorChanged: (value) =>
            _setSingleParty(YorksV1ProjectPartyKind.mainContractor, value),
        onAddSubcontractor: () => _addNamedParty(
          YorksV1ProjectPartyKind.subcontractor,
          _subcontractorController,
        ),
        onAddOtherContractor: () => _addNamedParty(
          YorksV1ProjectPartyKind.otherContractor,
          _otherContractorController,
        ),
        onRemoveParty: _removePartyAt,
        onAddInitialMember: _addInitialMember,
        onRemoveInitialMember: _removeInitialMemberAt,
        showTeam: !_isEditing,
      ),
      YorksV1ProjectCreationStage.buildings => _BuildingsStage(
        draft: draft,
        language: language,
        codeController: _buildingCodeController,
        nameController: _buildingNameController,
        floorsController: _buildingFloorsController,
        deliveryAddressController: _buildingDeliveryAddressController,
        hasFrpRoom: _hasFrpRoom,
        editingBuildingIndex: _editingBuildingIndex,
        validationErrors: _validationErrors,
        onHasFrpRoomChanged: (value) => setState(() => _hasFrpRoom = value),
        onAddBuilding: _addBuilding,
        onEditBuilding: _editBuildingAt,
        onCancelEditing: _resetBuildingEditor,
        onRemoveBuilding: _removeBuildingAt,
      ),
      YorksV1ProjectCreationStage.attachments => _AttachmentsStage(
        draft: draft,
        language: language,
        validationErrors: _validationErrors,
        onAddAttachment: _addAttachment,
        onDroppedAttachments: _addSelectedAttachments,
        onDropError: _showInvalidAttachmentMessage,
        onRemoveAttachment: _removeAttachmentAt,
        pendingFiles: _selectedAttachmentFiles,
      ),
      YorksV1ProjectCreationStage.reviewAndCreate => _ReviewStage(
        draft: draft,
        language: language,
        validationErrors: _validationErrors,
        teamDirectory: teamDirectory!,
        onRetryDirectory: () =>
            ref.invalidate(yorksV1ActiveProjectTeamDirectoryProvider),
      ),
    };

    return stageBody;
  }

  void _synchronizeControllers(YorksV1ProjectCreationDraft draft) {
    _setControllerText(_referenceController, draft.reference);
    _setControllerText(_nameController, draft.name);
    _setControllerText(_clientController, draft.clientName ?? '');
    _setControllerText(
      _jobOrContractController,
      draft.jobOrContractReference ?? '',
    );
    _setControllerText(_siteController, draft.siteLocation ?? '');
    _setControllerText(_notesController, draft.notes ?? '');
    _setControllerText(
      _consultantController,
      _partyFor(draft, YorksV1ProjectPartyKind.consultant)?.name ?? '',
    );
    _setControllerText(
      _mainContractorController,
      _partyFor(draft, YorksV1ProjectPartyKind.mainContractor)?.name ?? '',
    );
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  YorksV1ProjectCreationDraft _currentDraft() {
    if (_isEditing) {
      final draft = _pendingDraft ?? _editDraft;
      if (draft != null) return draft;
    }
    final authUserId = _activeAuthUserId;
    if (authUserId == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unauthenticated,
      );
    }
    return _pendingDraft ??
        ref.read(yorksV1ProjectCreationDraftProvider(authUserId));
  }

  void _queueDraft(
    YorksV1ProjectCreationDraft Function(YorksV1ProjectCreationDraft current)
    transform,
  ) {
    if (_activeAuthUserId == null) return;
    _pendingDraft = transform(_currentDraft());
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_flushPendingDraft());
    });
  }

  Future<void> _flushPendingDraft() async {
    _draftSaveTimer?.cancel();
    final pending = _pendingDraft;
    final authUserId = _activeAuthUserId;
    if (pending == null || authUserId == null) return;
    _pendingDraft = null;
    if (_isEditing) {
      if (mounted) setState(() => _editDraft = pending);
      return;
    }
    await ref
        .read(yorksV1ProjectCreationDraftProvider(authUserId).notifier)
        .save(pending);
  }

  Future<void> _saveDraft(YorksV1ProjectCreationDraft draft) async {
    _draftSaveTimer?.cancel();
    _pendingDraft = null;
    final authUserId = _activeAuthUserId;
    if (authUserId == null) return;
    if (_isEditing) {
      if (mounted) setState(() => _editDraft = draft);
      return;
    }
    await ref
        .read(yorksV1ProjectCreationDraftProvider(authUserId).notifier)
        .save(draft);
  }

  Future<void> _selectStage(YorksV1ProjectCreationStage target) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (target.index > current.currentStage.index) return;
    await _setStage(target);
  }

  Future<void> _setStage(YorksV1ProjectCreationStage stage) async {
    final authUserId = _activeAuthUserId;
    if (authUserId == null) return;
    final current = _currentDraft();
    _draftSaveTimer?.cancel();
    _pendingDraft = null;
    if (_isEditing) {
      _editDraft = current.copyWith(currentStage: stage);
      if (!mounted) return;
      _validationErrors = const {};
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
      return;
    }
    await ref
        .read(yorksV1ProjectCreationDraftProvider(authUserId).notifier)
        .save(current.copyWith(currentStage: stage));
    if (!mounted) return;
    _validationErrors = const {};
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _continue() async {
    await _flushPendingDraft();
    final draft = _currentDraft();
    final errors = _errorsForStage(draft.currentStage, draft);
    if (draft.currentStage == YorksV1ProjectCreationStage.projectDetails &&
        !(_detailsFormKey.currentState?.validate() ?? false)) {
      _presentValidationErrors(errors.isEmpty ? _requiredFieldErrors : errors);
      return;
    }
    if (errors.isNotEmpty) {
      _presentValidationErrors(errors);
      return;
    }
    final next = draft.currentStage.next;
    if (next != null) await _setStage(next);
  }

  Future<void> _skipAttachments() async {
    await _flushPendingDraft();
    await _setStage(YorksV1ProjectCreationStage.reviewAndCreate);
  }

  Future<void> _back() async {
    await _flushPendingDraft();
    if (!mounted) return;
    final current = _currentDraft().currentStage;
    final previous = current.previous;
    if (previous == null) {
      await Navigator.of(context).maybePop();
      return;
    }
    await _setStage(previous);
  }

  Set<YorksV1ProjectValidationCode> get _requiredFieldErrors => {
    YorksV1ProjectValidationCode.missingProjectReference,
    YorksV1ProjectValidationCode.missingProjectName,
  };

  Set<YorksV1ProjectValidationCode> _errorsForStage(
    YorksV1ProjectCreationStage stage,
    YorksV1ProjectCreationDraft draft,
  ) {
    final all = draft.toCreationInput().validate();
    return switch (stage) {
      YorksV1ProjectCreationStage.projectDetails =>
        all
            .where(
              (error) =>
                  error ==
                      YorksV1ProjectValidationCode.missingProjectReference ||
                  error == YorksV1ProjectValidationCode.missingProjectName ||
                  error == YorksV1ProjectValidationCode.invalidDateRange ||
                  error == YorksV1ProjectValidationCode.unsupportedProjectDate,
            )
            .toSet(),
      YorksV1ProjectCreationStage.partiesAndAccess =>
        all
            .where(
              (error) =>
                  error == YorksV1ProjectValidationCode.invalidProjectParty ||
                  error == YorksV1ProjectValidationCode.duplicateProjectParty ||
                  error == YorksV1ProjectValidationCode.duplicateMember ||
                  error == YorksV1ProjectValidationCode.missingMemberAuthUserId,
            )
            .toSet(),
      YorksV1ProjectCreationStage.buildings =>
        all
            .where(
              (error) =>
                  error == YorksV1ProjectValidationCode.missingBuilding ||
                  error == YorksV1ProjectValidationCode.invalidBuilding ||
                  error == YorksV1ProjectValidationCode.duplicateBuildingCode,
            )
            .toSet(),
      YorksV1ProjectCreationStage.attachments =>
        all
            .where(
              (error) =>
                  error == YorksV1ProjectValidationCode.invalidAttachment,
            )
            .toSet(),
      YorksV1ProjectCreationStage.reviewAndCreate => all,
    };
  }

  void _presentValidationErrors(Set<YorksV1ProjectValidationCode> errors) {
    if (!mounted) return;
    setState(() => _validationErrors = Set.unmodifiable(errors));
    _showMessage(_messageForValidation(errors), error: true);
  }

  TranslatableString _messageForValidation(
    Set<YorksV1ProjectValidationCode> errors,
  ) {
    if (errors.contains(YorksV1ProjectValidationCode.invalidDateRange)) {
      return YorksV1ProjectStrings.endDateAfterStart;
    }
    if (errors.contains(YorksV1ProjectValidationCode.unsupportedProjectDate)) {
      return YorksV1ProjectStrings.projectDateSupportedRange;
    }
    if (errors.contains(YorksV1ProjectValidationCode.missingBuilding) ||
        errors.contains(YorksV1ProjectValidationCode.invalidBuilding)) {
      return YorksV1ProjectStrings.atLeastOneBuilding;
    }
    if (errors.contains(YorksV1ProjectValidationCode.duplicateBuildingCode)) {
      return YorksV1ProjectStrings.duplicateBuildingCode;
    }
    if (errors.contains(YorksV1ProjectValidationCode.duplicateMember)) {
      return YorksV1ProjectStrings.duplicateMember;
    }
    if (errors.contains(YorksV1ProjectValidationCode.missingProjectReference) ||
        errors.contains(YorksV1ProjectValidationCode.missingProjectName)) {
      return YorksV1ProjectStrings.requiredField;
    }
    if (errors.contains(YorksV1ProjectValidationCode.invalidAttachment)) {
      return YorksV1ProjectStrings.invalidAttachment;
    }
    return YorksV1ProjectStrings.stageNeedsAttention;
  }

  void _showMessage(TranslatableString copy, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,
          content: Text(copy.primary),
        ),
      );
  }

  Future<void> _selectDate({required bool isStartDate}) async {
    await _flushPendingDraft();
    if (!mounted) return;
    final draft = _currentDraft();
    final selected = isStartDate ? draft.startDate : draft.endDate;
    final today = DateUtils.dateOnly(DateTime.now());
    final earliest = DateTime(today.year - yorksV1ProjectDateWindowYears);
    final latest = DateTime(today.year + yorksV1ProjectDateWindowYears, 12, 31);
    final startDate = draft.startDate == null
        ? null
        : DateUtils.dateOnly(draft.startDate!);
    final firstDate =
        !isStartDate &&
            startDate != null &&
            !startDate.isBefore(earliest) &&
            !startDate.isAfter(latest)
        ? startDate
        : earliest;
    final requestedInitial =
        selected ?? (isStartDate ? today : startDate ?? today);
    final date = await showDatePicker(
      context: context,
      initialDate: _clampDate(requestedInitial, firstDate, latest),
      firstDate: firstDate,
      lastDate: latest,
    );
    if (date == null) return;
    await _saveDraft(
      isStartDate
          ? draft.copyWith(startDate: DateUtils.dateOnly(date))
          : draft.copyWith(endDate: DateUtils.dateOnly(date)),
    );
  }

  void _setSingleParty(YorksV1ProjectPartyKind kind, String name) {
    _queueDraft((current) {
      final existing = _partyFor(current, kind);
      final parties = <YorksV1ProjectPartyInput>[
        for (final party in current.parties)
          if (party.kind != kind) party,
      ];
      if (name.trim().isNotEmpty) {
        parties.add(
          YorksV1ProjectPartyInput(
            kind: kind,
            name: name,
            contactName: existing?.contactName,
            contactPhone: existing?.contactPhone,
            contactEmail: existing?.contactEmail,
            address: existing?.address,
          ),
        );
      }
      return current.copyWith(parties: parties);
    });
  }

  Future<void> _addNamedParty(
    YorksV1ProjectPartyKind kind,
    TextEditingController controller,
  ) async {
    final name = controller.text.trim();
    if (name.isEmpty) {
      _showMessage(YorksV1ProjectStrings.requiredField, error: true);
      return;
    }
    await _flushPendingDraft();
    final current = _currentDraft();
    await _saveDraft(
      current.copyWith(
        parties: [
          ...current.parties,
          YorksV1ProjectPartyInput(kind: kind, name: name),
        ],
      ),
    );
    controller.clear();
  }

  Future<void> _removePartyAt(int index) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (index < 0 || index >= current.parties.length) return;
    await _saveDraft(
      current.copyWith(
        parties: [
          for (var item = 0; item < current.parties.length; item++)
            if (item != index) current.parties[item],
        ],
      ),
    );
  }

  Future<void> _addInitialMember(
    YorksV1ProjectTeamDirectoryMember member,
    YorksV1ProjectMembershipRole projectRole,
  ) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (current.initialMembers.any(
      (assigned) => assigned.authUserId == member.authUserId,
    )) {
      _showMessage(YorksV1ProjectStrings.duplicateMember, error: true);
      return;
    }
    await _saveDraft(
      current.copyWith(
        initialMembers: [
          ...current.initialMembers,
          YorksV1InitialProjectMemberInput(
            authUserId: member.authUserId,
            projectRole: projectRole,
          ),
        ],
      ),
    );
  }

  Future<void> _removeInitialMemberAt(int index) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (index < 0 || index >= current.initialMembers.length) return;
    await _saveDraft(
      current.copyWith(
        initialMembers: [
          for (var item = 0; item < current.initialMembers.length; item++)
            if (item != index) current.initialMembers[item],
        ],
      ),
    );
  }

  Future<void> _addBuilding() async {
    final name = _buildingNameController.text.trim();
    if (name.isEmpty) {
      _showMessage(YorksV1ProjectStrings.requiredField, error: true);
      return;
    }
    await _flushPendingDraft();
    final current = _currentDraft();
    final editingIndex = _editingBuildingIndex;
    if (editingIndex != null &&
        (editingIndex < 0 || editingIndex >= current.buildings.length)) {
      _resetBuildingEditor();
      return;
    }
    final existing = editingIndex == null
        ? null
        : current.buildings[editingIndex];
    final building = YorksV1ProjectBuildingInput(
      sourceScopeId: existing?.sourceScopeId,
      code: _buildingCodeController.text,
      name: name,
      floorsOrLevels: _buildingFloorsController.text
          .split(RegExp(r'[\n,]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      hasFrpRoom: _hasFrpRoom,
      deliveryAddress: _emptyToNull(_buildingDeliveryAddressController.text),
    );
    final buildings = [...current.buildings];
    if (editingIndex == null) {
      buildings.add(building);
    } else {
      buildings[editingIndex] = building;
    }
    await _saveDraft(current.copyWith(buildings: buildings));
    if (!mounted) return;
    setState(() {
      _editingBuildingIndex = null;
      _seedNextBuildingForm(building, buildings);
    });
  }

  Future<void> _editBuildingAt(int index) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (index < 0 || index >= current.buildings.length || !mounted) return;
    final building = current.buildings[index];
    setState(() {
      _editingBuildingIndex = index;
      _setControllerText(_buildingCodeController, building.code);
      _setControllerText(_buildingNameController, building.name);
      _setControllerText(
        _buildingFloorsController,
        building.floorsOrLevels.join(', '),
      );
      _setControllerText(
        _buildingDeliveryAddressController,
        building.deliveryAddress ?? '',
      );
      _hasFrpRoom = building.hasFrpRoom;
    });
  }

  void _resetBuildingEditor() {
    if (!mounted) return;
    setState(() {
      _editingBuildingIndex = null;
      _buildingCodeController.clear();
      _buildingNameController.clear();
      _buildingFloorsController.clear();
      _buildingDeliveryAddressController.clear();
      _hasFrpRoom = false;
    });
  }

  void _seedNextBuildingForm(
    YorksV1ProjectBuildingInput building,
    List<YorksV1ProjectBuildingInput> existingBuildings,
  ) {
    _setControllerText(
      _buildingCodeController,
      _nextBuildingCode(building.code, existingBuildings),
    );
    _setControllerText(_buildingNameController, building.name);
    _setControllerText(
      _buildingFloorsController,
      building.floorsOrLevels.join(', '),
    );
    _setControllerText(
      _buildingDeliveryAddressController,
      building.deliveryAddress ?? '',
    );
    _hasFrpRoom = building.hasFrpRoom;
  }

  String _nextBuildingCode(
    String source,
    List<YorksV1ProjectBuildingInput> existingBuildings,
  ) {
    final normalized = source.trim().toUpperCase();
    if (normalized.isEmpty) return '';
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(normalized);
    final prefix = match?.group(1) ?? '$normalized-';
    final numericSuffix = match?.group(2) ?? '';
    final minimumDigits = numericSuffix.length;
    var number = int.tryParse(numericSuffix) ?? 1;
    final existing = existingBuildings
        .map((building) => building.normalizedCode)
        .toSet();
    String candidate;
    do {
      number++;
      candidate = '$prefix${number.toString().padLeft(minimumDigits, '0')}';
    } while (existing.contains(candidate));
    return candidate;
  }

  Future<void> _removeBuildingAt(int index) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (index < 0 || index >= current.buildings.length) return;
    await _saveDraft(
      current.copyWith(
        buildings: [
          for (var item = 0; item < current.buildings.length; item++)
            if (item != index) current.buildings[item],
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      if (_editingBuildingIndex == index) {
        _editingBuildingIndex = null;
        _buildingCodeController.clear();
        _buildingNameController.clear();
        _buildingFloorsController.clear();
        _buildingDeliveryAddressController.clear();
        _hasFrpRoom = false;
      } else if (_editingBuildingIndex != null &&
          index < _editingBuildingIndex!) {
        _editingBuildingIndex = _editingBuildingIndex! - 1;
      }
    });
  }

  Future<void> _addAttachment() async {
    try {
      final selected = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (selected == null || !mounted) return;
      await _addSelectedAttachments([selected]);
    } on YorksV1DomainException catch (error) {
      _showMessage(
        error.code == YorksV1DomainErrorCode.invalidInput
            ? YorksV1ProjectStrings.invalidAttachment
            : YorksV1ProjectStrings.errorFor(error.code),
        error: true,
      );
    } catch (_) {
      _showMessage(
        YorksV1ProjectStrings.errorFor(
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
        error: true,
      );
    }
  }

  /// Adds picker and browser-drop files through one deduplicated local-draft
  /// path. Nothing is uploaded until the create command has succeeded.
  Future<void> _addSelectedAttachments(
    List<YorksV1SelectedDocument> selectedFiles,
  ) async {
    if (selectedFiles.isEmpty) return;
    await _flushPendingDraft();
    final current = _currentDraft();
    final existingNames = {
      for (final attachment in current.attachments)
        attachment.fileName.trim().toLowerCase(),
    };
    final pendingNames = {
      for (final file in _selectedAttachmentFiles)
        file.fileName.trim().toLowerCase(),
    };
    final additions = <YorksV1SelectedDocument>[];
    final reselected = <String, YorksV1SelectedDocument>{};
    var skippedDuplicate = false;
    for (final selected in selectedFiles) {
      final key = selected.fileName.trim().toLowerCase();
      if (existingNames.contains(key) && !pendingNames.contains(key)) {
        // Browser/file-picker bytes cannot be persisted safely in a local
        // recovery record. Selecting the same named file after resume is a
        // deliberate reattachment, not a duplicate.
        reselected[key] = selected;
        pendingNames.add(key);
        continue;
      }
      if (!existingNames.add(key)) {
        skippedDuplicate = true;
        continue;
      }
      additions.add(selected);
    }
    if (additions.isEmpty && reselected.isEmpty) {
      _showMessage(YorksV1ProjectStrings.duplicateAttachment, error: true);
      return;
    }
    await _saveDraft(
      current.copyWith(
        attachments: [
          for (final attachment in current.attachments)
            reselected[attachment.fileName.trim().toLowerCase()] == null
                ? attachment
                : YorksV1ProjectAttachmentInput(
                    fileName:
                        reselected[attachment.fileName.trim().toLowerCase()]!
                            .fileName,
                    mimeType:
                        reselected[attachment.fileName.trim().toLowerCase()]!
                            .mimeType,
                    sizeBytes:
                        reselected[attachment.fileName.trim().toLowerCase()]!
                            .bytes
                            .lengthInBytes,
                  ),
          for (final selected in additions)
            YorksV1ProjectAttachmentInput(
              fileName: selected.fileName,
              mimeType: selected.mimeType,
              sizeBytes: selected.bytes.lengthInBytes,
            ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _selectedAttachmentFiles = [
        for (final file in _selectedAttachmentFiles)
          if (!reselected.containsKey(file.fileName.trim().toLowerCase())) file,
        ...reselected.values,
        ...additions,
      ];
    });
    if (skippedDuplicate) {
      _showMessage(YorksV1ProjectStrings.duplicateAttachment, error: true);
    }
  }

  void _showInvalidAttachmentMessage() {
    _showMessage(YorksV1ProjectStrings.invalidAttachment, error: true);
  }

  Future<void> _removeAttachmentAt(int index) async {
    await _flushPendingDraft();
    final current = _currentDraft();
    if (index < 0 || index >= current.attachments.length) return;
    final removedFileName = current.attachments[index].fileName;
    await _saveDraft(
      current.copyWith(
        attachments: [
          for (var item = 0; item < current.attachments.length; item++)
            if (item != index) current.attachments[item],
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _selectedAttachmentFiles = [
        for (final file in _selectedAttachmentFiles)
          if (file.fileName.trim().toLowerCase() !=
              removedFileName.trim().toLowerCase())
            file,
      ];
    });
  }

  Future<void> _createProject() async {
    if (_isCreating) return;
    final role = ref.read(yorksV1CurrentRoleProvider);
    final access = yorksV1FeatureActionAccess(
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      _isEditing
          ? YorksV1CapabilityKeys.projectsEdit
          : YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: role?.canCreateProject == true,
      projectId: widget.editItem?.project.id,
    );
    if (!access.canWrite) return;
    await _flushPendingDraft();
    final draft = _currentDraft();
    if (!_isEditing && _hasAttachmentsNeedingReselect(draft)) {
      _showMessage(YorksV1ProjectStrings.attachmentNeedsReselect, error: true);
      if (draft.currentStage != YorksV1ProjectCreationStage.attachments) {
        await _setStage(YorksV1ProjectCreationStage.attachments);
      }
      return;
    }
    final loadedDirectory = ref
        .read(yorksV1ActiveProjectTeamDirectoryProvider)
        .asData
        ?.value;
    if (!_isEditing &&
        loadedDirectory != null &&
        _hasUnavailableInitialMember(draft, loadedDirectory)) {
      _showMessage(
        YorksV1ProjectStrings.teamMemberNoLongerAvailable,
        error: true,
      );
      if (draft.currentStage != YorksV1ProjectCreationStage.partiesAndAccess) {
        await _setStage(YorksV1ProjectCreationStage.partiesAndAccess);
      }
      return;
    }
    final errors = draft.toCreationInput().validate();
    if (errors.isNotEmpty) {
      final targetStage = _firstInvalidStage(errors);
      if (targetStage != draft.currentStage) await _setStage(targetStage);
      // Stage navigation clears prior errors. Present this validation result
      // afterwards so the destination retains its actionable inline feedback.
      _presentValidationErrors(errors);
      return;
    }

    setState(() => _isCreating = true);
    try {
      if (_isEditing) {
        final item = widget.editItem!;
        final updatedProject = await ref
            .read(yorksV1ProjectCommandControllerProvider.notifier)
            .updateProject(
              YorksV1ProjectUpdateInput(
                idempotencyKey: draft.creationIdempotencyKey,
                projectId: item.project.id,
                expectedProjectVersion: item.project.recordVersion,
                project: draft.toCreationInput(),
              ),
            );
        final failedAttachmentUploads = await _uploadSelectedAttachments(
          updatedProject,
        );
        ref.invalidate(yorksV1ProjectPortfolioProvider);
        if (!mounted) return;
        setState(() => _isCreating = false);
        if (failedAttachmentUploads > 0) {
          _showMessage(YorksV1ProjectStrings.attachmentUploadFailed);
        }
        widget.onProjectUpdated?.call(updatedProject);
        return;
      }

      final result = await ref
          .read(yorksV1ProjectCommandControllerProvider.notifier)
          .createProject(draft.toCreationInput());

      // The five-stage R35 flow ends at a usable workspace.  The create RPC
      // intentionally records the new project as a draft so activation stays
      // an audited, server-authorized lifecycle transition.  Complete that
      // transition here when the transaction returned an active Project
      // Engineer membership (the server re-checks the same invariant under a
      // row lock).  Without this bridge a newly-created project could be
      // opened in the UI but every MR submission would correctly be rejected
      // because submissions require an active project.
      var createdProject = result.project;
      if (createdProject.state == YorksV1ProjectLifecycle.draft &&
          result.members.any(
            (member) =>
                member.projectRole ==
                    YorksV1ProjectMembershipRole.projectEngineer &&
                member.effectiveTo == null,
          )) {
        createdProject = await ref
            .read(yorksV1ProjectCommandControllerProvider.notifier)
            .setProjectState(
              YorksV1SetProjectStateInput(
                idempotencyKey: const Uuid().v4(),
                projectId: createdProject.id,
                currentState: createdProject.state,
                targetState: YorksV1ProjectLifecycle.active,
                expectedProjectVersion: createdProject.recordVersion,
              ),
            );
      }

      final failedAttachmentUploads = await _uploadSelectedAttachments(
        createdProject,
      );

      final authUserId = _activeAuthUserId;
      if (authUserId != null) {
        await ref
            .read(yorksV1ProjectCreationDraftProvider(authUserId).notifier)
            .discard();
      }
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _selectedAttachmentFiles = const [];
      });
      if (failedAttachmentUploads > 0) {
        _showMessage(YorksV1ProjectStrings.attachmentUploadFailed);
      }
      final onProjectCreated = widget.onProjectCreated;
      if (onProjectCreated != null) {
        onProjectCreated(createdProject);
      } else if (mounted) {
        context.go(RoutePaths.yorksV1ProjectPath(createdProject.id));
      }
    } on YorksV1DomainException catch (error) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      _showMessage(YorksV1ProjectStrings.errorFor(error.code), error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      _showMessage(
        YorksV1ProjectStrings.errorFor(
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
        error: true,
      );
    }
  }

  bool _hasAttachmentsNeedingReselect(YorksV1ProjectCreationDraft draft) {
    if (draft.attachments.isEmpty) return false;
    final selectedNames = {
      for (final file in _selectedAttachmentFiles)
        file.fileName.trim().toLowerCase(),
    };
    return draft.attachments.any(
      (attachment) =>
          !selectedNames.contains(attachment.fileName.trim().toLowerCase()),
    );
  }

  Future<int> _uploadSelectedAttachments(YorksV1Project project) async {
    final files = List<YorksV1SelectedDocument>.of(_selectedAttachmentFiles);
    if (files.isEmpty) return 0;

    var failed = 0;
    for (final file in files) {
      try {
        await ref
            .read(yorksV1DocumentsRepositoryProvider)
            .upload(
              YorksV1DocumentUploadInput(
                projectId: project.id,
                entityType: YorksV1DocumentEntityType.project,
                entityId: project.id,
                classification: YorksV1DocumentClassification.operational,
                fileName: file.fileName,
                mimeType: file.mimeType,
                bytes: file.bytes,
                idempotencyKey: const Uuid().v4(),
              ),
            );
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }

  YorksV1ProjectCreationStage _firstInvalidStage(
    Set<YorksV1ProjectValidationCode> errors,
  ) {
    for (final stage in YorksV1ProjectCreationStage.values) {
      if (_errorsForStage(stage, _currentDraft()).isNotEmpty) return stage;
    }
    return YorksV1ProjectCreationStage.reviewAndCreate;
  }
}

class _AccessState extends StatelessWidget {
  const _AccessState({
    required this.title,
    required this.description,
    required this.language,
  });

  final TranslatableString title;
  final TranslatableString description;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: NexusPageShell(
          eyebrow: YorksV1ProjectStrings.projects.primary,
          title: title.primary,
          child: NexusSectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, color: AppColors.error),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _LocalizedCopy(
                    copy: description,
                    language: language,
                    englishStyle: AppTypography.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _R35ProjectCreationFrame extends StatelessWidget {
  const _R35ProjectCreationFrame({
    required this.currentStage,
    required this.content,
    required this.navigation,
    required this.verticalNavigation,
    required this.footer,
  });

  final YorksV1ProjectCreationStage currentStage;
  final Widget content;
  final Widget navigation;
  final bool verticalNavigation;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final mobileBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _R35CreationStageHeader(stage: currentStage),
        const Divider(height: 1, color: AppColors.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
          child: content,
        ),
        const Divider(height: 1, color: AppColors.line),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: footer,
        ),
      ],
    );
    final decoration = BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
    if (!verticalNavigation) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: AppColors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: navigation,
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            mobileBody,
          ],
        ),
      );
    }

    final frameHeight = MediaQuery.sizeOf(context).width <= 1024
        ? 680.0
        : 670.0;
    final desktopBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _R35CreationStageHeader(stage: currentStage),
        const Divider(height: 1, color: AppColors.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: content,
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: footer,
          ),
        ),
      ],
    );
    return SizedBox(
      height: frameHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(15),
          boxShadow: decoration.boxShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 230,
              child: ColoredBox(
                color: AppColors.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        YorksV1ProjectStrings.projectSetup.primary,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        YorksV1ProjectStrings.projectSetupDescription.primary,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                          fontSize: 10.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 22),
                      navigation,
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.line),
            Expanded(child: desktopBody),
          ],
        ),
      ),
    );
  }
}

class _R35CreationStageHeader extends StatelessWidget {
  const _R35CreationStageHeader({required this.stage});

  final YorksV1ProjectCreationStage stage;

  @override
  Widget build(BuildContext context) {
    final step = YorksV1ProjectStrings.stepOf.primary
        .replaceFirst('{current}', '${stage.index + 1}')
        .replaceFirst(
          '{total}',
          '${YorksV1ProjectCreationStage.values.length}',
        );
    final compact =
        MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint;
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(24, 22, 24, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.toUpperCase(),
            style: AppTypography.eyebrow.copyWith(
              color: AppColors.blue,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _stageCopy(stage).primary,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          if (compact)
            Text(
              (stage == YorksV1ProjectCreationStage.reviewAndCreate
                      ? YorksV1ProjectStrings.reviewCreationDescription
                      : _stageDescription(stage))
                  .primary,
              style: AppTypography.bodySmall.copyWith(height: 1.45),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  YorksV1ProjectStrings.stepSaved.primary,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StageNavigation extends StatelessWidget {
  const _StageNavigation({
    required this.currentStage,
    required this.language,
    required this.vertical,
    required this.onSelect,
  });

  final YorksV1ProjectCreationStage currentStage;
  final AppLanguage language;
  final bool vertical;
  final ValueChanged<YorksV1ProjectCreationStage> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final stage in YorksV1ProjectCreationStage.values)
        _StageNavigationItem(
          stage: stage,
          currentStage: currentStage,
          language: language,
          onTap: stage.index <= currentStage.index
              ? () => onSelect(stage)
              : null,
        ),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stage in YorksV1ProjectCreationStage.values)
          Expanded(
            child: _MobileStageNavigationItem(
              stage: stage,
              currentStage: currentStage,
              onTap: stage.index <= currentStage.index
                  ? () => onSelect(stage)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _MobileStageNavigationItem extends StatelessWidget {
  const _MobileStageNavigationItem({
    required this.stage,
    required this.currentStage,
    required this.onTap,
  });

  final YorksV1ProjectCreationStage stage;
  final YorksV1ProjectCreationStage currentStage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = stage == currentStage;
    final completed = stage.index < currentStage.index;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: _stageCopy(stage).primary,
      child: InkWell(
        key: ValueKey('yorks-v1-project-stage-${stage.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Column(
            children: [
              Row(
                children: [
                  if (stage.index > 0)
                    Expanded(
                      child: Divider(
                        color: completed || selected
                            ? AppColors.blue
                            : AppColors.lineStrong,
                      ),
                    )
                  else
                    const Spacer(),
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: completed || selected
                          ? AppColors.blue
                          : AppColors.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: completed || selected
                            ? AppColors.blue
                            : AppColors.lineStrong,
                      ),
                    ),
                    child: completed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : Text(
                            '${stage.index + 1}',
                            style: AppTypography.labelSmall.copyWith(
                              color: selected ? Colors.white : AppColors.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  if (stage.index <
                      YorksV1ProjectCreationStage.values.length - 1)
                    Expanded(
                      child: Divider(
                        color: completed
                            ? AppColors.blue
                            : AppColors.lineStrong,
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                (YorksMobileUi.isActive(context) &&
                            currentStage ==
                                YorksV1ProjectCreationStage.reviewAndCreate
                        ? _mobileReviewStageCopy(stage)
                        : _stageCopy(stage))
                    .primary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(
                  fontSize: 8,
                  color: selected ? AppColors.blue : AppColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageNavigationItem extends StatelessWidget {
  const _StageNavigationItem({
    required this.stage,
    required this.currentStage,
    required this.language,
    required this.onTap,
  });

  final YorksV1ProjectCreationStage stage;
  final YorksV1ProjectCreationStage currentStage;
  final AppLanguage language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = stage == currentStage;
    final copy = _stageCopy(stage);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? AppColors.blueContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          key: ValueKey('yorks-v1-project-stage-${stage.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.navy
                          : AppColors.neutralContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${stage.index + 1}',
                      style: AppTypography.labelLarge.copyWith(
                        color: selected ? AppColors.onPrimary : AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LocalizedCopy(
                      copy: copy,
                      language: language,
                      englishStyle: AppTypography.labelLarge.copyWith(
                        color: selected ? AppColors.navy : AppColors.ink,
                        fontSize: 10.5,
                      ),
                      secondaryStyle: AppTypography.labelSmall,
                    ),
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

class _DetailsStage extends StatelessWidget {
  const _DetailsStage({
    required this.formKey,
    required this.language,
    required this.referenceController,
    required this.nameController,
    required this.clientController,
    required this.jobOrContractController,
    required this.siteController,
    required this.notesController,
    required this.startDate,
    required this.endDate,
    required this.validationErrors,
    required this.onReferenceChanged,
    required this.onNameChanged,
    required this.onClientChanged,
    required this.onJobOrContractChanged,
    required this.onSiteChanged,
    required this.onNotesChanged,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
  });

  final GlobalKey<FormState> formKey;
  final AppLanguage language;
  final TextEditingController referenceController;
  final TextEditingController nameController;
  final TextEditingController clientController;
  final TextEditingController jobOrContractController;
  final TextEditingController siteController;
  final TextEditingController notesController;
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final ValueChanged<String> onReferenceChanged;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onClientChanged;
  final ValueChanged<String> onJobOrContractChanged;
  final ValueChanged<String> onSiteChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;

  @override
  Widget build(BuildContext context) {
    final required = YorksV1ProjectStrings.requiredField.primary;
    return Form(
      key: formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              MediaQuery.sizeOf(context).width > AppSpacing.compactBreakpoint;
          final fields = [
            LedgerTextField(
              key: const ValueKey('yorks-v1-project-reference'),
              controller: referenceController,
              label: YorksV1ProjectStrings.yorksReference.active(language),
              hintText: YorksV1ProjectStrings.yorksReferenceHint.active(
                language,
              ),
              helperText: YorksV1ProjectStrings.yorksReferenceHelp.active(
                language,
              ),
              onChanged: onReferenceChanged,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? required : null,
            ),
            LedgerTextField(
              key: const ValueKey('yorks-v1-project-name'),
              controller: nameController,
              label: YorksV1ProjectStrings.projectName.active(language),
              hintText: YorksV1ProjectStrings.projectNameHint.active(language),
              onChanged: onNameChanged,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? required : null,
            ),
            LedgerTextField(
              key: const ValueKey('yorks-v1-project-client'),
              controller: clientController,
              label: YorksV1ProjectStrings.client.active(language),
              hintText: YorksV1ProjectStrings.clientHint.active(language),
              onChanged: onClientChanged,
            ),
            LedgerTextField(
              key: const ValueKey('yorks-v1-project-job-contract'),
              controller: jobOrContractController,
              label: YorksV1ProjectStrings.jobOrContractReference.active(
                language,
              ),
              hintText: YorksV1ProjectStrings.jobOrContractReferenceHint.active(
                language,
              ),
              onChanged: onJobOrContractChanged,
            ),
            if (wide)
              // R38 places a commercial field in this cell. Engineers must
              // not receive that value, so preserve the visual row rhythm
              // without introducing a field or response-shape dependency.
              const SizedBox(height: 67),
            LedgerTextField(
              key: const ValueKey('yorks-v1-project-site'),
              controller: siteController,
              label: YorksV1ProjectStrings.siteLocation.active(language),
              hintText: YorksV1ProjectStrings.siteLocationHint.active(language),
              onChanged: onSiteChanged,
            ),
            _DateField(
              copy: YorksV1ProjectStrings.startDate,
              value: startDate,
              language: language,
              onTap: onSelectStartDate,
            ),
            _DateField(
              copy: YorksV1ProjectStrings.endDate,
              value: endDate,
              language: language,
              onTap: onSelectEndDate,
              error:
                  validationErrors.contains(
                    YorksV1ProjectValidationCode.invalidDateRange,
                  )
                  ? YorksV1ProjectStrings.endDateAfterStart.primary
                  : validationErrors.contains(
                      YorksV1ProjectValidationCode.unsupportedProjectDate,
                    )
                  ? YorksV1ProjectStrings.projectDateSupportedRange.primary
                  : null,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Wrap(
                  spacing: 15,
                  runSpacing: 15,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width: (constraints.maxWidth - 15) / 2,
                        child: field,
                      ),
                  ],
                )
              else
                ..._withGaps(fields),
              const SizedBox(height: AppSpacing.lg),
              LedgerTextField(
                key: const ValueKey('yorks-v1-project-notes'),
                controller: notesController,
                label: YorksV1ProjectStrings.notes.active(language),
                hintText: YorksV1ProjectStrings.notesHint.active(language),
                maxLines: 4,
                onChanged: onNotesChanged,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.copy,
    required this.value,
    required this.language,
    required this.onTap,
    this.error,
  });

  final TranslatableString copy;
  final DateTime? value;
  final AppLanguage language;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final selected = value == null ? null : DateUtils.dateOnly(value!);
    final parts = selected == null
        ? const ['DD', 'MM', 'YYYY']
        : [
            selected.day.toString().padLeft(2, '0'),
            selected.month.toString().padLeft(2, '0'),
            selected.year.toString().padLeft(4, '0'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LocalizedCopy(
          copy: copy,
          language: language,
          englishStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.inkSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
          secondaryStyle: AppTypography.labelSmall,
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: copy.primary,
          child: InkWell(
            key: ValueKey('yorks-v1-project-date-${copy.primary}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 300.0;
                final compact =
                    MediaQuery.sizeOf(context).width <
                    AppSpacing.compactBreakpoint;
                final controlHeight = compact ? AppSpacing.minTapTarget : 36.0;
                final gap = availableWidth < 360
                    ? AppSpacing.xs
                    : AppSpacing.sm;
                final boxWidth =
                    ((availableWidth - controlHeight - (gap * 3)) / 3)
                        .clamp(44.0, 74.0)
                        .toDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var index = 0; index < parts.length; index++)
                      SizedBox(
                        width: boxWidth,
                        height: controlHeight,
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(
                            horizontal: availableWidth < 360
                                ? AppSpacing.xs
                                : AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Text(
                            parts[index],
                            style: AppTypography.bodyMedium.copyWith(
                              color: selected == null
                                  ? AppColors.mutedLight
                                  : AppColors.ink,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: controlHeight,
                      height: controlHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          YorksV1ProjectStrings.dateFormatHelp.active(language),
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.muted,
            fontSize: 8.5,
            height: 1.25,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            error!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _PartiesAndAccessStage extends StatelessWidget {
  const _PartiesAndAccessStage({
    required this.draft,
    required this.language,
    required this.consultantController,
    required this.mainContractorController,
    required this.subcontractorController,
    required this.otherContractorController,
    required this.validationErrors,
    required this.creatorRole,
    required this.creatorAuthUserId,
    required this.teamDirectory,
    required this.onConsultantChanged,
    required this.onMainContractorChanged,
    required this.onAddSubcontractor,
    required this.onAddOtherContractor,
    required this.onRemoveParty,
    required this.onAddInitialMember,
    required this.onRemoveInitialMember,
    this.showTeam = true,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final TextEditingController consultantController;
  final TextEditingController mainContractorController;
  final TextEditingController subcontractorController;
  final TextEditingController otherContractorController;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final YorksV1Role creatorRole;
  final String creatorAuthUserId;
  final AsyncValue<List<YorksV1ProjectTeamDirectoryMember>> teamDirectory;
  final ValueChanged<String> onConsultantChanged;
  final ValueChanged<String> onMainContractorChanged;
  final VoidCallback onAddSubcontractor;
  final VoidCallback onAddOtherContractor;
  final ValueChanged<int> onRemoveParty;
  final void Function(
    YorksV1ProjectTeamDirectoryMember member,
    YorksV1ProjectMembershipRole projectRole,
  )
  onAddInitialMember;
  final ValueChanged<int> onRemoveInitialMember;
  final bool showTeam;

  @override
  Widget build(BuildContext context) {
    final subcontractors = <_IndexedParty>[
      for (var index = 0; index < draft.parties.length; index++)
        if (draft.parties[index].kind == YorksV1ProjectPartyKind.subcontractor)
          _IndexedParty(index, draft.parties[index]),
    ];
    final otherContractors = <_IndexedParty>[
      for (var index = 0; index < draft.parties.length; index++)
        if (draft.parties[index].kind ==
            YorksV1ProjectPartyKind.otherContractor)
          _IndexedParty(index, draft.parties[index]),
    ];
    final hasPartyError =
        validationErrors.contains(
          YorksV1ProjectValidationCode.invalidProjectParty,
        ) ||
        validationErrors.contains(
          YorksV1ProjectValidationCode.duplicateProjectParty,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusSectionCard(
          title: YorksV1ProjectStrings.partiesAndAccess.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 620;
                  final fields = [
                    LedgerTextField(
                      key: const ValueKey('yorks-v1-project-consultant'),
                      controller: consultantController,
                      label: YorksV1ProjectStrings.consultant.active(language),
                      hintText: YorksV1ProjectStrings.consultant.active(
                        language,
                      ),
                      onChanged: onConsultantChanged,
                    ),
                    LedgerTextField(
                      key: const ValueKey('yorks-v1-project-main-contractor'),
                      controller: mainContractorController,
                      label: YorksV1ProjectStrings.mainContractor.active(
                        language,
                      ),
                      hintText: YorksV1ProjectStrings.mainContractor.active(
                        language,
                      ),
                      onChanged: onMainContractorChanged,
                    ),
                  ];
                  if (!wide) return Column(children: _withGaps(fields));
                  return Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final field in fields)
                        SizedBox(
                          width: (constraints.maxWidth - AppSpacing.lg) / 2,
                          child: field,
                        ),
                    ],
                  );
                },
              ),
              if (hasPartyError) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  YorksV1ProjectStrings.stageNeedsAttention.primary,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _NamedPartyAdder(
                key: const ValueKey('yorks-v1-project-subcontractors'),
                label: YorksV1ProjectStrings.subcontractors,
                language: language,
                controller: subcontractorController,
                entries: subcontractors,
                onAdd: onAddSubcontractor,
                onRemove: onRemoveParty,
              ),
              const SizedBox(height: AppSpacing.lg),
              _NamedPartyAdder(
                key: const ValueKey('yorks-v1-project-other-contractors'),
                label: YorksV1ProjectStrings.otherContractors,
                language: language,
                controller: otherContractorController,
                entries: otherContractors,
                onAdd: onAddOtherContractor,
                onRemove: onRemoveParty,
              ),
            ],
          ),
        ),
        if (showTeam) ...[
          const SizedBox(height: AppSpacing.lg),
          NexusSectionCard(
            title: YorksV1ProjectStrings.projectTeam.primary,
            description: YorksV1ProjectStrings.accessDescription.primary,
            child: _InitialTeamAccessEditor(
              draft: draft,
              language: language,
              creatorRole: creatorRole,
              creatorAuthUserId: creatorAuthUserId,
              teamDirectory: teamDirectory,
              onAddMember: onAddInitialMember,
              onRemoveMember: onRemoveInitialMember,
            ),
          ),
        ],
      ],
    );
  }
}

class _InitialTeamAccessEditor extends StatelessWidget {
  const _InitialTeamAccessEditor({
    required this.draft,
    required this.language,
    required this.creatorRole,
    required this.creatorAuthUserId,
    required this.teamDirectory,
    required this.onAddMember,
    required this.onRemoveMember,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final YorksV1Role creatorRole;
  final String creatorAuthUserId;
  final AsyncValue<List<YorksV1ProjectTeamDirectoryMember>> teamDirectory;
  final void Function(
    YorksV1ProjectTeamDirectoryMember member,
    YorksV1ProjectMembershipRole projectRole,
  )
  onAddMember;
  final ValueChanged<int> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    return teamDirectory.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _LocalizedCopy(
              copy: YorksV1ProjectStrings.loadingTeamDirectory,
              language: language,
              englishStyle: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
      error: (_, _) => _TeamDirectoryUnavailable(
        draft: draft,
        language: language,
        onRemoveMember: onRemoveMember,
      ),
      data: (members) {
        final initialProjectEngineerCount = draft.initialMembers
            .where(
              (member) =>
                  member.projectRole ==
                  YorksV1ProjectMembershipRole.projectEngineer,
            )
            .length;
        final siteCreator = creatorRole == YorksV1Role.siteEngineer;
        final choices = members
            .where(
              (member) =>
                  member.authUserId != creatorAuthUserId &&
                  (!siteCreator ||
                      member.eligibleRole == YorksV1Role.projectEngineer),
            )
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InitialTeamResponsibilityBanner(
              language: language,
              siteCreator: siteCreator,
            ),
            const SizedBox(height: AppSpacing.lg),
            _InitialTeamCardPicker(
              choices: choices,
              initialMembers: draft.initialMembers,
              language: language,
              siteCreator: siteCreator,
              canAddProjectEngineer:
                  !siteCreator || initialProjectEngineerCount == 0,
              onAdd: onAddMember,
              onRemove: (authUserId) {
                final index = draft.initialMembers.indexWhere(
                  (member) => member.authUserId == authUserId,
                );
                if (index >= 0) onRemoveMember(index);
              },
            ),
            if (choices.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _LocalizedCopy(
                copy: YorksV1ProjectStrings.noEligibleTeamMembers,
                language: language,
                englishStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InitialTeamResponsibilityBanner extends StatelessWidget {
  const _InitialTeamResponsibilityBanner({
    required this.language,
    required this.siteCreator,
  });

  final AppLanguage language;
  final bool siteCreator;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.blueContainer.withValues(alpha: .48),
      border: Border.all(color: AppColors.blueContainerStrong),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LocalizedCopy(
          copy: YorksV1ProjectStrings.projectTeamPermissionRule,
          language: language,
          englishStyle: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _LocalizedCopy(
          copy: siteCreator
              ? YorksV1ProjectStrings.initialProjectEngineerHint
              : YorksV1ProjectStrings.projectTeamPermissionDescription,
          language: language,
          englishStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _InitialTeamCardPicker extends StatelessWidget {
  const _InitialTeamCardPicker({
    required this.choices,
    required this.initialMembers,
    required this.language,
    required this.siteCreator,
    required this.canAddProjectEngineer,
    required this.onAdd,
    required this.onRemove,
  });

  final List<YorksV1ProjectTeamDirectoryMember> choices;
  final List<YorksV1InitialProjectMemberInput> initialMembers;
  final AppLanguage language;
  final bool siteCreator;
  final bool canAddProjectEngineer;
  final void Function(
    YorksV1ProjectTeamDirectoryMember member,
    YorksV1ProjectMembershipRole projectRole,
  )
  onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth >= 940
          ? 3
          : constraints.maxWidth >= 600
          ? 2
          : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: count == 1 ? 3.8 : 2.8,
        ),
        itemCount: choices.length,
        itemBuilder: (context, index) {
          final member = choices[index];
          final existing = initialMembers
              .where((entry) => entry.authUserId == member.authUserId)
              .firstOrNull;
          final suggestedRole =
              member.eligibleRole == YorksV1Role.projectEngineer
              ? YorksV1ProjectMembershipRole.projectEngineer
              : YorksV1ProjectMembershipRole.siteEngineer;
          final enabled =
              existing != null ||
              !siteCreator ||
              (suggestedRole == YorksV1ProjectMembershipRole.projectEngineer &&
                  canAddProjectEngineer);
          return _InitialTeamCard(
            member: member,
            role: existing?.projectRole ?? suggestedRole,
            selected: existing != null,
            enabled: enabled,
            onPressed: () {
              if (existing != null) {
                onRemove(member.authUserId);
              } else if (enabled) {
                onAdd(member, suggestedRole);
              }
            },
          );
        },
      );
    },
  );
}

class _InitialTeamCard extends StatelessWidget {
  const _InitialTeamCard({
    required this.member,
    required this.role,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final YorksV1ProjectTeamDirectoryMember member;
  final YorksV1ProjectMembershipRole role;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    child: InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.line,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.surfaceContainerLow,
              foregroundColor: AppColors.navy,
              child: Text(_safeMemberDisplayName(member).substring(0, 1)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _safeMemberDisplayName(member),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    YorksV1ProjectStrings.roleLabel(role.wireValue).primary,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? AppColors.blue : AppColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _InitialTeamMemberChips extends StatelessWidget {
  const _InitialTeamMemberChips({
    required this.initialMembers,
    required this.memberByAuthUserId,
    required this.language,
    required this.onRemove,
  });

  final List<YorksV1InitialProjectMemberInput> initialMembers;
  final Map<String, YorksV1ProjectTeamDirectoryMember> memberByAuthUserId;
  final AppLanguage language;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (initialMembers.isEmpty) {
      return _LocalizedCopy(
        copy: YorksV1ProjectStrings.accessDescription,
        language: language,
        englishStyle: AppTypography.bodyMedium,
      );
    }
    final hasUnavailableMember = initialMembers.any(
      (member) => !memberByAuthUserId.containsKey(member.authUserId),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasUnavailableMember) ...[
          _LocalizedCopy(
            copy: YorksV1ProjectStrings.teamMemberNoLongerAvailable,
            language: language,
            englishStyle: AppTypography.bodySmall.copyWith(
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _LocalizedCopy(
            copy: YorksV1ProjectStrings.profileId,
            language: language,
            englishStyle: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var index = 0; index < initialMembers.length; index++)
              InputChip(
                label: Text(
                  _safeMemberDisplayName(
                    memberByAuthUserId[initialMembers[index].authUserId],
                  ),
                ),
                avatar: Icon(
                  initialMembers[index].projectRole ==
                          YorksV1ProjectMembershipRole.projectEngineer
                      ? Icons.engineering_outlined
                      : Icons.badge_outlined,
                  size: 18,
                ),
                onDeleted: onRemove == null ? null : () => onRemove!(index),
              ),
          ],
        ),
      ],
    );
  }
}

class _TeamDirectoryUnavailable extends StatelessWidget {
  const _TeamDirectoryUnavailable({
    required this.draft,
    required this.language,
    required this.onRemoveMember,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final ValueChanged<int> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LocalizedCopy(
          copy: YorksV1ProjectStrings.teamDirectoryUnavailable,
          language: language,
          englishStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.error,
          ),
        ),
        if (draft.initialMembers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InitialTeamMemberChips(
            initialMembers: draft.initialMembers,
            memberByAuthUserId: const {},
            language: language,
            onRemove: onRemoveMember,
          ),
        ],
      ],
    );
  }
}

class _NamedPartyAdder extends StatelessWidget {
  const _NamedPartyAdder({
    super.key,
    required this.label,
    required this.language,
    required this.controller,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });

  final TranslatableString label;
  final AppLanguage language;
  final TextEditingController controller;
  final List<_IndexedParty> entries;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LocalizedCopy(
          copy: label,
          language: language,
          englishStyle: AppTypography.titleSmall,
          secondaryStyle: AppTypography.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LedgerTextField(
                controller: controller,
                // The section heading above is the field label. Repeating it
                // here renders two stacked headings in the R35 desktop form.
                label: null,
                hintText: label.active(language),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: SecondaryButton(
                label: YorksV1ProjectStrings.add.primary,
                onPressed: onAdd,
                isExpanded: false,
                icon: Icons.add,
              ),
            ),
          ],
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in entries)
                InputChip(
                  label: Text(entry.party.name),
                  onDeleted: () => onRemove(entry.index),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BuildingsStage extends StatelessWidget {
  const _BuildingsStage({
    required this.draft,
    required this.language,
    required this.codeController,
    required this.nameController,
    required this.floorsController,
    required this.deliveryAddressController,
    required this.hasFrpRoom,
    required this.editingBuildingIndex,
    required this.validationErrors,
    required this.onHasFrpRoomChanged,
    required this.onAddBuilding,
    required this.onEditBuilding,
    required this.onCancelEditing,
    required this.onRemoveBuilding,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final TextEditingController floorsController;
  final TextEditingController deliveryAddressController;
  final bool hasFrpRoom;
  final int? editingBuildingIndex;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final ValueChanged<bool> onHasFrpRoomChanged;
  final VoidCallback onAddBuilding;
  final ValueChanged<int> onEditBuilding;
  final VoidCallback onCancelEditing;
  final ValueChanged<int> onRemoveBuilding;

  @override
  Widget build(BuildContext context) {
    final buildingError =
        validationErrors.contains(
          YorksV1ProjectValidationCode.missingBuilding,
        ) ||
        validationErrors.contains(
          YorksV1ProjectValidationCode.invalidBuilding,
        ) ||
        validationErrors.contains(
          YorksV1ProjectValidationCode.duplicateBuildingCode,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexusSectionCard(
          title: YorksV1ProjectStrings.buildings.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.blueContainerStrong),
                ),
                child: _LocalizedCopy(
                  copy: YorksV1ProjectStrings.buildingsIntro,
                  language: language,
                  englishStyle: AppTypography.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 620;
                  final fields = [
                    LedgerTextField(
                      key: const ValueKey('yorks-v1-building-code'),
                      controller: codeController,
                      label: YorksV1ProjectStrings.buildingCode.active(
                        language,
                      ),
                      hintText: YorksV1ProjectStrings.buildingCode.active(
                        language,
                      ),
                    ),
                    LedgerTextField(
                      key: const ValueKey('yorks-v1-building-name'),
                      controller: nameController,
                      label: YorksV1ProjectStrings.buildingName.active(
                        language,
                      ),
                      hintText: YorksV1ProjectStrings.buildingName.active(
                        language,
                      ),
                    ),
                  ];
                  if (!wide) return Column(children: _withGaps(fields));
                  return Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final field in fields)
                        SizedBox(
                          width: (constraints.maxWidth - AppSpacing.lg) / 2,
                          child: field,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              LedgerTextField(
                key: const ValueKey('yorks-v1-building-floors'),
                controller: floorsController,
                label: YorksV1ProjectStrings.floorsOrLevels.active(language),
                hintText: YorksV1ProjectStrings.floorsOrLevels.active(language),
              ),
              const SizedBox(height: AppSpacing.lg),
              LedgerTextField(
                key: const ValueKey('yorks-v1-building-delivery-address'),
                controller: deliveryAddressController,
                label: YorksV1ProjectStrings.deliveryAddress.active(language),
                hintText: YorksV1ProjectStrings.deliveryAddress.active(
                  language,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  value: hasFrpRoom,
                  onChanged: (value) => onHasFrpRoomChanged(value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: _LocalizedCopy(
                    copy: YorksV1ProjectStrings.hasFrpRoom,
                    language: language,
                    englishStyle: AppTypography.titleSmall,
                    secondaryStyle: AppTypography.labelSmall,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label:
                    (editingBuildingIndex == null
                            ? YorksV1ProjectStrings.addBuilding
                            : YorksV1ProjectStrings.updateBuilding)
                        .primary,
                onPressed: onAddBuilding,
                icon: editingBuildingIndex == null
                    ? Icons.add_business_outlined
                    : Icons.save_outlined,
              ),
              if (editingBuildingIndex != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onCancelEditing,
                    child: Text(
                      YorksV1ProjectStrings.cancelBuildingEdit.primary,
                    ),
                  ),
                ),
              ],
              if (buildingError) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  validationErrors.contains(
                        YorksV1ProjectValidationCode.duplicateBuildingCode,
                      )
                      ? YorksV1ProjectStrings.duplicateBuildingCode.primary
                      : YorksV1ProjectStrings.atLeastOneBuilding.primary,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NexusSectionCard(
          title: YorksV1ProjectStrings.buildings.primary,
          child: draft.buildings.isEmpty
              ? _LocalizedCopy(
                  copy: YorksV1ProjectStrings.noBuildingsAdded,
                  language: language,
                  englishStyle: AppTypography.bodyMedium,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < draft.buildings.length;
                      index++
                    ) ...[
                      _BuildingSummary(
                        building: draft.buildings[index],
                        language: language,
                        onEdit: () => onEditBuilding(index),
                        onRemove: () => onRemoveBuilding(index),
                      ),
                      if (index != draft.buildings.length - 1)
                        const Divider(height: AppSpacing.xxl),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _BuildingSummary extends StatelessWidget {
  const _BuildingSummary({
    required this.building,
    required this.language,
    required this.onEdit,
    required this.onRemove,
  });

  final YorksV1ProjectBuildingInput building;
  final AppLanguage language;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.apartment_outlined, color: AppColors.navy),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(building.name, style: AppTypography.titleMedium),
              if (building.code.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(building.normalizedCode, style: AppTypography.bodySmall),
              ],
              if (building.floorsOrLevels.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  building.floorsOrLevels.join(', '),
                  style: AppTypography.bodySmall,
                ),
              ],
              if (_emptyToNull(building.deliveryAddress) != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(building.deliveryAddress!, style: AppTypography.bodySmall),
              ],
            ],
          ),
        ),
        Column(
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: YorksV1ProjectStrings.editBuilding.primary,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: YorksV1ProjectStrings.remove.primary,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentsStage extends StatelessWidget {
  const _AttachmentsStage({
    required this.draft,
    required this.language,
    required this.validationErrors,
    required this.onAddAttachment,
    required this.onDroppedAttachments,
    required this.onDropError,
    required this.onRemoveAttachment,
    required this.pendingFiles,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final VoidCallback onAddAttachment;
  final Future<void> Function(List<YorksV1SelectedDocument>)
  onDroppedAttachments;
  final VoidCallback onDropError;
  final ValueChanged<int> onRemoveAttachment;
  final List<YorksV1SelectedDocument> pendingFiles;

  @override
  Widget build(BuildContext context) {
    return NexusSectionCard(
      title: YorksV1ProjectStrings.attachments.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocalizedCopy(
            copy: YorksV1ProjectStrings.attachmentsDropzoneDescription,
            language: language,
            englishStyle: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _ProjectAttachmentDropzone(
            language: language,
            onPick: onAddAttachment,
            onDropped: onDroppedAttachments,
            onDropError: onDropError,
          ),
          if (validationErrors.contains(
            YorksV1ProjectValidationCode.invalidAttachment,
          )) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              YorksV1ProjectStrings.invalidAttachment.primary,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (draft.attachments.isEmpty)
            Column(
              children: [
                Text(
                  YorksV1ProjectStrings.noAttachmentsAdded.primary,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1ProjectStrings.attachmentsDoNotBlock.primary,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
                ),
              ],
            )
          else
            Column(
              children: [
                for (
                  var index = 0;
                  index < draft.attachments.length;
                  index++
                ) ...[
                  _AttachmentSummary(
                    attachment: draft.attachments[index],
                    pendingFile: _pendingFileFor(
                      draft.attachments[index],
                      pendingFiles,
                    ),
                    onRemove: () => onRemoveAttachment(index),
                  ),
                  if (index != draft.attachments.length - 1)
                    const Divider(height: AppSpacing.xxl),
                ],
              ],
            ),
        ],
      ),
    );
  }

  YorksV1SelectedDocument? _pendingFileFor(
    YorksV1ProjectAttachmentInput attachment,
    List<YorksV1SelectedDocument> files,
  ) {
    for (final file in files) {
      if (file.fileName == attachment.fileName) return file;
    }
    return null;
  }
}

/// Uses the native picker everywhere and adds a browser drop target only on
/// web. Both paths produce the same checked in-memory file representation.
class _ProjectAttachmentDropzone extends StatefulWidget {
  const _ProjectAttachmentDropzone({
    required this.language,
    required this.onPick,
    required this.onDropped,
    required this.onDropError,
  });

  final AppLanguage language;
  final VoidCallback onPick;
  final Future<void> Function(List<YorksV1SelectedDocument>) onDropped;
  final VoidCallback onDropError;

  @override
  State<_ProjectAttachmentDropzone> createState() =>
      _ProjectAttachmentDropzoneState();
}

class _ProjectAttachmentDropzoneState
    extends State<_ProjectAttachmentDropzone> {
  DropzoneViewController? _dropzoneController;
  bool _dragging = false;

  static const _acceptedMimeTypes = <String>[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/jpeg',
    'image/png',
  ];

  Future<void> _handleDroppedFiles(
    List<DropzoneFileInterface>? droppedFiles,
  ) async {
    final controller = _dropzoneController;
    if (controller == null || droppedFiles == null || droppedFiles.isEmpty) {
      return;
    }
    if (mounted) setState(() => _dragging = false);
    final selectedFiles = <YorksV1SelectedDocument>[];
    var hasInvalidFile = false;
    for (final file in droppedFiles) {
      try {
        final name = await controller.getFilename(file);
        final bytes = await controller.getFileData(file);
        selectedFiles.add(
          YorksV1SelectedDocument.checked(fileName: name, bytes: bytes),
        );
      } on YorksV1DomainException {
        hasInvalidFile = true;
      } catch (_) {
        hasInvalidFile = true;
      }
    }
    if (selectedFiles.isNotEmpty) {
      await widget.onDropped(selectedFiles);
    }
    if (hasInvalidFile) widget.onDropError();
  }

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      button: true,
      label: YorksV1ProjectStrings.attachmentsDropzoneTitle.primary,
      child: InkWell(
        key: const ValueKey('yorks-v1-attachment-dropzone'),
        onTap: widget.onPick,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: CustomPaint(
          painter: _DashedAttachmentBorderPainter(
            color: (_dragging ? AppColors.navy : AppColors.blue).withValues(
              alpha: _dragging ? 0.9 : 0.55,
            ),
            radius: AppSpacing.radiusMd,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _dragging
                  ? AppColors.blue.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxxl,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.file_upload_outlined,
                  size: 30,
                  color: AppColors.muted,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _dragging
                      ? YorksV1ProjectStrings.attachmentsDropzoneActive.primary
                      : YorksV1ProjectStrings.attachmentsDropzoneTitle.primary,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: _LocalizedCopy(
                    copy: YorksV1ProjectStrings.attachmentsDropzonePrompt,
                    language: widget.language,
                    englishStyle: AppTypography.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: widget.onPick,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(YorksV1ProjectStrings.addAttachment.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!kIsWeb) return content;
    return Stack(
      children: [
        Positioned.fill(
          child: DropzoneView(
            mime: _acceptedMimeTypes,
            operation: DragOperation.copy,
            cursor: CursorType.grab,
            onCreated: (controller) => _dropzoneController = controller,
            onHover: () {
              if (mounted) setState(() => _dragging = true);
            },
            onLeave: () {
              if (mounted) setState(() => _dragging = false);
            },
            onDropInvalid: (_) => widget.onDropError(),
            onDropFiles: (files) {
              unawaited(_handleDroppedFiles(files));
            },
          ),
        ),
        content,
      ],
    );
  }
}

class _AttachmentSummary extends StatelessWidget {
  const _AttachmentSummary({
    required this.attachment,
    required this.pendingFile,
    required this.onRemove,
  });

  final YorksV1ProjectAttachmentInput attachment;
  final YorksV1SelectedDocument? pendingFile;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.description_outlined, color: AppColors.navy),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.fileName, style: AppTypography.titleMedium),
              if (attachment.mimeType?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    attachment.mimeType!,
                    if (attachment.sizeBytes != null)
                      _formatAttachmentSize(attachment.sizeBytes!),
                    if (pendingFile != null)
                      YorksV1ProjectStrings.attachmentReady.primary
                    else
                      YorksV1ProjectStrings.attachmentNeedsReselect.primary,
                  ].join(' · '),
                  style: AppTypography.bodySmall.copyWith(
                    color: pendingFile == null ? AppColors.warning : null,
                  ),
                ),
              ] else
                Text(
                  pendingFile == null
                      ? YorksV1ProjectStrings.attachmentNeedsReselect.primary
                      : YorksV1ProjectStrings.attachmentReady.primary,
                  style: AppTypography.bodySmall.copyWith(
                    color: pendingFile == null ? AppColors.warning : null,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRemove,
          tooltip: YorksV1ProjectStrings.remove.primary,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

String _formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DashedAttachmentBorderPainter extends CustomPainter {
  _DashedAttachmentBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 7).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedAttachmentBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _ReviewStage extends StatelessWidget {
  const _ReviewStage({
    required this.draft,
    required this.language,
    required this.validationErrors,
    required this.teamDirectory,
    required this.onRetryDirectory,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final AsyncValue<List<YorksV1ProjectTeamDirectoryMember>> teamDirectory;
  final VoidCallback onRetryDirectory;

  @override
  Widget build(BuildContext context) {
    final loadedDirectory = teamDirectory.asData?.value;
    final directory = loadedDirectory ?? const [];
    final memberByAuthUserId = {
      for (final member in directory) member.authUserId: member,
    };
    final hasUnavailableMember =
        loadedDirectory != null &&
        _hasUnavailableInitialMember(draft, loadedDirectory);
    final notProvided = YorksV1ProjectStrings.notProvided.active(language);
    String namesForRole(YorksV1ProjectMembershipRole role) {
      final names = [
        for (final initialMember in draft.initialMembers)
          if (initialMember.projectRole == role)
            _safeMemberDisplayName(
              memberByAuthUserId[initialMember.authUserId],
            ),
      ];
      return names.isEmpty ? notProvided : names.join(', ');
    }

    String namesForParty(YorksV1ProjectPartyKind kind) {
      final names = [
        for (final party in draft.parties)
          if (party.kind == kind) party.name.trim(),
      ].where((name) => name.isNotEmpty).toList(growable: false);
      return names.isEmpty ? notProvided : names.join(', ');
    }

    String buildingSummary() {
      if (draft.buildings.isEmpty) return notProvided;
      return draft.buildings
          .map((building) => '${building.code} · ${building.name}')
          .join('\n');
    }

    String attachmentSummary() {
      if (draft.attachments.isEmpty) return notProvided;
      final names = draft.attachments.map((attachment) => attachment.fileName);
      return '${draft.attachments.length} · ${names.join(', ')}';
    }

    final start = draft.startDate == null
        ? notProvided
        : MaterialLocalizations.of(context).formatMediumDate(draft.startDate!);
    final end = draft.endDate == null
        ? notProvided
        : MaterialLocalizations.of(context).formatMediumDate(draft.endDate!);

    if (YorksMobileUi.isActive(context)) {
      final inputErrors = draft.toCreationInput().validate();
      final directoryLoaded = teamDirectory.asData != null;
      return _MobileReviewStage(
        draft: draft,
        language: language,
        ready:
            directoryLoaded &&
            !hasUnavailableMember &&
            inputErrors.isEmpty &&
            validationErrors.isEmpty,
        directoryLoading: teamDirectory.isLoading,
        directoryFailed: teamDirectory.hasError,
        hasUnavailableMember: hasUnavailableMember,
        showValidation: inputErrors.isNotEmpty || validationErrors.isNotEmpty,
        onRetryDirectory: onRetryDirectory,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.successContainer,
            border: Border.all(color: AppColors.success.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      YorksV1ProjectStrings.readyToCreateWorkspace.primary,
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onSuccessContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      YorksV1ProjectStrings
                          .materialsNotRequiredAtCreation
                          .primary,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onSuccessContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasUnavailableMember) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              border: Border.all(color: AppColors.error.withValues(alpha: .2)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LocalizedCopy(
                  copy: YorksV1ProjectStrings.teamMemberNoLongerAvailable,
                  language: language,
                  englishStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _LocalizedCopy(
                  copy: YorksV1ProjectStrings.profileId,
                  language: language,
                  englishStyle: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            final cards = [
              _ReviewSummaryCard(
                language: language,
                title: YorksV1ProjectStrings.projects.active(language),
                rows: [
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.yorksReference.active(
                      language,
                    ),
                    value: draft.reference,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.projectName.active(language),
                    value: draft.name,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.client.active(language),
                    value: _emptyToNull(draft.clientName) ?? notProvided,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.jobOrContractReference.active(
                      language,
                    ),
                    value:
                        _emptyToNull(draft.jobOrContractReference) ??
                        notProvided,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.siteLocation.active(language),
                    value: _emptyToNull(draft.siteLocation) ?? notProvided,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.startDate.active(language),
                    value: start,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.endDate.active(language),
                    value: end,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.notes.active(language),
                    value: _emptyToNull(draft.notes) ?? notProvided,
                  ),
                ],
              ),
              _ReviewSummaryCard(
                language: language,
                title: YorksV1ProjectStrings.accessAndBuildings.active(
                  language,
                ),
                rows: [
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.consultant.active(language),
                    value:
                        _emptyToNull(
                          _partyFor(
                            draft,
                            YorksV1ProjectPartyKind.consultant,
                          )?.name,
                        ) ??
                        notProvided,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.mainContractor.active(
                      language,
                    ),
                    value:
                        _emptyToNull(
                          _partyFor(
                            draft,
                            YorksV1ProjectPartyKind.mainContractor,
                          )?.name,
                        ) ??
                        notProvided,
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.subcontractors.active(
                      language,
                    ),
                    value: namesForParty(YorksV1ProjectPartyKind.subcontractor),
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.otherContractors.active(
                      language,
                    ),
                    value: namesForParty(
                      YorksV1ProjectPartyKind.otherContractor,
                    ),
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.projectEngineers.active(
                      language,
                    ),
                    value: namesForRole(
                      YorksV1ProjectMembershipRole.projectEngineer,
                    ),
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.siteEngineers.active(language),
                    value: namesForRole(
                      YorksV1ProjectMembershipRole.siteEngineer,
                    ),
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.buildings.active(language),
                    value: buildingSummary(),
                  ),
                  _ReviewSummaryRow(
                    label: YorksV1ProjectStrings.attachments.active(language),
                    value: attachmentSummary(),
                  ),
                ],
              ),
            ];
            if (!wide) return Column(children: _withGaps(cards));
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        if (validationErrors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _ValidationBanner(language: language),
        ],
      ],
    );
  }
}

class _MobileReviewStage extends StatelessWidget {
  const _MobileReviewStage({
    required this.draft,
    required this.language,
    required this.ready,
    required this.directoryLoading,
    required this.directoryFailed,
    required this.hasUnavailableMember,
    required this.showValidation,
    required this.onRetryDirectory,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final bool ready;
  final bool directoryLoading;
  final bool directoryFailed;
  final bool hasUnavailableMember;
  final bool showValidation;
  final VoidCallback onRetryDirectory;

  @override
  Widget build(BuildContext context) {
    final projectEngineers = draft.initialMembers
        .where(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        )
        .length;
    final siteEngineers = draft.initialMembers
        .where(
          (member) =>
              member.projectRole == YorksV1ProjectMembershipRole.siteEngineer,
        )
        .length;
    final notProvided = YorksV1ProjectStrings.notProvided.active(language);
    final metrics = <_MobileReviewMetric>[
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.client.active(language),
        value: _emptyToNull(draft.clientName) ?? notProvided,
      ),
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.siteLocation.active(language),
        value: _emptyToNull(draft.siteLocation) ?? notProvided,
      ),
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.projectEngineers.active(language),
        value: '$projectEngineers',
      ),
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.siteEngineers.active(language),
        value: '$siteEngineers',
      ),
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.buildings.active(language),
        value: '${draft.buildings.length}',
      ),
      _MobileReviewMetric(
        label: YorksV1ProjectStrings.attachments.active(language),
        value: '${draft.attachments.length}',
      ),
    ];
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: draft.reference.trim().isEmpty
                                  ? notProvided
                                  : draft.reference.trim(),
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            TextSpan(
                              text: draft.name.trim().isEmpty
                                  ? ''
                                  : '  ${draft.name.trim()}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (directoryLoading)
                      const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      _MobileReviewStatus(ready: ready),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: metrics.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: _mobileReviewMetricExtent(context),
                  ),
                  itemBuilder: (context, index) {
                    final metric = metrics[index];
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              metric.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.muted,
                                fontSize: 9,
                              ),
                            ),
                            Text(
                              metric.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (ready)
            _MobileReviewCallout(
              title: YorksV1ProjectStrings.whatHappensNext,
              description: YorksV1ProjectStrings.creationScopeOutcome,
              language: language,
              success: true,
            )
          else if (hasUnavailableMember)
            _MobileReviewCallout(
              title: YorksV1ProjectStrings.stageNeedsAttention,
              description: YorksV1ProjectStrings.teamMemberNoLongerAvailable,
              language: language,
            )
          else if (directoryFailed)
            _MobileReviewCallout(
              title: YorksV1ProjectStrings.stageNeedsAttention,
              description: YorksV1ProjectStrings.teamDirectoryUnavailable,
              language: language,
              actionLabel: YorksV1ProjectStrings.retry,
              onAction: onRetryDirectory,
            )
          else if (showValidation)
            _ValidationBanner(language: language),
        ],
      ),
    );
  }
}

class _MobileReviewMetric {
  const _MobileReviewMetric({required this.label, required this.value});

  final String label;
  final String value;
}

double _mobileReviewMetricExtent(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final labelHeight = scaler.scale(9) * 1.2;
  final valueHeight =
      scaler.scale(AppTypography.labelLarge.fontSize ?? 14) * 1.2;
  // Keep additional leading beyond the explicit cell padding because Flutter's
  // nonlinear text scaler may allocate more glyph/strut height than a scaled
  // font-size estimate at accessibility sizes.
  final requiredHeight = 20 + labelHeight + valueHeight;
  return requiredHeight < 42 ? 42 : requiredHeight;
}

class _MobileReviewStatus extends StatelessWidget {
  const _MobileReviewStatus({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: ready ? AppColors.successContainer : AppColors.warningContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
    ),
    child: Text(
      (ready
              ? YorksV1ProjectStrings.ready
              : YorksV1ProjectStrings.stageNeedsAttention)
          .primary,
      style: AppTypography.labelSmall.copyWith(
        color: ready
            ? AppColors.onSuccessContainer
            : AppColors.onWarningContainer,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MobileReviewCallout extends StatelessWidget {
  const _MobileReviewCallout({
    required this.title,
    required this.description,
    required this.language,
    this.success = false,
    this.actionLabel,
    this.onAction,
  });

  final TranslatableString title;
  final TranslatableString description;
  final AppLanguage language;
  final bool success;
  final TranslatableString? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: success
          ? AppColors.successContainer.withValues(alpha: .55)
          : AppColors.errorContainer,
      border: Border.all(
        color: success
            ? AppColors.success.withValues(alpha: .22)
            : AppColors.error.withValues(alpha: .22),
      ),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(
            color: success
                ? AppColors.successContainer
                : AppColors.errorContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            success ? Icons.check_rounded : Icons.error_outline_rounded,
            color: success ? AppColors.success : AppColors.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LocalizedCopy(
                copy: title,
                language: language,
                englishStyle: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              _LocalizedCopy(
                copy: description,
                language: language,
                englishStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: AppSpacing.minTapTarget,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onAction,
                      child: Text(actionLabel!.active(language)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReviewSummaryRow {
  const _ReviewSummaryRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({
    required this.language,
    required this.title,
    required this.rows,
  });

  final AppLanguage language;
  final String title;
  final List<_ReviewSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final labelWidth = MediaQuery.sizeOf(context).width >= 680 ? 152.0 : 116.0;
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const Divider(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(
                      rows[index].label,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      rows[index].value,
                      textAlign: TextAlign.start,
                      style: AppTypography.labelLarge,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: _LocalizedCopy(
        copy: YorksV1ProjectStrings.stageNeedsAttention,
        language: language,
        englishStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.onErrorContainer,
        ),
      ),
    );
  }
}

class _StageActions extends StatelessWidget {
  const _StageActions({
    required this.stage,
    required this.language,
    required this.saving,
    required this.onBack,
    required this.onContinue,
    required this.onSkip,
    required this.onCreate,
    required this.primaryLabel,
  });

  final YorksV1ProjectCreationStage stage;
  final AppLanguage language;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback? onCreate;
  final TranslatableString primaryLabel;

  @override
  Widget build(BuildContext context) {
    final isReview = stage == YorksV1ProjectCreationStage.reviewAndCreate;
    final isAttachments = stage == YorksV1ProjectCreationStage.attachments;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth <= AppSpacing.compactBreakpoint;
        final back = SecondaryButton(
          label: YorksV1ProjectStrings.back.primary,
          onPressed: saving ? null : onBack,
          icon: Icons.arrow_back,
          isExpanded: stacked,
        );
        final primary = PrimaryButton(
          key: ValueKey('yorks-v1-project-${isReview ? 'create' : 'continue'}'),
          label: isReview
              ? primaryLabel.primary
              : YorksV1ProjectStrings.next.primary,
          onPressed: saving ? null : (isReview ? onCreate : onContinue),
          icon: isReview ? Icons.add_business_outlined : Icons.arrow_forward,
          isTrailingIcon: true,
          isLoading: saving,
          isExpanded: stacked,
        );
        final skip = SecondaryButton(
          label: YorksV1ProjectStrings.skipForNow.primary,
          onPressed: saving ? null : onSkip,
          isExpanded: stacked,
        );
        if (stage == YorksV1ProjectCreationStage.projectDetails) {
          return stacked
              ? primary
              : Align(alignment: Alignment.centerRight, child: primary);
        }
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isAttachments) ...[
                Align(alignment: Alignment.centerRight, child: skip),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(child: back),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: primary),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            back,
            const Spacer(),
            if (isAttachments) ...[skip, const SizedBox(width: AppSpacing.sm)],
            primary,
          ],
        );
      },
    );
  }
}

class _LocalizedCopy extends StatelessWidget {
  const _LocalizedCopy({
    required this.copy,
    required this.language,
    this.englishStyle,
    this.secondaryStyle,
  });

  final TranslatableString copy;
  final AppLanguage language;
  final TextStyle? englishStyle;
  final TextStyle? secondaryStyle;

  @override
  Widget build(BuildContext context) {
    return YorksV1ActiveText(
      copy: copy,
      language: language,
      style: englishStyle ?? secondaryStyle,
    );
  }
}

class _IndexedParty {
  const _IndexedParty(this.index, this.party);

  final int index;
  final YorksV1ProjectPartyInput party;
}

YorksV1ProjectPartyInput? _partyFor(
  YorksV1ProjectCreationDraft draft,
  YorksV1ProjectPartyKind kind,
) {
  for (final party in draft.parties) {
    if (party.kind == kind) return party;
  }
  return null;
}

TranslatableString _stageCopy(YorksV1ProjectCreationStage stage) {
  return switch (stage) {
    YorksV1ProjectCreationStage.projectDetails =>
      YorksV1ProjectStrings.projectDetails,
    YorksV1ProjectCreationStage.partiesAndAccess =>
      YorksV1ProjectStrings.partiesAndAccess,
    YorksV1ProjectCreationStage.buildings => YorksV1ProjectStrings.buildings,
    YorksV1ProjectCreationStage.attachments =>
      YorksV1ProjectStrings.attachments,
    YorksV1ProjectCreationStage.reviewAndCreate =>
      YorksV1ProjectStrings.reviewAndCreate,
  };
}

TranslatableString _mobileReviewStageCopy(YorksV1ProjectCreationStage stage) {
  return switch (stage) {
    YorksV1ProjectCreationStage.projectDetails =>
      YorksV1ProjectStrings.detailsStep,
    YorksV1ProjectCreationStage.partiesAndAccess =>
      YorksV1ProjectStrings.accessStep,
    YorksV1ProjectCreationStage.buildings => YorksV1ProjectStrings.buildings,
    YorksV1ProjectCreationStage.attachments => YorksV1ProjectStrings.filesStep,
    YorksV1ProjectCreationStage.reviewAndCreate =>
      YorksV1ProjectStrings.reviewStep,
  };
}

TranslatableString _stageDescription(YorksV1ProjectCreationStage stage) {
  return switch (stage) {
    YorksV1ProjectCreationStage.projectDetails =>
      YorksV1ProjectStrings.createProjectDescription,
    YorksV1ProjectCreationStage.partiesAndAccess =>
      YorksV1ProjectStrings.accessDescription,
    YorksV1ProjectCreationStage.buildings =>
      YorksV1ProjectStrings.buildingsIntro,
    YorksV1ProjectCreationStage.attachments =>
      YorksV1ProjectStrings.attachmentsDropzoneDescription,
    YorksV1ProjectCreationStage.reviewAndCreate =>
      YorksV1ProjectStrings.reviewBeforeCreate,
  };
}

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

DateTime _clampDate(DateTime value, DateTime minimum, DateTime maximum) {
  final date = DateUtils.dateOnly(value);
  if (date.isBefore(minimum)) return minimum;
  if (date.isAfter(maximum)) return maximum;
  return date;
}

bool _hasUnavailableInitialMember(
  YorksV1ProjectCreationDraft draft,
  List<YorksV1ProjectTeamDirectoryMember> directory,
) {
  final activeAuthUserIds = {for (final member in directory) member.authUserId};
  return draft.initialMembers.any(
    (member) => !activeAuthUserIds.contains(member.authUserId),
  );
}

String _safeMemberDisplayName(YorksV1ProjectTeamDirectoryMember? member) {
  if (member == null ||
      member.displayName.trim().isEmpty ||
      member.displayName.trim() == member.authUserId.trim() ||
      YorksV1ProjectTeamDirectoryMember.isEmailLikeDisplayName(
        member.displayName,
      )) {
    return YorksV1ProjectStrings.profileId.primary;
  }
  return member.displayName;
}

List<Widget> _withGaps(List<Widget> children) {
  return [
    for (var index = 0; index < children.length; index++) ...[
      children[index],
      if (index != children.length - 1) const SizedBox(height: AppSpacing.lg),
    ],
  ];
}
