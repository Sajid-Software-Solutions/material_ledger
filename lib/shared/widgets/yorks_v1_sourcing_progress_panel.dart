import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../models/app_language.dart';
import '../models/yorks_v1_project_strings.dart';
import '../models/yorks_v1_sourcing_strings.dart';
import '../providers/yorks_v1_sourcing_progress_provider.dart';

/// Only server-confirmed operational progress is shared with the team. Private
/// editor buffers and commercial inputs never enter this projection.
class YorksV1SourcingProgressPanel extends ConsumerWidget {
  const YorksV1SourcingProgressPanel({
    super.key,
    required this.scope,
    required this.language,
    required this.itemLabels,
    this.onUpdate,
  });
  final YorksV1SourcingScope scope;
  final AppLanguage language;
  final Map<String, String> itemLabels;
  final VoidCallback? onUpdate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(yorksV1SourcingProgressProvider(scope));
    final progress = state.progress;
    final current = progress?.isCurrent == true;
    final date = progress == null
        ? ''
        : '${MaterialLocalizations.of(context).formatMediumDate(progress.updatedAt.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(progress.updatedAt.toLocal()))}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            children: [
              Text(
                YorksV1SourcingStrings.title.active(language),
                style: AppTypography.titleSmall,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: YorksV1SourcingStrings.refresh.active(language),
                    onPressed: state.loading || state.saving
                        ? null
                        : () => ref
                              .read(
                                yorksV1SourcingProgressProvider(scope).notifier,
                              )
                              .load(),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                  if (onUpdate != null)
                    TextButton.icon(
                      onPressed:
                          state.loading || state.saving || state.error != null
                          ? null
                          : onUpdate,
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: Text(
                        (state.saving
                                ? YorksV1SourcingStrings.sharing
                                : YorksV1SourcingStrings.updateTeam)
                            .active(language),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null)
            Text(
              YorksV1SourcingStrings.readFailed.active(language),
              style: AppTypography.bodySmall,
            ),
          if (!state.loading && state.error == null && progress == null)
            Text(
              YorksV1SourcingStrings.empty.active(language),
              style: AppTypography.bodySmall,
            ),
          if (progress != null) ...[
            Text(
              current
                  ? YorksV1SourcingStrings.counts(
                      progress.readyLines,
                      progress.partialLines,
                      progress.waitingLines,
                    ).active(language)
                  : YorksV1SourcingStrings.outdated.active(language),
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${progress.updatedBy}${progress.updatedByRole == null ? '' : ' · ${YorksV1ProjectStrings.roleLabel(progress.updatedByRole).active(language)}'} · $date',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            if (current)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  YorksV1SourcingStrings.details.active(language),
                  style: AppTypography.bodySmall,
                ),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final line in progress.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            child: Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                Text(
                                  itemLabels[line.requestLineId] ??
                                      YorksV1SourcingStrings.item.active(
                                        language,
                                      ),
                                  style: AppTypography.bodySmall,
                                ),
                                Text(
                                  '${YorksV1SourcingStrings.ready.active(language)} ${line.readyQuantity} / ${line.requestedQuantity}',
                                  style: AppTypography.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (line.expectedDate != null)
                                  Text(
                                    '${YorksV1SourcingStrings.expected.active(language)} ${line.expectedDate}',
                                    style: AppTypography.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
          if (onUpdate != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1SourcingStrings.explanation.active(language),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
