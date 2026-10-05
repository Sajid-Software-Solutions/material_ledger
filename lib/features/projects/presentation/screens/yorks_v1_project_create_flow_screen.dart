import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/router.dart';
import '../../../../app/yorks_navigation_history.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/controllers/yorks_v1_project_controller.dart';
import '../../../../shared/controllers/yorks_v1_project_setup_coordinator.dart';
import '../../../../shared/controllers/yorks_v1_project_creation_draft_controller.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/analytics_event.dart';
import '../../../../shared/services/analytics_service.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_setup_operation.dart';
import '../../../../shared/models/yorks_v1_project_portfolio.dart';
import '../../../../shared/models/yorks_v1_project_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_project_setup_desktop_strings.dart';
import '../../../../shared/models/yorks_v1_project_team_directory_member.dart';
import '../../../../shared/models/yorks_v1_permission_management.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_project_controller_provider.dart';
import '../../../../shared/providers/yorks_v1_project_setup_coordinator_provider.dart';
import '../../../../shared/providers/yorks_v1_project_setup_navigation_provider.dart';
import '../../../../shared/providers/yorks_v1_project_reference_advisory_provider.dart';
import '../../../../shared/providers/yorks_v1_project_creation_draft_provider.dart';
import '../../../../shared/providers/yorks_v1_project_team_directory_provider.dart';
import '../../../../shared/providers/yorks_v1_project_portfolio_provider.dart';
import '../../../../shared/providers/yorks_v1_permission_provider.dart';
import '../../../../shared/services/yorks_v1_document_file_service.dart';
import '../../../materials/presentation/yorks_v1_feature_action_access.dart';
import 'yorks_v1_project_setup_desktop_theme.dart';
import 'yorks_v1_project_setup_desktop_shell.dart';
import 'yorks_v1_project_setup_mobile_shell.dart';
import 'yorks_v1_project_setup_mobile_theme.dart';
import '../../../../shared/models/yorks_v1_project_setup_mobile_strings.dart';
import '../../../../shared/models/yorks_v1_project_setup_shell_strings.dart';
import '../widgets/yorks_v1_project_setup_pending_recovery.dart';
import '../widgets/yorks_v1_project_setup_attachment_preview.dart';

part 'yorks_v1_project_setup_desktop_stages.dart';
part 'yorks_v1_project_setup_mobile_stages.dart';

/// The normalized Yorks V1 R35 project creation experience.
///
/// This screen intentionally owns only recoverable local draft input and
/// delegates the committed create command to [YorksV1ProjectCommandController].
/// It never writes projects, scopes, memberships or BOQ groups locally.
class YorksV1ProjectCreateFlowScreen extends ConsumerStatefulWidget {
  const YorksV1ProjectCreateFlowScreen({
    super.key,
    this.onProjectCreated,
    this.editItem,
    this.onProjectUpdated,
    this.resumeDraftId,
    this.newDraftId,
    this.legacyRecovery = false,
  }) : assert(resumeDraftId == null || newDraftId == null),
       assert(!legacyRecovery || (resumeDraftId == null && newDraftId == null));

  /// Explicit selection from Projects or an anchored setup URL. Missing and
  /// unsupported selections stay guarded instead of resuming another draft.
  final String? resumeDraftId;

  /// Optional deterministic fresh ID for a composed entry/test fixture. Normal
  /// Create navigation lets this mounted screen generate its own new ID.
  final String? newDraftId;
  final bool legacyRecovery;

  /// Lets route composition move to the authoritative project workspace after
  /// the server has committed the project. It is deliberately called only
  /// after its confirmed receipt and local draft retirement are durable.
  final ValueChanged<YorksV1Project>? onProjectCreated;

  /// Supplying an authorized portfolio item changes this five-stage surface
  /// into an edit flow. The server is still the authority for every update.
  final YorksV1ProjectPortfolioItem? editItem;
  final ValueChanged<YorksV1Project>? onProjectUpdated;

  bool get isEditing => editItem != null;

  @override
  ConsumerState<YorksV1ProjectCreateFlowScreen> createState() =>
      _YorksV1ProjectCreateFlowScreenState();
}

/// Resolves the current authorized project projection before presenting the
/// same five-stage R35 setup form in update mode.
class YorksV1ProjectEditFlowScreen extends ConsumerWidget {
  const YorksV1ProjectEditFlowScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(yorksV1ProjectPortfolioProvider);
    return portfolio.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  YorksV1ProjectStrings.errorFor(
                    YorksV1DomainErrorCode.backendUnavailable,
                  ).active(ref.watch(languageProvider)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(yorksV1ProjectPortfolioProvider),
                  child: Text(
                    YorksV1ProjectStrings.retry.active(
                      ref.watch(languageProvider),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
        return YorksV1ProjectCreateFlowScreen(
          editItem: item.first,
          onProjectUpdated: (_) =>
              context.go(RoutePaths.yorksV1ProjectPath(projectId)),
        );
      },
    );
  }
}

class _YorksV1ProjectCreateFlowScreenState
    extends ConsumerState<YorksV1ProjectCreateFlowScreen>
    with WidgetsBindingObserver {
  var _detailsFormKey = GlobalKey<FormState>();
  final _featureScaffoldKey = GlobalKey<ScaffoldState>();
  final _featureMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _scrollController = ScrollController();
  final _fieldFocusNodes = {
    for (final name in [
      'reference',
      'name',
      'client',
      'contract',
      'site',
      'notes',
      'contactName',
      'contactPhone',
      'contactEmail',
      'contactAddress',
      'startDate',
      'endDate',
      'consultant',
      'mainContractor',
      'subcontractor',
      'otherContractor',
      'buildingCode',
      'buildingName',
      'buildingFloors',
      'buildingAddress',
    ])
      name: FocusNode(debugLabel: 'project-setup-$name'),
  };

  final _referenceController = TextEditingController();
  final _nameController = TextEditingController();
  final _clientController = TextEditingController();
  final _jobOrContractController = TextEditingController();
  final _siteController = TextEditingController();
  final _notesController = TextEditingController();
  final _clientContactNameController = TextEditingController();
  final _clientContactPhoneController = TextEditingController();
  final _clientContactEmailController = TextEditingController();
  final _clientAddressController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _consultantController = TextEditingController();
  final _mainContractorController = TextEditingController();
  final _subcontractorController = TextEditingController();
  final _otherContractorController = TextEditingController();
  final _buildingCodeController = TextEditingController();
  final _buildingNameController = TextEditingController();
  final _buildingFloorsController = TextEditingController();
  final _buildingDeliveryAddressController = TextEditingController();

  YorksV1ProjectSetupOperation? _completedOperation;
  bool _releasingConfirmedHistory = false;
  bool _confirmedHistoryReleaseFailed = false;

  bool _synchronizingEditor = false;
  bool _restoredEditor = false;
  bool _editInitialized = false;
  bool _editReady = false;
  Future<void>? _editSeedInitialization;
  bool _resumeEntryStarted = false;
  bool _resumeEntryReady = false;
  bool _resumeEntryBusy = false;
  bool _resumeEntryFailed = false;
  String? _resumeExpectedDraftId;
  final _visitedStages = <YorksV1ProjectCreationStage>{
    YorksV1ProjectCreationStage.projectDetails,
  };
  YorksV1ProjectBuildingInput? _removedBuilding;
  int? _removedBuildingIndex;
  List<YorksV1ProjectBuildingInput>? _buildingUndoRows;
  YorksV1ProjectPartyInput? _removedParty;
  int? _removedPartyIndex;
  YorksV1ProjectCreationStage? _renderedStage;
  YorksV1ProjectCreationStage? _restoredNavigationStage;
  String? _lastFocusedField;
  bool _restoringNavigation = false;
  int? _leaveAuthorizedGeneration;
  String? _manuallySavedInput;
  bool _manualSavePending = false;
  Future<bool?>? _leaveDecision;
  bool _confirmedContextResult = false;
  bool _disposed = false;
  YorksV1ProjectCreationDraftController? _liveDraftController;
  late final YorksV1ProjectSetupNavigationGuard _navigationService;
  Timer? _draftSaveTimer;
  YorksV1ProjectCreationDraft? _pendingDraft;
  YorksV1ProjectCreationDraft? _editDraft;
  String? _activeAuthUserId;
  String? _activeEditProjectId;
  String? _activeCreationDraftId;
  String? _activeBackendIdentity;
  bool _activeLegacyRecovery = false;
  late String _freshDraftId;
  YorksV1ProjectCreationDraftContext? _selectedCreationContext;
  bool _draftUrlAnchorQueued = false;
  Set<YorksV1ProjectValidationCode> _validationErrors = const {};
  bool _hasFrpRoom = false;
  int? _editingBuildingIndex;
  bool _isCreating = false;
  int _contextGeneration = 0;
  bool _checkingOwnership = false;
  bool _ownershipCheckFailed = false;
  late final Future<bool> Function() _navigationGuard = _prepareLeave;
  List<YorksV1SelectedDocument> _selectedAttachmentFiles = const [];

  List<TextEditingController> get _controllers => [
    _referenceController,
    _nameController,
    _clientController,
    _jobOrContractController,
    _siteController,
    _notesController,
    _clientContactNameController,
    _clientContactPhoneController,
    _clientContactEmailController,
    _clientAddressController,
    _startDateController,
    _endDateController,
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

  bool _isCurrentContext(int generation) =>
      !_disposed &&
      mounted &&
      generation == _contextGeneration &&
      ref.read(yorksV1AuthUserIdProvider) == _activeAuthUserId &&
      widget.editItem?.project.id == _activeEditProjectId &&
      ref.read(yorksV1ProjectDraftBackendIdentityProvider) ==
          _activeBackendIdentity &&
      _activeLegacyRecovery == widget.legacyRecovery &&
      (_isEditing || _effectiveCreationDraftId == _activeCreationDraftId);

  String get _effectiveCreationDraftId => widget.legacyRecovery
      ? 'legacy-recovery'
      : widget.resumeDraftId ?? _freshDraftId;

  YorksV1ProjectCreationDraftContext _creationContext(String owner) {
    final selected = _selectedCreationContext;
    if (selected != null &&
        selected.ownerAuthUserId == owner &&
        selected.draftId == _effectiveCreationDraftId) {
      return selected;
    }
    return _selectedCreationContext = YorksV1ProjectCreationDraftContext(
      ownerAuthUserId: owner,
      draftId: _effectiveCreationDraftId,
      entry: widget.resumeDraftId == null
          ? YorksV1ProjectCreationDraftEntry.newProposal
          : YorksV1ProjectCreationDraftEntry.resume,
    );
  }

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
    final seed = YorksV1ProjectCreationDraft(
      ownerAuthUserId: authUserId,
      currentStage: YorksV1ProjectCreationStage.projectDetails,
      creationIdempotencyKey: const Uuid().v4(),
      mode: YorksV1ProjectDraftMode.edit,
      projectId: item.project.id,
      baseVersion: item.project.version,
      reference: item.project.reference,
      name: item.project.name,
      clientName: client?.name ?? item.clientName,
      clientContactName: client?.contactName,
      clientContactPhone: client?.contactPhone,
      clientContactEmail: client?.contactEmail,
      clientAddress: client?.address,
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
    _editDraft = seed.copyWith(baseSnapshot: seed.toJson());
    if (!_editInitialized) {
      _editInitialized = true;
      final initial = _editDraft!;
      final generation = _contextGeneration;
      final editContext = YorksV1ProjectEditDraftContext(
        ownerAuthUserId: authUserId,
        projectId: item.project.id,
      );
      _editSeedInitialization =
          Future.microtask(() async {
            if (!_isCurrentContext(generation)) return;
            await ref
                .read(yorksV1ProjectEditDraftProvider(editContext).notifier)
                .initializeEdit(initial);
            if (_isCurrentContext(generation)) {
              setState(() => _editReady = true);
            }
          }).catchError((_) {
            // The entry gate retains the storage failure and offers a fenced
            // acknowledgement retry. No seed is exposed as an editable proposal.
          });
    }
  }

  YorksV1ProjectEditDraftContext _editContext(String owner) =>
      YorksV1ProjectEditDraftContext(
        ownerAuthUserId: owner,
        projectId: widget.editItem!.project.id,
      );
  bool _usesOriginalCreationProvider(String owner) => ref.read(
    yorksV1ProjectSelectedDraftUsesLegacyProvider(_creationContext(owner)),
  );
  YorksV1ProjectCreationDraftController _draftController(String owner) =>
      _isEditing
      ? ref.read(yorksV1ProjectEditDraftProvider(_editContext(owner)).notifier)
      : widget.legacyRecovery
      ? ref.read(yorksV1ProjectLegacyRecoveryDraftControllerProvider(owner))
      : _usesOriginalCreationProvider(owner)
      ? ref.read(yorksV1ProjectSetupCreationDraftProvider(owner).notifier)
      : ref.read(
          yorksV1ProjectSetupCreationDraftByIdProvider(
            _creationContext(owner),
          ).notifier,
        );

  bool get _requiresResumeEntry =>
      _isEditing ||
      widget.legacyRecovery ||
      _selectedCreationContext?.entry ==
          YorksV1ProjectCreationDraftEntry.resume;

  bool _canAcquireResume(int generation) {
    if (!_isCurrentContext(generation)) return false;
    final role = ref.read(yorksV1CurrentRoleProvider);
    if (role?.canCreateProject != true) return false;
    final router = GoRouter.maybeOf(context);
    if (router != null && router.state.uri != GoRouterState.of(context).uri) {
      // An outgoing scene may still be mounted during a route transition.
      // It cannot acquire the proposal after the selected entry has changed.
      return false;
    }
    // Ownership only opens the same owner-scoped local input buffer. Match
    // its existing availability policy during a permission-service outage;
    // remote commands still require a trusted canWrite decision separately.
    return yorksV1FeatureActionAccess(
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      _isEditing
          ? YorksV1CapabilityKeys.projectsEdit
          : YorksV1CapabilityKeys.projectsCreate,
      legacyAllowed: true,
      projectId: widget.editItem?.project.id,
    ).isVisible;
  }

  void _startResumeEntry() {
    if (_resumeEntryStarted) return;
    _resumeEntryStarted = true;
    final generation = _contextGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentContext(generation)) {
        unawaited(_acquireResumeEntry());
      }
    });
  }

  Future<void> _acquireResumeEntry({bool retry = false}) async {
    final owner = _activeAuthUserId;
    if (owner == null || _resumeEntryBusy) return;
    final generation = _contextGeneration;
    final controller = _draftController(owner);
    setState(() {
      _resumeEntryBusy = true;
      _resumeEntryFailed = false;
    });
    try {
      await controller.initialized;
      if (_editSeedInitialization != null) await _editSeedInitialization;
      if (!_isCurrentContext(generation)) return;
      final expectedId = _resumeExpectedDraftId ??=
          !_isEditing && !widget.legacyRecovery
          ? _effectiveCreationDraftId
          : controller.currentDraftId;
      final acquired = retry
          ? await controller.retryResumeOwnership(
              expectedDraftId: expectedId,
              canAcquire: () => _canAcquireResume(generation),
            )
          : await controller.resumeEditing(
              expectedDraftId: expectedId,
              canAcquire: () => _canAcquireResume(generation),
            );
      if (!_isCurrentContext(generation)) return;
      // An unseeded Edit fallback is a display snapshot; read the actual
      // provider status so a failed seed/acquisition cannot bypass this gate.
      final acquiredDraft = _isEditing
          ? ref.read(yorksV1ProjectEditDraftProvider(_editContext(owner)))
          : _currentDraft();
      final storageFailed =
          acquiredDraft.storageState == YorksV1ProjectDraftStorageState.failed;
      setState(() {
        // Missing/corrupt/retired records can render their existing guarded
        // recovery surface. Failed acknowledgement keeps fields unhydrated.
        _resumeEntryFailed = !acquired && storageFailed;
        _resumeEntryReady = !_resumeEntryFailed;
        _restoredEditor = false;
        _restoredNavigationStage = null;
        _ownershipCheckFailed = false;
        if (acquired && _isEditing) _editReady = true;
      });
    } catch (_) {
      if (_isCurrentContext(generation)) {
        setState(() => _resumeEntryFailed = true);
      }
    } finally {
      if (_isCurrentContext(generation)) {
        setState(() => _resumeEntryBusy = false);
      }
    }
  }

  Widget _resumeEntryGate(
    AppLanguage language,
    YorksV1FeatureActionAccess permission,
  ) => Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            key: const Key('yorks-v1-project-resume-entry'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_resumeEntryBusy ||
                  (permission.isVisible && !_resumeEntryFailed))
                const CircularProgressIndicator(
                  key: Key('yorks-v1-project-resume-loading'),
                ),
              YorksV1ActionAvailabilityNotice(
                access: permission,
                language: language,
                onRetry: () => ref
                    .read(yorksV1CurrentPermissionSnapshotProvider.notifier)
                    .retryVerification(),
              ),
              if (_resumeEntryFailed) ...[
                Text(
                  YorksV1ProjectStrings.localSaveFailed.active(language),
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  key: const Key('yorks-v1-project-resume-retry'),
                  onPressed: _resumeEntryBusy || !permission.isVisible
                      ? null
                      : () => _acquireResumeEntry(retry: true),
                  child: Text(YorksV1ProjectStrings.retry.active(language)),
                ),
              ],
              TextButton(
                onPressed: () => context.go(RoutePaths.yorksV1Projects),
                child: Text(
                  YorksV1ProjectSetupShellStrings.returnToProjects.active(
                    language,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _resumedElsewhereNotice(AppLanguage language) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      key: const Key('yorks-v1-project-draft-resumed-elsewhere'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(YorksV1ProjectStrings.draftResumedElsewhere.active(language)),
        TextButton(
          onPressed: () => context.go(RoutePaths.yorksV1Projects),
          child: Text(
            YorksV1ProjectSetupShellStrings.returnToProjects.active(language),
          ),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    _freshDraftId =
        widget.newDraftId ??
        (!widget.isEditing &&
                !widget.legacyRecovery &&
                widget.resumeDraftId == null
            ? const Uuid().v4()
            : '');
    _navigationService = ref.read(yorksV1ProjectSetupNavigationGuardProvider);
    _navigationService.register(
      _navigationGuard,
      creationSelection: () =>
          _isEditing ||
              _activeAuthUserId == null ||
              !_isCurrentContext(_contextGeneration)
          ? null
          : (
              draftId: widget.legacyRecovery ? null : _effectiveCreationDraftId,
              legacyRecovery: widget.legacyRecovery,
            ),
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_queueNavigationContext);
    for (final entry in _fieldFocusNodes.entries) {
      entry.value.addListener(() {
        if (entry.value.hasFocus && !_restoringNavigation) {
          _lastFocusedField = entry.key;
          _queueNavigationContext();
        }
      });
    }
    for (final controller in [
      _subcontractorController,
      _otherContractorController,
      _buildingCodeController,
      _buildingNameController,
      _buildingFloorsController,
      _buildingDeliveryAddressController,
    ]) {
      controller.addListener(_queueEditorState);
    }
    _startDateController.addListener(() => _typedDateChanged(true));
    _endDateController.addListener(() => _typedDateChanged(false));
  }

  @override
  void didUpdateWidget(covariant YorksV1ProjectCreateFlowScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A canonical Create request can reuse this route's State after an
    // anchored Resume. It still requests a new independent proposal.
    if (!widget.isEditing &&
        !widget.legacyRecovery &&
        widget.resumeDraftId == null &&
        (oldWidget.resumeDraftId != null ||
            oldWidget.legacyRecovery ||
            oldWidget.newDraftId != widget.newDraftId)) {
      _freshDraftId = widget.newDraftId ?? const Uuid().v4();
      _draftUrlAnchorQueued = false;
    }
  }

  void _anchorDraftUrl(YorksV1ProjectCreationDraft draft) {
    if (_isEditing ||
        _draftUrlAnchorQueued ||
        _confirmedContextResult ||
        _releasingConfirmedHistory ||
        _isCreating) {
      return;
    }
    final readOnlySelection = draft.isReadOnly && _pendingDraft == null;
    if (!readOnlySelection &&
        draft.storageState != YorksV1ProjectDraftStorageState.dirty &&
        draft.storageState != YorksV1ProjectDraftStorageState.saved) {
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final scene = GoRouterState.of(context).uri;
    if (scene.path != RoutePaths.engineerCreateProject) return;
    bool isCurrentCreationScene() {
      if (router.routerDelegate.currentConfiguration.isEmpty ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return false;
      }
      final top = router.state.uri;
      return top.path == RoutePaths.engineerCreateProject &&
          top.queryParameters.containsKey('draft') ==
              scene.queryParameters.containsKey('draft') &&
          top.queryParameters['draft'] == scene.queryParameters['draft'] &&
          top.queryParameters['recovery'] == scene.queryParameters['recovery'];
    }

    if (!isCurrentCreationScene()) return;
    final selectedId = widget.legacyRecovery ? null : _effectiveCreationDraftId;
    if (!widget.legacyRecovery &&
        scene.queryParameters.containsKey('draft') &&
        scene.queryParameters['draft'] != selectedId) {
      return;
    }
    final target = widget.legacyRecovery
        ? scene
        : scene.replace(
            queryParameters: {...scene.queryParameters, 'draft': selectedId!},
          );
    if (router.routerDelegate.currentConfiguration.uri == target) return;
    final generation = _contextGeneration;
    final controller = _draftController(draft.ownerAuthUserId);
    _draftUrlAnchorQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.initialized;
      if (!_isCurrentContext(generation) ||
          !isCurrentCreationScene() ||
          _confirmedContextResult ||
          _releasingConfirmedHistory ||
          _isCreating) {
        return;
      }
      final currentDraft = _currentDraft();
      if (!currentDraft.isReadOnly) {
        if (!controller.writable ||
            currentDraft.storageState ==
                YorksV1ProjectDraftStorageState.failed) {
          _draftUrlAnchorQueued = false;
          return;
        }
        try {
          await _flushPendingDraft();
          if (!_isCurrentContext(generation) || !isCurrentCreationScene()) {
            return;
          }
          // Explicit checkpoint preserves fields, partial editors and local
          // metadata even while navigation-restoration listeners are paused.
          final checkpoint = _withLocalRowIds(_currentDraft());
          await controller.save(
            checkpoint.copyWith(rawEditorState: _rawEditorState(checkpoint)),
            saveTrigger: 'navigation',
          );
          if (!_isCurrentContext(generation) || !isCurrentCreationScene()) {
            return;
          }
          await controller.flush(saveTrigger: 'navigation');
          if (!_isCurrentContext(generation) || !isCurrentCreationScene()) {
            return;
          }
          if (!_currentDraft().isAcknowledged || _pendingDraft != null) {
            _draftUrlAnchorQueued = false;
            return;
          }
        } catch (_) {
          if (_isCurrentContext(generation)) _draftUrlAnchorQueued = false;
          return;
        }
      } else if (_pendingDraft != null) {
        _draftUrlAnchorQueued = false;
        return;
      }
      if (!mounted ||
          !_isCurrentContext(generation) ||
          !isCurrentCreationScene() ||
          _confirmedContextResult ||
          _releasingConfirmedHistory ||
          _isCreating) {
        return;
      }
      final current = GoRouterState.of(context).uri;
      if (current.path != RoutePaths.engineerCreateProject) return;
      final anchored = widget.legacyRecovery
          ? current.toString()
          : current
                .replace(
                  queryParameters: {
                    ...current.queryParameters,
                    'draft': selectedId!,
                  },
                )
                .toString();
      final page = ModalRoute.of(context)?.settings;
      final pageKey = page is Page ? page.key : null;
      final carryover =
          pageKey is ValueKey<String> &&
              pageKey.value.isNotEmpty &&
              pageKey.value.length <= 160
          ? <String, String>{
              RoutePaths.projectSetupAnchorPageKeyExtra: pageKey.value,
              RoutePaths.projectSetupAnchorSelectorExtra: widget.legacyRecovery
                  ? 'legacy'
                  : 'draft:$selectedId',
            }
          : null;
      ref
          .read(yorksNavigationHistoryProvider.notifier)
          .replaceCurrent(current.toString(), anchored);
      // Preserve the mounted same-proposal page while changing the real browser
      // URL. The extra carries only page identity; query selects the draft.
      Router.neglect(context, () => router.go(anchored, extra: carryover));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingDraft());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_verifyResumedOwnership());
    }
  }

  Future<void> _verifyResumedOwnership() async {
    final owner = _activeAuthUserId;
    if (owner == null || !mounted || !_resumeEntryReady) return;
    final generation = _contextGeneration;
    final controller = _draftController(owner);
    setState(() {
      _checkingOwnership = true;
      _ownershipCheckFailed = false;
    });
    try {
      await controller.verifyOwnership();
    } catch (_) {
      if (_isCurrentContext(generation)) {
        _ownershipCheckFailed = !_currentDraft().isReadOnly;
      }
    } finally {
      if (_isCurrentContext(generation)) {
        setState(() => _checkingOwnership = false);
      }
    }
  }

  @override
  void dispose() {
    // A text edit may still be inside the short debounce window when a route
    // is popped or the app is backgrounded.  Start the owner-scoped local save
    // from the captured final values. Riverpod listeners must be detached
    // before save publishes a revision to avoid notifying a defunct element.
    _disposed = true;
    _draftSaveTimer?.cancel();
    final pending = _pendingDraft;
    _pendingDraft = null;
    if (pending != null && _liveDraftController != null) {
      final stable = _withLocalRowIds(pending);
      final snapshot = stable.copyWith(rawEditorState: _rawEditorState(stable));
      final controller = _liveDraftController!;
      unawaited(
        Future<void>.microtask(
          () => controller.save(snapshot),
        ).catchError((_) {}),
      );
    }
    _navigationService.unregister(_navigationGuard);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    for (final node in _fieldFocusNodes.values) {
      node.dispose();
    }
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
    final backend = ref.watch(yorksV1ProjectDraftBackendIdentityProvider);
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
    if (_activeAuthUserId != authUserId ||
        _activeEditProjectId != widget.editItem?.project.id ||
        _activeLegacyRecovery != widget.legacyRecovery ||
        _activeBackendIdentity != backend ||
        (!_isEditing && _activeCreationDraftId != _effectiveCreationDraftId)) {
      _contextGeneration++;
      _isCreating = false;
      _checkingOwnership = false;
      _ownershipCheckFailed = false;
      for (final node in _fieldFocusNodes.values) {
        node.unfocus();
      }
      _draftSaveTimer?.cancel();
      _pendingDraft = null;
      _activeAuthUserId = authUserId;
      _activeEditProjectId = widget.editItem?.project.id;
      _activeCreationDraftId = _isEditing ? null : _effectiveCreationDraftId;
      _activeBackendIdentity = backend;
      _activeLegacyRecovery = widget.legacyRecovery;
      _selectedCreationContext = null;
      _draftUrlAnchorQueued = false;
      _validationErrors = const {};
      _detailsFormKey = GlobalKey<FormState>();
      _selectedAttachmentFiles = const [];
      _editDraft = null;
      _editingBuildingIndex = null;
      _restoredEditor = false;
      _editInitialized = false;
      _editReady = false;
      _editSeedInitialization = null;
      _resumeEntryStarted = false;
      _resumeEntryReady = false;
      _resumeEntryBusy = false;
      _resumeEntryFailed = false;
      _resumeExpectedDraftId = null;
      _synchronizingEditor = true;
      for (final controller in _controllers) {
        controller.clear();
      }
      _hasFrpRoom = false;
      _synchronizingEditor = false;
      _removedBuilding = null;
      _removedBuildingIndex = null;
      _buildingUndoRows = null;
      _removedParty = null;
      _removedPartyIndex = null;
      _renderedStage = null;
      _restoredNavigationStage = null;
      _lastFocusedField = null;
      _restoringNavigation = false;
      _leaveAuthorizedGeneration = null;
      _manuallySavedInput = null;
      _manualSavePending = false;
      _leaveDecision = null;
      _confirmedContextResult = false;
      _completedOperation = null;
      _releasingConfirmedHistory = false;
      _confirmedHistoryReleaseFailed = false;
      _visitedStages.clear();
      _visitedStages.add(YorksV1ProjectCreationStage.projectDetails);
    }

    _seedEditDraft(authUserId);
    final useOriginalCreation =
        !_isEditing &&
        !widget.legacyRecovery &&
        ref.watch(
          yorksV1ProjectSelectedDraftUsesLegacyProvider(
            _creationContext(authUserId),
          ),
        );
    final storedDraft = _isEditing
        ? ref.watch(yorksV1ProjectEditDraftProvider(_editContext(authUserId)))
        : widget.legacyRecovery
        ? ref.watch(yorksV1ProjectLegacyRecoveryDraftProvider(authUserId))
        : useOriginalCreation
        ? ref.watch(yorksV1ProjectSetupCreationDraftProvider(authUserId))
        : ref.watch(
            yorksV1ProjectSetupCreationDraftByIdProvider(
              _creationContext(authUserId),
            ),
          );
    _liveDraftController = _draftController(authUserId);
    if (_isEditing && storedDraft.baseVersion == null) {
      _editDraft = _editDraft!.copyWith(
        draftId: storedDraft.draftId,
        backendIdentity: storedDraft.backendIdentity,
        revision: storedDraft.revision,
        acknowledgedRevision: storedDraft.acknowledgedRevision,
        writerEpoch: storedDraft.writerEpoch,
        storageState: storedDraft.storageState,
      );
    }
    final draft = _isEditing && storedDraft.baseVersion == null
        ? _editDraft!
        : storedDraft;
    if (!_requiresResumeEntry) {
      // Anchoring a newly created proposal keeps its immutable new-entry
      // context and its existing lease through the same-ID URL replacement.
      _resumeEntryReady = true;
    } else if (!_resumeEntryReady) {
      if (permission.isVisible) _startResumeEntry();
      return _resumeEntryGate(language, permission);
    }
    _anchorDraftUrl(draft);
    _visitedStages.addAll(draft.visitedStages);
    _restoreRawEditor(draft);
    _visitedStages.add(draft.currentStage);
    _synchronizeControllers(_pendingDraft ?? draft);
    _renderedStage = draft.currentStage;
    _restoreSectionContext(draft);
    final commandState = ref.watch(yorksV1ProjectCommandControllerProvider);
    final setupState = ref.watch(_coordinatorProvider(draft));
    final committed = setupState.operation?.coreSucceeded == true;
    // A confirmed result belongs to its project, not the next creation form.
    // Releasing the proposal preserves its exact journal and pending files.
    if (committed && !_isCreating && !_confirmedContextResult) {
      final historyOwnedElsewhere =
          draft.storageState == YorksV1ProjectDraftStorageState.ownedElsewhere;
      final waitingForOwnership =
          draft.storageState == YorksV1ProjectDraftStorageState.initializing ||
          _checkingOwnership;
      final historyReleaseFailed =
          _confirmedHistoryReleaseFailed || _ownershipCheckFailed;
      if (!waitingForOwnership &&
          draft.storageState ==
              YorksV1ProjectDraftStorageState.recoveryRequired &&
          setupState.recoveryError == null &&
          !_releasingConfirmedHistory) {
        // A retired/missing local envelope needs no new writer when its exact
        // immutable journal already verifies the committed project. Keep its
        // local records untouched and open only the authorized known result.
        _releasingConfirmedHistory = true;
        final generation = _contextGeneration;
        final operation = setupState.operation!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isCurrentContext(generation)) return;
          _confirmedContextResult = true;
          _openConfirmedProject(operation.project!, operation: operation);
        });
      } else if (!waitingForOwnership &&
          !draft.isReadOnly &&
          !historyReleaseFailed &&
          !_releasingConfirmedHistory) {
        _releasingConfirmedHistory = true;
        final generation = _contextGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isCurrentContext(generation)) return;
          unawaited(_releaseConfirmedHistory(draft, generation));
        });
      }
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child:
                  waitingForOwnership ||
                      (!historyOwnedElsewhere &&
                          !historyReleaseFailed &&
                          !draft.isReadOnly)
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (historyOwnedElsewhere
                                  ? YorksV1ProjectStrings.draftResumedElsewhere
                                  : YorksV1ProjectStrings.localSaveFailed)
                              .active(language),
                          textAlign: TextAlign.center,
                        ),
                        if (!historyOwnedElsewhere)
                          TextButton(
                            onPressed: _retryConfirmedHistory,
                            child: Text(
                              YorksV1ProjectStrings.retry.active(language),
                            ),
                          ),
                        TextButton(
                          onPressed: () =>
                              context.go(RoutePaths.yorksV1Projects),
                          child: Text(
                            YorksV1ProjectSetupShellStrings.returnToProjects
                                .active(language),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }
    final intentLocked = committed || setupState.outcomeUncertain;

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
        setupState.busy ||
        ((commandState.operation ==
                    YorksV1ProjectCommandOperation.createProject ||
                commandState.operation ==
                    YorksV1ProjectCommandOperation.updateProject) &&
            commandState.status == YorksV1ProjectCommandStatus.saving);
    final storageFailed =
        draft.storageState == YorksV1ProjectDraftStorageState.failed;
    final ownedElsewhere =
        draft.storageState == YorksV1ProjectDraftStorageState.ownedElsewhere;
    final recoveryRequired =
        draft.storageState == YorksV1ProjectDraftStorageState.recoveryRequired;
    final readOnly =
        !_draftController(authUserId).writable ||
        draft.isReadOnly ||
        _checkingOwnership ||
        _ownershipCheckFailed ||
        (_isEditing && !_editReady) ||
        draft.storageState == YorksV1ProjectDraftStorageState.initializing;
    final hasLocalInput = _isEditing
        ? draft.hasRecoverableContent
        : _hasMeaningfulSetupInput(_pendingDraft ?? draft);
    final acknowledged =
        draft.storageState == YorksV1ProjectDraftStorageState.saved &&
        draft.acknowledgedRevision == draft.revision &&
        _pendingDraft == null &&
        hasLocalInput;
    final localStatus = recoveryRequired
        ? YorksV1ProjectStrings.draftNeedsRecovery
        : ownedElsewhere
        ? YorksV1ProjectStrings.draftOwnedElsewhere
        : storageFailed || _ownershipCheckFailed
        ? YorksV1ProjectStrings.localSaveFailed
        : !hasLocalInput && _pendingDraft == null
        ? YorksV1ProjectStrings.notSavedYet
        : _pendingDraft != null ||
              draft.storageState == YorksV1ProjectDraftStorageState.saving ||
              draft.storageState == YorksV1ProjectDraftStorageState.dirty
        ? YorksV1ProjectStrings.savingLocalDraft
        : acknowledged
        ? (_isEditing
              ? YorksV1ProjectStrings.editSavedLocally
              : YorksV1ProjectStrings.draftSaved)
        : YorksV1ProjectStrings.notSavedYet;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveLocalDraftIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _SaveLocalDraftIntent(),
      },
      child: Actions(
        actions: {
          _SaveLocalDraftIntent: CallbackAction<_SaveLocalDraftIntent>(
            onInvoke: (_) {
              if (_completedOperation?.cleanupComplete != true) {
                unawaited(_saveDraft(_currentDraft(), manual: true));
              }
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: _pendingDraft == null && !storageFailed,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final generation = _contextGeneration;
            final canLeave = await _prepareLeave();
            if (!context.mounted ||
                !mounted ||
                !_isCurrentContext(generation)) {
              return;
            }
            if (!canLeave) return;
            await Navigator.of(context).maybePop(result);
          },
          child: ScaffoldMessenger(
            key: _featureMessengerKey,
            child: Scaffold(
              key: _featureScaffoldKey,
              backgroundColor: AppColors.surface,
              body: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop =
                        YorksProjectSetupDesktopTheme.isDesktopForWidth(
                          context,
                          constraints.maxWidth,
                        );
                    final rail = constraints.maxWidth >= 980;
                    final showHelp =
                        constraints.maxWidth >= 1280 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.5;
                    final navigation = _StageNavigation(
                      currentStage: draft.currentStage,
                      language: language,
                      vertical: rail,
                      visitedStages: _isEditing
                          ? YorksV1ProjectCreationStage.values.toSet()
                          : _visitedStages,
                      onSelect: _selectStage,
                    );
                    final content = _buildStageContent(
                      draft: draft,
                      language: language,
                      creatorRole: role,
                      creatorAuthUserId: authUserId,
                      teamDirectory: teamDirectory,
                      setupState: setupState,
                    );
                    if (YorksProjectSetupDesktopTheme.isDesktop(context) ||
                        YorksProjectSetupMobileTheme.isMobileLayout(context)) {
                      final editorPending =
                          (draft.currentStage ==
                                  YorksV1ProjectCreationStage.buildings &&
                              _hasUnappliedBuildingEditor) ||
                          (draft.currentStage ==
                                  YorksV1ProjectCreationStage
                                      .partiesAndAccess &&
                              _hasUnappliedPartyEditor);
                      final completeStages = {
                        for (final stage in YorksV1ProjectCreationStage.values)
                          if (stage !=
                                  YorksV1ProjectCreationStage.reviewAndCreate &&
                              (_isEditing || _visitedStages.contains(stage)) &&
                              _errorsForStage(stage, draft).isEmpty &&
                              !(stage ==
                                      YorksV1ProjectCreationStage.buildings &&
                                  _hasUnappliedBuildingEditor) &&
                              !(stage ==
                                      YorksV1ProjectCreationStage
                                          .partiesAndAccess &&
                                  _hasUnappliedPartyEditor) &&
                              !(stage ==
                                      YorksV1ProjectCreationStage
                                          .projectDetails &&
                                  _hasInvalidTypedDates))
                            stage,
                      };
                      final buildShell = desktop
                          ? YorksV1ProjectSetupDesktopShell.new
                          : YorksV1ProjectSetupMobileShell.new;
                      return YorksProjectSetupLayoutScope(
                        availableWidth: constraints.maxWidth,
                        child: buildShell(
                          language: language,
                          stage: draft.currentStage,
                          visitedStages: _isEditing
                              ? YorksV1ProjectCreationStage.values.toSet()
                              : _visitedStages,
                          completeStages: completeStages,
                          completed: false,
                          reference: draft.reference,
                          projectName: draft.name,
                          localStatus: localStatus.active(language),
                          saving: saving,
                          readOnly: readOnly,
                          savedOnDevice: acknowledged,
                          isEditing: _isEditing,
                          scrollController: _scrollController,
                          onSelectStage: _selectStage,
                          onSaveDraft: saving || readOnly || _manualSavePending
                              ? null
                              : () => _saveDraft(_currentDraft(), manual: true),
                          onBack: _back,
                          onReturnToProjects: () async {
                            final generation = _contextGeneration;
                            if (!await _prepareLeave() ||
                                !mounted ||
                                !context.mounted ||
                                !_isCurrentContext(generation)) {
                              return;
                            }
                            context.go(RoutePaths.yorksV1Projects);
                          },
                          onContinue: saving || readOnly || editorPending
                              ? null
                              : _continue,
                          onSkip: saving || readOnly ? null : _skipAttachments,
                          onFinalAction:
                              permission.canWrite &&
                                  !readOnly &&
                                  (intentLocked ||
                                      (!_hasUnappliedBuildingEditor &&
                                          !_hasUnappliedPartyEditor))
                              ? _createProject
                              : null,
                          primaryLabel: intentLocked
                              ? (setupState.outcomeUncertain
                                    ? YorksV1ProjectStrings.checkSavedStatus
                                    : YorksV1ProjectStrings
                                          .continueFileRecovery)
                              : _isEditing
                              ? YorksV1ProjectStrings.saveChanges
                              : YorksV1ProjectStrings.createProject,
                          footerHint: editorPending
                              ? YorksV1ProjectSetupShellStrings
                                    .buildingEditPending
                              : null,
                          headerActions: [
                            if (_ownershipCheckFailed)
                              TextButton(
                                onPressed: _verifyResumedOwnership,
                                child: Text(
                                  YorksV1ProjectStrings.retry.active(language),
                                ),
                              ),
                          ],
                          notices: [
                            if (ownedElsewhere)
                              _resumedElsewhereNotice(language),
                            if (_isEditing)
                              YorksV1ProjectSetupPendingRecovery(
                                project: widget.editItem!.project,
                                activeMembers: widget.editItem!.activeMembers,
                              ),
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
                            if (_validationErrors.isNotEmpty && !intentLocked)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      YorksV1ProjectStrings.stageNeedsAttention
                                          .active(language),
                                      style: AppTypography.titleSmall,
                                    ),
                                    for (final error in _validationErrors)
                                      TextButton.icon(
                                        onPressed: readOnly
                                            ? null
                                            : () => _focusInvalidField(error),
                                        icon: const Icon(
                                          Icons.error_outline,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${_validationTargetLabel(error).active(language)}: ${_messageForValidation({error}).active(language)}',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (setupState.operation != null ||
                                setupState.recoveryError != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _ProjectSetupOutcomePanel(
                                  state: setupState,
                                  language: language,
                                  onRecover: _createProject,
                                  onOpen: setupState.project == null
                                      ? null
                                      : () => context.go(
                                          RoutePaths.yorksV1ProjectPath(
                                            setupState.project!.id,
                                          ),
                                        ),
                                  onReselect: () => _setStage(
                                    YorksV1ProjectCreationStage.attachments,
                                  ),
                                  onRetryFile: _retrySetupFile,
                                  onRemovePendingFile: _removePendingSetupFile,
                                ),
                              ),
                            if (recoveryRequired)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _DesktopPanel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        YorksV1ProjectStrings.draftNeedsRecovery
                                            .active(language),
                                      ),
                                      TextButton(
                                        onPressed: _reviewRecoveredDraft,
                                        child: Text(
                                          YorksV1ProjectStrings
                                              .reviewRecoveredDraft
                                              .active(language),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                          body: AbsorbPointer(
                            absorbing:
                                saving ||
                                readOnly ||
                                (intentLocked &&
                                    draft.currentStage !=
                                        YorksV1ProjectCreationStage
                                            .attachments),
                            child:
                                intentLocked &&
                                    draft.currentStage !=
                                        YorksV1ProjectCreationStage.attachments
                                ? _OriginalSetupIntentSummary(
                                    operation: setupState.operation!,
                                    language: language,
                                  )
                                : content,
                          ),
                        ),
                      );
                    }
                    final stackHeader =
                        constraints.maxWidth < 600 &&
                        (MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                            ownedElsewhere ||
                            _ownershipCheckFailed);
                    final heading = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_isEditing
                                  ? YorksV1ProjectStrings.editProject
                                  : YorksV1ProjectStrings.projectSetup)
                              .active(language),
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            localStatus.active(language),
                            style: AppTypography.bodySmall.copyWith(
                              color: storageFailed
                                  ? AppColors.error
                                  : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            rail ? 24 : 14,
                            16,
                            rail ? 24 : 14,
                            12,
                          ),
                          child: Flex(
                            direction: stackHeader
                                ? Axis.vertical
                                : Axis.horizontal,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (stackHeader)
                                SizedBox(width: double.infinity, child: heading)
                              else
                                Expanded(child: heading),
                              SizedBox(width: 12, height: stackHeader ? 8 : 0),
                              if (_ownershipCheckFailed)
                                TextButton(
                                  onPressed: _verifyResumedOwnership,
                                  child: Text(
                                    YorksV1ProjectStrings.retry.active(
                                      language,
                                    ),
                                  ),
                                ),
                              OutlinedButton.icon(
                                onPressed:
                                    saving || readOnly || _manualSavePending
                                    ? null
                                    : () => _saveDraft(
                                        _currentDraft(),
                                        manual: true,
                                      ),
                                icon: const Icon(Icons.save_outlined, size: 18),
                                label: Text(
                                  YorksV1ProjectStrings.saveDraft.active(
                                    language,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                        if (!rail)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: navigation,
                          ),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (rail)
                                SizedBox(
                                  width: 214,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      10,
                                      12,
                                      20,
                                    ),
                                    child: navigation,
                                  ),
                                ),
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  padding: EdgeInsets.fromLTRB(
                                    rail ? 12 : 14,
                                    12,
                                    rail ? 20 : 14,
                                    24,
                                  ),
                                  child: Align(
                                    alignment: AlignmentDirectional.topStart,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 920,
                                      ),
                                      child: Container(
                                        padding: EdgeInsets.all(rail ? 28 : 16),
                                        decoration: BoxDecoration(
                                          color:
                                              AppColors.surfaceContainerLowest,
                                          border: Border.all(
                                            color: AppColors.line,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusLg,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _R35CreationStageHeader(
                                              stage: draft.currentStage,
                                              language: language,
                                            ),
                                            const SizedBox(height: 20),
                                            if (ownedElsewhere)
                                              _resumedElsewhereNotice(language),
                                            if (_validationErrors.isNotEmpty &&
                                                !intentLocked)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 16,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      YorksV1ProjectStrings
                                                          .stageNeedsAttention
                                                          .active(language),
                                                      style: AppTypography
                                                          .titleSmall,
                                                    ),
                                                    for (final error
                                                        in _validationErrors)
                                                      TextButton.icon(
                                                        onPressed: readOnly
                                                            ? null
                                                            : () =>
                                                                  _focusInvalidField(
                                                                    error,
                                                                  ),
                                                        icon: const Icon(
                                                          Icons.error_outline,
                                                          size: 18,
                                                        ),
                                                        label: Text(
                                                          '${_validationTargetLabel(error).active(language)}: ${_messageForValidation({error}).active(language)}',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            if (setupState.operation != null ||
                                                setupState.recoveryError !=
                                                    null) ...[
                                              _ProjectSetupOutcomePanel(
                                                state: setupState,
                                                language: language,
                                                onRecover: _createProject,
                                                onOpen:
                                                    setupState.project == null
                                                    ? null
                                                    : () => context.go(
                                                        RoutePaths.yorksV1ProjectPath(
                                                          setupState
                                                              .project!
                                                              .id,
                                                        ),
                                                      ),
                                                onReselect: () => _setStage(
                                                  YorksV1ProjectCreationStage
                                                      .attachments,
                                                ),
                                                onRetryFile: _retrySetupFile,
                                                onRemovePendingFile:
                                                    _removePendingSetupFile,
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                            if (recoveryRequired)
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors
                                                      .neutralContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppSpacing.radiusMd,
                                                      ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      YorksV1ProjectStrings
                                                          .draftNeedsRecovery
                                                          .active(language),
                                                    ),
                                                    TextButton(
                                                      onPressed:
                                                          _reviewRecoveredDraft,
                                                      child: Text(
                                                        YorksV1ProjectStrings
                                                            .reviewRecoveredDraft
                                                            .active(language),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            AbsorbPointer(
                                              absorbing:
                                                  saving ||
                                                  readOnly ||
                                                  (intentLocked &&
                                                      draft.currentStage !=
                                                          YorksV1ProjectCreationStage
                                                              .attachments),
                                              child:
                                                  intentLocked &&
                                                      draft.currentStage !=
                                                          YorksV1ProjectCreationStage
                                                              .attachments
                                                  ? _OriginalSetupIntentSummary(
                                                      operation:
                                                          setupState.operation!,
                                                      language: language,
                                                    )
                                                  : content,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (showHelp)
                                SizedBox(
                                  width: 260,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      12,
                                      24,
                                      24,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: AppColors.blueContainer
                                              .withValues(alpha: .45),
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusLg,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.info_outline,
                                              color: AppColors.blue,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              _stageCopy(
                                                draft.currentStage,
                                              ).active(language),
                                              style: AppTypography.titleMedium,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _stageDescription(
                                                draft.currentStage,
                                              ).active(language),
                                              style: AppTypography.bodyMedium,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              YorksV1ProjectStrings
                                                  .permittedDetailsHelp
                                                  .active(language),
                                              style: AppTypography.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            border: Border(
                              top: BorderSide(color: AppColors.line),
                            ),
                          ),
                          child: _StageActions(
                            stage: draft.currentStage,
                            language: language,
                            saving: saving,
                            onBack: _back,
                            onContinue: _continue,
                            onSkip: _skipAttachments,
                            onCreate: permission.canWrite && !readOnly
                                ? _createProject
                                : null,
                            primaryLabel: intentLocked
                                ? (setupState.outcomeUncertain
                                      ? YorksV1ProjectStrings.checkSavedStatus
                                      : YorksV1ProjectStrings
                                            .continueFileRecovery)
                                : _isEditing
                                ? YorksV1ProjectStrings.saveChanges
                                : YorksV1ProjectStrings.createProject,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
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
    required YorksV1ProjectSetupState setupState,
  }) {
    final generation = _contextGeneration;
    final stage = draft.currentStage;
    bool mayAct({
      bool mutation = true,
      bool fileRecovery = false,
      bool bufferOnly = false,
    }) {
      if (!_isCurrentContext(generation) ||
          _currentDraft().draftId != draft.draftId) {
        return false;
      }
      final role = ref.read(yorksV1CurrentRoleProvider);
      final access = yorksV1FeatureActionAccess(
        ref.read(yorksV1CurrentPermissionSnapshotProvider),
        _isEditing
            ? YorksV1CapabilityKeys.projectsEdit
            : YorksV1CapabilityKeys.projectsCreate,
        legacyAllowed: role?.canCreateProject == true,
        projectId: widget.editItem?.project.id,
      );
      if (!mutation) return access.isVisible;
      final current = _currentDraft();
      final operation = ref.read(_coordinatorProvider(current)).operation;
      return (bufferOnly ? access.isVisible : access.canWrite) &&
          _draftController(current.ownerAuthUserId).writable &&
          !current.isReadOnly &&
          current.storageState !=
              YorksV1ProjectDraftStorageState.initializing &&
          !_checkingOwnership &&
          !_ownershipCheckFailed &&
          !_isCreating &&
          (fileRecovery &&
                  (operation == null || operation.draftId == current.draftId) ||
              operation?.coreSucceeded != true &&
                  operation?.hasUnresolvedCommand != true);
    }

    VoidCallback guardedBufferAction(VoidCallback action) => () {
      if (mayAct(bufferOnly: true)) action();
    };
    ValueChanged<T> guardedBufferValue<T>(ValueChanged<T> action) => (value) {
      if (mayAct(bufferOnly: true)) action(value);
    };
    VoidCallback guardedFileAction(VoidCallback action) => () {
      if (mayAct(fileRecovery: true)) action();
    };
    ValueChanged<T> guardedFileValue<T>(ValueChanged<T> action) => (value) {
      if (mayAct(fileRecovery: true)) action(value);
    };
    ValueChanged<T> guardedReadValue<T>(ValueChanged<T> action) => (value) {
      if (mayAct(mutation: false)) action(value);
    };
    VoidCallback guardedAction(VoidCallback action) => () {
      if (mayAct()) action();
    };
    VoidCallback? guardedNullableAction(VoidCallback? action) =>
        action == null ? null : guardedAction(action);
    VoidCallback guardedReadAction(VoidCallback action) => () {
      if (mayAct(mutation: false)) action();
    };
    ValueChanged<T> guardedValue<T>(ValueChanged<T> action) => (value) {
      if (mayAct()) action(value);
    };
    void Function(A, B) guardedPair<A, B>(void Function(A, B) action) =>
        (first, second) {
          if (mayAct()) action(first, second);
        };

    final advisory =
        stage == YorksV1ProjectCreationStage.projectDetails &&
            _referenceController.text.trim().isNotEmpty
        ? ref.watch(
            yorksV1ProjectReferenceAdvisoryProvider((
              reference: _referenceController.text,
              projectId: widget.editItem?.project.id,
            )),
          )
        : null;
    final referenceHint = advisory?.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      data: (value) => switch (value) {
        YorksV1ProjectReferenceAdvisory.duplicateVisible =>
          YorksV1ProjectStrings.referenceVisibleDuplicate,
        YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope =>
          YorksV1ProjectStrings.referenceNoVisibleMatch,
        YorksV1ProjectReferenceAdvisory.unavailable =>
          YorksV1ProjectStrings.referenceCheckUnavailable,
      },
      error: (_, _) => YorksV1ProjectStrings.referenceCheckUnavailable,
      loading: () => YorksV1ProjectStrings.referenceChecking,
    );
    final stageBody = switch (stage) {
      YorksV1ProjectCreationStage.projectDetails => _DetailsStage(
        formKey: _detailsFormKey,
        referenceHint: referenceHint,
        focusNodes: _fieldFocusNodes,
        language: language,
        referenceController: _referenceController,
        nameController: _nameController,
        clientController: _clientController,
        jobOrContractController: _jobOrContractController,
        siteController: _siteController,
        notesController: _notesController,
        contactNameController: _clientContactNameController,
        contactPhoneController: _clientContactPhoneController,
        contactEmailController: _clientContactEmailController,
        contactAddressController: _clientAddressController,
        onContactChanged: guardedBufferValue(_clientContactsChanged),
        contactsExpanded: draft.rawEditorState['contactsExpanded'] == true,
        onContactsExpanded: guardedBufferValue(
          (expanded) => _queueDraft(
            (current) => current.copyWith(
              rawEditorState: {
                ...current.rawEditorState,
                'contactsExpanded': expanded,
              },
            ),
            semanticEdit: false,
          ),
        ),
        startDateController: _startDateController,
        endDateController: _endDateController,
        validationErrors: _validationErrors,
        onReferenceChanged: guardedBufferValue(
          (value) =>
              _queueDraft((current) => current.copyWith(reference: value)),
        ),
        onNameChanged: guardedBufferValue(
          (value) => _queueDraft((current) => current.copyWith(name: value)),
        ),
        onClientChanged: guardedBufferValue(
          (value) =>
              _queueDraft((current) => current.copyWith(clientName: value)),
        ),
        onJobOrContractChanged: guardedBufferValue(
          (value) => _queueDraft(
            (current) => current.copyWith(jobOrContractReference: value),
          ),
        ),
        onSiteChanged: guardedBufferValue(
          (value) =>
              _queueDraft((current) => current.copyWith(siteLocation: value)),
        ),
        onNotesChanged: guardedBufferValue(
          (value) => _queueDraft((current) => current.copyWith(notes: value)),
        ),
        onSelectStartDate: guardedBufferAction(
          () => _selectDate(isStartDate: true),
        ),
        onSelectEndDate: guardedBufferAction(
          () => _selectDate(isStartDate: false),
        ),
        onTodayStart: guardedBufferAction(() => _useToday(true)),
        onTodayEnd: guardedBufferAction(() => _useToday(false)),
      ),
      YorksV1ProjectCreationStage.partiesAndAccess => _PartiesAndAccessStage(
        draft: draft,
        focusNodes: _fieldFocusNodes,
        language: language,
        consultantController: _consultantController,
        mainContractorController: _mainContractorController,
        subcontractorController: _subcontractorController,
        otherContractorController: _otherContractorController,
        validationErrors: _validationErrors,
        creatorRole: creatorRole,
        creatorAuthUserId: creatorAuthUserId,
        teamDirectory: teamDirectory!,
        onConsultantChanged: guardedBufferValue(
          (value) => _setSingleParty(YorksV1ProjectPartyKind.consultant, value),
        ),
        onMainContractorChanged: guardedBufferValue(
          (value) =>
              _setSingleParty(YorksV1ProjectPartyKind.mainContractor, value),
        ),
        onAddSubcontractor: guardedAction(
          () => _addNamedParty(
            YorksV1ProjectPartyKind.subcontractor,
            _subcontractorController,
          ),
        ),
        onAddOtherContractor: guardedAction(
          () => _addNamedParty(
            YorksV1ProjectPartyKind.otherContractor,
            _otherContractorController,
          ),
        ),
        onRemoveParty: guardedValue(_removePartyAt),
        onUndoPartyRemoval: guardedNullableAction(
          _removedParty == null ? null : _undoPartyRemoval,
        ),
        onAddInitialMember: guardedPair(_addInitialMember),
        onRemoveInitialMember: guardedValue(_removeInitialMemberAt),
        showTeam: !_isEditing,
        editItem: widget.editItem,
        onManageAccess: guardedNullableAction(
          _isEditing
              ? () => context.go(
                  RoutePaths.yorksV1ProjectPath(widget.editItem!.project.id),
                )
              : null,
        ),
      ),
      YorksV1ProjectCreationStage.buildings => _BuildingsStage(
        draft: draft,
        language: language,
        codeController: _buildingCodeController,
        focusNodes: _fieldFocusNodes,
        nameController: _buildingNameController,
        floorsController: _buildingFloorsController,
        deliveryAddressController: _buildingDeliveryAddressController,
        hasFrpRoom: _hasFrpRoom,
        editingBuildingIndex: _editingBuildingIndex,
        validationErrors: _validationErrors,
        onHasFrpRoomChanged: guardedBufferValue((value) {
          setState(() => _hasFrpRoom = value);
          _queueEditorState();
        }),
        onAddBuilding: guardedAction(_addBuilding),
        onEditBuilding: guardedValue(_editBuildingAt),
        onCancelEditing: guardedAction(_resetBuildingEditor),
        onDuplicateBuilding: guardedValue(_duplicateBuildingAt),
        onUndoRemove: guardedNullableAction(
          _buildingUndoRows == null && _removedBuilding == null
              ? null
              : _undoRemoveBuilding,
        ),
        onRemoveBuilding: guardedValue(_removeBuildingAt),
        onMoveBuilding: guardedPair(_moveBuilding),
      ),
      YorksV1ProjectCreationStage.attachments => _AttachmentsStage(
        draft: draft,
        language: language,
        validationErrors: _validationErrors,
        onAddAttachment: guardedFileAction(_addAttachment),
        onDroppedAttachments: (files) async {
          if (mayAct(fileRecovery: true)) {
            await _addSelectedAttachments(files);
          }
        },
        onDropError: () {
          if (mayAct(mutation: false)) _showInvalidAttachmentMessage();
        },
        onRemoveAttachment: guardedFileValue(_removeAttachmentAt),
        pendingFiles: _selectedAttachmentFiles,
        setupState: setupState,
        onRetryFile: guardedFileValue(_retrySetupFile),
        onChangeCategory: guardedPair(_setAttachmentCategory),
        onPreviewAttachment: guardedReadValue(_previewAttachment),
      ),
      YorksV1ProjectCreationStage.reviewAndCreate => _ReviewStage(
        draft: draft,
        pendingFiles: _selectedAttachmentFiles,
        language: language,
        validationErrors: _validationErrors,
        teamDirectory: teamDirectory!,
        onRetryDirectory: guardedReadAction(
          () => ref.invalidate(yorksV1ActiveProjectTeamDirectoryProvider),
        ),
        creatorRole: creatorRole,
        creatorAuthUserId: creatorAuthUserId,
        editItem: widget.editItem,
        onResolveConflict: guardedAction(_reviewEditConflict),
        onEdit: guardedValue(_selectStage),
      ),
    };

    return KeyedSubtree(
      key: ValueKey(
        'project-setup-stage-${draft.ownerAuthUserId}|${draft.backendIdentity}|${draft.draftId}|${stage.name}',
      ),
      child: _ProjectSetupReadOnlyScope(
        readOnly:
            !_draftController(draft.ownerAuthUserId).writable ||
            !_resumeEntryReady ||
            _checkingOwnership ||
            _ownershipCheckFailed ||
            _isCreating ||
            (_isEditing && !_editReady) ||
            ((setupState.operation?.coreSucceeded == true ||
                    setupState.outcomeUncertain) &&
                stage != YorksV1ProjectCreationStage.attachments),
        child: stageBody,
      ),
    );
  }

  void _synchronizeControllers(YorksV1ProjectCreationDraft draft) {
    _synchronizingEditor = true;
    _setControllerText(
      _startDateController,
      draft.rawEditorState['dateStartText'] as String? ??
          _typedDateText(draft.startDate),
    );
    _setControllerText(
      _endDateController,
      draft.rawEditorState['dateEndText'] as String? ??
          _typedDateText(draft.endDate),
    );
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
      _clientContactNameController,
      draft.clientContactName ?? '',
    );
    _setControllerText(
      _clientContactPhoneController,
      draft.clientContactPhone ?? '',
    );
    _setControllerText(
      _clientContactEmailController,
      draft.clientContactEmail ?? '',
    );
    _setControllerText(_clientAddressController, draft.clientAddress ?? '');
    _setControllerText(
      _consultantController,
      _partyFor(draft, YorksV1ProjectPartyKind.consultant)?.name ?? '',
    );
    _setControllerText(
      _mainContractorController,
      _partyFor(draft, YorksV1ProjectPartyKind.mainContractor)?.name ?? '',
    );
    _synchronizingEditor = false;
  }

  void _restoreRawEditor(YorksV1ProjectCreationDraft draft) {
    if (_restoredEditor ||
        (_isEditing && draft.mode != YorksV1ProjectDraftMode.edit)) {
      return;
    }
    _restoredEditor = true;
    _synchronizingEditor = true;
    final raw = draft.rawEditorState;
    _setControllerText(
      _subcontractorController,
      raw['subcontractorText'] as String? ?? '',
    );
    _setControllerText(
      _otherContractorController,
      raw['otherContractorText'] as String? ?? '',
    );
    _setControllerText(
      _buildingCodeController,
      raw['buildingCode'] as String? ?? '',
    );
    _setControllerText(
      _buildingNameController,
      raw['buildingName'] as String? ?? '',
    );
    _setControllerText(
      _buildingFloorsController,
      raw['buildingFloors'] as String? ?? '',
    );
    _setControllerText(
      _buildingDeliveryAddressController,
      raw['buildingAddress'] as String? ?? '',
    );
    _hasFrpRoom = raw['buildingFrp'] == true;
    final editingId = raw['buildingLocalId'] as String?;
    final editing = draft.buildings.indexWhere(
      (building) =>
          editingId != null &&
          (building.localRowId == editingId ||
              building.sourceScopeId == editingId),
    );
    _editingBuildingIndex = editing >= 0 ? editing : null;
    _synchronizingEditor = false;
  }

  Map<String, dynamic> _rawEditorState(YorksV1ProjectCreationDraft draft) => {
    ...draft.rawEditorState,
    'sectionContext': _savedSectionContext(draft),
    'dateStartText': _startDateController.text,
    'dateEndText': _endDateController.text,
    'subcontractorText': _subcontractorController.text,
    'otherContractorText': _otherContractorController.text,
    'buildingCode': _buildingCodeController.text,
    'buildingName': _buildingNameController.text,
    'buildingFloors': _buildingFloorsController.text,
    'buildingAddress': _buildingDeliveryAddressController.text,
    'buildingFrp': _hasFrpRoom,
    'buildingLocalId':
        _editingBuildingIndex == null ||
            _editingBuildingIndex! >= draft.buildings.length
        ? null
        : draft.buildings[_editingBuildingIndex!].localRowId ??
              draft.buildings[_editingBuildingIndex!].sourceScopeId,
  };

  Map<String, dynamic> _savedSectionContext(YorksV1ProjectCreationDraft draft) {
    final saved = Map<String, dynamic>.from(
      (draft.rawEditorState['sectionContext'] as Map?) ?? const {},
    );
    if (draft.currentStage != _renderedStage) return saved;
    final existing = Map<String, dynamic>.from(
      (saved[draft.currentStage.name] as Map?) ?? const {},
    );
    saved[draft.currentStage.name] = {
      ...existing,
      'scroll': _scrollController.hasClients
          ? _scrollController.offset
          : (existing['scroll'] ?? 0),
      'focusedField': _lastFocusedField ?? existing['focusedField'],
    };
    return saved;
  }

  void _queueNavigationContext() {
    if (!_resumeEntryReady ||
        _completedOperation?.cleanupComplete == true ||
        _restoringNavigation ||
        _synchronizingEditor ||
        _activeAuthUserId == null ||
        !_isCurrentContext(_contextGeneration)) {
      return;
    }
    _queueDraft(
      (draft) => draft.copyWith(rawEditorState: _rawEditorState(draft)),
      semanticEdit: false,
    );
  }

  void _restoreSectionContext(YorksV1ProjectCreationDraft draft) {
    if (_restoredNavigationStage == draft.currentStage ||
        draft.storageState == YorksV1ProjectDraftStorageState.initializing) {
      return;
    }
    final generation = _contextGeneration;
    final stage = draft.currentStage;
    _restoredNavigationStage = stage;
    _restoringNavigation = true;
    final contextState =
        ((draft.rawEditorState['sectionContext'] as Map?)?[stage.name]
            as Map?) ??
        const {};
    final offset = (contextState['scroll'] as num?)?.toDouble() ?? 0;
    final focusedField = contextState['focusedField'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentContext(generation) ||
          _currentDraft().currentStage != stage) {
        return;
      }
      _restoringNavigation = true;
      _lastFocusedField = focusedField;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
      _fieldFocusNodes[focusedField]?.requestFocus();
      Future.microtask(() {
        if (_isCurrentContext(generation)) _restoringNavigation = false;
      });
    });
  }

  YorksV1ProjectCreationDraft _withLocalRowIds(
    YorksV1ProjectCreationDraft draft,
  ) => draft.copyWith(
    parties: [
      for (final party in draft.parties)
        if (party.retainedFields['local_row_id'] != null)
          party
        else
          YorksV1ProjectPartyInput(
            kind: party.kind,
            name: party.name,
            contactName: party.contactName,
            contactPhone: party.contactPhone,
            contactEmail: party.contactEmail,
            address: party.address,
            retainedFields: {
              ...party.retainedFields,
              'local_row_id': const Uuid().v4(),
            },
          ),
    ],
    buildings: [
      for (final building in draft.buildings)
        if (building.localRowId != null)
          building
        else
          building.copyWith(localRowId: const Uuid().v4()),
    ],
  );
  void _queueEditorState() {
    if (!_resumeEntryReady ||
        _synchronizingEditor ||
        _activeAuthUserId == null) {
      return;
    }
    _queueDraft(
      (draft) => draft.copyWith(rawEditorState: _rawEditorState(draft)),
    );
  }

  void _typedDateChanged(bool start) {
    if (_synchronizingEditor || _activeAuthUserId == null) return;
    final text = (start ? _startDateController : _endDateController).text;
    final parsed = _parseTypedDate(text);
    _queueDraft(
      (draft) =>
          (start
                  ? draft.copyWith(startDate: parsed)
                  : draft.copyWith(endDate: parsed))
              .copyWith(rawEditorState: _rawEditorState(draft)),
    );
  }

  bool get _hasInvalidTypedDates => [
    _startDateController.text,
    _endDateController.text,
  ].any((text) => text.trim().isNotEmpty && _parseTypedDate(text) == null);
  bool get _hasUnappliedBuildingEditor =>
      _buildingNameController.text.trim().isNotEmpty ||
      _buildingCodeController.text.trim().isNotEmpty ||
      _buildingFloorsController.text.trim().isNotEmpty ||
      _buildingDeliveryAddressController.text.trim().isNotEmpty ||
      _hasFrpRoom;
  bool get _hasUnappliedPartyEditor =>
      _subcontractorController.text.trim().isNotEmpty ||
      _otherContractorController.text.trim().isNotEmpty;
  void _clientContactsChanged(String _) => _queueDraft(
    (draft) => draft.copyWith(
      clientContactName: _clientContactNameController.text,
      clientContactPhone: _clientContactPhoneController.text,
      clientContactEmail: _clientContactEmailController.text,
      clientAddress: _clientAddressController.text,
    ),
  );

  Future<void> _reviewRecoveredDraft() async {
    final generation = _contextGeneration;
    final owner = _activeAuthUserId;
    if (owner == null) return;
    final controller = _draftController(owner);
    final proposal = controller.readQuarantinedProposal();
    final language = ref.read(languageProvider);
    if (proposal == null) {
      _showMessage(YorksV1ProjectStrings.localRecoveryUnavailable, error: true);
      return;
    }
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          YorksV1ProjectStrings.reviewRecoveredDraft.active(language),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(proposal.reference, style: AppTypography.titleMedium),
              Text(proposal.name),
              const SizedBox(height: 12),
              Text(
                '${YorksV1ProjectStrings.buildings.active(language)}: ${proposal.buildings.length}',
              ),
              Text(
                '${YorksV1ProjectStrings.attachments.active(language)}: ${proposal.attachments.length}',
              ),
              const SizedBox(height: 12),
              Text(YorksV1ProjectStrings.draftNeedsRecovery.active(language)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(YorksV1ProjectStrings.back.active(language)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              YorksV1ProjectStrings.restoreForThisBackend.active(language),
            ),
          ),
        ],
      ),
    );
    if (restore != true || !_isCurrentContext(generation)) return;
    await controller.adoptQuarantinedProposal();
    if (_isCurrentContext(generation)) {
      ref.invalidate(yorksV1ProjectSelectedDraftUsesLegacyProvider);
      setState(() {
        _restoredEditor = false;
      });
    }
  }

  Future<void> _reviewEditConflict() async {
    final generation = _contextGeneration;
    if (!_isEditing) return;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final proposal = _currentDraft();
    final portfolio = await ref.read(yorksV1ProjectPortfolioProvider.future);
    if (!_isCurrentContext(generation)) return;
    final latest = portfolio
        .where((item) => item.project.id == proposal.projectId)
        .firstOrNull;
    if (latest == null || !mounted) return;
    if (latest.project.version == proposal.baseVersion) {
      ref.invalidate(yorksV1ProjectPortfolioProvider);
      return;
    }
    final current = _projectItemDraft(latest, proposal.ownerAuthUserId);
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ProjectConflictReviewDialog(
        base: proposal.baseSnapshot,
        current: current.toJson(),
        proposal: proposal.toJson(),
        language: ref.read(languageProvider),
      ),
    );
    if (selected == null || !_isCurrentContext(generation)) return;
    final rebased = YorksV1ProjectCreationDraft.fromJson({
      ...proposal.toJson(),
      ...selected,
      'baseVersion': latest.project.version,
      'baseSnapshot': current.toJson(),
      'creationIdempotencyKey': const Uuid().v4(),
    });
    // This is a deliberately reviewed local proposal. The eventual server
    // command still compares its new base version at transaction commit.
    _synchronizingEditor = true;
    _setControllerText(_startDateController, _typedDateText(rebased.startDate));
    _setControllerText(_endDateController, _typedDateText(rebased.endDate));
    _synchronizingEditor = false;
    await _saveDraft(
      rebased.copyWith(
        rawEditorState: {
          ...rebased.rawEditorState,
          'dateStartText': _typedDateText(rebased.startDate),
          'dateEndText': _typedDateText(rebased.endDate),
        },
      ),
    );
    if (_isCurrentContext(generation)) {
      setState(() {
        _restoredEditor = false;
      });
    }
  }

  void _setAttachmentCategory(
    int index,
    YorksV1ProjectAttachmentCategory category,
  ) {
    _queueDraft((draft) {
      if (index < 0 || index >= draft.attachments.length) return draft;
      final operation = ref.read(_coordinatorProvider(draft)).operation;
      if (operation != null &&
          (operation.coreSucceeded || operation.hasUnresolvedCommand)) {
        return draft;
      }
      return draft.copyWith(
        attachments: [
          for (var row = 0; row < draft.attachments.length; row++)
            row == index
                ? draft.attachments[row].copyWith(
                    categoryKey: category.wireValue,
                  )
                : draft.attachments[row],
        ],
      );
    });
  }

  Future<void> _previewAttachment(
    YorksV1ProjectAttachmentInput attachment,
  ) async {
    final generation = _contextGeneration;
    final owner = _activeAuthUserId;
    if (owner == null ||
        !_draftController(owner).writable ||
        _checkingOwnership ||
        _ownershipCheckFailed) {
      return;
    }
    final backend = ref.read(yorksV1ProjectDraftBackendIdentityProvider);
    bool hasAccess(WidgetRef reader) {
      final role = reader.read(yorksV1CurrentRoleProvider);
      return reader.read(yorksV1AuthUserIdProvider) == owner &&
          reader.read(yorksV1ProjectDraftBackendIdentityProvider) == backend &&
          yorksV1FeatureActionAccess(
            reader.read(yorksV1CurrentPermissionSnapshotProvider),
            _isEditing
                ? YorksV1CapabilityKeys.projectsEdit
                : YorksV1CapabilityKeys.projectsCreate,
            legacyAllowed: role?.canCreateProject == true,
            projectId: widget.editItem?.project.id,
          ).canWrite;
    }

    if (!hasAccess(ref)) return;
    try {
      await _draftController(owner).verifyOwnership();
    } catch (_) {
      return;
    }
    if (!mounted || !_isCurrentContext(generation) || !hasAccess(ref)) return;
    final current = _currentDraft();
    final exact = current.attachments
        .where(
          (file) =>
              file.localId == attachment.localId &&
              file.fileName == attachment.fileName &&
              file.mimeType == attachment.mimeType &&
              file.sizeBytes == attachment.sizeBytes &&
              file.contentHash == attachment.contentHash,
        )
        .firstOrNull;
    if (exact == null) return;
    final selected = _selectedAttachmentFiles
        .where(
          (file) =>
              file.fileName == exact.fileName &&
              file.mimeType == exact.mimeType &&
              file.bytes.length == exact.sizeBytes &&
              exact.contentHash != null &&
              sha256.convert(file.bytes).toString() == exact.contentHash,
        )
        .firstOrNull;
    if (selected == null) {
      _showMessage(YorksV1ProjectStrings.fileReselect);
      return;
    }
    final fileService = ref.read(yorksV1DocumentFileServiceProvider);
    final language = ref.read(languageProvider);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, reader, _) {
          reader.watch(yorksV1AuthUserIdProvider);
          reader.watch(yorksV1ProjectDraftBackendIdentityProvider);
          reader.watch(yorksV1CurrentRoleProvider);
          reader.watch(yorksV1CurrentPermissionSnapshotProvider);
          if (!_isCurrentContext(generation) || !hasAccess(reader)) {
            return AlertDialog(
              content: Text(
                YorksV1ProjectStrings.noPermission.active(language),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    YorksV1ProjectSetupDesktopStrings.closePreview.active(
                      language,
                    ),
                  ),
                ),
              ],
            );
          }
          return YorksV1ProjectSetupAttachmentPreview(
            file: selected,
            language: language,
            onSave: () async {
              if (!_isCurrentContext(generation) || !hasAccess(ref)) return;
              try {
                await fileService.saveDocument(
                  bytes: selected.bytes,
                  fileName: selected.fileName,
                  mimeType: selected.mimeType,
                );
              } catch (_) {
                if (_isCurrentContext(generation) && hasAccess(ref)) {
                  _showMessage(
                    YorksV1ProjectStrings.errorFor(
                      YorksV1DomainErrorCode.unexpectedResponse,
                    ),
                    error: true,
                  );
                }
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _finishResolvedRecovery(
    YorksV1ProjectSetupCoordinator coordinator,
    String owner,
    int generation,
  ) async {
    await coordinator.captureKnownOutcome();
    if (!_isCurrentContext(generation)) return;
    final operation = coordinator.currentState.operation;
    if (operation == null ||
        !operation.coreSucceeded ||
        operation.filesPending ||
        operation.hasUnresolvedCommand ||
        coordinator.currentState.recoveryError != null) {
      return;
    }
    try {
      await coordinator.markCleanupComplete();
      if (!_isCurrentContext(generation)) return;
      setState(() => _completedOperation = coordinator.currentState.operation);
      final retired = await _draftController(
        owner,
      ).retireConfirmedOperation(_completedOperation!);
      if (!_isCurrentContext(generation)) return;
      if (retired) _resetRetiredDraftProvider(owner);
      _openConfirmedProject(operation.project!, operation: _completedOperation);
    } catch (_) {
      if (_isCurrentContext(generation)) {
        _showMessage(YorksV1ProjectStrings.projectSavedHousekeeping);
      }
    }
  }

  void _resetRetiredDraftProvider(String owner) {
    _draftSaveTimer?.cancel();
    _pendingDraft = null;
    if (_isEditing) {
      ref.invalidate(yorksV1ProjectEditDraftProvider(_editContext(owner)));
    } else if (widget.legacyRecovery) {
      ref.invalidate(
        ref.read(yorksV1ProjectLegacyRecoveryDraftSourceProvider(owner)),
      );
      ref.invalidate(yorksV1ProjectLegacyRecoveryDraftSourceProvider(owner));
      ref.invalidate(yorksV1ProjectLegacyRecoveryDraftProvider(owner));
      ref.invalidate(
        yorksV1ProjectLegacyRecoveryDraftControllerProvider(owner),
      );
    } else if (_usesOriginalCreationProvider(owner)) {
      ref.invalidate(yorksV1ProjectSetupCreationDraftProvider(owner));
      if (!widget.legacyRecovery) {
        ref.invalidate(
          yorksV1ProjectSelectedDraftUsesLegacyProvider(
            _creationContext(owner),
          ),
        );
      }
    } else {
      ref.invalidate(
        yorksV1ProjectSetupCreationDraftByIdProvider(_creationContext(owner)),
      );
    }
  }

  Future<void> _retrySetupFile(YorksV1ProjectSetupFile file) async {
    final generation = _contextGeneration;
    final draft = _currentDraft();
    final bytes = _selectedAttachmentFiles
        .where(
          (selected) =>
              selected.fileName == file.fileName &&
              selected.mimeType == file.mimeType &&
              selected.bytes.length == file.sizeBytes &&
              (file.contentHash == null ||
                  sha256.convert(selected.bytes).toString() ==
                      file.contentHash),
        )
        .firstOrNull;
    if (bytes == null) {
      await _setStage(YorksV1ProjectCreationStage.attachments);
      if (!_isCurrentContext(generation)) return;
      await _addAttachment();
      return;
    }
    try {
      final coordinator = ref.read(_coordinatorProvider(draft).notifier);
      await coordinator.uploadFile(
        localId: file.localId,
        bytes: bytes.bytes,
        documents: ref.read(yorksV1DocumentsRepositoryProvider),
      );
      if (!_isCurrentContext(generation)) return;
      await _finishResolvedRecovery(
        coordinator,
        draft.ownerAuthUserId,
        generation,
      );
    } catch (_) {
      if (!_isCurrentContext(generation)) return;
      _showMessage(YorksV1ProjectStrings.projectSavedFilesPending);
    }
  }

  Future<void> _removePendingSetupFile(YorksV1ProjectSetupFile file) async {
    final generation = _contextGeneration;
    final draft = _currentDraft();
    final coordinator = ref.read(_coordinatorProvider(draft).notifier);
    try {
      await coordinator.removePendingFile(file.localId);
      if (!_isCurrentContext(generation)) return;
      final index = _currentDraft().attachments.indexWhere(
        (attachment) =>
            attachment.localId == file.localId ||
            (attachment.localId == null &&
                attachment.fileName == file.fileName &&
                attachment.contentHash == file.contentHash),
      );
      if (index >= 0) await _removeAttachmentAt(index);
      if (!_isCurrentContext(generation)) return;
      await _finishResolvedRecovery(
        coordinator,
        draft.ownerAuthUserId,
        generation,
      );
    } catch (_) {
      if (_isCurrentContext(generation)) {
        _showMessage(
          YorksV1ProjectStrings.localRecoveryUnavailable,
          error: true,
        );
      }
    }
  }

  void _useToday(bool start) {
    (start ? _startDateController : _endDateController).text = _typedDateText(
      DateTime.now(),
    );
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  YorksV1ProjectCreationDraft _currentDraft({bool includePending = true}) {
    if (_isEditing) {
      if (includePending && _pendingDraft != null) return _pendingDraft!;
      final owner = _activeAuthUserId;
      if (owner != null) {
        final stored = ref.read(
          yorksV1ProjectEditDraftProvider(_editContext(owner)),
        );
        if (stored.baseVersion != null) return stored;
      }
      if (_editDraft != null) return _editDraft!;
    }
    final authUserId = _activeAuthUserId;
    if (authUserId == null) {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.unauthenticated,
      );
    }
    return (includePending ? _pendingDraft : null) ??
        (widget.legacyRecovery
            ? ref.read(yorksV1ProjectLegacyRecoveryDraftProvider(authUserId))
            : _usesOriginalCreationProvider(authUserId)
            ? ref.read(yorksV1ProjectSetupCreationDraftProvider(authUserId))
            : ref.read(
                yorksV1ProjectSetupCreationDraftByIdProvider(
                  _creationContext(authUserId),
                ),
              ));
  }

  void _queueDraft(
    YorksV1ProjectCreationDraft Function(YorksV1ProjectCreationDraft current)
    transform, {
    bool semanticEdit = true,
  }) {
    if (_activeAuthUserId == null || !_resumeEntryReady) return;
    if (!_draftController(_activeAuthUserId!).writable ||
        _currentDraft().isReadOnly ||
        _currentDraft().storageState ==
            YorksV1ProjectDraftStorageState.initializing ||
        _checkingOwnership ||
        _ownershipCheckFailed) {
      return;
    }
    final current = _currentDraft();
    final next = transform(current);
    _pendingDraft = next;
    // Controller listeners also report selection/composition/focus updates.
    // Only changed recoverable input invalidates an explicit save; a cursor
    // move in a hydrated date or unfinished editor is not a content edit.
    if (semanticEdit &&
        _localInputIdentity(current) != _localInputIdentity(next)) {
      _leaveAuthorizedGeneration = null;
      _manuallySavedInput = null;
    }
    if (mounted) setState(() {});
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_flushPendingDraft());
    });
  }

  Future<void> _flushPendingDraft() async {
    final generation = _contextGeneration;
    _draftSaveTimer?.cancel();
    final pending = _pendingDraft;
    final owner = _activeAuthUserId;
    if (pending == null || owner == null) return;
    _pendingDraft = null;
    try {
      await _draftController(owner).save(pending);
    } catch (_) {
      if (_isCurrentContext(generation)) {
        setState(() {
          // A fenced writer may be rejected before the controller records
          // this frontend buffer. Keep it visible without replacing newer
          // input or granting the stale snapshot a different writer epoch.
          _pendingDraft ??= pending;
        });
      }
    }
  }

  Future<bool> _prepareLeave() async {
    final generation = _contextGeneration;
    final owner = _activeAuthUserId;
    if (owner == null) return true;
    // No editable fields have been hydrated while Resume acquisition waits.
    // Leaving this gate must not checkpoint empty controls into the proposal.
    if (!_resumeEntryReady) return true;
    if (_leaveAuthorizedGeneration == generation) {
      _leaveAuthorizedGeneration = null;
      return true;
    }
    if (_confirmedContextResult ||
        ref
                .read(_coordinatorProvider(_currentDraft()))
                .operation
                ?.coreSucceeded ==
            true) {
      return true;
    }
    final controller = _draftController(owner);
    _queueNavigationContext();
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return true;
    final draft = _currentDraft();
    if (draft.isReadOnly || !_hasMeaningfulSetupInput(draft)) return true;
    try {
      await controller.flush(saveTrigger: 'navigation');
      if (!_isCurrentContext(generation)) return true;
      final saved = _currentDraft();
      if (saved.isAcknowledged && _pendingDraft == null) {
        // Explicit Save draft is already a deliberate acknowledgement of the
        // recoverable input. Navigation/focus checkpoints may advance its
        // storage revision without changing that input. New edits still ask.
        if (_manuallySavedInput == _localInputIdentity(saved)) return true;
        final language = ref.read(languageProvider);
        if (!mounted) return true;
        _leaveDecision ??= showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(YorksV1ProjectStrings.leaveSetupTitle.active(language)),
            content: Text(
              YorksV1ProjectStrings.leaveSavedDraftHelp.active(language),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(YorksV1ProjectStrings.keepWorking.active(language)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  YorksV1ProjectStrings.leaveWithSavedDraft.active(language),
                ),
              ),
            ],
          ),
        );
        final decision = await _leaveDecision;
        if (!_isCurrentContext(generation)) return true;
        _leaveDecision = null;
        if (decision != true) return false;
        _leaveAuthorizedGeneration = generation;
        return true;
      }
    } catch (_) {
      // Keep recoverable editor input visible until a local write succeeds.
    }
    if (_isCurrentContext(generation)) {
      _showMessage(YorksV1ProjectStrings.localSaveFailed, error: true);
    }
    return false;
  }

  bool _hasMeaningfulSetupInput(YorksV1ProjectCreationDraft draft) {
    final inputOnly = draft.copyWith(
      rawEditorState: {
        for (final entry in draft.rawEditorState.entries)
          if (!const {
            'sectionContext',
            'contactsExpanded',
            'buildingLocalId',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );
    if (!inputOnly.hasRecoverableContent) return false;
    if (_isEditing &&
        draft.baseSnapshot.isNotEmpty &&
        !_hasInvalidTypedDates &&
        !_hasUnappliedBuildingEditor &&
        !_hasUnappliedPartyEditor) {
      final before = YorksV1ProjectCreationDraft.fromJson(
        draft.baseSnapshot,
      ).toCreationInput().toRpcPayload();
      final after = draft.toCreationInput().toRpcPayload();
      return yorksV1CanonicalSetupJson(before) !=
          yorksV1CanonicalSetupJson(after);
    }
    return true;
  }

  String _localInputIdentity(YorksV1ProjectCreationDraft draft) {
    final json = draft.toJson();
    for (final key in const {
      'revision',
      'acknowledgedRevision',
      'writerEpoch',
      'updatedAt',
      'currentStage',
      'visitedStages',
    }) {
      json.remove(key);
    }
    json['rawEditorState'] = {
      for (final entry in draft.rawEditorState.entries)
        if (!const {
          'sectionContext',
          'contactsExpanded',
          'buildingLocalId',
        }.contains(entry.key))
          entry.key: entry.value,
    };
    return yorksV1CanonicalSetupJson(json);
  }

  Future<void> _saveDraft(
    YorksV1ProjectCreationDraft draft, {
    bool manual = false,
  }) async {
    if (manual && _manualSavePending) return;
    final generation = _contextGeneration;
    final owner = _activeAuthUserId;
    if (owner == null ||
        draft.ownerAuthUserId != owner ||
        draft.projectId != widget.editItem?.project.id ||
        !_isCurrentContext(generation)) {
      return;
    }
    _draftSaveTimer?.cancel();
    _pendingDraft = null;
    _leaveAuthorizedGeneration = null;
    if (manual) {
      setState(() {
        _manualSavePending = true;
        _manuallySavedInput = null;
      });
    }
    YorksV1ProjectCreationDraft? snapshot;
    try {
      final stableDraft = _withLocalRowIds(draft);
      snapshot = stableDraft.copyWith(
        rawEditorState: _rawEditorState(stableDraft),
      );
      final controller = _draftController(owner);
      await controller.save(
        snapshot,
        saveTrigger: manual ? 'manual' : 'checkpoint',
      );
      if (!manual || !_isCurrentContext(generation)) return;
      await controller.flush(saveTrigger: 'manual');
      if (!_isCurrentContext(generation)) return;
      final saved = _currentDraft(includePending: false);
      final current = _currentDraft();
      final savedInput = _localInputIdentity(saved);
      final snapshotInput = _localInputIdentity(snapshot);
      if (saved.isAcknowledged &&
          savedInput == snapshotInput &&
          _localInputIdentity(current) == snapshotInput) {
        // Scroll/focus checkpoints can be queued while the save completes.
        // They do not change the acknowledged input; pending typed content
        // still has to match that exact input before acknowledging this Save.
        _manuallySavedInput = savedInput;
        _showMessage(
          _isEditing
              ? YorksV1ProjectStrings.editSavedLocally
              : YorksV1ProjectStrings.draftSaved,
        );
      } else {
        _showMessage(YorksV1ProjectStrings.changedDuringLocalSave);
      }
    } catch (_) {
      if (_isCurrentContext(generation)) {
        setState(() {
          _pendingDraft ??= snapshot ?? draft;
        });
        if (manual) {
          _showMessage(YorksV1ProjectStrings.localSaveFailed, error: true);
        }
      }
    } finally {
      if (manual && _isCurrentContext(generation)) {
        setState(() => _manualSavePending = false);
      }
    }
  }

  Future<void> _selectStage(YorksV1ProjectCreationStage target) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    if (!_isEditing && !_visitedStages.contains(target)) return;
    await _setStage(target);
  }

  Future<void> _setStage(YorksV1ProjectCreationStage stage) async {
    final generation = _contextGeneration;
    final owner = _activeAuthUserId;
    if (owner == null) return;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final previous = _currentDraft().currentStage;
    _visitedStages.add(stage);
    if (stage != previous) {
      try {
        ref
            .read(analyticsServiceProvider)
            .capture(
              AnalyticsEvent.projectSetupStepViewed,
              properties: {
                AnalyticsProperty.mode: _isEditing ? 'edit' : 'create',
                AnalyticsProperty.step: switch (stage) {
                  YorksV1ProjectCreationStage.projectDetails =>
                    'project_details',
                  YorksV1ProjectCreationStage.partiesAndAccess =>
                    'parties_and_access',
                  YorksV1ProjectCreationStage.buildings => 'buildings',
                  YorksV1ProjectCreationStage.attachments => 'attachments',
                  YorksV1ProjectCreationStage.reviewAndCreate => 'review',
                },
                AnalyticsProperty.entryPoint: 'navigation',
              },
            );
      } catch (_) {
        // Analytics cannot prevent a local step checkpoint.
      }
    }
    final current = _currentDraft();
    await _saveDraft(
      current.copyWith(
        currentStage: stage,
        visitedStages: _visitedStages,
        rawEditorState: _rawEditorState(current),
      ),
    );
    if (!_isCurrentContext(generation)) return;
    setState(() => _validationErrors = const {});
  }

  Future<void> _continue() async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final draft = _currentDraft();
    if ((draft.currentStage == YorksV1ProjectCreationStage.buildings &&
            _hasUnappliedBuildingEditor) ||
        (draft.currentStage == YorksV1ProjectCreationStage.partiesAndAccess &&
            _hasUnappliedPartyEditor)) {
      _showMessage(YorksV1ProjectStrings.unappliedInput);
      return;
    }
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
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    await _setStage(YorksV1ProjectCreationStage.reviewAndCreate);
  }

  Future<void> _back() async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _currentDraft().currentStage;
    final previous = current.previous;
    if (previous == null) {
      final canLeave = await _prepareLeave();
      if (!_isCurrentContext(generation) || !canLeave) return;
      if (!mounted) return;
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
    if (errors.isNotEmpty) {
      final generation = _contextGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrentContext(generation)) {
          unawaited(_focusInvalidField(errors.first));
        }
      });
    }
  }

  Future<void> _focusInvalidField(YorksV1ProjectValidationCode error) async {
    final generation = _contextGeneration;
    final field = switch (error) {
      YorksV1ProjectValidationCode.missingProjectReference => 'reference',
      YorksV1ProjectValidationCode.missingProjectName => 'name',
      YorksV1ProjectValidationCode.invalidDateRange ||
      YorksV1ProjectValidationCode.unsupportedProjectDate => 'endDate',
      YorksV1ProjectValidationCode.duplicateBuildingCode => 'buildingCode',
      YorksV1ProjectValidationCode.missingBuilding ||
      YorksV1ProjectValidationCode.invalidBuilding => 'buildingName',
      _ => null,
    };
    final target = switch (field) {
      'reference' ||
      'name' ||
      'startDate' ||
      'endDate' => YorksV1ProjectCreationStage.projectDetails,
      'buildingCode' || 'buildingName' => YorksV1ProjectCreationStage.buildings,
      _ => _firstInvalidStage({error}),
    };
    if (_currentDraft().currentStage != target) await _setStage(target);
    if (!_isCurrentContext(generation)) return;
    if (error == YorksV1ProjectValidationCode.duplicateBuildingCode) {
      final buildings = _currentDraft().buildings;
      final codes = <String>{};
      final duplicate = buildings.indexWhere(
        (building) => !codes.add(building.normalizedCode),
      );
      if (duplicate >= 0) await _editBuildingAt(duplicate);
    }
    if (!_isCurrentContext(generation)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentContext(generation)) return;
      final node = _fieldFocusNodes[field];
      node?.requestFocus();
      final fieldContext = node?.context;
      if (fieldContext != null) {
        unawaited(Scrollable.ensureVisible(fieldContext, alignment: .2));
      }
    });
  }

  TranslatableString _validationTargetLabel(
    YorksV1ProjectValidationCode error,
  ) => switch (error) {
    YorksV1ProjectValidationCode.missingProjectReference =>
      YorksV1ProjectStrings.yorksReference,
    YorksV1ProjectValidationCode.missingProjectName =>
      YorksV1ProjectStrings.projectName,
    YorksV1ProjectValidationCode.invalidDateRange ||
    YorksV1ProjectValidationCode.unsupportedProjectDate =>
      YorksV1ProjectStrings.endDate,
    YorksV1ProjectValidationCode.duplicateBuildingCode =>
      YorksV1ProjectStrings.buildingCode,
    YorksV1ProjectValidationCode.missingBuilding ||
    YorksV1ProjectValidationCode.invalidBuilding =>
      YorksV1ProjectStrings.buildingName,
    _ => _stageCopy(_firstInvalidStage({error})),
  };

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
    final featureBox = _featureScaffoldKey.currentContext?.findRenderObject();
    final availableWidth = featureBox is RenderBox && featureBox.hasSize
        ? featureBox.size.width
        : MediaQuery.sizeOf(context).width;
    // Leave the setup stage rail and sticky actions available while feedback
    // is visible. Use this nested Scaffold's actual content width rather than
    // the viewport, which also includes the persistent office sidebar.
    final sideMargin = ((availableWidth - 560) / 2).clamp(
      16.0,
      double.infinity,
    );
    (_featureMessengerKey.currentState ?? ScaffoldMessenger.of(context))
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 100),
          backgroundColor: error ? AppColors.error : null,
          content: Text(copy.active(ref.read(languageProvider))),
        ),
      );
  }

  Future<void> _selectDate({required bool isStartDate}) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
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
    if (!mounted) return;
    final date = await showDatePicker(
      context: context,
      initialDate: _clampDate(requestedInitial, firstDate, latest),
      firstDate: firstDate,
      lastDate: latest,
    );
    if (date == null || !_isCurrentContext(generation)) return;
    (isStartDate ? _startDateController : _endDateController).text =
        _typedDateText(date);
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
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
            retainedFields: existing?.retainedFields ?? const {},
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
    final generation = _contextGeneration;
    final name = controller.text.trim();
    if (name.isEmpty) {
      _showMessage(YorksV1ProjectStrings.requiredField, error: true);
      return;
    }
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _currentDraft();
    await _saveDraft(
      current.copyWith(
        parties: [
          ...current.parties,
          YorksV1ProjectPartyInput(kind: kind, name: name),
        ],
      ),
    );
    if (!_isCurrentContext(generation)) return;
    controller.clear();
  }

  Future<void> _removePartyAt(int index) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _withLocalRowIds(_currentDraft());
    if (index < 0 || index >= current.parties.length) return;
    _removedParty = current.parties[index];
    _removedPartyIndex = index;
    await _saveDraft(
      current.copyWith(
        parties: [
          for (var item = 0; item < current.parties.length; item++)
            if (item != index) current.parties[item],
        ],
      ),
    );
  }

  Future<void> _undoPartyRemoval() async {
    final generation = _contextGeneration;
    final removed = _removedParty;
    if (removed == null) return;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final draft = _currentDraft();
    final parties = [...draft.parties];
    parties.insert(
      (_removedPartyIndex ?? parties.length).clamp(0, parties.length),
      removed,
    );
    _removedParty = null;
    _removedPartyIndex = null;
    await _saveDraft(draft.copyWith(parties: parties));
    if (_isCurrentContext(generation)) setState(() {});
  }

  Future<void> _addInitialMember(
    YorksV1ProjectTeamDirectoryMember member,
    YorksV1ProjectMembershipRole projectRole,
  ) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
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
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
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
    final generation = _contextGeneration;
    final name = _buildingNameController.text.trim();
    if (name.isEmpty) {
      _showMessage(YorksV1ProjectStrings.requiredField, error: true);
      return;
    }
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _withLocalRowIds(_currentDraft());
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
      flags: existing?.flags ?? const {},
      retainedFields: existing?.retainedFields ?? const {},
      localRowId: existing?.localRowId ?? const Uuid().v4(),
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
    _buildingUndoRows = [...current.buildings];
    await _saveDraft(current.copyWith(buildings: buildings));
    if (!_isCurrentContext(generation)) return;
    setState(() {
      _editingBuildingIndex = null;
      _resetBuildingEditor();
    });
  }

  Future<void> _editBuildingAt(int index) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
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
    _queueEditorState();
  }

  Future<void> _duplicateBuildingAt(int index) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final draft = _currentDraft();
    if (index < 0 || index >= draft.buildings.length) return;
    setState(() {
      _editingBuildingIndex = null;
      _seedNextBuildingForm(draft.buildings[index], draft.buildings);
    });
    _queueEditorState();
  }

  Future<void> _undoRemoveBuilding() async {
    final generation = _contextGeneration;
    final removed = _removedBuilding;
    final priorRows = _buildingUndoRows;
    if (removed == null && priorRows == null) return;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final draft = _currentDraft();
    final selectedId = _editingBuildingIndex == null
        ? null
        : draft.buildings[_editingBuildingIndex!].localRowId;
    final buildings = priorRows == null ? [...draft.buildings] : [...priorRows];
    if (priorRows == null) {
      buildings.insert(
        (_removedBuildingIndex ?? buildings.length).clamp(0, buildings.length),
        removed!,
      );
    }
    _buildingUndoRows = null;
    _removedBuilding = null;
    _removedBuildingIndex = null;
    final selectedIndex = buildings.indexWhere(
      (building) => selectedId != null && building.localRowId == selectedId,
    );
    _editingBuildingIndex = selectedIndex < 0 ? null : selectedIndex;
    await _saveDraft(draft.copyWith(buildings: buildings));
    if (_isCurrentContext(generation)) {
      setState(() {
        _removedBuilding = null;
        _removedBuildingIndex = null;
      });
    }
  }

  Future<void> _moveBuilding(int index, int direction) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final draft = _withLocalRowIds(_currentDraft());
    final destination = index + direction;
    if (index < 0 ||
        index >= draft.buildings.length ||
        destination < 0 ||
        destination >= draft.buildings.length) {
      return;
    }
    final buildings = [...draft.buildings];
    final row = buildings.removeAt(index);
    buildings.insert(destination, row);
    _buildingUndoRows = [...draft.buildings];
    if (_editingBuildingIndex == index) {
      _editingBuildingIndex = destination;
    } else if (_editingBuildingIndex == destination) {
      _editingBuildingIndex = index;
    }
    await _saveDraft(draft.copyWith(buildings: buildings));
    if (_isCurrentContext(generation)) setState(() {});
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
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _withLocalRowIds(_currentDraft());
    if (index < 0 || index >= current.buildings.length) return;
    if (current.buildings[index].sourceScopeId != null) {
      _showMessage(
        YorksV1ProjectStrings.scopeRetirementRequiresReconciliation,
        error: true,
      );
      return;
    }
    _removedBuilding = current.buildings[index];
    _removedBuildingIndex = index;
    _buildingUndoRows = [...current.buildings];
    await _saveDraft(
      current.copyWith(
        buildings: [
          for (var item = 0; item < current.buildings.length; item++)
            if (item != index) current.buildings[item],
        ],
      ),
    );
    if (!_isCurrentContext(generation)) return;
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
    final generation = _contextGeneration;
    try {
      final selected = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (selected == null || !_isCurrentContext(generation)) return;
      await _addSelectedAttachments([selected]);
    } on YorksV1DomainException catch (error) {
      if (!_isCurrentContext(generation)) return;
      _showMessage(
        error.code == YorksV1DomainErrorCode.invalidInput
            ? YorksV1ProjectStrings.invalidAttachment
            : YorksV1ProjectStrings.errorFor(error.code),
        error: true,
      );
    } catch (_) {
      if (!_isCurrentContext(generation)) return;
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
    final generation = _contextGeneration;
    if (selectedFiles.isEmpty) return;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _currentDraft();
    final attachments = [...current.attachments];
    final pendingFiles = [..._selectedAttachmentFiles];
    var skippedDuplicate = false;
    for (final selected in selectedFiles) {
      final hash = sha256.convert(selected.bytes).toString();
      final operation = ref.read(_coordinatorProvider(current)).operation;
      if (operation != null &&
          (operation.coreSucceeded || operation.hasUnresolvedCommand)) {
        final matchesOriginal = operation.files.any(
          (file) =>
              file.fileName == selected.fileName &&
              file.mimeType == selected.mimeType &&
              file.sizeBytes == selected.bytes.length &&
              (file.contentHash == null || file.contentHash == hash),
        );
        if (!matchesOriginal) {
          _showMessage(YorksV1ProjectStrings.fileContentMismatch, error: true);
          continue;
        }
      }
      final hasBytes = pendingFiles.any(
        (file) =>
            file.fileName == selected.fileName &&
            file.mimeType == selected.mimeType &&
            sha256.convert(file.bytes).toString() == hash,
      );
      if (hasBytes) {
        skippedDuplicate = true;
        continue;
      }
      final index = attachments.indexWhere(
        (attachment) =>
            attachment.fileName == selected.fileName &&
            attachment.mimeType == selected.mimeType &&
            attachment.sizeBytes == selected.bytes.length &&
            (attachment.contentHash == null || attachment.contentHash == hash),
      );
      final existing = index < 0 ? null : attachments[index];
      final replacement =
          (existing ??
                  YorksV1ProjectAttachmentInput(
                    localId: const Uuid().v4(),
                    fileName: selected.fileName,
                    mimeType: selected.mimeType,
                    categoryKey:
                        YorksV1ProjectAttachmentCategory.general.wireValue,
                  ))
              .copyWith(
                fileName: selected.fileName,
                mimeType: selected.mimeType,
                sizeBytes: selected.bytes.length,
                contentHash: hash,
              );
      if (index < 0) {
        attachments.add(replacement);
      } else {
        attachments[index] = replacement;
      }
      pendingFiles.add(selected);
    }
    if (pendingFiles.length == _selectedAttachmentFiles.length) {
      _showMessage(YorksV1ProjectStrings.duplicateAttachment, error: true);
      return;
    }
    await _saveDraft(current.copyWith(attachments: attachments));
    if (!_isCurrentContext(generation)) return;
    setState(() => _selectedAttachmentFiles = pendingFiles);
    if (skippedDuplicate) {
      _showMessage(YorksV1ProjectStrings.duplicateAttachment, error: true);
    }
  }

  void _showInvalidAttachmentMessage() {
    _showMessage(YorksV1ProjectStrings.invalidAttachment, error: true);
  }

  Future<void> _removeAttachmentAt(int index) async {
    final generation = _contextGeneration;
    await _flushPendingDraft();
    if (!_isCurrentContext(generation)) return;
    final current = _currentDraft();
    if (index < 0 || index >= current.attachments.length) return;
    final removed = current.attachments[index];
    final operation = ref.read(_coordinatorProvider(current)).operation;
    if (operation?.hasUnresolvedCommand == true &&
        operation?.coreSucceeded != true) {
      _showMessage(
        YorksV1ProjectStrings.originalSubmissionPending,
        error: true,
      );
      return;
    }
    if (operation?.coreSucceeded == true) {
      final file = operation!.files
          .where(
            (file) =>
                file.localId == removed.localId ||
                (removed.localId == null &&
                    file.fileName == removed.fileName &&
                    file.contentHash == removed.contentHash),
          )
          .firstOrNull;
      if (file != null &&
          file.status != YorksV1ProjectSetupFileStatus.removed) {
        await _removePendingSetupFile(file);
        return;
      }
    }
    await _saveDraft(
      current.copyWith(
        attachments: [
          for (var item = 0; item < current.attachments.length; item++)
            if (item != index) current.attachments[item],
        ],
      ),
    );
    if (!_isCurrentContext(generation)) return;
    setState(() {
      _selectedAttachmentFiles = [
        for (final file in _selectedAttachmentFiles)
          if (!(file.fileName == removed.fileName &&
              file.mimeType == removed.mimeType &&
              file.bytes.length == removed.sizeBytes &&
              (removed.contentHash == null ||
                  sha256.convert(file.bytes).toString() ==
                      removed.contentHash)))
            file,
      ];
    });
  }

  StateNotifierProvider<
    YorksV1ProjectSetupCoordinator,
    YorksV1ProjectSetupState
  >
  _coordinatorProvider(YorksV1ProjectCreationDraft draft) =>
      widget.legacyRecovery
      ? yorksV1ProjectLegacyRecoveryCoordinatorProvider(_setupScope(draft))
      : yorksV1ProjectSetupCoordinatorProvider(_setupScope(draft));

  YorksV1ProjectSetupScope _setupScope(YorksV1ProjectCreationDraft draft) => (
    ownerAuthUserId: _activeAuthUserId!,
    draftId: draft.draftId,
    projectId: _isEditing ? widget.editItem!.project.id : null,
  );

  Future<void> _releaseConfirmedHistory(
    YorksV1ProjectCreationDraft draft,
    int generation,
  ) async {
    try {
      final controller = _draftController(draft.ownerAuthUserId);
      await controller.initialized;
      if (!_isCurrentContext(generation)) return;
      if (!controller.writable ||
          controller.currentDraftId != draft.draftId ||
          _checkingOwnership ||
          _ownershipCheckFailed) {
        setState(() => _releasingConfirmedHistory = false);
        return;
      }
      await controller.verifyOwnership();
      if (!_isCurrentContext(generation)) return;
      final coordinator = ref.read(_coordinatorProvider(draft).notifier);
      final operation = await coordinator.acknowledgeConfirmedCore();
      if (!_isCurrentContext(generation)) return;
      final retired = await controller.retireConfirmedOperation(operation);
      if (!_isCurrentContext(generation)) return;
      _draftSaveTimer?.cancel();
      _pendingDraft = null;
      if (retired) _resetRetiredDraftProvider(draft.ownerAuthUserId);
      ref.invalidate(_coordinatorProvider(draft));
      _confirmedContextResult = true;
      _openConfirmedProject(operation.project!, operation: operation);
    } catch (_) {
      if (!_isCurrentContext(generation)) return;
      setState(() {
        _releasingConfirmedHistory = false;
        _confirmedHistoryReleaseFailed = true;
      });
    }
  }

  Future<void> _retryConfirmedHistory() async {
    final generation = _contextGeneration;
    await _verifyResumedOwnership();
    if (!_isCurrentContext(generation)) return;
    setState(() {
      _releasingConfirmedHistory = false;
      _confirmedHistoryReleaseFailed = _ownershipCheckFailed;
    });
  }

  void _openConfirmedProject(
    YorksV1Project project, {
    YorksV1ProjectSetupOperation? operation,
  }) {
    final role = ref.read(yorksV1CurrentRoleProvider);
    final owner = _activeAuthUserId;
    final members = operation?.mode == YorksV1ProjectSetupMode.create
        ? YorksV1ProjectCreationResult.fromRpcJson(
            operation!.core.result!,
          ).members
        : widget.editItem?.activeMembers ?? const <YorksV1ProjectMember>[];
    final ownMembership = members.any(
      (member) =>
          member.memberAuthUserId == owner && member.isActiveAt(DateTime.now()),
    );
    final legacyReadable =
        role == YorksV1Role.admin ||
        role?.isGlobalProjectEngineer == true ||
        (role?.isEngineering == true && ownMembership);
    final access = yorksV1FeatureActionAccess(
      ref.read(yorksV1CurrentPermissionSnapshotProvider),
      YorksV1CapabilityKeys.projectsView,
      legacyAllowed: legacyReadable,
      projectId: project.id,
    );
    if (!access.isVisible) {
      context.go(RoutePaths.yorksV1Projects);
    } else if (_isEditing && widget.onProjectUpdated != null) {
      widget.onProjectUpdated!(project);
    } else if (!_isEditing && widget.onProjectCreated != null) {
      widget.onProjectCreated!(project);
    } else {
      context.go(RoutePaths.yorksV1ProjectPath(project.id));
    }
  }

  Future<void> _createProject() async {
    final generation = _contextGeneration;
    if (_isCreating || _activeAuthUserId == null) return;
    final owner = _activeAuthUserId!;
    final draftController = _draftController(owner);
    if (!draftController.writable || (_isEditing && !_editReady)) return;
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
    if (!_isCurrentContext(generation)) return;
    final draft = _currentDraft();
    final coordinator = ref.read(_coordinatorProvider(draft).notifier);
    final originalOperation = coordinator.currentState.operation;
    // Original unresolved/confirmed commands are recovered independently of
    // subsequently typed form values. Only a new reviewed intent is validated.
    if (originalOperation == null ||
        (!originalOperation.coreSucceeded &&
            !originalOperation.hasUnresolvedCommand)) {
      if (_isEditing && draft.baseSnapshot.isNotEmpty) {
        final before = YorksV1ProjectCreationDraft.fromJson(
          draft.baseSnapshot,
        ).toCreationInput().toRpcPayload()..remove('idempotency_key');
        final after = draft.toCreationInput().toRpcPayload()
          ..remove('idempotency_key');
        if (yorksV1CanonicalSetupJson(before) ==
                yorksV1CanonicalSetupJson(after) &&
            !_hasInvalidTypedDates &&
            !_hasUnappliedBuildingEditor &&
            !_hasUnappliedPartyEditor) {
          try {
            await draftController.retire(
              resultProjectId: widget.editItem!.project.id,
            );
          } catch (_) {
            if (_isCurrentContext(generation)) {
              _showMessage(YorksV1ProjectStrings.localSaveFailed, error: true);
            }
            return;
          }
          if (!_isCurrentContext(generation)) return;
          _confirmedContextResult = true;
          _resetRetiredDraftProvider(owner);
          _openConfirmedProject(widget.editItem!.project);
          return;
        }
      }
      if (_hasInvalidTypedDates) {
        _showMessage(YorksV1ProjectStrings.invalidTypedDate, error: true);
        await _setStage(YorksV1ProjectCreationStage.projectDetails);
        return;
      }
      if (_hasUnappliedBuildingEditor || _hasUnappliedPartyEditor) {
        _showMessage(YorksV1ProjectStrings.unappliedInput, error: true);
        await _setStage(
          _hasUnappliedBuildingEditor
              ? YorksV1ProjectCreationStage.buildings
              : YorksV1ProjectCreationStage.partiesAndAccess,
        );
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
        await _setStage(YorksV1ProjectCreationStage.partiesAndAccess);
        return;
      }
      final errors = draft.toCreationInput().validate();
      if (errors.isNotEmpty) {
        final targetStage = _firstInvalidStage(errors);
        if (targetStage != draft.currentStage) await _setStage(targetStage);
        if (!_isCurrentContext(generation)) return;
        _presentValidationErrors(errors);
        return;
      }
    }

    // Retirement can dispose the provider's original notifier. The durable
    // snapshot remains the known result if navigation/callbacks later fail.
    YorksV1ProjectSetupState outcome() {
      if (_completedOperation?.coreSucceeded == true) {
        return YorksV1ProjectSetupState(operation: _completedOperation);
      }
      return coordinator.currentState;
    }

    setState(() => _isCreating = true);
    try {
      if (originalOperation == null ||
          (!originalOperation.coreSucceeded &&
              !originalOperation.hasUnresolvedCommand)) {
        final files = _preparedFileManifest(draft);
        if (_isEditing) {
          await coordinator.prepareUpdate(
            YorksV1ProjectUpdateInput(
              idempotencyKey: draft.creationIdempotencyKey,
              projectId: widget.editItem!.project.id,
              expectedProjectVersion:
                  draft.baseVersion ?? widget.editItem!.project.recordVersion,
              project: draft.toCreationInput(),
            ),
            files: files,
          );
        } else {
          await coordinator.prepareCreate(
            draft.toCreationInput(),
            files: files,
          );
        }
      }
      if (!_isCurrentContext(generation)) return;
      var project = await coordinator.submitCore();
      if (!_isCurrentContext(generation)) return;
      _confirmedContextResult = true;
      final operation = coordinator.currentState.operation!;
      if (!_isEditing && project.state == YorksV1ProjectLifecycle.draft) {
        final result = YorksV1ProjectCreationResult.fromRpcJson(
          operation.core.result!,
        );
        final canActivate = result.members.any(
          (member) =>
              member.projectRole ==
                  YorksV1ProjectMembershipRole.projectEngineer &&
              member.effectiveTo == null,
        );
        if (canActivate) {
          try {
            project = await coordinator.activate();
            if (!_isCurrentContext(generation)) return;
          } catch (_) {
            // The committed Draft project stays known and can be opened. An
            // uncertain activation keeps its own original phase key/version.
            project = coordinator.currentState.project ?? project;
          }
        }
      }
      final failedFiles = await _uploadSelectedAttachments(coordinator);
      if (!_isCurrentContext(generation)) return;
      final latest = coordinator.currentState.operation!;
      var draftRetired = false;
      await coordinator.captureKnownOutcome();
      if (!_isCurrentContext(generation)) return;
      final confirmed = await coordinator.acknowledgeConfirmedCore();
      if (!_isCurrentContext(generation)) return;
      if (!latest.filesPending &&
          !latest.hasUnresolvedCommand &&
          coordinator.currentState.recoveryError == null) {
        try {
          await coordinator.markCleanupComplete();
        } catch (_) {
          if (_isCurrentContext(generation)) {
            _showMessage(YorksV1ProjectStrings.projectSavedHousekeeping);
          }
        }
      }
      // Pending activation/uploads retain their original keys in the project
      // recovery catalogue. They must not occupy the next creation proposal.
      draftRetired = await draftController.retireConfirmedOperation(
        coordinator.currentState.operation ?? confirmed,
      );
      ref.invalidate(yorksV1ProjectPortfolioProvider);
      if (!_isCurrentContext(generation)) return;
      setState(() {
        _completedOperation = coordinator.currentState.operation;
        _isCreating = false;
      });
      if (failedFiles > 0) {
        _showMessage(YorksV1ProjectStrings.projectSavedFilesPending);
      } else if (project.state == YorksV1ProjectLifecycle.draft &&
          !_isEditing) {
        _showMessage(YorksV1ProjectStrings.projectCreatedDraft);
      }
      final completedOperation = coordinator.currentState.operation;
      if (draftRetired) _resetRetiredDraftProvider(draft.ownerAuthUserId);
      ref.invalidate(_coordinatorProvider(draft));
      _openConfirmedProject(project, operation: completedOperation);
      unawaited(
        ref
            .read(yorksV1CurrentPermissionSnapshotProvider.notifier)
            .refresh(authorityMayHaveChanged: true),
      );
    } on YorksV1ProjectSetupRecoveryException catch (error) {
      if (!_isCurrentContext(generation)) return;
      setState(() => _isCreating = false);
      _showMessage(_setupRecoveryMessage(error.code), error: true);
    } on YorksV1DomainException catch (error) {
      if (!_isCurrentContext(generation)) return;
      setState(() => _isCreating = false);
      if (outcome().operation?.coreSucceeded == true) {
        _showMessage(YorksV1ProjectStrings.projectSavedHousekeeping);
      } else if (outcome().outcomeUncertain) {
        _showMessage(
          YorksV1ProjectStrings.commandOutcomeUncertain,
          error: true,
        );
      } else {
        _showMessage(YorksV1ProjectStrings.errorFor(error.code), error: true);
      }
    } catch (_) {
      if (!_isCurrentContext(generation)) return;
      setState(() => _isCreating = false);
      _showMessage(
        outcome().operation?.coreSucceeded == true
            ? YorksV1ProjectStrings.projectSavedHousekeeping
            : outcome().outcomeUncertain
            ? YorksV1ProjectStrings.commandOutcomeUncertain
            : YorksV1ProjectStrings.journalUnavailable,
        error: outcome().operation?.coreSucceeded != true,
      );
    }
  }

  TranslatableString _setupRecoveryMessage(
    YorksV1ProjectSetupRecoveryError code,
  ) => switch (code) {
    YorksV1ProjectSetupRecoveryError.changedUnresolvedIntent =>
      YorksV1ProjectStrings.originalSubmissionPending,
    YorksV1ProjectSetupRecoveryError.fileMismatch =>
      YorksV1ProjectStrings.fileContentMismatch,
    YorksV1ProjectSetupRecoveryError.retryLimit =>
      YorksV1ProjectStrings.commandRetryLimit,
    YorksV1ProjectSetupRecoveryError.recoveryBlocked =>
      YorksV1ProjectStrings.localRecoveryUnavailable,
    YorksV1ProjectSetupRecoveryError.journalUnavailable =>
      YorksV1ProjectStrings.journalUnavailable,
  };

  List<YorksV1ProjectSetupFile> _preparedFileManifest(
    YorksV1ProjectCreationDraft draft,
  ) => [
    for (final attachment in draft.attachments)
      YorksV1ProjectSetupFile(
        localId: attachment.localId ?? const Uuid().v4(),
        idempotencyKey: const Uuid().v4(),
        fileName: attachment.fileName,
        mimeType: attachment.mimeType ?? 'application/octet-stream',
        sizeBytes: attachment.sizeBytes ?? 0,
        categoryKey: attachment.categoryKey,
        classification: YorksV1DocumentClassification.operational,
        contentHash:
            attachment.contentHash ??
            (_matchingSelectedAttachment(attachment) == null
                ? null
                : sha256
                      .convert(_matchingSelectedAttachment(attachment)!.bytes)
                      .toString()),
        status: _matchingSelectedAttachment(attachment) == null
            ? YorksV1ProjectSetupFileStatus.needsReselect
            : YorksV1ProjectSetupFileStatus.selected,
      ),
  ];

  YorksV1SelectedDocument? _matchingSelectedAttachment(
    YorksV1ProjectAttachmentInput attachment,
  ) {
    for (final file in _selectedAttachmentFiles) {
      if (file.fileName != attachment.fileName ||
          file.mimeType != attachment.mimeType ||
          file.bytes.length != attachment.sizeBytes) {
        continue;
      }
      if (attachment.contentHash != null &&
          attachment.contentHash != sha256.convert(file.bytes).toString()) {
        continue;
      }
      return file;
    }
    return null;
  }

  Future<int> _uploadSelectedAttachments(
    YorksV1ProjectSetupCoordinator coordinator,
  ) async {
    final operation = coordinator.currentState.operation!;
    var pending = 0;
    for (final intent in operation.files) {
      if (intent.status == YorksV1ProjectSetupFileStatus.ready ||
          intent.status == YorksV1ProjectSetupFileStatus.removed) {
        continue;
      }
      final attachment = YorksV1ProjectAttachmentInput(
        fileName: intent.fileName,
        mimeType: intent.mimeType,
        sizeBytes: intent.sizeBytes,
        contentHash: intent.contentHash,
      );
      final selected = _matchingSelectedAttachment(attachment);
      if (selected == null) {
        pending++;
        continue;
      }
      try {
        await coordinator.uploadFile(
          localId: intent.localId,
          bytes: selected.bytes,
          documents: ref.read(yorksV1DocumentsRepositoryProvider),
        );
      } catch (_) {
        pending++;
      }
    }
    return pending;
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

/// Input values may come from a preserved frontend buffer. Editability comes
/// from the live controller fence, never from that buffer's old storage flags.
class _ProjectSetupReadOnlyScope extends InheritedWidget {
  const _ProjectSetupReadOnlyScope({
    required this.readOnly,
    required super.child,
  });

  final bool readOnly;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ProjectSetupReadOnlyScope>()
          ?.readOnly ??
      false;

  @override
  bool updateShouldNotify(_ProjectSetupReadOnlyScope oldWidget) =>
      readOnly != oldWidget.readOnly;
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
          eyebrow: YorksV1ProjectStrings.projects.active(language),
          title: title.active(language),
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

class _SaveLocalDraftIntent extends Intent {
  const _SaveLocalDraftIntent();
}

class _R35CreationStageHeader extends StatelessWidget {
  const _R35CreationStageHeader({required this.stage, required this.language});
  final YorksV1ProjectCreationStage stage;
  final AppLanguage language;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        YorksV1ProjectStrings.stepOf
            .active(language)
            .replaceFirst('{current}', '${stage.index + 1}')
            .replaceFirst('{total}', '5'),
        style: AppTypography.eyebrow.copyWith(color: AppColors.blue),
      ),
      const SizedBox(height: 8),
      Text(
        _stageCopy(stage).active(language),
        style: AppTypography.headlineSmall.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _stageDescription(stage).active(language),
        style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class _StageNavigation extends StatefulWidget {
  const _StageNavigation({
    required this.currentStage,
    required this.language,
    required this.vertical,
    required this.visitedStages,
    required this.onSelect,
  });
  final YorksV1ProjectCreationStage currentStage;
  final AppLanguage language;
  final bool vertical;
  final Set<YorksV1ProjectCreationStage> visitedStages;
  final ValueChanged<YorksV1ProjectCreationStage> onSelect;

  @override
  State<_StageNavigation> createState() => _StageNavigationState();
}

class _StageNavigationState extends State<_StageNavigation> {
  final _nodes = [
    for (final stage in YorksV1ProjectCreationStage.values)
      FocusNode(debugLabel: 'project-setup-${stage.name}'),
  ];
  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _moveFocus(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final eligible = [
      for (final stage in YorksV1ProjectCreationStage.values)
        if (widget.visitedStages.contains(stage)) stage.index,
    ];
    if (eligible.isEmpty) return KeyEventResult.ignored;
    final focused = _nodes.indexWhere((node) => node.hasFocus);
    final position = eligible.indexOf(focused);
    final key = event.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    int? destination;
    if (key == LogicalKeyboardKey.home) {
      destination = eligible.first;
    } else if (key == LogicalKeyboardKey.end) {
      destination = eligible.last;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight)) {
      destination = eligible[(position + 1).clamp(0, eligible.length - 1)];
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
      destination = eligible[(position - 1).clamp(0, eligible.length - 1)];
    }
    if (destination == null) return KeyEventResult.ignored;
    _nodes[destination].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final stage in YorksV1ProjectCreationStage.values)
        FocusTraversalOrder(
          order: NumericFocusOrder(stage.index.toDouble()),
          child: widget.vertical
              ? _StageNavigationItem(
                  stage: stage,
                  currentStage: widget.currentStage,
                  language: widget.language,
                  focusNode: _nodes[stage.index],
                  onTap: widget.visitedStages.contains(stage)
                      ? () => widget.onSelect(stage)
                      : null,
                )
              : _MobileStageNavigationItem(
                  stage: stage,
                  currentStage: widget.currentStage,
                  language: widget.language,
                  focusNode: _nodes[stage.index],
                  onTap: widget.visitedStages.contains(stage)
                      ? () => widget.onSelect(stage)
                      : null,
                ),
        ),
    ];
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _moveFocus,
        child: widget.vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final child in children) Expanded(child: child),
                ],
              ),
      ),
    );
  }
}

class _MobileStageNavigationItem extends StatelessWidget {
  const _MobileStageNavigationItem({
    required this.stage,
    required this.currentStage,
    required this.language,
    required this.onTap,
    required this.focusNode,
  });

  final YorksV1ProjectCreationStage stage;
  final YorksV1ProjectCreationStage currentStage;
  final AppLanguage language;
  final VoidCallback? onTap;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final selected = stage == currentStage;
    final completed = stage.index < currentStage.index;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: _stageCopy(stage).active(language),
      child: InkWell(
        key: ValueKey('yorks-v1-project-stage-${stage.name}'),
        onTap: onTap,
        focusNode: focusNode,
        canRequestFocus: onTap != null,
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
                    .active(language),
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
    required this.focusNode,
  });

  final YorksV1ProjectCreationStage stage;
  final YorksV1ProjectCreationStage currentStage;
  final AppLanguage language;
  final VoidCallback? onTap;
  final FocusNode focusNode;

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
          focusNode: focusNode,
          canRequestFocus: onTap != null,
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
    required this.referenceHint,
    required this.language,
    required this.focusNodes,
    required this.referenceController,
    required this.nameController,
    required this.clientController,
    required this.jobOrContractController,
    required this.siteController,
    required this.notesController,
    required this.contactNameController,
    required this.contactPhoneController,
    required this.contactEmailController,
    required this.contactAddressController,
    required this.onContactChanged,
    required this.contactsExpanded,
    required this.onContactsExpanded,
    required this.startDateController,
    required this.endDateController,
    required this.validationErrors,
    required this.onReferenceChanged,
    required this.onNameChanged,
    required this.onClientChanged,
    required this.onJobOrContractChanged,
    required this.onSiteChanged,
    required this.onNotesChanged,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onTodayStart,
    required this.onTodayEnd,
  });

  final GlobalKey<FormState> formKey;
  final TranslatableString? referenceHint;
  final AppLanguage language;
  final Map<String, FocusNode> focusNodes;
  final TextEditingController referenceController;
  final TextEditingController nameController;
  final TextEditingController clientController;
  final TextEditingController jobOrContractController;
  final TextEditingController siteController;
  final TextEditingController notesController;
  final TextEditingController contactNameController;
  final TextEditingController contactPhoneController;
  final TextEditingController contactEmailController;
  final TextEditingController contactAddressController;
  final ValueChanged<String> onContactChanged;
  final bool contactsExpanded;
  final ValueChanged<bool> onContactsExpanded;
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final ValueChanged<String> onReferenceChanged;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onClientChanged;
  final ValueChanged<String> onJobOrContractChanged;
  final ValueChanged<String> onSiteChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;
  final VoidCallback onTodayStart;
  final VoidCallback onTodayEnd;

  @override
  Widget build(BuildContext context) {
    if (YorksProjectSetupDesktopTheme.isDesktop(context)) {
      return _DesktopDetailsStage(this);
    }
    if (YorksProjectSetupMobileTheme.isMobileLayout(context)) {
      return _MobileDetailsStage(this);
    }
    final required = YorksV1ProjectStrings.requiredField.active(language);
    return Form(
      key: formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          final fields = [
            LedgerTextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-project-reference'),
              controller: referenceController,
              focusNode: focusNodes['reference'],
              semanticsLabel: YorksV1ProjectStrings.yorksReference.active(
                language,
              ),
              label: YorksV1ProjectStrings.yorksReference.active(language),
              hintText: YorksV1ProjectStrings.yorksReferenceHint.active(
                language,
              ),
              helperText:
                  (referenceHint ?? YorksV1ProjectStrings.yorksReferenceHelp)
                      .active(language),
              onChanged: onReferenceChanged,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? required : null,
            ),
            LedgerTextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-project-name'),
              controller: nameController,
              focusNode: focusNodes['name'],
              semanticsLabel: YorksV1ProjectStrings.projectName.active(
                language,
              ),
              label: YorksV1ProjectStrings.projectName.active(language),
              hintText: YorksV1ProjectStrings.projectNameHint.active(language),
              onChanged: onNameChanged,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? required : null,
            ),
            LedgerTextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-project-client'),
              controller: clientController,
              focusNode: focusNodes['client'],
              semanticsLabel: YorksV1ProjectStrings.client.active(language),
              label: YorksV1ProjectStrings.client.active(language),
              hintText: YorksV1ProjectStrings.clientHint.active(language),
              onChanged: onClientChanged,
            ),
            LedgerTextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-project-job-contract'),
              controller: jobOrContractController,
              focusNode: focusNodes['contract'],
              semanticsLabel: YorksV1ProjectStrings.jobOrContractReference
                  .active(language),
              label: YorksV1ProjectStrings.jobOrContractReference.active(
                language,
              ),
              hintText: YorksV1ProjectStrings.jobOrContractReferenceHint.active(
                language,
              ),
              onChanged: onJobOrContractChanged,
            ),
            LedgerTextField(
              readOnly: _ProjectSetupReadOnlyScope.of(context),
              key: const ValueKey('yorks-v1-project-site'),
              controller: siteController,
              focusNode: focusNodes['site'],
              semanticsLabel: YorksV1ProjectStrings.siteLocation.active(
                language,
              ),
              label: YorksV1ProjectStrings.siteLocation.active(language),
              hintText: YorksV1ProjectStrings.siteLocationHint.active(language),
              onChanged: onSiteChanged,
            ),
            _DateField(
              copy: YorksV1ProjectStrings.startDate,
              controller: startDateController,
              focusNode: focusNodes['startDate'],
              onToday: onTodayStart,
              language: language,
              onTap: onSelectStartDate,
            ),
            _DateField(
              copy: YorksV1ProjectStrings.endDate,
              controller: endDateController,
              focusNode: focusNodes['endDate'],
              onToday: onTodayEnd,
              language: language,
              onTap: onSelectEndDate,
              error:
                  validationErrors.contains(
                    YorksV1ProjectValidationCode.invalidDateRange,
                  )
                  ? YorksV1ProjectStrings.endDateAfterStart.active(language)
                  : validationErrors.contains(
                      YorksV1ProjectValidationCode.unsupportedProjectDate,
                    )
                  ? YorksV1ProjectStrings.projectDateSupportedRange.active(
                      language,
                    )
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
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  initiallyExpanded: contactsExpanded,
                  onExpansionChanged: onContactsExpanded,
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    YorksV1ProjectStrings.optionalContacts.active(language),
                    style: AppTypography.titleSmall,
                  ),
                  children: [
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      controller: contactNameController,
                      focusNode: focusNodes['contactName'],
                      semanticsLabel: YorksV1ProjectStrings.contactName.active(
                        language,
                      ),
                      label: YorksV1ProjectStrings.contactName.active(language),
                      onChanged: onContactChanged,
                    ),
                    const SizedBox(height: 12),
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      controller: contactPhoneController,
                      focusNode: focusNodes['contactPhone'],
                      semanticsLabel: YorksV1ProjectStrings.contactPhone.active(
                        language,
                      ),
                      label: YorksV1ProjectStrings.contactPhone.active(
                        language,
                      ),
                      onChanged: onContactChanged,
                    ),
                    const SizedBox(height: 12),
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      controller: contactEmailController,
                      focusNode: focusNodes['contactEmail'],
                      semanticsLabel: YorksV1ProjectStrings.contactEmail.active(
                        language,
                      ),
                      label: YorksV1ProjectStrings.contactEmail.active(
                        language,
                      ),
                      onChanged: onContactChanged,
                    ),
                    const SizedBox(height: 12),
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      controller: contactAddressController,
                      focusNode: focusNodes['contactAddress'],
                      semanticsLabel: YorksV1ProjectStrings.contactAddress
                          .active(language),
                      label: YorksV1ProjectStrings.contactAddress.active(
                        language,
                      ),
                      onChanged: onContactChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              LedgerTextField(
                readOnly: _ProjectSetupReadOnlyScope.of(context),
                key: const ValueKey('yorks-v1-project-notes'),
                controller: notesController,
                focusNode: focusNodes['notes'],
                semanticsLabel: YorksV1ProjectStrings.notes.active(language),
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
    required this.controller,
    required this.language,
    required this.onTap,
    required this.onToday,
    this.error,
    this.focusNode,
  });
  final TranslatableString copy;
  final TextEditingController controller;
  final AppLanguage language;
  final VoidCallback onTap;
  final VoidCallback onToday;
  final String? error;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        readOnly: _ProjectSetupReadOnlyScope.of(context),
        key: ValueKey('yorks-v1-project-date-${copy.en}'),
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: copy.active(language),
          hintText: YorksV1ProjectStrings.dateInputHint.active(language),
          helperText: YorksV1ProjectStrings.typedDateFormatHelp.active(
            language,
          ),
          errorText: error,
          suffixIcon: IconButton(
            onPressed: onTap,
            tooltip: copy.active(language),
            icon: const Icon(Icons.calendar_today_outlined, size: 20),
          ),
        ),
        validator: (value) =>
            value == null ||
                value.trim().isEmpty ||
                _parseTypedDate(value) != null
            ? null
            : YorksV1ProjectStrings.invalidTypedDate.active(language),
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          onPressed: onToday,
          child: Text(YorksV1ProjectStrings.today.active(language)),
        ),
      ),
    ],
  );
}

DateTime? _parseTypedDate(String text) {
  final match = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

String _typedDateText(DateTime? date) => date == null
    ? ''
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class _PartiesAndAccessStage extends StatelessWidget {
  const _PartiesAndAccessStage({
    required this.draft,
    required this.focusNodes,
    required this.onUndoPartyRemoval,
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
    this.editItem,
    this.onManageAccess,
  });

  final YorksV1ProjectCreationDraft draft;
  final Map<String, FocusNode> focusNodes;
  final VoidCallback? onUndoPartyRemoval;
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
  final YorksV1ProjectPortfolioItem? editItem;
  final VoidCallback? onManageAccess;

  @override
  Widget build(BuildContext context) {
    if (YorksProjectSetupDesktopTheme.isDesktop(context)) {
      return _DesktopPartiesStage(this);
    }
    if (YorksProjectSetupMobileTheme.isMobileLayout(context)) {
      return _MobilePartiesStage(this);
    }
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
          title: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                YorksV1ProjectStrings.partiesAreMetadata.active(language),
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 620;
                  final fields = [
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      key: const ValueKey('yorks-v1-project-consultant'),
                      controller: consultantController,
                      focusNode: focusNodes['consultant'],
                      semanticsLabel: YorksV1ProjectStrings.consultant.active(
                        language,
                      ),
                      label: YorksV1ProjectStrings.consultant.active(language),
                      hintText: YorksV1ProjectStrings.consultant.active(
                        language,
                      ),
                      onChanged: onConsultantChanged,
                    ),
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      key: const ValueKey('yorks-v1-project-main-contractor'),
                      controller: mainContractorController,
                      focusNode: focusNodes['mainContractor'],
                      semanticsLabel: YorksV1ProjectStrings.mainContractor
                          .active(language),
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
                  YorksV1ProjectStrings.stageNeedsAttention.active(language),
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
                focusNode: focusNodes['subcontractor'],
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
                focusNode: focusNodes['otherContractor'],
                entries: otherContractors,
                onAdd: onAddOtherContractor,
                onRemove: onRemoveParty,
              ),
            ],
          ),
        ),
        if (!showTeam && editItem != null) ...[
          const SizedBox(height: AppSpacing.lg),
          NexusSectionCard(
            title: YorksV1ProjectStrings.projectTeam.active(language),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final member in editItem!.activeMembers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${member.displayName ?? YorksV1ProjectStrings.profileId.active(language)} · ${YorksV1ProjectStrings.roleLabel(member.projectRole.wireValue).active(language)}',
                    ),
                  ),
                Text(
                  YorksV1ProjectStrings.accessAppliedSeparately.active(
                    language,
                  ),
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onManageAccess,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: Text(
                    YorksV1ProjectStrings.manageAccess.active(language),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (onUndoPartyRemoval != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onUndoPartyRemoval,
              icon: const Icon(Icons.undo),
              label: Text(
                YorksV1ProjectStrings.undoPartyRemoval.active(language),
              ),
            ),
          ),
        if (showTeam) ...[
          const SizedBox(height: AppSpacing.lg),
          NexusSectionCard(
            title: YorksV1ProjectStrings.projectTeam.active(language),
            description: YorksV1ProjectStrings.accessDescription.active(
              language,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_automaticCreatorMembershipText(creatorRole, language)
                    case final membership?) ...[
                  Text(
                    membership,
                    key: const ValueKey(
                      'yorks-v1-automatic-creator-membership',
                    ),
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _InitialTeamAccessEditor(
                  draft: draft,
                  language: language,
                  creatorRole: creatorRole,
                  creatorAuthUserId: creatorAuthUserId,
                  teamDirectory: teamDirectory,
                  onAddMember: onAddInitialMember,
                  onRemoveMember: onRemoveInitialMember,
                ),
              ],
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
            if (_hasUnavailableInitialMember(draft, members)) ...[
              _InitialTeamMemberChips(
                initialMembers: draft.initialMembers,
                memberByAuthUserId: {
                  for (final member in members) member.authUserId: member,
                },
                language: language,
                onRemove: onRemoveMember,
              ),
              const SizedBox(height: 16),
            ],
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

class _InitialTeamCardPicker extends StatefulWidget {
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
    YorksV1ProjectTeamDirectoryMember,
    YorksV1ProjectMembershipRole,
  )
  onAdd;
  final ValueChanged<String> onRemove;
  @override
  State<_InitialTeamCardPicker> createState() => _InitialTeamCardPickerState();
}

class _InitialTeamCardPickerState extends State<_InitialTeamCardPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final selected = widget.initialMembers
        .map((entry) => entry.authUserId)
        .toSet();
    final results = widget.choices
        .where(
          (member) =>
              !selected.contains(member.authUserId) &&
              _safeMemberDisplayName(
                member,
              ).toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .take(20)
        .toList();
    Widget row(YorksV1ProjectTeamDirectoryMember member, bool isSelected) {
      final role = member.eligibleRole == YorksV1Role.projectEngineer
          ? YorksV1ProjectMembershipRole.projectEngineer
          : YorksV1ProjectMembershipRole.siteEngineer;
      final enabled =
          isSelected ||
          !widget.siteCreator ||
          (role == YorksV1ProjectMembershipRole.projectEngineer &&
              widget.canAddProjectEngineer);
      return Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          key: ValueKey('yorks-v1-project-team-picker-${member.authUserId}'),
          value: isSelected,
          onChanged: enabled && !_ProjectSetupReadOnlyScope.of(context)
              ? (_) => isSelected
                    ? widget.onRemove(member.authUserId)
                    : widget.onAdd(member, role)
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            _safeMemberDisplayName(member),
            style: AppTypography.labelLarge,
          ),
          subtitle: Text(
            YorksV1ProjectStrings.roleLabel(
              role.wireValue,
            ).active(widget.language),
            style: AppTypography.bodySmall,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected.isNotEmpty) ...[
          Text(
            YorksV1ProjectStrings.selectedTeam.active(widget.language),
            style: AppTypography.titleSmall,
          ),
          for (final member in widget.choices.where(
            (member) => selected.contains(member.authUserId),
          ))
            row(member, true),
          const Divider(height: 24),
        ],
        TextField(
          readOnly: _ProjectSetupReadOnlyScope.of(context),
          key: const ValueKey('yorks-v1-project-team-search'),
          decoration: InputDecoration(
            labelText: YorksV1ProjectStrings.searchTeam.active(widget.language),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          Text(
            YorksV1ProjectStrings.noTeamSearchResults.active(widget.language),
          )
        else
          for (final member in results) row(member, false),
      ],
    );
  }
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
    required this.focusNode,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });

  final TranslatableString label;
  final AppLanguage language;
  final TextEditingController controller;
  final FocusNode? focusNode;
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
                readOnly: _ProjectSetupReadOnlyScope.of(context),
                controller: controller,
                focusNode: focusNode,
                // The section heading above is the field label. Repeating it
                // here renders two stacked headings in the R35 desktop form.
                label: null,
                semanticsLabel: label.active(language),
                hintText: label.active(language),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: SecondaryButton(
                label: YorksV1ProjectStrings.add.active(language),
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
                  key: ValueKey(
                    'yorks-v1-party-${entry.party.retainedFields['local_row_id'] ?? '${entry.party.kind.name}-${entry.index}'}',
                  ),
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
    required this.focusNodes,
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
    required this.onDuplicateBuilding,
    required this.onUndoRemove,
    required this.onMoveBuilding,
  });

  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final Map<String, FocusNode> focusNodes;
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
  final ValueChanged<int> onDuplicateBuilding;
  final VoidCallback? onUndoRemove;
  final void Function(int index, int direction) onMoveBuilding;

  @override
  Widget build(BuildContext context) {
    if (YorksProjectSetupDesktopTheme.isDesktop(context)) {
      return _DesktopBuildingsStage(this);
    }
    if (YorksProjectSetupMobileTheme.isMobileLayout(context)) {
      return _MobileBuildingsStage(this);
    }
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
          title: YorksV1ProjectStrings.addBuilding.active(language),
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
                  copy: YorksV1ProjectStrings.commonScopeHelp,
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
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      key: const ValueKey('yorks-v1-building-code'),
                      controller: codeController,
                      focusNode: focusNodes['buildingCode'],
                      semanticsLabel: YorksV1ProjectStrings.buildingCode.active(
                        language,
                      ),
                      label: YorksV1ProjectStrings.buildingCode.active(
                        language,
                      ),
                      hintText: YorksV1ProjectStrings.buildingCode.active(
                        language,
                      ),
                    ),
                    LedgerTextField(
                      readOnly: _ProjectSetupReadOnlyScope.of(context),
                      key: const ValueKey('yorks-v1-building-name'),
                      controller: nameController,
                      focusNode: focusNodes['buildingName'],
                      semanticsLabel: YorksV1ProjectStrings.buildingName.active(
                        language,
                      ),
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
                readOnly: _ProjectSetupReadOnlyScope.of(context),
                key: const ValueKey('yorks-v1-building-floors'),
                controller: floorsController,
                focusNode: focusNodes['buildingFloors'],
                semanticsLabel: YorksV1ProjectStrings.floorsOrLevels.active(
                  language,
                ),
                label: YorksV1ProjectStrings.floorsOrLevels.active(language),
                hintText: YorksV1ProjectStrings.levelsLabelsHint.active(
                  language,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              LedgerTextField(
                readOnly: _ProjectSetupReadOnlyScope.of(context),
                key: const ValueKey('yorks-v1-building-delivery-address'),
                controller: deliveryAddressController,
                focusNode: focusNodes['buildingAddress'],
                semanticsLabel: YorksV1ProjectStrings.deliveryAddress.active(
                  language,
                ),
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
                  key: const ValueKey('yorks-v1-building-has-frp-room'),
                  value: hasFrpRoom,
                  onChanged: _ProjectSetupReadOnlyScope.of(context)
                      ? null
                      : (value) => onHasFrpRoomChanged(value ?? false),
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
                        .active(language),
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
                      YorksV1ProjectStrings.cancelBuildingEdit.active(language),
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
                      ? YorksV1ProjectStrings.duplicateBuildingCode.active(
                          language,
                        )
                      : YorksV1ProjectStrings.atLeastOneBuilding.active(
                          language,
                        ),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (onUndoRemove != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onUndoRemove,
              icon: const Icon(Icons.undo),
              label: Text(
                YorksV1ProjectStrings.undoBuildingChange.active(language),
              ),
            ),
          ),
        NexusSectionCard(
          title: YorksV1ProjectStrings.addedBuildings.active(language),
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
                        key: ValueKey<String>(
                          draft.buildings[index].localRowId ??
                              draft.buildings[index].sourceScopeId ??
                              '${draft.buildings[index].hashCode}',
                        ),
                        building: draft.buildings[index],
                        language: language,
                        onEdit: () => onEditBuilding(index),
                        onRemove: () => onRemoveBuilding(index),
                        onDuplicate: () => onDuplicateBuilding(index),
                        onMoveUp: index == 0
                            ? null
                            : () => onMoveBuilding(index, -1),
                        onMoveDown: index == draft.buildings.length - 1
                            ? null
                            : () => onMoveBuilding(index, 1),
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
    super.key,
    required this.building,
    required this.language,
    required this.onEdit,
    required this.onRemove,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final YorksV1ProjectBuildingInput building;
  final AppLanguage language;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

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
              const SizedBox(height: 4),
              Text(
                (building.hasFrpRoom
                        ? YorksV1ProjectStrings.frpYes
                        : YorksV1ProjectStrings.frpNo)
                    .active(language),
                style: AppTypography.bodySmall.copyWith(
                  color: building.hasFrpRoom
                      ? AppColors.success
                      : AppColors.muted,
                ),
              ),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onMoveUp,
                  tooltip: YorksV1ProjectStrings.moveBuildingUp.active(
                    language,
                  ),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  onPressed: onMoveDown,
                  tooltip: YorksV1ProjectStrings.moveBuildingDown.active(
                    language,
                  ),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
            IconButton(
              onPressed: onDuplicate,
              tooltip: YorksV1ProjectStrings.addAnotherLikeThis.active(
                language,
              ),
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: YorksV1ProjectStrings.editBuilding.active(language),
              icon: const Icon(Icons.edit_outlined),
            ),
            if (building.sourceScopeId == null)
              IconButton(
                onPressed: onRemove,
                tooltip: YorksV1ProjectStrings.remove.active(language),
                icon: const Icon(Icons.close),
              )
            else
              Tooltip(
                message: YorksV1ProjectStrings.existingBuildingRetirementBlocked
                    .active(language),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ),
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
    required this.onChangeCategory,
    required this.onPreviewAttachment,
    this.setupState,
    this.onRetryFile,
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
  final void Function(int, YorksV1ProjectAttachmentCategory) onChangeCategory;
  final ValueChanged<YorksV1ProjectAttachmentInput> onPreviewAttachment;
  final YorksV1ProjectSetupState? setupState;
  final ValueChanged<YorksV1ProjectSetupFile>? onRetryFile;

  @override
  Widget build(BuildContext context) {
    if (YorksProjectSetupDesktopTheme.isDesktop(context)) {
      return _DesktopAttachmentsStage(this);
    }
    if (YorksProjectSetupMobileTheme.isMobileLayout(context)) {
      return _MobileAttachmentsStage(this);
    }
    return NexusSectionCard(
      title: YorksV1ProjectStrings.attachments.active(language),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LocalizedCopy(
            copy: YorksV1ProjectStrings.operationalFilesOnly,
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
              YorksV1ProjectStrings.invalidAttachment.active(language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (draft.attachments.isEmpty)
            Column(
              children: [
                Text(
                  YorksV1ProjectStrings.noAttachmentsAdded.active(language),
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  YorksV1ProjectStrings.attachmentsDoNotBlock.active(language),
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
                    language: language,
                    onReselect: onAddAttachment,
                    onChangeCategory: (category) =>
                        onChangeCategory(index, category),
                    onPreview: () =>
                        onPreviewAttachment(draft.attachments[index]),
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
      if (file.fileName == attachment.fileName &&
          file.mimeType == attachment.mimeType &&
          file.bytes.length == attachment.sizeBytes &&
          (attachment.contentHash == null ||
              sha256.convert(file.bytes).toString() ==
                  attachment.contentHash)) {
        return file;
      }
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
    final onDropped = widget.onDropped;
    final onDropError = widget.onDropError;
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
      await onDropped(selectedFiles);
    }
    if (hasInvalidFile) onDropError();
  }

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      button: true,
      label: YorksV1ProjectStrings.attachmentsDropzoneTitle.active(
        widget.language,
      ),
      child: InkWell(
        key: const ValueKey('yorks-v1-attachment-dropzone'),
        onTap: widget.onPick,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: CustomPaint(
          painter: _DashedAttachmentBorderPainter(
            color:
                (_dragging
                        ? AppColors.navy
                        : YorksProjectSetupDesktopTheme.isDesktop(context)
                        ? YorksProjectSetupDesktopTheme.blue
                        : AppColors.blue)
                    .withValues(alpha: _dragging ? 0.9 : 0.55),
            radius: AppSpacing.radiusMd,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _dragging
                  ? AppColors.blue.withValues(alpha: 0.06)
                  : YorksProjectSetupDesktopTheme.isDesktop(context)
                  ? const Color(0xFFF7FBFE)
                  : const Color(0xFFF7FBFE),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            padding:
                (YorksProjectSetupDesktopTheme.isDesktop(context) ||
                    YorksProjectSetupMobileTheme.isMobileLayout(context))
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.xxxl,
                  ),
            child: YorksProjectSetupDesktopTheme.isDesktop(context)
                ? _DesktopDropzoneContents(
                    language: widget.language,
                    onPick: widget.onPick,
                    dragging: _dragging,
                  )
                : YorksProjectSetupMobileTheme.isMobileLayout(context)
                ? _MobileDropzoneContents(
                    language: widget.language,
                    onPick: widget.onPick,
                    dragging: _dragging,
                  )
                : Column(
                    children: [
                      const Icon(
                        Icons.file_upload_outlined,
                        size: 30,
                        color: AppColors.muted,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _dragging
                            ? YorksV1ProjectStrings.attachmentsDropzoneActive
                                  .active(widget.language)
                            : YorksV1ProjectStrings.attachmentsDropzoneTitle
                                  .active(widget.language),
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
                        label: Text(
                          YorksV1ProjectStrings.addAttachment.active(
                            widget.language,
                          ),
                        ),
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
    required this.language,
    required this.attachment,
    required this.pendingFile,
    required this.onRemove,
    required this.onReselect,
    required this.onChangeCategory,
    required this.onPreview,
  });

  final AppLanguage language;
  final YorksV1ProjectAttachmentInput attachment;
  final YorksV1SelectedDocument? pendingFile;
  final VoidCallback onRemove;
  final VoidCallback onReselect;
  final ValueChanged<YorksV1ProjectAttachmentCategory> onChangeCategory;
  final VoidCallback onPreview;

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
              const SizedBox(height: AppSpacing.sm),
              _AttachmentCategoryPicker(
                attachment: attachment,
                language: language,
                onChanged: onChangeCategory,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: pendingFile == null ? onReselect : onPreview,
                icon: Icon(
                  pendingFile == null
                      ? Icons.attach_file
                      : Icons.visibility_outlined,
                ),
                label: Text(
                  (pendingFile == null
                          ? YorksV1ProjectStrings.fileReselect
                          : YorksV1ProjectSetupDesktopStrings.preview)
                      .active(language),
                ),
              ),
              if (attachment.mimeType?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    attachment.mimeType!,
                    if (attachment.sizeBytes != null)
                      _formatAttachmentSize(attachment.sizeBytes!),
                    if (pendingFile != null)
                      YorksV1ProjectStrings.filesSelected.active(language)
                    else
                      YorksV1ProjectStrings.attachmentNeedsReselect.active(
                        language,
                      ),
                  ].join(' · '),
                  style: AppTypography.bodySmall.copyWith(
                    color: pendingFile == null ? AppColors.warning : null,
                  ),
                ),
              ] else
                Text(
                  pendingFile == null
                      ? YorksV1ProjectStrings.attachmentNeedsReselect.active(
                          language,
                        )
                      : YorksV1ProjectStrings.filesSelected.active(language),
                  style: AppTypography.bodySmall.copyWith(
                    color: pendingFile == null ? AppColors.warning : null,
                  ),
                ),
            ],
          ),
        ),
        if (pendingFile == null)
          IconButton(
            onPressed: onReselect,
            tooltip: YorksV1ProjectStrings.attachmentNeedsReselect.active(
              language,
            ),
            icon: const Icon(Icons.attach_file),
          ),
        IconButton(
          onPressed: onRemove,
          tooltip: YorksV1ProjectStrings.remove.active(language),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

TranslatableString _attachmentCategoryLabel(
  YorksV1ProjectAttachmentCategory? category,
) => switch (category) {
  YorksV1ProjectAttachmentCategory.general =>
    YorksV1ProjectSetupDesktopStrings.categoryGeneral,
  YorksV1ProjectAttachmentCategory.drawing =>
    YorksV1ProjectSetupDesktopStrings.categoryDrawing,
  YorksV1ProjectAttachmentCategory.calculation =>
    YorksV1ProjectSetupDesktopStrings.categoryCalculation,
  YorksV1ProjectAttachmentCategory.schedule =>
    YorksV1ProjectSetupDesktopStrings.categorySchedule,
  YorksV1ProjectAttachmentCategory.approval =>
    YorksV1ProjectSetupDesktopStrings.categoryApproval,
  YorksV1ProjectAttachmentCategory.materialList =>
    YorksV1ProjectSetupDesktopStrings.categoryMaterialList,
  YorksV1ProjectAttachmentCategory.other =>
    YorksV1ProjectSetupDesktopStrings.categoryOther,
  null => YorksV1ProjectSetupDesktopStrings.retainedCategory,
};

class _AttachmentCategoryPicker extends StatelessWidget {
  const _AttachmentCategoryPicker({
    super.key,
    required this.attachment,
    required this.language,
    this.onChanged,
  });
  final YorksV1ProjectAttachmentInput attachment;
  final AppLanguage language;
  final ValueChanged<YorksV1ProjectAttachmentCategory>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${YorksV1ProjectSetupDesktopStrings.category.active(language)} (${YorksV1ProjectStrings.optional.active(language)})',
    child: DropdownButtonFormField<String>(
      key: ValueKey('${attachment.localId}:${attachment.effectiveCategoryKey}'),
      initialValue: attachment.effectiveCategoryKey,
      isExpanded: true,
      style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        constraints: BoxConstraints(minHeight: 44),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: [
        for (final category in YorksV1ProjectAttachmentCategory.values)
          DropdownMenuItem(
            value: category.wireValue,
            child: Text(_attachmentCategoryLabel(category).active(language)),
          ),
        if (attachment.category == null)
          DropdownMenuItem(
            value: attachment.effectiveCategoryKey,
            enabled: false,
            child: Text(
              YorksV1ProjectSetupDesktopStrings.retainedCategory.active(
                language,
              ),
            ),
          ),
      ],
      onChanged: onChanged == null || _ProjectSetupReadOnlyScope.of(context)
          ? null
          : (value) {
              final selected = YorksV1ProjectAttachmentCategory.values
                  .where((category) => category.wireValue == value)
                  .firstOrNull;
              if (selected != null) onChanged!(selected);
            },
    ),
  );
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
    this.pendingFiles = const [],
    required this.draft,
    required this.language,
    required this.validationErrors,
    required this.teamDirectory,
    required this.onRetryDirectory,
    required this.creatorRole,
    required this.creatorAuthUserId,
    required this.onEdit,
    required this.onResolveConflict,
    this.editItem,
  });
  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  final Set<YorksV1ProjectValidationCode> validationErrors;
  final AsyncValue<List<YorksV1ProjectTeamDirectoryMember>> teamDirectory;
  final VoidCallback onRetryDirectory;
  final YorksV1Role creatorRole;
  final String creatorAuthUserId;
  final ValueChanged<YorksV1ProjectCreationStage> onEdit;
  final YorksV1ProjectPortfolioItem? editItem;
  final List<YorksV1SelectedDocument> pendingFiles;
  final VoidCallback onResolveConflict;
  @override
  Widget build(BuildContext context) {
    if (YorksProjectSetupDesktopTheme.isDesktop(context)) {
      return _DesktopReviewStage(this);
    }
    if (YorksProjectSetupMobileTheme.isMobileLayout(context)) {
      return _MobileReviewStage(this);
    }
    final absent = YorksV1ProjectStrings.notProvided.active(language);
    String text(String? value) => _emptyToNull(value) ?? absent;
    String date(DateTime? value) =>
        value == null ? absent : _typedDateText(value);
    final byId = {
      for (final member
          in teamDirectory.asData?.value ??
              <YorksV1ProjectTeamDirectoryMember>[])
        member.authUserId: member,
    };
    final pe =
        draft.initialMembers.any(
          (member) =>
              member.projectRole ==
              YorksV1ProjectMembershipRole.projectEngineer,
        ) ||
        creatorRole == YorksV1Role.projectEngineer ||
        creatorRole.isGlobalProjectEngineer;
    final automaticMembership = _automaticCreatorMembershipText(
      creatorRole,
      language,
    );
    final teamReview = [
      ?automaticMembership,
      for (final member in draft.initialMembers)
        if (member.authUserId != creatorAuthUserId ||
            member.projectRole != _creatorProjectRole(creatorRole))
          '${_safeMemberDisplayName(byId[member.authUserId])} · ${YorksV1ProjectStrings.roleLabel(member.projectRole.wireValue).active(language)}',
    ].join('\n');
    Widget card(
      YorksV1ProjectCreationStage stage,
      List<_ReviewSummaryRow> rows,
    ) => _ReviewSummaryCard(
      language: language,
      title: _stageCopy(stage).active(language),
      rows: rows,
      editLabel: switch (stage) {
        YorksV1ProjectCreationStage.projectDetails =>
          YorksV1ProjectStrings.editProjectDetails.active(language),
        YorksV1ProjectCreationStage.partiesAndAccess =>
          YorksV1ProjectStrings.editPartiesAccess.active(language),
        YorksV1ProjectCreationStage.buildings =>
          YorksV1ProjectStrings.editBuildings.active(language),
        YorksV1ProjectCreationStage.attachments =>
          YorksV1ProjectStrings.editAttachments.active(language),
        YorksV1ProjectCreationStage.reviewAndCreate => null,
      },
      onEdit: () => onEdit(stage),
    );
    final cards = <Widget>[
      card(YorksV1ProjectCreationStage.projectDetails, [
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.yorksReference.active(language),
          value: draft.reference,
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.projectName.active(language),
          value: draft.name,
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.client.active(language),
          value: text(draft.clientName),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.jobOrContractReference.active(language),
          value: text(draft.jobOrContractReference),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.siteLocation.active(language),
          value: text(draft.siteLocation),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.startDate.active(language),
          value: date(draft.startDate),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.endDate.active(language),
          value: date(draft.endDate),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.notes.active(language),
          value: text(draft.notes),
        ),
      ]),
      card(YorksV1ProjectCreationStage.partiesAndAccess, [
        for (final kind in [
          YorksV1ProjectPartyKind.consultant,
          YorksV1ProjectPartyKind.mainContractor,
          YorksV1ProjectPartyKind.subcontractor,
          YorksV1ProjectPartyKind.otherContractor,
        ])
          _ReviewSummaryRow(
            label: _partyKindCopy(kind).active(language),
            value: text(
              draft.parties
                  .where((party) => party.kind == kind)
                  .map((party) => party.name)
                  .join(', '),
            ),
          ),
        if (editItem == null)
          _ReviewSummaryRow(
            label: YorksV1ProjectStrings.projectTeam.active(language),
            value: teamReview.isEmpty ? absent : teamReview,
          ),
        if (editItem != null)
          _ReviewSummaryRow(
            label: YorksV1ProjectStrings.projectTeam.active(language),
            value: YorksV1ProjectStrings.accessAppliedSeparately.active(
              language,
            ),
          ),
      ]),
      card(YorksV1ProjectCreationStage.buildings, [
        for (final building in draft.buildings)
          _ReviewSummaryRow(
            label: text(building.code),
            value:
                '${building.name}\n${building.floorsOrLevels.join(', ')}\n${text(building.deliveryAddress)}\n${(building.hasFrpRoom ? YorksV1ProjectStrings.frpYes : YorksV1ProjectStrings.frpNo).active(language)}',
          ),
      ]),
      card(YorksV1ProjectCreationStage.attachments, [
        for (final attachment in draft.attachments)
          _ReviewSummaryRow(
            label: attachment.fileName,
            value: YorksV1ProjectStrings.filesSelected.active(language),
          ),
        if (draft.attachments.isEmpty)
          _ReviewSummaryRow(
            label: YorksV1ProjectStrings.attachments.active(language),
            value: absent,
          ),
      ]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editItem == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.blueContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Text(
              (pe
                      ? YorksV1ProjectStrings.expectedActiveProject
                      : YorksV1ProjectStrings.expectedDraftProject)
                  .active(language),
              style: AppTypography.bodyMedium,
            ),
          ),
        if (editItem != null)
          _EditProposalComparison(draft: draft, language: language),
        const SizedBox(height: 16),
        if (teamDirectory.hasError &&
            draft.initialMembers.isNotEmpty &&
            editItem == null) ...[
          Text(
            YorksV1ProjectStrings.teamDirectoryUnavailable.active(language),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
          ),
          TextButton(
            onPressed: onRetryDirectory,
            child: Text(YorksV1ProjectStrings.retry.active(language)),
          ),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(children: _withGaps(cards));
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards)
                  SizedBox(width: (constraints.maxWidth - 16) / 2, child: card),
              ],
            );
          },
        ),
        if (validationErrors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ValidationBanner(language: language),
        ],
      ],
    );
  }
}

class _EditProposalComparison extends StatelessWidget {
  const _EditProposalComparison({required this.draft, required this.language});
  final YorksV1ProjectCreationDraft draft;
  final AppLanguage language;
  @override
  Widget build(BuildContext context) {
    final base = draft.baseSnapshot;
    final after = draft.toJson();
    final labels = <String, TranslatableString>{
      'reference': YorksV1ProjectStrings.yorksReference,
      'name': YorksV1ProjectStrings.projectName,
      'clientName': YorksV1ProjectStrings.client,
      'jobOrContractReference': YorksV1ProjectStrings.jobOrContractReference,
      'siteLocation': YorksV1ProjectStrings.siteLocation,
      'startDate': YorksV1ProjectStrings.startDate,
      'endDate': YorksV1ProjectStrings.endDate,
      'notes': YorksV1ProjectStrings.notes,
      'clientContactName': YorksV1ProjectStrings.contactName,
      'clientContactPhone': YorksV1ProjectStrings.contactPhone,
      'clientContactEmail': YorksV1ProjectStrings.contactEmail,
      'clientAddress': YorksV1ProjectStrings.contactAddress,
      'parties': YorksV1ProjectStrings.partiesAndAccess,
      'buildings': YorksV1ProjectStrings.buildings,
    };
    String display(Object? value) {
      if (value == null || value == '') {
        return YorksV1ProjectStrings.notProvided.active(language);
      }
      if (value is List) {
        return value
            .map((entry) {
              if (entry is Map) {
                return [
                  entry['code'],
                  entry['name'],
                  entry['contact_name'],
                  entry['contact_phone'],
                  entry['contact_email'],
                  entry['address'],
                  if (entry.containsKey('flags'))
                    ((entry['flags'] as Map)['has_frp_room'] == true
                            ? YorksV1ProjectStrings.frpYes
                            : YorksV1ProjectStrings.frpNo)
                        .active(language),
                  if (entry['floors_levels'] is List)
                    (entry['floors_levels'] as List).join(', '),
                  entry['delivery_address'],
                ].where((item) => item != null && item != '').join(' · ');
              }
              return '$entry';
            })
            .join('\n');
      }
      return '$value';
    }

    final changes = [
      for (final key in labels.keys)
        if (!mapEquals({'value': base[key]}, {'value': after[key]}) &&
            display(base[key]) != display(after[key]))
          key,
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            YorksV1ProjectStrings.reviewChanges.active(language),
            style: AppTypography.titleMedium,
          ),
          if (changes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                YorksV1ProjectStrings.noProjectChanges.active(language),
              ),
            ),
          for (final key in changes) ...[
            const Divider(height: 24),
            Text(
              labels[key]!.active(language),
              style: AppTypography.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${YorksV1ProjectStrings.beforeChange.active(language)}: ${display(base[key])}',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              '${YorksV1ProjectStrings.afterChange.active(language)}: ${display(after[key])}',
              style: AppTypography.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewSummaryCard extends StatelessWidget {
  const _ReviewSummaryCard({
    required this.language,
    required this.title,
    required this.rows,
    this.editLabel,
    this.onEdit,
  }) : assert(onEdit == null || editLabel != null);

  final AppLanguage language;
  final String title;
  final List<_ReviewSummaryRow> rows;
  final String? editLabel;
  final VoidCallback? onEdit;

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
            Row(
              children: [
                Expanded(child: Text(title, style: AppTypography.titleMedium)),
                if (onEdit != null)
                  Semantics(
                    label: editLabel,
                    button: true,
                    onTap: onEdit,
                    excludeSemantics: true,
                    child: IconButton(
                      onPressed: onEdit,
                      tooltip: editLabel,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),
              ],
            ),
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
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final back = SecondaryButton(
          label: YorksV1ProjectStrings.back.active(language),
          onPressed: saving ? null : onBack,
          icon: Icons.arrow_back,
          isExpanded: stacked,
        );
        final primary = PrimaryButton(
          key: ValueKey('yorks-v1-project-${isReview ? 'create' : 'continue'}'),
          label: isReview
              ? primaryLabel.active(language)
              : YorksV1ProjectStrings.next.active(language),
          onPressed: saving ? null : (isReview ? onCreate : onContinue),
          icon: isReview ? Icons.add_business_outlined : Icons.arrow_forward,
          isTrailingIcon: true,
          isLoading: saving,
          isExpanded: stacked,
        );
        final skip = SecondaryButton(
          label: YorksV1ProjectStrings.skipForNow.active(language),
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
              if (largeText) ...[
                back,
                const SizedBox(height: AppSpacing.sm),
                primary,
              ] else
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

YorksV1ProjectMembershipRole? _creatorProjectRole(YorksV1Role role) {
  if (role == YorksV1Role.siteEngineer) {
    return YorksV1ProjectMembershipRole.siteEngineer;
  }
  if (role == YorksV1Role.projectEngineer || role.isGlobalProjectEngineer) {
    return YorksV1ProjectMembershipRole.projectEngineer;
  }
  return null;
}

String? _automaticCreatorMembershipText(
  YorksV1Role creatorRole,
  AppLanguage language,
) {
  final projectRole = _creatorProjectRole(creatorRole);
  if (projectRole == null) return null;
  return '${YorksV1ProjectStrings.automaticCreatorMembership.active(language)} · ${YorksV1ProjectStrings.roleLabel(projectRole.wireValue).active(language)}';
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

TranslatableString _partyKindCopy(YorksV1ProjectPartyKind kind) =>
    switch (kind) {
      YorksV1ProjectPartyKind.client => YorksV1ProjectStrings.client,
      YorksV1ProjectPartyKind.consultant => YorksV1ProjectStrings.consultant,
      YorksV1ProjectPartyKind.mainContractor =>
        YorksV1ProjectStrings.mainContractor,
      YorksV1ProjectPartyKind.subcontractor =>
        YorksV1ProjectStrings.subcontractors,
      YorksV1ProjectPartyKind.otherContractor =>
        YorksV1ProjectStrings.otherContractors,
    };

class _ReviewSummaryRow {
  const _ReviewSummaryRow({required this.label, required this.value});
  final String label;
  final String value;
}

YorksV1ProjectCreationDraft _projectItemDraft(
  YorksV1ProjectPortfolioItem item,
  String owner,
) {
  final client = item.parties
      .where((party) => party.kind == YorksV1ProjectPartyKind.client)
      .firstOrNull;
  return YorksV1ProjectCreationDraft(
    ownerAuthUserId: owner,
    currentStage: YorksV1ProjectCreationStage.reviewAndCreate,
    creationIdempotencyKey: 'comparison',
    mode: YorksV1ProjectDraftMode.edit,
    projectId: item.project.id,
    baseVersion: item.project.version,
    reference: item.project.reference,
    name: item.project.name,
    clientName: client?.name ?? item.clientName,
    clientContactName: client?.contactName,
    clientContactPhone: client?.contactPhone,
    clientContactEmail: client?.contactEmail,
    clientAddress: client?.address,
    jobOrContractReference: item.project.jobOrContractReference,
    siteLocation: item.project.siteLocation,
    startDate: item.project.startDate,
    endDate: item.project.endDate,
    notes: item.project.notes,
    parties: item.parties
        .where((party) => party.kind != YorksV1ProjectPartyKind.client)
        .toList(),
    buildings: item.buildings,
    updatedAt: DateTime.now().toUtc(),
  );
}

class _ProjectConflictReviewDialog extends StatefulWidget {
  const _ProjectConflictReviewDialog({
    required this.base,
    required this.current,
    required this.proposal,
    required this.language,
  });
  final Map<String, dynamic> base;
  final Map<String, dynamic> current;
  final Map<String, dynamic> proposal;
  final AppLanguage language;
  @override
  State<_ProjectConflictReviewDialog> createState() =>
      _ProjectConflictReviewDialogState();
}

class _ProjectConflictReviewDialogState
    extends State<_ProjectConflictReviewDialog> {
  final _choices = <String, bool>{};
  @override
  Widget build(BuildContext context) {
    final fields = <String, TranslatableString>{
      'reference': YorksV1ProjectStrings.yorksReference,
      'name': YorksV1ProjectStrings.projectName,
      'clientName': YorksV1ProjectStrings.client,
      'jobOrContractReference': YorksV1ProjectStrings.jobOrContractReference,
      'siteLocation': YorksV1ProjectStrings.siteLocation,
      'startDate': YorksV1ProjectStrings.startDate,
      'endDate': YorksV1ProjectStrings.endDate,
      'notes': YorksV1ProjectStrings.notes,
      'clientContactName': YorksV1ProjectStrings.contactName,
      'clientContactPhone': YorksV1ProjectStrings.contactPhone,
      'clientContactEmail': YorksV1ProjectStrings.contactEmail,
      'clientAddress': YorksV1ProjectStrings.contactAddress,
      'parties': YorksV1ProjectStrings.partiesAndAccess,
      'buildings': YorksV1ProjectStrings.buildings,
    };
    String normalized(Object? value) =>
        yorksV1CanonicalSetupJson({'value': value});
    String display(Object? value) {
      if (value == null || value == '') {
        return YorksV1ProjectStrings.notProvided.active(widget.language);
      }
      if (value is List) {
        return value
            .map(
              (item) => item is Map
                  ? [
                      item['code'],
                      item['name'],
                      item['contact_name'],
                      item['contact_phone'],
                      item['contact_email'],
                      item['address'],
                      if (item['floors_levels'] is List)
                        (item['floors_levels'] as List).join(', '),
                      item['delivery_address'],
                      if (item['flags'] is Map)
                        ((item['flags'] as Map)['has_frp_room'] == true
                                ? YorksV1ProjectStrings.frpYes
                                : YorksV1ProjectStrings.frpNo)
                            .active(widget.language),
                    ].where((entry) => entry != null && entry != '').join(' · ')
                  : '$item',
            )
            .join('\n');
      }
      return '$value';
    }

    final conflicts = fields.keys
        .where(
          (key) =>
              normalized(widget.base[key]) != normalized(widget.current[key]) &&
              normalized(widget.base[key]) !=
                  normalized(widget.proposal[key]) &&
              normalized(widget.current[key]) !=
                  normalized(widget.proposal[key]),
        )
        .toList();
    return AlertDialog(
      title: Text(YorksV1ProjectStrings.reviewChanges.active(widget.language)),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                YorksV1ProjectStrings.conflictReviewHelp.active(
                  widget.language,
                ),
              ),
              for (final key in fields.keys.where(
                (key) =>
                    normalized(widget.base[key]) !=
                        normalized(widget.current[key]) ||
                    normalized(widget.base[key]) !=
                        normalized(widget.proposal[key]),
              )) ...[
                const Divider(height: 24),
                Text(
                  fields[key]!.active(widget.language),
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${YorksV1ProjectStrings.originalProject.active(widget.language)}: ${display(widget.base[key])}',
                ),
                Text(
                  '${YorksV1ProjectStrings.currentProject.active(widget.language)}: ${display(widget.current[key])}',
                ),
                Text(
                  '${YorksV1ProjectStrings.proposalChange.active(widget.language)}: ${display(widget.proposal[key])}',
                ),
                if (conflicts.contains(key))
                  DropdownButtonFormField<bool>(
                    initialValue: _choices[key],
                    decoration: InputDecoration(
                      labelText: fields[key]!.active(widget.language),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: false,
                        child: Text(
                          YorksV1ProjectStrings.currentProject.active(
                            widget.language,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text(
                          YorksV1ProjectStrings.proposalChange.active(
                            widget.language,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      if (value != null) _choices[key] = value;
                    }),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(YorksV1ProjectStrings.back.active(widget.language)),
        ),
        FilledButton(
          onPressed: conflicts.any((key) => !_choices.containsKey(key))
              ? null
              : () {
                  final result = <String, dynamic>{};
                  for (final key in fields.keys) {
                    result[key] = conflicts.contains(key)
                        ? (_choices[key] == true
                              ? widget.proposal[key]
                              : widget.current[key])
                        : normalized(widget.proposal[key]) ==
                              normalized(widget.base[key])
                        ? widget.current[key]
                        : widget.proposal[key];
                  }
                  Navigator.pop(context, result);
                },
          child: Text(
            YorksV1ProjectStrings.applyReviewedChoices.active(widget.language),
          ),
        ),
      ],
    );
  }
}

class _ProjectSetupOutcomePanel extends StatelessWidget {
  const _ProjectSetupOutcomePanel({
    required this.state,
    required this.language,
    required this.onRecover,
    required this.onOpen,
    required this.onReselect,
    required this.onRetryFile,
    required this.onRemovePendingFile,
  });
  final YorksV1ProjectSetupState state;
  final AppLanguage language;
  final VoidCallback onRecover;
  final VoidCallback? onOpen;
  final VoidCallback onReselect;
  final ValueChanged<YorksV1ProjectSetupFile> onRetryFile;
  final ValueChanged<YorksV1ProjectSetupFile> onRemovePendingFile;
  @override
  Widget build(BuildContext context) {
    final operation = state.operation;
    final known = operation?.coreSucceeded == true;
    final project = state.project;
    final original = operation?.core.payload;
    final supportReference = operation?.supportReference;
    final copy = known
        ? (operation!.filesPending
              ? YorksV1ProjectStrings.projectSavedFilesPending
              : project?.state == YorksV1ProjectLifecycle.draft
              ? YorksV1ProjectStrings.projectCreatedDraft
              : YorksV1ProjectStrings.projectCreated)
        : state.outcomeUncertain
        ? YorksV1ProjectStrings.commandOutcomeUncertain
        : state.recoveryError != null
        ? YorksV1ProjectStrings.journalUnavailable
        : YorksV1ProjectStrings.stageNeedsAttention;
    return Container(
      key: const ValueKey('yorks-v1-project-operation-outcome'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: known ? AppColors.blueContainer : AppColors.neutralContainer,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              copy.active(language),
              style: AppTypography.titleMedium,
            ),
          ),
          if (project != null) ...[
            const SizedBox(height: 8),
            Text('${project.reference} · ${project.name}'),
            Text(
              YorksV1ProjectStrings.stateLabel(project.state).active(language),
              style: AppTypography.bodySmall,
            ),
          ],
          if (!known && original != null) ...[
            const SizedBox(height: 8),
            Text(
              '${original['project_ref'] ?? ''} · ${original['name'] ?? ''}',
            ),
          ],
          if (supportReference != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    '${YorksV1ProjectStrings.supportReference.active(language)}: $supportReference',
                    style: AppTypography.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: supportReference)),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: YorksV1ProjectStrings.copySupportReference.active(
                    language,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (onOpen != null)
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    YorksV1ProjectStrings.openSavedProject.active(language),
                  ),
                ),
              if (state.outcomeUncertain ||
                  state.recoveryError != null ||
                  operation?.activation?.status ==
                      YorksV1ProjectSetupCommandStatus.confirmedRejected)
                FilledButton(
                  onPressed: state.busy ? null : onRecover,
                  child: Text(
                    YorksV1ProjectStrings.checkSavedStatus.active(language),
                  ),
                ),
            ],
          ),
          if (operation?.filesPending == true)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onReselect,
                child: Text(
                  YorksV1ProjectStrings.continueFileRecovery.active(language),
                ),
              ),
            ),
          for (final file in operation?.files ?? <YorksV1ProjectSetupFile>[])
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file.fileName, style: AppTypography.labelLarge),
                        Text(
                          (switch (file.status) {
                            YorksV1ProjectSetupFileStatus.selected =>
                              YorksV1ProjectStrings.fileSelected,
                            YorksV1ProjectSetupFileStatus.needsReselect =>
                              YorksV1ProjectStrings.fileReselect,
                            YorksV1ProjectSetupFileStatus.uploading =>
                              YorksV1ProjectStrings.fileUploading,
                            YorksV1ProjectSetupFileStatus.ready =>
                              YorksV1ProjectStrings.fileReady,
                            YorksV1ProjectSetupFileStatus.failed =>
                              YorksV1ProjectStrings.fileFailed,
                            YorksV1ProjectSetupFileStatus.outcomeUncertain =>
                              YorksV1ProjectStrings.fileChecking,
                            YorksV1ProjectSetupFileStatus.removed =>
                              YorksV1ProjectStrings.fileRemoved,
                          }).active(language),
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (file.status != YorksV1ProjectSetupFileStatus.ready &&
                      file.status != YorksV1ProjectSetupFileStatus.removed)
                    TextButton(
                      onPressed: state.busy ? null : () => onRetryFile(file),
                      child: Text(
                        (file.status ==
                                    YorksV1ProjectSetupFileStatus.needsReselect
                                ? YorksV1ProjectStrings.fileReselect
                                : YorksV1ProjectStrings.retryFile)
                            .active(language),
                      ),
                    ),
                  if (known &&
                      (file.status == YorksV1ProjectSetupFileStatus.selected ||
                          file.status ==
                              YorksV1ProjectSetupFileStatus.needsReselect))
                    IconButton(
                      onPressed: state.busy
                          ? null
                          : () => onRemovePendingFile(file),
                      icon: const Icon(Icons.close),
                      tooltip: YorksV1ProjectStrings.removePendingFile.active(
                        language,
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

class _OriginalSetupIntentSummary extends StatelessWidget {
  const _OriginalSetupIntentSummary({
    required this.operation,
    required this.language,
  });
  final YorksV1ProjectSetupOperation operation;
  final AppLanguage language;
  @override
  Widget build(BuildContext context) {
    final original = operation.core.payload;
    String text(Object? value) => value == null || value == ''
        ? YorksV1ProjectStrings.notProvided.active(language)
        : '$value';
    return _ReviewSummaryCard(
      language: language,
      title: YorksV1ProjectStrings.originalProject.active(language),
      rows: [
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.yorksReference.active(language),
          value: text(original['project_ref']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.projectName.active(language),
          value: text(original['name']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.siteLocation.active(language),
          value: text(original['project_site']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.startDate.active(language),
          value: text(original['start_date']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.endDate.active(language),
          value: text(original['target_completion_date']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.notes.active(language),
          value: text(original['notes']),
        ),
        _ReviewSummaryRow(
          label: YorksV1ProjectStrings.buildings.active(language),
          value: (original['buildings'] as List? ?? const [])
              .map(
                (building) => building is Map
                    ? '${building['code'] ?? ''} · ${building['name'] ?? ''}'
                    : '',
              )
              .join('\n'),
        ),
      ],
    );
  }
}
