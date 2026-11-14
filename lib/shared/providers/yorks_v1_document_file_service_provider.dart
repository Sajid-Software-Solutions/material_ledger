import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/yorks_v1_document_file_service.dart';
import '../services/yorks_v1_multi_file_service.dart';

final yorksV1DocumentFileServiceProvider = Provider<YorksV1DocumentFileService>(
  (_) => const YorksV1PlatformDocumentFileService(),
);

/// Chooses several files at once, for bulk upload.
final yorksV1MultiFileServiceProvider = Provider<YorksV1MultiFileService>(
  (_) => const YorksV1PlatformMultiFileService(),
);
