import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_material_request_strings.dart';

/// Recovery is explicit. A status read never implicitly retries a write.
class YorksV1SubmissionRecoveryPanel extends StatelessWidget {
  const YorksV1SubmissionRecoveryPanel({
    super.key,
    required this.language,
    required this.checking,
    required this.canRetry,
    required this.onCheck,
    required this.onRetry,
    this.save = false,
  });

  final AppLanguage language;
  final bool checking;
  final bool canRetry;
  final VoidCallback onCheck;
  final VoidCallback onRetry;
  final bool save;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (save
                      ? YorksV1MaterialRequestStrings.saveUnconfirmed
                      : YorksV1MaterialRequestStrings.submissionUnconfirmed)
                  .active(language),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: ValueKey(
                    save ? 'mr-check-draft-save' : 'mr-check-submission',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: checking ? null : onCheck,
                  icon: checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    (save
                            ? YorksV1MaterialRequestStrings.checkSaveStatus
                            : YorksV1MaterialRequestStrings
                                  .checkSubmissionStatus)
                        .active(language),
                  ),
                ),
                if (canRetry)
                  OutlinedButton(
                    key: ValueKey(
                      save
                          ? 'mr-retry-same-draft-save'
                          : 'mr-retry-same-submission',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    onPressed: checking ? null : onRetry,
                    child: Text(
                      (save
                              ? YorksV1MaterialRequestStrings.retrySameSave
                              : YorksV1MaterialRequestStrings
                                    .retrySameSubmission)
                          .active(language),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
