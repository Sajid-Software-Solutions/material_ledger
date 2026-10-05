import 'package:supabase_flutter/supabase_flutter.dart';

/// A negative result is limited to the caller's current RLS-visible scope.
/// The create/update RPC and active-reference constraint remain authoritative.
enum YorksV1ProjectReferenceAdvisory {
  duplicateVisible,
  noMatchInAccessibleScope,
  unavailable,
}

abstract interface class YorksV1ProjectReferenceAdvisoryDataClient {
  Future<bool> hasVisibleActiveReference({
    required String normalizedReference,
    String? excludingProjectId,
  });
}

class SupabaseYorksV1ProjectReferenceAdvisoryDataClient
    implements YorksV1ProjectReferenceAdvisoryDataClient {
  const SupabaseYorksV1ProjectReferenceAdvisoryDataClient(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> hasVisibleActiveReference({
    required String normalizedReference,
    String? excludingProjectId,
  }) async {
    var query = _client
        .from('v1_projects')
        .select('id')
        .eq('project_ref', normalizedReference)
        .neq('state', 'archived');
    if (excludingProjectId != null) {
      query = query.neq('id', excludingProjectId);
    }
    final rows = await query.limit(1);
    // No identity, name, commercial field or count leaves this read seam.
    return rows.isNotEmpty;
  }
}

class YorksV1ProjectReferenceAdvisoryRepository {
  const YorksV1ProjectReferenceAdvisoryRepository({
    YorksV1ProjectReferenceAdvisoryDataClient? dataClient,
    this.queryTimeout = const Duration(seconds: 10),
  }) : _dataClient = dataClient;

  final YorksV1ProjectReferenceAdvisoryDataClient? _dataClient;
  final Duration queryTimeout;

  Future<YorksV1ProjectReferenceAdvisory> check({
    required String reference,
    String? projectId,
  }) async {
    final normalized = reference.trim().toUpperCase();
    final client = _dataClient;
    if (normalized.isEmpty || client == null) {
      return YorksV1ProjectReferenceAdvisory.unavailable;
    }
    final excluded = projectId?.trim();
    try {
      final visible = await client
          .hasVisibleActiveReference(
            normalizedReference: normalized,
            excludingProjectId: excluded == null || excluded.isEmpty
                ? null
                : excluded,
          )
          .timeout(queryTimeout);
      return visible
          ? YorksV1ProjectReferenceAdvisory.duplicateVisible
          : YorksV1ProjectReferenceAdvisory.noMatchInAccessibleScope;
    } catch (_) {
      return YorksV1ProjectReferenceAdvisory.unavailable;
    }
  }
}
