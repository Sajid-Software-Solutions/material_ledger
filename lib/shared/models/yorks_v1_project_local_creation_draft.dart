import 'yorks_v1_project_creation_draft.dart';

enum YorksV1ProjectLocalCreationDraftStatus {
  empty,
  saved,
  recoveryRequired,
  unavailable,
}

/// Minimal, owner-scoped portfolio projection. It contains no contacts, raw
/// editors, files, command payloads, writer IDs or recovery bytes.
class YorksV1ProjectLocalCreationDraftSummary {
  const YorksV1ProjectLocalCreationDraftSummary({
    required this.draftId,
    required this.reference,
    required this.name,
    required this.currentStage,
    required this.savedAt,
    required this.acknowledgedRevision,
    this.outcomeUncertain = false,
  });

  final String draftId;
  final String reference;
  final String name;
  final YorksV1ProjectCreationStage currentStage;
  final DateTime savedAt;
  final int acknowledgedRevision;
  final bool outcomeUncertain;
}

class YorksV1ProjectLocalCreationDraftState {
  const YorksV1ProjectLocalCreationDraftState({
    this.status = YorksV1ProjectLocalCreationDraftStatus.empty,
    this.summary,
    this.outcomeUncertain = false,
    this.summaries = const [],
    this.recoveryDraftIds = const [],
    this.hasLegacyRecovery = false,
    this.hasCatalogueRecovery = false,
    this.legacyRecoveryDraftIds = const [],
  });

  final YorksV1ProjectLocalCreationDraftStatus status;
  final YorksV1ProjectLocalCreationDraftSummary? summary;
  final bool outcomeUncertain;

  /// Individually resumable acknowledged proposals, separate from server rows.
  final List<YorksV1ProjectLocalCreationDraftSummary> summaries;

  /// Known selected IDs whose retained bytes/intent need guarded recovery.
  final List<String> recoveryDraftIds;
  final bool hasLegacyRecovery;
  final bool hasCatalogueRecovery;

  /// Original singleton intents without an independently resumable envelope.
  /// They use the guarded legacy writer and exact original latest pointer.
  final List<String> legacyRecoveryDraftIds;
}
