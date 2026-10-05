import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_project_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_local_draft_strings.dart';
import '../../../../shared/models/yorks_v1_project_setup_shell_strings.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/providers/yorks_v1_project_local_creation_draft_provider.dart';

/// Presentation of one acknowledged device-local setup. It never subscribes to
/// a draft controller, claims ownership, or changes the server project list.
class YorksV1ProjectLocalDraftCard extends StatelessWidget {
  const YorksV1ProjectLocalDraftCard({
    super.key,
    required this.draftState,
    required this.language,
    required this.onResume,
    this.draftId,
    this.entryKey,
    this.resumeLabel,
  });

  final YorksV1ProjectLocalCreationDraftState draftState;
  final AppLanguage language;
  final VoidCallback? onResume;
  final String? draftId;
  final String? entryKey;
  final TranslatableString? resumeLabel;

  @override
  Widget build(BuildContext context) {
    if (draftState.status == YorksV1ProjectLocalCreationDraftStatus.empty) {
      return const SizedBox.shrink();
    }
    final summary = draftState.summary;
    final identity = entryKey ?? summary?.draftId ?? draftId ?? 'notice';
    final saved = summary != null;
    final title = saved
        ? YorksV1ProjectLocalDraftStrings.title
        : draftState.status ==
              YorksV1ProjectLocalCreationDraftStatus.unavailable
        ? YorksV1ProjectLocalDraftStrings.unavailableTitle
        : YorksV1ProjectLocalDraftStrings.recoveryTitle;
    final description = draftState.outcomeUncertain
        ? YorksV1ProjectStrings.commandOutcomeUncertain
        : saved
        ? YorksV1ProjectLocalDraftStrings.deviceOnly
        : draftState.status ==
              YorksV1ProjectLocalCreationDraftStatus.unavailable
        ? YorksV1ProjectLocalDraftStrings.unavailable
        : YorksV1ProjectStrings.localRecoveryUnavailable;
    return Directionality(
      textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        key: ValueKey('yorks-v1-project-saved-local-draft-$identity'),
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: const BorderSide(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.1;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        saved ? Icons.save_outlined : Icons.restore_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          title.active(language),
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (saved) ...[
                    Text(
                      YorksV1ProjectSetupShellStrings.saved.active(language),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    if (summary.reference.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        summary.reference,
                        key: const ValueKey('yorks-v1-local-draft-reference'),
                        style: AppTypography.labelLarge,
                      ),
                    ],
                    if (summary.name.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        summary.name,
                        key: const ValueKey('yorks-v1-local-draft-name'),
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${YorksV1ProjectLocalDraftStrings.currentStep.active(language)}: ${_stageLabel(summary.currentStage).active(language)}',
                      key: const ValueKey('yorks-v1-local-draft-step'),
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        Text(
                          '${YorksV1ProjectLocalDraftStrings.lastSaved.active(language)}:',
                          style: AppTypography.bodySmall,
                        ),
                        Text(
                          _savedTimestamp(summary.savedAt),
                          key: const ValueKey('yorks-v1-local-draft-saved-at'),
                          textDirection: TextDirection.ltr,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    description.active(language),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              );
              final action = OutlinedButton.icon(
                key: ValueKey('yorks-v1-project-resume-local-draft-$identity'),
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(44, 44)),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: onResume,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  (resumeLabel ?? YorksV1ProjectLocalDraftStrings.resume)
                      .active(language),
                ),
              );
              if (onResume == null) return details;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: AppSpacing.md),
                    action,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: AppSpacing.xl),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _savedTimestamp(DateTime savedAt) {
  final local = savedAt.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

TranslatableString _stageLabel(YorksV1ProjectCreationStage stage) =>
    switch (stage) {
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
