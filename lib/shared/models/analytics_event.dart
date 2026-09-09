/// Phase 2 uses human-readable event names and the expanded workflow/friction
/// taxonomy. Properties remain stable snake_case dimensions.
const int analyticsSchemaVersion = 2;

/// The complete Yorks product-analytics event allowlist. New events must be
/// reviewed here and documented before a call site can emit them.
enum AnalyticsEvent {
  authenticationAttempted('authentication attempted'),
  authenticationSucceeded('authentication succeeded'),
  authenticationFailed('authentication failed'),
  sessionRestored('session restored'),
  userSignedOut('user signed out'),
  projectCreationStarted('project creation started'),
  projectCreationAttempted('project creation attempted'),
  projectCreated('project created'),
  projectCreationFailed('project creation failed'),
  projectOpened('project opened'),
  projectAccessChanged('project access changed'),
  projectUpdated('project updated'),
  projectUpdateFailed('project update failed'),
  documentUploadAttempted('attachment upload started'),
  documentUploadSucceeded('attachment uploaded'),
  documentUploadFailed('attachment upload failed'),
  materialRequestStarted('material request started'),
  materialRequestItemAdded('material request item added'),
  materialRequestItemRemoved('material request item removed'),
  materialRequestDraftSaved('material request draft saved'),
  materialRequestReviewOpened('material request review reached'),
  materialRequestSubmissionAttempted('material request submit attempted'),
  materialRequestSubmitted('material request submitted'),
  materialRequestSubmissionFailed('material request submission failed'),
  materialRequestOpened('material request opened'),
  materialRequestApproved('material request approved'),
  materialRequestReturned('material request returned'),
  materialRequestDecisionFailed('material request decision failed'),
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
  feedbackExpectedMs;

  String get wireName => _snakeCase(name);
}

typedef AnalyticsProperties = Map<AnalyticsProperty, Object?>;

enum AnalyticsSearchContext { inventory, materialRequest }

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
  materialRequests,
  materialRequestDraft,
  materialRequestDetail,
  procurementArrangement,
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
