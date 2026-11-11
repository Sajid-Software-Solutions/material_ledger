import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';

/// Minimal picker data, protected by the same project RLS as the portfolio.
/// No parties, membership contacts, scopes or commercial records are hydrated.
class CompanyAnalyticsProjectOption {
  const CompanyAnalyticsProjectOption({
    required this.id,
    required this.reference,
    required this.name,
  });
  final String id;
  final String reference;
  final String name;

  factory CompanyAnalyticsProjectOption.fromJson(Map<String, dynamic> row) {
    String value(String key) {
      final value = row[key];
      if (value is! String || value.trim().isEmpty) {
        throw const YorksV1DomainException(
          YorksV1DomainErrorCode.unexpectedResponse,
        );
      }
      return value;
    }

    return CompanyAnalyticsProjectOption(
      id: value('id'),
      reference: value('project_ref'),
      name: value('name'),
    );
  }
}

class CompanyAnalyticsProjectOptionsRepository {
  const CompanyAnalyticsProjectOptionsRepository(this.client);
  final SupabaseClient client;

  Future<List<CompanyAnalyticsProjectOption>> load() async {
    final results = <CompanyAnalyticsProjectOption>[];
    // Page explicitly: the API row cap must not silently truncate options.
    for (var offset = 0; ; offset += 200) {
      final rows = await client
          .from('v1_projects')
          .select('id, project_ref, name')
          .order('project_ref')
          .order('id')
          .range(offset, offset + 199)
          .timeout(const Duration(seconds: 15));
      results.addAll(rows.map(CompanyAnalyticsProjectOption.fromJson));
      if (rows.length < 200) return List.unmodifiable(results);
    }
  }
}
