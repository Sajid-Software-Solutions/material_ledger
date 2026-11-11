import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/yorks_v1_material_summary_document_service.dart';

/// Injectable so widget tests can verify export flows without platform
/// share sheets or save dialogs.
final yorksV1MaterialSummaryDocumentServiceProvider =
    Provider<YorksV1MaterialSummaryDocumentService>(
      (_) => const YorksV1MaterialSummaryDocumentService(),
    );
