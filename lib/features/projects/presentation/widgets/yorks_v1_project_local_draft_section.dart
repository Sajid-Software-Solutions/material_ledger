import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_project_local_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_local_draft_strings.dart';
import 'yorks_v1_project_local_draft_card.dart';

/// A bounded device-local catalogue, kept separate from server project rows,
/// filters and counts. Expansion makes every retained entry reachable.
class YorksV1ProjectLocalDraftSection extends StatefulWidget {
  const YorksV1ProjectLocalDraftSection({
    super.key,
    required this.draftState,
    required this.language,
    required this.scopeIdentity,
    required this.onResume,
    required this.onLegacyRecovery,
    required this.onRetry,
  });

  final YorksV1ProjectLocalCreationDraftState draftState;
  final AppLanguage language;
  final String scopeIdentity;
  final ValueChanged<String> onResume;
  final VoidCallback onLegacyRecovery;
  final VoidCallback onRetry;

  @override
  State<YorksV1ProjectLocalDraftSection> createState() =>
      _YorksV1ProjectLocalDraftSectionState();
}

class _YorksV1ProjectLocalDraftSectionState
    extends State<YorksV1ProjectLocalDraftSection> {
  bool _expanded = false;
  static const _initialLimit = 3;

  @override
  void didUpdateWidget(covariant YorksV1ProjectLocalDraftSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeIdentity != widget.scopeIdentity) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.draftState;
    final summaries = state.summaries;
    final knownIds = summaries.map((summary) => summary.draftId).toSet();
    final recoveryIds = state.recoveryDraftIds
        .where((id) => !knownIds.contains(id))
        .toSet()
        .toList();
    final entries = <(String, YorksV1ProjectLocalCreationDraftSummary?)>[
      for (final summary in summaries) (summary.draftId, summary),
      for (final id in recoveryIds) (id, null),
    ];
    Widget cardFor((String, YorksV1ProjectLocalCreationDraftSummary?) entry) {
      final summary = entry.$2;
      return YorksV1ProjectLocalDraftCard(
        key: ValueKey('saved-local-draft-${entry.$1}'),
        draftId: entry.$1,
        draftState: YorksV1ProjectLocalCreationDraftState(
          status: summary == null
              ? YorksV1ProjectLocalCreationDraftStatus.recoveryRequired
              : YorksV1ProjectLocalCreationDraftStatus.saved,
          summary: summary,
          outcomeUncertain:
              summary?.outcomeUncertain ??
              (state.legacyRecoveryDraftIds.contains(entry.$1) &&
                  state.outcomeUncertain),
        ),
        language: widget.language,
        onResume: state.legacyRecoveryDraftIds.contains(entry.$1)
            ? widget.onLegacyRecovery
            : () => widget.onResume(entry.$1),
        resumeLabel: state.legacyRecoveryDraftIds.contains(entry.$1)
            ? YorksV1ProjectLocalDraftStrings.reviewRecovery
            : null,
      );
    }

    if (entries.isEmpty &&
        !state.hasLegacyRecovery &&
        state.status == YorksV1ProjectLocalCreationDraftStatus.empty) {
      return const SizedBox.shrink();
    }
    final count = _expanded
        ? entries.length
        : entries.length.clamp(0, _initialLimit);
    return Directionality(
      textDirection: widget.language.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Column(
        key: const ValueKey('yorks-v1-project-saved-local-drafts'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isNotEmpty) ...[
            Text(
              YorksV1ProjectLocalDraftStrings.savedDrafts.active(
                widget.language,
              ),
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              YorksV1ProjectLocalDraftStrings.chooseDraft.active(
                widget.language,
              ),
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < count; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.md),
              cardFor(entries[index]),
            ],
            if (entries.length > _initialLimit) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('yorks-v1-project-expand-local-drafts'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(
                    (_expanded
                            ? YorksV1ProjectLocalDraftStrings.showFewer
                            : YorksV1ProjectLocalDraftStrings.showAll)
                        .active(widget.language),
                  ),
                ),
              ),
            ],
          ],
          if (state.hasLegacyRecovery) ...[
            if (entries.isNotEmpty) const SizedBox(height: AppSpacing.md),
            YorksV1ProjectLocalDraftCard(
              entryKey: 'legacy-recovery',
              draftState: const YorksV1ProjectLocalCreationDraftState(
                status: YorksV1ProjectLocalCreationDraftStatus.recoveryRequired,
              ),
              language: widget.language,
              onResume: widget.onLegacyRecovery,
              resumeLabel: YorksV1ProjectLocalDraftStrings.reviewRecovery,
            ),
          ],
          if (state.hasCatalogueRecovery ||
              state.status ==
                  YorksV1ProjectLocalCreationDraftStatus.unavailable ||
              !state.hasLegacyRecovery &&
                  entries.isEmpty &&
                  state.status ==
                      YorksV1ProjectLocalCreationDraftStatus
                          .recoveryRequired) ...[
            if (entries.isNotEmpty) const SizedBox(height: AppSpacing.md),
            YorksV1ProjectLocalDraftCard(
              entryKey: 'catalogue-notice',
              draftState: YorksV1ProjectLocalCreationDraftState(
                status: state.status,
              ),
              language: widget.language,
              onResume: widget.onRetry,
              resumeLabel: YorksV1ProjectLocalDraftStrings.retryDiscovery,
            ),
          ],
        ],
      ),
    );
  }
}
