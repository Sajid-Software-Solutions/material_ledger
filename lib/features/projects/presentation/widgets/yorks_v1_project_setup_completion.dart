import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_setup_operation.dart';
import 'yorks_v1_project_setup_completion_strings.dart';

export 'yorks_v1_project_setup_completion_strings.dart';

class YorksV1ProjectSetupSummaryRow {
  const YorksV1ProjectSetupSummaryRow({
    required this.label,
    required this.value,
    this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
}

/// Presentation eligibility supplied by the current protected workspace.
/// Role labels or a successful create never substitute for these decisions.
class YorksV1ProjectSetupCompletionPermissions {
  const YorksV1ProjectSetupCompletionPermissions({
    this.canOpenProject = false,
    this.canEditProject = false,
    this.canAddBoq = false,
    this.canInviteTeam = false,
    this.canUploadDocuments = false,
    this.canCreateMaterialRequests = false,
    this.canReturnToProjects = false,
  });
  final bool canOpenProject;
  final bool canEditProject;
  final bool canAddBoq;
  final bool canInviteTeam;
  final bool canUploadDocuments;
  final bool canCreateMaterialRequests;
  final bool canReturnToProjects;
}

/// A saved-project surface, never an optimistic command indicator. The
/// operation remains owned by the coordinator; this widget performs no writes,
/// cleanup, navigation, or recovery dispatch without an explicit callback.
class YorksV1ProjectSetupCompletion extends StatelessWidget {
  const YorksV1ProjectSetupCompletion({
    super.key,
    required this.operation,
    required this.copy,
    required this.permissions,
    this.summaryRows = const [],
    this.recoveryPanel,
    this.localRecoveryPending = false,
    this.busy = false,
    this.showBanner = true,
    this.compact = false,
    this.onDismissBanner,
    this.onOpenProject,
    this.onEditProject,
    this.onAddBoq,
    this.onInviteTeam,
    this.onUploadDocuments,
    this.onReturnToProjects,
  });

  final YorksV1ProjectSetupOperation operation;
  final YorksV1ProjectSetupCompletionCopy copy;
  final YorksV1ProjectSetupCompletionPermissions permissions;
  final List<YorksV1ProjectSetupSummaryRow> summaryRows;
  final Widget? recoveryPanel;
  final bool localRecoveryPending;
  final bool busy;
  final bool showBanner;

  /// Scoped phone/tablet sizing; operation and permission semantics are shared.
  final bool compact;
  final VoidCallback? onDismissBanner;
  final VoidCallback? onOpenProject;
  final VoidCallback? onEditProject;
  final VoidCallback? onAddBoq;
  final VoidCallback? onInviteTeam;
  final VoidCallback? onUploadDocuments;
  final VoidCallback? onReturnToProjects;

  String _text(YorksV1ProjectSetupCompletionText key) => copy[key];

  TextStyle get _bodyStyle => AppTypography.bodyMedium.copyWith(
    fontSize: compact ? 12 : 14,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    if (!operation.coreSucceeded || operation.project == null) {
      return const SizedBox.shrink();
    }
    final project = operation.project!;
    final editable =
        project.state == YorksV1ProjectLifecycle.draft ||
        project.state == YorksV1ProjectLifecycle.active;
    final mutationReady = !busy && !operation.hasUnresolvedCommand;
    final canBoq = permissions.canAddBoq && editable && mutationReady;
    final canTeam = permissions.canInviteTeam && editable && mutationReady;
    final canDocuments =
        permissions.canUploadDocuments &&
        project.state != YorksV1ProjectLifecycle.archived &&
        !busy;
    final steps =
        <
          (YorksV1ProjectSetupCompletionText, YorksV1ProjectSetupCompletionText)
        >[
          if (canBoq && onAddBoq != null)
            (
              YorksV1ProjectSetupCompletionText.addBoqStepTitle,
              YorksV1ProjectSetupCompletionText.addBoqDescription,
            ),
          if (permissions.canCreateMaterialRequests &&
              mutationReady &&
              project.state == YorksV1ProjectLifecycle.active)
            (
              YorksV1ProjectSetupCompletionText.createRequests,
              YorksV1ProjectSetupCompletionText.createRequestsDescription,
            ),
          if (canDocuments && onUploadDocuments != null)
            (
              YorksV1ProjectSetupCompletionText.uploadDocumentsStepTitle,
              YorksV1ProjectSetupCompletionText.uploadDocumentsDescription,
            ),
          if (canTeam && onInviteTeam != null)
            (
              YorksV1ProjectSetupCompletionText.inviteTeamStepTitle,
              YorksV1ProjectSetupCompletionText.inviteTeamDescription,
            ),
        ];
    final summary = _summary(
      project,
      canEdit: permissions.canEditProject && editable && mutationReady,
    );
    final nextSteps = steps.isEmpty ? null : _steps(steps);
    final actions = _actions(
      canBoq: canBoq,
      canTeam: canTeam,
      canDocuments: canDocuments,
    );
    return Directionality(
      textDirection: copy.language.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBanner) ...[
            _banner(project),
            const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
          ],
          if (operation.hasUnresolvedCommand)
            _attention(
              _text(YorksV1ProjectSetupCompletionText.activationPending),
            ),
          if (operation.filesPending)
            _attention(_text(YorksV1ProjectSetupCompletionText.filesPending)),
          if (localRecoveryPending)
            _attention(
              _text(YorksV1ProjectSetupCompletionText.recoveryPending),
            ),
          if (recoveryPanel != null) ...[
            recoveryPanel!,
            const SizedBox(height: AppSpacing.md),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < AppSpacing.stackedBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    if (nextSteps != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      nextSteps,
                    ],
                    const SizedBox(height: AppSpacing.md),
                    actions,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          if (nextSteps != null) ...[
                            const SizedBox(
                              height: AppSpacing.md + AppSpacing.xxs,
                            ),
                            nextSteps,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md + AppSpacing.xxs),
                    Expanded(flex: 11, child: actions),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _banner(YorksV1Project project) {
    final stateKey = switch (project.state) {
      YorksV1ProjectLifecycle.draft =>
        YorksV1ProjectSetupCompletionText.draftState,
      YorksV1ProjectLifecycle.active =>
        YorksV1ProjectSetupCompletionText.activeState,
      YorksV1ProjectLifecycle.onHold =>
        YorksV1ProjectSetupCompletionText.onHoldState,
      YorksV1ProjectLifecycle.completed =>
        YorksV1ProjectSetupCompletionText.completedState,
      YorksV1ProjectLifecycle.archived =>
        YorksV1ProjectSetupCompletionText.archivedState,
    };
    final description = project.state == YorksV1ProjectLifecycle.draft
        ? YorksV1ProjectSetupCompletionText.draftDescription
        : operation.mode == YorksV1ProjectSetupMode.edit
        ? YorksV1ProjectSetupCompletionText.updatedDescription
        : YorksV1ProjectSetupCompletionText.activeDescription;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : AppSpacing.xl,
              vertical: compact ? 14 : AppSpacing.xl + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.successContainer.withValues(alpha: 0.65),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 32 : 50,
                  height: compact ? 32 : 50,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: AppColors.onSuccess,
                    size: compact ? 24 : 34,
                  ),
                ),
                SizedBox(width: compact ? 12 : AppSpacing.xxl),
                Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      end: onDismissBanner == null ? 0 : 44,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                _text(
                                  operation.mode == YorksV1ProjectSetupMode.edit
                                      ? YorksV1ProjectSetupCompletionText
                                            .updatedTitle
                                      : YorksV1ProjectSetupCompletionText
                                            .createdTitle,
                                ),
                                style: AppTypography.headlineMedium.copyWith(
                                  color: AppColors.navy,
                                  fontSize: compact ? 18 : 28,
                                ),
                              ),
                            ),
                            Text(
                              _text(stateKey),
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(_text(description), style: _bodyStyle),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onDismissBanner != null)
            PositionedDirectional(
              top: 7,
              end: 7,
              child: IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                onPressed: onDismissBanner,
                tooltip: _text(YorksV1ProjectSetupCompletionText.dismissBanner),
                icon: const Icon(Icons.close, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attention(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 20,
              color: AppColors.onWarningContainer,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: _bodyStyle.copyWith(color: AppColors.onWarningContainer),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _summary(YorksV1Project project, {required bool canEdit}) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            _heading(
              YorksV1ProjectSetupCompletionText.summaryTitle,
              YorksV1ProjectSetupCompletionText.summaryDescription,
            ),
            if (canEdit && onEditProject != null)
              OutlinedButton.icon(
                onPressed: onEditProject,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  _text(YorksV1ProjectSetupCompletionText.editProject),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTapTarget),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final row in [
          YorksV1ProjectSetupSummaryRow(
            label: _text(YorksV1ProjectSetupCompletionText.referenceLabel),
            value: project.reference,
          ),
          YorksV1ProjectSetupSummaryRow(
            label: _text(YorksV1ProjectSetupCompletionText.nameLabel),
            value: project.name,
          ),
          ...summaryRows,
        ])
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xs + AppSpacing.xxs,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 34,
                  child: Text(
                    row.label,
                    style: _bodyStyle.copyWith(color: AppColors.muted),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 66,
                  child: row.onTap == null
                      ? Text(
                          row.value,
                          style: _bodyStyle.copyWith(color: AppColors.navy),
                        )
                      : TextButton(
                          onPressed: row.onTap,
                          style: TextButton.styleFrom(
                            alignment: AlignmentDirectional.centerStart,
                            minimumSize: const Size(0, AppSpacing.minTapTarget),
                          ),
                          child: Text(row.value),
                        ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _steps(
    List<(YorksV1ProjectSetupCompletionText, YorksV1ProjectSetupCompletionText)>
    steps,
  ) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          YorksV1ProjectSetupCompletionText.nextStepsTitle,
          YorksV1ProjectSetupCompletionText.nextStepsDescription,
        ),
        const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
        for (final (index, step) in steps.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == steps.length - 1
                  ? AppSpacing.md
                  : AppSpacing.lg + AppSpacing.xxs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 26 : 38,
                  height: compact ? 26 : 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.blueContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.blue,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 12 : AppSpacing.xxl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(step.$1),
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _text(step.$2),
                        style: _bodyStyle.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _actions({
    required bool canBoq,
    required bool canTeam,
    required bool canDocuments,
  }) => _panel(
    padding: EdgeInsets.all(compact ? 12 : AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          YorksV1ProjectSetupCompletionText.nextActionsTitle,
          YorksV1ProjectSetupCompletionText.nextActionsDescription,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (permissions.canOpenProject && onOpenProject != null)
          _action(
            YorksV1ProjectSetupCompletionText.openProject,
            Icons.folder_outlined,
            onOpenProject!,
            primary: true,
          ),
        if (canBoq && onAddBoq != null)
          _action(
            YorksV1ProjectSetupCompletionText.addBoq,
            Icons.description_outlined,
            onAddBoq!,
          ),
        if (canTeam && onInviteTeam != null)
          _action(
            YorksV1ProjectSetupCompletionText.inviteTeam,
            Icons.person_add_alt_1_outlined,
            onInviteTeam!,
          ),
        if (canDocuments && onUploadDocuments != null)
          _action(
            YorksV1ProjectSetupCompletionText.uploadDocuments,
            Icons.upload_file_outlined,
            onUploadDocuments!,
          ),
        if (permissions.canReturnToProjects && onReturnToProjects != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(height: 1, color: AppColors.line),
          ),
          _action(
            YorksV1ProjectSetupCompletionText.returnToProjects,
            Icons.arrow_back,
            onReturnToProjects!,
          ),
        ],
        if (permissions.canEditProject) ...[
          const SizedBox(height: AppSpacing.xxl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.blueContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.blue, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _text(YorksV1ProjectSetupCompletionText.editLaterHint),
                    style: _bodyStyle.copyWith(color: AppColors.navyHover),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _action(
    YorksV1ProjectSetupCompletionText label,
    IconData icon,
    VoidCallback callback, {
    bool primary = false,
  }) {
    final content = Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: Text(_text(label))),
        if (primary) const Icon(Icons.chevron_right, size: 24),
      ],
    );
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.navy,
      minimumSize: const Size(double.infinity, 48),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      side: const BorderSide(color: AppColors.blueContainerStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      textStyle: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: primary
          ? FilledButton(
              onPressed: callback,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size(double.infinity, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                textStyle: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: content,
            )
          : OutlinedButton(onPressed: callback, style: style, child: content),
    );
  }

  Widget _heading(
    YorksV1ProjectSetupCompletionText title,
    YorksV1ProjectSetupCompletionText description,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          _text(title),
          style: AppTypography.headlineSmall.copyWith(
            color: AppColors.navy,
            fontSize: compact ? 16 : 22,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        _text(description),
        style: _bodyStyle.copyWith(color: AppColors.muted),
      ),
    ],
  );

  Widget _panel({required Widget child, EdgeInsets? padding}) => Container(
    padding:
        padding ??
        (compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl + AppSpacing.xxs,
                vertical: AppSpacing.lg + AppSpacing.xxs,
              )),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    ),
    child: child,
  );
}
