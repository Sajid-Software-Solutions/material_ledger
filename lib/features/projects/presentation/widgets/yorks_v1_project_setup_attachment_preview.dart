import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/zoom/yorks_workspace_zoom.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_project_setup_desktop_strings.dart';
import '../../../../shared/services/yorks_v1_document_file_service.dart';

/// Renders exact locally selected bytes. It never fetches a URL, uploads a
/// document or changes classification. The caller supplies its current access
/// guard around this surface.
class YorksV1ProjectSetupAttachmentPreview extends StatelessWidget {
  const YorksV1ProjectSetupAttachmentPreview({
    super.key,
    required this.file,
    required this.language,
    this.onSave,
  });

  final YorksV1SelectedDocument file;
  final AppLanguage language;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    Widget failure() => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          YorksV1ProjectSetupDesktopStrings.previewFailure.active(language),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium,
        ),
      ),
    );
    final Widget body;
    if (file.mimeType == 'application/pdf') {
      body = YorksWorkspaceZoomExclusion(
        child: PdfPreview(
          key: const ValueKey('yorks-v1-local-file-pdf-preview'),
          build: (_) async => file.bytes,
          pdfFileName: file.fileName,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowPrinting: false,
          allowSharing: false,
          useActions: false,
          onError: (_, _) => failure(),
        ),
      );
    } else if (file.mimeType == 'image/jpeg' || file.mimeType == 'image/png') {
      body = InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Center(
          child: Image.memory(
            file.bytes,
            key: const ValueKey('yorks-v1-local-file-image-preview'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => failure(),
          ),
        ),
      );
    } else {
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 48),
              const SizedBox(height: AppSpacing.lg),
              Text(
                YorksV1ProjectSetupDesktopStrings.previewUnsupported.active(
                  language,
                ),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium,
              ),
              if (onSave != null) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  key: const ValueKey('yorks-v1-local-file-save'),
                  onPressed: onSave,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(
                    YorksV1ProjectSetupDesktopStrings.saveLocalFile.active(
                      language,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Dialog.fullscreen(
      key: const ValueKey('yorks-v1-local-file-preview'),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.fileName,
                      style: AppTypography.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  IconButton(
                    tooltip: YorksV1ProjectSetupDesktopStrings.closePreview
                        .active(language),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
