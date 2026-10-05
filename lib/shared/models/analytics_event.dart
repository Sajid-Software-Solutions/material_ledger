/// Phase 2 uses human-readable event names and the expanded workflow/friction
/// taxonomy. Properties remain stable snake_case dimensions.
const int analyticsSchemaVersion = 2;

/// The complete Yorks product-analytics event allowlist. New events must be
/// reviewed here and documented before a call site can emit them.
enum AnalyticsEvent {
  companyRequestStarted('company request started'),
  companyRequestOpened('company request opened'),
  companyRequestActionConfirmed('company request action confirmed'),
  companyRequestActionFailed('company request action failed'),
  companyRequestActionUnconfirmed('company request action unconfirmed'),
  authenticationAttempted('authentication attempted'),
  authenticationSucceeded('authentication succeeded'),
  authenticationFailed('authentication failed'),
  sessionRestored('session restored'),
  userSignedOut('user signed out'),
  projectCreationStarted('project creation started'),
  projectCreationAttempted('project creation attempted'),
  projectCreated('project created'),
  projectCreationFailed('project creation failed'),
  projectSetupStepViewed('project setup step viewed'),
  projectDraftSaved('project draft saved'),
  projectDraftRestored('project draft restored'),
  projectDraftSaveFailed('project draft save failed'),
  projectSetupConflictDetected('project setup conflict detected'),
  projectCommandOutcomeUncertain('project command outcome uncertain'),
  projectCommandReconciled('project command reconciled'),
  projectSetupCompleted('project setup completed'),
  projectOpened('project opened'),
  projectAccessChanged('project access changed'),
  projectUpdated('project updated'),
  projectUpdateFailed('project update failed'),
  accountsWorkspaceViewed('accounts workspace viewed'),
  accountsTabSelected('accounts tab selected'),
  accountsBuildingGroupToggled('accounts building group toggled'),
  accountsRecordOpened('accounts record opened'),
  accountsFilterChanged('accounts filter changed'),
  accountsReportRequested('accounts report requested'),
  documentUploadAttempted('attachment upload started'),
  documentUploadSucceeded('attachment uploaded'),
  documentUploadFailed('attachment upload failed'),
  materialRequestStarted('material request started'),
  materialRequestItemAdded('material request item added'),
  materialRequestItemRemoved('material request item removed'),
  materialRequestDraftSaved('material request draft saved'),
  materialRequestDraftDeleteAttempted(
    'material request draft delete attempted',
  ),
  materialRequestDraftDeleted('material request draft deleted'),
  materialRequestDraftDeleteFailed('material request draft delete failed'),
  materialRequestReviewOpened('material request review reached'),
  materialRequestSubmissionAttempted('material request submit attempted'),
  materialRequestSubmitted('material request submitted'),
  materialRequestSubmissionFailed('material request submission failed'),
  materialRequestSubmissionUnconfirmed(
    'material request submission unconfirmed',
  ),
  materialRequestSubmissionReconciled('material request submission reconciled'),
  materialRequestOpened('material request opened'),
  protectedReadCoordinated('protected read coordinated'),
  materialRequestApproved('material request approved'),
  materialRequestReturned('material request returned'),
  materialRequestDecisionFailed('material request decision failed'),
  materialRequestEditingAccessChanged(
    'material request editing access changed',
  ),
  materialRequestEditingAccessFailed('material request editing access failed'),
  approvalActionStarted('approval started'),
  approvalActionCompleted('approval completed'),
  procurementRequestOpened('procurement request opened'),
  arrangementStarted('procurement started'),
  arrangementSaveAttempted('procurement action started'),
  arrangementSaveCompleted('procurement action completed'),
  procurementActionFailed('procurement action failed'),
  dispatchAttempted('dispatch attempted'),
  dispatchCompleted('dispatch completed'),
  dispatchFailed('dispatch failed'),
  receiptReviewCompleted('receipt review completed'),
  inventoryOpened('inventory opened'),
  inventorySearched('inventory searched'),
  inventorySearchNoResults('inventory search no results'),
  materialSearchCompleted('material search completed'),
  inventoryItemSelected('inventory item selected'),
  inventoryItemCreated('inventory item created'),
  inventoryActionStarted('stock action started'),
  inventoryActionCompleted('stock action completed'),
  inventoryActionFailed('stock action failed'),
  inventoryImportStarted('inventory import started'),
  inventoryImportCompleted('inventory import completed'),
  inventoryImportFailed('inventory import failed'),
  formValidationFailed('form validation failed'),
  validationLoopDetected('validation loop detected'),
  materialSearchStruggleDetected('search struggle detected'),
  uiRepeatedActionDetected('repeated action detected'),
  uiActionNoFeedback('action produced no feedback'),
  operationCompleted('operation completed'),
  featureFlagInteracted('feature flag evaluated'),
  reliabilityError('reliability error occurred');

  const AnalyticsEvent(this.wireName);

  final String wireName;
}

enum AnalyticsProperty {
  schemaVersion,
  appVersion,
  appBuild,
  releaseId,
  buildMode,
  environment,
  platform,
  role,
  screenName,
  source,
  entryPoint,
  networkState,
  operation,
  actionType,
  objectType,
  workflow,
  outcome,
  errorCategory,
  retryable,
  resultCount,
  itemCount,
  buildingCount,
  attachmentCount,
  receivedLineCount,
  exceptionLineCount,
  hasExceptions,
  durationMs,
  retryCount,
  attemptCount,
  noResultCount,
  tapCount,
  operationWasLoading,
  cached,
  success,
  featureFlag,
  variant,
  queryLengthBucket,
  searchContext,
  formType,
  fieldType,
  validationReason,
  fileType,
  fileSizeBucket,
  inventoryAction,
  arrangementMode,
  requestTiming,
  entryMode,
  listFilter,
  recordState,
  receiptOutcome,
  mode,
  step,
  storageScope,
  saveTrigger,
  conflictType,
  phase,
  feedbackExpectedMs,
  loadTrigger,
  coalesced,
  cacheState,
  requestGeneration,
  visibilityState;

  String get wireName => _snakeCase(name);
}

typedef AnalyticsProperties = Map<AnalyticsProperty, Object?>;

enum AnalyticsSearchContext {
  inventory,
  materialRequest,
  companyMaterialRequest,
}

enum AnalyticsScreen {
  splash,
  languageSelection,
  login,
  changePassword,
  dashboard,
  materials,
  projects,
  projectCreate,
  projectDetail,
  projectEdit,
  boqGroups,
  boqWorksheet,
  projectDocuments,
  companyMaterialRequests,
  companyMaterialRequestDraft,
  companyMaterialRequestDetail,
  materialRequests,
  materialRequestDraft,
  materialRequestDetail,
  procurement,
  logistics,
  returnsDocuments,
  inventory,
  inventoryImport,
  inventorySuppliers,
  inventorySupplierDetail,
  dispatches,
  returns,
  returnCreate,
  returnDetail,
  accounts,
  accountsProjects,
  accountsBilling,
  accountsClaims,
  accountsReceipts,
  accountsSupplierBills,
  accountsDocuments,
  accountsReports,
  accountsActivity,
  operationalAnalytics,
  workforce,
  workforceAdministration,
  workforceAttendance,
  workforceTimesheets,
  teamChat,
  teamChatConversation,
  configuration,
  userManagement,
  profile,
  notifications,
  notificationPreferences,
  rentals,
  people,
  browse,
  engineeringTool,
  settings,
  unknown;

  String get wireName => _snakeCase(name);
}

enum AnalyticsErrorCategory {
  validation,
  permissionDenied,
  authentication,
  offline,
  conflict,
  insufficientStock,
  featureDisabled,
  timeout,
  network,
  database,
  storage,
  unknown;

  String get wireName => _snakeCase(name);
}

enum AnalyticsFeatureFlag {
  compactRequestWorkspace,
  streamlinedInventorySearch,
  projectCreationGuidance;

  String get wireName => 'yorks_${_snakeCase(name)}';
}

String analyticsWireName(Enum value) => _snakeCase(value.name);

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toLowerCase();

/// Project setup telemetry uses a finite catalogue; identifiers and arbitrary
/// categorical strings must not become draft or command correlation keys.
AnalyticsProperties projectSetupAnalyticsProperties(
  AnalyticsEvent event,
  AnalyticsProperties properties,
) {
  final allowed = switch (event) {
    AnalyticsEvent.projectSetupStepViewed => {
      AnalyticsProperty.mode,
      AnalyticsProperty.step,
      AnalyticsProperty.entryPoint,
    },
    AnalyticsEvent.projectDraftSaved => {
      AnalyticsProperty.mode,
      AnalyticsProperty.storageScope,
      AnalyticsProperty.saveTrigger,
    },
    AnalyticsEvent.projectDraftRestored => {
      AnalyticsProperty.mode,
      AnalyticsProperty.step,
      AnalyticsProperty.source,
    },
    AnalyticsEvent.projectDraftSaveFailed => {
      AnalyticsProperty.mode,
      AnalyticsProperty.errorCategory,
    },
    AnalyticsEvent.projectSetupConflictDetected => {
      AnalyticsProperty.mode,
      AnalyticsProperty.conflictType,
    },
    AnalyticsEvent.projectCommandOutcomeUncertain => {
      AnalyticsProperty.operation,
      AnalyticsProperty.phase,
      AnalyticsProperty.errorCategory,
    },
    AnalyticsEvent.projectCommandReconciled => {
      AnalyticsProperty.operation,
      AnalyticsProperty.outcome,
      AnalyticsProperty.phase,
    },
    AnalyticsEvent.projectSetupCompleted => {
      AnalyticsProperty.mode,
      AnalyticsProperty.outcome,
    },
    _ => null,
  };
  if (allowed == null) return properties;
  const categories = <AnalyticsProperty, Set<String>>{
    AnalyticsProperty.mode: {'create', 'edit'},
    AnalyticsProperty.step: {
      'project_details',
      'parties_and_access',
      'buildings',
      'attachments',
      'review',
    },
    AnalyticsProperty.storageScope: {'device'},
    AnalyticsProperty.saveTrigger: {
      'manual',
      'checkpoint',
      'navigation',
      'background',
    },
    AnalyticsProperty.conflictType: {
      'local_owner',
      'server_version',
      'stale_prerequisite',
    },
    AnalyticsProperty.phase: {
      'create',
      'update',
      'activation',
      'upload',
      'finalize',
      'cleanup',
    },
    AnalyticsProperty.outcome: {
      'active',
      'draft_pending_activation',
      'saved_files_pending',
      'updated',
      'confirmed',
      'not_saved',
      'denied',
      'conflict',
    },
    AnalyticsProperty.operation: {
      'project_create',
      'project_update',
      'project_activation',
      'project_upload',
      'project_finalize',
      'project_cleanup',
    },
    AnalyticsProperty.entryPoint: {
      'navigation',
      'projects',
      'review',
      'resume',
      'direct',
    },
    AnalyticsProperty.source: {'device', 'local_recovery'},
    AnalyticsProperty.errorCategory: {
      'offline',
      'network',
      'backend_unavailable',
      'unauthorized',
      'conflict',
      'validation',
      'unexpected_response',
      'unknown',
      'storage',
      'timeout',
      'permission_denied',
      'authentication',
      'database',
      'feature_disabled',
    },
  };
  return {
    for (final entry in properties.entries)
      if (allowed.contains(entry.key) &&
          categories[entry.key]!.contains(
            entry.value is Enum
                ? analyticsWireName(entry.value as Enum)
                : entry.value,
          ))
        entry.key: entry.value,
  };
}
